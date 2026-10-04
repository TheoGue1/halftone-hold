# Halftone Hold

Medieval incremental game, rendered through a four-ink halftone print shader. Godot 4.7.

## Play

In the browser: https://theogue1.github.io/halftone-hold/

Locally (Godot 4.7):

```
godot --path .
```

## Web build

```
godot --headless --path . --export-release "Web" docs/index.html
```

`docs/` is served by GitHub Pages (single-threaded build, no special headers needed).

## Loop

- Press the Royal Seal, buy 12 holdings (Peasant → Celestial Citadel). Milestones double output.
- **Crusade** (first ~15 min): reset the run for Renown. Renown multiplies gold and grants Web points.
- **Passive Web**: 714 nodes, 6 sectors, 109 notables, 18 keystones with trade-offs. Free refunds.
- **Dynasty** (~1 h): reset Renown and the Web for Royal Blood, which raises Renown's power.
- **Omens**: golden carts, falling stars, dragon raids, pilgrims. Click them in the Kingdom.
- **Reliquary**: scratch-cards (drag to scratch) paying gold and 17 levelling relics, 3–6 equip slots.
- **Seasons & weather**: 10-minute cycle; each empowers one Web sector (gold rings in the Web).
- **Crusade map**: 4 destinations trading Renown for spoils. **Oaths**: run restrictions for permanent rewards.
- **Counting Table** (Vault tab): 2048-style coin merging; best coin = permanent gold multiplier.
- **Chapel**: six stained-glass sliding puzzles (3×3 to 5×5); each restored window empowers a Web sector.
- **Court**: advisors unlocked by deeds automate buying, crusading, omens and cards.
- **The Infinite Hoard**: reach 1.79e308 gold (~7.5 h for an optimal player in the sim).

Features unlock progressively (`Content.UNLOCKS`, conditions in `Game.unlock_ready`): omens ~4 min,
crusades ~8 min, Web ~17 min, Reliquary ~25 min, map ~35 min, Court ~30 min, dynasties ~40 min,
seasons at dynasty 1, layouts 3, Dragon Peaks 4, oaths 5, Silk Road 7, Ledger 10, relic slots 2/8/20,
Counting Table 2, Chapel 6 with a new window every 2 dynasties up to 16.

## Tests

```
godot --headless --path . --script tests/self_check.gd            # logic checks
godot --headless --path . --script tests/self_check.gd -- sim cps=1   # + pacing sim, unlock timeline
godot --path . tests/shot.tscn -- --out=/tmp/s.png --page=web --late --ui-check
```

Balance knobs are the constants at the top of `scripts/game.gd`. Rerun the sim after changing them.

Fonts: EB Garamond and IM Fell English SC, SIL OFL (see `fonts/`).
