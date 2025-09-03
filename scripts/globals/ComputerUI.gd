extends CanvasLayer

@export var pause_game_on_open: bool = true

var _did_trade_today: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _btn_trade: Button = $Center/Window/VBoxContainer/Content/ExecuteTrade
@onready var _lbl_result: Label = $Center/Window/VBoxContainer/Content/ResultLabel
@onready var _btn_close_a: Button = $Center/Window/VBoxContainer/TitleBar/CloseButton
@onready var _btn_close_b: Button = $Center/Window/VBoxContainer/Footer/Close

func _ready() -> void:
	_rng.randomize()
	if not _btn_trade.pressed.is_connected(_on_trade_pressed):
		_btn_trade.pressed.connect(_on_trade_pressed)
	if not _btn_close_a.pressed.is_connected(_on_close_pressed):
		_btn_close_a.pressed.connect(_on_close_pressed)
	if not _btn_close_b.pressed.is_connected(_on_close_pressed):
		_btn_close_b.pressed.connect(_on_close_pressed)
	Game.phase_changed.connect(_on_phase_changed)
	Game.day_advanced.connect(_on_day_advanced)
	_refresh()

func open() -> void:
	visible = true
	if pause_game_on_open:
		get_tree().paused = true
		process_mode = Node.PROCESS_MODE_WHEN_PAUSED	# <-- Godot 4
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()

func close() -> void:
	if pause_game_on_open:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT		# <-- Godot 4
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_phase_changed(_phase: StringName, _day: int) -> void:
	_refresh()

func _on_day_advanced(_day: int) -> void:
	_did_trade_today = false
	_lbl_result.text = ""
	_refresh()

func _refresh() -> void:
	var market_open: bool = String(Game.phase) == "Market"
	_btn_trade.disabled = (not market_open) or _did_trade_today
	if market_open:
		if _did_trade_today:
			_btn_trade.text = "Trade Used"
		else:
			_btn_trade.text = "Execute Trade"
	else:
		_btn_trade.text = "Markets Closed"

func _on_trade_pressed() -> void:
	if _btn_trade.disabled:
		return
	var sign: int = (_rng.randi_range(0, 1) * 2) - 1
	var mag: int = _rng.randi_range(120, 380)
	var pnl: int = sign * mag
	var fmt: String = "+$%d" if pnl >= 0 else "-$%d"
	_lbl_result.text = fmt % abs(pnl)
	_did_trade_today = true
	_refresh()

func _on_close_pressed() -> void:
	close()
