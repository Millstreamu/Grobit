class_name LightingSystem
extends Node2D
## Tier-2 darkness + vision. Darkens the whole world canvas with a CanvasModulate,
## then reveals it only where light falls: a shadow-casting cone in front of Grobit
## (plus a faint ambient glow so point-blank isn't pitch black), and static lamps
## placed at lit objects. Walls carry LightOccluder2D (see AreaGenerator._add_wall)
## so light stops at walls and casts real shadows.
##
## Toggle off for debugging with GROBIT_LIGHTS_OFF=1.

## World darkness — the ambient floor everything sits at outside of light. Kept high
## enough that walls and doors stay faintly readable (so you can see the room shape
## and where the exits are), but low enough that the cone/lamps clearly dominate.
const DARK := Color(0.24, 0.255, 0.315)

## Flat tint applied to floor tiles (see AreaGenerator._add_floor). Darkening the
## open floor makes the walls read as the brighter structure in ambient light, so
## room outlines and door gaps stand out for navigation.
const FLOOR_TINT := Color(0.5, 0.5, 0.55)

## Cone reach in pixels (texture height). ~300px ≈ 9 tiles of forward vision.
const CONE_W := 256
const CONE_H := 300
const CONE_HALF_ANGLE_DEG := 34.0

## Radius (px) of the always-on glow around Grobit so nearby danger is readable.
const AMBIENT_RADIUS := 84

var _canvas_modulate: CanvasModulate
var _cone_texture: Texture2D
var _ambient_texture: Texture2D
var _lamp_texture: Texture2D
var _enabled := true


func _ready() -> void:
	add_to_group("lighting_system")  # so world buildables (Power Relay) can find us
	_enabled = not OS.has_environment("GROBIT_LIGHTS_OFF")
	if not _enabled:
		return
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.color = DARK
	add_child(_canvas_modulate)


## Gives Grobit a forward vision cone (auto-aligned to its facing, since it's a
## child of the rotating body) and a faint radial glow. Both cast shadows.
func attach_player(player: Node2D) -> void:
	if not _enabled or player == null:
		return
	if _cone_texture == null:
		_cone_texture = _make_cone_texture()
	if _ambient_texture == null:
		_ambient_texture = _make_radial_texture(256)

	# Grobit's sprite is drawn facing UP (-Y); the cone texture also points up, so as
	# a child of the body it swings to wherever Grobit faces with no per-frame code.
	var cone := PointLight2D.new()
	cone.name = "VisionCone"
	cone.texture = _cone_texture
	cone.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	cone.energy = 1.15
	# Apex sits at the bottom-centre of the texture; shift it up so the apex is on
	# Grobit rather than the texture's centre.
	cone.offset = Vector2(0, -CONE_H * 0.5)
	cone.shadow_enabled = true
	cone.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	cone.shadow_filter_smooth = 2.0
	player.add_child(cone)

	var glow := PointLight2D.new()
	glow.name = "VisionGlow"
	glow.texture = _ambient_texture
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.energy = 0.9
	glow.texture_scale = float(AMBIENT_RADIUS * 2) / 256.0
	glow.shadow_enabled = true
	glow.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	player.add_child(glow)


## Lights a whole room: drops shadow-casting lamps spread across the given floor-tile
## centres (thinned so they don't pile up), so the room reads as fully lit while walls
## still contain the glow. Used by the Power Relay buildable.
func light_room(tiles: Array, tint := Color(1.0, 0.96, 0.85)) -> void:
	if not _enabled:
		return
	var placed: Array = []
	for t: Vector2 in tiles:
		var crowded := false
		for p: Vector2 in placed:
			if p.distance_to(t) < 96.0:  # ~3 tiles apart keeps the lamp count down
				crowded = true
				break
		if crowded:
			continue
		add_lamp(t, 135.0, 1.05, tint)  # radius > spacing so coverage still overlaps
		placed.append(t)


## Places a static lamp at a world position (e.g. a lit station or safe room).
func add_lamp(world_position: Vector2, radius := 120.0, energy := 1.1, tint := Color(1.0, 0.92, 0.78)) -> void:
	if not _enabled:
		return
	if _lamp_texture == null:
		_lamp_texture = _make_radial_texture(256)
	var lamp := PointLight2D.new()
	lamp.texture = _lamp_texture
	lamp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	lamp.color = tint
	lamp.energy = energy
	lamp.texture_scale = (radius * 2.0) / 256.0
	lamp.shadow_enabled = true
	lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	lamp.global_position = world_position
	add_child(lamp)


# ------------------------------------------------------------- textures ----

## A wedge of light: apex at the bottom-centre, opening straight up (-Y), with both
## radial (distance) and angular (edge) falloff for a soft flashlight look.
static func _make_cone_texture() -> ImageTexture:
	var img := Image.create(CONE_W, CONE_H, false, Image.FORMAT_RGBA8)
	var apex := Vector2(CONE_W * 0.5, CONE_H - 1)
	var half_angle := deg_to_rad(CONE_HALF_ANGLE_DEG)
	var max_dist := float(CONE_H)
	for y in CONE_H:
		for x in CONE_W:
			var v := Vector2(x, y) - apex
			var dist := v.length()
			var ang := absf(v.angle_to(Vector2.UP))
			var a := 0.0
			if dist <= max_dist and ang <= half_angle:
				var radial: float = pow(clampf(1.0 - dist / max_dist, 0.0, 1.0), 1.5)
				var angular := smoothstep(0.0, 1.0, clampf(1.0 - ang / half_angle, 0.0, 1.0))
				a = radial * angular
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## A soft round falloff, white centre to transparent edge.
static func _make_radial_texture(size: int) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size
	tex.height = size
	return tex
