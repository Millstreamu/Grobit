class_name ScrapNode
extends InteractableObject
## A harvestable scrap pile. HOLD [F] while next to it: a progress bar fills, and each
## time it completes you pull one piece of Junk into the Scrapper Arm's holding cells.
## The pile has `tokens` charges (one per Junk) and is removed when emptied. Solid +
## grid-locked. (The old slot/rust minigame has been retired.)

## Seconds of holding to pull one piece of junk.
const HARVEST_SECONDS := 0.8

var tokens := 6
var harvest_label := "scrap"
var node_sprite := "scrap_node"
var node_color := "8a7f6d"

var rng := RandomNumberGenerator.new()
var _pool: Array = []       # weighted item pool (now just junk); defaults to "junk"
var _progress := 0.0


func _configure() -> void:
	add_to_group("scrap_nodes")
	_sprite_id = node_sprite
	_sprite_color = node_color
	solid_size = Vector2(26, 26)
	interact_radius = 30.0


## Rolls this node's contents from a harvest node definition (see area.json harvest).
func generate(def: Dictionary, seed_rng: RandomNumberGenerator = null) -> void:
	if seed_rng != null:
		rng.seed = seed_rng.randi()
	else:
		rng.randomize()
	harvest_label = String(def.get("label", "scrap"))
	node_sprite = String(def.get("sprite", "scrap_node"))
	node_color = String(def.get("color", "8a7f6d"))
	_pool = def.get("pool", [])
	tokens = rng.randi_range(int(def.get("tokens_min", 3)), int(def.get("tokens_max", 8)))


func can_interact() -> bool:
	return _in_range and tokens > 0


func is_spent() -> bool:
	return tokens <= 0


func interaction_prompt() -> String:
	return "Hold [F] to scrap %s  (%d left)" % [harvest_label, tokens]


## Driven by SelectionManager while [F] is held and this is the selected pile. Fills a
## progress bar; each completion deposits one item (typed scrap → the Scrapper Arm bar,
## general junk → the factory grid), until the pile is dry.
func hold_interact(delta: float) -> void:
	if tokens <= 0:
		return
	_progress += delta
	if _progress >= HARVEST_SECONDS:
		# Only consume a charge once the item actually lands; otherwise hold at full and
		# retry (the arm slot or the grid is full).
		if _deposit(_roll_item()):
			_progress = 0.0
			tokens -= 1
			if tokens <= 0:
				queue_free()
		else:
			_progress = HARVEST_SECONDS
			_notify("Full — can't take more of that scrap.")
	queue_redraw()


## Routes a harvested item to its home: the four scrap types stack in the Scrapper Arm
## bar; anything else (general junk) goes into the factory grid as before.
func _deposit(item: String) -> bool:
	if RunState.ARM_SCRAP_TYPES.has(item):
		return RunState.arm_add(item, 1) > 0
	if item in RunState.BAR_CURRENCIES:
		return RunState.add(item, 1) > 0  # junk → top-bar currency (no grid cell needed)
	if RunState.factory == null or not RunState.has_space():
		return false
	return RunState.add(item, 1) > 0


## Releasing [F] resets the in-progress fill (each piece needs a continuous hold).
func hold_release() -> void:
	if _progress != 0.0:
		_progress = 0.0
		queue_redraw()


func _draw() -> void:
	if _progress <= 0.0 or tokens <= 0:
		return
	var w := 26.0
	var h := 5.0
	var top := Vector2(-w * 0.5, -solid_size.y * 0.5 - 11.0)
	draw_rect(Rect2(top, Vector2(w, h)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(top, Vector2(w * clampf(_progress / HARVEST_SECONDS, 0.0, 1.0), h)), Color(0.55, 0.9, 0.55))
	draw_rect(Rect2(top, Vector2(w, h)), Color(0.8, 0.9, 0.8, 0.5), false, 1.0)


func _roll_item() -> String:
	if _pool.is_empty():
		return "junk"
	var total := 0.0
	for entry: Dictionary in _pool:
		total += float(entry.get("weight", 1))
	var pick := rng.randf() * total
	for entry: Dictionary in _pool:
		pick -= float(entry.get("weight", 1))
		if pick <= 0.0:
			return String(entry.get("id", "junk"))
	return String(_pool[_pool.size() - 1].get("id", "junk"))


func _notify(text: String) -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("log_message"):
			hud.log_message(text)
			return
