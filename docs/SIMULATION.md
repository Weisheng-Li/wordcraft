# Wordcraft — Simulation and balance metrics

Part of the design docs. Hub: [DESIGN.md](DESIGN.md) (§15).

The simulation plays **bot vs bot** rounds with no window, much faster than real time, and reports balance metrics. It complements playtesting:
- **Playtesting** shows whether the bot behaves like a person. Fix the bot's rules when it doesn't.
- **The simulation** shows how the rules play out over hundreds of rounds, as that bot plays them.

**The numbers describe the rules as the bot plays them.** They point at problems; they don't prove them. To check a finding, play against the bot and see whether it holds.

---

## Running it

```
lovec . --sim 1m [--stats] [--workers N] [--cap 300] [--p1 PROFILE] [--p2 PROFILE]
```

| Option | Meaning |
|---|---|
| `--sim N` / `--sim Mm` | Play `N` rounds (default 200), or as many as fit in `M` minutes (e.g. `1m`, `10m`). Rounds still being played when time runs out are finished and counted. |
| `--stats` | Also rewrite [STATS.md](STATS.md) with the report (see "Stats history" below) |
| `--workers N` | Worker threads (default: one per logical CPU core) |
| `--cap S` | A round that hasn't ended after `S` seconds of fight time is stopped and counted as "no winner" (default 300). |
| `--p1`, `--p2` | Bot profile for that side, from `botProfiles` in `data/tuning.json` (default: the plain `bot` settings) |

- **Speed:** rounds are spread over worker threads, one per logical CPU core. On the dev machine (8 cores, 16 threads) that's about **145 rounds per minute**: ~150 rounds in 1 min, ~1,450 in 10 min. 16 threads measured 15% faster than 8. One round alone takes about 2.7 s (a round averages ~160 s of game time, at a fixed 60 steps per second).
- **Seeds:** every run uses a fresh random seed, so two runs of the same code give slightly different numbers. That difference is what the ± measures.
- **Output:** a report in the console, plus a CSV saved to LÖVE's save folder (`%APPDATA%\LOVE\wordcraft\sim_<p1>_vs_<p2>.csv`).
- **Profiles** override any `bot` number for one side, and can list `avoidWords` the bot never picks up, e.g. `"noAccelerate": { "avoidWords": ["accelerate"] }`. They're used for A/B runs.

## Stats history

[STATS.md](STATS.md) holds the report of the latest `--stats` run, headed only by its round count. When a gameplay change (rules, tuning, bot) is committed, the user asks for one of two runs, and the new STATS.md goes into the same commit:

| Run | Command | Rounds | Good for |
|---|---|---|---|
| Small | `lovec . --sim 1m --stats` | ~150 | "Did this change do what I expected, and break nothing?" Beam hit rates, shield/speed and wave numbers are precise; ret/word and pickup share of level-1 shapes are good; round length to ±4 s; win rate only to ±4 points. |
| Big | `lovec . --sim 10m --stats` | ~1,450 | Win rate (±1.3 points): A/B profiles, P1/P2 fairness. Level-2 and level-3 shapes. |

`git log -p docs/STATS.md` then shows how each change moved the numbers, and checking out a commit shows the rules that produced them. Interpretation still goes in the results log below.

### Reading ±

Every average and share comes with **± one standard error**: roughly how far that number would move if the same code were run again. It's computed from how much the number varies **between rounds** (rounds are the independent samples; beams or pickups within one round aren't).
- A change between two runs is real if it's clearly bigger than both ±s combined. About 2× is a safe bar. Round length going from 168±4 s to 150±4 s is real; 168±15 to 160±15 isn't.
- More rounds shrink the ±: 4× the rounds halves it.
- Rare shapes (most level-3 ones) have a wide ±, or none when only one round had them. Don't read much into them from a small run.
- Quantiles (median, 10%/90%) and counts have no ±.

## How it works

- **Code:** `src/sim.lua` (rules and report, no `love.*`), `src/simjobs.lua` (hands out rounds to threads) and `src/simworker.lua` (the thread).
- **Threads:** each worker loads the data itself, plays the rounds it's handed, and sends each round's stats back as one self-contained record. The main thread merges all records and computes every metric once, over all rounds, so the report is the same as if one thread had played them all.
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
| Win rate P1 / P2 / draw / no winner | Mainly for A/B runs between profiles. The same bot on both sides should come out about 50/50; if not, something is unfair. |

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

**Traps by condition** (under section 3): one row per armed trap's condition set (e.g. `close`, `dash/still`).

| Column | Meaning |
|---|---|
| traps | Traps armed |
| fired | Average firings per trap |
| armed | Average time armed, i.e. its effect window, until the next template ends |
| per min | Firings per minute while armed. Together with `armed`, this shows how often the trigger comes up. |

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
One row per finished or timed-out template: `round, player, shape, level, result (cast / trap / timeout), words, window, damage, blocked, fired (trap firings), conditions (a trap's condition set), mine, theirs`. Use it for any group-by the report doesn't do.

## Value of a spell or rule: A/B win rate

Some value is indirect. Speed, for example, means more words, which means more casts later. Per-template numbers miss that. **The overall measure is how much the win rate drops when one side stops using something.** Run a profile on one side (e.g. `--p1 noAccelerate`) against the default bot and compare P1's win rate with the same-bot baseline. Use a big (10 min) run: a small one only shows differences over about 10 points.

---

## Results log

Newest first. Each entry records the bot version, because bot changes shift every number. Raw numbers for every gameplay commit are in the history of [STATS.md](STATS.md).

### 2026-11-01 — repeating traps, `hit` removed, 0.75 s recharge

- **Setup:** small run (1 min, 237 rounds), default vs default. Traps now fire every time their condition holds until the effect window ends. `close`/`still` recharge 0.75 s. `I get hit` is removed. An in-between run (212 rounds, 2 s recharge, `hit` still in) gave `when` ret/word 0.17 and `close`/`still`/`dash`/`hit` 1.51/1.75/2.54/0.50 firings per trap.
- **Reading:** `when` ret/word 0.27±0.01 (was 0.10), level with `combo` (0.25); `repeat` still strongest (0.68). Firings per trap: `close` 2.34, `still` 2.63, `dash` 2.53. Trap beams hit 27.8% vs 31.2% for plain casts. Cost: `when` picks 42.1% (was 45.5) and timeouts 24.8%, as the bot keeps its traps firing instead of collecting. Rounds 109±2 s (was 127).
- **P1/P2:** 43.9/56.1 ±3.2. The P2 lean is back (the in-between run had 50.5/49.5). Still worth a big run.

### 2026-11-01 — bot with human limits

- **Setup:** small run (1 min, 201 rounds), default vs default. The bot now has human limits (0.45 s reaction, misses 10% of aim rays, greed for words within 24 px, 0.5 s reading time). Traps still fire once.
- **Reading:** beams land much more often: 31.9±0.5% hit (was 24.6) and 55% stopped by walls (was 63). Rounds are shorter, 127±3 s (was 159). `when` is still the weakest template (ret/word 0.10, picks 45.5%); `repeat` the strongest (0.65). Against the old sharp bot, an earlier A/B (missChance 0.25) lost 16% to 84%.
- **P1/P2 again leans P2:** 42.8/57.2 ±3.5 (first baseline 45.8/54.0, last run 49.1/50.9). Twice now at about 2 standard errors. Worth a big run to settle it.

### 2026-10-31 — 8-direction bot, first STATS.md

- **Setup:** small run (1 min, 159 rounds), default vs default, same rules as the first baseline. The bot now moves and dashes in 8 directions only.
- **Reading:** as expected, nothing moved much. `when` is still the weakest (ret/word 0.08±0.00, picks 45.6±0.4%), `repeat` the strongest (0.53±0.01). Trap beams still hit no more often than plain casts (24.9±0.5%). Round length 159±4 s (was 168). P1/P2 came out 49.1/50.9 ±4.0, so the earlier 45.8/54.0 split may have been noise. A big run would settle it.

### 2026-10-31 — first baseline

- **Setup:** 400 rounds, seed 1, default vs default, cap 300 s. A/B: 200 rounds each with P1 `noAccelerate` (seed 2) and P1 `noShield` (seed 3).
- **Game:** template timeouts 7.5 / 12 / 16.5 s, waves every 6 s.
- **Bot:** hides behind walls from lasers (no reflex dash), dashes only to win word races. It still moves and dashes in **any direction**; a keyboard player only has 8. It was limited to 8 directions right after this run. That wasn't rerun, since the change isn't expected to move these findings much. Rerun before relying on movement-sensitive numbers (word races, pickup share).

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
