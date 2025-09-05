# CEO_NPC.gd – Godot 4 (FIXED: waypoint alias resolution)
extends CharacterBody3D

signal drunk_level_changed(level: int)
signal insider_info_given(ticker: StringName)
signal reached_destination(location: String)

# ---------- Movement ----------
@export var walk_speed: float = 3.0
@export var run_speed: float = 5.0
@export var turn_speed: float = 10.0

# ---------- Drunk system ----------
@export var drunk_threshold: int = 3
@export var max_drunk_level: int = 5
@export var sober_up_time: float = 120.0
@export var insider_boost_pct: float = 0.05
@export var insider_certainty: float = 0.9

# Optional idle target
@export var idle_target: NodePath

# ---------- Nodes ----------
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var state_label: Label3D = $StateLabel

# ---------- Vars ----------
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

var drunk_level: int = 0
var _sober_timer: float = 0.0
var _player_near: bool = false
var _has_given_tip_today: bool = false
var _planned_ticker: StringName = &""

# Waypoint walking (manual, legacy)
var _wp_nodes: Array[Node3D] = []
var _wp_index: int = 0
var _walking: bool = false
var _current_scene_key: String = ""

# ================== WORLD-CLOCK DRIVER ==================
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
var __ceo_last_scene_key: String = ""     # scene key passed to apply_time_segment
var __ceo_segment_just_set: bool = false

@export var __ceo_face_forward: bool = true
@export var __ceo_height_keep: bool = true
@export var __ceo_smoothing: float = 0.0
# ========================================================

func _ready() -> void:
	add_to_group("ceo_npc")
	add_to_group("ceo")  # compat for systems that search 'ceo' instead of 'ceo_npc'

	if nav_agent:
		nav_agent.navigation_finished.connect(_on_navigation_finished)
		nav_agent.velocity_computed.connect(_on_velocity_computed)

	if interaction_area:
		var c_enter := Callable(self, "_on_body_entered")
		if not interaction_area.body_entered.is_connected(c_enter):
			interaction_area.body_entered.connect(c_enter)

		var c_exit := Callable(self, "_on_body_exited")
		if not interaction_area.body_exited.is_connected(c_exit):
			interaction_area.body_exited.connect(c_exit)
				# Ensure our Area monitors the Player’s layers (model swaps often break this)
		var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
		if player:
			interaction_area.collision_mask = 0
			for bit in range(1, 33): # Godot 4 uses 1..32
				if player.get_collision_layer_value(bit):
					interaction_area.set_collision_mask_value(bit, true)



func _physics_process(delta: float) -> void:
	# keepalive for schedule driver
	if __ceo_keepalive > 0.0:
		__ceo_keepalive -= delta
	else:
		__ceo_time_active = false

	# --------- SELF-DRIVE FALLBACK (autoload-agnostic + loud on-screen debug) ---------
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

			# On-screen status BEFORE any overwrite below
			if state_label:
				var status: String = "Sched" if __ceo_time_active else ("Walking" if _walking else "Idle")
				var wp_info: String = str(_wp_index) + "/" + str(_wp_nodes.size())
				var poly_info: String = "Poly=" + str(__ceo_poly.size())
				var here2: String = __scene_key_norm()
				var seg2: String = __ceo_last_scene_key
				state_label.text = "CEO: %s | WP %s | %s | Here=%s Seg=%s" % [status, wp_info, poly_info, here2, seg2]

			if here == seg_scene:
				apply_time_segment(here, names, t0, t1, ws)
	# ----------------------------------------------------------------------------------

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Legacy walker only if schedule driver isn't active
	if __ceo_time_active:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_process_waypoint_walk()

	# Drunk ticking
	if drunk_level > 0:
		_sober_timer += delta
		if _sober_timer >= sober_up_time:
			_sober_timer = 0.0
			if drunk_level > 0:
				drunk_level -= 1
				emit_signal("drunk_level_changed", drunk_level)
				if typeof(DialogueUI) != TYPE_NIL:
					DialogueUI.notify("CEO is sobering up... Level: " + str(drunk_level), "info", 2.0)

	# FINAL label (does NOT hide missing-WP info; shows poly count + here/seg)
	if state_label:
		var status: String = "Sched" if __ceo_time_active else ("Walking" if _walking else "Idle")
		var wp_info: String = str(_wp_index) + "/" + str(_wp_nodes.size())
		var poly_info: String = "Poly=" + str(__ceo_poly.size())
		var here2: String = __scene_key_norm()
		var seg2: String = __ceo_last_scene_key
		state_label.text = "CEO: %s | WP %s | %s | Here=%s Seg=%s" % [status, wp_info, poly_info, here2, seg2]

	move_and_slide()

# ---------------- WAYPOINT API (legacy/local walker; FIXED) ----------------
func set_waypoints_by_names(names: PackedStringArray, scene_key: String = "") -> void:
	_wp_nodes.clear()
	_wp_index = 0
	_current_scene_key = scene_key

	var root := get_tree().current_scene
	if root == null:
		_walking = false
		return

	# FIXED: Handle pipe-separated aliases in waypoint names
	for raw in names:
		var node3: Node3D = _resolve_waypoint_with_aliases(root, String(raw))
		if node3 != null:
			_wp_nodes.append(node3)
		else:
			push_warning("[CEO_NPC] Waypoint NOT FOUND in scene '%s': '%s'" % [scene_key, String(raw)])

	if _wp_nodes.size() == 0:
		_walking = false
		if state_label:
			state_label.text = "CEO: Idle | WP 0/0 | NO WPs FOUND (%s)" % [",".join(names)]
		return

	# Hard-snap to the first waypoint's transform (avoids wrong-floor spawn)
	var first: Node3D = _wp_nodes[0]
	global_transform = first.global_transform

	# Walk if there's somewhere to go
	if _wp_nodes.size() > 1:
		_wp_index = 1
		_set_nav_target(_wp_nodes[1].global_position)
		_walking = true
	else:
		_set_nav_target(first.global_position)
		_walking = false

	_debug_nav_probe()
	_validate_waypoints(names)

# NEW: Resolve waypoint with pipe-separated aliases (for legacy walker)
func _resolve_waypoint_with_aliases(root: Node, raw: String) -> Node3D:
	var options: PackedStringArray = raw.split("|", false)
	
	for opt in options:
		# Try exact path first
		var node: Node = root.get_node_or_null(opt)
		if node and node is Node3D:
			return node as Node3D
		
		# Try recursive find
		node = root.find_child(opt, true, false)
		if node and node is Node3D:
			return node as Node3D
	
	# Try normalized matching for all options
	for opt in options:
		var norm_opt: String = _norm_name(opt)
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is Node3D:
				if _norm_name(cur.name) == norm_opt:
					return cur as Node3D
			for c in cur.get_children():
				stack.append(c)
	
	return null

func clear_waypoints() -> void:
	_wp_nodes.clear()
	_wp_index = 0
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
				emit_signal("reached_destination", _current_scene_key)
				if typeof(CEOBrain) != TYPE_NIL and CEOBrain.has_method("notify_scene_segment_arrived"):
					CEOBrain.notify_scene_segment_arrived(_current_scene_key)
				return

	# movement
	if nav_agent and _wp_nodes.size() > _wp_index:
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		var dir: Vector3 = (next_pos - global_position).normalized()
		velocity.x = dir.x * walk_speed
		velocity.z = dir.z * walk_speed
		if dir.length() > 0.1:
			var yaw: float = atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(rotation.y, yaw, turn_speed * get_physics_process_delta_time())
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func _set_nav_target(pos: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = pos

func _on_navigation_finished() -> void:
	if not _walking and _wp_nodes.size() <= 1:
		emit_signal("reached_destination", _current_scene_key)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if nav_agent and nav_agent.avoidance_enabled:
		velocity = safe_velocity

func _node3d(p: NodePath) -> Node3D:
	if p.is_empty():
		return null
	var n: Node = get_node_or_null(p)
	return (n as Node3D) if (n and n is Node3D) else null

# ---------------- INTERACTION (kept) ----------------
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = true
		print("[CEO] player entered interaction area")
		
		if typeof(DialogueUI) != TYPE_NIL:
			var status: String = "CEO - Drunk level: " + str(drunk_level) + "/" + str(drunk_threshold)
			DialogueUI.notify(status, "info", 2.0)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = false

func interact() -> Dictionary:
	if drunk_level < drunk_threshold:
		var beers_needed: int = drunk_threshold - drunk_level
		if typeof(DialogueUI) != TYPE_NIL:
			DialogueUI.show_npc_dialogue("CEO", "Buy me a drink first, will ya?")
			DialogueUI.notify("Needs " + str(beers_needed) + " beer(s)", "warning", 2.0)
		return {"success": false, "message": "Buy me a drink first, will ya?", "hint": "Needs " + str(beers_needed) + " beer(s)"}
	else:
		return _give_insider_info()

func give_beer() -> Dictionary:
	if drunk_level >= max_drunk_level:
		if typeof(DialogueUI) != TYPE_NIL:
			DialogueUI.show_npc_dialogue("CEO", "I can't... *hiccup* ...drink anymore... come back tomorrow...")
		return {"success": false, "message": "He's had enough... maybe tomorrow."}


	drunk_level += 1
	_sober_timer = 0.0
	emit_signal("drunk_level_changed", drunk_level)

	if typeof(DialogueUI) != TYPE_NIL:
		DialogueUI.notify("CEO drunk level: " + str(drunk_level) + "/" + str(drunk_threshold), "info", 2.0)

	if drunk_level >= drunk_threshold and not _has_given_tip_today:
		return _give_insider_info()
	elif drunk_level < drunk_threshold:
		var beers_needed_2: int = drunk_threshold - drunk_level
		if typeof(DialogueUI) != TYPE_NIL:
			var responses: Array[String] = [
				"Thanks for the drink! *takes a sip*",
				"You're a real pal, you know that? *hiccup*",
				"One more and I might tell you something interesting..."
			]
			if drunk_level > 0 and drunk_level <= responses.size():
				DialogueUI.show_npc_dialogue("CEO", responses[drunk_level - 1])
				DialogueUI.notify("Needs " + str(beers_needed_2) + " more beer(s)", "warning", 2.0)
		return {"success": true, "message": "Thanks for the drink!", "hint": "Needs " + str(beers_needed_2) + " more beer(s)..."}

	if typeof(DialogueUI) != TYPE_NIL:
		var messages: Array[Dictionary] = [
			{"speaker": "CEO", "text": "Listen... *leans in conspiratorially*"},
			{"speaker": "CEO", "text": "I heard " + String(_get_random_ticker()) + " is gonna make BIG moves tomorrow."},
			{"speaker": "CEO", "text": "Don't tell anyone I told you!"}
		]
		DialogueUI.show_dialogue_sequence(messages, 2.5)
	return {"success": true, "message": "I've said too much already..."}

func _give_insider_info() -> Dictionary:
	if _has_given_tip_today:
		if typeof(DialogueUI) != TYPE_NIL:
			DialogueUI.show_npc_dialogue("CEO", "I've said too much already... *looks around nervously*")
		return {"success": false, "message": "I've said too much already..."}

	_has_given_tip_today = true

	var is_accurate: bool = randf() <= insider_certainty
	var ticker_to_reveal: StringName
	if is_accurate and _planned_ticker != &"":
		ticker_to_reveal = _planned_ticker
	else:
		ticker_to_reveal = _get_random_ticker()

	_schedule_insider_move(ticker_to_reveal, is_accurate)

	if typeof(InsiderInfo) != TYPE_NIL:
		InsiderInfo.add_move_tomorrow_tip(String(ticker_to_reveal), "Move expected tomorrow for " + String(ticker_to_reveal))

	emit_signal("insider_info_given", ticker_to_reveal)

	if typeof(DialogueUI) != TYPE_NIL:
		var messages2: Array[Dictionary] = [
			{"speaker": "CEO", "text": "Listen... *leans in conspiratorially*"},
			{"speaker": "CEO", "text": "I heard " + String(ticker_to_reveal) + " is gonna make BIG moves tomorrow."},
			{"speaker": "CEO", "text": "Don't tell anyone I told you!"}
		]
		DialogueUI.show_dialogue_sequence(messages2, 2.5)
		DialogueUI.show_insider_tip(String(ticker_to_reveal))

	return {
		"success": true,
		"message": "Listen... I heard " + String(ticker_to_reveal) + " is gonna make big moves tomorrow.",
		"ticker": ticker_to_reveal,
		"is_tip": true
	}

func _roll_insider_info() -> void:
	if typeof(MarketSim) != TYPE_NIL and MarketSim.symbols.size() > 0:
		var idx: int = randi() % MarketSim.symbols.size()
		_planned_ticker = MarketSim.symbols[idx]
		print("[CEO] Insider info rolled for tomorrow: ", _planned_ticker)

func _get_random_ticker() -> StringName:
	if typeof(MarketSim) != TYPE_NIL and MarketSim.symbols.size() > 0:
		var idx: int = randi() % MarketSim.symbols.size()
		return MarketSim.symbols[idx]
	return &"ACME"

func _schedule_insider_move(ticker: StringName, is_accurate: bool) -> void:
	if typeof(MarketSim) == TYPE_NIL:
		return
	if not MarketSim.has_method("force_next_mover"):
		push_warning("[CEO] MarketSim needs force_next_mover() method")
		return
	var move_size: float = insider_boost_pct if is_accurate else MarketSim.mover_target_max_pct
	MarketSim.call("force_next_mover", ticker, move_size)
	print("[CEO] Scheduled ", ticker, " as tomorrow's mover (", move_size * 100.0, "% target)")

# ---------------- SAVE/LOAD ----------------
func get_save_data() -> Dictionary:
	return {
		"drunk_level": drunk_level,
		"has_given_tip": _has_given_tip_today,
		"planned_ticker": _planned_ticker,
		"sober_timer": _sober_timer
	}

func load_save_data(data: Dictionary) -> void:
	drunk_level = data.get("drunk_level", 0)
	_has_given_tip_today = data.get("has_given_tip", false)
	_planned_ticker = data.get("planned_ticker", &"")
	_sober_timer = data.get("sober_timer", 0.0)

# ---------------- Utilities ----------------
func ground_to_floor(max_drop: float = 5.0) -> void:
	var pos: Vector3 = global_position

	if nav_agent:
		var map: RID = nav_agent.get_navigation_map()
		if map.is_valid():
			var nav_pos: Vector3 = NavigationServer3D.map_get_closest_point(map, pos)
			pos.y = nav_pos.y

	var space := get_world_3d().direct_space_state
	var from: Vector3 = pos + Vector3(0, 1.5, 0)
	var to: Vector3 = pos - Vector3(0, max_drop, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [self]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(q)
	if hit.has("position"):
		pos.y = (hit["position"] as Vector3).y

	global_position = pos

func _snap_to_nav_y() -> void:
	if nav_agent == null:
		return
	var map: RID = nav_agent.get_navigation_map()
	if not map.is_valid():
		return
	var p: Vector3 = global_position
	var nav_p: Vector3 = NavigationServer3D.map_get_closest_point(map, p)
	if abs(nav_p.y - p.y) <= 0.5:
		p.y = nav_p.y
		global_position = p

func _validate_waypoints(names: PackedStringArray, tolerance: float = 0.25) -> void:
	if nav_agent == null:
		return
	var map: RID = nav_agent.get_navigation_map()
	if not map.is_valid():
		return
	var root := get_tree().current_scene
	for nm in names:
		# Handle pipe-separated aliases
		var node3: Node3D = _resolve_waypoint_with_aliases(root, String(nm))
		if node3:
			var pos2: Vector3 = node3.global_position
			var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, pos2)
			var d: float = pos2.distance_to(closest)
			if d > tolerance:
				push_warning("[CEO] Waypoint '%s' is off navmesh by %.2fm" % [nm, d])

func _debug_nav_probe() -> void:
	if nav_agent == null:
		return
	var map: RID = nav_agent.get_navigation_map()
	if map.is_valid():
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, global_position)
		var dist: float = global_position.distance_to(closest)
		var dist3: float = snapped(dist, 0.001)
		print("[nav] dist_to_nav=", str(dist3), "  pos=", global_position, "  closest=", closest)

# ================== WORLD-CLOCK DRIVER API ==================
func apply_time_segment(scene_key: String, names: PackedStringArray, t0: float, t1: float, ws: float) -> void:
	__ceo_time_active = true
	__ceo_keepalive = __CEOSTATE_TIMEOUT

	var seg_sig: String = scene_key + "|" + ",".join(names) + "|" + str(t0) + ">" + str(t1)

	# Rebuild polyline only when segment changes
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
		# Hard-snap on new segment to the first waypoint (correct floor)
		if __ceo_poly.size() > 0:
			global_position = __ceo_poly[0]

	# Loud feedback if nothing resolved
	if __ceo_poly.is_empty():
		if state_label:
			state_label.text = "CEO: Sched | WP 0/0 | Poly=0 | NO WPs (" + ",".join(names) + ")"
		push_warning("[CEO_NPC] Poly build empty for scene_key='" + scene_key + "' names=(" + ",".join(names) + ")")
		return

	# Optional: display current scheduling status on the label
	if state_label:
		var mode := ("IDLE" if names.size() <= 1 else "MOVE")
		state_label.text = "CEO: Sched-" + mode + " | Poly=" + str(__ceo_poly.size()) + " | Here=" + __ceo_last_scene_key + " Seg=" + scene_key

	# Compute progress along segment (idle segments will clamp to start)
	var p: float = __ceo_progress(ws, __ceo_t0, __ceo_t1)
	if names.size() <= 1:
		p = 0.0

	var target: Vector3 = __ceo_sample_by_frac(__ceo_poly, __ceo_cumlens, __ceo_total_len, p)

	# Keep height only AFTER the initial hard-snap to avoid cross-floor snapping
	if __ceo_height_keep and not __ceo_segment_just_set:
		target.y = global_position.y

	# Move
	if __ceo_smoothing > 0.0:
		var alpha: float = clamp(get_physics_process_delta_time() * __ceo_smoothing, 0.0, 1.0)
		global_position = global_position.lerp(target, alpha)
	else:
		global_position = target

	# Face travel direction
	if __ceo_face_forward:
		var nextp: Vector3 = __ceo_sample_by_frac(__ceo_poly, __ceo_cumlens, __ceo_total_len, min(p + 0.01, 1.0))
		var dir: Vector3 = nextp - global_position
		dir.y = 0.0
		if dir.length() > 0.001:
			look_at(global_position + dir.normalized(), Vector3.UP)

	# Fire reached once at end of moving legs
	if names.size() > 1 and __ceo_last_scene_key == scene_key and __ceo_prev_p >= 0.0 and __ceo_prev_p < 0.999 and p >= 0.999:
		emit_signal("reached_destination", scene_key)
		if typeof(CEOBrain) != TYPE_NIL and CEOBrain.has_method("notify_scene_segment_arrived"):
			CEOBrain.notify_scene_segment_arrived(scene_key)

	__ceo_prev_p = p
	__ceo_segment_just_set = false

# ---- world-driver helpers ----
# Accepts alias strings like "Apt_Door|Apartment_Door|AptDoor"
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
			push_warning("[CEO_NPC] Missing waypoint (aliases tried): " + raw)

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

# ---- autoload + scene-key helpers ----
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

# Finds a Node3D by exact path, then recursive name, then case-insensitive,
# then normalized (underscores/dashes/spaces removed). Returns null if not found.
func _find_node3d_best(root: Node, needle: String) -> Node3D:
	# 1) exact path
	var n: Node = root.get_node_or_null(needle)
	if n and n is Node3D:
		return n as Node3D

	# 2) exact name (recursive)
	var f: Node = root.find_child(needle, true, false)
	if f and f is Node3D:
		return f as Node3D

	# 3) case-insensitive exact name
	var needle_l: String = needle.to_lower()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		var c3: Node3D = cur as Node3D
		if c3 and c3.name.to_lower() == needle_l:
			return c3
		for c in cur.get_children():
			stack.append(c)

	# 4) normalized match (remove "_", "-", " ")
	var norm: String = _norm_name(needle)
	stack = [root]
	while not stack.is_empty():
		var cur2: Node = stack.pop_back()
		var c32: Node3D = cur2 as Node3D
		if c32 and _norm_name(c32.name) == norm:
			return c32
		for c in cur2.get_children():
			stack.append(c)

	return null

func _norm_name(s: String) -> String:
	return s.to_lower().replace("_","").replace("-","").replace(" ","")

func _repair_interaction_area() -> void:
	# Find or create the Area3D
	var area := get_node_or_null("InteractionArea") as Area3D
	if area == null:
		area = Area3D.new()
		area.name = "InteractionArea"
		add_child(area)
	interaction_area = area

	# Make sure it’s monitoring
	interaction_area.monitoring = true
	interaction_area.monitorable = true

	# Ensure a usable collision shape (~1.6 m radius bubble)
	var cs := interaction_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		cs = CollisionShape3D.new()
		interaction_area.add_child(cs)
	if cs.shape == null:
		var sph := SphereShape3D.new()
		sph.radius = 1.6
		cs.shape = sph
	elif cs.shape is SphereShape3D and (cs.shape as SphereShape3D).radius < 0.8:
		(cs.shape as SphereShape3D).radius = 1.6

	# Make sure we actually detect the Player’s body
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player:
		interaction_area.collision_mask = 0
		for bit in range(1, 33): # physics layers are 1..32 in Godot 4
			if player.get_collision_layer_value(bit):
				interaction_area.set_collision_mask_value(bit, true)

	# Reconnect signals if needed (Godot 4: use Callable)
	var c_enter := Callable(self, "_on_body_entered")
	var c_exit  := Callable(self, "_on_body_exited")
	if not interaction_area.body_entered.is_connected(c_enter):
		interaction_area.body_entered.connect(c_enter)
	if not interaction_area.body_exited.is_connected(c_exit):
		interaction_area.body_exited.connect(c_exit)
