# EventBus.gd
# Save this as an Autoload: Project Settings > Autoload > Add as "EventBus"
extends Node

# ============ TRADING EVENTS ============
signal trade_requested(symbol: String, quantity: int, is_buy: bool, price: float)
signal trade_executed(symbol: String, quantity: int, is_buy: bool, price: float, success: bool)
signal market_prices_updated(prices: Dictionary)
signal portfolio_updated(cash: float, holdings: Dictionary)
signal market_opened()
signal market_closed()

# ============ NPC EVENTS ============
signal npc_interaction_started(npc_id: String, interaction_type: String)
signal npc_interaction_completed(npc_id: String, result: Dictionary)
signal beer_purchased()
signal beer_given_to_npc(npc_id: String)
signal insider_tip_given(ticker: String, npc_id: String)

# ============ CEO SPECIFIC EVENTS ============
signal ceo_drunk_level_changed(level: int, max_level: int)
signal ceo_schedule_changed(scene: String, waypoints: Array)
signal ceo_arrived_at_destination(location: String)

# ============ DIALOGUE EVENTS ============
signal dialogue_requested(speaker: String, text: String, duration: float, options: Array)
signal dialogue_completed(choice_index: int)
signal notification_requested(text: String, type: String, duration: float)

# ============ TIME/PHASE EVENTS ============
# These will replace direct Game.gd signal connections
signal time_updated(hour: int, minute: int, day: int)
signal phase_changed(phase: String, day: int)
signal day_advanced(day: int)
signal sleep_requested()

# ============ SCENE EVENTS ============
signal scene_change_requested(scene_key: String, spawn_point: String)
signal scene_loaded(scene_key: String)

# ============ UI EVENTS ============
signal ui_opened(ui_name: String)
signal ui_closed(ui_name: String)

signal npc_arrived(npc_id: String, location: String)

func emit_notification(text: String, type: String = "info", duration: float = 3.0) -> void:
	emit_signal("notification_requested", text, type, duration)

func emit_dialogue(speaker: String, text: String, duration_or_options: Variant = null, options: Array = []) -> void:
	var duration: float = 0.0
	var opts: Array = []
	if duration_or_options == null:
		opts = options
	elif duration_or_options is Array:
		opts = duration_or_options
	else:
		duration = float(duration_or_options)
		opts = options
	emit_signal("dialogue_requested", speaker, text, duration, opts)

func emit_trade(symbol: String, qty: int, is_buy: bool, price: float = -1.0) -> void:
	emit_signal("trade_requested", symbol, qty, is_buy, price)

var _debug_mode: bool = false

func set_debug(enabled: bool) -> void:
	_debug_mode = enabled
	if _debug_mode:
		print("[EventBus] Debug mode enabled - will log all signals")
		_connect_debug_listeners()

func _connect_debug_listeners() -> void:
	for sig in get_signal_list():
		var signal_name = sig["name"]
		if not is_connected(signal_name, _on_debug_signal):
			connect(signal_name, _on_debug_signal.bind(signal_name))

func _on_debug_signal(signal_name: String, args: Array = []) -> void:
	print("[EventBus] Signal: ", signal_name, " Args: ", args)
