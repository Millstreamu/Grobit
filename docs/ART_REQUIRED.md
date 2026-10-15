# Grobit — Artwork Required (2026-10, v0.4-aware)

Art is referenced by **id** and resolved by `ContentLibrary`: from an atlas (`content/atlases/prototype/*.json`
→ `.png`, a `sprites` map of id → frame), from a dedicated file (only `goblin` → `content/atlases/Goblin.png`
today), or — when missing — a **generated colored-square placeholder**. So nothing blocks on missing art;
this is the list for when you want to replace placeholders.

**Already present:** `goblin` (Goblin.png), `enemy_basic`, `scrap_metal`, `tech_data`, `selection_16/32/64`,
plus some legacy frames (`power_cell`, `power_generator`, `extraction_beacon`, `respawn_beacon`, `electronics`,
`raw_material`, `grobit`, `grobit_gun_01`). **~82 referenced ids currently fall back to placeholders.**

Sizes seen in code: resource/machine icons **16×16** (some 18–24), the bot/props **24–32**, tiles **32×32**.
Add a new frame to an atlas JSON (`"id": {x,y,w,h}`) or drop in a dedicated PNG.

---

Format of each line: **`id`** — Name · size · `#color` (the tint it's drawn with now) · what it is.
Top-down view throughout. Match the `#color` so new art reads the same as the placeholder it replaces.

## Priority 1 — Core actors & the v0.4 production redesign (make first)

- **`scrapbot`** — Scrapbot · 24–32px · `#9ad06a` · the player's tracked salvage bot/turret you drive and
  protect; the weapon mounts on it. *Placeholder now; always on screen.*
- **`enemy_spawner`** — Spawner · 24px (18px + `#4a3a66` when wrecked) · `#8a5ad0` · a hive/vent/portal that
  pours enemies out during a breach; needs an intact (bright) and a wrecked/dim state.
- **`proc_heat`** — Heater · 16–24px · `#e0662e` · a furnace/kiln. **Show a clear INPUT edge + OUTPUT edge**
  (an arrow), because chains only connect where ports line up.
- **`proc_press`** — Presser · 16–24px · `#8a93a0` · a stamping press (same in/out-edge requirement).
- **`proc_mold`** — Molder · 16–24px · `#3f9fb6` · a casting/mold machine.
- **`proc_fold`** — Folder · 16–24px · `#c8a24a` · a bending/folding machine.
- **`ammo_loader`** — Ammo Loader · 16–24px · `#ffcf6a` · an autoloader module (a packable bay shape);
  speeds fire rate.
- **`food`** — Food · 16px · `#7ec850` · rations / a food crate (gathered in runs; pays recruiting).
- **Enemy bruiser (tier 2)** — *optional* · 22px · `#e08a3a` · a bigger, heavier enemy (goes for the bot);
  currently a tinted `enemy_basic`. Grunt (tier 1) already uses `enemy_basic` (`#c0504a`, 16px).

## Priority 2 — Regularly visible

**Weapons (bay modules, 16–24px, packable top-down shapes):**
- **`weapon_steel`** — Steel Cannon · `#b9c2cc` · heavy slow cannon.
- **`weapon_copper`** — Copper Blaster · `#c8722e` · fast light blaster.
- **`weapon_plastic`** — Resin Repeater · `#3fb6a8` · spread/shotgun (fires 3 pellets).
- **`weapon_ceramic`** — Ceramic Lance · `#e0d7c0` · piercing lance/railgun.

**Scrap piles (16–18px, floor piles):**
- **`scrap_steel`** `#8f98a3` · **`scrap_copper`** `#b0632a` · **`scrap_plastic`** `#359186` ·
  **`scrap_ceramic`** `#c4bba2` · **`scrap_node`** (generic pile marker).

**Refined materials (16px, ingot/unit):**
- **`steel`** `#b9c2cc` · **`copper`** `#c8722e` · **`plastic`** `#3fb6a8` · **`ceramic`** `#e0d7c0`.

**Ammo (16px, small rounds/cells):**
- **`steel_slugs`** `#cfd6dd` · **`charge_cells`** `#e8a13a` · **`resin_capsules`** `#56d3c4` ·
  **`ceramic_charges`** `#efe6cf`.

**Lair stations (24–30px, top-down kiosks/benches):**
- **`system_terminal`** `#5aa9e6` (blue console) · **`repair_station`** `#c0563a` (red bench) ·
  **`fabricator`** `#c98a3a` (orange crafting bench) · **`component_exchange`** `#e0a93a` (amber trade kiosk).

**World/UI bits:** **`scrap_node`** (pile), **`machine_crate`** (bulky recovered-machine crate in the hold),
**`storage_cache`**, **`hazard_zone`** (floor hazard), **`tool`** (tool pickup).

## Priority 3 — New chain PRODUCTS (16px; make when the Phase-4 economy swaps in)
Defined in `process.json`, not yet icons. Keep each in its material's colour family:
- **`steel_plate`**, **`steel_ingot`**, **`steel_spring`** — steel `#b9c2cc` family.
- **`copper_sheet`**, **`copper_coil`** — copper `#c8722e`.
- **`plastic_casing`** — plastic `#3fb6a8`. · **`ceramic_tile`** — ceramic `#e0d7c0`.

---

## Legacy — likely RETIRED by the v0.4 redesign (probably skip)
Confirm against the roadmap before investing — Phase 4 replaces the recycler/conveyor factory.

- **Old factory machines** (replaced by process verbs): `recycler_steel/copper/plastic/ceramic`,
  `ammo_maker_steel/copper/plastic/ceramic`, `comp_maker_control/coupling/frame/thermal`, `smelter`,
  `grinder`, `separator`, `refiner`, `assembler`, `constructor`, `circuit_printer`, `scrap_recycler`.
- **Old-economy resources/components:** `bent_panel`, `cable_bundle`, `mechanical_parts`, `electronic_scrap`,
  `metal_bar`, `metal_plate`, `polymer`, `polymer_sheet`, `circuit_board`, `control_unit`, `control_assembly`,
  `power_coupling`, `power_relay`, `reinforced_frame`, `structural_frame`, `thermal_core`, `motor`,
  `broken_motor`, `burnt_board`, `copper_wire`, `refined_copper`, `mixed_components`, `e_waste_node`,
  `circuit_printer`.
- **Other enemy types** (variety — keep only if you want more than grunt/bruiser): `enemy_brute`,
  `enemy_shooter`, `enemy_swarmer`.
- **Dead/removed systems:** `respawn_beacon` (ability/respawn flow removed), `extraction_beacon` (deleted).

## Lair stations (Phase 1 — buildable base) · 30×30, top-down
Each is a placeable station object in the lair (`data/game/stations.json`).

- **`station_workshop`** — Workshop · 30×30 · `#d9a441` · the production-floor station.
- **`station_missions`** — Mission Board · 30×30 · `#5aa9e6` · colony quests + lair goal.
- **`station_line`** — Process Line · 30×30 · `#6ad0e0` · the chain-building bench.
- **`station_quarters`** — Goblin Quarters · 30×30 · `#7ec850` · recruit + tools + memorial.
- **`station_upgrades`** — Upgrade Bench · 30×30 · `#b48be2` · machine/tech/cargo upgrades.
- (`fabricator`, `component_exchange` reuse their existing icons.)

## Environment tiles (present; only if you want to replace them)
`floor_clean`, `floor_damaged`, `wall`, `wall_damaged`, `door_closed`, `door_open` — all exist in
`content/tilesets/prototype/prototype_environment.*`.
