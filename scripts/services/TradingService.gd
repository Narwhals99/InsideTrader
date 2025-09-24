# TradingService.gd
# This wraps Portfolio and MarketSim functionality with proper events
class_name TradingService
extends Resource
const OptionMarketService = preload("res://scripts/services/OptionMarketService.gd")

# ============ MARKET QUERIES ============
static func get_price(symbol: String) -> float:
	if typeof(MarketSim) == TYPE_NIL:
		push_error("[TradingService] MarketSim not found")
		return 0.0
	return MarketSim.get_price(StringName(symbol))

static func get_all_prices() -> Dictionary:
	if typeof(MarketSim) == TYPE_NIL:
		return {}
	return MarketSim.get_all_prices()

static func is_market_open() -> bool:
	if typeof(Game) == TYPE_NIL:
		return false
	return Game.is_market_open()

static func get_market_status() -> Dictionary:
	var status := {
		"is_open": is_market_open(),
		"phase": "",
		"minutes_until_close": 0
	}
	
	if typeof(Game) != TYPE_NIL:
		status.phase = String(Game.phase)
		if status.is_open:
			status.minutes_until_close = Game.minutes_until_market_close()
	
	return status

# ============ PORTFOLIO QUERIES ============
static func get_cash() -> float:
	if typeof(Portfolio) == TYPE_NIL:
		return 0.0
	return Portfolio.cash

static func get_position(symbol: String) -> Dictionary:
	if typeof(Portfolio) == TYPE_NIL:
		return {"shares": 0, "avg_cost": 0.0}
	return Portfolio.get_position(StringName(symbol))

static func get_net_worth() -> float:
	if typeof(Portfolio) == TYPE_NIL:
		return 0.0
	return Portfolio.net_worth()

static func can_afford_purchase(symbol: String, quantity: int) -> bool:
	var price := get_price(symbol)
	var cost := price * quantity
	return get_cash() >= cost

# ============ TRADING ACTIONS ============
static func execute_buy(symbol: String, quantity: int, price: float = -1.0) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"message": "",
		"symbol": symbol,
		"quantity": quantity,
		"price": 0.0,
		"total_cost": 0.0
	}
	
	# Validation
	if not is_market_open():
		result.message = "Market is closed"
		EventBus.emit_notification(result.message, "warning")
		return result
	
	if quantity <= 0:
		result.message = "Invalid quantity"
		return result
	
	# Get price
	if price <= 0:
		price = get_price(symbol)
	result.price = price
	result.total_cost = price * quantity
	
	# Check affordability
	if not can_afford_purchase(symbol, quantity):
		result.message = "Insufficient funds (need $%.2f)" % result.total_cost
		EventBus.emit_notification(result.message, "danger")
		return result
	
	# Execute trade
	if typeof(Portfolio) != TYPE_NIL:
		result.success = Portfolio.buy(StringName(symbol), quantity, price)
		if result.success:
			result.message = "Bought %d %s @ $%.2f" % [quantity, symbol, price]
			EventBus.emit_notification(result.message, "success")
			EventBus.emit_signal("trade_executed", symbol, quantity, true, price, true)
	
	return result

static func execute_sell(symbol: String, quantity: int, price: float = -1.0) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"message": "",
		"symbol": symbol,
		"quantity": quantity,
		"price": 0.0,
		"proceeds": 0.0
	}
	
	# Validation
	if not is_market_open():
		result.message = "Market is closed"
		EventBus.emit_notification(result.message, "warning")
		return result
	
	var position := get_position(symbol)
	var shares_owned := int(position.get("shares", 0))
	
	if shares_owned <= 0:
		result.message = "No shares to sell"
		EventBus.emit_notification(result.message, "warning")
		return result
	
	# Adjust quantity if trying to oversell
	if quantity > shares_owned:
		quantity = shares_owned
		result.quantity = quantity
	
	# Get price
	if price <= 0:
		price = get_price(symbol)
	result.price = price
	result.proceeds = price * quantity
	
	# Execute trade
	if typeof(Portfolio) != TYPE_NIL:
		result.success = Portfolio.sell(StringName(symbol), quantity, price)
		if result.success:
			result.message = "Sold %d %s @ $%.2f" % [quantity, symbol, price]
			EventBus.emit_notification(result.message, "success")
			EventBus.emit_signal("trade_executed", symbol, quantity, false, price, true)
	
	return result

static func close_position(symbol: String) -> Dictionary:
	var position := get_position(symbol)
	var shares := int(position.get("shares", 0))
	if shares <= 0:
		return {
			"success": false,
			"message": "No position to close"
		}
	return execute_sell(symbol, shares)

# ============ OPTION QUERIES ============
static func get_option_quote(option_id: String) -> Dictionary:
	if typeof(OptionMarketService) == TYPE_NIL:
		return {}
	return OptionMarketService.get_option_quote(option_id)

static func get_option_positions() -> Dictionary:
	if typeof(Portfolio) == TYPE_NIL:
		return {}
	return Portfolio.get_all_option_positions()

static func get_option_position(option_id: String) -> Dictionary:
	if typeof(Portfolio) == TYPE_NIL:
		return {}
	return Portfolio.get_option_position(option_id)

static func option_market_value(option_id: String) -> float:
	if typeof(Portfolio) == TYPE_NIL:
		return 0.0
	return Portfolio.option_market_value(option_id)

static func can_afford_option(option_id: String, contracts: int, premium: float = -1.0) -> bool:
	if typeof(Portfolio) == TYPE_NIL or contracts <= 0:
		return false
	var quote: Dictionary = get_option_quote(option_id)
	if quote.is_empty():
		return false
	var multiplier: int = int(quote.get("multiplier", 100))
	var use_premium: float = premium
	if use_premium <= 0.0:
		use_premium = float(quote.get("ask", quote.get("mark", 0.0)))
	if use_premium <= 0.0:
		return false
	var commission: float = float(Portfolio.commission_per_trade)
	var total: float = use_premium * float(multiplier) * float(contracts) + commission
	return Portfolio.cash >= total

static func execute_option_buy(option_id: String, contracts: int, price: float = -1.0) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"message": "",
		"option_id": option_id,
		"contracts": contracts,
		"premium": 0.0,
		"total_cost": 0.0,
		"multiplier": 0
	}
	if not is_market_open():
		result.message = "Market is closed"
		EventBus.emit_notification(result.message, "warning")
		return result
	if contracts <= 0:
		result.message = "Invalid contract count"
		return result
	var quote: Dictionary = get_option_quote(option_id)
	if quote.is_empty():
		result.message = "Option not available"
		return result
	var premium: float = price
	if premium <= 0.0:
		premium = float(quote.get("ask", quote.get("mark", 0.0)))
	if premium <= 0.0:
		result.message = "No premium available"
		return result
	var multiplier: int = int(quote.get("multiplier", 100))
	var commission: float = 0.0
	if typeof(Portfolio) != TYPE_NIL:
		commission = float(Portfolio.commission_per_trade)
	var total_cost: float = premium * float(multiplier) * float(contracts) + commission
	result.premium = premium
	result.multiplier = multiplier
	result.total_cost = total_cost
	if typeof(Portfolio) == TYPE_NIL:
		result.message = "Portfolio unavailable"
		return result
	if Portfolio.cash < total_cost:
		result.message = "Insufficient funds (need $%.2f)" % total_cost
		EventBus.emit_notification(result.message, "danger")
		return result
	var contract_obj: Variant = quote.get("contract", null)
	var ok: bool = Portfolio.buy_option(option_id, contracts, premium, contract_obj)
	result.success = ok
	if ok:
		result.message = "Bought %d x %s @ $%.2f" % [contracts, option_id, premium]
		EventBus.emit_notification(result.message, "success")
		EventBus.emit_signal("trade_executed", option_id, contracts, true, premium, true)
	else:
		result.message = "Order failed"
	return result

static func execute_option_sell(option_id: String, contracts: int, price: float = -1.0) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"message": "",
		"option_id": option_id,
		"request_contracts": contracts,
		"filled_contracts": 0,
		"premium": 0.0,
		"gross": 0.0,
		"proceeds": 0.0,
		"multiplier": 0
	}
	if not is_market_open():
		result.message = "Market is closed"
		EventBus.emit_notification(result.message, "warning")
		return result
	if contracts <= 0:
		result.message = "Invalid contract count"
		return result
	if typeof(Portfolio) == TYPE_NIL:
		result.message = "Portfolio unavailable"
		return result
	var pos: Dictionary = Portfolio.get_option_position(option_id)
	var owned: int = int(pos.get("contracts", 0))
	if owned <= 0:
		result.message = "No contracts to sell"
		return result
	var contracts_to_sell: int = min(contracts, owned)
	var quote: Dictionary = get_option_quote(option_id)
	if quote.is_empty():
		result.message = "Option not available"
		return result
	var premium: float = price
	if premium <= 0.0:
		premium = float(quote.get("bid", quote.get("mark", 0.0)))
	if premium < 0.0:
		premium = 0.0
	var multiplier: int = int(quote.get("multiplier", pos.get("multiplier", 100)))
	var gross: float = premium * float(multiplier) * float(contracts_to_sell)
	var commission: float = 0.0
	if typeof(Portfolio) != TYPE_NIL:
		commission = float(Portfolio.commission_per_trade)
	var proceeds: float = gross - commission
	result.premium = premium
	result.multiplier = multiplier
	result.gross = gross
	result.proceeds = proceeds
	result.filled_contracts = contracts_to_sell
	var ok: bool = Portfolio.sell_option(option_id, contracts_to_sell, premium)
	result.success = ok
	if ok:
		result.message = "Sold %d x %s @ $%.2f" % [contracts_to_sell, option_id, premium]
		EventBus.emit_notification(result.message, "success")
		EventBus.emit_signal("trade_executed", option_id, contracts_to_sell, false, premium, true)
	else:
		result.message = "Order failed"
	return result

static func close_option_position(option_id: String) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"message": "",
		"option_id": option_id
	}
	if typeof(Portfolio) == TYPE_NIL:
		result.message = "Portfolio unavailable"
		return result
	var pos: Dictionary = Portfolio.get_option_position(option_id)
	var contracts: int = int(pos.get("contracts", 0))
	if contracts <= 0:
		result.message = "No position to close"
		return result
	var quote: Dictionary = get_option_quote(option_id)
	var premium: float = float(quote.get("bid", quote.get("mark", pos.get("last_price", 0.0))))
	var sell_result: Dictionary = execute_option_sell(option_id, contracts, premium)
	return sell_result
# ============ INSIDER TRADING ============
static func add_insider_tip(ticker: String, message: String = "") -> void:
	if typeof(InsiderInfo) != TYPE_NIL:
		if message == "":
			message = "Movement expected for " + ticker
		InsiderInfo.add_move_tomorrow_tip(ticker, message)
		EventBus.emit_signal("insider_tip_given", ticker, "ceo")

static func has_insider_tip(ticker: String) -> bool:
	if typeof(InsiderInfo) == TYPE_NIL:
		return false
	return InsiderInfo.has_tip_for_ticker(ticker)

static func get_all_insider_tips() -> Array:
	if typeof(InsiderInfo) == TYPE_NIL:
		return []
	return InsiderInfo.get_active_tips()

# ============ MARKET MANIPULATION (for CEO) ============
static func schedule_mover(ticker: String, move_percent: float) -> void:
	if typeof(MarketSim) != TYPE_NIL and MarketSim.has_method("force_next_mover"):
		MarketSim.force_next_mover(StringName(ticker), move_percent)
		print("[TradingService] Scheduled mover: ", ticker, " @ ", move_percent * 100, "%")
