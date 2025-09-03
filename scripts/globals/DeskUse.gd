extends Area3D

@export var require_interact: bool = true
@export var office_only_market: bool = true
@export var ui: Node = null	# drag your ComputerUI (CanvasLayer) here in Inspector

var _player_inside: bool = false

func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

	if require_interact and not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)

	# Fallback if you forgot to drag the UI
	if ui == null:
		ui = get_tree().get_first_node_in_group("computer_ui")
	print("[DeskUse] ready. ui=", ui)

func _on_enter(b: Node) -> void:
	if b.is_in_group("player"):
		_player_inside = true
		print("[DeskUse] enter")
		if not require_interact:
			_try_open()

func _on_exit(b: Node) -> void:
	if b.is_in_group("player"):
		_player_inside = false
		print("[DeskUse] exit")

func _input(event: InputEvent) -> void:
	if require_interact and _player_inside and event.is_action_pressed("interact"):
		_try_open()

func _try_open() -> void:
	if office_only_market and String(Game.phase) != "Market":
		print("[DeskUse] blocked: phase=", String(Game.phase))
		return
	if ui == null:
		push_warning("[DeskUse] No UI ref. Drag the ComputerUI CanvasLayer into 'ui'.")
		return
	if not ui.has_method("open"):
		push_warning("[DeskUse] UI has no 'open()' (script not attached?). Node=", ui)
		return
	ui.call("open")
	print("[DeskUse] OPENED UI")
