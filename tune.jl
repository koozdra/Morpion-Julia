# Hyper-parameter search for the population search in population.jl.
#
# Protocol: every run gets a fixed iteration budget and a seed that is shared
# across configs (common random numbers), so configs are compared on identical
# random streams. Two phases:
#   1. screening — random configs sampled from SPACE, short runs, few seeds
#   2. final     — the top screening configs (plus the current defaults as the
#                  baseline) re-evaluated with longer runs on fresh seeds
# Score = best candidate max_score when the budget is exhausted. Wall time is
# recorded per run so score/time tradeoffs stay visible (a config that only
# wins by spending more time in end_search shows up in the secs column).
#
# Usage:
#   julia -t auto --project=. tune.jl            # full search
#   julia -t auto --project=. tune.jl --quick    # fast harness smoke test
#
# Per-run results are appended to data/tune_results.csv.

include("population.jl")

using Random
using Printf

const SPACE = (
  num_modifications=[3, 6, 10, 16],
  default_back_accept=[4, 8, 10, 14],
  selection_skew=[1, 2, 4, 8],
  move_selection_skew=[0.5, 1.0, 2.0],
  idle_reset=[16, 32, 64],
  idle_reset_step_back=[4, 8, 16],
  improvement_step_up=[16, 32, 64],
  end_search_interval=[4000, 10000, 25000],
  debug_interval=[2500, 5000, 10000],
)

# The current hand-tuned defaults. debug_interval is 100_000 in production; it
# is pinned to the middle of its search range here so maintenance (pruning,
# perm re-sorting) actually runs within the short tuning budgets.
const BASELINE = (
  num_modifications=10,
  default_back_accept=10,
  selection_skew=2,
  move_selection_skew=1.0,
  idle_reset=32,
  idle_reset_step_back=10,
  improvement_step_up=32,
  end_search_interval=10000,
  debug_interval=5000,
)

sample_config(rng) = map(v -> rand(rng, v), SPACE)

function run_one(cfg, seed, iters)
  Random.seed!(seed)
  t0 = time()
  cands = main(; max_iterations=iters, verbose=false, cfg...)
  (score=maximum(c.max_score for c in cands), secs=time() - t0)
end

function evaluate(configs, ids, seeds, iters; phase)
  jobs = [(ci, seed) for ci in ids for seed in seeds]
  results = Vector{NamedTuple}(undef, length(jobs))
  done = Threads.Atomic{Int}(0)
  Threads.@threads :dynamic for j in eachindex(jobs)
    ci, seed = jobs[j]
    r = run_one(configs[ci], seed, iters)
    results[j] = (config=ci, seed=seed, score=r.score, secs=r.secs)
    n = Threads.atomic_add!(done, 1) + 1
    @printf("  [%s] %3d/%d  cfg%02d seed %2d -> %3d  (%.1fs)\n",
      phase, n, length(jobs), ci, seed, r.score, r.secs)
    flush(stdout)
  end
  results
end

function summarize(ids, results)
  agg = map(ids) do ci
    scores = [r.score for r in results if r.config == ci]
    secs = [r.secs for r in results if r.config == ci]
    (config=ci, mean=sum(scores) / length(scores),
      min=minimum(scores), max=maximum(scores),
      secs=sum(secs) / length(secs))
  end
  sort(agg, by=a -> -a.mean)
end

cfg_string(cfg) = join(["$k=$(cfg[k])" for k in keys(SPACE)], " ")

function print_table(configs, agg)
  for (rank, a) in enumerate(agg)
    tag = a.config == 1 ? " (baseline)" : ""
    @printf("%2d. cfg%02d  mean %6.2f  range [%d, %d]  %5.1fs  %s%s\n",
      rank, a.config, a.mean, a.min, a.max, a.secs, cfg_string(configs[a.config]), tag)
  end
end

function write_csv(path, configs, results, phase)
  open(path, "a") do io
    for r in results
      cfg = configs[r.config]
      println(io, join([phase; r.config; [cfg[k] for k in keys(SPACE)]; r.seed; r.score; round(r.secs, digits=2)], ","))
    end
  end
end

function tune(; quick=false)
  n_screen = quick ? 3 : 60
  screen_seeds = quick ? [1] : [1, 2, 3]
  screen_iters = quick ? 2_000 : 150_000
  n_final = quick ? 2 : 8
  final_seeds = quick ? [11] : [11, 12, 13, 14, 15, 16, 17, 18]
  final_iters = quick ? 3_000 : 750_000

  # config 1 is always the baseline
  rng = MersenneTwister(7)
  configs = Any[BASELINE]
  seen = Set{Any}([BASELINE])
  while length(configs) < n_screen + 1
    c = sample_config(rng)
    c in seen && continue
    push!(seen, c)
    push!(configs, c)
  end

  mkpath("data")
  csv = joinpath("data", "tune_results.csv")
  open(csv, "w") do io
    println(io, join(["phase"; "config"; String.(collect(keys(SPACE))); "seed"; "score"; "secs"], ","))
  end

  println("Phase 1: $(length(configs)) configs × $(length(screen_seeds)) seeds × $screen_iters iterations, $(Threads.nthreads()) threads")
  flush(stdout)
  res1 = evaluate(configs, eachindex(configs), screen_seeds, screen_iters; phase="screen")
  write_csv(csv, configs, res1, "screen")
  agg1 = summarize(eachindex(configs), res1)
  println("\nScreening ranking:")
  print_table(configs, agg1)

  finalist_ids = [a.config for a in agg1[1:min(n_final, length(agg1))]]
  1 in finalist_ids || push!(finalist_ids, 1)  # baseline always advances

  println("\nPhase 2: configs $(sort(finalist_ids)) × $(length(final_seeds)) fresh seeds × $final_iters iterations")
  flush(stdout)
  res2 = evaluate(configs, finalist_ids, final_seeds, final_iters; phase="final")
  write_csv(csv, configs, res2, "final")
  agg2 = summarize(finalist_ids, res2)
  println("\nFinal ranking:")
  print_table(configs, agg2)

  best = agg2[1]
  baseline = only(a for a in agg2 if a.config == 1)
  println()
  @printf("Best: cfg%02d  mean %.2f  (baseline mean %.2f, Δ %+.2f)\n",
    best.config, best.mean, baseline.mean, best.mean - baseline.mean)
  println("Best config: ", cfg_string(configs[best.config]))
  println("Per-run results in $csv")

  configs, agg2
end

if abspath(PROGRAM_FILE) == @__FILE__
  tune(quick=("--quick" in ARGS))
end
