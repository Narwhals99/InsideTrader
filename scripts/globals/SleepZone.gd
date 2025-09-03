# SleepZone.gd
extends Area3D

@export var require_interact: bool = true
@export var wake_spawn: String = ""	# optional Marker3D name to snap to after sleep

var _player_inside: bool = false

func _ready() -> void:
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	if require_interact and not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)

func _on_enter(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		if not require_interact:
			_do_sleep(body)

func _on_exit(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false

func _input(event: InputEvent) -> void:
	if require_interact and _player_inside and event.is_action_pressed("interact"):
		var p := _get_player()
		if p: _do_sleep(p)

func _do_sleep(player: Node) -> void:
	Game.sleep_to_morning()	# day++ and phase=Morning (SunSkyRig updates via signal)
	if wake_spawn != "":
		var root: Node = get_tree().current_scene
		var n: Node = root.find_child(wake_spawn, true, false)
		if n is Node3D and player is Node3D:
			var sp: Node3D = n
			var pl: Node3D = player
			pl.global_transform.origin = sp.global_transform.origin
			# face same yaw as marker
			var e: Vector3 = sp.global_transform.basis.get_euler()
			pl.rotation.y = e.y

func _get_player() -> Node:
	for b in get_overlapping_bodies():
		if b.is_in_group("player"):
			return b
	return null
