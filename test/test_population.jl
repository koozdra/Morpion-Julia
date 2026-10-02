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
  c = Candidate(0, perms, index, Dict{UInt64,StepBackPack}(),
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

  # every retained perm is a real, fully played game whose stored hash matches
  for p in c.perms
    @test points_hash(p.moves) == p.moves_hash
    @test (verify(Morpion(p.moves)); true)
  end
  @test maximum(length(p.moves) for p in c.perms) == c.max_score
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
