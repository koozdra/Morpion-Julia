# DNA generation and evaluation.

@testset "generate_dna_all is a permutation that replays its game" begin
  rng = MersenneTwister(2024)
  N = 46 * 46 * 4
  for _ in 1:8
    _, made = random_game(rng)
    dna = generate_dna_all(made)
    @test sort(dna) == UInt16.(1:N)

    replayed, h = eval_dna_and_hash(dna)
    @test replayed == made
    @test h == points_hash(made)
  end
end

@testset "eval_dna_and_hash matches eval_dna_and_hash_optimized" begin
  rng = MersenneTwister(555)
  N = 46 * 46 * 4
  for _ in 1:8
    dna = UInt16.(shuffle(rng, 1:N))
    m1, h1 = eval_dna_and_hash(dna)
    m2, h2 = eval_dna_and_hash_optimized(dna)
    @test m1 == m2
    @test h1 == h2
    @test (verify(Morpion(m1)); true)
    @test h1 == points_hash(m1)
  end
end

@testset "eval_dna_and_hash! (buffer-reusing) matches eval_dna_and_hash" begin
  rng = MersenneTwister(888)
  N = 46 * 46 * 4
  board = zeros(UInt8, 46 * 46)
  possible = Move[]
  made = Move[]
  values = UInt16[]
  for _ in 1:8
    dna = UInt16.(shuffle(rng, 1:N))
    m1, h1 = eval_dna_and_hash(dna)
    m2, h2 = eval_dna_and_hash!(dna, board, possible, made, values)
    @test m2 == m1
    @test h2 == h1
  end
end

@testset "eval_dna handles degenerate dna and always yields a valid game" begin
  N = 46 * 46 * 4

  # all-zero dna: every choice falls to the random tie-break
  moves = eval_dna(zeros(UInt16, N))
  @test (verify(Morpion(moves)); true)

  # dna with many duplicate values
  rng = MersenneTwister(777)
  moves2 = eval_dna(rand(rng, UInt16, N))
  @test (verify(Morpion(moves2)); true)
end
