# Bug: Scrapper Arm harvest slots stay behind after the arm moves

**Status:** Fixed. Relocation now treats the Scrapper Arm's typed holding cells as
part of its claimed footprint, preserves their material assignments and counts,
and recreates them beside the moved core. Regression coverage verifies cleanup,
state preservation, post-move harvesting, bounds, and collision handling.

## Summary

Moving the Scrapper Arm in the inventory relocates only its core cell. The four
typed holding cells that receive harvested scrap remain at the arm's previous
position. Subsequent copper, steel, plastic, and ceramic scrap therefore appears
to spawn into empty or unrelated cells instead of alongside the visible arm.

Suggested severity: **High**. Reorganizing the inventory can separate a mandatory
resource-entry machine from its inputs, leave invisible reserved cells behind,
and make the factory layout misleading until the inventory is reset or reloaded.

## Reproduction

1. Start a run with the pre-placed Scrapper Arm in the factory inventory.
2. Open the inventory while factory layout editing is available.
3. Put the cursor on the Scrapper Arm's core and press `M` to lift it.
4. Move the preview to another valid location and press `Space` to place it.
5. Inspect the four cells beside the old and new core positions.
6. Harvest a scrap pile of an unlocked material, or otherwise deposit typed scrap
   through `FactoryGrid.deposit_harvest()`.

**Actual:** The Scrapper Arm core moves, but its four typed scrap spawn/holding
points stay beside the old core. Harvested material continues to be deposited at
those old cells. No corresponding holding points appear beside the new core.

**Expected:** The core and all four typed holding cells move together as one rigid
five-cell machine. Existing counts and each cell's material assignment should be
preserved at the equivalent offsets from the new core, and the old footprint
should be completely cleared.

## Investigation and root cause

The Scrapper Arm differs from ordinary machines in two important ways:

- `place_scrapper_arm()` creates its four holding cells as `arm_slot` cells using
  the authored `holding` offsets.
- Those cells are not stored in the machine's generic `slots` array; their
  positions are derived from `hold_offsets_of(m)` and the current core.

The ordinary move path does not preserve that representation:

1. `FactoryPanel._handle_move_input()` calls `move_offsets(mi)` and then
   `move_machine(mi, new_core)` for every machine, including the Scrapper Arm.
2. `move_offsets()` returns offsets only for positions in `m.slots`. The arm's
   `arm_slot` holding cells are not in that array, so the returned list is empty.
3. `_relocate()` clears the old core, extra body cells, and `m.slots`, but it does
   not clear `holding_positions(m)`. The old typed holding cells consequently
   remain in the grid.
4. `_relocate()` recreates only the core, body, and generic `machine_slot` cells
   supplied through `slot_offsets`. It never recreates `arm_slot` cells or copies
   their `scrap` and `count` values at the new core.

`can_relocate()` does include `hold_offsets_of(m)` when checking that the proposed
ports are in bounds and do not collide with another machine. This makes the move
preview appear to validate the complete arm footprint even though `_relocate()`
does not actually move that footprint. The validation and mutation paths therefore
disagree.

The stale cells remain active harvest destinations because
`deposit_harvest()` searches the grid for the matching `arm_slot` kind and scrap
type; it does not require that the cell still be adjacent to the arm's current
core.

## Recommended fix

Treat Scrapper Arm holding cells as stateful machine-owned cells during every
relocation:

1. Before clearing anything, capture each holding offset and its complete cell
   data, including the typed `scrap` identifier and current `count`.
2. Include the holding offsets in the relocation footprint and collision checks
   without converting them into generic upgrade/module slots.
3. Clear all old holding positions when the old machine footprint is vacated.
4. Restore each captured cell at `new_core + offset` as an `arm_slot`, preserving
   its material assignment and count.
5. Keep the generic `m.slots` and module relocation behavior unchanged for normal
   machine slots.

A machine-owned-cell abstraction shared by placement, pickup, collision checking,
and relocation would reduce the chance that future special cell kinds develop the
same split-footprint bug. At minimum, relocation should explicitly branch for the
Scrapper Arm in the same way that placement and pickup already do.

## Regression test plan

Add coverage to the factory relocation test that:

1. Places a Scrapper Arm and deposits distinct non-zero counts into multiple
   unlocked typed holding cells.
2. Moves the arm by a known delta.
3. Asserts the old core and all four old holding positions are empty.
4. Asserts the new core and four translated holding positions have the correct
   cell kinds, scrap types, and original counts.
5. Deposits another harvested item after the move and verifies only the matching
   new holding cell increments.
6. Verifies a move is rejected when any translated holding position is out of
   bounds or overlaps another machine.
7. Retains an ordinary-machine relocation case to ensure input/output/module slots
   still translate correctly.

## Acceptance criteria

- Moving the Scrapper Arm relocates its core and all four typed holding cells by
  the same delta.
- Existing harvested scrap counts and material-to-slot assignments survive the
  move.
- No `arm_slot` cells remain at the previous location.
- New harvests are deposited only into holding cells beside the arm's new core.
- The move preview's accepted footprint exactly matches the cells written by the
  completed move.
- Invalid moves remain blocked when any part of the five-cell arm footprint is
  out of bounds or occupied by another machine.
- Automated regression coverage exercises both populated and empty arm slots.
