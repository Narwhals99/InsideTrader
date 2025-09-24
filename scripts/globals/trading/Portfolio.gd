extends Node
const OptionMarketService = preload("res://scripts/services/OptionMarketService.gd")
const OptionContract = preload("res://scripts/resources/OptionContract.gd")
const MIN_OPTION_MARK: float = 0.01

signal portfolio_changed()
signal order_executed(order: Dictionary)

@export var starting_cash: float = 10000.0
@export var commission_per_trade: float = 0.0
@export var allow_oversell: bool = false

var cash: float = 0.0
var realized_pnl: float = 0.0
var positions: Dictionary = {}			# sym:StringName -> {shares:int, avg_cost:float}
var option_positions: Dictionary = {}		# option_id:String -> {contracts:int, avg_premium:float, details:Dictionary, last_price:float}
var orders: Array[Dictionary] = []		# append executed orders

func _ready() -> void:
	cash = starting_cash

# --- Queries ---
func get_position(sym: StringName) -> Dictionary:
	return positions.get(sym, {"shares": 0, "avg_cost": 0.0})

func position_value(sym: StringName) -> float:
	var pos := get_position(sym)
	if pos["shares"] <= 0:
		return 0.0
	# BEFORE:
	# var px := MarketSim.get_price(sym)

	# AFTER:
	var px: float = MarketSim.get_price(sym)

	return float(pos["shares"]) * px

func holdings_value() -> float:
	var total: float = 0.0
	for s in positions.keys():
		total += position_value(s)
	total += option_holdings_value()
	return total

func option_holdings_value() -> float:
	var total: float = 0.0
	for opt_id in option_positions.keys():
		total += option_market_value(String(opt_id))
	return total

func get_option_position(option_id: String) -> Dictionary:
	if not option_positions.has(option_id):
		return {
			"contracts": 0,
			"avg_premium": 0.0,
			"details": _get_option_details(option_id),
			"last_price": 0.0
		}
	var pos: Dictionary = option_positions[option_id]
	var copy: Dictionary = pos.duplicate(true)
	var base_details: Dictionary = _get_option_details(option_id)
	copy["details"] = _merge_option_details(base_details, copy.get("details", {}))
	return copy

func get_all_option_positions() -> Dictionary:
	return option_positions.duplicate(true)

func has_option_position(option_id: String) -> bool:
	if not option_positions.has(option_id):
		return false
	var pos: Dictionary = option_positions[option_id]
	return int(pos.get("contracts", 0)) > 0

func option_market_value(option_id: String) -> float:
	if not option_positions.has(option_id):
		return 0.0
	var pos: Dictionary = option_positions[option_id]
	var contracts: int = int(pos.get("contracts", 0))
	if contracts <= 0:
		return 0.0
	var details: Dictionary = _get_option_details(option_id)
	var multiplier: int = int(details.get("multiplier", pos.get("multiplier", 100)))
	var mark: float = float(pos.get("last_price", 0.0))
	var used_quote: bool = false
	if typeof(OptionMarketService) != TYPE_NIL and OptionMarketService.has_option(option_id):
		var quote: Dictionary = OptionMarketService.get_option_quote(option_id)
		if not quote.is_empty():
			mark = float(quote.get("mark", mark))
			used_quote = true
	if not used_quote:
		mark = _fallback_option_mark(details, mark)
	pos["details"] = details
	pos["last_price"] = mark
	option_positions[option_id] = pos
	return mark * float(multiplier) * float(contracts)

# Keep the original for compatibility but document the difference
func net_worth() -> float:
	"""DEPRECATED: Use portfolio_net_worth() or total_net_worth() instead"""
	return portfolio_net_worth()

# --- Mutations ---
func buy(sym: StringName, qty: int, price: float = -1.0) -> bool:
	if qty <= 0:
		return false
	if price <= 0.0:
		price = MarketSim.get_price(sym)
	var cost: float = price * qty + commission_per_trade
	
	# Check portfolio cash only (not bank)
	if cash < cost:
		# NEW: Offer to withdraw from bank if they have funds there
		if typeof(BankService) != TYPE_NIL:
			var bank_bal = BankService.get_balance()
			if bank_bal > 0:
				var needed = cost - cash
				EventBus.emit_notification(
					"Insufficient portfolio cash. Need $%.2f more. (Wallet has $%.2f)" % [needed, bank_bal],
					"warning",
					4.0
				)
				EventBus.emit_notification(
					"Use Banking tab to transfer funds to portfolio",
					"info",
					4.0
				)
			else:
				EventBus.emit_notification("Not enough cash for trade!", "danger", 3.0)
		else:
			# Fallback to old DialogueUI if BankService doesn't exist
			DialogueUI.notify("Not enough cash for trade!", "danger")
		return false
	
	# Continue with the purchase
	var pos := get_position(sym)
	var old_shares: int = int(pos["shares"])
	var old_avg: float = float(pos["avg_cost"])
	var new_shares: int = old_shares + qty
	var new_avg: float = ((old_avg * old_shares) + (price * qty)) / float(new_shares)
	
	positions[sym] = {"shares": new_shares, "avg_cost": new_avg}
	cash -= cost
	
	var order := {
		"type": "BUY",
		"symbol": String(sym),
		"qty": qty,
		"price": price,
		"day": Game.day,
		"phase": String(Game.phase),
	}
	orders.append(order)
	emit_signal("order_executed", order)
	emit_signal("portfolio_changed")
	
	# Note: This line was unreachable in your original code (after return true)
	# Moving it before return if you want to show it:
	# DialogueUI.show_trade_result(true, "Bought " + str(qty) + " " + String(sym))
	
	return true

func sell(sym: StringName, qty: int, price: float = -1.0) -> bool:
	if qty <= 0:
		return false
	if price <= 0.0:
		price = MarketSim.get_price(sym)

	var pos := get_position(sym)
	var own: int = int(pos["shares"])
	if own <= 0 and not allow_oversell:
		return false
	if not allow_oversell and qty > own:
		qty = own
	if qty <= 0:
		return false

	var avg: float = float(pos["avg_cost"])
	var proceeds: float = price * qty - commission_per_trade
	cash += proceeds

	var pnl: float = (price - avg) * qty
	realized_pnl += pnl

	var new_shares: int = own - qty
	if new_shares > 0:
		positions[sym] = {"shares": new_shares, "avg_cost": avg}
	else:
		positions[sym] = {"shares": 0, "avg_cost": 0.0}

	var order := {
		"type": "SELL",
		"symbol": String(sym),
		"qty": qty,
		"price": price,
		"day": Game.day,
		"phase": String(Game.phase),
		"realized_pnl": pnl,
	}
	orders.append(order)
	emit_signal("order_executed", order)
	emit_signal("portfolio_changed")
	return true
func buy_option(option_id: String, contracts: int, premium: float, contract: OptionContract = null) -> bool:
	if contracts <= 0 or premium <= 0.0:
		return false
	var details: Dictionary = _get_option_details(option_id, contract)
	var multiplier: int = int(details.get("multiplier", 100))
	var total_premium: float = premium * float(multiplier) * float(contracts)
	var total_cost: float = total_premium + commission_per_trade
	if total_cost <= 0.0:
		return false
	if cash < total_cost:
		return false
	cash -= total_cost
	var existing: Dictionary = {}
	if option_positions.has(option_id):
		existing = option_positions[option_id]
	else:
		existing = {
			"contracts": 0,
			"avg_premium": 0.0,
			"details": details,
			"last_price": 0.0,
			"multiplier": multiplier
		}
	var old_contracts: int = int(existing.get("contracts", 0))
	var old_avg: float = float(existing.get("avg_premium", 0.0))
	var new_contracts: int = old_contracts + contracts
	var new_avg: float = ((old_avg * old_contracts) + (premium * contracts)) / float(new_contracts)
	existing["contracts"] = new_contracts
	existing["avg_premium"] = new_avg
	existing["details"] = details
	existing["last_price"] = premium
	existing["multiplier"] = multiplier
	option_positions[option_id] = existing

	var order := {
		"type": "BUY_OPTION",
		"option_id": option_id,
		"contracts": contracts,
		"premium": premium,
		"multiplier": multiplier,
		"total_cost": total_cost,
		"day": Game.day,
		"phase": String(Game.phase)
	}
	orders.append(order)
	emit_signal("order_executed", order)
	emit_signal("portfolio_changed")
	return true

func sell_option(option_id: String, contracts: int, premium: float) -> bool:
	if contracts <= 0:
		return false
	if not option_positions.has(option_id):
		return false
	var pos: Dictionary = option_positions[option_id]
	var owned: int = int(pos.get("contracts", 0))
	if owned <= 0:
		return false
	if contracts > owned:
		contracts = owned
	if contracts <= 0:
		return false
	var details: Dictionary = _get_option_details(option_id)
	var multiplier: int = int(details.get("multiplier", pos.get("multiplier", 100)))
	var gross: float = premium * float(multiplier) * float(contracts)
	var proceeds: float = gross - commission_per_trade
	cash += proceeds
	var avg: float = float(pos.get("avg_premium", 0.0))
	var pnl_per_contract: float = (premium - avg) * float(multiplier)
	var realized: float = pnl_per_contract * float(contracts)
	realized_pnl += realized

	var remaining: int = owned - contracts
	if remaining > 0:
		pos["contracts"] = remaining
		pos["last_price"] = premium
		option_positions[option_id] = pos
	else:
		option_positions.erase(option_id)

	var order := {
		"type": "SELL_OPTION",
		"option_id": option_id,
		"contracts": contracts,
		"premium": premium,
		"multiplier": multiplier,
		"gross": gross,
		"proceeds": proceeds,
		"realized_pnl": realized,
		"day": Game.day,
		"phase": String(Game.phase)
	}
	orders.append(order)
	emit_signal("order_executed", order)
	emit_signal("portfolio_changed")
	return true

func close_option_position(option_id: String) -> bool:
	if not option_positions.has(option_id):
		return false
	var pos: Dictionary = option_positions[option_id]
	var contracts: int = int(pos.get("contracts", 0))
	if contracts <= 0:
		return false
	var premium: float = float(pos.get("last_price", 0.0))
	if typeof(OptionMarketService) != TYPE_NIL and OptionMarketService.has_option(option_id):
		var quote: Dictionary = OptionMarketService.get_option_quote(option_id)
		if not quote.is_empty():
			premium = float(quote.get("bid", quote.get("mark", premium)))
	return sell_option(option_id, contracts, premium)

# Update net_worth methods to handle separation
func portfolio_net_worth() -> float:
	"""Get net worth of just the portfolio (cash + holdings)"""
	return cash + holdings_value()

func total_net_worth() -> float:
	"""Get total net worth including bank account"""
	var portfolio_total = portfolio_net_worth()
	var bank_balance = 0.0
	if typeof(BankService) != TYPE_NIL:
		bank_balance = BankService.get_balance()
	return portfolio_total + bank_balance
	
func can_afford_trade(symbol: StringName, qty: int, price: float = -1.0) -> bool:
	"""Check if portfolio cash (not bank) can cover the trade"""
	if price <= 0.0:
		price = MarketSim.get_price(symbol)
	var cost: float = price * qty + commission_per_trade
	return cash >= cost
	
func _fallback_option_mark(details: Dictionary, previous_mark: float) -> float:
	var mark: float = max(previous_mark, 0.0)
	var underlying: String = String(details.get("underlying", ""))
	var strike: float = float(details.get("strike", 0.0))
	var opt_type: int = int(details.get("option_type", OptionContract.OptionType.CALL))
	var spot: float = 0.0
	if underlying != "" and typeof(MarketSim) != TYPE_NIL:
		spot = float(MarketSim.get_price(StringName(underlying)))
	if spot <= 0.0:
		return max(mark, MIN_OPTION_MARK)
	var intrinsic: float = 0.0
	if opt_type == OptionContract.OptionType.CALL:
		intrinsic = max(0.0, spot - strike)
	else:
		intrinsic = max(0.0, strike - spot)
	var fallback_mark: float = max(intrinsic, MIN_OPTION_MARK)
	if fallback_mark <= 0.0 and mark > 0.0:
		fallback_mark = mark
	return fallback_mark


func option_positions_count() -> int:
	return option_positions.size()

func _get_option_details(option_id: String, contract: OptionContract = null) -> Dictionary:
	var base: Dictionary = {}
	if contract != null:
		base = _details_from_contract(contract)
	elif option_positions.has(option_id):
		var stored: Dictionary = option_positions[option_id]
		if stored.has("details") and stored["details"] is Dictionary:
			base = (stored["details"] as Dictionary).duplicate(true)
	if typeof(OptionMarketService) != TYPE_NIL and OptionMarketService.has_option(option_id):
		var quote: Dictionary = OptionMarketService.get_option_quote(option_id)
		if not quote.is_empty():
			base = _merge_option_details(base, quote)
	if base.is_empty():
		var symbol_hint: String = ""
		if typeof(OptionMarketService) != TYPE_NIL and OptionMarketService.has_option(option_id):
			symbol_hint = String(OptionMarketService.symbol_for_option(option_id))
		base = {
			"option_id": option_id,
			"underlying": symbol_hint,
			"option_type": 0,
			"strike": 0.0,
			"expiry_day": 0,
			"expiry_phase": "close",
			"multiplier": 100
		}
	else:
		base["option_id"] = option_id
		if not base.has("multiplier"):
			base["multiplier"] = 100
	return base

func _merge_option_details(base: Dictionary, update: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate(true) if base != null else {}
	if update == null or update.is_empty():
		return merged
	if update.has("contract"):
		var contract_val: Variant = update["contract"]
		if contract_val is OptionContract:
			var contract_inst: OptionContract = contract_val as OptionContract
			var contract_details: Dictionary = _details_from_contract(contract_inst)
			merged = _merge_option_details(merged, contract_details)
	var option_id_val: Variant = update.get("option_id", update.get("id", merged.get("option_id", "")))
	var option_id_str: String = String(option_id_val)
	if option_id_str.strip_edges() != "":
		merged["option_id"] = option_id_str
	var symbol_val: Variant = update.get("symbol", update.get("underlying", merged.get("underlying", "")))
	var symbol_str: String = String(symbol_val)
	if symbol_str.strip_edges() != "":
		merged["underlying"] = symbol_str
	if update.has("option_type"):
		merged["option_type"] = int(update["option_type"])
	if update.has("strike"):
		merged["strike"] = float(update["strike"])
	if update.has("expiry_day"):
		merged["expiry_day"] = int(update["expiry_day"])
	if update.has("expiry_phase"):
		merged["expiry_phase"] = String(update["expiry_phase"])
	if update.has("multiplier"):
		merged["multiplier"] = int(update["multiplier"])
	return merged

func _details_from_contract(contract: OptionContract) -> Dictionary:
	var details: Dictionary = {}
	if contract == null:
		return details
	details["option_id"] = String(contract.id)
	details["underlying"] = String(contract.underlying)
	details["option_type"] = int(contract.option_type)
	details["strike"] = float(contract.strike)
	details["expiry_day"] = int(contract.expiry_day)
	details["expiry_phase"] = String(contract.expiry_phase)
	details["multiplier"] = int(contract.multiplier)
	return details
