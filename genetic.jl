import Base.hash
using Evolutionary
using Random
include("./morpion.jl")

function new_indvidual()
	return shuffle(UInt16(1):UInt16(46 * 46 * 4))
end

function score_individual(individual::Vector{UInt16})
	return length(eval_dna(individual))
end

function mutate!(individual::Vector{UInt16})
	# Get the length of the individual
	n = length(individual)

	# Randomly select two distinct indices
	idx1, idx2 = rand(1:n, 2)
	while idx1 == idx2
		idx2 = rand(1:n)
	end

	# Swap the elements at the selected indices
	individual[idx1], individual[idx2] = individual[idx2], individual[idx1]

	return individual
end

function order_crossover(parent1::Vector{UInt16}, parent2::Vector{UInt16})
	size = length(parent1)

	# Choose two random crossover points
	crossover_points = sort(rand(1:size, 2))
	start, stop = crossover_points[1], crossover_points[2]

	# Initialize offspring with placeholders
	offspring1 = fill(UInt16(0), size)
	offspring2 = fill(UInt16(0), size)

	# Copy the segment between the crossover points from each parent to the offspring
	offspring1[start:stop] .= parent1[start:stop]
	offspring2[start:stop] .= parent2[start:stop]

	# Helper function to fill the remaining positions
	function fill_remaining(offspring, parent, start, stop)
		current_pos = stop + 1
		for i in 1:size
			candidate = parent[(stop+i)%size+1]
			if !in(candidate, offspring)
				offspring[current_pos] = candidate
				current_pos = (current_pos % size) + 1
			end
		end
	end

	# Fill the remaining positions in the offspring
	fill_remaining(offspring1, parent2, start, stop)
	fill_remaining(offspring2, parent1, start, stop)

	return offspring1, offspring2
end

function roulette_wheel_selection(population, num_parents)
	total_fitness = sum(ind[2] for ind in population)
	selected_parents = []

	for _ in 1:num_parents
		pick = rand() * total_fitness
		current = 0.0
		for individual in population
			current += individual[2]
			if current > pick
				push!(selected_parents, individual[1])
				break
			end
		end
	end

	return selected_parents
end

function tournament_selection(population, num_parents, tournament_size)
	selected_parents = []

	for _ in 1:num_parents
		# Randomly select a subset of the population for the tournament
		tournament = rand(population, tournament_size)

		# Initialize variables to track the best individual
		best_individual = tournament[1]
		best_fitness = best_individual[2]

		# Iterate over the tournament to find the best individual
		for individual in tournament
			if individual[2] > best_fitness
				best_individual = individual
				best_fitness = individual[2]
			end
		end

		# Add the best individual to the selected parents
		push!(selected_parents, best_individual[1])
	end

	return selected_parents
end

function rank_based_selection(population, num_parents)
	sorted_population = sort(population, by = x -> x[2], rev = true)
	ranks = 1:length(sorted_population)
	total_rank = sum(ranks)
	selected_parents = []

	for _ in 1:num_parents
		pick = rand() * total_rank
		current = 0.0
		for (i, individual) in enumerate(sorted_population)
			current += ranks[i]
			if current > pick
				push!(selected_parents, individual[1])
				break
			end
		end
	end

	return selected_parents
end

function main()
	# Initialize
	population_size = 50
	population = [new_indvidual() for _ in 1:population_size]

	scored_individuals = map(individual -> (individual, score_individual(individual)), population)

	selected = tournament_selection(scored_individuals, 10, 10)

	println(map(score_individual, selected))

end



main()


# Define your score function
# function score_function(individual::Vector{UInt16})
# 	score = length(eval_dna(individual))
# 	return -score  # Negative because Evolutionary.jl minimizes by default
# end

# # Problem parameters
# const N_GENES = 46 * 46 * 4
# const BOUNDS = (1, N_GENES)

# # Custom mutation that preserves uniqueness
# function custom_mutation!(individual::Vector{UInt16}, bounds; rng = Random.GLOBAL_RNG, p = 0.1)
# 	for i in eachindex(individual)
# 		if rand(rng) < p
# 			new_value = rand(rng, UInt16(bounds[1]):UInt16(bounds[2]))
# 			while new_value in individual
# 				new_value = rand(rng, UInt16(bounds[1]):UInt16(bounds[2]))
# 			end
# 			individual[i] = new_value
# 		end
# 	end
# 	return individual
# end

# # Crossover function with rng parameter
# function custom_crossover(p1::Vector{UInt16}, p2::Vector{UInt16}; rng = Random.GLOBAL_RNG)
# 	n = length(p1)
# 	point = rand(rng, 1:n-1)

# 	# Initialize children as copies of parents
# 	c1 = copy(p1)
# 	c2 = copy(p2)

# 	# Create sets of available numbers for each child
# 	available1 = Set(p2)  # Numbers available for child 1
# 	available2 = Set(p1)  # Numbers available for child 2

# 	# Remove numbers that are already used in the first segment
# 	for i in 1:point
# 		delete!(available1, c1[i])
# 		delete!(available2, c2[i])
# 	end

# 	# Fill the remaining positions
# 	available1_array = collect(available1)
# 	available2_array = collect(available2)

# 	# Shuffle available numbers
# 	shuffle!(rng, available1_array)
# 	shuffle!(rng, available2_array)

# 	# Fill remaining positions
# 	for i in (point+1):n
# 		if !isempty(available1_array)
# 			c1[i] = pop!(available1_array)
# 		end
# 		if !isempty(available2_array)
# 			c2[i] = pop!(available2_array)
# 		end
# 	end

# 	return c1, c2
# end

# # Initialize a single valid individual
# function init_individual(bounds)
# 	return shuffle(UInt16.(bounds[1]:bounds[2]))
# end

# # Create a wrapper function for mutation that properly handles the rng parameter
# mutation_wrapper(x; rng = Random.GLOBAL_RNG) = custom_mutation!(x, BOUNDS; rng = rng)

# # Setup the optimization with corrected mutation function
# opt = GA(
# 	populationSize = 50,
# 	selection = rouletteinv,
# 	crossover = custom_crossover,
# 	mutation = mutation_wrapper,  # Use the wrapper function that handles rng
# 	crossoverRate = 0.7,
# 	mutationRate = 0.1,
# 	ε = 0.1,
# )

# # Create initial population
# initial_population = [init_individual(BOUNDS) for _ in 1:opt.populationSize]

# # Run the optimization
# result = Evolutionary.optimize(
# 	score_function,
# 	initial_population,
# 	opt,
# 	Evolutionary.Options(
# 		iterations = 100,
# 		store_trace = true,
# 		show_trace = true,
# 		show_every = 1,
# 	),
# )

# # Get the best solution
# best_individual = result.minimizer
# best_score = -result.minimum  # Convert back to positive score
# println("Best score found: $best_score")
# println("Best individual: $best_individual")