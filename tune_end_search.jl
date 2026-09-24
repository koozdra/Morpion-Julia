# Hyper-parameter search for end_search (population.jl).
#
# Why two phases with different objectives: end-to-end final score has a ~±15
# point spread across seeds (see tune.jl), which swamps any end_search effect.
# So phase A scores end_search DIRECTLY on a fixed corpus of source games,
# where the signal is clean:
#
#   breakthrough — a completion scoring ABOVE its source. This is what actually
#                  moves the optimizer forward; ties and lower-scoring variants
#                  only add pool churn.
#   cost         — seconds per call. end_search runs every end_search_interval
#                  iterations, so a slow call is a direct throughput tax.
#
# Phase B then validates the best phase-A configs end-to-end on paired seeds,
# because a config that finds more breakthroughs still has to pay for itself.
#
# Usage:
#   julia -t auto --project=. tune_end_search.jl           # full search
#   julia -t auto --project=. tune_end_search.jl --quick   # harness smoke test
#
# Per-run results land in data/tune_end_search_{a,b}.csv.

include("population.jl")

using Random
using Printf
using Statistics

const SPACE = (
  es_back_accept=[3, 5, 8, 12],
  es_step_back_fraction=[0.15, 0.25, 0.4, 0.6],
  es_stall_cut_off=[50, 200, 600],
  es_index_cap=[200, 1000, 5000],
)

const BASELINE = (
  es_back_accept=5,
  es_step_back_fraction=0.25,
  es_stall_cut_off=200,
  es_index_cap=1000,
)

sample_config(rng) = map(v -> rand(rng, v), SPACE)
cfg_string(cfg) = join(["$k=$(cfg[k])" for k in keys(cfg)], " ")

# --- source corpus: games at a spread of maturities, since end_search behaves
# very differently on a sparse early board vs a dense late one ---
function build_sources(; quick=false)
  specs = quick ? [(1, 5_000), (2, 20_000)] :
          [(s, it) for it in (20_000, 60_000, 150_000) for s in (1, 2, 3)]
  srcs = Vector{Move}[]
  for (seed, iters) in specs
    Random.seed!(seed)
    push!(srcs, main(max_iterations=iters, verbose=false)[1].max_moves)
  end
  srcs
end

# One end_search call: how many breakthroughs, best gain, result count, cost.
function score_call(cfg, source, seed)
  Random.seed!(seed)
  t0 = time()
  res = end_search(source, cfg.es_back_accept;
    step_back_fraction=cfg.es_step_back_fraction,
    stall_cut_off=cfg.es_stall_cut_off,
    index_cap=cfg.es_index_cap)
  secs = time() - t0
  sc = length(source)
  best = isempty(res) ? 0 : maximum(length(m) for (_, m) in res)
  breakthroughs = count(m -> length(m) > sc, values(res))
  (breakthroughs=breakthroughs, best_gain=best - sc, n=length(res), secs=secs)
end

function phase_a(configs, sources, reps)
  jobs = [(ci, si, r) for ci in eachindex(configs) for si in eachindex(sources) for r in 1:reps]
  out = Vector{NamedTuple}(undef, length(jobs))
  done = Threads.Atomic{Int}(0)
  Threads.@threads :dynamic for j in eachindex(jobs)
    ci, si, r = jobs[j]
    m = score_call(configs[ci], sources[si], 5000 + 97 * r + si)
    out[j] = (config=ci, source=si, rep=r, m...)
    n = Threads.atomic_add!(done, 1) + 1
    n % 25 == 0 && (@printf("  [A] %4d/%d\n", n, length(jobs)); flush(stdout))
  end
  out
end

function summarize_a(configs, rows)
  map(eachindex(configs)) do ci
    mine = filter(r -> r.config == ci, rows)
    (config=ci,
      bt_rate=mean(r.breakthroughs > 0 for r in mine),
      bt=mean(r.breakthroughs for r in mine),
      gain=mean(r.best_gain for r in mine),
      n=mean(r.n for r in mine),
      secs=mean(r.secs for r in mine))
  end
end

# --- phase B: end-to-end, paired seeds ---
function phase_b(configs, ids, seeds, iters)
  jobs = [(ci, s) for ci in ids for s in seeds]
  out = Vector{NamedTuple}(undef, length(jobs))
  done = Threads.Atomic{Int}(0)
  Threads.@threads :dynamic for j in eachindex(jobs)
    ci, seed = jobs[j]
    cfg = configs[ci]
    Random.seed!(seed)
    t0 = time()
    cands = main(; max_iterations=iters, verbose=false,
      es_back_accept=cfg.es_back_accept,
      es_step_back_fraction=cfg.es_step_back_fraction,
      es_stall_cut_off=cfg.es_stall_cut_off,
      es_index_cap=cfg.es_index_cap)
    out[j] = (config=ci, seed=seed,
      score=maximum(c.max_score for c in cands), secs=time() - t0)
    n = Threads.atomic_add!(done, 1) + 1
    @printf("  [B] %3d/%d cfg%02d seed %2d -> %3d (%.0fs)\n", n, length(jobs), ci, seed, out[j].score, out[j].secs)
    flush(stdout)
  end
  out
end

function tune(; quick=false)
  n_cfg = quick ? 3 : 40
  reps = quick ? 1 : 3
  n_final = quick ? 2 : 4
  b_seeds = quick ? [1] : collect(21:34)
  b_iters = quick ? 3_000 : 300_000

  rng = MersenneTwister(11)
  configs = Any[BASELINE]
  seen = Set{Any}([BASELINE])
  while length(configs) < n_cfg + 1
    c = sample_config(rng)
    c in seen && continue
    push!(seen, c)
    push!(configs, c)
  end

  println("Building source corpus...")
  sources = build_sources(quick=quick)
  println("  ", length(sources), " sources, scores: ", [length(s) for s in sources])
  mkpath("data")

  println("\nPhase A: ", length(configs), " configs × ", length(sources), " sources × ", reps,
    " reps, ", Threads.nthreads(), " threads")
  flush(stdout)
  rows = phase_a(configs, sources, reps)
  open(joinpath("data", "tune_end_search_a.csv"), "w") do io
    println(io, "config,", join(String.(collect(keys(SPACE))), ","), ",source,rep,breakthroughs,best_gain,n,secs")
    for r in rows
      c = configs[r.config]
      println(io, join([r.config; [c[k] for k in keys(SPACE)]; r.source; r.rep;
        r.breakthroughs; r.best_gain; r.n; round(r.secs, digits=4)], ","))
    end
  end

  agg = summarize_a(configs, rows)
  # rank by breakthrough rate, tie-broken by cost (cheaper wins)
  ranked = sort(agg, by=a -> (-a.bt_rate, -a.bt, a.secs))
  println("\nPhase A ranking (by breakthrough rate, then cost):")
  for (i, a) in enumerate(ranked)
    @printf("%2d. cfg%02d  bt_rate %.2f  bt/call %.2f  best_gain %+.2f  results %6.1f  %7.3fs  %s%s\n",
      i, a.config, a.bt_rate, a.bt, a.gain, a.n, a.secs, cfg_string(configs[a.config]),
      a.config == 1 ? "  (baseline)" : "")
  end

  base_a = only(a for a in agg if a.config == 1)
  @printf("\nBaseline: bt_rate %.2f  bt/call %.2f  best_gain %+.2f  %.3fs\n",
    base_a.bt_rate, base_a.bt, base_a.gain, base_a.secs)

  if maximum(a.bt_rate for a in agg) == 0
    println("\nNO config produced a single breakthrough — end_search cannot exceed its")
    println("source score on this corpus regardless of these parameters. Phase B would")
    println("only measure pool-churn effects; running it anyway for the top configs.")
  end

  finalists = [a.config for a in ranked[1:min(n_final, length(ranked))]]
  1 in finalists || push!(finalists, 1)

  println("\nPhase B: configs ", sort(finalists), " × ", length(b_seeds), " paired seeds × ", b_iters, " iters")
  flush(stdout)
  rowsb = phase_b(configs, finalists, b_seeds, b_iters)
  open(joinpath("data", "tune_end_search_b.csv"), "w") do io
    println(io, "config,", join(String.(collect(keys(SPACE))), ","), ",seed,score,secs")
    for r in rowsb
      c = configs[r.config]
      println(io, join([r.config; [c[k] for k in keys(SPACE)]; r.seed; r.score; round(r.secs, digits=2)], ","))
    end
  end

  byc = Dict(ci => Dict(r.seed => r.score for r in rowsb if r.config == ci) for ci in finalists)
  base = byc[1]
  println("\nPhase B (paired vs baseline):")
  resb = []
  for ci in finalists
    sc = [byc[ci][s] for s in b_seeds]
    d = [byc[ci][s] - base[s] for s in b_seeds]
    push!(resb, (config=ci, mean=mean(sc), diff=mean(d), sem=std(d) / sqrt(length(d)), wins=count(>(0), d)))
  end
  for a in sort(resb, by=a -> -a.mean)
    @printf("  cfg%02d  mean %6.2f  paired Δ %+6.2f ± %.2f  wins %2d/%d  %s%s\n",
      a.config, a.mean, a.diff, a.sem, a.wins, length(b_seeds),
      cfg_string(configs[a.config]), a.config == 1 ? "  (baseline)" : "")
  end
  println("\nPer-run data in data/tune_end_search_{a,b}.csv")
  configs, ranked, resb
end

if abspath(PROGRAM_FILE) == @__FILE__
  tune(quick=("--quick" in ARGS))
end
