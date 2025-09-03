# Bartender_NPC.gd - Fixed version
extends Area3D

signal beer_purchased()

@export var beer_price: float = 20.0
@export var interact_range: float = 3.0
@export var interact_lock_time: float = 0.2

var _player_near: bool = false
var _player_has_beer: bool = false
var _interact_locked: bool = false

func _ready() -> void:
	add_to_group("bartender_npc")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Ensure interact action exists
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = true
		# Only prompt when the player does NOT have a beer.
		if typeof(DialogueUI) != TYPE_NIL and not _player_has_beer:
			DialogueUI.notify("Press E to buy beer ($" + str(beer_price) + ")", "info", 2.0)

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
	await get_tree().create_timer(interact_lock_time).timeout
	_interact_locked = false

func interact() -> Dictionary:
	# Autoload guards
	if typeof(Portfolio) == TYPE_NIL:
		push_error("[Bartender] Autoload 'Portfolio' missing (Project Settings → Autoload).")
		return {"success": false, "message": "System error"}
	if typeof(DialogueUI) == TYPE_NIL:
		push_error("[Bartender] Autoload 'DialogueUI' missing (Project Settings → Autoload).")
		return {"success": false, "message": "System error"}
	
	# Only show "already have a beer" when pressing E again
	if _player_has_beer:
		DialogueUI.show_npc_dialogue("Bartender", "You already have a beer. Give it to someone first!")
		return {
			"success": false,
			"message": "You already have a beer. Give it to someone first!"
		}
	
	var current_cash: float = Portfolio.cash
	
	if current_cash < beer_price:
		DialogueUI.show_npc_dialogue("Bartender", "You need $" + str(beer_price) + " for a beer. Come back when you have the cash.")
		DialogueUI.notify("Not enough cash! Need $" + str(beer_price), "danger", 3.0)
		return {
			"success": false,
			"message": "You need $" + str(beer_price) + " for a beer."
		}
	
	# Purchase
	Portfolio.cash -= beer_price
	_player_has_beer = true
	emit_signal("beer_purchased")
	
	DialogueUI.show_npc_dialogue("Bartender", "Here's your beer! Someone might appreciate it...")
	DialogueUI.notify("Beer purchased! -$" + str(beer_price), "success", 2.0)
	DialogueUI.notify("Cash remaining: $" + str(Portfolio.cash), "info", 2.0)
	print("[Bartender] Sold beer for $", beer_price, ". Player cash remaining: $", Portfolio.cash)
	
	return {
		"success": true,
		"message": "Here's your beer!",
		"item": "beer"
	}

func player_gave_beer() -> void:
	_player_has_beer = false
	if typeof(DialogueUI) != TYPE_NIL:
		DialogueUI.notify("Beer given away", "info", 1.0)
	print("[Bartender] Player gave away their beer")

func has_beer() -> bool:
	return _player_has_beer
