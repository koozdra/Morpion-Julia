import Base.hash
import Base.copy
include("morpion.jl")

type Searchy
	points_hash::UInt64
	score::Int32
	pack::String
	visits::Int32
	step_created::UInt32
	step_visited::UInt32
end

function Searchy(morpion::Morpion)
	Searchy(points_hash(morpion),score(morpion),generate_pack(morpion),0,0,0)
end

function isless(a::Searchy, b::Searchy)
	a.score < b.score
end

function run()

    step = 0
    max_score = 0
    max_pack = ""



    tic()

    while true

        searchy = Searchy(random_morpion())

    	if step % 1000 == 0
    		time = toq()
    		println("$(step). $(time)")
    		tic()
    	end

    	step += 1
    end

end

run()
