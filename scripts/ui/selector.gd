class_name Selector
extends Node2D
## Reusable world-space highlight bracket built from the `selection_16/32/64`
## atlas sprites. Give it a position and a target size in pixels and it picks the
## smallest bracket that fits. Designed to be pooled/reused: one instance can be
## moved around and shown/hidden every frame.
##
## This is the shared primitive for "what is selected/targeted" visuals. Current
## users: aim target, in-range interactables, and the build placement tile. Future
## UI (target picker, inventory slot, build menu) can reuse the same instance or
## the same `selection_*` sprites directly.

const SIZES := [16, 32, 64]

@export var pulse := true
@export var color := Color(1, 0.95, 0.4)

var _sprite: Sprite2D
var _time := 0.0
var _current_size := 0


func _ready() -> void:
	z_index = 6
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_apply_size(16)
	_sprite.modulate = color


func _process(delta: float) -> void:
	if not pulse or not visible:
		return
	_time += delta
	_sprite.modulate = Color(color.r, color.g, color.b, 0.6 + 0.4 * sin(_time * 6.0))


## Show the bracket at a world position, sized to fit `size_px`.
func highlight(world_position: Vector2, size_px := 32) -> void:
	visible = true
	global_position = world_position
	_apply_size(size_px)


func clear() -> void:
	visible = false


func set_color(new_color: Color) -> void:
	color = new_color
	if not pulse:
		_sprite.modulate = color


func _apply_size(size_px: int) -> void:
	var chosen: int = SIZES[SIZES.size() - 1]
	for s: int in SIZES:
		if size_px <= s:
			chosen = s
			break
	if chosen == _current_size:
		return
	_current_size = chosen
	_sprite.texture = ContentLibrary.get_icon("selection_%d" % chosen, Vector2i(chosen, chosen))
