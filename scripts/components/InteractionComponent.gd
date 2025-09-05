# InteractionComponent.gd
# Base class for all NPC interactions
class_name InteractionComponent
extends Area3D

@export var interaction_range: float = 2.0
@export var require_key_press: bool = true
@export var interaction_key: String = "interact"
@export var interaction_cooldown: float = 0.5
@export var interaction_prompt: String = "Press E to interact"

# Interaction data that child classes can override
@export_group("Interaction Config")
@export var npc_id: String = "generic_npc"
@export var npc_display_name: String = "NPC"

var _player_in_range: bool = false
var _interaction_locked: bool = false
var _cooldown_timer: float = 0.0

signal player_entered_range()
signal player_exited_range()
signal interaction_triggered(result: Dictionary)

func _ready() -> void:
	# Setup collision
	monitoring = true
	monitorable = true
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Ensure interaction key exists
	_ensure_input_action()
	
	# Setup collision shape if missing
	_ensure_collision_shape()

func _ensure_collision_shape() -> void:
	if get_child_count() == 0:
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = interaction_range
		shape.shape = sphere
		add_child(shape)

func _ensure_input_action() -> void:
	if not InputMap.has_action(interaction_key):
		InputMap.add_action(interaction_key)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_E
		InputMap.action_add_event(interaction_key, event)

func _physics_process(delta: float) -> void:
	if _cooldown_timer > 0:
		_cooldown_timer -= delta

func _input(event: InputEvent) -> void:
	if not require_key_press:
		return
	
	if _player_in_range and event.is_action_pressed(interaction_key):
		if _cooldown_timer <= 0:
			trigger_interaction()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		player_entered_range.emit()
		_on_player_entered()
		
		if interaction_prompt != "":
			EventBus.emit_notification(interaction_prompt, "info", 2.0)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		player_exited_range.emit()
		_on_player_exited()

func trigger_interaction() -> void:
	if _interaction_locked:
		return
	
	_interaction_locked = true
	_cooldown_timer = interaction_cooldown
	
	# Get interaction result from child implementation
	var result := perform_interaction()
	
	# Emit events
	EventBus.emit_signal("npc_interaction_completed", npc_id, result)
	interaction_triggered.emit(result)
	
	_interaction_locked = false

# ============ VIRTUAL METHODS FOR CHILD CLASSES ============
func perform_interaction() -> Dictionary:
	# Override this in child classes
	return {
		"success": true,
		"type": "generic",
		"message": "Interaction completed"
	}

func _on_player_entered() -> void:
	# Override for custom behavior when player enters range
	pass

func _on_player_exited() -> void:
	# Override for custom behavior when player exits range
	pass

# ============ UTILITY METHODS ============
func is_player_in_range() -> bool:
	return _player_in_range

func set_interaction_enabled(enabled: bool) -> void:
	set_physics_process(enabled)
	monitoring = enabled

func show_dialogue(text: String, duration: float = 4.0) -> void:
	EventBus.emit_dialogue(npc_display_name, text)

func give_item_to_player(item_id: String, quantity: int = 1) -> void:
	# This would connect to an inventory system
	EventBus.emit_signal("item_received", item_id, quantity)

func check_player_has_item(item_id: String) -> bool:
	# This would check player inventory
	# For now, check if bartender has beer (for compatibility)
	if item_id == "beer":
		var bartender = get_tree().get_first_node_in_group("bartender_npc")
		if bartender and bartender.has_method("has_beer"):
			return bartender.has_beer()
	return false
