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
	
	# Check if player can afford it
	var cash = TradingService.get_cash()
	if cash < beer_price:
		EventBus.emit_dialogue("Bartender", 
			"You need $%.0f for a beer. Come back when you have the cash." % beer_price)
		EventBus.emit_notification("Not enough cash! Need $%.0f" % beer_price, "danger", 3.0)
		return {
			"success": false,
			"message": "You need $%.0f for a beer." % beer_price
		}
	
	# Purchase beer (still using Portfolio directly for now - will migrate later)
	if typeof(Portfolio) != TYPE_NIL:
		Portfolio.cash -= beer_price
	
	# Add beer to shared inventory
	Inventory.add_item("beer", 1)
	
	# Emit events
	EventBus.emit_signal("beer_purchased")
	
	# Show feedback
	EventBus.emit_dialogue("Bartender", "Here's your beer! Someone might appreciate it...", 3.0)
	EventBus.emit_notification("Beer purchased! -$%.0f" % beer_price, "success", 2.0)
	EventBus.emit_notification("Cash remaining: $%.0f" % (cash - beer_price), "info", 2.0)
	
	print("[Bartender_NEW] Sold beer for $", beer_price)
	
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
		EventBus.emit_notification("Press E to buy beer ($%.0f)" % beer_price, "info", 2.0)
