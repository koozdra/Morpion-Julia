# 166 HYhAHqWtBWCUVGkZRRxasI/rdT+39uUf9d22ap+y7/fX7/3+
# 170 Ey0gDuBpwaSCtRHDsNrbIXYUQ//n9ev7Ivz3VX37/5/rf//9
# 170 EykgD3IyGWSDsFAhMXIsPeav6+ju7V07eqfruddfv/nfO///6
# 170 qiQRjpmQsgU2CKFJbAAfUVaF5deL//zru/vbens3yfr31z+/trw
# 171 0yAij1VlSSRWksIzgzcdfpnkXTvX/Jn+meaz21Z+rf/1sX59/g
# 171 F0wgDolGsg5l0kkIno6jbiovx31/l5b3v42y8je9dvt2d//vvQ
# 172 AENMhclbKcGxHhKhtGnBJdfX1DeJf7L6X+vt09fU7/Ptcv//va
# 172 LBFEq2HLWWKB2qBilJqZcOZ3q+y/6xvzfetT91c3Tfv3/9/ae
# 172 UkiDTozaJmq4Mi4JQpJhYu3LPXzf7Tbzf1eV7+rOrb99//udfg
# 175 KyQihtyDUKLaq0EcpmqsRa/XuYvfN79c9T0t356/9+23fb5y/U
# 176 LoyBD5plSCpD5FoFqixU76aU8b7m9+5k/s+X6en2739dr7/+34
# 177 0yAij1VlSSRWksIzgzcN9Zbvzv7q16+0Hffl2P7f/K53f/fXdg
# 177 AYOOj1VpKGCndhSsQa0p/uNfNrf88av8Zs1nae523r93Hz/3++
# 177 AYOOj1VpKGCndhSsQa1s+k3ft/usr69mLd/Su+3f+7Z9/+3u4
# 177 CBMXT2TomgmTmJcpVpeTTr589vL/jW/hnms7Z3O29fu5ef9/3w
# 177 FEBMv6lokkiL84GQw9LndS5++33Kr9d8RvfNu/Nv/5zff/b3W
# 177 FEBMv6lokkqKS4cwzB4f1Vc/fb7lr9d8RvfNu/Nv/p5vv/t7b
# 177 FEBMv6lokkqKS4cwzBsf0ubovt9/yOd/M468fl18r1/el5/7/fA
# 177 IiAjf2jokjJLE4Zwyk4vWzYlXn77f1lf/be7tN7f/p5fv/t7X
# 178 0yAij1VlSSRWgtGcINgU4jPuvLppfb390rzecGjnu8r//rpv//b9
# 178 7EBET5ZlRiSHYc0gSqEaxn9OfXDfr79Vak78WKOe7yv//Wm//9v0

include("morpion.jl")
using Random
using DataStructures

function selectByR(v::Vector, r::Float64)
    v[floor(Int, r*length(v))+1]
end

function apply_swaps!(perm::Vector{UInt16}, swaps)
    for (a, b) in swaps
        perm[a], perm[b] = perm[b], perm[a]
    end
    perm
end

function revert_swaps!(perm::Vector{UInt16}, swaps)
    for (a, b) in reverse(swaps)
        perm[a], perm[b] = perm[b], perm[a]
    end
    perm
end

# A configuration's identity: the set of dots it placed (points hash, the
# default) or the set of lines it drew (lines = true). Several games draw the
# same dots with different lines; only the lines key tells them apart.
@inline move_key(m::Move, lines::Bool) =
    lines ? LINE_ZOBRIST[dna_index(m)] : points_zobrist[board_index(m.x, m.y)]
config_hash(moves::Vector{Move}, lines::Bool) = lines ? lines_hash(moves) : points_hash(moves)

# Winds back the last 1..step_back_fraction*score moves of `moves` and samples
# random completions from each prefix, until stall_cut_off completions in a row
# add nothing new (or index_cap results are collected). Returns every distinct
# completion scoring above score - back_accept, keyed by points hash (or by
# lines hash with lines = true).
function end_search(moves::Array{Move,1}, back_accept;
    step_back_fraction::Real=0.25, stall_cut_off::Int=200, index_cap::Int=1000, lines::Bool=false)
    score = length(moves)

    index = Dict{UInt64,Array{Move,1}}()

    # reusable per-completion buffers (contents are copied on accept)
    eval_board = zeros(UInt8, 46 * 46)
    eval_possible_moves = Move[]
    eval_made_moves = Move[]

    # Progressively wind back the moves taken on a board
    for step_back in 1:floor(Int64, score*step_back_fraction)
        # Make the subset of moves on the board
        # move_policy = OrderedDict{Move,Int32}()
        board = initial_board()
        possible_moves = initial_moves()
        made_moves = Move[]

        move_index = 1
        for move in moves[1:(end-step_back)]
            push!(made_moves, move)
            make_move(board, move, possible_moves)
            # move_policy[move] = score - move_index - 1
            # move_index += 1
        end

        # Perform a random completion from where the moves left off
        # Keep track of new configurations found and reset search timer if a new one is found
        no_new_index_counter = 0
        while no_new_index_counter <= stall_cut_off && length(index) < index_cap
            copyto!(eval_board, board)
            empty!(eval_possible_moves)
            append!(eval_possible_moves, possible_moves)
            empty!(eval_made_moves)
            append!(eval_made_moves, made_moves)

            eval_move_index = move_index

            while !isempty(eval_possible_moves)
                random_possible_move = eval_possible_moves[rand(1:end)]
                push!(eval_made_moves, random_possible_move)
                make_move(eval_board, random_possible_move, eval_possible_moves)
                # move_policy[random_possible_move] = eval_move_index
                # eval_move_index += 1
            end

            eval_score = length(eval_made_moves)
            eval_points_hash = config_hash(eval_made_moves, lines)

            if eval_score > score - back_accept && !haskey(index, eval_points_hash)
                index[eval_points_hash] = copy(eval_made_moves)
                no_new_index_counter = 0
            end

            no_new_index_counter += 1
        end
    end

    index
end

# One random completion from a checkpoint (board, possible moves, points hash of
# the moves so far, or lines hash with lines = true). Leaves the completion's
# own moves in `suffix` and returns the hash of the whole game.
function ucb_completion!(board, possible_moves, suffix, from_board, from_possible, h::UInt64, lines::Bool=false)
    copyto!(board, from_board)
    empty!(possible_moves)
    append!(possible_moves, from_possible)
    empty!(suffix)
    while !isempty(possible_moves)
        move = possible_moves[rand(1:end)]
        push!(suffix, move)
        make_move(board, move, possible_moves)
        h ⊻= move_key(move, lines)
    end
    h
end

# Move-average sampling (MAST) for end_search_ucb's completions: per line, the
# mean final game length of the completions that drew it. A MAST completion
# picks each move by a Gibbs distribution over those means (temperature tau);
# lines not seen yet count as good as the best seen.
mutable struct MASTStats
    sum::Vector{Float64}
    cnt::Vector{Float64}
    tau::Float64
    w::Vector{Float64}          # scratch for move weights
end

MASTStats(tau::Real=1.0) = MASTStats(zeros(46 * 46 * 4), zeros(46 * 46 * 4), tau, Float64[])

# ucb_completion! with MAST move choice; `base_len` is the length of the game
# before the completion. Updates the statistics with the finished game.
function mast_completion!(mast::MASTStats, board, possible_moves, suffix, from_board, from_possible,
    h::UInt64, base_len::Int, lines::Bool)
    copyto!(board, from_board)
    empty!(possible_moves)
    append!(possible_moves, from_possible)
    empty!(suffix)
    w = mast.w
    while !isempty(possible_moves)
        resize!(w, length(possible_moves))
        qmax = -Inf
        @inbounds for i in eachindex(possible_moves)
            c = dna_index(possible_moves[i])
            w[i] = mast.cnt[c] > 0 ? mast.sum[c] / mast.cnt[c] : NaN
            isnan(w[i]) || (qmax = max(qmax, w[i]))
        end
        z = 0.0
        @inbounds for i in eachindex(possible_moves)
            w[i] = exp((isnan(w[i]) || qmax == -Inf ? 0.0 : w[i] - qmax) / mast.tau)
            z += w[i]
        end
        r = rand() * z
        i = 1
        @inbounds while i < length(possible_moves) && r > w[i]
            r -= w[i]
            i += 1
        end
        move = possible_moves[i]
        push!(suffix, move)
        make_move(board, move, possible_moves)
        h ⊻= move_key(move, lines)
    end
    final = base_len + length(suffix)
    @inbounds for m in suffix
        c = dna_index(m)
        mast.sum[c] += final
        mast.cnt[c] += 1
    end
    h
end

# end_search variant that treats each wind-back depth as a bandit arm. The game
# is replayed once, keeping the position before each of its last
# step_back_fraction*score moves; one pull of an arm is one random completion
# from that position, rewarded when it finds a new point set scoring above
# score - back_accept. Arms are picked by UCB1 on reward per pull, so rollouts
# go to the depths that are still turning up new completions instead of a
# fixed stall per depth. Stops once stall_rollouts average completions' worth of
# moves in a row find nothing new (or index_cap results are collected).
# Returns the same kind of index as end_search (lines = true keys it by lines).
# mast = true draws completions with move-average sampling (see MASTStats)
# instead of uniformly.
function end_search_ucb(moves::Array{Move,1}, back_accept;
    step_back_fraction::Real=0.25, stall_rollouts::Int=2000, index_cap::Int=1000,
    exploration::Real=0.1, warmup::Int=2, lines::Bool=false, mast::Bool=false)
    score = length(moves)
    depth = floor(Int, score * step_back_fraction)
    index = Dict{UInt64,Array{Move,1}}()
    depth < 1 && return index

    # checkpoint k: the position before the last k moves, and its points hash
    boards = Vector{Vector{UInt8}}(undef, depth)
    possibles = Vector{Vector{Move}}(undef, depth)
    prefix_hashes = zeros(UInt64, depth)
    board = initial_board()
    possible_moves = initial_moves()
    h = UInt64(0)
    for (i, move) in enumerate(moves)
        k = score - i + 1
        if k <= depth
            boards[k] = copy(board)
            possibles[k] = copy(possible_moves)
            prefix_hashes[k] = h
        end
        make_move(board, move, possible_moves)
        h ⊻= move_key(move, lines)
    end

    rewards = zeros(Int, depth)
    pulls = zeros(Int, depth)
    # per arm, kept current as it is pulled: mean reward and 1/sqrt(pulls)
    means = zeros(depth)
    inv_sqrt_pulls = zeros(depth)
    total_pulls = 0
    total_moves = 0
    moves_since_new = 0

    eval_board = zeros(UInt8, 46 * 46)
    eval_possible_moves = Move[]
    eval_suffix = Move[]
    stats = mast ? MASTStats() : nothing

    k = 0
    while true
        if total_pulls < warmup * depth
            k = total_pulls % depth + 1
        else
            (length(index) < index_cap &&
                moves_since_new < stall_rollouts * total_moves / total_pulls) || break
            bonus = exploration * sqrt(log(total_pulls))
            best_value = -Inf
            for a in 1:depth
                value = means[a] + bonus * inv_sqrt_pulls[a]
                if value > best_value
                    best_value = value
                    k = a
                end
            end
        end

        h = stats === nothing ?
            ucb_completion!(eval_board, eval_possible_moves, eval_suffix,
                boards[k], possibles[k], prefix_hashes[k], lines) :
            mast_completion!(stats, eval_board, eval_possible_moves, eval_suffix,
                boards[k], possibles[k], prefix_hashes[k], score - k, lines)
        played = length(eval_suffix)
        found = score - k + played > score - back_accept && !haskey(index, h)
        found && (index[h] = vcat(moves[1:(score-k)], eval_suffix))

        rewards[k] += found
        pulls[k] += 1
        means[k] = rewards[k] / pulls[k]
        inv_sqrt_pulls[k] = 1 / sqrt(pulls[k])
        total_pulls += 1
        total_moves += played
        moves_since_new = found ? 0 : moves_since_new + played
    end

    index
end

# end_search by nested rollout policy adaptation (NRPA). Each run steps back to
# a random depth (a fraction of the source's length drawn from depth_range) and
# searches from there to the end of the game: level-0 searches are playouts
# whose moves are drawn by a softmax over per-line weights; a level-n search
# runs `iterations` level-(n-1) searches, each time moving the weights towards
# the best sequence found so far. The weights start `warm` adaptation steps
# towards the source's own continuation, so playouts begin near it. Runs repeat
# until `budget_s` seconds are spent. Returns every distinct completion seen
# that scores above length(moves) - back_accept, keyed like end_search.
mutable struct NRPARun
    root_board::Vector{UInt8}
    root_possible::Vector{Move}
    root_hash::UInt64
    prefix::Vector{Move}        # the source's moves before the root
    floor_score::Int
    lines::Bool
    board::Vector{UInt8}        # scratch
    possible::Vector{Move}
    weights::Vector{Float64}    # scratch for playout probabilities
    results::Dict{UInt64,Vector{Move}}
    deadline::Float64
end

function nrpa_playout!(run::NRPARun, policy::Vector{Float64})
    board = run.board
    possible = run.possible
    copyto!(board, run.root_board)
    empty!(possible)
    append!(possible, run.root_possible)
    seq = Move[]
    h = run.root_hash
    w = run.weights
    while !isempty(possible)
        resize!(w, length(possible))
        z = 0.0
        @inbounds for i in eachindex(possible)
            w[i] = exp(policy[dna_index(possible[i])])
            z += w[i]
        end
        r = rand() * z
        i = 1
        @inbounds while i < length(possible) && r > w[i]
            r -= w[i]
            i += 1
        end
        m = possible[i]
        push!(seq, m)
        make_move(board, m, possible)
        h ⊻= move_key(m, run.lines)
    end
    if length(run.prefix) + length(seq) > run.floor_score && !haskey(run.results, h)
        run.results[h] = vcat(run.prefix, seq)
    end
    seq
end

# A copy of `policy` moved towards `seq` (replayed from the root): +alpha on
# each chosen move, -alpha times its softmax probability on every legal move.
function nrpa_adapt(run::NRPARun, policy::Vector{Float64}, seq::Vector{Move}; alpha::Float64=1.0)
    adapted = copy(policy)
    board = run.board
    possible = run.possible
    copyto!(board, run.root_board)
    empty!(possible)
    append!(possible, run.root_possible)
    for m in seq
        z = 0.0
        @inbounds for p in possible
            z += exp(policy[dna_index(p)])
        end
        @inbounds for p in possible
            c = dna_index(p)
            adapted[c] -= alpha * exp(policy[c]) / z
        end
        adapted[dna_index(m)] += alpha
        make_move(board, m, possible)
    end
    adapted
end

function nrpa_level(run::NRPARun, level::Int, policy::Vector{Float64}, iterations::Int)
    level == 0 && return nrpa_playout!(run, policy)
    best = Move[]
    for _ in 1:iterations
        seq = nrpa_level(run, level - 1, policy, iterations)
        length(seq) >= length(best) && (best = seq)
        policy = nrpa_adapt(run, policy, best)
        time() > run.deadline && break
    end
    best
end

function end_search_nrpa(moves::Array{Move,1}, back_accept;
    level::Int=2, iterations::Int=20, warm::Int=3, depth_range=(0.05, 0.5),
    budget_s::Real=0.006, lines::Bool=false)
    score = length(moves)
    results = Dict{UInt64,Array{Move,1}}()
    deadline = time() + budget_s
    while true
        fraction = depth_range[1] + rand() * (depth_range[2] - depth_range[1])
        depth = clamp(floor(Int, score * fraction), 1, score)
        board = initial_board()
        possible = initial_moves()
        h = UInt64(0)
        for m in moves[1:score-depth]
            make_move(board, m, possible)
            h ⊻= move_key(m, lines)
        end
        run = NRPARun(board, possible, h, moves[1:score-depth], score - back_accept, lines,
            zeros(UInt8, 46 * 46), Move[], Float64[], results, deadline)
        policy = zeros(46 * 46 * 4)
        continuation = moves[score-depth+1:end]
        for _ in 1:warm
            policy = nrpa_adapt(run, policy, continuation)
        end
        nrpa_level(run, level, policy, iterations)
        time() > deadline && break
    end
    results
end

# DNA for a perm stored as moves only (main's dna_storage=:moves), written into
# `dna`: a fixed random base permutation rotated by the perm's points hash (so
# perms don't all share one ordering of their unplayed moves), with the played
# moves given the highest values in game order, so the greedy rollout replays
# `moves` exactly.
function dna_from_moves!(dna::Vector{UInt16}, base::Vector{UInt16}, moves::Vector{Move}, h::UInt64)
    N = length(base)
    r = Int(h % UInt64(N))
    copyto!(dna, 1, base, r + 1, N - r)
    copyto!(dna, N - r + 1, base, 1, r)
    L = length(moves)
    @inbounds for (i, m) in enumerate(moves)
        dna[dna_index(m)] = UInt16(N + L - i + 1)
    end
    dna
end

# Packed storage (main's dna_storage=:pack): a game is stored as the decisions
# of a canonical replay, the scheme generate_pack uses. Repeatedly take the
# possible moves not yet rejected, sorted by (dot, line); for each, one bit says
# whether the game plays it (it is played) or not (it is rejected for good).
# About 1.7 bits per move. Decoding replays the game in that canonical order,
# so the original move order is lost; only the set of lines survives.
const PACK_N = 46 * 46 * 4
pack_key(m::Move) = board_index(m.x, m.y) * PACK_N + dna_index(m)

mutable struct PackCodec
    board::Vector{UInt8}
    possible::Vector{Move}
    round::Vector{Move}
    bits::Vector{Bool}
    in_game::Vector{UInt32}   # stamp: this dna index is a move of the game being encoded
    rejected::Vector{UInt32}  # stamp: rejected in this encode/decode
    stamp::UInt32
end

PackCodec() = PackCodec(zeros(UInt8, 46 * 46), Move[], Move[], Bool[], zeros(UInt32, PACK_N), zeros(UInt32, PACK_N), 0)

function pack_reset!(c::PackCodec)
    c.stamp += 1
    copyto!(c.board, initial_board_master)
    empty!(c.possible)
    append!(c.possible, initial_moves_master)
    c.stamp
end

# the possible moves not rejected so far, in canonical order
function pack_round!(c::PackCodec, st)
    empty!(c.round)
    @inbounds for m in c.possible
        c.rejected[dna_index(m)] != st && push!(c.round, m)
    end
    # insertion sort: rounds are ~15 moves, and sort! with a key allocates
    r = c.round
    @inbounds for i in 2:length(r)
        m = r[i]
        k = pack_key(m)
        j = i - 1
        while j >= 1 && pack_key(r[j]) > k
            r[j+1] = r[j]
            j -= 1
        end
        r[j+1] = m
    end
    r
end

function pack_encode(c::PackCodec, moves::Vector{Move})
    st = pack_reset!(c)
    @inbounds for m in moves
        c.in_game[dna_index(m)] = st
    end
    remaining = length(moves)
    empty!(c.bits)
    while remaining > 0
        round = pack_round!(c, st)
        isempty(round) && error("pack_encode: not a valid game")
        @inbounds for m in round
            i = dna_index(m)
            if c.in_game[i] == st
                push!(c.bits, true)
                make_move(c.board, m, c.possible)
                c.in_game[i] = 0
                remaining -= 1
                remaining == 0 && break
            else
                push!(c.bits, false)
                c.rejected[i] = st
            end
        end
    end
    nb = length(c.bits)
    out = zeros(UInt8, 2 + cld(nb, 8))
    out[1] = nb & 0xff
    out[2] = nb >> 8
    @inbounds for k in 1:nb
        c.bits[k] && (out[2+((k-1)>>3)+1] |= 0x01 << ((k - 1) & 7))
    end
    out
end

# Decodes `pack` into `out` (cleared first) in canonical order.
function pack_decode!(c::PackCodec, out::Vector{Move}, pack::Vector{UInt8})
    st = pack_reset!(c)
    empty!(out)
    nb = Int(pack[1]) | Int(pack[2]) << 8
    k = 0
    while k < nb
        round = pack_round!(c, st)
        @inbounds for m in round
            bit = (pack[2+(k>>3)+1] >> (k & 7)) & 0x01 == 0x01
            k += 1
            if bit
                push!(out, m)
                make_move(c.board, m, c.possible)
            else
                c.rejected[dna_index(m)] = st
            end
            k == nb && break
        end
    end
    out
end

# identifies a game's set of lines (unlike points_hash, which only sees dots)
const LINE_ZOBRIST = rand(Random.Xoshiro(0x6c696e6573), UInt64, PACK_N)
lines_hash(moves::Vector{Move}) = reduce(⊻, (LINE_ZOBRIST[dna_index(m)] for m in moves); init=UInt64(0))

const EMPTY_MOVES = Move[]       # shared by every packed perm; never mutated
const EMPTY_PACK = UInt8[]

mutable struct Perm
    visits::Int
    perm::Vector{UInt16}
    # TODO: remove moves, not using it for anything
    moves::Vector{Move}
    moves_hash::UInt64
    # checkpoints of the game `perm` plays, built once the perm has been picked
    # cache_min_picks times in the current print interval; `valid` is cleared
    # whenever `perm` changes to a dna whose game differs
    cache::Union{Nothing,EvalCache}
    # picks in the current print interval (`pick_window` = iteration ÷ print_interval)
    window_picks::Int
    pick_window::Int
    # game length, kept separately because packed perms have no moves vector
    score::Int
    # the packed game under dna_storage=:pack (EMPTY_PACK otherwise)
    pack::Vector{UInt8}
    # slot of its decoded moves in the DecodeCache (0 = not cached)
    slot::Int
end

Perm(visits, perm, moves, moves_hash) = Perm(visits, perm, moves, moves_hash, nothing, 0, -1, length(moves), EMPTY_PACK, 0)

# Decoded moves of recently picked packed perms (dna_storage=:pack), in a fixed
# number of reusable slots with CLOCK replacement (an approximation of LRU: a
# hit marks its slot recently used; a miss advances the hand past recently used
# slots, clearing their marks, and evicts the first one that isn't).
mutable struct DecodeCache
    slots::Vector{Vector{Move}}
    owner::Vector{Union{Nothing,Perm}}
    used::Vector{Bool}
    hand::Int
    hits::Int
    misses::Int
end

DecodeCache(n::Int) = DecodeCache([Move[] for _ in 1:n], Vector{Union{Nothing,Perm}}(nothing, n), fill(false, n), 1, 0, 0)

# The decoded moves of packed perm p, from the cache or decoded into a slot.
# The returned vector belongs to the cache: read it, don't keep it.
function cached_moves!(dc::DecodeCache, codec::PackCodec, p::Perm)
    s = p.slot
    if s > 0 && dc.owner[s] === p
        dc.used[s] = true
        dc.hits += 1
        return dc.slots[s]
    end
    dc.misses += 1
    n = length(dc.slots)
    while dc.used[dc.hand]
        dc.used[dc.hand] = false
        dc.hand = dc.hand % n + 1
    end
    s = dc.hand
    old = dc.owner[s]
    old === nothing || (old.slot = 0)
    dc.owner[s] = p
    dc.used[s] = true
    p.slot = s
    dc.hand = s % n + 1
    pack_decode!(codec, dc.slots[s], p.pack)
end

# Forgets p's cached moves (its pack changed).
function uncache!(dc::DecodeCache, p::Perm)
    s = p.slot
    if s > 0 && dc.owner[s] === p
        dc.owner[s] = nothing
        dc.used[s] = false
    end
    p.slot = 0
end

mutable struct Candidate
    visits::Int
    perms::Vector{Perm}
    index::Dict{UInt64,Perm}
    max_moves::Vector{Move}
    max_score::Int
    back_accept::Int
    idle_counter::Float64
    improvement_counter::Int
    # perms dropped by pruning, kept (up to main's archive_size, best scores
    # first) so a later widening of the window can put them back
    archive::Vector{Perm}
end

Candidate(visits, perms, index, max_moves, max_score, back_accept, idle_counter, improvement_counter) =
    Candidate(visits, perms, index, max_moves, max_score, back_accept, idle_counter, improvement_counter, Perm[])

# Tighten back_accept by one and drop every perm (and its index entry) that
# falls below the new acceptance window.
function prune_candidate!(c::Candidate; archive_size::Int=0)
    c.improvement_counter = 0
    c.idle_counter = 0

    c.back_accept = max(0, c.back_accept - 1)
    prune_below!(c; archive_size=archive_size)
end

# Drops (and archives, up to archive_size) every perm below the current window
# max_score - back_accept.
function prune_below!(c::Candidate; archive_size::Int=0)
    filter!(c.perms) do perm
        if perm.score < c.max_score - c.back_accept
            delete!(c.index, perm.moves_hash)
            if archive_size > 0
                perm.cache = nothing   # a checkpoint cache is ~94 KB; rebuilt if it returns
                push!(c.archive, perm)
            end
            false  # drop it from c.perms
        else
            true   # keep it
        end
    end

    if length(c.archive) > archive_size
        # keep the best scores; among equal scores, the most recently pruned
        reverse!(c.archive)
        sort!(c.archive, by=p -> -p.score)   # stable
        resize!(c.archive, archive_size)
    end

    c
end

# reintroduce! plus its counter and log line, for the idle reset and the timer
# window's reset
function reintroduce_and_log!(c::Candidate, iteration::Int, verbose::Bool, stats)
    back, dropped = reintroduce!(c)
    stats === nothing || (stats.reintroduced += sum(last, back; init=0))
    if verbose && (!isempty(back) || dropped > 0)
        println("$iteration. reintroduced $(sum(last, back; init=0)) archived configurations: ",
            join(["$(sc)×$(n)" for (sc, n) in back], " "),
            " (window >$(c.max_score - c.back_accept); dropped $dropped below it)")
    end
end

# Empties the archive: every archived perm whose score is inside the current
# window and that isn't in the pool already goes back into the pool; the rest
# (below the window, or rediscovered meanwhile) are dropped. Returns the number
# put back at each score, highest first, and the number dropped below the window.
function reintroduce!(c::Candidate)
    floor_score = c.max_score - c.back_accept
    counts = Dict{Int,Int}()
    dropped = 0
    for p in c.archive
        if p.score < floor_score
            dropped += 1
        elseif !haskey(c.index, p.moves_hash)
            push!(c.perms, p)
            c.index[p.moves_hash] = p
            counts[p.score] = get(counts, p.score, 0) + 1
        end
    end
    empty!(c.archive)
    sort!(collect(counts), by=x -> -x[1]), dropped
end

# Optional instrumentation for main(; stats=SearchStats()). One row per rollout
# (column vectors) plus section timings, end_search outcomes and per-maintenance
# snapshots. Costs roughly one extra parent replay per distinct parent, so only
# pass it for analysis runs.
const OUTCOME_NOOP = Int8(0)     # child game identical to the parent's
const OUTCOME_REJECT = Int8(1)   # below the acceptance window
const OUTCOME_REVISIT = Int8(2)  # in the window but already in the index
const OUTCOME_ACCEPT = Int8(3)   # new perm added to the pool
const OUTCOME_BEST = Int8(4)     # new candidate max_score

mutable struct SearchStats
    # per rollout
    iteration::Vector{Int32}
    seconds::Vector{Float32}
    parent_pos::Vector{Int32}    # index of the parent in candidate.perms
    parent_visits::Vector{Int32} # parent's picks since it last produced an accepted child (before this one)
    parent_hash::Vector{UInt64}  # parent's points hash (identifies the configuration picked)
    pool_size::Vector{Int32}
    parent_score::Vector{Int16}
    max_score::Vector{Int16}
    back_accept::Vector{Int16}
    num_swaps::Vector{Int8}
    swap_pos_min::Vector{Int16}  # earliest parent-game position of a swapped move
    restart::Vector{Int16}       # first step a swapped dna index is legal in the parent game (0 = never)
    diverge::Vector{Int16}       # first step the child game differs (0 = identical)
    eval_score::Vector{Int16}
    outcome::Vector{Int8}
    # section timings (ns); eval_ns includes checkpoint cache builds
    eval_ns::Int
    cache_builds::Int
    cache_retargets::Int
    end_search_ns::Int
    maintenance_ns::Int
    # end_search: (iteration, source score, max_score, results, best result, accepted, new best)
    end_searches::Vector{NTuple{7,Int}}
    # source game of each end_search call (same order), when keep_es_sources
    es_sources::Vector{Vector{Move}}
    keep_es_sources::Bool
    # decode cache counters under dna_storage=:pack
    pack_cache_hits::Int
    pack_cache_misses::Int
    # idle resets (window widenings) and archived perms put back at them
    idle_resets::Int
    reintroduced::Int
    # maintenance snapshots: (iteration, seconds, candidate, max_score, back_accept, pool size, perms at max, distinct scores)
    snapshots::Vector{NTuple{8,Float64}}
    # parent game -> step at which each dna index first became legal (0 = never)
    legal_cache::Dict{UInt64,Vector{Int16}}
    # rejected rollouts are only recorded when iteration % reject_sample == 0
    # (weight them by reject_sample); every other outcome is always recorded
    reject_sample::Int
    # false skips the per-rollout rows entirely (they grow by one row per
    # non-rejected rollout, ~330 MB over a 30-minute run), keeping only the
    # timings, end_search records and snapshots
    rows::Bool
end

SearchStats(; reject_sample::Int=1, rows::Bool=true, keep_es_sources::Bool=false) = SearchStats(Int32[], Float32[],
    Int32[], Int32[], UInt64[], Int32[], Int16[], Int16[], Int16[], Int8[], Int16[], Int16[], Int16[], Int16[], Int8[],
    0, 0, 0, 0, 0, NTuple{7,Int}[], Vector{Move}[], keep_es_sources, 0, 0, 0, 0, NTuple{8,Float64}[], Dict{UInt64,Vector{Int16}}(),
    reject_sample, rows)

# Step (1-based) at which each dna index first appears among the possible moves
# while replaying `moves`; 0 if it never does.
function first_legal_steps(moves::Vector{Move})
    first_legal = zeros(Int16, 46 * 46 * 4)
    board = initial_board()
    possible = initial_moves()
    for (step, move) in enumerate(moves)
        for m in possible
            i = dna_index(m)
            first_legal[i] == 0 && (first_legal[i] = step)
        end
        make_move(board, move, possible)
    end
    first_legal
end

function record_rollout!(s::SearchStats, t0, iteration, parent, parent_pos, candidate,
    max_score, back_accept, modifications, eval_moves, outcome)
    key = hash(parent.moves)
    first_legal = get!(() -> first_legal_steps(parent.moves), s.legal_cache, key)
    length(s.legal_cache) > 5000 && empty!(s.legal_cache)

    restart = typemax(Int16)
    for (a, b) in modifications, i in (a, b)
        first_legal[i] > 0 && (restart = min(restart, first_legal[i]))
    end
    restart == typemax(Int16) && (restart = 0)

    swap_pos_min = typemax(Int16)
    for (a, _) in modifications
        p = findfirst(m -> dna_index(m) == a, parent.moves)
        p === nothing || (swap_pos_min = min(swap_pos_min, p))
    end

    diverge = 0
    n = min(length(eval_moves), length(parent.moves))
    for i in 1:n
        if eval_moves[i] != parent.moves[i]
            diverge = i
            break
        end
    end
    diverge == 0 && length(eval_moves) != length(parent.moves) && (diverge = n + 1)

    push!(s.iteration, iteration)
    push!(s.seconds, time() - t0)
    push!(s.parent_pos, parent_pos)
    push!(s.parent_visits, parent.visits)
    push!(s.parent_hash, parent.hash)
    push!(s.pool_size, length(candidate.perms))
    push!(s.parent_score, length(parent.moves))
    push!(s.max_score, max_score)
    push!(s.back_accept, back_accept)
    push!(s.num_swaps, length(modifications))
    push!(s.swap_pos_min, swap_pos_min)
    push!(s.restart, restart)
    push!(s.diverge, diverge)
    push!(s.eval_score, length(eval_moves))
    # rejects keep their label so the reject_sample weighting stays correct
    push!(s.outcome, diverge == 0 && outcome != OUTCOME_REJECT ? OUTCOME_NOOP : outcome)
    s
end

function main(; max_iterations::Union{Nothing,Int}=nothing,
    max_seconds::Union{Nothing,Real}=nothing,
    stats::Union{Nothing,SearchStats}=nothing,
    end_search_interval::Int=10000,
    # maintenance (perm re-sorting, pruning, idle bookkeeping) runs every
    # debug_interval iterations; the progress line prints every print_interval
    # iterations (keep it a multiple of debug_interval)
    debug_interval::Int=100000,
    print_interval::Int=100000,
    verbose::Bool=true,
    # hyper-parameters (defaults are the hand-tuned values; see tune.jl for the
    # search harness that explores them)
    num_modifications::Int=10,
    default_back_accept::Int=10,
    selection_skew::Real=10,
    move_selection_skew::Real=1,
    idle_reset::Int=32,
    idle_reset_step_back::Int=default_back_accept,
    improvement_step_up::Int=10,
    initial_candidates_size::Int=1,
    # end_search wind-back depth (fraction of the source's score) and how many
    # fruitless completions in a row end each wind-back step
    es_step_back_fraction::Real=0.25,
    es_stall_cut_off::Int=200,
    # :ucb (end_search_ucb, which stops after es_ucb_stall_rollouts), :nrpa
    # (end_search_nrpa, a tree search; see the es_nrpa_* settings), two
    # back-to-back combinations whose results are merged -- :ucb_then_mast
    # (end_search_ucb, then end_search_ucb with MAST completions stopping after
    # es_mast_stall_rollouts) and :mast_then_nrpa (that MAST search, then
    # end_search_nrpa) -- or :sequential (the original end_search, which uses
    # es_stall_cut_off)
    es_mode::Symbol=:ucb_then_mast,
    es_ucb_stall_rollouts::Int=2000,
    initial_perms_size::Int=100,
    # rollouts resume from a checkpoint of the parent's game every this many
    # moves (0 = always replay from the start; results are identical either way)
    checkpoint_interval::Int=4,
    # every print_interval iterations, drop the checkpoint caches of perms that
    # weren't picked as a parent since the last cleanup (~94 KB each); a perm
    # picked again rebuilds its cache, so results are unchanged
    release_idle_caches::Bool=true,
    # a perm only gets a checkpoint cache from its cache_min_picks-th pick within
    # a print interval on; a cache costs ~1.4 rollouts to build and saves ~18%
    # of each later rollout, so caching rarely picked perms wastes time and memory
    cache_min_picks::Int=8,
    # :pack keeps only a packed set of lines per perm (~1.8 bits per move, see
    # PackCodec), decoded in canonical order when the perm is picked, so its
    # move order is lost; :moves keeps each perm's moves in the order played;
    # both rebuild a dna from the moves on every pick (see dna_from_moves!).
    # :full keeps every perm's evolved dna (16.6 KB each). checkpoint_interval,
    # release_idle_caches and cache_min_picks only apply to :full
    dna_storage::Symbol=:pack,
    # under :pack, how many recently picked perms keep their decoded moves
    # (~0.8 KB each); 0 decodes on every pick
    pack_cache_size::Int=16384,
    # what makes two configurations the same: :points (the set of dots) or
    # :lines (the set of lines drawn). Keys the pool index, the end_searched
    # set, end_search's own dedup and the "child is its parent" check
    config_key::Symbol=:points,
    # how often each pool is re-sorted for selection, and which orders are used:
    # :alternate (score order, then visits order, ...), :score or :visits
    sort_interval::Int=debug_interval,
    sort_rotation::Symbol=:alternate,
    # put each new best at the front of its pool instead of the back
    new_best_first::Bool=false,
    # keep up to this many pruned perms per candidate and put them back when the
    # idle reset widens the window (0 = pruned perms are dropped)
    archive_size::Int=100_000,
    # es_mode = :nrpa settings: NRPA level, iterations per level, warm-start
    # adaptations towards the source, and seconds per end_search call
    es_nrpa_level::Int=2,
    es_nrpa_iterations::Int=20,
    es_nrpa_warm::Int=3,
    es_nrpa_budget::Real=0.006,
    # stall of the MAST stage in :ucb_then_mast and :mast_then_nrpa
    es_mast_stall_rollouts::Int=500,
    # how much each accepted child reduces the idle counter (the idle reset
    # fires once the counter, +1 per maintenance interval, reaches idle_reset)
    idle_decrement::Real=0.1,
    # how the acceptance window moves: :counters (pruning after
    # improvement_step_up improvements, widening at idle resets, reset on a new
    # best) or :timer (sweeps from window_start below the max to the max over
    # window_cycle maintenance intervals, then resets wide; new bests keep the
    # cycle going)
    window_schedule::Symbol=:timer,
    window_cycle::Int=128,
    window_start::Int=20)
    es_mode in (:sequential, :ucb, :nrpa, :ucb_then_mast, :mast_then_nrpa) ||
        throw(ArgumentError("es_mode must be :sequential, :ucb, :nrpa, :ucb_then_mast or :mast_then_nrpa, got $es_mode"))
    dna_storage in (:full, :moves, :pack) || throw(ArgumentError("dna_storage must be :full, :moves or :pack, got $dna_storage"))
    config_key in (:points, :lines) || throw(ArgumentError("config_key must be :points or :lines, got $config_key"))
    window_schedule in (:counters, :timer) || throw(ArgumentError("window_schedule must be :counters or :timer, got $window_schedule"))
    sort_rotation in (:alternate, :score, :visits) || throw(ArgumentError("sort_rotation must be :alternate, :score or :visits, got $sort_rotation"))
    lines_key = config_key === :lines
    perm_length = 46 * 46 * 4
    moves_only = dna_storage !== :full
    pack_mode = dna_storage === :pack
    codec = PackCodec()
    pick_moves = Move[]   # the picked perm's decoded moves under :pack
    packed_perm(moves, h) = Perm(0, UInt16[], EMPTY_MOVES, h, nothing, 0, -1, length(moves), pack_encode(codec, moves), 0)
    decode_cache = DecodeCache(pack_mode ? pack_cache_size : 0)
    # with moves_only, pool perms store no dna; the picked perm's dna is rebuilt
    # into dna_buf
    dna_base = moves_only ? shuffle(UInt16(1):UInt16(perm_length)) : UInt16[]
    dna_buf = zeros(UInt16, moves_only ? perm_length : 0)
    stored_dna(dna) = moves_only ? UInt16[] : copy(dna)

    candidates = Candidate[]

    end_searched = Dict{UInt64,Bool}()



    for i in 1:initial_candidates_size
        # seed each candidate with initial_perms_size random perms (duplicate board
        # configurations are dropped), best first
        perms = Perm[]
        index = Dict{UInt64,Perm}()
        for _ in 1:initial_perms_size
            perm = UInt16.(1:perm_length)
            shuffle!(perm)
            perm_moves, perm_moves_hash = eval_dna_and_hash(perm)
            lines_key && (perm_moves_hash = lines_hash(perm_moves))
            haskey(index, perm_moves_hash) && continue

            new_perm = pack_mode ? packed_perm(perm_moves, perm_moves_hash) : Perm(
                0,
                moves_only ? UInt16[] : perm,
                perm_moves,
                perm_moves_hash
            )
            push!(perms, new_perm)
            index[perm_moves_hash] = new_perm
        end
        sort!(perms, by=p -> -p.score)
        best = perms[1]
        best_moves = pack_mode ? copy(pack_decode!(codec, Move[], best.pack)) : best.moves

        push!(candidates,
            Candidate(
                0,
                perms,
                index,
                best_moves,
                best.score,
                default_back_accept,
                0,
                0
            )
        )
    end

    # reusable rollout buffers for eval_dna_and_hash! (eval_moves aliases
    # eval_made below, so it must be copied before being stored anywhere)
    eval_board = zeros(UInt8, 46 * 46)
    eval_possible = Move[]
    eval_made = Move[]
    eval_values = UInt16[]
    modifications = Tuple{Int,Int}[]
    restart_idx = Int[]
    restart_newv = UInt16[]
    restart = 0
    # released caches, reused before allocating new ones
    spare_caches = EvalCache[]
    max_spare_caches = 64

    iteration = 1
    start_time = time()
    last_debug_time = start_time

    while max_iterations === nothing || iteration <= max_iterations
        if max_seconds !== nothing && iteration % 1000 == 0 && time() - start_time >= max_seconds
            break
        end
        candidate_position = (iteration % length(candidates)) + 1
        candidate = candidates[candidate_position]

        candidate.visits += 1

        # weighted
        perm_pos = floor(Int, rand()^selection_skew * length(candidate.perms)) + 1
        perm = candidate.perms[perm_pos]
        pmoves = !pack_mode ? perm.moves :
                 pack_cache_size > 0 ? cached_moves!(decode_cache, codec, perm) :
                 pack_decode!(codec, pick_moves, perm.pack)
        perm_score = perm.score
        stats !== nothing && stats.rows &&
            (stats_parent = (moves=copy(pmoves), visits=perm.visits, hash=perm.moves_hash))  # refresh may overwrite perm.moves
        perm.visits += 1

        stats === nothing || (eval_t0 = time_ns())
        window = iteration ÷ print_interval
        if perm.pick_window != window
            perm.pick_window = window
            perm.window_picks = 0
        end
        perm.window_picks += 1
        use_cache = checkpoint_interval > 0 && !moves_only &&
            (perm.cache !== nothing || perm.window_picks >= cache_min_picks)
        dna = moves_only ? dna_from_moves!(dna_buf, dna_base, pmoves, perm.moves_hash) : perm.perm

        if use_cache
            if perm.cache === nothing
                perm.cache = isempty(spare_caches) ? EvalCache(checkpoint_interval) : pop!(spare_caches)
            end
            perm.cache.last_used = iteration
            if !perm.cache.valid
                build_eval_cache!(perm.cache, perm.perm, eval_board, eval_possible, eval_made, eval_values)
                stats === nothing || (stats.cache_builds += 1)
            end
        end

        empty!(modifications)
        for _ in 1:rand(2:num_modifications)
            push!(modifications, (dna_index(selectByR(pmoves, rand()^move_selection_skew)), rand(1:perm_length)))
        end

        use_cache &&
            (restart = restart_step(perm.cache, dna, modifications, restart_idx, restart_newv))
        apply_swaps!(dna, modifications)

        if use_cache
            eval_moves, eval_moves_hash = eval_dna_and_hash_cached!(dna, perm.cache, restart,
                eval_board, eval_possible, eval_made, eval_values)
        else
            eval_moves, eval_moves_hash = eval_dna_and_hash!(dna, eval_board, eval_possible, eval_made, eval_values)
        end
        lines_key && (eval_moves_hash = lines_hash(eval_moves))
        eval_score = length(eval_moves)
        if stats !== nothing
            stats.eval_ns += time_ns() - eval_t0
            stats_max_score = candidate.max_score
            stats_back_accept = candidate.back_accept
            stats_outcome = OUTCOME_REJECT
        end

        is_in_index = haskey(candidate.index, eval_moves_hash)

        if eval_score > candidate.max_score
            new_perm = pack_mode ? packed_perm(eval_moves, eval_moves_hash) : Perm(
                0,
                stored_dna(dna),
                copy(eval_moves),
                eval_moves_hash
            )

            # a new best goes to the front (picked most) or waits at the back for
            # the next score-order sort
            new_best_first ? pushfirst!(candidates[candidate_position].perms, new_perm) :
            push!(candidates[candidate_position].perms, new_perm)
            candidates[candidate_position].max_score = eval_score
            candidates[candidate_position].max_moves = pack_mode ? copy(eval_moves) : new_perm.moves
            candidates[candidate_position].index[eval_moves_hash] = new_perm

            verbose && println("$iteration. $perm_score ($(perm.visits)) => $eval_score $(candidate.max_score) ###### $eval_score")
            stats === nothing || (stats_outcome = OUTCOME_BEST)
            candidate.idle_counter = 0
            window_schedule === :counters && (candidate.back_accept = default_back_accept)


        elseif eval_score >= (candidate.max_score - candidate.back_accept)

            if !is_in_index
                new_perm = pack_mode ? packed_perm(eval_moves, eval_moves_hash) : Perm(
                    0,
                    stored_dna(dna),
                    copy(eval_moves),
                    eval_moves_hash
                )

                candidate.index[eval_moves_hash] = new_perm
                push!(candidate.perms, new_perm)
                stats === nothing || (stats_outcome = OUTCOME_ACCEPT)

                arrow_symbol =
                    if eval_score > perm_score
                        "="
                    else
                        "-"
                    end
                verbose && println("$iteration. $perm_score ($(perm.visits)) $arrow_symbol> $eval_score $(candidate.max_score) i:$(length(candidate.index)) impr:$(candidate.improvement_counter)")

                perm.visits = 0

                candidate.idle_counter = max(0, candidate.idle_counter - idle_decrement)
                if eval_score > (candidate.max_score - candidate.back_accept)

                    candidate.improvement_counter += 1
                end
            else
                stats === nothing || (stats_outcome = OUTCOME_REVISIT)
                # refresh the stored perm in place (same board configuration, new dna)
                stored = candidate.index[eval_moves_hash]
                # the parent's own cache is checked below, where its dna is kept
                stored !== perm && stored.cache !== nothing && (stored.cache.valid = false)
                moves_only || copyto!(stored.perm, dna)
                if pack_mode
                    # the pack only records the set of lines: re-pack only if the
                    # child drew these dots with different lines
                    if stored !== perm || lines_hash(eval_moves) != lines_hash(pmoves)
                        stored.pack = pack_encode(codec, eval_moves)
                        uncache!(decode_cache, stored)
                    end
                else
                    resize!(stored.moves, length(eval_moves))
                    copyto!(stored.moves, eval_moves)
                end
            end
        end

        if stats !== nothing && stats.rows && (stats_outcome != OUTCOME_REJECT || iteration % stats.reject_sample == 0)
            record_rollout!(stats, start_time, iteration, stats_parent, perm_pos, candidate,
                stats_max_score, stats_back_accept, modifications, eval_moves, stats_outcome)
        end

        if eval_moves_hash != perm.moves_hash
            moves_only || revert_swaps!(dna, modifications)
        elseif perm.cache !== nothing && perm.cache.valid
            # the parent keeps the child dna: its game is the child's, which may play
            # the same points in a different order
            if eval_moves != perm.cache.moves
                retarget_eval_cache!(perm.cache, perm.perm, eval_moves, eval_moves_hash)
                stats === nothing || (stats.cache_retargets += 1)
            else
                refresh_eval_cache_values!(perm.cache, perm.perm)
            end
        end


        if iteration % end_search_interval == 0
            stats === nothing || (es_t0 = time_ns())
            end_search_candidate = rand(candidates)
            best = argmax(end_search_candidate.perms) do p
                is_end_searched = haskey(end_searched, p.moves_hash)
                if is_end_searched
                    0
                else
                    p.score
                end
            end

            if !haskey(end_searched, best.moves_hash)
                es_source = pack_mode ? pack_decode!(codec, Move[], best.pack) : best.moves

                results = if es_mode === :ucb
                    end_search_ucb(es_source, 5;
                        step_back_fraction=es_step_back_fraction, stall_rollouts=es_ucb_stall_rollouts, lines=lines_key)
                elseif es_mode === :nrpa
                    end_search_nrpa(es_source, 5; level=es_nrpa_level, iterations=es_nrpa_iterations,
                        warm=es_nrpa_warm, budget_s=es_nrpa_budget, lines=lines_key)
                elseif es_mode === :ucb_then_mast
                    merge!(end_search_ucb(es_source, 5; step_back_fraction=es_step_back_fraction,
                            stall_rollouts=es_ucb_stall_rollouts, lines=lines_key),
                        end_search_ucb(es_source, 5; step_back_fraction=es_step_back_fraction,
                            stall_rollouts=es_mast_stall_rollouts, lines=lines_key, mast=true))
                elseif es_mode === :mast_then_nrpa
                    merge!(end_search_ucb(es_source, 5; step_back_fraction=es_step_back_fraction,
                            stall_rollouts=es_mast_stall_rollouts, lines=lines_key, mast=true),
                        end_search_nrpa(es_source, 5; level=es_nrpa_level, iterations=es_nrpa_iterations,
                            warm=es_nrpa_warm, budget_s=es_nrpa_budget, lines=lines_key))
                else
                    end_search(es_source, 5;
                        step_back_fraction=es_step_back_fraction, stall_cut_off=es_stall_cut_off, lines=lines_key)
                end
                es_max_before = end_search_candidate.max_score
                es_accepted = 0
                es_best = 0

                for (es_moves_hash, es_moves) in sort(collect(results), by=x -> length(x[2]))
                    es_score = length(es_moves)

                    is_in_index = haskey(end_search_candidate.index, es_moves_hash)

                    if es_score > end_search_candidate.max_score
                        end_search_candidate.visits = 0
                        new_perm = pack_mode ? packed_perm(es_moves, es_moves_hash) : Perm(
                            0,
                            moves_only ? UInt16[] : generate_dna_all(es_moves),
                            es_moves,
                            es_moves_hash
                        )

                        new_best_first ? pushfirst!(end_search_candidate.perms, new_perm) :
                        push!(end_search_candidate.perms, new_perm)
                        end_search_candidate.index[es_moves_hash] = new_perm
                        end_search_candidate.max_moves = es_moves
                        end_search_candidate.max_score = es_score

                        verbose && println("$iteration. $(es_score) -> $( end_search_candidate.max_score) ###### $(end_search_candidate.max_score)")

                        end_search_candidate.idle_counter = 0
                        window_schedule === :counters && (end_search_candidate.back_accept = default_back_accept)
                        es_best += 1

                    elseif es_score >= (end_search_candidate.max_score - end_search_candidate.back_accept) && !is_in_index
                        new_perm = pack_mode ? packed_perm(es_moves, es_moves_hash) : Perm(
                            0,
                            moves_only ? UInt16[] : generate_dna_all(es_moves),
                            es_moves,
                            es_moves_hash
                        )
                        push!(end_search_candidate.perms, new_perm)
                        end_search_candidate.index[es_moves_hash] = new_perm
                        es_accepted += 1

                        end_search_candidate.idle_counter = max(0, end_search_candidate.idle_counter - idle_decrement)
                        if es_score > (end_search_candidate.max_score - end_search_candidate.back_accept)

                            end_search_candidate.improvement_counter += 1
                        end

                        verbose && println("$iteration. ES $(best.score) -> $es_score i:$(length(end_search_candidate.index))")
                    end
                end

                end_searched[best.moves_hash] = true

                if stats !== nothing
                    push!(stats.end_searches, (iteration, best.score, es_max_before, length(results),
                        isempty(results) ? 0 : maximum(length, values(results)), es_accepted, es_best))
                    stats.keep_es_sources && push!(stats.es_sources, copy(es_source))
                end
            end
            stats === nothing || (stats.end_search_ns += time_ns() - es_t0)

        end

        if iteration % debug_interval == 0
            stats === nothing || (maint_t0 = time_ns())
            should_print = verbose && iteration % print_interval == 0
            release_caches = release_idle_caches && checkpoint_interval > 0 && iteration % print_interval == 0
            current_time = time()
            elapsed = current_time - last_debug_time


            for c in sort(candidates, by=(c -> c.max_score))
                if window_schedule === :timer
                    # the window sweeps from window_start below the max to the max
                    # over window_cycle maintenance intervals, then resets wide
                    k = (iteration ÷ debug_interval) % window_cycle
                    if k == 0
                        c.back_accept = window_start
                        stats === nothing || (stats.idle_resets += 1)
                        archive_size > 0 && reintroduce_and_log!(c, iteration, verbose, stats)
                    else
                        c.back_accept = round(Int, window_start * (1 - k / window_cycle))
                        prune_below!(c; archive_size=archive_size)
                    end
                elseif c.improvement_counter >= improvement_step_up
                    prune_candidate!(c; archive_size=archive_size)
                end

                if release_caches
                    released = 0
                    cached = 0
                    for p in c.perms
                        p.cache === nothing && continue
                        if p.cache.last_used <= iteration - print_interval
                            p.cache.valid = false
                            length(spare_caches) < max_spare_caches && push!(spare_caches, p.cache)
                            p.cache = nothing
                            released += 1
                        else
                            cached += 1
                        end
                    end
                    should_print && released > 0 && println("$iteration. released $released idle checkpoint caches, $cached still cached, pool $(length(c.perms))")
                end

                if should_print
                    max_pack = generate_pack(c.max_moves)

                    println("$iteration. $(c.max_score) >$(c.max_score - c.back_accept) $(round(elapsed, digits=2))s idle:$(round(c.idle_counter, digits=1)) i:$(length(c.index)) impr:$(c.improvement_counter) $max_pack")
                end



                window_schedule === :timer && continue   # no idle reset: the timer widens

                c.idle_counter += 1

                if c.idle_counter >= idle_reset
                    c.improvement_counter = 0
                    c.idle_counter = 0
                    c.back_accept += idle_reset_step_back
                    stats === nothing || (stats.idle_resets += 1)
                    archive_size > 0 && reintroduce_and_log!(c, iteration, verbose, stats)
                end
            end

            if should_print
                last_debug_time = current_time
            end

            if stats !== nothing
                stats.maintenance_ns += time_ns() - maint_t0
                for (ci, c) in enumerate(candidates)
                    scores = [p.score for p in c.perms]
                    push!(stats.snapshots, (iteration, time() - start_time, ci, c.max_score, c.back_accept,
                        length(c.perms), count(==(c.max_score), scores), length(unique(scores))))
                end
            end

        end

        # Re-sort each pool; perms are picked by rand()^selection_skew over this
        # order. By score then fewest visits (exploit) or by fewest visits
        # (explore); sort_rotation = :alternate switches every sort_interval.
        # Earlier ideas for a third order, kept for reference:
        #   p -> -(p.score - p.visits / (p.score * 10000))
        #   UCB-style: normalized score + sqrt(2) * sqrt(log(c.visits + 1) / p.visits)
        if iteration % sort_interval == 0
            by_score = sort_rotation === :score ||
                       (sort_rotation === :alternate && (iteration ÷ sort_interval) % 2 == 0)
            for c in candidates
                if by_score
                    sort!(c.perms, by=p -> (-p.score, p.visits))
                else
                    sort!(c.perms, by=p -> p.visits)
                end
            end
        end

        iteration += 1
    end

    if stats !== nothing
        stats.pack_cache_hits = decode_cache.hits
        stats.pack_cache_misses = decode_cache.misses
    end
    candidates
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end