# The search driver in population.jl.

@testset "selectByR stays in bounds" begin
  v = collect(1:10)
  @test selectByR(v, 0.0) == 1
  @test selectByR(v, prevfloat(1.0)) == 10
  @test selectByR([42], 0.0) == 42
  @test selectByR([42], prevfloat(1.0)) == 42

  rng = MersenneTwister(1)
  for _ in 1:1000
    @test selectByR(v, rand(rng)^2) in v
  end
end

@testset "apply_swaps!/revert_swaps! restore the perm exactly" begin
  rng = MersenneTwister(2)
  perm_length = 46 * 46 * 4
  perm = UInt16.(shuffle(rng, 1:perm_length))
  original = copy(perm)
  for trial in 1:100
    swaps = [(rand(rng, 1:perm_length), rand(rng, 1:perm_length)) for _ in 1:rand(rng, 1:10)]
    push!(swaps, (5, 5))  # degenerate self-swap
    apply_swaps!(perm, swaps)
    revert_swaps!(perm, swaps)
    @test perm == original
  end
end

@testset "population end_search returns valid, distinct, close-scoring games" begin
  Random.seed!(1618)
  base = random_morpion()
  back_accept = 5
  results = end_search(base, back_accept)
  @test results isa Dict{UInt64,Array{Move,1}}
  @test !isempty(results)
  for (h, moves) in results
    @test (verify(Morpion(moves)); true)
    @test length(moves) > length(base) - back_accept
    @test points_hash(moves) == h
  end
end

@testset "prune_candidate! keeps index and perms consistent" begin
  Random.seed!(3)
  perms = Perm[]
  index = Dict{UInt64,Perm}()
  while length(perms) < 20
    moves = random_morpion()
    h = points_hash(moves)
    haskey(index, h) && continue
    p = Perm(0, generate_dna_all(moves), moves, h)
    push!(perms, p)
    index[h] = p
  end
  max_score, best_i = findmax(p -> length(p.moves), perms)
  c = Candidate(0, perms, index,
    perms[best_i].moves, max_score, 3, 5.0, 50)

  prune_candidate!(c)

  @test c.improvement_counter == 0
  @test c.idle_counter == 0
  @test c.back_accept == 2
  @test all(length(p.moves) >= c.max_score - c.back_accept for p in c.perms)
  @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
  # the best perm always survives the prune
  @test any(p -> p.moves_hash == points_hash(c.max_moves), c.perms)

  # back_accept never goes below zero
  c.back_accept = 0
  prune_candidate!(c)
  @test c.back_accept == 0
end

@testset "bounded main() smoke run" begin
  Random.seed!(4)
  candidates = main(max_iterations=1500, end_search_interval=700,
    debug_interval=500, verbose=false)

  @test candidates isa Vector{Candidate}
  @test length(candidates) == 1
  c = candidates[1]

  @test c.max_score == length(c.max_moves)
  @test c.max_score >= 20
  @test (verify(Morpion(c.max_moves)); true)

  # index and perm list always describe the same population
  @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
  @test length(Set(p.moves_hash for p in c.perms)) == length(c.perms)

  # every retained perm is a real, fully played game whose stored hash and
  # score match (packed perms, the default, are decoded first)
  codec = PackCodec()
  for p in c.perms
    moves = isempty(p.pack) ? p.moves : pack_decode!(codec, Move[], p.pack)
    @test points_hash(moves) == p.moves_hash
    @test length(moves) == p.score
    @test (verify(Morpion(moves)); true)
  end
  @test maximum(p.score for p in c.perms) == c.max_score
end

@testset "checkpointed main() reproduces the uncheckpointed search exactly" begin
  runs = map((0, 8, 3)) do interval
    Random.seed!(11)
    c = main(max_iterations=20_000, end_search_interval=3000, debug_interval=1000,
      verbose=false, initial_perms_size=10, checkpoint_interval=interval, dna_storage=:full)[1]
    (c.max_score, c.max_moves, [p.moves_hash for p in c.perms], [p.perm for p in c.perms])
  end
  @test runs[2] == runs[1]
  @test runs[3] == runs[1]
end

@testset "releasing idle checkpoint caches doesn't change the search" begin
  runs = map((false, true)) do release
    Random.seed!(12)
    cs = main(max_iterations=30_000, end_search_interval=3000, debug_interval=1000,
      print_interval=1000, verbose=false, initial_perms_size=10, release_idle_caches=release,
      dna_storage=:full)
    c = cs[1]
    cached = count(p -> p.cache !== nothing, c.perms)
    (sig=(c.max_score, c.max_moves, [p.moves_hash for p in c.perms], [p.perm for p in c.perms]),
      cached=cached, pool=length(c.perms))
  end
  @test runs[2].sig == runs[1].sig
  # without release every perm that was ever a parent keeps its cache
  @test runs[2].cached < runs[1].cached
end

@testset "dna_from_moves! rebuilds a dna that replays the game" begin
  rng = MersenneTwister(21)
  N = 46 * 46 * 4
  base = shuffle(rng, UInt16(1):UInt16(N))
  dna = zeros(UInt16, N)
  games = [random_game(rng)[2] for _ in 1:10]
  append!(games, [unpack_pack(p[2]).moves for p in GOLDEN_PACKS[[1, 6, 15]]])
  for moves in games
    h = points_hash(moves)
    dna_from_moves!(dna, base, moves, h)
    @test allunique(dna)
    replayed, rh = eval_dna_and_hash(dna)
    @test replayed == moves
    @test rh == h
  end
end

@testset "main() with moves-only dna storage" begin
  Random.seed!(13)
  c = main(max_iterations=30_000, end_search_interval=3000, debug_interval=1000,
    verbose=false, initial_perms_size=10, dna_storage=:moves)[1]
  @test all(p -> isempty(p.perm) && p.cache === nothing, c.perms)
  @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
  @test maximum(length(p.moves) for p in c.perms) == c.max_score
  base = shuffle(MersenneTwister(1), UInt16(1):UInt16(46 * 46 * 4))
  dna = zeros(UInt16, length(base))
  for p in c.perms[1:min(end, 50)]
    @test points_hash(p.moves) == p.moves_hash
    @test (verify(Morpion(p.moves)); true)
    @test eval_dna_and_hash(dna_from_moves!(dna, base, p.moves, p.moves_hash))[1] == p.moves
  end
  @test_throws ArgumentError main(max_iterations=10, verbose=false, dna_storage=:bogus)
end

@testset "SearchStats(rows=false) keeps only the summaries and doesn't change the search" begin
  runs = map((nothing, SearchStats(rows=false), SearchStats(reject_sample=10))) do st
    Random.seed!(14)
    c = main(max_iterations=20_000, end_search_interval=2000, debug_interval=1000,
      verbose=false, initial_perms_size=10, stats=st)[1]
    (c.max_moves, [p.moves_hash for p in c.perms])
  end
  @test runs[2] == runs[1]
  @test runs[3] == runs[1]

  s = SearchStats(rows=false)
  Random.seed!(14)
  main(max_iterations=20_000, end_search_interval=2000, debug_interval=1000,
    verbose=false, initial_perms_size=10, stats=s)
  @test isempty(s.outcome) && isempty(s.iteration)
  @test length(s.snapshots) == 20
  @test !isempty(s.end_searches)
  @test s.eval_ns > 0
end

@testset "pack codec round-trips games in canonical order" begin
  c = PackCodec()
  out = Move[]
  rng = MersenneTwister(31)
  games = [random_game(rng)[2] for _ in 1:30]
  append!(games, [unpack_pack(p[2]).moves for p in GOLDEN_PACKS[[1, 6, 15]]])
  for g in games
    p = pack_encode(c, g)
    d = copy(pack_decode!(c, out, p))
    @test Set(d) == Set(g)                       # same lines
    @test points_hash(d) == points_hash(g)
    @test pack_encode(c, d) == p                 # canonical
    @test d == unpack_pack(generate_pack(g)).moves
    @test (verify(Morpion(d)); true)
  end
end

@testset "main() with packed storage keeps a consistent pool" begin
  Random.seed!(15)
  c = main(max_iterations=30_000, end_search_interval=3000, debug_interval=1000,
    verbose=false, initial_perms_size=10, dna_storage=:pack)[1]
  @test isempty(EMPTY_MOVES)                     # the shared empty vector is never written to
  @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
  codec = PackCodec()
  out = Move[]
  for p in c.perms
    m = pack_decode!(codec, out, p.pack)
    @test length(m) == p.score
    @test points_hash(m) == p.moves_hash
  end
  @test maximum(p.score for p in c.perms) == c.max_score == length(c.max_moves)
end

@testset "DecodeCache returns the same moves as decoding, with bounded slots" begin
  codec = PackCodec()
  dc = DecodeCache(4)
  rng = MersenneTwister(41)
  perms = map(1:10) do _
    g = random_game(rng)[2]
    Perm(0, UInt16[], EMPTY_MOVES, points_hash(g), nothing, 0, -1, length(g), pack_encode(codec, g), 0)
  end
  out = Move[]
  for _ in 1:200
    p = perms[rand(rng, 1:10)]
    @test cached_moves!(dc, codec, p) == pack_decode!(codec, out, p.pack)
  end
  @test dc.hits > 0 && dc.misses > 0
  @test count(p -> p.slot > 0, perms) <= 4
  @test all(p -> p.slot == 0 || dc.owner[p.slot] === p, perms)
  p = perms[1]
  cached_moves!(dc, codec, p)
  uncache!(dc, p)
  @test p.slot == 0
end

@testset "packed storage gives the same search with or without the decode cache" begin
  runs = map((0, 64, 16384)) do n
    Random.seed!(16)
    c = main(max_iterations=30_000, end_search_interval=3000, debug_interval=1000,
      verbose=false, initial_perms_size=10, dna_storage=:pack, pack_cache_size=n)[1]
    (c.max_moves, [p.moves_hash for p in c.perms], [p.pack for p in c.perms])
  end
  @test runs[2] == runs[1]
  @test runs[3] == runs[1]
end

@testset "end_search can key results by lines" begin
  src = unpack_pack(GOLDEN_PACKS[6][2]).moves
  for f in (end_search, end_search_ucb)
    Random.seed!(17)
    r = f(src, 5; lines=true)
    @test !isempty(r)
    for (h, m) in r
      @test h == lines_hash(m)
      @test length(m) > length(src) - 5
    end
  end
end

@testset "main() with config_key=:lines keys every perm by its lines" begin
  for storage in (:pack, :moves)
    Random.seed!(18)
    c = main(max_iterations=30_000, end_search_interval=3000, debug_interval=1000,
      verbose=false, initial_perms_size=10, dna_storage=storage, config_key=:lines)[1]
    @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
    codec = PackCodec()
    for p in c.perms
      m = storage === :pack ? pack_decode!(codec, Move[], p.pack) : p.moves
      @test lines_hash(m) == p.moves_hash
      @test length(m) == p.score
    end
  end
  @test_throws ArgumentError main(max_iterations=10, verbose=false, config_key=:bogus)
end

@testset "pruned perms are archived (best first, capped) and reintroduced when the window widens" begin
  rng = MersenneTwister(51)
  perms = Perm[]; index = Dict{UInt64,Perm}()
  while length(perms) < 40
    g = random_game(rng)[2]
    h = points_hash(g)
    haskey(index, h) && continue
    p = Perm(0, UInt16[], g, h); push!(perms, p); index[h] = p
  end
  max_score = maximum(p.score for p in perms)
  c = Candidate(0, perms, index, perms[1].moves, max_score, 6, 0.0, 0)
  before = Set(p.moves_hash for p in perms)

  prune_candidate!(c; archive_size=10)           # window shrinks to > max - 5
  @test c.back_accept == 5
  @test all(p -> p.score >= max_score - 5, c.perms)
  @test length(c.archive) <= 10
  @test all(p -> p.score < max_score - 5, c.archive)
  @test issorted([p.score for p in c.archive], rev=true)
  @test isempty(intersect(Set(p.moves_hash for p in c.archive), Set(keys(c.index))))

  c.back_accept += 2                             # an idle reset widens the window a little
  archived = copy(c.archive)
  back, dropped = reintroduce!(c)
  @test isempty(c.archive)                       # drained: put back or dropped
  @test sum(last, back; init=0) + dropped == length(archived)
  @test dropped == count(p -> p.score < max_score - c.back_accept, archived)
  @test all(p -> p.score >= max_score - c.back_accept, filter(p -> haskey(c.index, p.moves_hash), archived))
  @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
  @test issubset(Set(keys(c.index)), before)
  @test issorted(first.(back), rev=true)

  # pruning without an archive keeps nothing
  c2 = Candidate(0, copy(perms), copy(index), perms[1].moves, max_score, 6, 0.0, 0)
  prune_candidate!(c2)
  @test isempty(c2.archive)
end

@testset "main() with an archive keeps the pool and archive consistent" begin
  Random.seed!(19)
  c = main(max_iterations=60_000, end_search_interval=3000, debug_interval=1000, idle_reset=5,
    improvement_step_up=20, verbose=false, initial_perms_size=10, archive_size=500)[1]
  @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
  @test length(c.archive) <= 500
  pool = Set(objectid(p) for p in c.perms)
  @test !any(p -> objectid(p) in pool, c.archive)   # a perm is either in the pool or archived
end

@testset "timer window schedule sweeps from wide to the max, then resets" begin
  for N in (13_000, 22_000)          # last maintenance mid-cycle
    Random.seed!(21)
    c = main(max_iterations=N, end_search_interval=3000, debug_interval=1000, verbose=false,
      initial_perms_size=10, window_schedule=:timer, window_cycle=8, window_start=20)[1]
    k = (N ÷ 1000) % 8
    expected = k == 0 ? 20 : round(Int, 20 * (1 - k / 8))
    @test c.back_accept == expected
    @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
    k == 0 || @test all(p -> p.score >= c.max_score - c.back_accept || p.score == c.max_score, c.perms)
  end
  Random.seed!(22)
  c = main(max_iterations=10_000, debug_interval=1000, verbose=false, initial_perms_size=10, idle_decrement=0.0)[1]
  @test Set(keys(c.index)) == Set(p.moves_hash for p in c.perms)
  @test_throws ArgumentError main(max_iterations=10, verbose=false, window_schedule=:bogus)
end

@testset "timer window shape skews time towards narrow windows" begin
  N = 13_000                          # last maintenance at k = 13 of 16
  Random.seed!(23)
  c = main(max_iterations=N, end_search_interval=3000, debug_interval=1000, verbose=false,
    initial_perms_size=10, window_cycle=16, window_start=20, window_shape=2)[1]
  @test c.back_accept == round(Int, 20 * (1 - 13 / 16)^2)
end
