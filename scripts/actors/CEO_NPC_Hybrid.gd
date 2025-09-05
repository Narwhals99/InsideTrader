# CEO_NPC_Hybrid.gd
# This preserves ALL your waypoint/schedule logic while adding modular features
extends CharacterBody3D

# ============ KEEP ALL YOUR ORIGINAL MOVEMENT VARS ============
@export var walk_speed: float = 3.0
@export var run_speed: float = 5.0
@export var turn_speed: float = 10.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var state_label: Label3D = $StateLabel

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

# Waypoint walking (YOUR ORIGINAL SYSTEM)
var _wp_nodes: Array[Node3D] = []
var _wp_index: int = 0
var _walking: bool = false
var _current_scene_key: String = ""

# ============ WORLD-CLOCK DRIVER (YOUR ORIGINAL) ============
var __ceo_time_active: bool = false
var __ceo_keepalive: float = 0.0
const __CEOSTATE_TIMEOUT := 0.6

var __ceo_seg_sig: String = ""
var __ceo_poly: Array[Vector3] = []
var __ceo_cumlens: Array[float] = []
var __ceo_total_len: float = 0.0
var __ceo_t0: float = 0.0
var __ceo_t1: float = 0.0
var __ceo_prev_p: float = -1.0
var __ceo_last_scene_key: String = ""
var __ceo_segment_just_set: bool = false

@export var __ceo_face_forward: bool = true
@export var __ceo_height_keep: bool = true
@export var __ceo_smoothing: float = 0.0

# ============ NEW MODULAR COMPONENTS ============
var drunk_system: InsiderDrunkComponent
var _player_near: bool = false

@export_group("Insider Configuration")
@export var npc_name: String = "Mr. Johnson"
@export var npc_id: String = "ceo"
@export var npc_title: String = "CEO"
@export var associated_tickers: Array[String] = ["ACME", "BETA"]
@export var drinks_needed: int = 3
@export var tip_accuracy: float = 0.9

@export_group("Dialogue Lines")
@export var need_drink_lines: Array[String] = [
	"I only discuss business over drinks.",
	"Company policy - no drinks, no insider info.",
	"Get me something from the bar first."
]
@export var tip_intro: String = "Between you and me..."
@export var tip_format: String = "%s is going to make moves tomorrow."
@export var tip_outro: String = "You didn't hear it from me!"

func _ready() -> void:
	add_to_group("ceo_npc")
	add_to_group("ceo")
	add_to_group("insider_npc")
	
	# Setup navigation (YOUR ORIGINAL)
	if nav_agent:
		nav_agent.navigation_finished.connect(_on_navigation_finished)
		nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	# Setup interaction (YOUR ORIGINAL + NEW)
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)
	
	# Setup drunk system (NEW)
	_setup_drunk_system()
	
	print("[CEO_Hybrid] Initialized - preserving schedule/waypoint system")

	# TEST: Simple movement test
	print("[TEST] CEO Hybrid ready, waiting 2 seconds...")
	await get_tree().create_timer(2.0).timeout

	print("[TEST] Testing waypoint system...")
	# If in test scene with markers
	set_waypoints_by_names(PackedStringArray(["CEO_Desk", "CEO_Table"]), "test")

	# Test drunk system
	print("[TEST] Drunk system check - threshold: ", drinks_needed)
	print("[TEST] Associated tickers: ", associated_tickers)
	
func _physics_process(delta: float) -> void:
	# KEEP YOUR ORIGINAL KEEPALIVE
	if __ceo_keepalive > 0.0:
		__ceo_keepalive -= delta
	else:
		__ceo_time_active = false
	
	# YOUR ORIGINAL SELF-DRIVE FALLBACK
	if not __ceo_time_active:
		var brain := _find_autoload("ceobrain")
		var here: String = __scene_key_norm()
		if brain != null and brain.has_method("get_active_segment") and brain.has_method("get_world_seconds"):
			var seg: Dictionary = brain.call("get_active_segment") as Dictionary
			var seg_scene: String = __norm(String(seg.get("scene","")))
			var names: PackedStringArray = seg.get("waypoints", PackedStringArray())
			var t0: float = float(seg.get("t0", 0.0))
			var t1: float = float(seg.get("t1", 0.0))
			var ws: float = float(brain.call("get_world_seconds"))
			
			if here == seg_scene:
				apply_time_segment(here, names, t0, t1, ws)
	
	# YOUR ORIGINAL GRAVITY
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	
	# YOUR ORIGINAL MOVEMENT
	if __ceo_time_active:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_process_waypoint_walk()
	
	# Update label
	if state_label:
		var status: String = "Sched" if __ceo_time_active else ("Walking" if _walking else "Idle")
		var drunk_info = ""
		if drunk_system:
			drunk_info = "Drunk: %d/%d" % [drunk_system.drunk_level, drunk_system.drunk_threshold]
		state_label.text = "CEO: %s | %s" % [status, drunk_info]
	
	move_and_slide()

# ============ KEEP ALL YOUR WAYPOINT METHODS EXACTLY AS IS ============
func set_waypoints_by_names(names: PackedStringArray, scene_key: String = "") -> void:
	_wp_nodes.clear()
	_wp_index = 0
	_current_scene_key = scene_key
	
	var root := get_tree().current_scene
	if root == null:
		_walking = false
		return
	
	for raw in names:
		var node3: Node3D = _resolve_waypoint_with_aliases(root, String(raw))
		if node3 != null:
			_wp_nodes.append(node3)
		else:
			push_warning("[CEO_Hybrid] Waypoint NOT FOUND: '%s'" % String(raw))
	
	if _wp_nodes.size() == 0:
		_walking = false
		return
	
	var first: Node3D = _wp_nodes[0]
	global_transform = first.global_transform
	
	if _wp_nodes.size() > 1:
		_wp_index = 1
		_set_nav_target(_wp_nodes[1].global_position)
		_walking = true
	else:
		_set_nav_target(first.global_position)
		_walking = false

func _process_waypoint_walk() -> void:
	if not _walking or _wp_nodes.size() == 0 or _wp_index >= _wp_nodes.size():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	
	var tgt: Node3D = _wp_nodes[_wp_index]
	if tgt:
		var reached: bool = false
		if nav_agent:
			var target_pos: Vector3 = nav_agent.target_position
			var dist_to_target: float = global_position.distance_to(target_pos)
			var desired: float = ((nav_agent.target_desired_distance) if nav_agent.target_desired_distance > 0.0 else 0.4) + 0.15
			if dist_to_target <= desired or nav_agent.is_navigation_finished():
				reached = true
		else:
			reached = (tgt.global_position - global_position).length() <= 0.5
		
		if reached:
			_wp_index += 1
			if _wp_nodes.size() > _wp_index:
				_set_nav_target(_wp_nodes[_wp_index].global_position)
			else:
				_walking = false
				if typeof(CEOBrain) != TYPE_NIL and CEOBrain.has_method("notify_scene_segment_arrived"):
					CEOBrain.notify_scene_segment_arrived(_current_scene_key)
				return
	
	if nav_agent and _wp_nodes.size() > _wp_index:
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		var dir: Vector3 = (next_pos - global_position).normalized()
		velocity.x = dir.x * walk_speed
		velocity.z = dir.z * walk_speed
		if dir.length() > 0.1:
			var yaw: float = atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(rotation.y, yaw, turn_speed * get_physics_process_delta_time())

# ============ KEEP YOUR WORLD-CLOCK DRIVER EXACTLY ============
func apply_time_segment(scene_key: String, names: PackedStringArray, t0: float, t1: float, ws: float) -> void:
	__ceo_time_active = true
	__ceo_keepalive = __CEOSTATE_TIMEOUT
	
	var seg_sig: String = scene_key + "|" + ",".join(names) + "|" + str(t0) + ">" + str(t1)
	
	if seg_sig != __ceo_seg_sig:
		__ceo_poly = __ceo_resolve_polyline(names)
		__ceo_build_cumlens(__ceo_poly)
		__ceo_total_len = __ceo_cumlens.back() if __ceo_cumlens.size() > 0 else 0.0
		__ceo_t0 = t0
		__ceo_t1 = t1
		__ceo_seg_sig = seg_sig
		__ceo_prev_p = -1.0
		__ceo_last_scene_key = scene_key
		__ceo_segment_just_set = true
		if __ceo_poly.size() > 0:
			global_position = __ceo_poly[0]
	
	if __ceo_poly.is_empty():
		return
	
	var p: float = __ceo_progress(ws, __ceo_t0, __ceo_t1)
	if names.size() <= 1:
		p = 0.0
	
	var target: Vector3 = __ceo_sample_by_frac(__ceo_poly, __ceo_cumlens, __ceo_total_len, p)
	
	if __ceo_height_keep and not __ceo_segment_just_set:
		target.y = global_position.y
	
	if __ceo_smoothing > 0.0:
		var alpha: float = clamp(get_physics_process_delta_time() * __ceo_smoothing, 0.0, 1.0)
		global_position = global_position.lerp(target, alpha)
	else:
		global_position = target
	
	if __ceo_face_forward:
		var nextp: Vector3 = __ceo_sample_by_frac(__ceo_poly, __ceo_cumlens, __ceo_total_len, min(p + 0.01, 1.0))
		var dir: Vector3 = nextp - global_position
		dir.y = 0.0
		if dir.length() > 0.001:
			look_at(global_position + dir.normalized(), Vector3.UP)
	
	__ceo_prev_p = p
	__ceo_segment_just_set = false

# [KEEP ALL YOUR OTHER WORLD-CLOCK METHODS - I won't repeat them all but they stay]

# ============ NEW MODULAR INTERACTION (REPLACES OLD) ============
func _setup_drunk_system() -> void:
	drunk_system = load("res://scripts/components/InsiderDrunkComponent.gd").new()
	drunk_system.name = "DrunkSystem"
	drunk_system.drunk_threshold = drinks_needed
	drunk_system.tip_accuracy = tip_accuracy
	drunk_system.associated_tickers = associated_tickers
	add_child(drunk_system)
	drunk_system.setup(npc_name, associated_tickers)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = true
		print("[CEO_Hybrid] Player entered interaction area")
		EventBus.emit_notification("CEO - Drunk level: %d/%d" % [drunk_system.drunk_level, drunk_system.drunk_threshold], "info", 2.0)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = false

func interact() -> Dictionary:
	if drunk_system.drunk_level < drunk_system.drunk_threshold:
		EventBus.emit_dialogue(npc_name, need_drink_lines[randi() % need_drink_lines.size()])
		return {"success": false, "message": "Need drinks first"}
	else:
		return _give_insider_info()

func give_beer() -> Dictionary:
	if not drunk_system.can_accept_beer():
		EventBus.emit_dialogue(npc_name, "I can't drink anymore...")
		return {"success": false}
	
	var result = drunk_system.give_beer()
	EventBus.emit_dialogue(npc_name, result.get("message", "Thanks!"))
	
	if result.get("gave_tip", false):
		_show_tip_dialogue(result.get("ticker", "ACME"))
	
	return result

func _give_insider_info() -> Dictionary:
	var result = drunk_system.give_insider_tip()
	if result.get("success", false):
		_show_tip_dialogue(result.get("ticker", "ACME"))
	return result

func _show_tip_dialogue(ticker: String) -> void:
	var messages = [
		{"speaker": npc_name, "text": tip_intro},
		{"speaker": npc_name, "text": tip_format % ticker},
		{"speaker": npc_name, "text": tip_outro}
	]
	if typeof(DialogueUI) != TYPE_NIL:
		DialogueUI.show_dialogue_sequence(messages, 2.5)

# ============ KEEP ALL YOUR UTILITY METHODS ============
func _resolve_waypoint_with_aliases(root: Node, raw: String) -> Node3D:
	# [YOUR ORIGINAL CODE STAYS]
	var options: PackedStringArray = raw.split("|", false)
	for opt in options:
		var node: Node = root.get_node_or_null(opt)
		if node and node is Node3D:
			return node
		node = root.find_child(opt, true, false)
		if node and node is Node3D:
			return node
	return null

func _set_nav_target(pos: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = pos

func _on_navigation_finished() -> void:
	if not _walking and _wp_nodes.size() <= 1:
		emit_signal("reached_destination", _current_scene_key)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if nav_agent and nav_agent.avoidance_enabled:
		velocity = safe_velocity

# [KEEP ALL YOUR OTHER HELPER METHODS]

func _find_autoload(name_contains: String) -> Node:
	var want: String = name_contains.strip_edges().to_lower().replace("_","")
	var root := get_tree().get_root()
	for n in root.get_children():
		var nm: String = String(n.name).to_lower().replace("_","")
		if nm.findn(want) != -1:
			return n
	return null

func __scene_key_norm() -> String:
	var cs := get_tree().current_scene
	if cs == null:
		return ""
	var raw: String = cs.name
	return __norm(raw)

func __norm(raw: String) -> String:
	var s: String = raw.strip_edges().to_lower().replace("_","").replace("-","")
	if s == "apartment" or s == "apt" or s == "apartmentlobby":
		return "aptlobby"
	if s == "officelobby" or s == "hq":
		return "office"
	if s == "plaza" or s == "square":
		return "hub"
	if s == "bar":
		return "club"
	return s

# ============ WORLD-CLOCK POLYLINE METHODS (FROM YOUR ORIGINAL) ============
func __ceo_resolve_polyline(names: PackedStringArray) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var root := get_tree().current_scene
	if root == null or names.size() == 0:
		return pts

	for nm in names:
		var picked: Node3D = null
		var raw: String = String(nm)
		var options: PackedStringArray = raw.split("|", false)

		# exact path / name / recursive
		for opt in options:
			var node_any: Node = root.get_node_or_null(opt)
			if node_any == null:
				node_any = root.find_child(opt, true, false)
			var node3: Node3D = node_any as Node3D
			if node3 != null:
				picked = node3
				break

		# case-insensitive + normalized fallback
		if picked == null:
			var opts_norm: Array[String] = []
			for o in options:
				opts_norm.append(o.to_lower().replace("_","").replace("-",""))
			var stack: Array[Node] = [root]
			while not stack.is_empty() and picked == null:
				var cur: Node = stack.pop_back()
				var c3: Node3D = cur as Node3D
				if c3:
					var nm_norm: String = c3.name.to_lower().replace("_","").replace("-","")
					if opts_norm.has(nm_norm):
						picked = c3
						break
				for ch in cur.get_children():
					stack.append(ch)

		if picked != null:
			pts.append(picked.global_transform.origin)
		else:
			push_warning("[CEO_Hybrid] Missing waypoint: " + raw)

	# drop near-duplicates
	var out: Array[Vector3] = []
	for p in pts:
		if out.is_empty() or out.back().distance_squared_to(p) > 0.0001:
			out.append(p)
	return out

func __ceo_build_cumlens(poly: Array[Vector3]) -> void:
	__ceo_cumlens.clear()
	if poly.size() == 0:
		return
	__ceo_cumlens.resize(poly.size())
	__ceo_cumlens[0] = 0.0
	var total: float = 0.0
	for i in range(1, poly.size()):
		total += poly[i].distance_to(poly[i - 1])
		__ceo_cumlens[i] = total

func __ceo_progress(ws: float, t0: float, t1: float) -> float:
	var day: float = 86400.0
	var dur: float = t1 - t0
	if dur < 0.0:
		dur += day
	var off: float = ws - t0
	if off < 0.0:
		off += day
	if dur <= 0.0001:
		return 1.0
	return clamp(off / dur, 0.0, 1.0)

func __ceo_sample_by_frac(poly: Array[Vector3], cum: Array[float], total: float, frac: float) -> Vector3:
	if poly.size() == 0:
		return global_position
	if poly.size() == 1:
		return poly[0]
	var f: float = clamp(frac, 0.0, 1.0)
	if total <= 0.0001:
		return poly.back()
	var target_len: float = total * f
	for i in range(1, poly.size()):
		var a: float = cum[i - 1]
		var b: float = cum[i]
		if target_len <= b:
			var seg_len: float = max(b - a, 0.000001)
			var t: float = (target_len - a) / seg_len
			return poly[i - 1].lerp(poly[i], t)
	return poly.back()
