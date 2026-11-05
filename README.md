# Wordcraft

A local 1v1 pixel-art fighting game: two wizards grab random words and combine them into spells to attack each other.

Built with [LÖVE](https://love2d.org) 11.5. Game rules live in [docs/DESIGN.md](docs/DESIGN.md).

## Run

1. Install LÖVE: `winget install love2d.love2d`
2. From this folder: `love .`

## Controls

| Action | Player 1 (blue) | Player 2 (red) |
|--------|-----------------|----------------|
| Move   | `W` `A` `S` `D` | `↑` `←` `↓` `→` |
| Dash   | `Left Shift`    | `Right Shift`  |

`R` restarts after a round ends. `F2` opens the **training room** (one player vs a dummy): first walk into the character you want to play, then `Space` switches which tiles are on the floor (templates, spells or conditions). `F2` again goes back to the match (and the next `F2` opens a fresh room with the character pick); `Esc` leaves it for character select. `F3` hands P2 to the **bot** or gives it back (`love . --bot` starts with P2 set to AI).

The game opens on the **character select** screen: movement keys move your cursor, your dash key confirms. Each side can be a person or the `AI`; once you confirm your own side, your keys can set up the other side too (that's how you set up a bot opponent alone). `Esc` un-confirms both sides. In a match, `Esc` returns to character select. Close the window to quit.

## Tuning and testing

- `powershell -ExecutionPolicy Bypass -File tools\dev.ps1` runs the game and restarts it only when `tools\restart.ps1` is run (Claude runs it once after finishing a batch of changes, so half-done edits never launch). `R` restarts a finished round; `F5` reloads code and data.
- Every gameplay number is in `data/tuning.json`. After editing it (or any code), press **F5** in the game to reload. Live reload without a restart is planned.
- **Dev quick start:** a local, git-ignored `data/dev.json` skips character select and starts a set match on launch (and after `F5`). `Esc` still opens character select. Without the file (or with `enabled: false`) the game starts on the select screen. Example (human Bulwark vs AI Spellslinger; ids from `data/characters.json`):

  ```json
  { "quickStart": { "enabled": true, "characters": ["shieldmage", "wizard"], "control": ["human", "ai"] } }
  ```
- `lovec . --selftest` runs a headless check of the spell rules.
- `lovec . --shot` saves a screenshot after a few seconds to LÖVE's save folder, then quits.
- `lovec . --shot-training` does the same for the training room.
- `lovec . --shot-select` does the same for the character select screen, `lovec . --shot-pick` for the training room's character pick, and `lovec . --shot-parry` for a Bulwark parry.
- `lovec . --sim 400` runs 400 bot-vs-bot rounds (or `--sim 1m` for as many as fit in a minute) on every CPU core with no window, and prints balance metrics, plus a CSV per template in LÖVE's save folder. `--stats` also rewrites `docs/STATS.md`. Add `--workers N`, `--cap SECONDS`, `--p1 PROFILE`, `--p2 PROFILE` (profiles: `botProfiles` in `data/tuning.json`), `--c1 CHARACTER`, `--c2 CHARACTER` (e.g. `--c2 shieldmage`). See [docs/SIMULATION.md](docs/SIMULATION.md).

## Sprites

The wizard sprites (idle and casting frames) are generated from text grids in `tools/make_sprites.ps1`. To regenerate them after editing:

```
powershell -ExecutionPolicy Bypass -File tools\make_sprites.ps1
```

## Layout

| Path | What lives there |
|------|------------------|
| `main.lua`, `conf.lua` | LÖVE entry point and window config |
| `src/` | Game code. Rules (spells, combat) are kept separate from drawing. |
| `data/` | Engine-neutral JSON: words, templates, arena layout, tuning numbers |
| `assets/sprites/` | PNG sprite sheets on a fixed grid |
| `assets/fonts/` | Pixel fonts |
| `assets/audio/` | `.ogg` / `.wav` |
| `tools/` | Dev scripts (e.g. sprite generation), not shipped with the game |

## Migration-friendly rules

- Game data goes in `data/*.json`, never hardcoded in Lua.
- Rule modules (`arena`, `player`, `spellbook`, `wordfield`, `game`, `bot`, `sim`, `data`) don't call `love.*`; only `render.lua`, `main.lua` and the simulation's thread code (`simjobs.lua`, `simworker.lua`) do.
- Tuning is read every frame from one shared table, never cached at load time, so it can be live-reloaded later.
- Assets use standard formats (PNG, OGG/WAV, TTF/bitmap fonts).
