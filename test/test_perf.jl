# Performance guardrails: the hot path must stay type-stable and its
# allocations bounded. Budgets are deliberately generous — these exist to catch
# order-of-magnitude regressions, not to tune.

@testset "hot path type stability" begin
  rng = MersenneTwister(8)
  N = 46 * 46 * 4
  dna = UInt16.(shuffle(rng, 1:N))
  @test (Test.@inferred eval_dna_and_hash_optimized(dna)) isa Tuple{Vector{Move},UInt64}
  @test (Test.@inferred points_hash(Move[])) isa UInt64
end

@testset "hot path allocation budget" begin
  rng = MersenneTwister(9)
  N = 46 * 46 * 4
  dna = UInt16.(shuffle(rng, 1:N))
  eval_dna_and_hash_optimized(dna)  # warm up compilation
  allocs = @allocated eval_dna_and_hash_optimized(dna)
  @test allocs < 2_000_000

  # the buffer-reusing variant used by main() must stay allocation-free once
  # its buffers are warm
  board = zeros(UInt8, 46 * 46)
  possible = Move[]
  made = Move[]
  values = UInt16[]
  eval_dna_and_hash!(dna, board, possible, made, values)
  allocs2 = @allocated eval_dna_and_hash!(dna, board, possible, made, values)
  @test allocs2 < 10_000
end
