# Wordcraft — Characters (ideas)

Status: **Ideas**, except the Bulwark, whose prototype is built. Linked from the [DESIGN.md](DESIGN.md) hub.


## Names

Decided 2026-11-05, so the characters are easy to tell apart and remember. Each name says the playstyle; internal ids, sprites and tuning keys stay as they were.

| Name | Id | Style |
|---|---|---|
| **Spellslinger** | `wizard` | The original: fast, dashes, stacks templates |
| **Bulwark** | `shieldmage` | Armoured, parries with a door shield |

Older text (and the code) still says "wizard" for the Spellslinger. Future characters keep the same plain one-word style (Trapper, Thief).
## Why more characters

Playing the wizard is a lot to handle at once: reading the template, reading the words on the floor, and dodging the opponent's attacks. Lasers hit walls 57% of the time in the simulation, so movement and cover already take half your attention. A level-1 template times out after 7.5 s, so you often end up holding a stacked template that needs many words, and the board changes quickly (dead-board waves bring the average gap down to 4.3 s).

**First idea:** make template stacking the **wizard's** mechanic, so the wizard is the complex character on purpose, and give other characters simpler rules (level-1 templates only, no stacking).

**Decided 2026-11-03: every character keeps template stacking.** The complexity stacking adds is fine; there's no plan to remove it. Characters differ in what they do with their spells and their special (dash key), not in how templates work. Words stay at the centre of every character.

Things to keep in mind:
- **You still read your opponent.** A simple character fighting a wizard still has to read the wizard's template to dodge and deny. "Status is always visual" (DESIGN §8) has to hold for every character.
- **Balance work grows.** Every new character needs its own matchups, its own bot logic, and waves that serve each vocabulary. Words the warrior can use change how denial works for the wizard.
- **Stacking stays,** so the `stacking: false` test is dropped.

## Bulwark — Proposed (prototype built)

A heavily armoured mage with a big door shield: tanky, with a parry instead of a dash. Phase 1 of the character plan has two characters besides the wizard: this one (built first) and the trapper.

**Look:** the wizard's hooded cousin. Hood and white beard over plate armour, the door shield in the left hand, and the wizard's own staff (same pixels and position) in the right hand. Its attacks therefore look exactly like the wizard's: same orbs, aim rays and beams from the same gem. It walks with the wizard's foot cycle. Sprites: `shieldmage_blue` / `shieldmage_red` in `tools/make_sprites.ps1`.

**Rules** (numbers under `characters.shieldmage` in `tuning.json`):
- **Uses words and templates exactly like the wizard**, including stacking, and casts with its staff.
- **Shield charges work exactly like the wizard's:** they end with the effect window. (Lasting, decaying charges were tried and dropped; see History.)
- **Same walking speed as the wizard.**
- **`3` HP instead of `10`, and every successful parry heals `1`** (up to full; once per press, even if it stops a volley). Playtest version from 2026-11-05: 5 HP with no reward lost 41 / 59 to the Spellslinger in simulation, 3 HP + heal is even (SIMULATION.md results log). The HUD shows 3 pips; a heal shows a green `+1` over Bulwark.
- **No dash. The dash key parries instead:** the mage raises the shield for a **`0.25 s` window** (a dash's invulnerability lasts `0.15 s`, so timing is a little more forgiving but still a skill). It can keep walking. Every beam that lands in the window is **parried**: no damage, no shield charge used, no knockback. A parry takes priority over shield charges.
- **Cooldown `2 s`, except after a successful parry: then there's none**, so a good read can parry the next beam of a stream too. A missed parry (nothing landed in the window) leaves the full cooldown.
- **`I dash` fires when the mage parries** (its dash key), so `when I dash, cast attack` means "attack as I raise the shield".

**Status shown on the mage:**
- **Parrying:** the shield-raised pose (shield swung in front, the mage still facing the opponent) for the whole window.
- **Parried:** `PARRY` floats up in gold (like `BLOCK` in cyan), the beam stops dead at the shield with a big gold spark, the mage flashes white, and a gold ring snaps outward with eight white sparks flying off. The pose holds for the `0.35 s` flash.
- Shield rings as usual. The grey bar over the head shows the parry cooldown.

**History:** the first prototype (2026-11-03) had a **slam** on the dash key: a ring that hit through walls after a `0.6 s` windup, costing a shield charge. Playtesting showed that losing the dash was the real problem: much less mobility, so fewer words picked up, so few shield charges, so the slam was rarely usable. The parry replaces it: it's defensive like the dash, and needs no charges.

**Lasting shields, tried and dropped (2026-11-04):** the first design had charges that never expired. In playtests one big shield spell (5–10 charges) decided the round, so charges got a decay instead (with `n` charges the next goes after `40 / n` s). Simulation then showed lasting shields slow the whole game down even with decay (results log in [SIMULATION.md](SIMULATION.md), 2026-11-04), and the parry is already a strong defence, so the mage now has the wizard's expiring charges. The rule still exists as an option (`shieldLasts`, `shieldDecay` per character in `tuning.json`) for experiments.

**Bot:** instead of hiding from a beam it has noticed, it keeps collecting words and parries. Each press is timed `parryLead` (`0.125 s`, mid-window) before impact plus normal timing error (`parryJitter`, sd `0.1 s`), so about 80% of its presses land in the window, close to a practised player. A mistimed press costs the cooldown; then it hides. With lasting shields, measured over 40 bot rounds vs the wizard bot (2026-11-04): of wizard beams that got past the walls, 59% parried, 36% blocked by charges, 5% hit; the mage won 39 of 40. With perfect timing it was 74% parried and 38 of 40, so the charges, not the timing, carry it.

## Trapper — liked

Zoning and area control. Turns `when` into traps on the map.

- Uses only `when ___, cast ___` templates.
- Completing one **places a trap on the floor** where the trapper stands (maybe 2 at most), instead of arming it on the body. It fires when its condition is true for someone at that spot, or when an enemy walks into it.
- Plays around cover and chokepoints: block the route to a word, guard a corner.
- Open: which conditions make sense for a trap on the floor (`enemy is close` reads naturally as "enemy steps near it"), how long traps last, and how they show (an always-visible rune in the owner's colour).

## Thief — interesting, needs balancing

A denial specialist: steals filled words from the opponent's template, which pressures big wizard stacks.

- Short templates of its own.
- Touching the enemy (or standing near them for a while) steals one filled word from their template.
- **Problem:** the best strategy would be to follow the opponent around so they never get anything done. That's a bad experience for the other player. It needs limits before it's worth building, for example: a long cooldown between steals, steals only from templates at level 2 or above, the thief being vulnerable while stealing, or the stolen word dropping back onto the floor instead of going to the thief.

## Rejected

- **Ranger** (every word fires the moment it's picked up, aimed by hand in the facing direction): aiming with 8-direction keyboard movement feels bad.
- **Echo** (reads the enemy's template and recasts their last spell at level 1): not interesting enough.
