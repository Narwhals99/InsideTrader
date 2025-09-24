extends Resource
class_name OptionPricingService

const OptionContract = preload("res://scripts/resources/OptionContract.gd")
const DAYS_IN_YEAR: float = 252.0
const MIN_TIME_FRACTION: float = 1.0 / DAYS_IN_YEAR
const DEFAULT_IV: float = 0.45
const DEFAULT_RISK_FREE: float = 0.01
const MIN_MARK_PRICE: float = 0.01
const MIN_SPREAD: float = 0.02
const SPREAD_PCT: float = 0.12

static func price_contract(contract: OptionContract, underlying_price: float, days_to_expiry: int, implied_vol: float = DEFAULT_IV, risk_free_rate: float = DEFAULT_RISK_FREE) -> Dictionary:
	if contract == null:
		return {}
	contract.ensure_id()
	var spot: float = float(max(underlying_price, 0.01))
	var strike: float = float(max(contract.strike, 0.01))
	var time_days: int = int(max(days_to_expiry, 0))
	var time_fraction: float = float(max(MIN_TIME_FRACTION, float(time_days) / DAYS_IN_YEAR))
	var sigma: float = float(max(implied_vol, 0.0001))

	var intrinsic: float = contract.intrinsic_value(spot)
	if time_days <= 0 or sigma <= 0.0002:
		var mark_now: float = float(max(intrinsic, MIN_MARK_PRICE))
		return _quote_from_mark(contract, mark_now, intrinsic, 0.0, 0.0, 0.0, 0.0, implied_vol)

	var sqrt_time: float = sqrt(time_fraction)
	var sigma_sq: float = sigma * sigma
	var numerator: float = log(spot / strike) + (risk_free_rate + 0.5 * sigma_sq) * time_fraction
	var denom: float = sigma * sqrt_time
	var d1: float = numerator / denom
	var d2: float = d1 - sigma * sqrt_time
	var nd1: float = _norm_cdf(d1)
	var nd2: float = _norm_cdf(d2)
	var neg_nd1: float = _norm_cdf(-d1)
	var neg_nd2: float = _norm_cdf(-d2)
	var discount: float = exp(-risk_free_rate * time_fraction)
	var discount_strike: float = strike * discount

	var pdf_d1: float = _norm_pdf(d1)
	var gamma: float = pdf_d1 / (spot * sigma * sqrt_time)
	var vega: float = spot * pdf_d1 * sqrt_time

	var mark: float = MIN_MARK_PRICE
	var delta: float = 0.0
	var theta_yearly: float = 0.0
	if contract.option_type == OptionContract.OptionType.CALL:
		mark = float(max(MIN_MARK_PRICE, spot * nd1 - discount_strike * nd2))
		delta = nd1
		theta_yearly = (-spot * pdf_d1 * sigma) / (2.0 * sqrt_time) - risk_free_rate * discount_strike * nd2
	else:
		mark = float(max(MIN_MARK_PRICE, discount_strike * neg_nd2 - spot * neg_nd1))
		delta = nd1 - 1.0
		theta_yearly = (-spot * pdf_d1 * sigma) / (2.0 * sqrt_time) + risk_free_rate * discount_strike * neg_nd2

	var theta_daily: float = theta_yearly / DAYS_IN_YEAR
	var extrinsic: float = float(max(0.0, mark - intrinsic))
	return _quote_from_mark(contract, mark, intrinsic, extrinsic, delta, gamma, vega, implied_vol, theta_daily)

static func _quote_from_mark(contract: OptionContract, mark: float, intrinsic: float, extrinsic: float, delta: float, gamma: float, vega: float, implied_vol: float, theta_per_day: float = 0.0) -> Dictionary:
	var spread: float = float(max(MIN_SPREAD, mark * SPREAD_PCT))
	var half: float = spread * 0.5
	var bid: float = float(max(0.0, mark - half))
	var ask: float = float(max(mark + half, bid + 0.01))
	return {
		"id": contract.id,
		"mark": mark,
		"bid": bid,
		"ask": ask,
		"intrinsic": intrinsic,
		"extrinsic": extrinsic,
		"delta": delta,
		"gamma": gamma,
		"vega": vega,
		"theta_per_day": theta_per_day,
		"implied_vol": implied_vol
	}

static func _norm_cdf(x: float) -> float:
	return 0.5 * (1.0 + _erf(x / sqrt(2.0)))

static func _erf(z: float) -> float:
	var sign: float = 1.0 if z >= 0.0 else -1.0
	var x: float = float(abs(z))
	var p: float = 0.3275911
	var a1: float = 0.254829592
	var a2: float = -0.284496736
	var a3: float = 1.421413741
	var a4: float = -1.453152027
	var a5: float = 1.061405429
	var t: float = 1.0 / (1.0 + p * x)
	var poly: float = (((((a5 * t) + a4) * t) + a3) * t + a2) * t + a1
	var y: float = 1.0 - poly * t * exp(-x * x)
	return sign * y

static func _norm_pdf(x: float) -> float:
	return 0.3989422804014327 * exp(-0.5 * x * x)

