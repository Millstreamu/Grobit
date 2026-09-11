class_name ResourceCounter
extends Node

var scrap_metal := 0
@onready var label: Label = $ScrapLabel


func _ready() -> void:
	add_to_group("resource_counter")
	_update_label()


func add_scrap_metal(amount: int) -> void:
	scrap_metal += amount
	_update_label()


func _update_label() -> void:
	label.text = "Scrap metal: %d" % scrap_metal
