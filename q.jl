import Base.hash
using Random
using Statistics
include("morpion.jl")

function update_state_action_values!(state_action_values::Dict{UInt64,Float64}, alpha::Float64, gamma::Float64, state_hash::UInt64, reward::Float64, max_next_value::Float64)
  current_value = get(state_action_values, state_hash, 0.0)
  state_action_values[state_hash] = current_value + alpha * (reward + (gamma * (max_next_value)) - current_value)
end

function find_next_move_hash(bit_board::Array{UInt64,1}, move::Move)
  bit_board_set_move!(move, bit_board)
  next_move_hash = bit_board_hash(bit_board)
  bit_board_unset_move!(move, bit_board)
  next_move_hash
end

function find_move_value(bit_board::Array{UInt64,1}, state_action_values::Dict{UInt64,Float64}, move::Move)
  next_move_hash = find_next_move_hash(bit_board, move)
  (get(state_action_values, next_move_hash, 0.0), next_move_hash)
end

function find_moves_max_value(bit_board::Array{UInt64,1}, state_action_values::Dict{UInt64,Float64}, moves::Array{Move,1})
  best = nothing
  best_value = -Inf
  for move in moves
    value, hash = find_move_value(bit_board, state_action_values, move)
    if value > best_value
      best = (move, value, hash)
      best_value = value
    end
  end
  return best
end

function select_move(bit_board::Array{UInt64,1}, state_action_values::Dict{UInt64,Float64}, moves::Array{Move,1})
  explore = rand() > 0.9

  if explore
    move = rand(moves)
    value, next_move_hash = find_move_value(bit_board, state_action_values, move)
    return (move, value, next_move_hash)
  else
    best_idx = 0
    best_value = -Inf
    best_hash = 0
    for (i, move) in enumerate(moves)
      value, next_move_hash = find_move_value(bit_board, state_action_values, move)
      if value > best_value
        best_value = value
        best_hash = next_move_hash
        best_idx = i
      end
    end
    move = moves[best_idx]
    return (move, best_value, best_hash)
  end
end

function build_state_action_data(bit_board::Array{UInt64,1}, state_action_values::Dict{UInt64,Float64}, moves::Array{Move,1})
  results = [(move, next_move_hash, value) for move in moves for (value, next_move_hash) = [find_move_value(bit_board, state_action_values, move)]]
  max_tuple = reduce((a, b) -> a[3] > b[3] ? a : b, results)
  return (results, max_tuple)
end



function main(; alpha=0.2, gamma=0.7, exploration_rate=0.1, debug_interval=10000, max_iterations=0)
  state_action_values = Dict{UInt64,Float64}()
  iteration = 0
  max_score = 0
  recent_scores = []

  while max_iterations == 0 || iteration < max_iterations
    bit_board = bit_board_build()
    board = initial_board()
    possible_moves = initial_moves()
    made_moves = Move[]
    current_state_hash = nothing

    while !isempty(possible_moves)
      explore = rand() < exploration_rate
      state_values, max_state_value = build_state_action_data(bit_board, state_action_values, possible_moves)

      selected_move, next_move_hash, value =
        if explore
          rand(state_values)
        else
          max_state_value
        end

      # Q-learning update at each step
      if !isnothing(current_state_hash)
        reward = 1.0
        update_state_action_values!(state_action_values, alpha, gamma, current_state_hash, reward, value)
      end

      push!(made_moves, selected_move)
      make_move(board, selected_move, possible_moves)
      bit_board_set_move!(selected_move, bit_board)
      current_state_hash = next_move_hash
    end

    score = length(made_moves)
    max_score = max(max_score, score)
    # Always push score to recent_scores
    push!(recent_scores, score)
    if length(recent_scores) > 1000
      recent_scores = recent_scores[end-999:end]
    end
    if iteration > 0 && iteration % debug_interval == 0
      avg_score = mean(recent_scores)
      println("$iteration. S: $score | Max: $max_score | Avg(1k): $(round(avg_score, digits=2)) | Exp: $exploration_rate | α: $alpha | γ: $gamma")
      # for (i, move) in enumerate(initial_moves())
      #   value = find_move_value(bit_board_build(), state_action_values, move)
      #   println("[$i] $move $value")
      # end
    end
    iteration += 1
  end
  return max_score, recent_scores
end

# Higher-level function to test combinations of hyperparameters
function test_hyperparameters(hyperparam_grid; debug_interval=10000, max_iterations=10000)
  results = []
  for params in hyperparam_grid
    alpha = get(params, :alpha, 0.1)
    gamma = get(params, :gamma, 0.9)
    exploration_rate = get(params, :exploration_rate, 0.1)
    println("Testing: alpha=$alpha, gamma=$gamma, exploration_rate=$exploration_rate")
    max_score, scores = main(alpha=alpha, gamma=gamma, exploration_rate=exploration_rate, debug_interval=debug_interval, max_iterations=max_iterations)
    avg_score = isempty(scores) ? 0.0 : mean(scores)
    push!(results, (alpha=alpha, gamma=gamma, exploration_rate=exploration_rate, max_score=max_score, avg_score=avg_score))
  end
  # Sort results by max_score descending, then avg_score descending
  sorted_results = sort(results, by=r -> (-r.max_score, -r.avg_score))
  # Print results as a table
  println("\nHyperparameter Search Results:")
  println(rpad("alpha", 8), rpad("gamma", 8), rpad("explore", 10), rpad("max_score", 10), rpad("avg_score", 10))
  println(repeat("-", 46))
  for r in sorted_results
    println(rpad(string(r.alpha), 8), rpad(string(r.gamma), 8), rpad(string(r.exploration_rate), 10), rpad(string(r.max_score), 10), rpad(string(round(r.avg_score, digits=2)), 10))
  end
  return results
end

# Example usage:
# grid = [Dict(:alpha => a, :gamma => g, :exploration_rate => e)
#         for a in [0.01, 0.05, 0.1, 0.2],
#         g in [0.7, 0.8, 0.9, 0.95],
#         e in [0.01, 0.05, 0.1, 0.2]]
# results = test_hyperparameters(grid, max_iterations=500000)

# Hyperparameter Search Results:
# alpha   gamma   explore   max_score avg_score
# ----------------------------------------------
# 0.01    0.8     0.1       104       59.43
# 0.01    0.7     0.2       104       56.88
# 0.01    0.9     0.2       104       54.7
# 0.2     0.7     0.1       101       59.45

main()