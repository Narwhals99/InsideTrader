extends CharacterBody3D

@export var walk_speed: float = 4.0
@export var run_speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.15

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
@onready var cam: Camera3D = $Camera3D

func _ready() -> void:
	add_to_group("player")
	cam.make_current()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_ensure_inputs()
	_snap_to_spawn_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-deg_to_rad(event.relative.x * mouse_sensitivity))		# yaw
		cam.rotate_x(-deg_to_rad(event.relative.y * mouse_sensitivity))	# pitch
		cam.rotation_degrees.x = clampf(cam.rotation_degrees.x, -80.0, 80.0)

	if event.is_action_pressed("ui_cancel"):
		var m: int = Input.get_mouse_mode()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if m == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var x: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var z: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	var input_vec: Vector2 = Vector2(x, z).normalized()

	var f: Vector3 = -global_transform.basis.z
	var r: Vector3 = global_transform.basis.x
	var dir: Vector3 = (r * input_vec.x + f * input_vec.y).normalized()

	var speed: float = (run_speed if Input.is_action_pressed("run") else walk_speed)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	move_and_slide()

func _ensure_inputs() -> void:
	var map := {
		"move_forward": [KEY_W, KEY_UP],
		"move_backward": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT],
		"jump": [KEY_SPACE],
	}
	for a in map.keys():
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			for k in map[a]:
				var e := InputEventKey.new()
				e.physical_keycode = k
				InputMap.action_add_event(a, e)
	if not InputMap.has_action("ui_cancel"):
		InputMap.add_action("ui_cancel")
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("ui_cancel", esc)

func _snap_to_spawn_deferred() -> void:
	if Game.next_spawn == "":
		return
	await get_tree().process_frame
	var wanted: String = Game.next_spawn
	var root: Node = get_tree().current_scene
	var found: Node = root.find_child(wanted, true, false)
	if found is Node3D:
		var sp: Node3D = found
		var t: Transform3D = sp.global_transform
		# position
		global_transform.origin = t.origin
		# face same yaw as marker (its -Z forward)
		var e: Vector3 = t.basis.get_euler()
		rotation.y = e.y
		$Camera3D.rotation.x = 0.0
		print("[Player] spawned at:", wanted, " yaw=", e.y)
	else:
		print("[Player] spawn NOT found:", wanted)
	Game.next_spawn = ""
