class_name ScrapNode
extends InteractableObject
## A harvestable scrap pile — the input end of the loop. Interacting (F) opens the
## scrapping MINIGAME (see docs/INVENTORY_FACTORY_DIRECTION.md): 4 slots of junk, a
## pool of 1–8 "tokens", and optional rusted / loose modifiers. The minigame UI
## (ScrapMinigame) drives it via hit_slot(); harvested items land in the scrapper
## arm's holding cells in the inventory-factory. Solid + grid-locked.

const SLOT_COUNT := 4

var tokens := 5
var loose := false
var slots: Array = []      # SLOT_COUNT entries: a resource id, or "" if empty
var rust: Array = []       # SLOT_COUNT ints: hits still needed to expose (0 = open)
var harvest_label := "scrap"
var node_sprite := "scrap_node"
var node_color := "8a7f6d"

var rng := RandomNumberGenerator.new()
var _pool: Array = []       # weighted junk pool: [{id, weight}, ...]


func _configure() -> void:
	add_to_group("scrap_nodes")
	_sprite_id = node_sprite
	_sprite_color = node_color
	solid_size = Vector2(26, 26)
	interact_radius = 26.0


## Rolls this node's contents from a harvest node definition (see area.json
## harvest.nodes[]). Call before adding to the tree so sprite/colour apply.
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
	loose = rng.randf() < float(def.get("loose_chance", 0.0))
	var rust_chance := float(def.get("rust_chance", 0.0))
	var rust_min := int(def.get("rust_min", 1))
	var rust_max := int(def.get("rust_max", 3))
	slots.clear()
	rust.clear()
	for _i in SLOT_COUNT:
		slots.append(_roll_item())
		rust.append(rng.randi_range(rust_min, rust_max) if rng.randf() < rust_chance else 0)


func can_interact() -> bool:
	return _in_range and tokens > 0


func interaction_prompt() -> String:
	return "[F] Scrap %s  (%d tokens)" % [harvest_label, tokens]


func interact() -> void:
	if tokens <= 0:
		return
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_scrap_minigame"):
			hud.open_scrap_minigame(self)
			return


## Slot states for the UI: {"rust":int, "id":String} (id "" = empty).
func slot_state(index: int) -> Dictionary:
	if index < 0 or index >= SLOT_COUNT:
		return {}
	return {"rust": int(rust[index]), "id": String(slots[index])}


## Acts on a slot (spends one token per resolved decision). Returns a short result
## code the UI can message: "rust" (cracked rust), "empty" (nothing there, no cost),
## "arm_full" (no room, no cost), "spent" (out of tokens), or a resource id (taken).
func hit_slot(index: int) -> String:
	if tokens <= 0:
		return "spent"
	if index < 0 or index >= SLOT_COUNT:
		return "empty"

	if int(rust[index]) > 0:
		tokens -= 1
		rust[index] = int(rust[index]) - 1
		_after_action()
		return "rust"

	var id := String(slots[index])
	if id == "":
		return "empty"  # exposed but already taken; don't waste a token

	if RunState.factory == null or not RunState.factory.deposit_harvest(id):
		return "arm_full"  # no holding space; don't spend the token

	tokens -= 1
	slots[index] = ""
	_after_action()
	return id


func is_spent() -> bool:
	return tokens <= 0


# -------------------------------------------------------------- internal ----

func _after_action() -> void:
	# Loose nodes reshuffle their exposed, non-empty slots after every action.
	if loose:
		for i in SLOT_COUNT:
			if int(rust[i]) == 0 and String(slots[i]) != "":
				slots[i] = _roll_item()


func _roll_item() -> String:
	if _pool.is_empty():
		return ""
	var total := 0.0
	for entry: Dictionary in _pool:
		total += float(entry.get("weight", 1))
	var pick := rng.randf() * total
	for entry: Dictionary in _pool:
		pick -= float(entry.get("weight", 1))
		if pick <= 0.0:
			return String(entry.get("id", ""))
	return String(_pool[_pool.size() - 1].get("id", ""))
