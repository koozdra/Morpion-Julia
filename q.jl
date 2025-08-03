import Base.hash
using Random
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


function main()

  test_make_and_remove_moves()
  # state_action_values = Dict{UInt64,Float64}()

  # bit_board = bit_board_build()

  # board = initial_board()
  # possible_moves = initial_moves()
  # made_moves = Move[]
  # current_state_hash = nothing

  # while !isempty(possible_moves)
  #   selected_move, value, next_move_hash = select_move(bit_board, state_action_values, possible_moves)

  #   push!(made_moves, selected_move)
  #   make_move(board, selected_move, possible_moves)
  #   bit_board_set_move!(selected_move, bit_board)

  #   if isnothing(current_state_hash)
  #     current_state_hash = next_move_hash
  #   else
  #     update_state_action_values!(state_action_values, 0.1, 0.9, current_state_hash, 1,)
  #   end
  # end

  # println("$(length(made_moves))")

  # for (i, move) in enumerate(initial_moves())
  #   value = find_move_value(bit_board_build(), state_action_values, move)
  #   println("[$i] $move $value")
  # end


end

main()
