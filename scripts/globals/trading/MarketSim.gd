extends Node

signal price_updated(symbol: StringName, price: float)
signal prices_changed(prices: Dictionary)

@export var symbols: Array[StringName] = [&"ACME", &"BETA", &"GAMMA"]
@export var start_prices: Array[float] = [100.0, 42.0, 10.0]

# --- Volatility / cadence ---
@export var target_nonmover_abs_move_pct: float = 1.2	# avg |open→close| for non-movers (%). Set 0 to fall back to volatility_pct
@export var volatility_pct: float = 0.005				# legacy: per-tick stdev as FRACTION (0.005 = 0.5%). Used only if target_nonmover_abs_move_pct <= 0
@export var tick_interval_sec: float = 0.25				# base real seconds at base rate
@export var base_minutes_rate: float = 24.0				# your normal minutes_rate at startup (in-game minutes per real second)
@export var clamp_tick_sigma_z: float = 3.0				# clamp single-tick noise to ±Zσ (0 disables)

# --- Market schedule / behavior ---
@export var only_when_market_open: bool = true
@export var clamp_floor: float = 0.01
@export var clamp_ceiling: float = 1000000.0

# --- Mover knobs ---
@export var mover_daily_chance: float = 0.5				# 50% chance there’s a mover today
@export var mover_target_min_pct: float = 0.008			# daily drift floor (0.8%)
@export var mover_target_max_pct: float = 0.020			# daily drift cap   (2.0%)
@export var mover_vol_mult: float = 1.20				# extra choppiness while mover

# --- Debug overlay ---
@export var debug_overlay: bool = true
@export var debug_refresh_sec: float = 0.5
var _debug_layer: CanvasLayer = null
var _debug_label: Label = null
var _debug_accum: float = 0.0

# --- Intraday snapshots ---
var _today_open: Dictionary = {}	# sym -> open price at market open
var _today_close: Dictionary = {}	# sym -> close price at market close

# --- State ---
var _prices: Dictionary = {}			# { StringName: float }
var _timer: Timer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _is_market_open: bool = false
var _last_minutes_rate: float = -1.0
var _mover_symbol: StringName = &""
var _mover_dir: int = 0					# +1 or -1
var _mover_target_daily_drift: float = 0.0	# e.g., 0.02 = +2% over the day

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
		if not Game.day_advanced.is_connected(_on_day_advanced):
			Game.day_advanced.connect(_on_day_advanced)
		_on_phase_changed(Game.phase, Game.day)

	_apply_rate_to_timer(true)

	# Debug UI
	if debug_overlay:
		_ensure_debug_ui()
		_update_debug_ui()

func _process(_dt: float) -> void:
	var mr: float = _get_minutes_rate()
	if mr != _last_minutes_rate:
		_last_minutes_rate = mr
		_apply_rate_to_timer(false)

	# Debug overlay cadence
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

func _minutes_per_tick() -> float:
	# Fixed to base rate so ticks/day stays constant as you speed/slow the clock
	return float(base_minutes_rate) * float(tick_interval_sec)

func _market_minutes_total() -> int:
	if typeof(Game) != TYPE_NIL:
		return max(1, int(Game.T_AFTERMARKET) - int(Game.T_MARKET))
	return 390	# 9:30–16:00

func _ticks_per_market_day() -> int:
	var total_mins: float = float(_market_minutes_total())
	var mpt: float = _minutes_per_tick()
	if mpt <= 0.0:
		return 1
	return max(1, int(round(total_mins / mpt)))

func _sigma_tick_frac_nonmover() -> float:
	# Derive per-tick σ from desired daily E|Δ%| (so daily feel stays stable even if cadence changes)
	if target_nonmover_abs_move_pct > 0.0:
		var N: float = float(_ticks_per_market_day())
		var sigma_day_pct: float = target_nonmover_abs_move_pct / 0.8	# since E|N(0,σ)| ≈ 0.8σ
		var sigma_tick_pct: float = sigma_day_pct / sqrt(N)
		return sigma_tick_pct * 0.01	# % → fraction
	# Fallback to legacy per-tick σ (already a fraction)
	return max(0.0, volatility_pct)

# ---------------- Phase / day ----------------
func _on_phase_changed(phase: StringName, _day: int) -> void:
	_is_market_open = (phase == &"Market")
	if only_when_market_open:
		if _is_market_open:
			_daily_roll_mover()
			_restart_timer()
			_snapshot_opens()
		else:
			_snapshot_closes()
			_clear_daily_mover()
			_stop_timer()
	else:
		if _is_market_open:
			_daily_roll_mover()
			_snapshot_opens()
		else:
			_snapshot_closes()
			_clear_daily_mover()

	if debug_overlay:
		_update_debug_ui()

func _on_day_advanced(_day: int) -> void:
	# Placeholder for daily logic (mean reversion, splits, etc.)
	pass

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

		var p: float = 0.0
		if _prices.has(sym):
			p = float(_prices[sym])

		# Effective per-tick σ (fraction)
		var sigma_eff: float = sigma_base
		if _is_market_open and sym == _mover_symbol and _mover_target_daily_drift > 0.0:
			sigma_eff = sigma_base * mover_vol_mult

		# Zero-mean Gaussian noise
		var eps: float = float(_rng.randfn(0.0, sigma_eff))
		# Optional clamp to kill freak one-tick jumps
		if clamp_tick_sigma_z > 0.0 and sigma_eff > 0.0:
			var lim: float = clamp_tick_sigma_z * sigma_eff
			if eps >  lim: eps =  lim
			if eps < -lim: eps = -lim

		# Add per-tick drift for today's mover (during Market only)
		var step: float = eps
		if _is_market_open and sym == _mover_symbol and _mover_target_daily_drift > 0.0:
			step += _mover_drift_per_tick()

		var new_p: float = clamp(p * (1.0 + step), clamp_floor, clamp_ceiling)

		if new_p != p:
			_prices[sym] = new_p
			emit_signal("price_updated", sym, new_p)

	emit_signal("prices_changed", _prices)

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

func set_volatility(percent_stddev: float) -> void:
	# Legacy setter: only used if target_nonmover_abs_move_pct <= 0
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
func _daily_roll_mover() -> void:
	_mover_symbol = &""
	_mover_dir = 0
	_mover_target_daily_drift = 0.0

	var roll: float = _rng.randf()
	if roll > mover_daily_chance:
		return

	if symbols.is_empty():
		return
	var idx: int = _rng.randi_range(0, symbols.size() - 1)
	_mover_symbol = symbols[idx]

	if _rng.randf() >= 0.5:
		_mover_dir = 1
	else:
		_mover_dir = -1

	var lo: float = min(mover_target_min_pct, mover_target_max_pct)
	var hi: float = max(mover_target_min_pct, mover_target_max_pct)
	_mover_target_daily_drift = _rng.randf_range(lo, hi)

func _clear_daily_mover() -> void:
	_mover_symbol = &""
	_mover_dir = 0
	_mover_target_daily_drift = 0.0

func _mover_drift_per_tick() -> float:
	var total_mins: float = float(_market_minutes_total())
	var mins_per_tick: float = _minutes_per_tick()
	if total_mins <= 0.0 or mins_per_tick <= 0.0:
		return 0.0
	var per_tick: float = _mover_target_daily_drift * (mins_per_tick / total_mins)
	return float(_mover_dir) * per_tick

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
	label.add_theme_font_size_override("font_size", 12)
	label.position = Vector2(8, 8)
	label.size = Vector2(380, 0)	# auto-height
	_debug_layer.add_child(label)
	_debug_label = label

func _update_debug_ui() -> void:
	if _debug_label == null:
		return

	var lines: Array[String] = []

	# Time / market
	var time_str: String = ""
	var dstr: String = ""
	var phase_str: String = ""
	var open_str: String = ""

	if typeof(Game) != TYPE_NIL and Game.has_method("get_time_string"):
		time_str = String(Game.get_time_string())
	if typeof(Game) != TYPE_NIL:
		dstr = "Day " + str(int(Game.day))
		phase_str = String(Game.phase)
		if _is_market_open:
			open_str = "Open"
		else:
			open_str = "Closed"

	# Tick timing
	var eff_wait: float = tick_interval_sec
	if _timer != null:
		eff_wait = _timer.wait_time
	var mr: float = 0.0
	if typeof(Game) != TYPE_NIL:
		mr = float(Game.minutes_rate)
	var mins_per_tick: float = _minutes_per_tick()
	var N: int = _ticks_per_market_day()
	var sig_tick_pct: float = _sigma_tick_frac_nonmover() * 100.0
	var sig_day_pct: float = sig_tick_pct * sqrt(float(N))
	var exp_abs_move: float = 0.8 * sig_day_pct

	lines.append("⏱  " + time_str + "  |  " + dstr + "  |  " + phase_str + " (" + open_str + ")")
	lines.append("🎛  symbols=" + str(symbols.size()) + "  tick=" + _fmt_secs(eff_wait) + "  base_mpt=" + _fmt_min(mins_per_tick) + "  min_rate=" + String.num(mr, 2))
	lines.append("📈  N=" + str(N) + "  σ_tick≈" + String.num(sig_tick_pct, 3) + "%  σ_day≈" + String.num(sig_day_pct, 2) + "%  E|Δ|≈" + String.num(exp_abs_move, 2) + "%")

	# Mover (if any)
	var mover_line: String = "none"
	if _is_market_open and _mover_symbol != &"" and _mover_target_daily_drift > 0.0:
		var dir_str: String = "+"
		if _mover_dir < 0:
			dir_str = "-"
		var tgt_pct: float = _mover_target_daily_drift * 100.0
		var drift_tick_pct: float = _mover_drift_per_tick() * 100.0
		mover_line = String(_mover_symbol) + "  " + dir_str + String.num(tgt_pct, 2) + "%  vol×" + String.num(mover_vol_mult, 2) + "  drift/tick=" + String.num(drift_tick_pct, 3) + "%"

	lines.append("🔥  mover: " + mover_line)

	_debug_label.text = "\n".join(lines)

func _fmt_secs(s: float) -> String:
	if s >= 1.0:
		return String.num(s, 2) + "s"
	else:
		return String.num(s * 1000.0, 0) + "ms"

func _fmt_min(m: float) -> String:
	return String.num(m, 2) + "m"
