include("morpion.jl")

function evaluate_model(model)
	possible_moves = initial_moves()
	board = initial_board()
	made_moves = Move[]

	while !isempty(possible_moves)
		move = reduce((a, b) -> (model[@inbounds dna_index(a)] > model[@inbounds dna_index(b)]) ? a : b, possible_moves)
		push!(made_moves, move)
		make_move(board, move, possible_moves)
	end

	(made_moves, length(made_moves))
end

function make_modification(model, modification)
	(index1, index2) = modification
	model[index1], model[index2] = model[index2], model[index1]
end

function reverse_modification(modification)
	(a, b) = modification
	(b, a)
end

function make_modifications(model, modifications)
	foreach(modification -> make_modification(model, modification), modifications)
end

function run()
	model = [UInt16(i) for i in 1:(46*46*4)]
	moves, score = evaluate_model(model)

	best_model, best_score, best_moves = model, score, moves


	println(best_score)

	iteration = 0
	t = time()

	while (true)
		modifications =
			[(dna_index(rand(moves)), rand(1:(46*46*4))),
				(dna_index(rand(moves)), rand(1:(46*46*4))),
				(dna_index(rand(moves)), rand(1:(46*46*4))),
			]
		make_modifications(model, modifications)
		eval_moves, eval_score = evaluate_model(model)
		eval_hash = points_hash(eval_moves)

		if (eval_score < score)
			make_modifications(model, reverse(map(reverse_modification, modifications)))
		elseif (eval_score == score)
			moves = eval_moves
		else
			moves = eval_moves
			score = eval_score

			println("$iteration. $score")
		end

		if iteration > 0 && iteration % 100000 == 0
			dt = time() - t

			println("$iteration. $score $(round(dt, digits=2))")

			t = time()
		end

		iteration += 1

	end

end


run()
