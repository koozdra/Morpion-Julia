include("morpion.jl")
using Random
using DataStructures

function end_search(moves::Array{Move,1}, back_accept)
  score = length(moves)

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

      if eval_score > score - back_accept && !haskey(index, eval_points_hash)
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
  inactivity_new_found_reset = 10
  step_back = 0

  backup_back = 1

  debug_interval = 100000

  last_debug_time = time()
  index = Dict(perm_moves_hash => (build_move_policy(perm_moves), 0))
  index_keys = [perm_moves_hash]

  backup = Dict(perm_moves_hash => (build_move_policy(perm_moves), 0))

  end_searched = Dict{UInt64,Int64}()
  taboo = Dict{UInt64,Bool}()

  end_search_debounce = 5000
  end_search_ttl = 10000000
  last_end_search_iteration = 0

  taboo_visits = 1000000

  focus_min = 1
  focus_max = 100000
  focus_interval = 1000000
  focus = focus_min

  focus_balance_distance = 10000000

  for i in 1:1000
    perm_length = 46 * 46 * 4
    perm = UInt16.(1:perm_length)
    shuffle!(perm)
    perm_moves, perm_moves_hash = eval_dna_and_hash(perm)

    index[perm_moves_hash] = (build_move_policy(perm_moves), 0)
  end

  while true


    # focus_balance = 50 * (1 + sin(2π * iteration / focus_balance_distance))

    # if iteration % 1000000 == 0
    #   println("$iteration. refocussing...")
    #   step_back = 0

    #   filter!(function (k)
    #       p_policy, p_visits = index[k]
    #       p_score = length(p_policy)
    #       should_keep = p_score >= max_score - step_back

    #       if !should_keep
    #         delete!(index, k)
    #         # delete!(end_searched, k)
    #         # println("- $p_score")
    #         backup[k] = (p_policy, 0)
    #       end

    #       should_keep
    #     end, index_keys)
    # end

    focus =
    # if iteration % 100 <= focus_balance
    # if iteration % 2 == 0
      if iteration % 10 == 0
        focus_min
      else
        focus_max
      end

    max_key = nothing
    max_key_score = -99999999
    for key in rand(index_keys, 10)
      # for key in index_keys
      p_policy, p_visits = index[key]
      # p_score = length(p_policy)
      # is_in_taboo = haskey(taboo, key)

      key_score = -p_visits
      # key_score = p_score - (p_visits / focus)
      # if focus == focus_max
      #   if p_visits < taboo_visits
      #     p_score - (p_visits / focus_max)
      #   else
      #     0
      #   end
      # else
      #   -p_visits
      # end

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

    should_end_search =
      if haskey(end_searched, selected_key)
        last_visited_iteration = end_searched[selected_key]
        diff = iteration - last_visited_iteration
        diff > end_search_ttl
      else
        true
      end

    if selected_score < (max_score - step_back)
      println(" - selecting out of bounds")
      filter!(function (k)
          p_policy, p_visits = index[k]
          p_score = length(p_policy)
          should_keep = k != selected_key

          if !should_keep
            delete!(index, k)
            # delete!(end_searched, k)
            # println("- $p_score")
            backup[k] = (p_policy, p_visits)
          end

          should_keep
        end, index_keys)

    elseif should_end_search &&
           selected_score >= (max_score - step_back) &&
           selected_score > 100 &&
           iteration > last_end_search_iteration + end_search_debounce

      es_start = time()
      result_index = end_search(collect(keys(move_policy)), step_back)
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
              if (found_score > max_score - step_back)
                inactivity_counter = max(0, inactivity_counter - floor(inactivity_counter_reset / 100))
              end

              if found_score > max_score - step_back
                inactivity_new_found_counter += 1
              end

              if found_score > max_score
                max_score = found_score
                max_moves = found_moves

                println("$iteration. ******** $max_score")

                # index = Dict(f_key => (build_move_policy(found_moves), 0))
                # index_keys = [f_key]
                # index[eval_points_hash] = (build_move_policy(eval_moves), 0)
                # push!(index_keys, eval_points_hash)

                step_back = 0

                inactivity_new_found_counter = 0
              end
              # elseif (found_score >= max_score - step_back - backup_back) && !haskey(backup, f_key)
              #   backup[f_key] = (build_move_policy(found_moves), 0)
            end
          end
        end
      end

      println("$iteration. ES $selected_score f:$(length(result_index)) n:$(new_found_count) $(round(es_end - es_start, digits=2))")

      end_searched[selected_key] = iteration
      last_end_search_iteration = iteration
    else

      # TODO: do something about this copy
      eval_policy = copy(move_policy)
      eval_policy_key_set = keys(eval_policy)
      eval_policy_score = length(eval_policy_key_set)

      # TODO: don't wait till selected visits to start random
      # make this more modular

      eval_policy[collect(eval_policy_key_set)[selected_visits%eval_policy_score+1]] = -100

      if (selected_visits ÷ eval_policy_score) % 2 == 0
        for _ in rand(1:4)
          eval_policy[rand(eval_policy_key_set)] = -100
        end
      end

      # TODO: this should return the move policy so it doesn't have to be built later
      eval_moves, eval_points_hash = eval_dna_and_hash_move_policy_uint64(eval_policy)
      eval_score = length(eval_moves)

      # trace
      if iteration % 10001 == 0
        min_visited = 9999999999

        for (key, value) in index
          p_policy, p_visits = value
          p_score = length(p_policy)
          if (p_score >= max_score - step_back)
            min_visited = min(min_visited, p_visits)
          end
        end

        println("$iteration. $selected_score ($selected_visits) $(max_score - step_back)/$max_score i:$(length(index_keys)) s:$step_back")

        if min_visited > focus_min
          step_back += 1


          for (b_key, b_value) in collect(pairs(backup))
            b_policy, b_visits = b_value
            b_score = length(b_policy)
            if b_score >= max_score - step_back && !haskey(index, b_key)
              push!(index_keys, b_key)
              index[b_key] = (b_policy, b_visits)
              # println(" + $b_score")
            end
          end
        end
      end

      if (eval_score > max_score)
        max_score = eval_score
        max_moves = eval_moves

        println("$iteration. ******** $max_score")
        println("$iteration. $selected_score ($selected_visits) -> $eval_score")

        # index = Dict(eval_points_hash => (build_move_policy(eval_moves), 0))
        # index_keys = [eval_points_hash]
        index[eval_points_hash] = (build_move_policy(eval_moves), 0)
        push!(index_keys, eval_points_hash)

        step_back = 0
        inactivity_counter = 0
        inactivity_new_found_counter = 0

      else
        is_in_index = haskey(index, eval_points_hash)
        is_in_taboo = haskey(taboo, eval_points_hash)


        if !is_in_index

          if eval_score >= (max_score - step_back)

            println("$iteration. $selected_score ($selected_visits) -> $eval_score s:$step_back")
            if eval_score > (max_score - step_back)
              inactivity_counter = max(0, inactivity_counter - floor(inactivity_counter_reset / 100))
            end


            p_policy, p_visits = index[selected_key]
            index[selected_key] = (p_policy, 0)

            if eval_score > (max_score - step_back)
              inactivity_new_found_counter += 1

            end

            # inactivity_counter = max(0, inactivity_counter - (inactivity_counter_reset / 100))

            index[eval_points_hash] = (build_move_policy(eval_moves), 0)
            push!(index_keys, eval_points_hash)
            # elseif eval_score >= (max_score - step_back - backup_back) && !haskey(backup, eval_points_hash)
            #   backup[eval_points_hash] = (build_move_policy(eval_moves), 0)
            # println("$iteration.  $selected_score ($selected_visits) -> $eval_score")
          end
        else
          p_policy, p_visits = index[eval_points_hash]
          index[eval_points_hash] = (build_move_policy(eval_moves), p_visits)
        end

      end
    end


    if iteration > 0 && iteration % debug_interval == 0
      # min_visited = 9999999999

      # for (key, value) in index
      #   p_policy, p_visits = value
      #   p_score = length(p_policy)
      #   if (p_score >= max_score - step_back)
      #     min_visited = min(min_visited, p_visits)
      #   end
      # end

      current_time = time()
      elapsed = current_time - last_debug_time
      println("$iteration. $max_score ($(max_score - step_back) $inactivity_new_found_counter/$inactivity_new_found_reset $(length(index_keys)) $(round(elapsed, digits=2))s)")
      last_debug_time = current_time

      # if min_visited > focus_min
      #   step_back += 1


      #   for (b_key, b_value) in collect(pairs(backup))
      #     b_policy, b_visits = b_value
      #     b_score = length(b_policy)
      #     if b_score >= max_score - step_back && !haskey(index, b_key)
      #       push!(index_keys, b_key)
      #       index[b_key] = (b_policy, 0)
      #       # println(" + $b_score")
      #     end
      #   end
      # end



      # for (key, value) in index
      #   p_policy, p_visits = value
      #   p_score = length(p_policy)
      #   m, h = eval_dna_and_hash_move_policy_uint64(p_policy)
      #   is_match = key == h
      #   println("$p_score: $p_visits $is_match $(length(m))")
      # end

      # empty!(end_searched)
    end

    if iteration > 0 && iteration % 5000000 == 0
      println()
      println("$max_score")
      println("$max_moves")
      println()
    end

    # if selected_visits > taboo_visits && !haskey(taboo, selected_key)
    #   taboo[selected_key] = true
    #   println("$iteration. - $selected_score")
    # end

    # if iteration > 0 && iteration % 10000000 == 0
    #   step_back = 0
    #   inactivity_new_found_counter = 0
    #   inactivity_counter = 0

    #   # empty!(end_searched)

    #   println("---------------------------------------------------")
    # end

    # if inactivity_counter >= inactivity_counter_reset
    #   # if selected_score > 10000
    #   step_back += 1
    #   inactivity_counter = 0

    #   for (b_key, b_value) in collect(pairs(backup))
    #     b_policy, b_visits = b_value
    #     b_score = length(b_policy)
    #     if b_score >= max_score - step_back && !haskey(index, b_key)
    #       push!(index_keys, b_key)
    #       index[b_key] = (b_policy, 0)
    #       # println(" + $b_score")
    #     end
    #   end
    # end

    anneal_distance = 10_000_000
    anneal_max_step_back = 11

    calc_step_back = anneal_max_step_back - floor((iteration % anneal_distance) * (anneal_max_step_back + 1) / anneal_distance)

    if calc_step_back != step_back
      step_back = calc_step_back

      filter!(function (k)
          p_policy, p_visits = index[k]
          p_score = length(p_policy)
          should_keep = p_score >= max_score - step_back

          if !should_keep
            delete!(index, k)
            # delete!(end_searched, k)
            # println("- $p_score")
            backup[k] = (p_policy, p_visits)
          end

          should_keep
        end, index_keys)
    end

    # if inactivity_new_found_counter >= inactivity_new_found_reset
    #   step_back = max(0, step_back - 1)
    #   inactivity_new_found_counter = 0
    #   inactivity_counter = 0

    #   filter!(function (k)
    #       p_policy, p_visits = index[k]
    #       p_score = length(p_policy)
    #       should_keep = p_score >= max_score - step_back

    #       if !should_keep
    #         delete!(index, k)
    #         # delete!(end_searched, k)
    #         # println("- $p_score")
    #         backup[k] = (p_policy, 0)
    #       end

    #       should_keep
    #     end, index_keys)
    # end

    if length(backup) > 500000
      kvs = collect(backup)                         # Vector of Pair(key => (array, int))
      sort!(kvs, by=kv -> length(last(kv)[1]))    # sort by length of the array in the tuple
      k = fld(length(kvs), 2)                       # number to drop (lower half)
      for kv in kvs[1:k]
        delete!(backup, first(kv))                # remove those keys
      end
      println("cleaning backup: $(length(backup))")
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
# Move[Move(3, 10, 3, 6, 4), Move(6, 10, 6, 6, 4), Move(4, 6, 0, 6, 2), Move(4, 8, 2, 6, 3), Move(5, 6, 4, 6, 2), Move(2, 2, 0, 4, 1), Move(5, 8, 3, 10, 1), Move(2, 8, 2, 8, 2), Move(2, 7, 0, 5, 3), Move(2, 9, 2, 9, 2), Move(2, 10, 2, 6, 4), Move(5, 7, 2, 10, 1), Move(5, 10, 5, 6, 4), Move(4, 10, 2, 10, 2), Move(7, 7, 4, 10, 1), Move(1, 7, 0, 6, 3), Move(4, 3, 0, 3, 2), Move(5, 3, 4, 3, 2), Move(7, 0, 3, 0, 2), Move(9, 7, 9, 3, 4), Move(0, 7, 0, 3, 4), Move(4, 7, 0, 7, 2), Move(7, 10, 3, 6, 3), Move(6, 5, 2, 9, 1), Move(4, 11, 4, 7, 4), Move(6, 4, 6, 2, 4), Move(5, 5, 2, 8, 1), Move(4, 4, 2, 2, 3), Move(4, 5, 4, 3, 4), Move(3, 5, 1, 7, 1), Move(3, 4, 3, 2, 4), Move(1, 8, 0, 7, 3), Move(8, 7, 4, 7, 2), Move(7, 8, 4, 11, 1), Move(8, 9, 4, 5, 3), Move(7, 9, 7, 6, 4), Move(8, 10, 4, 6, 3), Move(8, 8, 8, 6, 4), Move(5, 4, 1, 8, 1), Move(5, 2, 5, 2, 4), Move(7, 4, 3, 4, 2), Move(2, 5, 1, 6, 1), Move(1, 5, 0, 5, 2), Move(2, 4, 2, 2, 4), Move(4, 2, 2, 2, 2), Move(5, 1, 1, 5, 1), Move(3, -1, 3, -1, 3), Move(3, -2, 3, -2, 4), Move(1, 4, 1, 4, 4), Move(-1, 2, -1, 2, 3), Move(4, 1, 0, 5, 1), Move(4, -1, 4, -1, 4), Move(7, 1, 3, 1, 2), Move(0, 2, 0, 2, 3), Move(7, 2, 4, -1, 3), Move(7, 5, 7, 2, 4), Move(8, 5, 4, 5, 2), Move(10, 7, 6, 3, 3), Move(10, 8, 6, 4, 3), Move(9, 8, 6, 8, 2), Move(10, 9, 6, 5, 3), Move(11, 6, 7, 10, 1), Move(9, 9, 6, 9, 2), Move(10, 10, 6, 6, 3), Move(10, 6, 10, 6, 4), Move(11, 5, 7, 9, 1), Move(12, 6, 8, 6, 2), Move(11, 7, 8, 10, 1), Move(8, 4, 7, 3, 3), Move(8, 2, 8, 2, 4), Move(10, 4, 8, 2, 3), Move(11, 4, 7, 4, 2), Move(11, 3, 11, 3, 4), Move(12, 2, 8, 6, 1), Move(12, 7, 8, 7, 2), Move(10, 5, 8, 3, 3), Move(12, 5, 8, 5, 2), Move(12, 3, 8, 7, 1), Move(10, 3, 8, 3, 2), Move(10, 2, 10, 2, 4), Move(11, 2, 7, 6, 1), Move(11, 1, 7, 5, 1), Move(2, 1, 2, 1, 3), Move(-1, 4, -1, 4, 2), Move(1, 2, -1, 4, 1), Move(-2, 2, -2, 2, 2), Move(-1, 3, -2, 2, 3), Move(12, 4, 12, 3, 4), Move(9, 2, 6, 2, 2), Move(8, 1, 8, 1, 3), Move(10, 1, 6, 5, 1), Move(9, 1, 7, 1, 2), Move(10, 0, 6, 4, 1), Move(8, 0, 8, 0, 3), Move(9, -1, 5, 3, 1), Move(9, 0, 9, -1, 4), Move(10, -1, 6, 3, 1), Move(8, -1, 8, -1, 3), Move(8, -2, 8, -2, 3), Move(11, 0, 7, 0, 2), Move(11, -1, 11, -1, 4), Move(7, -1, 7, -1, 2), Move(9, -3, 5, 1, 1), Move(9, -2, 5, 2, 1), Move(7, -2, 7, -2, 4), Move(10, -2, 10, -2, 4), Move(6, -2, 6, -2, 2), Move(6, -1, 6, -2, 4), Move(8, -3, 4, 1, 1), Move(7, -4, 7, -4, 3), Move(5, -1, 3, -1, 2), Move(4, -2, 4, -2, 3), Move(5, -2, 5, -2, 4), Move(4, -3, 4, -3, 3), Move(2, -2, 2, -2, 2), Move(9, 10, 6, 10, 2), Move(9, 11, 9, 7, 4), Move(8, -4, 8, -4, 4), Move(7, -5, 7, -5, 3), Move(7, -3, 4, 0, 1), Move(7, -6, 7, -6, 4), Move(6, -3, 3, 0, 1), Move(5, -3, 5, -3, 2), Move(6, -4, 3, -1, 1), Move(4, -4, 4, -4, 3), Move(5, -4, 4, -4, 2), Move(4, -5, 4, -5, 3), Move(6, -5, 3, -2, 1), Move(4, -6, 4, -6, 4), Move(6, -6, 6, -6, 4), Move(2, 0, 2, 0, 3), Move(1, 1, -1, 3, 1), Move(1, 0, 1, 0, 4), Move(2, -1, 2, -2, 4), Move(0, 1, -1, 2, 1), Move(-1, 0, -1, 0, 3), Move(0, 0, -1, 0, 2), Move(0, -1, 0, -1, 4), Move(-1, 1, -1, 1, 2), Move(1, -1, -2, 2, 1), Move(-1, -1, -1, -1, 2), Move(-1, -2, -1, -2, 4), Move(-2, -2, -2, -2, 3), Move(-2, -3, -2, -3, 3), Move(1, -2, 1, -2, 3), Move(0, -2, -2, -2, 2), Move(5, -5, 4, -6, 3), Move(3, -5, 3, -5, 2), Move(5, -6, 5, -6, 4), Move(3, -6, 3, -6, 2), Move(3, -3, 2, -2, 1), Move(3, -4, 3, -6, 4), Move(2, -3, -1, 0, 1), Move(1, -3, 1, -3, 2), Move(2, -4, -1, -1, 1), Move(1, -4, 1, -4, 4), Move(0, -4, 0, -4, 2), Move(0, -5, 0, -5, 3), Move(-1, -5, -1, -5, 3), Move(0, -3, 0, -5, 4), Move(2, -5, -1, -2, 1), Move(1, -5, -1, -5, 2), Move(2, -6, 2, -6, 4), Move(0, -6, 0, -6, 3), Move(-1, -3, -2, -2, 1), Move(-3, -3, -3, -3, 2), Move(-2, -4, -2, -4, 3), Move(1, -7, -3, -3, 1), Move(0, -8, 0, -8, 3)]
# 169
# Move[Move(9, 7, 9, 3, 4), Move(10, 3, 6, 3, 2), Move(10, 6, 6, 6, 2), Move(8, 4, 6, 2, 3), Move(7, 7, 5, 9, 1), Move(8, 5, 6, 7, 1), Move(8, 7, 8, 3, 4), Move(10, 7, 6, 7, 2), Move(7, 4, 6, 3, 3), Move(2, 7, 0, 5, 3), Move(6, 5, 6, 5, 4), Move(6, 4, 6, 1, 4), Move(10, 4, 6, 4, 2), Move(3, 5, 3, 5, 4), Move(3, 4, 3, 1, 4), Move(0, 2, 0, 2, 4), Move(10, 5, 10, 3, 4), Move(7, 2, 6, 1, 3), Move(7, 8, 6, 9, 1), Move(7, 9, 3, 9, 2), Move(7, 5, 7, 5, 4), Move(5, 3, 5, 3, 3), Move(11, 5, 7, 5, 2), Move(7, 1, 7, 1, 4), Move(8, 2, 7, 1, 3), Move(8, 8, 7, 9, 1), Move(4, 3, 2, 3, 2), Move(10, 2, 6, 6, 1), Move(5, 4, 4, 3, 3), Move(4, 5, 2, 7, 1), Move(5, 5, 3, 5, 2), Move(9, 1, 5, 5, 1), Move(5, 6, 3, 4, 3), Move(4, 6, 2, 6, 2), Move(4, 4, 4, 4, 3), Move(2, 4, 2, 4, 2), Move(8, 0, 4, 4, 1), Move(9, 2, 6, 2, 2), Move(10, 1, 6, 5, 1), Move(8, 1, 6, 1, 2), Move(8, -1, 8, -1, 4), Move(4, 2, 4, 2, 4), Move(5, 7, 3, 5, 3), Move(5, 8, 5, 5, 4), Move(4, 8, 4, 8, 2), Move(1, 5, 1, 5, 3), Move(4, 7, 2, 7, 2), Move(2, 5, 2, 5, 3), Move(2, 2, 2, 2, 4), Move(5, 2, 2, 2, 2), Move(5, 1, 5, 1, 4), Move(-1, 5, -1, 5, 1), Move(-2, 5, -2, 5, 2), Move(4, 10, 4, 6, 4), Move(7, -1, 3, 3, 1), Move(6, -2, 6, -2, 3), Move(2, 10, 2, 10, 1), Move(2, 9, 2, 9, 1), Move(2, 8, 2, 6, 4), Move(1, 7, 0, 6, 3), Move(1, 9, 1, 9, 1), Move(7, 0, 4, 3, 1), Move(9, 0, 5, 0, 2), Move(9, -1, 9, -1, 4), Move(10, -1, 6, 3, 1), Move(6, -1, 6, -1, 2), Move(5, -2, 5, -2, 3), Move(6, -3, 6, -3, 4), Move(7, -2, 6, -3, 3), Move(7, -3, 7, -3, 4), Move(5, -1, 3, 1, 1), Move(5, -3, 5, -3, 4), Move(4, 1, 3, 2, 1), Move(2, 1, 2, 1, 2), Move(4, -1, 2, 1, 1), Move(4, -2, 4, -2, 4), Move(3, -3, 3, -3, 3), Move(3, -2, 3, -2, 2), Move(3, -1, 3, -3, 4), Move(2, -1, 2, -1, 2), Move(1, -2, 1, -2, 3), Move(2, -2, 2, -2, 3), Move(2, -3, 2, -3, 3), Move(0, 7, 0, 7, 1), Move(-1, 1, -1, 1, 3), Move(2, 0, 2, -2, 4), Move(1, 1, 1, 1, 1), Move(1, 0, 1, 0, 2), Move(0, -1, 0, -1, 3), Move(0, 0, 0, 0, 3), Move(1, -1, -1, 1, 1), Move(1, 2, 1, -2, 4), Move(1, 4, 1, 2, 4), Move(-1, 6, -1, 6, 1), Move(-2, 6, -2, 6, 2), Move(-1, 4, -2, 5, 1), Move(-2, 4, -2, 4, 2), Move(0, -2, 0, -2, 3), Move(-1, -2, -1, -2, 2), Move(10, 0, 10, -1, 4), Move(0, 1, 0, -2, 4), Move(-1, 0, -1, 0, 3), Move(-2, 1, -2, 1, 1), Move(-1, 2, -2, 1, 3), Move(-2, 2, -2, 2, 2), Move(-1, 3, -1, 2, 4), Move(-3, 1, -3, 1, 3), Move(-2, 3, -2, 3, 2), Move(-2, 7, -2, 3, 4), Move(-1, 7, -2, 7, 2), Move(0, 8, -2, 6, 3), Move(1, 8, 0, 8, 2), Move(1, 10, 1, 6, 4), Move(3, 10, -1, 6, 3), Move(0, 10, 0, 10, 2), Move(0, 9, 0, 6, 4), Move(-1, 9, -1, 9, 2), Move(-4, 1, -4, 1, 2), Move(-3, 2, -4, 1, 3), Move(2, 11, 2, 11, 1), Move(-1, 8, -2, 7, 3), Move(-2, 10, -2, 10, 1), Move(-2, 8, -2, 8, 1), Move(-1, 10, -1, 6, 4), Move(-2, 11, -2, 11, 1), Move(-2, 9, -2, 7, 4), Move(-3, 5, -3, 5, 1), Move(-1, -1, -1, -2, 4), Move(-2, -1, -2, -1, 2), Move(4, -3, 2, -3, 2), Move(-3, 4, -3, 4, 1), Move(5, -4, 1, 0, 1), Move(-2, 0, -2, -1, 4), Move(-3, 0, -3, 0, 2), Move(-3, 3, -3, 0, 4), Move(-4, 2, -4, 2, 3), Move(-5, 3, -5, 3, 1), Move(-5, 2, -5, 2, 1), Move(-6, 2, -6, 2, 2), Move(-4, 4, -6, 2, 3), Move(-4, 3, -5, 2, 3), Move(-4, 5, -4, 1, 4), Move(-5, 5, -5, 5, 1), Move(-6, 3, -6, 3, 2), Move(-6, 5, -6, 5, 2), Move(-5, 4, -6, 5, 1), Move(-5, 6, -5, 2, 4), Move(-6, 4, -6, 4, 2), Move(-3, 6, -6, 3, 3), Move(-6, 6, -6, 2, 4), Move(-4, 6, -6, 6, 2), Move(-3, 7, -4, 6, 3), Move(-3, 8, -3, 4, 4), Move(-4, 7, -6, 5, 3), Move(-4, 8, -4, 8, 2), Move(-5, 9, -5, 9, 1), Move(-4, 9, -4, 5, 4), Move(-5, 10, -5, 10, 1), Move(-3, 9, -5, 9, 2), Move(-5, 7, -6, 6, 3), Move(-6, 7, -6, 7, 2), Move(-7, 8, -7, 8, 1), Move(-5, 8, -5, 6, 4), Move(-3, 10, -6, 7, 3), Move(-4, 10, -5, 10, 2), Move(-6, 9, -6, 9, 1), Move(-4, 11, -4, 11, 1), Move(-3, 12, -7, 8, 3), Move(-3, 11, -3, 8, 4)]
# 170
# Move[Move(9, 7, 9, 3, 4), Move(7, 9, 3, 9, 2), Move(3, 5, 3, 5, 4), Move(3, 4, 3, 1, 4), Move(6, 5, 6, 5, 4), Move(6, 4, 6, 1, 4), Move(7, 7, 5, 9, 1), Move(4, 6, 0, 6, 2), Move(5, 7, 3, 5, 3), Move(8, 7, 5, 7, 2), Move(5, 6, 4, 6, 2), Move(5, 3, 5, 3, 2), Move(7, 5, 5, 3, 3), Move(7, 8, 7, 5, 4), Move(10, 5, 6, 9, 1), Move(8, 5, 6, 5, 2), Move(8, 4, 8, 3, 4), Move(5, 1, 5, 1, 3), Move(7, 2, 6, 1, 3), Move(10, 2, 6, 6, 1), Move(5, 8, 5, 8, 1), Move(5, 5, 5, 5, 4), Move(4, 4, 3, 3, 3), Move(4, 3, 1, 3, 2), Move(5, 4, 4, 3, 3), Move(5, 2, 5, 1, 4), Move(7, 4, 5, 2, 3), Move(10, 4, 6, 4, 2), Move(7, 1, 7, 1, 4), Move(8, 2, 6, 0, 3), Move(9, 2, 6, 2, 2), Move(10, 1, 6, 5, 1), Move(9, 1, 5, 5, 1), Move(8, 1, 6, 1, 2), Move(4, 5, 4, 5, 1), Move(2, 5, 2, 5, 2), Move(1, 2, 1, 2, 3), Move(2, 4, 2, 4, 2), Move(8, 0, 4, 4, 1), Move(8, -1, 8, -1, 4), Move(2, 2, 2, 2, 4), Move(4, 2, 2, 2, 2), Move(4, 1, 4, 1, 4), Move(6, -1, 2, 3, 1), Move(7, -1, 3, 3, 1), Move(4, 7, 2, 5, 3), Move(4, 8, 4, 5, 4), Move(1, 5, 1, 5, 3), Move(2, 10, 2, 10, 1), Move(2, 8, 2, 8, 2), Move(1, 9, 1, 9, 1), Move(2, 1, 2, 1, 2), Move(2, 9, 2, 9, 1), Move(2, 7, 2, 6, 4), Move(1, 7, 1, 7, 2), Move(1, 8, 1, 5, 4), Move(0, 9, 0, 9, 1), Move(0, 8, 0, 8, 1), Move(0, 7, 0, 5, 4), Move(-1, 8, -1, 8, 1), Move(-2, 8, -2, 8, 2), Move(-1, 9, -1, 9, 2), Move(-1, 7, -1, 7, 1), Move(-2, 6, -2, 6, 3), Move(-1, 5, -2, 6, 1), Move(-2, 5, -2, 5, 2), Move(-2, 4, -2, 4, 3), Move(-2, 7, -2, 4, 4), Move(-1, 6, -1, 5, 4), Move(-3, 4, -3, 4, 3), Move(1, 4, -2, 7, 1), Move(1, 1, 1, 1, 4), Move(-1, 4, -2, 4, 2), Move(-3, 6, -3, 6, 1), Move(-4, 6, -4, 6, 2), Move(-3, 7, -3, 7, 2), Move(-5, 5, -5, 5, 3), Move(7, 0, 4, 3, 1), Move(9, 0, 5, 0, 2), Move(9, -1, 9, -1, 4), Move(5, -1, 5, -1, 2), Move(6, -2, 2, 2, 1), Move(5, -3, 5, -3, 3), Move(5, -2, 5, -3, 4), Move(4, -3, 4, -3, 3), Move(6, -3, 6, -3, 4), Move(7, -2, 6, -3, 3), Move(10, 3, 10, 1, 4), Move(5, 10, 1, 6, 3), Move(7, -3, 7, -3, 4), Move(4, -1, 2, 1, 1), Move(4, -2, 4, -3, 4), Move(3, -2, 3, -2, 2), Move(2, -3, 2, -3, 3), Move(3, -3, 2, -3, 2), Move(3, -1, 3, -3, 4), Move(2, -4, 2, -4, 3), Move(2, 0, 1, 1, 1), Move(1, -1, 1, -1, 3), Move(1, 0, 1, 0, 2), Move(0, -1, 0, -1, 3), Move(2, -1, 1, -1, 2), Move(0, 1, 0, 1, 1), Move(0, 2, 0, 1, 4), Move(-1, 1, -1, 1, 3), Move(-2, 1, -2, 1, 2), Move(-1, 2, -2, 1, 3), Move(-2, 2, -2, 2, 2), Move(-1, 3, -1, 1, 4), Move(-3, 1, -3, 1, 3), Move(2, -2, 2, -3, 4), Move(1, -3, 1, -3, 3), Move(1, -2, 1, -3, 4), Move(0, -3, 0, -3, 3), Move(0, 0, -1, 1, 1), Move(0, -2, 0, -3, 4), Move(-1, -2, -1, -2, 2), Move(-1, 0, -2, 1, 1), Move(-3, 5, -3, 5, 1), Move(-3, 3, -3, 3, 4), Move(-4, 4, -5, 5, 1), Move(-2, 3, -3, 3, 2), Move(-4, 5, -4, 5, 1), Move(-5, 4, -5, 4, 3), Move(-6, 5, -6, 5, 2), Move(-6, 4, -6, 4, 2), Move(-2, 0, -2, 0, 4), Move(-3, 0, -3, 0, 2), Move(-1, -1, -2, 0, 1), Move(-1, -3, -1, -3, 4), Move(-2, -3, -2, -3, 2), Move(-2, -2, -2, -2, 3), Move(-3, 2, -3, 2, 3), Move(-3, -1, -3, -1, 4), Move(-2, -1, -3, -1, 2), Move(-3, -2, -3, -2, 3), Move(-4, 1, -4, 1, 1), Move(-2, -4, -2, -4, 4), Move(-3, -5, -3, -5, 3), Move(-4, 3, -6, 5, 1), Move(-4, 2, -4, 2, 4), Move(-5, 3, -6, 4, 1), Move(-6, 2, -6, 2, 3), Move(-5, 2, -6, 2, 2), Move(-5, 1, -5, 1, 4), Move(-6, 0, -6, 0, 3), Move(-6, 1, -6, 1, 2), Move(-7, 0, -7, 0, 3), Move(-6, 3, -6, 1, 4), Move(-4, 0, -6, 2, 1), Move(-5, 0, -7, 0, 2), Move(-4, -1, -6, 1, 1), Move(-4, -2, -4, -2, 4), Move(-5, -2, -5, -2, 2), Move(-5, -3, -5, -3, 3), Move(-6, -3, -6, -3, 3), Move(-5, -1, -5, -3, 4), Move(-3, -3, -6, 0, 1), Move(-3, -4, -3, -5, 4), Move(-4, -3, -6, -3, 2), Move(-4, -5, -4, -5, 3), Move(-6, -1, -7, 0, 1), Move(-7, -1, -7, -1, 2), Move(-6, -2, -6, -3, 4), Move(-4, -4, -7, -1, 1), Move(-4, -6, -4, -6, 4), Move(-7, -3, -7, -3, 3), Move(-7, -2, -7, -2, 3), Move(-7, 3, -7, 3, 2), Move(-7, -4, -7, -4, 4)]
# 170
# Move[Move(9, 7, 9, 3, 4), Move(7, 7, 5, 9, 1), Move(7, 9, 3, 9, 2), Move(5, 3, 5, 3, 2), Move(4, 3, 1, 3, 2), Move(5, 6, 5, 6, 2), Move(4, 6, 1, 6, 2), Move(3, 5, 3, 5, 4), Move(5, 7, 3, 5, 3), Move(8, 7, 5, 7, 2), Move(3, 4, 3, 1, 4), Move(6, 4, 6, 0, 4), Move(7, 5, 5, 3, 3), Move(7, 8, 7, 5, 4), Move(5, 10, 5, 10, 1), Move(2, 7, 1, 6, 3), Move(5, 8, 5, 6, 4), Move(4, 8, 3, 8, 2), Move(1, 5, 1, 5, 3), Move(2, 10, 2, 10, 1), Move(4, 5, 3, 4, 3), Move(8, 5, 4, 9, 1), Move(6, 5, 6, 4, 4), Move(5, 5, 5, 5, 2), Move(2, 5, 1, 5, 2), Move(0, 7, 0, 7, 1), Move(4, 7, 2, 5, 3), Move(1, 7, 1, 7, 2), Move(4, 10, 4, 6, 4), Move(2, 8, 0, 6, 3), Move(1, 9, 1, 9, 1), Move(2, 9, 2, 6, 4), Move(1, 10, 1, 10, 1), Move(1, 8, 1, 6, 4), Move(0, 9, 0, 9, 1), Move(0, 8, 0, 5, 4), Move(-1, 8, -1, 8, 2), Move(-1, 9, -1, 9, 2), Move(4, 4, 1, 7, 1), Move(2, 2, 2, 2, 3), Move(2, 4, 2, 2, 4), Move(-1, 7, -1, 7, 1), Move(4, 2, 4, 2, 4), Move(5, 4, 4, 3, 3), Move(5, 2, 5, 2, 4), Move(1, 4, 1, 4, 2), Move(-1, 6, -1, 6, 1), Move(-1, 5, -1, 5, 4), Move(-2, 6, -2, 6, 1), Move(-3, 5, -3, 5, 3), Move(-2, 5, -3, 5, 2), Move(-3, 4, -3, 4, 3), Move(-3, 6, -3, 6, 2), Move(-2, 7, -3, 6, 3), Move(7, 4, 5, 2, 3), Move(9, 2, 5, 6, 1), Move(8, 4, 5, 4, 2), Move(5, 1, 5, 1, 3), Move(10, 2, 6, 6, 1), Move(8, 2, 8, 2, 4), Move(9, 1, 5, 5, 1), Move(1, 2, 1, 2, 4), Move(0, 2, 0, 2, 2), Move(0, 1, 0, 1, 4), Move(-1, 1, -1, 1, 3), Move(-1, 4, -3, 6, 1), Move(-2, 4, -3, 4, 2), Move(-2, 3, -2, 3, 4), Move(-1, 0, -1, 0, 3), Move(-3, 2, -3, 2, 3), Move(7, 2, 5, 2, 2), Move(7, 1, 7, 1, 4), Move(5, -1, 5, -1, 3), Move(8, 1, 5, 1, 2), Move(9, 0, 5, 4, 1), Move(9, -1, 9, -1, 4), Move(8, 0, 5, 3, 1), Move(7, 0, 5, 0, 2), Move(8, -1, 4, 3, 1), Move(8, -2, 8, -2, 4), Move(5, -2, 5, -2, 4), Move(-3, 3, -3, 2, 4), Move(-4, 2, -4, 2, 3), Move(-1, 3, -3, 3, 2), Move(10, 5, 6, 1, 3), Move(3, 10, 1, 10, 2), Move(7, -1, 3, 3, 1), Move(6, -2, 6, -2, 3), Move(6, -1, 5, -1, 2), Move(4, -3, 4, -3, 3), Move(7, -3, 3, 1, 1), Move(7, -2, 7, -3, 4), Move(4, -2, 4, -2, 2), Move(4, 1, 3, 2, 1), Move(4, -1, 4, -2, 4), Move(-1, 2, -1, 1, 4), Move(1, 0, -3, 4, 1), Move(2, 0, 1, 0, 2), Move(1, -1, 1, -1, 3), Move(-2, 2, -4, 2, 2), Move(-3, 1, -3, 1, 3), Move(-3, 7, -3, 7, 2), Move(1, 1, -2, 4, 1), Move(2, 1, 1, 1, 2), Move(1, -2, 1, -2, 4), Move(-2, 1, -3, 1, 2), Move(0, -1, -3, 2, 1), Move(-3, 0, -3, 0, 3), Move(2, -1, 1, -2, 3), Move(3, -1, 1, -1, 2), Move(2, -2, 2, -2, 4), Move(1, -3, 1, -3, 3), Move(0, 0, -3, 3, 1), Move(-2, 0, -3, 0, 2), Move(-2, -1, -2, -1, 4), Move(6, -3, 2, 1, 1), Move(6, -4, 6, -4, 4), Move(5, -5, 5, -5, 3), Move(5, -3, 2, 0, 1), Move(3, -3, 3, -3, 2), Move(3, -2, 3, -3, 4), Move(5, -4, 1, 0, 1), Move(4, -5, 4, -5, 3), Move(0, -2, 0, -2, 2), Move(2, -3, 2, -3, 3), Move(5, -6, 5, -6, 4), Move(4, -4, 1, -1, 1), Move(4, -6, 4, -6, 4), Move(3, -4, 1, -2, 1), Move(2, -4, 2, -4, 2), Move(3, -5, 0, -2, 1), Move(2, -6, 2, -6, 3), Move(2, -5, 2, -6, 4), Move(1, -5, 1, -5, 2), Move(0, -6, 0, -6, 3), Move(-1, -1, -4, 2, 1), Move(-3, -1, -3, -1, 2), Move(-3, -2, -3, -2, 4), Move(0, -3, 0, -3, 4), Move(-1, -3, -1, -3, 2), Move(-2, -2, -2, -2, 3), Move(0, -4, -2, -2, 1), Move(-1, -2, -1, -3, 4), Move(1, -4, -3, 0, 1), Move(1, -6, 1, -6, 4), Move(3, -6, 1, -6, 2), Move(0, -7, 0, -7, 3), Move(3, -7, 3, -7, 4), Move(0, -5, 0, -7, 4), Move(-4, -2, -4, -2, 2), Move(-5, -3, -5, -3, 3), Move(-2, -3, -2, -3, 3), Move(-1, -4, -3, -2, 1), Move(-2, -4, -2, -4, 2), Move(-3, -5, -3, -5, 3), Move(-2, -5, -2, -5, 4), Move(-3, -6, -3, -6, 3), Move(-1, -5, -3, -5, 2), Move(-3, -3, -4, -2, 1), Move(-3, -4, -3, -6, 4), Move(-4, -3, -5, -3, 2), Move(-5, -4, -5, -4, 3), Move(-1, -6, -4, -3, 1), Move(-2, -7, -2, -7, 3), Move(-2, -6, -3, -6, 2), Move(-3, -7, -3, -7, 3), Move(-1, -7, -1, -7, 4), Move(-4, -7, -4, -7, 2), Move(-4, -4, -5, -3, 1), Move(-6, -4, -6, -4, 2)]
# 170
# Move[Move(4, 6, 0, 6, 2), Move(5, 6, 4, 6, 2), Move(4, 3, 0, 3, 2), Move(5, 3, 4, 3, 2), Move(2, 7, 0, 5, 3), Move(0, 7, 0, 3, 4), Move(2, 9, 2, 9, 2), Move(3, 4, 3, 0, 4), Move(2, 5, 0, 7, 1), Move(2, 8, 2, 5, 4), Move(6, 5, 6, 5, 4), Move(4, 7, 2, 9, 1), Move(1, 7, 0, 7, 2), Move(4, 10, 0, 6, 3), Move(7, 7, 4, 10, 1), Move(4, 8, 4, 6, 4), Move(5, 8, 2, 8, 2), Move(8, 5, 4, 9, 1), Move(7, 10, 3, 6, 3), Move(1, 5, 0, 4, 3), Move(6, 4, 6, 1, 4), Move(5, 5, 2, 8, 1), Move(1, 4, 1, 3, 4), Move(-1, 2, -1, 2, 3), Move(4, 1, 0, 5, 1), Move(3, 5, 3, 5, 4), Move(-1, 5, -1, 5, 2), Move(4, 4, 2, 6, 1), Move(2, 4, 0, 4, 2), Move(0, 2, 0, 2, 3), Move(4, 2, 0, 6, 1), Move(4, 5, 4, 2, 4), Move(7, 5, 4, 5, 2), Move(9, 7, 5, 3, 3), Move(5, 7, 3, 9, 1), Move(8, 7, 4, 7, 2), Move(5, 10, 5, 6, 4), Move(7, 8, 5, 10, 1), Move(8, 9, 4, 5, 3), Move(7, 9, 7, 6, 4), Move(8, 10, 4, 6, 3), Move(8, 8, 8, 6, 4), Move(9, 9, 5, 5, 3), Move(9, 8, 9, 5, 4), Move(10, 8, 6, 8, 2), Move(10, 9, 6, 9, 2), Move(5, 4, 5, 4, 3), Move(5, 2, 5, 2, 4), Move(7, 2, 3, 6, 1), Move(7, 4, 7, 2, 4), Move(10, 7, 6, 3, 3), Move(8, 4, 4, 4, 2), Move(10, 6, 6, 2, 3), Move(10, 5, 10, 5, 4), Move(11, 6, 7, 2, 3), Move(12, 5, 8, 9, 1), Move(11, 5, 8, 5, 2), Move(12, 4, 8, 8, 1), Move(12, 6, 8, 6, 2), Move(11, 7, 8, 10, 1), Move(2, -1, 2, -1, 3), Move(12, 7, 8, 7, 2), Move(2, 2, -1, 5, 1), Move(2, 1, 2, 1, 4), Move(1, 2, 1, 2, 2), Move(0, 1, 0, 1, 3), Move(1, 1, 0, 1, 2), Move(0, 0, 0, 0, 3), Move(0, -1, 0, -1, 4), Move(8, 2, 8, 2, 4), Move(9, 2, 5, 2, 2), Move(9, 1, 9, 1, 4), Move(10, 1, 6, 5, 1), Move(10, 4, 8, 2, 3), Move(11, 4, 8, 4, 2), Move(11, 3, 11, 3, 4), Move(12, 2, 8, 6, 1), Move(12, 3, 12, 2, 4), Move(13, 2, 9, 6, 1), Move(10, 3, 8, 3, 2), Move(8, 1, 8, 1, 3), Move(1, 0, 0, -1, 3), Move(2, 0, 0, 0, 2), Move(3, -2, -1, 2, 1), Move(4, -1, 3, -2, 3), Move(5, -2, 1, 2, 1), Move(1, -1, 1, -1, 3), Move(4, -2, 4, -2, 4), Move(3, -1, 0, -1, 2), Move(5, -3, 1, 1, 1), Move(10, 2, 10, 1, 4), Move(11, 2, 9, 2, 2), Move(12, 1, 8, 5, 1), Move(8, 0, 8, 0, 3), Move(7, 0, 4, 0, 2), Move(8, -1, 4, 3, 1), Move(11, 1, 8, 1, 2), Move(8, -2, 8, -2, 4), Move(12, 0, 8, 4, 1), Move(1, -2, 1, -2, 4), Move(6, 10, 4, 10, 2), Move(10, 0, 6, 4, 1), Move(2, -2, 1, -2, 2), Move(2, -3, 2, -3, 4), Move(9, 0, 8, -1, 3), Move(11, 0, 8, 0, 2), Move(11, -1, 11, -1, 4), Move(5, 1, 2, -2, 3), Move(5, -1, 5, -2, 4), Move(7, 1, 4, 1, 2), Move(7, -1, 4, 2, 1), Move(7, -2, 7, -2, 4), Move(6, -1, 4, -1, 2), Move(8, -3, 4, 1, 1), Move(9, -1, 8, -2, 3), Move(3, -3, 3, -3, 3), Move(3, -4, 3, -4, 4), Move(4, -5, 0, -1, 1), Move(4, -3, 3, -4, 3), Move(6, -3, 2, -3, 2), Move(5, -4, 4, -5, 3), Move(6, -2, 6, -3, 4), Move(4, -4, 4, -4, 3), Move(5, -5, 1, -1, 1), Move(4, -6, 4, -6, 4), Move(5, -6, 5, -6, 4), Move(9, -2, 5, -2, 2), Move(7, -3, 3, 1, 1), Move(6, -4, 4, -6, 3), Move(7, -4, 3, -4, 2), Move(6, -5, 5, -6, 3), Move(7, -6, 3, -2, 1), Move(7, -5, 7, -6, 4), Move(8, -5, 4, -5, 2), Move(9, -6, 5, -2, 1), Move(10, -1, 9, -2, 3), Move(11, -2, 7, 2, 1), Move(9, -3, 9, -3, 4), Move(10, -3, 6, -3, 2), Move(12, -1, 8, -1, 2), Move(12, -2, 12, -2, 4), Move(10, -2, 10, -3, 4), Move(8, -4, 8, -4, 3), Move(8, -6, 8, -6, 4), Move(9, -7, 5, -3, 1), Move(6, -6, 4, -6, 2), Move(6, -7, 6, -7, 4), Move(9, -4, 6, -7, 3), Move(9, -5, 9, -7, 4), Move(13, -2, 9, -2, 2), Move(14, -3, 10, 1, 1), Move(11, -3, 7, 1, 1), Move(10, -4, 8, -6, 3), Move(11, -4, 7, -4, 2), Move(12, -5, 8, -1, 1), Move(11, -5, 11, -5, 4), Move(10, -5, 8, -5, 2), Move(12, -3, 9, -6, 3), Move(13, -3, 10, -3, 2), Move(12, -6, 8, -2, 1), Move(12, -4, 12, -6, 4), Move(10, -6, 9, -7, 3), Move(11, -6, 8, -6, 2), Move(12, -7, 8, -3, 1), Move(14, -4, 10, 0, 1), Move(11, -7, 7, -3, 1), Move(10, -7, 10, -7, 4), Move(8, -7, 8, -7, 2), Move(13, -4, 10, -7, 3), Move(15, -4, 11, -4, 2)]
# 170
# Move[Move(0, 7, 0, 3, 4), Move(2, 9, 2, 9, 2), Move(4, 6, 0, 6, 2), Move(5, 6, 4, 6, 2), Move(4, 3, 0, 3, 2), Move(5, 3, 4, 3, 2), Move(2, 7, 0, 5, 3), Move(3, 4, 3, 0, 4), Move(2, 5, 0, 7, 1), Move(2, 8, 2, 5, 4), Move(3, 5, 3, 4, 4), Move(6, 5, 6, 5, 4), Move(4, 7, 2, 9, 1), Move(1, 7, 0, 7, 2), Move(4, 10, 0, 6, 3), Move(7, 7, 4, 10, 1), Move(4, 8, 4, 6, 4), Move(5, 8, 2, 8, 2), Move(8, 5, 4, 9, 1), Move(7, 10, 3, 6, 3), Move(1, 5, 0, 4, 3), Move(4, 5, 0, 5, 2), Move(4, 4, 1, 7, 1), Move(4, 2, 4, 2, 4), Move(2, 4, 0, 6, 1), Move(1, 4, 0, 4, 2), Move(4, 1, 0, 5, 1), Move(1, 2, 1, 2, 4), Move(0, 1, 0, 1, 3), Move(-1, 2, -1, 2, 3), Move(0, 2, 0, 2, 3), Move(2, 2, 0, 2, 2), Move(2, 1, 2, 1, 4), Move(1, 1, 0, 1, 2), Move(4, -1, 0, 3, 1), Move(4, -2, 4, -2, 4), Move(0, 0, 0, 0, 3), Move(0, -1, 0, -1, 4), Move(6, 4, 6, 1, 4), Move(5, 5, 2, 8, 1), Move(7, 5, 4, 5, 2), Move(9, 7, 5, 3, 3), Move(5, 7, 3, 9, 1), Move(5, 10, 5, 6, 4), Move(8, 7, 4, 7, 2), Move(7, 8, 5, 10, 1), Move(8, 9, 4, 5, 3), Move(7, 9, 7, 6, 4), Move(8, 10, 4, 6, 3), Move(8, 8, 8, 6, 4), Move(9, 9, 5, 5, 3), Move(9, 8, 9, 5, 4), Move(10, 8, 6, 8, 2), Move(10, 9, 6, 9, 2), Move(5, 4, 5, 4, 3), Move(7, 2, 3, 6, 1), Move(5, 2, 5, 2, 4), Move(7, 4, 7, 2, 4), Move(10, 7, 6, 3, 3), Move(8, 4, 4, 4, 2), Move(10, 6, 6, 2, 3), Move(10, 5, 10, 5, 4), Move(11, 6, 7, 2, 3), Move(12, 5, 8, 9, 1), Move(11, 5, 8, 5, 2), Move(12, 4, 8, 8, 1), Move(12, 6, 8, 6, 2), Move(11, 7, 8, 10, 1), Move(8, 2, 8, 2, 4), Move(10, 4, 8, 2, 3), Move(11, 4, 8, 4, 2), Move(11, 3, 11, 3, 4), Move(12, 2, 8, 6, 1), Move(9, 2, 5, 2, 2), Move(9, 1, 9, 1, 4), Move(10, 0, 6, 4, 1), Move(10, 1, 6, 5, 1), Move(12, 3, 12, 2, 4), Move(10, 3, 8, 3, 2), Move(13, 2, 9, 6, 1), Move(8, 1, 8, 1, 3), Move(10, 2, 10, 1, 4), Move(11, 2, 9, 2, 2), Move(12, 1, 8, 5, 1), Move(8, 0, 8, 0, 3), Move(7, 0, 4, 0, 2), Move(8, -1, 4, 3, 1), Move(9, 0, 8, -1, 3), Move(11, 1, 8, 1, 2), Move(12, 0, 8, 4, 1), Move(11, 0, 8, 0, 2), Move(11, -1, 11, -1, 4), Move(8, -2, 8, -2, 4), Move(9, -1, 8, -2, 3), Move(2, -1, 2, -1, 3), Move(-1, 5, -1, 5, 1), Move(12, 7, 8, 7, 2), Move(1, 0, 0, -1, 3), Move(2, 0, 0, 0, 2), Move(1, -1, 1, -1, 3), Move(1, -2, 1, -2, 4), Move(3, -2, -1, 2, 1), Move(2, -3, 2, -3, 3), Move(3, -1, 0, -1, 2), Move(5, -3, 1, 1, 1), Move(2, -2, 2, -3, 4), Move(5, -2, 1, -2, 2), Move(5, 1, 2, -2, 3), Move(5, -1, 5, -2, 4), Move(7, 1, 4, 1, 2), Move(3, -3, 3, -3, 3), Move(7, -1, 4, 2, 1), Move(7, -2, 7, -2, 4), Move(6, -1, 4, -1, 2), Move(8, -3, 4, 1, 1), Move(4, -3, 4, -3, 3), Move(6, -3, 2, -3, 2), Move(3, -4, 3, -4, 4), Move(4, -5, 0, -1, 1), Move(5, -4, 4, -5, 3), Move(6, 10, 4, 10, 2), Move(6, -2, 6, -3, 4), Move(7, -3, 3, 1, 1), Move(9, -2, 5, -2, 2), Move(10, -1, 9, -2, 3), Move(9, -3, 9, -3, 4), Move(10, -3, 6, -3, 2), Move(10, -2, 10, -3, 4), Move(8, -4, 8, -4, 3), Move(12, -1, 8, -1, 2), Move(12, -2, 12, -2, 4), Move(11, -3, 7, 1, 1), Move(11, -2, 7, 2, 1), Move(13, -2, 9, -2, 2), Move(14, -3, 10, 1, 1), Move(4, -4, 4, -4, 3), Move(4, -6, 4, -6, 4), Move(5, -5, 1, -1, 1), Move(5, -6, 5, -6, 4), Move(6, -4, 4, -6, 3), Move(7, -4, 3, -4, 2), Move(6, -5, 5, -6, 3), Move(7, -6, 3, -2, 1), Move(7, -5, 7, -6, 4), Move(8, -5, 4, -5, 2), Move(8, -6, 8, -6, 4), Move(6, -6, 4, -6, 2), Move(9, -7, 5, -3, 1), Move(9, -4, 7, -6, 3), Move(9, -6, 5, -2, 1), Move(9, -5, 9, -7, 4), Move(10, -4, 8, -6, 3), Move(11, -4, 7, -4, 2), Move(12, -5, 8, -1, 1), Move(11, -5, 11, -5, 4), Move(10, -5, 8, -5, 2), Move(12, -3, 9, -6, 3), Move(13, -3, 10, -3, 2), Move(14, -4, 10, 0, 1), Move(12, -6, 8, -2, 1), Move(12, -4, 12, -6, 4), Move(10, -6, 9, -7, 3), Move(11, -7, 7, -3, 1), Move(10, -7, 10, -7, 4), Move(11, -6, 8, -6, 2), Move(12, -7, 8, -3, 1), Move(13, -7, 9, -7, 2), Move(13, -4, 10, -7, 3), Move(15, -4, 11, -4, 2), Move(6, -7, 6, -7, 4)]
# 176
# Move[Move(7, 2, 5, 0, 3), Move(5, 3, 5, 3, 2), Move(5, 6, 5, 6, 2), Move(4, 6, 1, 6, 2), Move(4, 3, 1, 3, 2), Move(6, 4, 6, 0, 4), Move(5, 5, 3, 7, 1), Move(6, 5, 6, 4, 4), Move(3, -1, 3, -1, 4), Move(5, 1, 3, -1, 3), Move(9, 7, 9, 3, 4), Move(7, 5, 5, 3, 3), Move(8, 5, 5, 5, 2), Move(5, 8, 5, 8, 1), Move(7, 4, 7, 2, 4), Move(5, 2, 5, 2, 3), Move(5, 4, 5, 0, 4), Move(5, 7, 5, 4, 4), Move(8, 4, 5, 7, 1), Move(10, 4, 6, 4, 2), Move(8, 2, 8, 2, 4), Move(4, 7, 4, 7, 1), Move(2, 0, 2, 0, 2), Move(4, 2, 4, 2, 2), Move(7, 1, 6, 0, 3), Move(4, 1, 3, 1, 2), Move(4, 4, 4, 0, 4), Move(7, 10, 3, 6, 3), Move(1, 4, 1, 4, 1), Move(0, 7, 0, 3, 4), Move(1, -1, 1, -1, 3), Move(7, 7, 6, 8, 1), Move(8, 8, 4, 4, 3), Move(8, 7, 5, 7, 2), Move(9, 8, 5, 4, 3), Move(7, 8, 5, 8, 2), Move(3, 5, 3, 5, 1), Move(7, 9, 3, 5, 3), Move(8, 9, 4, 9, 2), Move(8, 10, 8, 6, 4), Move(9, 10, 5, 6, 3), Move(7, 11, 7, 7, 4), Move(2, 2, 0, 4, 1), Move(3, 4, 3, 3, 4), Move(2, 4, 2, 4, 2), Move(2, 5, 2, 5, 1), Move(1, 5, 1, 5, 1), Move(4, 5, 1, 5, 2), Move(2, 7, 2, 7, 1), Move(2, 8, 2, 4, 4), Move(1, 7, 1, 7, 2), Move(4, 8, 4, 4, 4), Move(-1, 3, -1, 3, 3), Move(-1, 2, -1, 2, 3), Move(1, 2, 1, 2, 3), Move(1, 8, 1, 4, 4), Move(6, 10, 3, 7, 3), Move(5, 10, 5, 10, 2), Move(6, 11, 2, 7, 3), Move(6, 12, 6, 8, 4), Move(5, 12, 5, 12, 1), Move(5, 11, 5, 8, 4), Move(4, 10, 2, 8, 3), Move(4, 12, 4, 12, 1), Move(4, 11, 4, 8, 4), Move(3, 12, 3, 12, 1), Move(2, 12, 2, 12, 2), Move(3, 11, 2, 12, 1), Move(2, 11, 2, 11, 2), Move(2, 1, 2, 0, 4), Move(0, 2, 0, 2, 2), Move(1, 1, -1, 3, 1), Move(-1, 4, -1, 4, 1), Move(-2, 3, -2, 3, 3), Move(-2, 4, -2, 4, 2), Move(-1, 5, -2, 4, 3), Move(1, 0, 1, 0, 4), Move(0, -1, 0, -1, 3), Move(-3, 3, -3, 3, 2), Move(3, 10, 3, 7, 4), Move(1, 12, 1, 12, 1), Move(2, 9, 1, 8, 3), Move(2, 10, 2, 8, 4), Move(1, 11, 1, 11, 1), Move(1, 10, 1, 10, 2), Move(1, 9, 1, 8, 4), Move(0, 8, 0, 8, 3), Move(-1, 8, -1, 8, 2), Move(0, 9, 0, 9, 2), Move(-2, 7, -2, 7, 3), Move(0, 11, 0, 11, 1), Move(0, 10, 0, 7, 4), Move(-1, 11, -1, 11, 1), Move(-2, 11, -2, 11, 2), Move(-1, 10, -2, 11, 1), Move(-2, 9, -2, 9, 1), Move(-3, 8, -3, 8, 3), Move(-1, 6, -3, 8, 1), Move(-1, 7, -1, 3, 4), Move(-3, 7, -3, 7, 2), Move(-1, 9, -1, 7, 4), Move(-2, 10, -2, 10, 1), Move(-2, 8, -2, 7, 4), Move(-4, 6, -4, 6, 3), Move(-3, 9, -3, 9, 1), Move(-3, 10, -3, 10, 2), Move(-3, 6, -3, 6, 4), Move(-2, 6, -3, 6, 2), Move(-4, 8, -4, 8, 1), Move(-2, 5, -2, 3, 4), Move(-3, 5, -3, 5, 2), Move(-5, 7, -5, 7, 1), Move(-6, 6, -6, 6, 3), Move(-4, 9, -4, 9, 2), Move(-3, 4, -3, 4, 3), Move(-3, 2, -3, 2, 4), Move(-4, 4, -4, 4, 3), Move(-5, 8, -5, 8, 2), Move(-6, 7, -6, 7, 3), Move(-4, 7, -5, 8, 1), Move(-4, 5, -4, 5, 4), Move(-5, 6, -6, 7, 1), Move(-7, 7, -7, 7, 2), Move(-7, 6, -7, 6, 2), Move(-5, 5, -7, 7, 1), Move(-5, 4, -5, 4, 4), Move(-6, 3, -6, 3, 3), Move(-6, 4, -6, 4, 2), Move(-6, 5, -6, 3, 4), Move(-7, 5, -7, 5, 2), Move(-7, 4, -7, 4, 3), Move(-7, 3, -7, 3, 4), Move(-4, 3, -7, 6, 1), Move(-5, 3, -7, 3, 2), Move(-8, 2, -8, 2, 3), Move(-1, 1, -1, 1, 3), Move(0, 1, -1, 1, 2), Move(2, -1, -2, 3, 1), Move(1, -2, 1, -2, 3), Move(0, 0, 0, -1, 4), Move(-2, 2, -3, 3, 1), Move(-4, 2, -4, 2, 2), Move(-3, 1, -7, 5, 1), Move(-4, 1, -4, 1, 4), Move(-1, -1, -1, -1, 3), Move(-1, 0, -1, -1, 4), Move(-2, 1, -3, 2, 1), Move(-5, 1, -5, 1, 2), Move(-6, 0, -6, 0, 3), Move(-2, 0, -2, 0, 2), Move(-2, -1, -2, -1, 4), Move(-3, -1, -3, -1, 2), Move(-3, -2, -3, -2, 3), Move(-3, 0, -3, -2, 4), Move(-5, 2, -6, 3, 1), Move(-5, 0, -5, 0, 4), Move(-6, -1, -6, -1, 3), Move(-4, 0, -6, 0, 2), Move(-6, 2, -7, 3, 1), Move(-6, 1, -6, -1, 4), Move(-5, -1, -5, -1, 3), Move(-7, 0, -7, 0, 3), Move(-7, 2, -8, 2, 2), Move(-4, -1, -7, 2, 1), Move(-7, -1, -7, -1, 2), Move(-5, -2, -5, -2, 3), Move(-7, 1, -7, -1, 4), Move(-4, -2, -8, 2, 1), Move(-8, 0, -8, 0, 3), Move(-5, -3, -5, -3, 3), Move(-5, -4, -5, -4, 4), Move(-4, -3, -4, -3, 4), Move(-8, 1, -8, 1, 1), Move(-9, 1, -9, 1, 2), Move(-6, -2, -9, 1, 1), Move(-2, -2, -6, -2, 2)]
# 176
# Move[Move(6, 5, 6, 5, 4), Move(9, 2, 9, 2, 4), Move(6, 4, 6, 1, 4), Move(7, 7, 5, 9, 1), Move(5, 6, 5, 6, 2), Move(7, 4, 5, 6, 1), Move(7, 5, 7, 3, 4), Move(5, 3, 5, 3, 2), Move(4, 3, 1, 3, 2), Move(5, 4, 3, 2, 3), Move(8, 4, 5, 4, 2), Move(5, 1, 5, 1, 3), Move(5, 7, 5, 7, 1), Move(2, 9, 2, 9, 2), Move(3, 10, 3, 6, 4), Move(5, 8, 3, 10, 1), Move(5, 5, 5, 5, 4), Move(5, 2, 5, 1, 4), Move(8, 5, 5, 2, 3), Move(10, 5, 6, 5, 2), Move(8, 7, 8, 3, 4), Move(4, 2, 4, 2, 3), Move(0, 2, 0, 2, 4), Move(7, -1, 3, 3, 1), Move(4, 7, 4, 7, 2), Move(7, 8, 6, 9, 1), Move(4, 8, 3, 8, 2), Move(1, 5, 1, 5, 3), Move(4, 6, 1, 6, 2), Move(4, 5, 4, 5, 4), Move(7, 2, 6, 1, 3), Move(8, 2, 5, 2, 2), Move(9, 1, 5, 5, 1), Move(8, 1, 4, 5, 1), Move(1, 10, 1, 10, 1), Move(7, 1, 5, 1, 2), Move(3, 4, 2, 3, 3), Move(7, 0, 3, 4, 1), Move(8, 0, 4, 0, 2), Move(8, -1, 8, -1, 4), Move(9, -1, 5, 3, 1), Move(7, -2, 7, -2, 4), Move(3, 5, 3, 2, 4), Move(2, 5, 2, 5, 2), Move(1, 4, 1, 4, 3), Move(2, 4, 2, 4, 3), Move(4, 4, 1, 4, 2), Move(4, 1, 4, 1, 4), Move(2, 2, 2, 2, 3), Move(2, 1, 2, 1, 4), Move(1, 2, 1, 2, 2), Move(-1, 6, -1, 6, 1), Move(1, 1, 1, 1, 4), Move(-1, 7, -1, 7, 1), Move(6, -1, 3, 2, 1), Move(5, -1, 5, -1, 2), Move(6, -2, 2, 2, 1), Move(6, -3, 6, -3, 4), Move(5, -3, 5, -3, 3), Move(5, -2, 5, -3, 4), Move(4, -1, 2, 1, 1), Move(4, -3, 4, -3, 3), Move(4, -2, 4, -3, 4), Move(3, -3, 3, -3, 3), Move(2, -3, 2, -3, 2), Move(3, -2, 2, -3, 3), Move(2, -2, 2, -2, 2), Move(3, -1, 3, -3, 4), Move(1, -3, 1, -3, 3), Move(2, 0, 1, 1, 1), Move(2, -1, 2, -3, 4), Move(1, -2, 1, -2, 3), Move(1, -1, 1, -1, 2), Move(0, -2, 0, -2, 3), Move(1, 0, 1, -3, 4), Move(0, 1, 0, 1, 1), Move(-1, 1, -1, 1, 2), Move(0, 0, 0, 0, 2), Move(-2, 2, -2, 2, 1), Move(0, -1, 0, -2, 4), Move(-1, -2, -1, -2, 3), Move(-2, 0, -2, 0, 3), Move(-2, -2, -2, -2, 2), Move(-1, -1, -2, -2, 3), Move(-3, 1, -3, 1, 1), Move(-1, 3, -3, 1, 3), Move(1, 7, 1, 7, 1), Move(2, 7, 0, 5, 3), Move(2, 8, 2, 5, 4), Move(0, 7, 0, 7, 2), Move(1, 8, -1, 6, 3), Move(-1, 5, -1, 5, 3), Move(-2, 6, -2, 6, 1), Move(-3, 6, -3, 6, 2), Move(-2, 5, -2, 5, 2), Move(-1, 4, -2, 5, 1), Move(-1, 2, -1, 2, 4), Move(-3, 2, -3, 2, 2), Move(-1, 0, -1, -2, 4), Move(-2, -1, -2, -1, 3), Move(-2, 1, -2, -2, 4), Move(-4, 3, -4, 3, 1), Move(-3, 0, -3, 0, 3), Move(-4, 0, -4, 0, 2), Move(-3, -1, -3, -1, 2), Move(-3, 3, -3, -1, 4), Move(-2, 3, -3, 3, 2), Move(-2, 4, -2, 2, 4), Move(-3, 4, -3, 4, 2), Move(-5, 2, -5, 2, 3), Move(-4, 1, -4, 1, 3), Move(-6, 3, -6, 3, 1), Move(-3, 5, -3, 5, 1), Move(-3, 7, -3, 3, 4), Move(1, 9, 1, 6, 4), Move(0, 10, 0, 10, 1), Move(-5, 1, -5, 1, 2), Move(-6, 2, -6, 2, 1), Move(-4, 5, -4, 5, 1), Move(-4, 2, -5, 1, 3), Move(-4, 4, -4, 0, 4), Move(-7, 2, -7, 2, 2), Move(-5, 3, -6, 2, 3), Move(-5, 4, -7, 2, 3), Move(-5, 5, -5, 1, 4), Move(-6, 6, -6, 6, 1), Move(-6, 5, -6, 5, 2), Move(-7, 3, -7, 3, 2), Move(-6, 4, -6, 2, 4), Move(-7, 4, -7, 4, 2), Move(-7, 5, -7, 5, 1), Move(-7, 6, -7, 2, 4), Move(-4, 6, -7, 3, 3), Move(-5, 6, -7, 6, 2), Move(-8, 7, -8, 7, 1), Move(-1, 8, -1, 8, 1), Move(0, 8, -1, 8, 2), Move(2, 10, -2, 6, 3), Move(1, 11, 1, 11, 1), Move(0, 9, 0, 6, 4), Move(-2, 7, -3, 6, 3), Move(-4, 7, -4, 7, 2), Move(-4, 8, -4, 4, 4), Move(-1, 10, -1, 10, 1), Move(-1, 9, -1, 6, 4), Move(-2, 8, -3, 7, 3), Move(-2, 9, -2, 9, 2), Move(-2, 10, -2, 6, 4), Move(-3, 10, -3, 10, 2), Move(-3, 11, -3, 11, 1), Move(-3, 8, -5, 6, 3), Move(-3, 9, -3, 7, 4), Move(-5, 8, -5, 8, 2), Move(-5, 7, -6, 6, 3), Move(-6, 9, -6, 9, 1), Move(-5, 9, -5, 5, 4), Move(-4, 9, -6, 9, 2), Move(-6, 7, -7, 6, 3), Move(-6, 10, -6, 10, 1), Move(-5, 10, -5, 10, 1), Move(-6, 8, -6, 6, 4), Move(-7, 7, -8, 7, 2), Move(-4, 10, -7, 7, 3), Move(-7, 10, -7, 10, 2), Move(-5, 11, -5, 11, 1), Move(-7, 9, -7, 9, 1), Move(-7, 8, -7, 6, 4), Move(-4, 11, -8, 7, 3), Move(-4, 12, -4, 8, 4), Move(-8, 8, -8, 8, 3), Move(-8, 9, -8, 9, 1), Move(-9, 8, -9, 8, 2), Move(-5, 12, -5, 12, 1), Move(-6, 11, -9, 8, 3), Move(-2, 11, -6, 11, 2), Move(-5, 13, -5, 9, 4)]
# 177
# Move[Move(7, 7, 5, 9, 1), Move(7, 0, 3, 0, 2), Move(5, 3, 5, 3, 2), Move(4, 3, 1, 3, 2), Move(9, 2, 9, 2, 4), Move(7, 2, 5, 0, 3), Move(5, 6, 5, 6, 2), Move(4, 6, 1, 6, 2), Move(3, -1, 3, -1, 4), Move(5, 1, 3, -1, 3), Move(2, 9, 2, 9, 2), Move(6, -1, 6, -1, 4), Move(4, 1, 2, 3, 1), Move(7, 1, 3, 1, 2), Move(7, 4, 7, 0, 4), Move(6, 5, 5, 6, 1), Move(6, 4, 6, 3, 4), Move(5, 5, 3, 7, 1), Move(4, 4, 3, 3, 3), Move(3, 5, 2, 6, 1), Move(3, 4, 3, 3, 4), Move(5, 2, 3, 4, 1), Move(8, 2, 5, 2, 2), Move(5, 4, 5, 2, 4), Move(5, -1, 5, -1, 3), Move(5, -2, 5, -2, 4), Move(2, -1, 2, -1, 3), Move(4, -1, 2, -1, 2), Move(4, 2, 4, -1, 4), Move(2, 4, 2, 4, 1), Move(1, 4, 1, 4, 2), Move(8, 1, 5, -2, 3), Move(8, 4, 5, 4, 2), Move(8, 5, 8, 1, 4), Move(5, 8, 5, 8, 1), Move(10, 7, 6, 3, 3), Move(2, 2, 1, 3, 1), Move(1, 2, 1, 2, 2), Move(2, 1, 1, 2, 1), Move(1, 0, 1, 0, 3), Move(2, 0, 2, -1, 4), Move(1, -1, 1, -1, 3), Move(1, 1, 1, -1, 4), Move(4, 5, 3, 6, 1), Move(2, 5, 2, 5, 2), Move(-1, 2, -1, 2, 3), Move(2, 7, 2, 3, 4), Move(0, 1, 0, 1, 3), Move(-1, 1, -1, 1, 2), Move(-2, 3, -2, 3, 1), Move(0, 2, -1, 1, 3), Move(0, 0, 0, 0, 4), Move(-1, 0, -1, 0, 2), Move(-1, -1, -1, -1, 3), Move(-1, 3, -1, -1, 4), Move(-2, 4, -2, 4, 1), Move(-3, 3, -3, 3, 2), Move(-2, 2, -3, 3, 1), Move(1, 5, -2, 2, 3), Move(1, 7, 1, 3, 4), Move(-1, 5, -3, 3, 3), Move(-2, 5, -2, 5, 2), Move(-2, 6, -2, 2, 4), Move(-3, 7, -3, 7, 1), Move(4, 7, 4, 3, 4), Move(1, 10, 1, 10, 1), Move(5, 7, 1, 7, 2), Move(7, 9, 3, 5, 3), Move(5, 10, 5, 6, 4), Move(6, 11, 2, 7, 3), Move(6, 10, 6, 7, 4), Move(4, 8, 2, 6, 3), Move(2, 8, 2, 8, 2), Move(7, 5, 4, 8, 1), Move(10, 5, 6, 5, 2), Move(7, 8, 7, 4, 4), Move(8, 7, 6, 9, 1), Move(-1, 4, -2, 3, 3), Move(-3, 4, -3, 4, 2), Move(-3, 6, -3, 6, 1), Move(-1, 6, -3, 6, 2), Move(-2, 7, -2, 7, 1), Move(-1, 7, -1, 3, 4), Move(-2, 8, -2, 8, 1), Move(0, 7, -3, 7, 2), Move(0, 8, 0, 4, 4), Move(1, 8, -3, 4, 3), Move(-1, 8, -2, 8, 2), Move(-2, 9, -2, 9, 1), Move(-2, 10, -2, 6, 4), Move(-1, 9, -2, 10, 1), Move(-3, 5, -3, 3, 4), Move(1, 9, -3, 5, 3), Move(0, 9, -2, 9, 2), Move(-1, 10, -1, 10, 1), Move(-1, 11, -1, 7, 4), Move(0, 10, -1, 11, 1), Move(1, 11, -3, 7, 3), Move(2, 10, -2, 10, 2), Move(2, 11, 2, 7, 4), Move(3, 12, -1, 8, 3), Move(0, 12, 0, 12, 1), Move(0, 11, 0, 8, 4), Move(3, 11, -1, 11, 2), Move(3, 10, 3, 7, 4), Move(1, 12, 1, 12, 1), Move(1, 13, 1, 9, 4), Move(2, 14, -2, 10, 3), Move(4, 10, 2, 10, 2), Move(2, 12, 1, 13, 1), Move(4, 11, 4, 7, 4), Move(5, 12, 1, 8, 3), Move(2, 13, 2, 13, 1), Move(4, 12, 0, 12, 2), Move(5, 13, 1, 9, 3), Move(2, 15, 2, 11, 4), Move(5, 11, 1, 7, 3), Move(3, 13, 2, 14, 1), Move(4, 13, 1, 13, 2), Move(3, 14, 2, 15, 1), Move(4, 15, 0, 11, 3), Move(7, 11, 3, 11, 2), Move(4, 14, 4, 11, 4), Move(5, 15, 1, 11, 3), Move(3, 15, 3, 11, 4), Move(6, 15, 2, 15, 2), Move(6, 12, 3, 15, 1), Move(9, 7, 6, 7, 2), Move(10, 8, 6, 4, 3), Move(5, 14, 5, 11, 4), Move(6, 14, 2, 14, 2), Move(6, 13, 6, 11, 4), Move(7, 16, 3, 12, 3), Move(-3, 2, -3, 2, 2), Move(8, 9, 4, 5, 3), Move(8, 8, 8, 5, 4), Move(10, 6, 6, 10, 1), Move(11, 7, 7, 3, 3), Move(9, 8, 6, 8, 2), Move(7, 10, 6, 11, 1), Move(7, 12, 7, 8, 4), Move(8, 12, 4, 12, 2), Move(8, 11, 4, 15, 1), Move(9, 12, 5, 8, 3), Move(10, 9, 6, 5, 3), Move(9, 9, 6, 9, 2), Move(9, 10, 9, 6, 4), Move(8, 10, 7, 11, 1), Move(8, 13, 8, 9, 4), Move(10, 10, 6, 10, 2), Move(11, 11, 7, 7, 3), Move(10, 11, 10, 7, 4), Move(7, 14, 6, 15, 1), Move(9, 11, 7, 11, 2), Move(7, 13, 5, 15, 1), Move(7, 15, 7, 12, 4), Move(9, 13, 5, 13, 2), Move(9, 14, 9, 10, 4), Move(10, 14, 6, 10, 3), Move(10, 15, 6, 11, 3), Move(8, 14, 6, 14, 2), Move(10, 12, 7, 15, 1), Move(11, 13, 7, 9, 3), Move(9, 15, 5, 11, 3), Move(8, 15, 6, 15, 2), Move(9, 16, 5, 12, 3), Move(10, 13, 10, 11, 4), Move(11, 12, 7, 16, 1), Move(12, 12, 8, 12, 2), Move(8, 16, 8, 16, 1), Move(9, 17, 5, 13, 3), Move(8, 17, 8, 13, 4), Move(9, 18, 9, 14, 4), Move(12, 13, 8, 9, 3), Move(11, 14, 8, 17, 1), Move(11, 15, 11, 11, 4), Move(13, 13, 9, 13, 2)]