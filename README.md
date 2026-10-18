# Wordcraft

A local 1v1 pixel-art fighting game: two wizards grab random words and combine them into spells to attack each other.

Built with [LÖVE](https://love2d.org) 11.5.

## Run

1. Install LÖVE: `winget install love2d.love2d`
2. From this folder: `love .`

## Layout

| Path | What lives there |
|------|------------------|
| `main.lua`, `conf.lua` | LÖVE entry point and window config |
| `src/` | Game code. Rules (spells, combat) are kept separate from drawing. |
| `data/` | Engine-neutral JSON: words, spell recipes, tuning numbers |
| `assets/sprites/` | PNG sprite sheets on a fixed grid |
| `assets/fonts/` | Pixel fonts |
| `assets/audio/` | `.ogg` / `.wav` |

## Migration-friendly rules

- Game data goes in `data/*.json`, never hardcoded in Lua.
- Rule modules (e.g. spell lookup) don't call `love.graphics`.
- Assets use standard formats (PNG, OGG/WAV, TTF/bitmap fonts).
