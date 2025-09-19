extends Area3D

@export_enum("hub","apartment","office","club","aptlobby","UpTownApartment","GroceryHood","RestaurantHood") var target_scene_key: String = "hub"
@export var target_spawn: String = ""	# Marker3D name in target scene

# Keep but set to "None" now that the clock drives phases (using it may desync the clock)
@export_enum("None","Morning","Market","Evening","LateNight") var phase_on_trigger: String = "None"
@export_enum("None","Morning","Market","Evening","LateNight") var required_phase: String = "None"

@export var min_net_worth: float = 0.0	# ← set this on the Office entrance
@export var require_interact: bool = false
@export var one_shot: bool = false
@export var locked_hint: String = "Closed right now."

var _armed: bool = true
var _player_inside: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if require_interact and not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event("interact", ev)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		if not require_interact:
			_trigger()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false

func _input(event: InputEvent) -> void:
	if require_interact and _player_inside and event.is_action_pressed("interact"):
		_trigger()

func _trigger() -> void:
	if not _armed:
		return

	# Phase gate (kept)
	if required_phase != "None" and String(Game.phase) != required_phase:
		print("[Portal] locked:", name, " requires phase ", required_phase, " (now:", String(Game.phase), ") — ", locked_hint)
		return

	# Net worth gate (new)
	if min_net_worth > 0.0:
		var nw: float = Portfolio.net_worth()
		if nw < min_net_worth:
			var shortfall: float = min_net_worth - nw
			print("[Portal] locked:", name, " requires NW ≥ $%.2f (now: $%.2f, short: $%.2f). %s" % [min_net_worth, nw, shortfall, locked_hint])
			return

	_armed = not one_shot

	# Don’t use phase_on_trigger anymore (clock owns phase). Leave as "None".
	if phase_on_trigger != "None":
		print("[Portal] phase_on_trigger is deprecated with the clock. Leave it as 'None'.")

	Game.next_spawn = target_spawn
	Scenes.change_to(target_scene_key)	# deferred in Scenes.gd
