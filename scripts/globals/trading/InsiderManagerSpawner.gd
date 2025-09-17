extends Node

var manager_scene: PackedScene = preload("res://scenes/globals/trading/MarketSim.tscn")
var manager_instance: Node = null

func _ready() -> void:
	print("[InsiderInfo] Autoload ready")

func ensure_spawned() -> void:
	if manager_instance and is_instance_valid(manager_instance):
		return
	if manager_scene == null:
		push_error("[InsiderInfo] manager_scene missing")
		return
	manager_instance = manager_scene.instantiate()
	get_tree().get_root().add_child(manager_instance)
	print("[InsiderInfo] Manager scene spawned")

func _process(_delta: float) -> void:
	ensure_spawned()
