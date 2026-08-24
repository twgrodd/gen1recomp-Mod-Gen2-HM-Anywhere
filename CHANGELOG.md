# Changelog

## 2.8.1 — Cleanup release

- Kept the proven v2.8.0 gameplay implementation unchanged.
- Reworked Lua comments to explain the Gen2 field-move and menu ordering.
- Expanded README with installation, compatibility, safety, and implementation notes.
- Added `DIFFERENCES.md` documenting the intentional gameplay/UI changes.
- Declared the mod explicitly for Pokémon Gold and Silver.
- Updated the engine compatibility range for Gen1Recomp++ 0.2.20+.
- Added the project GitHub metadata for release/update discovery.
- Standardized the manifest category and human-readable description.
- Kept Pidgeot as the FLY animation source.

## 2.8.0

- Changed the temporary FLY field-move source to Pidgeot so the native Fly animation shows a bird.
- Kept all other HM behavior unchanged.

## 2.7.0

- Fixed FLY for Gen1Recomp++ 0.2.20 by using Gold's live `game.world` object.

## 2.4.0

- Fixed HM menu execution ordering.
- Restored the proven menu field-action path for CUT, SURF, FLASH, and the other ordinary HMs.
