# Forest search: instead of one flat pool, keep many root configurations, each
# growing a tree of useful modifications. Every iteration walks down from a root
# with UCB, choosing at each node between modifying that node ("stay") and
# descending into one of its children, so the walk heads towards lines of
# improvement that paid off before. The many roots keep diversity: a root whose
# tree is exhausted is replaced by a fresh random one.
#
# Reuses population.jl's building blocks: the engine, policies rebuilt from games
# (dna_from_moves!), packed perms and the decode cache, mutation and end_search.

isdefined(@__MODULE__, :Perm) || include(joinpath(@__DIR__, "population.jl"))

# A configuration in the forest. `perm` holds the game (packed) and its keys.
mutable struct FNode
    perm::Perm
    parent::Int32            # 0 for a root
    root::Int32
    depth::Int32
    children::Vector{Int32}
    n::Int                   # walks through this node
    reward::Float64          # reward credited by those walks
    stay_n::Int              # modifications of this node
    stay_reward::Float64     # reward from them
    fruitless::Int           # modifications since its last useful child
    best::Int                # best score in its subtree
    closed::Bool             # no more modifications of this node
    dead::Bool               # closed, and every child dead
end

score(f::FNode) = Int(f.perm.score)

mutable struct Forest
    nodes::Vector{FNode}
    index::Dict{UInt64,Int32}        # island (dot set) -> node
    roots::Vector{Int32}             # alive and dead
    n::Int                           # walks in total
    best::Int
    best_moves::Vector{Move}
end

Forest() = Forest(FNode[], Dict{UInt64,Int32}(), Int32[], 0, 0, Move[])

function add_node!(F::Forest, p::Perm, parent::Integer)
    root = parent == 0 ? Int32(length(F.nodes) + 1) : F.nodes[parent].root
    depth = parent == 0 ? Int32(0) : F.nodes[parent].depth + Int32(1)
    push!(F.nodes, FNode(p, parent, root, depth, Int32[], 0, 0.0, 0, 0.0, 0, Int(p.score), false, false))
    id = Int32(length(F.nodes))
    F.index[p.moves_hash] = id
    if parent == 0
        push!(F.roots, id)
    else
        # children stay sorted by score, best first (newest first among equals),
        # so progressive widening considers the best ones
        ch = F.nodes[parent].children
        k = 1
        while k <= length(ch) && F.nodes[ch[k]].perm.score > p.score
            k += 1
        end
        insert!(ch, k, id)
        # the new score raises the best of every ancestor
        a = Int(parent)
        while a != 0 && F.nodes[a].best < p.score
            F.nodes[a].best = p.score
            a = F.nodes[a].parent
        end
    end
    id
end

# UCB value of option (count m, reward r) under a parent with n walks
@inline ucb(r, m, n, c) = (m == 0 ? 0.0 : r / m) + c * sqrt(log(n + 1) / (m + 1))

# Walks from a root to the node to modify; fills `path` with the nodes visited.
# Progressive widening: a node walked n times considers only its best
# 1 + floor(pw_c * n^pw_alpha) live children, so the walk goes deep on the best
# children first and widens as a node earns visits.
function walk!(F::Forest, path::Vector{Int32}, c::Real; pw_c::Real=1.0, pw_alpha::Real=0.5,
    window::Int=typemax(Int) ÷ 2)
    empty!(path)
    v = Int32(0)
    bv = -Inf
    for r in F.roots
        F.nodes[r].dead && continue
        x = ucb(F.nodes[r].reward, F.nodes[r].n, F.n, c)
        x > bv && (bv = x; v = r)
    end
    v == 0 && return Int32(0)
    floor_score = F.nodes[v].best - window   # this root's acceptance window
    while true
        push!(path, v)
        node = F.nodes[v]
        best = Int32(0)    # 0 = stay
        bv = (node.closed || node.perm.score < floor_score) ? -Inf : ucb(node.stay_reward, node.stay_n, node.n, c)
        width = 1 + floor(Int, pw_c * node.n^pw_alpha)
        seen = 0
        for ch in node.children
            seen >= width && break
            cn = F.nodes[ch]
            (cn.dead || cn.best < floor_score) && continue
            seen += 1
            x = ucb(cn.reward, cn.n, node.n, c)
            x > bv && (bv = x; best = ch)
        end
        if best == 0
            # nothing usable at or above the root's window here, and a root's best
            # only rises: this subtree is finished for good
            if bv == -Inf
                bury!(F, v)
                length(path) == 1 && return Int32(0)
                pop!(path); v = path[end]; pop!(path)
                continue
            end
            return v
        end
        v = best
    end
end

# Credits a modification of path[end] with reward r along the whole path.
function backup!(F::Forest, path::Vector{Int32}, r::Real)
    F.n += 1
    for v in path
        F.nodes[v].n += 1
        F.nodes[v].reward += r
    end
    leaf = F.nodes[path[end]]
    leaf.stay_n += 1
    leaf.stay_reward += r
end

# Closes node v; marks it and its ancestors dead when nothing below them is open.
function close!(F::Forest, v::Integer)
    F.nodes[v].closed = true
    a = Int(v)
    while a != 0
        node = F.nodes[a]
        (node.closed && all(ch -> F.nodes[ch].dead, node.children)) || break
        node.dead = true
        a = node.parent
    end
end

# Marks v finished (closed and dead) and propagates death up the tree.
function bury!(F::Forest, v::Integer)
    F.nodes[v].closed = true
    F.nodes[v].dead = true
    a = Int(F.nodes[v].parent)
    while a != 0
        node = F.nodes[a]
        (node.closed && all(ch -> F.nodes[ch].dead, node.children)) || break
        node.dead = true
        a = node.parent
    end
end

alive_roots(F::Forest) = count(r -> !F.nodes[r].dead, F.roots)

# reward for a modification of a node scoring `parent` that produced a useful
# child scoring `child` (sideways moves down to parent - step count)
@inline useful_reward(child, parent, step) = min(3.0, (child - parent + step + 1) / (step + 1))

"""
    forest_search(; max_seconds, roots=32, step=2, exploration=1.0, close_after=20_000,
                  child_cap=256, end_search_interval=5000, ...) -> Forest

Grows a forest of `roots` random starting games. A child of node u is useful when
it is a new island (dot set) scoring at least `score(u) - step` and within `window`
of the best score in u's root tree; it becomes a child node and the walk that
produced it is rewarded (more for climbing, most for raising the root's best).
Nodes and subtrees below their root's window are skipped and closed. A node that
has produced no useful child in `close_after` modifications is closed; a root
whose whole tree is closed is replaced by a fresh random root. Every
`end_search_interval` walks, the node just reached is end-searched (once per line
set) and its useful results become its children.
"""
function forest_search(; max_seconds::Real=60, max_iterations::Union{Nothing,Int}=nothing,
    roots::Int=32, step::Int=2, exploration::Real=1.0, close_after::Int=20_000, child_cap::Int=256,
    pw_c::Real=1.0, pw_alpha::Real=0.5, es_children::Int=32, window::Int=5,
    end_search_interval::Int=5000, es_step_back_fraction::Real=0.4,
    es_ucb_stall_rollouts::Int=2000, es_mast_stall_rollouts::Int=500,
    min_modifications::Int=2, num_modifications::Int=10, move_selection_skew::Real=1,
    pack_cache_size::Int=16384, print_interval::Int=1_000_000, verbose::Bool=true)

    perm_length = 46 * 46 * 4
    codec = PackCodec()
    dc = DecodeCache(pack_cache_size)
    pick_moves = Move[]
    dna_base = shuffle(UInt16(1):UInt16(perm_length))
    dna_buf = zeros(UInt16, perm_length)
    eval_board = zeros(UInt8, 46 * 46); eval_possible = Move[]; eval_made = Move[]; eval_values = UInt16[]
    modifications = Tuple{Int,Int}[]
    path = Int32[]
    es_searched = Set{UInt64}()
    F = Forest()

    function new_root!()
        while true
            moves, h = eval_dna_and_hash(shuffle(UInt16(1):UInt16(perm_length)))
            haskey(F.index, h) && continue
            id = add_node!(F, Perm(codec, moves, h), 0)
            if length(moves) > F.best
                F.best = length(moves); F.best_moves = moves
            end
            return id
        end
    end
    for _ in 1:roots
        new_root!()
    end

    start = time()
    iteration = 0
    while (max_iterations === nothing || iteration < max_iterations) &&
          (iteration % 1000 != 0 || time() - start < max_seconds)
        iteration += 1
        while alive_roots(F) < roots
            new_root!()
        end
        v = walk!(F, path, exploration; pw_c=pw_c, pw_alpha=pw_alpha, window=window)
        v == 0 && continue
        node = F.nodes[v]
        p = node.perm
        pmoves = pack_cache_size > 0 ? cached_moves!(dc, codec, p) : pack_decode!(codec, pick_moves, p.pack)
        dna = dna_from_moves!(dna_buf, dna_base, pmoves, p.moves_hash)
        empty!(modifications)
        for _ in 1:rand(min_modifications:num_modifications)
            push!(modifications, (dna_index(selectByR(pmoves, rand()^move_selection_skew)), rand(1:perm_length)))
        end
        apply_swaps!(dna, modifications)
        child, ch = eval_dna_and_hash!(dna, eval_board, eval_possible, eval_made, eval_values)
        cs = length(child)

        r = 0.0
        root_best = F.nodes[node.root].best
        if cs >= score(node) - step && cs >= root_best - window
            if !haskey(F.index, ch)
                if length(node.children) < child_cap || cs > score(node)
                    add_node!(F, Perm(codec, copy(child), ch), v)
                    r = useful_reward(cs, score(node), step) + max(0, cs - root_best)
                    node.fruitless = 0
                    if cs > F.best
                        F.best = cs; F.best_moves = copy(child)
                        verbose && println("$iteration. new best $cs (root $(node.root), depth $(node.depth + 1)) $(generate_pack(F.best_moves))")
                    end
                end
            else
                # the island exists: it takes the child's lines, as in the pool search
                w = F.nodes[F.index[ch]]
                if lines_hash(child) != w.perm.lines_key
                    w.perm.pack = inline_pack(pack_encode(codec, child))
                    w.perm.lines_key = lines_hash(child)
                    uncache!(dc, w.perm)
                end
            end
        end
        r == 0 && (node.fruitless += 1)
        backup!(F, path, r)
        node.fruitless >= close_after && !node.closed && close!(F, v)

        if iteration % end_search_interval == 0 && !(node.perm.lines_key in es_searched)
            push!(es_searched, node.perm.lines_key)
            src = perm_moves(codec, node.perm)
            results = merge!(end_search_ucb(src, step + 1; step_back_fraction=es_step_back_fraction,
                    stall_rollouts=es_ucb_stall_rollouts),
                end_search_ucb(src, step + 1; step_back_fraction=es_step_back_fraction,
                    stall_rollouts=es_mast_stall_rollouts, mast=true))
            # the best es_children new results become children
            added = 0
            for (h, m) in sort!(collect(results), by=x -> -length(x[2]))
                added >= es_children && break
                haskey(F.index, h) && continue
                length(m) >= F.nodes[node.root].best - window || continue
                length(node.children) < child_cap || length(m) > score(node) || continue
                add_node!(F, Perm(codec, m, h), v)
                added += 1
                if length(m) > F.best
                    F.best = length(m); F.best_moves = m
                    verbose && println("$iteration. new best $(length(m)) by end_search (root $(node.root)) $(generate_pack(m))")
                end
            end
        end

        if verbose && iteration % print_interval == 0
            depths = [F.nodes[v].depth for v in path]
            println("$iteration. best $(F.best), nodes $(length(F.nodes)), roots alive $(alive_roots(F))/$(length(F.roots)), ",
                "walk depth $(isempty(depths) ? 0 : maximum(depths)), $(round(time() - start, digits=1))s")
        end
    end
    F
end

# Best score of each root's tree, and how many of those trees reached `at_least`.
root_bests(F::Forest) = [F.nodes[r].best for r in F.roots]

if abspath(PROGRAM_FILE) == @__FILE__
    forest_search(max_seconds=Inf)
end
