# NPCScheduleResource.gd
# This replaces the hardcoded schedule in CEOBrain.gd
# NOTE: NPCScheduleEntry must be in a separate file (NPCScheduleEntry.gd)
class_name NPCScheduleResource
extends Resource

@export var schedule_entries: Array[NPCScheduleEntry] = []
@export var debug_mode: bool = false

func get_active_segment(world_seconds: float) -> Dictionary:
	# Find which schedule entry matches current time
	for entry in schedule_entries:
		if entry.is_active_at_time(world_seconds):
			return entry.to_dictionary()
	
	# Fallback
	return {
		"scene": "apartment",
		"waypoints": ["Spawn_Point"],
		"activity": "idle",
		"t0": 0.0,
		"t1": 86400.0
	}

func get_schedule_for_phase(phase: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for entry in schedule_entries:
		if entry.phase == phase:
			results.append(entry.to_dictionary())
	return results
