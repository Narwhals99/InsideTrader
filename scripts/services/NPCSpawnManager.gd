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

func _update_all_npcs() -> void:
	var current_scene = _get_current_scene_key()
	if current_scene == "":
		return
	
	var world_seconds = TimeService.get_world_seconds()
	
	for npc_config in managed_npcs:
		var npc_id = npc_config.get("id", "")
		var should_spawn = _should_npc_be_in_scene(npc_id, current_scene, world_seconds)
		
		if should_spawn:
			_spawn_or_update_npc(npc_config, world_seconds)
		else:
			_despawn_npc(npc_id)

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
			var seg_scene = segment.get("scene", "").to_lower().replace("_", "")
			
			return seg_scene == scene
	
	return false

func _spawn_or_update_npc(config: Dictionary, world_seconds: float) -> void:
	var npc_id = config.get("id", "")
	var scene_path = config.get("scene_path", "")
	var schedule_path = config.get("schedule_path", "")
	
	# Check if already spawned
	if spawned_npcs.has(npc_id):
		var instance = spawned_npcs[npc_id]
		if is_instance_valid(instance):
			# Update its schedule segment
			_update_npc_schedule(instance, schedule_path, world_seconds)
			return
	
	# Need to spawn
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_error("[NPCSpawnManager] Failed to load: " + scene_path)
		return
	
	var instance = packed_scene.instantiate()
	var root = get_tree().current_scene
	if root:
		root.add_child(instance)
		spawned_npcs[npc_id] = instance
		
		# CRITICAL: Spawn at first waypoint of current segment!
		var schedule = load(schedule_path) as NPCScheduleResource
		if schedule:
			var segment = schedule.get_active_segment(world_seconds)
			var waypoints = segment.get("waypoints", PackedStringArray())
			if waypoints.size() > 0 and instance is Node3D:
				var first_wp = _find_waypoint_in_scene(root, waypoints[0])
				if first_wp:
					(instance as Node3D).global_transform = first_wp.global_transform
					print("[NPCSpawnManager] Spawned ", npc_id, " at waypoint: ", waypoints[0])
		
		# Then update schedule for movement
		_update_npc_schedule(instance, schedule_path, world_seconds)
		
		print("[NPCSpawnManager] Spawned ", npc_id, " in ", _get_current_scene_key())

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

func _get_current_scene_key() -> String:
	var scene = get_tree().current_scene
	if not scene:
		return ""
	
	var name = scene.name.to_lower().replace("_", "").replace("-", "")
	
	# Normalize common variants
	if name in ["apartment", "apt", "apartmentlobby"]:
		return "aptlobby"
	if name in ["officelobby", "hq"]:
		return "office"
	if name in ["plaza", "square"]:
		return "hub"
	if name == "bar":
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
