class_name FactoryProcessor
extends Node
## Drives the inventory-factory in real time (Step 2 of the redesign — see
## docs/SLICE_1_SCOPE.md). Ticks `RunState.factory` every frame.
##
## Runs in PROCESS_MODE_ALWAYS so machines keep processing even while the factory
## panel is open: the panel pauses the tree for planning, but the factory stays
## live, so you watch items flow through it as you rearrange.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if RunState.factory != null:
		RunState.factory.tick(delta)
