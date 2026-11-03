# Wordcraft — Characters (ideas)

Status: **Ideas**. Nothing here is decided or built yet. Linked from the [DESIGN.md](DESIGN.md) hub.

## Why more characters

Playing the wizard is a lot to handle at once: reading the template, reading the words on the floor, and dodging the opponent's attacks. Lasers hit walls 57% of the time in the simulation, so movement and cover already take half your attention. A level-1 template times out after 7.5 s, so you often end up holding a stacked template that needs many words, and the board changes quickly (dead-board waves bring the average gap down to 4.3 s).

**Idea:** make template stacking the **wizard's** mechanic, so the wizard is the complex character on purpose. Other characters get simpler rules: level-1 templates only, or no templates at all, and no stacking. They still pick up words. Words stay at the centre of every character; simple characters just use fewer, shorter ones.

Things to keep in mind:
- **You still read your opponent.** A simple character fighting a wizard still has to read the wizard's template to dodge and deny. "Status is always visual" (DESIGN §8) has to hold for every character.
- **Balance work grows.** Every new character needs its own matchups, its own bot logic, and waves that serve each vocabulary. Words the warrior can use change how denial works for the wizard.
- **Before building:** check that stacking really is the main load. Try a `stacking: false` tuning flag (a timeout deals a fresh level-1 template) and playtest it, so we don't fix the wrong thing. The wave churn is the other suspect.

## Shield warrior — liked

A slow, tanky melee character that controls space. Walls don't protect you from it.

- **Slower** than the wizard.
- **Shield stacks don't expire.** Each `shield` word adds a stack.
- **Attack is a one-time slam** in a circle around the warrior, and it **ignores walls**. A ring on the floor fills for about 1 s (like the laser's aim time), then hits everything inside once. To escape, walk out of the ring or dash through it (invulnerable). The circle looks nothing like a beam, so ignoring walls doesn't break the readable-rules principle.
- **The slam radius grows with shield stacks.**
- Words: only `shield` and `attack` (attack = slam) matter to the warrior. They could be single-blank `cast ___` templates, or apply straight on pickup.

**Open: snowballing.** Stacks that never expire, combined with a radius that grows with them, go against the "effect window: no snowballing" rule (DESIGN §8). We can't tell whether that hurts until it's prototyped. Possible fixes if it does:
- Cap the stacks (e.g. 5).
- **Stacks as ammo:** the slam *spends* stacks, and its radius depends on how many it spends. That's a choice between keeping the armour and cashing it in for a big hit.

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
