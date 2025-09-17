extends Node

signal npc_spawned(npc_id: StringName, npc: Node)
signal npc_despawned(npc_id: StringName)

@export var managed_npcs: Array[Dictionary] = [
	{
		"id": "cfo",
		"scene_path": "res://scenes/actors/CFO_NPC.tscn",
		"schedule_path": "res://resources/schedules/cfo_schedule.tres"
	}
]

var _spawned: Dictionary = {}     # id:StringName -> Node
var _schedules: Dictionary = {}   # id:StringName -> NPCScheduleResource
var _last_scene_key: StringName = StringName()
var _poll_accum: float = 0.0
@export var poll_interval_sec: float = 0.5

# Autoload name is **ScheduleStore** (autoload path: res://NPCScheduleStore.gd, Name: ScheduleStore)
@onready var ScheduleStore: NPCScheduleStore = get_node_or_null("/root/ScheduleStore") as NPCScheduleStore

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	if ScheduleStore == null:
		push_error("[NPCSpawnManager] Autoload '/root/ScheduleStore' not found.")
	_preload_schedules()
	_last_scene_key = _get_current_scene_key()
	_respawn_for_scene(_last_scene_key)

func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < poll_interval_sec:
		return
	_poll_accum = 0.0

	var now_key: StringName = _get_current_scene_key()
	if now_key != _last_scene_key:
		_last_scene_key = now_key
		_respawn_for_scene(now_key)

	# Keep NPC schedules in-sync with world time, even off-screen
	_check_time_fast_forward()
	# If an NPC is spawned but waiting for time, start them the moment clock reaches departure
	_check_time_gated_starts(_last_scene_key)

func refresh_now() -> void:
	_respawn_for_scene(_get_current_scene_key())

func _preload_schedules() -> void:
	for cfg in managed_npcs:
		if not cfg.has("id"):
			continue
		var id: StringName = StringName(cfg["id"])
		var path: String = String(cfg.get("schedule_path", ""))
		if path != "":
			var res: Resource = load(path)
			if res is NPCScheduleResource:
				_schedules[id] = res as NPCScheduleResource

func _get_current_scene_key() -> StringName:
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

func _world_seconds() -> int:
	# Prefer Game autoload if present
	var g: Node = get_node_or_null("/root/Game")
	if g != null:
		if g.has_method("get_world_seconds"):
			return int(g.call("get_world_seconds"))
		# Common fallback fields on your Game.gd
		if g.has_method("get_hour") and g.has_method("get_minute"):
			return int(g.call("get_hour")) * 3600 + int(g.call("get_minute")) * 60
		if "clock_minutes" in g:
			return int(g.get("clock_minutes")) * 60

	# Try TimeService if you use it
	var ts: Node = get_node_or_null("/root/TimeService")
	if ts != null:
		if ts.has_method("get_world_seconds"):
			return int(ts.call("get_world_seconds"))
		if ts.has_method("get_time_seconds"):
			return int(ts.call("get_time_seconds"))
		if ts.has_method("get_total_seconds"):
			return int(ts.call("get_total_seconds"))
		# Common fallbacks
		var hh_v = ts.get("hour")
		var mm_v = ts.get("minute")
		if hh_v != null and mm_v != null:
			return int(hh_v) * 3600 + int(mm_v) * 60

	# Unknown time source → return -1 so we don't soft-lock gating
	return -1


func _respawn_for_scene(this_key: StringName) -> void:
	# Despawn anything that no longer belongs in this scene
	var keys: Array = _spawned.keys()
	for id_any in keys:
		var id: StringName = StringName(id_any)
		var entry_here: NPCScheduleEntry = _entry_for(id, this_key)
		if entry_here == null:
			_despawn(id)

	# Spawn anything that should be here and isn't
	for cfg in managed_npcs:
		var id2: StringName = StringName(cfg["id"])
		if _spawned.has(id2):
			continue
		# Off-screen fast-forward before selecting entry
		_fast_forward_index_to_time(id2)
		var entry: NPCScheduleEntry = _entry_for(id2, this_key)
		if entry == null:
			continue
		_spawn_npc_for_entry(id2, cfg, entry)

func _entry_for(npc_id: StringName, this_key: StringName) -> NPCScheduleEntry:
	var sched_any: Variant = _schedules.get(npc_id, null)
	var sched: NPCScheduleResource = sched_any as NPCScheduleResource
	if sched == null or sched.schedule_entries.size() == 0:
		return null
	var p: Dictionary = _progress_for(npc_id)
	var entry_index: int = clamp(int(p.get("entry_index", 0)), 0, sched.schedule_entries.size() - 1)
	var entry: NPCScheduleEntry = sched.schedule_entries[entry_index]
	if StringName(entry.scene_key) != this_key:
		return null
	return entry

func _spawn_npc_for_entry(npc_id: StringName, cfg: Dictionary, entry: NPCScheduleEntry) -> void:
	var scene_path: String = String(cfg["scene_path"])
	var packed_res: Resource = load(scene_path)
	var packed: PackedScene = packed_res as PackedScene
	if packed == null:
		push_warning("[NPCSpawnManager] Could not load scene for %s" % [npc_id])
		return

	var npc: Node = packed.instantiate() as Node
	_spawned[npc_id] = npc

	# Parent to current scene
	var root: Node = get_tree().current_scene
	if root == null:
		add_child(npc)
	else:
		root.add_child(npc)

	# Clean stale refs if NPC frees itself
	npc.tree_exited.connect(_on_npc_tree_exited.bind(npc_id))

	# Position: 1) persisted  2) spawn marker  3) first waypoint
	var p: Dictionary = _progress_for(npc_id)
	var last_scene: StringName = StringName(p.get("last_scene", StringName()))
	var last_pos: Vector3 = p.get("last_position", Vector3.ZERO)
	
	# Off-screen continuation: if this entry already started earlier, place along path
	
	var predicted: Dictionary = _predict_progress(npc_id, entry)
	if predicted.has("pos") and npc is Node3D:
		(npc as Node3D).global_position = predicted["pos"]

	var placed: bool = false
	if last_scene == _last_scene_key and last_pos != Vector3.ZERO and npc is Node3D:
		(npc as Node3D).global_position = last_pos
		placed = true

	if not placed:
		var spot: Node3D = _find_spawn_marker(root, npc_id)
		if spot and npc is Node3D:
			(npc as Node3D).global_transform = spot.global_transform
			placed = true

	if not placed:
		var wp0: Node3D = _first_waypoint_node(root, entry)
		if wp0 and npc is Node3D:
			(npc as Node3D).global_position = wp0.global_position
			placed = true

	# Don’t start yet if the entry is time-gated and we’re early
	_maybe_start_spawned_npc(npc_id, npc, entry)

	emit_signal("npc_spawned", npc_id, npc)

# ---------- Time/Away syncing ----------

func _check_time_fast_forward() -> void:
	# Only fast-forward NPCs that are NOT currently spawned in the scene.
	for cfg in managed_npcs:
		if not cfg.has("id"):
			continue
		var id: StringName = StringName(cfg["id"])
		if _spawned.has(id):
			# DEBUG
			# print("[FF] skip (spawned) npc=", id)
			continue
		_fast_forward_index_to_time(id)


func _fast_forward_index_to_time(npc_id: StringName) -> void:
	if ScheduleStore == null:
		return
	var sched_any: Variant = _schedules.get(npc_id, null)
	var sched: NPCScheduleResource = sched_any as NPCScheduleResource
	if sched == null:
		return

	var p: Dictionary = _progress_for(npc_id)
	var idx: int = int(p.get("entry_index", 0))
	var now: int = _world_seconds()
	var advanced: bool = false

	# Advance past time-gated entries only if their departure time has already passed.
	# (Off-screen catch-up; do NOT simulate travel while away.)
	while idx < sched.schedule_entries.size() - 1:
		var e: NPCScheduleEntry = sched.schedule_entries[idx]
		var gate: bool = bool(e.wait_for_time)
		if gate:
			var depart_secs: int = 0
			if e.has_method("get_departure_seconds"):
				depart_secs = int(e.call("get_departure_seconds"))
			else:
				depart_secs = int(e.departure_hour) * 3600 + int(e.departure_minute) * 60
			if now >= depart_secs:
				idx += 1
				advanced = true
				continue
		break

	if advanced:
		ScheduleStore.set_entry_index(npc_id, idx)
		print("[FF] npc=", npc_id, " advanced_to_index=", idx, " now=", now)


func _check_time_gated_starts(this_key: StringName) -> void:
	# Validate refs BEFORE assigning to typed variables
	var ids: Array = _spawned.keys()
	for id_any in ids:
		var id: StringName = StringName(id_any)
		var npc: Node = _get_spawned_if_valid(id)
		if npc == null:
			continue
		var entry: NPCScheduleEntry = _entry_for(id, this_key)
		if entry == null:
			continue
		_maybe_start_spawned_npc(id, npc, entry)

func _maybe_start_spawned_npc(npc_id: StringName, npc: Node, entry: NPCScheduleEntry) -> void:
	# Don't start twice
	var p: Dictionary = _progress_for(npc_id)
	if bool(p.get("started", false)):
		return

	# Time gate
	var should_wait: bool = bool(entry.wait_for_time)
	var depart_secs: int = 0
	if should_wait:
		if entry.has_method("get_departure_seconds"):
			depart_secs = int(entry.call("get_departure_seconds"))
		else:
			depart_secs = int(entry.departure_hour) * 3600 + int(entry.departure_minute) * 60
	var now: int = _world_seconds()
	if now < 0:
		should_wait = false
	if should_wait and now < depart_secs:
		return

	# If this entry has already been running (we left & re-entered), continue from predicted point
	var resume_i: int = 0
	var predicted: Dictionary = _predict_progress(npc_id, entry)
	if predicted.has("finished") and bool(predicted["finished"]):
		# Off-screen finished; advance and don't start here
		var total_entries: int = 0
		var sched_any: Variant = _schedules.get(npc_id, null)
		var sched: NPCScheduleResource = sched_any as NPCScheduleResource
		if sched != null:
			total_entries = sched.schedule_entries.size()
		if ScheduleStore:
			ScheduleStore.complete_and_advance(npc_id, total_entries)
		_despawn(npc_id)
		return

	if predicted.has("pos") and npc is Node3D:
		(npc as Node3D).global_position = predicted["pos"]
	if predicted.has("resume_i"):
		resume_i = int(predicted["resume_i"])

	# Start
	var total: int = 0
	var sched_any2: Variant = _schedules.get(npc_id, null)
	var sched2: NPCScheduleResource = sched_any2 as NPCScheduleResource
	if sched2 != null:
		total = sched2.schedule_entries.size()

	if npc.has_method("start_schedule_entry"):
		npc.call("start_schedule_entry", entry, resume_i, total)
		if ScheduleStore:
			ScheduleStore.mark_started(npc_id, _last_scene_key, resume_i)
			# also refresh runtime (speed+names+start time) in case we resumed mid-path
			var speed: float = entry.movement_speed
			if "entry_speed" in p and float(p.entry_speed) > 0.0:
				speed = float(p.entry_speed)
			var names: PackedStringArray = entry.waypoint_names
			var started_at: int = now if now >= 0 else 0
			ScheduleStore.mark_entry_runtime(npc_id, speed, names, started_at)


func _on_npc_tree_exited(npc_id: StringName) -> void:
	if _spawned.has(npc_id):
		var v: Variant = _spawned.get(npc_id, null)
		if v == null or not is_instance_valid(v):
			_spawned.erase(npc_id)


func _progress_for(npc_id: StringName) -> Dictionary:
	if ScheduleStore:
		return ScheduleStore.get_progress(npc_id)
	return {
		"entry_index": 0,
		"started": false,
		"last_scene": StringName(),
		"last_waypoint_i": 0,
		"last_position": Vector3.ZERO
	}

func _first_waypoint_node(root: Node, entry: NPCScheduleEntry) -> Node3D:
	if root == null or entry == null:
		return null
	for nm in entry.waypoint_names:
		var name_s: String = String(nm)
		if name_s == "":
			continue
		var found: Node = root.find_child(name_s, true, false)
		if found and found is Node3D:
			return found as Node3D
	return null

func _find_spawn_marker(root: Node, npc_id: StringName) -> Node3D:
	if root == null:
		return null
	var grp: String = "npc_spawn_%s" % String(npc_id)
	var list: Array = root.get_tree().get_nodes_in_group(grp)
	for n in list:
		if n is Node3D:
			return n as Node3D
	var target_name: String = "%s_Spawn" % String(npc_id).to_upper()
	var found: Node = root.find_child(target_name, true, false)
	if found and found is Node3D:
		return found as Node3D
	var gen: Array = root.get_tree().get_nodes_in_group("npc_spawn")
	for n2 in gen:
		if n2 is Node3D:
			return n2 as Node3D
	return null

func _despawn(npc_id: StringName) -> void:
	if not _spawned.has(npc_id):
		return
	var v: Variant = _spawned.get(npc_id, null)
	_spawned.erase(npc_id)
	if v != null and is_instance_valid(v):
		var node := v as Node
		if node != null:
			node.queue_free()
	emit_signal("npc_despawned", npc_id)

func _get_spawned_if_valid(npc_id: StringName) -> Node:
	if not _spawned.has(npc_id):
		return null
	var v: Variant = _spawned.get(npc_id, null)
	if v == null or not is_instance_valid(v):
		# scrub stale ref (NPC probably queue_freed itself)
		_spawned.erase(npc_id)
		return null
	return v as Node

func _waypoint_positions(entry: NPCScheduleEntry) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var root: Node = get_tree().current_scene
	if root == null or entry == null:
		return pts
	for nm in entry.waypoint_names:
		var n: Node = root.find_child(String(nm), true, false)
		if n and n is Node3D:
			pts.append((n as Node3D).global_position)
	return pts

func _predict_progress(npc_id: StringName, entry: NPCScheduleEntry) -> Dictionary:
	# Returns {"pos":Vector3, "resume_i":int} or {"finished":true}
	var out := {}
	var p: Dictionary = _progress_for(npc_id)
	if not bool(p.get("started", false)):
		return out
	var start_secs: int = int(p.get("entry_started_at", -1))
	if start_secs < 0:
		return out
	var now: int = _world_seconds()
	if now < 0 or now < start_secs:
		return out

	var speed: float = float(p.get("entry_speed", entry.movement_speed))
	var pts: Array[Vector3] = _waypoint_positions(entry)
	if pts.size() < 2:
		return out

	var travel: float = speed * float(now - start_secs)
	var acc: float = 0.0

	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg_len: float = a.distance_to(b)
		if travel <= acc + seg_len:
			var t: float = clamp((travel - acc) / max(seg_len, 0.0001), 0.0, 1.0)
			out["pos"] = a.lerp(b, t)
			out["resume_i"] = i
			return out
		acc += seg_len

	# Past the end -> treat as finished
	out["finished"] = true
	out["pos"] = pts[pts.size() - 1]
	out["resume_i"] = pts.size() - 1
	return out
