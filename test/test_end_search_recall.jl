# Recall / soundness of population.jl's end_search against exhaustive ground
# truth. For a fixed SOURCE game and a wind-back window, enumerate_end_search_targets
# computes every reachable TARGET position from scratch; end_search must find
# only real targets (soundness) and, when its node budget covers the whole tree,
# all of them (completeness).
#
# The exhaustive phase of end_search uses no RNG, so with a budget large enough
# to cover the window the result is deterministic and can be compared exactly.
# It is opt-in (node_budget > 0); the default reproduces the randomized-only
# strategy, which end_search_ref below re-implements for comparison.

# Deterministic sources with reachable-target sets that are rich but still
# exhaustively enumerable at MAX_STEP_BACK. Seeds 7/25/28 each expose 16
# distinct reachable targets; golden-175 is a mature, near-saturated board.
const MAX_STEP_BACK = 9

function recall_sources()
  srcs = Tuple{String,Vector{Move}}[]
  push!(srcs, ("golden-175", unpack_pack(GOLDEN_PACKS[6][2]).moves))
  for seed in (7, 25, 28)
    push!(srcs, ("random-$seed", random_game(MersenneTwister(seed))[2]))
  end
  srcs
end

# The pre-rework randomized-only strategy (what the default must reproduce).
function end_search_ref(moves::Array{Move,1}, back_accept)
  score = length(moves)
  index = Dict{UInt64,Array{Move,1}}()
  eb = zeros(UInt8, 46 * 46); ep = Move[]; em = Move[]
  for step_back in 1:floor(Int64, score * 0.25)
    board = initial_board(); possible_moves = initial_moves(); made_moves = Move[]
    for mv in moves[1:(end-step_back)]
      push!(made_moves, mv); make_move(board, mv, possible_moves)
    end
    nn = 0
    while nn <= 200 && length(index) < 1000
      copyto!(eb, board); empty!(ep); append!(ep, possible_moves)
      empty!(em); append!(em, made_moves)
      while !isempty(ep)
        r = ep[rand(1:end)]; push!(em, r); make_move(eb, r, ep)
      end
      h = points_hash(em)
      if length(em) > score - back_accept && !haskey(index, h)
        index[h] = copy(em); nn = 0
      end
      nn += 1
    end
  end
  index
end

@testset "default end_search (budget 0) matches pure random sampling exactly" begin
  # The exhaustive phase is opt-in; with the default node_budget=0 end_search
  # must reproduce the randomized-only strategy move-for-move (same RNG draws).
  for (name, source) in recall_sources()
    Random.seed!(4242)
    a = end_search(source, 5)          # default: node_budget = 0
    Random.seed!(4242)
    b = end_search_ref(source, 5)
    @test Set(keys(a)) == Set(keys(b))
    @test length(a) == length(b)
  end
end

@testset "exhaustive end_search is sound and valid (subset of ground truth)" begin
  back_accept = 5
  for (name, source) in recall_sources()
    targets, capped = enumerate_end_search_targets(source, MAX_STEP_BACK, back_accept)
    @test !capped  # window chosen so ground truth is fully computable

    Random.seed!(2026)
    results = end_search(source, back_accept;
      max_step_back=MAX_STEP_BACK, node_budget=2_000_000)

    # SOUND: never invent a position that isn't actually reachable
    @test issubset(Set(keys(results)), targets)
    # every returned sequence is a legal complete game, scores in-window, and
    # its stored hash is correct
    for (h, moves) in results
      @test (verify(Morpion(moves)); true)
      @test length(moves) > length(source) - back_accept
      @test points_hash(moves) == h
      @test h in targets
    end
  end
end

@testset "exhaustive end_search is complete when the budget covers the window" begin
  back_accept = 5
  for (name, source) in recall_sources()
    targets, capped = enumerate_end_search_targets(source, MAX_STEP_BACK, back_accept)
    @test !capped

    # a budget larger than the whole tree ⇒ phase 1 covers everything ⇒
    # end_search must find every reachable target, and no more
    Random.seed!(2026)
    results = end_search(source, back_accept;
      max_step_back=MAX_STEP_BACK, node_budget=2_000_000)
    @test Set(keys(results)) == targets
    # ...so it recalls at least as much as the random sampler
    Random.seed!(7)
    rand_hits = length(intersect(Set(keys(end_search_ref(source, back_accept))), targets))
    @test length(targets) >= rand_hits
  end
end

@testset "exhaustive phase is deterministic (no RNG dependence)" begin
  source = random_game(MersenneTwister(7))[2]
  Random.seed!(1)
  a = end_search(source, 5; max_step_back=MAX_STEP_BACK, node_budget=2_000_000)
  Random.seed!(999)  # different seed must not change a budget-covered result
  b = end_search(source, 5; max_step_back=MAX_STEP_BACK, node_budget=2_000_000)
  @test Set(keys(a)) == Set(keys(b))
end
