# NeedsSystem.gd
# Add as Autoload: "NeedsSystem" OR attach to a Node in your scene
extends Node

signal need_changed(need_id: String, value: float, max_value: float)
signal need_critical(need_id: String, value: float)
signal need_satisfied(need_id: String)
signal need_failed(need_id: String, consequence: Dictionary)
signal need_reminder(need_id: String, message: String)

# ============ INSPECTOR CONTROLS ============
@export_group("System Settings")
@export var system_enabled: bool = true
@export var update_interval: float = 1.0  # How often to update needs (seconds)
@export var debug_mode: bool = false  # Print debug messages

@export_group("Hunger System")
@export var hunger_enabled: bool = true
@export var hunger_max: float = 100.0
@export var hunger_start_value: float = 80.0
@export var hunger_decay_per_hour: float = 5 # Needs food ~2x per day
@export var hunger_critical_threshold: float = 20.0
@export var hunger_food_restore: float = 50.0
@export var hunger_apply_consequences: bool = true
@export var hunger_speed_penalty: float = 0.7  # 70% speed when starving

@export_group("Energy System")
@export var energy_enabled: bool = false  # DISABLED BY DEFAULT
@export var energy_max: float = 100.0
@export var energy_start_value: float = 100.0
@export var energy_decay_per_hour: float = 4.16  # Lasts 24 hours
@export var energy_critical_threshold: float = 15.0
@export var energy_coffee_restore: float = 30.0
@export var energy_sleep_restore: float = 100.0
@export var energy_apply_consequences: bool = false

@export_group("Rent System")
@export var rent_enabled: bool = true
@export var rent_amount: float = 1500.0
@export var rent_interval_days: int = 7
@export var rent_auto_pay_from_bank: bool = true
@export var rent_grace_period_days: int = 2
@export var rent_apply_consequences: bool = true
@export var rent_allow_manual_payment: bool = false  # Can player pay early?

@export_group("Reminders")
@export var show_hunger_reminders: bool = true
@export var show_energy_reminders: bool = true
@export var show_rent_reminders: bool = true
@export var rent_reminder_days: Array[int] = [3, 1, 0]  # Days before due

# ============ RUNTIME DATA ============
var needs_data: Dictionary = {}
var active_consequences: Dictionary = {}
var _last_update_time: float = 0.0
var _payment_strikes: Dictionary = {}
var _next_rent_day: int = 7
var _reminder_cooldowns: Dictionary = {}
var _last_world_seconds: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if not system_enabled:
		set_process(false)
		return
	
	# Initialize enabled systems
	_initialize_needs()
	
	# Initialize world time tracking
	if typeof(Game) != TYPE_NIL and Game.has_method("get_world_seconds"):
		_last_world_seconds = Game.get_world_seconds()
	
	# Connect to game systems
	if typeof(Game) != TYPE_NIL:
		if not Game.day_advanced.is_connected(_on_day_advanced):
			Game.day_advanced.connect(_on_day_advanced)
	
	print("[NeedsSystem] Initialized - Hunger:", hunger_enabled, " Energy:", energy_enabled, " Rent:", rent_enabled)
	
	# FORCE OVERRIDE FOR TESTING - Comment out when you're done testing
	#hunger_decay_per_hour = 120.0  # This will make hunger drop 1 point every 30 game seconds
	#print("[NeedsSystem] OVERRIDE: Set hunger_decay to ", hunger_decay_per_hour, " per hour")

func _initialize_needs() -> void:
	# Initialize hunger
	if hunger_enabled:
		needs_data["hunger"] = {
			"current": hunger_start_value,
			"max": hunger_max
		}
	
	# Initialize energy
	if energy_enabled:
		needs_data["energy"] = {
			"current": energy_start_value,
			"max": energy_max
		}
	
	# Initialize rent
	if rent_enabled and typeof(Game) != TYPE_NIL:
		_next_rent_day = int(Game.day) + rent_interval_days

func _process(_delta: float) -> void:
	if not system_enabled:
		return
	
	# Accumulate real time
	_last_update_time += _delta
	if _last_update_time < update_interval:
		return  # Don't process until interval is reached
	
	# Reset the accumulator
	_last_update_time = 0.0
	
	# Now check game time
	if typeof(Game) == TYPE_NIL or not Game.has_method("get_world_seconds"):
		return
	
	var current_world_seconds = Game.get_world_seconds()
	var game_time_passed = current_world_seconds - _last_world_seconds
	
	# Skip if no game time has passed
	if game_time_passed <= 0:
		return
	
	_last_world_seconds = current_world_seconds
	
	# Process enabled needs with game time
	if hunger_enabled:
		_process_hunger(game_time_passed)
	
	if energy_enabled:
		_process_energy(game_time_passed)
# ============ HUNGER SYSTEM ============
func _process_hunger(delta_time: float) -> void:
	# Make sure hunger data exists
	if not needs_data.has("hunger"):
		needs_data["hunger"] = {"current": hunger_start_value, "max": hunger_max}
	
	# Get current value directly (not a copy)
	var current = needs_data["hunger"]["current"]
	
	# Decay hunger
	var decay_per_second = hunger_decay_per_hour / 3600.0
	var decay_amount = decay_per_second * delta_time
	
	current -= decay_amount
	current = clamp(current, 0.0, hunger_max)
	
	# Update the value directly in the dictionary
	needs_data["hunger"]["current"] = current
	
	# Emit the change signal for UI updates
	emit_signal("need_changed", "hunger", current, hunger_max)
	
	# Check for reminders
	if show_hunger_reminders:
		_check_hunger_reminders(current)
	
	# Apply consequences if enabled
	if hunger_apply_consequences and current <= hunger_critical_threshold:
		_apply_hunger_penalty()
	elif hunger_apply_consequences and current > hunger_critical_threshold:
		_remove_hunger_penalty()

func _check_hunger_reminders(current_value: float) -> void:
	var last_reminder = _reminder_cooldowns.get("hunger", 101.0)
	
	if current_value <= 60 and last_reminder > 60:
		EventBus.emit_notification("Getting hungry", "info", 3.0)
		_reminder_cooldowns["hunger"] = current_value
	elif current_value <= 40 and last_reminder > 40:
		EventBus.emit_notification("Really need to eat soon", "warning", 3.0)
		_reminder_cooldowns["hunger"] = current_value
	elif current_value <= 20 and last_reminder > 20:
		EventBus.emit_notification("STARVING! Find food now!", "danger", 4.0)
		emit_signal("need_critical", "hunger", current_value)
		_reminder_cooldowns["hunger"] = current_value

func _apply_hunger_penalty() -> void:
	if active_consequences.has("hunger_speed"):
		return
	
	var player = get_tree().get_first_node_in_group("player")
	if player and "walk_speed" in player:
		player.set_meta("original_walk_speed", player.walk_speed)
		player.set_meta("original_run_speed", player.run_speed)
		player.walk_speed *= hunger_speed_penalty
		player.run_speed *= hunger_speed_penalty
		active_consequences["hunger_speed"] = true
		
		if debug_mode:
			print("[NeedsSystem] Applied hunger speed penalty")
		EventBus.emit_notification("Too hungry to run properly", "warning", 3.0)

func _remove_hunger_penalty() -> void:
	if not active_consequences.has("hunger_speed"):
		return
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_meta("original_walk_speed"):
		player.walk_speed = player.get_meta("original_walk_speed")
		player.run_speed = player.get_meta("original_run_speed")
		active_consequences.erase("hunger_speed")
		
		if debug_mode:
			print("[NeedsSystem] Removed hunger speed penalty")

func eat_food(amount: float = -1.0) -> void:
	"""Call this when player eats food"""
	if not hunger_enabled:
		return
	
	var restore = amount if amount > 0 else hunger_food_restore
	var hunger_data = needs_data.get("hunger", {})
	var current = hunger_data.get("current", 0.0)
	
	current = min(current + restore, hunger_max)
	hunger_data["current"] = current
	
	EventBus.emit_notification("Hunger restored! (+%.0f)" % restore, "success", 2.0)
	emit_signal("need_changed", "hunger", current, hunger_max)
	emit_signal("need_satisfied", "hunger")
	
	# Reset reminder cooldown
	_reminder_cooldowns["hunger"] = 101.0

# ============ ENERGY SYSTEM ============
func _process_energy(delta_time: float) -> void:
	if not energy_enabled:
		return
	
	var energy_data = needs_data.get("energy", {})
	var current = energy_data.get("current", energy_max)
	
	# Decay energy
	var decay_per_second = energy_decay_per_hour / 3600.0
	current -= decay_per_second * delta_time
	current = clamp(current, 0.0, energy_max)
	
	energy_data["current"] = current
	emit_signal("need_changed", "energy", current, energy_max)
	
	# Check for reminders
	if show_energy_reminders and current <= 30:
		if not _reminder_cooldowns.has("energy_30"):
			EventBus.emit_notification("Getting tired, need sleep or coffee", "warning", 3.0)
			_reminder_cooldowns["energy_30"] = true
	
	# Force sleep if energy hits 0
	if energy_apply_consequences and current <= 0:
		force_sleep()

func drink_coffee() -> void:
	"""Call when player drinks coffee"""
	if not energy_enabled:
		return
	
	var energy_data = needs_data.get("energy", {})
	var current = energy_data.get("current", 0.0)
	current = min(current + energy_coffee_restore, energy_max)
	energy_data["current"] = current
	
	EventBus.emit_notification("Energy boosted! (+%.0f)" % energy_coffee_restore, "success", 2.0)
	emit_signal("need_changed", "energy", current, energy_max)

func force_sleep() -> void:
	"""Force player to sleep and restore energy"""
	if typeof(Game) != TYPE_NIL and Game.has_method("sleep_to_morning"):
		Game.sleep_to_morning()
	
	if energy_enabled:
		var energy_data = needs_data.get("energy", {})
		energy_data["current"] = energy_sleep_restore
		emit_signal("need_changed", "energy", energy_sleep_restore, energy_max)
		EventBus.emit_notification("You got some rest. Energy restored!", "success", 3.0)

# ============ RENT SYSTEM ============
func _check_rent() -> void:
	if not rent_enabled or typeof(Game) == TYPE_NIL:
		return
	
	var current_day = int(Game.day)
	var days_until = _next_rent_day - current_day
	
	# Show reminders
	if show_rent_reminders and days_until in rent_reminder_days:
		var reminder = "Rent due "
		match days_until:
			0: reminder = "RENT DUE TODAY! ($%.0f)" % rent_amount
			1: reminder = "Rent due tomorrow ($%.0f)" % rent_amount
			_: reminder = "Rent due in %d days ($%.0f)" % [days_until, rent_amount]
		
		EventBus.emit_notification(reminder, "warning" if days_until > 0 else "danger", 5.0)
		emit_signal("need_reminder", "rent", reminder)
	
	# Process payment on due date
	if current_day >= _next_rent_day and rent_auto_pay_from_bank:
		_process_rent_payment()

func _process_rent_payment() -> void:
	var success = false
	
	# Try to pay from bank
	if typeof(BankService) != TYPE_NIL:
		if BankService.can_afford(rent_amount):
			success = BankService.purchase("Rent Payment", rent_amount)
	
	if success:
		# Payment successful
		_next_rent_day += rent_interval_days
		_payment_strikes["rent"] = 0
		
		EventBus.emit_notification("Rent paid: $%.0f" % rent_amount, "success", 3.0)
		emit_signal("need_satisfied", "rent")
		
		if debug_mode:
			print("[NeedsSystem] Rent paid successfully. Next due: Day ", _next_rent_day)
	else:
		# Payment failed
		var strikes = _payment_strikes.get("rent", 0) + 1
		_payment_strikes["rent"] = strikes
		
		EventBus.emit_notification("FAILED TO PAY RENT! Strike %d/3" % strikes, "danger", 5.0)
		
		if rent_apply_consequences:
			_apply_rent_consequence(strikes)

func _apply_rent_consequence(strikes: int) -> void:
	match strikes:
		1:
			EventBus.emit_dialogue("Landlord", 
				"You missed rent! Pay within %d days or face eviction!" % rent_grace_period_days, 
				5.0)
		2:
			EventBus.emit_dialogue("Landlord", 
				"Second missed payment! Your apartment is locked for today!", 
				5.0)
			# Could lock apartment here
		3:
			EventBus.emit_dialogue("GAME OVER", 
				"You've been evicted! Better luck next time.", 
				0.0)
			# Could trigger game over

func pay_rent_manually() -> bool:
	"""Allow manual rent payment if enabled"""
	if not rent_allow_manual_payment or not rent_enabled:
		return false
	
	if typeof(BankService) != TYPE_NIL:
		if BankService.can_afford(rent_amount):
			if BankService.purchase("Early Rent Payment", rent_amount):
				_next_rent_day = int(Game.day) + rent_interval_days
				EventBus.emit_notification("Rent paid early!", "success", 3.0)
				return true
	
	return false

# ============ EVENT HANDLERS ============
func _on_day_advanced(_day: int) -> void:
	# Check rent
	if rent_enabled:
		_check_rent()
	
	# Reset daily reminder cooldowns
	_reminder_cooldowns.clear()

# ============ PUBLIC API ============
func get_need_value(need_id: String) -> float:
	"""Get current value of a need"""
	var need = needs_data.get(need_id, {})
	return need.get("current", 0.0)

func get_need_percentage(need_id: String) -> float:
	"""Get need as percentage (0-100)"""
	var need = needs_data.get(need_id, {})
	var current = need.get("current", 0.0)
	var max_val = need.get("max", 100.0)
	return (current / max_val) * 100.0 if max_val > 0 else 0.0

func is_need_critical(need_id: String) -> bool:
	"""Check if need is at critical level"""
	match need_id:
		"hunger":
			return get_need_value("hunger") <= hunger_critical_threshold
		"energy":
			return get_need_value("energy") <= energy_critical_threshold
		_:
			return false

func get_days_until_rent() -> int:
	"""Get days until next rent payment"""
	if not rent_enabled or typeof(Game) == TYPE_NIL:
		return -1
	return _next_rent_day - int(Game.day)

func set_system_enabled(enabled: bool) -> void:
	"""Enable/disable entire system at runtime"""
	system_enabled = enabled
	set_process(enabled)
	if enabled:
		_initialize_needs()
