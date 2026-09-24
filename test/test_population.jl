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
