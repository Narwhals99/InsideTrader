# InsiderNPC.gd — DROP-IN
# Assumes Godot 4.x
extends CharacterBody3D

@export var npc_id: StringName = &"cfo"
@export var schedule_resource: NPCScheduleResource
@export var movement_speed_override: float = -1.0   # optional: override entry speed
@export var debug_logging: bool = true

# Persisted index restored at _ready()
var _current_entry_index: int = 0
var _active_total_entries: int = 0


# Autoload (Project Settings → Autoload: path res://NPCScheduleStore.gd, Name: ScheduleStore)
@onready var ScheduleStore: NPCScheduleStore = get_node_or_null("/root/ScheduleStore") as NPCScheduleStore

# Movement plumbing
var _movement: Node = null                     # your custom movement component (optional)
var _agent: NavigationAgent3D = null           # fallback runner
var _active_entry: NPCScheduleEntry = null
var _resume_idx: int = 0
var _pts: Array[Vector3] = []
var _using_fallback: bool = false

func _now_secs() -> int:
	var g: Node = get_node_or_null("/root/Game")
	if g != null:
		if g.has_method("get_world_seconds"):
			return int(g.call("get_world_seconds"))
		if "clock_minutes" in g:
			return int(g.get("clock_minutes")) * 60
	return -1

func _ready() -> void:
	# Restore persisted progress (index only; SpawnManager will call start_schedule_entry)
	if schedule_resource and schedule_resource.schedule_entries.size() > 0 and ScheduleStore:
		var p: Dictionary = ScheduleStore.get_progress(npc_id)
		_current_entry_index = clamp(
			int(p.get("entry_index", 0)),
			0,
			schedule_resource.schedule_entries.size() - 1
		)
		_dbg("Restored entry_index=%d" % _current_entry_index)

	# Cache movement component if present
	_movement = null
	if has_node("NPCMovementComponent"):
		_movement = get_node("NPCMovementComponent")
	else:
		for child in get_children():
			# match by class_name if user gave it one
			if child.get_class() == "NPCMovementComponent":
				_movement = child
				break
		if _movement == null and get_tree():
			var list: Array = get_tree().get_nodes_in_group("npc_movement")
			for n in list:
				if n.get_parent() == self:
					_movement = n
					break

	# Connect movement signals (guard duplicates); we accept any of these:
	# waypoint_reached(int i), path_complete(), entry_finished()
	if _movement:
		if _movement.has_signal("waypoint_reached") and has_method("_on_movement_waypoint_reached"):
			var cb_wp := Callable(self, "_on_movement_waypoint_reached")
			if not _movement.is_connected("waypoint_reached", cb_wp):
				_movement.connect("waypoint_reached", cb_wp)
		if _movement.has_signal("path_complete") and has_method("_on_movement_path_complete"):
			var cb_done := Callable(self, "_on_movement_path_complete")
			if not _movement.is_connected("path_complete", cb_done):
				_movement.connect("path_complete", cb_done)
		if _movement.has_signal("entry_finished") and has_method("_on_entry_finished"):
			var cb_entry := Callable(self, "_on_entry_finished")
			if not _movement.is_connected("entry_finished", cb_entry):
				_movement.connect("entry_finished", cb_entry)

	# Fallback agent is created lazily if needed

func start_schedule_entry(entry: NPCScheduleEntry, resume_index: int = 0, total_entries: int = -1) -> void:
	_active_entry = entry
	_resume_idx = max(0, resume_index)
	_active_total_entries = (total_entries if total_entries > 0 else (
		(schedule_resource.schedule_entries.size() if schedule_resource else 0)
	))
	if _active_entry == null:
		_dbg_warn("start_schedule_entry: null entry")
		return

	# Resolve waypoints to world positions
	_pts = _resolve_waypoint_positions(_active_entry.waypoint_names)
	if _pts.size() == 0:
		_dbg_warn("No waypoint nodes found for scene_key=%s waypoints=%s" % [_active_entry.scene_key, str(_active_entry.waypoint_names)])
		return

	# Record "started"
	_mark_entry_started(_resume_idx)

	# Use explicit speed (entry or override)
	var move_speed: float = (movement_speed_override if movement_speed_override > 0.0 else _active_entry.movement_speed)

	# Prefer user movement component
	if _movement:
		_using_fallback = false
		if _movement.has_method("start_waypoint_path"):
			_movement.call("start_waypoint_path", _pts, _resume_idx, move_speed, _active_entry.loop_waypoints)
			_dbg("start_waypoint_path: %d pts, resume=%d, speed=%.2f, total_entries=%d" % [_pts.size(), _resume_idx, move_speed, _active_total_entries])
			return
		if _movement.has_method("start_path"):
			_movement.call("start_path", _pts, _resume_idx, move_speed, _active_entry.loop_waypoints)
			_dbg("start_path: %d pts, resume=%d, speed=%.2f, total_entries=%d" % [_pts.size(), _resume_idx, move_speed, _active_total_entries])
			return
		_dbg_warn("Movement component present but lacks start_* method; falling back.")

	# Fallback: simple NavigationAgent3D runner (unchanged)
	_using_fallback = true
	if _agent == null or not is_instance_valid(_agent):
		_agent = NavigationAgent3D.new()
		add_child(_agent)
		_agent.avoidance_enabled = false
		_agent.path_max_distance = 0.5
		_agent.path_desired_distance = 0.25
	_dbg("Fallback runner engaged. total_entries=%d" % _active_total_entries)
	var idx: int = clamp(_resume_idx, 0, _pts.size() - 1)
	_agent.target_position = _pts[idx]
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _using_fallback or _active_entry == null or _agent == null:
		set_physics_process(false)
		return

	var next: Vector3 = _agent.get_next_path_position()
	var to_next: Vector3 = next - global_position
	if to_next.length() > 0.05:
		var speed: float = (movement_speed_override if movement_speed_override > 0.0 else _active_entry.movement_speed)
		velocity = to_next.normalized() * speed
		move_and_slide()
	else:
		# Close to sub-target; if finished, advance waypoint or finish entry
		if _agent.is_navigation_finished():
			# Find current index in _pts by nearest
			var cur_idx: int = _nearest_index(global_position, _pts)
			_mark_waypoint(cur_idx)
			var next_idx: int = cur_idx + 1
			if next_idx >= _pts.size():
				set_physics_process(false)
				_on_movement_path_complete()  # finish
			else:
				_agent.target_position = _pts[next_idx]

# ---- Movement signal handlers ----
func _on_movement_waypoint_reached(i: int) -> void:
	_mark_waypoint(i)

func _on_movement_path_complete() -> void:
	# Movement done for this entry; advance schedule and despawn (handoff to next scene)
	_mark_entry_complete_and_advance()
	queue_free()

# Some movement components emit "entry_finished" instead of "path_complete"
func _on_entry_finished() -> void:
	_on_movement_path_complete()

# ---- Helpers ----
func _resolve_waypoint_positions(names: PackedStringArray) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var root: Node = get_tree().current_scene
	if root == null:
		return pts
	for nm in names:
		var name_s: String = String(nm)
		if name_s == "":
			continue
		var found: Node = root.find_child(name_s, true, false)
		if found and found is Node3D:
			pts.append((found as Node3D).global_position)
	return pts

func _nearest_index(pos: Vector3, pts: Array[Vector3]) -> int:
	var best_i: int = 0
	var best_d: float = 1e30
	for i in pts.size():
		var d: float = pos.distance_to(pts[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i

func _scene_key() -> StringName:
	if has_node("/root/SceneService"):
		var svc: Node = get_node("/root/SceneService")
		if "current_key" in svc:
			return StringName(svc.current_key)
		if svc.has_method("get_current_key"):
			return StringName(svc.call("get_current_key"))
	if has_node("/root/Scenes"):
		var sc: Node = get_node("/root/Scenes")
		if "current_key" in sc:
			return StringName(sc.current_key)
	var cs: Node = get_tree().current_scene
	if cs != null and cs.scene_file_path != "":
		return StringName(cs.scene_file_path.get_file().get_basename())
	return StringName()

# ---- Persistence hooks ----
func _mark_entry_started(resume_waypoint_i: int = 0) -> void:
	if ScheduleStore == null:
		return
	var scene_key: StringName = _scene_key()
	ScheduleStore.mark_started(npc_id, scene_key, resume_waypoint_i)

	# record runtime so we can continue while off-screen
	var speed: float = (movement_speed_override if movement_speed_override > 0.0 else _active_entry.movement_speed)
	var started_at: int = _now_secs()
	ScheduleStore.mark_entry_runtime(npc_id, speed, _active_entry.waypoint_names, started_at)


func _mark_waypoint(i: int) -> void:
	if ScheduleStore == null:
		return
	var scene_key: StringName = _scene_key()
	ScheduleStore.mark_position(npc_id, scene_key, global_position, i)
	if debug_logging:
		_dbg("Reached waypoint %d @ %s" % [i, str(global_position)])

func _mark_entry_complete_and_advance() -> void:
	if ScheduleStore == null:
		return
	var total: int = _active_total_entries
	ScheduleStore.complete_and_advance(npc_id, total)
	if debug_logging:
		_dbg("Entry complete; advanced index (total=%d)" % total)


# ---- Logging ----
func _dbg(msg: String) -> void:
	if debug_logging:
		print("[InsiderNPC] ", msg)

func _dbg_warn(msg: String) -> void:
	push_warning("[InsiderNPC] " + msg)
	if debug_logging:
		print("[InsiderNPC][WARN] ", msg)
