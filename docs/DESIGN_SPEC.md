# Grobit — Core Design and Prototype Specification

> **Version 0.3 — crew tools and field recovery**
> This revision replaces the in-bot factory concept with a configurable expedition rig. It is
> intended to define enough gameplay, UI, progression, and data structure to build and evaluate
> the first complete playable loop.
>
> **This is the design TARGET.** The current build matches some of it, differs on some, and hasn't
> reached the rest. **§0 (Build Reality) is the reconciliation** — read it first when playtesting
> so you know what's actually in the game vs. what's still aspirational. It supersedes the older
> `docs/archive/*` direction notes.

---

## 0. Build reality (spec ↔ current build, 2026-10)

The v0.3 spec is a partial **redirection** from where the code is. Three ideas in particular are
new-or-changed and are the main work ahead:

- **Scrapbot = module rig, not a factory.** The spec replaces the in-bot factory with a 6-slot
  module bay (power/cooling/heat). The build still uses the **8×8 factory grid** (recyclers,
  inserters, conveyors, ammo-fed weapons). This is the biggest divergence.
- **Tools have ROLES, not just tiers.** The spec has three tool *families* — Identify / Scavenge /
  Repair — each tiered 1–3, plus an **identification step** (targets start unknown). The build has
  one **scavenge-only** tool per goblin, tiered 1–4, no identify step, and any goblin can repair.
- **Noise meter + injury buffer.** The spec drives breaches from an accumulating **noise meter**
  and gives downed goblins a 5s rescue window. The build uses a simple **alarm timer** (breach at
  7s) and **instant permadeath** (no downed state).

### Legend
✅ matches the spec  ·  ◑ partial / differs in detail  ·  ○ not built yet  ·  ✂ replaced or cut in the build

### Status by system

| Spec area | Status | Reality in the build |
|-----------|:------:|----------------------|
| Deploy / recall, "oversee not micro" (§3, §6) | ✅ | `[E]` deploys the whole colony / recalls; goblins are autonomous. No per-goblin selection. |
| Named goblins + permadeath + memorial (§6) | ◑ | Named roster + memorial exist, but death is **instant** — no downed/rescue/injury buffer yet. |
| "Everything must be hauled home" (§5) | ✅ | Scrap and repaired machines are carried to the bot; killed carrier loses what it holds. |
| Scavenge tool tiers gate scrap (§7) | ◑ | Implemented, but **4 tiers** (steel→ceramic), **one tool per goblin**, scavenge only. No Identify/Repair families, no per-family tiers. |
| Identification step (unknown → inspect) (§5, §7) | ○ | Not built. Piles/machines are worked directly; no Survey Kit / scan-to-reveal. |
| Field repair → haul → **lair refurbish** (§5) | ◑ | Goblin repairs (time scales with cost) + hauls + bank. But repair pays the cost in-field and banks directly — **no second lair-refurbish step**, no repair-tool gate. |
| Harvest/value → time (§7) | ✅ | Per-piece scavenge time scales with scrap tier. |
| Noise meter (Quiet/Warning/Breach, decay) (§8) | ✂ | Replaced by a **time alarm**: breach at `ALARM_TIME = 7s`; no per-action noise or decay. |
| Breach + escalating besiegers (§8) | ◑ | Besieger: hp 3, dmg 1, cd 0.8, spd 58; spawn every 1.4s, cap 3 **+1 every 8s**. No **Armoured Besieger** variant yet. |
| Recall drops common / keeps rare; **emergency departure** (§9) | ◑ | Recall returns everyone and banks what they carry. No drop-common/keep-rare split; **no hold-to-emergency-depart**. |
| Scrapbot **module bay** (power/cooling/heat) (§10) | ✂ | Not built. Weapons/production live in the **factory grid**; weapons auto-fire when fed ammo. No power/cooling/heat budgets. |
| Cargo rules (stack 3, bulky −25% speed) (§5) | ◑ | Goblin carries 3 scrap; machines haul as one trip. No bulky speed penalty. |
| Recruitment w/ catch-up pricing (§6) | ◑ | Recruit with Tech Data, cap **6** (spec says 5); cost `3 × size` (spec uses 4/10/18 catch-up). |
| Traits (Quick Hands/Long Legs/Mule) (§6) | ○ | Not built — goblins have no traits yet. |
| Lair **project board** w/ milestone rewards (§11) | ✂ | Replaced by the lair **System Terminal** (upload Tech Data, recruit, upgrade machine type, upgrade/equip tool). |
| Lair systems give **gameplay rewards** per milestone (§11) | ○ | Current lair needs are **passive bars** filled by bridge components to fill → beacon win — the spec explicitly warns against passive bars; milestone rewards are TODO. |
| Distress-beacon win (§1, §11) | ✅ | Fill all four needs (oxygen/power/water/food) → beacon → `RESULT_RESCUED`. |
| Persistent base + extraction (§5, §15) | ◑ | **Inventory now persists** (grid + caches + inserters); extraction keeps base materials and ships components. Spec's "banked cargo / map discarded" is close but reality keeps more in the grid. |
| Room scan cards, threat ratings, archetypes (§4) | ○ | Rooms generate, but no scan card / threat rating / archetype signalling. |
| Save/load campaign state (§14) | ✅ | `MetaState` saves to `user://` (roster, tools, factory blob, needs, unlocks). |
| Telemetry / debug controls (§16) | ◑ | Headless test scenes + some `GROBIT_*` debug env hooks; no in-run telemetry export. |

### What the build has that the spec doesn't mention
- A real **factory/recycler economy** (scrap → refined materials via recyclers, scrap inserters,
  conveyors/splitters/filters, caches). The spec defers all of this (§2) — but it currently *is*
  the scrapbot's loadout, so it can't just be deferred until the module rig replaces it.
- **Ceramic (tier 4)** scrap/tools are live now (spec reserves ceramic for post-prototype).

### Realignment roadmap (working back toward the spec)
Ordered so each step is independently playtestable. We're "a few steps back," so early items
re-shape existing systems rather than add new ones.

1. **Identification pass.** Targets spawn unknown; add a Survey Kit (Identify role) + reveal.
   Decide whether the starter 3 goblins carry one tool from each family (spec §7).
2. **Tool roles.** Split the single scavenge tool into Identify / Scavenge / Repair families,
   each tiered; gate repair behind a repair tool. (Big — touches tools, terminal, goblin AI.)
3. **Injury buffer.** Add downed (5s) + rescue + injured-can't-deploy, in place of instant death.
4. **Noise model (optional).** Decide: keep the simple time alarm, or move to the accumulating
   noise meter with decay (spec §8). Flag this as an open call before building.
5. **Lair project board.** Reshape the System Terminal into the project board; give lair-system
   milestones real gameplay rewards instead of passive bars.
6. **The scrapbot hold — DONE (§0.1).** Split the one carried factory grid into a bot **cargo
   hold** (Dredge-style, fills during a run) + **module bay** (weapons/support + in-field
   consumable processors), with heavy refining moved to the lair workshop. Built across 5 slices
   (cargo hold → lair workshop → module bay → bay processors → gating + hold upgrade); category-
   gated; cargo hold is upgradable. Tests: `cargo_hold_test`, `lair_workshop_test`,
   `module_bay_test`, `bay_processor_test`, `loadout_polish_test`.
7. Polish: room scan cards, Armoured Besieger, emergency departure, traits, telemetry export.

> **Decisions still open for Grobit specifically** (beyond the spec's §19): keep 4 tiers or drop
> ceramic to match the 3-tier prototype? Keep instant permadeath or add the injury buffer? Settle
> these before the step they gate. **(The loadout fork is resolved — §0.1.)**

---

## 0.1 Resolved: the scrapbot hold (C-hybrid, Dredge-style)

We're taking **option C** (hybrid) with a **Dredge-style spatial hold** instead of the spec's flat
6-slot / power-cooling-heat bay (§10). This keeps the built shaped-footprint placement engine
(`FactoryGrid`) and splits *production* (lair) from *loadout + cargo* (bot).

- **Lair = workshop.** The existing factory grid lives at the lair and does the **heavy refining
  between runs**: scrap → base materials (recyclers), crafting components/bridge parts. It is no
  longer carried into the field.
- **Bot = two grids:**
  - **Module bay** — a fixed grid of shaped slots holding the expedition loadout: weapons
    (auto-fire, fed ammo), support (scanner, cargo rack, medbay…), and **1–2 in-field
    PROCESSORS** that make *run-sustaining consumables* — ammo, batteries/power, repair kits,
    armor. Bay space is the core tension: a processor you bring is a weapon or cargo slot you
    give up. Heavy refining is NOT allowed here — only lightweight "keep the run going" output.
  - **Cargo hold** — a separate grid the goblins deposit hauled loot into. **Scrap packs 1×1**
    (small stacks); **recovered machines are bulky shaped pieces** (reuse their footprints). When
    the hold fills you can't carry more → extract. This makes "when do I leave?" a spatial
    decision stacked on the siege clock. Cargo-rack modules / hull upgrades enlarge it.
- **Reuse:** `FactoryGrid`'s cells + shaped placement + per-instance layouts power both the bay
  and the hold; recyclers/recipes move to the lair-side grid unchanged.

Open sub-questions to settle as we build: exact bay vs. hold sizes; what batteries/repair
kits/armor actually *do* (implies a bot/goblin damage-sustain model); whether cargo-rack is a bay
module that trades into hold size.

---

## 0.2 Direction v0.4 — proposed (brainstorm 2026-10, NOT yet built)

Decisions from a chronological UX/flesh-out brainstorm. **Design intent, not implemented** — these
supersede parts of the v0.3 target and the current build once scheduled. Walked the player's path:
launch → lair → pre-run → (drive/run/extract still to brainstorm).

### Cold open & onboarding
- **Title/main menu** with a one-line premise (currently boots straight into `run.tscn`). Menu also
  hosts a **debug save** — a pre-built lair for testing (details TBD).
- **Win goal stays tucked in the Tasks tab** — no persistent HUD objective tracker. (Endgame itself —
  lair needs/beacon — is PARKED for now; revisit later.)
- **Guided first run:** each station **teaches itself** the first time you use it (contextual nudges),
  driven by the Mission Board. A heavier dedicated tutorial comes later.

### The lair becomes a BUILDABLE base
- The lair is a set of **stations the player builds and places themselves** — "the lair is up to the
  player." Reuses the existing **BuildManager/BuildPalette** + the lair's **`_lair_cells`** grid.
- **Workshop is free/pre-placed** (so you can start); everything else is **built with refined
  materials**: Mess Hall (recruit, Food), Tool-upgrade bench, Machine-upgrade bench, Tech bench
  (Tech Data unlocks), Mission Board — **and the existing Fabricator, Component Exchange, Repair
  Station fold into the buildable set too.**
- This **dismantles the current 4-tab System Terminal (`LairPanel`)** — each tab becomes its own
  physical station panel.
- **Placement is free**, stations **movable/removable** (reuse the machine move/scrap flow).
- **Soft sequence** early: the Mission Board guides building the unique stations in a sensible order;
  **after all unique buildings are up, building is free.** Post-sequence freedom (duplicates for
  throughput? utility/decor?) is UNDECIDED — duplicates a *maybe*, utility/decor a later version.

### Production redesign — assembly lines, not a conveyor sim
Replaces the 8×8 factory grid (recyclers + inserters/conveyors/splitters/filters). **Trim all the
routing complexity.**
- Machines are **generic process VERBS** — Heater, Presser, Molder, Folder, … — not material recyclers.
- **Connected chains (Option A):** scrap enters at an **Intake** and is handed machine-to-machine
  only where an **out-port and the next in-port LINE UP** on touching edges. **No conveyors** — if
  the ports don't align, that chain is dead (can't route around it). The puzzle is **aligning ports +
  packing the uniquely-shaped machines** into the grid.
- Mostly **1-in / 1-out**; **advanced machines may have multi-in/out** as opt-in complexity (keep it
  rare).
- **Product = f(input scrap type, ordered sequence of verbs).** Different scrap through the same
  sequence → different result.
- A grid fits **~1–3 products** depending on how much you can pack in.
- **Fluid** — rearrange the line anytime; nothing is locked to a product.
- **Recipe knowledge = HYBRID:** a few **known starter recipes** (never stuck) + the rest
  **discovered** by experimenting and logged in a **known-recipes book**. The guided run teaches one;
  the Mission Board nudges toward more.
- **Controller-first** throughout (cursor placement/rotation; no mouse dependency).

### The expedition / drive — push-your-luck (Beat 3)
A run is a **tense push-your-luck expedition**: deeper = richer loot, but pressure only climbs.
- **Heat = ONE run-wide meter (presence).** Never decays; only rises. It climbs while **enemies see
  you and you're engaging them**, and crawls/holds when you're not seen or fighting. Resets per run.
- **Enemy escalation keyed to Heat:** low Heat → enemies that only damage **goblins**; past a
  threshold → bigger enemies that can damage the **scrapbot**.
- **Bot has HP. Bot destroyed → GAME OVER, reload last save.** Saves happen **at the lair between
  runs**; extracting banks your haul (by saving). No mid-run checkpoints.
- **Doors are decision points.** Opening one runs a **two-stage hacking minigame:** (1) flick switches
  into the right **sequence**, then (2) stop a **circular/rotating timing bar** in the green. It
  reveals the room's **alarm** (its Heat cost + siege intensity); you **open** (adds Heat) or **skip**
  (no cost, no loot). **Botched hack = Heat spike + the door locks** for a bit. Tougher doors = longer
  sequence / tighter circle. Controller-first (d-pad + one button).
- **No separate detector subsystem** — rooms simply contain enemies; being seen + engaging is what
  raises Heat.
- **Once it's hot you can't avoid the swarm** — the decision collapses to *"do I have the firepower to
  push on, or run home?"*

### Combat & abilities rework (Beat 3)
- **Manual-fire turret.** The bay weapon **auto-AIMS** (keeps the nearest / Tab-picked target) but
  **the player presses SPACE to shoot** — no more auto-fire. Ammo (workshop-made, capped by hold size)
  is the clock; Ammo Loaders raise fire rate. This is the **only** counter-play in a hot room.
- **Abilities come ONLY from installed bay modules**, used from the **bot menu (ScrapbotPanel)**. The
  old field ability-on-Space **and** the run-start ability picker are **removed** (frees Space to
  shoot, and clears the ability picker out of the cold open).
- Module abilities are **tactical, NOT time-based** — use them from the paused menu, no twitch: e.g.
  **Scan** (reveal a room's loot potential, random/nearby room on the map), **Reduce Heat −10**
  (coolant module), **Heal Goblins** (medkit module), etc. The bay's "abilities strip" becomes the
  real, usable list, each entry powered by its module.

### In a room — command & defend (Beat 4)
- Drive in, **park (planted)**, **deploy the squad [E]**. **Goblins idle until commanded** — a light
  COMMAND layer, not autonomous oversight (a deliberate turn toward hands-on tactics, away from the
  v0.3 "oversee not micro" pillar).
- **Command cursor on WASD** (you move a cursor, not a character). Point at a pile / broken machine /
  floor drop and press **F** to create or grow a task: **each press adds one goblin** to it.
- **Priority = assignment order** (first task created is worked first, then the second, …). Your
  allocation **splits the squad** — 2 on task A + 1 on task B sends 2 and 1. A **Cancel** pulls all
  goblins off a task.
- Goblins **auto-haul to the bot when full and return to their task** (no babysitting trips); idle
  goblins wait at the bot.
- **Floor loot (food / materials / tech data) is gathered by goblins only** — you're planted, so
  they're your hands in the field.
- **You defend with the planted turret:** auto-aim, **Space to fire**, **Tab** to switch target.
  Fighting raises **Heat** → bigger, bot-threatening enemies arrive.
- **Instant permadeath** (no downed/rescue). **The player decides when a room is "done"** and recalls —
  nothing auto-ends it.
- In-room control map: **WASD** cursor · **F** task menu · **Space** fire · **Tab** target · **E** deploy/recall.

### Extraction — the drive-back gauntlet (Beat 5)
- Leaving is **player-decided**; recall the squad and **drive the bot all the way home** through the
  facility — a **retreat gauntlet**, not a clean exit.
- **Spawners** sit in certain rooms and produce the enemies. Below a Heat threshold you can **relieve
  pressure proactively** — clear a room's enemies and **destroy its spawner**. **Past a Heat threshold
  the facility is fully alerted:** spawners keep producing even when "destroyed."
- On the way back, enemies **path from the spawner rooms toward the bot** (converging on you); the
  hotter it is, the more come and the more relentless.
- **Bot destroyed anywhere = GAME OVER → reload last save.** All-or-nothing; the haul is lost if you
  don't make it home.
- **Auto-save on every return to the lair** — the only save point; a lost run rolls back to the last
  successful return.
- **The bot's turret destroys spawners** — shoot them down to relieve pressure. **Two staged Heat
  lines:** bot-killer enemies appear **first**, then a slightly higher line **fully alerts the
  facility** (past it spawners keep producing even when destroyed). Reads as: bigger enemies = "danger
  now," full-alert = "you can't clear your way out — run."

### Back home — arrival & the between-run loop (Beat 6)
- **The facility resets each run** — roguelite-fresh: new layout, spawners and Heat reset every trip.
  (Run-based, not a persistent dungeon you chip down.)
- On a successful return: **auto-save**, the haul unloads into the base inventory, and a **run summary
  card** shows — **scrap hauled, goblins lost (to the memorial), recipes/machines discovered** — before
  dropping back into the lair. The exhale beat after the gauntlet.
- Then the between-run loop already specced above: refine scrap → make ammo → spend **Food** (recruit)
  / **materials** (build + upgrade) / **Tech Data** (unlocks) → build/rearrange the lair → set the
  loadout at the bot → relaunch. The **Mission Board** points at the next goal.

### Still open (not yet brainstormed)
Hacking-minigame tuning; the module→ability catalogue (which bay modules grant Scan / Reduce-Heat /
Heal-Goblins / …); and the **endgame**, deliberately PARKED (lair needs / beacon / win — revisit
later). Economy rework (Food recruiting, materials for building/upgrades, Tech Data = unlocks only) is
already DONE in the build — see the colony-harvest memo.

---

## 1. Product statement

**Grobit** is a top-down salvage game about leading a small colony of autonomous goblins into a dead industrial facility.

The player drives a modular scrapbot, chooses rooms to salvage, and deploys named goblins to search scrap heaps and recover broken technology. Work generates noise. Noise causes breaches. The scrapbot's weapons and support modules buy the colony time, but the player must decide when the remaining loot is no longer worth the risk.

Recovered materials and components are used at the lair to improve tools, construct bot modules, and repair four survival systems. Completing all four systems activates a distress beacon and wins the campaign.

### Player fantasy

> I am the driver and protector of a vulnerable scavenger crew. I prepare the machine, choose which risks to take, and get attached to the goblins who survive them.

### Design pillars

1. **Command, do not micromanage.** Goblins work autonomously. The player's important decisions are where to deploy, what to prioritise, how to configure the bot, and when to leave.
2. **Everything valuable must make it home.** Loot only becomes safe when a goblin carries it into the scrapbot and the bot returns to the lair.
3. **The scrapbot buys time.** Its systems control danger; they should never make danger irrelevant.
4. **Named lives matter.** Goblins have small mechanical identities, persistent histories, injuries, and permanent death.
5. **Progress has visible purpose.** Every expedition should advance a chosen tool, module, or lair repair.

---

## 2. Scope of the initial test build

The first build must answer five questions:

1. Is watching autonomous goblins search and haul satisfying?
2. Does the player understand what loot they need and where to seek it?
3. Does the breach create a meaningful stay-or-leave decision?
4. Does configuring the scrapbot change how an expedition plays?
5. Does losing a goblin feel consequential without causing an unrecoverable campaign spiral?

### Build now

- One lair scene and one generated expedition map
- Three room archetypes plus a lair entrance
- Three material types and four component types
- Three heap types and one recoverable broken module
- Four scrapbot modules, including two weapons
- Three goblin traits and three assignable tool roles
- Tool tiers 1–3
- Noise, warning, breach, escalation, recall, extraction, injury, and death
- Two partially repairable lair systems
- Save/load for campaign state
- Debug controls and telemetry for balance testing

### Defer until the loop is proven

- Conveyors, inserters, production recipes, and in-bot factory simulation
- Secondary equipment, armour, or more than one equipped work tool per goblin
- More than one enemy family
- Bosses and story events
- Complex module rotations or per-cell wiring
- Food/upkeep simulation
- All four final lair systems and the full ending
- Procedural module footprints

---

## 3. Core loops

### Campaign loop

1. Select a project at the lair: a tool upgrade, bot module, or lair repair.
2. Review the project's required materials and components.
3. Configure the scrapbot for the intended expedition.
4. Explore rooms and inspect their salvage signals.
5. Deploy goblins, recover loot, and survive breaches.
6. Return to the lair and bank surviving cargo.
7. Complete projects and unlock safer access to richer regions.

### Room loop

1. **Scan:** entering a room reveals its threat rating, breach points, and broad salvage signals.
2. **Choose:** the player parks near promising unknown heaps or broken machines and decides whether to deploy.
3. **Identify:** goblins carrying survey tools inspect targets, revealing their contents, difficulty, and value.
4. **Work:** scavengers strip identified heaps while repairers stabilise identified machines for retrieval.
5. **Haul:** any free goblin may carry exposed loot or a recovered machine back to the bot.
6. **Warn:** work-generated noise reaches the warning threshold; doors signal the coming breach.
7. **Defend:** enemies enter while modules consume ammunition, energy, and heat capacity.
8. **Recall:** goblins drop ordinary loose salvage and return. Carriers of rare or bulky objects keep carrying them and move more slowly.
9. **Depart:** the player leaves for another room or returns to the lair.

### Desired rhythm

| Segment | Target duration |
| --- | ---: |
| Inspect and position | 5–12 seconds |
| Quiet salvage | 10–16 seconds |
| Warning | 3 seconds |
| Defended salvage | 10–25 seconds |
| Recall and escape | 3–8 seconds |
| Typical room visit | 30–60 seconds |
| Typical expedition | 8–15 minutes |

---

## 4. World and room selection

The initial expedition is a small connected map of 6–9 rooms. The player can return to the lair entrance at any time. Distance creates pressure because ammunition, injuries, and cargo accumulate across rooms.

### Room scan

On entry, the HUD displays a compact scan card:

- Room archetype and threat rating
- Number of unopened heaps
- Likely materials
- Possible components
- Presence of a broken module or rare objective part
- Environmental modifier, if any

The scan communicates probabilities, not exact contents. Example:

> **Pump Station — Threat 2**  
> Steel common · Copper possible · Pump likely · 2 breach doors

### Prototype room archetypes

| Room | Primary salvage | Secondary salvage | Character |
| --- | --- | --- | --- |
| Maintenance bay | Steel, motors | Wiring | Safe, open, introductory |
| Pump station | Steel, pumps | Copper | Narrow paths and long hauling routes |
| Control room | Copper, wiring | Circuit boards | Valuable, noisy, multiple breach points |

### Environmental modifiers for later testing

- **Echoing:** all work creates 20% more noise.
- **Collapsed:** one fewer breach point; goblin movement is 15% slower.
- **Dormant security:** contains better loot; enemies enter with armour.
- **Flooded:** bot movement and electrical weapon cooling are reduced.

Only Echoing is required for the first build.

---

## 5. Salvage and cargo

### Resource categories

#### Materials

Common resources used broadly in construction.

| Material | Tier | Main sources | Main uses |
| --- | ---: | --- | --- |
| Steel | 1 | Maintenance heaps | Basic modules, repairs, ammunition |
| Copper | 2 | Electrical heaps | Power systems, wiring, advanced tools |
| Plastic | 3 | Laboratory heaps | Lightweight modules, scatter ammunition |

Ceramic is reserved for the post-prototype fourth tier.

#### Components

Recognisable parts with narrower uses.

| Component | Typical source | Example uses |
| --- | --- | --- |
| Motor | Maintenance bay | Tool upgrade, ammo press, lair ventilation |
| Wiring | Control room | Scanner, weapon power, lair power |
| Pump | Pump station | Medical station, lair oxygen/water |
| Circuit board | Control room | Scanner, advanced weapons, system repairs |

#### Rare parts

Named objective pieces required for major lair milestones. Rare parts are signalled by the room scan and hauled as bulky objects. They are not random drops from ordinary heaps.

### Salvage targets and identification

Scrap heaps and broken machines begin **unidentified**. The room scan indicates broad possibilities, but an equipped identifier goblin must physically inspect a target before the colony can work it.

Identifying a target reveals:

- Its type and required tool tier
- Its remaining work or searches
- Its likely material and component categories
- Any guaranteed component or recoverable module
- For a machine, its module type, condition, and field-repair time

Identification takes time but produces little noise. Once identified, the target remains identified for the rest of the expedition—even if the colony leaves the room. This makes scouting a valid low-commitment visit.

### Scrap heaps

Each heap has:

- A tool-tier requirement
- A number of searches remaining
- A weighted loot table
- Search time per item
- Noise per completed search
- Optional guaranteed item revealed on the final search

Only a goblin equipped with a salvage tool of the required tier may work an identified heap. The goblin searches one item at a time. The item becomes visible when uncovered, creating a small anticipation beat before it is hauled.

### Broken machines

Broken machines are the main source of new scrapbot modules.

1. An identifier goblin inspects the unknown machine and reveals what it is.
2. A repair goblin with a sufficient tool tier performs a noisy field repair.
3. The field repair makes the machine safe to transport; it does not make the module immediately usable.
4. Any goblin hauls the recovered machine to the bot as a bulky object.
5. At the lair, the player refurbishes it by paying a smaller material/component cost, after which it becomes an installable module.

A failed or interrupted field repair retains its progress during the current expedition. A machine is lost only if its carrier dies before depositing it, it is abandoned on extraction, or the expedition fails.

### Cargo rules

- A goblin carries one item stack at a time.
- Materials stack to 3 units in a goblin's hands.
- Components are carried individually.
- Bulky parts and recovered modules require one goblin and reduce its speed by 25%.
- Deposited cargo is safe from room enemies but remains part of the expedition until the bot reaches the lair.
- If the bot is destroyed or the expedition is abandoned, unbanked cargo is lost. Bot destruction is not required in the first build; an explicit **Abandon Expedition** debug action is sufficient to test this rule.

### Loot-generation constraint

Pure randomness must never completely block progression. When a project is tracked:

- At least one room on the generated map must advertise a source for each required component.
- A room advertised as **likely** must contain at least one matching component.
- A rare objective part must have a known room and cannot be replaced by an unrelated drop.

---

## 6. Goblin colony

### Starting colony

- Start with 3 goblins.
- Maximum prototype colony size: 5.
- Every goblin has a generated name, portrait colour, one positive trait, health, injury state, lifetime haul count, and expedition history.
- Every goblin has exactly one equipped work tool, assigned at the lair before departure.

### Baseline statistics

| Stat | Initial value |
| --- | ---: |
| Maximum health | 3 |
| Move speed | 86 px/s |
| Work interaction range | 10 px |
| Material carry stack | 3 |
| Recall response delay | 0.15 s |

### Prototype traits

| Trait | Effect |
| --- | --- |
| Quick Hands | Identify, scavenge, and repair interactions are 15% faster |
| Long Legs | Movement speed is 12% higher |
| Mule | Material carry stack increases from 3 to 4 |

Traits should be bonuses, not liabilities. Their purpose is attachment and roster texture, not optimisation pressure.

### Universal tasks

Every goblin can haul revealed items, carry a downed goblin, board the scrapbot, and wait safely. Tools determine specialised work, not basic survival behaviour.

### Autonomous work priority

By default, each idle goblin selects a valid task in this order:

1. Recall, rescue, or emergency state
2. Player-prioritised compatible work
3. Revealed item waiting to be hauled
4. Partially completed compatible work
5. Nearest compatible identified target
6. Nearest unidentified target, if carrying an identifier tool
7. Return to a safe waiting position near the bot

Only one goblin reserves a normal work point at a time. A goblin never reserves a target its equipped tool cannot service. Bulky machines may expose two repair points in a later version.

### Player orders

The player does not select individual goblins. Available orders are:

- **Deploy / Recall:** one context-sensitive button
- **Prioritise:** point at a heap, item, or broken module and mark it as the colony's preferred task
- **Cancel priority:** point at the marked object or hold the prioritise control

Prioritising an unidentified target first attracts an identifier. Once identified, the same marker persists and attracts the required scavenger or repairer. The player gives one intention; the crew performs the dependency chain.

### Injury and death

- At 0 health, a goblin becomes **downed** for 5 seconds before dying.
- A downed goblin can be rescued automatically by another idle goblin if recall has been issued or no higher-priority threat is nearby.
- A rescuer moves at 65% speed and cannot carry loot.
- Getting a downed goblin into the bot leaves it **injured** after the expedition.
- An injured goblin survives but cannot deploy on the next expedition unless treated by a medical support module or a lair project.
- A goblin not recovered before its downed timer expires dies permanently and enters the memorial.

This buffer makes individual mistakes readable and creates rescues without weakening permadeath.

### Recruitment

Recruitment uses Tech Data recovered from data caches or dismantled modules.

| Current living roster | Cost to recruit |
| ---: | ---: |
| 1–2 | 4 Tech Data |
| 3 | 10 Tech Data |
| 4 | 18 Tech Data |

The catch-up price prevents an early death spiral while making the fifth goblin an investment.

---

## 7. Goblin tools, roles, and access tiers

Tools are persistent colony equipment assigned to individual goblins at the lair. Each goblin equips exactly one tool, which determines its specialised field job. Tools cannot normally be swapped during an expedition.

### Tool families

| Role | Prototype tool | Field capability | Typical behaviour |
| --- | --- | --- | --- |
| Identify | Survey Kit | Identifies unknown heaps and machines | Moves ahead of the work crew and reveals opportunities |
| Scavenge | Scrap Claw | Extracts loot from identified heaps | Produces steady cargo and noise |
| Repair | Patch Rig | Field-repairs identified machines | Performs long, noisy, high-value recovery work |

The starting colony receives one tier-1 tool from each family. This guarantees that the three-goblin starting crew can perform the complete identify → work → haul loop.

### Tool assignment

- Tools are equipped from the colony roster screen in the lair.
- The UI shows each goblin's portrait, trait, equipped tool, tier, and resulting role.
- A tool may be moved freely between healthy goblins while at the lair.
- An injured goblin automatically returns its tool to storage; progression is never lost through death.
- Before departure, the readiness panel warns about missing capabilities: `No identifier: unknown salvage cannot be opened` or `No repairer: machines can be identified but not recovered`.
- The game permits unusual crews, including all-scavenger or scout-only expeditions. Warnings inform rather than block departure.

### Tool tiers

Each family has its own tier. A tool can interact with a target whose requirement is equal to or below its tier.

| Family | Tier 1 | Tier 2 | Tier 3 |
| --- | --- | --- | --- |
| Identify | Survey Kit | Signal Probe | Diagnostic Array |
| Scavenge | Scrap Claw | Copper Cutter | Poly Ripper |
| Repair | Patch Rig | Arc Welder | Rebuild Harness |

Prototype upgrade costs:

| Upgrade | Cost |
| --- | --- |
| Any tool, tier 1 → 2 | 6 Steel + 1 Motor + role-specific component |
| Any tool, tier 2 → 3 | 6 Copper + 2 Wiring + 1 Circuit Board |

Role-specific components are Wiring for identify, Motor for scavenge, and Pump for repair. Exact costs should be tuned after measuring how often each role is deployed.

### Work timings

```text
identify_seconds = target.identify_seconds × identify_tool.speed_modifier
scavenge_seconds = heap.search_seconds × scavenge_tool.speed_modifier
repair_seconds = machine.repair_seconds × repair_tool.speed_modifier
```

Set base timings per target rather than multiplying time directly by tier. Recommended starting values:

| Action | Tier-1 target | Noise on completion |
| --- | ---: | ---: |
| Identify heap | 1.5 s | 2 |
| Identify machine | 2.5 s | 3 |
| Extract one heap result | 1.25 s | 7–10 |
| Field-repair machine | 6–10 s | 18–28 total |

### Crew-composition tension

- More identifiers reveal choices quickly but contribute little once a room is known.
- More scavengers increase ordinary yield and raise noise rapidly.
- More repairers recover modules faster but may have nothing useful to do in some rooms.
- Larger colonies enable redundancy, specialisation, and simultaneous hauling.

The default three-goblin crew is flexible but deliberately inefficient: while one goblin identifies and one performs specialised work, the third hauls. Recruitment improves throughput by allowing duplicate roles rather than only adding raw labour.

---

## 8. Noise, breach, and escalation

Noise is generated by actions. It is displayed as a meter with three named regions: **Quiet**, **Warning**, and **Breach**.

### Prototype noise values

| Event | Noise |
| --- | ---: |
| Identify a heap | +2 |
| Identify a machine | +3 |
| Complete a material search | +7 |
| Reveal a component | +10 |
| Each repair work tick | +3 |
| Complete field repair | +10 |
| Standard weapon shot | +0.6 |
| Heavy weapon shot | +2 |
| Goblin downed | +8 |

- Warning begins at 70 noise.
- Breach occurs at 100 noise.
- Warning lasts at least 3 seconds even if an action pushes the meter directly past 100.
- Before breach, noise decays by 2 per second when no goblin is working and no weapon is firing.
- After breach, noise no longer decays during that room visit.

### Enemy escalation

Prototype enemy: **Besieger**.

| Parameter | Initial value |
| --- | ---: |
| Health | 3 |
| Contact damage | 1 |
| Attack cooldown | 1.25 s |
| Move speed | 54 px/s |
| Initial spawn interval | 2.0 s |
| Initial alive cap | 3 |

Every 10 seconds after breach:

- Spawn interval decreases by 0.15 seconds, to a floor of 0.9 seconds.
- Alive cap increases by 1, to a prototype maximum of 8.

At 30 seconds after breach, 25% of spawns become **Armoured Besiegers** with 6 health. This is the soft room-ending pressure.

### Encounter goal

With a functional weapon and ordinary ammunition, the player should comfortably survive the first 10 seconds after breach, feel pressure by 20 seconds, and usually recall before 35 seconds.

---

## 9. Recall and departure

Recall must be dependable but must not erase the consequences of staying late.

### Normal recall

- All goblins immediately stop working.
- Goblins carrying common materials drop them.
- Goblins carrying components may drop them if threatened; otherwise they keep them.
- Goblins carrying rare parts or modules keep carrying them at the bulky-item speed penalty.
- Downed goblins become valid rescue tasks.
- The bot cannot leave while a living goblin remains outside.

### Emergency departure

Holding the deploy/recall button for 1 second after recall begins starts a 3-second departure countdown.

- The countdown is clearly announced in audio and UI.
- Any goblin aboard when it ends survives.
- Any living goblin outside is abandoned and recorded as missing/dead.
- The player may cancel before the final second.

Emergency departure should be rare, explicit, and emotionally uncomfortable—not an easy optimisation.

---

## 10. The scrapbot module system

The scrapbot is an expedition loadout, not a production factory.

### Prototype module bay

- Six module slots arranged as a 3 × 2 grid.
- Modules occupy one slot during the prototype.
- The bot supplies 6 power capacity and 6 cooling capacity.
- Each installed module has power draw and heat generation.
- Passive modules reserve power. Active modules generate heat while operating.
- When heat reaches maximum, active modules shut down for a 3-second vent cycle.

This tests loadout choice without requiring spatial wiring. Adjacency and irregular footprints can be added only if configuration lacks depth.

### Starting modules

| Module | Role | Power | Heat | Behaviour |
| --- | --- | ---: | ---: | --- |
| Scrap Repeater | Basic weapon | 2 | 0.7/shot | 1 damage, 0.35 s fire interval |
| Scanner | Information | 1 | 0 | Improves room scan from vague to likely loot |
| Cargo Rack | Capacity | 0 | 0 | +6 material cargo and +2 component cargo |

### Prototype craftable modules

| Module | Cost | Power | Heat | Behaviour |
| --- | --- | ---: | ---: | --- |
| Scattergun | 8 Steel, 3 Plastic, 1 Motor | 3 | 2.2/shot | Five short-range pellets; strong crowd control |
| Ammo Press | 6 Steel, 1 Motor, 1 Wiring | 2 | 0.5/cycle | Converts 1 Steel into 6 repeater rounds over 4 s |
| Recall Beacon | 4 Copper, 2 Wiring | 2 | 0 | Goblins move 20% faster while recalled |
| Field Medbay | 6 Steel, 2 Pumps, 1 Circuit Board | 3 | 1/s | Slowly treats one boarded injured goblin |

### Ammunition

- Repeater ammunition is prepared at the lair or produced by the Ammo Press.
- Scatter ammunition uses Plastic and cannot be produced by the prototype Ammo Press.
- Ammunition loaded into the bot is expedition inventory and is lost if the expedition is abandoned.
- The loadout screen estimates ammunition as **Low**, **Adequate**, or **Heavy** for the selected map threat.

### Weapon behaviour

- Weapons automatically target the nearest enemy threatening a goblin.
- The player may press the ability button to mark a priority target.
- Weapons stop firing when overheated, unpowered, out of ammunition, or manually disabled.
- Manual disable is important for controlling noise and conserving ammunition.

---

## 11. Lair projects and meta progression

The lair uses a project screen rather than a spatial factory. One project may be tracked at a time, but any affordable project can be completed.

### Project categories

1. **Colony:** recruit goblins and treat injuries.
2. **Tools:** unlock higher-tier heaps.
3. **Scrapbot:** craft modules and increase fundamental bot capacities.
4. **Lair systems:** advance the campaign and grant permanent benefits.

### Prototype lair systems

Each system has three milestones. The full game will use four systems with additional milestones.

#### Oxygen

| Milestone | Cost | Reward |
| --- | --- | --- |
| Patch leaks | 8 Steel + 1 Pump | Injured goblins recover after one expedition |
| Restore circulation | 6 Copper + 2 Pumps + 2 Wiring | Goblin maximum health becomes 4 |
| Stabilise oxygen | Rare Oxygen Regulator + 2 Circuit Boards | Oxygen system complete |

#### Power

| Milestone | Cost | Reward |
| --- | --- | --- |
| Restore junction | 6 Steel + 2 Wiring | Scrapbot power capacity +1 |
| Rebuild transformer | 8 Copper + 1 Motor + 2 Wiring | Scrapbot cooling capacity +1 |
| Stabilise grid | Rare Control Relay + 2 Circuit Boards | Power system complete |

### Progression rules

- Projects consume banked resources immediately on confirmation.
- Locked projects show their prerequisites and benefits.
- Completing a project produces an obvious visual change in the lair.
- Tool upgrades and lair milestones should compete for at least one resource.
- The project tracker appears on the expedition HUD and room scan.

### Full-campaign direction

The eventual four systems remain oxygen, power, water, and food. Completing milestones should change play throughout the campaign; the player should not fill four passive bars. Completing all systems unlocks the distress beacon finale.

---

## 12. UI and UX specification

### Run HUD

Always visible:

- Goblin roster strip: portrait, name, health, carried item, downed state
- Noise meter: Quiet / Warning / Breach, with threshold markers
- Weapon status: ammunition, heat, active/disabled state
- Bot cargo summary
- Context prompt for deploy, recall, prioritise, and interact
- Tracked-project ingredients

Contextual:

- Room scan card on entry
- Heap contents and remaining searches when nearby
- Large warning banner and door indicators before breach
- Recall status: `3/3 returning`, then `2/3 aboard`
- Emergency-departure countdown with the names of goblins still outside

### Lair screens

#### Project board

- Category tabs
- Project cards with icon, result, cost, and prerequisite
- Affordable and tracked states
- `Track` and `Build` actions are separate

#### Scrapbot loadout

- Six-slot module bay
- Module storage list
- Power and cooling budgets
- Ammunition load controls
- Plain-language warnings, such as `Scattergun installed but no shells loaded`
- Expedition readiness summary

#### Colony roster

- Living goblins with trait, status, equipped tool, role, tier, and lifetime haul count
- Tool inventory and one-click assignment/swap controls
- Crew capability summary: Identify / Scavenge / Repair, including highest available tier
- Departure warnings for missing roles or targets above the crew's tool tiers
- Recruitment action and current cost
- Memorial section for fallen goblins

#### Expedition summary

- Banked materials and components
- Modules and rare parts recovered
- Ammunition consumed
- Goblins injured, recovered, missing, or killed
- Projects newly affordable
- One primary continue action: `Return to Lair`

### Interaction principles

- Never communicate danger using colour alone; pair colour with shape, text, and sound.
- A goblin's current intention should be visible through an icon or short label.
- Every irreversible action requires a hold or confirmation.
- The player should reach deployment within 30 seconds of starting an ordinary expedition.
- Avoid inventory drag-and-drop during danger. Field interaction is limited to module toggles, target priority, and recall.

### Prototype controls

| Input | Action |
| --- | --- |
| WASD | Drive scrapbot / move in lair |
| E | Deploy or recall colony |
| Hold E after recall | Emergency departure |
| F | Interact / confirm |
| Right mouse or controller equivalent | Prioritise pointed task or enemy |
| Space | Toggle primary active module or weapon |
| Tab | Cycle installed weapons/modules |
| I | Cargo and status overlay; no field rearrangement |

---

## 13. Economy and initial balance targets

### Typical room yield

| Room quality | Materials | Components | Expected danger |
| --- | ---: | ---: | --- |
| Low | 6–10 | 0–1 | Can leave before or just after breach |
| Standard | 10–16 | 1–2 | Requires 10–20 seconds of defence |
| Valuable | 12–20 | 2–4 or one module | Requires ammunition and a risky recall |

Room yield assumes a balanced three-goblin crew. Specialised crews should change extraction speed, not silently alter the generated contents.

### Typical expedition outcome

- Visit 3–5 rooms.
- Bank 25–45 material units.
- Bank 3–7 components.
- Spend 25–60% of loaded ammunition.
- Complete a small project every 1–2 expeditions.
- Complete a major lair milestone every 3–5 expeditions.

### Anti-spiral safeguards

- Tier-1 heaps and basic repeater ammunition remain accessible without advanced components.
- Recruitment becomes cheaper below the starting colony size.
- The starting weapon cannot be permanently lost.
- A failed expedition loses field cargo and loaded consumables, not completed lair projects or stored modules.
- The generated map always contains at least one low-threat recovery room.

---

## 14. Data required for implementation

All balance values should be externalised. Suggested JSON resources follow; exact Godot class names may differ.

### Item definition

```json
{
  "id": "component_motor",
  "name": "Motor",
  "category": "component",
  "tier": 1,
  "stack_size": 1,
  "cargo_size": 1,
  "tags": ["mechanical", "maintenance"]
}
```

### Heap definition

```json
{
  "id": "heap_maintenance_t1",
  "name": "Maintenance Heap",
  "identify_tool_tier": 1,
  "scavenge_tool_tier": 1,
  "identify_seconds": 1.5,
  "searches_min": 4,
  "searches_max": 7,
  "seconds_per_search": 1.25,
  "noise_per_search": 7,
  "loot": [
    {"item": "material_steel", "weight": 70, "quantity_min": 1, "quantity_max": 3},
    {"item": "component_motor", "weight": 18, "quantity_min": 1, "quantity_max": 1},
    {"item": "component_wiring", "weight": 12, "quantity_min": 1, "quantity_max": 1}
  ]
}
```

### Broken-machine definition

```json
{
  "id": "broken_machine_recall_beacon",
  "name": "Damaged Recall Beacon",
  "identify_tool_tier": 1,
  "repair_tool_tier": 1,
  "identify_seconds": 2.5,
  "repair_seconds": 8.0,
  "repair_noise_total": 24,
  "recovered_item": "damaged_module_recall_beacon",
  "refurbish_cost": [
    {"item": "material_copper", "quantity": 3},
    {"item": "component_wiring", "quantity": 1}
  ]
}
```

### Tool definition

```json
{
  "id": "tool_survey_kit_t1",
  "name": "Survey Kit",
  "role": "identify",
  "tier": 1,
  "speed_modifier": 1.0,
  "valid_target_tags": ["unknown_heap", "unknown_machine"]
}
```

### Module definition

```json
{
  "id": "module_scrap_repeater",
  "name": "Scrap Repeater",
  "category": "weapon",
  "power_draw": 2,
  "heat_per_use": 0.7,
  "cooling_per_second": 1.0,
  "ammo_item": "ammo_repeater",
  "fire_interval": 0.35,
  "damage": 1,
  "noise_per_use": 0.6,
  "target_rule": "nearest_threat_to_goblin"
}
```

### Project definition

```json
{
  "id": "upgrade_scrap_claw_t2",
  "name": "Upgrade Scrap Claw: Copper Cutter",
  "category": "tool",
  "requires_projects": [],
  "cost": [
    {"item": "material_steel", "quantity": 8},
    {"item": "component_motor", "quantity": 2}
  ],
  "effects": [
    {"type": "upgrade_tool_instance", "tool_instance_id": "tool_instance_scavenge_01", "to_tier": 2}
  ]
}
```

### Goblin persistent record

```json
{
  "id": "goblin_0042",
  "name": "Mottle",
  "trait": "quick_hands",
  "equipped_tool_id": "tool_survey_kit_t1",
  "status": "healthy",
  "max_health": 3,
  "lifetime_items_hauled": 27,
  "expeditions_survived": 4,
  "memorial_note": ""
}
```

### Campaign save data

The save must contain:

- Banked item counts
- Living roster and memorial records
- Completed and tracked projects
- Owned tool instances, equipped-tool assignments, and per-family tiers
- Owned and installed modules
- Loaded ammunition
- Lair-system milestones
- Current map seed and expedition state if mid-expedition saving is supported
- Schema version for migration

---

## 15. System states and failure handling

### Expedition states

```text
PREPARING → EXPLORING → DEPLOYED → WARNING → BREACHED → RECALLING
     ↑           ↑                                            |
     └────────── LAIR ← EXTRACTING ←──────────────────────────┘
```

Room state persists during an expedition: searched heaps remain empty, dropped items remain where they fell, and breached rooms remain dangerous. Returning to the lair ends and discards the current map.

### Campaign failure

The campaign does not hard-fail when the colony dies. If no goblins remain:

- The lair receives one emergency recruit with no trait.
- Tech Data is set to at least 4.
- A low-threat recovery expedition is generated.
- The memorial and lost cargo remain, preserving consequence.

This recovery rule should be presented as a rare survivor arriving at the lair, not as a reset button.

---

## 16. Telemetry and test tools

Record the following for each room:

- Room archetype and threat rating
- Colony size and installed modules
- Time from deploy to warning, breach, recall, and final boarding
- Noise source totals
- Loot generated, revealed, dropped, deposited, and extracted
- Ammunition spent and weapon uptime
- Enemy spawns, kills, alive peak, and damage dealt
- Goblin downs, rescues, injuries, abandonments, and deaths

Record the following for each expedition:

- Rooms entered and salvaged
- Resources banked and lost
- Projects completed before and after
- Expedition duration
- Reason for returning or failing

### Debug controls

- Spawn a specified heap or enemy
- Add materials/components/Tech Data
- Set noise to 69, 99, or breached
- Damage/down a selected goblin
- Toggle infinite ammunition and invulnerability independently
- Speed game simulation to ×2 and ×4
- Display goblin task reservations and paths
- Export the current run summary as JSON

---

## 17. Acceptance tests for the vertical slice

The slice is ready for external testing when:

1. A new player can equip a viable crew, select a tracked project, identify a useful room, and deploy without explanation from the developer.
2. The identify → scavenge/repair → haul dependency is understandable without opening a help screen.
3. Every goblin's equipped role, current task, and change of intent is visually understandable.
4. The warning gives enough time to make a conscious stay-or-recall decision.
5. The first ten post-breach seconds are survivable with the starter repeater and reasonable ammunition.
6. Remaining for thirty post-breach seconds is visibly dangerous even with a good loadout.
7. At least two crew compositions and two scrapbot loadouts produce meaningfully different room strategies.
8. A player can recover from one goblin death without losing the dead goblin's equipped tool or restarting the campaign.
9. No required component is blocked solely by unlucky loot generation.
10. Completing a lair milestone changes both the lair presentation and a gameplay rule.
11. A full expedition, extraction, purchase, save, reload, and second expedition can be completed without state loss.

---

## 18. Recommended implementation order

1. Goblin tool assignment, role filtering, task reservations, hauling, deposit, and recall
2. Target identification, heap scavenging, broken-machine repair, loot generation, cargo, and room scan
3. Noise states, breach doors, enemy spawning, damage, downing, and rescue
4. Starter weapon, ammunition, heat, and automatic targeting
5. Extraction, banking, expedition summary, and persistence
6. Project board, per-family tool upgrades, and tracked-project guidance
7. Scrapbot module loadout, power/cooling budgets, and additional modules
8. Recruitment, injuries, memorial, and catch-up rules
9. Lair milestone effects, telemetry export, and tuning pass

The first internal milestone should be one hand-authored room containing one unknown heap, one unknown broken machine, three goblins equipped with one tool from each family, one breach door, and the starter repeater. Prove identify → scavenge/repair → haul → recall before building map generation or meta progression.

---

## 19. Decisions intentionally left open

These should be answered through testing rather than assumed now:

- Whether the module bay needs spatial footprints and adjacency
- Whether components should ever stack
- Whether goblins may keep ordinary loot during recall
- Whether a player-controlled bot weapon ability improves engagement
- Whether mid-expedition saving is necessary
- Whether injuries add drama or merely delay play
- Whether maps should persist across expeditions later in development

The prototype should expose these as tunables or isolated rules wherever practical.
