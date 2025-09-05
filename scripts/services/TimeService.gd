# TimeService.gd
# Provides a clean API for all time-related queries
class_name TimeService
extends Resource

# Time constants (matching your Game.gd)
const MINUTES_PER_DAY: int = 24 * 60
const T_MORNING: int = 6 * 60          # 06:00
const T_MARKET: int = 9 * 60 + 30      # 09:30  
const T_AFTERMARKET: int = 16 * 60     # 16:00
const T_EVENING_END: int = 22 * 60     # 22:00

const PHASE_MORNING = "Morning"
const PHASE_MARKET = "Market"
const PHASE_EVENING = "Evening"
const PHASE_LATENIGHT = "LateNight"

# ============ QUERIES ============
static func get_current_time() -> Dictionary:
	if typeof(Game) == TYPE_NIL:
		return {"hour": 6, "minute": 0, "day": 1, "phase": PHASE_MORNING}
	
	return {
		"hour": Game.get_hour(),
		"minute": Game.get_minute(),
		"day": Game.day,
		"phase": String(Game.phase),
		"clock_minutes": Game.clock_minutes,
		"time_string": Game.get_time_string()
	}

static func get_world_seconds() -> float:
	if typeof(Game) != TYPE_NIL and Game.has_method("get_world_seconds"):
		return Game.get_world_seconds()
	return 0.0

static func is_phase(phase_name: String) -> bool:
	if typeof(Game) == TYPE_NIL:
		return false
	return String(Game.phase) == phase_name

static func is_market_hours() -> bool:
	return is_phase(PHASE_MARKET)

static func is_evening() -> bool:
	return is_phase(PHASE_EVENING)

static func is_late_night() -> bool:
	return is_phase(PHASE_LATENIGHT)

static func minutes_until_phase(phase_name: String) -> int:
	if typeof(Game) == TYPE_NIL:
		return -1
	
	var current_minutes: int = Game.clock_minutes
	var target_minutes: int = _get_phase_start_time(phase_name)
	
	if target_minutes < 0:
		return -1
	
	# Handle next day wrap
	if target_minutes <= current_minutes:
		return (MINUTES_PER_DAY - current_minutes) + target_minutes
	
	return target_minutes - current_minutes

# ============ FORMATTERS ============
static func format_time(minutes: int) -> String:
	var hours: int = int(minutes / 60) % 24
	var mins: int = minutes % 60
	var period: String = "AM"
	
	if hours >= 12:
		period = "PM"
		if hours > 12:
			hours -= 12
	elif hours == 0:
		hours = 12
	
	return "%d:%02d %s" % [hours, mins, period]

static func format_current_time() -> String:
	if typeof(Game) != TYPE_NIL and Game.has_method("get_time_string"):
		return Game.get_time_string()
	return "??:??"

# ============ SCHEDULE HELPERS ============
static func get_phase_for_minutes(minutes: int) -> String:
	if minutes >= T_MARKET and minutes < T_AFTERMARKET:
		return PHASE_MARKET
	elif minutes >= T_AFTERMARKET and minutes < T_EVENING_END:
		return PHASE_EVENING
	elif minutes >= T_EVENING_END or minutes < T_MORNING:
		return PHASE_LATENIGHT
	else:
		return PHASE_MORNING

static func _get_phase_start_time(phase_name: String) -> int:
	match phase_name:
		PHASE_MORNING:
			return T_MORNING
		PHASE_MARKET:
			return T_MARKET
		PHASE_EVENING:
			return T_AFTERMARKET
		PHASE_LATENIGHT:
			return T_EVENING_END
		_:
			return -1

# ============ TIME MANIPULATION ============
static func request_sleep() -> void:
	EventBus.emit_signal("sleep_requested")
	if typeof(Game) != TYPE_NIL and Game.has_method("sleep_to_morning"):
		Game.sleep_to_morning()

static func set_time(hour: int, minute: int) -> void:
	if typeof(Game) != TYPE_NIL and Game.has_method("set_time"):
		Game.set_time(hour, minute)
		EventBus.emit_signal("time_updated", hour, minute, Game.day)

static func advance_phase() -> void:
	if typeof(Game) != TYPE_NIL and Game.has_method("advance_phase"):
		Game.advance_phase()
