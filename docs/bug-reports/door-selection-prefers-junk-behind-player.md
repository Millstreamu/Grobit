# Bug: junk behind the player steals door interaction selection

**Status:** Fixed. Interaction selection now prefers eligible objects in the
player's forward half-plane before applying type priority and distance. The HUD
uses the same target-selection helper as the highlight and input dispatcher.

## Summary

When the player stands between a usable door and an in-range junk pile, the
selection highlight can move to the pile behind the player. Pressing or holding
`F` then starts harvesting the pile instead of opening the door in front of the
player.

This is deterministic whenever both objects are interactable; it only appears
intermittent during play because both objects must be inside their respective
interaction ranges at the same time.

## Reproduction

1. Place a closed, unsealed door less than 34 px in front of the player.
2. Place a non-empty `ScrapNode` less than 30 px behind the player (or stand so
   an existing door and pile are simultaneously in range).
3. Face and approach the door while remaining in range of the pile.
4. Observe the green interaction highlight and the contextual interaction
   prompt.
5. Hold `F`.

**Actual:** The junk pile behind the player is highlighted, the HUD shows its
harvest prompt, and holding `F` harvests it. The door does not open.

**Expected:** The door in front of the player is highlighted and `F` opens it.
An object behind the player should not override the intended in-front target
merely because both are in range.

## Impact

- Interaction feedback contradicts the player's facing and movement intent.
- Opening a door may require backing away from a pile first, which is especially
  awkward at a room boundary.
- The same selection routine drives both the highlight and the action, so this
  is not only a visual defect: `F` is dispatched to the wrong object.
- The HUD independently repeats the same ranking rule, so its prompt agrees
  with the wrong selection rather than helping the player diagnose it.

Suggested severity: **Medium**. The issue blocks the intended interaction until
the player repositions, but does not permanently prevent progress.

## Investigation and root cause

`SelectionManager._nearest_interactable()` does not account for facing or the
player-to-object direction. It ranks every in-range interactable by priority
first and distance second. Doors explicitly return priority `-10`; ordinary
interactables without `interact_priority()` receive priority `0`. Consequently,
any eligible junk pile wins over any eligible door regardless of which side of
the player it is on or how much closer the door is.

The relevant values are:

| Interactable | Eligibility | Effective priority |
| --- | --- | ---: |
| Door | Player within 34 px and door is not forced/sealed | -10 |
| `ScrapNode` | Player overlaps its 30 px range and it has tokens | 0 (default) |

Once the pile wins, the manager uses that same target for the highlight and for
input dispatch. Because a `ScrapNode` implements `hold_interact()`, holding `F`
harvests the pile. `HUD._interaction_prompt()` duplicates the priority-then-
distance selection algorithm, producing the pile prompt as well.

The low door priority was introduced deliberately so a pickup located in a
doorway can be collected instead of being hidden behind the door selection. The
existing `doorpickup_test` codifies that all higher-priority pickups must beat a
closer door. That broad rule also covers unrelated piles behind the player,
which is the unintended side effect reported here.

## Fix considerations

A fix should preserve the doorway-pickup escape case without making doors lose
globally to every other in-range object. Possible approaches include:

1. Prefer targets in a forward-facing cone, then rank by interaction priority
   and distance within that cone.
2. Apply the door penalty only when the competing pickup actually overlaps (or
   is sufficiently close to) the doorway.
3. Introduce a shared target-ranking helper with an explicit contextual rule
   for doorway obstructions, rather than a permanent type-wide door penalty.

The selection manager and HUD should consume the same helper so the prompt,
highlight, and interaction action cannot diverge as their rules evolve.

## Acceptance criteria

- With a door in front and a junk pile behind, both in range, the door receives
  the highlight and pressing `F` opens it.
- A collectible positioned in or immediately on a doorway can still be selected
  and removed, preserving the behavior covered by `doorpickup_test`.
- When two eligible targets are on the same side and have the same contextual
  priority, the nearer target wins.
- The HUD prompt always describes the exact object highlighted and activated by
  `SelectionManager`.
- Automated coverage includes the front-door/behind-pile geometry as well as the
  existing pickup-in-doorway geometry.

## Validation note

The `doorpickup_test` regression scene now covers both sides of the rule: a door
in front beats junk behind the player, while a pickup in front can still beat a
nearby door so an obstructed doorway can be cleared.
