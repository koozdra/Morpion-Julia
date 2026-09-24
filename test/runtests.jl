# Test suite for the morpion library and the population search driver.
# Run with:  julia --project=. test/runtests.jl

using Test
using Random
using DataStructures

# population.jl pulls in morpion.jl; its main() only runs when the file is the
# program entry point, so including it here just loads definitions.
include(joinpath(@__DIR__, "..", "population.jl"))

include("helpers.jl")

Random.seed!(20260912)

@testset "Morpion-Julia" begin
  @testset "engine" begin
    include("test_engine.jl")
  end
  @testset "encoding & hashing" begin
    include("test_encoding.jl")
  end
  @testset "dna" begin
    include("test_dna.jl")
  end
  @testset "end search & loose moves" begin
    include("test_end_search.jl")
  end
  @testset "end search recall vs ground truth" begin
    include("test_end_search_recall.jl")
  end
  @testset "population search driver" begin
    include("test_population.jl")
  end
  @testset "performance guardrails" begin
    include("test_perf.jl")
  end
end
