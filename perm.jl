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
  inactivity_counter_reset = 1000000
  inactivity_new_found_counter = 0
  inactivity_new_found_reset = 100
  step_back = 0

  debug_interval = 100000

  last_debug_time = time()
  index = Dict(perm_moves_hash => (build_move_policy(perm_moves), 0))
  index_keys = [perm_moves_hash]

  end_searched = Dict{UInt64,Bool}()


  while true

    max_key = nothing
    max_key_score = 0
    for key in rand(index_keys, 10)
      # for key in index_keys
      p_policy, p_visits = index[key]
      p_score = length(p_policy)

      key_score = p_score - (p_visits / 1000000.0)

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

    if !haskey(end_searched, selected_key) && selected_score > 100

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
            if (found_score >= max_score - step_back)
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

      if floor(selected_visits / eval_policy_score) % 2 == 1
        eval_policy[rand(eval_policy_key_set)] = -100
        eval_policy[rand(eval_policy_key_set)] = -100
      end

      # TODO: this should return the move policy so it doesn't have to be built later
      eval_moves, eval_points_hash = eval_dna_and_hash_move_policy_uint64(eval_policy)
      eval_score = length(eval_moves)

      # # trace
      if iteration % 10000 == 0
        println("$iteration. $selected_score ($selected_visits) ma:$(max_score - step_back)/$max_score")
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

            p_policy, p_visits = index[selected_key]
            index[selected_key] = (p_policy, 0)

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

      a = length(index_keys)
      b = length(index)

      # filter!(function (k)
      #     p, p_moves, p_visits = index[k]
      #     p_score = length(p_moves)
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