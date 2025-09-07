# NPCScheduleEntry.gd - Add a new state variable and fix the methods
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
var is_started: bool = false  # ADD THIS - tracks if entry has been started
var start_time: float = -1.0  # When this entry actually started
var arrival_time: float = -1.0  # When NPC arrived (for idle duration)

func get_departure_seconds() -> float:
	"""Get the departure time in world seconds (only used if wait_for_time is true)"""
	return float((departure_hour * 60 + departure_minute) * 60)

func get_departure_minutes() -> int:
	"""Get the departure time in minutes since midnight"""
	return departure_hour * 60 + departure_minute

func can_start(world_seconds: float, previous_completed: bool) -> bool:
	"""Check if this entry can start now"""
	if is_completed or is_started:  # CHANGED: Also check is_started
		return false
	
	# If this is sequential (not time-based), start when previous is done
	if not wait_for_time:
		return previous_completed
	
	# If time-based, check against current clock time
	if typeof(Game) != TYPE_NIL:
		return Game.clock_minutes >= get_departure_minutes()
	
	# Fallback to world_seconds if Game not available
	var time_of_day = fmod(world_seconds, 86400.0)
	return time_of_day >= get_departure_seconds()

func should_complete(world_seconds: float) -> bool:
	"""Check if this entry should be marked complete"""
	if is_completed:
		return true
	
	# Must be started to complete
	if not is_started:
		return false
	
	# Moving activities complete when destination is reached (handled elsewhere)
	if activity == "moving":
		return false  # Will be set by movement system
	
	# Idle activities complete after duration
	if activity == "idle" and arrival_time > 0:
		if typeof(Game) != TYPE_NIL:
			var current_minutes = Game.clock_minutes
			var arrival_minutes = arrival_time / 60.0
			var elapsed = current_minutes - arrival_minutes
			return elapsed >= idle_duration_minutes
		else:
			var elapsed = world_seconds - arrival_time
			return elapsed >= (idle_duration_minutes * 60.0)
	
	return false

func start() -> void:
	"""Mark this entry as started"""
	if is_started:  # ADD THIS CHECK
		return  # Don't start twice
	
	is_started = true  # ADD THIS
	is_completed = false
	
	if typeof(Game) != TYPE_NIL:
		start_time = float(Game.clock_minutes * 60)
	else:
		start_time = TimeService.get_world_seconds()
	
	print("[Schedule] Starting: %s in %s at time %.0f" % [activity, scene_key, start_time])

func complete() -> void:
	"""Mark this entry as completed"""
	is_completed = true
	is_started = false  # Reset for next day
	print("[Schedule] Completed: %s in %s" % [activity, scene_key])

func reset_for_new_day() -> void:
	"""Reset state for a new day"""
	is_completed = false
	is_started = false  # ADD THIS
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
		"is_completed": is_completed,
		"is_started": is_started  # ADD THIS
	}
