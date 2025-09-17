# NPCScheduleEntry.gd — COMPLETE
class_name NPCScheduleEntry
extends Resource

@export var phase: String = "Morning"
@export var scene_key: String = "aptlobby"
@export var activity: String = "moving"  # "moving" | "idle" | "working" | "socializing"

@export_group("Timing")
@export var wait_for_time: bool = false
@export var departure_hour: int = 6               # 0–23
@export var departure_minute: int = 0             # 0–59
@export var idle_duration_minutes: int = 30       # used when activity == "idle"

@export_group("Movement")
@export var waypoint_names: PackedStringArray = []# names in the scene to walk through
@export var loop_waypoints: bool = false
@export var movement_speed: float = 3.0

@export_group("Interaction / Flavor")
@export var interaction_enabled: bool = true
@export var dialogue_lines: Array[String] = []
@export var idle_animation: String = ""

# --------- Runtime (do NOT put this in save files) ---------
var is_started: bool = false
var is_completed: bool = false
var arrival_time: float = -1.0  # world seconds when we reached the target

func get_departure_seconds() -> float:
	return float(departure_hour) * 3600.0 + float(departure_minute) * 60.0

func can_start(world_seconds: float, previous_completed: bool) -> bool:
	if is_started or is_completed:
		return false
	if not previous_completed:
		return false
	if wait_for_time:
		return world_seconds >= get_departure_seconds()
	return true

func should_complete(world_seconds: float) -> bool:
	if activity == "moving":
		return false
	if activity == "idle" and idle_duration_minutes > 0 and arrival_time >= 0.0:
		return world_seconds >= arrival_time + float(idle_duration_minutes) * 60.0
	return false

func start() -> void:
	is_started = true

func complete() -> void:
	is_completed = true

func reset_for_new_day() -> void:
	is_started = false
	is_completed = false
	arrival_time = -1.0

func to_dictionary() -> Dictionary:
	return {
		"scene": scene_key,
		"waypoints": waypoint_names,
		"activity": activity,
		"phase": phase,
		"wait_for_time": wait_for_time,
		"departure_time": get_departure_seconds() if wait_for_time else -1.0,
		"loop": loop_waypoints,
		"speed": movement_speed,
		"interaction": interaction_enabled,
		"dialogue": dialogue_lines,
		"is_completed": is_completed,
		"is_started": is_started
	}
