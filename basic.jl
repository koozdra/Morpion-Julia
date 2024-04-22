import Base.hash
include("morpion.jl")

function main()
  max_moves = random_morpion()
  max_score = length(max_moves)

  num_iterations_time = 100000
  # max_visits = 1000000
  max_visits = 1000000

  step_back = 0

  backup_accept_score_modifier = -step_back
  index_backup_accept_modifier = -step_back

  iteration = 0
  num_new_generated_counter = 0 
  num_time_steps_no_new_generated_counter = 0
  improvement_counter = 0

  t = time()

  index = Dict{UInt64,Tuple{Int,Array{Move,1}}}()
  index[points_hash(max_moves)] = (0, max_moves)
  index_max_score = max_score

  

  backup_index = Dict{UInt64, Array{Move, 1}}()
  taboo_index = Dict{UInt64, Bool}()

  dna_cache = Dict{UInt64, Array{Int}}()

  select_new_item = false
  current_index_key = rand(keys(index))

  while true

    
    
    if isempty(keys(index))      
      max_backup_score = maximum(p -> length(p[2]), backup_index)
      # println("max backup score: $(max_backup_score)")
      for key in collect(keys(backup_index))
        moves = backup_index[key]
        if !haskey(taboo_index, key)
          if length(moves) >= (max_backup_score + index_backup_accept_modifier)
            index[key] = (0, moves)
          
          end
        end
      end

      # index_keys = collect(keys(index))
      index_max_score = max_backup_score
    end

    

    # rand_index_key = rand(keys(index))

    # index_key = rand(keys(index))

    # index_keys = collect(keys(index))

    # index_key = rand(index_keys)
    # index_key = index_keys[(iteration%length(index_keys)) + 1]
    # index_key = index_keys[findmax(index_key -> -index[index_key][1], index_keys)[2]]
    # index_key = index_keys[findmax(index_key -> length(index[index_key][2]), index_keys)[2]]
    # index_key = index_keys[findmax(index_key -> (length(index[index_key][2]), -index[index_key][1]), index_keys)[2]]
    
    # if iteration > 0 && (iteration % 10) == 0
    #   index_key = index_keys[
    #     findmax(index_key -> length(index[index_key][2]) - floor(index[index_key][1] / (length(index[index_key][2]) * 1)), index_keys)[2]
    #   ]
    # elseif iteration > 0 && (iteration % 10) == 1
    #   index_key = index_keys[findmax(index_key -> (length(index[index_key][2]), -index[index_key][1]), index_keys)[2]]
    # elseif iteration > 0 && (iteration % 10) == 2
    #   index_key = index_keys[findmax(index_key -> -index[index_key][1], index_keys)[2]]
    # else
    #   # index_key = index_keys[(iteration%length(index_keys)) + 1]    
    #   index_key = rand(index_keys)
    # end

    
    # if iteration > 0 && (iteration % 100) == 0
    #   # index_key = index_keys[findmax(index_key -> (length(index[index_key][2]), -index[index_key][1]), index_keys)[2]]
    #   index_key = index_keys[
    #     findmax(index_key -> length(index[index_key][2]) - (index[index_key][1] / (length(index[index_key][2]) * 2)), index_keys)[2]
    #   ]
    #   # (v, m) = index[index_key]
    #   #   println(" selecting $(length(m))($v)")
    # elseif iteration > 0 && (iteration % 100) == 1
    #     index_key = index_keys[findmax(index_key -> length(index[index_key][2]) + rand(), index_keys)[2]]
        
    # else
    #   # index_key = index_keys[(iteration%length(index_keys)) + 1]
    #   index_key = rand(index_keys)
    # end

    # index_key = index_keys[(iteration%length(index_keys)) + 1]
    

    if !haskey(index, current_index_key)
      current_index_key = rand(keys(index))
    end

    index_key = current_index_key

    (visits, moves) = index[index_key]
    index[index_key] = (visits + 1, moves)
    selected_score = length(moves)

    if visits > (selected_score * 1)
      current_index_key = rand(keys(index))
    end

    test_dna = generate_dna(moves)

    visit_move = moves[(visits % length(moves)) + 1]
    test_dna[dna_index(visit_move)] = 0

    # for i in 1:2
      # random_move = max_moves[rand(1:end)]
      # test_dna[dna_index(random_move)] = 0
    # end

    eval_moves = eval_dna(test_dna)
    eval_score = length(eval_moves)

    eval_points_hash = points_hash(eval_moves)

    is_in_taboo = haskey(taboo_index, eval_points_hash)
    is_in_index = haskey(index, eval_points_hash)
    is_in_backup = haskey(backup_index, eval_points_hash)

    if is_in_backup
      backup_index[eval_points_hash] = eval_moves
    end

    if is_in_index
      (v, m) = index[eval_points_hash]
      index[eval_points_hash] = (v, eval_moves)
    end

    if !is_in_taboo
      
      if eval_score > max_score
        println("$iteration. ******* $eval_score")
        max_score = eval_score
        max_moves = eval_moves

        step_back = 0
          
        backup_accept_score_modifier = -step_back
        index_backup_accept_modifier = -step_back

        improvement_counter = 0
      end

      if !is_in_index
        
        if !is_in_backup
          # if eval_score == selected_score
          #   println("$iteration. $(length(moves)) ($visits) -> $eval_score")
            
            
            

          #   backup_index[eval_points_hash] = eval_moves
          #   index[eval_points_hash] = (0, eval_moves)

          
          #   index[index_key] = (0, moves)

          if (eval_score >= index_max_score - 5)
            backup_index[eval_points_hash] = eval_moves
          end

          if (eval_score >= index_max_score + backup_accept_score_modifier)
            backup_index[eval_points_hash] = eval_moves
            index[eval_points_hash] = (0, eval_moves)

            index[index_key] = (0, moves)
    
            println("$iteration. $selected_score ($visits) > $eval_score (impr: $improvement_counter)")

            num_new_generated_counter += 1
          end

          if eval_score > (index_max_score + backup_accept_score_modifier)
            improvement_counter +=  1
          end

          

          # if eval_score > selected_score
            # improvement_counter +=  1

          #   println("$iteration. $(length(moves)) ($visits) => $eval_score")

          #   index[index_key] = (0, moves)
          #   # empty!(index)
          #   # println("clearing index ---")
          # end
        end

        if eval_score > index_max_score
          empty!(index)
        end
        
      end

      

    end

    if iteration > 0 && iteration % num_iterations_time == 0
      dt = time() - t

      println("$iteration. index:$(length(index)) backup:$(length(backup_index)) impr:$improvement_counter new:$num_new_generated_counter new_generated:$num_new_generated_counter no_new:$num_time_steps_no_new_generated_counter $(index_max_score - step_back)/$index_max_score/$max_score $dt")

      if num_new_generated_counter <= 5
        num_time_steps_no_new_generated_counter += 1

        if num_time_steps_no_new_generated_counter == 2
          step_back += 1
          
          backup_accept_score_modifier = -step_back
          index_backup_accept_modifier = -step_back
          
          empty!(index)
          num_time_steps_no_new_generated_counter = 0
          # improvement_counter = 0
        end
      else
        num_time_steps_no_new_generated_counter = 0
      end

      num_new_generated_counter = 0

      if improvement_counter >= 10
        step_back = max(0, step_back - 1)
        improvement_counter = 0
        backup_accept_score_modifier = -step_back
        index_backup_accept_modifier = -step_back

        empty!(index)
      end

      t = time()
    end

    if iteration > 0 && iteration % 10000000 == 0
      step_back = 0
      backup_accept_score_modifier = -step_back
      index_backup_accept_modifier = -step_back
      empty!(index)
    end

    if iteration > 0 && iteration % 10000000 == 0
      println(max_score)
      println(max_moves)

      
    end

    if visits > max_visits
      taboo_index[index_key] = true
      delete!(index, index_key)
      delete!(backup_index, index_key)

      if !isempty(index)
        new_index_max_score = maximum(p -> length(p[2][2]), index)
        if new_index_max_score < index_max_score
          empty!(index)
        end
        # println("index max $index_max_score")
      end

      println("$iteration. -$(length(moves)) index:$(length(index)) index_max:$index_max_score")
    end

    iteration += 1
  end


end

main()


# 168 
# Move[Move(4, 6, 0, 6, 2), Move(0, 7, 0, 3, 4), Move(4, 3, 0, 3, 2), Move(5, 3, 4, 3, 2), Move(3, 10, 3, 6, 4), Move(5, 8, 3, 10, 1), Move(2, 7, 0, 5, 3), Move(2, 9, 2, 9, 2), Move(6, 10, 6, 6, 4), Move(4, 8, 2, 6, 3), Move(2, 8, 2, 8, 2), Move(5, 6, 4, 6, 2), Move(2, 2, 0, 4, 1), Move(2, 5, 2, 5, 4), Move(3, 4, 0, 7, 1), Move(3, 5, 3, 2, 4), Move(4, 4, 2, 6, 1), Move(5, 5, 2, 2, 3), Move(6, 4, 2, 8, 1), Move(6, 5, 6, 2, 4), Move(4, 7, 2, 9, 1), Move(1, 7, 0, 7, 2), Move(-1, 5, -1, 5, 3), Move(7, 10, 3, 6, 3), Move(1, 5, -1, 5, 2), Move(7, 0, 3, 0, 2), Move(4, 5, 4, 3, 4), Move(7, 5, 3, 5, 2), Move(5, 7, 3, 9, 1), Move(5, 10, 5, 6, 4), Move(4, 10, 3, 10, 2), Move(4, 11, 4, 7, 4), Move(1, 8, 0, 7, 3), Move(5, 4, 1, 8, 1), Move(1, 4, 1, 4, 4), Move(4, 1, 0, 5, 1), Move(7, 4, 3, 4, 2), Move(7, 2, 7, 2, 4), Move(5, 2, 5, 2, 4), Move(4, -1, 4, -1, 3), Move(8, -1, 4, 3, 1), Move(7, 7, 4, 10, 1), Move(8, 7, 4, 7, 2), Move(7, 8, 4, 11, 1), Move(8, 9, 4, 5, 3), Move(7, 9, 7, 6, 4), Move(8, 10, 4, 6, 3), Move(8, 8, 8, 6, 4), Move(9, 8, 5, 4, 3), Move(10, 8, 6, 8, 2), Move(9, 7, 6, 4, 3), Move(10, 6, 6, 10, 1), Move(9, 9, 9, 5, 4), Move(8, 5, 5, 2, 3), Move(4, 2, 4, -1, 4), Move(8, 2, 4, 2, 2), Move(8, 4, 8, 2, 4), Move(11, 7, 7, 3, 3), Move(12, 6, 8, 10, 1), Move(11, 6, 8, 6, 2), Move(2, 4, 0, 6, 1), Move(-1, 4, -1, 4, 2), Move(10, 9, 6, 9, 2), Move(10, 10, 6, 6, 3), Move(10, 7, 10, 6, 4), Move(12, 7, 8, 7, 2), Move(12, 5, 8, 9, 1), Move(2, 1, 2, 1, 4), Move(1, 2, -1, 4, 1), Move(0, 2, 0, 2, 2), Move(-1, 1, -1, 1, 3), Move(-1, 2, -1, 2, 3), Move(-1, 3, -1, 1, 4), Move(-2, 2, -2, 2, 3), Move(10, 5, 8, 3, 3), Move(11, 5, 7, 5, 2), Move(10, 4, 8, 2, 3), Move(11, 4, 7, 4, 2), Move(11, 3, 11, 3, 4), Move(12, 2, 8, 6, 1), Move(12, 3, 8, 7, 1), Move(12, 4, 12, 2, 4), Move(10, 3, 8, 3, 2), Move(10, 2, 10, 2, 4), Move(11, 2, 7, 6, 1), Move(9, 2, 8, 2, 2), Move(9, 1, 9, 1, 4), Move(10, 0, 6, 4, 1), Move(10, 1, 6, 5, 1), Move(11, 1, 7, 5, 1), Move(9, 0, 8, -1, 3), Move(8, 1, 8, 1, 3), Move(7, 1, 7, 1, 2), Move(5, 1, 3, 1, 2), Move(3, -1, 3, -1, 3), Move(3, -2, 3, -2, 4), Move(10, -1, 6, 3, 1), Move(10, -2, 10, -2, 4), Move(8, 0, 8, 0, 3), Move(9, -1, 6, 2, 1), Move(8, -2, 8, -2, 3), Move(11, 0, 7, 0, 2), Move(11, -1, 11, -1, 4), Move(7, -1, 7, -1, 2), Move(7, -2, 7, -2, 4), Move(9, -3, 5, 1, 1), Move(9, -2, 9, -3, 4), Move(6, -2, 6, -2, 2), Move(6, -1, 6, -2, 4), Move(5, -1, 3, -1, 2), Move(5, -2, 5, -2, 4), Move(8, -3, 4, 1, 1), Move(4, -3, 4, -3, 3), Move(8, -4, 8, -4, 4), Move(7, -5, 7, -5, 3), Move(7, -4, 7, -4, 3), Move(7, -3, 4, 0, 1), Move(7, -6, 7, -6, 4), Move(6, -3, 3, 0, 1), Move(5, -3, 5, -3, 2), Move(4, -4, 4, -4, 3), Move(4, -2, 4, -2, 3), Move(2, -2, 2, -2, 2), Move(6, -4, 3, -1, 1), Move(5, -4, 4, -4, 2), Move(4, -5, 4, -5, 3), Move(6, -5, 3, -2, 1), Move(6, -6, 6, -6, 4), Move(4, -6, 4, -6, 4), Move(5, -5, 4, -6, 3), Move(3, -3, 2, -2, 1), Move(3, -5, 3, -5, 2), Move(5, -6, 5, -6, 4), Move(3, -6, 3, -6, 2), Move(3, -4, 3, -6, 4), Move(2, 0, 2, 0, 3), Move(1, 1, -1, 3, 1), Move(1, 0, 1, 0, 4), Move(0, 1, -1, 1, 2), Move(-1, 0, -1, 0, 3), Move(0, 0, -1, 0, 2), Move(1, -1, -2, 2, 1), Move(2, -1, -1, 2, 1), Move(2, -3, 2, -3, 4), Move(1, -3, 1, -3, 2), Move(0, -1, 0, -1, 3), Move(0, -2, 0, -2, 4), Move(2, -4, 0, -2, 1), Move(-1, -1, -1, -1, 2), Move(1, -2, -1, 0, 1), Move(1, -4, 1, -4, 4), Move(0, -5, 0, -5, 3), Move(0, -4, 0, -4, 2), Move(-1, -5, -1, -5, 3), Move(0, -3, 0, -3, 3), Move(0, -6, 0, -6, 4), Move(1, -5, 0, -6, 3), Move(2, -5, -1, -5, 2), Move(-1, -2, -1, -2, 1), Move(-2, -2, -2, -2, 2), Move(-1, -3, -1, -3, 4), Move(2, -6, -2, -2, 1), Move(2, -7, 2, -7, 4), Move(-3, -3, -3, -3, 3), Move(-2, -3, -3, -3, 2), Move(-2, -4, -2, -4, 3), Move(1, -7, -3, -3, 1), Move(0, -8, 0, -8, 3)]
# 177
# Move[Move(6, 4, 6, 0, 4), Move(3, 4, 3, 0, 4), Move(2, 0, 2, 0, 2), Move(0, 2, 0, 2, 4), Move(2, 2, 0, 4, 1), Move(7, 2, 5, 0, 3), Move(-1, 3, -1, 3, 2), Move(9, 7, 9, 3, 4), Move(-1, 6, -1, 6, 2), Move(3, 5, 3, 4, 4), Move(1, 4, -1, 6, 1), Move(1, 5, -1, 3, 3), Move(6, 5, 6, 4, 4), Move(1, 2, 1, 2, 4), Move(4, 2, 0, 2, 2), Move(5, 3, 2, 0, 3), Move(4, 3, 3, 3, 2), Move(5, 4, 3, 2, 3), Move(4, 5, 3, 6, 1), Move(5, 6, 1, 2, 3), Move(4, 6, 3, 6, 2), Move(2, 4, 0, 2, 3), Move(-1, 7, -1, 7, 1), Move(4, 4, 2, 4, 2), Move(4, 1, 4, 0, 4), Move(2, 1, 2, 0, 4), Move(-1, 4, -1, 4, 1), Move(-2, 4, -2, 4, 2), Move(-1, 5, -1, 3, 4), Move(2, 5, -1, 5, 2), Move(4, 7, 0, 3, 3), Move(2, 7, -1, 4, 3), Move(4, 8, 4, 4, 4), Move(1, 1, -2, 4, 1), Move(5, 1, 1, 1, 2), Move(8, 4, 4, 0, 3), Move(2, 8, 2, 4, 4), Move(1, 7, -2, 4, 3), Move(0, 7, -1, 7, 2), Move(-1, 8, -1, 8, 1), Move(5, 5, 1, 1, 3), Move(5, 7, 5, 3, 4), Move(2, 10, 2, 10, 1), Move(1, 9, 1, 9, 1), Move(0, 8, 0, 8, 1), Move(1, 8, -1, 8, 2), Move(3, 11, -1, 7, 3), Move(1, 10, 1, 6, 4), Move(2, 9, 1, 10, 1), Move(0, 9, 0, 9, 2), Move(-1, 10, -1, 10, 1), Move(0, 10, 0, 6, 4), Move(3, 10, -1, 10, 2), Move(3, 12, 3, 8, 4), Move(4, 11, 0, 7, 3), Move(2, 11, -1, 8, 3), Move(2, 12, 2, 8, 4), Move(4, 10, 2, 12, 1), Move(4, 12, 4, 8, 4), Move(7, -1, 3, 3, 1), Move(5, 8, 2, 11, 1), Move(7, 8, 3, 8, 2), Move(5, 10, 3, 12, 1), Move(5, 11, 5, 7, 4), Move(6, 11, 2, 11, 2), Move(7, 12, 3, 8, 3), Move(7, 5, 3, 5, 2), Move(7, 7, 3, 7, 2), Move(7, 4, 7, 4, 4), Move(10, 4, 6, 4, 2), Move(11, 3, 7, 7, 1), Move(10, 3, 7, 3, 2), Move(8, 5, 6, 7, 1), Move(8, 7, 8, 3, 4), Move(5, 2, 3, 0, 3), Move(8, 2, 4, 2, 2), Move(9, 1, 5, 5, 1), Move(5, -1, 5, -1, 4), Move(9, 2, 5, 6, 1), Move(6, 12, 2, 8, 3), Move(5, 12, 2, 12, 2), Move(6, 10, 6, 8, 4), Move(7, 10, 3, 10, 2), Move(8, 11, 4, 7, 3), Move(7, 11, 3, 7, 3), Move(7, 9, 7, 8, 4), Move(8, 9, 4, 9, 2), Move(8, 8, 4, 12, 1), Move(9, 10, 5, 6, 3), Move(9, 8, 5, 12, 1), Move(8, 10, 8, 7, 4), Move(9, 11, 5, 7, 3), Move(10, 11, 6, 11, 2), Move(9, 9, 9, 7, 4), Move(10, 10, 6, 6, 3), Move(11, 10, 7, 10, 2), Move(10, 9, 7, 6, 3), Move(11, 8, 7, 12, 1), Move(10, 7, 7, 4, 3), Move(11, 7, 7, 7, 2), Move(7, 1, 5, -1, 3), Move(7, 0, 7, 0, 4), Move(8, 1, 5, 1, 2), Move(6, -1, 6, -1, 3), Move(7, -2, 3, 2, 1), Move(10, 8, 10, 7, 4), Move(11, 9, 7, 5, 3), Move(12, 6, 8, 10, 1), Move(11, 6, 11, 6, 4), Move(10, 6, 7, 6, 2), Move(10, 5, 10, 3, 4), Move(11, 5, 7, 5, 2), Move(12, 8, 8, 4, 3), Move(13, 7, 9, 3, 3), Move(11, 4, 7, 8, 1), Move(13, 8, 9, 8, 2), Move(11, 2, 11, 2, 4), Move(12, 4, 8, 8, 1), Move(12, 7, 9, 4, 3), Move(12, 9, 8, 9, 2), Move(14, 7, 10, 11, 1), Move(12, 5, 12, 5, 4), Move(15, 7, 11, 7, 2), Move(13, 6, 10, 3, 3), Move(8, -1, 4, 3, 1), Move(8, 0, 8, -1, 4), Move(9, -1, 5, 3, 1), Move(9, 0, 9, -1, 4), Move(10, 0, 6, 0, 2), Move(10, 2, 7, -1, 3), Move(12, 2, 8, 2, 2), Move(10, 1, 7, -2, 3), Move(10, -1, 10, -1, 4), Move(11, -1, 7, -1, 2), Move(11, -2, 7, 2, 1), Move(13, 4, 9, 8, 1), Move(13, 5, 13, 4, 4), Move(14, 6, 11, 3, 3), Move(14, 4, 10, 4, 2), Move(15, 6, 11, 6, 2), Move(15, 5, 11, 9, 1), Move(14, 5, 11, 5, 2), Move(14, 3, 14, 3, 4), Move(15, 4, 11, 8, 1), Move(12, 3, 11, 2, 3), Move(15, 3, 15, 3, 4), Move(16, 2, 12, 6, 1), Move(13, 3, 11, 3, 2), Move(12, 1, 12, 1, 4), Move(11, 1, 10, 0, 3), Move(13, 1, 9, 1, 2), Move(12, 0, 8, 4, 1), Move(14, 2, 11, -1, 3), Move(11, 0, 11, -2, 4), Move(13, 2, 11, 0, 3), Move(15, 2, 12, 2, 2), Move(13, 0, 13, 0, 4), Move(14, 0, 10, 0, 2), Move(14, -1, 10, 3, 1), Move(15, -1, 11, 3, 1), Move(14, 1, 14, -1, 4), Move(15, 0, 11, 4, 1), Move(12, -1, 11, -2, 3), Move(13, -1, 11, -1, 2), Move(13, -2, 9, 2, 1), Move(15, 1, 15, -1, 4), Move(12, -2, 12, -2, 3), Move(12, -3, 12, -3, 4), Move(16, 1, 12, -3, 3), Move(16, 0, 12, 4, 1), Move(17, 1, 13, 1, 2), Move(13, -3, 9, 1, 1), Move(14, -2, 13, -3, 3), Move(15, -2, 11, -2, 2), Move(13, -4, 13, -4, 4), Move(17, 0, 13, 4, 1), Move(18, 0, 14, 0, 2)]
# 177
# Move[Move(9, 2, 9, 2, 4), Move(-1, 3, -1, 3, 2), Move(0, 7, 0, 3, 4), Move(2, 7, 0, 5, 3), Move(2, 9, 2, 9, 2), Move(-1, 6, -1, 6, 2), Move(7, 7, 5, 9, 1), Move(3, 5, 3, 5, 4), Move(3, 4, 3, 1, 4), Move(1, 5, -1, 3, 3), Move(6, 5, 6, 5, 4), Move(6, 4, 6, 1, 4), Move(1, 4, -1, 6, 1), Move(1, 7, 1, 3, 4), Move(4, 7, 0, 7, 2), Move(5, 6, 2, 9, 1), Move(4, 6, 3, 6, 2), Move(5, 5, 3, 7, 1), Move(4, 4, 3, 3, 3), Move(5, 3, 2, 6, 1), Move(4, 3, 3, 3, 2), Move(2, 5, 0, 7, 1), Move(4, 5, 2, 5, 2), Move(-1, 2, -1, 2, 3), Move(2, 8, 2, 5, 4), Move(4, 8, 4, 5, 4), Move(-1, 5, -1, 5, 3), Move(-2, 5, -2, 5, 2), Move(2, 2, -1, 5, 1), Move(-1, 4, -1, 2, 4), Move(2, 4, -1, 4, 2), Move(4, 2, 0, 6, 1), Move(4, 1, 4, 1, 4), Move(2, 1, 2, 1, 4), Move(1, 2, -2, 5, 1), Move(0, 1, 0, 1, 3), Move(0, 2, -1, 2, 2), Move(-1, 1, -1, 1, 3), Move(1, 1, -1, 1, 2), Move(1, 8, -2, 5, 3), Move(5, 8, 1, 8, 2), Move(8, 5, 4, 9, 1), Move(5, 4, 1, 8, 1), Move(5, 2, 5, 2, 4), Move(2, -1, 2, -1, 3), Move(1, 0, 1, 0, 3), Move(1, -1, 1, -1, 4), Move(2, 0, 1, -1, 3), Move(7, 2, 3, 2, 2), Move(0, 0, 0, 0, 2), Move(0, -1, 0, -1, 4), Move(-1, -1, -1, -1, 3), Move(3, -1, -1, -1, 2), Move(4, -2, 0, 2, 1), Move(7, 10, 3, 6, 3), Move(3, -2, -1, 2, 1), Move(4, -1, 3, -2, 3), Move(3, -3, 3, -3, 4), Move(2, -2, -1, 1, 1), Move(4, -3, 4, -3, 4), Move(5, 1, 2, -2, 3), Move(7, 1, 3, 1, 2), Move(5, -1, 3, -3, 3), Move(5, -2, 5, -2, 4), Move(6, -2, 2, -2, 2), Move(7, -3, 3, 1, 1), Move(6, -3, 2, 1, 1), Move(6, -1, 6, -3, 4), Move(7, -2, 3, 2, 1), Move(7, -1, 3, -1, 2), Move(8, -2, 4, 2, 1), Move(5, -3, 3, -3, 2), Move(7, 0, 7, -2, 4), Move(8, 1, 4, -3, 3), Move(8, 0, 4, 0, 2), Move(9, 1, 5, -3, 3), Move(7, 4, 3, 4, 2), Move(7, 5, 7, 2, 4), Move(10, 5, 6, 5, 2), Move(9, 7, 5, 3, 3), Move(5, 7, 3, 9, 1), Move(8, 7, 4, 7, 2), Move(5, 10, 5, 6, 4), Move(2, -3, 2, -3, 4), Move(11, 6, 7, 2, 3), Move(9, 8, 5, 4, 3), Move(10, 6, 7, 6, 2), Move(8, 4, 6, 2, 3), Move(8, 2, 8, 2, 4), Move(8, -1, 8, -2, 4), Move(9, -2, 5, 2, 1), Move(10, -2, 6, -2, 2), Move(9, -1, 6, 2, 1), Move(9, 0, 9, -2, 4), Move(10, -1, 6, 3, 1), Move(11, -1, 7, -1, 2), Move(10, 0, 7, 3, 1), Move(11, 1, 7, -3, 3), Move(10, 2, 7, 5, 1), Move(11, 2, 7, 2, 2), Move(10, 1, 10, -2, 4), Move(12, 3, 8, -1, 3), Move(11, 0, 7, 4, 1), Move(12, 0, 8, 0, 2), Move(11, 3, 11, -1, 4), Move(10, 3, 7, 3, 2), Move(10, 4, 10, 2, 4), Move(11, 4, 7, 4, 2), Move(13, 2, 9, 6, 1), Move(12, 5, 8, 1, 3), Move(12, 1, 8, 5, 1), Move(11, 5, 7, 1, 3), Move(11, 7, 11, 3, 4), Move(13, 1, 9, 1, 2), Move(14, 2, 10, -2, 3), Move(12, 2, 9, 5, 1), Move(12, 4, 12, 0, 4), Move(13, 3, 10, 6, 1), Move(15, 2, 11, 2, 2), Move(7, 8, 5, 10, 1), Move(7, 9, 7, 6, 4), Move(8, 10, 4, 6, 3), Move(8, 8, 5, 8, 2), Move(8, 9, 8, 6, 4), Move(9, 10, 5, 6, 3), Move(9, 9, 9, 6, 4), Move(10, 9, 6, 9, 2), Move(10, 7, 7, 10, 1), Move(6, 10, 6, 10, 1), Move(7, 11, 3, 7, 3), Move(12, 7, 8, 7, 2), Move(10, 8, 7, 11, 1), Move(10, 10, 10, 6, 4), Move(11, 10, 7, 10, 2), Move(11, 11, 7, 7, 3), Move(13, 5, 9, 1, 3), Move(13, 4, 13, 1, 4), Move(14, 3, 11, 6, 1), Move(14, 5, 10, 5, 2), Move(15, 3, 11, 3, 2), Move(15, 4, 11, 0, 3), Move(14, 4, 11, 4, 2), Move(14, 6, 14, 2, 4), Move(12, 6, 11, 7, 1), Move(15, 5, 11, 1, 3), Move(15, 6, 15, 2, 4), Move(16, 7, 12, 3, 3), Move(13, 6, 11, 6, 2), Move(12, 8, 12, 4, 4), Move(11, 8, 11, 8, 1), Move(13, 8, 9, 8, 2), Move(12, 9, 8, 5, 3), Move(14, 7, 11, 10, 1), Move(11, 9, 11, 7, 4), Move(13, 7, 11, 9, 1), Move(15, 7, 12, 7, 2), Move(13, 9, 13, 5, 4), Move(14, 9, 10, 9, 2), Move(14, 10, 10, 6, 3), Move(15, 10, 11, 6, 3), Move(14, 8, 14, 6, 4), Move(15, 9, 11, 5, 3), Move(12, 10, 11, 11, 1), Move(13, 10, 11, 10, 2), Move(13, 11, 9, 7, 3), Move(15, 8, 15, 6, 4), Move(12, 11, 12, 11, 1), Move(12, 12, 12, 8, 4), Move(16, 9, 12, 5, 3), Move(16, 8, 12, 12, 1), Move(13, 12, 9, 8, 3), Move(17, 8, 13, 8, 2), Move(13, 13, 13, 9, 4), Move(14, 11, 13, 12, 1), Move(15, 11, 11, 11, 2), Move(17, 9, 13, 5, 3), Move(18, 9, 14, 9, 2)]
# 177
# Move[Move(7, 0, 3, 0, 2), Move(7, 2, 5, 0, 3), Move(6, -1, 6, -1, 4), Move(5, 3, 5, 3, 2), Move(3, -1, 3, -1, 4), Move(7, 7, 5, 9, 1), Move(5, 6, 5, 6, 2), Move(9, 2, 9, 2, 4), Move(5, 1, 3, -1, 3), Move(2, 9, 2, 9, 2), Move(4, 6, 1, 6, 2), Move(4, 3, 1, 3, 2), Move(4, 1, 2, 3, 1), Move(7, 1, 3, 1, 2), Move(7, 4, 7, 0, 4), Move(6, 5, 5, 6, 1), Move(6, 4, 6, 3, 4), Move(5, 5, 3, 7, 1), Move(4, 4, 3, 3, 3), Move(3, 5, 3, 5, 1), Move(3, 4, 3, 3, 4), Move(5, 2, 3, 4, 1), Move(2, -1, 2, -1, 3), Move(5, 4, 5, 2, 4), Move(8, 2, 5, 2, 2), Move(8, 4, 5, 4, 2), Move(5, -1, 5, -1, 3), Move(5, -2, 5, -2, 4), Move(2, 2, 1, 3, 1), Move(8, 1, 5, -2, 3), Move(4, -1, 2, -1, 2), Move(4, 5, 4, 5, 1), Move(2, 5, 2, 5, 2), Move(4, 2, 4, -1, 4), Move(4, 7, 4, 3, 4), Move(8, 5, 8, 1, 4), Move(5, 8, 5, 8, 1), Move(7, 10, 3, 6, 3), Move(2, 4, 2, 4, 1), Move(1, 4, 1, 4, 2), Move(-1, 2, -1, 2, 3), Move(1, 10, 1, 10, 1), Move(1, 2, 1, 2, 2), Move(2, 1, 1, 2, 1), Move(2, 0, 2, -1, 4), Move(1, -1, 1, -1, 3), Move(1, 0, 1, 0, 3), Move(10, 7, 6, 3, 3), Move(1, 1, 1, 0, 4), Move(0, 1, 0, 1, 3), Move(-1, 1, -1, 1, 2), Move(2, 7, 2, 3, 4), Move(5, 10, 1, 6, 3), Move(-2, 3, -2, 3, 1), Move(0, 2, -1, 1, 3), Move(0, 0, 0, 0, 4), Move(-1, -1, -1, -1, 3), Move(-1, 0, -1, 0, 2), Move(-1, 3, -1, -1, 4), Move(-2, 4, -2, 4, 1), Move(-3, 3, -3, 3, 2), Move(-2, 2, -3, 3, 1), Move(-3, 2, -3, 2, 2), Move(-1, 4, -3, 2, 3), Move(-3, 4, -3, 4, 2), Move(1, 5, -2, 2, 3), Move(5, 7, 5, 6, 4), Move(7, 9, 3, 5, 3), Move(7, 5, 5, 7, 1), Move(7, 8, 7, 4, 4), Move(9, 7, 5, 3, 3), Move(10, 5, 6, 5, 2), Move(8, 7, 6, 9, 1), Move(11, 7, 7, 7, 2), Move(10, 6, 7, 3, 3), Move(1, 7, 1, 7, 2), Move(-1, 5, -3, 3, 3), Move(-2, 5, -2, 5, 2), Move(-3, 6, -3, 6, 1), Move(-2, 6, -2, 2, 4), Move(-1, 6, -3, 6, 2), Move(-2, 7, -2, 7, 1), Move(-3, 7, -3, 7, 1), Move(-1, 7, -1, 3, 4), Move(-2, 8, -2, 8, 1), Move(-3, 5, -3, 2, 4), Move(0, 7, -3, 7, 2), Move(1, 8, -3, 4, 3), Move(1, 9, 1, 5, 4), Move(-1, 8, -1, 8, 1), Move(0, 9, -3, 6, 3), Move(0, 8, 0, 4, 4), Move(2, 8, -2, 8, 2), Move(-1, 9, -1, 9, 1), Move(-1, 10, -1, 10, 1), Move(4, 8, 2, 8, 2), Move(6, 10, 2, 6, 3), Move(6, 11, 6, 7, 4), Move(-2, 9, -2, 9, 2), Move(-2, 10, -2, 6, 4), Move(8, 8, 6, 10, 1), Move(8, 9, 8, 5, 4), Move(9, 8, 6, 11, 1), Move(10, 9, 6, 5, 3), Move(9, 9, 6, 9, 2), Move(10, 8, 6, 8, 2), Move(10, 10, 10, 6, 4), Move(11, 11, 7, 7, 3), Move(-1, 11, -1, 7, 4), Move(0, 10, -1, 11, 1), Move(1, 11, -3, 7, 3), Move(2, 10, -2, 10, 2), Move(2, 11, 2, 7, 4), Move(0, 12, 0, 12, 1), Move(0, 11, 0, 8, 4), Move(3, 11, -1, 11, 2), Move(4, 12, 0, 8, 3), Move(-4, 4, -4, 4, 3), Move(3, 10, 3, 7, 4), Move(1, 12, 1, 12, 1), Move(4, 10, 2, 10, 2), Move(5, 11, 1, 7, 3), Move(1, 13, 1, 9, 4), Move(2, 12, 1, 13, 1), Move(3, 12, 0, 12, 2), Move(4, 11, 4, 7, 4), Move(7, 11, 3, 11, 2), Move(8, 10, 7, 11, 1), Move(9, 10, 6, 10, 2), Move(10, 11, 6, 7, 3), Move(9, 11, 9, 7, 4), Move(7, 12, 7, 8, 4), Move(8, 11, 7, 11, 2), Move(6, 13, 6, 13, 1), Move(2, 14, -2, 10, 3), Move(3, 13, 2, 14, 1), Move(5, 12, 1, 8, 3), Move(2, 13, 2, 13, 1), Move(3, 14, -1, 10, 3), Move(3, 15, 3, 11, 4), Move(2, 15, 2, 11, 4), Move(4, 13, 2, 15, 1), Move(5, 13, 1, 13, 2), Move(5, 14, 1, 10, 3), Move(5, 15, 5, 11, 4), Move(4, 14, 1, 11, 3), Move(6, 12, 3, 15, 1), Move(4, 15, 4, 11, 4), Move(6, 15, 2, 15, 2), Move(8, 12, 4, 12, 2), Move(6, 14, 6, 11, 4), Move(7, 14, 3, 14, 2), Move(8, 13, 8, 9, 4), Move(9, 12, 6, 15, 1), Move(9, 14, 5, 10, 3), Move(7, 13, 5, 15, 1), Move(9, 13, 5, 13, 2), Move(9, 15, 9, 11, 4), Move(10, 14, 6, 10, 3), Move(8, 14, 5, 11, 3), Move(11, 14, 7, 14, 2), Move(10, 13, 7, 10, 3), Move(10, 12, 10, 10, 4), Move(7, 15, 7, 15, 1), Move(8, 16, 4, 12, 3), Move(7, 16, 7, 12, 4), Move(11, 13, 7, 9, 3), Move(12, 12, 8, 16, 1), Move(11, 12, 8, 12, 2), Move(11, 15, 11, 11, 4), Move(8, 15, 7, 16, 1), Move(9, 16, 5, 12, 3), Move(8, 17, 8, 13, 4), Move(10, 15, 6, 15, 2), Move(9, 18, 5, 14, 3), Move(12, 13, 8, 17, 1), Move(13, 13, 9, 13, 2)]
# 178
# Move[Move(3, -1, 3, -1, 4), Move(9, 2, 9, 2, 4), Move(7, 0, 3, 0, 2), Move(5, 3, 5, 3, 2), Move(7, 2, 5, 0, 3), Move(6, -1, 6, -1, 4), Move(2, 9, 2, 9, 2), Move(7, 7, 5, 9, 1), Move(5, 1, 3, -1, 3), Move(4, 3, 1, 3, 2), Move(5, 6, 5, 6, 2), Move(4, 6, 1, 6, 2), Move(4, 1, 2, 3, 1), Move(7, 1, 3, 1, 2), Move(7, 4, 7, 0, 4), Move(6, 5, 5, 6, 1), Move(6, 4, 6, 3, 4), Move(5, 5, 3, 7, 1), Move(4, 4, 3, 3, 3), Move(3, 5, 3, 5, 1), Move(3, 4, 3, 3, 4), Move(5, 2, 3, 4, 1), Move(2, -1, 2, -1, 3), Move(5, 4, 5, 2, 4), Move(8, 4, 5, 4, 2), Move(8, 2, 5, 2, 2), Move(5, -1, 5, -1, 3), Move(5, -2, 5, -2, 4), Move(4, -1, 2, -1, 2), Move(4, 2, 4, -1, 4), Move(2, 4, 2, 4, 1), Move(2, 2, 1, 3, 1), Move(8, 1, 5, -2, 3), Move(8, 5, 8, 1, 4), Move(5, 8, 5, 8, 1), Move(1, 4, 1, 4, 2), Move(1, 2, 1, 2, 2), Move(2, 1, 1, 2, 1), Move(1, 0, 1, 0, 3), Move(2, 0, 2, -1, 4), Move(1, -1, 1, -1, 3), Move(1, 1, 1, -1, 4), Move(4, 5, 4, 5, 1), Move(4, 7, 4, 3, 4), Move(2, 5, 2, 5, 3), Move(2, 7, 2, 3, 4), Move(5, 10, 1, 6, 3), Move(0, 1, 0, 1, 3), Move(-1, 1, -1, 1, 2), Move(0, 2, -1, 1, 3), Move(-1, 3, -1, 3, 1), Move(0, 0, 0, 0, 4), Move(1, 5, 1, 5, 2), Move(-2, 2, -2, 2, 3), Move(-3, 3, -3, 3, 1), Move(10, 7, 6, 3, 3), Move(-2, 3, -3, 3, 2), Move(1, 10, 1, 10, 1), Move(-1, 0, -1, 0, 2), Move(-1, -1, -1, -1, 3), Move(-1, 2, -1, -1, 4), Move(-3, 4, -3, 4, 1), Move(-2, 1, -2, 1, 3), Move(1, 7, 1, 3, 4), Move(5, 7, 1, 7, 2), Move(5, 11, 5, 7, 4), Move(7, 9, 3, 5, 3), Move(7, 5, 5, 7, 1), Move(10, 5, 6, 5, 2), Move(7, 8, 7, 4, 4), Move(8, 9, 4, 5, 3), Move(8, 7, 6, 9, 1), Move(9, 7, 6, 7, 2), Move(10, 8, 6, 4, 3), Move(-3, 2, -3, 2, 2), Move(-1, 4, -3, 2, 3), Move(-2, 4, -3, 4, 2), Move(-2, 5, -2, 1, 4), Move(-3, 6, -3, 6, 1), Move(-1, 5, -3, 3, 3), Move(-3, 5, -3, 5, 2), Move(-3, 7, -3, 3, 4), Move(-2, 6, -3, 7, 1), Move(-1, 6, -3, 6, 2), Move(-1, 7, -1, 3, 4), Move(-2, 8, -2, 8, 1), Move(-2, 7, -2, 7, 1), Move(-2, 9, -2, 5, 4), Move(0, 7, -3, 7, 2), Move(1, 8, -3, 4, 3), Move(0, 8, 0, 4, 4), Move(1, 9, -3, 5, 3), Move(-1, 9, -1, 9, 1), Move(0, 9, -2, 9, 2), Move(-1, 10, -1, 10, 1), Move(-1, 8, -1, 8, 1), Move(2, 8, -2, 8, 2), Move(-1, 11, -1, 7, 4), Move(4, 8, 2, 8, 2), Move(0, 10, -1, 11, 1), Move(1, 11, -3, 7, 3), Move(2, 10, 1, 11, 1), Move(6, 10, 2, 6, 3), Move(-2, 10, -2, 10, 2), Move(8, 8, 8, 5, 4), Move(9, 8, 6, 8, 2), Move(10, 9, 6, 5, 3), Move(9, 9, 6, 9, 2), Move(9, 10, 9, 6, 4), Move(4, 10, 1, 7, 3), Move(3, 10, 2, 10, 2), Move(3, 11, 3, 7, 4), Move(4, 11, 4, 7, 4), Move(5, 12, 1, 8, 3), Move(6, 11, 6, 7, 4), Move(7, 11, 3, 11, 2), Move(2, 11, 2, 7, 4), Move(3, 12, -1, 8, 3), Move(1, 12, 1, 12, 1), Move(0, 11, -1, 11, 2), Move(1, 13, 1, 9, 4), Move(0, 12, 0, 8, 4), Move(2, 14, -2, 10, 3), Move(2, 12, 1, 13, 1), Move(4, 12, 0, 12, 2), Move(5, 13, 1, 9, 3), Move(3, 13, 2, 14, 1), Move(10, 6, 6, 10, 1), Move(11, 7, 7, 3, 3), Move(7, 10, 6, 11, 1), Move(2, 13, 2, 13, 1), Move(2, 15, 2, 11, 4), Move(4, 13, 1, 13, 2), Move(8, 10, 7, 11, 1), Move(10, 10, 6, 10, 2), Move(10, 11, 10, 7, 4), Move(7, 12, 7, 8, 4), Move(11, 11, 7, 7, 3), Move(3, 14, 2, 15, 1), Move(4, 15, 0, 11, 3), Move(3, 15, 3, 11, 4), Move(4, 14, 4, 11, 4), Move(6, 12, 3, 15, 1), Move(5, 15, 1, 11, 3), Move(6, 15, 2, 15, 2), Move(8, 12, 4, 12, 2), Move(5, 14, 5, 11, 4), Move(6, 14, 2, 14, 2), Move(6, 13, 6, 11, 4), Move(7, 16, 3, 12, 3), Move(8, 11, 5, 14, 1), Move(8, 13, 8, 9, 4), Move(9, 11, 7, 11, 2), Move(9, 14, 5, 10, 3), Move(7, 13, 6, 14, 1), Move(9, 13, 5, 13, 2), Move(9, 12, 9, 10, 4), Move(7, 14, 6, 15, 1), Move(10, 14, 6, 10, 3), Move(10, 13, 6, 9, 3), Move(8, 14, 6, 14, 2), Move(7, 15, 7, 12, 4), Move(9, 15, 5, 11, 3), Move(10, 12, 7, 15, 1), Move(10, 15, 10, 11, 4), Move(11, 13, 7, 9, 3), Move(8, 15, 6, 15, 2), Move(9, 16, 5, 12, 3), Move(11, 12, 7, 16, 1), Move(12, 13, 8, 9, 3), Move(12, 12, 8, 12, 2), Move(13, 13, 9, 13, 2), Move(8, 16, 8, 16, 1), Move(8, 17, 8, 13, 4), Move(9, 17, 5, 13, 3), Move(9, 18, 9, 14, 4), Move(11, 14, 8, 17, 1), Move(11, 15, 11, 11, 4)]
