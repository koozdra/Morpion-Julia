# Loose-move detection/removal and the library's end_search.

@testset "find_loose_moves and remove_move (evaluator API)" begin
  rng = MersenneTwister(31337)
  removed_any = 0
  for trial in 1:15
    evaluator = MorpionEvaluator()
    while !isempty(evaluator.possible_moves)
      make_move(evaluator, evaluator.possible_moves[rand(rng, 1:length(evaluator.possible_moves))])
    end

    loose = find_loose_moves(evaluator)
    isempty(loose) && continue

    for move in loose
      # independent check of "loose": no other move's line covers its point
      cover = 0
      for m in evaluator.morpion.moves
        dx, dy = direction_offset[m.direction]
        for i in 0:4
          if (Int(m.start_x) + dx * i, Int(m.start_y) + dy * i) == (Int(move.x), Int(move.y))
            cover += 1
          end
        end
      end
      @test cover == 1
    end

    move = loose[1]
    remove_move(evaluator, move)
    removed_any += 1

    @test !(move in evaluator.morpion.moves)
    # state must equal a from-scratch replay of the remaining moves
    board2, possible2 = replay(evaluator.morpion.moves)
    @test evaluator.board == board2
    @test Set(evaluator.possible_moves) == Set(possible2)
    @test Set(evaluator.possible_moves) == Set(rule_possible_moves(evaluator.morpion.moves))
  end
  @test removed_any > 0
end

@testset "remove_loose_moves leaves a valid partial game" begin
  rng = MersenneTwister(4242)
  for trial in 1:10
    evaluator = MorpionEvaluator()
    while !isempty(evaluator.possible_moves)
      make_move(evaluator, evaluator.possible_moves[rand(rng, 1:length(evaluator.possible_moves))])
    end
    full_score = score(evaluator.morpion)

    remove_loose_moves(evaluator)

    @test verify_partial(evaluator.morpion, evaluator.morpion)
    @test score(evaluator.morpion) <= full_score
    @test Set(evaluator.possible_moves) == Set(rule_possible_moves(evaluator.morpion.moves))
  end
end

@testset "library end_search returns valid nearby games" begin
  Random.seed!(2718)  # end_search draws from the global RNG
  base = Morpion(random_morpion())
  results = end_search(base, 3)
  @test results isa Vector{Morpion}
  for r in results
    @test (verify(r); true)
    @test score(r) >= score(base) - 10
  end
  @test issorted(results, by=score)
end
