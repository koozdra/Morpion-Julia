# Research log

This file records what we have tried on the Morpion 5T search in `population.jl`, what happened, and what we concluded. Add to it as experiments finish, including the ones that don't work: a null result saves the next person from re-running it.

**Adding an entry:** put it under the matching section, newest last. Give it a date, the question, the setup (seeds, run length, which defaults), the numbers, and a verdict:

- **Adopted:** now in the code.
- **Rejected:** made things worse.
- **Null:** no measurable effect.
- **Open:** not finished or not tested end to end.

If an entry stops being true (the code or defaults changed), mark it rather than deleting it.

## Contents

- [How to run experiments](#how-to-run-experiments)
- [Current state](#current-state)
- [Selection and search dynamics](#selection-and-search-dynamics)
- [Hyperparameters](#hyperparameters)
- [end_search](#end_search)
- [Neighbourhood structure](#neighbourhood-structure)
- [Performance](#performance)
- [Memory](#memory)
- [Background: the record and the literature](#background-the-record-and-the-literature)
- [Open questions and next directions](#open-questions-and-next-directions)

## How to run experiments

**Rules learned the hard way:**

- **Compare at equal wall clock** (`main(max_seconds=...)`), never at equal iterations. An iteration budget hides the cost of anything slow, such as a deeper end_search.
- **Use paired seeds and report a confidence interval** on the per-seed difference. Final scores vary by about ±15 points across seeds, and a single run can get stuck around 115, so effects under about ±5 points need 40+ paired seeds.
- **Re-test winners on fresh seeds.** A tuning winner at +11.4 collapsed to −1.9 on new seeds (winner's curse).
- **Per-attempt accept rate doesn't predict final score.** Several changes raised accepts or breakthroughs per call and did nothing end to end. Judge changes on final score.
- **Defaults drift.** Many entries below were measured under older defaults. Check the date against the defaults history in [Current state](#current-state).

**Tools in the repo:**

- `main(stats=SearchStats(reject_sample=k))` records one row per rollout: parent position, visits and hash, pool size, swap count, restart and divergence step, child score, and outcome (no-op / reject / revisit / accept / new best). It also records section timings, every end_search call, and a pool snapshot at each maintenance step. Rejected rollouts are sampled 1 in `k`; weight them by `k`. It costs about 13% throughput and doesn't change results. Non-rejected rollouts are always recorded, which adds about 330 MB over a 30-minute run. For long benchmarks use `SearchStats(rows=false)`, which keeps only the timings, end_search records and snapshots.
- `main(max_seconds=...)` gives a wall-clock budget.
- `test/helpers.jl`'s `enumerate_end_search_targets` exhaustively enumerates every game an end_search can reach from a source. Use it as ground truth for recall.
- `tune.jl` and `tune_end_search.jl` are the hyperparameter search harnesses.
- The scripts behind most entries below (ground-truth enumerator with a transposition table, live-source capture, A/B runners) lived in scratch space and were **not committed**.

## Current state

Defaults as of 2026-10-02 (branch `moves-only-dna`):

| Setting | Value | Note |
|---|---|---|
| `num_modifications` | 10 | 2–10 swaps per mutation |
| `default_back_accept` | 10 | was 3 in late September |
| `selection_skew` | 10 | `rand()^10` over the sorted pool |
| `idle_reset` / `improvement_step_up` | 512 / 10000 | pruning almost never runs, so the pool grows without limit |
| `initial_perms_size` | 100 | random perms each candidate starts with |
| `es_mode` | `:ucb` | UCB end_search (see below) |
| `dna_storage` | `:moves` | pool keeps moves only (see [Memory](#memory)) |
| `checkpoint_interval`, `release_idle_caches`, `cache_min_picks` | 4, true, 8 | only apply to `dna_storage=:full` |

## Selection and search dynamics

### Perm selection and the sort rotation (2026-09-27): measured
3 seeds × 3M iterations, `selection_skew=10`, small pools (median 68 perms):

- 65% of picks go to `perms[1]` and 73% to positions 1–3. Analytically P(first) = n^−0.1, so this weakens as the pool grows. With 2026-10 defaults and pools of 10–50k, about half of all picks land beyond position 64.
- Only 40% of picks hit a perm at the pool's max score, because new perms are pushed to the end and wait for the next re-sort. A new best waited a median of 706 iterations (max 30k) before its first pick.
- The old sort phase 2, `-(score - visits/(score*10000))`, gave the same top 5 as phase 0 in 30/30 sorts. That phase has since been commented out; the code now alternates score order and visits order.

### Plateaus and `perms[1]` exhaustion (2026-09-28): measured
8 seeds × 180 s with `SearchStats`:

- **Plateaus come early** (superseded under 2026-10 defaults; see [Long runs](#long-runs-with-the-current-defaults-2026-10-02-measured)): 4 of 8 runs reached their final score within 35 s. The widening of `back_accept` fired at most once per ~150 s plateau, because `idle_counter` goes +1 per 100k iterations and −0.1 per accept.
- **`perms[1]` runs dry between re-sorts:** its accepts per pick fall 19× from its first 1k picks after a re-sort to the 30k–100k window, which held about 45% of all compute. Fresh perms at the back of the list yield about 10× more accepts and bests per pick.

### Long runs with the current defaults (2026-10-02): measured
8 seeds × 30 min, 2026-10-02 defaults (moves-only DNA, UCB end_search), 8 runs in parallel:

| Minute | 1 | 2 | 5 | 10 | 15 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|---|
| Mean best score | 140.5 | 148.4 | 154.6 | 157.1 | 158.1 | 159.9 | 161.1 | 161.2 |

- **No early plateau any more:** the "plateau by ~30 s" result above was under late-September defaults. Now all 8 runs improve after minute 5 (by +1 to +13), and 7 of 8 after minute 15 (by up to +10). Most runs' last gain came between minutes 19 and 27.
- **Final scores:** 157, 158, 159, 159, 160, 160, 167, 170 (seeds 401–408). Gains slow down: +6.6 from minute 5 to 30, and only +0.1 from 25 to 30.
- **Pool and memory:** the pool averages 26k perms at 5 min, 48k at 15, and 55k at 30 (max 104k). Peak RSS was 1.0–1.8 GB, but that is inflated by `SearchStats`, which records a row for every non-rejected rollout. Without stats, a 15M-iteration run (59k perms) peaked at 430 MB vs 758 MB with them.
- **Throughput holds:** 73k → 63k → 69k iterations/s per process over minutes 0–5, 5–15, and 15–30, with 8 processes sharing the machine.

### Spreading selection away from `perms[1]` (2026-09-28): **Rejected**
A/B at 180 s × 12 paired seeds (baseline mean 151.2). Differences are per-seed, with a 95% interval:

| Arm | Difference |
|---|---|
| Re-sort every 10k iterations, `idle_reset=640` | −9.6 [−19.0, −1.3] |
| `selection_skew=2` | −6.0 [−11.9, −0.8] |
| Re-sort every 10k, `idle_reset=64` | −2.7 [−10.3, +3.0] |

High per-pick yield from fresh perms doesn't turn into score, so long, deep exploitation of `perms[1]` appears to be load-bearing. Both 10k-sort arms produced the highest peaks (161, 160 vs 155) but also the worst failures. They raise variance, which might suit best-of-N record hunting (untested).

### Taboo list for long-visited perms (2026-10-02): **Rejected** (not built)
Question: past some visit count (picks since the perm last produced an accepted child), is a perm useless and safe to drop?
Setup: 6 seeds × 300 s, 2026-10 defaults.

| Picks since last success | Share of picks | Accepts per 1M picks | New bests per 1M picks, after 60 s |
|---|---|---|---|
| 0–9 | 7% | 12,489 | 0.71 |
| 1,000–2,999 | 11% | 419 | 0.42 |
| 10,000–29,999 | 7% | 64 | 0.17 |
| 100,000+ | 2% | 4 | 0 |

Accepts fall about 3,000×, but late in a run new bests don't fall with them. Perms past 1,000 visits took 35% of picks and produced 29% of late new bests. The only lossless threshold (100k visits) saves 2% of picks. Perms past 10k visits are under 0.5% of the pool, so a taboo list wouldn't save memory either.

### `initial_perms_size` (2026-09-28): **Open**
Each candidate now starts with n random perms instead of 1 (default 100). Only a 2k-iteration smoke test was run; it has never been A/B tested.

## Hyperparameters

### Main-loop search with `tune.jl` (September 2026): **Null**
339 runs at 750k iterations: no config beat the baseline. A phase-2 winner at +11.4 fell to −1.9 on fresh seeds.
Caveat: the baseline tested was `tune.jl`'s (`selection_skew=2`, `default_back_accept=10`, `idle_reset=32`, `improvement_step_up=32`, `debug_interval=5000`). 750k iterations is about 6–9 s, the early phase, while most runs plateau later. The current defaults and the plateau regime have never been tuned.

### Mutation size (2026-09-24): **Null**
Late-run accept rate falls steadily with swap count k (k=2: 7.6 per 1k; k=10: 1.26 per 1k), and k=2 gives about 5× the new bests. Narrowing the range still doesn't change final scores: 2–4 vs 2–10 gave −0.3 [−4.4, +3.8] at 180 s × 26 seeds, and 2–3, 1–3 and 2–6 were also null at 3M iterations.

## end_search

### Hyperparameter search with `tune_end_search.jl` (September 2026): **Null**
At `step_back_fraction=0.25`, end_search never finds a completion above its source on mature games (breakthrough rate 0.00, against 0.22 at 0.4 and 0.33 at 0.6). The deeper configs still lose at equal wall clock (0.6/200/200: −5.8; 0.6/600/5000: −9.9).

### Exhaustive end_search (September 2026): **Rejected**
A depth-first search with a transposition table gave about 100% recall against about 98%. Over 14 seeds it scored 102.4 vs 105.5 at 150k iterations and cost about 5% throughput. It floods the pool with equal or lower variants and finds no breakthroughs the random sampler misses. The code was never committed.

### Recall and duplication on live sources (2026-09-28): measured
357 end_search calls captured from six 90 s runs, scored against exhaustive ground truth over the full 25% wind-back window.

- **Duplication:** 98.6% of rollouts end on a point set already seen in that call.
- **Recall:** mean 0.73 per call, 0.50 pooled, 0.40 pooled after 20 s. It found 13 of the 22 completions that beat the candidate's current max.
- **Neighbourhood size:** tiny on converged games (1–2k positions, about 1 ms to enumerate), but live sources have a median of 28 targets and up to 1,097. The exhaustive tail reaches 15M `make_move` calls, so pure exhaustive search isn't viable.
- **Contribution:** with late-September defaults, end_search was about 5% of time but about 40% of new-best events, and half the progress after 60 s.

### Dedup search over positions (2026-09-28): **Rejected**
Random descent that never re-enters a fully explored position (transposition table keyed by the set of lines played) found fewer targets at equal cost: pooled 0.39 vs 0.50. Each distinct point set is reached by about 18 different terminal positions (26 in the window), because the same dots can be drawn with different lines. Merging on point sets would be unsound for interior positions.

### Settings: depth vs stall cutoff (2026-09-28): **Null** end to end
Per call, the stall cutoff has steep diminishing returns and depth drives breakthroughs. (0.5 depth, stall 25) beat the max on 5.0% of calls at 0.41× the cost of the default (0.25, 200), which scored 3.5%. End to end at 180 s × 16 paired seeds, it made no difference: (0.5, 25) gave −1.2 [−6.5, +3.8] and (0.35, 50) gave −3.1 [−7.8, +0.9]. end_search calls producing a new best stayed at about 14 per run in every arm.

### UCB over wind-back checkpoints (2026-09-28): **Adopted** (`es_mode=:ucb`), **Open** end to end
Each wind-back depth is a bandit arm with a saved position. One pull is one random completion from it, rewarded when it finds a new in-window configuration. Arms are picked by UCB1 on reward per pull (c=0.1, undiscounted counts), and the search stops after `stall_rollouts` average completions' worth of moves without a find.

At equal wall time (0.96×) it finds 0.53 vs 0.50 of targets pooled, with the same per-call recall (0.73) and the same rate of beating the max (3.5%). It was made the default on 2026-09-28 without an end-to-end A/B.

Pitfalls found along the way:
- Ranking arms by reward per `make_move`, or discounting the counts, pins it to the cheap, exhausted depth-1 arm.
- A closure that reassigned captured counters made it 3–4× slower.
- Re-hashing and copying the whole game on every pull dominated its cost.

## Neighbourhood structure

### Dead ends under end_search (2026-09-28): measured
Using the exhaustive neighbourhood (anything reachable by undoing up to 25% of the moves):

- **Live sources:** 0% have no neighbour at all, 1% none within 4 points, 24% none scoring at least as high as the source, and 64% none scoring higher.
- **Converged games:** none of 7 (three run results, a 142, golden 166/175/178) has a better neighbour, and four have no equal one either. A converged game is a local optimum for end_search.

### Following end_search transitively (2026-09-28): **Null**
Running end_search on end_search's own results, to a fixed point, exhaustively on 60 live sources:
- **Coverage:** median 32 → 38 games, 1.2× pooled. The 13 sources with the biggest neighbourhoods hit caps and grow more (about 1.9× median).
- **Escapes:** a better game becomes reachable for 21 → 24 of 60 sources. Only 3 of the 39 dead ends escape, all at depth 2.
- **Converged games:** none is rescued.

A neighbour shares most of the source's moves, so its own window covers mostly the same ground. Escaping needs a neighbourhood that changes different moves (see [Open questions](#open-questions-and-next-directions)).

## Performance

### Evaluation checkpointing (2026-09-28): **Adopted**, then mostly superseded
A child's game copies its parent's until a changed DNA value wins a selection it lost before. Each perm caches its game's first-legal steps, play steps, chosen values, and a position every K moves. A child resumes from the last checkpoint before its restart step (`EvalCache`, `restart_step`, `rollout_heal!` in `morpion.jl`).

- **Result:** 1.078× wall clock with bit-identical results, under late-September defaults. The restart bound is near the true divergence (25% vs 27% of weighted work), so the ceiling is the mutation itself: with 2–10 swaps, the earliest lands around move 15 of ~125.
- **Pitfall:** parents adopt same-dots reordered children on about 9% of iterations, and re-replaying the cache eagerly cancelled the whole gain. The fix: cut the cache back on adoption and let later child rollouts heal it.
- **2026-10-02:** with large pools and spread-out picks it gives only about 2%, and it is off under the default `dna_storage=:moves`.

### Profile of the default search (2026-10-02): measured
One run, 12M iterations, pool 34k perms:

| Where the time goes | Share |
|---|---|
| Rollouts (`make_move` alone is 78%) | 79.5% |
| end_search (UCB) | 5.0% |
| Building mutations | 2.0% |
| Rebuilding the picked perm's DNA | 1.6% |
| Picking a perm + bookkeeping | ~3% |
| Garbage collection | 0.4% |

Throughput goes from 0.79 to about 1.1 s per 100k iterations over the run. That matches games lengthening (about 100 → 158 moves); time per move is flat or slightly lower. The engine runs about 61 ns/move, on par with the fastest published engine, so there is no cheap code-level speedup left.

### Boxed variables in `main` (2026-10-02): **Adopted** (fix)
A data-structure review found the main loop was type-unstable. The idle-reset `filter!(c.step_back_index) do ... end` closure (dead code: `step_back_index` is never filled) captured `iteration`, which the loop reassigns. It also assigned `is_in_index` and `new_perm`, which `main` uses too. Julia boxes such variables, so `candidate`, `perm` and everything after them lost their types.

Removing the capture and making the closure's variables `local` gave bit-identical results:

| | Before | After |
|---|---|---|
| Allocation per iteration | 589 B | 19 B |
| Time, 2 seeds × 4M iterations | 78.0 s | 71.3 s (1.09× faster) |

A test in `test/test_perf.jl` now fails if any of `main`'s variables is boxed. The dead `step_back_index` machinery (`StepBackPack`, the `Candidate` field, the idle-reset loop over it) and unused locals like `score_multiplier` were then deleted, again with bit-identical results.

## Memory

### Process memory baseline (2026-10-02): measured
Bare Julia is 169 MB. After loading and compiling the search it's 325 MB with 4 MB live. A 15M-iteration run (59k perms) peaks at 417 MB with about 100 MB live, of which 49 MB is the pool. So roughly three quarters of peak RSS is fixed runtime overhead.

### Checkpoint caches under large pools (2026-10-02): **Adopted** (full-DNA mode)
With `default_back_accept=10` and `improvement_step_up=10000`, pools reach 10–54k perms in 5 minutes. Caching every parent cost about 94 KB per perm and up to 10.6 GB peak RSS. A first fix (release caches that were idle for a print interval) made runs slower and raised peak RSS, because most perms are picked about once per interval and got rebuilt every time.

Final version: a perm gets a cache only from its 8th pick in a print interval, and idle caches are released. Peak RSS on a 52k pool went 10.6 → 2.3 GB, with identical results and the same speed.

### Lossless DNA compression (2026-10-02): **Rejected** (analysis only)
Pool DNAs are unrelated permutations: a median of 8,463 of 8,464 entries differ from the best perm, because each end_search result starts a fresh random lineage. Delta encoding has nothing to exploit, and bit-packing saves only 12%.

An LRU cache of DNAs was also non-viable: hit rates were 44–47% at 64 perms, 61–66% at 1,024, and 86–95% at 16k. Each miss means a lossy 62 µs `generate_dna_all`.

### Moves-only DNA storage (2026-10-02): **Adopted** (`dna_storage=:moves`)
Pool perms keep only their moves. When a perm is picked, `dna_from_moves!` rebuilds its DNA in about 0.3 µs: a fixed random base permutation rotated by the perm's hash, with the played moves given the top values in game order, so the greedy rollout replays the game exactly. This drops the evolved ordering of unplayed moves, so it is a different search.

A/B at 300 s × 16 paired seeds:

| | Full DNA | Moves-only |
|---|---|---|
| Mean (median) score | 148.4 (153.5) | 153.8 (154.5) |
| Spread (sd) | 13.3 | 3.6 |
| Pool memory | 878 MB | 29 MB |
| Peak RSS | 2.49 GB | 0.77 GB |
| Iterations in 5 min | 21.1M | 21.1M |

Per seed the difference is +5.4 [+0.1, +12.1], median +2, with moves-only better on 9 seeds and worse on 7. The gap comes mostly from two stuck full-DNA runs (115, 116). Moves-only is at least no worse and may be more robust.

### Compact move representation (2026-10-02): **Open** (analysis only)
Under moves-only storage, a perm's memory is almost all its move list. A `Move` is 5 bytes (x, y, start_x, start_y, direction as `Int8`), and games average 147 moves, so 774 B per perm. For 59k perms that's 44 MB of a 49 MB pool. The whole process peaks around 430 MB, and most of that is the Julia runtime and transient garbage, not the pool.

Options:
- **2-byte line index per move:** `dna_index` (start and direction, 1..8,464) as `UInt16`. It's lossless: the new dot is the line's only empty cell at that point in a replay. The hot path only needs the index (DNA rebuild and mutation targets), so there's no decode cost per pick. Only end_search sources need full moves, and those can be replayed once per call. That cuts per-perm memory 2.3× (~340 B), saving ~25 MB at 59k perms, about 6% of the process.
- **14-bit packing:** about 12% smaller again than 2 bytes, for extra complexity.
- **Choice-index encoding** (like `generate_pack`, ~44 bytes, ~1.8 bits per move): ~17× smaller, but decoding needs a replay of the game (about one rollout) on every pick.

Not worth doing for 30-minute runs. It may be for runs of hours, if the pool keeps growing.

**Pack plus a decode cache (2026-10-02): Rejected** (analysis only). Measured on a 150-move game:
- **The pack doesn't keep move order:** `generate_pack` stores the set of lines (41 characters, 49 bytes as a `String`), and `unpack_pack` returns it in a canonical order. Under moves-only storage a perm's order is its DNA, so the codec would have to change to store per-step choice indices (~3–4 bits per move, ~60–75 bytes).
- **Decoding is slow:** `unpack_pack` takes 22 µs and `generate_pack` 33 µs, against a 14.7 µs rollout. Even a fast decoder can't beat a plain replay, at 8.5 µs.
- **Misses would be frequent:** picks are spread across the pool, so the LRU hit rates measured earlier apply. At 4,096 cached perms, 73–78% hit means ~20% slower; at 16,384 (13 MB of cache), 86–95% hit means 5–12% slower.
- **The saving is small:** per perm ~200 B instead of ~940 B, so about 25 MB total at 59k perms including the cache. The 2-byte index saves about the same with no slowdown and much less code.

## Background: the record and the literature

Researched 2026-09-24.

- **The record:** 5T 178 (Rosin, August 2011, nested rollout policy adaptation, NRPA) is still unbeaten.
- **Later compute converged on Rosin's grid:** Nagórko (2019) found 178 in 10/10 runs of level-6 parallel NRPA on 768 cores, always Rosin's grid up to symmetry. Buzer and Cazenave (2021) spent about 57k core-hours on level-5 NRPA; 2% of runs hit 178, and warm starts from the best sequence gave only 176–178.
- **Upper bound:** 485 (MIP, 2015). Its relaxation admits 317-move grids, so it can't get much tighter.
- **Our 178s are Rosin's family:** the two 178s in `population.jl`'s header share 177/178 dots and 171 and 174 of 178 lines with Rosin's 178 (best of 8 symmetries). Our 177s are variants of Rosin's 177A/B. Other families in the archive top out at 170–175.
- **DNA keys:** the key (new dot, direction) never collides between simultaneously legal lines (0 in about 376k moves), so re-keying by line would add nothing.
- **Rosin's grids:** http://www.morpionsolitaire.com/Grid5T178Rosin.txt (also 177RosinA/B), in Pentasol format. To replay one here: the reference point R is cross cell (3,3), (a,b) is (x,y), and line cells are dot + (i − offset)·v for i in −2..2, with v = −1 × {'|':(0,1), '-':(1,0), '/':(1,−1), '\':(1,1)}.
- **Directions to skip:** deep learning (5D only, below record), symmetric-grid search (ceiling about 136), LP pruning.

## Open questions and next directions

Roughly in priority order:

1. **Compare settings over 30-minute runs, not 3–5 minutes:** scores keep climbing until about minute 25 (see [Long runs](#long-runs-with-the-current-defaults-2026-10-02-measured)), so short A/Bs may miss effects that only show up later.
2. **Undo a move and only what depends on it (dependency-closure ruin-and-recreate):** remove a move plus every move that depends on it, keep the rest (always a valid game), and re-complete. It changes mid-game moves without undoing everything after them, which end_search can't do. First measurement: how small these dependent sets are, and how many end_search dead ends (above) gain a better neighbour.
3. **Best-of-N parallel runs:** the machine has 14 cores and runs are single-threaded. High-variance settings (frequent re-sort) might pay off when only the maximum over N runs counts.
4. **Tune the current defaults in the plateau regime:** all hyperparameter searches so far were early-phase or used older defaults.
5. **End-to-end check of UCB end_search**, which was made default without one.
6. **Bound the pool:** it grows without limit under the current settings. That's cheap in memory now (about 0.8 KB per perm), but it also spreads picks out.
7. **Ranked directions from the September literature review:** an exact endgame proof for the 178 family; a dot-set SAT/MIP for 179-dot sets near the family; anti-attractor diversity (reject grids overlapping the family, islands, symmetry-canonical dedup); calibration against NRPA (only for publishing).
