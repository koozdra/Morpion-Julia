# The forest search in forest.jl.

@testset "forest search keeps a consistent forest" begin
  Random.seed!(41)
  step = 2
  F = forest_search(max_seconds=Inf, max_iterations=30_000, roots=8, step=step, close_after=40,
    end_search_interval=1000, verbose=false)
  codec = PackCodec()
  @test length(F.index) == length(F.nodes)
  @test all(i -> F.index[F.nodes[i].perm.moves_hash] == i, eachindex(F.nodes))
  for (i, f) in enumerate(F.nodes)
    m = perm_moves(codec, f.perm)
    @test length(m) == f.perm.score
    @test points_hash(m) == f.perm.moves_hash
    @test lines_hash(m) == f.perm.lines_key
    @test f.best >= f.perm.score
    @test all(ch -> F.nodes[ch].parent == i && F.nodes[ch].root == f.root, f.children)
    @test all(ch -> F.nodes[ch].perm.score >= f.perm.score - step, f.children)   # useful children only
    @test all(ch -> f.best >= F.nodes[ch].best, f.children)
    f.dead && @test f.closed      # buried subtrees below their root's window need not be marked below the top
  end
  @test F.best == maximum(f.perm.score for f in F.nodes) == length(F.best_moves)
  @test alive_roots(F) >= 7                       # dead roots are replaced
  @test maximum(f.depth for f in F.nodes) >= 2    # trees grow below the roots
end

@testset "walk! takes unexplored options and skips dead subtrees" begin
  codec = PackCodec()
  F = Forest()
  g(seed) = eval_dna_and_hash(shuffle(MersenneTwister(seed), UInt16(1):UInt16(46 * 46 * 4)))
  m1, h1 = g(1); m2, h2 = g(2); m3, h3 = g(3)
  r1 = add_node!(F, Perm(codec, m1, h1), 0)
  r2 = add_node!(F, Perm(codec, m2, h2), 0)
  c1 = add_node!(F, Perm(codec, m3, h3), r1)
  @test F.nodes[r1].best == max(length(m1), length(m3))
  path = Int32[]
  close!(F, r2)                                   # a closed childless root is dead
  @test F.nodes[r2].dead
  for _ in 1:20
    v = walk!(F, path, 1.0)
    @test path[1] == r1                           # only live root
    backup!(F, path, 0.0)
  end
  close!(F, c1); close!(F, r1)
  @test F.nodes[r1].dead && walk!(F, path, 1.0) == 0
end
