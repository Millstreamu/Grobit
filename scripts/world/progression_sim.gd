extends Node
## Progression simulation (no UI). Drives the REAL systems — arm tier-gating (deposit_harvest/
## arm_accepts), recipe data (GameData), repair costs (AreaGenerator._repair_cost_for), the arm
## upgrade gate (MetaState) and lair-need delivery — across a series of runs, and prints the
## climb so you can see the player work up through the machines and tiers over time.
##
## Run: godot --headless --path . res://scenes/test/progression_sim.tscn
## (Writes the save — the runner backs it up.)

const TIER_MAT := ["steel", "copper", "plastic", "ceramic"]
const TIER_SCRAP := ["steel_scrap", "copper_scrap", "plastic_scrap", "ceramic_scrap"]
const RECYCLER := {"steel": "steel_recycler", "copper": "copper_recycler", "plastic": "plastic_recycler", "ceramic": "ceramic_recycler"}
## Which bridge component each arm level needs (mirrors TerminalPanel.ARM_GATE_COMPONENT).
const BRIDGE := {2: "reinforced_frame", 3: "power_coupling", 4: "thermal_core"}
## Which component fills which lair need (mirrors MetaState.NEED_COMPONENT).
const NEED_COMPONENT := {"reinforced_frame": "oxygen", "power_coupling": "power", "control_assembly": "water", "thermal_core": "food"}

const HARVEST_PER_TIER := 8    # scrap you can gather of each UNLOCKED tier, per run
const TD_PER_RUN := 4          # Tech Data earned per run (scrapping spare/duplicate machines)
## A run's realistic NET output toward the goal — the design intent is "bring back one progress
## thing per run": either an arm tier unlock, or one component delivered to a lair need.
const DELIVER_PER_RUN := 1
## Machines are SCARCE: a Component Maker (needed to craft a bridge/need component) is a lucky
## find. You can't climb a tier or fill a need until you've FOUND its maker — this is what makes
## the early game slow. Chance per run to find one more (random) component maker.
const CM_FIND_CHANCE := 0.4
const COMPONENT_MAKERS := ["frame_maker", "coupling_maker", "thermal_maker", "control_maker"]
const MAX_RUNS := 120

var _cm_owned := {}
var _rng := RandomNumberGenerator.new()

var _gen: AreaGenerator
var fail := 0


func _ready() -> void:
	_gen = AreaGenerator.new()
	add_child(_gen)
	_rng.seed = 20260205  # fixed so the simulated finds are reproducible
	# Clean slate: arm L1 (steel only), nothing banked, lair empty.
	MetaState.machine_levels = {}
	MetaState.tech_data = 0
	MetaState.lair_needs = {}
	MetaState.beacon_sent = false
	MetaState.machine_instances = []
	RunState.begin_run(GameData.first_area_id(), 1)

	print("\n==================  GROBIT — PROGRESSION SIMULATION  ==================")
	print("Start: Scrapper Arm Lv1 (steel only).  Goal: fill all 4 lair needs → beacon.")
	print("Machines are scarce: you can't climb a tier until you FIND its component maker.")
	print("Each run: harvest unlocked tiers, earn Tech Data, and bring back ONE progress thing.\n")

	var run := 0
	while not MetaState.beacon_sent and run < MAX_RUNS:
		run += 1
		_simulate_run(run)

	print("\n----------------------------------------------------------------------")
	if MetaState.beacon_sent:
		print("OUTCOME: RESCUED in %d runs — the lair is whole, the distress beacon is away." % run)
	else:
		print("OUTCOME: not rescued within %d runs (needs: %s)." % [MAX_RUNS, _needs_str()])
	print("Final: Arm Lv%d (%s).  Machines in storage: %d." % [_arm_lvl(), _tier_name(_arm_lvl()), RunState.instance_count()])
	print("======================================================================\n")

	if fail == 0 and MetaState.beacon_sent:
		print("PROGRESSION_SIM: ALL PASS")
	else:
		printerr("PROGRESSION_SIM: %d check failure(s), rescued=%s" % [fail, MetaState.beacon_sent])
	MetaState.machine_levels = {}
	MetaState.lair_needs = {}
	MetaState.beacon_sent = false
	get_tree().quit(fail if not MetaState.beacon_sent else 0)


func _simulate_run(run: int) -> void:
	var lvl := _arm_lvl()
	var log_bits: Array = []

	# --- 1) Harvest (real arm, proving the tier gate) ---
	var arm := FactoryGrid.new(6, 4)
	arm.place_scrapper_arm(Vector2i(0, 0))
	var mats := {}
	var harvested: Array = []
	for t in lvl:  # tiers 1..lvl are unlocked
		var scrap: String = TIER_SCRAP[t]
		var got := 0
		for _i in HARVEST_PER_TIER:
			if arm.deposit_harvest(scrap):
				got += 1
		_ck(got == HARVEST_PER_TIER, "run %d: harvested %s (tier %d is unlocked)" % [run, scrap, t + 1])
		mats[TIER_MAT[t]] = got  # recyclers convert scrap → material 1:1 (see recipes.json)
		harvested.append("%d %s" % [got, TIER_MAT[t]])
	# The next tier must be LOCKED.
	if lvl < 4:
		_ck(not arm.deposit_harvest(TIER_SCRAP[lvl]), "run %d: next tier (%s) is still locked" % [run, TIER_SCRAP[lvl]])
	log_bits.append("harvest+recycle → " + ", ".join(harvested))

	# --- 2) Earn Tech Data (scrapping junk) ---
	MetaState.tech_data += TD_PER_RUN

	# --- 2b) Scarce machines: maybe find a Component Maker this run (gates crafting components) ---
	if _cm_owned.size() < COMPONENT_MAKERS.size() and _rng.randf() < CM_FIND_CHANCE:
		var missing: Array = []
		for m: String in COMPONENT_MAKERS:
			if not _cm_owned.has(m):
				missing.append(m)
		var found: String = missing[_rng.randi_range(0, missing.size() - 1)]
		_cm_owned[found] = true
		log_bits.append("found & repaired a %s → storage" % GameData.machines[found].get("name", found))

	# A run accomplishes ONE main thing: climb a tier, or bring back one progress component.
	var climbed := false

	# --- 3) Climb: need the bridge component's MAKER, then Tech Data + the component ---
	if lvl < 4:
		var comp: String = BRIDGE[lvl + 1]
		var td_cost := MetaState.machine_upgrade_cost("scrapper_arm")
		if not _cm_owned.has(_maker_for(comp)):
			log_bits.append("stuck at %s tier — need to find a %s to make a %s" % [_tier_name(lvl).to_upper(), _maker_name(comp), _short(comp)])
		elif MetaState.tech_data >= td_cost and _craft(comp, mats):
			MetaState.upgrade_machine("scrapper_arm")  # spends the Tech Data; +1 level
			log_bits.append("TERMINAL: Arm Lv%d→Lv%d  (−1 %s, −%d TD)  ✦ %s UNLOCKED" % [lvl, lvl + 1, _short(comp), td_cost, _tier_name(lvl + 1).to_upper()])
			climbed = true
		elif MetaState.tech_data < td_cost:
			log_bits.append("scrounging for the arm upgrade (Tech Data %d/%d)" % [MetaState.tech_data, td_cost])

	# --- 4) Repair a machine of the next tier (shows escalating repair cost) ---
	var target_tier := mini(lvl + 1, 4)
	var rec_id: String = RECYCLER[TIER_MAT[target_tier - 1]]
	var rcost := _gen._repair_cost_for("Recycler", rec_id)
	if _afford(rcost, mats):
		_spend(rcost, mats)
		RunState.add_machine_instance(rec_id)
		log_bits.append("repaired a %s (cost %s) → storage" % [GameData.machines[rec_id].get("name", rec_id), _cost_str(rcost)])

	# --- 5) Bring back one progress component for a lair need (if we didn't climb this run) ---
	if not climbed:
		var delivered := {}
		var count := 0
		for comp_id: String in NEED_COMPONENT:
			var need: String = NEED_COMPONENT[comp_id]
			while count < DELIVER_PER_RUN and _cm_owned.has(_maker_for(comp_id)) and MetaState.need_amount(need) < MetaState.NEED_MAX and _craft(comp_id, mats):
				if MetaState.deliver_to_needs({comp_id: 1}).is_empty():
					break
				delivered[need] = int(delivered.get(need, 0)) + 1
				count += 1
		if not delivered.is_empty():
			var parts: Array = []
			for need: String in delivered:
				parts.append("%s +%d (%d/%d)" % [need, delivered[need], MetaState.need_amount(need), MetaState.NEED_MAX])
			log_bits.append("LAIR haul: " + ", ".join(parts))

	# --- Win check ---
	if MetaState.lair_restored() and not MetaState.beacon_sent:
		MetaState.send_beacon()
		log_bits.append("*** ALL NEEDS MET — DISTRESS BEACON SENT ***")

	print("RUN %2d  [%s]  TD %d   Lair %s" % [run, _tier_name(_arm_lvl()).to_upper(), MetaState.tech_data, _needs_str()])
	for b: String in log_bits:
		print("        • %s" % b)


# --------------------------------------------------------------- helpers ----

## Crafts one `component` if `mats` holds its recipe needs (reads GameData so it matches the real
## machines). Deducts the materials. Returns success.
func _craft(component: String, mats: Dictionary) -> bool:
	var maker := _maker_for(component)
	var recipes := GameData.recipes_for(maker)
	if recipes.is_empty():
		return false
	var needs: Dictionary = recipes[0].get("needs", {})
	if not _afford(needs, mats):
		return false
	_spend(needs, mats)
	return true


func _maker_for(component: String) -> String:
	match component:
		"reinforced_frame": return "frame_maker"
		"power_coupling": return "coupling_maker"
		"control_assembly": return "control_maker"
		"thermal_core": return "thermal_maker"
	return ""


func _maker_name(component: String) -> String:
	return String(GameData.machines.get(_maker_for(component), {}).get("name", _maker_for(component)))


func _afford(cost: Dictionary, mats: Dictionary) -> bool:
	for id: String in cost:
		if int(mats.get(id, 0)) < int(cost[id]):
			return false
	return true


func _spend(cost: Dictionary, mats: Dictionary) -> void:
	for id: String in cost:
		mats[id] = int(mats.get(id, 0)) - int(cost[id])


func _arm_lvl() -> int:
	return int(MetaState.machine_level("scrapper_arm"))


func _tier_name(lvl: int) -> String:
	return TIER_MAT[clampi(lvl - 1, 0, 3)]


func _short(id: String) -> String:
	return String(id).trim_suffix("_scrap").capitalize().replace("_", " ")


func _cost_str(cost: Dictionary) -> String:
	var parts: Array = []
	for id: String in cost:
		parts.append("%d %s" % [int(cost[id]), id])
	return ", ".join(parts)


func _needs_str() -> String:
	var parts: Array = []
	for need: String in MetaState.LAIR_NEEDS:
		parts.append("%s%d/%d" % [need.substr(0, 1).to_upper(), MetaState.need_amount(need), MetaState.NEED_MAX])
	return " ".join(parts)


func _ck(condition: bool, label: String) -> void:
	if not condition:
		fail += 1
		printerr("  FAIL - ", label)
