# InsiderNPC.gd - SEQUENTIAL SCHEDULE VERSION
# NPCs complete activities in order, only waiting for time when specified
extends CharacterBody3D

@export_group("NPC Identity")
@export var npc_name: String = "Executive"
@export var npc_id: String = "exec_1"
@export var npc_title: String = "Executive"
@export var npc_company: String = "ACME Corp"

@export_group("Schedule")
@export var use_schedule: bool = true
@export var schedule_resource: NPCScheduleResource

@export_group("Insider Settings")
@export var associated_tickers: Array[String] = ["ACME"]
@export var drinks_needed: int = 3
@export var tip_accuracy: float = 0.9
@export var tip_move_size: float = 0.05

@export_group("Movement")
@export var movement_speed: float = 2.0

@export_group("Interaction")
@export var interaction_range: float = 2.0
@export var dialogue_portrait: Texture2D

@export_group("Dialogue Lines")
@export var need_drink_lines: Array[String] = [
	"Buy me a drink first, will ya?",
	"I don't talk business without a drink in hand.",
	"Get me something from the bar first.",
	"I'm a bit parched... how about a beer?",
	"Nothing loosens the tongue like a cold beer..."
]

@export var drunk_responses: Array[String] = [
	"Thanks for the drink!",
	"You're alright, you know that?",
	"One more and I might tell you something..."
]

@export var too_drunk_lines: Array[String] = [
	"I can't... *hiccup* ...drink anymore...",
	"The room is... spinning a bit...",
	"Maybe tomorrow, friend..."
]

@export var already_gave_tip_lines: Array[String] = [
	"I've said enough for today...",
	"Can't be too careful... walls have ears.",
	"Check back tomorrow, maybe?"
]

@export_subgroup("Tip Dialogue")
@export var tip_intro: String = "Alright, listen closely..."
@export var tip_format: String = "%s is going to make moves tomorrow."
@export var tip_outro: String = "You didn't hear it from me!"

@export_group("Display")
@export var state_label: Label3D
@export var name_label: Label3D

# Components
var movement: NPCMovementComponent
var drunk_system: InsiderDrunkComponent
var interaction_area: Area3D

# State
var _player_near: bool = false
var _current_entry_index: int = 0
var _current_location: String = ""
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

func _ready() -> void:
	add_to_group("insider_npc")
	add_to_group("npc_" + npc_id)
	
	_setup_components()
	
	if name_label:
		name_label.text = npc_title
	
	print("[InsiderNPC] %s (%s) initialized with tickers: %s" % [npc_name, npc_title, associated_tickers])

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	
	if use_schedule and schedule_resource:
		_update_schedule()
	
	if movement:
		movement.process_movement(delta)
	
	if state_label:
		_update_state_label()
	
	move_and_slide()

func _input(event: InputEvent) -> void:
	if _player_near and event.is_action_pressed("interact"):
		interact()

# ============ SEQUENTIAL SCHEDULE SYSTEM ============

func _update_schedule() -> void:
	if not schedule_resource or schedule_resource.schedule_entries.is_empty():
		return
	
	var world_seconds = TimeService.get_world_seconds()
	var current_entry = _get_current_entry()
	
	if not current_entry:
		print("[%s] ERROR: No current entry!" % npc_name)
		return
	
	# DEBUG: Print what's happening
	print("[%s] Entry %d: wait_for_time=%s, departure=%d:%02d, current_time=%s, can_start=%s" % [
		npc_name, 
		_current_entry_index,
		current_entry.wait_for_time,
		current_entry.departure_hour,
		current_entry.departure_minute,
		TimeService.format_current_time(),
		current_entry.can_start(world_seconds, _is_previous_entry_completed())
	])
	
	# Rest of the function...
	
	# Compatibility check
	var first_entry = schedule_resource.schedule_entries[0]
	if not first_entry.has_method("can_start"):
		push_error("[%s] Schedule resource has old format! Please recreate it." % npc_name)
		use_schedule = false
		return
	
	# Rest of the function...
	"""Process schedule entries sequentially"""
	if not schedule_resource or schedule_resource.schedule_entries.is_empty():
		return
	
	if not current_entry:
		return
	
	# Check if current entry should complete
	if current_entry.should_complete(world_seconds):
		_complete_current_entry()
		return
	
	# Check if we can start the current entry
	var previous_completed = _is_previous_entry_completed()
	if not current_entry.is_completed and current_entry.can_start(world_seconds, previous_completed):
		_start_current_entry()

func _start_current_entry() -> void:
	"""Begin executing the current schedule entry"""
	var entry = _get_current_entry()
	if not entry:
		return
	
	entry.start()
	_current_location = entry.scene_key
	
	# Only process if we're in the right scene
	if not _is_in_current_scene():
		print("[%s] Not in scene %s, waiting..." % [npc_name, entry.scene_key])
		return
	
	print("[%s] Starting entry %d: %s in %s" % [npc_name, _current_entry_index, entry.activity, entry.scene_key])
	
	if entry.activity == "moving":
		if entry.waypoint_names.size() > 0 and movement:
			movement.stop_at_destination = true
			movement.loop_waypoints = entry.loop_waypoints
			movement.walk_speed = entry.movement_speed
			movement.set_waypoints_by_names(entry.waypoint_names, get_tree().current_scene)
	elif entry.activity == "idle":
		entry.arrival_time = TimeService.get_world_seconds()
		if entry.waypoint_names.size() > 0 and movement:
			# Go to idle position
			var single_waypoint = PackedStringArray([entry.waypoint_names[0]])
			movement.stop_at_destination = true
			movement.set_waypoints_by_names(single_waypoint, get_tree().current_scene)
		else:
			# Just stop where we are
			movement.stop()

func _complete_current_entry() -> void:
	"""Mark current entry as complete and advance"""
	var entry = _get_current_entry()
	if entry:
		entry.complete()
	
	_advance_to_next_entry()

func _advance_to_next_entry() -> void:
	"""Move to the next schedule entry"""
	_current_entry_index += 1
	
	# Check if we've completed the whole schedule
	if _current_entry_index >= schedule_resource.schedule_entries.size():
		print("[%s] Schedule complete, restarting" % npc_name)
		_current_entry_index = 0
		# Reset all entries for new day
		for entry in schedule_resource.schedule_entries:
			entry.reset_for_new_day()

func _get_current_entry() -> NPCScheduleEntry:
	"""Get the current schedule entry"""
	if _current_entry_index >= 0 and _current_entry_index < schedule_resource.schedule_entries.size():
		return schedule_resource.schedule_entries[_current_entry_index]
	return null

func _is_previous_entry_completed() -> bool:
	"""Check if the previous entry is done (or if we're at the start)"""
	if _current_entry_index == 0:
		return true  # No previous entry
	
	var prev_index = _current_entry_index - 1
	if prev_index >= 0 and prev_index < schedule_resource.schedule_entries.size():
		return schedule_resource.schedule_entries[prev_index].is_completed
	
	return true

func _is_in_current_scene() -> bool:
	"""Check if NPC is in the currently loaded scene"""
	var current_scene_name = get_tree().current_scene.name.to_lower().replace(" ", "").replace("_", "").replace("-", "")
	var npc_scene = _current_location.to_lower().replace("_", "").replace(" ", "").replace("-", "")
	
	# Handle scene name variants
	if npc_scene == "aptlobby" or npc_scene == "apartmentlobby":
		npc_scene = "aptlobby"
	elif npc_scene == "apartment" or npc_scene == "apt":
		npc_scene = "apartment"
	
	if current_scene_name == "apartmentlobby":
		current_scene_name = "aptlobby"
	elif current_scene_name == "apartment" or current_scene_name == "apt" or current_scene_name == "playerapartment":
		current_scene_name = "apartment"
	
	return current_scene_name == npc_scene

# ============ COMPONENT SETUP ============
func _setup_components() -> void:
	# Movement
	movement = NPCMovementComponent.new()
	movement.name = "Movement"
	add_child(movement)
	movement.setup(self)
	movement.walk_speed = movement_speed
	movement.stop_at_destination = true
	movement.destination_reached.connect(_on_destination_reached)
	
	# Drunk System
	drunk_system = preload("res://scripts/components/InsiderDrunkComponent.gd").new()
	drunk_system.name = "DrunkSystem"
	drunk_system.drunk_threshold = drinks_needed
	drunk_system.tip_accuracy = tip_accuracy
	drunk_system.tip_move_size = tip_move_size
	add_child(drunk_system)
	drunk_system.setup(npc_name, associated_tickers)
	if drunk_system.has_signal("tip_given"):
		drunk_system.tip_given.connect(_on_tip_given)
	
	# Interaction Area
	_setup_interaction_area()

func _setup_interaction_area() -> void:
	interaction_area = Area3D.new()
	interaction_area.name = "InteractionArea"
	add_child(interaction_area)
	
	var shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = interaction_range
	shape.shape = sphere
	interaction_area.add_child(shape)
	
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e = InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)

# ============ CALLBACKS ============
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = true
		_show_interaction_prompt()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = false

func _on_destination_reached() -> void:
	"""Called when NPC reaches their destination"""
	var current_entry = _get_current_entry()
	if current_entry:
		if current_entry.activity == "moving":
			# Movement complete, mark entry as done
			current_entry.complete()
			print("[%s] Reached destination, completing entry" % npc_name)
		elif current_entry.activity == "idle":
			# Started idling, record arrival time
			current_entry.arrival_time = TimeService.get_world_seconds()
			print("[%s] Started idling for %d minutes" % [npc_name, current_entry.idle_duration_minutes])
	
	EventBus.emit_signal("npc_arrived", npc_id, _current_location)

func _on_tip_given(ticker: String) -> void:
	pass  # Handled by drunk system

# ============ INTERACTION ============
func interact() -> Dictionary:
	if Inventory.has_beer():
		return give_beer()
	else:
		return request_tip()

func give_beer() -> Dictionary:
	if not drunk_system.can_accept_beer():
		_show_dialogue(_get_too_drunk_line())
		return {"success": false, "reason": "too_drunk"}
	
	if not Inventory.remove_item("beer", 1):
		return {"success": false, "reason": "no_beer"}
	
	var result = drunk_system.give_beer()
	
	if result.get("gave_tip", false):
		_show_tip_dialogue(result.get("ticker", ""))
	else:
		_show_dialogue(_get_drunk_response_line(drunk_system.drunk_level))
	
	EventBus.emit_signal("beer_given_to_npc", npc_id)
	
	return result

func request_tip() -> Dictionary:
	if not drunk_system.is_drunk_enough():
		var beers = drunk_system.drunk_threshold - drunk_system.drunk_level
		_show_dialogue(_get_need_drinks_dialogue())
		EventBus.emit_notification("%s needs %d beer(s)" % [npc_title, beers], "warning", 2.0)
		return {"success": false, "beers_needed": beers}
	
	if drunk_system._has_given_tip_today:
		_show_dialogue(_get_already_tipped_line())
		return {"success": false, "reason": "already_gave"}
	
	var result = drunk_system.give_insider_tip()
	if result.get("success"):
		_show_tip_dialogue(result.get("ticker", ""))
	
	return result

# ============ DIALOGUE ============
func _show_dialogue(text: String) -> void:
	EventBus.emit_dialogue(npc_name, text)

func _show_tip_dialogue(ticker: String) -> void:
	var messages = _get_tip_dialogue_sequence(ticker)
	if typeof(DialogueUI) != TYPE_NIL:
		DialogueUI.show_dialogue_sequence(messages, 2.5)

func _get_need_drinks_dialogue() -> String:
	if need_drink_lines.is_empty():
		return "Buy me a drink first!"
	return need_drink_lines[randi() % need_drink_lines.size()]

func _get_drunk_response_line(drunk_level_param: int) -> String:
	if drunk_responses.is_empty():
		return "Thanks!"
	var index = min(drunk_level_param - 1, drunk_responses.size() - 1)
	if index < 0:
		index = 0
	return drunk_responses[index]

func _get_too_drunk_line() -> String:
	if too_drunk_lines.is_empty():
		return "I can't drink anymore..."
	return too_drunk_lines[randi() % too_drunk_lines.size()]

func _get_already_tipped_line() -> String:
	if already_gave_tip_lines.is_empty():
		return "I've said enough for today..."
	return already_gave_tip_lines[randi() % already_gave_tip_lines.size()]

func _get_tip_dialogue_sequence(ticker: String) -> Array:
	return [
		{"speaker": npc_name, "text": tip_intro},
		{"speaker": npc_name, "text": tip_format % ticker},
		{"speaker": npc_name, "text": tip_outro}
	]

func _show_interaction_prompt() -> void:
	if drunk_system and drunk_system.drunk_level < drunk_system.drunk_threshold:
		var beers = drunk_system.drunk_threshold - drunk_system.drunk_level
		EventBus.emit_notification("%s needs %d beer(s)" % [npc_title, beers], "info", 2.0)
	else:
		EventBus.emit_notification("Talk to %s" % npc_title, "info", 2.0)

# ============ STATE DISPLAY ============
func _update_state_label() -> void:
	if not state_label or not drunk_system:
		return
	
	var drunk = "%d/%d" % [drunk_system.drunk_level, drunk_system.drunk_threshold]
	var tip = "Tip: " + ("Given" if drunk_system._has_given_tip_today else "Ready")
	var status = "Idle"
	
	if movement and movement.is_moving:
		status = "Moving"
	
	var location = _current_location if _current_location != "" else "Unknown"
	var entry = _get_current_entry()
	var entry_info = ""
	if entry:
		entry_info = "E%d: %s" % [_current_entry_index, entry.activity]
	
	state_label.text = "%s | %s | %s | %s | Drunk: %s | %s" % [npc_title, location, status, entry_info, drunk, tip]

# ============ SAVE/LOAD ============
func get_save_data() -> Dictionary:
	return {
		"npc_id": npc_id,
		"drunk": drunk_system.get_save_data() if drunk_system else {},
		"location": _current_location,
		"entry_index": _current_entry_index
	}

func load_save_data(data: Dictionary) -> void:
	if drunk_system and data.has("drunk"):
		drunk_system.load_save_data(data["drunk"])
	_current_location = data.get("location", "")
	_current_entry_index = data.get("entry_index", 0)
