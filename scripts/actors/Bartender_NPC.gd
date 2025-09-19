# Bartender_NPC_NEW.gd
# Modular bartender using Inventory system
extends Area3D

@export var beer_price: float = 20.0
@export var interact_range: float = 3.0

var _player_near: bool = false
var _interact_locked: bool = false

func _ready() -> void:
	add_to_group("bartender_npc")
	
	# Setup collision
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Ensure interact action exists
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)
	
	# Listen for beer events
	EventBus.beer_given_to_npc.connect(_on_beer_given_away)
	
	print("[Bartender_NEW] Initialized with modular system")

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = true
		_show_prompt()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = false

func _input(event: InputEvent) -> void:
	if _player_near and event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	if _interact_locked:
		return
	
	_interact_locked = true
	interact()
	
	# Simple cooldown
	await get_tree().create_timer(0.2).timeout
	_interact_locked = false

func interact() -> Dictionary:
	# Check if player already has beer (using shared Inventory)
	if Inventory.has_beer():
		EventBus.emit_dialogue("Bartender", "You already have a beer. Give it to someone first!", 3.0)
		return {
			"success": false,
			"message": "You already have a beer. Give it to someone first!"
		}
	
	# NEW: Check BANK balance instead of Portfolio
	var bank_balance = 0.0
	if typeof(BankService) != TYPE_NIL:
		bank_balance = BankService.get_balance()
	else:
		# Fallback to old system if BankService not found
		bank_balance = TradingService.get_cash()
	
	if bank_balance < beer_price:
		EventBus.emit_dialogue("Bartender", 
			"You need $%.0f for a beer. Come back when you have the cash." % beer_price)
		EventBus.emit_notification("Not enough cash! Need $%.0f (Have: $%.0f)" % [beer_price, bank_balance], "danger", 3.0)
		return {
			"success": false,
			"message": "You need $%.0f for a beer." % beer_price
		}
	
	# NEW: Use BankService.purchase() instead of direct Portfolio manipulation
	var purchase_success = false
	if typeof(BankService) != TYPE_NIL:
		purchase_success = BankService.purchase("Beer", beer_price)
	else:
		# Fallback to old system
		if typeof(Portfolio) != TYPE_NIL and Portfolio.cash >= beer_price:
			Portfolio.cash -= beer_price
			purchase_success = true
	
	if not purchase_success:
		EventBus.emit_dialogue("Bartender", "Transaction failed. Try again.")
		return {
			"success": false,
			"message": "Transaction failed"
		}
	
	# Add beer to shared inventory
	Inventory.add_item("beer", 1)
	
	# Emit events
	EventBus.emit_signal("beer_purchased")
	EventBus.emit_signal("wallet_purchase_made", "Beer", beer_price)
	
	# Show feedback
	EventBus.emit_dialogue("Bartender", "Here's your beer! Someone might appreciate it...", 3.0)
	EventBus.emit_notification("Beer purchased! -$%.0f" % beer_price, "success", 2.0)
	
	# Show new bank balance
	if typeof(BankService) != TYPE_NIL:
		EventBus.emit_notification("Wallet balance: $%.0f" % BankService.get_balance(), "info", 2.0)
	
	print("[Bartender] Sold beer for $", beer_price, " from bank account")
	
	return {
		"success": true,
		"message": "Here's your beer!",
		"item": "beer"
	}

func _on_beer_given_away(npc_id: String) -> void:
	# Inventory handles this now
	var target := npc_id.capitalize()
	EventBus.emit_notification("Beer given to %s" % target, "info", 1.0)
	print("[Bartender] Player gave beer to", npc_id)

func has_beer() -> bool:
	"""For compatibility with old CEO code"""
	return Inventory.has_beer()

func player_gave_beer() -> void:
	"""Called by CEO for compatibility"""
	if Inventory.give_beer():
		EventBus.emit_signal("beer_given_to_npc", "ceo")

func _show_prompt() -> void:
	if not Inventory.has_beer():
		# Check bank balance for the prompt
		var can_afford = false
		if typeof(BankService) != TYPE_NIL:
			can_afford = BankService.can_afford(beer_price)
		else:
			# Fallback to portfolio check
			can_afford = (TradingService.get_cash() >= beer_price)
		
		if can_afford:
			EventBus.emit_notification("Press E to buy beer ($%.0f)" % beer_price, "info", 2.0)
		else:
			EventBus.emit_notification("Beer costs $%.0f (insufficient wallet funds)" % beer_price, "warning", 2.0)
