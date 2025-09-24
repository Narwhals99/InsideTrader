extends Resource
class_name OptionContract

enum OptionType { CALL = 1, PUT = -1 }

@export var id: String = ""
@export var underlying: StringName = &""
@export var option_type: int = OptionType.CALL
@export var strike: float = 0.0
@export var expiry_day: int = 0
@export var expiry_phase: StringName = &"close"
@export var multiplier: int = 100
@export var created_day: int = 0

func _init(data: Dictionary = {}) -> void:
	if not data.is_empty():
		underlying = StringName(data.get("underlying", underlying))
		option_type = int(data.get("option_type", option_type))
		strike = float(data.get("strike", strike))
		expiry_day = int(data.get("expiry_day", expiry_day))
		expiry_phase = StringName(data.get("expiry_phase", expiry_phase))
		multiplier = int(data.get("multiplier", multiplier))
		created_day = int(data.get("created_day", created_day))
		id = data.get("id", build_id(underlying, option_type, strike, expiry_day))

func ensure_id() -> void:
	if id.strip_edges() == "":
		id = build_id(underlying, option_type, strike, expiry_day)

static func build_id(sym: StringName, opt_type: int, strike_price: float, expiry_day: int) -> String:
	var type_char := "C" if opt_type == OptionType.CALL else "P"
	var strike_key := _strike_to_key(strike_price)
	return "%s_%s_%s_%s" % [String(sym), str(expiry_day), strike_key, type_char]

static func _strike_to_key(strike_price: float) -> String:
	return str(int(round(strike_price * 100.0)))

func intrinsic_value(underlying_price: float) -> float:
	if option_type == OptionType.CALL:
		return max(0.0, underlying_price - strike)
	return max(0.0, strike - underlying_price)

func is_in_the_money(underlying_price: float) -> bool:
	return intrinsic_value(underlying_price) > 0.0

func days_to_expiry(current_day: int) -> int:
	return max(0, expiry_day - current_day)

func has_expired(current_day: int, current_phase: StringName) -> bool:
	if current_day < expiry_day:
		return false
	if current_day > expiry_day:
		return true
	return _phase_index(current_phase) >= _phase_index(expiry_phase)

func _phase_index(phase: StringName) -> int:
	var order := {
		&"pre": 0,
		&"morning": 1,
		&"market": 2,
		&"midday": 3,
		&"close": 4,
		&"evening": 5,
	}
	return int(order.get(phase, 99))

func describe() -> String:
	var type_char := "C" if option_type == OptionType.CALL else "P"
	return "%s %s %s @ %.2f" % [String(underlying), str(expiry_day), type_char, strike]
