# Bug: generated scrap and junk piles overlap on the ground

**Status:** Fixed. All stationary generated room content now claims a unique,
navigation-safe floor tile before it is spawned.

## Summary

Harvestable Scrap Nodes already used the room's claimed-tile registry, but broken
machine finds (the junk piles) and loose salvage pickups chose an unrestricted
random interior tile. They could therefore select the same tile as a Scrap Node,
another machine find, a Fabricator, or another salvage pickup. Two sprites and
interaction areas then appeared directly on top of one another.

Suggested severity: **Medium**. The overlap does not usually block navigation,
but it hides content, makes interaction selection ambiguous, and can make a room
look as though it contains less salvage than was generated.

## Reproduction

1. Start runs with different seeds and inspect non-start rooms, especially salvage
   rooms and rooms receiving one of the guaranteed broken-machine finds.
2. Find a room where a broken machine or loose pickup randomly selects a tile
   already claimed by a Scrap Node or other generated object.
3. Observe the sprites and interaction targets occupying the same floor tile.

**Actual:** solid props reserve tiles, while non-solid ground content ignores the
reservation and can spawn on top of existing content or one another.

**Expected:** every stationary generated pile or pickup gets a distinct floor tile
that is also outside doorway navigation reservations.

## Root cause

`Room.spawn_harvest()` and Fabricator placement call
`claim_random_prop_tile()`, which atomically filters and records occupied tiles.
In contrast, `_maybe_spawn_machine()`, `_spawn_guaranteed_chain()`, and
`Room.spawn_salvage()` called `_random_interior_point()`. That helper is suitable
for transient enemies and visual markers, but it has no awareness of navigation
reservations or earlier placement claims.

The guaranteed-chain pass runs after ordinary room population, making overlap
especially likely: it could place a junk pile onto any Scrap Node, Fabricator, or
earlier random machine already in the chosen room.

## Fix

- Use the room's atomic claimed-tile API for random machine finds and salvage.
- Use the same API for guaranteed machine finds; if the initially chosen room is
  full, scan the remaining non-start rooms from that random starting point.
- Skip optional content when no safe tile remains rather than overlap it.
- Emit a warning only if no room can accommodate a guaranteed find.
- Retain unrestricted random placement only for moving/transient entities such as
  enemies and non-interactable spawner markers.

## Regression coverage

The door-clearance regression now also models a Scrap Node followed by a junk
pile. It asserts that the two claims differ and that a third claim fails cleanly
when the room is exhausted. Structural tests verify every affected placement path
uses `claim_random_prop_tile()` and no longer assigns `_random_interior_point()`.

## Acceptance criteria

- Scrap Nodes, Fabricators, broken machine piles, and salvage pickups never share
  a floor tile at generation time.
- These objects never occupy a navigation-reserved doorway landing.
- Optional content is skipped if a room has no safe free tile.
- Guaranteed machine finds try all eligible rooms before reporting that placement
  is impossible.
