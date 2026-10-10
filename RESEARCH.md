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

Defaults as of 2026-10-08:

| Setting | Value | Note |
|---|---|---|
| `num_modifications` | 10 | 2–10 swaps per mutation |
| `default_back_accept` | 10 | was 3 in late September |
| `selection_skew` | 10 | `rand()^10` over the sorted pool |
| `sort_rotation` | `:visits` | the pool is re-sorted by fewest visits only (the score-ordered phase was redundant under the timer); was `:alternate` until 2026-10-08 |
| `window_schedule`, `window_cycle`, `window_start` | `:timer`, 128, 10 | the window narrows linearly from `window_start` below the max to the max over 128 maintenance intervals (12.8M iterations), then resets wide; timer since 2026-10-08 (see [Escape settings](#escape-settings-and-a-timer-driven-window-2026-10-08-timer-128-adopted-default-since-2026-10-08)); `window_start` 20 → 10 on 2026-10-09 (10–25 is a plateau, below 10 traps runs). `window_adapt` (adaptive step back) is available but off |
| `idle_reset` / `improvement_step_up` | 32 / 10 | only used with `window_schedule=:counters` (was 512 / 10000 on 2026-10-02, 128 / 100 on 2026-10-04) |
| `initial_perms_size` | 100 | random perms each candidate starts with |
| `es_mode` | `:ucb_then_mast` | UCB end_search followed by a MAST-guided pass, results merged (since 2026-10-08; see [end_search](#end_search)) |
| `dna_storage` | `:pack` | pool keeps a packed set of lines per perm, decoded through a 16k-slot cache (`pack_cache_size`); was `:moves` until 2026-10-04 (see [Memory](#memory)) |
| `archive_size` | 100,000 | pruned perms are archived and put back when the window widens again: at each timer reset (or idle reset under `:counters`); since 2026-10-06 |
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

### Selection under the current defaults (2026-10-05): measured
6 seeds × 10 min, 2026-10-04 defaults (pools of ~1.4k perms, median; p10 384, p90 4.5k), `SearchStats`. Selection is `rand()^10` over a pool re-sorted every 100k iterations, alternating score order (exploit) and fewest-visits order (explore).

- **The explore phase rarely produces new bests:** it gets 50% of picks but only 22% of new bests (0.21 vs 0.74 per 1M picks). Max-score perms sit at the back of visits order, so only 0.1% of explore picks hit one.
- **Exploit productivity collapses after each re-sort:** new bests per 1M picks are 22.5 in the first 1k iterations, then 2.4 (1k–10k), 0.6 (10k–30k), and 0.26 (30k–100k). The first 10k iterations (5% of exploit picks) give 46% of the exploit phase's new bests. A new best is pushed to the back and waits for the next score-order sort.
- **Position 1 gets about 50% of all picks.** P(first) = n^−0.1, so this is lower than with September's tiny pools.

### Selection settings (2026-10-05): **Null**
A/B at 10 min × 12 paired seeds. New options make each change possible without side effects: `sort_interval` (decoupled from `debug_interval`), `sort_rotation` and `new_best_first`; all default to the previous behaviour.

| Arm | Mean (median) | Per seed vs base | Better / worse / tied |
|---|---|---|---|
| base (alternate, re-sort every 100k, skew 10) | 151.6 (155.0) | — | — |
| score order only (no explore phase) | 150.5 (156.0) | −1.1 [−9.0, +5.5] | 5 / 5 / 2 |
| re-sort every 25k | 153.1 (156.0) | +1.5 [−2.9, +6.8] | 6 / 6 / 0 |
| new bests to the front | 152.2 (156.0) | +0.6 [−2.3, +3.8] | 6 / 6 / 0 |
| skew 5 | 150.6 (156.5) | −1.0 [−9.8, +6.9] | 5 / 6 / 1 |
| skew 20 | 153.4 (156.5) | +1.8 [−1.8, +5.9] | 6 / 5 / 1 |

Every arm is within noise of the base: medians differ by at most 1.5 points and every interval spans zero. The per-pick yield differences above don't turn into final score, consistent with the September finding. Most of the variance is stuck runs, and they're tied to the seed, not the setting: seed 1107 stuck at 109–138 in every arm. So the selection system is on a flat optimum, and the bigger lever is probably detecting and escaping stuck runs.

### Archiving pruned perms and reintroducing them (2026-10-06): **Adopted** (default `archive_size=100_000` since 2026-10-06; the A/B was within noise)
When pruning tightens the window, perms below it used to be dropped and had to be rediscovered after the idle reset widened it again. `archive_size` keeps up to that many pruned perms per candidate (best scores first, most recently pruned first among equal scores). At each idle reset, the ones back inside the window are reintroduced, logged as `reintroduced N archived configurations: 157×12 156×30 … (window >148, M still archived)`.

The idle reset only fires on a hard plateau: pruning, accepts and new bests all reset the idle counter, so the window must first shrink until nothing is accepted for `idle_reset` (128) maintenance intervals. In 30-minute runs that happened 6–11 times per run.

A/B at 30 min × 12 paired seeds, 2026-10-05 defaults, archive of 100k vs none:

| | Final scores | Mean (median) | Mean best at 5 / 10 / 20 / 30 min | Pool median / max | Peak RSS |
|---|---|---|---|---|---|
| none | 160 156 158 157 172 155 160 157 151 117 162 158 | 155.2 (157.5) | 150.2 / 151.1 / 154.0 / 155.2 | 1.6k / 20k | 371 MB |
| archive 100k | 160 150 161 157 172 155 161 158 154 118 157 170 | 156.1 (157.5) | 149.8 / 151.8 / 154.4 / 156.1 | 2.0k / 101k | 373 MB |

- **Score:** archive − none = +0.8 [−1.4, +3.4], median +0.5; better on 6 seeds, worse on 2, tied on 4.
- **Reintroduction is large:** about 318k perms per run, roughly 36k per idle reset, briefly swelling the pool to as much as 101k perms before pruning shrinks it again.
- **No memory cost.**

Not significant. A gentler variant may be worth trying: reintroducing only the top few scores below the max, or capping how many come back per reset.

Update (2026-10-06): each idle reset now drains the archive completely. Perms inside the widened window go back to the pool, and everything still below it is dropped instead of kept (the A/B above kept them; on average ~85k were still archived at the end of a 30-minute run). This variant hasn't been A/B tested separately.

### Escape settings, and a timer-driven window (2026-10-08): timer 128 **Adopted** (default since 2026-10-08)
A/B at 30 min × 8 paired seeds, `es_mode=:ucb_then_mast`, 2026-10-07 defaults (`idle_reset=32`, `improvement_step_up=10`, `idle_reset_step_back=10`, `default_back_accept=10`, 1 candidate). Each arm changes one setting.

New options (off by default):
- `idle_decrement`: how much each accepted child delays the idle reset (was a hard-coded 0.1).
- `window_schedule=:timer` with `window_cycle` and `window_start`: the window narrows linearly from `window_start` below the max to the max over `window_cycle` maintenance intervals, then resets wide (reintroducing from the archive). Counter-driven pruning and the idle reset are off, and new bests don't restart the cycle.

| Arm | Final scores | Mean (median) | Mean best at 5 / 10 / 20 / 30 min | Per seed vs base [95%] | Better / worse / tied |
|---|---|---|---|---|---|
| base | 153 158 161 151 159 158 161 152 | 156.6 (158.0) | 149.0 / 154.1 / 156.2 / 156.6 | — | — |
| idle 16 | 154 152 159 161 155 162 153 152 | 156.0 (154.5) | 150.6 / 153.1 / 155.1 / 156.0 | −0.6 [−4.1, +3.2] | 3 / 4 / 1 |
| step-up 5 | 155 155 156 160 157 158 159 151 | 156.4 (156.5) | 144.5 / 154.6 / 155.8 / 156.4 | −0.2 [−2.6, +2.8] | 2 / 5 / 1 |
| widen 20 | 155 154 156 156 162 156 157 152 | 156.0 (156.0) | 150.0 / 153.5 / 155.6 / 156.0 | −0.6 [−3.0, +1.8] | 3 / 4 / 1 |
| back-accept 20 (widen kept at 10) | 161 162 154 157 157 157 148 156 | 156.5 (157.0) | 151.2 / 152.4 / 155.1 / 156.5 | −0.1 [−5.0, +4.1] | 4 / 4 / 0 |
| 4 candidates | 161 160 158 168 158 158 161 157 | 160.1 (159.0) | 155.4 / 157.0 / 158.5 / 160.1 | +3.5 [−0.1, +8.0] | 4 / 2 / 2 |
| idle decrement 0 | 157 159 156 158 157 162 153 153 | 156.9 (157.0) | 152.8 / 153.4 / 155.9 / 156.9 | +0.2 [−3.1, +3.2] | 5 / 3 / 0 |
| timer, 32 intervals, start 20 | 155 155 157 165 177 159 159 152 | 159.9 (158.0) | 153.5 / 155.5 / 158.2 / 159.9 | +3.2 [−1.5, +8.9] | 4 / 3 / 1 |
| **timer, 128 intervals, start 20** | 159 157 171 160 169 161 157 154 | **161.0** (159.5) | 152.0 / 152.2 / **160.5** / 161.0 | **+4.4 [+0.9, +7.8]** | **6 / 2 / 0** |

- **Timer 128 is the first escape change with an interval above zero:** +4.4 [+0.9, +7.8], better on 6 of 8 seeds. Its gains come late: the mean best jumps from 152.2 at 10 min to 160.5 at 20 min, as the slow sweep plays out.
- **The timer arms produced 4 of the 5 runs that reached 165**, including a **177** (timer 32, seed 1605) and a **171** (timer 128, seed 1603). Both were added to the header of `population.jl`.
- **4 candidates is close behind** (+3.5 [−0.1, +8.0]).
- **The counter tweaks are all null:** idle 16, step-up 5, widen 20, back-accept 20, idle decrement 0. The current counter values sit on a flat optimum, consistent with the selection A/B.
- Untested next steps: timer 128 combined with 4 candidates; other cycle lengths (64, 256); start widths 15 and 30.

### Timer window follow-up (2026-10-08): **Null** (keep timer 128, start 20)
A/B at 30 min × 8 paired seeds around the new defaults (timer, cycle 128, start 20, `es_mode=:ucb_then_mast`):

| Arm | Final scores | Mean (median) | sd | Per seed vs base [95%] | Better / worse / tied |
|---|---|---|---|---|---|
| base | 167 177 159 158 156 161 160 158 | 162.0 (159.5) | 6.9 | — | — |
| + 4 candidates | 160 159 158 159 159 158 157 169 | 159.9 (159.0) | 3.8 | −2.1 [−7.9, +3.1] | 3 / 5 / 0 |
| cycle 64 | 159 161 161 157 163 167 160 152 | 160.0 (160.5) | 4.4 | −2.0 [−7.2, +2.8] | 3 / 4 / 1 |
| cycle 256 | 158 159 157 156 166 161 158 161 | 159.5 (158.5) | 3.2 | −2.5 [−8.2, +2.5] | 2 / 5 / 1 |
| start 15 | 158 160 159 159 160 159 159 158 | 159.0 (159.0) | 0.8 | −3.0 [−7.9, +0.8] | 2 / 4 / 2 |
| start 30 | 160 158 156 159 153 160 161 117 | 153.0 (158.5) | 14.8 | **−9.0 [−19.5, −1.2]** | 2 / 6 / 0 |

- **Nothing beat the defaults.** Every variant's point estimate is below the base, but only start 30 is clearly worse (it includes a run stuck at 117). Part of the base's mean comes from its 167 and 177 on the first two seeds.
- **Combining 4 candidates with the timer doesn't add up** (−2.1); the two escape mechanisms aren't complementary.
- **Start 15 is extremely consistent** (sd 0.8, 158–160 on every seed) but never broke out.
- **New game:** a **177** from the base (seed 1702), pack `7EBET5ZlRiSWRsI5…`, close to the 178 `7EBET5ZlRiSHYc0…`; added to the header of `population.jl`.

### Timer sweep shape, and sort order under the timer (2026-10-08): shape **Null**, visits-only **Adopted** (equivalent; default since 2026-10-08), uniform **Rejected**
A/B at 30 min × 8 paired seeds around the defaults (timer 128, start 20, `es_mode=:ucb_then_mast`). New option `window_shape` (default 1): `back_accept = round(window_start × (1 − k/window_cycle)^window_shape)`. Shapes above 1 narrow fast and spend longer near the max; with shape 2 the window is 5 or narrower for half the cycle, with shape 3 for about two thirds.

| Arm | Final scores | Mean (median) | sd | Per seed vs base [95%] | Better / worse / tied |
|---|---|---|---|---|---|
| shape 1 (base) | 177 162 161 156 157 160 158 162 | 161.6 (160.5) | 6.6 | — | — |
| shape 2 | 162 160 160 156 152 161 157 157 | 158.1 (158.5) | 3.3 | **−3.5 [−7.1, −0.8]** | 1 / 6 / 1 |
| shape 3 | 169 162 157 155 175 161 158 157 | 161.8 (159.5) | 6.9 | +0.1 [−4.0, +5.8] | 2 / 4 / 2 |
| visits order only (`sort_rotation=:visits`) | 177 159 162 160 155 156 161 159 | 161.1 (159.5) | 6.8 | −0.5 [−2.4, +1.4] | 3 / 4 / 1 |
| uniform pick (`selection_skew=1`) | 156 161 155 151 152 157 160 157 | 156.1 (156.5) | 3.5 | **−5.5 [−10.5, −1.9]** | 1 / 7 / 0 |

- **Linear stays.** Shape 2 is worse. Shape 3 is level on average, with two breakthroughs (175, 169) but more runs below the base.
- **The score-ordered sort phase is redundant under the timer:** visits-only is equivalent to the alternating rotation, within about ±2 points. The timer's narrowing does the focusing that phase used to do.
- **Picks still need a skew:** uniform selection is clearly worse.
- **New games:** two 177s (base and visits-only, both seed 1801) and a 175 (shape 3, seed 1805), all variants of the `CBMXT2Tom…` family; added to the header of `population.jl`.

### Timer step pacing, more time at the late steps (2026-10-09): **Null**
`window_dwell` (default 0) keeps the width linear in the timer step k but makes later steps last longer: step k lasts in proportion to k^dwell, with the cycle still 128 maintenance intervals. So the logged `k/128` moves fast through the wide steps and slowly through the narrow ones. With dwell 0.5 the window is 5 or narrower for ~35% of the cycle, with dwell 1 for ~44% (vs 25% at dwell 0). A/B at 30 min × 8 paired seeds, current defaults:

| Arm | Final scores | Mean (median) | sd | Per seed vs dwell 0 [95%] | Better / worse / tied |
|---|---|---|---|---|---|
| dwell 0 (default) | 160 162 162 157 163 161 155 159 | 159.9 (160.5) | 2.7 | — | — |
| dwell 0.5 | 157 159 160 156 156 164 155 158 | 158.1 (157.5) | 2.9 | −1.8 [−3.6, +0.1] | 1 / 6 / 1 |
| dwell 1 | 159 159 159 156 157 176 158 160 | 160.5 (159.0) | 6.4 | +0.6 [−2.8, +5.2] | 3 / 5 / 0 |

- **Same conclusion as `window_shape`:** spending more of the cycle near the max doesn't help on average. Dwell 0.5 is slightly worse, and dwell 1's mean is lifted by one run while it's worse on 5 of 8 seeds.
- **Even pacing keeps runs improving later:** median last gain at minute 25.7 for dwell 0, vs 23.2 and 16.3.
- **New game:** **176** (dwell 1, seed 1906), pack `FEBMv6lokkiL84GQw5…`, a variant of the `FEBMv6lokk…` 177 family; added to the header of `population.jl`.

### Timer step back (`window_start`) from 1 to 25 (2026-10-09): **keep 20**
A/B at 30 min × 8 paired seeds, current defaults (timer 128, linear, visits-only sort, `es_mode=:ucb_then_mast`):

| Step back | Final scores | Mean (median) | sd | Per seed vs 20 [95%] | Better / worse / tied | Median last gain |
|---|---|---|---|---|---|---|
| 1 | 148 132 152 154 136 111 154 133 | 140.0 (142.0) | 15.0 | **−19.2 [−29.2, −10.6]** | 0 / 8 / 0 | min 1.5 |
| 3 | 159 135 158 157 148 158 148 159 | 152.8 (157.5) | 8.5 | **−6.5 [−14.0, −0.2]** | 2 / 4 / 2 | min 6.7 |
| 5 | 147 158 156 121 156 160 148 159 | 150.6 (156.0) | 12.9 | **−8.6 [−18.5, −0.2]** | 2 / 4 / 2 | min 5.0 |
| 10 | 156 159 156 159 158 159 162 160 | 158.6 (159.0) | 2.0 | −0.6 [−4.2, +2.0] | 4 / 3 / 1 | min 8.6 |
| **20 (default)** | 157 155 158 156 156 159 174 159 | 159.2 (157.5) | 6.1 | — | — | min 25.5 |
| 25 | 156 155 157 161 160 159 158 157 | 157.9 (157.5) | 2.0 | −1.4 [−6.0, +2.0] | 2 / 4 / 2 | min 13.8 |

Together with the earlier follow-up (15: −3.0; 30: −9.0):
- **Small step backs trap runs.** With 1, runs stop improving within minutes (median last gain at 1.5 min) and some end far down (111, 132, 133). 3 and 5 usually do fine but sometimes trap badly (121, 135).
- **10–25 is a plateau:** within about a point of each other. 20 keeps runs improving longest (median last gain 25.5 min) and produced the only breakout (174).
- **New game:** **174** (step back 20, seed 2007), pack `FEBMv6lokkqKS4cwzBofV1…`, a variant of the `FEBMv6lokk…` family; added to the header of `population.jl`.

### Adaptive step back (2026-10-09): **small positive, not significant**
`window_adapt=true`: each candidate counts the new configurations added to its pool during a timer cycle. At each reset it widens the next cycle's step back by `window_adapt_step` (2) if that count was below `window_adapt_target`, otherwise narrows it by 2, within `window_adapt_min`–`window_adapt_max` (1–30), starting from `window_start`. `SearchStats.cycles` records every cycle's (iteration, count, step back used, next step back).

- **Calibration matters.** A cycle typically adds thousands to hundreds of thousands of configurations (the pool stays at 1–2k because pruning keeps removing them). A first attempt with targets 10–10,000 drove every run's step back down into the trap zone (2–8), and was stopped after one round.
- **Recalibrated A/B** at 30 min × 8 paired seeds, step back starting at 20 in every arm:

| Arm | Final scores | Mean (median) | Per seed vs fixed 20 [95%] | Better / worse / tied | Step back: final per run (mean over run) |
|---|---|---|---|---|---|
| fixed 20 | 155 159 160 152 157 162 157 155 | 157.1 (157.0) | — | — | 20 |
| target 20k | 159 159 159 152 157 163 157 162 | 158.5 (159.0) | +1.4 [−0.1, +3.2] | 3 / 1 / 4 | 6–14 (13.3) |
| target 50k | 159 163 158 152 157 163 157 159 | 158.5 (158.5) | +1.4 [−0.1, +2.9] | 4 / 1 / 3 | 8–20 (14.8) |
| target 150k | 155 163 158 152 157 163 157 155 | 157.5 (157.0) | +0.4 [−0.6, +1.6] | 2 / 1 / 5 | 10–28 (18.7) |
| target 400k | 156 162 159 155 157 163 157 155 | 158.0 (157.0) | +0.9 [+0.0, +1.9] | 4 / 1 / 3 | 28–30 (24.4) |

- **Every adaptive arm is slightly ahead of fixed 20** (+0.4 to +1.4) and worse on only 1 seed of 8. But the intervals touch zero, and many runs tie exactly: all arms use 20 for the first cycle, so runs often reach the same plateau first.
- **Targets of 20k–50k did best.** They settle the step back around 8–20 (mean about 14), which agrees with the fixed-step-back plateau of 10–25.
- **No run reached 165** in any arm of this A/B, so it says nothing about breakthroughs.

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

### end_search's contribution under the current defaults (2026-10-02): measured
From the 8 × 30-minute runs (2026-10-02 defaults). The earlier entries in this section were under September defaults, when end_search seemed not to matter.

- **It drives most of the progress:** calls that raised the candidate's max account for 328 of 541 points gained (61%), and 32 of 53 points after minute 5 (60%).
- **But rarely:** only 18–31 of about 12k calls per run raised the max (0.2%).
- **Supply is no longer a limit:** every 10k-iteration slot found an unsearched source.
- **It fills the pool:** each call adds about 7 perms, about 86k per run.
- **Cost:** about 11.6 ms per call at 20k perms, roughly 11–12% of time.

### Calling end_search more often (2026-10-02): **Null**
8 paired seeds × 30 min, varying `end_search_interval` (iterations between calls):

| Interval | Final scores | Mean | Mean best at 5 / 10 / 20 / 30 min | Time in end_search |
|---|---|---|---|---|
| 10,000 (default) | 157 161 156 164 161 161 159 170 | 161.1 | 154.4 / 156.8 / 158.2 / 161.1 | 11% |
| 5,000 | 160 118 159 158 162 160 159 162 | 154.8 | 151.8 / 152.8 / 154.2 / 154.8 | 16% |
| 2,500 | 160 161 156 159 159 158 162 162 | 159.6 | 158.1 / 158.8 / 159.4 / 159.6 | 28% |

Per seed against the default: 5,000 gave −6.4 [−17.8, +0.9] (median −0.5, with one stuck run at 118), and 2,500 gave −1.5 [−4.1, +0.9] (median −1.0).

Calling it 4× as often got further early (158.1 vs 154.4 at 5 min) but then nearly stopped improving: +1.5 from minute 5 to 30, against +6.7 for the default. Its pool was also smaller (34k vs 52k perms). The default interval is fine for 30-minute runs; a 2,500 interval might suit runs of a few minutes.

### Comprehensiveness under the current defaults (2026-10-02): measured
298 end_search calls sampled from 6 × 10-minute runs (2026-10-02 defaults, `improvement_step_up=1000`), each scored against exhaustive ground truth over the 25% wind-back window, 2 seeds per call per variant.

Neighbourhoods are bigger than in September: a median of 51 in-window alternatives per call (mean 135, max 2,227).

| Variant | Recall per call | Pooled | All found | Beats max found | Time |
|---|---|---|---|---|---|
| UCB, stall 2000 (default) | 0.59 | 0.36 | 13% | 8/10 | 1.00× |
| UCB, stall 4000 | 0.63 | 0.40 | 15% | 8/10 | 1.95× |
| UCB, stall 8000 | 0.67 | 0.45 | 17% | 8/10 | 4.12× |
| UCB, exploration 0.3 | 0.58 | 0.35 | 13% | 8/10 | 0.97× |
| UCB, dot-uniform completion | 0.57 | 0.34 | 12% | 8/10 | 1.04× |
| UCB, dot-uniform, stall 1000 | 0.53 | 0.30 | 11% | 8/10 | 0.51× |
| Old sequential end_search | 0.60 | 0.34 | 15% | 8/10 | 1.02× |

- **Recall falls with neighbourhood size.** The default finds every alternative in 63% of calls with 1–5 of them, 38% with 6–20, 2% with 21–100, and never above 100 (pooled recall 0.80, 0.78, 0.57, 0.31).
- **Only budget buys recall, and slowly.** Twice the time adds about 4 points of pooled recall; four times adds 9.
- **Exploration didn't help, and neither did dot-uniform completions.** Dot-uniform picks uniformly among new dots rather than moves, aimed at the ~18 games per point set.
- **Breakthroughs are rarely missed.** Only 5 of 298 calls had a completion that beat the max, and every variant found it in 8 of 10 tries.
- **Exhaustive enumeration isn't an option.** Even an unoptimised version is 53× the default's total time (median 55 ms vs 4.2 ms per call, max 6.7 s), and only 30% of calls finish within 20 ms.

Given that doubling end_search's time via call frequency didn't raise 30-minute scores (above), buying recall with a longer stall is unlikely to either.

### Tree-search and reinforcement-learning end_search variants, head to head (2026-10-08): measured offline
300 end_search calls captured from 6 × 10-minute runs (2026-10-07 defaults: `idle_reset=32`, `improvement_step_up=10`, packed storage, archive). Every variant ran on the same sources one after another; the two persistent variants ran on every call in order and were scored on the same 300. Ground truth (exhaustive, 25% window) was available for 287 calls, with a median of 34 reachable in-window variants per call (mean 75).

Variants, all keyed and windowed like `end_search`:
- **NMCS** (nested Monte Carlo search): at each step try every legal move with a random completion (level 1) or a level-1 search (level 2), and follow the best sequence seen, starting from the source's own continuation.
- **NRPA**: warm-started level-2 nested rollout policy adaptation (`end_search_nrpa`), repeated from random depths of 5–50% until a time budget.
- **GNRPA conflict prior**: NRPA plus a bias penalising moves that compete with other legal lines for the same dot.
- **NRPA context codes**: a move's weight depends on the previous move (sparse policy).
- **NRPA persistent**: one policy kept across calls, moved towards every continuation that beat the source.
- **UCB + MAST**: the current UCB end_search, with completions favouring lines whose rollouts averaged longer games (move-average sampling); optionally kept across calls.

| Variant | Time | Variants found | Recall (per call / pooled) | All found | Beats source | Beats max | Reaches best* |
|---|---|---|---|---|---|---|---|
| UCB (current) | 1.00× | 34.2 | 0.54 / 0.43 | 14% | 45.3% | 1.33% | 59.1% |
| UCB, stall 8000 | 3.75× | 42.2 | 0.61 / 0.52 | 19% | 49.3% | 1.33% | 67.1% |
| UCB + MAST | 1.58× | 35.9 | 0.58 / 0.45 | 15% | 47.7% | 1.33% | 64.0% |
| UCB + MAST, stall 500 | 0.39× | 29.3 | 0.52 / 0.37 | 13% | 46.3% | 1.33% | 60.4% |
| UCB + MAST, persistent | 1.06× | 13.4 | 0.41 / 0.17 | 13% | 40.7% | 1.33% | 48.2% |
| NMCS level 1, 25% | 0.03× | 8.6 | 0.31 / 0.11 | 9% | 33.3% | 1.00% | 32.9% |
| NMCS level 1, repeated | 1.01× | 27.3 | 0.50 / 0.31 | 16% | 44.3% | 2.00% | 55.5% |
| NMCS level 2, 25% | 1.00× | 32.1 | 0.60 / 0.40 | 18% | 49.0% | 1.33% | 62.2% |
| NRPA | 1.03× | 17.5 | 0.40 / 0.18 | 12% | 48.7% | 2.00% | 61.6% |
| NRPA, 4× budget | 4.07× | 41.4 | 0.60 / 0.36 | 18% | 64.3% | 3.00% | 86.0% |
| NRPA persistent | 1.23× | 19.2 | 0.39 / 0.18 | 9% | 59.0% | 1.67% | 77.4% |
| GNRPA conflict prior | 1.06× | 17.5 | 0.38 / 0.18 | 11% | 48.7% | 1.67% | 58.5% |
| NRPA context codes | 1.06× | 14.3 | 0.34 / 0.16 | 11% | 32.0% | 1.33% | 32.9% |

\* Reaches the best completion possible within the 25% window, among calls where that beats the source.

Back-to-back combinations (union of results, times added):

| Combination | Time | Variants found | Pooled recall | Beats source | Beats max | Reaches best* |
|---|---|---|---|---|---|---|
| UCB + NMCS level 1 | 1.03× | 34.2 | 0.43 | 45.3% | 1.33% | 59.1% |
| UCB + (UCB + MAST, stall 500) | 1.39× | 41.1 | 0.51 | 48.7% | 1.33% | 68.9% |
| (UCB + MAST, stall 500) + NRPA | 1.42× | 36.9 | 0.42 | 56.0% | 2.33% | 77.4% |
| UCB + NRPA | 2.03× | 41.2 | 0.47 | 55.0% | 2.33% | 76.2% |

Findings:
- **Completeness and finding better games pull in different directions.** Random-rollout methods (UCB, MAST) find the most variants; policy-learning methods (NRPA) find fewer variants but improve on the source far more often.
- **MAST playouts are the most efficient way to find variants:** with stall 500, 86% of the current method's variants in 39% of the time.
- **Cross-call policy learning works:** persistent NRPA beats plain NRPA (59% vs 49% of calls improve on the source; 77% vs 62% reach the best possible) at similar time. Persistent MAST does worse: its stale statistics narrow the completions.
- **The context codes and the conflict prior don't help.**
- **Combinations get the best of both:** UCB plus MAST(stall 500) matches stall-8000 completeness (41 variants, recall 0.51) at 37% of its time. MAST(stall 500) plus NRPA finds more variants than the current method (37 vs 34) and improves on the source far more often (56% vs 45%; reaches best 77% vs 59%), at 1.42× the end_search time.

A first 30-minute A/B round of plain NRPA vs UCB (4 seeds, stopped early) was inconclusive: UCB 156 162 159 157, NRPA (6 ms) 152 158 170 157, NRPA (24 ms) 158 150 160 157.

### Combined end_search modes, end to end (2026-10-08): **Null / Rejected**
A/B at 30 min × 12 paired seeds, 2026-10-07 defaults. New modes (off by default): `es_mode=:ucb_then_mast` (UCB, then UCB with MAST completions at `es_mast_stall_rollouts=500`, results merged) and `:mast_then_nrpa` (that MAST pass, then `end_search_nrpa` at 6 ms).

| Arm | Final scores | Mean (median) | sd | Mean best at 5 / 10 / 20 / 30 min | Time in end_search | Calls raising the max |
|---|---|---|---|---|---|---|
| UCB (current) | 159 152 162 158 172 160 161 154 156 176 157 162 | 160.8 (159.5) | 7.0 | 152.5 / 155.2 / 159.2 / 160.8 | 2.9% | 19.3 |
| UCB then MAST | 158 159 157 160 159 161 161 158 156 161 160 160 | 159.2 (159.5) | 1.6 | 155.8 / 156.8 / 158.7 / 159.2 | 5.2% | 19.8 |
| MAST then NRPA | 159 161 159 174 141 157 160 117 158 157 157 157 | 154.8 (157.5) | 13.9 | 150.3 / 151.8 / 154.0 / 154.8 | 4.1% | 24.7 |

Per seed vs UCB: UCB then MAST −1.6 [−5.3, +1.7] (median 0; better 5, worse 5, tied 2); MAST then NRPA −6.0 [−14.9, +1.9] (median −2; better 3, worse 7, tied 2).

- **The offline gains didn't carry over,** again. MAST then NRPA raised the max more often (24.7 vs 19.3 calls per run) yet finished lower, with two stuck runs (141, 117) alongside a 174.
- **UCB then MAST was remarkably consistent** (156–161 on every seed, never stuck), but it never broke out either: no run above 161. It's ahead early (155.8 vs 152.5 at 5 min) and behind by 30 min.
- **UCB alone produced the two best runs: 172 and 176.** The 176 (seed 1510) wasn't saved, because the A/B runner only recorded scores. Runners should save `max_moves` from now on.
- Recommendation was to keep `es_mode=:ucb`. Switched the default to `:ucb_then_mast` on 2026-10-08 anyway, for its consistency: no stuck runs, sd 1.6.

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

### Julia compiler flags (2026-10-02): **Null**
2 seeds × 4M iterations, each configuration run twice, one run at a time:

| Flags | Time |
|---|---|
| default | 71.5–71.7 s |
| `-O3` | 71.1 s |
| `--check-bounds=no` | 71.2–71.9 s |
| both | 71.8–73.0 s |

All within ±1%, with identical results. The hot loops are already `@inbounds`, and the default `-O2` gets everything `-O3` would.

### Several searches as threads in one process (2026-10-02): measured
8 seeded searches × 4M iterations, run either as `Threads.@spawn` tasks in one `julia -t 8` process or as 8 separate processes:
- **Same results:** identical scores per seed. Julia's RNG is task-local, so each task seeds its own.
- **Same throughput:** 40.7 s wall with threads, 35–40 s per process.
- **Much less memory:** 502 MB peak for the threaded process against about 330–360 MB *each* for separate processes (~2.7 GB total). The runtime and compiled code are shared.

Threads don't speed up a single search; the main loop is sequential.

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

### Packed storage and move order (2026-10-04): **Adopted** (default since 2026-10-04)
`dna_storage=:pack` stores each perm as a bit-packed set of lines, using the scheme `generate_pack` uses: one bit per candidate move considered in a canonical replay. A 178-move game takes 41 bytes. Decoding returns the canonical order, so a perm's move order is lost, and so is the drift through orders that moves-only storage has: same-dots reordered children get adopted on about 9% of iterations.

Fast codec: 12 µs to decode or encode, with no allocation. Optional `DecodeCache` of decoded moves (`pack_cache_size`, CLOCK replacement, default 16,384 slots). Results are identical with or without the cache.

A/B at 10 min × 12 paired seeds, 2026-10-04 defaults (`idle_reset=128`, `improvement_step_up=100`, so pools stay at about 1–2k perms):

| Arm | Mean (median) final | Mean best at 2 / 5 / 10 min | Iterations/s | Bytes per perm |
|---|---|---|---|---|
| moves (default) | 152.5 (155.0) | 148.0 / 151.2 / 152.5 | 88k | 907 |
| pack, no cache | 156.5 (157.0) | 151.9 / 154.8 / 156.5 | 39k | 197 |
| pack, 16k cache (98.6% hits) | 156.9 (157.5) | 154.4 / 156.6 / 156.9 | 86k | 197 + cache |

- **Pack + cache vs moves:** +4.4 [−0.1, +11.8] at equal time (median +2; better on 7 seeds, worse on 4, tied on 1).
- **Uncached pack vs moves:** +4.0 [−0.2, +11.0] at equal time, and +5.8 [+1.4, +12.5] at equal iterations.
- **Caveat:** part of the mean gap is one stuck moves run (117); the medians differ by 2.

Conclusions:
- **Move order isn't load-bearing.** A fixed canonical order is at least as good, and possibly slightly better. Even with 56% fewer iterations, uncached pack matched moves.
- **The cache removes the speed cost:** 86k vs 88k iterations/s.
- **Memory hardly matters at these settings:** pools are ~1–2k perms (about 1 MB under moves), so peak RSS was ~355–362 MB in every arm. With small pools the cache holds every perm's moves anyway; the saving only appears with large pools (e.g. `improvement_step_up=10000`, 50k+ perms).

### Keying configurations by lines instead of dots (2026-10-05): **Rejected**
`config_key=:lines` makes the set of lines drawn, rather than the set of dots placed, a configuration's identity. That covers the pool index, the end_searched set, the child-is-its-parent check, and end_search's own dedup (`lines=true`). Games that place the same dots with different lines (about 18 per point set) become separate perms instead of being merged.

A/B at 10 min × 12 paired seeds, 2026-10-04 defaults (packed storage):

| Key | Final scores | Mean (median) | Pool at 5 / 10 min | end_search calls raising the max | Time in end_search | Iterations |
|---|---|---|---|---|---|---|
| points (default) | 158 157 152 158 157 162 159 156 159 159 132 155 | 155.3 (157.5) | 1.2k / 1.9k | 19.6 | 6.4% | 53.1M |
| lines | 157 158 151 146 140 129 134 111 139 147 124 117 | 137.8 (139.5) | 42k / 114k | 9.2 | 11.4% | 44.5M |

Lines − points: −17.6 [−26.0, −9.6] at equal time, and −17.4 [−25.8, −9.4] at equal iterations, worse on 11 of 12 seeds. Line variants flood the pool (60× more perms), which spreads selection over lateral copies of the same dot sets. end_search also spends nearly twice the time and raises the max half as often. Merging by dots works as useful dedup; keep `:points`. A longer `:lines` run (2026-10-05) confirmed that the index keeps growing.

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
