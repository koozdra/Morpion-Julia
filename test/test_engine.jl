# Core rules: indexing, Move semantics, initial state, validate_line, and the
# incremental possible-move maintenance checked against reference oracles.

@testset "indexing" begin
  # board_index is a bijection from the 46×46 coordinate window onto 1:46²
  board_indices = [board_index(x, y) for x in -18:27 for y in -18:27]
  @test sort(board_indices) == collect(1:46*46)

  # dna_index is injective over the full window
  dna_indices = [dna_index(x, y, d) for x in -18:27 for y in -18:27 for d in 1:4]
  @test length(unique(dna_indices)) == length(dna_indices)

  # ...and stays within the dna array bounds for every geometrically feasible
  # move start (all five cells of the line inside the window)
  N = 46 * 46 * 4
  for d in 1:4
    dx, dy = direction_offset[d]
    for x in -18:27, y in -18:27
      feasible = -18 <= x + 4 * dx <= 27 && -18 <= y + 4 * dy <= 27
      feasible || continue
      @test 1 <= dna_index(x, y, d) <= N
    end
  end
end

@testset "Move semantics" begin
  a = Move(1, 2, 3, 4, 1)
  b = Move(1, 2, 3, 4, 1)
  c = Move(1, 2, 3, 4, 2)
  @test a == b
  @test isequal(a, b)
  @test a != c
  @test hash(a) == hash(b)
  @test hash(a, UInt(7)) == hash(b, UInt(7))

  # separately-constructed equal Moves behave as one key in Dicts and Sets
  d = Dict(a => 1)
  @test haskey(d, b)
  @test length(Set([a, b, c])) == 2

  # isless is a strict total order: irreflexive, antisymmetric, total
  rng = MersenneTwister(11)
  ms = [Move(rand(rng, -18:27), rand(rng, -18:27), rand(rng, -18:27), rand(rng, -18:27), rand(rng, 1:4)) for _ in 1:40]
  violations = 0
  for m1 in ms, m2 in ms
    if isless(m1, m2) && isless(m2, m1)
      violations += 1
    end
    if m1 != m2 && !isless(m1, m2) && !isless(m2, m1)
      violations += 1
    end
  end
  @test violations == 0
  @test issorted(sort(ms))
end

@testset "initial state" begin
  board = initial_board()
  @test board_points(board) == CROSS_POINTS
  @test length(board_points(board)) == 36

  moves0 = initial_moves()
  @test length(moves0) == 28
  @test length(Set(moves0)) == 28
  @test Set(scan_possible_moves(board)) == Set(moves0)
  @test Set(rule_possible_moves(Move[])) == Set(moves0)

  # fresh copies every call: mutating one must not leak into the next
  b2 = initial_board()
  b2[1] = 0xff
  @test initial_board()[1] != 0xff
end

@testset "validate_line acceptance cases" begin
  # plain case: four points and one empty cell, no existing line (ce=1, ca=4)
  board = zeros(UInt8, 46 * 46)
  for x in 0:3
    board[board_index(x, 0)] |= mask_x
  end
  @test validate_line(board, 0, 0, 2) == (4, 0)
  # shifted scan with two empty cells is rejected
  @test validate_line(board, 1, 0, 2) == ()

  # filling the empty cell leaves nothing to place
  board[board_index(4, 0)] |= mask_x
  @test validate_line(board, 0, 0, 2) == ()

  # touching rule: a new line may start at the endpoint of an existing
  # collinear line (ce=1, ca=3, cd=1 with the shared point at an end).
  # Existing line: (-4,0)..(0,0) in direction e; its new point was (0,0).
  board = zeros(UInt8, 46 * 46)
  for x in -4:-1
    board[board_index(x, 0)] |= mask_x
  end
  for x in -4:0
    board[board_index(x, 0)] |= mask_dir[2]
  end
  for x in 1:3
    board[board_index(x, 0)] |= mask_x
  end
  @test validate_line(board, 0, 0, 2) == (4, 0)

  # overlap: scanning from (-1,0) would reuse the segment (-1,0)-(0,0) of the
  # existing line, so it must be rejected
  @test validate_line(board, -1, 0, 2) == ()

  # bridging: a new line connecting the endpoints of two existing collinear
  # lines is legal (ce=1, ca=2, cd=2)
  board = zeros(UInt8, 46 * 46)
  for x in -4:0
    board[board_index(x, 0)] |= mask_dir[2]
  end
  for x in 4:8
    board[board_index(x, 0)] |= mask_dir[2]
  end
  for x in -4:-1
    board[board_index(x, 0)] |= mask_x
  end
  for x in 5:8
    board[board_index(x, 0)] |= mask_x
  end
  board[board_index(1, 0)] |= mask_x
  board[board_index(2, 0)] |= mask_x
  @test validate_line(board, 0, 0, 2) == (3, 0)
end

@testset "line_table lookup agrees with validate_line on every window" begin
  # make_move validates lines through line_empty's lookup table; validate_line
  # is the readable reference. Compare them at every in-bounds window of boards
  # sampled throughout random games.
  rng = MersenneTwister(97)
  mismatches = 0
  windows = 0
  for game in 1:20
    board = initial_board()
    possible = initial_moves()
    step = 0
    while !isempty(possible)
      move = possible[rand(rng, 1:length(possible))]
      make_move(board, move, possible)
      step += 1
      step % 5 == 0 || continue
      for direction in 1:4
        dx, dy = direction_offset[direction]
        for x in -12:21, y in -12:21
          expected = validate_line(board, x, y, direction)
          e = line_empty(board, board_index(x, y), direction)
          got = e < 0 ? () : (x + dx * e, y + dy * e)
          windows += 1
          got == expected || (mismatches += 1)
        end
      end
    end
  end
  @test windows > 100_000
  @test mismatches == 0
end

@testset "incremental possible-move list matches both oracles" begin
  rng = MersenneTwister(1234)
  for game in 1:10
    board = initial_board()
    possible = initial_moves()
    made = Move[]
    mismatches = 0
    while !isempty(possible)
      move = possible[rand(rng, 1:length(possible))]
      push!(made, move)
      make_move(board, move, possible)

      if length(Set(possible)) != length(possible) ||         # no duplicates
         Set(possible) != Set(scan_possible_moves(board)) ||  # full rescan
         Set(possible) != Set(rule_possible_moves(made))      # 5T rule oracle
        mismatches += 1
      end
    end
    @test mismatches == 0
    @test 20 <= length(made) <= 150
  end
end

@testset "values-tracking make_move (5-arg) stays in sync with the oracles" begin
  rng = MersenneTwister(4321)
  N = 46 * 46 * 4
  for game in 1:6
    dna = UInt16.(shuffle(rng, 1:N))
    board = initial_board()
    possible = initial_moves()
    values = UInt16[dna[dna_index(m)] for m in possible]
    made = Move[]
    mismatches = 0
    while !isempty(possible)
      move = possible[rand(rng, 1:length(possible))]
      push!(made, move)
      make_move(board, move, possible, values, dna)

      if length(values) != length(possible) ||
         any(values[i] != dna[dna_index(possible[i])] for i in eachindex(possible)) ||
         Set(possible) != Set(scan_possible_moves(board)) ||
         Set(possible) != Set(rule_possible_moves(made))
        mismatches += 1
      end
    end
    @test mismatches == 0
  end
end

@testset "remove_move inverts make_move (array API)" begin
  rng = MersenneTwister(42)
  for trial in 1:5
    board = initial_board()
    possible = initial_moves()
    made = Move[]
    board_states = Vector{UInt8}[]
    move_states = Vector{Move}[]
    while !isempty(possible)
      push!(board_states, copy(board))
      push!(move_states, copy(possible))
      move = possible[rand(rng, 1:length(possible))]
      push!(made, move)
      make_move(board, move, possible)
    end
    @test length(made) > 20
    while !isempty(made)
      i = length(made)
      move = made[end]
      remove_move(made, possible, board, move)
      @test board == board_states[i]
      @test Set(possible) == Set(move_states[i])
    end
    @test board == initial_board()
    @test Set(possible) == Set(initial_moves())
  end
end
