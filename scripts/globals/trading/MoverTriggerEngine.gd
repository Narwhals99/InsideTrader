extends RefCounted

class_name MoverTriggerEngine

const MoverEngine = preload("res://scripts/globals/trading/MoverEngine.gd")

class Context:
	var day: int = 0
	var phase: StringName = StringName()
	var symbols: Array = []
	var prices: Dictionary = {}
	var history: Dictionary = {}
	var today_open: Dictionary = {}
	var today_close: Dictionary = {}
	var rng: RandomNumberGenerator = null
	var get_last_days: Callable = Callable()
	var config: Dictionary = {}

class MoverFactor:
	var priority: int = 0

	func evaluate(_context: Context) -> Array:
		return []

class RandomDailyFactor extends MoverFactor:
	func _init(priority_value: int = 0) -> void:
		priority = priority_value

	func evaluate(context: Context) -> Array:
		if context == null:
			return []
		var rng: RandomNumberGenerator = context.rng
		if rng == null:
			return []
		var symbols: Array = context.symbols
		if symbols.is_empty():
			return []
		var chance: float = float(context.config.get("mover_daily_chance", 0.0))
		if chance <= 0.0:
			return []
		if rng.randf() > chance:
			return []
		var lo_cfg: float = float(context.config.get("mover_target_min_pct", 0.0))
		var hi_cfg: float = float(context.config.get("mover_target_max_pct", 0.0))
		var lo: float = min(abs(lo_cfg), abs(hi_cfg))
		var hi: float = max(abs(lo_cfg), abs(hi_cfg))
		if hi <= 0.0:
			return []
		if lo <= 0.0:
			lo = hi * 0.5
		var symbol: StringName = symbols[rng.randi_range(0, symbols.size() - 1)]
		var drift: float = abs(rng.randf_range(lo, hi))
		if drift <= 0.0:
			drift = hi
		var direction: int = 1 if rng.randf() >= 0.5 else -1
		var state := MoverEngine.MoverState.new()
		state.symbol = symbol
		state.direction = direction
		state.target_daily_drift = drift
		state.horizon = MoverEngine.HorizonType.INTRADAY
		state.duration_days = 1
		state.start_mode = MoverEngine.StartMode.IMMEDIATE
		state.metadata = {
			"factor": "random_daily"
		}
		return [state]

class StreakFactor extends MoverFactor:
	var streak_length: int = 3
	var direction: int = 1
	var start_mode: int = MoverEngine.StartMode.NEXT_SESSION
	var horizon: int = MoverEngine.HorizonType.SWING
	var duration_days: int = 2
	var min_average_magnitude: float = 0.0
	var lead_days: int = 1
	var label: String = "streak"

	func _init(settings: Dictionary = {}) -> void:
		priority = int(settings.get("priority", 10))
		streak_length = max(1, int(settings.get("length", 3)))
		direction = 1 if int(settings.get("direction", 1)) >= 0 else -1
		start_mode = int(settings.get("start_mode", MoverEngine.StartMode.NEXT_SESSION))
		horizon = int(settings.get("horizon", MoverEngine.HorizonType.SWING))
		duration_days = max(1, int(settings.get("duration_days", 2)))
		min_average_magnitude = abs(float(settings.get("min_average", 0.0)))
		lead_days = max(0, int(settings.get("lead_days", 1)))
		label = String(settings.get("label", "streak"))

	func evaluate(context: Context) -> Array:
		if context == null:
			return []
		if context.get_last_days == Callable():
			return []
		if context.symbols.is_empty():
			return []
		var results: Array = []
		for raw_symbol in context.symbols:
			var symbol: StringName = raw_symbol
			var entries: Array = context.get_last_days.call(symbol, streak_length)
			if entries.size() < streak_length:
				continue
			if not _matches_direction(entries):
				continue
			var average_change: float = _average_daily_change(entries)
			if average_change == 0.0:
				continue
			var magnitude: float = abs(average_change)
			if magnitude < min_average_magnitude:
				continue
			var min_cfg: float = abs(float(context.config.get("mover_target_min_pct", magnitude)))
			var max_cfg: float = abs(float(context.config.get("mover_target_max_pct", magnitude)))
			var lo: float = min(min_cfg, max_cfg)
			var hi: float = max(min_cfg, max_cfg)
			if hi <= 0.0:
				hi = magnitude
			if lo <= 0.0:
				lo = magnitude
			var target: float = clamp(magnitude, lo, hi)
			var state := MoverEngine.MoverState.new()
			state.symbol = symbol
			state.direction = direction
			state.target_daily_drift = target
			state.horizon = horizon
			state.duration_days = max(1, duration_days)
			state.start_mode = start_mode
			if start_mode == MoverEngine.StartMode.SCHEDULED or start_mode == MoverEngine.StartMode.NEXT_SESSION:
				var desired_day: int = context.day + lead_days
				if start_mode == MoverEngine.StartMode.NEXT_SESSION and lead_days <= 0:
					desired_day = context.day
				state.start_day = desired_day
				state.start_phase = MoverEngine.PHASE_MARKET
			state.metadata = {
				"factor": label,
				"streak_days": streak_length,
				"avg_change": average_change
			}
			results.append(state)
		return results

	func _matches_direction(entries: Array) -> bool:
		for entry_dict in entries:
			var entry: Dictionary = entry_dict
			var open_px: float = float(entry.get("open", 0.0))
			var close_px: float = float(entry.get("close", open_px))
			if open_px <= 0.0:
				return false
			var delta: float = close_px - open_px
			if direction >= 0 and delta <= 0.0:
				return false
			if direction < 0 and delta >= 0.0:
				return false
		return true

	func _average_daily_change(entries: Array) -> float:
		var sum_change: float = 0.0
		var count: int = 0
		for entry_dict in entries:
			var entry: Dictionary = entry_dict
			var open_px: float = float(entry.get("open", 0.0))
			var close_px: float = float(entry.get("close", open_px))
			if open_px <= 0.0:
				continue
			var pct: float = (close_px - open_px) / open_px
			sum_change += pct
			count += 1
		if count <= 0:
			return 0.0
		return sum_change / float(count)

var _factors: Array = []

func add_factor(factor: MoverFactor) -> void:
	if factor == null:
		return
	_factors.append(factor)
	_factors.sort_custom(Callable(self, "_sort_by_priority"))

func clear_factors() -> void:
	_factors.clear()

func evaluate(context: Context) -> Array:
	if context == null:
		return []
	var records: Dictionary = {}
	for factor in _factors:
		var produced: Array = factor.evaluate(context)
		for state_obj in produced:
			var state: MoverEngine.MoverState = state_obj
			if state == null:
				continue
			if state.symbol == StringName():
				continue
			var sym_key: StringName = state.symbol
			var entry: Dictionary = {}
			entry["state"] = state
			entry["priority"] = factor.priority
			if records.has(sym_key):
				var current_priority: int = int(records[sym_key].get("priority", -2147483648))
				if factor.priority < current_priority:
					continue
			records[sym_key] = entry
	var result: Array = []
	for record_dict in records.values():
		var out_state: MoverEngine.MoverState = record_dict.get("state", null)
		if out_state != null:
			result.append(out_state)
	return result

func _sort_by_priority(a: MoverFactor, b: MoverFactor) -> bool:
	return a.priority > b.priority
