# Slice 1 — "Scrap → refine → ship" vertical

> Scope for the first implementation slice of the inventory-factory redesign
> ([`INVENTORY_FACTORY_DIRECTION.md`](INVENTORY_FACTORY_DIRECTION.md)). Goal: prove
> the **whole loop in miniature** end-to-end, and lay the **factory-grid
> foundation** the rest of the design builds on. Priority order as always:
> **Works > Playable > Easy to modify > Understandable > Looks decent > Polished.**

## What the slice proves (the miniature loop)

Drop into a small map → **harvest** a scrap node via the new **minigame** → items
land in the **scrapper-arm machine** in your inventory grid → an adjacent **refiner
machine** auto-converts them (real-time) → **complete a simple objective** to unlock
shipping → build a **retrieval cartridge** in a cleared room, **load it, ship = leave
the map** → shipped resources add to a persistent **Mars total**.

## In scope

- A **factory-grid inventory**: cells hold empty / a resource / part of a machine.
- **Two machine types**: the **scrapper arm** (receives harvested items) and one
  **refiner** (`scrap_metal → refined_metal`). Data-driven.
- **Real-time processing** (ticks even when the panel is closed), **adjacency
  auto-chaining** (a machine's output cell = the next machine's input cell), and the
  **exit-slot blocking** rule.
- **Scrapping minigame**: 4 slots, 1–8 node tokens, rusted (1–4 slots, 1–3 hits) and
  loose modifiers, real-time/exposed, items into the arm's holding cells; node
  persists until depleted.
- **Objective gate** (one terminal to activate) → **retrieval cartridge** (cheap
  metal) → **ship = leave**, banking chosen resources to a `MetaState` Mars total.

## Explicitly OUT (later slices)

Modules / decode station / data-chip drafting; machine **leveling**, **RNG slots**,
**reshuffle**; **conveyors** & **logic** machines; **multi-input** recipes (copper
etc.); **weapons-as-machines** & ammo; machine/recipe **meta-unlocks** (all
available in the slice); the full **Mars tech tree** (slice uses a single number).

## Slice assumptions for open design questions (MVP — flag to change)

- **Grid size:** keep the current **5×4** for now.
- **Output arrow:** **fixed per machine definition** (no rotation, no player choice).
- **Recipes:** **single-input only** this slice.
- **Entrance:** the **scrapper arm itself** is the entry point (no separate entrance
  mechanic yet).
- **Minigame exposure:** while scrapping, the player is **locked in place**, the
  world keeps running, **auto-shoot stays on**, movement is disabled — so you can be
  hurt but aren't defenceless.
- **Loose reshuffle:** reshuffles the **exposed, non-empty** slots after each action.
- **Cartridge:** fixed cost (a little metal) and a fixed **capacity (~6 items)**; you
  pick what to load.
- **Objective:** one **"activate objective terminal"** in the map unlocks shipping.
- **Persistence:** shipped resources → a single **Mars total** in `MetaState`;
  **modules omitted** this slice.

## Build steps (ordered, each independently verifiable)

### Step 0 — Factory-grid data model (no UI)
- New `scripts/core/factory_grid.gd` (or rework `RunState.slots`): an R×C grid; each
  cell = `{}` | `{kind:"resource", id}` | `{kind:"machine_part", machine_id, role}`.
- Machine instance: `{def_id, origin, cells:[{offset, role:"core"|"input"|"output"}],
  out_dir, input_buffer, progress}`. **No rotation** — footprint is as-authored.
- `data/game/machines.json`: `scrapper_arm` (holding cells, no recipe) + `refiner`
  (input cell, output dir, `recipe: scrap_metal→refined_metal`, `seconds`).
- **Verify:** headless — place a refiner, put `scrap_metal` in its input cell, tick,
  assert `refined_metal` appears in the output cell and the input is consumed;
  assert it **blocks** when the output cell is occupied.

### Step 1 — Grid UI + machine placement
- Rework `scripts/ui/inventory_panel.gd` to draw the grid: cells, machines (icon +
  **direction arrow**), items, cursor.
- Keyboard: cursor move; **place-machine** mode (choose from available machines,
  place if footprint fits at cursor); **pick up / move** an item cell.
- Scrapper arm **pre-placed** at run start.
- **Verify:** windowed screenshot — arm + refiner placed, arrow visible.

### Step 2 — Real-time processing, adjacency, blocking
- Tick machines from a run-level system every frame (runs with panel closed too).
  Consume input → after `seconds` → write to the arrow cell **if free** (else
  blocked). Shared output/input cell = the auto-chain.
- **Verify:** place arm→refiner adjacent; confirm items flow `scrap_metal →
  refined_metal` on their own; back-pressure blocks when the output cell is full.

### Step 3 — Scrapping minigame + arm intake
- New minigame on `ScrapNode`: 4 slots, tokens, rust, loose; real-time overlay
  (player locked/exposed, auto-shoot on). Each action spends a token; harvest moves
  the item into a free arm holding cell (blocked if the arm is full → exit). Node
  persists with remaining tokens; depletes to nothing at 0.
- Replace the current press-F harvest path.
- **Verify:** headless drives a few harvests; windowed screenshot of the minigame.

### Step 4 — Objective gate + retrieval cartridge (ship = leave)
- Simple **objective terminal** in the map; activating it **unlocks shipping**.
- **Retrieval cartridge** buildable (cheap metal) placeable in a **cleared room**;
  opens a load screen (pick up to capacity from the grid) → confirm → **run ends**,
  resources banked to the `MetaState` Mars total. Replaces `extraction_beacon`.
- **Verify:** full headless run reaches ship; Mars total increments; windowed shot
  of the load screen + Mars total.

### Step 5 — Reconcile & cleanup
- Rework out the **power-cell harvest fuel** (`scrapper_charge`/`reload_arm`,
  `ScrapNode` fuel gate, HUD "Scrapper Arm" line, `starter_cache`/`efficient_arm`
  tech). Retire or dormant: recycler modules, old manufacturing/Fabricator screen.
- Update `tests/test_project_structure.py` (new scripts/data) and
  `docs/ARTWORK_NEEDED.md`.

## Art needed (added to ARTWORK_NEEDED when built)
`refiner` machine, `scrapper_arm` machine, `machine_arrow` (output direction),
`refined_metal` icon, junk item icons (`scrap_metal`, `wire`, `plastics`,
`fuel_canister`, `metal_crate`), `objective_terminal`, `retrieval_cartridge`, and
minigame slot/rust UI. All fall back to coloured placeholders — nothing blocks.

## Risks / notes
- Biggest step is **0–2** (the grid model + real-time tick + adjacency); once that's
  solid the rest is comparatively small.
- This **replaces the current inventory model** (`RunState.slots` one-item bag +
  recycler feed). Keep the old code until Step 1 works, then switch the HUD over.
- Combat-during-minigame is the main *feel* unknown — the "locked but auto-shooting"
  MVP is the cheapest honest version of "real-time/exposed"; revisit after playtest.
