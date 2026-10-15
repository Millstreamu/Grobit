extends Node
## Phase 1 — buildable lair stations. The station data loads, the layout persists in MetaState
## (add/remove/round-trip), and a placed LairStation configures itself and routes [F] to the right
## focused panel (asserted via the def's `panel`). The build-mode placement + default seed run on a
## live lair (RunController) and are covered by the full-game boot + screenshots.

var fail := 0


func _ready() -> void:
	# Station data (Phase 4 economy swap: the free production station is the Process Line now).
	_ck(GameData.stations.has("line") and GameData.stations.has("missions"), "stations.json loaded")
	_ck(bool(GameData.stations.get("line", {}).get("free", false)), "the Process Line is free")
	_ck(bool(GameData.stations.get("missions", {}).get("free", false)), "the Mission Board is free")
	_ck(not GameData.stations.get("quarters", {}).get("cost", {}).is_empty(), "Goblin Quarters costs products")
	_ck(String(GameData.stations.get("quarters", {}).get("panel", "")) == "goblins", "Quarters opens the goblins section")
	_ck(String(GameData.stations.get("missions", {}).get("panel", "")) == "missions", "Mission Board opens the missions section")

	# MetaState layout: add / remove / query.
	MetaState.lair_stations = []
	_ck(not MetaState.has_lair_stations(), "a fresh lair has no stations")
	MetaState.add_lair_station("line", 5, 7)
	MetaState.add_lair_station("missions", 8, 7)
	_ck(MetaState.has_lair_stations() and MetaState.lair_stations.size() == 2, "two stations recorded")
	_ck(MetaState.remove_lair_station_at(5, 7), "removing a station at its tile reports success")
	_ck(MetaState.lair_stations.size() == 1, "one station left after the remove")
	_ck(not MetaState.remove_lair_station_at(99, 99), "removing an empty tile is a no-op")

	# Persistence round-trip through the save file.
	MetaState.save_game()
	MetaState.lair_stations = []
	MetaState.load_game()
	_ck(MetaState.lair_stations.size() == 1 and String(MetaState.lair_stations[0].get("type", "")) == "missions", "the layout round-trips through save/load")

	# A placed LairStation configures itself and names its station.
	var st := LairStation.new()
	st.station_type = "line"
	add_child(st)
	_ck(st.is_in_group("lair_stations"), "a placed station joins the lair_stations group")
	_ck("Process Line" in st.interaction_prompt(), "its [F] prompt names the station")
	st.free()

	MetaState.lair_stations = []   # leave the (restored) save clean
	MetaState.save_game()

	if fail == 0:
		print("LAIR_STATIONS_TEST: ALL PASS")
	else:
		printerr("LAIR_STATIONS_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
