class_name ScrapNode
extends InteractableObject
## A harvestable scrap pile. The scrapbot itself can't strip it — only deployed GOBLINS do, via
## take_one() (see HarvesterGoblin). The pile has `tokens` charges (one piece each) and is removed
## when emptied. Solid + grid-locked. Not player-interactable.

var tokens := 6
var harvest_label := "scrap"
var node_sprite := "scrap_node"
var node_color := "8a7f6d"

var rng := RandomNumberGenerator.new()
var _pool: Array = []       # weighted item pool of typed scrap; defaults to "copper_scrap"


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


## The scrapbot can't harvest — only goblins can. Never offer this to the player's [F].
func can_interact() -> bool:
	return false


func is_spent() -> bool:
	return tokens <= 0


## The pile's main scrap type (its first pool entry), for the tier check.
func _primary_scrap() -> String:
	return String(_pool[0].get("id", "")) if not _pool.is_empty() else ""


## This pile's scrap tier (1 = steel … 4 = ceramic, 0 if non-scrap). A goblin can only strip it
## if its TOOL's tier is at least this (checked in HarvesterGoblin).
func scrap_tier() -> int:
	return FactoryGrid.scrap_tier(_primary_scrap())


## Kept for callers that ask whether a pile is globally inert. Nothing locks a pile now — what
## can be scrapped is decided per goblin by its tool — so this is always false.
func _is_locked() -> bool:
	return false


## Pulls one piece off the pile and returns its scrap id (a goblin carries it back to the bot).
## Empties and removes the pile when the last token is taken. Returns "" when the pile is dry.
func take_one() -> String:
	if tokens <= 0:
		return ""
	var id := _roll_item()
	tokens -= 1
	if tokens <= 0:
		queue_free()
	return id


func _roll_item() -> String:
	if _pool.is_empty():
		return "copper_scrap"
	var total := 0.0
	for entry: Dictionary in _pool:
		total += float(entry.get("weight", 1))
	var pick := rng.randf() * total
	for entry: Dictionary in _pool:
		pick -= float(entry.get("weight", 1))
		if pick <= 0.0:
			return String(entry.get("id", "copper_scrap"))
	return String(_pool[_pool.size() - 1].get("id", "copper_scrap"))
