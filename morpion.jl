import Base.hash
import Base.copy
import Base.==
import Bits.bits

#  R  XXXX
#     X  X
#     X  X
#  XXXX  XXXX
#  X        x
#  X        x
#  XXXX  XXXX
#     X  X
#     X  X
#     XXXX
# R = (0,0)
struct Move
	x::Int8
	y::Int8
	start_x::Int8
	start_y::Int8
	#	ne => 1,
	#	e => 2,
	#	se => 3,
	#	s => 4
	direction::Int8
end

function move_equality(a::Move, b::Move)
	a.x == b.x && a.y == b.y && a.start_x == b.start_x && a.start_y == b.start_y && a.direction == b.direction
end
==(a::Move, b::Move) = move_equality(a::Move, b::Move)
isequal(a::Move, b::Move) = move_equality(a::Move, b::Move)




function hash(m::Move)
	hash((m.x, m.y, m.start_x, m.start_y, m.direction))
end

function isless(a::Move, b::Move)
	a.x < b.x || a.y < b.y || a.start_x < b.start_x || a.start_y < b.start_y || a.direction < b.direction
end

function copy(move::Move)
	Move(move.x, move.y, move.start_x, move.start_y, move.direction)
end

struct Morpion
	moves::Array{Move, 1}
end
Morpion() = Morpion([])

function copy(morpion::Morpion)
	Morpion(copy(morpion.moves))
end

function score(morpion::Morpion)
	length(morpion.moves)
end

function isless(a::Morpion, b::Morpion)
	score(a) < score(b)
end

@inline function board_index(x::Number, y::Number)
	(x + 18) * 46 + (y + 18)
end

@inline function dna_index(x::Number, y::Number, direction::Number)
	(x + 18) * 46 * 4 + (y + 18) * 4 + direction
end

@inline function dna_index(move::Move)
	dna_index(move.start_x, move.start_y, move.direction)
end

const direction_names = String["ne", "e", "se", "s"]
const direction_offset = [(1, -1) (1, 0) (1, 1) (0, 1)]
const mask_x = 0b00001
const mask_dir = [0b00010, 0b00100, 0b01000, 0b10000]

@inline function initial_moves()
	Move[
		Move(3, -1, 3, -1, 4),
		Move(6, -1, 6, -1, 4),
		Move(2, 0, 2, 0, 2),
		Move(7, 0, 3, 0, 2),
		Move(3, 4, 3, 0, 4),
		Move(7, 2, 5, 0, 3),
		Move(6, 4, 6, 0, 4),
		Move(0, 2, 0, 2, 4),
		Move(9, 2, 9, 2, 4),
		Move(-1, 3, -1, 3, 2),
		Move(4, 3, 0, 3, 2),
		Move(0, 7, 0, 3, 4),
		Move(5, 3, 5, 3, 2),
		Move(10, 3, 6, 3, 2),
		Move(9, 7, 9, 3, 4),
		Move(2, 2, 0, 4, 1),
		Move(2, 7, 0, 5, 3),
		Move(3, 5, 3, 5, 4),
		Move(6, 5, 6, 5, 4),
		Move(-1, 6, -1, 6, 2),
		Move(4, 6, 0, 6, 2),
		Move(3, 10, 3, 6, 4),
		Move(5, 6, 5, 6, 2),
		Move(10, 6, 6, 6, 2),
		Move(6, 10, 6, 6, 4),
		Move(2, 9, 2, 9, 2),
		Move(7, 9, 3, 9, 2),
		Move(7, 7, 5, 9, 1),
	]
end

# function generate_initial_moves()
# 	Move[
# 		Move(3, -1, 3, -1, 4),
# 		Move(6, -1, 6, -1, 4),
# 		Move(2, 0, 2, 0, 2),
# 		Move(7, 0, 3, 0, 2),
# 		Move(3, 4, 3, 0, 4),
# 		Move(7, 2, 5, 0, 3),
# 		Move(6, 4, 6, 0, 4),
# 		Move(0, 2, 0, 2, 4),
# 		Move(9, 2, 9, 2, 4),
# 		Move(-1, 3, -1, 3, 2),
# 		Move(4, 3, 0, 3, 2),
# 		Move(0, 7, 0, 3, 4),
# 		Move(5, 3, 5, 3, 2),
# 		Move(10, 3, 6, 3, 2),
# 		Move(9, 7, 9, 3, 4),
# 		Move(2, 2, 0, 4, 1),
# 		Move(2, 7, 0, 5, 3),
# 		Move(3, 5, 3, 5, 4),
# 		Move(6, 5, 6, 5, 4),
# 		Move(-1, 6, -1, 6, 2),
# 		Move(4, 6, 0, 6, 2),
# 		Move(3, 10, 3, 6, 4),
# 		Move(5, 6, 5, 6, 2),
# 		Move(10, 6, 6, 6, 2),
# 		Move(6, 10, 6, 6, 4),
# 		Move(2, 9, 2, 9, 2),
# 		Move(7, 9, 3, 9, 2),
# 		Move(7, 7, 5, 9, 1),
# 	]
# end
# cached_initial_moves = generate_initial_moves()
# function initial_moves()
# 	copy(cached_initial_moves)
# end


# this should really be handled through memoization
function generate_initial_board()
	board = zeros(UInt8, 46 * 46)

	# iterate over the
	for move in initial_moves()
		delta_x, delta_y = direction_offset[move.direction]

		for i in 0:4
			x = move.start_x + delta_x * i
			y = move.start_y + delta_y * i

			if x != move.x || y != move.y
				board[board_index(x, y)] = mask_x
			end
		end
	end
	board
end
initial_board_master = generate_initial_board();
function initial_board()
	copy(initial_board_master)
end


struct MorpionEvaluator
	morpion::Morpion
	possible_moves::Array{Move, 1}
	board::Array{UInt8, 1}
end

MorpionEvaluator() = MorpionEvaluator(Morpion(), initial_moves(), initial_board())

function morpion_evaluator(morpion::Morpion)
	evaluator = MorpionEvaluator()
	for move in morpion.moves
		make_move(evaluator, move)
	end

	evaluator
end

function copy(evaluator::MorpionEvaluator)
	MorpionEvaluator(copy(evaluator.morpion), copy(evaluator.possible_moves), copy(evaluator.board))
end

function random_completion(evaluator::MorpionEvaluator)
	while !isempty(evaluator.possible_moves)
		make_move(evaluator, evaluator.possible_moves[rand(1:length(evaluator.possible_moves))])
	end

	#@assert isempty(evaluator.possible_moves) "random completion has remnant possible moves"
end

function find_loose_moves(evaluator::MorpionEvaluator)
	loose_moves = Move[]

	points_board = zeros(UInt8, 46 * 46)

	for move in evaluator.morpion.moves
		board_value = evaluator.board[board_index(move.x, move.y)]
		#0b00010
		#0b00100
		#0b01000
		#0b10000
		if board_value == 2 ||
		   board_value == 4 ||
		   board_value == 8 ||
		   board_value == 16

			#println("$(move) $(board_value)")
			push!(loose_moves, move)

		end

		delta_x, delta_y = direction_offset[move.direction]

		for offset in 0:4
			curr_x = move.start_x + delta_x * offset
			curr_y = move.start_y + delta_y * offset

			points_board[board_index(curr_x, curr_y)] += 1
		end
	end

	filter!(loose_moves) do loose_move
		points_board[board_index(loose_move.x, loose_move.y)] == 1
	end

	loose_moves
end


function validate_line(board, x, y, direction)
	#println("evaluating: $x, $y, $(direction_names[direction])")


	move = ()

	delta_x, delta_y = direction_offset[direction]

	empty_x = 0
	empty_y = 0

	index_d = 0

	ca = 0
	ce = 0
	cd = 0

	for offset in 0:4

		curr_x = x + delta_x * offset
		curr_y = y + delta_y * offset

		empty = false
		available = false
		end_point = false


		#value = get(board, (curr_x, curr_y), 0)
		value = board[board_index(curr_x, curr_y)]

		empty = value == 0

		contains_direction = value & mask_dir[direction] != 0
		#before_contains_direction = get(board, (curr_x - delta_x, curr_y - delta_y), 0) & mask_dir[direction] != 0
		#after_contains_direction = get(board, (curr_x + delta_x, curr_y + delta_y), 0) & mask_dir[direction] != 0
		before_contains_direction = board[board_index(curr_x - delta_x, curr_y - delta_y)] & mask_dir[direction] != 0
		after_contains_direction = board[board_index(curr_x + delta_x, curr_y + delta_y)] & mask_dir[direction] != 0



		available = !empty && !contains_direction

		#end_point = contains_direction && (before_contains_direction || after_contains_direction) && !(before_contains_direction && after_contains_direction)
		end_point = contains_direction && (before_contains_direction || after_contains_direction) && !(before_contains_direction && after_contains_direction)

		if empty
			ce += 1
			empty_x = curr_x
			empty_y = curr_y
		elseif available
			ca += 1
		elseif end_point
			cd += 1
			index_d = offset
		end


		#println(" point: $curr_x, $curr_y ($(bits(value)))  $empty $available $end_point ($(before_contains_direction),$(after_contains_direction)))")

		if ce == 1 && ca == 3 && cd == 1 && (index_d == 0 || index_d == 4) ||
		   ce == 1 && ca == 4 ||
		   ce == 1 && ca == 2 && cd == 2

			#new_move = Move(empty_x, empty_y, move.x + delta_x * offset, move.y + delta_y * offset, direction)

			#if !in(new_move, possible_moves)
			#	push!(possible_moves, new_move)
			#	println("adding: $new_move")
			#end

			move = (empty_x, empty_y)
		end

	end

	#println()

	#corrolaries
	#	occupied = value & mask_x != 0
	#	contains_direction = board[x + 16, y + 16] & mask_dir[direction] != 0
	#	before_contains_direction = board[x - delta_x + 16, y - delta_x + 16] & mask_dir[direction] != 0
	#	after_contains_direction = board[x + delta_x + 16, y + delta_x + 16] & mask_dir[direction] != 0


	#state transition definitions definitions
	#	empty = value == 0
	#	available = occupied && !contains_direction
	#	end_point = contains_direction && (before_contains_direction || after_contains_direction)

	move
end


function update_board(board::Array{UInt8, 1}, move::Move)

	#board[board_index(move.x, move.y)] |= mask_x

	delta_x, delta_y = direction_offset[move.direction]

	for i in 0:4

		x = move.start_x + delta_x * i
		y = move.start_y + delta_y * i

		board[board_index(x, y)] |= mask_dir[move.direction]

	end
end


@inline function make_move(evaluator::MorpionEvaluator, move::Move)

	push!(evaluator.morpion.moves, move)
	make_move(evaluator.board, move, evaluator.possible_moves)

end

function remove_loose_moves(evaluator::MorpionEvaluator)
	loose_moves = find_loose_moves(evaluator)
	for move in loose_moves
		remove_move(evaluator, move)
	end
end


function verify_partial(morpion::Morpion, original::Morpion)

	evaluator = MorpionEvaluator()

	valid = true

	for move in morpion.moves

		#@assert in(move, evaluator.possible_moves) "$(morpion.moves)\n$(original.moves) verify_partial"

		valid = in(move, evaluator.possible_moves)

		if !valid
			return false
		end

		make_move(evaluator, move)


	end

	valid

end

function verify(morpion::Morpion)

	evaluator = MorpionEvaluator()

	for move in morpion.moves

		@assert in(move, evaluator.possible_moves)

		make_move(evaluator, move)

	end

	@assert isempty(evaluator.possible_moves)

end


function verify(morpion::Morpion, original::Morpion)

	evaluator = MorpionEvaluator()

	for move in morpion.moves

		@assert in(move, evaluator.possible_moves) "$(original.moves)\n$(morpion.moves) move not in possible moves"

		make_move(evaluator, move)

	end

	@assert isempty(evaluator.possible_moves) "$(original.moves) still possible moves left"

end

function verify(morpion::Morpion, original::Morpion, the::Morpion)

	evaluator = MorpionEvaluator()

	for move in morpion.moves

		@assert in(move, evaluator.possible_moves) "$(original.moves)\n$(morpion.moves) $(the.moves) move not in possible moves"

		make_move(evaluator, move)

	end

	@assert isempty(evaluator.possible_moves) "$(original.moves) still possible moves left"

end


function remove_move(evaluator::MorpionEvaluator, move::Move)

	# remove the move from the taken moves
	deleteat!(evaluator.morpion.moves, findfirst(evaluator.morpion.moves, move))

	# add the move to the list of possible moves
	push!(evaluator.possible_moves, move)

	# update the board to reflect the removal of the move
	evaluator.board[board_index(move.x, move.y)] &= ~mask_x

	delta_x, delta_y = direction_offset[move.direction]
	for i in 0:4
		x = move.start_x + delta_x * i
		y = move.start_y + delta_y * i
		#println("before ($x,$y): $(bits(evaluator.board[board_index(x,y)]))")
		evaluator.board[board_index(x, y)] &= ~mask_dir[move.direction]
		#println("after ($x,$y):  $(bits(evaluator.board[board_index(x,y)]))")
	end

	# it might be the case that this move shared an end point with another move's line.
	# since we updated the board for the full length of this move, we have to go back
	# and reactivate the board position for the point that was unintentially undone.


	# update the moves that might have been affected (must share direction)
	# (this could be more efficient but not too bad)
	for taken_move in evaluator.morpion.moves
		if move.direction == taken_move.direction
			update_board(evaluator.board, taken_move)
		end
	end

	# now that the move position is available we scan the rays
	# to find possible moves that were available at this point
	for direction in 1:4

		delta_x, delta_y = direction_offset[direction]

		#println(direction_names[direction])

		for offset in -4:0

			test_x = move.x + delta_x * offset
			test_y = move.y + delta_y * offset

			position = validate_line(evaluator.board, test_x, test_y, direction)

			if position != ()

				new_move = Move(position[1], position[2], test_x, test_y, direction)

				if !in(new_move, evaluator.possible_moves)

					push!(evaluator.possible_moves, new_move)
					#println("adding: $new_move")
				end
			end

		end
	end

	# it could be the case that when this move was made it removed an interesecting move outside of the rays
	# an extended search is required outside the bounds of the rays along the direction of the move
	delta_x, delta_y = direction_offset[move.direction]
	for offset in 1:3
		test_x = move.start_x + delta_x * offset
		test_y = move.start_y + delta_y * offset

		position = validate_line(evaluator.board, test_x, test_y, move.direction)

		if position != ()
			new_move = Move(position[1], position[2], test_x, test_y, move.direction)
			if !in(new_move, evaluator.possible_moves)

				push!(evaluator.possible_moves, new_move)
				#println("adding: $new_move")
			end
		end
	end

	for offset in 1:3
		test_x = move.start_x - delta_x * offset
		test_y = move.start_y - delta_y * offset

		position = validate_line(evaluator.board, test_x, test_y, move.direction)

		if position != ()
			new_move = Move(position[1], position[2], test_x, test_y, move.direction)
			if !in(new_move, evaluator.possible_moves)

				push!(evaluator.possible_moves, new_move)
				#println("adding: $new_move")
			end
		end
	end



	# we have to remove any moves that are no longer possible
	#filter!( (m::Move) -> validate_line(evaluator.board, m.start_x ,m.start_y , m.direction) != () , evaluator.possible_moves)

	filter!(evaluator.possible_moves) do m::Move
		t = validate_line(evaluator.board, m.start_x, m.start_y, m.direction) != ()

		if !t
			#println("removing: $(m)")
		end

		t
	end


end

@inline function make_move(board::Array{UInt8, 1}, move::Move, possible_moves::Array{Move, 1})


	#println("making: $move")


	#@assert in(move, possible_moves) "attempting to make move not in possible moves"

	update_board(board, move)

	#validate_line(board, move.start_x ,move.start_y , move.direction)


	# TODO can these be done with one filter operation?
	# EXPERIMENTAL
	# deleteat!(possible_moves, findfirst(possible_moves, move))
	filter!((move::Move) -> validate_line(board, move.start_x, move.start_y, move.direction) != (), possible_moves)


	for direction in 1:4

		delta_x, delta_y = direction_offset[direction]

		#println(direction_names[direction])

		for offset in -4:0

			test_x = move.x + delta_x * offset
			test_y = move.y + delta_y * offset

			position = validate_line(board, test_x, test_y, direction)

			if position != ()

				new_move = Move(position[1], position[2], test_x, test_y, direction)

				# TODO this in operation might be avoided if we use a set
				if !in(new_move, possible_moves)

					push!(possible_moves, new_move)
					#println("adding: $new_move")
				end
			end

		end
	end
end


function base64hex(char::Char)
	enc = 0

	if char >= 'A' && char <= 'Z'
		enc = char - 'A'
	elseif char >= 'a' && char <= 'z'
		enc = char - 'a' + 26
	elseif char >= '0' && char <= '9'
		enc = char - '0' + 52
	elseif char == '+'
		enc = 62
	elseif char == '/'
		enc = 63
	end

	bits(enc)[(end-5):end]
end

function pack_binary(moves::Array{Move, 1})
	b = ""

	#verify(Morpion(moves))

	taken_move_index = Dict{Move, Bool}()
	taboo_moves = Dict{Move, Bool}()
	possible_moves = initial_moves()
	board = initial_board()

	for move in moves
		taken_move_index[move] = true
	end

	while !isempty(possible_moves) && !isempty(taken_move_index)

		poss_moves = filter((possible_move::Move) -> !haskey(taboo_moves, possible_move), possible_moves)

		#@assert !isempty(poss_moves) "$(possible_moves)"

		sort!(poss_moves, by = (move::Move) -> (move.x, move.y, move.start_x, move.start_y, move.direction))

		for move in poss_moves

			if haskey(taken_move_index, move)
				b = string(b, "1")

				#push!(taken_moves,move)
				make_move(board, move, possible_moves)

				delete!(taken_move_index, move)

			else
				taboo_moves[move] = true
				b = string(b, "0")
			end
		end
	end

	b
end

function generate_pack(morpion::Morpion)

	b = pack_binary(morpion.moves)

	i = 1

	bin_pack = ""

	base64_enc_table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

	for pos in 1:6:length(b)

		hex = rpad(b[pos:min(length(b), pos + 5)], 6, "0")

		# index = parseint("0b"*hex) + 1
		index = parse(Int, "0b" * hex) + 1

		bin_pack *= string(base64_enc_table[index])
	end

	bin_pack
end

function unpack_pack(pack::String)
	b = ""

	for char in pack
		b = string(b, base64hex(char))
	end

	unpack_binary(b)

end

function unpack_binary(b::String)

	possible_moves = initial_moves()
	board = initial_board()

	taboo_moves = Dict{Move, Bool}()
	i = 1

	moves = Move[]

	sort!(possible_moves, by = (move::Move) -> (move.x, move.y, move.start_x, move.start_y, move.direction))

	while !isempty(possible_moves) && i <= length(b)

		#collect all possible moves that don't appear in the taboo list
		poss_moves = filter((possible_move::Move) -> !haskey(taboo_moves, possible_move), possible_moves)

		#@assert !isempty(poss_moves) "$(possible_moves)"

		#sort in a consistent manner
		sort!(poss_moves, by = (move::Move) -> (move.x, move.y, move.start_x, move.start_y, move.direction))

		for move in poss_moves
			if b[i] == '1'
				push!(moves, move)
				make_move(board, move, possible_moves)
			else
				taboo_moves[move] = true
			end
			i += 1
		end

	end

	moves

end

function unpack_binary(b::String)

	possible_moves = initial_moves()
	board = initial_board()

	taboo_moves = Dict{Move, Bool}()
	i = 1

	morpion = Morpion()

	sort!(possible_moves, by = (move::Move) -> (move.x, move.y, move.start_x, move.start_y, move.direction))

	while !isempty(possible_moves) && i <= length(b)

		#collect all possible moves that don't appear in the taboo list
		poss_moves = filter((possible_move::Move) -> !haskey(taboo_moves, possible_move), possible_moves)

		#@assert !isempty(poss_moves) "$(possible_moves)"

		#sort in a consistent manner
		sort!(poss_moves, by = (move::Move) -> (move.x, move.y, move.start_x, move.start_y, move.direction))

		for move in poss_moves
			if b[i] == '1'
				push!(morpion.moves, move)
				make_move(board, move, possible_moves)
			else
				taboo_moves[move] = true
			end
			i += 1
		end

	end

	morpion

end

@inline function generate_dna(moves::Array{Move, 1})
	morpion_dna = zeros(UInt8, 46 * 46 * 4)
	i = 0
	for move in moves
		morpion_dna[dna_index(move)] = length(moves) + 1 - i
		i += 1
	end

	morpion_dna
end

# add a dropout attribute that will randomely drop n elements
# to combine the generation and the modification step
function generate_move_preferances(moves::Array{Move, 1})
	Dict(move => UInt8(index) for (index, move) in enumerate(reverse(moves)))
end

function eval_move_preferences(preferences::Dict{Move, UInt8})
	board = initial_board()
	possible_moves = initial_moves()
	moves = Move[]

	function eval_reducer(a::Move, b::Move)
		a_value = haskey(preferences, a) ? preferences[a] : 0
		b_value = haskey(preferences, b) ? preferences[b] : 0

		if (a_value == 0 && b_value == 0)
			rand() > 0.5 ? a : b
		else
			a_value > b_value ? a : b
		end
	end

	while !isempty(possible_moves)
		# move = reduce( (a,b) -> (dna[dna_index(a)] > dna[dna_index(b)]) ? a : b, possible_moves)
		move = reduce(eval_reducer, possible_moves)
		push!(moves, move)
		make_move(board, move, possible_moves)
	end

	moves
end

# function generate_dna(morpion::Morpion)
# 	morpion_dna = rand(46*46*4)
# 	i = 0
# 	for move in morpion.moves
# 		morpion_dna[dna_index(move)] = length(morpion.moves) + 1 - i
# 		i += 1
# 	end

# 	morpion_dna
# end

# function eval_dna(dna::Array{Float64,1})
# 	board = initial_board()
# 	possible_moves = initial_moves()
# 	morpion = Morpion()

# 	while !isempty(possible_moves)
# 		move = reduce( (a,b) -> (dna[dna_index(a)] > dna[dna_index(b)]) ? a : b ,possible_moves)
# 		push!(morpion.moves, move)
# 		make_move(board, move, possible_moves)
# 	end

# 	morpion
# end


@inline function eval_dna(dna::Array{UInt8, 1})
	eval_dna(dna, initial_board(), initial_moves())
end


@inline function eval_dna(dna::Array{UInt8, 1}, board, possible_moves)
	# board = initial_board()
	# possible_moves = initial_moves()
	# morpion = Morpion()
	moves = Move[]

	function eval_reducer(a::Move, b::Move)
		a_value = dna[dna_index(a)]
		b_value = dna[dna_index(b)]

		if (a_value == 0 && b_value == 0)
			rand() > 0.5 ? a : b
		else
			a_value > b_value ? a : b
		end
	end

	while !isempty(possible_moves)
		# move = reduce( (a,b) -> (dna[dna_index(a)] > dna[dna_index(b)]) ? a : b, possible_moves)
		move = reduce(eval_reducer, possible_moves)
		push!(moves, move)
		make_move(board, move, possible_moves)
	end

	moves
end

function random_morpion()
	possible_moves = initial_moves()
	board = initial_board()
	taken_moves = Move[]

	while !isempty(possible_moves)
		move = possible_moves[rand(1:length(possible_moves))]
		push!(taken_moves, move)
		make_move(board, move, possible_moves)
	end

	# Morpion(taken_moves)
	taken_moves
end

function points_hash(morpion::Morpion)
	hash(sort(map((move) -> (move.x, move.y), morpion.moves)))
end

function points_hash(moves::Array{Move, 1})
	# dimitri
	board = zeros(Bool, 46 * 46)
	for move in moves
		board[board_index(move.x, move.y)] = true
	end
	hash(board)
	# hash(sort(map((move) -> (move.x, move.y), moves)))
end

function end_search(morpion::Morpion, trials::Number)
	evaluator = morpion_evaluator(copy(morpion))

	index = Dict{UInt64, Bool}()


	min_accept = score(morpion) - 10
	timeout = 30
	max_new_found = 20

	new_found_count = 0
	step = 0

	new_found = Morpion[]


	while score(evaluator.morpion) > score(morpion) / 2 && step < timeout && new_found_count < max_new_found

		#loose_moves = find_loose_moves(evaluator)

		# oh god
		#before = copy(evaluator.morpion)

		remove_loose_moves(evaluator)

		#@assert verify_partial(evaluator.morpion, morpion) "$(morpion.moves)\n$(before.moves)\n$(evaluator.morpion.moves)\n$(loose_moves)"

		i = 0
		while i < trials
			eva = copy(evaluator)
			random_completion(eva)

			#verify(eva.morpion, evaluator.morpion, morpion)

			phash = points_hash(eva.morpion)

			if !haskey(index, phash) && score(eva.morpion) >= min_accept
				index[phash] = true
				i = 0
				#experimental
				step = 0

				push!(new_found, eva.morpion)
				new_found_count += 1

			end
			i += 1
		end

		step += 1
	end

	sort(new_found, by = (t) -> score(t))
end

function to_js(morpion::Morpion)

	join(
		map(
			(move) -> "$(move.x),$(move.y),$(move.start_x),$(move.start_y),$(direction_names[move.direction])",
			morpion.moves,
		),
		"|",
	)

end
