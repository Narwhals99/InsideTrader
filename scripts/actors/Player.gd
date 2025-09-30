extends CharacterBody3D

@export var walk_speed: float = 4.0
@export var run_speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.15
@export var third_person_distance: float = 3.5
@export var third_person_margin: float = 0.2
@export_flags_3d_physics var third_person_collision_mask: int = 1

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
var use_first_person: bool = true
var camera_pitch: float = 0.0

@onready var cam_fp: Camera3D = $Camera3D
@onready var third_person_rig: SpringArm3D = $ThirdPerson
@onready var cam_tp: Camera3D = $ThirdPerson/Camera3D

func _ready() -> void:
	add_to_group("player")
	_ensure_inputs()
	if typeof(Game) != TYPE_NIL:
		use_first_person = bool(Game.player_prefers_first_person)
	camera_pitch = cam_fp.rotation_degrees.x
	_configure_third_person_rig()
	_set_camera_mode(use_first_person, true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_snap_to_spawn_deferred()

func _configure_third_person_rig() -> void:
	if third_person_rig == null:
		return
	third_person_rig.spring_length = third_person_distance
	third_person_rig.margin = third_person_margin
	if third_person_collision_mask > 0:
		third_person_rig.collision_mask = third_person_collision_mask

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_view"):
		_toggle_view_mode()
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-deg_to_rad(event.relative.x * mouse_sensitivity))
		_update_pitch(event.relative.y * mouse_sensitivity)

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

func _toggle_view_mode() -> void:
	_set_camera_mode(not use_first_person)

func _set_camera_mode(first_person: bool, force: bool = false) -> void:
	if not force and first_person == use_first_person:
		return
	use_first_person = first_person

	camera_pitch = clampf(camera_pitch, -80.0, 80.0)

	if use_first_person:
		cam_tp.current = false
		cam_fp.make_current()
		cam_fp.rotation_degrees.x = camera_pitch
		third_person_rig.rotation_degrees.x = 0.0
	else:
		cam_fp.current = false
		cam_tp.make_current()
		third_person_rig.rotation_degrees.x = camera_pitch
		cam_fp.rotation_degrees.x = 0.0

	if typeof(Game) != TYPE_NIL:
		Game.player_prefers_first_person = use_first_person

func _update_pitch(mouse_delta: float) -> void:
	camera_pitch = clampf(camera_pitch - mouse_delta, -80.0, 80.0)
	if use_first_person:
		cam_fp.rotation_degrees.x = camera_pitch
	else:
		third_person_rig.rotation_degrees.x = camera_pitch

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
	if not InputMap.has_action("toggle_view"):
		InputMap.add_action("toggle_view")
		var key_v := InputEventKey.new()
		key_v.physical_keycode = KEY_V
		InputMap.action_add_event("toggle_view", key_v)

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
		global_transform.origin = t.origin
		var e: Vector3 = t.basis.get_euler()
		rotation.y = e.y
		cam_fp.rotation_degrees.x = 0.0
		third_person_rig.rotation_degrees.x = 0.0
		camera_pitch = 0.0
		print("[Player] spawned at:", wanted, " yaw=", e.y)
	else:
		print("[Player] spawn NOT found:", wanted)
	Game.next_spawn = ""
