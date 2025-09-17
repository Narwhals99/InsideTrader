# NPCScheduleResource.gd — COMPLETE
class_name NPCScheduleResource
extends Resource

@export var schedule_entries: Array[NPCScheduleEntry] = []
@export var debug_mode: bool = false

func get_active_segment(world_seconds: float) -> Dictionary:
	for entry in schedule_entries:
		if not entry.is_completed:
			return entry.to_dictionary()
	if schedule_entries.size() > 0:
		return schedule_entries[0].to_dictionary()
	return {}

func get_entries_for_phase(phase: String) -> Array:
	var results: Array = []
	for entry in schedule_entries:
		if entry.phase == phase:
			results.append(entry.to_dictionary())
	return results

func reset_all_entries() -> void:
	for entry in schedule_entries:
		if entry.has_method("reset_for_new_day"):
			entry.reset_for_new_day()
		else:
			# Fallback for older resources
			entry.is_started = false
			entry.is_completed = false
