# Recall / validity of population.jl's end_search against exhaustive ground
# truth. For a fixed SOURCE game and a wind-back window,
# enumerate_end_search_targets computes every reachable TARGET position from
# scratch. end_search samples completions at random, so these tests check that
# what it returns is real and that it recalls part of the ground truth, and
# pin its behaviour to the reference implementation below.
#
# (An opt-in exhaustive phase, node_budget > 0, was prototyped in Sept 2026 and
# dropped: complete coverage didn't improve final scores.)

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

# Reference re-implementation of end_search's random sampling strategy.
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

@testset "end_search matches the reference random sampler exactly" begin
  # end_search must reproduce end_search_ref move-for-move (same RNG draws).
  for (name, source) in recall_sources()
    Random.seed!(4242)
    a = end_search(source, 5)
    Random.seed!(4242)
    b = end_search_ref(source, 5)
    @test Set(keys(a)) == Set(keys(b))
    @test length(a) == length(b)
  end
end

@testset "end_search results are valid, in-window, and correctly hashed" begin
  back_accept = 5
  for (name, source) in recall_sources()
    Random.seed!(2026)
    results = end_search(source, back_accept)
    @test !isempty(results)
    for (h, moves) in results
      @test (verify(Morpion(moves)); true)
      @test length(moves) > length(source) - back_accept
      @test points_hash(moves) == h
    end
  end
end

@testset "end_search recalls reachable ground-truth targets" begin
  # end_search winds back further than MAX_STEP_BACK, so it can also return
  # positions outside the enumerated window; only check it finds targets
  # inside it.
  back_accept = 5
  for (name, source) in recall_sources()
    targets, capped = enumerate_end_search_targets(source, MAX_STEP_BACK, back_accept)
    @test !capped
    Random.seed!(2026)
    results = end_search(source, back_accept)
    @test !isempty(intersect(Set(keys(results)), targets))
  end
end
