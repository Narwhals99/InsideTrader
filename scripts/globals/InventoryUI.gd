# InventoryUI.gd
# Attach to a CanvasLayer node in your InventoryUI scene
extends CanvasLayer

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

# Item display data (expand this as you add more items)
var item_data: Dictionary = {
	"beer": {
		"name": "Beer",
		"icon": "",  # Can replace with actual texture path
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
		"icon": "",
		"description": "Access card for restricted areas",
		"stackable": false
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

func close() -> void:
	if not is_open:
		return
	
	is_open = false
	visible = false
	
	if pause_game_on_open:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT
	
	# Restore mouse mode for FPS
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
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_use_item(item_id)

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
