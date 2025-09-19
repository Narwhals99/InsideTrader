extends Node

signal phase_changed(phase: StringName, day: int)
signal day_advanced(day: int)

var next_spawn: String = ""	# used by your portals/doors

const PHASE_ORDER: Array[StringName] = [&"Morning", &"Market", &"Evening", &"LateNight"]

var day: int = 1
var phase: StringName = &"Morning"
var _phase_index: int = 0

# -------------------- CLOCK --------------------
const MINUTES_PER_DAY: int = 24 * 60
const T_MORNING: int = 6 * 60
const T_MARKET: int = 9 * 60 + 30
const T_AFTERMARKET: int = 16 * 60
const T_EVENING_END: int = 22 * 60

@export var minutes_rate: float = 0.5			# in-game minutes per real second

var clock_minutes: int = T_MORNING
var _minute_accum: float = 0.0
var _clock_running: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS	# keep time advancing even if UI pauses the tree
	set_process(true)
	# start in Morning, synced
	clock_minutes = T_MORNING
	_phase_index = 0
	phase = PHASE_ORDER[_phase_index]
	emit_signal("phase_changed", phase, day)
	__ws_accum = float(clock_minutes) * 60.0
	__ws_last_us = Time.get_ticks_usec()


func _process(delta: float) -> void:
	if not _clock_running:
		return
	_minute_accum += delta * minutes_rate
	while _minute_accum >= 1.0:
		_advance_minutes(1)
		_minute_accum -= 1.0

func _advance_minutes(n: int) -> void:
	clock_minutes = clamp(clock_minutes + n, 0, MINUTES_PER_DAY - 1)
	_update_phase_if_needed()

func _update_phase_if_needed() -> void:
	var p: StringName = _phase_from_minutes(clock_minutes)
	if p != phase:
		phase = p
		emit_signal("phase_changed", phase, day)
		if phase == &"Morning":
			day += 1
			emit_signal("day_advanced", day)

func _phase_from_minutes(m: int) -> StringName:
	if m >= T_MARKET and m < T_AFTERMARKET:
		return &"Market"
	if m >= T_AFTERMARKET and m < T_EVENING_END:
		return &"Evening"
	if m >= T_EVENING_END or m < T_MORNING:
		return &"LateNight"
	return &"Morning"

func is_market_open() -> bool:
	return clock_minutes >= T_MARKET and clock_minutes < T_AFTERMARKET

func minutes_until_market_close() -> int:
	if clock_minutes >= T_AFTERMARKET:
		return 0
	return max(0, T_AFTERMARKET - clock_minutes)

func get_hour() -> int:
	return int(floor(float(clock_minutes) / 60.0)) % 24

func get_minute() -> int:
	return clock_minutes % 60

func get_time_string() -> String:
	var h: int = get_hour()
	var m: int = get_minute()
	var am: bool = h < 12
	var h12: int = h % 12
	if h12 == 0:
		h12 = 12
	var suffix: String = " AM"
	if not am:
		suffix = " PM"
	return str(h12).pad_zeros(2) + ":" + str(m).pad_zeros(2) + suffix

func set_clock_running(r: bool) -> void:
	_clock_running = r

# -------------------- TIME SETTER --------------------
func set_time(h: int, m: int) -> void:
	var minutes: int = (h % 24) * 60 + (m % 60)
	minutes = clamp(minutes, 0, MINUTES_PER_DAY - 1)
	clock_minutes = minutes
	# keep world-seconds aligned with the visible clock
	__ws_accum = float(minutes) * 60.0
	__ws_last_us = Time.get_ticks_usec()  # reset delta so the next step isn't huge
	_update_phase_if_needed()

func sleep_to_morning() -> void:
	day += 1
	_phase_index = 0
	phase = PHASE_ORDER[_phase_index]
	clock_minutes = T_MORNING
	__ws_accum = float(clock_minutes) * 60.0
	__ws_last_us = Time.get_ticks_usec()
	_clock_running = true
	emit_signal("day_advanced", day)
	emit_signal("phase_changed", phase, day)


# -------------------- PHASE API (kept) --------------------
func set_phase(p: StringName) -> void:
	if p == phase:
		return
	var idx: int = PHASE_ORDER.find(p)
	if idx == -1:
		push_warning("Unknown phase: %s" % String(p))
		return
	_phase_index = idx
	phase = p
	emit_signal("phase_changed", phase, day)

func advance_phase() -> void:
	# jump to next phase START (keeps clock/phase in sync)
	if phase == &"Morning":
		set_time(9, 30)
	elif phase == &"Market":
		set_time(16, 0)
	elif phase == &"Evening":
		set_time(20, 0)
	else:
		# LateNight -> next morning
		sleep_to_morning()

func previous_phase() -> void:
	# jump to previous phase START
	if phase == &"Market":
		set_time(6, 0)
	elif phase == &"Evening":
		set_time(9, 30)
	elif phase == &"LateNight":
		set_time(16, 0)
	else:
		# Morning -> previous LateNight (22:00 for convenience)
		set_time(20, 0)


# -------------------- INPUT / DEV HOTKEYS --------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			# Phase jumps (kept)
			KEY_BRACKETRIGHT:
				advance_phase()
			KEY_BRACKETLEFT:
				previous_phase()

			# Direct phase start times (kept)
			KEY_1:
				set_time(6, 0)		# Morning
			KEY_2:
				set_time(9, 30)		# Market
			KEY_3:
				set_time(16, 0)		# Aftermarket (Evening)
			KEY_4:
				set_time(20, 0)		# LateNight

			# Clock controls
			KEY_T:
				# toggles running/paused without any ternary expressions
				_clock_running = not _clock_running
				var status: String = "running"
				if not _clock_running:
					status = "paused"
				print("[Clock] ", status)
			KEY_EQUAL:				# '+' (Shift + '=' on US)
				minutes_rate = min(minutes_rate * 2.0, 480.0)
				print("[Clock] rate =", minutes_rate, " min/sec")
			KEY_MINUS:
				minutes_rate = max(minutes_rate * 0.5, 0.05)
				print("[Clock] rate =", minutes_rate, " min/sec")
			KEY_H:
				_advance_minutes(60)
				print("[Clock]", get_time_string())

			# Quick test trade keys (kept)
			KEY_B:
				if String(phase) != "Market":
					print("[BUY] Market closed")
					return
				var p_buy: float = MarketSim.get_price(&"ACME")
				var ok_buy: bool = Portfolio.buy(&"ACME", 1, p_buy)
				print("[BUY ACME @", p_buy, "] ok=", ok_buy, " cash=", Portfolio.cash, " pos=", Portfolio.get_position(&"ACME"))
			KEY_N:
				if String(phase) != "Market":
					print("[SELL] Market closed")
					return
				var p_sell: float = MarketSim.get_price(&"ACME")
				var ok_sell: bool = Portfolio.sell(&"ACME", 1, p_sell)
				print("[SELL ACME @", p_sell, "] ok=", ok_sell, " cash=", Portfolio.cash, " pos=", Portfolio.get_position(&"ACME"))

			# Phone toggle (Tab) supports Autoload "Phone" OR scene-local group "phone_ui"
			KEY_TAB:
				# 1) Autoload case
				if has_node("/root/Phone"):
					var phone: CanvasLayer = get_node("/root/Phone") as CanvasLayer
					if phone:
						if phone.visible:
							phone.call("close")
						else:
							phone.call("open")
					return
				# 2) Scene-local case
				var nodes: Array = get_tree().get_nodes_in_group("phone_ui")
				if nodes.size() == 0:
					print("[Phone] No PhoneUI in this scene")
					return
				var ui_node: Node = nodes[0]
				if not ui_node.has_method("open"):
					print("[Phone] UI missing open()/close()")
					return
				var ui_layer: CanvasLayer = ui_node as CanvasLayer
				if ui_layer and ui_layer.visible:
					ui_node.call("close")
				else:
					ui_node.call("open")

			_:
				pass

# --- WORLD CLOCK (typed, warnings-as-errors safe) ---

var __ws_last_us: int = -1
var __ws_accum: float = 0.0

func get_world_seconds() -> float:
	var now_us: int = Time.get_ticks_usec()
	if __ws_last_us < 0:
		__ws_last_us = now_us  # first-call init (no jump)
	var dt_real: float = float(now_us - __ws_last_us) / 1_000_000.0
	__ws_last_us = now_us

	# Minutes of game-time per real second (defaults to 24)
	var minutes_rate_local: float = 0.5  # CHANGED from 24.0 to 0.5
	if _has_prop("minutes_rate"):
		var mr_val: Variant = get("minutes_rate")
		if typeof(mr_val) == TYPE_FLOAT or typeof(mr_val) == TYPE_INT:
			minutes_rate = float(mr_val)
	elif _has_prop("base_minutes_rate"):
		var bmr_val: Variant = get("base_minutes_rate")
		if typeof(bmr_val) == TYPE_FLOAT or typeof(bmr_val) == TYPE_INT:
			minutes_rate = float(bmr_val)

	# Optional global time scale (dev speed-up)
	var time_scale: float = 1.0
	if _has_prop("dev_time_scale"):
		var ts_val: Variant = get("dev_time_scale")
		if typeof(ts_val) == TYPE_FLOAT or typeof(ts_val) == TYPE_INT:
			time_scale = float(ts_val)
	elif _has_prop("time_scale"):
		var ts2_val: Variant = get("time_scale")
		if typeof(ts2_val) == TYPE_FLOAT or typeof(ts2_val) == TYPE_INT:
			time_scale = float(ts2_val)

	# Advance world seconds (0..86400)
	__ws_accum = fposmod(__ws_accum + dt_real * minutes_rate * time_scale * 60.0, 86400.0)
	return __ws_accum

func _has_prop(name: String) -> bool:
	var plist: Array = get_property_list()
	for i in range(plist.size()):
		var p: Dictionary = plist[i]
		if String(p.get("name", "")) == name:
			return true
	return false
