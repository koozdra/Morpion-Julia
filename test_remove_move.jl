using Test
include("morpion.jl")

function test_remove_move_basic()
  board = initial_board()
  possible_moves = initial_moves()
  made_moves = Move[]

  # Make a move
  move = possible_moves[1]
  make_move(board, move, possible_moves)
  push!(made_moves, move)
  board_after = deepcopy(board)
  moves_after = deepcopy(possible_moves)

  # Remove the move
  remove_move(made_moves, possible_moves, board, move)
  @test board == initial_board()
  @test Set(possible_moves) == Set(initial_moves())
end

test_remove_move_basic()

function test_remove_move_cycle()
  board = initial_board()
  possible_moves = initial_moves()
  made_moves = Move[]
  states = []
  moves_states = []

  # Make 3 moves
  for i in 1:3
    move = possible_moves[1]
    push!(made_moves, move)
    push!(states, deepcopy(board))
    push!(moves_states, deepcopy(possible_moves))
    make_move(board, move, possible_moves)
  end

  # Remove moves in reverse order
  for i in 3:-1:1
    move = made_moves[i]
    remove_move(made_moves, possible_moves, board, move)
    @test board == states[i]
    @test Set(possible_moves) == Set(moves_states[i])
  end
end

test_remove_move_cycle()

function test_remove_move_random()
  board = initial_board()
  possible_moves = initial_moves()
  made_moves = Move[]
  states = []
  moves_states = []

  # Make random moves
  for i in 1:5
    move = rand(possible_moves)
    push!(made_moves, move)
    push!(states, deepcopy(board))
    push!(moves_states, deepcopy(possible_moves))
    make_move(board, move, possible_moves)
  end

  # Remove moves in reverse order
  for i in 5:-1:1
    move = made_moves[i]
    remove_move(made_moves, possible_moves, board, move)
    @test board == states[i]
    @test Set(possible_moves) == Set(moves_states[i])
  end
end

test_remove_move_random()

println("All remove_move unit tests passed.")
