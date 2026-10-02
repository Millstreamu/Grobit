extends Node
## Regression coverage for generated-prop tile reservations and claims.
## Run: godot --headless --path . res://scenes/test/door_clearance_test.tscn


func _ready() -> void:
	var failures := 0
	var room := Room.new()
	room.rng.seed = 1234
	room.interior_tiles.assign([
		Vector2(16, 16),
		Vector2(48, 16),
		Vector2(80, 16),
	])
	room.reserve_navigation_tile(Vector2(16, 16))

	failures += _check(room.is_navigation_reserved(Vector2(16, 16)), "door landing is navigation-reserved")
	var first: Variant = room.claim_nearest_prop_tile(Vector2(16, 16))
	failures += _check(first == Vector2(48, 16), "nearest claim skips the reserved door landing")
	var second: Variant = room.claim_nearest_prop_tile(Vector2(48, 16))
	failures += _check(second == Vector2(80, 16), "a second prop cannot overlap the first claim")
	var exhausted: Variant = room.claim_random_prop_tile()
	failures += _check(exhausted == null, "an exhausted room fails instead of using an unsafe fallback")

	var generator := AreaGenerator.new()
	generator.rooms.append(room)
	failures += _check(generator.is_navigation_reserved(Vector2(16, 16)), "generator exposes reservations to build mode")
	failures += _check(not generator.is_navigation_reserved(Vector2(48, 16)), "ordinary claimed tiles are not navigation reservations")

	if failures == 0:
		print("DOOR_CLEARANCE_TEST: ALL PASS")
	else:
		printerr("DOOR_CLEARANCE_TEST: %d FAILURE(S)" % failures)
	generator.rooms.clear()
	generator.free()
	room.free()
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
