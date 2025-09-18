extends RefCounted

class_name MoverEngine

enum HorizonType { INTRADAY = 0, SWING = 1 }
enum StartMode { IMMEDIATE = 0, NEXT_SESSION = 1, SCHEDULED = 2 }

class MoverState:
	var symbol: StringName = StringName()
	var direction: int = 0
	var target_daily_drift: float = 0.0
	var horizon: int = HorizonType.INTRADAY
	var start_day: int = -1
	var start_phase: StringName = StringName()
	var duration_days: int = 1
	var start_mode: int = StartMode.IMMEDIATE
	var metadata: Dictionary = {}
	var activated_day: int = -1
	var expires_day: int = -1
	var active: bool = false

	func is_active() -> bool:
		return active and symbol != StringName() and target_daily_drift > 0.0

	func duplicate() -> MoverState:
		var copy := MoverState.new()
		copy.symbol = symbol
		copy.direction = direction
		copy.target_daily_drift = target_daily_drift
		copy.horizon = horizon
		copy.start_day = start_day
		copy.start_phase = start_phase
		copy.duration_days = duration_days
		copy.start_mode = start_mode
		copy.metadata = metadata.duplicate(true)
		copy.activated_day = activated_day
		copy.expires_day = expires_day
		copy.active = active
		return copy

const PHASE_MARKET: StringName = StringName("Market")

var _current_day: int = 0
var _current_phase: StringName = StringName()
var _active_by_symbol: Dictionary = {}
var _scheduled_states: Array = []

func update_clock(day: int, phase: StringName) -> void:
	_current_day = day
	_current_phase = phase
	_activate_due_states()
	_retire_finished_states()

func notify_day_advanced(day: int) -> void:
	_current_day = day
	_activate_due_states()
	_retire_finished_states()

func activate_simple(symbol: StringName, direction: int, target_daily_drift: float, horizon: int = HorizonType.INTRADAY, duration_days: int = 1, start_mode: int = StartMode.IMMEDIATE) -> void:
	var state := MoverState.new()
	state.symbol = symbol
	state.direction = direction
	state.target_daily_drift = abs(target_daily_drift)
	state.horizon = horizon
	state.duration_days = max(1, duration_days)
	state.start_mode = start_mode
	_queue_state(state)

func activate_from_state(state: MoverState) -> void:
	if state == null:
		return
	var copy := state.duplicate()
	if copy.duration_days <= 0:
		copy.duration_days = 1
	_queue_state(copy)

func clear_active() -> void:
	_active_by_symbol.clear()
	_scheduled_states.clear()

func clear_intraday_states() -> void:
	var to_remove: Array = []
	for symbol in _active_by_symbol.keys():
		var s: MoverState = _active_by_symbol[symbol]
		if s != null and s.horizon == HorizonType.INTRADAY:
			to_remove.append(symbol)
	for sym in to_remove:
		_active_by_symbol.erase(sym)

func has_active() -> bool:
	return not _active_by_symbol.is_empty()

func is_symbol_active(symbol: StringName) -> bool:
	return _active_by_symbol.has(symbol)

func get_active_state() -> MoverState:
	for value in _active_by_symbol.values():
		var state: MoverState = value
		if state != null:
			return state.duplicate()
	return MoverState.new()

func get_primary_symbol() -> StringName:
	for symbol in _active_by_symbol.keys():
		return symbol
	return StringName()

func get_current_symbol() -> StringName:
	return get_primary_symbol()

func get_direction() -> int:
	var state := get_active_state()
	return state.direction if state.is_active() else 0

func get_target_daily_drift() -> float:
	var state := get_active_state()
	return state.target_daily_drift if state.is_active() else 0.0

func get_state_for_symbol(symbol: StringName) -> MoverState:
	if _active_by_symbol.has(symbol):
		var state: MoverState = _active_by_symbol[symbol]
		if state != null:
			return state.duplicate()
	return null

func get_active_states() -> Array:
	var result: Array = []
	for value in _active_by_symbol.values():
		var state: MoverState = value
		if state != null:
			result.append(state.duplicate())
	return result

func retire_symbol(symbol: StringName) -> void:
	if _active_by_symbol.has(symbol):
		_active_by_symbol.erase(symbol)
	_remove_scheduled_for_symbol(symbol)

func debug_summary() -> String:
	if _active_by_symbol.is_empty():
		return "none"
	var parts: Array = []
	for value in _active_by_symbol.values():
		var state: MoverState = value
		if state == null:
			continue
		var dir_str: String = "+" if state.direction >= 0 else "-"
		var label: String = "%s %s%.2f%%" % [String(state.symbol), dir_str, state.target_daily_drift * 100.0]
		if state.horizon == HorizonType.SWING:
			label += " swing"
		parts.append(label)
	return "; ".join(parts)

func _queue_state(state: MoverState) -> void:
	_remove_scheduled_for_symbol(state.symbol)
	match state.start_mode:
		StartMode.IMMEDIATE:
			if state.start_day < 0:
				state.start_day = _current_day
			if state.start_phase == StringName():
				state.start_phase = _current_phase
			_start_state(state)
		StartMode.NEXT_SESSION:
			if state.start_day < 0:
				state.start_day = _current_day
			state.start_phase = PHASE_MARKET
			if _current_phase == PHASE_MARKET and state.start_day <= _current_day:
				_start_state(state)
			else:
				_scheduled_states.append(state)
		StartMode.SCHEDULED:
			if state.start_day < 0:
				state.start_day = _current_day
			if state.start_phase == StringName():
				state.start_phase = PHASE_MARKET
			_scheduled_states.append(state)
		_:
			_scheduled_states.append(state)

func _activate_due_states() -> void:
	if _scheduled_states.is_empty():
		return
	var remaining: Array = []
	for state in _scheduled_states:
		if _should_start_now(state):
			_start_state(state)
		else:
			remaining.append(state)
	_scheduled_states = remaining

func _should_start_now(state: MoverState) -> bool:
	if state.start_mode == StartMode.NEXT_SESSION:
		if _current_phase != PHASE_MARKET:
			return false
		if state.start_day < 0:
			return true
		return _current_day >= state.start_day
	var desired_day: int = state.start_day
	if desired_day < 0:
		desired_day = _current_day
	if _current_day < desired_day:
		return false
	if _current_day > desired_day:
		return true
	if state.start_phase == StringName():
		return true
	return state.start_phase == _current_phase

func _start_state(state: MoverState) -> void:
	if state.symbol == StringName():
		return
	state.active = true
	state.activated_day = _current_day
	if state.duration_days <= 0:
		state.duration_days = 1
	state.expires_day = state.activated_day + state.duration_days - 1
	state.start_day = state.activated_day
	_active_by_symbol[state.symbol] = state

func _retire_finished_states() -> void:
	if _active_by_symbol.is_empty():
		return
	var to_remove: Array = []
	for symbol in _active_by_symbol.keys():
		var state: MoverState = _active_by_symbol[symbol]
		if state == null:
			to_remove.append(symbol)
			continue
		if state.horizon == HorizonType.INTRADAY and _current_phase != PHASE_MARKET:
			if state.activated_day >= 0 and _current_day >= state.activated_day:
				to_remove.append(symbol)
				continue
		if state.expires_day >= 0 and _current_day > state.expires_day:
			to_remove.append(symbol)
	for sym in to_remove:
		_active_by_symbol.erase(sym)

func _remove_scheduled_for_symbol(symbol: StringName) -> void:
	if _scheduled_states.is_empty():
		return
	var remaining: Array = []
	for state in _scheduled_states:
		if state.symbol != symbol:
			remaining.append(state)
	_scheduled_states = remaining