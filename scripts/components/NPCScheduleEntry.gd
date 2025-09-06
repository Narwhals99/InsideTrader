# NPCScheduleEntry.gd - SEQUENTIAL SCHEDULE SYSTEM
# Entries happen in order, only some wait for specific times
class_name NPCScheduleEntry
extends Resource

@export var phase: String = "Morning"
@export var scene_key: String = "aptlobby"
@export var activity: String = "moving"  # idle, moving, working, socializing

@export_group("Timing")
@export var wait_for_time: bool = false  # If true, wait until departure_time to start
@export var departure_hour: int = 6
@export var departure_minute: int = 0
@export var idle_duration_minutes: int = 30  # Only for "idle" activities

@export_group("Movement")
@export var waypoint_names: PackedStringArray = []
@export var loop_waypoints: bool = false
@export var movement_speed: float = 3.0

@export_group("Behavior")
@export var interaction_enabled: bool = true
@export var dialogue_lines: PackedStringArray = []
@export var idle_animation: String = ""

# Runtime state
var is_completed: bool = false
var start_time: float = -1.0  # When this entry actually started
var arrival_time: float = -1.0  # When NPC arrived (for idle duration)

func get_departure_seconds() -> float:
	"""Get the departure time in world seconds (only used if wait_for_time is true)"""
	return float((departure_hour * 60 + departure_minute) * 60)

func can_start(world_seconds: float, previous_completed: bool) -> bool:
	"""Check if this entry can start now"""
	if is_completed:
		return false
	
	# If this is sequential (not time-based), start when previous is done
	if not wait_for_time:
		return previous_completed
	
	# If time-based, wait for the specific time
	return world_seconds >= get_departure_seconds()

func should_complete(world_seconds: float) -> bool:
	"""Check if this entry should be marked complete"""
	if is_completed:
		return true
	
	# Moving activities complete when destination is reached (handled elsewhere)
	if activity == "moving":
		return false  # Will be set by movement system
	
	# Idle activities complete after duration
	if activity == "idle" and arrival_time > 0:
		var elapsed = world_seconds - arrival_time
		return elapsed >= (idle_duration_minutes * 60.0)
	
	return false

func start() -> void:
	"""Mark this entry as started"""
	start_time = TimeService.get_world_seconds()
	is_completed = false
	print("[Schedule] Starting: %s in %s" % [activity, scene_key])

func complete() -> void:
	"""Mark this entry as completed"""
	is_completed = true
	print("[Schedule] Completed: %s in %s" % [activity, scene_key])

func reset_for_new_day() -> void:
	"""Reset state for a new day"""
	is_completed = false
	start_time = -1.0
	arrival_time = -1.0

func to_dictionary() -> Dictionary:
	return {
		"scene": scene_key,
		"waypoints": waypoint_names,
		"activity": activity,
		"phase": phase,
		"wait_for_time": wait_for_time,
		"departure_time": get_departure_seconds() if wait_for_time else -1,
		"loop": loop_waypoints,
		"speed": movement_speed,
		"interaction": interaction_enabled,
		"dialogue": dialogue_lines,
		"is_completed": is_completed
	}
