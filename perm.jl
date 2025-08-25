include("morpion.jl")
using Random
using DataStructures

function end_search(moves::Array{Move,1})
  score = length(moves)
  back_accept_modifier = -5

  index = Dict{UInt64,Array{Move,1}}()

  # Progressively wind back the moves taken on a board
  for step_back in 1:floor(Int64, score * 0.25)
    # Make the subset of moves on the board
    # move_policy = OrderedDict{Move,Int32}()
    board = initial_board()
    possible_moves = initial_moves()
    made_moves = Move[]

    move_index = 1
    for move in moves[1:end-step_back]
      push!(made_moves, move)
      make_move(board, move, possible_moves)
      # move_policy[move] = score - move_index - 1
      # move_index += 1
    end

    # Perform a random completion from where the moves left off
    # Keep track of new configurations found and reset search timer if a new one is found
    no_new_index_counter = 0
    no_new_index_counter_cut_off = 200
    while no_new_index_counter <= no_new_index_counter_cut_off && length(index) < 1000
      eval_board = copy(board)
      eval_possible_moves = copy(possible_moves)
      eval_made_moves = copy(made_moves)

      eval_move_index = move_index

      while !isempty(eval_possible_moves)
        random_possible_move = eval_possible_moves[rand(1:end)]
        push!(eval_made_moves, random_possible_move)
        make_move(eval_board, random_possible_move, eval_possible_moves)
        # move_policy[random_possible_move] = eval_move_index
        # eval_move_index += 1
      end

      eval_score = length(eval_made_moves)
      # extremely slow, must be improved (has to build the policy and then the hash, two iterations through the moves in the hot loop)
      # _, eval_points_hash = eval_dna_and_hash_move_policy_uint64(build_move_policy(eval_made_moves))
      eval_points_hash = points_hash(eval_made_moves)

      if eval_score > score + back_accept_modifier && !haskey(index, eval_points_hash)
        index[eval_points_hash] = eval_made_moves
        no_new_index_counter = 0
      end

      no_new_index_counter += 1
    end
  end

  index
end

function build_perm(moves::Vector{Move})
  perm_length = 46 * 46 * 4
  all_indices = collect(1:perm_length)

  # Get 1-based dna_indices of moves, in order
  move_indices = [dna_index(move) for move in moves]  # dna_index now must return in 1:perm_length

  # Build new index order: moves first, then others
  nonmove_indices = setdiff(all_indices, move_indices)
  new_order = vcat(move_indices, nonmove_indices)

  perm = Array{UInt16}(undef, perm_length)
  for i in 1:perm_length
    idx = new_order[i]
    value = UInt16(perm_length - i)
    perm[idx] = value
  end

  return perm
end

# Preallocated arrays for eval_dna_and_hash_move_policy!
eval_board = zeros(UInt8, 46 * 46)
eval_possible_moves = Vector{Move}()
sizehint!(eval_possible_moves, 200)
eval_made_moves = Vector{Move}()
sizehint!(eval_made_moves, 200)
eval_points_hash_board = zeros(Bool, 46 * 46)

function main()
  perm_length = 46 * 46 * 4
  perm = UInt16.(1:perm_length)
  shuffle!(perm)
  perm_moves, perm_moves_hash = eval_dna_and_hash(perm)

  max_score = length(perm_moves)
  max_moves = []
  iteration = 0

  inactivity_counter = 0
  inactivity_counter_reset = 500000
  inactivity_new_found_counter = 0
  inactivity_new_found_reset = 10
  step_back = 0

  debug_interval = 100000

  last_debug_time = time()
  index = Dict(perm_moves_hash => (build_move_policy(perm_moves), 0))
  index_keys = [perm_moves_hash]

  end_searched = Dict{UInt64,Bool}()

  focus_min = 100
  focus_max = 1000000
  focus_interval = 1000000
  focus = focus_min

  while true

    # focus = focus_min + (focus_max - focus_min) * ((iteration % focus_interval) / focus_interval)
    focus =
    # if (iteration ÷ focus_interval) % 2 == 0
      if iteration % 2 == 0
        focus_min
      else
        focus_max
      end

    max_key = nothing
    max_key_score = 0
    for key in rand(index_keys, 10)
      # for key in index_keys
      p_policy, p_visits = index[key]
      p_score = length(p_policy)

      key_score =
        if p_score >= (max_score - step_back)
          p_score - (p_visits / focus)
        else
          0
        end

      if key_score > max_key_score
        max_key = key
        max_key_score = key_score
      end
    end
    selected_key = max_key
    if selected_key === nothing
      selected_key = index_keys[(iteration%length(index_keys))+1]
    end

    # selected_key = index_keys[(iteration%length(index_keys))+1]

    move_policy, selected_visits = index[selected_key]
    selected_score = length(move_policy)

    index[selected_key] = (move_policy, selected_visits + 1)

    if !haskey(end_searched, selected_key) && selected_score >= (max_score - step_back) && selected_score > 100

      es_start = time()
      result_index = end_search(collect(keys(move_policy)))
      es_end = time()

      new_found_count = 0

      if !isempty(result_index)
        for found_index_key in collect(keys(result_index))


          found_moves = result_index[found_index_key]
          found_score = length(found_moves)

          _, f_key = eval_dna_and_hash_move_policy_uint64(build_move_policy(found_moves))


          if !haskey(index, f_key)
            if (found_score >= max_score - step_back) || found_score >= selected_score
              index[f_key] = (build_move_policy(found_moves), 0)
              push!(index_keys, f_key)

              println("$iteration.  es $selected_score > $found_score")

              if found_score > max_score - step_back
                inactivity_new_found_counter += 1
              end

              if found_score > max_score
                max_score = found_score
                max_moves = found_moves

                println("$iteration. ******** $max_score")

                index = Dict(f_key => (build_move_policy(found_moves), 0))
                index_keys = [f_key]

                step_back = 0
                inactivity_counter = 0
                inactivity_new_found_counter = 0
              end
            end
          end
        end
      end

      println("$iteration. ES $selected_score f:$(length(result_index)) n:$(new_found_count) $(round(es_end - es_start, digits=2))")

      end_searched[selected_key] = true
    else

      # TODO: do something about this copy
      eval_policy = copy(move_policy)
      eval_policy_key_set = keys(eval_policy)
      eval_policy_score = length(eval_policy_key_set)

      eval_policy[collect(eval_policy_key_set)[selected_visits%eval_policy_score+1]] = -100

      if (selected_visits ÷ eval_policy_score) % 2 == 1
        for _ in rand(1:4)
          eval_policy[rand(eval_policy_key_set)] = -100
        end
      end

      # TODO: this should return the move policy so it doesn't have to be built later
      eval_moves, eval_points_hash = eval_dna_and_hash_move_policy_uint64(eval_policy)
      eval_score = length(eval_moves)

      # # trace
      if iteration % 10001 == 0
        inactivity_pct = round(100 * inactivity_counter / inactivity_counter_reset)
        println("$iteration. $selected_score ($selected_visits) $(max_score - step_back)/$max_score i:$(length(index_keys)) $(lpad(inactivity_pct, 2, '0'))%")
      end

      if (eval_score > max_score)
        max_score = eval_score
        max_moves = eval_moves

        println("$iteration. ******** $max_score")
        println("$iteration. $selected_score ($selected_visits) -> $eval_score")

        index = Dict(eval_points_hash => (build_move_policy(eval_moves), 0))
        index_keys = [eval_points_hash]

        step_back = 0
        inactivity_counter = 0
        inactivity_new_found_counter = 0

      else
        is_in_index = haskey(index, eval_points_hash)


        if !is_in_index

          if eval_score >= (max_score - step_back)

            println("$iteration. $selected_score ($selected_visits) -> $eval_score")

            if eval_score >= selected_score
              p_policy, p_visits = index[selected_key]
              index[selected_key] = (p_policy, 0)
            end

            if eval_score > (max_score - step_back)
              inactivity_new_found_counter += 1

            end

            inactivity_counter = 0

            index[eval_points_hash] = (build_move_policy(eval_moves), 0)
            push!(index_keys, eval_points_hash)
          end
        else
          p_policy, p_visits = index[eval_points_hash]
          index[eval_points_hash] = (build_move_policy(eval_moves), p_visits)
        end

      end
    end


    if iteration > 0 && iteration % debug_interval == 0
      current_time = time()
      elapsed = current_time - last_debug_time
      inactivity_pct = round(100 * inactivity_counter / inactivity_counter_reset)
      println("$iteration. $max_score ($(max_score - step_back) $(lpad(inactivity_pct, 2, '0'))% $inactivity_new_found_counter/$inactivity_new_found_reset $(length(index_keys)) $(round(elapsed, digits=2))s)")
      last_debug_time = current_time

      # for (key, value) in index
      #   p_policy, p_visits = value
      #   p_score = length(p_policy)
      #   m, h = eval_dna_and_hash_move_policy_uint64(p_policy)
      #   is_match = key == h
      #   println("$p_score: $p_visits $is_match $(length(m))")
      # end

      # empty!(end_searched)
    end

    if iteration > 0 && iteration % 10000000 == 0
      println()
      println("$max_score")
      println("$max_moves")
      println()
    end

    if inactivity_counter >= inactivity_counter_reset
      # if selected_score > 10000
      step_back += 1
      inactivity_counter = 0
    end

    if inactivity_new_found_counter >= inactivity_new_found_reset
      step_back = max(0, step_back - 1)
      inactivity_new_found_counter = 0
      inactivity_counter = 0

      # a = length(index_keys)
      # b = length(index)
      # filter!(function (k)
      #     p_policy, p_visits = index[k]
      #     p_score = length(p_policy)
      #     should_keep = p_score >= (max_score - step_back)

      #     if !should_keep
      #       delete!(index, k)
      #       delete!(end_searched, k)
      #       # println("- $p_score")
      #     end

      #     should_keep
      #   end, index_keys)

      # println(" --- index: $b -> $(length(index)) ->  keys: $a -> $(length(index_keys))")

    end

    # if selected_visits > 1000000 && length(index_keys) > 10
    #   taboo_index[selected_key] = true

    #   println("$iteration: - $selected_score")

    #   delete!(index, selected_key)
    #   filter!((k) -> k != selected_key, index_keys)
    # end

    inactivity_counter += 1
    iteration += 1
  end
end

main()

# 169
# Move[Move(9, 7, 9, 3, 4), Move(10, 3, 6, 3, 2), Move(10, 6, 6, 6, 2), Move(8, 4, 6, 2, 3), Move(7, 7, 5, 9, 1), Move(8, 5, 6, 7, 1), Move(8, 7, 8, 3, 4), Move(10, 7, 6, 7, 2), Move(7, 4, 6, 3, 3), Move(2, 7, 0, 5, 3), Move(6, 5, 6, 5, 4), Move(6, 4, 6, 1, 4), Move(10, 4, 6, 4, 2), Move(3, 5, 3, 5, 4), Move(3, 4, 3, 1, 4), Move(0, 2, 0, 2, 4), Move(10, 5, 10, 3, 4), Move(7, 2, 6, 1, 3), Move(7, 8, 6, 9, 1), Move(7, 9, 3, 9, 2), Move(7, 5, 7, 5, 4), Move(5, 3, 5, 3, 3), Move(11, 5, 7, 5, 2), Move(7, 1, 7, 1, 4), Move(8, 2, 7, 1, 3), Move(8, 8, 7, 9, 1), Move(4, 3, 2, 3, 2), Move(10, 2, 6, 6, 1), Move(5, 4, 4, 3, 3), Move(4, 5, 2, 7, 1), Move(5, 5, 3, 5, 2), Move(9, 1, 5, 5, 1), Move(5, 6, 3, 4, 3), Move(4, 6, 2, 6, 2), Move(4, 4, 4, 4, 3), Move(2, 4, 2, 4, 2), Move(8, 0, 4, 4, 1), Move(9, 2, 6, 2, 2), Move(10, 1, 6, 5, 1), Move(8, 1, 6, 1, 2), Move(8, -1, 8, -1, 4), Move(4, 2, 4, 2, 4), Move(5, 7, 3, 5, 3), Move(5, 8, 5, 5, 4), Move(4, 8, 4, 8, 2), Move(1, 5, 1, 5, 3), Move(4, 7, 2, 7, 2), Move(2, 5, 2, 5, 3), Move(2, 2, 2, 2, 4), Move(5, 2, 2, 2, 2), Move(5, 1, 5, 1, 4), Move(-1, 5, -1, 5, 1), Move(-2, 5, -2, 5, 2), Move(4, 10, 4, 6, 4), Move(7, -1, 3, 3, 1), Move(6, -2, 6, -2, 3), Move(2, 10, 2, 10, 1), Move(2, 9, 2, 9, 1), Move(2, 8, 2, 6, 4), Move(1, 7, 0, 6, 3), Move(1, 9, 1, 9, 1), Move(7, 0, 4, 3, 1), Move(9, 0, 5, 0, 2), Move(9, -1, 9, -1, 4), Move(10, -1, 6, 3, 1), Move(6, -1, 6, -1, 2), Move(5, -2, 5, -2, 3), Move(6, -3, 6, -3, 4), Move(7, -2, 6, -3, 3), Move(7, -3, 7, -3, 4), Move(5, -1, 3, 1, 1), Move(5, -3, 5, -3, 4), Move(4, 1, 3, 2, 1), Move(2, 1, 2, 1, 2), Move(4, -1, 2, 1, 1), Move(4, -2, 4, -2, 4), Move(3, -3, 3, -3, 3), Move(3, -2, 3, -2, 2), Move(3, -1, 3, -3, 4), Move(2, -1, 2, -1, 2), Move(1, -2, 1, -2, 3), Move(2, -2, 2, -2, 3), Move(2, -3, 2, -3, 3), Move(0, 7, 0, 7, 1), Move(-1, 1, -1, 1, 3), Move(2, 0, 2, -2, 4), Move(1, 1, 1, 1, 1), Move(1, 0, 1, 0, 2), Move(0, -1, 0, -1, 3), Move(0, 0, 0, 0, 3), Move(1, -1, -1, 1, 1), Move(1, 2, 1, -2, 4), Move(1, 4, 1, 2, 4), Move(-1, 6, -1, 6, 1), Move(-2, 6, -2, 6, 2), Move(-1, 4, -2, 5, 1), Move(-2, 4, -2, 4, 2), Move(0, -2, 0, -2, 3), Move(-1, -2, -1, -2, 2), Move(10, 0, 10, -1, 4), Move(0, 1, 0, -2, 4), Move(-1, 0, -1, 0, 3), Move(-2, 1, -2, 1, 1), Move(-1, 2, -2, 1, 3), Move(-2, 2, -2, 2, 2), Move(-1, 3, -1, 2, 4), Move(-3, 1, -3, 1, 3), Move(-2, 3, -2, 3, 2), Move(-2, 7, -2, 3, 4), Move(-1, 7, -2, 7, 2), Move(0, 8, -2, 6, 3), Move(1, 8, 0, 8, 2), Move(1, 10, 1, 6, 4), Move(3, 10, -1, 6, 3), Move(0, 10, 0, 10, 2), Move(0, 9, 0, 6, 4), Move(-1, 9, -1, 9, 2), Move(-4, 1, -4, 1, 2), Move(-3, 2, -4, 1, 3), Move(2, 11, 2, 11, 1), Move(-1, 8, -2, 7, 3), Move(-2, 10, -2, 10, 1), Move(-2, 8, -2, 8, 1), Move(-1, 10, -1, 6, 4), Move(-2, 11, -2, 11, 1), Move(-2, 9, -2, 7, 4), Move(-3, 5, -3, 5, 1), Move(-1, -1, -1, -2, 4), Move(-2, -1, -2, -1, 2), Move(4, -3, 2, -3, 2), Move(-3, 4, -3, 4, 1), Move(5, -4, 1, 0, 1), Move(-2, 0, -2, -1, 4), Move(-3, 0, -3, 0, 2), Move(-3, 3, -3, 0, 4), Move(-4, 2, -4, 2, 3), Move(-5, 3, -5, 3, 1), Move(-5, 2, -5, 2, 1), Move(-6, 2, -6, 2, 2), Move(-4, 4, -6, 2, 3), Move(-4, 3, -5, 2, 3), Move(-4, 5, -4, 1, 4), Move(-5, 5, -5, 5, 1), Move(-6, 3, -6, 3, 2), Move(-6, 5, -6, 5, 2), Move(-5, 4, -6, 5, 1), Move(-5, 6, -5, 2, 4), Move(-6, 4, -6, 4, 2), Move(-3, 6, -6, 3, 3), Move(-6, 6, -6, 2, 4), Move(-4, 6, -6, 6, 2), Move(-3, 7, -4, 6, 3), Move(-3, 8, -3, 4, 4), Move(-4, 7, -6, 5, 3), Move(-4, 8, -4, 8, 2), Move(-5, 9, -5, 9, 1), Move(-4, 9, -4, 5, 4), Move(-5, 10, -5, 10, 1), Move(-3, 9, -5, 9, 2), Move(-5, 7, -6, 6, 3), Move(-6, 7, -6, 7, 2), Move(-7, 8, -7, 8, 1), Move(-5, 8, -5, 6, 4), Move(-3, 10, -6, 7, 3), Move(-4, 10, -5, 10, 2), Move(-6, 9, -6, 9, 1), Move(-4, 11, -4, 11, 1), Move(-3, 12, -7, 8, 3), Move(-3, 11, -3, 8, 4)]

# 170
# Move[Move(9, 7, 9, 3, 4), Move(7, 9, 3, 9, 2), Move(3, 5, 3, 5, 4), Move(3, 4, 3, 1, 4), Move(6, 5, 6, 5, 4), Move(6, 4, 6, 1, 4), Move(7, 7, 5, 9, 1), Move(4, 6, 0, 6, 2), Move(5, 7, 3, 5, 3), Move(8, 7, 5, 7, 2), Move(5, 6, 4, 6, 2), Move(5, 3, 5, 3, 2), Move(7, 5, 5, 3, 3), Move(7, 8, 7, 5, 4), Move(10, 5, 6, 9, 1), Move(8, 5, 6, 5, 2), Move(8, 4, 8, 3, 4), Move(5, 1, 5, 1, 3), Move(7, 2, 6, 1, 3), Move(10, 2, 6, 6, 1), Move(5, 8, 5, 8, 1), Move(5, 5, 5, 5, 4), Move(4, 4, 3, 3, 3), Move(4, 3, 1, 3, 2), Move(5, 4, 4, 3, 3), Move(5, 2, 5, 1, 4), Move(7, 4, 5, 2, 3), Move(10, 4, 6, 4, 2), Move(7, 1, 7, 1, 4), Move(8, 2, 6, 0, 3), Move(9, 2, 6, 2, 2), Move(10, 1, 6, 5, 1), Move(9, 1, 5, 5, 1), Move(8, 1, 6, 1, 2), Move(4, 5, 4, 5, 1), Move(2, 5, 2, 5, 2), Move(1, 2, 1, 2, 3), Move(2, 4, 2, 4, 2), Move(8, 0, 4, 4, 1), Move(8, -1, 8, -1, 4), Move(2, 2, 2, 2, 4), Move(4, 2, 2, 2, 2), Move(4, 1, 4, 1, 4), Move(6, -1, 2, 3, 1), Move(7, -1, 3, 3, 1), Move(4, 7, 2, 5, 3), Move(4, 8, 4, 5, 4), Move(1, 5, 1, 5, 3), Move(2, 10, 2, 10, 1), Move(2, 8, 2, 8, 2), Move(1, 9, 1, 9, 1), Move(2, 1, 2, 1, 2), Move(2, 9, 2, 9, 1), Move(2, 7, 2, 6, 4), Move(1, 7, 1, 7, 2), Move(1, 8, 1, 5, 4), Move(0, 9, 0, 9, 1), Move(0, 8, 0, 8, 1), Move(0, 7, 0, 5, 4), Move(-1, 8, -1, 8, 1), Move(-2, 8, -2, 8, 2), Move(-1, 9, -1, 9, 2), Move(-1, 7, -1, 7, 1), Move(-2, 6, -2, 6, 3), Move(-1, 5, -2, 6, 1), Move(-2, 5, -2, 5, 2), Move(-2, 4, -2, 4, 3), Move(-2, 7, -2, 4, 4), Move(-1, 6, -1, 5, 4), Move(-3, 4, -3, 4, 3), Move(1, 4, -2, 7, 1), Move(1, 1, 1, 1, 4), Move(-1, 4, -2, 4, 2), Move(-3, 6, -3, 6, 1), Move(-4, 6, -4, 6, 2), Move(-3, 7, -3, 7, 2), Move(-5, 5, -5, 5, 3), Move(7, 0, 4, 3, 1), Move(9, 0, 5, 0, 2), Move(9, -1, 9, -1, 4), Move(5, -1, 5, -1, 2), Move(6, -2, 2, 2, 1), Move(5, -3, 5, -3, 3), Move(5, -2, 5, -3, 4), Move(4, -3, 4, -3, 3), Move(6, -3, 6, -3, 4), Move(7, -2, 6, -3, 3), Move(10, 3, 10, 1, 4), Move(5, 10, 1, 6, 3), Move(7, -3, 7, -3, 4), Move(4, -1, 2, 1, 1), Move(4, -2, 4, -3, 4), Move(3, -2, 3, -2, 2), Move(2, -3, 2, -3, 3), Move(3, -3, 2, -3, 2), Move(3, -1, 3, -3, 4), Move(2, -4, 2, -4, 3), Move(2, 0, 1, 1, 1), Move(1, -1, 1, -1, 3), Move(1, 0, 1, 0, 2), Move(0, -1, 0, -1, 3), Move(2, -1, 1, -1, 2), Move(0, 1, 0, 1, 1), Move(0, 2, 0, 1, 4), Move(-1, 1, -1, 1, 3), Move(-2, 1, -2, 1, 2), Move(-1, 2, -2, 1, 3), Move(-2, 2, -2, 2, 2), Move(-1, 3, -1, 1, 4), Move(-3, 1, -3, 1, 3), Move(2, -2, 2, -3, 4), Move(1, -3, 1, -3, 3), Move(1, -2, 1, -3, 4), Move(0, -3, 0, -3, 3), Move(0, 0, -1, 1, 1), Move(0, -2, 0, -3, 4), Move(-1, -2, -1, -2, 2), Move(-1, 0, -2, 1, 1), Move(-3, 5, -3, 5, 1), Move(-3, 3, -3, 3, 4), Move(-4, 4, -5, 5, 1), Move(-2, 3, -3, 3, 2), Move(-4, 5, -4, 5, 1), Move(-5, 4, -5, 4, 3), Move(-6, 5, -6, 5, 2), Move(-6, 4, -6, 4, 2), Move(-2, 0, -2, 0, 4), Move(-3, 0, -3, 0, 2), Move(-1, -1, -2, 0, 1), Move(-1, -3, -1, -3, 4), Move(-2, -3, -2, -3, 2), Move(-2, -2, -2, -2, 3), Move(-3, 2, -3, 2, 3), Move(-3, -1, -3, -1, 4), Move(-2, -1, -3, -1, 2), Move(-3, -2, -3, -2, 3), Move(-4, 1, -4, 1, 1), Move(-2, -4, -2, -4, 4), Move(-3, -5, -3, -5, 3), Move(-4, 3, -6, 5, 1), Move(-4, 2, -4, 2, 4), Move(-5, 3, -6, 4, 1), Move(-6, 2, -6, 2, 3), Move(-5, 2, -6, 2, 2), Move(-5, 1, -5, 1, 4), Move(-6, 0, -6, 0, 3), Move(-6, 1, -6, 1, 2), Move(-7, 0, -7, 0, 3), Move(-6, 3, -6, 1, 4), Move(-4, 0, -6, 2, 1), Move(-5, 0, -7, 0, 2), Move(-4, -1, -6, 1, 1), Move(-4, -2, -4, -2, 4), Move(-5, -2, -5, -2, 2), Move(-5, -3, -5, -3, 3), Move(-6, -3, -6, -3, 3), Move(-5, -1, -5, -3, 4), Move(-3, -3, -6, 0, 1), Move(-3, -4, -3, -5, 4), Move(-4, -3, -6, -3, 2), Move(-4, -5, -4, -5, 3), Move(-6, -1, -7, 0, 1), Move(-7, -1, -7, -1, 2), Move(-6, -2, -6, -3, 4), Move(-4, -4, -7, -1, 1), Move(-4, -6, -4, -6, 4), Move(-7, -3, -7, -3, 3), Move(-7, -2, -7, -2, 3), Move(-7, 3, -7, 3, 2), Move(-7, -4, -7, -4, 4)]

