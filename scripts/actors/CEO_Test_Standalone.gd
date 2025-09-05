# CEO_Test_Standalone.gd
# A simple test to verify the movement system works WITHOUT schedule interference
extends CharacterBody3D

@export var walk_speed: float = 3.0
@export var turn_speed: float = 10.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var state_label: Label3D = $StateLabel

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

# Simple waypoint system test
var waypoints: Array[Vector3] = []
var current_waypoint: int = 0
var is_moving: bool = false

# Drunk component test
var drunk_system

func _ready() -> void:
	print("[CEO_TEST] Standalone test starting...")
	
	# Don't add to CEO groups to avoid interference
	add_to_group("test_npc")
	
	# Setup nav agent if exists
	if nav_agent:
		nav_agent.navigation_finished.connect(_on_nav_finished)
	
	# Test drunk system
	_setup_drunk_test()
	
	# Start movement test after delay
	await get_tree().create_timer(2.0).timeout
	_start_movement_test()

func _physics_process(delta: float) -> void:
	# Simple gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	
	# Simple movement
	if is_moving and current_waypoint < waypoints.size():
		var target = waypoints[current_waypoint]
		var distance = global_position.distance_to(target)
		
		if distance < 0.5:
			print("[CEO_TEST] Reached waypoint ", current_waypoint)
			current_waypoint += 1
			if current_waypoint >= waypoints.size():
				is_moving = false
				print("[CEO_TEST] Movement complete!")
		else:
			var direction = (target - global_position).normalized()
			velocity.x = direction.x * walk_speed
			velocity.z = direction.z * walk_speed
			
			# Simple rotation
			if direction.length() > 0.1:
				look_at(global_position + direction, Vector3.UP)
	else:
		velocity.x = 0
		velocity.z = 0
	
	# Update label
	if state_label:
		var status = "Moving" if is_moving else "Idle"
		var drunk_info = ""
		if drunk_system:
			drunk_info = " | Drunk: %d/3" % drunk_system.drunk_level
		state_label.text = "TEST: " + status + drunk_info
	
	move_and_slide()

func _setup_drunk_test() -> void:
	drunk_system = load("res://scripts/components/InsiderDrunkComponent.gd").new()
	drunk_system.name = "DrunkTest"
	drunk_system.drunk_threshold = 3
	add_child(drunk_system)
	print("[CEO_TEST] Drunk system created")

func _start_movement_test() -> void:
	print("[CEO_TEST] Starting movement test...")
	
	# Create a simple square path
	var pos = global_position
	waypoints = [
		pos + Vector3(5, 0, 0),   # Right
		pos + Vector3(5, 0, 5),   # Forward-right
		pos + Vector3(0, 0, 5),   # Forward
		pos + Vector3(0, 0, 0),   # Back to start
	]
	
	current_waypoint = 0
	is_moving = true
	print("[CEO_TEST] Moving through ", waypoints.size(), " waypoints")

func _on_nav_finished() -> void:
	print("[CEO_TEST] Navigation finished signal received")
