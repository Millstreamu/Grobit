# Inventory Factory — Design Direction

> **Status:** design record, not yet implemented. Captured 2026-09-19 from the
> project owner's spoken vision. This is now the north-star direction for the
> inventory and supersedes the simple grid inventory + in-room manufacturing where
> the two conflict. Nothing here is built yet; see "Open questions" before coding.
>
> Companion to [`MASTER_PROTOTYPE_DIRECTION.md`](MASTER_PROTOTYPE_DIRECTION.md).

## One-line vision

**The inventory *is* the factory.** Instead of a passive bag of resources, the
inventory grid is a spatial puzzle where you place processing machines, wire them
into assembly lines, and watch raw materials flow through into finished products —
all inside a fixed grid, with no rotation, so *fitting things together* is the core
challenge.

## The point: send resources home (+ the Mars goal)

> Captured 2026-09-19. This is the **purpose** the factory serves — easy to lose
> sight of: the game is about **sending refined resources back to base**.

- **Core purpose:** harvest → **refine in your factory** → **send the results
  home**. Everything else exists to serve this.
- **Progressive depth, run over run:** early on you might only be able to grab
  **scrap metal**, refine it, and send it back. You die, earn **improvements + a new
  machine** (e.g. wire → copper), and the refine-and-send chain deepens each run.
- **Overarching goal:** each map's goals **advance the game** *and* contribute to
  **re-commissioning the "research facility on Mars"** — the long game / win
  condition the deliveries feed.
- **Delivery mechanic — the "retrieval cartridge"** (placeholder name): **cheap to
  build (simple metal)**. You **load it, mark it ready**, and an **arm drills
  through the roof, descends, and grabs it** to send it home.
- **Safe rooms only:** delivery can happen **only in "safe rooms"**, never in
  dangerous ones — so getting valuable refined goods to a safe room to ship is part
  of the risk.

*(This reframes the current per-area `power_generator` objective and the
`extraction_beacon` "leave safely" flow — see "What this changes" and the open
questions for how they reconcile.)*

## Resolved decisions (2026-09-19)

1. **Persistence — factory resets each run; modules & unlocks don't.** You start
   every run with a **bare grid** and rebuild the machines/layout from scratch (the
   spatial puzzle resets), so the **factory is per-run state**. But your
   **persistent module collection**, **unlocked machine/recipe types**, and
   **reshuffle count** carry over — that's the meta layer. See "Meta progression
   (modules)".
2. **Processing — real-time in the background.** Machines keep processing while you
   explore and fight; the inventory screen is a **live view** you open to watch and
   manage. Machines tick even when the panel is closed.
3. **Item flow — adjacent slots auto-transfer.** An **exit slot placed directly
   against the next machine's input slot feeds it automatically.** Conveyors are
   only needed to move items **across a gap** (non-adjacent), plus logic for
   routing. (This refines the "manual at start" note — see UX rules below.)
4. **Power — none.** Machines just run when fed; there is **no power constraint**.
   Focus stays on the spatial/routing puzzle. (The scrapper-arm power-cell fuel
   loop for *harvesting* is unaffected by this and still stands for now.)

## Core concepts

### Machines live in the inventory grid
- Processing is done by **machines that occupy inventory slots** (not a separate
  crafting screen, not in-room stations for the basic chain).
- Each conversion needs **its own machine**. Examples given:
  - scrap → metal
  - wire → copper
  - copper + metal → electronics
- A machine takes a **minimum of two slots**: one **machine slot** + one **input
  slot**. (Multi-input recipes like copper + metal will need more input slots —
  see open questions on how multi-input footprints look.)
- The **machine slot shows an arrow** indicating **which adjacent slot the finished
  product comes out of** (the "exit slot").

### No rotation — this is the puzzle
- Machines **cannot be rotated** in the inventory. Their footprint (machine slot +
  input slot(s) + exit-slot direction) is fixed as given.
- Because you can't rotate, arranging machines so outputs line up with the next
  machine's inputs is a genuine spatial puzzle.

### Assembly lines (Factorio-like)
- You **arrange machines so one machine's output feeds the next machine's input**,
  building multi-step assembly lines inside the grid.
- Items are **visible flowing through** the processes in real time as you play and
  resources arrive.

### Progression: level up machines (RNG-shaped)
- As you play you can **"level up" machines** to gain **more slots**, or **add
  modules to slots** to improve them (faster, better yield, etc.).
- **The catch:** the *location* of newly-added slots is **RNG**. An upgrade might
  add slots in an **L-shape**, a **straight line**, etc.
- Since there's no rotation, **choosing which upgrades to take so everything still
  fits** (and still chains into your lines) is the strategic puzzle.

### Where upgrades come from
- Upgrades still come from the **repairable building found in rooms** (existing
  repair-station concept), **but now require materials produced by your assembly
  line** — so the factory feeds its own progression.

### The entrance (predictable)
- There is a **common, predictable entrance to the inventory** — a fixed point
  where incoming resources arrive — so the player can plan their layout around a
  known input location. (Behavior when the entrance slot is occupied: open — see
  questions.)

### Conveyors & logic
- **Conveyors** move items between slots/machines automatically, but are
  **expensive**, so early game you move things by hand.
- **Logic machines** exist to help automate (splitting/routing/etc. — details
  open).

### Final products
- Finished products have **no special destination** — they just **take up empty
  inventory space**. Managing that space (products competing with machines and
  in-flight items) is part of the challenge.

### Weapons & combat upgrades folded in
- **No more ability/upgrade "cards."** A weapon is a **machine in your inventory**
  that can also have **module slots** for upgrades.
- You can craft **improved ammo** for increased damage, etc. (details later).

## Meta progression (modules)

> Captured 2026-09-19. Resolves the "what carries between runs" question left open
> when we chose *factory resets each run*. The meta layer is **modules** (plus a
> reshuffle mechanic), not persistent machines.

- **Modules are the meta.** Machines are improved by **modules placed in their
  slots** (see the factory system). What grows over many runs is *what modules you
  can get* and *how flexibly you can fit upgrades* — not any built factory.
- **Module data library (persistent).** There is a growing library of modules that
  *can* appear. You **find new modules, or unlock them by completing things**,
  which permanently adds them to the library ("the module data library is
  improved"). A bigger library = a richer pool to draw from.
- **Data chips + decode station (RNG, in-run).** You spend **`tech_data`** (the
  existing resource — the "data chip") at a **decode station found/built in rooms**,
  and **pick 1 of 3 modules** drawn from your unlocked pool. This is the deliberate
  RNG that keeps runs varied; pool growth is what tilts the odds over time.
  Decoded modules join your **persistent collection** (kept across runs).
- **Reshuffle (RNG layouts).** Machine layouts are **RNG-shaped** in two places now:
  the **build-time port roll** (in/out cells placed randomly around the core when a
  machine is first built) and the **level-up slot roll**. A **reshuffle** re-rolls the
  current pending layout so a bad shape isn't a dead end. **Decision (2026-09-26):**
  the per-run reshuffle budget **defaults to 0** — you live with what you roll — and
  **only meta progression grants more** (the `reshuffles` meta effect). Both the build
  and level-up flows draw from this one shared `RunState.reshuffles` budget.

### Placeholders (tunable)
- Decode: **pick 1 of 3**.
- Reshuffle: **defaults to 0 per run**; meta progression (the `reshuffles` effect)
  grants more.

### Resolved decisions (meta, 2026-09-19)
1. **Decoded modules persist across runs.** You keep a **permanent collection** of
   the modules you decode/find; each run you rebuild the factory from scratch but
   **bring your module arsenal** to slot in (limited by fit / RNG slot shapes). So
   "resets each run" = machines, layout, and in-flight items reset — **modules and
   unlocks do not**.
2. **Machines/recipes also unlock over time** (alongside modules + reshuffle). The
   meta layer is: **persistent module collection** + **unlocked machine/recipe
   types** + **reshuffle count**. All available from run 1 is *not* the model —
   there's a real tech tree of what you can build.
3. **Decode station is found/built in rooms (in-run).** Decoding is a mid-run
   decision (like repair stations), not a calm between-run hub step.
4. **Data chip = the existing `tech_data` resource.** Reuse `tech_data` as the
   decode currency; no new item.

### Open questions (meta)
5. **"Pool grows" meaning:** does the growing pool refer to the set of module
   **types the 1-of-3 draft can offer** (unlocked by completing things), your
   **owned collection**, or both? (Working interpretation: completing things
   unlocks *draftable types*; decoding/finding adds *owned instances*.)
6. **Unlock triggers:** what "completing things" adds a module (or machine/recipe)
   to the pool — clearing an area, killing a boss, first-time crafting a product,
   objectives?
7. **Reshuffle counter:** is the reshuffle count **per-run** or a **meta pool**, and
   what's the growth curve?
8. **The other 2 decode options:** discarded on pick, or bankable/re-rollable?
9. **Module nature:** rarity/tiers? Can the same module appear twice? Are modules
   **consumable** or **reusable** within a run; can they be **moved/removed** once
   slotted?

## UX rules (as specified)

- **Manual at the boundaries, automatic between adjacent machines.** You **manually
  move** raw resources from the entrance into the first machine's input, and
  **manually clear final products** out of the way. Between machines whose exit and
  input slots **touch**, transfer is **automatic** (resolved decision 3).
  Conveyors/logic remove the remaining manual hops (entrance→machine, and any
  non-adjacent gap). *(Open: whether the entrance→first-input feed is manual until a
  conveyor, or auto if adjacent — question 8.)*
- **Exit-slot blocking:** if an item is **sitting in a machine's exit slot, that
  machine is blocked** — it won't process again until the item is **moved out**.
  Once cleared, a new input can be processed.
- Items are **watchable in transit** — you can see resources move through the
  machines as they process.

## Later (explicitly deferred by the owner)

- **Scraping nodes in rooms becomes a minigame** — now specced below in
  "Scrapping minigame".
- Detailed **weapon-machine + ammo** mechanics.
- Detailed **logic-machine** behaviors.
- **Grant the `reshuffles` meta effect somewhere.** Reshuffles now default to 0 and
  come only from `MetaState.effect_total("reshuffles", …)`, but **nothing currently
  grants it**, so the count stays 0 forever. Later: add a module/tech/unlock that
  provides the `reshuffles` effect (and decide the growth curve — see meta open
  question 7). Wiring: `RunState.begin_run()` reads the effect; the build/level UI in
  `factory_panel.gd` already spends and displays `RunState.reshuffles`.

## Scrapping minigame (node harvesting)

> Captured 2026-09-19. Harvesting a scrap node in a room is a small
> pick-and-manage minigame instead of a single press-F. **Important revision:** the
> **scrapper arm is a machine in the inventory** (see the factory system above), so
> harvested items flow directly into the arm's slots in the inventory grid.

### The node
- A node presents **4 slots**, each holding a **scrappable item**, e.g. *scrap
  metal, wire, plastics, empty fuel canister, metal crate* (a pool of junk types).
- Each node has an **independent pool of tokens** — a number **1–8** (placeholder)
  — representing how many **arm actions** the node holds. Actions spend tokens;
  when tokens hit **0 the node is spent and disappears**.
  - *(This node-token pool replaces the earlier "arm gets 6 charges per node"
    framing — the depletion counter now lives on the node.)*
- **Selecting an exposed slot** performs an action: it spends **1 token** and adds
  that slot's item to the **scrapper arm's holding slots** in your inventory (if
  there is room — see capacity below).

### Node modifiers (can combine)
- **Rusted:** **1–4** of the 4 slots are rusted over; each rusted slot needs
  **1–3 "hits"** of the arm to break the rust and expose the slot before its item
  can be taken. Tension: **take what's already exposed, or spend actions exposing a
  rusted slot** for what might be under it. (With only 1–8 tokens, you often
  *can't* expose everything — a deliberate trade-off.)
- **Loose:** **each hit/harvest reshuffles** the slot items into something else. A
  node can be **both loose and rusty**.

### Arm capacity = the limiter (ties into the factory)
- The scrapper arm (a machine in the inventory) has **holding slots**. If it has
  **3 empty slots you can harvest 3 items before it's full**.
- If those items **flow straight out into machines / conveyors**, the arm's slots
  keep freeing up and you can **keep harvesting** — so a well-built factory lets you
  strip a node in one visit.
- If the arm **fills up**, you can **exit the node**; the node **persists with its
  remaining tokens** and you can come back later, until it's fully depleted.

### Numbers so far (placeholders, all tunable)
- Node tokens: **1–8**.
- Rusted slots: **1–4** of 4; rust hits per slot: **1–3**.
- Arm holding slots: from the scrapper-arm machine's size (grows via factory
  level-ups — see open question).

### Resolved decisions (minigame, 2026-09-19)
1. **Power cells come OFF harvesting.** The node's 1–8 tokens are the harvest limit;
   power cells are kept as a resource but **repurposed for something else later**.
   *Consequence:* the just-built power-cell harvest-fuel code is now scheduled for
   rework/removal — see "What this changes" below.
2. **Every arm action spends a token** — rust-breaking hits *and* harvest picks each
   cost 1 of the node's tokens. Rust genuinely competes with harvesting for the
   scarce pool.
3. **Real-time / exposed.** Scrapping does **not** pause the world — enemies and
   time keep running, so harvesting is a risky commitment in contested rooms.
4. **Arm holding slots = the scrapper-arm machine's grid slots.** Harvested items
   land directly in the arm machine's slots in the inventory; **leveling the arm
   (RNG slots) grows harvest capacity** and drops items in-grid ready to route.

### Open questions (minigame)
5. **Loose reshuffle scope:** on a hit, do **all 4 slots** change, only the
   **not-yet-taken** ones, and do **rusted (still-hidden)** slots also reshuffle?
6. **Item pool:** is the junk pool **global weighted**, or **per node type / room /
   area**? Do rarer junk types exist?
7. **Visibility:** does the player **see** the node's remaining token count and each
   slot's rust level?
8. **Where items land:** do harvested items enter at the arm machine's **exit
   slot(s)** (subject to the exit-slot blocking rule), or fill **any** empty arm
   holding slot?

## What this changes vs. the current build

Current systems this reshapes or replaces (to reconcile when implementing):
- **Grid inventory** (`scripts/ui/inventory_panel.gd`, `RunState.slots`): becomes
  the factory canvas rather than a one-item-per-slot bag.
- **Recycler modules** (`scripts/machines/recycler_system.gd`, feed-the-module in
  inventory): generalized into the machine/assembly-line system.
- **In-room Fabricator + Manufacturing screen** (`scripts/build/fabricator.gd`,
  `scripts/machines/manufacturing.gd`, `scripts/ui/manufacture_panel.gd`):
  likely replaced by in-inventory machines (scope — see questions).
- **Ability cards / chooser** (`scripts/ui/ability_choice_panel.gd`,
  `scripts/player/grobit_abilities.gd`): weapons/abilities become inventory
  machines with module slots.
- **Repair stations** (`scripts/world/repair_station.gd`): kept, but reward costs
  are paid in assembly-line products.
- **Extraction beacon + area objective** (`scripts/build/extraction_beacon.gd`,
  the `power_generator` objective in `area.json`, `scripts/machines/power_generator.gd`):
  reframed by the **send-resources-home** loop and the **Mars re-commission** goal —
  the retrieval cartridge (safe-room shipping) becomes the primary way resources
  leave, and per-map goals feed Mars. Exact replace/coexist is an open question.
- **Scrapper-arm power-cell fuel loop** (just built): **to be reworked out of
  harvesting.** Harvesting is now gated by node tokens (minigame), not power cells,
  and the arm becomes an inventory machine. On implementation, remove/repurpose
  `RunState.scrapper_charge` / `charge_per_cell` / `reload_arm`, the `ScrapNode`
  fuel gate + HUD "Scrapper Arm" line, and the `starter_cache` / `efficient_arm`
  tech (they assume the power-cell gate). Power cells stay as a resource for a
  future use (open).

### Resolved decisions (sending home / Mars, 2026-09-19)
1. **Shipped = progress; unshipped = lost on death.** Shipping resources home is the
   **only** way they become permanent (funding improvements, machine/recipe
   unlocks, and Mars progress). Die with goods still in your factory → **gone**.
   (Modules & prior unlocks still persist — those are a separate track.) This is the
   central **"refine deeper vs. ship what you've got"** tension.
2. **Each map has a separate objective that gates shipping.** You complete a
   distinct map objective (repair a thing, reach a place — the current
   power-generator is an example) which **unlocks the ability to ship/leave**;
   shipping is the reward path. Per-map objectives ladder up to re-commissioning
   Mars.
3. **"Safe room" = any room you've cleared.** Kill all enemies in a room and it
   becomes safe (and stays safe) — reusing the existing lock/clear/unlock mechanic.
   You can ship from any secured room.
4. **One big cartridge = leave the map.** Shipping is a **single climactic action
   per map**: build the retrieval cartridge (cheap metal) in a cleared room, load
   your chosen resources, send it — and that **ends your time on the map**
   (successful extraction). There is **no incremental mid-run banking**; the
   retrieval cartridge **replaces** the old `extraction_beacon`. → cartridge
   **capacity** is the key lever (what you get to keep — see open question).

### Open questions (sending home / Mars)
5. **Cartridge capacity & cost:** how much does one cartridge hold (you likely can't
   ship your whole factory — you pick your best), and what does it cost to build?
6. **Shipping exposure:** does building/loading/calling the arm **take time** (a
   risk window / can the room be re-threatened), even though it's a cleared room?
7. **Mars milestones:** is re-commissioning a **tech tree of milestone deliveries**
   ("ship N copper → unlock the copper machine"), a **cumulative total**, or
   **story-gated stages** — and does it directly drive the machine/recipe & module
   unlocks?
8. **Fail state:** if you can't complete the map objective or can't survive to ship,
   is the whole run's resource haul simply lost (with modules/unlocks kept)? Any
   partial-credit or retry?

## Open questions (factory/inventory — resolve before/while building)

Recorded for later; the four architecture-defining ones are resolved above.

1. **Meta progression:** RESOLVED — it's **modules** (+ a reshuffle mechanic). See
   the "Meta progression (modules)" section above.
2. **Grid size:** what are the **starting dimensions**, and does the grid canvas
   ever **grow within a run** (separate from per-machine slot upgrades)?
3. **Output-arrow direction:** is a machine's exit-slot direction **fixed by the
   machine / its RNG shape**, or **chosen by the player at placement** (given "no
   rotation")?
4. **Multi-input recipes:** how does a footprint with **2+ inputs** (e.g. copper +
   metal → electronics) look — two input slots adjacent to the machine? Does
   order/position matter?
5. **Entrance:** where is it (fixed corner/edge?), and when the entrance slot is
   **occupied**, what happens to incoming resources — **queue, block harvesting,
   overflow to nearest empty slot, or drop**? Is the entrance→first-machine feed
   manual until a conveyor, or automatic if adjacent?
6. **Module RNG:** do **module slots** also appear in RNG locations, or only
   machine **level-up** slots? Can modules be moved/removed once placed?
7. **Weapon-machine mechanics:** does a weapon machine **consume crafted ammo from
   the grid to fire**, or is it a **stat/module container** whose modules define
   the gun? (owner said "later" — recording.)
8. **Failure/soft-lock:** if your layout can no longer fit a needed upgrade or gets
   clogged, is that a **fair run-ending fail** (roguelite), and what relief exists?
9. **Conveyor/logic cost & rules:** what do conveyors cost, how fast are they, and
   what exact logic pieces exist (splitter, filter, inserter…)?
10. **Harvest interaction:** how does the future **scraping minigame** deliver into
    the entrance, and does the current scrapper-arm/power-cell fuel loop stay?
