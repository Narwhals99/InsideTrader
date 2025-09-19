# NeedsHUD.gd
# Attach to a CanvasLayer node (or add as scene)
# Shows visual bars for player needs on left side of screen
extends CanvasLayer

@export_group("Display Settings")
@export var always_visible: bool = true
@export var fade_when_full: bool = true  # Fade out bars when needs are satisfied
@export var show_labels: bool = true
@export var show_values: bool = false  # Show numeric values
@export var vertical_spacing: int = 10
@export var bar_width: int = 40
@export var bar_height: int = 150
@export var margin_from_edge: int = 20
@export var margin_from_top: int = 100

@export_group("Style")
@export var background_opacity: float = 0.7
@export var bar_background_color: Color = Color(0.1, 0.1, 0.1, 0.8)
@export var hunger_color: Color = Color(0.8, 0.4, 0.1)  # Orange
@export var energy_color: Color = Color(0.2, 0.6, 0.9)  # Blue
@export var hunger_critical_color: Color = Color(0.9, 0.2, 0.1)  # Red
@export var energy_critical_color: Color = Color(0.4, 0.2, 0.6)  # Purple

@export_group("Animations")
@export var use_animations: bool = true
@export var pulse_when_critical: bool = true
@export var animation_speed: float = 1.0

# UI Elements (created dynamically)
var container: VBoxContainer
var hunger_bar: ProgressBar
var hunger_label: Label
var energy_bar: ProgressBar
var energy_label: Label
var rent_panel: Panel
var rent_label: Label

# State tracking
var _is_hunger_critical: bool = false
var _is_energy_critical: bool = false
var _pulse_timer: float = 0.0
var _needs_system: Node = null

func _ready() -> void:
	layer = 5  # Below phone/inventory but above game
	
	# Find NeedsSystem
	_needs_system = get_node_or_null("/root/NeedsSystem")
	if not _needs_system:
		# Try to find it in the scene
		_needs_system = get_tree().get_first_node_in_group("needs_system")
	
	if not _needs_system:
		push_warning("[NeedsHUD] NeedsSystem not found! HUD will not update.")
		return
	
	# Create UI
	_create_ui()
	
	# Connect to needs system signals
	if not _needs_system.need_changed.is_connected(_on_need_changed):
		_needs_system.need_changed.connect(_on_need_changed)
	if not _needs_system.need_critical.is_connected(_on_need_critical):
		_needs_system.need_critical.connect(_on_need_critical)
	
	# Initial update
	_update_all_displays()

func _create_ui() -> void:
	# Main container - anchored to bottom left
	container = VBoxContainer.new()
	container.name = "NeedsContainer"
	container.add_theme_constant_override("separation", vertical_spacing)
	
	# Anchor to bottom left
	container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	container.position = Vector2(margin_from_edge, -500)  # Negative Y to go up from bottom
	
	add_child(container)
	
	# Rest of the function remains the same...
	
	# Create background panel
	var bg_panel = Panel.new()
	bg_panel.name = "Background"
	bg_panel.position = Vector2(-10, -10)
	bg_panel.size = Vector2(bar_width + 40, (bar_height + 30) * 3 + vertical_spacing * 2 + 20)
	bg_panel.modulate.a = background_opacity
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	bg_style.border_color = Color(0.2, 0.2, 0.2, 0.5)
	bg_style.corner_radius_top_left = 5
	bg_style.corner_radius_top_right = 5
	bg_style.corner_radius_bottom_left = 5
	bg_style.corner_radius_bottom_right = 5
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.border_width_top = 2
	bg_style.border_width_bottom = 2
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	container.add_child(bg_panel)
	container.move_child(bg_panel, 0)
	
	# HUNGER BAR
	var hunger_container = VBoxContainer.new()
	hunger_container.name = "HungerContainer"
	container.add_child(hunger_container)
	
	if show_labels:
		hunger_label = Label.new()
		hunger_label.text = "Hunger"
		hunger_label.add_theme_font_size_override("font_size", 12)
		hunger_label.add_theme_color_override("font_color", hunger_color)
		hunger_container.add_child(hunger_label)
	
	hunger_bar = _create_vertical_bar()
	hunger_bar.name = "HungerBar"
	hunger_bar.modulate = hunger_color
	hunger_container.add_child(hunger_bar)
	
	# ENERGY BAR (if enabled)
	if _needs_system and _needs_system.get("energy_enabled"):
		var energy_container = VBoxContainer.new()
		energy_container.name = "EnergyContainer"
		container.add_child(energy_container)
		
		if show_labels:
			energy_label = Label.new()
			energy_label.text = "Energy"
			energy_label.add_theme_font_size_override("font_size", 12)
			energy_label.add_theme_color_override("font_color", energy_color)
			energy_container.add_child(energy_label)
		
		energy_bar = _create_vertical_bar()
		energy_bar.name = "EnergyBar"
		energy_bar.modulate = energy_color
		energy_container.add_child(energy_bar)
	
	# RENT DISPLAY
	if _needs_system and _needs_system.get("rent_enabled"):
		rent_panel = Panel.new()
		rent_panel.name = "RentPanel"
		rent_panel.custom_minimum_size = Vector2(bar_width + 20, 50)
		
		var rent_style = StyleBoxFlat.new()
		rent_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
		rent_style.border_color = Color(0.4, 0.4, 0.2)
		rent_style.corner_radius_top_left = 3
		rent_style.corner_radius_top_right = 3
		rent_style.corner_radius_bottom_left = 3
		rent_style.corner_radius_bottom_right = 3
		rent_style.border_width_left = 1
		rent_style.border_width_right = 1
		rent_style.border_width_top = 1
		rent_style.border_width_bottom = 1
		rent_panel.add_theme_stylebox_override("panel", rent_style)
		
		var rent_vbox = VBoxContainer.new()
		rent_vbox.add_theme_constant_override("separation", 2)
		rent_panel.add_child(rent_vbox)
		
		var rent_title = Label.new()
		rent_title.text = "Rent Due"
		rent_title.add_theme_font_size_override("font_size", 11)
		rent_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
		rent_vbox.add_child(rent_title)
		
		rent_label = Label.new()
		rent_label.text = "? days"
		rent_label.add_theme_font_size_override("font_size", 14)
		rent_label.add_theme_color_override("font_color", Color.WHITE)
		rent_vbox.add_child(rent_label)
		
		container.add_child(rent_panel)

func _create_vertical_bar() -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(bar_width, bar_height)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.show_percentage = show_values
	
	# Style the bar
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = bar_background_color
	bar_bg.corner_radius_top_left = 3
	bar_bg.corner_radius_top_right = 3
	bar_bg.corner_radius_bottom_left = 3
	bar_bg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bar_bg)
	
	var bar_fg = StyleBoxFlat.new()
	bar_fg.bg_color = Color.WHITE  # Will be modulated
	bar_fg.corner_radius_top_left = 3
	bar_fg.corner_radius_top_right = 3
	bar_fg.corner_radius_bottom_left = 3
	bar_fg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", bar_fg)
	
	return bar

func _process(delta: float) -> void:
	if not visible:
		return
	
	# Handle pulsing animation for critical needs
	if pulse_when_critical and (_is_hunger_critical or _is_energy_critical):
		_pulse_timer += delta * animation_speed * 4.0
		var pulse = abs(sin(_pulse_timer)) * 0.3 + 0.7
		
		if _is_hunger_critical and hunger_bar:
			hunger_bar.modulate.a = pulse
		if _is_energy_critical and energy_bar:
			energy_bar.modulate.a = pulse
	
	# Update rent display
	if rent_label and _needs_system:
		var days = _needs_system.get_days_until_rent()
		if days >= 0:
			rent_label.text = str(days) + " days"
			
			# Color code based on urgency
			if days == 0:
				rent_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
			elif days <= 3:
				rent_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
			else:
				rent_label.add_theme_color_override("font_color", Color.WHITE)
	
	# Auto-hide when needs are satisfied (optional)
	if fade_when_full and not always_visible:
		var should_show = false
		
		if hunger_bar and hunger_bar.value < 80:
			should_show = true
		if energy_bar and energy_bar.value < 80:
			should_show = true
		if _needs_system and _needs_system.get_days_until_rent() <= 3:
			should_show = true
		
		var target_alpha = 1.0 if should_show else 0.3
		if container:
			container.modulate.a = lerp(container.modulate.a, target_alpha, delta * 2.0)

func _on_need_changed(need_id: String, value: float, max_value: float) -> void:
	var percentage = (value / max_value) * 100.0 if max_value > 0 else 0.0
	
	match need_id:
		"hunger":
			if hunger_bar:
				if use_animations:
					var tween = create_tween()
					tween.tween_property(hunger_bar, "value", percentage, 0.5)
				else:
					hunger_bar.value = percentage
				
				# Update color based on level
				if percentage <= 20:
					hunger_bar.modulate = hunger_critical_color
					_is_hunger_critical = true
				else:
					hunger_bar.modulate = hunger_color
					_is_hunger_critical = false
				
				# Update label if showing values
				if show_values and hunger_label:
					hunger_label.text = "Hunger: %.0f%%" % percentage
		
		"energy":
			if energy_bar:
				if use_animations:
					var tween = create_tween()
					tween.tween_property(energy_bar, "value", percentage, 0.5)
				else:
					energy_bar.value = percentage
				
				# Update color based on level
				if percentage <= 15:
					energy_bar.modulate = energy_critical_color
					_is_energy_critical = true
				else:
					energy_bar.modulate = energy_color
					_is_energy_critical = false
				
				# Update label if showing values
				if show_values and energy_label:
					energy_label.text = "Energy: %.0f%%" % percentage

func _on_need_critical(need_id: String, _value: float) -> void:
	# Flash the bar when it becomes critical
	if not use_animations:
		return
	
	var bar: ProgressBar = null
	match need_id:
		"hunger":
			bar = hunger_bar
		"energy":
			bar = energy_bar
	
	if bar:
		var tween = create_tween()
		tween.set_loops(3)
		tween.tween_property(bar, "modulate:a", 0.2, 0.2)
		tween.tween_property(bar, "modulate:a", 1.0, 0.2)

func _update_all_displays() -> void:
	if not _needs_system:
		return
	
	# Update hunger
	if _needs_system.get("hunger_enabled"):
		var hunger_val = _needs_system.get_need_value("hunger")
		var hunger_max = _needs_system.get("hunger_max")
		_on_need_changed("hunger", hunger_val, hunger_max)
	
	# Update energy
	if _needs_system.get("energy_enabled"):
		var energy_val = _needs_system.get_need_value("energy")
		var energy_max = _needs_system.get("energy_max")
		_on_need_changed("energy", energy_val, energy_max)

# Public API
func show_hud() -> void:
	visible = true
	_update_all_displays()

func hide_hud() -> void:
	visible = false

func set_always_visible(always: bool) -> void:
	always_visible = always

func flash_need(need_id: String) -> void:
	"""Flash a specific need bar to draw attention"""
	var bar: ProgressBar = null
	match need_id:
		"hunger":
			bar = hunger_bar
		"energy":
			bar = energy_bar
	
	if bar and use_animations:
		var tween = create_tween()
		tween.set_loops(5)
		tween.tween_property(bar, "modulate:v", 2.0, 0.1)
		tween.tween_property(bar, "modulate:v", 1.0, 0.1)
