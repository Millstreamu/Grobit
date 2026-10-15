# Grobit — Development Workflow

How we build Grobit with AI (Claude) heavily, **without rework or wrong guesses**. The rule of thumb:
**design decisions live in a spec you approve or in data you own — never guessed mid-build by the AI.**

---

## The loop (per feature / slice)

1. **Spec first — but only for big or ambiguous slices.** Before writing code on anything large or
   unclear, Claude writes a short spec: what it does, which data files it reads, and **every design
   decision called out with a recommended default**. You approve or tweak *before any code exists*. Small,
   obvious slices skip this — Claude just builds them, stating the defaults it chose so you can veto.
   (Your call, 2026-10: **only big slices get the plan-mode gate.**)
2. **Decisions get captured** in the relevant `docs/` file + Claude's memory, so they're never
   re-litigated.
3. **Build the system.** Logic lives in code; every *knob* (number, cost, name, which-recipe-makes-what)
   lives in a `data/game/*.json` file you can edit.
4. **Verify.** Headless test sweep stays green, plus a screenshot for anything visual. Every slice lands
   green.

When Claude hits a fork it didn't anticipate mid-build, it stops and asks rather than guessing.

---

## Three layers — and who owns each

| Layer | Lives in | Owned by |
|---|---|---|
| **Content / balance data** | `data/game/*.json` | **You** (via the Config Studio or direct edits) |
| **Art** | `*-atlas.png` + `*-atlas.json` (from Proplet) | **You** (draw in Proplet, drop in) |
| **Systems / behaviour** | `scripts/**/*.gd` | **Claude** (built from approved specs) |

The goal: the only things Claude *decides* are implementation details. All *design* is yours, expressed
as approved specs + data + art.

### Data files (what each controls)

| File | Controls |
|---|---|
| `resources.json` | Every resource/item (name, icon, colour, stack). Includes chain products. |
| `machines.json` | Factory machines **and** bay modules (weapons, ammo loader, **ability modules**). |
| `recipes.json` | Old-factory machine recipes (refining/crafting). |
| `process.json` | Phase-4 process-verb **chains** (verbs + sequence→product recipes). |
| `stations.json` | Phase-1 buildable **lair stations** (cost, which panel they open). |
| `buildables.json` | Field buildables placed during a run. |
| `tech.json` | Tech-Data progression unlocks. |
| `quests.json` | Colony quests (Mission Board). |
| `enemies.json` | Enemy stats & behaviour. |
| `families.json` | Material families → weapon ammo mapping. |
| `generation.json` | Map-generation parameters. |
| `area.json` | Area defs (room enemy weights, salvage loot). |
| `abilities.json` | **DEAD** — the old field-ability system (removed Phase 0.2). Slated for deletion. |

---

## Art pipeline (Proplet → game)

Proplet exports a sprite sheet as **`Name-atlas.png` + `Name-atlas.json`**. The JSON shape is already
exactly what the game reads — no conversion:

```json
{ "image": "Name-atlas.png",
  "sprites": { "sprite_id": { "x": 0, "y": 0, "w": 24, "h": 24, "kind": "decor" } } }
```

Proplet's extra top-level fields (`width`, `height`, `count`, `padding`, `spacing`) are ignored by the
loader (`scripts/content/atlas_content.gd` reads only `image` + `sprites`). Steps:

1. Draw the sprite in Proplet using the **`id`, pixel size, and palette** listed in `docs/ART_REQUIRED.md`.
2. Export and drop `Name-atlas.png` + `Name-atlas.json` into the project.
3. Register the `.json` in `ContentLibrary.ATLAS_PATHS` (earlier paths win on id conflicts).
   *(Planned improvement: auto-discover `*-atlas.json` so this step needs no code edit.)*

**Missing art never blocks gameplay** — any unknown sprite id falls back to a flat coloured square (the
`color` from the data def). So systems ship first; art fills in by `id` later. `docs/ART_REQUIRED.md` is
the running shopping list (id · size · palette · what it's for).

---

## The Config Studio (user-friendly game configuration)

`tools/config-studio/index.html` — a standalone HTML tool: open it in a browser, author data with
forms/sliders + a live generation preview, then **Download / Copy** the JSON and save it over the matching
`data/game/*.json`. This is your lever to tune the game without touching code.

**Status (2026-10): stale.** It was built before much of the current game and only covers
`generation / enemies / abilities / recipes / buildables`. It still edits the dead `abilities.json` and
knows nothing about `process.json`, `stations.json`, the new ability modules in `machines.json`, the chain
products in `resources.json`, `quests.json`, or `tech.json`. **Config Studio v2** (bringing it in line
with the current data model) is a planned "big" slice and will get a spec first.

---

## Testing

- Headless sweep: every `scenes/test/*.tscn` whose script calls `get_tree().quit`. A slice isn't done
  until the sweep is green. New `class_name` scripts need a `--headless --import` pass to register.
- Visual slices get a screenshot (render harness or the live game) before being called done.
- Claude never commits or pushes — **you** do that.
