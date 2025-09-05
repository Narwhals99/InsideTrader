# NPCScheduleEntry.gd
# Save this as a separate file in scripts/components/
class_name NPCScheduleEntry
extends Resource

@export var phase: String = "Morning"
@export var scene_key: String = "apartment"
@export var activity: String = "idle"  # idle, moving, working, socializing

@export_group("Time Range")
@export var start_hour: int = 6
@export var start_minute: int = 0
@export var end_hour: int = 9
@export var end_minute: int = 0

@export_group("Movement")
@export var waypoint_names: PackedStringArray = []
@export var loop_waypoints: bool = false
@export var movement_speed: float = 3.0

@export_group("Behavior")
@export var interaction_enabled: bool = true
@export var dialogue_lines: PackedStringArray = []
@export var idle_animation: String = ""

func get_start_minutes() -> int:
	return start_hour * 60 + start_minute

func get_end_minutes() -> int:
	return end_hour * 60 + end_minute

func get_start_seconds() -> float:
	return float(get_start_minutes() * 60)

func get_end_seconds() -> float:
	return float(get_end_minutes() * 60)

func is_active_at_time(world_seconds: float) -> bool:
	var start_sec = get_start_seconds()
	var end_sec = get_end_seconds()
	
	# Handle day wrap (e.g., 23:00 to 2:00)
	if start_sec > end_sec:
		return world_seconds >= start_sec or world_seconds < end_sec
	else:
		return world_seconds >= start_sec and world_seconds < end_sec

func to_dictionary() -> Dictionary:
	return {
		"scene": scene_key,
		"waypoints": waypoint_names,
		"activity": activity,
		"phase": phase,
		"t0": get_start_seconds(),
		"t1": get_end_seconds(),
		"loop": loop_waypoints,
		"speed": movement_speed,
		"interaction": interaction_enabled,
		"dialogue": dialogue_lines
	}
