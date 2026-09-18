class_name RepairStation
extends InteractableObject
## Broken equipment repaired for a resource cost, granting a run reward: unlock a
## new ability, +max health, or a shoot upgrade. Solid and grid-locked. The reward
## is decided when the area is generated.

var cost: Dictionary = {}
var reward := "max_health"  # "ability" | "max_health" | "aegis_rounds"
var repaired := false


func _configure() -> void:
	add_to_group("repair_stations")
	_sprite_id = "repair_station"
	_sprite_color = "c0563a"
	solid_size = Vector2(30, 30)
	interact_radius = 30.0


func can_interact() -> bool:
	return _in_range and not repaired


func interaction_prompt() -> String:
	if repaired:
		return "Equipment repaired"
	return "[F] Repair (%s) — reward: %s" % [_cost_text(), _reward_label()]


func interact() -> void:
	if repaired:
		return
	if not RunState.can_afford(cost):
		_notify("Need %s to repair." % _cost_text())
		return
	RunState.spend(cost)
	repaired = true
	_sprite.modulate = Color(0.5, 1.0, 0.5)
	_grant_reward()


func _grant_reward() -> void:
	var player := get_tree().get_first_node_in_group("player") as GrobitPlayer
	match reward:
		"aegis_rounds":
			if player != null and player.combat != null:
				player.combat.enable_aegis()
			_notify("Repaired: Aegis Rounds — a 1s shield every 3 shots.")
		"ability":
			var ability_id := RunState.first_locked_ability()
			if ability_id.is_empty():
				_grant_max_health(player)
				return
			RunState.unlock_ability(ability_id)
			_notify("Repaired: unlocked %s! Choose your ability." % String(GameData.abilities[ability_id].get("name", ability_id)))
			for hud: Node in get_tree().get_nodes_in_group("hud"):
				if hud.has_method("open_ability_choice"):
					hud.open_ability_choice()
		_:
			_grant_max_health(player)


func _grant_max_health(player: GrobitPlayer) -> void:
	if player != null:
		player.increase_max_health(5)
	_notify("Repaired: +5 max health.")


func _reward_label() -> String:
	match reward:
		"ability": return "unlock ability"
		"aegis_rounds": return "Aegis Rounds"
		_: return "+5 max HP"


func _cost_text() -> String:
	var parts: Array = []
	for res: String in cost:
		parts.append("%d %s" % [int(cost[res]), GameData.resource_name(res)])
	return ", ".join(parts)
