extends Node

signal portfolio_changed()
signal order_executed(order: Dictionary)

@export var starting_cash: float = 10000.0
@export var commission_per_trade: float = 0.0
@export var allow_oversell: bool = false

var cash: float = 0.0
var realized_pnl: float = 0.0
var positions: Dictionary = {}			# sym:StringName -> {shares:int, avg_cost:float}
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
	return total

func net_worth() -> float:
	return cash + holdings_value()

# --- Mutations ---
func buy(sym: StringName, qty: int, price: float = -1.0) -> bool:
	if qty <= 0:
		return false
	if price <= 0.0:
		price = MarketSim.get_price(sym)
	var cost: float = price * qty + commission_per_trade
	if cash < cost:
		DialogueUI.notify("Not enough cash for trade!", "danger")
		return false

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
	return true
	
	DialogueUI.show_trade_result(true, "Bought " + str(qty) + " " + String(sym))

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
