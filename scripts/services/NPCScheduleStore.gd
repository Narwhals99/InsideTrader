extends Node
class_name NPCScheduleStore

# npc_id -> progress dict
var _progress: Dictionary = {}

static func _blank() -> Dictionary:
	return {
		"entry_index": 0,
		"started": false,
		"last_scene": StringName(),
		"last_waypoint_i": 0,
		"last_position": Vector3.ZERO,
		# runtime for off-screen continuation
		"entry_started_at": -1,                # world seconds when movement began
		"entry_speed": 0.0,                    # m/s used for this entry
		"entry_waypoint_names": PackedStringArray() # names used to rebuild the path
	}

func _ensure(npc_id: StringName) -> void:
	if not _progress.has(npc_id):
		_progress[npc_id] = _blank()

func get_progress(npc_id: StringName) -> Dictionary:
	_ensure(npc_id)
	var p: Dictionary = _progress[npc_id]
	return p

func set_entry_index(npc_id: StringName, idx: int) -> void:
	_ensure(npc_id)
	var p: Dictionary = _progress[npc_id]
	p.entry_index = max(0, idx)
	p.started = false
	p.last_waypoint_i = 0
	p.entry_started_at = -1

func mark_started(npc_id: StringName, scene_key: StringName, waypoint_i: int = 0) -> void:
	_ensure(npc_id)
	var p: Dictionary = _progress[npc_id]
	p.started = true
	p.last_scene = scene_key
	p.last_waypoint_i = max(0, waypoint_i)

# NEW: store runtime data to allow off-screen continuation
func mark_entry_runtime(npc_id: StringName, speed: float, waypoint_names: PackedStringArray, started_at_secs: int) -> void:
	_ensure(npc_id)
	var p: Dictionary = _progress[npc_id]
	p.entry_speed = float(speed)
	p.entry_waypoint_names = waypoint_names
	p.entry_started_at = int(started_at_secs)

func mark_position(npc_id: StringName, scene_key: StringName, pos: Vector3, waypoint_i: int) -> void:
	_ensure(npc_id)
	var p: Dictionary = _progress[npc_id]
	p.last_scene = scene_key
	p.last_position = pos
	p.last_waypoint_i = max(0, waypoint_i)

func complete_and_advance(npc_id: StringName, total_entries: int) -> void:
	_ensure(npc_id)
	var p: Dictionary = _progress[npc_id]
	if total_entries <= 0:
		p.entry_index = 0
	else:
		p.entry_index = clamp(p.entry_index + 1, 0, total_entries - 1)
	p.started = false
	p.last_waypoint_i = 0
	p.entry_started_at = -1
