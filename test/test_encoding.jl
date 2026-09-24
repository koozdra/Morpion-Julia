# Pack encoding/decoding and the hashing functions.

@testset "base64hex" begin
  @test base64hex('A') == "000000"
  @test base64hex('B') == "000001"
  @test base64hex('a') == "011010"
  @test base64hex('0') == "110100"
  @test base64hex('+') == "111110"
  @test base64hex('/') == "111111"
end

@testset "golden packs" begin
  for (expected_score, pack) in GOLDEN_PACKS
    m = unpack_pack(pack)
    @test length(m.moves) == expected_score
    @test (verify(m); true)
    @test generate_pack(m.moves) == pack
  end
end

@testset "pack round-trip on random games" begin
  rng = MersenneTwister(99)
  for _ in 1:20
    _, made = random_game(rng)
    pack = generate_pack(made)
    m2 = unpack_pack(pack)
    @test length(m2.moves) == length(made)
    @test Set(m2.moves) == Set(made)
    @test points_hash(m2.moves) == points_hash(made)
    @test generate_pack(m2.moves) == pack
    @test (verify(m2); true)
  end
end

@testset "points_hash order-invariance and discrimination" begin
  rng = MersenneTwister(123)
  games = [random_game(rng)[2] for _ in 1:400]

  # distinct point sets never share a hash; identical point sets always do
  seen = Dict{UInt64,Set{Tuple{Int,Int}}}()
  collisions = 0
  for made in games
    ph = points_hash(made)
    pts = Set((Int(m.x), Int(m.y)) for m in made)
    if haskey(seen, ph)
      seen[ph] == pts || (collisions += 1)
    else
      seen[ph] = pts
    end
  end
  @test collisions == 0

  # the canonical reordering produced by pack/unpack keeps the hash
  for made in games[1:10]
    reordered = unpack_pack(generate_pack(made)).moves
    @test points_hash(reordered) == points_hash(made)
  end
end

@testset "moves_and_points_hash agrees with its bit-board variant" begin
  rng = MersenneTwister(321)
  games = [random_game(rng)[2] for _ in 1:100]
  seen_a = Dict{UInt64,Vector{Int}}()
  seen_b = Dict{UInt64,Vector{Int}}()
  for made in games
    key = sort([dna_index(m) for m in made])
    for (seen, h) in ((seen_a, moves_and_points_hash(made)),
      (seen_b, moves_and_points_hash_uint64(made)))
      if haskey(seen, h)
        @test seen[h] == key
      else
        seen[h] = key
      end
    end
  end
  # both variants discriminate the same set of games
  @test length(seen_a) == length(seen_b)
end

@testset "bit board set/unset round-trip" begin
  rng = MersenneTwister(5)
  _, made = random_game(rng)
  bb = bit_board_build()
  empty_hash = bit_board_hash(bb)
  for m in made
    bit_board_set_move!(m, bb)
  end
  @test bit_board_hash(bb) == moves_and_points_hash_uint64(made)
  for m in made
    bit_board_unset_move!(m, bb)
  end
  @test bit_board_hash(bb) == empty_hash
  @test all(bb .== 0)
end
