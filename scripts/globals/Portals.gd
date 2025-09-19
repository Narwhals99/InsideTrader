extends Area3D

@export_enum("hub","apartment","office","club","aptlobby","UpTownApartment","GroceryHood","RestaurantHood") var target_scene_key: String = "hub"
@export var target_spawn: String = ""    # Marker3D name in target scene

# Keep but set to "None" now that the clock drives phases (using it may desync the clock)
@export_enum("None","Morning","Market","Evening","LateNight") var phase_on_trigger: String = "None"
@export_enum("None","Morning","Market","Evening","LateNight") var required_phase: String = "None"

@export var min_net_worth: float = 0.0    # Set this on the Office entrance
@export var require_interact: bool = false
@export var one_shot: bool = false
@export var locked_hint: String = "Closed right now."

@export var requires_purchase: bool = false
@export var purchase_price: float = 0.0
@export var purchase_item_name: String = ""
@export var purchase_storage_key: String = ""
@export var purchase_prompt_text: String = ""
@export var insufficient_funds_message: String = ""

var _armed: bool = true
var _player_inside: bool = false
var _purchase_unlocked: bool = false
var _purchase_dialog_active: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if require_interact and not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event("interact", ev)
	if requires_purchase:
		_purchase_unlocked = _is_purchase_complete()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		if not require_interact:
			_trigger()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false

func _input(event: InputEvent) -> void:
	if require_interact and _player_inside and event.is_action_pressed("interact"):
		_trigger()

func _trigger() -> void:
	if not _armed:
		return

	if required_phase != "None" and typeof(Game) != TYPE_NIL and String(Game.phase) != required_phase:
		print("[Portal] locked:", name, " requires phase ", required_phase, " (now:", String(Game.phase), ") -> ", locked_hint)
		return

	if min_net_worth > 0.0:
		var nw: float = Portfolio.net_worth()
		if nw < min_net_worth:
			var shortfall: float = min_net_worth - nw
			print("[Portal] locked:", name, " requires NW >= $%.2f (now: $%.2f, short: $%.2f). %s" % [min_net_worth, nw, shortfall, locked_hint])
			return

	if requires_purchase and not _purchase_unlocked:
		_prompt_purchase()
		return

	_complete_travel()

func _complete_travel() -> void:
	_armed = not one_shot
	if phase_on_trigger != "None":
		print("[Portal] phase_on_trigger is deprecated with the clock. Leave it as 'None'.")
	Game.next_spawn = target_spawn
	Scenes.change_to(target_scene_key)

func _prompt_purchase() -> void:
	if _purchase_dialog_active:
		return
	if typeof(EventBus) == TYPE_NIL:
		print("[Portal] EventBus missing; cannot prompt for purchase on ", name)
		return
	_purchase_dialog_active = true
	if not EventBus.dialogue_completed.is_connected(_on_purchase_choice):
		EventBus.dialogue_completed.connect(_on_purchase_choice)
	var speaker: String = _get_purchase_item_name()
	var prompt: String = _get_purchase_prompt_text()
	var options: Array[Dictionary] = [
		{"text": _get_buy_option_text()},
		{"text": "Maybe later"}
	]
	EventBus.emit_dialogue(speaker, prompt, options)

func _on_purchase_choice(index: int) -> void:
	if not _purchase_dialog_active:
		return
	_purchase_dialog_active = false
	if EventBus.dialogue_completed.is_connected(_on_purchase_choice):
		EventBus.dialogue_completed.disconnect(_on_purchase_choice)
	if index != 0:
		return
	if _attempt_purchase():
		_complete_travel()

func _attempt_purchase() -> bool:
	if _purchase_unlocked:
		return true
	if purchase_price <= 0.0:
		_record_purchase_unlock()
		return true
	if typeof(BankService) == TYPE_NIL:
		print("[Portal] BankService missing; cannot process purchase for ", name)
		return false
	if not BankService.can_afford(purchase_price):
		_notify_insufficient_funds()
		return false
	var item: String = _get_purchase_item_name()
	if item.strip_edges() == "":
		item = name
	if not BankService.purchase(item, purchase_price):
		return false
	_record_purchase_unlock()
	return true

func _notify_insufficient_funds() -> void:
	var message: String = insufficient_funds_message
	if message.strip_edges() == "":
		message = "You don't have enough money to buy this apartment (%s)" % _format_price(purchase_price)
	if typeof(EventBus) != TYPE_NIL:
		EventBus.emit_notification(message, "danger", 3.0)
	else:
		print(message)

func _get_purchase_item_name() -> String:
	if purchase_item_name.strip_edges() != "":
		return purchase_item_name.strip_edges()
	if target_scene_key.strip_edges() != "":
		return target_scene_key
	return name

func _get_purchase_prompt_text() -> String:
	if purchase_prompt_text.strip_edges() != "":
		return purchase_prompt_text
	return "Purchase %s for %s?" % [_get_purchase_item_name(), _format_price(purchase_price)]

func _get_buy_option_text() -> String:
	if purchase_price <= 0.0:
		return "Unlock"
	return "Buy for %s" % _format_price(purchase_price)

func _get_purchase_key() -> String:
	if purchase_storage_key.strip_edges() != "":
		return purchase_storage_key.strip_edges()
	if target_scene_key.strip_edges() != "":
		return target_scene_key
	return name

func _record_purchase_unlock() -> void:
	_purchase_unlocked = true
	var key: String = _get_purchase_key()
	if key == "":
		return
	if typeof(Game) != TYPE_NIL and Game.has_method("unlock_portal_purchase"):
		Game.unlock_portal_purchase(key)

func _is_purchase_complete() -> bool:
	var key: String = _get_purchase_key()
	if key == "":
		return false
	if typeof(Game) != TYPE_NIL and Game.has_method("has_portal_purchase"):
		return Game.has_portal_purchase(key)
	return false

func _format_price(amount: float) -> String:
	var cents: int = roundi(amount * 100.0)
	var dollars: int = int(cents / 100)
	var remainder: int = abs(cents % 100)
	if remainder == 0:
		return "$" + _format_int_with_commas(dollars)
	return "$%s.%02d" % [_format_int_with_commas(dollars), remainder]

func _format_int_with_commas(value: int) -> String:
	var sign: String = ""
	var absolute: int = value
	if absolute < 0:
		sign = "-"
		absolute = -absolute
	var digits: String = str(absolute)
	var i: int = digits.length() - 3
	while i > 0:
		digits = digits.substr(0, i) + "," + digits.substr(i, digits.length() - i)
		i -= 3
	return sign + digits
