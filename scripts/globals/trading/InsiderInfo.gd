# InsiderInfo.gd - Autoload (Godot 4)
# Manages and persists insider trading tips throughout the game
extends Node

signal tips_changed()

# Active tips that haven't expired yet
var _tips: Array[Dictionary] = []

func _ready() -> void:
	# Listen for day changes to expire old tips
	if typeof(Game) != TYPE_NIL:
		if Game.has_signal("day_advanced"):
			Game.day_advanced.connect(_on_day_advanced)
		if Game.has_signal("phase_changed"):
			Game.phase_changed.connect(_on_phase_changed)

# Add a tip that a stock will move tomorrow
func add_move_tomorrow_tip(ticker: String, message: String) -> void:
	var tip: Dictionary = {
		"ticker": ticker,
		"message": message,
		"received_day": _get_current_day(),
		"expires_day": _get_current_day() + 2,  # Valid through tomorrow
		"expires_phase": &"Morning",  # Expires when tomorrow's market opens
		"type": "move_tomorrow"
	}
	_tips.append(tip)
	emit_signal("tips_changed")
	print("[InsiderInfo] Added tip: ", ticker, " expires day ", tip.expires_day)

# Get all active (non-expired) tips
func get_active_tips() -> Array[Dictionary]:
	_expire_old_tips()
	return _tips.duplicate(true)

# Check if we have a tip for a specific ticker
func has_tip_for_ticker(ticker: String) -> bool:
	_expire_old_tips()
	for tip in _tips:
		if String(tip.get("ticker", "")) == ticker:
			return true
	return false

# Get tip for a specific ticker (if any)
func get_tip_for_ticker(ticker: String) -> Dictionary:
	_expire_old_tips()
	for tip in _tips:
		if String(tip.get("ticker", "")) == ticker:
			return tip
	return {}

# Clear all tips (for new game, etc)
func clear_all_tips() -> void:
	_tips.clear()
	emit_signal("tips_changed")

# Save/Load support
func get_save_data() -> Dictionary:
	return {
		"tips": _tips.duplicate(true)
	}

func load_save_data(data: Dictionary) -> void:
	_tips = data.get("tips", []).duplicate(true)
	_expire_old_tips()
	emit_signal("tips_changed")

# --- Private helpers ---

func _get_current_day() -> int:
	if typeof(Game) != TYPE_NIL:
		return int(Game.day)
	return 1

func _get_current_phase() -> StringName:
	if typeof(Game) != TYPE_NIL:
		return Game.phase
	return &"Morning"

func _expire_old_tips() -> void:
	var current_day: int = _get_current_day()
	var current_phase: StringName = _get_current_phase()
	
	var expired_count: int = 0
	var i: int = _tips.size() - 1
	while i >= 0:
		var tip: Dictionary = _tips[i]
		var expire_day: int = int(tip.get("expires_day", 0))
		var expire_phase: StringName = tip.get("expires_phase", &"Morning")
		
		var should_expire: bool = false
		
		# Check if past expiry day
		if current_day > expire_day:
			should_expire = true
		# Check if on expiry day and past expiry phase
		elif current_day == expire_day:
			if _phase_to_index(current_phase) >= _phase_to_index(expire_phase):
				should_expire = true
		
		if should_expire:
			_tips.remove_at(i)
			expired_count += 1
		
		i -= 1
	
	if expired_count > 0:
		print("[InsiderInfo] Expired ", expired_count, " tips")
		emit_signal("tips_changed")

func _phase_to_index(phase: StringName) -> int:
	# Convert phase to index for comparison
	var phases: Array[StringName] = [&"Morning", &"Market", &"Evening", &"LateNight"]
	var idx: int = phases.find(phase)
	return idx if idx >= 0 else 0

func _on_day_advanced(_day: int) -> void:
	_expire_old_tips()

func _on_phase_changed(_phase: StringName, _day: int) -> void:
	_expire_old_tips()
