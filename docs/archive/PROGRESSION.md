# Grobit — Game Progression

How the game's progression is laid out as of this build. A goblin drives a salvage
scrapbot out of its lair into procedurally-generated ruins, harvests scrap, runs an
in-grid factory, and climbs a **four-tier tech ladder** to fix up the lair and send a
distress beacon.

This doc covers what's **implemented**. Placeholder numbers are flagged; the authoritative
source for every value is the file cited.

---

## 1. The core loop

```
  LAIR (set up)  ──►  drive out  ──►  RUN (harvest + fight + craft)  ──►  extract home  ──►  LAIR
      ▲                                                                                        │
      └────────────────────────── spend / deliver, then launch again ◄─────────────────────────┘
```

1. **Lair setup** — you're the goblin on foot. Open the factory at the scrapbot, arrange
   your machines/transport from storage, and hit **Accept** to launch. The layout is then
   **locked for the run** (you can still shuffle loose items, not rebuild).
2. **The run** — the facility generates the moment you drive out. Harvest scrap, repair
   machines you find, fire weapons, craft materials/components while you explore.
3. **Extract** — drive back to the scrapbot and climb out. Your whole inventory comes home;
   crafted **components get delivered to the lair's survival needs**.
4. **Repeat** — spend Tech Data + components to climb the ladder, place new machines, launch
   again. Fill all four lair needs to win.

Key framing files: `scripts/world/run_controller.gd` (run lifecycle, extraction, bootstrap),
`scripts/world/area_generator.gd` (two-phase generation: lair up front, facility on hop-in).

---

## 2. The materials ladder (the spine)

Four material tiers, climbed in order. The **Scrapper Arm's level** gates which tier you can
even collect, so it's the backbone of progression.

| Tier | Material | Scrap (harvested) | Unlocked at |
|------|----------|-------------------|-------------|
| 1 | **Steel**   | `steel_scrap`   | start (arm L1) |
| 2 | **Copper**  | `copper_scrap`  | arm L2 |
| 3 | **Plastic** | `plastic_scrap` | arm L3 |
| 4 | **Ceramic** | `ceramic_scrap` | arm L4 |

Order & gating: `FactoryGrid.ARM_SLOT_TYPES` (`scripts/core/factory_grid.gd`).

### The Scrapper Arm

The arm is a **5-cell grid machine**: a core + **4 typed scrap slots** laid out in tier order
(steel, copper, plastic, ceramic). It is pre-placed and persists.

- **Harvest → slot.** Holding `[F]` on a scrap pile stacks that scrap (to `ARM_SLOT_MAX = 99`)
  into its slot — *only if that tier is unlocked*. Locked-tier piles still **spawn as visible
  teasers** but read "Arm can't hold X yet" and can't be harvested.
- **Recyclers pull when adjacent.** A recycler whose input cell touches a slot draws the scrap
  straight out — no conveyor or insert needed. Pack recyclers around the arm.
- **Arm level = tier unlocked.** L1 = steel only; each level lights the next slot.

Code: `deposit_harvest` / `arm_accepts` / `arm_level` and the `_consume_available` "pull"
(`scripts/core/factory_grid.gd`).

---

## 3. The economy (what turns into what)

```
 scrap pile ──harvest──► ARM SLOT ──adjacent recycler──► MATERIAL ──┬─► AMMO MAKER ──► ammo ──► WEAPON (fires)
 (steel/copper/…)                     (steel/copper/…)             └─► COMPONENT MAKER ──► component ──┬─► arm upgrade (Terminal)
                                                                                                        └─► lair need (on extract)
```

- **Recyclers** — `<material>_scrap` → `<material>` (1:1, ~2.0s each). `data/game/recipes.json`.
- **Ammo makers** — 2× a material → its ammo (~2.5s). One ammo family per material.
- **Component makers** — combine two materials into a **component** (the mid-tier goods):

  | Maker | Recipe | Produces | Role |
  |-------|--------|----------|------|
  | `frame_maker`    | 2 steel          | **Reinforced Frame** | bridge T1→T2 · lair **oxygen** |
  | `coupling_maker` | steel + copper   | **Power Coupling**    | bridge T2→T3 · lair **power** |
  | `control_maker`  | copper + plastic | **Control Assembly**  | lair **water** |
  | `thermal_maker`  | copper + plastic | **Thermal Core**      | bridge T3→T4 · lair **food** |

  Recipes are tuned so each bridge component is craftable from the tiers you've already
  unlocked. Source: `data/game/recipes.json`.

- **Tech Data** — the one top-bar currency. Earned by **scrapping spare/duplicate machines**;
  uploaded at a System Terminal to bank it permanently.

There is **no untyped "junk"** — everything is typed.

---

## 4. Climbing the ladder (the cost chain)

Progression is forced into order because **both repair costs and arm-unlock costs are paid in
prior-tier goods**. Even if you *find* a ceramic machine early, you can't afford or feed it yet.

### Leveling the Scrapper Arm (at a System Terminal)

Each level costs **Tech Data + the tier's bridge component** (consumed from the factory). The
arm caps at **tier 4**.

| Arm level | Unlocks | Tech Data (placeholder) | Bridge component |
|-----------|---------|-------------------------|------------------|
| 1 → 2 | copper  | 3  | Reinforced Frame |
| 2 → 3 | plastic | 6  | Power Coupling |
| 3 → 4 | ceramic | 9  | Thermal Core |

`ARM_GATE_COMPONENT` / `ARM_MAX_LEVEL` (`scripts/ui/terminal_panel.gd`); TD cost =
`3 × level` (`MetaState.machine_upgrade_cost`).

### Repair costs (escalate in the PRIOR tier's material)

Found machines are repaired with refined materials; the cost rises as you climb:

| Machine tier | Repair cost (placeholder) |
|--------------|---------------------------|
| Steel (T1) | 2 steel |
| Copper (T2) | 4 steel |
| Plastic (T3) | 4 copper |
| Ceramic (T4) | 4 plastic |
| Transport (conveyors) | 1 steel |
| Cross-tier (component makers) | 3 steel |

`_repair_cost_for` / `_material_of` (`scripts/world/area_generator.gd`).

### Machine throughput

Any machine type can be **permanently upgraded** at a System Terminal (Tech Data), raising its
processing speed (and gating higher recipes). Persists across runs. `MetaState.machine_level`.

---

## 5. Finding, repairing & hoarding machines

- **Machines are found broken** in rooms (RNG). Tiers aren't hidden — higher-tier machines
  spawn and are grabbable, so you see what's ahead.
- **Repair** pays the tier cost, then the machine goes to **persistent storage** (not placed
  mid-run — the field factory is locked). You place it at a later run's **setup**.
- **Transport** (conveyors / splitters / filters) and **storage caches** are also found &
  repaired, but are **fungible** — stored as simple counts.

### Duplicates are worth collecting (per-instance layouts)

Every found **machine** keeps its **own rolled layout** — which sides its input/output/body
sit on. Two steel recyclers are *not* interchangeable: one might fit a tight corner the other
can't. Storage shows each instance with a **layout thumbnail**; placing uses that frozen
layout (no re-roll, no rotation). Data model: `MetaState.machine_instances` /
`RunState.add_machine_instance` / the `[G]` storage list in `scripts/ui/factory_panel.gd`.

---

## 6. The lair & the endgame

The meta goal is **fixing up the lair**: four survival needs, each filled to `NEED_MAX = 5`
by **delivering the matching component on extraction**.

| Lair need | Filled by | (component tier) |
|-----------|-----------|------------------|
| **Oxygen** | Reinforced Frame | T1 (steel) |
| **Power**  | Power Coupling   | T2 (copper) |
| **Water**  | Control Assembly | T3 (plastic) |
| **Food**   | Thermal Core     | T3 (plastic) |

`LAIR_NEEDS` / `NEED_COMPONENT` / `deliver_to_needs` (`scripts/core/meta_state.gd`).

**The strategic tension:** those same components are what you spend to level the arm. Every
component is a choice — **climb the ladder, or fix the lair.**

**Endgame:** when all four needs are maxed, your next extraction fires the **distress beacon**
→ `RESULT_RESCUED` ("Other goblins are coming for you"). One-way win flag (`send_beacon`).

Progress is shown on the end-of-run summary (each need `x / 5`, flagging what you delivered
this run) and in the debug readout (``[`]``) as a one-line `Lair: Oxy 2/5 Pow 5/5 …`.

---

## 7. Payoff — why climb?

All three, by design:

1. **Weapons** scale by material family (found broken, repaired, fed their ammo family):
   - Copper — fast, light (dmg 2, 0.25s)
   - Steel — heavy hitter (dmg 6, 0.70s)
   - Plastic — spread, 3 pellets (dmg 2, 0.45s)
   - Ceramic — pierces 2 enemies (dmg 4, 0.52s)
2. **Throughput** — permanent machine speed upgrades (Tech Data at the Terminal).
3. **Lair needs** — higher tiers unlock the components that finish the lair.

Ceramic (T4) is **not required** to win — it's the optional **combat apex** (pierce weapon +
ceramic ammo). The lair is completable at tier 3.

---

## 8. Starting state & the first run

- **Grid:** 8 × 8 (`FACTORY_COLS/ROWS`).
- **Fresh factory (first run only):** a **Scrapper Arm** (L1, steel) + one seeded **Steel
  Recycler** against the steel slot, so the steel economy runs immediately.
- **Bootstrap climb:** harvest steel → steel → craft a Reinforced Frame → spend it + Tech Data
  at a Terminal → copper unlocks → repeat up the ladder.
- **Debug reset (F9):** wipes the factory to a bare arm and clears storage, instances, lair
  needs, and the beacon — a clean slate (keeps the lair shape).

---

## 9. Build history (the slices that got us here)

- **C1 — Arm as tier gate:** arm levels 1–4 gate scrap slots; inert locked piles; steel start.
- **C2 — Cost-chain ladder:** bridge components, tier-escalating repair costs, arm-unlock gate.
- **C3 — Per-instance layouts:** machine storage became unique instances with rolled layouts.
- **C4 — Lair needs + endgame:** component delivery fills four needs; distress-beacon win.

(Earlier work established: persistent factory layout, typed-scrap economy, lock-editing-to-
setup, deferred facility generation, the goblin/scrapbot framing.)

---

## 10. Not yet built (next candidates)

- **Two extraction types** — a components run (keep your factory) vs a big-machine run that
  wipes everything except the hauled machine and sends you back unarmed.
- **Tier-weighted generation** — currently all tiers spawn as teasers; weight piles/finds
  toward your current+next tier.
- **A proper win/credits screen** beyond the summary line.
- **Tuning pass** — every number above marked "placeholder" (`NEED_MAX`, repair costs,
  arm-upgrade Tech Data, recipe amounts) lives in one clearly-commented spot per value.
