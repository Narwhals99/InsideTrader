# RestaurantWorker.gd
# Save as res://scripts/actors/RestaurantWorker.gd
# Attach this to the CharacterBody3D in your restaurant scene
# This combines the vendor functionality with a physical NPC
extends CharacterBody3D

@export_group("NPC Settings")
@export var npc_name: String = "Restaurant Worker"
@export var npc_id: String = "restaurant_worker_1"
@export var idle_animation: String = ""  # If you have animations

@export_group("Restaurant Settings")
@export var restaurant_name: String = "RestaurantHood Diner"
@export var use_default_menu: bool = true  # Use the default menu from RestaurantSetup
@export var custom_menu_items: Array[FoodData] = []  # Or define custom items in Inspector

# The Area3D child that handles interaction
var interaction_area: Area3D
var _player_in_range: bool = false

func _ready() -> void:
	add_to_group("restaurant_worker")
	
	# Find or create the Area3D child for interaction
	interaction_area = get_node_or_null("InteractionArea")
	if not interaction_area:
		interaction_area = Area3D.new()
		interaction_area.name = "InteractionArea"
		add_child(interaction_area)
		
		# Add a collision shape for interaction range
		var col_shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 3.0  # Interaction range
		col_shape.shape = sphere
		interaction_area.add_child(col_shape)
	
	# Connect area signals to track player
	interaction_area.body_entered.connect(_on_area_body_entered)
	interaction_area.body_exited.connect(_on_area_body_exited)
	interaction_area.monitoring = true
	
	# Set up the vendor component FIRST
	_setup_vendor()
	
	# THEN connect to EventBus dialogue_completed at the parent level
	if typeof(EventBus) != TYPE_NIL:
		if not EventBus.dialogue_completed.is_connected(_on_restaurant_dialogue_choice):
			EventBus.dialogue_completed.connect(_on_restaurant_dialogue_choice)
			print("[RestaurantWorker] Connected to EventBus.dialogue_completed")
	
	print("[RestaurantWorker] %s ready at %s" % [npc_name, restaurant_name])

func _on_restaurant_dialogue_choice(choice_index: int) -> void:
	# Forward the choice to the vendor if it has a menu open
	if interaction_area and interaction_area.has_method("_on_dialogue_choice"):
		if interaction_area.get("_menu_open"):
			print("[RestaurantWorker] Forwarding choice ", choice_index, " to vendor")
			interaction_area._on_dialogue_choice(choice_index)

func _on_area_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		EventBus.emit_notification("Press E to order food", "info", 2.0)

func _on_area_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false

func _input(event: InputEvent) -> void:
	# Handle input HERE in the CharacterBody3D instead of in the Area3D
	if event.is_action_pressed("interact") and _player_in_range:
		if interaction_area and interaction_area.has_method("open_menu"):
			# Check if menu is already open
			if interaction_area.get("_menu_open"):
				# Menu is open, close it
				if interaction_area.has_method("close_menu"):
					interaction_area.close_menu()
			else:
				# Menu is closed, open it
				interaction_area.open_menu()

func _setup_vendor() -> void:
	# Load and attach the FoodVendor script to the Area3D
	var vendor_script = load("res://scripts/components/FoodVendor.gd")
	if vendor_script:
		interaction_area.set_script(vendor_script)
		
		# Configure vendor settings
		interaction_area.vendor_name = restaurant_name
		interaction_area.vendor_id = npc_id + "_vendor"
		interaction_area.greeting_message = "Welcome to %s! What can I get for you today?" % restaurant_name
		interaction_area.closed_message = "Sorry, we're closed right now. Come back later!"
		interaction_area.no_money_message = "Sorry, you don't have enough money for that."
		
		# Set up menu
		if use_default_menu:
			var setup_script = load("res://scripts/areas/RestaurantSetup.gd")
			if setup_script:
				interaction_area.menu_items = setup_script.create_default_menu()
		else:
			interaction_area.menu_items = custom_menu_items
		
		# Configure interaction
		interaction_area.require_key_press = true
		interaction_area.show_wallet_balance = true
		interaction_area.show_nutrition_info = true
		interaction_area.show_prices = true
		interaction_area.auto_close_menu_on_purchase = false  # Keep menu open for multiple purchases
		
		# Operating hours - restaurants typically open most of the day
		interaction_area.always_open = false
		# Create properly typed array for open_phases
		var phases: Array[String] = []
		phases.append("Morning")
		phases.append("Market") 
		phases.append("Evening")
		phases.append("LateNight")
		interaction_area.open_phases = phases
		interaction_area.open_hour = 6   # 6 AM
		interaction_area.close_hour = 23  # 11 PM
		
		# Connect to vendor events if needed
		if not interaction_area.item_purchased.is_connected(_on_item_purchased):
			interaction_area.item_purchased.connect(_on_item_purchased)
		
		print("[RestaurantWorker] Vendor component configured with %d menu items" % interaction_area.menu_items.size())

func _on_item_purchased(item: FoodData, cost: float) -> void:
	# Play animation, sound effect, etc.
	print("[RestaurantWorker] Sold %s for $%.2f" % [item.display_name, cost])
	
	# Could trigger animations or dialogue here
	if item.category == "drink":
		_play_serve_drink_animation()
	else:
		_play_serve_food_animation()
	
	# Random thank you messages
	var thanks = [
		"Enjoy your %s!" % item.display_name,
		"Thanks for your business!",
		"That's a great choice!",
		"Coming right up!",
		"Here you go, fresh and hot!"
	]
	EventBus.emit_dialogue(npc_name, thanks[randi() % thanks.size()], 2.0)

func _play_serve_food_animation() -> void:
	# Implement if you have animations
	pass

func _play_serve_drink_animation() -> void:
	# Implement if you have animations
	pass

# Optional: Make the NPC look at the player when they're near
func _physics_process(_delta: float) -> void:
	# Disabled for now - can be re-enabled with proper rotation logic
	pass
	
func _look_at_player(player: Node3D) -> void:
	# Disabled - was causing NPC to face away
	pass

# Public API for other systems
func set_menu(items: Array[FoodData]) -> void:
	if interaction_area:
		interaction_area.menu_items = items

func add_menu_item(item: FoodData) -> void:
	if interaction_area:
		interaction_area.add_menu_item(item)

func is_open() -> bool:
	if interaction_area:
		return interaction_area.is_open()
	return false

func open_menu_for_player() -> void:
	"""Called externally to force open the menu"""
	if interaction_area:
		interaction_area.open_menu()
