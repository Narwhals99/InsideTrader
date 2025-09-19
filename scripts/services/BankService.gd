# BankService.gd
# Add as Autoload: Project Settings > Autoload > Add as "BankService"
# This is your WALLET for all non-trading expenses
extends Node

signal bank_balance_changed(new_balance: float)
signal transaction_completed(type: String, amount: float, new_balance: float)
signal withdrawal_attempted(amount: float, success: bool)
signal deposit_attempted(amount: float, success: bool)
signal purchase_attempted(item: String, cost: float, success: bool)

# Bank account is your walking-around money
@export var starting_bank_balance: float = 500.0  # Start with less since it's spending money
@export var min_bank_balance: float = 0.0  # Can't overdraft
@export var daily_withdraw_limit: float = 5000.0
@export var daily_deposit_limit: float = 10000.0

var bank_balance: float = 0.0
var _daily_withdrawn: float = 0.0
var _daily_deposited: float = 0.0
var _last_transaction_day: int = -1
var _transaction_history: Array[Dictionary] = []

func _ready() -> void:
	bank_balance = starting_bank_balance
	
	# Connect to day changes to reset daily limits
	if typeof(Game) != TYPE_NIL:
		if not Game.day_advanced.is_connected(_on_day_advanced):
			Game.day_advanced.connect(_on_day_advanced)
	
	print("[BankService] Initialized with balance: $", bank_balance)

# ============ QUERIES ============
func get_balance() -> float:
	"""Get current bank/wallet balance"""
	return bank_balance

func can_afford(amount: float) -> bool:
	"""Check if wallet has enough for a purchase"""
	return bank_balance >= amount

func get_available_to_withdraw() -> float:
	"""How much can be withdrawn from portfolio considering daily limit"""
	_check_daily_reset()
	var remaining_limit = max(0.0, daily_withdraw_limit - _daily_withdrawn)
	# Can't withdraw more than what portfolio has
	var portfolio_cash = 0.0
	if typeof(Portfolio) != TYPE_NIL:
		portfolio_cash = Portfolio.cash
	return min(portfolio_cash, remaining_limit)

func get_available_to_deposit() -> float:
	"""How much can be deposited to portfolio considering daily limit"""
	_check_daily_reset()
	var remaining_limit = max(0.0, daily_deposit_limit - _daily_deposited)
	# Can't deposit more than what's in bank
	return min(bank_balance - min_bank_balance, remaining_limit)

func get_daily_limits_status() -> Dictionary:
	_check_daily_reset()
	return {
		"withdrawn_today": _daily_withdrawn,
		"deposited_today": _daily_deposited,
		"withdraw_remaining": daily_withdraw_limit - _daily_withdrawn,
		"deposit_remaining": daily_deposit_limit - _daily_deposited,
		"day": _last_transaction_day
	}

func get_transaction_history(count: int = 10) -> Array[Dictionary]:
	"""Get last N transactions"""
	var start = max(0, _transaction_history.size() - count)
	return _transaction_history.slice(start, _transaction_history.size())

# ============ WALLET PURCHASES (for non-market transactions) ============
func purchase(item_name: String, cost: float) -> bool:
	"""Make a purchase from bank/wallet (for beer, items, etc)"""
	if cost <= 0:
		return true  # Free items always succeed
	
	if not can_afford(cost):
		EventBus.emit_notification(
			"Not enough cash! Need $%.2f (Have: $%.2f)" % [cost, bank_balance], 
			"danger", 
			3.0
		)
		emit_signal("purchase_attempted", item_name, cost, false)
		return false
	
	# Deduct from bank
	bank_balance -= cost
	
	# Record transaction
	_record_transaction("purchase", cost, 0.0, item_name)
	
	# Emit signals
	emit_signal("bank_balance_changed", bank_balance)
	emit_signal("transaction_completed", "purchase", cost, bank_balance)
	emit_signal("purchase_attempted", item_name, cost, true)
	EventBus.emit_signal("bank_transaction_completed", {
		"type": "purchase",
		"item": item_name,
		"amount": cost,
		"success": true,
		"new_balance": bank_balance
	})
	EventBus.emit_notification(
		"Purchased %s for $%.2f" % [item_name, cost], 
		"info", 
		2.0
	)
	
	return true

func add_money(amount: float, reason: String = "income") -> void:
	"""Add money directly to bank (for rewards, selling items, etc)"""
	if amount <= 0:
		return
	
	bank_balance += amount
	_record_transaction("income", amount, 0.0, reason)
	
	emit_signal("bank_balance_changed", bank_balance)
	emit_signal("transaction_completed", "income", amount, bank_balance)
	EventBus.emit_signal("bank_balance_updated", bank_balance)
	EventBus.emit_notification(
		"Received $%.2f (%s)" % [amount, reason], 
		"success", 
		2.0
	)

# ============ PORTFOLIO TRANSFERS ============
func withdraw_from_portfolio(amount: float) -> Dictionary:
	"""Transfer from trading portfolio to bank/wallet"""
	var result = {
		"success": false,
		"amount": amount,
		"message": "",
		"new_bank_balance": bank_balance,
		"new_portfolio_cash": 0.0
	}
	
	_check_daily_reset()
	
	# Validation
	if amount <= 0:
		result.message = "Invalid amount"
		return result
	
	if typeof(Portfolio) == TYPE_NIL:
		result.message = "Portfolio system unavailable"
		return result
	
	if amount > Portfolio.cash:
		result.message = "Insufficient portfolio funds (Available: $%.2f)" % Portfolio.cash
		EventBus.emit_notification(result.message, "danger", 3.0)
		emit_signal("withdrawal_attempted", amount, false)
		return result
	
	if _daily_withdrawn + amount > daily_withdraw_limit:
		var remaining = daily_withdraw_limit - _daily_withdrawn
		result.message = "Daily withdrawal limit exceeded (Remaining: $%.2f)" % remaining
		EventBus.emit_notification(result.message, "warning", 3.0)
		emit_signal("withdrawal_attempted", amount, false)
		return result
	
	# Execute transfer
	Portfolio.cash -= amount
	bank_balance += amount
	_daily_withdrawn += amount
	
	result.success = true
	result.new_bank_balance = bank_balance
	result.new_portfolio_cash = Portfolio.cash
	result.message = "Withdrew $%.2f from portfolio" % amount
	
	# Record transaction
	_record_transaction("withdraw", amount, 0.0)
	
	# Emit signals
	emit_signal("bank_balance_changed", bank_balance)
	emit_signal("transaction_completed", "withdraw", amount, bank_balance)
	emit_signal("withdrawal_attempted", amount, true)
	Portfolio.emit_signal("portfolio_changed")
	EventBus.emit_signal("bank_withdrawal_completed", result)
	EventBus.emit_notification(result.message, "success", 3.0)
	
	return result

func deposit_to_portfolio(amount: float) -> Dictionary:
	"""Transfer from bank/wallet to trading portfolio"""
	var result = {
		"success": false,
		"amount": amount,
		"message": "",
		"new_bank_balance": bank_balance,
		"new_portfolio_cash": 0.0
	}
	
	_check_daily_reset()
	
	# Validation
	if amount <= 0:
		result.message = "Invalid amount"
		return result
	
	if amount > bank_balance - min_bank_balance:
		result.message = "Insufficient bank funds (Available: $%.2f)" % (bank_balance - min_bank_balance)
		EventBus.emit_notification(result.message, "danger", 3.0)
		emit_signal("deposit_attempted", amount, false)
		return result
	
	if _daily_deposited + amount > daily_deposit_limit:
		var remaining = daily_deposit_limit - _daily_deposited
		result.message = "Daily deposit limit exceeded (Remaining: $%.2f)" % remaining
		EventBus.emit_notification(result.message, "warning", 3.0)
		emit_signal("deposit_attempted", amount, false)
		return result
	
	# Execute transfer
	bank_balance -= amount
	if typeof(Portfolio) != TYPE_NIL:
		Portfolio.cash += amount
		result.new_portfolio_cash = Portfolio.cash
	_daily_deposited += amount
	
	result.success = true
	result.new_bank_balance = bank_balance
	result.message = "Deposited $%.2f to portfolio" % amount
	
	# Record transaction
	_record_transaction("deposit", amount, 0.0)
	
	# Emit signals
	emit_signal("bank_balance_changed", bank_balance)
	emit_signal("transaction_completed", "deposit", amount, bank_balance)
	emit_signal("deposit_attempted", amount, true)
	if typeof(Portfolio) != TYPE_NIL:
		Portfolio.emit_signal("portfolio_changed")
	EventBus.emit_signal("bank_deposit_completed", result)
	EventBus.emit_notification(result.message, "success", 3.0)
	
	return result

# ============ PRIVATE HELPERS ============
func _check_daily_reset() -> void:
	"""Reset daily limits if it's a new day"""
	if typeof(Game) == TYPE_NIL:
		return
	
	var current_day = int(Game.day)
	if _last_transaction_day < 0:
		_last_transaction_day = current_day
		return
	
	if current_day != _last_transaction_day:
		_daily_withdrawn = 0.0
		_daily_deposited = 0.0
		_last_transaction_day = current_day
		print("[BankService] Daily limits reset for day ", current_day)

func _record_transaction(type: String, amount: float, fee: float, description: String = "") -> void:
	var transaction = {
		"type": type,
		"amount": amount,
		"fee": fee,
		"description": description,
		"balance_after": bank_balance,
		"timestamp": Time.get_ticks_msec(),
		"day": Game.day if typeof(Game) != TYPE_NIL else 0,
		"time_string": Game.get_time_string() if typeof(Game) != TYPE_NIL else "??:??"
	}
	
	_transaction_history.append(transaction)
	
	# Keep only last 100 transactions
	if _transaction_history.size() > 100:
		_transaction_history = _transaction_history.slice(-100, _transaction_history.size())

func _on_day_advanced(_day: int) -> void:
	_check_daily_reset()

# ============ SAVE/LOAD ============
func get_save_data() -> Dictionary:
	return {
		"bank_balance": bank_balance,
		"daily_withdrawn": _daily_withdrawn,
		"daily_deposited": _daily_deposited,
		"last_transaction_day": _last_transaction_day,
		"transaction_history": _transaction_history.duplicate(true)
	}

func load_save_data(data: Dictionary) -> void:
	bank_balance = data.get("bank_balance", starting_bank_balance)
	_daily_withdrawn = data.get("daily_withdrawn", 0.0)
	_daily_deposited = data.get("daily_deposited", 0.0)
	_last_transaction_day = data.get("last_transaction_day", -1)
	_transaction_history = data.get("transaction_history", []).duplicate(true)
	
	emit_signal("bank_balance_changed", bank_balance)
