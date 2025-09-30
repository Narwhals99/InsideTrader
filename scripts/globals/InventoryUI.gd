# InventoryUI.gd
# Attach to a CanvasLayer node in your InventoryUI scene
extends CanvasLayer

# Preload FoodData class
const FoodData = preload("res://scripts/resources/FoodData.gd")

@export var pause_game_on_open: bool = false
@export var grid_columns: int = 5
@export var slot_size: Vector2 = Vector2(80, 80)

# UI References (set these in the scene)
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/VBox/Header/Title
@onready var close_button: Button = $Panel/VBox/Header/CloseButton
@onready var grid_container: GridContainer = $Panel/VBox/ScrollContainer/GridContainer
@onready var item_info_panel: Panel = $Panel/ItemInfoPanel
@onready var item_name_label: Label = $Panel/ItemInfoPanel/VBox/ItemName
@onready var item_quantity_label: Label = $Panel/ItemInfoPanel/VBox/Quantity
@onready var item_description_label: Label = $Panel/ItemInfoPanel/VBox/Description

var is_open: bool = false
var item_slots: Dictionary = {}  # item_id -> slot UI reference
var selected_item: String = ""

# For food consumption
var _current_food_item: String = ""
var _current_food_data: FoodData = null

# Item display data (expand this as you add more items)
var item_data: Dictionary = {
	"beer": {
		"name": "Beer",
		"icon": "🍺",
		"description": "A cold beer. Someone might appreciate this.",
		"stackable": true,
		"max_stack": 99
	},
	"cash": {
		"name": "Cash",
		"icon": "$$",
		"description": "Money for purchases",
		"stackable": true,
		"max_stack": 9999
	},
	"key_card": {
		"name": "Key Card",
		"icon": "🔑",
		"description": "Access card for restricted areas",
		"stackable": false
	},
	# Food items
	"burger": {
		"name": "Classic Burger",
		"icon": "🍔",
		"description": "A juicy burger that restores hunger",
		"stackable": true,
		"max_stack": 10
	},
	"fries": {
		"name": "French Fries",
		"icon": "🍟",
		"description": "Crispy fries",
		"stackable": true,
		"max_stack": 10
	},
	"coffee": {
		"name": "Coffee",
		"icon": "☕",
		"description": "Gives you an energy boost",
		"stackable": true,
		"max_stack": 5
	},
	"salad": {
		"name": "Garden Salad",
		"icon": "🥗",
		"description": "A healthy salad",
		"stackable": true,
		"max_stack": 10
	},
	"soda": {
		"name": "Soda",
		"icon": "🥤",
		"description": "Refreshing soda",
		"stackable": true,
		"max_stack": 10
	},
	"pizza": {
		"name": "Pizza Slice",
		"icon": "🍕",
		"description": "Late night pizza",
		"stackable": true,
		"max_stack": 10
	}
}

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Setup UI
	_setup_ui()
	
	# Connect signals
	if close_button:
		close_button.pressed.connect(close)
	
	# Connect to inventory changes
	if typeof(Inventory) != TYPE_NIL:
		if not Inventory.inventory_changed.is_connected(_on_inventory_changed):
			Inventory.inventory_changed.connect(_on_inventory_changed)
	
	# Setup input
	if not InputMap.has_action("open_inventory"):
		InputMap.add_action("open_inventory")
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F
		InputMap.action_add_event("open_inventory", event)
	
	# Hide item info initially
	if item_info_panel:
		item_info_panel.visible = false

func _setup_ui() -> void:
	if not panel:
		# Create the UI programmatically if scene not set up
		panel = Panel.new()
		panel.name = "Panel"
		panel.size = Vector2(500, 600)
		panel.position = Vector2(100, 50)
		add_child(panel)
		
		var vbox := VBoxContainer.new()
		vbox.name = "VBox"
		panel.add_child(vbox)
		
		# Header
		var header := HBoxContainer.new()
		header.name = "Header"
		vbox.add_child(header)
		
		title_label = Label.new()
		title_label.text = "Inventory"
		title_label.add_theme_font_size_override("font_size", 20)
		header.add_child(title_label)
		
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(spacer)
		
		close_button = Button.new()
		close_button.text = "X"
		close_button.custom_minimum_size = Vector2(30, 30)
		header.add_child(close_button)
		close_button.pressed.connect(close)
		
		# Scroll container for grid
		var scroll := ScrollContainer.new()
		scroll.name = "ScrollContainer"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(scroll)
		
		grid_container = GridContainer.new()
		grid_container.name = "GridContainer"
		grid_container.columns = grid_columns
		grid_container.add_theme_constant_override("h_separation", 10)
		grid_container.add_theme_constant_override("v_separation", 10)
		scroll.add_child(grid_container)
		
		# Item info panel (overlay)
		item_info_panel = Panel.new()
		item_info_panel.name = "ItemInfoPanel"
		item_info_panel.size = Vector2(200, 150)
		item_info_panel.position = Vector2(520, 100)
		item_info_panel.visible = false
		add_child(item_info_panel)
		
		var info_vbox := VBoxContainer.new()
		info_vbox.name = "VBox"
		item_info_panel.add_child(info_vbox)
		
		item_name_label = Label.new()
		item_name_label.name = "ItemName"
		item_name_label.add_theme_font_size_override("font_size", 16)
		info_vbox.add_child(item_name_label)
		
		item_quantity_label = Label.new()
		item_quantity_label.name = "Quantity"
		info_vbox.add_child(item_quantity_label)
		
		item_description_label = Label.new()
		item_description_label.name = "Description"
		item_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(item_description_label)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_inventory"):
		if is_open:
			close()
		else:
			open()

func open() -> void:
	if is_open:
		return
	
	is_open = true
	visible = true
	
	if pause_game_on_open:
		get_tree().paused = true
		process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# Ensure mouse is visible
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Refresh the display
	_refresh_inventory_display()
	
	# Play open sound if available
	EventBus.emit_signal("ui_opened", "inventory")

func close(restore_mouse_mode: bool = true) -> void:
	if not is_open:
		return
	
	is_open = false
	visible = false
	
	if pause_game_on_open:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT
	
	# Restore mouse mode for FPS
	if restore_mouse_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Hide info panel
	if item_info_panel:
		item_info_panel.visible = false
	
	EventBus.emit_signal("ui_closed", "inventory")

func _refresh_inventory_display() -> void:
	# Clear existing slots
	for child in grid_container.get_children():
		child.queue_free()
	item_slots.clear()
	
	# Get current inventory from the service
	if typeof(Inventory) == TYPE_NIL:
		return
	
	var items: Dictionary = Inventory.items
	
	# Create slot for each item
	for item_id in items:
		var quantity: int = items[item_id]
		if quantity <= 0:
			continue
		
		var slot := _create_item_slot(item_id, quantity)
		grid_container.add_child(slot)
		item_slots[item_id] = slot
	
	# Add some empty slots for visual consistency
	var current_slots := items.size()
	var target_slots := grid_columns * 3  # Show at least 3 rows
	for i in range(target_slots - current_slots):
		var empty_slot := _create_empty_slot()
		grid_container.add_child(empty_slot)

func _create_item_slot(item_id: String, quantity: int) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = slot_size
	slot.size = slot_size
	
	# Add a stylebox for the slot
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style.border_color = Color(0.4, 0.4, 0.4)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	slot.add_theme_stylebox_override("panel", style)
	
	# Item icon or text
	var icon_label := Label.new()
	var data: Dictionary = item_data.get(item_id, {})
	icon_label.text = data.get("icon", "?")
	icon_label.add_theme_font_size_override("font_size", 32)
	icon_label.position = Vector2(20, 10)
	slot.add_child(icon_label)
	
	# Item name
	var name_label := Label.new()
	name_label.text = data.get("name", item_id.capitalize())
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.position = Vector2(5, 50)
	slot.add_child(name_label)
	
	# Quantity badge
	if quantity > 1:
		var qty_label := Label.new()
		qty_label.text = str(quantity)
		qty_label.add_theme_font_size_override("font_size", 14)
		qty_label.add_theme_color_override("font_color", Color(1, 1, 0))
		qty_label.position = Vector2(60, 5)
		slot.add_child(qty_label)
	
	# Make it interactive
	slot.gui_input.connect(_on_slot_input.bind(item_id))
	slot.mouse_entered.connect(_on_slot_hover.bind(item_id, true))
	slot.mouse_exited.connect(_on_slot_hover.bind(item_id, false))
	
	return slot

func _create_empty_slot() -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = slot_size
	slot.size = slot_size
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style.border_color = Color(0.2, 0.2, 0.2)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	slot.add_theme_stylebox_override("panel", style)
	
	return slot

func _on_slot_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select_item(item_id)
			# Check if it's a food item and show consume option
			_check_food_consumption(item_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_use_item(item_id)

func _check_food_consumption(item_id: String) -> void:
	# Check if this is a food item by trying to load its data
	var food_data = _get_food_data(item_id)
	if food_data:
		_show_food_options(item_id, food_data)

func _get_food_data(item_id: String) -> FoodData:
	# Try to load food data for this item
	# First check if we have a registry of food items
	var food_data_path = "res://data/food/%s.tres" % item_id
	if ResourceLoader.exists(food_data_path):
		return load(food_data_path) as FoodData
	
	# Or create a temporary FoodData based on known items
	var temp_food = _create_temp_food_data(item_id)
	return temp_food

func _create_temp_food_data(item_id: String) -> FoodData:
	# Create FoodData for known food items that were purchased
	var food = FoodData.new()
	match item_id:
		"burger", "classic_burger":
			food.item_id = item_id
			food.display_name = "Classic Burger"
			food.hunger_restore = 40.0
			food.consume_message = "That burger really hit the spot!"
			return food
		"fries", "french_fries":
			food.item_id = item_id
			food.display_name = "French Fries"
			food.hunger_restore = 15.0
			food.consume_message = "The fries were perfectly crispy!"
			return food
		"coffee":
			food.item_id = item_id
			food.display_name = "Coffee"
			food.energy_restore = 30.0
			food.buff_duration = 60.0
			food.speed_multiplier = 1.15
			food.consume_message = "The coffee gives you a nice energy boost!"
			return food
		"salad", "garden_salad":
			food.item_id = item_id
			food.display_name = "Garden Salad"
			food.hunger_restore = 25.0
			food.consume_message = "You feel healthier after that salad!"
			return food
		"soda":
			food.item_id = item_id
			food.display_name = "Soda"
			food.hunger_restore = 5.0
			food.energy_restore = 10.0
			food.consume_message = "The cold soda is refreshing!"
			return food
		"pizza", "pizza_slice":
			food.item_id = item_id
			food.display_name = "Pizza Slice"
			food.hunger_restore = 30.0
			food.consume_message = "Nothing beats late night pizza!"
			return food
		_:
			return null

func _show_food_options(item_id: String, food_data: FoodData) -> void:
	# Create a simple context menu for food items
	var options = []
	
	# Build consume option with details
	var consume_text = "Eat %s" % food_data.display_name
	if food_data.hunger_restore > 0:
		consume_text += " (+%.0f hunger)" % food_data.hunger_restore
	if food_data.energy_restore > 0:
		consume_text += " (+%.0f energy)" % food_data.energy_restore
	
	options.append({"id": "consume", "text": consume_text})
	options.append({"id": "cancel", "text": "Cancel"})
	
	# Store the current food item being interacted with
	_current_food_item = item_id
	_current_food_data = food_data
	
	# Show dialogue menu for the food
	EventBus.emit_signal("dialogue_requested", "Inventory", "What do you want to do?", 0.0, options)
	
	# Connect to response if not already
	if not EventBus.dialogue_completed.is_connected(_on_food_choice):
		EventBus.dialogue_completed.connect(_on_food_choice)
	if is_open:
		close(false)

func _on_food_choice(choice_index: int) -> void:
	if _current_food_item == "" or not _current_food_data:
		return
	
	if choice_index == 0:  # Consume
		_consume_food_item(_current_food_item, _current_food_data)
	
	# Clear current food
	_current_food_item = ""
	_current_food_data = null

func _consume_food_item(item_id: String, food_data: FoodData) -> void:
	# Check if player is too full
	if food_data.hunger_restore > 0 and typeof(NeedsSystem) != TYPE_NIL:
		var current_hunger = NeedsSystem.get_need_value("hunger")
		if current_hunger >= 95.0:
			EventBus.emit_notification("You're too full to eat this right now.", "warning", 2.0)
			return
	
	# Remove from inventory
	if not Inventory.remove_item(item_id, 1):
		EventBus.emit_notification("Failed to consume item", "danger", 2.0)
		return
	
	# Apply food effects
	if food_data.hunger_restore > 0 and typeof(NeedsSystem) != TYPE_NIL:
		NeedsSystem.eat_food(food_data.hunger_restore)
	
	if food_data.energy_restore > 0 and typeof(NeedsSystem) != TYPE_NIL:
		if NeedsSystem.energy_enabled:
			NeedsSystem.drink_coffee()  # Reuse existing method
	
	# Apply speed buff if any
	if food_data.buff_duration > 0 and food_data.speed_multiplier != 1.0:
		_apply_speed_buff(food_data.speed_multiplier, food_data.buff_duration)
	
	# Show consume message
	EventBus.emit_notification(food_data.get_consume_message(), "success", 3.0)
	
	# Refresh inventory display
	_refresh_inventory_display()

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

func _on_slot_hover(item_id: String, hovering: bool) -> void:
	if not item_info_panel:
		return
	
	if hovering:
		_show_item_info(item_id)
	else:
		item_info_panel.visible = false

func _select_item(item_id: String) -> void:
	selected_item = item_id
	print("[Inventory] Selected: ", item_id)
	
	# Highlight the slot
	if item_slots.has(item_id):
		var slot: Panel = item_slots[item_id]
		var style := slot.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.border_color = Color(1, 1, 0)

func _use_item(item_id: String) -> void:
	print("[Inventory] Attempting to use: ", item_id)
	
	# Item-specific use logic
	match item_id:
		"beer":
			# Check if near an NPC who wants beer
			var message := "You need to be near someone who wants a beer."
			EventBus.emit_notification(message, "info", 2.0)
		_:
			EventBus.emit_notification("Can't use " + item_id + " right now", "info", 2.0)

func _show_item_info(item_id: String) -> void:
	if not item_info_panel:
		return
	
	var data: Dictionary = item_data.get(item_id, {})
	var quantity: int = 0
	if typeof(Inventory) != TYPE_NIL:
		quantity = Inventory.get_quantity(item_id)
	
	item_name_label.text = data.get("name", item_id.capitalize())
	item_quantity_label.text = "Quantity: " + str(quantity)
	item_description_label.text = data.get("description", "No description available")
	
	# Position near mouse
	var mouse_pos := get_viewport().get_mouse_position()
	item_info_panel.position = mouse_pos + Vector2(10, 10)
	
	# Keep on screen
	var screen_size: Vector2 = get_viewport().size
	if item_info_panel.position.x + item_info_panel.size.x > screen_size.x:
		item_info_panel.position.x = mouse_pos.x - item_info_panel.size.x - 10
	if item_info_panel.position.y + item_info_panel.size.y > screen_size.y:
		item_info_panel.position.y = mouse_pos.y - item_info_panel.size.y - 10
	
	item_info_panel.visible = true

func _on_inventory_changed() -> void:
	if is_open:
		_refresh_inventory_display()

# Public API for other systems
func add_item_type(item_id: String, name: String, icon: String, description: String, stackable: bool = true) -> void:
	item_data[item_id] = {
		"name": name,
		"icon": icon,
		"description": description,
		"stackable": stackable,
		"max_stack": 99 if stackable else 1
	}

func get_selected_item() -> String:
	return selected_item

func is_inventory_open() -> bool:
	return is_open
