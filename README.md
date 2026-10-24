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

`R` restarts after a round ends. `Esc` quits.

## Tuning and testing

- `powershell -ExecutionPolicy Bypass -File tools\dev.ps1` runs the game and restarts it only when `tools\restart.ps1` is run (Claude runs it once after finishing a batch of changes, so half-done edits never launch). `R` restarts a finished round; `F5` reloads code and data.
- Every gameplay number is in `data/tuning.json`. After editing it (or any code), press **F5** in the game to reload. Live reload without a restart is planned.
- `lovec . --selftest` runs a headless check of the spell rules.
- `lovec . --shot` saves a screenshot after a few seconds to LÖVE's save folder, then quits.

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
- Rule modules (`arena`, `player`, `spellbook`, `wordfield`, `game`) don't call `love.*`; only `render.lua` and `main.lua` do.
- Tuning is read every frame from one shared table, never cached at load time, so it can be live-reloaded later.
- Assets use standard formats (PNG, OGG/WAV, TTF/bitmap fonts).
