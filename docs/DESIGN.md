# Wordcraft — Design (v1 / proof of concept)

Two wizards fight in a top-down arena. Each player has a **spell template** with blanks. Words spawn around the arena; walking over a word that fits one of your blanks fills it. When every blank is filled, the spell is cast (or armed).

Status legend: **Decided** = agreed, build it. **Proposed** = a recommendation that can still change. **Open** = needs a decision before or during building.

---

## 1. View and movement — Decided (numbers Proposed)

- **Perspective:** "2.5D" top-down view tilted toward the camera, like Stardew Valley or Brawl Stars, drawn in plain 2D. Sprites are bottom-anchored and **y-sorted**, so whoever is lower on screen is drawn in front, and each one has a shadow underneath.
- **Movement:** free 8-direction movement on the floor plane. **No grid-locked movement.** Diagonal movement is normalised, so moving diagonally isn't faster.
- **No jumping.**
- **Dash:** a short burst of movement with a cooldown, during which the player is **invulnerable**.

| Dash property | Proposed value |
|---|---|
| Distance / duration | ~48 px over 0.15 s |
| Direction | Current movement direction; if standing still, the direction the wizard faces |
| Cooldown | 2 s |
| Invulnerable | For the whole dash. A laser that would hit a dashing player misses. |
| Walls | Stop the dash. You can't dash through walls. |
| Words | Words you pass over during a dash are picked up as usual. |

- **Players pass through each other** (Proposed). This avoids body-blocking and the extra collision code it needs.
- **Facing:** the sprite flips to match the last horizontal movement. Only side-view art is needed for v1.

## 2. Controls — Decided

| Action | Player 1 | Player 2 |
|---|---|---|
| Move | `W` `A` `S` `D` | `↑` `←` `↓` `→` |
| Dash | `Left Shift` | `Right Shift` |
| Quit | `Esc` | |
| Restart (after a round ends) | `R` | |

Many keyboards can't register lots of keys pressed at once (ghosting), so test with both players mashing keys. Swap keys if needed.

## 3. Arena — Proposed

- The arena fits **one screen** with no camera scrolling. The game renders at 320×180, with a strip at the top reserved for the HUD.
- **Walls are tiles** on a 16 px grid in a **mirror-symmetric** layout: a few blocks to hide behind, and every open floor tile reachable.
- The players start on opposite sides, at mirrored positions.

## 4. Word types — Decided

Every word has exactly one type. Word tiles on the map are colour-coded by type, and so are the blanks in templates.

| Type | Words | Fits into |
|------|-------|-----------|
| **Spell** | attack, shield, accelerate | `cast ___` blanks |
| **Condition** | I dash, I stand still, I get hit, enemy is close, enemy is far | `when ___` blanks |

Conditions go after `when`, and spells go after `cast`.

"I dash" replaces "I jump", because jumping was removed.

## 5. Templates — Decided

| Template | Blanks | Behaviour |
|----------|--------|-----------|
| `when ___, cast ___` | Condition, Spell | Completing it **arms** a trap that fires the spell **once**, the first time the condition is true. |
| `cast ___ and ___` | Spell, Spell | Casts both spells at once when completed. |
| `repeat N: cast ___` | Spell | `N` is rolled when the template is dealt and shown in the template. The wizard **raises the staff N times**; each raise casts the spell (see "Raises" below). |

- Each new template is drawn **uniformly at random** from the three, independently for each player (Proposed).
- `N` is rolled from **2–5**, because `repeat 1` would just be a plain cast.

## 6. Spells — Decided (numbers Proposed)

| Spell | Effect | Proposed numbers |
|-------|--------|------------------|
| **attack** | Auto-aim laser from caster to enemy. Blocked by shield charges and by walls. | 1 damage (Decided) |
| **shield** | Gives one **shield charge** that absorbs the next laser hit. | Lasts until the effect window ends (§8) |
| **accelerate** | Boosts walking speed; **stacks**. Dash distance is unchanged. | +35% per stack, up to 3 stacks, until the effect window ends (§8) |

**Laser telegraph (Decided):** an attack first shows a **thin, flashing aim ray in the caster's colour (blue or red)** toward the enemy for about `1 s`. The ray flashes faster just before firing. Then a **thick beam** fires and deals the damage. A truly instant, auto-aimed laser could only be avoided by already standing behind a wall. The telegraph gives the enemy time to **dash through it** (invulnerability) or **step behind a wall**, which is what makes dash and walls matter.
- The aim line tracks the enemy during the telegraph, and line of sight is checked when the laser fires.
- If a wall is in the way at that moment, the laser stops at the wall and does nothing.

Interactions within **one** template:
- `repeat 3: cast shield` gives 3 charges.
- `repeat 3: cast accelerate` gives 3 stacks (+105% speed). Stacks are capped at 3.
- `cast attack and attack` is a **volley**: one raise, two orbs, two beams that land together. A single shield charge blocks only one of them; one well-timed dash dodges both.

**Raises (Decided):** each raise of the staff casts **every spell after `cast`** once.
- `cast A and B and C` raises **once** and casts all of them together. That makes it fast: the reward for collecting more words.
- `repeat N: cast A and B` raises **N times**, casting A and B on every raise. The staff lowers for `0.35 s` between raises, so you can count them.
- A raise that includes an attack lasts the full 1 s aim, because every beam uses the same aim time to keep dodging learnable. A raise with only shield or accelerate is short (`0.35 s`).
- Shield and accelerate apply **as the staff goes up**; attacks fire when the aim ends.
- Example: `repeat 3: cast attack` is a stream of 3 beams about 1.35 s apart, so a single dash can't avoid them all. `cast attack, attack and attack` is a volley of 3 beams at once, dodgeable with one perfect dash.

## 7. Conditions — Decided (thresholds Proposed)

All conditions depend on player or enemy state, never on map tiles.

| Condition | True when… | Proposed threshold |
|-----------|-----------|--------------------|
| I dash | the caster starts a dash | — |
| I stand still | the caster hasn't moved or dashed for a while | 1.0 s |
| I get hit | the caster **takes damage**. A hit absorbed by a shield or dodged with a dash doesn't count. | — |
| enemy is close | straight-line distance between the players is below a threshold | < 56 px |
| enemy is far | straight-line distance is above a threshold | > 160 px |

**Trigger timing (Proposed):** an armed trap fires on the first frame its condition is true, **including the moment it's armed**. For example, arming `when enemy is far, cast attack` while the enemy is already far fires it right away. It's predictable, and it keeps condition words from feeling useless.

## 8. Templates over time — Decided (numbers Proposed)

### Getting a new template

- Each player is dealt one random template at match start.
- A player gets a new template, after a `0.5 s` delay (Proposed), when **either** of these happens first:
  - they **complete** their current template (cast or armed), or
  - the template **times out** after `15 s` (Proposed). A countdown bar shows the time left.
- On a timeout, the next template **stacks** onto the current one and filled words are kept (see Template stacking below). Words are lost only when a level-3 template times out.

### Effect window: no snowballing

Whatever a completed template produced lasts **only until the player's next template ends**, whether it completes or times out. At that moment the old effect is removed and the new template's effect (if any) takes its place.

| Effect | When the next template ends |
|--------|-----------------------------|
| Shield charges | Unused charges disappear. |
| Accelerate | Speed returns to normal. |
| Armed `when` trap | Disarmed if it hasn't fired. |
| Repeat still raising | The remaining raises are cancelled. Beams already charging still fire. |
| Attack | Instant, so it's unaffected. |

A player has at most **one** active effect at a time, plus a template in progress. A spell fired by a trap counts as that trap's effect, so it lives in the same window.

Example: P1 completes `repeat 4: cast shield` and gets 4 charges. P1's next template times out 15 s later, so any unused charges disappear at that moment.

### Status is always visual

Every status is drawn on the wizard, so both players can read it without looking at the HUD:

| Status | How it shows |
|---|---|
| Shield charges | One cyan **ring** around the wizard per charge, up to 5. Above 5 it becomes **one bold ring with the count** (e.g. `x6`). Display only: there is no cap on charges. |
| Accelerate | **Speed lines** trailing behind, two more per stack |
| Armed trap | A cyan **rune circle** turning on the floor under the wizard. The HUD also names its condition, e.g. `trap: hit > shield`. |
| Casting | **Casting pose** (see below) |
| Dash cooldown | Small grey bar over the head while recharging |
| Hit | Red flash and knockback |
| Laser result | **Floating combat text** over the target: `-1` (hit), `BLOCK` (shield), `DODGE` (dash). Texts from shots that land together stack, so a 3-shot volley shows three. A laser stopped by a wall shows a spark at the wall instead. |

### Casting pose

While the staff is raised, and while any of the player's lasers is still charging, that wizard switches to a **casting frame**: they turn to face the opponent with the **staff raised overhead**. The staff lowers between the raises of a `repeat`. **Each charging attack has its own orb in the caster's colour**: the first on the staff gem, extra ones in a volley arcing over the head. Each orb grows over the 1 s aim and flashes just before its beam fires, and each aim ray and beam starts at its orb, so you can count the incoming shots and see who is attacking. A raise without an attack shows a small gold glint on the gem.

### Template stacking — Decided (numbers Proposed)

When a template **times out**, the next template **stacks onto it** instead of replacing it. A player who doesn't like the words on the map can wait: the spell gets bigger and needs more words, but hits harder.

- **Stack levels:** a fresh template is level 1. Each timeout stacks one more template on, up to **level 3**. If a level-3 template times out, it's discarded (words lost) and a fresh level-1 template is dealt.
- **Completing** a template at any level casts it, and the next template starts again at level 1.
- **Every timeout ends the previous effect**, including a stacking timeout. The effect-window rule above still applies, so waiting never extends an old shield or trap.
- The timeout timer restarts in full at each level.

**Merge rules.** Every template, single or stacked, has the shape `when <conditions>, repeat <N>: cast <spells>`, where the `when` and `repeat` parts are optional.
- Words already collected **stay filled**.
- Condition blanks pile up and are joined with **or**: the trap fires when *any* of them is true.
- Spell blanks pile up into one list: `cast [a], [b] and [c]`. All of them are cast together. (Exception: a second repeat adds no blank; see below.)
- **Two repeats:** the counts **add up** and the second repeat's spell blank is **dropped**: `repeat 5: cast a` + `repeat 5` → `repeat 10: cast a`. Three stacked repeats reach at most `repeat 15`. That keeps stacking a trade-off: another repeat gives **more casts of the same spells**, while `and` gives **more spells per cast**. If the second repeat also added a blank, repeat + repeat would be strictly stronger than repeat + `and`. Big repeats are slow: every raise has its own 1 s aim, so a long stream gives the target time to find cover, and any raises left over are cancelled when the next template ends (§8).
- Example: `when ___, cast ___` + `repeat 3: cast ___` → `when ___, repeat 3: cast ___ and ___`.
- Blanks are filled left to right: conditions first, then spells.

**Showing the level.** The template text and its timeout bar change colour by level: white (1), gold (2), pink (3). The HUD panel flashes when a template stacks up.

## 9. Word spawning — Decided (numbers Proposed)

Words arrive in **waves**.

- **A wave every `12 s`**: close to the 15 s template timeout but slightly shorter. The first wave arrives when the round starts.
- **Taken words are not replaced** until the next wave. **Exception:** if the map is completely empty, the next wave starts right away. Its markers flash for the usual 1 s, and the 12 s timer restarts from that wave.
- **Each new wave clears the previous wave's leftovers.**
- **What spawns (Decided):**
  - **2 spell words, and one of them is always `attack`.** Otherwise players tend to sit and wait for their template to stack.
  - **One condition word per open condition blank** across both players. For example, if both players hold `when ___, cast ___`, two conditions spawn. A filled condition blank doesn't count, and when nobody needs a condition, none spawn.
  - **Every word in a wave is unique.** If more conditions are needed than there are different condition words (5), the wave spawns all 5.
  - The words are chosen when the markers appear, 1 s before landing.
- **Position (Proposed):** random open floor tiles, never inside a wall, at least **40 px** from either player and **24 px** from other words.
- **Warning (Proposed):** spawn markers flash for 1 s before a wave lands.

### Pickup

- Touching a word picks it up **only if it fits an empty blank** in your template, filling the **leftmost** matching blank. Otherwise the word stays on the map, available to the other player.
- **Ties (Proposed):** if both players touch the same word on the same frame, the closer player gets it; if they're equally close, it's random.
- **Denial is intended:** both templates are visible, so grabbing a word your opponent needs is a deliberate strategy.
- **Pickup feedback (Decided):** when a word is picked up, a copy of its tile flies to the picker's head and shrinks, and a ring in the picker's colour (blue or red) bursts where the word was. When both players rush the same word, it's obvious who got it.

## 10. Round flow — Decided

1. "3-2-1" countdown. Players can't move yet.
2. Fight. Each wizard has **10 HP**, and every laser hit removes **1 HP** and **pushes the target back** a little (~14 px), straight away from the shooter. Walls stop the push. A blocked or dodged hit doesn't push.
3. The round ends when one wizard reaches 0 HP. If both reach 0 on the same frame, it's a **draw**. Everything freezes, and a "P1 wins" / "P2 wins" / "Draw" banner appears.
4. Press `R` to restart. Templates, effects, words and HP all reset.

A single round is enough for the POC.

## 11. HUD and readability — Proposed

- Each player's template is shown at the top of the screen, P1 on the left and P2 on the right. Blanks are colour-coded by type, and filled words appear inline.
- Under each template: the active effect (armed trap or accelerate), the HP bar and the template timeout bar.
- **Dash cooldown** is a small **grey** bar (about the width of the wizard) above the player's head, shown only while dash is recharging. It's grey so it isn't confused with health.
- There is no timer for the next wave; the flashing spawn markers are the warning.
- **Word tiles on the map use short labels**, such as `attack`, `shield`, `speed`, `dash`, `still`, `hit`, `close` and `far`, because full phrases like "enemy is close" are too wide at 320×180. The HUD shows the full phrase.
- **Open:** if text is still hard to read, raise the base resolution to 480×270. That's a one-line change in `main.lua`, and the art doesn't need redrawing.

## 12. Data layout — Proposed

To follow the README rule that data lives in JSON:

- `data/words.json`: each word has `id`, `text` (full phrase), `label` (short map label) and `type` (`spell` or `condition`).
- `data/templates.json`: the templates, with their blank types and `kind` (`when`, `combo`, `repeat`), plus the range of `N` for `repeat`.
- `data/tuning.json`: every gameplay number (speeds, timers, distances, HP, spawn rules).
- `data/arena.json`: the wall layout as a text grid, plus spawn points.

**Tuning goal (later):** a playtest mode that reloads `tuning.json` live, without restarting the game. To keep that possible, code reads tuning values every frame from one shared table and never copies them into locals at load time.

## 13. Open questions

- Is text readable at 320×180 with short labels, or should the resolution go up to 480×270? We'll decide once we've played it. (§11)

## 14. Training room — Decided

A sandbox for testing the UI and how templates and words combine. Later it can host a tutorial and give new players a safe place to experiment.

- **Entering:** `F2` toggles between versus and the training room. There's no menu yet.
- **One player** (P1 controls) against a **training dummy**.
- **Tiles by category:** templates (`when`, `and`, `repeat`), spells, and conditions. **Only one category is on the floor at a time; `Space` switches to the next.** Tabs along the bottom of the arena show which one is showing. All categories share one grid (three columns; the first row stays in place, and conditions add a second row underneath), so switching never rearranges the tiles. With no template, the top-left template area says "pick up a template tile". The grey **reset** tile is always there. A tile that appears right under the player when switching counts as already stepped on, so switching never takes a word by accident. The `repeat` tile rolls a random N (2–5) each time you take it, as in versus. Tiles never run out: walking onto one takes a copy and leaves it in place. You have to step off a tile and back on to take it again.
  - **Template tiles:** if you have no template, the tile becomes your template. If you already have one, it **stacks** onto it with the normal merge rules, up to the usual **max of 3**. At level 3, template tiles are refused.
  - **Word tiles** fill blanks exactly as in versus.
  - **Reset** clears your template and your active effect (shields, speed, trap, a repeat in progress).
- **No timers:** templates never time out and no new templates are dealt. You build whatever you want.
- **Step-by-step guide** in the right HUD panel. It teaches how to *build* a spell, so it reads both the template you hold (top left) and the tile tab on the floor (bottom). Each state has a title, up to two lines of instructions, and a **counter** set apart at the bottom in brighter text. Spell effects explain themselves, so there's no casting message. The guide doesn't mention `Space`; how to switch tabs will be hinted some other way. In order:
  1. **Trap armed** (a trap is waiting and no new template has been picked up yet): it fires once, the moment its condition is true. Footer: "try it near the dummy".
  2. **Templates tab → step 1**, for as long as you stay on that tab: up to 3 templates stack into one bigger spell. Counter: `templates 2/3`. At 3/3 it says the max is stacked and to fill the blanks.
  3. **Word tab without a template → step 1:** pick up a template first, from the templates tab.
  4. **Word tab with a template → step 2, fill the blanks:** "walk onto spells to fill the blanks" when the tab has what you need (mentioning the other tab if both kinds are needed), otherwise "you need conditions, from the conditions tab". Counter: `2 blanks left`.
- **The dummy** stands behind a short wall. It has **infinite HP** and doesn't move. A thin red circle shows its range: step inside and it attacks you with a normal laser (same aim and casting pose) every few seconds. The wall lets you test line of sight, and the dummy lets you test traps like `when hit` or `when close`.
- **The player can't lose** in training. Hits still show combat text, knockback and the hit flash, but HP doesn't drop.
- The room's layout, item positions and dummy settings live in `data/training.json`.

## 15. Ideas for later

### Pickup takes time (from playtest: "grab everything" is too strong)

Playtests showed that grabbing every word you can reach is the dominant strategy. Every word is useful, picking one up costs nothing, and speed snowballs because it lets you collect even faster. Waiting for a template to stack rarely pays off.

**Idea:** a player must **stand on a word for about 0.6 s** to take it, shown as a filling ring around the word. **Getting hit or dashing interrupts it.**
- Grabbing becomes a decision ("is this word worth standing still in the open for, while their staff is up?") instead of a reflex.
- It blunts the speed snowball: accelerate helps you *reach* words but not *collect* them, so it shifts toward dodging and positioning.
- It creates bait and punishment: a player picking up a word is a target, and may be about to trigger their own `I stand still` trap.

Related options, if this isn't enough:
- **Show the next wave's words early**, with labels on the markers about 3 s before they land, so players can plan routes and decide which words to contest or deny.
- **Make stacking pay more than linearly:** each level above 1 adds a bonus raise.
