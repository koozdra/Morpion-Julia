import Base.hash
include("morpion.jl")

function main()
  max_moves = random_morpion()
  max_score = length(max_moves)

  num_iterations_time = 100000
  # max_visits = 1000000
  max_visits = 100000

  step_back = 0

  backup_accept_score_modifier = -step_back
  index_backup_accept_modifier = -step_back

  iteration = 0
  num_new_generated_counter = 0 
  num_time_steps_no_new_generated_counter = 0

  t = time()

  index = Dict{UInt64,Tuple{Int,Array{Move,1}}}()
  index[points_hash(max_moves)] = (0, max_moves)
  index_max_score = max_score

  

  backup_index = Dict{UInt64, Array{Move, 1}}()
  taboo_index = Dict{UInt64, Bool}()

  dna_cache = Dict{UInt64, Array{Int}}()

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

    index_key = rand(keys(index))

    # index_keys = collect(keys(index))

    # index_key = rand(index_keys)
    # index_key = index_keys[(iteration%length(index_keys)) + 1]
    # index_key = index_keys[findmax(index_key -> -index[index_key][1], index_keys)[2]]
    # index_key = index_keys[findmax(index_key -> length(index[index_key][2]), index_keys)[2]]
    # index_key = index_keys[findmax(index_key -> (length(index[index_key][2]), -index[index_key][1]), index_keys)[2]]
    
    # if iteration > 0 && (iteration % 10) == 0
    #   # index_key = index_keys[findmax(index_key -> (length(index[index_key][2]), -index[index_key][1]), index_keys)[2]]
    #   index_key = index_keys[
    #     findmax(index_key -> length(index[index_key][2]) - floor(index[index_key][1] / (length(index[index_key][2]) * 1)), index_keys)[2]
    #   ]
    # elseif iteration > 0 && (iteration % 10) == 1
    #   index_key = index_keys[findmax(index_key -> (length(index[index_key][2]), -index[index_key][1]), index_keys)[2]]
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
    

    (visits, moves) = index[index_key]
    index[index_key] = (visits + 1, moves)
    selected_score = length(moves)

    test_dna = generate_dna(moves)

    visit_move = moves[(visits % length(moves)) + 1]
    test_dna[dna_index(visit_move)] = 0

    # for i in 1:2
    #   random_move = max_moves[rand(1:end)]
    #   test_dna[dna_index(random_move)] = 0
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
    
            println("$iteration. $selected_score ($visits) > $eval_score")

            num_new_generated_counter += 1
          end

          # if eval_score > selected_score
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

      println("$iteration. index:$(length(index)) backup:$(length(backup_index)) new:$num_new_generated_counter new_generated:$num_new_generated_counter no_new:$num_time_steps_no_new_generated_counter $(index_max_score - step_back)/$index_max_score/$max_score $dt")

      if num_new_generated_counter <= 5
        num_time_steps_no_new_generated_counter += 1

        if num_time_steps_no_new_generated_counter == 3
          step_back += 1
          
          backup_accept_score_modifier = -step_back
          index_backup_accept_modifier = -step_back
          
          empty!(index)
          num_time_steps_no_new_generated_counter = 0
        end
      else
        num_time_steps_no_new_generated_counter = 0
      end

      num_new_generated_counter = 0

      t = time()
    end

    if iteration > 0 && iteration % 10000000 == 0
      println(max_score)
      println(max_moves)

      step_back = 0
      backup_accept_score_modifier = -step_back
      index_backup_accept_modifier = -step_back
      empty!(index)
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
