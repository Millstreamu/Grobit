# Bug: solid room props can make a generated room inaccessible

**Status:** Confirmed by code inspection. The Component Exchange is one affected
prop, but the placement defect is shared by every solid `InteractableObject`
placed on an unrestricted interior tile.

## Summary

The generator keeps the door tile itself out of `Room.interior_tiles`, but it
does not reserve the walkable tile immediately inside either side of a door.
That approach tile is therefore a legal result from both the nearest-tile and
random-tile placement helpers. A 26–30 px solid prop centred on that tile leaves
no traversable gap for Grobit's collision body in a 32 px-wide passage.

The start-room Component Exchange can consequently appear immediately in front
of a door and cut off the connected room. The Retrieval Pad has the same start-
room risk. Random Scrap Nodes and Fabricators can create the same obstruction
in every populated non-start room, and the fixed Workshop Repair Station and
objective terminal are vulnerable when a room's computed centre resolves to a
door approach or a narrow choke point.

Suggested severity: **High**. A roll can make required content, including the
objective or the route back to extraction, unreachable. There is no way to move
or destroy most affected props.

## Reproduction

### Component Exchange

1. Generate runs until the start room has a doorway whose interior approach is
   the nearest floor tile to `start_position + Vector2(-32, 32)`.
2. Start the run and walk toward that doorway.
3. Observe the Component Exchange centred on the only 32 px approach tile.

**Actual:** the exchange's 30×30 `StaticBody2D` blocks the passage. Grobit cannot
fit through the one-pixel gaps on its sides, so the adjoining room is cut off.

**Expected:** generated solid props never occupy a door tile, either adjacent
door-approach tile, or any other tile required to reach a doorway.

### Other generated blockers

The same issue can be reproduced with a seed that makes
`Room._random_interior_point()` choose a door approach for a Scrap Node or
Fabricator. Workshop Repair Stations and the objective terminal use centre-
based placement instead, so reproduce those with a narrow/asymmetric room whose
centre or nearest-to-centre tile is on a required approach.

## Investigation and root cause

### Door construction does only half of the exclusion

`AreaGenerator._render_tiles()` adds ordinary non-wall tiles to
`room.interior_tiles`, but deliberately does not add the carved door tile. This
protects the exact tile occupied by `Door`; it does **not** protect the cardinal
floor tiles on either side of it. Those tiles remain in `interior_tiles` and are
the only way to enter or leave a one-tile door.

Both placement helpers operate on that unannotated list:

- `Room.nearest_interior_tile()` chooses the closest interior tile, excluding
  only exact world positions supplied by the caller.
- `Room._random_interior_point()` uniformly chooses any interior tile.

There is no shared occupied/reserved-tile registry, no door-clearance query,
and no post-generation connectivity validation. The start-room `taken` array
only prevents the Retrieval Pad and Component Exchange from selecting the same
tile as each other; it knows nothing about doors. Random room population does
not even prevent solid props from overlapping one another.

### Confirmed risk inventory

| Spawned object | Placement path | Solid? | Door-blocking assessment |
| --- | --- | --- | --- |
| Component Exchange | nearest start-room interior tile | Yes, 30×30 | **Confirmed risk**; permanent and mandatory |
| Retrieval Pad | nearest start-room interior tile | Yes, 30×30 | **Confirmed risk**; permanent and required to finish a run |
| Scrap Node | random interior tile | Yes, 26×26 | **Confirmed risk** until harvested; may be impossible to reach from the blocked side |
| Fabricator Station | random interior tile | Yes, 30×30 | **Confirmed risk**; permanent |
| Workshop Repair Station | room centroid (not snapped) | Yes, 30×30 | **Confirmed risk** in narrow/concave geometry; permanent after repair |
| Objective Terminal | nearest objective-room tile to centroid | Yes, 30×30 | **Confirmed risk** in narrow/concave geometry; progression-critical |
| Broken machine find | random interior tile | No (`Area2D`) | Can overlap/visually clutter a doorway approach but cannot physically seal it |
| Salvage/resource pickup | random interior tile | No (`Area2D`) | Does not physically block movement |
| Hazard Zone | room centre | No (`Area2D`) | Does not block movement, although it can cover an entrance with damage |
| Spawner marker | random interior tile | No (`Node2D`) | Marker itself does not block movement |
| Enemies | random interior tile, then move | Character body | Temporary dynamic congestion, not a permanent generation seal |
| Respawn Beacon / Power Relay | player-selected tile | No collision body currently | Cannot physically seal a door today, despite build placement accepting approach tiles |

`DecodeStation` is also a solid 30×30 station and would be affected if restored
to generated placement. Any future subclass of `InteractableObject` will inherit
the same risk unless it uses a safe placement API.

## Recommended fix

Implement the fix at the placement-policy level rather than adding a special
case for the Component Exchange:

1. **Record navigation-reserved tiles while doors are built.** For every carved
   door, reserve the door tile and at least the first interior tile on each side.
   Prefer reserving a two-tile-deep, three-tile-wide landing where geometry
   permits, so the player can approach and turn rather than merely squeeze past.
2. **Give each `Room` one placement API.** Replace direct calls to
   `_random_interior_point()`, `center()`, and `nearest_interior_tile()` for solid
   props with methods such as `claim_random_prop_tile()` and
   `claim_nearest_prop_tile()`. They should filter navigation reservations and
   already claimed footprints, claim the selected tile atomically, and return
   failure when no safe tile exists.
3. **Handle failure safely.** Optional props should be skipped or tried in
   another room. Mandatory stations should expand the search to another safe
   tile and fail generation loudly if none exists; silently falling back to an
   unsafe first tile would recreate the bug.
4. **Keep non-solid placement separate.** Pickups and visual markers need not
   consume blocking-prop slots, but avoiding reserved approaches is still useful
   for interaction clarity. Hazard placement should use its own safety rule.
5. **Protect player construction too.** Add the reserved navigation region to
   `BuildManager._is_valid()`. Today's beacon and relay are non-solid, but the
   rule prevents future buildable collision changes from reintroducing the bug.
6. **Validate reachability after population.** Flood-fill walkable tile centres
   with permanent solid footprints removed. Every door approach, mandatory
   station, and objective must remain reachable from the room's entry approaches.
   This is a defense in depth check, not a substitute for reservations.

The minimum safe patch is to exclude the two cardinal approach tiles from every
solid-prop placement call. The shared claim API plus reachability check is the
preferred fix because it also eliminates solid-prop overlap and guards future
content.

## Regression test plan

1. Unit-test the reserved set for horizontal and vertical doors: it contains the
   door and both interior approaches and does not reserve unrelated floor.
2. Generate a large deterministic seed range and assert that no solid prop's
   footprint intersects a door-clearance reservation.
3. For every generated room in that seed range, flood-fill after population and
   assert all of its door approaches are mutually reachable.
4. Assert the Retrieval Pad, Component Exchange, and objective terminal are on
   distinct, unreserved, claimed tiles.
5. Force a room with fewer safe tiles than optional props and verify optional
   placement fails cleanly instead of falling back to a doorway.
6. Assert build-mode placement is rejected on door-clearance tiles.
7. Retain a check that non-solid pickups can still be collected if they happen
   to land near a door, without treating them as permanent blockers.

## Acceptance criteria

- No permanent solid object intersects the reserved clearance region for any
  generated door.
- Every room remains traversable between all of its doors after population.
- Start-room stations and the objective are reachable for every tested seed.
- Solid generated props never overlap one another.
- Optional population degrades gracefully when a room has no safe placement.
- Player construction cannot occupy a navigation-reserved doorway approach.
- Automated tests exercise both door orientations, constrained rooms, and a
  deterministic multi-seed generation sample.
