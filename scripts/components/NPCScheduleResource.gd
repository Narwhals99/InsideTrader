# NPCScheduleResource.gd
# Container for NPC schedule entries
class_name NPCScheduleResource
extends Resource

@export var schedule_entries: Array[NPCScheduleEntry] = []
@export var debug_mode: bool = false

func get_active_segment(world_seconds: float) -> Dictionary:
	# For sequential system, just return current incomplete entry
	for entry in schedule_entries:
		if not entry.is_completed:
			return entry.to_dictionary()
	
	# If all complete, return first one (for next day)
	if schedule_entries.size() > 0:
		return schedule_entries[0].to_dictionary()
	
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

func reset_all_entries() -> void:
	"""Reset all entries for a new day"""
	for entry in schedule_entries:
		if entry.has_method("reset_for_new_day"):
			entry.reset_for_new_day()
		else:
			# Old entries might not have this method
			if "is_completed" in entry:
				entry.is_completed = false
