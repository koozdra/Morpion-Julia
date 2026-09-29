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

@testset "checkpointed eval matches a full rollout" begin
  rng = MersenneTwister(4242)
  N = 46 * 46 * 4
  board = zeros(UInt8, 46 * 46)
  possible = Move[]
  made = Move[]
  values = UInt16[]
  idx = Int[]
  newv = UInt16[]
  identical = 0
  for interval in (1, 3, 8, 1000)
    cache = EvalCache(interval)
    for _ in 1:6
      # parents: random dna, and a mature-looking game encoded by generate_dna_all
      parent = rand(rng, Bool) ? UInt16.(shuffle(rng, 1:N)) : generate_dna_all(random_game(rng)[2])
      m0, h0 = eval_dna_and_hash(parent)
      m1, h1 = build_eval_cache!(cache, parent, board, possible, made, values)
      @test m1 == m0 && h1 == h0
      @test cache.moves == m0 && cache.hash == h0

      for trial in 1:40
        swaps = if trial % 2 == 0
          # main-loop style: a played move's index against a random one
          [(dna_index(rand(rng, m0)), rand(rng, 1:N)) for _ in 1:rand(rng, 2:10)]
        else
          [(rand(rng, 1:N), rand(rng, 1:N)) for _ in 1:rand(rng, 1:4)]
        end
        r = restart_step(cache, parent, swaps, idx, newv)
        child = apply_swaps!(copy(parent), swaps)
        expected, eh = eval_dna_and_hash(child)
        # the restart step never lies past the first differing move
        d = findfirst(t -> t > length(expected) || expected[t] != m0[t], 1:length(m0))
        if r == 0
          @test expected == m0
          identical += 1
        else
          @test d === nothing || r <= d
        end
        got, gh = eval_dna_and_hash_cached!(child, cache, r, board, possible, made, values)
        @test got == expected
        @test gh == eh
      end
    end
  end
  @test identical > 0  # the "same game" shortcut is exercised
end

@testset "retargeted caches stay exact and heal back to a full build" begin
  rng = MersenneTwister(77)
  N = 46 * 46 * 4
  board = zeros(UInt8, 46 * 46)
  possible = Move[]
  made = Move[]
  values = UInt16[]
  idx = Int[]
  newv = UInt16[]
  for interval in (1, 5, 8)
    fresh = EvalCache(interval)
    retargeted = 0
    for _ in 1:60
      parent = UInt16.(shuffle(rng, 1:N))
      cache = EvalCache(interval)
      pm, ph = build_eval_cache!(cache, parent, board, possible, made, values)
      pm = copy(pm)
      # look for a child dna that plays the same points in another order
      found = false
      for _ in 1:30
        swaps = [(dna_index(rand(rng, pm)), rand(rng, 1:N)) for _ in 1:rand(rng, 2:6)]
        child = apply_swaps!(copy(parent), swaps)
        cm, ch = eval_dna_and_hash(child)
        (ch == ph && cm != pm) || continue
        retarget_eval_cache!(cache, child, cm, ch)
        @test cache.known <= length(cm)
        parent = child
        pm = cm
        found = true
        break
      end
      found || continue
      retargeted += 1

      # children of the adopted dna still evaluate exactly, and heal the cache
      for trial in 1:150
        swaps = [(dna_index(rand(rng, pm)), rand(rng, 1:N)) for _ in 1:rand(rng, 1:3)]
        r = restart_step(cache, parent, swaps, idx, newv)
        child = apply_swaps!(copy(parent), swaps)
        expected, eh = eval_dna_and_hash(child)
        got, gh = eval_dna_and_hash_cached!(child, cache, r, board, possible, made, values)
        @test got == expected && gh == eh
      end

      build_eval_cache!(fresh, parent, board, possible, made, values)
      @test cache.moves == fresh.moves && cache.hash == fresh.hash
      @test cache.play_step == fresh.play_step
      @test cache.chosen == fresh.chosen
      k = min(cache.known, fresh.known)
      @test [f <= k ? f : 0 for f in cache.first_legal] == [f <= k ? f : 0 for f in fresh.first_legal]
      @test cache.boards[1:cache.count] == fresh.boards[1:cache.count]
      @test cache.possible[1:cache.count] == fresh.possible[1:cache.count]
      @test cache.hashes[1:cache.count] == fresh.hashes[1:cache.count]
      # a fully healed cache is indistinguishable from a fresh one
      if cache.known > length(cache.moves)
        @test cache.first_legal == fresh.first_legal
        @test cache.count == fresh.count
      end
    end
    @test retargeted > 0
  end
end

@testset "EvalCache first-legal steps match a scan of the possible moves" begin
  rng = MersenneTwister(31)
  N = 46 * 46 * 4
  board = zeros(UInt8, 46 * 46)
  possible = Move[]
  made = Move[]
  values = UInt16[]
  cache = EvalCache(8)
  for _ in 1:10
    moves, _ = build_eval_cache!(cache, UInt16.(shuffle(rng, 1:N)), board, possible, made, values)
    @test cache.first_legal == first_legal_steps(moves)
    @test sort(cache.entries) == findall(>(0), cache.first_legal)
  end
end
