# Wordcraft — Simulation and balance metrics

Part of the design docs. Hub: [DESIGN.md](DESIGN.md) (§15).

The simulation plays **bot vs bot** rounds with no window, much faster than real time, and reports balance metrics. It complements playtesting:
- **Playtesting** shows whether the bot behaves like a person. Fix the bot's rules when it doesn't.
- **The simulation** shows how the rules play out over hundreds of rounds, as that bot plays them.

**The numbers describe the rules as the bot plays them.** They point at problems; they don't prove them. To check a finding, play against the bot and see whether it holds.

---

## Running it

```
lovec . --sim 1m [--stats] [--workers N] [--cap 300] [--p1 PROFILE] [--p2 PROFILE] [--c1 CHARACTER] [--c2 CHARACTER]
```

| Option | Meaning |
|---|---|
| `--sim N` / `--sim Mm` | Play `N` rounds (default 200), or as many as fit in `M` minutes (e.g. `1m`, `10m`). Rounds still being played when time runs out are finished and counted. |
| `--stats` | Also rewrite [STATS.md](STATS.md) with the report (see "Stats history" below) |
| `--workers N` | Worker threads (default: one per logical CPU core) |
| `--cap S` | A round that hasn't ended after `S` seconds of fight time is stopped and counted as "no winner" (default 300). |
| `--p1`, `--p2` | Bot profile for that side, from `botProfiles` in `data/tuning.json` (default: the plain `bot` settings) |
| `--c1`, `--c2` | Character for that side, an id from `data/characters.json` (default: `wizard`). Note the report adds both sides together; the CSV has a `player` column for per-side numbers. |

- **Speed:** rounds are spread over worker threads, one per logical CPU core. On the dev machine (8 cores, 16 threads) that's about **145 rounds per minute**: ~150 rounds in 1 min, ~1,450 in 10 min. 16 threads measured 15% faster than 8. One round alone takes about 2.7 s (a round averages ~160 s of game time, at a fixed 60 steps per second).
- **Seeds:** every run uses a fresh random seed, so two runs of the same code give slightly different numbers. That difference is what the ± measures.
- **Output:** a report in the console, plus two CSVs saved to LÖVE's save folder: `%APPDATA%\LOVE\wordcraft\sim_<p1>_vs_<p2>.csv` (one row per template) and `sim_<p1>_vs_<p2>_rounds.csv` (`round, length, winner`).
- **Profiles** override any `bot` number for one side, and can list `avoidWords` the bot never picks up, e.g. `"noAccelerate": { "avoidWords": ["accelerate"] }`. They're used for A/B runs. **Strategy profiles** also turn on flags that make the bot hold off on words (see "Strategy bots" in the results log). They're for testing only: the bot you play against (F3) is always the plain one.
- **A/B against the plain bot:** run the profile once as P1 and once as P2 (`--p1 X`, then `--p2 X`, 2 min each, ~1,000 rounds together) and add up its wins. That cancels any side bias. ±1.6 points; a profile needs about 53% to beat the plain bot for real.

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

### 6. Reading load
How much text a player has to take in at once: the words in **both** players' templates plus the words on the floor. Template words count every word of the HUD text, blanks included, filled or not: `when ___, cast ___` is 4, `repeat 3: cast ___` is 4. The trap row isn't counted.

| Metric | Notes |
|---|---|
| Average | Over fight time, with the template and floor parts split out |
| Median, 10%, 90%, max | From a sample every 0.5 s. The 90% mark is the busy moments. |

### CSV columns
One row per finished or timed-out template: `round, player, shape, level, result (cast / trap / timeout), words, window, damage, blocked, fired (trap firings), conditions (a trap's condition set), mine, theirs`. Use it for any group-by the report doesn't do.

## Value of a spell or rule: A/B win rate

Some value is indirect. Speed, for example, means more words, which means more casts later. Per-template numbers miss that. **The overall measure is how much the win rate drops when one side stops using something.** Run a profile on one side (e.g. `--p1 noAccelerate`) against the default bot and compare P1's win rate with the same-bot baseline. Use a big (10 min) run: a small one only shows differences over about 10 points.

---

## Results log

Newest first. Each entry records the bot version, because bot changes shift every number. Raw numbers for every gameplay commit are in the history of [STATS.md](STATS.md).

### 2026-11-05 — Bulwark parry rewards: shield charge vs heal

- **Question:** with expiring shields and 5 HP, Bulwark (id `shieldmage`) lost 41 / 59 to the Spellslinger (`wizard`). Which reward for a successful parry fixes that? Options under `characters.shieldmage.parry`: `shieldOnParry` (charges per successful parry press, ordinary ones that end with the effect window) and `healOnParry` (HP per press, up to full). Same bots as the entry below; 1,000 rounds per row, Spellslinger P1.
- **Result:**

  | Parry reward | Spellslinger wins | Bulwark wins | Median round | Hits on Bulwark / round | Hits on Spellslinger / round |
  |---|---|---|---|---|---|
  | None | 59.1% | 40.9% | 97 s | ~4.1 | ~7.3 |
  | +1 shield charge | 48.4% | 51.4% | 106 s | ~3.8 | ~7.9 |
  | +1 HP | 16.8% | 83.0% | 124 s | ~5.2 (most healed back) | ~9.3 |
  | +1 HP, Bulwark max HP 3 | 49.1% | 50.8% | 95 s (10%: 34 s, 90%: 169 s) | ~3.9 | ~7.1 |

- **Reading:** a charge on parry is roughly even (within ±1.6) and keeps rounds near the mirror's length. A heal at 5 HP undoes damage already taken: Bulwark parries ~10 times a round, so it out-heals the Spellslinger's ~5 hits and the rounds drag. Heal with max HP 3 is also even, but swingier: the shortest 10% of rounds end by 34 s (three quick hits before a parry lands) and the longest 10% run past 169 s (a parrying Bulwark that keeps topping up).

### 2026-11-04 — Bulwark vs wizard, balance

- **Setup:** wizard (P1) vs Bulwark (P2), plain bots with human limits; the mage bot parries noticed beams with ~80% timing (`parryJitter`). 1,000 rounds per row. Mage: 5 HP, parry `0.25 s` window, no cooldown on success.
- **Result:**

  | Mage shields | Wizard wins | Mage wins | Median round | Wizard hits on mage / round | Mage hits on wizard / round |
  |---|---|---|---|---|---|
  | Lasting, decay `40 / n` | 11.2% | 88.6% | 126 s | ~1.8 | ~9.7 |
  | Expire (kept) | 59.1% | 40.9% | 97 s | ~4.1 | ~7.3 |

  (Wizard mirror for reference: 51 / 49, median 111 s.) With expiring shields ~18% of all beams are parried; the mage picks up ~5% fewer words than the wizard (no dash for word races).
- **Reading:** lasting shields were what made the mage dominant, not the parry. With the wizard's shields and 5 HP it is now slightly weak against the bot; rounds are shorter because 5 HP goes quickly. HP 6 is the obvious next try.

### 2026-11-04 — lasting, decaying shields (wizard mirror)

- **Question:** the Bulwark briefly had shield charges that outlast the effect window and decay instead (with `n` charges the next goes after `40 / n` s). Would that rule be good for the game in general? Run with the rule given to both wizards (`characters.wizard`: `shieldLasts`, `shieldDecay` 40) vs the normal expiring charges. Plain bots with human limits, 1,000 rounds each, `--c1`/`--c2` both wizard.
- **Result:**

  | | Expire (kept) | Decay (`40 / n` s) |
  |---|---|---|
  | Round length, median | 111 s | 187 s (+70%) |
  | Stopped at the 300 s cap | 0% | 9.1% |
  | Beams per minute | ~29.5 | ~30.6 |
  | Beams: hit / blocked / wall | 29% / 13% / 57% | 15% / 40% / 44% |
  | HP hits per minute | ~8.6 | ~4.7 |
  | Shield charges that block something | 23% | 70% |
  | Return per word, level 1 / level 3 | 0.37 / 0.37 | 0.50 / 0.21 |
  | Reading load | 10.6 | 10.5 |

- **Reading:** same casting pace, but charges that last get used, so damage per minute halves and rounds drag (1 in 11 hits the cap). Cheap shield templates (`repeat` 0.84 per word) beat big stacked attacks (level 3 drops to 0.21), so stacking loses its point. Bots with a covering shield stack don't hide, so fewer beams hit walls: a more static, defensive game.
- **Decision:** dropped for every character; shields expire with the effect window. The rule stays as a per-character option for experiments. A much faster decay (~10–15) might be a middle ground, untested.

### 2026-11-01 — strategy bots: what beats the plain bot

- **Question:** the plain bot plays common sense and takes any word that fits. Which strategies win more against it by playing the rules (not by exploiting the bot)? Same rules and human limits as the 2026-11-01 run below.
- **Mirror check first:** plain vs plain, 10 min, 2,569 rounds: P1 49.2%, so **no side bias** (the earlier P2 lean was noise). Win rate across chunks of that run: 100 rounds 43–60%, 200 rounds 44–55%, 400 rounds 45–54%, 700 rounds 47–52%. So the A/B setup above uses ~1,000 rounds, with the profile on both sides.
- **Results** (profile's win rate vs the plain bot; flags in `src/bot.lua`, profiles in `botProfiles`):

| Profile | What it does | Win rate |
|---|---|---|
| `attackLast` | The last spell blank of any template only takes `attack` | **64.5±1.5%** |
| `best` | `attackLast` + attack pull 3, more race dashes, keep contesting | 63.5±1.2% |
| `alNoShield` | `attackLast` + never take `shield` | 61.4±1.5% |
| `afAttack3` | `attackFirst` with attack pull 3 | 60.6±1.5% |
| `afNoAccel` | `attackFirst` + never take `accelerate` | 60.3±1.5% |
| `afNoShield` | `attackFirst` + never take `shield` | 59.4±1.5% |
| `afContest` | `attackFirst` + don't give up words the enemy is closer to | 59.1±1.5% |
| `afRace` | `attackFirst` + dash for contested words much more often | 58.9±1.6% |
| `afDeny` | `attackFirst` + 3× bonus for taking words the enemy needs | 57.3±1.6% |
| `attackFirst` | `valueSpells` + attack pull 1.5 (was 0.3) | 57.2±1.9% |
| `valueSpells` | A `repeat`'s spell blank only takes `attack` | 55.6±1.6% |
| `afNoChase` | `attackFirst` + don't walk at the enemy to set off a `close` trap | 54.5±1.6% |
| `lateFinish` | While trap/shield/speed is up, hold the last blank until 2 s are left | 49.4±2.0% |
| `stackRepeat` | Don't fill a level-1 `repeat`; let it stack | 47.6±1.6% |
| `stackWeak` | Don't fill a level-1 `combo` or `when`; let it stack, hoping for a `repeat` | 42.2±1.6% |

- **Reading:**
  - **One dominant rule: every finished template should carry an `attack`.** Saving the last spell blank for `attack` beats common sense about 2 to 1. Nothing else adds to it: word-grabbing tweaks (deny, race, contest) are worth ≤ 2 points each and don't stack on top of `attackLast`.
  - **Shield and speed have little value of their own.** Skipping them costs little or even helps (`afNoAccel`, `afNoShield` ≥ `attackFirst`); they're only worth taking in a blank that isn't the attack's. Cause: they last only until the next template completes or times out (avg window 5 s), so finishing fast cuts your own buffs short, and 75% of shield charges expire unused. Next step: give them value of their own (e.g. their own timer).
  - **Waiting to stack doesn't pay.** `stackWeak` gets 0.92 damage per cast vs the plain bot's 0.49, but finishes under half as many templates (4,077 vs 8,682) and deals less in total. Level 3 returns 0.40 per word vs 0.36 at level 1, not enough to cover the timeout spent waiting. Holding the last blank (`lateFinish`) breaks even: the longer trap window is lost on words the enemy takes meanwhile, and walking over a word picks it up anyway.
  - **Chasing for `close` traps pays** (not chasing: −3 points).

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
