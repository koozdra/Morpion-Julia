import Base.hash
include("morpion.jl")
using BenchmarkTools

# Array.from({length: 20}, (v, i) => [Math.random() * (0.9 - 0.5) + 0.5, Math.random() * (0.9 - 0.5) + 0.5, Math.random() * (0.9 - 0.5) + 0.5, Math.random() * (0.9 - 0.5) + 0.5])

function random_completion(
	board::Array{UInt8},
	possible_moves::Array{Move, 1},
	made_moves::Array{Move, 1},
)
	while !isempty(possible_moves)
		move = possible_moves[rand(1:end)]
		push!(made_moves, move)
		make_move(board, move, possible_moves)
	end

	made_moves
end

function search(state_values::Dict{UInt64, Float64}, search_state::SearchState)
	if !isempty(search_state.possible_moves)
		unvisited_move = nothing
		max_move = nothing
		max_move_value = 0
		bit_board = search_state.bit_board
		for move in search_state.possible_moves
			bit_board_set_move(move, bit_board)
			next_state = bit_board_hash(bit_board)
			if haskey(state_values, next_state)
				state_value = state_values[next_state]
				if (state_value > max_move_value)
					max_move_value = state_value
					max_move = move
				end
			else
				unvisited_move = move
			end
			bit_board_unset_move(move, bit_board)
		end



		# println("$unvisited_move")

		if unvisited_move !== nothing
			bit_board_set_move(unvisited_move, search_state.bit_board)
			push!(search_state.states, bit_board_hash(search_state.bit_board))
			push!(search_state.made_moves, unvisited_move)

			unvisited_move
		else

			max_move = if max_move == nothing || rand() < 0.1
				rand(search_state.possible_moves)
			else
				max_move
			end

			if max_move === nothing
				println("$(search_state.possible_moves)")
			end

			bit_board_set_move(max_move, search_state.bit_board)
			push!(search_state.states, bit_board_hash(search_state.bit_board))
			push!(search_state.made_moves, max_move)

			make_move(search_state.board, max_move, search_state.possible_moves)

			search(state_values, search_state)
		end
	else
		nothing
	end
end

function main()
	state_values = Dict{UInt64, Float64}()
	initial_state = bit_board_hash(bit_board_build())

	max_score = 0
	max_moves = Move[]
	t = time()

	for i in 1:1000000
		search_state = SearchState()
		search(state_values, search_state)

		# println(search_state.made_moves)
		# println(search_state.states)

		eval_moves = random_completion(search_state.board, search_state.possible_moves, search_state.made_moves)
		eval_score = length(eval_moves)

		if eval_score > max_score
			max_score = eval_score
			max_moves = eval_moves
		end

		for state in search_state.states
			if haskey(state_values, state)
				state_value = state_values[state]
				state_values[state] = state_value + (1 / 2) * (state_value - eval_score)
			else
				state_values[state] = eval_score
			end
		end

		if i % 10000 == 0
			println("$i. $max_score m:$(length(state_values))")
			t = time()
		end

		# println(eval_moves)
		# println(eval_score)
		# println("")
	end

	# Episode
	# Tree Traversal to a Leaf Node
	# bit_board = bit_board_build()
	# state = bit_board_hash(bit_board)

	# board = initial_board()
	# possible_moves = initial_moves()
	# made_moves = Move[]

	# unvisited_move = null
	# max_move = null
	# max_move_value = 0
	# for move in possible_moves
	# 	bit_board_set_move(move, bit_board)
	# 	next_state = bit_board_hash(bit_board)
	# 	if haskey(state_values, next_state)
	# 		state_value = state_values[next_state]
	# 		if (state_value > max_move_value)
	# 			max_move_value = state_value
	# 			max_move = move
	# 		end
	# 	else
	# 		unvisited_move = move
	# 	end
	# 	bit_board_unset_move(move, bit_board)
	# end

	# if unvisited_move
	# 	eval_board = copy(board)
	# 	eval_possible_moves = copy(possible_moves)
	# 	eval_made_moves = copy(made_moves)

	# 	make_move(eval_board, unvisited_move, eval_possible_moves)

	# 	while !isempty(eval_possible_moves)
	# 		random_possible_move = eval_possible_moves[rand(1:end)]
	# 		push!(eval_made_moves, random_possible_move)
	# 		make_move(eval_board, random_possible_move, eval_possible_moves)
	# 	end

	# 	eval_score = length(eval_made_moves)

	# 	state_values[next_state] = eval_score
	# 	eval_score

	# end

	# move = test_moves[2]
	# bit_board_set_move(move, bit_board)
	# push!(made_moves, move)
	# make_move(board, move, possible_moves)

	# move = test_moves[1]
	# bit_board_set_move(move, bit_board)
	# push!(made_moves, move)
	# make_move(board, move, possible_moves)

	# println(bit_board_hash(bit_board))

	# Leaf Evaluation

	# for i in 1:10

	# 	board = initial_board()
	# 	possible_moves = initial_moves()
	# 	made_moves = Move[]

	# 	while !isempty(possible_moves)
	# 		random_possible_move = possible_moves[rand(1:end)]
	# 		push!(made_moves, random_possible_move)
	# 		make_move(board, random_possible_move, possible_moves)
	# 	end

	# 	bit_board = bit_board_build()
	# 	println(hash(bit_board))


	# 	# println(bit_board)

	# 	for move in made_moves
	# 		bit_board_set_move(move, bit_board)
	# 	end

	# 	# println(bit_board)

	# 	println(length(made_moves))
	# 	println(hash(bit_board))


	# end
end

main()
