# 166 HYhAHqWtBWCUVGkZRRxasI/rdT+39uUf9d22ap+y7/fX7/3+
# 170 EykgD3IyGWSDsFAhMXIsPeav6+ju7V07eqfruddfv/nfO///6
# 171 F0wgDolGsg5l0kkIno6jbiovx31/l5b3v42y8je9dvt2d//vvQ
# 172 LBFEq2HLWWKB2qBilJqZcOZ3q+y/6xvzfetT91c3Tfv3/9/ae
# 172 AENMhclbKcGxHhKhtGnBJdfX1DeJf7L6X+vt09fU7/Ptcv//va
# 175 KyQihtyDUKLaq0EcpmqsRa/XuYvfN79c9T0t356/9+23fb5y/U
# 176 LoyBD5plSCpD5FoFqixU76aU8b7m9+5k/s+X6en2739dr7/+34
# 177 AYOOj1VpKGCndhSsQa1s+k3ft/usr69mLd/Su+3f+7Z9/+3u4
# 177 FEBMv6lokkqKS4cwzBsf0ubovt9/yOd/M468fl18r1/el5/7/fA
# 177 FEBMv6lokkiL84GQw9LndS5++33Kr9d8RvfNu/Nv/5zff/b3W
# 177 CBMXT2TomgmTmJcpVpeTTr589vL/jW/hnms7Z3O29fu5ef9/3w
# 177 IiAjf2jokjJLE4Zwyk4vWzYlXn77f1lf/be7tN7f/p5fv/t7X
# 177 0yAij1VlSSRWksIzgzcN9Zbvzv7q16+0Hffl2P7f/K53f/fXdg
# 178 0yAij1VlSSRWgtGcINgU4jPuvLppfb390rzecGjnu8r//rpv//b9
# 178 7EBET5ZlRiSHYc0gSqEaxn9OfXDfr79Vak78WKOe7yv//Wm//9v0

include("morpion.jl")
using Random
using DataStructures

function end_search(moves::Array{Move,1}, back_accept)
  score = length(moves)

  index = Dict{UInt64,Array{Move,1}}()

  # Progressively wind back the moves taken on a board
  for step_back in 1:floor(Int64, score*0.25)
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
    # 200 best
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

mutable struct Perm
  visits::Int
  perm::Vector{UInt16}
  # TODO: remove moves, not using it for anything
  moves::Vector{Move}
  moves_hash::UInt64
end

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

function main()
  perm_length = 46 * 46 * 4

  # initial_candidates_size = 40
  initial_candidates_size = 1
  candidates = []

  # hyper-parameters
  # 3 best
  num_modifications = 10
  # 4 best
  # 5 too low
  # back_accept = 4
  default_back_accept = 10
  # 2 best, 4 good, testing something higher, 10
  selection_skew = 4

  move_selection_skew = 1

  idle_reset = 10
  idle_reset_step_back = 10
  improvement_step_up = 10

  step_back_index_prune_size = 300_000
  step_back_index_prune_target_size = Int(step_back_index_prune_size * 0.66)

  score_multiplier = 2

  end_searched = Dict{UInt64,Bool}()
  end_search_interval = 10000



  for i in 1:initial_candidates_size

    perm = UInt16.(1:perm_length)
    shuffle!(perm)
    perm_moves, perm_moves_hash = eval_dna_and_hash(perm)
    perm_score = length(perm_moves)

    new_perm = Perm(
      0,
      perm,
      perm_moves,
      perm_moves_hash
    )

    push!(candidates,
      Candidate(
        0,
        [new_perm],
        Dict(perm_moves_hash => new_perm),
        Dict{UInt64,StepBackPack}(),
        perm_moves,
        perm_score,
        default_back_accept,
        0,
        0
      )
    )
  end

  iteration = 1
  last_debug_time = time()

  function selectByR(v::Vector, r::Float64)
    v[floor(Int, r*length(v))+1]
  end

  while true
    candidate_position = (iteration % length(candidates)) + 1
    candidate = candidates[candidate_position]

    candidate.visits += 1

    # weighted
    perm = selectByR(candidate.perms, rand()^selection_skew)
    perm_score = length(perm.moves)
    perm.visits += 1

    modifications = map(_ -> (dna_index(selectByR(perm.moves, rand()^move_selection_skew)), rand(1:perm_length)), 1:rand(1:num_modifications))


    for mod in modifications
      mod_a, mod_b = mod
      perm.perm[mod_a], perm.perm[mod_b] =
        perm.perm[mod_b], perm.perm[mod_a]
    end

    eval_moves, eval_moves_hash = eval_dna_and_hash(perm.perm)
    eval_score = length(eval_moves)

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
      candidates[candidate_position].max_moves = eval_moves
      candidates[candidate_position].index[eval_moves_hash] = new_perm

      println("$iteration. $perm_score ($(perm.visits)) -> $eval_score $(candidate.max_score) ###### $eval_score")
      candidate.idle_counter = 0
      candidate.back_accept = default_back_accept


    elseif eval_score >= (candidate.max_score - candidate.back_accept)

      if !is_in_index
        new_perm = Perm(
          0,
          copy(perm.perm),
          eval_moves,
          eval_moves_hash
        )

        candidate.index[eval_moves_hash] = new_perm
        push!(candidate.perms, new_perm)
        println("$iteration. $perm_score ($(perm.visits)) -> $eval_score $(candidate.max_score) i:$(length(candidate.index)) impr:$(candidate.improvement_counter)")

        perm.visits = 0
        candidate.idle_counter = max(0, candidate.idle_counter - 0.1)

        if eval_score > (candidate.max_score - candidate.back_accept)
          candidate.improvement_counter += 1
        end
      else
        current = candidate.index[eval_moves_hash]
        if length(current.moves) !== eval_score ||
           eval_moves_hash !== current.moves_hash
          println("shit")
          readline()
        end

        candidate.index[eval_moves_hash].perm = copy(perm.perm)
        candidate.index[eval_moves_hash].moves = copy(eval_moves)
      end

      # elseif eval_score >= (candidate.max_score - candidate.back_accept - 5) &&
      #        !haskey(candidate.step_back_index, eval_moves_hash) &&
      #        !is_in_index
      #   candidate.step_back_index[eval_moves_hash] = StepBackPack(eval_score, 0, eval_moves, iteration)
    end

    # if eval_moves_hash != perm.moves_hash
    #   if haskey(candidate.index, eval_moves_hash)
    #     p = candidate.index[eval_moves_hash]
    #     p.perm = copy(perm.perm)
    #   end
    # end

    if eval_moves_hash != perm.moves_hash
      for mod in reverse(modifications)
        mod_a, mod_b = mod
        perm.perm[mod_a], perm.perm[mod_b] =
          perm.perm[mod_b], perm.perm[mod_a]
      end
    end


    if iteration % end_search_interval == 0
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

        results = end_search(best.moves, 5)

        # println("$iteration. ES $(length(best.moves))")

        for (es_moves_hash, es_moves) in sort(collect(results), by=x -> length(x[2]))
          es_score = length(es_moves)
          # println("$(length(best.moves)) $es_score")

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

            println("$iteration. $(es_score) -> $( end_search_candidate.max_score) ###### $(end_search_candidate.max_score)")

            end_search_candidate.idle_counter = 0
            end_search_candidate.back_accept = default_back_accept

          elseif es_score >= (end_search_candidate.max_score - end_search_candidate.back_accept) && !is_in_index
            new_perm = Perm(
              0,
              generate_dna_all(es_moves),
              es_moves,
              es_moves_hash
            )
            push!(end_search_candidate.perms, new_perm)
            end_search_candidate.index[es_moves_hash] = new_perm

            end_search_candidate.idle_counter = max(0, end_search_candidate.idle_counter - 0.1)

            if es_score > (end_search_candidate.max_score - end_search_candidate.back_accept)
              end_search_candidate.improvement_counter += 1
            end

            println("$iteration. ES $(length(best.moves)) -> $es_score i:$(length(end_search_candidate.index))")

            #experimental
            # end_searched[es_moves_hash] = true
            # elseif es_score >= (end_search_candidate.max_score - end_search_candidate.back_accept - 5) &&
            #        !haskey(end_search_candidate.step_back_index, es_moves_hash) &&
            #        !is_in_index
            #   end_search_candidate.step_back_index[es_moves_hash] = StepBackPack(eval_score, 0, es_moves, iteration)
          end
        end

        end_searched[best.moves_hash] = true
      end

    end

    if iteration % 100000 == 0
      current_time = time()
      elapsed = current_time - last_debug_time


      # sort_fn =
      #   if (iteration ÷ 100000) % 3 == 0
      #     (p -> (-length(p.moves), p.visits))
      #   elseif (iteration ÷ 100000) % 3 == 1
      #     (p -> p.visits)
      #   else
      #     function (p)
      #       score = length(p.moves)
      #       # -(score - p.visits/(score * score_multiplier))
      #       exploitation = score
      #       exploration = score_multiplier * sqrt(log(iteration + 1) / p.visits)
      #       -(exploitation + exploration)
      #     end

      #   end
      # sort_fn =
      #   function (p)
      #     score = length(p.moves)
      #     -(score - p.visits/(score * score_multiplier))
      #   end


      for c in sort(candidates, by=(c -> c.max_score))


        # if length(c.step_back_index) >= step_back_index_prune_size
        #   items = collect(c.step_back_index)

        #   partialsort!(items, 1:step_back_index_prune_target_size;
        #     by=x -> x[2].score,
        #     rev=true
        #   )

        #   empty!(c.step_back_index)

        #   for (key, value) in @view items[1:step_back_index_prune_target_size]
        #     c.step_back_index[key] = value
        #   end
        # end

        # sanity on index
        # for (index_key, perm) in c.index
        #   test_moves, test_hash = eval_dna_and_hash(perm.perm)
        #   valid = index_key == perm.moves_hash &&
        #           test_hash == index_key

        #   if !valid
        #     print("shit $(index_key == perm.moves_hash) $(test_moves == perm.moves) $(test_hash == index_key)")
        #     println("$(length(test_moves)) $(length(perm.moves))")
        #     readline()
        #   end
        # end

        if c.improvement_counter >= improvement_step_up
          c.improvement_counter = 0
          c.idle_counter = 0

          c.back_accept = max(0, c.back_accept - 1)
          filter!(c.perms) do perm
            if length(perm.moves) < c.max_score - c.back_accept
              delete!(c.index, perm.moves_hash)
              # delete!(end_searched, perm.moves_hash)

              # c.step_back_index[perm.moves_hash] = StepBackPack(
              #   length(perm.moves),
              #   perm.visits,
              #   perm.moves,
              #   iteration
              # )

              false  # drop it from c.perms
            else
              true   # keep it
            end


          end
        end

        sort_fn =
          if (iteration ÷ 100000) % 4 == 0
            (p -> (-length(p.moves), p.visits))
          elseif (iteration ÷ 100000) % 4 == 1
            (p -> p.visits)
          elseif (iteration ÷ 100000) % 4 == 2
            function (p)
              score = length(p.moves)
              -(score - p.visits/(score * 1000))
            end
          else
            function (p)
              score = length(p.moves)

              # normalization 
              min_score = c.max_score - c.back_accept
              normalized_score = (score - min_score) / (c.max_score - min_score + 0.0001)
              exploitation = normalized_score
              exploration = sqrt(2) * sqrt(log(c.visits + 1) / p.visits)
              -(exploitation + exploration)
            end

          end

        sort!(c.perms, by=sort_fn)

        max_pack = generate_pack(c.max_moves)

        println("$iteration. $(c.max_score) >$(c.max_score - c.back_accept) $(round(elapsed, digits=2))s idle:$(round(c.idle_counter, digits=1)) i:$(length(c.index)) si:$(length(c.step_back_index)) impr:$(c.improvement_counter) $max_pack")



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

      last_debug_time = current_time

    end

    iteration += 1
  end
end

main()