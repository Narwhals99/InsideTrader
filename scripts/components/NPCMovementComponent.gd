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

func set_waypoints_by_names(names: PackedStringArray, scene_root: Node = null, snap_to_first: bool = false) -> void:
	if scene_root == null:
		scene_root = character.get_tree().current_scene
	
	var points: Array[Vector3] = []
	for name in names:
		var node = _find_node_by_name(scene_root, name)
		if node is Node3D:
			points.append(node.global_position)
		else:
			push_warning("[NPCMovement] Waypoint not found: " + name)
	
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
		character.velocity.x = 0.0
		character.velocity.z = 0.0
	
	character.move_and_slide()

func _process_waypoint_movement(delta: float) -> void:
	if current_waypoint_index >= waypoints.size():
		if loop_waypoints and waypoints.size() > 0:
			current_waypoint_index = 0
			_set_next_target()
		else:
			_on_destination_reached()
		return
	
	var target_pos: Vector3
	if nav_agent and use_navigation:
		target_pos = nav_agent.get_next_path_position()
	else:
		target_pos = waypoints[current_waypoint_index]
	
	# Check if reached current waypoint
	var distance_to_target = character.global_position.distance_to(waypoints[current_waypoint_index])
	var threshold = 0.5
	if nav_agent:
		threshold = nav_agent.target_desired_distance + 0.1
	
	if distance_to_target <= threshold:
		_on_waypoint_reached()
		return
	
	# Calculate movement
	var direction = (target_pos - character.global_position)
	direction.y = 0
	direction = direction.normalized()
	
	# Apply movement
	character.velocity.x = direction.x * walk_speed
	character.velocity.z = direction.z * walk_speed
	
	# Rotate character
	if direction.length() > 0.1:
		var target_rotation = atan2(-direction.x, -direction.z)
		character.rotation.y = lerp_angle(character.rotation.y, target_rotation, turn_speed * delta)

func _set_next_target() -> void:
	if current_waypoint_index >= waypoints.size():
		return
	
	if nav_agent and use_navigation:
		nav_agent.target_position = waypoints[current_waypoint_index]

func _on_waypoint_reached() -> void:
	waypoint_reached.emit(current_waypoint_index)
	current_waypoint_index += 1
	
	if current_waypoint_index < waypoints.size():
		_set_next_target()
	elif loop_waypoints:
		current_waypoint_index = 0
		_set_next_target()
	else:
		_on_destination_reached()

func _on_destination_reached() -> void:
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
