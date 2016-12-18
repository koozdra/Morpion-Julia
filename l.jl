import Base.hash
import Base.copy
include("morpion.jl")

type Searchy
	points_hash::Uint64
	score::Int32
	pack::String
	visits::Int32
	step_created::Uint32
	step_visited::Uint32
end

function Searchy(morpion::Morpion)
	Searchy(points_hash(morpion),score(morpion),generate_pack(morpion),0,0,0)
end

function isless(a::Searchy, b::Searchy)
	a.score < b.score
end

type Searcher
  step::Int64
  max_score::Int32 # being optimistic ;)
  max_pack::String
  index::Dict{Uint64,Searchy}
  searched::Dict{Uint64,Searchy}
  morpion_cache::Dict{Uint64,Morpion}
end

function Searcher()
  searcher = Searcher(0, 0, "", Dict{Uint64,Searchy}(), Dict{Uint64,Searchy}(), Dict{Uint64,Morpion}());
end

function init(searcher)
  searchy = Searchy(random_morpion())
  searcher.index[searchy.points_hash] = searchy
  searcher
end

function end_search(morpion)

end

function visit(searcher)
  if isEmpty(searcher.index)
    init(searcher)
  end

  # selection

  # modification

  # side effects

end

function run()
  searcher = Searcher()
  while true
    visit(searcher)
  end
end

run()
