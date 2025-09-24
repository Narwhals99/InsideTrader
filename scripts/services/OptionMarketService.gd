extends Resource
class_name OptionMarketService

const OptionContract = preload("res://scripts/resources/OptionContract.gd")
const OptionPricingService = preload("res://scripts/services/OptionPricingService.gd")

static var _config: Dictionary = {
	"expiry_offsets": [1, 3, 5, 10],
	"strikes_per_side": 4,
	"strike_step_pct": 0.05,
	"min_strike_step": 1.0,
	"contract_multiplier": 100,
	"iv_base": 0.45,
	"iv_moneyness_slope": 0.35,
	"iv_term_slope": 0.02,
	"iv_put_skew": 0.05,
	"iv_min": 0.15,
	"iv_max": 1.5,
	"weekly_expiry_count": 4,
}

static var _chains: Dictionary = {}
static var _quotes_by_id: Dictionary = {}
static var _quote_symbol: Dictionary = {}
static var _expiry_schedule: Dictionary = {}

static func reset() -> void:
	_chains.clear()
	_quotes_by_id.clear()
	_quote_symbol.clear()
	_expiry_schedule.clear()

static func configure(overrides: Dictionary) -> void:
	for key in overrides.keys():
		if _config.has(key):
			_config[key] = overrides[key]

static func refresh_symbol(symbol: StringName, underlying_price: float, current_day: int, current_phase: StringName = &"market") -> void:
	var sym_key: String = String(symbol)
	_build_chain(sym_key, symbol, underlying_price, current_day, current_phase)

static func refresh_all(prices: Dictionary, current_day: int, current_phase: StringName = &"market") -> void:
	for key in prices.keys():
		var sym_name: StringName = StringName(String(key))
		var price: float = float(prices[key])
		refresh_symbol(sym_name, price, current_day, current_phase)

static func get_chain(symbol: StringName) -> Dictionary:
	var sym_key: String = String(symbol)
	if not _chains.has(sym_key):
		return {}
	var entry: Dictionary = _chains[sym_key]
	var expiry_ids: Dictionary = entry.get("expiry_ids", {})
	var result: Dictionary = {}
	for expiry_day in expiry_ids.keys():
		var ids: Array = expiry_ids[expiry_day]
		var rows: Array[Dictionary] = []
		for opt_id in ids:
			if _quotes_by_id.has(opt_id):
				rows.append(_quotes_by_id[opt_id].duplicate(true))
		result[expiry_day] = rows
	return result

static func get_option_quote(option_id: String) -> Dictionary:
	if not _quotes_by_id.has(option_id):
		return {}
	return _quotes_by_id[option_id].duplicate(true)

static func has_option(option_id: String) -> bool:
	return _quotes_by_id.has(option_id)

static func symbol_for_option(option_id: String) -> String:
	return _quote_symbol.get(option_id, "")

static func list_option_ids(symbol: StringName) -> Array[String]:
	var sym_key: String = String(symbol)
	if not _chains.has(sym_key):
		return []
	var ids: Array[String] = []
	var expiry_ids: Dictionary = _chains[sym_key].get("expiry_ids", {})
	for expiry_day in expiry_ids.keys():
		var day_ids: Array = expiry_ids[expiry_day]
		for opt_id in day_ids:
			ids.append(String(opt_id))
	return ids

static func _build_chain(sym_key: String, symbol: StringName, underlying_price: float, current_day: int, current_phase: StringName) -> void:
	var expiries: Array[int] = _compute_expiry_days(sym_key, current_day)
	var strike_step: float = _compute_strike_step(underlying_price)
	var strikes: Array[float] = _build_strikes(underlying_price, strike_step)
	_ensure_portfolio_strikes(sym_key, strikes)
	var keep_ids: Dictionary = {}
	_seed_keep_ids_with_open_positions(sym_key, keep_ids)
	var expiry_map: Dictionary = {}
	for expiry_day in expiries:
		var days_to_expiry: int = expiry_day - current_day
		if days_to_expiry < 0:
			continue
		var pricing_days: int = max(days_to_expiry, 0)
		var ids: Array[String] = []
		for strike in strikes:
			ids.append_array(_build_quotes_for_strike(symbol, sym_key, strike, underlying_price, pricing_days, expiry_day, current_day, current_phase, keep_ids))
		expiry_map[expiry_day] = ids
	_cleanup_removed(sym_key, keep_ids)
	_chains[sym_key] = {
		"expiry_ids": expiry_map,
		"last_refresh_day": current_day,
		"last_underlying": underlying_price,
		"last_phase": String(current_phase)
	}

static func _ensure_portfolio_strikes(sym_key: String, strikes: Array) -> void:
	if typeof(Portfolio) == TYPE_NIL:
		return
	var positions: Dictionary = Portfolio.get_all_option_positions()
	for opt_id_any in positions.keys():
		var opt_id: String = String(opt_id_any)
		var pos: Dictionary = positions[opt_id]
		var contracts: int = int(pos.get("contracts", 0))
		if contracts <= 0:
			continue
		var details: Dictionary = pos.get("details", {})
		var underlying := String(details.get("underlying", ""))
		if underlying == "" and _quote_symbol.has(opt_id):
			underlying = _quote_symbol[opt_id]
		if underlying != sym_key:
			continue
		var strike: float = float(details.get("strike", 0.0))
		if strike <= 0.0:
			continue
		var rounded: float = _round_to_cents(strike)
		if not strikes.has(rounded):
			strikes.append(rounded)
	strikes.sort()

static func _seed_keep_ids_with_open_positions(sym_key: String, keep_ids: Dictionary) -> void:
	if typeof(Portfolio) == TYPE_NIL:
		return
	var positions: Dictionary = Portfolio.get_all_option_positions()
	for opt_id_any in positions.keys():
		var opt_id: String = String(opt_id_any)
		var pos: Dictionary = positions[opt_id]
		var contracts: int = int(pos.get("contracts", 0))
		if contracts <= 0:
			continue
		var details: Dictionary = pos.get("details", {})
		var underlying := String(details.get("underlying", ""))
		if underlying == "" and _quote_symbol.has(opt_id):
			underlying = _quote_symbol[opt_id]
		if underlying != sym_key:
			continue
		keep_ids[opt_id] = true
static func _build_quotes_for_strike(symbol: StringName, sym_key: String, strike: float, underlying_price: float, days_to_expiry: int, expiry_day: int, current_day: int, current_phase: StringName, keep_ids: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for opt_type in [OptionContract.OptionType.CALL, OptionContract.OptionType.PUT]:
		var contract: OptionContract = OptionContract.new({
			"underlying": symbol,
			"option_type": opt_type,
			"strike": strike,
			"expiry_day": expiry_day,
			"expiry_phase": &"close",
			"created_day": current_day,
			"multiplier": int(_config.get("contract_multiplier", 100))
		})
		contract.ensure_id()
		var iv: float = _estimate_volatility(underlying_price, strike, days_to_expiry, opt_type)
		var quote: Dictionary = OptionPricingService.price_contract(contract, underlying_price, days_to_expiry, iv)
		var enriched: Dictionary = _compose_quote(contract, sym_key, underlying_price, days_to_expiry, current_day, current_phase, quote)
		_quotes_by_id[contract.id] = enriched
		_quote_symbol[contract.id] = sym_key
		keep_ids[contract.id] = true
		ids.append(contract.id)
	return ids

static func _compose_quote(contract: OptionContract, sym_key: String, underlying_price: float, days_to_expiry: int, current_day: int, current_phase: StringName, price_data: Dictionary) -> Dictionary:
	var copy: Dictionary = price_data.duplicate(true)
	copy["contract"] = contract
	copy["symbol"] = sym_key
	copy["underlying"] = underlying_price
	copy["days_to_expiry"] = days_to_expiry
	copy["last_update_day"] = current_day
	copy["last_update_phase"] = String(current_phase)
	copy["strike"] = contract.strike
	copy["option_type"] = contract.option_type
	copy["expiry_day"] = contract.expiry_day
	copy["expiry_phase"] = String(contract.expiry_phase)
	copy["multiplier"] = contract.multiplier
	return copy

static func _cleanup_removed(sym_key: String, keep_ids: Dictionary) -> void:
	var to_remove: Array[String] = []
	for opt_id in _quote_symbol.keys():
		if _quote_symbol[opt_id] == sym_key and not keep_ids.has(opt_id):
			to_remove.append(opt_id)
	for opt_id in to_remove:
		_quote_symbol.erase(opt_id)
		_quotes_by_id.erase(opt_id)

static func _compute_expiry_days(sym_key: String, current_day: int) -> Array[int]:
	var expiries: Array[int] = []
	var weekly_count: int = int(_config.get("weekly_expiry_count", 4))
	if weekly_count <= 0:
		weekly_count = 1
	var schedule: Dictionary = _expiry_schedule.get(sym_key, {})
	var target_weekday: int = 4  # Friday (0 = Monday)
	var base_friday: int = _next_weekday_on_or_after(current_day, target_weekday)
	for i in range(weekly_count):
		var key: String = "wk_" + str(i)
		var default_day: int = base_friday + i * 7
		var stored_day: int = int(schedule.get(key, default_day))
		if stored_day < current_day:
			stored_day = default_day
		stored_day = _next_weekday_on_or_after(stored_day, target_weekday)
		if not expiries.is_empty() and stored_day <= expiries[-1]:
			stored_day = _next_weekday_on_or_after(expiries[-1] + 1, target_weekday)
		expiries.append(stored_day)
		schedule[key] = stored_day
	var extra_days: Array[int] = _collect_portfolio_expiry_days(sym_key)
	for extra_day in extra_days:
		if extra_day >= current_day and not expiries.has(extra_day):
			expiries.append(extra_day)
	expiries.sort()
	_expiry_schedule[sym_key] = schedule
	return expiries


# Calendar helpers
static func _weekday_for_day(day_number: int) -> int:
	if day_number <= 0:
		day_number = 1
	if typeof(Game) != TYPE_NIL and Game.has_method("get_calendar_date_for_day"):
		var data: Dictionary = Game.get_calendar_date_for_day(day_number)
		if data.has("weekday"):
			return int(data["weekday"])
	return int(((day_number - 1) % 7))

static func _next_weekday_on_or_after(day_number: int, target_weekday: int) -> int:
	var day: int = max(1, day_number)
	var weekday: int = _weekday_for_day(day)
	var delta: int = (target_weekday - weekday + 7) % 7
	return day + delta

static func _collect_portfolio_expiry_days(sym_key: String) -> Array[int]:
	var result: Array[int] = []
	if typeof(Portfolio) == TYPE_NIL:
		return result
	var positions: Dictionary = Portfolio.get_all_option_positions()
	for opt_id_any in positions.keys():
		var opt_id: String = String(opt_id_any)
		var pos: Dictionary = positions[opt_id]
		var contracts: int = int(pos.get("contracts", 0))
		if contracts <= 0:
			continue
		var details: Dictionary = pos.get("details", {})
		var underlying := String(details.get("underlying", ""))
		if underlying == "" and _quote_symbol.has(opt_id):
			underlying = _quote_symbol[opt_id]
		if underlying != sym_key:
			continue
		var expiry_day: int = int(details.get("expiry_day", -1))
		if expiry_day >= 0 and not result.has(expiry_day):
			result.append(expiry_day)
	return result

static func _compute_strike_step(underlying_price: float) -> float:
	var step_pct: float = float(_config.get("strike_step_pct", 0.05))
	var min_step: float = float(_config.get("min_strike_step", 1.0))
	var step: float = max(min_step, underlying_price * step_pct)
	return _round_to_cents(step)

static func _build_strikes(underlying_price: float, step: float) -> Array[float]:
	var strikes: Array[float] = []
	var per_side: int = int(_config.get("strikes_per_side", 4))
	var center: float = _round_to_cents(round(underlying_price / max(step, 0.25)) * max(step, 0.25))
	for i in range(-per_side, per_side + 1):
		var strike: float = _round_to_cents(center + float(i) * step)
		if strike <= 0.25:
			continue
		strikes.append(strike)
	strikes.sort()
	return strikes

static func _estimate_volatility(spot: float, strike: float, days_to_expiry: int, opt_type: int) -> float:
	var base: float = float(_config.get("iv_base", 0.45))
	var slope: float = float(_config.get("iv_moneyness_slope", 0.35))
	var term: float = float(_config.get("iv_term_slope", 0.02))
	var skew: float = float(_config.get("iv_put_skew", 0.05))
	var iv_min: float = float(_config.get("iv_min", 0.15))
	var iv_max: float = float(_config.get("iv_max", 1.5))
	var moneyness: float = abs((strike - spot) / max(spot, 1.0))
	var time_factor: float = clamp(float(days_to_expiry) / 30.0, 0.0, 4.0)
	var iv: float = base + slope * moneyness + term * time_factor
	if opt_type == OptionContract.OptionType.PUT and strike > spot:
		iv += skew * min(1.0, (strike - spot) / max(spot, 1.0))
	return clamp(iv, iv_min, iv_max)

static func _round_to_cents(value: float) -> float:
	return floor(value * 100.0 + 0.5) / 100.0
