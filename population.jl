# 166 HYhAHqWtBWCUVGkZRRxasI/rdT+39uUf9d22ap+y7/fX7/3+
# 170 EykgD3IyGWSDsFAhMXIsPeav6+ju7V07eqfruddfv/nfO///6
# 170 Ey0gDuBpwaSCtRHDsNrbIXYUQ//n9ev7Ivz3VX37/5/rf//9
# 170 qiQRjpmQsgU2CKFJbAAfUVaF5deL//zru/vbens3yfr31z+/trw
# 171 F0wgDolGsg5l0kkIno6jbiovx31/l5b3v42y8je9dvt2d//vvQ
# 172 LBFEq2HLWWKB2qBilJqZcOZ3q+y/6xvzfetT91c3Tfv3/9/ae
# 172 AENMhclbKcGxHhKhtGnBJdfX1DeJf7L6X+vt09fU7/Ptcv//va
# 175 KyQihtyDUKLaq0EcpmqsRa/XuYvfN79c9T0t356/9+23fb5y/U
# 176 LoyBD5plSCpD5FoFqixU76aU8b7m9+5k/s+X6en2739dr7/+34
# 177 AYOOj1VpKGCndhSsQa1s+k3ft/usr69mLd/Su+3f+7Z9/+3u4
# 177 FEBMv6lokkqKS4cwzBsf0ubovt9/yOd/M468fl18r1/el5/7/fA
# 177 FEBMv6lokkiL84GQw9LndS5++33Kr9d8RvfNu/Nv/5zff/b3W
# 177 FEBMv6lokkqKS4cwzB4f1Vc/fb7lr9d8RvfNu/Nv/p5vv/t7b
# 177 CBMXT2TomgmTmJcpVpeTTr589vL/jW/hnms7Z3O29fu5ef9/3w
# 177 IiAjf2jokjJLE4Zwyk4vWzYlXn77f1lf/be7tN7f/p5fv/t7X
# 177 0yAij1VlSSRWksIzgzcN9Zbvzv7q16+0Hffl2P7f/K53f/fXdg
# 178 0yAij1VlSSRWgtGcINgU4jPuvLppfb390rzecGjnu8r//rpv//b9
# 178 7EBET5ZlRiSHYc0gSqEaxn9OfXDfr79Vak78WKOe7yv//Wm//9v0

include("morpion.jl")
using Random
using DataStructures

function selectByR(v::Vector, r::Float64)
  v[floor(Int, r*length(v))+1]
end

function apply_swaps!(perm::Vector{UInt16}, swaps)
  for (a, b) in swaps
    perm[a], perm[b] = perm[b], perm[a]
  end
  perm
end

function revert_swaps!(perm::Vector{UInt16}, swaps)
  for (a, b) in reverse(swaps)
    perm[a], perm[b] = perm[b], perm[a]
  end
  perm
end

# Winds back the last 1..step_back_fraction*score moves of `moves` and samples
# random completions from each prefix, until stall_cut_off completions in a row
# add nothing new (or index_cap results are collected). Returns every distinct
# completion scoring above score - back_accept, keyed by points hash.
function end_search(moves::Array{Move,1}, back_accept;
  step_back_fraction::Real=0.25, stall_cut_off::Int=200, index_cap::Int=1000)
  score = length(moves)

  index = Dict{UInt64,Array{Move,1}}()

  # reusable per-completion buffers (contents are copied on accept)
  eval_board = zeros(UInt8, 46 * 46)
  eval_possible_moves = Move[]
  eval_made_moves = Move[]

  # Progressively wind back the moves taken on a board
  for step_back in 1:floor(Int64, score*step_back_fraction)
    # Make the subset of moves on the board
    # move_policy = OrderedDict{Move,Int32}()
    board = initial_board()
    possible_moves = initial_moves()
    made_moves = Move[]

    move_index = 1
    for move in moves[1:(end-step_back)]
      push!(made_moves, move)
      make_move(board, move, possible_moves)
      # move_policy[move] = score - move_index - 1
      # move_index += 1
    end

    # Perform a random completion from where the moves left off
    # Keep track of new configurations found and reset search timer if a new one is found
    no_new_index_counter = 0
    while no_new_index_counter <= stall_cut_off && length(index) < index_cap
      copyto!(eval_board, board)
      empty!(eval_possible_moves)
      append!(eval_possible_moves, possible_moves)
      empty!(eval_made_moves)
      append!(eval_made_moves, made_moves)

      eval_move_index = move_index

      while !isempty(eval_possible_moves)
        random_possible_move = eval_possible_moves[rand(1:end)]
        push!(eval_made_moves, random_possible_move)
        make_move(eval_board, random_possible_move, eval_possible_moves)
        # move_policy[random_possible_move] = eval_move_index
        # eval_move_index += 1
      end

      eval_score = length(eval_made_moves)
      eval_points_hash = points_hash(eval_made_moves)

      if eval_score > score - back_accept && !haskey(index, eval_points_hash)
        index[eval_points_hash] = copy(eval_made_moves)
        no_new_index_counter = 0
      end

      no_new_index_counter += 1
    end
  end

  index
end

# One random completion from a checkpoint (board, possible moves, points hash of
# the moves so far). Leaves the completion's own moves in `suffix` and returns
# the points hash of the whole game.
function ucb_completion!(board, possible_moves, suffix, from_board, from_possible, h::UInt64)
  copyto!(board, from_board)
  empty!(possible_moves)
  append!(possible_moves, from_possible)
  empty!(suffix)
  while !isempty(possible_moves)
    move = possible_moves[rand(1:end)]
    push!(suffix, move)
    make_move(board, move, possible_moves)
    h ⊻= points_zobrist[board_index(move.x, move.y)]
  end
  h
end

# end_search variant that treats each wind-back depth as a bandit arm. The game
# is replayed once, keeping the position before each of its last
# step_back_fraction*score moves; one pull of an arm is one random completion
# from that position, rewarded when it finds a new point set scoring above
# score - back_accept. Arms are picked by UCB1 on reward per pull, so rollouts
# go to the depths that are still turning up new completions instead of a
# fixed stall per depth. Stops once stall_rollouts average completions' worth of
# moves in a row find nothing new (or index_cap results are collected).
# Returns the same kind of index as end_search.
function end_search_ucb(moves::Array{Move,1}, back_accept;
  step_back_fraction::Real=0.25, stall_rollouts::Int=2000, index_cap::Int=1000,
  exploration::Real=0.1, warmup::Int=2)
  score = length(moves)
  depth = floor(Int, score * step_back_fraction)
  index = Dict{UInt64,Array{Move,1}}()
  depth < 1 && return index

  # checkpoint k: the position before the last k moves, and its points hash
  boards = Vector{Vector{UInt8}}(undef, depth)
  possibles = Vector{Vector{Move}}(undef, depth)
  prefix_hashes = zeros(UInt64, depth)
  board = initial_board()
  possible_moves = initial_moves()
  h = UInt64(0)
  for (i, move) in enumerate(moves)
    k = score - i + 1
    if k <= depth
      boards[k] = copy(board)
      possibles[k] = copy(possible_moves)
      prefix_hashes[k] = h
    end
    make_move(board, move, possible_moves)
    h ⊻= points_zobrist[board_index(move.x, move.y)]
  end

  rewards = zeros(Int, depth)
  pulls = zeros(Int, depth)
  # per arm, kept current as it is pulled: mean reward and 1/sqrt(pulls)
  means = zeros(depth)
  inv_sqrt_pulls = zeros(depth)
  total_pulls = 0
  total_moves = 0
  moves_since_new = 0

  eval_board = zeros(UInt8, 46 * 46)
  eval_possible_moves = Move[]
  eval_suffix = Move[]

  k = 0
  while true
    if total_pulls < warmup * depth
      k = total_pulls % depth + 1
    else
      (length(index) < index_cap &&
       moves_since_new < stall_rollouts * total_moves / total_pulls) || break
      bonus = exploration * sqrt(log(total_pulls))
      best_value = -Inf
      for a in 1:depth
        value = means[a] + bonus * inv_sqrt_pulls[a]
        if value > best_value
          best_value = value
          k = a
        end
      end
    end

    h = ucb_completion!(eval_board, eval_possible_moves, eval_suffix,
      boards[k], possibles[k], prefix_hashes[k])
    played = length(eval_suffix)
    found = score - k + played > score - back_accept && !haskey(index, h)
    found && (index[h] = vcat(moves[1:score-k], eval_suffix))

    rewards[k] += found
    pulls[k] += 1
    means[k] = rewards[k] / pulls[k]
    inv_sqrt_pulls[k] = 1 / sqrt(pulls[k])
    total_pulls += 1
    total_moves += played
    moves_since_new = found ? 0 : moves_since_new + played
  end

  index
end

mutable struct Perm
  visits::Int
  perm::Vector{UInt16}
  # TODO: remove moves, not using it for anything
  moves::Vector{Move}
  moves_hash::UInt64
  # checkpoints of the game `perm` plays, built lazily when the perm is first
  # used as a parent; `valid` is cleared whenever `perm` changes to a dna whose
  # game differs
  cache::Union{Nothing,EvalCache}
end

Perm(visits, perm, moves, moves_hash) = Perm(visits, perm, moves, moves_hash, nothing)

struct StepBackPack
  score::Int
  visits::Int
  moves::Vector{Move}
  iteration_created::Int
end


mutable struct Candidate
  visits::Int
  perms::Vector{Perm}
  index::Dict{UInt64,Perm}
  step_back_index::Dict{UInt64,StepBackPack}
  max_moves::Vector{Move}
  max_score::Int
  back_accept::Int
  idle_counter::Float64
  improvement_counter::Int
end

# Tighten back_accept by one and drop every perm (and its index entry) that
# falls below the new acceptance window.
function prune_candidate!(c::Candidate)
  c.improvement_counter = 0
  c.idle_counter = 0

  c.back_accept = max(0, c.back_accept - 1)
  filter!(c.perms) do perm
    if length(perm.moves) < c.max_score - c.back_accept
      delete!(c.index, perm.moves_hash)
      false  # drop it from c.perms
    else
      true   # keep it
    end
  end

  c
end

# Optional instrumentation for main(; stats=SearchStats()). One row per rollout
# (column vectors) plus section timings, end_search outcomes and per-maintenance
# snapshots. Costs roughly one extra parent replay per distinct parent, so only
# pass it for analysis runs.
const OUTCOME_NOOP = Int8(0)     # child game identical to the parent's
const OUTCOME_REJECT = Int8(1)   # below the acceptance window
const OUTCOME_REVISIT = Int8(2)  # in the window but already in the index
const OUTCOME_ACCEPT = Int8(3)   # new perm added to the pool
const OUTCOME_BEST = Int8(4)     # new candidate max_score

mutable struct SearchStats
  # per rollout
  iteration::Vector{Int32}
  seconds::Vector{Float32}
  parent_pos::Vector{Int16}    # index of the parent in candidate.perms
  pool_size::Vector{Int16}
  parent_score::Vector{Int16}
  max_score::Vector{Int16}
  back_accept::Vector{Int16}
  num_swaps::Vector{Int8}
  swap_pos_min::Vector{Int16}  # earliest parent-game position of a swapped move
  restart::Vector{Int16}       # first step a swapped dna index is legal in the parent game (0 = never)
  diverge::Vector{Int16}       # first step the child game differs (0 = identical)
  eval_score::Vector{Int16}
  outcome::Vector{Int8}
  # section timings (ns); eval_ns includes checkpoint cache builds
  eval_ns::Int
  cache_builds::Int
  cache_retargets::Int
  end_search_ns::Int
  maintenance_ns::Int
  # end_search: (iteration, source score, max_score, results, best result, accepted, new best)
  end_searches::Vector{NTuple{7,Int}}
  # maintenance snapshots: (iteration, seconds, candidate, max_score, back_accept, pool size, perms at max, distinct scores)
  snapshots::Vector{NTuple{8,Float64}}
  # parent game -> step at which each dna index first became legal (0 = never)
  legal_cache::Dict{UInt64,Vector{Int16}}
  # rejected rollouts are only recorded when iteration % reject_sample == 0
  # (weight them by reject_sample); every other outcome is always recorded
  reject_sample::Int
end

SearchStats(; reject_sample::Int=1) = SearchStats(Int32[], Float32[], Int16[], Int16[], Int16[],
  Int16[], Int16[], Int8[], Int16[], Int16[], Int16[], Int16[], Int8[], 0, 0, 0, 0, 0,
  NTuple{7,Int}[], NTuple{8,Float64}[], Dict{UInt64,Vector{Int16}}(), reject_sample)

# Step (1-based) at which each dna index first appears among the possible moves
# while replaying `moves`; 0 if it never does.
function first_legal_steps(moves::Vector{Move})
  first_legal = zeros(Int16, 46 * 46 * 4)
  board = initial_board()
  possible = initial_moves()
  for (step, move) in enumerate(moves)
    for m in possible
      i = dna_index(m)
      first_legal[i] == 0 && (first_legal[i] = step)
    end
    make_move(board, move, possible)
  end
  first_legal
end

function record_rollout!(s::SearchStats, t0, iteration, parent, parent_pos, candidate,
  max_score, back_accept, modifications, eval_moves, outcome)
  key = hash(parent.moves)
  first_legal = get!(() -> first_legal_steps(parent.moves), s.legal_cache, key)
  length(s.legal_cache) > 5000 && empty!(s.legal_cache)

  restart = typemax(Int16)
  for (a, b) in modifications, i in (a, b)
    first_legal[i] > 0 && (restart = min(restart, first_legal[i]))
  end
  restart == typemax(Int16) && (restart = 0)

  swap_pos_min = typemax(Int16)
  for (a, _) in modifications
    p = findfirst(m -> dna_index(m) == a, parent.moves)
    p === nothing || (swap_pos_min = min(swap_pos_min, p))
  end

  diverge = 0
  n = min(length(eval_moves), length(parent.moves))
  for i in 1:n
    if eval_moves[i] != parent.moves[i]
      diverge = i
      break
    end
  end
  diverge == 0 && length(eval_moves) != length(parent.moves) && (diverge = n + 1)

  push!(s.iteration, iteration)
  push!(s.seconds, time() - t0)
  push!(s.parent_pos, parent_pos)
  push!(s.pool_size, length(candidate.perms))
  push!(s.parent_score, length(parent.moves))
  push!(s.max_score, max_score)
  push!(s.back_accept, back_accept)
  push!(s.num_swaps, length(modifications))
  push!(s.swap_pos_min, swap_pos_min)
  push!(s.restart, restart)
  push!(s.diverge, diverge)
  push!(s.eval_score, length(eval_moves))
  # rejects keep their label so the reject_sample weighting stays correct
  push!(s.outcome, diverge == 0 && outcome != OUTCOME_REJECT ? OUTCOME_NOOP : outcome)
  s
end

function main(; max_iterations::Union{Nothing,Int}=nothing,
  max_seconds::Union{Nothing,Real}=nothing,
  stats::Union{Nothing,SearchStats}=nothing,
  end_search_interval::Int=10000,
  # maintenance (perm re-sorting, pruning, idle bookkeeping) runs every
  # debug_interval iterations; the progress line prints every print_interval
  # iterations (keep it a multiple of debug_interval)
  debug_interval::Int=100000,
  print_interval::Int=100000,
  verbose::Bool=true,
  # hyper-parameters (defaults are the hand-tuned values; see tune.jl for the
  # search harness that explores them)
  num_modifications::Int=10,
  default_back_accept::Int=10,
  selection_skew::Real=10,
  move_selection_skew::Real=1,
  idle_reset::Int=128,
  idle_reset_step_back::Int=default_back_accept,
  improvement_step_up::Int=20,
  initial_candidates_size::Int=1,
  # end_search wind-back depth (fraction of the source's score) and how many
  # fruitless completions in a row end each wind-back step
  es_step_back_fraction::Real=0.25,
  es_stall_cut_off::Int=200,
  # :ucb (end_search_ucb, which stops after es_ucb_stall_rollouts) or
  # :sequential (the original end_search, which uses es_stall_cut_off)
  es_mode::Symbol=:ucb,
  es_ucb_stall_rollouts::Int=2000,
  initial_perms_size::Int=100,
  # rollouts resume from a checkpoint of the parent's game every this many
  # moves (0 = always replay from the start; results are identical either way)
  checkpoint_interval::Int=4)
  es_mode in (:sequential, :ucb) || throw(ArgumentError("es_mode must be :sequential or :ucb, got $es_mode"))
  perm_length = 46 * 46 * 4

  candidates = Candidate[]

  step_back_index_prune_size = 300_000
  step_back_index_prune_target_size = Int(step_back_index_prune_size * 0.66)

  score_multiplier = 2

  end_searched = Dict{UInt64,Bool}()



  for i in 1:initial_candidates_size
    # seed each candidate with initial_perms_size random perms (duplicate board
    # configurations are dropped), best first
    perms = Perm[]
    index = Dict{UInt64,Perm}()
    for _ in 1:initial_perms_size
      perm = UInt16.(1:perm_length)
      shuffle!(perm)
      perm_moves, perm_moves_hash = eval_dna_and_hash(perm)
      haskey(index, perm_moves_hash) && continue

      new_perm = Perm(
        0,
        perm,
        perm_moves,
        perm_moves_hash
      )
      push!(perms, new_perm)
      index[perm_moves_hash] = new_perm
    end
    sort!(perms, by=p -> -length(p.moves))
    best = perms[1]

    push!(candidates,
      Candidate(
        0,
        perms,
        index,
        Dict{UInt64,StepBackPack}(),
        best.moves,
        length(best.moves),
        default_back_accept,
        0,
        0
      )
    )
  end

  # reusable rollout buffers for eval_dna_and_hash! (eval_moves aliases
  # eval_made below, so it must be copied before being stored anywhere)
  eval_board = zeros(UInt8, 46 * 46)
  eval_possible = Move[]
  eval_made = Move[]
  eval_values = UInt16[]
  modifications = Tuple{Int,Int}[]
  restart_idx = Int[]
  restart_newv = UInt16[]
  restart = 0

  iteration = 1
  start_time = time()
  last_debug_time = start_time

  while max_iterations === nothing || iteration <= max_iterations
    if max_seconds !== nothing && iteration % 1000 == 0 && time() - start_time >= max_seconds
      break
    end
    candidate_position = (iteration % length(candidates)) + 1
    candidate = candidates[candidate_position]

    candidate.visits += 1

    # weighted
    perm_pos = floor(Int, rand()^selection_skew * length(candidate.perms)) + 1
    perm = candidate.perms[perm_pos]
    perm_score = length(perm.moves)
    stats === nothing || (stats_parent = (moves=copy(perm.moves),))  # refresh may overwrite perm.moves
    perm.visits += 1

    stats === nothing || (eval_t0 = time_ns())
    if checkpoint_interval > 0
      perm.cache === nothing && (perm.cache = EvalCache(checkpoint_interval))
      if !perm.cache.valid
        build_eval_cache!(perm.cache, perm.perm, eval_board, eval_possible, eval_made, eval_values)
        stats === nothing || (stats.cache_builds += 1)
      end
    end

    empty!(modifications)
    for _ in 1:rand(2:num_modifications)
      push!(modifications, (dna_index(selectByR(perm.moves, rand()^move_selection_skew)), rand(1:perm_length)))
    end

    checkpoint_interval > 0 &&
      (restart = restart_step(perm.cache, perm.perm, modifications, restart_idx, restart_newv))
    apply_swaps!(perm.perm, modifications)

    if checkpoint_interval > 0
      eval_moves, eval_moves_hash = eval_dna_and_hash_cached!(perm.perm, perm.cache, restart,
        eval_board, eval_possible, eval_made, eval_values)
    else
      eval_moves, eval_moves_hash = eval_dna_and_hash!(perm.perm, eval_board, eval_possible, eval_made, eval_values)
    end
    eval_score = length(eval_moves)
    if stats !== nothing
      stats.eval_ns += time_ns() - eval_t0
      stats_max_score = candidate.max_score
      stats_back_accept = candidate.back_accept
      stats_outcome = OUTCOME_REJECT
    end

    is_in_index = haskey(candidate.index, eval_moves_hash)

    if eval_score > candidate.max_score
      new_perm = Perm(
        0,
        copy(perm.perm),
        copy(eval_moves),
        eval_moves_hash
      )

      push!(candidates[candidate_position].perms, new_perm)
      candidates[candidate_position].max_score = eval_score
      candidates[candidate_position].max_moves = new_perm.moves
      candidates[candidate_position].index[eval_moves_hash] = new_perm

      verbose && println("$iteration. $perm_score ($(perm.visits)) => $eval_score $(candidate.max_score) ###### $eval_score")
      stats === nothing || (stats_outcome = OUTCOME_BEST)
      candidate.idle_counter = 0
      candidate.back_accept = default_back_accept


    elseif eval_score >= (candidate.max_score - candidate.back_accept)

      if !is_in_index
        new_perm = Perm(
          0,
          copy(perm.perm),
          copy(eval_moves),
          eval_moves_hash
        )

        candidate.index[eval_moves_hash] = new_perm
        push!(candidate.perms, new_perm)
        stats === nothing || (stats_outcome = OUTCOME_ACCEPT)

        arrow_symbol =
          if eval_score > perm_score
            "="
          else
            "-"
          end
        verbose && println("$iteration. $perm_score ($(perm.visits)) $arrow_symbol> $eval_score $(candidate.max_score) i:$(length(candidate.index)) impr:$(candidate.improvement_counter)")

        perm.visits = 0

        candidate.idle_counter = max(0, candidate.idle_counter - 0.1)
        if eval_score > (candidate.max_score - candidate.back_accept)

          candidate.improvement_counter += 1
        end
      else
        stats === nothing || (stats_outcome = OUTCOME_REVISIT)
        # refresh the stored perm in place (same board configuration, new dna)
        stored = candidate.index[eval_moves_hash]
        # the parent's own cache is checked below, where its dna is kept
        stored !== perm && stored.cache !== nothing && (stored.cache.valid = false)
        copyto!(stored.perm, perm.perm)
        resize!(stored.moves, length(eval_moves))
        copyto!(stored.moves, eval_moves)
      end
    end

    if stats !== nothing && (stats_outcome != OUTCOME_REJECT || iteration % stats.reject_sample == 0)
      record_rollout!(stats, start_time, iteration, stats_parent, perm_pos, candidate,
        stats_max_score, stats_back_accept, modifications, eval_moves, stats_outcome)
    end

    if eval_moves_hash != perm.moves_hash
      revert_swaps!(perm.perm, modifications)
    elseif perm.cache !== nothing && perm.cache.valid
      # the parent keeps the child dna: its game is the child's, which may play
      # the same points in a different order
      if eval_moves != perm.cache.moves
        retarget_eval_cache!(perm.cache, perm.perm, eval_moves, eval_moves_hash)
        stats === nothing || (stats.cache_retargets += 1)
      else
        refresh_eval_cache_values!(perm.cache, perm.perm)
      end
    end


    if iteration % end_search_interval == 0
      stats === nothing || (es_t0 = time_ns())
      end_search_candidate = rand(candidates)
      best = argmax(end_search_candidate.perms) do p
        is_end_searched = haskey(end_searched, p.moves_hash)
        if is_end_searched
          0
        else
          length(p.moves)
        end
      end

      if !haskey(end_searched, best.moves_hash)

        results = if es_mode === :ucb
          end_search_ucb(best.moves, 5;
            step_back_fraction=es_step_back_fraction, stall_rollouts=es_ucb_stall_rollouts)
        else
          end_search(best.moves, 5;
            step_back_fraction=es_step_back_fraction, stall_cut_off=es_stall_cut_off)
        end
        es_max_before = end_search_candidate.max_score
        es_accepted = 0
        es_best = 0

        for (es_moves_hash, es_moves) in sort(collect(results), by=x -> length(x[2]))
          es_score = length(es_moves)

          is_in_index = haskey(end_search_candidate.index, es_moves_hash)

          if es_score > end_search_candidate.max_score
            end_search_candidate.visits = 0
            new_perm = Perm(
              0,
              generate_dna_all(es_moves),
              es_moves,
              es_moves_hash
            )

            push!(end_search_candidate.perms, new_perm)
            end_search_candidate.index[es_moves_hash] = new_perm
            end_search_candidate.max_moves = es_moves
            end_search_candidate.max_score = es_score

            verbose && println("$iteration. $(es_score) -> $( end_search_candidate.max_score) ###### $(end_search_candidate.max_score)")

            end_search_candidate.idle_counter = 0
            end_search_candidate.back_accept = default_back_accept
            es_best += 1

          elseif es_score >= (end_search_candidate.max_score - end_search_candidate.back_accept) && !is_in_index
            new_perm = Perm(
              0,
              generate_dna_all(es_moves),
              es_moves,
              es_moves_hash
            )
            push!(end_search_candidate.perms, new_perm)
            end_search_candidate.index[es_moves_hash] = new_perm
            es_accepted += 1

            end_search_candidate.idle_counter = max(0, end_search_candidate.idle_counter - 0.1)
            if es_score > (end_search_candidate.max_score - end_search_candidate.back_accept)

              end_search_candidate.improvement_counter += 1
            end

            verbose && println("$iteration. ES $(length(best.moves)) -> $es_score i:$(length(end_search_candidate.index))")
          end
        end

        end_searched[best.moves_hash] = true

        if stats !== nothing
          push!(stats.end_searches, (iteration, length(best.moves), es_max_before, length(results),
            isempty(results) ? 0 : maximum(length, values(results)), es_accepted, es_best))
        end
      end
      stats === nothing || (stats.end_search_ns += time_ns() - es_t0)

    end

    if iteration % debug_interval == 0
      stats === nothing || (maint_t0 = time_ns())
      should_print = verbose && iteration % print_interval == 0
      current_time = time()
      elapsed = current_time - last_debug_time


      for c in sort(candidates, by=(c -> c.max_score))
        if c.improvement_counter >= improvement_step_up
          prune_candidate!(c)
        end

        sort_fn =
          if (iteration ÷ debug_interval) % 2 == 0
            (p -> (-length(p.moves), p.visits))
          else
            (iteration ÷ debug_interval) % 2 == 1
            (p -> p.visits)
            # else
            #   function (p)
            #     score = length(p.moves)
            #     -(score - p.visits/(score * 10000))
            #   end
            # else
            #   function (p)
            #     score = length(p.moves)

            #     # normalization 
            #     min_score = c.max_score - c.back_accept
            #     normalized_score = (score - min_score) / (c.max_score - min_score + 0.0001)
            #     exploitation = normalized_score
            #     exploration = sqrt(2) * sqrt(log(c.visits + 1) / p.visits)
            #     -(exploitation + exploration)
            #   end

          end

        sort!(c.perms, by=sort_fn)

        if should_print
          max_pack = generate_pack(c.max_moves)

          println("$iteration. $(c.max_score) >$(c.max_score - c.back_accept) $(round(elapsed, digits=2))s idle:$(round(c.idle_counter, digits=1)) i:$(length(c.index)) impr:$(c.improvement_counter) $max_pack")
        end



        c.idle_counter += 1

        if c.idle_counter >= idle_reset
          c.improvement_counter = 0
          c.idle_counter = 0
          c.back_accept += idle_reset_step_back

          filter!(c.step_back_index) do (key, sbp)

            is_in_index = haskey(c.index, key)
            age = iteration - sbp.iteration_created

            if ! is_in_index && sbp.score >= (c.max_score - c.back_accept)
              m = sbp.moves
              h = points_hash(m)
              new_perm = Perm(
                sbp.visits,
                generate_dna_all(m),
                m,
                h
              )
              push!(c.perms, new_perm)
              c.index[h] = new_perm
            end

            false
          end

          empty!(c.step_back_index)
        end
      end

      if should_print
        last_debug_time = current_time
      end

      if stats !== nothing
        stats.maintenance_ns += time_ns() - maint_t0
        for (ci, c) in enumerate(candidates)
          scores = [length(p.moves) for p in c.perms]
          push!(stats.snapshots, (iteration, time() - start_time, ci, c.max_score, c.back_accept,
            length(c.perms), count(==(c.max_score), scores), length(unique(scores))))
        end
      end

    end

    iteration += 1
  end

  candidates
end

if abspath(PROGRAM_FILE) == @__FILE__
  main()
end