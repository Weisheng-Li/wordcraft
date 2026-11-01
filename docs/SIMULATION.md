# Wordcraft — Simulation and balance metrics

Part of the design docs. Hub: [DESIGN.md](DESIGN.md) (§15).

The simulation plays **bot vs bot** rounds with no window, much faster than real time, and reports balance metrics. It complements playtesting:
- **Playtesting** shows whether the bot behaves like a person. Fix the bot's rules when it doesn't.
- **The simulation** shows how the rules play out over hundreds of rounds, as that bot plays them.

**The numbers describe the rules as the bot plays them.** They point at problems; they don't prove them. To check a finding, play against the bot and see whether it holds.

---

## Running it

```
lovec . --sim 400 [--seed 1] [--cap 300] [--p1 PROFILE] [--p2 PROFILE]
```

| Option | Meaning |
|---|---|
| `--sim N` | Number of rounds (default 200) |
| `--seed N` | Random seed. The same seed and code give the same rounds, so before/after comparisons use the same games. |
| `--cap S` | A round that hasn't ended after `S` seconds of fight time is stopped and counted as "no winner" (default 300). |
| `--p1`, `--p2` | Bot profile for that side, from `botProfiles` in `data/tuning.json` (default: the plain `bot` settings) |

- **Speed:** about 2.7 s per round (a round averages ~170 s of game time, at a fixed 60 steps per second). 400 rounds take about 18 min. Each run uses one CPU core, so several runs can go in parallel.
- **Output:** a report in the console, plus a CSV saved to LÖVE's save folder (`%APPDATA%\LOVE\wordcraft\sim_<p1>_vs_<p2>_seed<n>.csv`).
- **Profiles** override any `bot` number for one side, and can list `avoidWords` the bot never picks up, e.g. `"noAccelerate": { "avoidWords": ["accelerate"] }`. They're used for A/B runs.

## How it works

- **Code:** `src/sim.lua`.
- **Events:** the rules report what happens through `Game.onEvent`, which is off in normal play. The events are `complete`, `timeout`, `effectEnd`, `trapFired`, `spell`, `laser`, `pickup` and `wave`.
- **Tagging:** every finished template gets an **effect** record (its stacked kinds, level and word count). Every spell it casts carries that record (and, for traps, the condition that set it off). So a beam is always credited to the template that launched it, even if it lands after the effect window closed.
- **Pickups** are reported before they're applied, so a pickup that completes a template still counts inside the window it closes.

## Concepts

- **Shape:** what a template is made of, as its stacked template kinds sorted, e.g. `combo+when`. A shape belongs to one level (number of kinds).
- **Effect window:** from when a template completes until its effect ends, i.e. until the player's next template completes or times out (DESIGN §8). **A trap's window opens when it's armed**, not when it fires, so it gets credit for the pressure it creates while waiting.
- **Current return:** what the template did directly: **damage** its beams dealt plus **hits its shield charges blocked**. Per cast, and per word as `ret/word = (damage + blocked) / words`.
- **Future return (pickup share):** of all the words picked up during the effect window, the share the caster got: `mine / (mine + theirs)`.
  - Example: you finish `repeat 3: cast accelerate`, and until your next template ends you pick up 3 words while the enemy picks up 1. That window's share is 75%.
  - Pickups are **summed over all windows of a shape before dividing**. Single windows are short, and "1 vs 0" or "0 vs 0" would make per-window ratios jump around.
  - **Compare against the overall average, not 50%.** Right after you finish a spell your next template is fresh, while the enemy may hold more open blanks. That shifts the baseline away from 50% regardless of the spell.

## Report sections

### 1. Rounds
| Metric | Notes |
|---|---|
| Length: average, median, 10% and 90% marks | Pacing. A long 90% tail means stalemates. |
| Win rate P1 / P2 / draw / no winner | Mainly for A/B runs between profiles. The same bot on both sides should come out about 50/50; if not, something is unfair. At 400 rounds, one standard error is about ±2.5 points. |

### 2. Finished templates
One table **by shape** and the same numbers **summed by level**, plus an overall row.

| Column | Meaning |
|---|---|
| done | Templates completed (cast or trap armed) |
| t/out | Share of this shape that timed out instead. At level 3, a timeout means the words were lost. |
| words | Average words spent |
| window | Average effect window length |
| dmg, blocked | Average damage dealt and hits blocked per completion |
| ret/word | Current return per word |
| picks | Future return (pickup share) |

There's deliberately no per-spell breakdown inside templates. The three spells are compared through win-rate A/B runs and the combat section instead.

### 3. Beam hit rate by what fired it
For every beam: hit / blocked by shield / dodged by dash / stopped by a wall. Rows: `plain cast` (from a non-trap template) and one row per **trap condition that set it off**. Traps exist to make attacks land, so a condition that doesn't beat the plain-cast hit rate isn't doing its job.

### 4. Word spawning
| Metric | Notes |
|---|---|
| Waves, gap between waves (average, 10%/90%) | |
| Pulled early | Share of waves brought forward because the board was dead (nothing on it fits anyone) |
| Leftovers per wave | Words still on the floor when the next wave clears them |
| **One-sided board** | Words are on the floor, both players hold a template, and **only one player can use anything there**, so the other has nothing to pick up. Reported as: share of fight time, number and length of stretches, what ended each one (that player's pickup, the next wave, other, round end), and what was on the floor (condition only / spell only / mixed). |

### 5. Combat
| Metric | Notes |
|---|---|
| Beams per round, and results overall | hit / blocked / dodged / wall |
| Shield charges | Gained per round, share used (blocked a beam), share that expired unused |
| Accelerate | Stacks gained per round, share of the time it's active, average stacks while active, **pickups per minute while accelerated vs normal** |

### CSV columns
One row per finished or timed-out template: `round, player, shape, level, result (cast / trap / timeout), words, window, damage, blocked, fired (trap firings), mine, theirs`. Use it for any group-by the report doesn't do.

## Value of a spell or rule: A/B win rate

Some value is indirect. Speed, for example, means more words, which means more casts later. Per-template numbers miss that. **The overall measure is how much the win rate drops when one side stops using something.** Run a profile on one side (e.g. `--p1 noAccelerate`) against the default bot and compare P1's win rate with the same-bot baseline. At 200 rounds, differences under about ±7 points are noise.

---

## Results log

Newest first. Each entry records the bot version, because bot changes shift every number.

### 2026-10-31 — first baseline

- **Setup:** 400 rounds, seed 1, default vs default, cap 300 s. A/B: 200 rounds each with P1 `noAccelerate` (seed 2) and P1 `noShield` (seed 3).
- **Game:** template timeouts 7.5 / 12 / 16.5 s, waves every 6 s.
- **Bot:** hides behind walls from lasers (no reflex dash), dashes only to win word races. It still moves and dashes in **any direction**; a keyboard player only has 8. Limiting the bot to 8 directions is the next change, so rerun after it.

| Finding | Numbers | Reading |
|---|---|---|
| **Walls decide the game** | 64% of beams stopped by walls; 23% hit, 13% blocked, 0.2% dodged. Rounds avg 168 s (10% 108 s, 90% 234 s). | Largely the bot's perfect cover-seeking within the 1 s laser warning. Check in play whether people hide this reliably. |
| **`when` is weak at every level** | ret/word `when` 0.07 vs `combo` 0.20 vs `repeat` 0.52; pickup share `when` 44.8% (overall 49.8%) | Holding a trap costs pickups (the bot stands still or walks to you), and its beam doesn't land more often (next row). |
| **Traps don't improve hit rate** | Hit rate: plain cast 23%, `close` 22%, `still` 23%, `dash` 20%, `hit` 15% | A trap's beam still has the full 1 s warning after it triggers, so the timing advantage is gone. Ideas: a shorter warning for trap beams, or trap beams ignore the first wall. |
| **`repeat` is the most efficient template** | ret/word 0.52 (1 word for 2–5 casts); `repeat+repeat` 0.54 | Not broken; the template to beat. |
| **Stacking is rare and doesn't pay per word** | Level 1: 89% of finished templates, ret/word 0.22. Level 2: 10%, 0.19. Level 3: 0.8%, 0.21. Only 11% of templates time out. | A bigger stack hits harder but is no better per word spent. |
| **The 6 s wave timer barely matters** | 91% of waves pulled early by a dead board; real gap avg 3.6 s; 0.0 leftovers per wave | Bots empty the board almost instantly. Humans are slower, so the timer matters more in real play. |
| **One-sided board is small** | 5.4% of fight time, avg 1.4 s (90% 3.0 s); 93% a lone condition; 92% ended by the other player's pickup | No rule change needed yet. |
| **Shields mostly wasted** | 39 charges per round; 24% used, 75% expire unused | Short effect windows (avg 4.4 s), and the bot hides instead of tanking. |
| **Accelerate works** | ×1.45 pickup rate while active; some speed active 21% of the time | |
| **Neither shield nor speed changes who wins** | P1 win rate: baseline 45.8%, `noAccelerate` 54.5%, `noShield` 51.5% | Within noise (±7). Under bot play the game is `attack` plus cover. |
| **P1/P2 fairness: watch** | Same bot both sides: P1 45.8%, P2 54.0% | About 1.6 standard errors; not conclusive, but matches earlier runs. P1 always updates first each frame, a possible cause. Recheck. |
