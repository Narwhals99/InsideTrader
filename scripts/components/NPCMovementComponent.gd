# NPCMovementComponent.gd
# Movement system that doesn't snap to waypoints
class_name NPCMovementComponent
extends Node

@export var walk_speed: float = 3.0
@export var run_speed: float = 5.0
@export var turn_speed: float = 10.0
@export var use_navigation: bool = true
@export var stop_at_destination: bool = true
@export var loop_waypoints: bool = false

var character: CharacterBody3D
var nav_agent: NavigationAgent3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

# Waypoint system
var waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var is_moving: bool = false
var is_paused: bool = false

signal waypoint_reached(index: int)
signal destination_reached()
signal movement_started()
signal movement_stopped()

func setup(character_node: CharacterBody3D) -> void:
	character = character_node
	
	# Find or create NavigationAgent
	nav_agent = character.get_node_or_null("NavigationAgent3D")
	if nav_agent == null and use_navigation:
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		character.add_child(nav_agent)
	
	if nav_agent:
		nav_agent.navigation_finished.connect(_on_navigation_finished)
		nav_agent.velocity_computed.connect(_on_velocity_computed)

func set_waypoints(points: Array) -> void:
	waypoints.clear()
	for point in points:
		if point is Vector3:
			waypoints.append(point)
		elif point is Node3D:
			waypoints.append(point.global_position)
	
	current_waypoint_index = 0
	is_moving = waypoints.size() > 0
	
	if is_moving:
		_set_next_target()
		movement_started.emit()
		print("[NPCMovement] Started moving with ", waypoints.size(), " waypoints")
		print("[NPCMovement] First target: ", waypoints[0] if waypoints.size() > 0 else "none")
		print("[NPCMovement] Character starting at: ", character.global_position if character else "no character")

func set_waypoints_by_names(names: PackedStringArray, scene_root: Node = null, snap_to_first: bool = false) -> void:
	if scene_root == null:
		scene_root = character.get_tree().current_scene
	
	print("[NPCMovement] Looking for waypoints in scene: ", scene_root.name)
	print("[NPCMovement] Scene children: ")
	for child in scene_root.get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
	
	var points: Array[Vector3] = []
	for name in names:
		print("[NPCMovement] Searching for waypoint: ", name)
		var node = _find_node_by_name(scene_root, name)
		if node is Node3D:
			points.append(node.global_position)
			print("[NPCMovement] Found waypoint '", name, "' at position: ", node.global_position)
		else:
			push_warning("[NPCMovement] Waypoint not found: " + name)
			print("[NPCMovement] Failed to find waypoint: ", name)
	
	if points.is_empty():
		print("[NPCMovement] ERROR: No waypoints found! Movement will fail.")
		print("[NPCMovement] Tried to find: ", names)
		# List all Node3D children recursively to help debug
		print("[NPCMovement] Available Node3D nodes in scene:")
		_list_all_node3d(scene_root, "  ")
		return
	
	# ONLY snap on initial spawn, not during schedule changes
	if snap_to_first and points.size() > 0 and character:
		character.global_position = points[0]
		print("[NPCMovement] Snapped to first waypoint at position: ", points[0])
	
	set_waypoints(points)

func move_to(target: Vector3) -> void:
	waypoints = [target]
	current_waypoint_index = 0
	is_moving = true
	_set_next_target()
	movement_started.emit()

func stop() -> void:
	is_moving = false
	waypoints.clear()
	movement_stopped.emit()

func pause() -> void:
	is_paused = true

func resume() -> void:
	is_paused = false

func process_movement(delta: float) -> void:
	if character == null:
		push_error("[NPCMovement] No character assigned!")
		return
	
	# Apply gravity
	if not character.is_on_floor():
		character.velocity.y -= gravity * delta
	else:
		character.velocity.y = 0.0
	
	# Process movement
	if is_moving and not is_paused and waypoints.size() > 0:
		_process_waypoint_movement(delta)
	else:
		# IMPORTANT: Still need to clear velocity when not moving
		character.velocity.x = 0.0
		character.velocity.z = 0.0
	
	# Always call move_and_slide (but it should be called by the parent, not here)
	# character.move_and_slide() # <- Remove this if it exists

func _process_waypoint_movement(delta: float) -> void:
	# Safety check
	if current_waypoint_index >= waypoints.size():
		print("[NPCMovement] WARNING: waypoint index out of bounds!")
		if loop_waypoints and waypoints.size() > 0:
			current_waypoint_index = 0
			_set_next_target()
		else:
			_on_destination_reached()
		return
	
	var current_target = waypoints[current_waypoint_index]
	var target_pos: Vector3
	
	if nav_agent and use_navigation:
		if not nav_agent.is_target_reachable():
			print("[NPCMovement] Target not reachable via navigation!")
		target_pos = nav_agent.get_next_path_position()
	else:
		target_pos = current_target
	
	# Check distance to current waypoint (not the nav agent's intermediate position)
	var distance_to_target = character.global_position.distance_to(current_target)
	var threshold = 1.0  # Threshold for reaching waypoint
	
	if nav_agent:
		threshold = max(1.0, nav_agent.target_desired_distance + 0.1)
	
	# Debug every few frames
	if randf() < 0.01:  # 1% chance, roughly every 100 frames
		print("[NPCMovement] Distance to waypoint %d: %.2f (threshold: %.2f)" % [
			current_waypoint_index, 
			distance_to_target, 
			threshold
		])
	
	if distance_to_target <= threshold:
		print("[NPCMovement] Reached waypoint %d at distance %.2f" % [current_waypoint_index, distance_to_target])
		_on_waypoint_reached()
		return
	
	# Calculate movement direction (only on XZ plane)
	var direction = (target_pos - character.global_position)
	direction.y = 0  # Ignore vertical difference
	
	if direction.length() < 0.01:  # Too close, might cause jittering
		character.velocity.x = 0.0
		character.velocity.z = 0.0
		return
	
	direction = direction.normalized()
	
	# Apply movement
	character.velocity.x = direction.x * walk_speed
	character.velocity.z = direction.z * walk_speed
	
	# Rotate character smoothly
	if direction.length() > 0.1:
		var target_rotation = atan2(-direction.x, -direction.z)
		character.rotation.y = lerp_angle(character.rotation.y, target_rotation, turn_speed * delta)

func _set_next_target() -> void:
	"""Set the navigation target to the current waypoint"""
	if current_waypoint_index >= waypoints.size():
		print("[NPCMovement] ERROR: Trying to set target beyond waypoint array!")
		return
	
	var target = waypoints[current_waypoint_index]
	print("[NPCMovement] Setting target to waypoint %d at %s" % [current_waypoint_index, target])
	
	if nav_agent and use_navigation:
		nav_agent.target_position = target
		print("[NPCMovement] Nav agent target set to: ", nav_agent.target_position)

func _on_waypoint_reached() -> void:
	"""Called when a waypoint is reached"""
	print("[NPCMovement] Waypoint %d reached" % current_waypoint_index)
	waypoint_reached.emit(current_waypoint_index)
	
	# Advance to next waypoint
	current_waypoint_index += 1
	
	# Check if we have more waypoints
	if current_waypoint_index < waypoints.size():
		print("[NPCMovement] Moving to next waypoint %d/%d at %s" % [
			current_waypoint_index, 
			waypoints.size(), 
			waypoints[current_waypoint_index]
		])
		_set_next_target()
	elif loop_waypoints and waypoints.size() > 0:
		# Loop back to start
		print("[NPCMovement] Looping back to waypoint 0")
		current_waypoint_index = 0
		_set_next_target()
	else:
		# No more waypoints, destination reached
		print("[NPCMovement] All waypoints reached, stopping")
		_on_destination_reached()


func _on_destination_reached() -> void:
	"""Called when the final destination is reached"""
	print("[NPCMovement] Destination reached, stopping movement")
	is_moving = false
	if stop_at_destination:
		character.velocity = Vector3.ZERO
	destination_reached.emit()
	movement_stopped.emit()
	
func _on_navigation_finished() -> void:
	pass

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if nav_agent and nav_agent.avoidance_enabled:
		character.velocity = safe_velocity

func _find_node_by_name(root: Node, name: String) -> Node:
	# Handle pipe-separated aliases
	var options = name.split("|", false)
	
	for option in options:
		var node = root.get_node_or_null(option)
		if node:
			return node
		
		node = root.find_child(option, true, false)
		if node:
			return node
	
	# Try normalized matching
	for option in options:
		var norm_opt = option.to_lower().replace("_", "").replace("-", "").replace(" ", "")
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var cur = stack.pop_back()
			if cur is Node3D:
				var norm_name = cur.name.to_lower().replace("_", "").replace("-", "").replace(" ", "")
				if norm_name == norm_opt:
					return cur
			for child in cur.get_children():
				stack.append(child)
	
	push_warning("[NPCMovement] No waypoint found for any alias: " + name)
	return null

# Utility functions
func get_current_waypoint() -> Vector3:
	if current_waypoint_index < waypoints.size():
		return waypoints[current_waypoint_index]
	return Vector3.ZERO

func get_progress() -> float:
	if waypoints.size() == 0:
		return 0.0
	return float(current_waypoint_index) / float(waypoints.size())

func is_at_destination() -> bool:
	return not is_moving or current_waypoint_index >= waypoints.size()

func _list_all_node3d(node: Node, indent: String = "") -> void:
	if node is Node3D:
		print(indent, node.name, " (Node3D) at ", (node as Node3D).global_position)
	for child in node.get_children():
		_list_all_node3d(child, indent + "  ")
