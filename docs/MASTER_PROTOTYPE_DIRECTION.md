# GROBIT — MASTER PROTOTYPE DIRECTION

Grobit is a real-time top-down salvage/exploration game being built in Godot 4.

This document describes the direction for the first complete rough prototype.

The goal is NOT polish.

The goal is to get the major systems into a rough playable state so the full gameplay loop can be tested.

Do not invent major features beyond what is described here.

If a design detail is unclear, prefer the simplest implementation that can be changed later.

---

# CURRENTLY WORKING

The project already has:

- external PNG + JSON art loading
- tileset loading
- atlas loading
- visual content test
- Grobit player scene
- smooth real-time WASD movement
- smooth rotation toward movement direction
- wall collision
- camera following player
- basic enemy
- enemy follows player
- auto-targeted projectile attack
- enemy health/death
- scrap/resource drop
- resource pickup
- simple temporary resource counter

Preserve these systems unless a change is required for integration.

---

# CORE GAME IDEA

The player controls Grobit and explores a larger generated area made from connected rooms.

The player enters rooms through doors.

When entering a combat room, the entrance may lock.

The player deals with the room, collects salvage/resources, and continues deeper into the area.

During the run the player can:

- collect materials
- manage materials
- recycle/process materials
- craft/build certain things
- improve their ability to survive deeper into the area
- eventually gather and manufacture the materials needed to repair the area's major broken machine

The player can also construct an extraction point and leave the area with what they have collected.

Future runs benefit from technology/data discovered during previous runs.

---

# DESIGN PRINCIPLE

Grobit should get depth mainly from:

- interacting systems
- resource decisions
- technology
- crafting
- procedural room combinations
- different enemies
- different run strategies

Avoid relying on large amounts of animation or handcrafted content.

Art requirements should stay relatively low.

---

# IMPLEMENTATION APPROACH

Implement the following sections ONE AT A TIME.

After completing each major section:

- make sure the project still runs
- fix errors
- preserve existing systems
- keep the implementation understandable
- avoid prematurely polishing visuals
- continue to the next section only once the previous system works at a basic level

Do not rewrite working systems simply to make them more architecturally sophisticated.

---

# 1. RESOURCE SYSTEM

Replace the temporary single scrap counter with a simple reusable resource system.

Start with three prototype resources:

- raw_scrap
- metal
- electronics

Each resource should have:

- stable ID
- display name
- icon reference
- quantity

Artwork should continue to come from the existing atlas/content system.

Gameplay data should remain separate from artwork JSON.

Create simple game-data definitions for resources.

---

# 2. BASIC INVENTORY

Create a simple inventory interface.

The player should be able to open and close it.

For the rough prototype it only needs to show:

- resource icon
- resource name
- quantity

Do not build a complicated RPG inventory grid.

Resources can simply be stored as quantities.

Leave room for the system to become more complex later.

---

# 3. RECYCLER SYSTEM

Add the first version of Grobit's recycler mechanic.

The player has a small number of recycler/module slots.

For the prototype, start with ONE recycler slot.

Create one basic recycler:

Scrap Recycler

Example behaviour:

raw_scrap -> metal

The recycler should automatically process resources while installed.

Processing should happen over time rather than instantly.

Show enough UI information for the player to understand:

- recycler installed
- input material
- output material
- processing progress

Keep values configurable.

Do not build a large processing tree yet.

---

# 4. PLAYER HEALTH AND ENEMY DAMAGE

Give Grobit:

- health
- damage
- death

Allow the basic enemy to damage Grobit when close enough.

Keep enemy attacks extremely simple.

Add basic temporary visual/debug feedback when damage occurs.

Do not heavily polish combat effects.

---

# 5. GROBIT ABILITIES

Add rough versions of the four intended player abilities.

The current auto-targeted projectile attack becomes the main Shoot ability.

Prototype:

Shoot

- existing auto-target attack

EMP

- area around Grobit
- temporarily disables or damages nearby enemies

Shield

- temporary protection/reduced damage

Regen

- restores some health
- should have a cooldown or resource limitation

Controls should remain simple.

Expose cooldowns and other balance values for later tuning.

Do not create complicated skill trees yet.

---

# 6. DOORS AND ROOM CLEARING

Add working room doors.

Basic behaviour:

- Grobit enters a room
- combat room activates
- entrance door locks
- enemies become active/spawn
- once the room objective is complete, exits unlock

For the prototype, the objective can simply be:

kill all enemies

Structure this so other room-completion conditions could be added later.

---

# 7. MULTIPLE CONNECTED ROOMS

Create a rough area consisting of multiple connected rooms.

Rooms can initially be simple and ugly.

The important part is testing:

enter room
-> door locks
-> fight
-> salvage
-> door unlocks
-> choose next room

Allow branching where practical.

Do not create a giant map yet.

---

# 8. BASIC PROCEDURAL AREA GENERATION

Create a first rough seeded generator.

The generated area should consist of connected rooms rather than one continuous random noise map.

Rooms should eventually be able to have organic shapes, but the first version can be simpler.

Requirements:

- seed-based generation
- connected rooms
- start room
- combat rooms
- later room types can be added
- doors correctly connect rooms
- player cannot enter unreachable space

Keep generation data-driven where practical.

The generator should not contain hard-coded dependencies on the prototype artwork.

---

# 9. BUILD MODE

Add a very simple way for Grobit to construct things during a run.

The player enters a build mode or selects a buildable.

Show a placement preview.

Allow placement only in valid locations.

Building consumes resources.

For the prototype, only two buildables are required:

- Respawn Beacon
- Extraction Beacon

Do not create a large construction system yet.

---

# 10. RESPAWN BEACON

The Respawn Beacon acts as a temporary checkpoint.

Rough behaviour:

- player constructs beacon
- beacon has limited uses
- if Grobit dies, they respawn there
- one use is consumed
- if no valid beacon remains, the run ends

Start with 1 or 2 uses as an easily configurable value.

Exact penalties for death are NOT decided yet.

For the rough prototype, keep the penalty minimal.

---

# 11. EXTRACTION BEACON

The player can construct an Extraction Beacon using resources.

Once constructed, it allows the player to end the current run successfully.

Show a simple confirmation.

On extraction:

- record what resources were extracted
- end the current run
- show a basic run summary

This is an important part of the prototype.

The player should have the decision:

continue deeper for more resources

or

spend materials to build an extraction point and leave safely

---

# 12. TECH DATA

Add a prototype permanent progression resource:

tech_data

Tech data can be found during runs.

Extracted tech data persists outside the run.

Use a simple save system.

Tech data unlocks new technologies.

For now only make a tiny prototype tech list.

Example:

- improved recycler
- increased movement speed
- increased maximum health
- new buildable recipe

These are examples, not a requirement for the final progression design.

Keep unlock definitions data-driven.

---

# 13. BASIC RUN / META SEPARATION

Separate:

RUN DATA

from

PERMANENT DATA

Run data includes things such as:

- current materials
- current health
- installed recycler
- placed structures

Permanent data includes things such as:

- discovered technology
- unlocked recipes
- persistent tech data

Make restarting a run clean and reliable.

---

# 14. AREA OBJECTIVE

Add a rough version of the long-term objective for one area.

The area contains one major broken machine.

For the prototype this can be:

POWER GENERATOR

Repairing it requires several manufactured materials.

Example structure:

collect raw resources

-> recycle/refine them

-> manufacture required components

-> bring components to generator

-> repair generator

The exact crafting chain is NOT final.

Create only enough of a chain to prove the concept.

The important gameplay question is whether it feels satisfying to gradually create the materials needed for the final repair while exploring.

---

# 15. BASIC MANUFACTURING

Add only the minimum manufacturing required for the Power Generator objective.

Keep this separate from recyclers conceptually.

Recycler:
converts common/raw materials over time.

Manufacturing:
uses processed materials to create specific components.

Do not create a huge recipe system.

Use data-driven recipes so recipes can easily be added later.

---

# 16. COMPLETE PROTOTYPE LOOP

At the end, the player should roughly be able to:

start a run

-> enter generated area

-> clear rooms

-> collect salvage

-> process salvage using installed recycler

-> survive enemies

-> use abilities

-> move deeper

-> construct a respawn point

-> gather useful materials

-> manufacture components

-> either build an Extraction Beacon and leave

OR

-> continue until enough materials are available to repair the Power Generator

-> repair Power Generator

-> finish the area

-> keep extracted tech progression

-> start another run

The prototype does NOT need to be balanced for 20 hours yet.

It only needs to prove that this loop works.

---

# CONTENT / ART PIPELINE

Continue using the external pixel-art program.

Artwork comes into the project as PNG + JSON.

Two primary content formats currently exist:

TILESETS

- environment artwork
- terrain
- floors
- walls
- doors
- related map pieces

ATLASES

- items
- resources
- enemies
- player
- machines
- buildables
- UI icons
- other regular sprites

Do not require the user to manually recreate atlas regions inside Godot.

Gameplay definitions should reference artwork using stable content IDs.

Do not place balance/gameplay information into the artwork JSON unless genuinely necessary.

---

# PLACEHOLDER ART

If artwork does not yet exist for a new gameplay object:

use a simple generated placeholder

and clearly report which artwork is missing.

Do NOT block gameplay implementation because an art asset has not yet been created.

At the end of implementation, provide a list titled:

ARTWORK NEEDED

with every missing asset and suggested size.

---

# AREA CONFIGURATION

The eventual goal is for additional areas to be relatively easy to create.

Avoid embedding one area's exact contents throughout gameplay code.

Where practical, area definitions should eventually be able to specify things such as:

- tileset
- available enemies
- room types
- resource distribution
- major repair objective
- generation settings

Do NOT build a full area editor yet.

Just avoid architecture that would make multiple areas unnecessarily difficult later.

---

# IMPORTANT UNDECIDED DESIGN QUESTIONS

Do not permanently solve these unless implementation requires a temporary answer:

- inventory capacity
- weight limits
- exact death penalties
- exact recycler limitations
- power/energy systems
- exact room sizes
- exact map size
- exact crafting complexity
- exact number of ability slots
- exact progression balance
- exact resource economy
- exact tech tree structure

When a temporary answer is needed:

choose something simple,
make it configurable,
and document the assumption.

---

# FINAL PROTOTYPE PRIORITY

Priority order:

1. Works
2. Playable
3. Easy to modify
4. Understandable
5. Looks decent
6. Polished

Do not reverse this order.

The purpose of this prototype is to discover what Grobit should become through testing.
