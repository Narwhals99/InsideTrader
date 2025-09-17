# InsiderDrunkComponent.gd
# Universal drunk system for insider NPCs with confidence-driven tips
class_name InsiderDrunkComponent
extends Node

@export_group("Drunk Settings")
@export var drunk_threshold: int = 3
@export var max_drunk_level: int = 5
@export var sober_up_time: float = 120.0

@export_group("Tip Settings")
@export var confidence: float = 0.5
@export var tip_accuracy: float = 0.65
@export var tip_move_size: float = 0.04

@export_group("Insider Settings")
@export var associated_tickers: Array[String] = ["ACME"]

@export var debug_logging: bool = true

signal drunk_level_changed(level: int, max_level: int)
signal ready_for_tip()
signal tip_given(ticker: String)

var drunk_level: int = 0
var npc_name: String = "Insider"
var _sober_timer: float = 0.0
var _has_given_tip_today: bool = false
var _planned_ticker: String = ""
var _is_passed_out: bool = false

func _ready() -> void:
	EventBus.day_advanced.connect(_on_day_advanced)
	_roll_todays_tip()

func setup(name: String, tickers: Array[String], config: Dictionary = {}) -> void:
	npc_name = name
	if not tickers.is_empty():
		associated_tickers = tickers
	_apply_config(config)
	_roll_todays_tip()

func _apply_config(config: Dictionary) -> void:
	if config.has("confidence"):
		confidence = clamp(float(config["confidence"]), 0.0, 1.0)
	if config.has("tip_accuracy"):
		tip_accuracy = clamp(float(config["tip_accuracy"]), 0.0, 1.0)
	if config.has("tip_move_size"):
		tip_move_size = max(0.0, float(config["tip_move_size"]))
	if config.has("drunk_threshold"):
		drunk_threshold = max(1, int(config["drunk_threshold"]))
	if config.has("max_drunk"):
		max_drunk_level = max(drunk_threshold, int(config["max_drunk"]))
	if config.has("debug_logging"):
		debug_logging = bool(config["debug_logging"])

func _process(delta: float) -> void:
	if drunk_level > 0 and not _is_passed_out:
		_sober_timer += delta
		if _sober_timer >= sober_up_time:
			_sober_timer = 0.0
			drunk_level = max(0, drunk_level - 1)
			drunk_level_changed.emit(drunk_level, max_drunk_level)
			if debug_logging:
				print("[InsiderDrunk]", npc_name, "sobering to", drunk_level)
			EventBus.emit_notification("%s is sobering up (level %d)" % [npc_name, drunk_level], "info", 2.0)

func can_accept_beer() -> bool:
	return not _is_passed_out and drunk_level < max_drunk_level

func is_drunk_enough() -> bool:
	return drunk_level >= drunk_threshold and not _is_passed_out

func is_passed_out() -> bool:
	return _is_passed_out

func give_beer() -> Dictionary:
	if _is_passed_out:
		return {
			"success": false,
			"reason": "passed_out",
			"message": "%s doesn't respond." % npc_name,
			"confidence": confidence
		}

	if not can_accept_beer():
		return {
			"success": false,
			"reason": "too_drunk",
			"message": "I can't drink anymore...",
			"confidence": confidence
		}

	drunk_level += 1
	_sober_timer = 0.0
	drunk_level_changed.emit(drunk_level, max_drunk_level)
	if debug_logging:
		print("[InsiderDrunk]", npc_name, "level", drunk_level, "of", max_drunk_level)

	EventBus.emit_notification("%s drunk level: %d/%d" % [npc_name, drunk_level, drunk_threshold], "info", 2.0)

	var response := {
		"success": true,
		"gave_tip": false,
		"beers_needed": max(0, drunk_threshold - drunk_level),
		"confidence": confidence,
		"message": _get_drunk_response()
	}

	if drunk_level >= max_drunk_level:
		_is_passed_out = true
		response["pass_out"] = true
		if debug_logging:
			print("[InsiderDrunk]", npc_name, "passed out at level", drunk_level)
		return response

	if is_drunk_enough() and not _has_given_tip_today:
		ready_for_tip.emit()

	return response

func give_insider_tip() -> Dictionary:
	if _is_passed_out:
		return {
			"success": false,
			"reason": "passed_out",
			"confidence": confidence,
			"message": "..."
		}

	if _has_given_tip_today:
		return {
			"success": false,
			"reason": "already_given",
			"confidence": confidence,
			"message": "I've said too much already..."
		}

	if not is_drunk_enough():
		return {
			"success": false,
			"reason": "not_drunk",
			"confidence": confidence,
			"beers_needed": drunk_threshold - drunk_level,
			"message": "Buy me a drink first!"
		}

	_has_given_tip_today = true

	var is_accurate := randf() <= tip_accuracy
	var ticker := _planned_ticker if is_accurate else _get_random_ticker()

	var move_size := tip_move_size
	if not is_accurate:
		move_size *= 0.5

	TradingService.schedule_mover(ticker, move_size)
	TradingService.add_insider_tip(ticker, "%s mentioned %s" % [npc_name, ticker])

	tip_given.emit(ticker)
	EventBus.emit_signal("insider_tip_given", ticker, npc_name.to_lower().replace(" ", "_"))
	EventBus.emit_notification("Tip from %s (conf %.0f%%): %s will move soon!" % [npc_name, confidence * 100.0, ticker], "warning", 5.0)

	if debug_logging:
		print("[InsiderTip]", npc_name, "conf=%.2f" % confidence, "ticker=", ticker, "accurate=", is_accurate, "move=", move_size)

	return {
		"success": true,
		"gave_tip": true,
		"ticker": ticker,
		"is_accurate": is_accurate,
		"confidence": confidence,
		"move_size": move_size,
		"source": npc_name,
		"message": "I heard %s is making moves..." % ticker
	}

func _roll_todays_tip() -> void:
	_planned_ticker = _get_random_ticker()
	if debug_logging:
		print("[InsiderDrunk]", npc_name, "planned tip:", _planned_ticker)

func _get_random_ticker() -> String:
	if not associated_tickers.is_empty():
		return associated_tickers[randi() % associated_tickers.size()]

	if typeof(MarketSim) != TYPE_NIL and MarketSim.symbols.size() > 0:
		var idx = randi() % MarketSim.symbols.size()
		return String(MarketSim.symbols[idx])

	return "ACME"

func _get_drunk_response() -> String:
	var responses = [
		"Thanks for the drink!",
		"You're alright, you know that?",
		"One more and I might tell you something..."
	]
	if drunk_level > 0 and drunk_level <= responses.size():
		return responses[drunk_level - 1]
	return "Cheers!"

func _on_day_advanced(_day: int) -> void:
	_has_given_tip_today = false
	drunk_level = 0
	_is_passed_out = false
	_sober_timer = 0.0
	_roll_todays_tip()

func get_save_data() -> Dictionary:
	return {
		"drunk_level": drunk_level,
		"has_given_tip": _has_given_tip_today,
		"planned_ticker": _planned_ticker,
		"sober_timer": _sober_timer,
		"confidence": confidence,
		"passed_out": _is_passed_out
	}
