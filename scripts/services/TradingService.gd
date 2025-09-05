# TradingService.gd
# This wraps Portfolio and MarketSim functionality with proper events
class_name TradingService
extends Resource

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
	var result := {
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
	var result := {
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
