extends Node
## Phase 4 economy swap (4B) — chains can now produce the WHOLE economy: 4 base products (currency),
## 4 ammo (one per weapon family), 4 components (lair-need items). Verifies every role product resolves
## from some scrap + verb sequence, each (scrap, sequence) is unique, and the family ammo comes from the
## family's scrap. Resource ids are reused (defined in resources.json) so weapons/needs don't change.

const BASE := ["steel_plate", "copper_sheet", "plastic_casing", "ceramic_tile"]
const AMMO := ["charge_cells", "steel_slugs", "resin_capsules", "ceramic_charges"]
const COMPONENTS := ["reinforced_frame", "power_coupling", "control_assembly", "thermal_core"]

var fail := 0


func _ready() -> void:
	# Every role product is produced by some recipe, and resolves via GameData.process_product.
	for product: String in (BASE + AMMO + COMPONENTS):
		var r := _recipe_for(product)
		_ck(not r.is_empty(), "a chain makes %s" % product)
		if not r.is_empty():
			_ck(GameData.process_product(String(r.get("scrap", "")), r.get("sequence", [])) == product, "%s resolves from its scrap + sequence" % product)
		_ck(GameData.resources.has(product), "%s is a defined resource" % product)

	# Base products are starter-known; ammo + components are discoverable (teach the book).
	for p: String in BASE:
		_ck(MetaState.is_recipe_known(p), "%s is starter-known" % p)

	# No two recipes share the same (scrap, sequence).
	var seen: Dictionary = {}
	var dupes := 0
	for r: Dictionary in GameData.process_recipes:
		var key := "%s|%s" % [String(r.get("scrap", "")), ",".join(r.get("sequence", []))]
		if seen.has(key):
			dupes += 1
		seen[key] = true
	_ck(dupes == 0, "no duplicate (scrap, sequence) recipe keys")

	# Each weapon family's ammo is made from THAT family's scrap.
	for fam: String in GameData.families:
		var ammo := String(GameData.families[fam].get("ammo", ""))
		var r := _recipe_for(ammo)
		_ck(not r.is_empty() and String(r.get("scrap", "")) == fam + "_scrap", "%s ammo (%s) is chained from %s_scrap" % [fam, ammo, fam])

	if fail == 0:
		print("PROCESS_RECIPES_TEST: ALL PASS")
	else:
		printerr("PROCESS_RECIPES_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _recipe_for(product: String) -> Dictionary:
	for r: Dictionary in GameData.process_recipes:
		if String(r.get("product", "")) == product:
			return r
	return {}


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
