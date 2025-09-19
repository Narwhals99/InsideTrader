# FoodVendor.gd
# Save as res://scripts/components/FoodVendor.gd
# Attach to any Area3D to make it a food vendor (restaurant worker, vending machine, etc)
extends Area3D

# Preload FoodData if class_name isn't working
const FoodData = preload("res://scripts/resources/FoodData.gd")

@export_group("Vendor Settings")
@export var vendor_name: String = "Restaurant"
@export var vendor_id: String = "restaurant_1"
@export var greeting_message: String = "What can I get you today?"
@export var closed_message: String = "Sorry, we're closed right now."
@export var no_money_message: String = "You don't have enough money for that."
@export var purchase_cooldown: float = 0.5

@export_group("Operating Hours")
@export var always_open: bool = true
@export var open_phases: Array = ["Morning", "Market", "Evening"]  # When vendor is open (untyped array)
@export var open_hour: int = 6  # 24-hour format
@export var close_hour: int = 22

@export_group("Menu Items")
@export var menu_items: Array[FoodData] = []
@export var show_prices: bool = true
@export var show_descriptions: bool = true
@export var show_nutrition_info: bool = true  # Show hunger/energy restore values
@export var sort_by_category: bool = true

@export_group("Interaction")
@export var interaction_range: float = 3.0
@export var require_key_press: bool = false  # Changed to false - RestaurantWorker handles input
@export var interaction_key: String = "interact"
@export var auto_close_menu_on_purchase: bool = false
@export var show_wallet_balance: bool = true

@export_group("Visual Feedback")
@export var show_interaction_prompt: bool = true
@export var prompt_text: String = "Press E to order food"
@export var highlight_on_hover: bool = true

# Runtime state
var _player_in_range: bool = false
var _menu_open: bool = false
var _purchase_locked: bool = false
var _menu_options: Array = []

signal menu_opened()
signal menu_closed()
signal item_purchased(item: FoodData, cost: float)
signal purchase_failed(reason: String)

func _ready() -> void:
	# Enable input processing for this Area3D
	set_process_input(true)
	set_process_unhandled_input(true)
	
	# Setup collision detection
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Ensure interaction key exists
	if require_key_press and not InputMap.has_action(interaction_key):
		InputMap.add_action(interaction_key)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_E
		InputMap.action_add_event(interaction_key, event)
	
	# Connect to EventBus for menu responses
	if typeof(EventBus) != TYPE_NIL:
		if not EventBus.dialogue_completed.is_connected(_on_dialogue_choice):
			EventBus.dialogue_completed.connect(_on_dialogue_choice)
	
	print("[FoodVendor] %s initialized with %d menu items" % [vendor_name, menu_items.size()])

func _input(event: InputEvent) -> void:
	if not require_key_press:
		return
	
	if _player_in_range and not _menu_open and event.is_action_pressed(interaction_key):
		open_menu()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if show_interaction_prompt and not _menu_open:
			_show_prompt()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _menu_open:
			close_menu()

func open_menu() -> void:
	if _menu_open:
		return
	
	# Check if vendor is open
	if not is_open():
		EventBus.emit_dialogue(vendor_name, closed_message, 3.0)
		return
	
	_menu_open = true
	_build_menu_options()
	
	# Build the dialogue prompt
	var prompt = greeting_message
	if show_wallet_balance and typeof(BankService) != TYPE_NIL:
		var balance = BankService.get_balance()
		prompt += "\n[Wallet: $%.2f]" % balance
	
	# Show menu using dialogue system
	EventBus.emit_signal("dialogue_requested", vendor_name, prompt, 0.0, _menu_options)
	menu_opened.emit()

func close_menu() -> void:
	if not _menu_open:
		return
	
	_menu_open = false
	_menu_options.clear()
	
	# Clear dialogue
	EventBus.emit_signal("dialogue_requested", "", "", 0.0, [])
	menu_closed.emit()

func _build_menu_options() -> void:
	_menu_options.clear()
	
	# Get available items
	var available_items: Array[FoodData] = []
	for item in menu_items:
		if item and item.is_available_now():
			available_items.append(item)
	
	# Sort if needed
	if sort_by_category:
		available_items.sort_custom(_sort_by_category)
	
	# Build option entries
	for item in available_items:
		var option_text = item.display_name
		
		if show_prices:
			option_text += " - $%.2f" % item.get_current_price()
		
		if show_nutrition_info and (item.hunger_restore > 0 or item.energy_restore > 0):
			var nutrition = []
			if item.hunger_restore > 0:
				nutrition.append("+%.0f hunger" % item.hunger_restore)
			if item.energy_restore > 0:
				nutrition.append("+%.0f energy" % item.energy_restore)
			option_text += " (%s)" % ", ".join(nutrition)
		
		_menu_options.append({
			"id": item.item_id,
			"text": option_text,  # No number prefix - just click to select
			"data": item
		})
	
	# Add cancel option
	_menu_options.append({
		"id": "cancel",
		"text": "Never mind"
	})

func _sort_by_category(a: FoodData, b: FoodData) -> bool:
	if a.category == b.category:
		return a.base_price < b.base_price
	return a.category < b.category

func _on_dialogue_choice(choice_index: int) -> void:
	print("[FoodVendor] Dialogue choice received: ", choice_index)
	
	if not _menu_open:
		print("[FoodVendor] Menu not open, ignoring choice")
		return
	
	# Always close the menu after any choice
	_menu_open = false
	
	# If no valid choice (clicked outside or pressed E), just close
	if choice_index < 0 or choice_index >= _menu_options.size():
		print("[FoodVendor] Invalid choice index")
		return
	
	var choice = _menu_options[choice_index]
	print("[FoodVendor] Selected: ", choice.get("text", "unknown"))
	
	if choice.id == "cancel":
		print("[FoodVendor] Cancelled")
		return
	
	# Get the food item
	var food_item: FoodData = choice.get("data", null)
	if food_item:
		print("[FoodVendor] Attempting to purchase: ", food_item.display_name)
		_attempt_purchase(food_item)
	else:
		print("[FoodVendor] No food data found for choice!")

func _attempt_purchase(item: FoodData) -> void:
	print("[FoodVendor] Purchase attempt for: ", item.display_name, " at $", item.get_current_price())
	
	if _purchase_locked:
		print("[FoodVendor] Purchase locked, returning")
		return
	
	_purchase_locked = true
	
	# Get price
	var price = item.get_current_price()
	
	# Check if player can afford it (using BankService for wallet)
	if typeof(BankService) == TYPE_NIL:
		push_error("[FoodVendor] BankService not found!")
		_purchase_failed("Banking system unavailable")
		return
	
	var current_balance = BankService.get_balance()
	print("[FoodVendor] Wallet balance: $", current_balance, " Price: $", price)
	
	if not BankService.can_afford(price):
		print("[FoodVendor] Cannot afford!")
		_purchase_failed(no_money_message)
		EventBus.emit_notification(
			"Need $%.2f more for %s" % [price - BankService.get_balance(), item.display_name],
			"warning",
			3.0
		)
		return
	
	# Check if player is too full
	if item.hunger_restore > 0 and typeof(NeedsSystem) != TYPE_NIL:
		var current_hunger = NeedsSystem.get_need_value("hunger")
		if current_hunger >= 95.0:  # Nearly full
			_purchase_failed(item.full_message)
			EventBus.emit_notification(item.full_message, "warning", 2.0)
			return
	
	# Process payment through BankService
	var purchase_success = BankService.purchase(item.display_name, price)
	
	if not purchase_success:
		_purchase_failed("Transaction failed")
		return
	
	# Apply food effects
	_consume_food(item)
	
	# Success feedback
	EventBus.emit_notification(
		"Purchased %s for $%.2f" % [item.display_name, price],
		"success",
		2.0
	)
	
	item_purchased.emit(item, price)
	
	# Maybe close menu
	if auto_close_menu_on_purchase:
		close_menu()
	else:
		# Refresh menu to show updated wallet balance
		_build_menu_options()
		open_menu()
	
	# Cooldown
	await get_tree().create_timer(purchase_cooldown).timeout
	_purchase_locked = false

func _consume_food(item: FoodData) -> void:
	# Add to inventory for later consumption (instead of instant consumption)
	if typeof(Inventory) != TYPE_NIL:
		Inventory.add_item(item.item_id, 1)
		EventBus.emit_notification(
			"%s added to inventory!" % item.display_name,
			"info",
			2.0
		)
	
	# Show purchase success message
	EventBus.emit_dialogue(vendor_name, "Here's your %s!" % item.display_name, 3.0)
	
	# Note: We're NOT applying hunger/energy effects here anymore
	# The player will consume it from inventory when they want

func _apply_speed_buff(multiplier: float, duration: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	if "walk_speed" in player and "run_speed" in player:
		var original_walk = player.walk_speed
		var original_run = player.run_speed
		
		player.walk_speed *= multiplier
		player.run_speed *= multiplier
		
		EventBus.emit_notification(
			"Speed boost active for %.0f seconds!" % duration,
			"info",
			2.0
		)
		
		# Reset after duration
		await get_tree().create_timer(duration).timeout
		
		player.walk_speed = original_walk
		player.run_speed = original_run
		EventBus.emit_notification("Speed boost expired", "info", 2.0)

func _apply_special_effect(effect_id: String) -> void:
	# Implement custom effects here
	match effect_id:
		"instant_market_open":
			# Example: Special coffee that lets you trade for 1 minute even when market is closed
			pass
		"double_hunger_restore":
			# Example: Next food item restores double hunger
			pass
		_:
			print("[FoodVendor] Unknown special effect: ", effect_id)

func _purchase_failed(reason: String) -> void:
	purchase_failed.emit(reason)
	EventBus.emit_dialogue(vendor_name, reason, 3.0)
	
	# Don't close menu on failure, let player try again or cancel
	_purchase_locked = false

func _show_prompt() -> void:
	if not is_open():
		return
	
	EventBus.emit_notification(prompt_text, "info", 2.0)

func is_open() -> bool:
	if always_open:
		return true
	
	# Check phase-based hours
	if typeof(Game) != TYPE_NIL:
		var current_phase = String(Game.phase)
		if not current_phase in open_phases:
			return false
		
		# Check time-based hours
		var hour = Game.get_hour()
		if open_hour < close_hour:
			# Normal hours (e.g., 6am to 10pm)
			return hour >= open_hour and hour < close_hour
		else:
			# Overnight hours (e.g., 10pm to 2am)
			return hour >= open_hour or hour < close_hour
	
	return true

# Public API for external systems
func add_menu_item(item: FoodData) -> void:
	if item and not menu_items.has(item):
		menu_items.append(item)

func remove_menu_item(item_id: String) -> void:
	for i in range(menu_items.size() - 1, -1, -1):
		if menu_items[i].item_id == item_id:
			menu_items.remove_at(i)

func get_menu_item(item_id: String) -> FoodData:
	for item in menu_items:
		if item.item_id == item_id:
			return item
	return null

func set_item_availability(item_id: String, available: bool) -> void:
	var item = get_menu_item(item_id)
	if item:
		item.is_available = available
