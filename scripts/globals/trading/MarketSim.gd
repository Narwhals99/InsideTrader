extends Node

const MoverEngine = preload("res://scripts/globals/trading/MoverEngine.gd")
const MoverTriggerEngine = preload("res://scripts/globals/trading/MoverTriggerEngine.gd")
const OptionMarketService = preload("res://scripts/services/OptionMarketService.gd")

signal price_updated(symbol: StringName, price: float)
signal prices_changed(prices: Dictionary)

# List of tickers simulated in the market.
@export var symbols: Array[StringName] = [
	&"ACME",
	&"BETA",
	&"GAMMA",
	&"ORBX",
	&"QUAD",
	&"RIFT",
	&"SOLR",
	&"VENT",
	&"WAVE",
	&"ZENX"
]
# Starting price for each symbol in the same order as `symbols`.
@export var start_prices: Array[float] = [
	100.0,
	42.0,
	10.0,
	75.0,
	28.5,
	55.5,
	230.0,
	15.0,
	180.0,
	64.0
]

# Target absolute daily move (percent) for tickers without movers.
@export var target_nonmover_abs_move_pct: float = 1.2
# Fallback per-tick sigma when target_nonmover_abs_move_pct is zero.
@export var volatility_pct: float = 0.005
# Real-time seconds between price ticks.
@export var tick_interval_sec: float = 2.0
# Baseline in-game minutes advanced per tick.
@export var base_minutes_rate: float = 0.5
# Maximum Z-score used to clamp per-tick noise.
@export var clamp_tick_sigma_z: float = 3.0

# Restrict ticking to the market phase when true.
@export var only_when_market_open: bool = true
# Hard floor for simulated prices.
@export var clamp_floor: float = 0.01
# Hard ceiling for simulated prices.
@export var clamp_ceiling: float = 1000000.0

# Chance that a mover is generated on a given market open.
@export var mover_daily_chance: float = 0.5
# Minimum fraction drift targeted by movers.
@export var mover_target_min_pct: float = 0.008
# Maximum fraction drift targeted by movers.
@export var mover_target_max_pct: float = 0.020
# Volatility multiplier while a mover is active.
@export var mover_vol_mult: float = 1.20
# Number of recent days used by the streak factor.
@export var mover_streak_length: int = 3
# Minimum average daily change to qualify for a streak mover.
@export var mover_streak_min_avg_pct: float = 0.004
# Lead time (days) before a positive streak mover activates.
@export var mover_positive_lead_days: int = 1
# Duration (days) that positive streak movers remain active.
@export var mover_positive_duration_days: int = 2
# Lead time (days) before a negative streak mover activates.
@export var mover_negative_lead_days: int = 0
# Duration (days) that negative streak movers remain active.
@export var mover_negative_duration_days: int = 1
# Multiplier applied to swing mover drift targets.
@export var mover_swing_target_multiplier: float = 1.5
# Multiplier applied to intraday mover drift targets.
@export var mover_intraday_target_multiplier: float = 1.0

# Enable the on-screen market diagnostics overlay.
@export var debug_overlay: bool = true
# Seconds between debug overlay refreshes.
@export var debug_refresh_sec: float = 0.5
var _debug_layer: CanvasLayer = null
var _debug_label: Label = null
var _debug_accum: float = 0.0

# --- Intraday snapshots ---
var _today_open: Dictionary = {}
var _today_close: Dictionary = {}

# --- State ---
var _prices: Dictionary = {}
var _timer: Timer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _is_market_open: bool = false
var _last_minutes_rate: float = -1.0
var _movers: MoverEngine = MoverEngine.new()
var _mover_triggers: MoverTriggerEngine = null

# --- Insider Trading Support ---
var _forced_next_mover: StringName = &""
var _forced_next_move_size: float = 0.0

# Rolling daily history: { sym -> Array[{day:int, open:float, close:float}] }
var history: Dictionary = {}
const MAX_HISTORY_DAYS: int = 60

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_seed_prices()

	_timer = Timer.new()
	_timer.one_shot = false
	_timer.autostart = false
	_timer.wait_time = tick_interval_sec
	_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_timer)
	_timer.timeout.connect(_on_tick)

	if Game != null:
		if Game.minutes_rate > 0.0:
			base_minutes_rate = float(Game.minutes_rate)
		if not Game.phase_changed.is_connected(_on_phase_changed):
			Game.phase_changed.connect(_on_phase_changed)
		if not Game.phase_changed.is_connected(_on_game_phase_changed):
			Game.phase_changed.connect(_on_game_phase_changed)
		if not Game.day_advanced.is_connected(_on_day_advanced):
			Game.day_advanced.connect(_on_day_advanced)
		_on_phase_changed(Game.phase, Game.day)

	_apply_rate_to_timer(true)
	_setup_mover_triggers()

func _on_game_phase_changed(new_phase: StringName, day: int) -> void:
	var ph := String(new_phase).to_lower()
	if ph == "evening" or ph == "afterhours" or ph == "close" or ph == "closed":
		_record_today_to_history(int(day))

func _record_today_to_history(day: int) -> void:
	for sn in symbols:
		var sym: StringName = sn
		var open_px: float = get_today_open(sym)
		if open_px <= 0.0:
			continue
		var close_px: float = get_today_close(sym)
		if close_px <= 0.0:
			close_px = get_price(sym)
		_history_append(sym, day, open_px, close_px)

	if debug_overlay:
		_ensure_debug_ui()
		_update_debug_ui()

func _process(_dt: float) -> void:
	var mr: float = _get_minutes_rate()
	if mr != _last_minutes_rate:
		_last_minutes_rate = mr
		_apply_rate_to_timer(false)

	if debug_overlay:
		_debug_accum += _dt
		if _debug_accum >= debug_refresh_sec:
			_debug_accum = 0.0
			_ensure_debug_ui()
			_update_debug_ui()

# ---------------- Core helpers ----------------
func _seed_prices() -> void:
	_prices.clear()
	var n: int = max(symbols.size(), start_prices.size())
	for i in range(n):
		var sym: StringName
		if i < symbols.size():
			sym = symbols[i]
		else:
			sym = StringName("SYM" + str(i))

		var p: float
		if i < start_prices.size():
			p = start_prices[i]
		else:
			p = 100.0

		_prices[sym] = max(clamp_floor, p)

	emit_signal("prices_changed", _prices)
	_refresh_option_market()

func _minutes_per_tick() -> float:
	return float(base_minutes_rate) * float(tick_interval_sec)

func _market_minutes_total() -> int:
	if typeof(Game) != TYPE_NIL:
		return max(1, int(Game.T_AFTERMARKET) - int(Game.T_MARKET))
	return 390

func _ticks_per_market_day() -> int:
	var total_mins: float = float(_market_minutes_total())
	var mpt: float = _minutes_per_tick()
	if mpt <= 0.0:
		return 1
	return max(1, int(round(total_mins / mpt)))

func _sigma_tick_frac_nonmover() -> float:
	if target_nonmover_abs_move_pct > 0.0:
		var n_ticks: float = float(_ticks_per_market_day())
		var sigma_day_pct: float = target_nonmover_abs_move_pct / 0.8
		var sigma_tick_pct: float = sigma_day_pct / sqrt(n_ticks)
		return sigma_tick_pct * 0.01
	return max(0.0, volatility_pct)

# ---------------- Phase / day ----------------
func _on_phase_changed(phase: StringName, day: int) -> void:
	_movers.update_clock(int(day), phase)
	var weekend: bool = false
	if typeof(Game) != TYPE_NIL and Game.has_method("is_weekend"):
		weekend = Game.is_weekend()
	_is_market_open = (phase == &"Market") and not weekend
	if only_when_market_open:
		if _is_market_open:
			_daily_roll_mover(int(day), phase)
			_restart_timer()
			_snapshot_opens()
		else:
			_snapshot_closes()
			_clear_daily_mover()
			_stop_timer()
	else:
		if _is_market_open:
			_daily_roll_mover(int(day), phase)
			_snapshot_opens()
		else:
			_snapshot_closes()
			_clear_daily_mover()

	if debug_overlay:
		_update_debug_ui()
	_refresh_option_market()

func _on_day_advanced(day: int) -> void:
	_movers.notify_day_advanced(int(day))
	_refresh_option_market()

# ---------------- Timer scaling ----------------
func _apply_rate_to_timer(force_restart: bool) -> void:
	var scale: float = _compute_rate_scale()
	_timer.wait_time = tick_interval_sec / scale

	if only_when_market_open and not _is_market_open:
		_stop_timer()
		return

	if force_restart or _timer.is_stopped():
		_restart_timer()

func _restart_timer() -> void:
	if not _timer.is_stopped():
		_timer.stop()
	_timer.start()

func _stop_timer() -> void:
	if not _timer.is_stopped():
		_timer.stop()

func _compute_rate_scale() -> float:
	var mr: float = _get_minutes_rate()
	_last_minutes_rate = mr
	var denom: float = max(0.01, base_minutes_rate)
	return max(0.01, mr / denom)

func _get_minutes_rate() -> float:
	if Game == null:
		return base_minutes_rate
	var v: float = float(Game.minutes_rate)
	if v > 0.0:
		return v
	return base_minutes_rate

# ---------------- Ticking ----------------
func _on_tick() -> void:
	if _prices.is_empty():
		return

	var sigma_base: float = _sigma_tick_frac_nonmover()
	var keys: Array = _prices.keys()

	for i in range(keys.size()):
		var sym: StringName = StringName(keys[i])
		var p: float = float(_prices.get(sym, 0.0))

		var mover_state: MoverEngine.MoverState = null
		if _is_market_open:
			mover_state = _movers.get_state_for_symbol(sym)

		var sigma_eff: float = sigma_base
		if mover_state != null and mover_state.is_active():
			sigma_eff = sigma_base * mover_vol_mult

		var eps: float = float(_rng.randfn(0.0, sigma_eff))
		if clamp_tick_sigma_z > 0.0 and sigma_eff > 0.0:
			var lim: float = clamp_tick_sigma_z * sigma_eff
			eps = clamp(eps, -lim, lim)

		var step: float = eps
		if mover_state != null and mover_state.is_active():
			step += _mover_drift_per_tick(mover_state)

		var new_p: float = clamp(p * (1.0 + step), clamp_floor, clamp_ceiling)

		if new_p != p:
			_prices[sym] = new_p
			emit_signal("price_updated", sym, new_p)

	emit_signal("prices_changed", _prices)
	_refresh_option_market()

func _refresh_option_market() -> void:
	if typeof(OptionMarketService) == TYPE_NIL:
		return
	var current_day: int = 0
	var phase_sn: StringName = &"Market"
	if typeof(Game) != TYPE_NIL:
		current_day = int(Game.day)
		var gp = Game.phase
		if gp is StringName:
			phase_sn = gp
		else:
			phase_sn = StringName(String(gp))
	OptionMarketService.refresh_all(_prices.duplicate(true), current_day, phase_sn)

# ---------------- Public API ----------------
func get_price(symbol: StringName) -> float:
	if _prices.has(symbol):
		return float(_prices[symbol])
	return 0.0

func get_all_prices() -> Dictionary:
	return _prices.duplicate(true)

func set_price(symbol: StringName, price: float) -> void:
	var p: float = max(clamp_floor, price)
	_prices[symbol] = p
	emit_signal("price_updated", symbol, p)
	emit_signal("prices_changed", _prices)
	_refresh_option_market()

func set_volatility(percent_stddev: float) -> void:
	volatility_pct = max(0.0, percent_stddev)

func set_tick_interval(sec: float) -> void:
	tick_interval_sec = max(0.01, sec)
	_apply_rate_to_timer(false)

func force_market_open(open_now: bool) -> void:
	_is_market_open = open_now
	if open_now:
		_restart_timer()
	else:
		_stop_timer()

# ---------------- Mover logic ----------------
func _daily_roll_mover(day: int, phase: StringName) -> void:
	if _forced_next_mover != StringName() and _forced_next_move_size > 0.0:
		var forced_symbol: StringName = _forced_next_mover
		var forced_drift: float = _forced_next_move_size
		var direction: int = 1
		if forced_drift < 0.04:
			direction = 1 if _rng.randf() >= 0.5 else -1
		var state := MoverEngine.MoverState.new()
		state.symbol = forced_symbol
		state.direction = direction
		state.target_daily_drift = abs(forced_drift)
		state.start_mode = MoverEngine.StartMode.NEXT_SESSION
		_movers.activate_from_state(state)
		print("[MarketSim] Using forced mover: ", String(state.symbol), " dir=", state.direction, " drift=", String.num(state.target_daily_drift * 100.0, 2), "%")
		_forced_next_mover = StringName()
		_forced_next_move_size = 0.0
		return

	_setup_mover_triggers()
	var context: MoverTriggerEngine.Context = _build_mover_context(int(day), phase)
	var states: Array = _mover_triggers.evaluate(context)
	if states.is_empty():
		return

	for state in states:
		_movers.activate_from_state(state)
		var factor_label: String = String(state.metadata.get("factor", "unknown"))
		var drift_pct: String = String.num(state.target_daily_drift * 100.0, 2)
		var horizon_label: String = "swing" if state.horizon == MoverEngine.HorizonType.SWING else "day"
		print("[MarketSim] Trigger mover: ", String(state.symbol), " factor=", factor_label, " dir=", state.direction, " drift=", drift_pct, "% horizon=", horizon_label, " start_mode=", state.start_mode)


func _setup_mover_triggers() -> void:
	if _mover_triggers == null:
		_mover_triggers = MoverTriggerEngine.new()
	else:
		_mover_triggers.clear_factors()

	var random_factor: MoverTriggerEngine.RandomDailyFactor = MoverTriggerEngine.RandomDailyFactor.new()
	_mover_triggers.add_factor(random_factor)

	var positive_settings: Dictionary = {
		"priority": 20,
		"length": mover_streak_length,
		"direction": 1,
		"start_mode": MoverEngine.StartMode.NEXT_SESSION,
		"horizon": MoverEngine.HorizonType.SWING,
		"duration_days": max(1, mover_positive_duration_days),
		"min_average": mover_streak_min_avg_pct,
		"lead_days": max(0, mover_positive_lead_days),
		"target_multiplier": mover_swing_target_multiplier,
		"label": "streak_positive"
	}
	_mover_triggers.add_factor(MoverTriggerEngine.StreakFactor.new(positive_settings))

	var negative_settings: Dictionary = {
		"priority": 15,
		"length": mover_streak_length,
		"direction": -1,
		"start_mode": MoverEngine.StartMode.IMMEDIATE,
		"horizon": MoverEngine.HorizonType.INTRADAY,
		"duration_days": max(1, mover_negative_duration_days),
		"min_average": mover_streak_min_avg_pct,
		"lead_days": max(0, mover_negative_lead_days),
		"target_multiplier": mover_intraday_target_multiplier,
		"label": "streak_negative"
	}
	_mover_triggers.add_factor(MoverTriggerEngine.StreakFactor.new(negative_settings))


func _build_mover_context(day: int, phase: StringName) -> MoverTriggerEngine.Context:
	var ctx: MoverTriggerEngine.Context = MoverTriggerEngine.Context.new()
	ctx.day = day
	ctx.phase = phase
	ctx.symbols = symbols.duplicate()
	ctx.prices = _prices.duplicate(true)
	ctx.history = history.duplicate(true)
	ctx.today_open = _today_open.duplicate(true)
	ctx.today_close = _today_close.duplicate(true)
	ctx.rng = _rng
	ctx.get_last_days = Callable(self, "get_last_n_days")
	ctx.config = {
		"mover_daily_chance": mover_daily_chance,
		"mover_target_min_pct": mover_target_min_pct,
		"mover_target_max_pct": mover_target_max_pct
	}
	return ctx


func _clear_daily_mover() -> void:
	_movers.clear_intraday_states()

func _mover_drift_per_tick(state: MoverEngine.MoverState) -> float:
	if state == null or not state.is_active():
		return 0.0
	var total_mins: float = float(_market_minutes_total())
	var mins_per_tick: float = _minutes_per_tick()
	if total_mins <= 0.0 or mins_per_tick <= 0.0:
		return 0.0
	var per_tick: float = state.target_daily_drift * (mins_per_tick / total_mins)
	return float(state.direction) * per_tick

# ---------------- Intraday snapshots ----------------
func get_today_open(sym: StringName) -> float:
	return float(_today_open.get(sym, 0.0))

func get_today_close(sym: StringName) -> float:
	return float(_today_close.get(sym, 0.0))

func get_today_change_pct(sym: StringName) -> float:
	if not _today_open.has(sym):
		return 0.0
	var o: float = float(_today_open[sym])
	if o <= 0.0:
		return 0.0
	var p: float = get_price(sym)
	return (p - o) / o * 100.0

func _snapshot_opens() -> void:
	_today_open.clear()
	for sn in symbols:
		var s: StringName = sn
		_today_open[s] = get_price(s)
	_today_close.clear()

func _snapshot_closes() -> void:
	_today_close.clear()
	for sn in symbols:
		var s: StringName = sn
		_today_close[s] = get_price(s)

# ---------------- Debug overlay ----------------
func _ensure_debug_ui() -> void:
	if not debug_overlay:
		if _debug_layer != null:
			_debug_layer.queue_free()
			_debug_layer = null
			_debug_label = null
		return

	if _debug_layer != null:
		return

	_debug_layer = CanvasLayer.new()
	_debug_layer.layer = 99
	_debug_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_debug_layer)

	var label := Label.new()
	label.text = ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 12)
	label.position = Vector2(8, 8)
	label.size = Vector2(380, 0)
	_debug_layer.add_child(label)
	_debug_label = label

func _update_debug_ui() -> void:
	if _debug_label == null:
		return

	var lines: Array[String] = []

	var time_str: String = ""
	var day_str: String = ""
	var phase_str: String = ""
	var open_str: String = ""

	if typeof(Game) != TYPE_NIL and Game.has_method("get_time_string"):
		time_str = String(Game.get_time_string())
	if typeof(Game) != TYPE_NIL:
		day_str = "Day " + str(int(Game.day))
		phase_str = String(Game.phase)
		open_str = "Open" if _is_market_open else "Closed"

	var eff_wait: float = _timer.wait_time if _timer != null else tick_interval_sec
	var mr: float = 0.0
	if typeof(Game) != TYPE_NIL:
		mr = float(Game.minutes_rate)
	var mins_per_tick: float = _minutes_per_tick()
	var n_ticks: int = _ticks_per_market_day()
	var sig_tick_pct: float = _sigma_tick_frac_nonmover() * 100.0
	var sig_day_pct: float = sig_tick_pct * sqrt(float(n_ticks))
	var exp_abs_move: float = 0.8 * sig_day_pct

	lines.append("[clock] " + time_str + "  |  " + day_str + "  |  " + phase_str + " (" + open_str + ")")
	lines.append("[knobs] symbols=" + str(symbols.size()) + "  tick=" + String.num(eff_wait, 2) + "s  base_mpt=" + String.num(mins_per_tick, 2) + "m  min_rate=" + String.num(mr, 2))
	lines.append("[chart] N=" + str(n_ticks) + "  sigma_tick approx " + String.num(sig_tick_pct, 3) + "%  sigma_day approx " + String.num(sig_day_pct, 2) + "%  E|delta| approx " + String.num(exp_abs_move, 2) + "%")

	var mover_line: String = "none"
	var active_states := _movers.get_active_states()
	if _is_market_open and not active_states.is_empty():
		var parts: Array[String] = []
		for state_obj in active_states:
			var state: MoverEngine.MoverState = state_obj
			if state == null or not state.is_active():
				continue
			var dir_str: String = "+" if state.direction >= 0 else "-"
			var tgt_pct: float = state.target_daily_drift * 100.0
			var horizon_label: String = "swing" if state.horizon == MoverEngine.HorizonType.SWING else "day"
			var tick_pct: float = _mover_drift_per_tick(state) * 100.0
			parts.append(String(state.symbol) + "  " + dir_str + String.num(tgt_pct, 2) + "% " + horizon_label + " drift/tick=" + String.num(tick_pct, 3) + "%")
		if not parts.is_empty():
			mover_line = "; ".join(parts)
	else:
		var summary := _movers.debug_summary()
		if summary != "none":
			mover_line = summary

	lines.append("[fire] mover: " + mover_line)

	_debug_label.text = "\n".join(lines)

# ---------------- Public helpers ----------------
func force_next_mover(ticker: StringName, move_percent: float) -> void:
	_forced_next_mover = ticker
	_forced_next_move_size = abs(move_percent)
	print("[MarketSim] Next mover forced: ", ticker, " @ ", move_percent * 100.0, "%")

func get_current_mover() -> Dictionary:
	var state := _movers.get_active_state()
	if not state.is_active():
		return {"active": false}
	return {
		"active": true,
		"symbol": state.symbol,
		"direction": state.direction,
		"target_drift": state.target_daily_drift
	}

# ---------------- History helpers ----------------
func _history_ensure(sym: StringName) -> void:
	if not history.has(sym):
		history[sym] = []

func _history_append(sym: StringName, day: int, open_px: float, close_px: float) -> void:
	_history_ensure(sym)
	var arr: Array = history[sym]
	arr.append({"day": day, "open": open_px, "close": close_px})
	if arr.size() > MAX_HISTORY_DAYS:
		arr = arr.slice(arr.size() - MAX_HISTORY_DAYS, arr.size())
	history[sym] = arr

func get_last_n_days(symbol: StringName, count: int) -> Array:
	var result: Array = []
	if count <= 0:
		return result
	var sn: StringName = symbol
	if not history.has(sn):
		return result
	var entries: Array = history[sn] as Array
	if entries.is_empty():
		return result
	var start: int = max(0, entries.size() - count)
	for i in range(start, entries.size()):
		var entry_dict: Dictionary = entries[i] as Dictionary
		result.append(entry_dict.duplicate(true))
	return result
