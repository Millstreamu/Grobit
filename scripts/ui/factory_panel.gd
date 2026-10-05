class_name FactoryPanel
extends Control
## The inventory-factory window. The grid sits on the LEFT; a context panel on the RIGHT
## shows the part being positioned, or info about whatever the cursor is on.
##
## There is NO build menu. The model is direct:
##   • Machines you acquire (found/exchange/combine) wait in a [G] storage list and are
##     placed from there — drop them [Space], or scrap them [R] for Tech Data when there's
##     no room. (Tech Data buys PERMANENT machine upgrades at the base, not in-run levels.)
##   • [M] lifts a placed machine into your hand to move it; [R] in hand scraps it.
##   • [C] on a machine core marks it; [C] on a second merges both into one random
##     machine (dropped into your hand).
##   • [B] on an empty cell opens a radial to lay transport (conveyor/splitter/filter/cache).
##
## Opening pauses the world; the factory keeps ticking (its processor is ALWAYS).

const PANEL_SIZE := Vector2(640, 448)
const CELL := 36.0
const GAP := 4.0
const GRID_ORIGIN := Vector2(14, 92)  # pushed down to make room for the Scrapper Arm bar
const ARM_BAR_Y := 46.0
const RPANEL_X := 336.0
const RPANEL_W := 296.0
const RPANEL_TOP := 40.0
const ARROWS := {Vector2i(1, 0): "▶", Vector2i(-1, 0): "◀", Vector2i(0, 1): "▼", Vector2i(0, -1): "▲"}

var _cursor := Vector2i.ZERO
var _carried: Dictionary = {}
var _message := ""
var _font: Font

# Transport radial: press [B] on a cell to pick a conveyor/splitter/filter/cache to lay
# there. _radial_cell is the target cell; _radial_index is the highlighted option.
var _radial_mode := false
var _radial_index := 0
var _radial_cell := Vector2i.ZERO
const RADIAL_PARTS := ["__conveyor", "__splitter", "__filter", "storage_cache"]

## Combine groups: two machines of the SAME group merge into a DIFFERENT member of that
## group (never one of the two you used). Only these types can be combined with [C].
const COMBINE_GROUPS := {
	"Recycler": ["copper_recycler", "steel_recycler", "plastic_recycler", "ceramic_recycler"],
	"Ammo Maker": ["copper_ammo_maker", "steel_ammo_maker", "plastic_ammo_maker", "ceramic_ammo_maker"],
	"Component Maker": ["coupling_maker", "control_maker", "frame_maker", "thermal_maker"],
	"Weapon": ["copper_weapon", "steel_weapon", "plastic_weapon", "ceramic_weapon"],
}

# Place flow: a part is "in your hand" and positioned on the grid. Machines arrive here
# from stock (found/exchange/combine) and are dropped [Space] or scrapped [R]; transport
# arrives from the radial.
var _place_mode := false
var _place_id := ""
var _place_dir := Vector2i(1, 0)
## The port layout rolled for the machine currently being built (offsets relative to
## the core). Building is a spatial roll like leveling — each build's in/out cells land
## somewhere random around the core; [R] rerolls (spends a reshuffle). `_place_flash`
## briefly highlights the freshly-rolled layout.
var _place_in_offsets: Array = []
var _place_out_offsets: Array = []
var _place_hold_offsets: Array = []
var _place_body_offsets: Array = []
var _place_rng := RandomNumberGenerator.new()
var _place_flash := 0.0
## Index into RunState.machine_instances of the machine currently in hand (its frozen layout),
## or -1 when placing something that isn't a stored instance (transport). Removed on drop/scrap.
var _place_instance_index := -1

# Leveling is instant and in place (see _begin_level) — no sub-mode needed.

## Move mode: pick a placed machine up and set it back down elsewhere (no level
## change). Like level mode the cursor is the candidate core so the whole machine
## follows it; reuses the same can_relocate / relocation engine.
var _move_mode := false
var _move_mi := -1

## Moving a conveyor/splitter: the lifted transport cell (kind/dir/dir2/item) follows
## the cursor; [R] rotates it, [Space] drops it. `_conv_from` is where it started (for
## cancel).
var _move_conv := false
var _conv_cell: Dictionary = {}
var _conv_from := Vector2i.ZERO

# Module install sub-mode.
var _install_mode := false
var _install_slot := Vector2i.ZERO
var _install_opts: Array = []
var _install_index := 0

## Combine: press [C] on a machine core to mark it, then [C] on a second core to merge
## both into one random machine (which drops into your hand to place). (-1,-1) = nothing
## marked yet. See _combine_at_cursor.
var _combine_a_core := Vector2i(-1, -1)

## Storage list ([G]): a temporary holding list for unplaced machines so you can rearrange
## the grid. You CANNOT close the inventory until it's empty (no long-term storage). Browse
## it with [G]; retrieve one into your hand with [Space]. See _handle_storage_input.
var _storage_mode := false
var _storage_index := 0

# Processing animations: input items slide toward the core as a craft progresses,
# and freshly-produced items pop/slide out of the core into their output cell.
var _prev_res: Dictionary = {}    # pos -> resource id last frame (to spot new items)
var _pops: Array = []             # [{pos, origin, id, t, dur}] active out-slide anims
var _port_info: Dictionary = {}   # pos -> {kind, core, working, progress}, rebuilt each draw
## In/out item slides run at conveyor speed: one cell over FactoryGrid.CONVEYOR_INTERVAL.
const FEED_TIME := 0.35           # input slides fully into the core in this long, then processes
const POP_DUR := 0.35             # output slides one cell out at the same pace


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = PANEL_SIZE
	visible = false
	_font = ThemeDB.fallback_font
	_place_rng.randomize()
	if OS.has_environment("GROBIT_OPEN_FACTORY"):
		_debug_open.call_deferred()


func _debug_open() -> void:
	var f := RunState.factory
	if f != null:
		f.set_cell(Vector2i(1, 0), {"kind": "resource", "id": "scrap_metal"})
		f.set_cell(Vector2i(3, 3), {"kind": "resource", "id": "metal_bar"})
	open()
	var mode := OS.get_environment("GROBIT_OPEN_FACTORY")
	if mode == "place":
		_cursor = Vector2i(4, 4)
		_open_radial()
	elif mode == "flow" and f != null:
		f.place_machine("smelter", Vector2i(3, 0))
		f.set_cell(Vector2i(2, 0), {"kind": "resource", "id": "scrap_metal"})
		_cursor = Vector2i(3, 0)
	elif mode == "level" and f != null:
		f.place_machine("smelter", Vector2i(2, 2))
		_cursor = Vector2i(2, 2)


func is_open() -> bool:
	return visible


## Opens the inventory and begins placing a freshly-acquired machine (rolls it an instance).
func open_place(id: String) -> void:
	open()
	RunState.add_machine_instance(id)
	_begin_place_instance(RunState.machine_instances.size() - 1)


func open() -> void:
	visible = true
	_reset_modes()
	_cursor = Vector2i.ZERO
	_carried = {}
	_message = ""
	_pops.clear()
	_prev_res = _res_snapshot()  # so already-present items don't all pop on open
	get_tree().paused = true
	if _editable() and _has_unplaced():
		_message = "%d machine(s) in storage — [G] to place them (or leave them for a later run)." % _stock_total()
	queue_redraw()


## Machine ids currently in storage (not transport/caches — those lay from the [B] radial —
## and not the free starter arm).
func _stock_total() -> int:
	return RunState.instance_count()


## True while any machine instance is still waiting in storage.
func _has_unplaced() -> bool:
	return RunState.instance_count() > 0


## Enters place-mode ("in hand") for the stored machine instance at `index`, using its FROZEN
## rolled layout (no re-roll — that's what makes duplicates distinct). The instance stays in
## storage until actually dropped, so cancelling just leaves it there. Idle-only.
func _begin_place_instance(index: int) -> bool:
	if _place_mode or _move_mode or _move_conv or _install_mode or _radial_mode or _storage_mode:
		return false
	if index < 0 or index >= RunState.machine_instances.size():
		return false
	var inst: Dictionary = RunState.machine_instances[index]
	_place_instance_index = index
	_place_id = String(inst.get("def_id", ""))
	_place_mode = true
	_cursor = Vector2i(1, 1)
	_place_in_offsets = (inst.get("in_offsets", []) as Array).duplicate()
	_place_out_offsets = (inst.get("out_offsets", []) as Array).duplicate()
	_place_hold_offsets = (inst.get("hold_offsets", []) as Array).duplicate()
	_place_body_offsets = (inst.get("body_offsets", []) as Array).duplicate()
	_message = "Place %s — [Space] drop, [R] scrap, [G]/[Esc] back to storage." % _part_name(_place_id)
	return true


## User-requested close: refused while machines are still in storage (place or scrap them
## all first — there's no long-term storage). Returns true if it actually closed.
func try_close() -> bool:
	# Storage persists across runs (Slice C), so you can leave machines in it — closing and
	# launching are always allowed; place from storage [G] whatever you want to use this run.
	close()
	return true


## Accept the loadout and launch the run: locks the factory and drives the scrapbot out. Only
## valid during setup (in the lair). Anything left in storage is kept for a later run.
func _accept_and_launch() -> void:
	close()
	for controller: Node in get_tree().get_nodes_in_group("run_controller"):
		if controller.has_method("launch_from_setup"):
			controller.launch_from_setup()
			return


func close() -> void:
	visible = false
	_reset_modes()
	_return_carried()  # don't pocket-vanish a held stack on close
	get_tree().paused = false


## Puts any carried stack back into the factory grid (free cells).
func _return_carried() -> void:
	if not _carried.is_empty() and RunState.factory != null:
		RunState.add(String(_carried.get("id", "")), int(_carried.get("count", 1)))
	_carried = {}


func _reset_modes() -> void:
	_combine_a_core = Vector2i(-1, -1)
	_radial_mode = false
	_storage_mode = false
	_place_mode = false
	_move_mode = false
	_move_conv = false
	_install_mode = false
	_place_instance_index = -1


func _process(delta: float) -> void:
	if not visible:
		return
	if _place_flash > 0.0:
		_place_flash = maxf(_place_flash - delta, 0.0)
	_update_pops(delta)
	_handle_input()
	queue_redraw()


# --------------------------------------------------------- animations ----

## Snapshot of every resource cell (pos -> id) — used to spot newly-produced items.
func _res_snapshot() -> Dictionary:
	var out := {}
	var f := RunState.factory
	if f == null:
		return out
	for y in f.rows:
		for x in f.cols:
			var pos := Vector2i(x, y)
			if String(f.get_cell(pos).get("kind", "")) == "resource":
				out[pos] = String(f.get_cell(pos).id)
	return out


## Advances out-slide pops and spawns a new one wherever an item just appeared (from a
## machine's output cell it slides out of that machine's core; elsewhere it just pops).
func _update_pops(delta: float) -> void:
	var f := RunState.factory
	if f == null:
		return
	var kept: Array = []
	for p: Dictionary in _pops:
		p.t += delta
		if p.t < p.dur:
			kept.append(p)
	_pops = kept
	var cur := _res_snapshot()
	for pos: Vector2i in cur:
		if String(_prev_res.get(pos, "")) == "":  # wasn't a resource last frame → new
			_pops.append({"pos": pos, "origin": _output_core_of(f, pos), "id": cur[pos], "t": 0.0, "dur": POP_DUR})
	_prev_res = cur


## The core of the machine whose output cell is `pos`, or `pos` itself (no slide).
func _output_core_of(f: FactoryGrid, pos: Vector2i) -> Vector2i:
	for m: Dictionary in f.machines:
		if bool(m.get("removed", false)):
			continue
		for op: Vector2i in f.output_positions(m):
			if op == pos:
				return Vector2i(m.core)
	return pos


func _pop_for(pos: Vector2i) -> Dictionary:
	for p: Dictionary in _pops:
		if Vector2i(p.pos) == pos:
			return p
	return {}


# --------------------------------------------------------------- input ----

## Editing is allowed only during run SETUP — in the lair, before you commit. Once you Accept
## and drive out (RunState.driving), the factory is locked: you can open it to watch production
## but not rearrange it. (It keeps processing in the field; you just can't edit "as you go".)
func _editable() -> bool:
	return not RunState.driving


func _handle_input() -> void:
	if not _editable():
		# Field: the factory LAYOUT is locked (no building, combining, or lifting machines), but
		# you can still shuffle loose items around the grid — pick up and drop resource stacks.
		if Input.is_action_just_pressed("build_cancel"):
			close()
			return
		_move_cursor()
		if Input.is_action_just_pressed("attack") and RunState.factory != null \
				and String(RunState.factory.get_cell(_cursor).get("kind", "")) != "machine_slot":
			_pick_or_drop()  # machine slots (module installs) stay locked in the field
		return
	if _install_mode:
		if Input.is_action_just_pressed("build_cancel"):
			_install_mode = false
		else:
			_handle_install_input()
		return
	if _move_mode:
		if Input.is_action_just_pressed("build_cancel"):
			_move_mode = false  # cancel: the machine stays where it was
			_message = "Move cancelled."
		else:
			_handle_move_input()
		return
	if _move_conv:
		if Input.is_action_just_pressed("build_cancel"):
			_cancel_move_conv()
		else:
			_handle_move_conv_input()
		return
	if _radial_mode:
		_handle_radial_input()
		return
	if _storage_mode:
		_handle_storage_input()
		return
	if _place_mode:
		_handle_place_input()
		return

	# Normal inventory browsing.
	if Input.is_action_just_pressed("build_cancel"):
		if _combine_a_core != Vector2i(-1, -1):
			_combine_a_core = Vector2i(-1, -1)  # cancel a pending combine selection
			_message = "Combine cancelled."
			return
		try_close()  # refused while machines are still in storage
		return
	_move_cursor()
	if Input.is_action_just_pressed("confirm"):
		_accept_and_launch()
		return
	if Input.is_action_just_pressed("storage"):
		_open_storage()
		return
	if Input.is_action_just_pressed("toggle_build"):
		_open_radial()
		return
	if Input.is_action_just_pressed("combine"):
		_combine_at_cursor()
		return
	if Input.is_action_just_pressed("toggle_manufacture"):
		_begin_move()
		return
	if Input.is_action_just_pressed("reshuffle"):
		_remove_transport_or_hint()
		return
	if Input.is_action_just_pressed("attack"):
		if RunState.factory.get_cell(_cursor).get("kind", "") == "machine_slot":
			_slot_action()
		else:
			_pick_or_drop()


# --- transport radial (press [B] on a cell) ---

func _open_radial() -> void:
	var f := RunState.factory
	var k := String(f.get_cell(_cursor).get("kind", ""))
	if k != "" and k != "resource":
		_message = "Pick an empty cell for transport, then [B]."
		return
	_radial_mode = true
	_radial_index = 0
	_radial_cell = _cursor
	_message = ""


func _handle_radial_input() -> void:
	if Input.is_action_just_pressed("build_cancel") or Input.is_action_just_pressed("toggle_build"):
		_radial_mode = false
		return
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_up"):
		_radial_index = (_radial_index - 1 + RADIAL_PARTS.size()) % RADIAL_PARTS.size()
	if Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("move_down"):
		_radial_index = (_radial_index + 1) % RADIAL_PARTS.size()
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		_pick_radial(String(RADIAL_PARTS[_radial_index]))


## Chooses a transport part from the radial: if you have one in stock it's free, otherwise
## it's free (inserts/transport are free now). Then drops you into positioning at the selected cell.
func _pick_radial(id: String) -> void:
	var from_stock := RunState.stock_count(id) > 0
	if not from_stock and not RunState.can_afford(RunState.part_cost(id)):
		_message = "Need %s (or craft one at a Fabricator)." % _cost_text(RunState.part_cost(id))
		return
	_radial_mode = false
	_place_id = id
	_place_mode = true
	_cursor = _radial_cell
	_roll_place_layout()
	_message = "Place %s — [Space] drop, [R] rotate, [Esc] cancel." % _part_name(id)


# --- storage list (press [G]) ---

func _open_storage() -> void:
	if not _has_unplaced():
		_message = "Storage is empty. [M] to lift a machine, then [G] to stash it."
		return
	_storage_mode = true
	_storage_index = 0
	_message = "Storage — [W/S] pick, [Space] place it, [Esc] back."


func _handle_storage_input() -> void:
	if Input.is_action_just_pressed("build_cancel") or Input.is_action_just_pressed("storage"):
		_storage_mode = false
		return
	var n := RunState.instance_count()
	if n == 0:
		_storage_mode = false
		return
	_storage_index = clampi(_storage_index, 0, n - 1)
	if Input.is_action_just_pressed("move_up"):
		_storage_index = maxi(_storage_index - 1, 0)
	if Input.is_action_just_pressed("move_down"):
		_storage_index = mini(_storage_index + 1, n - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		_storage_mode = false
		_begin_place_instance(_storage_index)  # retrieve this instance (its layout) into hand


# --- combine (press [C] on two machine cores → one random machine in hand) ---

## Marks the machine under the cursor, or — if one of the same type is already marked —
## merges the two into a DIFFERENT member of that type (a recycler → another recycler,
## etc.), dropped into your hand to place.
func _combine_at_cursor() -> void:
	var f := RunState.factory
	var mi := f.machine_at(_cursor)
	if mi < 0:
		_message = "Put the cursor on a machine's core, then [C]."
		return
	var id := String(f.machines[mi].get("def_id", ""))
	var group := _combine_group(id)
	var core := Vector2i(f.machines[mi].core)
	if _combine_a_core == Vector2i(-1, -1):
		if group == "":
			_message = "Only recyclers, ammo makers, component makers and weapons can be combined."
			return
		_combine_a_core = core
		_message = "Combine: %s marked — [C] another %s." % [_part_name(id), group]
		return
	if core == _combine_a_core:
		_combine_a_core = Vector2i(-1, -1)  # same machine → unmark
		_message = "Combine cleared."
		return
	var first_mi := f.machine_at(_combine_a_core)
	if first_mi < 0:
		_combine_a_core = core if group != "" else Vector2i(-1, -1)  # first one's gone
		_message = "Combine: first machine was gone — re-marked." if group != "" else "Combine cleared."
		return
	var a_id := String(f.machines[first_mi].get("def_id", ""))
	# Both must be the same combinable group.
	if group == "" or _combine_group(a_id) != group:
		_message = "Combine needs two of the SAME type (both recyclers, both ammo makers, …)."
		return  # keep the first mark so you can pick a matching partner
	var a_name := _part_name(a_id)
	var b_name := _part_name(id)
	# Remove both machines (any held items re-enter the grid), then mint the result.
	_scrap_cache_contents(first_mi)
	_scrap_cache_contents(mi)
	f.pickup_machine(maxi(first_mi, mi))  # remove the higher index first to keep indices valid
	f.pickup_machine(mini(first_mi, mi))
	_combine_a_core = Vector2i(-1, -1)
	var result := _combine_result(group, a_id, id)
	RunState.add_machine_instance(result)  # the result is a fresh rolled-layout instance
	_message = "Combined %s + %s → %s." % [a_name, b_name, _part_name(result)]
	_begin_place_instance(RunState.machine_instances.size() - 1)  # into your hand to place


## The combine group an id belongs to ("" if it can't be combined).
func _combine_group(id: String) -> String:
	for g: String in COMBINE_GROUPS:
		if id in COMBINE_GROUPS[g]:
			return g
	return ""


## A random member of `group` that is neither input (always exists: 4 members, ≤2 excluded).
func _combine_result(group: String, a_id: String, b_id: String) -> String:
	var pool: Array = []
	for id: String in COMBINE_GROUPS[group]:
		if id != a_id and id != b_id:
			pool.append(id)
	return String(pool[_place_rng.randi_range(0, pool.size() - 1)])


## If a machine is a cache with a stack, spill it back into the grid so combining/scrapping
## it doesn't silently eat the items.
func _scrap_cache_contents(mi: int) -> void:
	var cs := RunState.factory.cache_state(mi)
	if cs.is_empty():
		return
	var count := int(cs.get("count", 0))
	var item := String(cs.get("id", ""))
	for _i in count:
		if item != "":
			RunState.factory.add_resource(item)


# --- positioning a chosen part ---

## Rolls (or clears) the port layout for the machine about to be placed. Transport
## parts have no ports, so they keep the direction-rotate behaviour instead.
func _roll_place_layout() -> void:
	_place_in_offsets = []
	_place_out_offsets = []
	_place_hold_offsets = []
	_place_body_offsets = []
	if _place_id.is_empty() or _place_id.begins_with("__"):
		return
	var layout := RunState.factory.roll_machine_layout(_place_id, _place_rng)
	_place_in_offsets = layout.get("in_offsets", [])
	_place_out_offsets = layout.get("out_offsets", [])
	_place_hold_offsets = layout.get("hold_offsets", [])
	_place_body_offsets = layout.get("body_offsets", [])
	_place_flash = 0.45


func _handle_place_input() -> void:
	var transport := _place_id.begins_with("__")
	if Input.is_action_just_pressed("build_cancel") or (not transport and Input.is_action_just_pressed("storage")):
		# Transport: cancel the placement. Machine: it's still in storage, so just stop
		# holding it (retrieve it again with [G]).
		_place_mode = false
		_message = "Cancelled." if transport else "Kept in storage — [G] to place it later."
		return
	_move_cursor()
	if Input.is_action_just_pressed("reshuffle"):
		if transport:
			_place_dir = Vector2i(-_place_dir.y, _place_dir.x)  # rotate the arrow
		else:
			_scrap_held_machine()  # [R] on a machine in hand → scrap it for tech data
			return
	if Input.is_action_just_pressed("attack"):
		_try_place()


## Scraps the machine currently in hand (being placed from stock) into Tech Data, then
## moves on to the next queued machine. This is the "no room → break it down" path.
func _scrap_held_machine() -> void:
	var id := _place_id
	if id.is_empty() or id.begins_with("__"):
		return
	if RunState.take_instance(_place_instance_index).is_empty():
		# No instance in hand to consume — don't mint tech data.
		_place_instance_index = -1
		_place_mode = false
		return
	_place_instance_index = -1
	var gained := _scrap_value(id)
	RunState.add("tech_data", gained)
	_place_mode = false
	_message = "Scrapped %s → +%d tech data." % [_part_name(id), gained]


## Tech Data a machine is worth when scrapped — bigger/more complex machines are worth more.
func _scrap_value(id: String) -> int:
	return RunState.factory.core_size_of(id) + 1


func _try_place() -> void:
	var id := _place_id
	if id.is_empty():
		return
	var f := RunState.factory
	var transport := id == "__conveyor" or id == "__splitter" or id == "__filter"
	var valid: bool
	if transport:
		# Transport can go on empty cells or over a loose item (it gets shifted aside).
		var k := String(f.get_cell(_cursor).get("kind", ""))
		valid = k == "" or k == "resource"
	else:
		valid = f.can_place_layout(id, _cursor, _place_in_offsets, _place_out_offsets, _place_hold_offsets, _place_body_offsets)
	if not valid:
		var why := " or rotate [R]" if transport else ", or scrap it [R]"
		_message = "Won't fit here — move it%s." % why
		return
	# Pay for it. Transport comes from storage; caches from storage or materials; found machines
	# are already yours (consume one from stock).
	if transport:
		# Conveyors/splitters/filters are found-and-repaired items now — place only from storage.
		if RunState.stock_count(id) <= 0:
			_message = "No %s in storage — find and repair one out in a run." % _part_name(id)
			return
		RunState.take_from_stock(id)
	elif id in RADIAL_PARTS:
		# Caches: place from storage, or pay their material cost to fabricate on the spot.
		if RunState.stock_count(id) > 0:
			RunState.take_from_stock(id)
		elif RunState.can_afford(RunState.part_cost(id)):
			RunState.spend(RunState.part_cost(id))
		else:
			_message = "Need %s." % _cost_text(RunState.part_cost(id))
			return
	elif id != "scrapper_arm":
		# A stored machine instance — confirmed below; it's removed from storage on a real drop.
		if _place_instance_index < 0 or _place_instance_index >= RunState.machine_instances.size():
			_message = "No %s to place." % _part_name(id)
			return
	# Place it.
	if transport:
		if id == "__conveyor":
			f.place_conveyor(_cursor, _place_dir)
		elif id == "__splitter":
			f.place_splitter(_cursor, _place_dir)
		else:
			f.place_filter(_cursor, _place_dir)
		return  # stay in positioning to lay a line
	f.place_machine_layout(id, _cursor, _place_in_offsets, _place_out_offsets, _place_hold_offsets, _place_body_offsets)
	if _place_instance_index >= 0:
		RunState.take_instance(_place_instance_index)  # the placed instance leaves storage
	_place_instance_index = -1
	_place_mode = false
	# Back to browsing — retrieve the next from storage with [G] when you're ready.


# --- shared actions ---

## Browsing [R]: removes a transport part (back to stock), or — on a machine — points you
## at the lift-then-scrap flow ([M] to pick it up, then [R] in hand to scrap for tech data).
func _remove_transport_or_hint() -> void:
	var f := RunState.factory
	var kind := String(f.get_cell(_cursor).get("kind", ""))
	if kind == "conveyor" or kind == "splitter" or kind == "filter":
		var item := String(f.get_cell(_cursor).get("item", ""))
		f.set_cell(_cursor, {})
		if item != "":
			f.add_resource(item)  # don't destroy an item that was riding it
		RunState.add_to_stock("__" + kind)  # transport returns to stock
		_message = "Removed %s → stock." % kind
		return
	if f.machine_at(_cursor) >= 0:
		_message = "[M] to pick the machine up, then [R] to scrap it for tech data."


func _slot_action() -> void:
	var f := RunState.factory
	if not f.module_at(_cursor).is_empty():
		var removed := f.remove_module(_cursor)
		_message = "Removed %s." % GameData.modules.get(removed, {}).get("name", removed)
		return
	_install_opts.clear()
	for id: String in MetaState.modules_owned:
		if MetaState.module_count(id) - f.installed_count(id) > 0:
			_install_opts.append(id)
	if _install_opts.is_empty():
		_message = "No modules available — decode some at a station."
		return
	_install_slot = _cursor
	_install_index = 0
	_install_mode = true
	_message = ""


func _handle_install_input() -> void:
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_up"):
		_install_index = maxi(_install_index - 1, 0)
	if Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("move_down"):
		_install_index = mini(_install_index + 1, _install_opts.size() - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		var id: String = _install_opts[_install_index]
		if RunState.factory.install_module(_install_slot, id):
			_message = "Installed %s." % GameData.modules.get(id, {}).get("name", id)
		_install_mode = false


func _begin_move() -> void:
	var f := RunState.factory
	var mi := f.machine_at(_cursor)
	if mi >= 0:
		_move_mi = mi
		_move_mode = true
		_message = "Move the machine to a new spot, then place it."
		return
	var kind := String(f.get_cell(_cursor).get("kind", ""))
	if kind == "conveyor" or kind == "splitter" or kind == "filter":
		_conv_cell = f.get_cell(_cursor).duplicate()
		_conv_from = _cursor
		f.set_cell(_cursor, {})  # lift it; restored on cancel
		_move_conv = true
		_message = "Move the %s — [R] rotate, [Space] place, [Esc] cancel." % kind
		return
	_message = "Put the cursor on a machine or conveyor to move it."


func _handle_move_conv_input() -> void:
	var f := RunState.factory
	_move_cursor()
	if Input.is_action_just_pressed("reshuffle"):  # rotate 90° CW
		_conv_cell["dir"] = Vector2i(-int(_conv_cell.dir.y), int(_conv_cell.dir.x))
		if _conv_cell.has("dir2"):
			_conv_cell["dir2"] = Vector2i(-int(_conv_cell.dir2.y), int(_conv_cell.dir2.x))
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		var k := String(f.get_cell(_cursor).get("kind", ""))
		if k != "" and k != "resource":
			_message = "Can't place there."
			return
		if k == "resource":
			f.displace_item(_cursor)
		f.set_cell(_cursor, _conv_cell)
		_move_conv = false
		_message = "Conveyor moved."


func _cancel_move_conv() -> void:
	RunState.factory.set_cell(_conv_from, _conv_cell)  # put it back
	_move_conv = false
	_message = "Move cancelled."


func _handle_move_input() -> void:
	var f := RunState.factory
	_move_cursor()  # the whole machine follows the cursor
	if Input.is_action_just_pressed("storage"):
		_stash_moving_machine()  # [G] on a lifted machine → send it to storage
		return
	if Input.is_action_just_pressed("reshuffle"):
		_scrap_moving_machine()  # [R] on a machine in hand → scrap it for tech data
		return
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		if not f.can_relocate(_move_mi, _cursor, f.move_offsets(_move_mi)):
			_message = "Won't fit here — move it [WASD] to an open spot."
			return
		f.move_machine(_move_mi, _cursor)
		_move_mode = false
		_message = "Machine moved."


## Scraps the machine currently lifted for a move into Tech Data (the "break it down"
## path for a machine already on your grid).
func _scrap_moving_machine() -> void:
	var f := RunState.factory
	var did := String(f.machines[_move_mi].get("def_id", ""))
	if did == "scrapper_arm":
		_message = "The Scrapper Arm can't be scrapped."
		return
	_scrap_cache_contents(_move_mi)
	f.pickup_machine(_move_mi)  # remove it from the grid
	var gained := _scrap_value(did)
	RunState.add("tech_data", gained)
	_move_mode = false
	_message = "Scrapped %s → +%d tech data." % [_part_name(did), gained]


## Sends the machine currently lifted for a move into the storage list (off the grid) so you
## can clear space and rearrange, then place it again later with [G].
func _stash_moving_machine() -> void:
	var f := RunState.factory
	var did := String(f.machines[_move_mi].get("def_id", ""))
	if did == "scrapper_arm":
		_message = "The Scrapper Arm can't be stored."
		return
	var cs := f.cache_state(_move_mi)
	if not cs.is_empty() and int(cs.get("count", 0)) > 0:
		_message = "Empty the cache before storing it."
		return
	# Preserve the machine's CURRENT layout so it goes back to storage as that same instance.
	var m: Dictionary = f.machines[_move_mi]
	var layout := {
		"in_offsets": f.in_offsets_of(m), "out_offsets": f.out_offsets_of(m),
		"hold_offsets": f.hold_offsets_of(m), "body_offsets": f.body_offsets_of(m),
	}
	f.pickup_machine(_move_mi)  # remove from the grid
	RunState.store_instance(did, layout)
	_move_mode = false
	_message = "%s → storage.  [G] to place it again." % _part_name(did)


# In-run leveling has been removed — machine upgrades are now PERMANENT, bought with banked
# Tech Data at the base (meta). The grid still tracks a `level` field for that future system.


func _move_cursor() -> void:
	var step := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"):
		step.y -= 1
	if Input.is_action_just_pressed("move_down"):
		step.y += 1
	if Input.is_action_just_pressed("move_left"):
		step.x -= 1
	if Input.is_action_just_pressed("move_right"):
		step.x += 1
	if step == Vector2i.ZERO:
		return
	var candidate := _cursor + step
	if RunState.factory != null and RunState.factory.in_bounds(candidate):
		_cursor = candidate


## Space on a cell: builds a carried stack of one resource. Same item under the cursor
## is added to the stack; an empty cell (or empty conveyor slot) receives ONE from the
## stack. So you can sweep up several of a resource, then place/feed them one per press.
func _pick_or_drop() -> void:
	var f := RunState.factory
	if f == null:
		return
	var cell := f.get_cell(_cursor)
	var kind := String(cell.get("kind", ""))
	var is_transport := kind == "conveyor" or kind == "splitter" or kind == "filter"
	# What resource (if any) is at the cursor: a loose item, or one riding transport.
	var here := ""
	if kind == "resource":
		here = String(cell.id)
	elif is_transport:
		here = String(cell.get("item", ""))

	# Carrying an item onto a filter sets what it filters (samples the id, keeps the item).
	if not _carried.is_empty() and kind == "filter":
		cell["filter_id"] = String(_carried.id)
		_message = "Filter set to %s — it turns out the 90° side." % GameData.resource_name(String(_carried.id))
		return

	if _carried.is_empty():
		if here != "":
			var took := f.cell_count(cell) if kind == "resource" else 1  # take the whole stack
			_carried = {"kind": "resource", "id": here, "count": took}
			_clear_item_at(cell, kind)
		return

	var cid := String(_carried.id)
	if here == cid:
		var took := f.cell_count(cell) if kind == "resource" else 1  # scoop up the whole stack
		_carried["count"] = int(_carried.count) + took
		_clear_item_at(cell, kind)
	elif here == "":
		if kind == "":
			f.set_cell(_cursor, {"kind": "resource", "id": cid, "count": 1})
			_dec_carried()
		elif is_transport:
			cell["item"] = cid  # live grid dict — rides from here
			_dec_carried()
		else:
			_message = "That cell is occupied."
	else:
		_message = "Holding %s — drop it first." % GameData.resource_name(cid)


## Clears the item at the cursor (a loose resource cell, or a conveyor's carry slot).
func _clear_item_at(cell: Dictionary, kind: String) -> void:
	if kind == "resource":
		RunState.factory.set_cell(_cursor, {})
	else:
		cell["item"] = ""  # get_cell returns the live grid dict, so this mutates it


## Removes one from the carried stack; empties the hand when it hits zero.
func _dec_carried() -> void:
	_carried["count"] = int(_carried.get("count", 1)) - 1
	if int(_carried.count) <= 0:
		_carried = {}


func _part_name(id: String) -> String:
	if id == "__conveyor":
		return "Conveyor"
	if id == "__splitter":
		return "Splitter"
	if id == "__filter":
		return "Filter"
	return String(GameData.machines.get(id, {}).get("name", id))


func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for id: String in cost:
		parts.append("%d %s" % [int(cost[id]), GameData.resource_name(id)])
	return ", ".join(parts)


## Everything placeable now comes from stock (machines found in rooms; transport/caches
## crafted at a Fabricator) except the free starter arm.
func _affordable(id: String) -> bool:
	return id == "scrapper_arm" or RunState.stock_count(id) > 0


# ---------------------------------------------------------------- draw ----

## The scrap bar is gone — scrap now lives in the Scrapper Arm MACHINE's slots in the grid.
## Only the Tech Data currency remains up here.
func _draw_arm_bar() -> void:
	draw_string(_font, Vector2(14, ARM_BAR_Y - 2), "TECH DATA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.62, 0.68))
	var r := Rect2(Vector2(14, ARM_BAR_Y + 2), Vector2(70, 30))
	var def: Dictionary = GameData.resources.get("tech_data", {})
	var col := Color.from_string("#" + String(def.get("color", "888888")), Color(0.5, 0.5, 0.5))
	draw_rect(r, Color(0.13, 0.13, 0.18))
	draw_rect(r, Color(col, 0.9), false, 1.5)
	var tex := ContentLibrary.get_icon(String(def.get("icon", "tech_data")), Vector2i(16, 16), String(def.get("color", "")))
	draw_texture_rect(tex, Rect2(r.position + Vector2(5, 7), Vector2(16, 16)), false)
	var n := RunState.currency_count("tech_data")
	draw_string(_font, r.position + Vector2(24, 20), "%d" % n, HORIZONTAL_ALIGNMENT_LEFT, 44, 13, Color(0.95, 0.95, 0.98) if n > 0 else Color(0.5, 0.5, 0.55))


func _cell_rect(pos: Vector2i) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(pos.x * (CELL + GAP), pos.y * (CELL + GAP)), Vector2(CELL, CELL))


## Outlines each machine together with its input/output/holding/module cells, so it
## is obvious which slots belong to which machine. Each machine gets a distinct hue;
## the outline hugs the union of the group's cells and bridges the inter-cell gap so
## it reads as a single enclosure even for L-shaped footprints.
func _draw_machine_borders(f: FactoryGrid) -> void:
	var mi := 0
	for m: Dictionary in f.machines:
		if bool(m.get("removed", false)):
			mi += 1
			continue
		var cells := {Vector2i(m.core): true}
		for o: Vector2i in f.body_offsets_of(m):
			cells[Vector2i(m.core) + o] = true
		for p: Vector2i in f.slot_positions(m):
			cells[p] = true
		for p: Vector2i in f.input_positions(m):
			cells[p] = true
		for p: Vector2i in f.output_positions(m):
			cells[p] = true
		for p: Vector2i in f.holding_positions(m):
			cells[p] = true
		# Distinct hue per machine; offset off pure red so a border never reads as "error".
		var col := Color.from_hsv(fmod(mi * 0.19 + 0.5, 1.0), 0.55, 1.0, 0.95)
		var pad := GAP * 0.5
		for cell: Vector2i in cells:
			var r := _cell_rect(cell).grow(pad)
			var tl := r.position
			var tr := r.position + Vector2(r.size.x, 0)
			var bl := r.position + Vector2(0, r.size.y)
			var br := r.position + r.size
			if not cells.has(cell + Vector2i(0, -1)):
				draw_line(tl, tr, col, 2.0)
			if not cells.has(cell + Vector2i(0, 1)):
				draw_line(bl, br, col, 2.0)
			if not cells.has(cell + Vector2i(-1, 0)):
				draw_line(tl, bl, col, 2.0)
			if not cells.has(cell + Vector2i(1, 0)):
				draw_line(tr, br, col, 2.0)
		mi += 1


func _draw() -> void:
	var f := RunState.factory
	draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.06, 0.06, 0.09, 1.0))
	draw_string(_font, Vector2(14, 34), "FACTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.9, 0.95))
	_draw_arm_bar()
	if f == null:
		return

	# --- left: the grid ---
	var role := {}
	_port_info.clear()
	for m: Dictionary in f.machines:
		if bool(m.get("removed", false)):
			continue
		var core := Vector2i(m.core)
		var working := String(m.get("status", "")) == "working"
		var prog := float(m.get("progress", 0.0))  # seconds into the current craft
		for p: Vector2i in f.input_positions(m):
			role[p] = "input"
			_port_info[p] = {"kind": "input", "core": core, "working": working, "progress": prog}
		for p: Vector2i in f.output_positions(m):
			role[p] = "output"
			_port_info[p] = {"kind": "output", "core": core, "working": working, "progress": prog}
		for p: Vector2i in f.holding_positions(m):
			if not role.has(p):
				role[p] = "holding"

	var preview := _preview_cells(f)
	for y in f.rows:
		for x in f.cols:
			var pos := Vector2i(x, y)
			_draw_cell(f, pos, _cell_rect(pos), String(role.get(pos, "")), preview)

	_draw_machine_borders(f)
	_draw_pops(f)

	if _move_mode:
		_draw_relocate_preview(f, _move_mi, f.move_offsets(_move_mi), [])
	elif _move_conv:
		var k := String(f.get_cell(_cursor).get("kind", ""))
		var okc := k == "" or k == "resource"
		var r := _cell_rect(_cursor)
		draw_rect(r, Color(0.4, 1, 0.4, 0.25) if okc else Color(1, 0.4, 0.4, 0.28))
		draw_rect(r.grow(1), Color(0.6, 1, 0.6) if okc else Color(1, 0.5, 0.5), false, 2.0)
		draw_string(_font, r.position + Vector2(4, r.size.y - 6), String(ARROWS.get(Vector2i(_conv_cell.get("dir", Vector2i.RIGHT)), "•")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.85, 0.85))

	if _place_mode and not _place_id.is_empty():
		if _place_id.begins_with("__"):
			var cr := _cell_rect(_cursor).position
			draw_string(_font, cr + Vector2(CELL * 0.5 - 8, CELL * 0.5 + 8), String(ARROWS.get(_place_dir, "•")), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 0.6))
		else:
			_draw_machine_preview(f, _place_id)

	# --- right: the context panel ---
	var rx := RPANEL_X + 12
	var rw := RPANEL_W - 24
	draw_line(Vector2(RPANEL_X, 24), Vector2(RPANEL_X, PANEL_SIZE.y - 20), Color(0.2, 0.2, 0.26), 1.0)
	if _storage_mode:
		_draw_storage_panel(rx, RPANEL_TOP, rw)
	elif _place_mode:
		_draw_part_info(rx, RPANEL_TOP, rw, _place_id, true)
	elif _install_mode:
		_draw_install_panel(rx, RPANEL_TOP, rw)
	elif _move_mode:
		_draw_move_panel(rx, RPANEL_TOP, rw)
	else:
		_draw_cursor_info(rx, RPANEL_TOP, rw)

	# Combine selection highlight + the radial overlay sit on top of the grid.
	if _combine_a_core != Vector2i(-1, -1):
		var ci := RunState.factory.machine_at(_combine_a_core)
		if ci >= 0:
			var cr := _cell_rect(_combine_a_core)
			draw_rect(cr.grow(2), Color(0.95, 0.85, 0.5), false, 3.0)
	if _radial_mode:
		_draw_radial()

	# Message + base controls along the bottom.
	if _message != "":
		draw_string(_font, Vector2(14, PANEL_SIZE.y - 26), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL_SIZE.x - 28, 13, Color(1, 0.95, 0.7))
	draw_string(_font, Vector2(14, PANEL_SIZE.y - 8), _base_controls(), HORIZONTAL_ALIGNMENT_LEFT, PANEL_SIZE.x - 28, 12, Color(0.62, 0.62, 0.68))


func _base_controls() -> String:
	if not _editable():
		return "[WASD] move   [Space] move items   [Esc] close    — layout locked (set it up in the lair)"
	if _storage_mode:
		return "[W/S] pick   [Space] place it   [G]/[Esc] back"
	if _radial_mode:
		return "[A/D] choose part   [Space] pick   [Esc] cancel"
	if _place_mode:
		if _place_id.begins_with("__"):
			return "[WASD] move   [Space] place   [R] rotate   [Esc] cancel"
		return "[WASD] move   [Space] drop   [R] scrap   [G]/[Esc] storage"
	if _move_mode:
		return "[WASD] move   [Space] place   [G] store   [R] scrap   [Esc] cancel"
	if _move_conv:
		return "[WASD] move   [R] rotate   [Space] place   [Esc] cancel"
	var combine_hint := "[C] combine" if _combine_a_core == Vector2i(-1, -1) else "[C] merge with marked"
	var store_hint := "[G] storage (%d)" % _stock_total() if _has_unplaced() else "[G] storage"
	return "[WASD] move  [Space] act  [M] lift  [B] transport  %s  %s  [Enter] accept & launch  [Esc] close" % [combine_hint, store_hint]


# --- right-panel renderers ---

## The transport radial: four part icons in a ring around the selected cell; the
## highlighted one shows its name + cost. Driven with [A]/[D] + [Space].
func _draw_radial() -> void:
	var center := _cell_rect(_radial_cell).get_center()
	var n := RADIAL_PARTS.size()
	var radius := 58.0
	draw_circle(center, radius + 20.0, Color(0.05, 0.05, 0.09, 0.92))
	draw_arc(center, radius + 20.0, 0, TAU, 56, Color(0.9, 0.8, 0.4, 0.5), 1.5)
	for i in n:
		var id: String = RADIAL_PARTS[i]
		var ang := -PI / 2.0 + TAU * float(i) / float(n)  # start at top, clockwise
		var p := center + Vector2(cos(ang), sin(ang)) * radius
		if i == _radial_index:
			draw_circle(p, 16.0, Color(0.95, 0.85, 0.5, 0.35))
		var tex := ContentLibrary.get_icon(_icon_of(id), Vector2i(20, 20), _color_of(id))
		draw_texture_rect(tex, Rect2(p - Vector2(10, 10), Vector2(20, 20)), false)
	var cur: String = RADIAL_PARTS[_radial_index]
	var cost_txt: String
	if cur == "__conveyor" or cur == "__splitter" or cur == "__filter":
		cost_txt = "in storage (%d)" % RunState.stock_count(cur) if RunState.stock_count(cur) > 0 else "none — find & repair one"
	elif RunState.stock_count(cur) > 0:
		cost_txt = "in stock (%d)" % RunState.stock_count(cur)
	else:
		cost_txt = _cost_text(RunState.part_cost(cur))
	var label := "%s — %s" % [_part_name(cur), cost_txt]
	draw_string(_font, Vector2(center.x - 160, center.y + radius + 38), label, HORIZONTAL_ALIGNMENT_CENTER, 320, 13, Color(0.95, 0.9, 0.7))


func _draw_part_info(x: float, y: float, w: float, id: String, _positioning: bool) -> void:
	if id.is_empty():
		return
	var tex := ContentLibrary.get_icon(_icon_of(id), Vector2i(22, 22), _color_of(id))
	draw_texture_rect(tex, Rect2(x, y, 22, 22), false)
	draw_string(_font, Vector2(x + 30, y + 17), _part_name(id), HORIZONTAL_ALIGNMENT_LEFT, w - 30, 16, Color(0.92, 0.92, 0.96))
	var tag := "free to build" if id == "scrapper_arm" else "in stock: %d" % RunState.stock_count(id)
	draw_string(_font, Vector2(x, y + 40), tag, HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(0.8, 0.85, 0.9))
	var yy := y + 62
	for line: String in _makes_lines(id):
		draw_string(_font, Vector2(x, yy), line, HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
		yy += 30


func _draw_cursor_info(x: float, y: float, w: float) -> void:
	var f := RunState.factory
	var cell := f.get_cell(_cursor)
	var kind := String(cell.get("kind", ""))
	draw_string(_font, Vector2(x, y + 14), "INSPECT", HORIZONTAL_ALIGNMENT_LEFT, w, 16, Color(0.9, 0.9, 0.95))
	if kind == "machine":
		var mi := int(cell.mi)
		var def: Dictionary = GameData.machines.get(String(f.machines[mi].def_id), {})
		var tex := ContentLibrary.get_icon(String(def.get("icon", "")), Vector2i(22, 22), String(def.get("color", "")))
		draw_texture_rect(tex, Rect2(x, y + 26, 22, 22), false)
		draw_string(_font, Vector2(x + 30, y + 43), "%s  L%d" % [String(def.get("name", "")), f.level_of(mi)], HORIZONTAL_ALIGNMENT_LEFT, w - 30, 15, Color(0.92, 0.92, 0.96))
		var stat := f.status_at(_cursor)
		draw_string(_font, Vector2(x, y + 66), "Status: %s" % (stat if stat != "" else "—"), HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(0.8, 0.85, 0.9))
		var yy := y + 86
		for line: String in _makes_lines(String(f.machines[mi].def_id)):
			draw_string(_font, Vector2(x, yy), line, HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
			yy += 30
		draw_string(_font, Vector2(x, yy + 4), "[M] move/lift   [C] combine   [G] store", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.7, 0.7, 0.75))
	elif kind == "machine_slot":
		var mod := f.module_at(_cursor)
		draw_string(_font, Vector2(x, y + 40), "Module slot", HORIZONTAL_ALIGNMENT_LEFT, w, 14, Color(0.85, 0.85, 0.95))
		if mod != "":
			var md: Dictionary = GameData.modules.get(mod, {})
			draw_string(_font, Vector2(x, y + 60), "%s — %s" % [String(md.get("name", mod)), String(md.get("desc", ""))], HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
			draw_string(_font, Vector2(x, y + 82), "[Space] remove", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.7, 0.7, 0.75))
		else:
			draw_string(_font, Vector2(x, y + 60), "empty — [Space] install a module", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
	elif kind == "resource":
		var id := String(cell.id)
		var tex := ContentLibrary.get_icon(GameData.resource_icon(id), Vector2i(20, 20), GameData.resource_color(id))
		draw_texture_rect(tex, Rect2(x, y + 26, 20, 20), false)
		var n := RunState.factory.cell_count(cell)
		var mx := GameData.stack_max(id)
		draw_string(_font, Vector2(x + 28, y + 42), "%s%s" % [GameData.resource_name(id), ("  x%d" % n) if n > 1 else ""], HORIZONTAL_ALIGNMENT_LEFT, w - 28, 15, Color(0.92, 0.92, 0.96))
		var detail := "stack %d / %d  —  [Space] pick up the stack" % [n, mx] if mx > 1 else "one unit  —  [Space] pick up / move"
		draw_string(_font, Vector2(x, y + 66), detail, HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
	elif kind == "arm_slot":
		var scrap := String(cell.get("scrap", ""))
		var tier := f.arm_tier_of(scrap)
		var locked := tier > f.arm_level()
		var tex := ContentLibrary.get_icon(GameData.resource_icon(scrap), Vector2i(20, 20), GameData.resource_color(scrap))
		draw_texture_rect(tex, Rect2(x, y + 26, 20, 20), false, Color(1, 1, 1, 0.35 if locked else 1.0))
		draw_string(_font, Vector2(x + 28, y + 42), "Arm slot — %s (tier %d)" % [GameData.resource_name(scrap), tier], HORIZONTAL_ALIGNMENT_LEFT, w - 28, 15, Color(0.92, 0.92, 0.96))
		if locked:
			draw_string(_font, Vector2(x, y + 66), "🔒 Locked — upgrade the Scrapper Arm to level %d." % tier, HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.9, 0.78, 0.5))
		else:
			draw_string(_font, Vector2(x, y + 66), "Holds %d. An adjacent recycler pulls it out." % int(cell.get("count", 0)), HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
	elif kind == "conveyor" or kind == "splitter" or kind == "filter":
		draw_string(_font, Vector2(x, y + 42), _part_name("__" + kind), HORIZONTAL_ALIGNMENT_LEFT, w, 15, Color(0.92, 0.92, 0.96))
		if kind == "filter":
			var fid := String(cell.get("filter_id", ""))
			if fid != "":
				draw_string(_font, Vector2(x, y + 64), "%s → 90° side, rest go straight" % GameData.resource_name(fid), HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
			else:
				draw_string(_font, Vector2(x, y + 64), "not set — carry an item + [Space] to pick", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.9, 0.75, 0.6))
		else:
			draw_string(_font, Vector2(x, y + 64), "moves items along its arrow", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
	else:
		draw_string(_font, Vector2(x, y + 42), "Empty cell", HORIZONTAL_ALIGNMENT_LEFT, w, 14, Color(0.7, 0.7, 0.75))
		if not _carried.is_empty():
			draw_string(_font, Vector2(x, y + 62), "carrying %d× %s — [Space] drop one" % [int(_carried.get("count", 1)), GameData.resource_name(String(_carried.get("id", "")))], HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))
		else:
			draw_string(_font, Vector2(x, y + 62), "[B] build transport", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.72, 0.82, 0.78))


func _draw_install_panel(x: float, y: float, w: float) -> void:
	draw_string(_font, Vector2(x, y + 14), "INSTALL MODULE", HORIZONTAL_ALIGNMENT_LEFT, w, 16, Color(0.9, 0.9, 0.95))
	for i in _install_opts.size():
		var id: String = _install_opts[i]
		var md: Dictionary = GameData.modules.get(id, {})
		var ry := y + 34 + i * 26
		if i == _install_index:
			draw_rect(Rect2(x - 2, ry - 2, w + 4, 24), Color(1, 1, 1, 0.10))
		draw_string(_font, Vector2(x + 4, ry + 13), "%s — %s" % [String(md.get("name", id)), String(md.get("desc", ""))], HORIZONTAL_ALIGNMENT_LEFT, w - 8, 12, Color(0.85, 0.9, 0.85))
	draw_string(_font, Vector2(x, y + 34 + _install_opts.size() * 26 + 10), "[←→] choose   [Space] install   [Esc] cancel", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.7, 0.7, 0.75))


func _draw_move_panel(x: float, y: float, w: float) -> void:
	var f := RunState.factory
	var mdef: Dictionary = GameData.machines.get(String(f.machines[_move_mi].def_id), {}) if _move_mi >= 0 else {}
	draw_string(_font, Vector2(x, y + 14), "MOVE: %s" % String(mdef.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 16, Color(0.9, 0.9, 0.95))
	var fits := f.can_relocate(_move_mi, _cursor, f.move_offsets(_move_mi))
	draw_string(_font, Vector2(x, y + 42), "Fits here: %s" % ("yes" if fits else "no — move [WASD] to open space"), HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(0.6, 0.95, 0.6) if fits else Color(1, 0.6, 0.55))
	draw_string(_font, Vector2(x, y + 70), "Keeps its level, modules and slots;", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.7, 0.72, 0.78))
	draw_string(_font, Vector2(x, y + 86), "items in the way shift aside.", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.7, 0.72, 0.78))
	draw_string(_font, Vector2(x, y + 114), "[WASD] move   [Space] place   [G] store   [Esc] cancel", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.75, 0.75, 0.8))


## The temporary storage list ([G]). Machines wait here while you rearrange; the inventory
## can't be closed until it's empty.
func _draw_storage_panel(x: float, y: float, w: float) -> void:
	draw_string(_font, Vector2(x, y + 14), "STORAGE", HORIZONTAL_ALIGNMENT_LEFT, w, 16, Color(0.95, 0.85, 0.5))
	draw_string(_font, Vector2(x, y + 32), "Each is a unique layout — picked ones keep their shape.", HORIZONTAL_ALIGNMENT_LEFT, w, 11, Color(0.8, 0.8, 0.86))
	var insts: Array = RunState.machine_instances
	if insts.is_empty():
		draw_string(_font, Vector2(x, y + 58), "empty", HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(0.6, 0.6, 0.65))
		return
	var rows := 9
	var top := clampi(_storage_index - rows / 2, 0, maxi(insts.size() - rows, 0))
	var list_y := y + 48
	for i in range(top, mini(top + rows, insts.size())):
		var inst: Dictionary = insts[i]
		var id := String(inst.get("def_id", ""))
		var ry := list_y + (i - top) * 28
		if i == _storage_index:
			draw_rect(Rect2(x - 2, ry - 2, w + 4, 26), Color(1, 1, 1, 0.12))
		var tex := ContentLibrary.get_icon(_icon_of(id), Vector2i(16, 16), _color_of(id))
		draw_texture_rect(tex, Rect2(x + 2, ry + 2, 16, 16), false)
		draw_string(_font, Vector2(x + 24, ry + 15), _part_name(id), HORIZONTAL_ALIGNMENT_LEFT, w - 90, 13, Color(0.92, 0.92, 0.96))
		_draw_layout_thumb(inst, Vector2(x + w - 58, ry + 1), 24.0)


## A tiny preview of an instance's rolled layout: core (white), body (grey), inputs (blue),
## outputs (green), holding (amber) — so two of the same machine read as different shapes.
func _draw_layout_thumb(inst: Dictionary, pos: Vector2, box: float) -> void:
	var cells := {Vector2i.ZERO: Color(0.92, 0.92, 0.96)}
	for o: Vector2i in inst.get("body_offsets", []):
		cells[o] = Color(0.55, 0.58, 0.66)
	for o: Vector2i in inst.get("hold_offsets", []):
		cells[o] = Color(0.9, 0.78, 0.45)
	for o: Vector2i in inst.get("in_offsets", []):
		cells[o] = Color(0.5, 0.7, 1.0)
	for o: Vector2i in inst.get("out_offsets", []):
		cells[o] = Color(0.5, 1.0, 0.7)
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	for c: Vector2i in cells:
		lo.x = mini(lo.x, c.x); lo.y = mini(lo.y, c.y)
		hi.x = maxi(hi.x, c.x); hi.y = maxi(hi.y, c.y)
	var span: int = maxi(hi.x - lo.x + 1, hi.y - lo.y + 1)
	var cs := box / float(maxi(span, 1))
	for c: Vector2i in cells:
		var r := Rect2(pos + Vector2(float(c.x - lo.x) * cs, float(c.y - lo.y) * cs), Vector2(cs - 1.0, cs - 1.0))
		draw_rect(r, cells[c])


func _icon_of(id: String) -> String:
	match id:
		"__conveyor":
			return "conveyor"
		"__splitter":
			return "splitter"
		"__filter":
			return "filter"
	return String(GameData.machines.get(id, {}).get("icon", id))


func _color_of(id: String) -> String:
	if id.begins_with("__"):
		return "45b0b0"
	return String(GameData.machines.get(id, {}).get("color", ""))


## Draws a machine footprint at the cursor while relocating (leveling or moving): the
## core (with the machine's icon), its existing slots, any newly rolled slots (marked
## "+"), and its in/out cells — tinted green if it can be dropped here, red if not.
func _draw_relocate_preview(f: FactoryGrid, mi: int, existing_offsets: Array, new_offsets: Array) -> void:
	if mi < 0 or mi >= f.machines.size():
		return
	var m: Dictionary = f.machines[mi]
	var def: Dictionary = GameData.machines.get(String(m.def_id), {})
	var all_offsets: Array = existing_offsets + new_offsets
	var fits := f.can_relocate(mi, _cursor, all_offsets)
	var fill := Color(0.4, 1, 0.4, 0.28) if fits else Color(1, 0.4, 0.4, 0.30)
	var edge := Color(0.6, 1, 0.6) if fits else Color(1, 0.5, 0.5)
	# In/out cells (this machine's rolled ports) so the player sees where flow lands.
	var port_defs := [[f.in_offsets_of(m), "IN", Color(0.7, 0.85, 1), Color(0.5, 0.7, 1.0, 0.14)], [f.out_offsets_of(m), "OUT", Color(0.7, 1, 0.8), Color(0.5, 1.0, 0.7, 0.14)]]
	for pd: Array in port_defs:
		for off: Vector2i in pd[0]:
			var p := _cursor + off
			if f.in_bounds(p):
				var rr := _cell_rect(p)
				draw_rect(rr.grow(-2), pd[3])
				draw_string(_font, rr.position + Vector2(3, 13), pd[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, pd[2])
	# Solid footprint: core + extra body tiles + existing slots + new slots.
	var body_extra: Array = f.body_offsets_of(m)
	var body: Array = [Vector2i.ZERO] + body_extra + all_offsets
	for i in body.size():
		var p: Vector2i = _cursor + body[i]
		if not f.in_bounds(p):
			continue
		var r := _cell_rect(p)
		draw_rect(r, fill)
		draw_rect(r.grow(1), edge, false, 2.0)
		if i == 0:
			var tex := ContentLibrary.get_icon(String(def.get("icon", m.def_id)), Vector2i(24, 24), String(def.get("color", "")))
			draw_texture_rect(tex, r.grow(-6), false, Color(1, 1, 1, 0.9))
		elif i > body_extra.size() + existing_offsets.size():
			# A newly added level slot: mark it so the player sees what's new.
			draw_string(_font, r.position + Vector2(r.size.x * 0.5 - 5, r.size.y * 0.5 + 5), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, edge)


## Draws each active out-slide: a freshly-produced item sliding from the machine core
## into its output cell, growing to full size as it lands.
func _draw_pops(f: FactoryGrid) -> void:
	for p: Dictionary in _pops:
		var e := smoothstep(0.0, 1.0, float(p.t) / float(p.dur))
		var from := _cell_rect(Vector2i(p.origin)).get_center()
		var to := _cell_rect(Vector2i(p.pos)).get_center()
		var c := from.lerp(to, e)
		var size := lerpf(10.0, 18.0, e)
		var id := String(p.id)
		draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(id), Vector2i(18, 18), GameData.resource_color(id)), Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size)), false)


func _draw_machine_preview(f: FactoryGrid, id: String) -> void:
	var def: Dictionary = GameData.machines.get(id, {})
	if def.is_empty() or not f.in_bounds(_cursor):
		return
	var fits := f.can_place_layout(id, _cursor, _place_in_offsets, _place_out_offsets, _place_hold_offsets, _place_body_offsets)
	# A freshly-rolled layout pulses briefly so the player notices the new arrangement.
	var pulse := 0.0
	if _place_flash > 0.0:
		pulse = abs(sin(_place_flash * 22.0)) * 0.6
	var body_col := (Color(0.4, 1, 0.4, 0.22) if fits else Color(1, 0.4, 0.4, 0.24)).lerp(Color(1, 1, 1, 0.5), pulse)
	var edge_col := Color(0.6, 1, 0.6) if fits else Color(1, 0.5, 0.5)
	# Extra body tiles (multi-tile core).
	for off: Vector2i in _place_body_offsets:
		if f.in_bounds(_cursor + off):
			var br := _cell_rect(_cursor + off)
			draw_rect(br, body_col)
			draw_rect(br.grow(1), edge_col, false, 2.0)
	var core := _cell_rect(_cursor)
	draw_rect(core, body_col)
	draw_rect(core.grow(1), edge_col, false, 2.0)
	var tex := ContentLibrary.get_icon(String(def.get("icon", id)), Vector2i(24, 24), String(def.get("color", "")))
	draw_texture_rect(tex, core.grow(-6), false, Color(1, 1, 1, 0.9))
	_draw_port_cell(f, _place_in_offsets, "IN", Color(0.5, 0.7, 1.0), pulse)
	_draw_port_cell(f, _place_out_offsets, "OUT", Color(0.5, 1.0, 0.7), pulse)
	_draw_port_cell(f, _place_hold_offsets, "HOLD", Color(0.9, 0.75, 0.4), pulse)


func _draw_port_cell(f: FactoryGrid, offsets: Array, label: String, tint: Color, pulse: float) -> void:
	for off: Vector2i in offsets:
		var p := _cursor + off
		if not f.in_bounds(p):
			continue
		var r := _cell_rect(p)
		draw_rect(r.grow(-2), Color(tint.r, tint.g, tint.b, 0.16).lerp(Color(1, 1, 1, 0.5), pulse))
		draw_rect(r.grow(1), tint, false, 2.0)
		draw_string(_font, r.position + Vector2(3, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)


func _draw_cell(f: FactoryGrid, pos: Vector2i, rect: Rect2, role: String, preview: Dictionary) -> void:
	var cell := f.get_cell(pos)
	var kind := String(cell.get("kind", ""))

	var bg := Color(0.12, 0.12, 0.15)
	match role:
		"input": bg = Color(0.12, 0.16, 0.24)
		"output": bg = Color(0.12, 0.22, 0.16)
		"holding": bg = Color(0.22, 0.18, 0.10)
	if kind == "machine":
		bg = Color(0.16, 0.18, 0.24)
	elif kind == "machine_body":
		bg = Color(0.15, 0.16, 0.21)  # extra body tile of a multi-tile machine
	elif kind == "machine_slot":
		bg = Color(0.20, 0.20, 0.30)
	draw_rect(rect, bg)

	if kind == "machine_body":
		# Mark it as part of the owning machine's body (reads as one unit with the core).
		draw_rect(rect.grow(-9), Color(0.4, 0.45, 0.55, 0.6), false, 2.0)

	if kind == "machine":
		var m: Dictionary = f.machines[int(cell.mi)]
		var def: Dictionary = GameData.machines.get(String(m.def_id), {})
		var tex := ContentLibrary.get_icon(String(def.get("icon", m.def_id)), Vector2i(24, 24), String(def.get("color", "")))
		draw_texture_rect(tex, rect.grow(-6), false)
		var cs := f.cache_state(int(cell.mi))
		if not cs.is_empty():
			# Storage cache: no output arrow/level — show its stored item + count/capacity.
			if String(cs.id) != "":
				draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(String(cs.id)), Vector2i(13, 13), GameData.resource_color(String(cs.id))), Rect2(rect.position + Vector2(rect.size.x - 16, 3), Vector2(13, 13)), false)
			var full := int(cs.count) >= int(cs.capacity)
			draw_string(_font, rect.position + Vector2(3, rect.size.y - 4), "%d/%d" % [int(cs.count), int(cs.capacity)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.7) if full else Color(0.7, 0.85, 1.0))
		else:
			draw_string(_font, rect.position + Vector2(rect.size.x - 12, 12), String(ARROWS.get(f.output_position(m) - pos, "•")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 1, 0.7))
			draw_string(_font, rect.position + Vector2(3, rect.size.y - 4), "L%d" % f.level_of(int(cell.mi)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.9, 0.5))
		var st := String(m.get("status", ""))
		if st != "":
			var dot := Color(0.5, 0.5, 0.55)
			if st == "working":
				dot = Color(0.4, 0.9, 0.5)
			elif st == "blocked":
				dot = Color(0.95, 0.75, 0.3)
			draw_rect(Rect2(rect.position + Vector2(rect.size.x - 10, rect.size.y - 10), Vector2(7, 7)), dot)
			var ratio := clampf(float(m.get("progress_ratio", 0.0)), 0.0, 1.0)
			if ratio > 0.0:
				var bar_col := Color(0.4, 0.9, 0.5) if st == "working" else Color(0.95, 0.75, 0.3)
				draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 3), Vector2((rect.size.x - 4) * ratio, 2)), bar_col)
	elif kind == "machine_slot":
		var mod := f.module_at(pos)
		if mod != "":
			var mdef: Dictionary = GameData.modules.get(mod, {})
			draw_texture_rect(ContentLibrary.get_icon(String(mdef.get("icon", mod)), Vector2i(22, 22), String(mdef.get("color", ""))), rect.grow(-7), false)
		else:
			draw_rect(rect.grow(-10), Color(0.35, 0.35, 0.5), false, 2.0)
	elif kind == "conveyor" or kind == "splitter" or kind == "filter":
		draw_rect(rect, Color(0.14, 0.11, 0.13) if kind == "filter" else Color(0.10, 0.13, 0.13))
		draw_string(_font, rect.position + Vector2(4, rect.size.y - 6), String(ARROWS.get(Vector2i(cell.get("dir", Vector2i.RIGHT)), "•")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.45, 0.75, 0.75))
		if kind == "splitter":
			draw_string(_font, rect.position + Vector2(rect.size.x - 15, rect.size.y - 6), String(ARROWS.get(Vector2i(cell.get("dir2", Vector2i.DOWN)), "•")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.6, 0.45))
		elif kind == "filter":
			# The 90° exit arrow (where the filtered item turns off), tinted pink.
			draw_string(_font, rect.position + Vector2(rect.size.x - 15, rect.size.y - 6), String(ARROWS.get(Vector2i(cell.get("dir2", Vector2i.DOWN)), "•")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.55, 0.75))
			# The filtered item's icon in the corner (or a dot if unset).
			var fid := String(cell.get("filter_id", ""))
			if fid != "":
				draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(fid), Vector2i(13, 13), GameData.resource_color(fid)), Rect2(rect.position + Vector2(rect.size.x - 15, 3), Vector2(13, 13)), false)
			else:
				draw_string(_font, rect.position + Vector2(4, 13), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.6, 0.7))
		var carried := String(cell.get("item", ""))
		if carried != "":
			draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(carried), Vector2i(15, 15), GameData.resource_color(carried)), rect.grow(-11), false)
	elif kind == "arm_slot":
		# A Scrapper Arm scrap slot: tinted to its type, showing the scrap icon + stored count.
		# A slot whose tier the arm hasn't reached yet is LOCKED — dimmed with a padlock.
		var scrap := String(cell.get("scrap", ""))
		var n := int(cell.get("count", 0))
		var locked := f.arm_tier_of(scrap) > f.arm_level()
		draw_rect(rect, Color(0.10, 0.10, 0.12) if locked else Color(0.18, 0.16, 0.10))
		draw_rect(rect.grow(-2), Color(GameData.resource_color(scrap), 0.18 if locked else 0.55), false, 2.0)
		draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(scrap), Vector2i(18, 18), GameData.resource_color(scrap)), rect.grow(-9), false, Color(1, 1, 1, 0.22 if locked else (0.95 if n > 0 else 0.4)))
		if locked:
			draw_string(_font, rect.position + Vector2(rect.size.x * 0.5 - 5, rect.size.y * 0.5 + 6), "🔒", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.8, 0.85))
		else:
			var badge := Rect2(rect.position + Vector2(rect.size.x - 17, rect.size.y - 14), Vector2(15, 12))
			draw_rect(badge, Color(0.08, 0.09, 0.12, 0.92))
			draw_string(_font, badge.position + Vector2(2, 10), "%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.95, 0.7) if n > 0 else Color(0.55, 0.55, 0.6))
	elif kind == "resource":
		# While an out-slide pop is playing for this cell, the pop overlay draws the
		# item instead (so it isn't drawn twice).
		if _pop_for(pos).is_empty():
			var id := String(cell.id)
			var inner := rect.grow(-9)
			var pi: Dictionary = _port_info.get(pos, {})
			# Feed-in: while a machine is working, its input item slides one cell into the
			# core over FEED_TIME (conveyor speed), then is "inside" (hidden) while it
			# processes; the product later slides back out (the pop). Idle/blocked inputs
			# just sit in the cell.
			if pi.get("kind", "") == "input" and bool(pi.get("working", false)):
				var feed := clampf(float(pi.get("progress", 0.0)) / FEED_TIME, 0.0, 1.0)
				if feed >= 1.0:
					pass  # fully drawn in — being processed, don't draw it in the cell
				else:
					var dir := Vector2(Vector2i(pi.core) - pos)
					inner.position += dir * (CELL + GAP) * feed
					draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(id), Vector2i(18, 18), GameData.resource_color(id)), inner, false)
			else:
				draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(id), Vector2i(18, 18), GameData.resource_color(id)), inner, false)
			# Stack count badge (bottom-right) when more than one sits here.
			var cnt := int(cell.get("count", 1))
			if cnt > 1:
				var b := Rect2(rect.position + Vector2(rect.size.x - 16, rect.size.y - 14), Vector2(14, 12))
				draw_rect(b, Color(0.08, 0.09, 0.12, 0.92))
				draw_string(_font, b.position + Vector2(2, 10), "%d" % cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.95, 0.7))

	# "holding" cells are no longer a meaningful role to surface, so don't label them.
	if role != "" and role != "holding" and kind != "machine":
		draw_string(_font, rect.position + Vector2(4, 13), role.substr(0, 3).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.75, 0.8))

	if preview.has(pos):
		draw_rect(rect, Color(0.4, 1, 0.4, 0.30) if preview[pos] else Color(1, 0.4, 0.4, 0.30))

	# Cursor highlight.
	if pos == _cursor:
		draw_rect(rect.grow(2), Color.WHITE, false, 2.0)
		# Carried stack rides the cursor: a small icon with a count badge.
		if not _carried.is_empty():
			var cid := String(_carried.get("id", ""))
			draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(cid), Vector2i(16, 16), GameData.resource_color(cid)), Rect2(rect.get_center() - Vector2(8, 8), Vector2(16, 16)), false, Color(1, 1, 1, 0.95))
			var n := int(_carried.get("count", 1))
			if n > 1:
				var b := Rect2(rect.position + Vector2(rect.size.x - 17, rect.size.y - 15), Vector2(15, 13))
				draw_rect(b, Color(0.08, 0.09, 0.12, 0.92))
				draw_rect(b, Color(0.5, 0.8, 1.0), false, 1.0)
				draw_string(_font, b.position + Vector2(2, 11), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.95, 1.0))


func _preview_cells(f: FactoryGrid) -> Dictionary:
	var out := {}
	if not _place_mode or _place_id.is_empty():
		return out
	var id := _place_id
	var afford := _affordable(id)
	if id.begins_with("__"):
		var k := String(f.get_cell(_cursor).get("kind", ""))
		out[_cursor] = (k == "" or k == "resource") and afford
		return out
	var ok := f.can_place_layout(id, _cursor, _place_in_offsets, _place_out_offsets, _place_hold_offsets, _place_body_offsets) and afford
	out[_cursor] = ok
	for offset: Vector2i in _place_in_offsets + _place_out_offsets + _place_hold_offsets + _place_body_offsets:
		out[_cursor + offset] = ok
	return out


func _makes_lines(id: String) -> Array:
	if id == "__conveyor":
		return ["Carries items one cell along its arrow", "(bridges gaps between machines)."]
	if id == "__splitter":
		return ["Sends items alternately to two outputs", "(its arrow + 90° from it)."]
	if id == "__filter":
		return ["One item type turns out the 90° side,", "the rest go straight. Carry an item +", "[Space] on it to set what it filters."]
	var def: Dictionary = GameData.machines.get(id, {})
	if bool(def.get("weapon", false)):
		var ammo := String(def.get("ammo", ""))
		var flavor := ""
		if int(def.get("pellets", 1)) > 1:
			flavor = "  ·  spread x%d" % int(def.get("pellets", 1))
		elif int(def.get("pierce", 0)) > 0:
			flavor = "  ·  pierces %d" % int(def.get("pierce", 0))
		return ["Fires in combat (dmg %d)%s." % [int(def.get("damage", 0)), flavor], "Feed %s into its input slot;" % GameData.resource_name(ammo), "shots draw from there."]
	var cap := int(def.get("capacity", 0))
	if cap > 0:
		return ["Stacks up to %d of one item fed to it." % cap, "Load a full cache at the retrieval pad to", "ship the whole stack in one slot."]
	var lines: Array = []
	for r: Dictionary in GameData.recipes_for(id):
		lines.append("%s → %s" % [_ingredients(r.get("needs", {})), _ingredients(r.get("produces", {}))])
	if lines.is_empty():
		lines.append("Receives harvested items.")
	return lines


func _ingredients(items: Dictionary) -> String:
	var parts: Array = []
	for res: String in items:
		var n := int(items[res])
		parts.append(("%d× %s" % [n, GameData.resource_name(res)]) if n > 1 else GameData.resource_name(res))
	return " + ".join(parts)
