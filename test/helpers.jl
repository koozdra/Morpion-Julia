# Shared helpers for the test suite: reference oracles and fixtures.

using Random

# The 36 points of the standard Morpion 5T starting cross, with R = (0, 0)
# matching the diagram at the top of morpion.jl.
const CROSS_POINTS = let
  pts = Tuple{Int,Int}[]
  for x in 3:6
    push!(pts, (x, 0))
    push!(pts, (x, 9))
  end
  for y in (1, 2, 7, 8), x in (3, 6)
    push!(pts, (x, y))
  end
  for y in (3, 6), x in vcat(0:3, 6:9)
    push!(pts, (x, y))
  end
  for y in (4, 5), x in (0, 9)
    push!(pts, (x, y))
  end
  Set(pts)
end

# All occupied points on a board (any bit set means a point exists there).
function board_points(board::Array{UInt8,1})
  Set((x, y) for x in -18:27 for y in -18:27 if board[board_index(x, y)] != 0)
end

# Full-rescan reference for the incrementally maintained possible-moves list:
# runs validate_line at every in-bounds (start, direction) on the board.
function scan_possible_moves(board::Array{UInt8,1})
  found = Move[]
  for direction in 1:4
    dx, dy = direction_offset[direction]
    for x in -18:27, y in -18:27
      in_bounds = true
      for o in -1:5
        cx, cy = x + dx * o, y + dy * o
        if cx < -18 || cx > 27 || cy < -18 || cy > 27
          in_bounds = false
          break
        end
      end
      in_bounds || continue
      position = validate_line(board, x, y, direction)
      if position != ()
        push!(found, Move(position[1], position[2], x, y, direction))
      end
    end
  end
  found
end

# Independent implementation of the 5T rule, from scratch: a move is a line of
# five consecutive grid points in one of the four directions where exactly one
# point is missing (the move's new point) and none of the line's four unit
# segments is used by an already-made move. Lines may share points (touching)
# but never segments. This never looks at the bitmask board, so it cross-checks
# both the board encoding and the incremental move maintenance.
function rule_possible_moves(made_moves::Vector{Move})
  points = Set{Tuple{Int,Int}}(CROSS_POINTS)
  segments = Set{Tuple{Int,Int,Int}}()
  for m in made_moves
    push!(points, (Int(m.x), Int(m.y)))
    dx, dy = direction_offset[m.direction]
    for i in 0:3
      push!(segments, (Int(m.start_x) + dx * i, Int(m.start_y) + dy * i, Int(m.direction)))
    end
  end

  x_lo, x_hi = extrema(p[1] for p in points)
  y_lo, y_hi = extrema(p[2] for p in points)

  found = Move[]
  for direction in 1:4
    dx, dy = direction_offset[direction]
    for sx in (x_lo-4):(x_hi+4), sy in (y_lo-4):(y_hi+4)
      cells = [(sx + dx * i, sy + dy * i) for i in 0:4]
      missing_cells = [c for c in cells if !(c in points)]
      length(missing_cells) == 1 || continue
      all(i -> !((sx + dx * i, sy + dy * i, direction) in segments), 0:3) || continue
      mx, my = missing_cells[1]
      push!(found, Move(mx, my, sx, sy, direction))
    end
  end
  found
end

# Play one random game to completion with the given RNG.
function random_game(rng::AbstractRNG)
  board = initial_board()
  possible = initial_moves()
  made = Move[]
  while !isempty(possible)
    move = possible[rand(rng, 1:length(possible))]
    push!(made, move)
    make_move(board, move, possible)
  end
  board, made
end

# Replay a move list from scratch, asserting each move is legal at its turn.
# Returns the resulting (board, possible_moves).
function replay(moves::Vector{Move})
  board = initial_board()
  possible = initial_moves()
  for m in moves
    @assert m in possible "replay: $m not legal at its turn"
    make_move(board, m, possible)
  end
  board, possible
end

# Exhaustive ground truth for end_search: from a `source` game, wind back the
# last `max_step_back` moves and enumerate EVERY distinct terminal position
# reachable by completing the shared prefix in all possible ways. Returns the
# set of points_hash values for completions scoring above
# length(source) - back_accept, plus a `capped` flag when the state cap was hit
# (then the set is only a lower bound and must not be used for completeness).
# This is a from-scratch reference — it shares no code with end_search beyond
# the move engine — so it can judge end_search's recall and soundness.
function enumerate_end_search_targets(source::Vector{Move}, max_step_back::Int,
  back_accept::Int; state_cap::Int=1_000_000)
  score = length(source)
  targets = Set{UInt64}()
  visited = Set{UInt64}()
  capped = Ref(false)

  function go(board, possible, made)
    capped[] && return
    h = hash(board)
    h in visited && return
    if length(visited) >= state_cap
      capped[] = true
      return
    end
    push!(visited, h)
    if isempty(possible)
      length(made) > score - back_accept && push!(targets, points_hash(made))
      return
    end
    for m in possible
      b2 = copy(board)
      p2 = copy(possible)
      make_move(b2, m, p2)
      go(b2, p2, vcat(made, m))
    end
  end

  board = initial_board()
  possible = initial_moves()
  prefix = source[1:(end-max_step_back)]
  for m in prefix
    make_move(board, m, possible)
  end
  go(board, possible, prefix)
  (targets, capped[])
end

# Games logged as `# score pack` comments at the top of population.jl.
const GOLDEN_PACKS = [
  (166, "HYhAHqWtBWCUVGkZRRxasI/rdT+39uUf9d22ap+y7/fX7/3+"),
  (170, "EykgD3IyGWSDsFAhMXIsPeav6+ju7V07eqfruddfv/nfO///6"),
  (171, "F0wgDolGsg5l0kkIno6jbiovx31/l5b3v42y8je9dvt2d//vvQ"),
  (172, "LBFEq2HLWWKB2qBilJqZcOZ3q+y/6xvzfetT91c3Tfv3/9/ae"),
  (172, "AENMhclbKcGxHhKhtGnBJdfX1DeJf7L6X+vt09fU7/Ptcv//va"),
  (175, "KyQihtyDUKLaq0EcpmqsRa/XuYvfN79c9T0t356/9+23fb5y/U"),
  (176, "LoyBD5plSCpD5FoFqixU76aU8b7m9+5k/s+X6en2739dr7/+34"),
  (177, "AYOOj1VpKGCndhSsQa1s+k3ft/usr69mLd/Su+3f+7Z9/+3u4"),
  (177, "FEBMv6lokkqKS4cwzBsf0ubovt9/yOd/M468fl18r1/el5/7/fA"),
  (177, "FEBMv6lokkiL84GQw9LndS5++33Kr9d8RvfNu/Nv/5zff/b3W"),
  (177, "FEBMv6lokkqKS4cwzB4f1Vc/fb7lr9d8RvfNu/Nv/p5vv/t7b"),
  (177, "CBMXT2TomgmTmJcpVpeTTr589vL/jW/hnms7Z3O29fu5ef9/3w"),
  (177, "IiAjf2jokjJLE4Zwyk4vWzYlXn77f1lf/be7tN7f/p5fv/t7X"),
  (177, "0yAij1VlSSRWksIzgzcN9Zbvzv7q16+0Hffl2P7f/K53f/fXdg"),
  (178, "0yAij1VlSSRWgtGcINgU4jPuvLppfb390rzecGjnu8r//rpv//b9"),
  (178, "7EBET5ZlRiSHYc0gSqEaxn9OfXDfr79Vak78WKOe7yv//Wm//9v0"),
]
