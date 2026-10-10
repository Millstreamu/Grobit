class_name FactoryProcessor
extends Node
## Drives the inventory-factory — now the LAIR WORKSHOP (see docs/DESIGN_SPEC.md §0.1). It refines
## the scrap the colony hauled home (scrap → base materials) and crafts, but ONLY while you're at
## the lair (not driving a run). Out in the field the bot carries a cargo hold, not a live factory;
## hauled scrap drains into the grid on extraction and is refined here, between runs.
##
## PROCESS_MODE_ALWAYS so it keeps ticking while the factory panel is open — you watch recyclers
## chew through your haul as you plan the next run.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not RunState.run_active:
		return
	# The LAIR WORKSHOP (factory) refines only at base — not while driving out on a run.
	if RunState.factory != null and not RunState.driving:
		RunState.factory.tick(delta)
	# The MODULE BAY's processors (ammo press, etc.) run ON THE BOT — at base to pre-fill, and in
	# the field to keep a run going (sustain: ammo/consumables from loaded material). Bay slots are
	# the limiter on how many processors you can carry. (Weapons fire separately via try_fire_weapon.)
	if RunState.bay != null:
		RunState.bay.tick(delta)
