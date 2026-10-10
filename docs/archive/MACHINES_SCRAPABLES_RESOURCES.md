# Grobit — Machines, Scrapables & Resources (design reference)

Working reference for the salvage/crafting economy. **Not a locked economy** — values,
recipes, timings and progression change after testing. Design intent:

- Found junk should feel like real broken machinery, not abstract ore.
- Keep raw resource *types* small; complexity comes from how things are processed.
- Some salvage supports multiple processing choices; fast = fewer/lower materials,
  deeper chains = better recovery.
- Artwork metadata stays separate from gameplay/balance data; recipes/yields/times
  are data-driven.

## Reconciliation with the built engine (decided 2026-09-20)

The full catalogue in the original brief is Factorio-scale; the inventory-factory is a
small grid. Resolved:

- **Sequential batch play with stockpiled machines.** You don't run all chains at
  once — build a line, run it, **pick machines up** (they go to a per-run stock,
  re-placeable for free), and re-lay them for the next batch. Intermediates stockpile
  as items in the grid.
- **Multi-output** machines (Recycler/Separator → several materials).
- **Grid machines vs world stations** are split: grid machines live in `machines.json`
  and are placed in the factory; room/utility stations (Repair, Decode, Objective
  terminal, Retrieval pad) are separate world interactable scripts.
- Ported a **spine**, not all 20 machines. Expand as data later.

## Implemented spine (in `data/game/`)

**Junk (harvested via the scrapping minigame):** Bent Panel, Cable Bundle, Burnt
Circuit Board, Broken Motor.

**Grid machines** (`machines.json`) + **recipes** (`recipes.json`):

| Machine | Recipe(s) |
|---|---|
| Scrap Recycler | bent_panel → scrap_metal ×2 · cable_bundle → copper_wire + polymer · broken_motor → scrap_metal + mechanical_parts *(fast recovery)* |
| Grinder | broken_motor → mixed_components *(step 1 of efficient recovery)* |
| Separator | burnt_board → electronic_scrap + copper_wire · mixed_components → scrap_metal + copper_wire + mechanical_parts *(3-way — efficient recovery)* |
| Smelter | scrap_metal → metal_bar |
| Press | metal_bar → metal_plate · polymer → polymer_sheet |
| Refiner | copper_wire → refined_copper |
| Circuit Printer | electronic_scrap + refined_copper → circuit_board |
| Constructor *(locked: ship 3 circuit_board)* | metal_plate + refined_copper + mechanical_parts → motor · circuit_board + refined_copper + polymer_sheet → control_unit |
| Assembler *(locked: ship 2 control_unit)* | metal_plate ×2 + mechanical_parts → structural_frame |

Multi-input is **set-based** (a recipe matches when its needed items are present across
the input cells, in any arrangement). Multi-output distributes products across the
machine's output cells (blocks if there isn't room for all of them).

**Fast-vs-efficient recovery** (the brief's key choice) is live: a Broken Motor gives
**2** materials fast through the Recycler, or **3** through Grinder → Separator.

## Later / not yet ported (the rest of the brief)

Foundry, Fabricator, Chemical Vat, Battery Charger, Power Converter, Shield Emitter,
Beacon Constructor, Compressor, Synthesizer, Tech Analyzer; deeper components
(Pump/Power Module/Sensor Module/Cooling Assembly/etc.); the **power-cell rebuild
chain** (damaged_power_cell → battery materials → charged cell); and Repair/Tech
utility stations as world objects. All additive as data on the current engine.
