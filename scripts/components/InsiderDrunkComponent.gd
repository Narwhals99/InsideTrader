# InsiderDrunkComponent.gd
# Universal drunk system that works for ANY insider NPC
class_name InsiderDrunkComponent
extends Node

@export_group("Drunk Settings")
@export var drunk_threshold: int = 3
@export var max_drunk_level: int = 5
@export var sober_up_time: float = 120.0

@export_group("Insider Settings")
@export var tip_accuracy: float = 0.9  # How often tips are correct
@export var tip_move_size: float = 0.05  # How much the stock moves
@export var associated_tickers: Array[String] = ["ACME"]  # This NPC's stocks

signal drunk_level_changed(level: int, max_level: int)
signal ready_for_tip()
signal tip_given(ticker: String)

var drunk_level: int = 0
var npc_name: String = "Insider"  # Set by parent
var _sober_timer: float = 0.0
var _has_given_tip_today: bool = false
var _planned_ticker: String = ""

func _ready() -> void:
	EventBus.day_advanced.connect(_on_day_advanced)
	_roll_todays_tip()

func setup(name: String, tickers: Array[String]) -> void:
	"""Called by parent NPC to configure this component"""
	npc_name = name
	if not tickers.is_empty():
		associated_tickers = tickers
	_roll_todays_tip()

func _process(delta: float) -> void:
	if drunk_level > 0:
		_sober_timer += delta
		if _sober_timer >= sober_up_time:
			_sober_timer = 0.0
			drunk_level -= 1
			drunk_level_changed.emit(drunk_level, max_drunk_level)
			EventBus.emit_notification("%s is sobering up (level %d)" % [npc_name, drunk_level], "info", 2.0)

func can_accept_beer() -> bool:
	return drunk_level < max_drunk_level

func is_drunk_enough() -> bool:
	return drunk_level >= drunk_threshold

func give_beer() -> Dictionary:
	if not can_accept_beer():
		return {
			"success": false,
			"reason": "too_drunk",
			"message": "I can't drink anymore..."
		}
	
	drunk_level += 1
	_sober_timer = 0.0
	drunk_level_changed.emit(drunk_level, max_drunk_level)
	
	EventBus.emit_notification("%s drunk level: %d/%d" % [npc_name, drunk_level, drunk_threshold], "info", 2.0)
	
	if is_drunk_enough() and not _has_given_tip_today:
		ready_for_tip.emit()
		return give_insider_tip()
	
	var beers_needed = drunk_threshold - drunk_level
	if beers_needed > 0:
		EventBus.emit_notification("%s needs %d more beer(s)" % [npc_name, beers_needed], "warning", 2.0)
	
	return {
		"success": true,
		"gave_tip": false,
		"beers_needed": beers_needed,
		"message": _get_drunk_response()
	}

func give_insider_tip() -> Dictionary:
	if _has_given_tip_today:
		return {
			"success": false,
			"reason": "already_given",
			"message": "I've said too much already..."
		}
	
	if not is_drunk_enough():
		return {
			"success": false,
			"reason": "not_drunk",
			"beers_needed": drunk_threshold - drunk_level,
			"message": "Buy me a drink first!"
		}
	
	_has_given_tip_today = true
	
	# Pick ticker and determine accuracy
	var is_accurate = randf() <= tip_accuracy
	var ticker = _planned_ticker if is_accurate else _get_random_ticker()
	
	# Schedule market move
	var move_size = tip_move_size if is_accurate else tip_move_size * 0.5
	TradingService.schedule_mover(ticker, move_size)
	TradingService.add_insider_tip(ticker, "%s mentioned %s" % [npc_name, ticker])
	
	# Fire events
	tip_given.emit(ticker)
	EventBus.emit_signal("insider_tip_given", ticker, npc_name.to_lower().replace(" ", "_"))
	EventBus.emit_notification("🔥 TIP from %s: %s will move!" % [npc_name, ticker], "warning", 5.0)
	
	return {
		"success": true,
		"gave_tip": true,
		"ticker": ticker,
		"is_accurate": is_accurate,
		"source": npc_name,
		"message": "I heard %s is making moves..." % ticker
	}

func _roll_todays_tip() -> void:
	_planned_ticker = _get_random_ticker()
	print("[%s] Today's tip: %s" % [npc_name, _planned_ticker])

func _get_random_ticker() -> String:
	if not associated_tickers.is_empty():
		return associated_tickers[randi() % associated_tickers.size()]
	
	# Fallback to market
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
	_sober_timer = 0.0
	_roll_todays_tip()

func get_save_data() -> Dictionary:
	return {
		"drunk_level": drunk_level,
		"has_given_tip": _has_given_tip_today,
		"planned_ticker": _planned_ticker,
		"sober_timer": _sober_timer
	}
