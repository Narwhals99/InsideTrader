# NPCSpawnManager.gd
# Autoload that manages spawning ALL scheduled NPCs in correct scenes
# Replaces CEOState.gd but works for any NPC
extends Node

# Register all NPCs that should be managed
@export var managed_npcs: Array[Dictionary] = [
	{
		"id": "cfo",
		"scene_path": "res://scenes/actors/CFO_NPC.tscn",
		"schedule_path": "res://resources/schedules/cfo_schedule.tres"
	}
]

var spawned_npcs: Dictionary = {}  # id -> instance

func _ready() -> void:
	# Listen for scene changes
	if typeof(EventBus) != TYPE_NIL:
		EventBus.scene_loaded.connect(_on_scene_loaded)
	
	# Process every frame to check schedules
	set_process(true)

func _process(_delta: float) -> void:
	_update_all_npcs()

# Add this debug version of _update_all_npcs() to NPCSpawnManager:

func _update_all_npcs() -> void:
	var current_scene = _get_current_scene_key()
	if current_scene == "":
		return
	
	var world_seconds = TimeService.get_world_seconds()
	
	# Debug print every 60 frames
	if Engine.get_process_frames() % 60 == 0:
		print("\n[NPCSpawnManager] === UPDATE CHECK ===")
		print("  Current scene (normalized): ", current_scene)
		print("  Current scene (raw): ", get_tree().current_scene.name)
		print("  World time: ", TimeService.format_current_time())
	
	for npc_config in managed_npcs:
		var npc_id = npc_config.get("id", "")
		var should_spawn = _should_npc_be_in_scene(npc_id, current_scene, world_seconds)
		
		if Engine.get_process_frames() % 60 == 0:
			print("  ", npc_id, " should spawn: ", should_spawn)
		
		if should_spawn:
			_spawn_or_update_npc(npc_config, world_seconds)
		else:
			_despawn_npc(npc_id)

# Also update _should_npc_be_in_scene() with more debug:
func _should_npc_be_in_scene(npc_id: String, scene: String, world_seconds: float) -> bool:
	# Find this NPC's schedule
	for config in managed_npcs:
		if config.get("id") == npc_id:
			var schedule_path = config.get("schedule_path", "")
			if schedule_path == "":
				return false
			
			var schedule = load(schedule_path) as NPCScheduleResource
			if not schedule:
				return false
			
			var segment = schedule.get_active_segment(world_seconds)
			var seg_scene = segment.get("scene", "")  # NO NORMALIZATION!
			
			# Debug print
			if Engine.get_process_frames() % 60 == 0:
				print("    ", npc_id, " schedule says: ", seg_scene)
				print("    Current scene key: ", scene)
				print("    Match: ", seg_scene == scene)
			
			return seg_scene == scene  # Simple string comparison
	
	return false

# And check the spawn attempt:
func _spawn_or_update_npc(config: Dictionary, world_seconds: float) -> void:
	var npc_id = config.get("id", "")
	var scene_path = config.get("scene_path", "")
	var schedule_path = config.get("schedule_path", "")
	
	print("\n[NPCSpawnManager] Attempting to spawn/update: ", npc_id)
	print("  Scene path: ", scene_path)
	print("  Schedule path: ", schedule_path)
	
	# Check if already spawned
	if spawned_npcs.has(npc_id):
		var instance = spawned_npcs[npc_id]
		if is_instance_valid(instance):
			print("  Already spawned, updating...")
			_update_npc_schedule(instance, schedule_path, world_seconds)
			return
	
	# Need to spawn
	print("  Loading scene...")
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_error("[NPCSpawnManager] Failed to load: " + scene_path)
		return
	
	var instance = packed_scene.instantiate()
	var root = get_tree().current_scene
	if root:
		root.add_child(instance)
		spawned_npcs[npc_id] = instance
		print("  Spawned successfully!")
		
		# Rest of spawn code...
		var schedule = load(schedule_path) as NPCScheduleResource
		if schedule:
			var segment = schedule.get_active_segment(world_seconds)
			var waypoints = segment.get("waypoints", PackedStringArray())
			print("  Waypoints: ", waypoints)
			
			# Try to find first waypoint
			if waypoints.size() > 0:
				var first_wp = _find_waypoint_in_scene(root, waypoints[0])
				if first_wp:
					print("  Found waypoint: ", waypoints[0], " at ", first_wp.global_position)
				else:
					print("  WARNING: Could not find waypoint: ", waypoints[0])
		
		_update_npc_schedule(instance, schedule_path, world_seconds)

func _update_npc_schedule(npc_instance: Node, schedule_path: String, world_seconds: float) -> void:
	if not npc_instance:
		return
	
	var schedule = load(schedule_path) as NPCScheduleResource
	if not schedule:
		return
	
	var segment = schedule.get_active_segment(world_seconds)
	var waypoints = segment.get("waypoints", PackedStringArray())
	
	# If NPC has the method, update waypoints
	if npc_instance.has_method("set_waypoints_by_names"):
		npc_instance.set_waypoints_by_names(waypoints, _get_current_scene_key())
	
	# For CEO compatibility
	if npc_instance.has_method("apply_time_segment"):
		var t0 = segment.get("t0", 0.0)
		var t1 = segment.get("t1", 86400.0)
		npc_instance.apply_time_segment(_get_current_scene_key(), waypoints, t0, t1, world_seconds)

func _despawn_npc(npc_id: String) -> void:
	if not spawned_npcs.has(npc_id):
		return
	
	var instance = spawned_npcs[npc_id]
	if is_instance_valid(instance):
		instance.queue_free()
		print("[NPCSpawnManager] Despawned ", npc_id)
	
	spawned_npcs.erase(npc_id)

# Replace the _get_current_scene_key() function in NPCSpawnManager with this:

func _get_current_scene_key() -> String:
	var scene = get_tree().current_scene
	if not scene:
		return ""
	
	var name = scene.name.to_lower().replace("_", "").replace("-", "")
	
	# Normalize common variants - BUT KEEP APARTMENT AND APTLOBBY SEPARATE!
	if name == "apartmentlobby" or name == "aptlobby":
		return "aptlobby"  # The building lobby
	elif name == "apartment" or name == "apt" or name == "playerapartment":
		return "apartment"  # The player's personal apartment
	elif name in ["officelobby", "hq"]:
		return "office"
	elif name in ["plaza", "square"]:
		return "hub"
	elif name == "bar":
		return "club"
	
	return name



func _find_waypoint_in_scene(root: Node, waypoint_string: String) -> Node3D:
	# Handle pipe-separated aliases
	var options = waypoint_string.split("|", false)
	
	for option in options:
		# Try exact node path
		var node = root.get_node_or_null(option)
		if node and node is Node3D:
			return node
		
		# Try recursive find
		node = root.find_child(option, true, false)
		if node and node is Node3D:
			return node
	
	# Try normalized matching for all options
	for option in options:
		var norm_opt = option.to_lower().replace("_", "").replace("-", "").replace(" ", "")
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var cur = stack.pop_back()
			if cur is Node3D:
				var norm_name = cur.name.to_lower().replace("_", "").replace("-", "").replace(" ", "")
				if norm_name == norm_opt:
					return cur as Node3D
			for child in cur.get_children():
				stack.append(child)
	
	push_warning("[NPCSpawnManager] Waypoint not found: " + waypoint_string)
	return null

func _calculate_segment_progress(world_seconds: float, t0: float, t1: float) -> float:
	# Calculate progress through a time segment (0.0 to 1.0)
	var duration = t1 - t0
	if duration <= 0:
		duration += 86400.0  # Handle day wrap
	
	var elapsed = world_seconds - t0
	if elapsed < 0:
		elapsed += 86400.0  # Handle day wrap
	
	if duration <= 0.0001:
		return 1.0
	
	return clamp(elapsed / duration, 0.0, 1.0)

func _interpolate_position_along_path(waypoints: Array[Vector3], progress: float) -> Vector3:
	if waypoints.size() == 0:
		return Vector3.ZERO
	if waypoints.size() == 1:
		return waypoints[0]
	
	# For idle segments (1 waypoint), stay at that waypoint
	if waypoints.size() == 1:
		return waypoints[0]
	
	# Calculate total path length
	var distances: Array[float] = [0.0]
	var total_length = 0.0
	for i in range(1, waypoints.size()):
		var segment_length = waypoints[i].distance_to(waypoints[i-1])
		total_length += segment_length
		distances.append(total_length)
	
	# Find position along path
	var target_distance = total_length * progress
	
	for i in range(1, waypoints.size()):
		if target_distance <= distances[i]:
			# Interpolate between waypoint i-1 and i
			var segment_start = distances[i-1]
			var segment_end = distances[i]
			var segment_length = segment_end - segment_start
			
			if segment_length <= 0.0001:
				return waypoints[i]
			
			var segment_progress = (target_distance - segment_start) / segment_length
			return waypoints[i-1].lerp(waypoints[i], segment_progress)
	
	return waypoints[-1]  # End of path

func _on_scene_loaded(scene_key: String) -> void:
	# Clear all spawned NPCs when scene changes
	for npc_id in spawned_npcs:
		_despawn_npc(npc_id)
	spawned_npcs.clear()
	
	print("[NPCSpawnManager] Scene changed to: ", scene_key)

# Manual registration for runtime-added NPCs
func register_npc(npc_id: String, scene_path: String, schedule_path: String = "") -> void:
	var config = {
		"id": npc_id,
		"scene_path": scene_path,
		"schedule_path": schedule_path
	}
	managed_npcs.append(config)
	print("[NPCSpawnManager] Registered NPC: ", npc_id)
