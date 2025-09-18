extends CharacterBody3D

signal insider_info_given(ticker: StringName)

const DRUNK_COMPONENT_SCRIPT := preload("res://scripts/components/InsiderDrunkComponent.gd")
const InsiderClasses := preload("res://scripts/globals/trading/InsiderClasses.gd")
const FLOOR_SNAP_UP: float = 2.5
const FLOOR_SNAP_DOWN: float = 6.0
const FLOOR_OFFSET_DEFAULT: float = 0.9
const DEFAULT_DIALOGUE_TIP_REFUSAL := "Not yet. Come back later."
const DEFAULT_DIALOGUE_LOCKED_OUT_PASSED := "They're out cold. Try again tomorrow."
const DEFAULT_DIALOGUE_LOCKED_OUT := "Come back tomorrow."
const DEFAULT_DIALOGUE_LOCKED_OUT_GIVE := "No more drinks tonight."

@export var npc_id: StringName = &"exec_assistant"
@export var insider_class: StringName = &"exec_assistant"
@export var company_name: String = "ACME"
@export var company_ticker: StringName = &"ACME"
@export var display_name: String = ""
@export var tip_tickers: Array[StringName] = []
@export var look_target: NodePath
@export var face_target_on_ready: bool = true
@export var auto_snap_to_floor: bool = false
@export var use_gravity: bool = true
@export var show_debug_label: bool = false
@export var debug_logging: bool = true

@export_group("Interaction")
@export var interaction_prompt: String = "What do you need?"
@export var response_duration: float = 4.0
@export var option_text_give_beer: String = "Give drink"
@export var option_text_request_tip: String = "Ask for trading tip"
@export var option_text_nevermind: String = "Never mind"
@export var dialogue_need_beer: String = "You don't even have a drink."
@export var dialogue_tip_refusal: String = DEFAULT_DIALOGUE_TIP_REFUSAL
@export var dialogue_pass_out: String = "They slump over the bar, completely out."
@export var dialogue_passed_out_tip: String = "(They're out cold.)"
@export var dialogue_passed_out_give: String = "Can't drink anymore..."

@export_group("Dialogue")
@export var sober_dialogue_options: Array[String] = [
	"Long day. Bring me something strong if you want to chat.",
	"Numbers are easier to talk about after a drink.",
	"Come back when you've got a beer in hand."
]
@export var post_tip_dialogue: String = "Keep your voice down, but watch %s tomorrow."
@export var ready_for_tip_dialogue: String = "Alright, alright... you've loosened me up."
@export var dialogue_locked_out: String = DEFAULT_DIALOGUE_LOCKED_OUT
@export var dialogue_locked_out_give: String = DEFAULT_DIALOGUE_LOCKED_OUT_GIVE
@export var dialogue_locked_out_passed_out: String = DEFAULT_DIALOGUE_LOCKED_OUT_PASSED

var _drunk: InsiderDrunkComponent = null
var _label: Label3D = null
var _interaction_area: Area3D = null
var _ready_hint_shown: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _class_config: Dictionary = {}
var _confidence: float = 0.5
var _awaiting_choice: bool = false
var _active_options: Array = []
var _prompt_timer: Timer = null
var _locked_until_next_day: bool = false
var _lockout_reason: String = ""
var _player_contact_count: int = 0

func _ready() -> void:
	add_to_group("npc")
	add_to_group("insider_npc")

	var class_lower := String(insider_class).to_lower()
	var class_group := "%s_npc" % class_lower
	if not is_in_group(class_group):
		add_to_group(class_group)
	if class_lower in ["ceo", "exec_assistant", "accountant", "journalist", "trading_bro"]:
		add_to_group("ceo_npc")

	_apply_class_config()

	_label = get_node_or_null("StateLabel") as Label3D
	if _label:
		_label.visible = show_debug_label
		_update_state_label()

	_interaction_area = get_node_or_null("InteractionArea") as Area3D
	if _interaction_area:
		_interaction_area.monitoring = true
		_interaction_area.monitorable = true
		if _interaction_area.collision_mask == 0:
			_interaction_area.collision_mask = 1
		if not _interaction_area.body_entered.is_connected(_on_interaction_body_entered):
			_interaction_area.body_entered.connect(_on_interaction_body_entered)
		if not _interaction_area.body_exited.is_connected(_on_interaction_body_exited):
			_interaction_area.body_exited.connect(_on_interaction_body_exited)

	_drunk = _ensure_drunk_component()
	if _drunk:
		if tip_tickers.is_empty():
			tip_tickers.append(company_ticker)
		var ticker_strings: Array[String] = []
		for t in tip_tickers:
			ticker_strings.append(String(t))
		_class_config["debug_logging"] = debug_logging
		_drunk.setup(display_name, ticker_strings, _class_config)
		_confidence = _drunk.confidence
		if not _drunk.drunk_level_changed.is_connected(_on_drunk_level_changed):
			_drunk.drunk_level_changed.connect(_on_drunk_level_changed)
		if not _drunk.tip_given.is_connected(_on_tip_given):
			_drunk.tip_given.connect(_on_tip_given)
		if not _drunk.ready_for_tip.is_connected(_on_ready_for_tip):
			_drunk.ready_for_tip.connect(_on_ready_for_tip)

	if face_target_on_ready:
		call_deferred("_face_target")

	if auto_snap_to_floor:
		call_deferred("_snap_to_floor")

	if typeof(EventBus) != TYPE_NIL:
		var dialogue_cb := Callable(self, "_on_dialogue_choice")
		if not EventBus.dialogue_completed.is_connected(dialogue_cb):
			EventBus.dialogue_completed.connect(dialogue_cb)
		var day_cb := Callable(self, "_on_day_advanced")
		if not EventBus.day_advanced.is_connected(day_cb):
			EventBus.day_advanced.connect(day_cb)

	set_physics_process(use_gravity)

func _exit_tree() -> void:
	_cancel_prompt_timer()
	if typeof(EventBus) != TYPE_NIL:
		var dialogue_cb := Callable(self, "_on_dialogue_choice")
		if EventBus.dialogue_completed.is_connected(dialogue_cb):
			EventBus.dialogue_completed.disconnect(dialogue_cb)
		var day_cb := Callable(self, "_on_day_advanced")
		if EventBus.day_advanced.is_connected(day_cb):
			EventBus.day_advanced.disconnect(day_cb)
	if _interaction_area and is_instance_valid(_interaction_area):
		if _interaction_area.body_entered.is_connected(_on_interaction_body_entered):
			_interaction_area.body_entered.disconnect(_on_interaction_body_entered)
		if _interaction_area.body_exited.is_connected(_on_interaction_body_exited):
			_interaction_area.body_exited.disconnect(_on_interaction_body_exited)
	if _drunk and is_instance_valid(_drunk):
		if _drunk.tip_given.is_connected(_on_tip_given):
			_drunk.tip_given.disconnect(_on_tip_given)
		if _drunk.ready_for_tip.is_connected(_on_ready_for_tip):
			_drunk.ready_for_tip.disconnect(_on_ready_for_tip)
		if _drunk.drunk_level_changed.is_connected(_on_drunk_level_changed):
			_drunk.drunk_level_changed.disconnect(_on_drunk_level_changed)

func show_interaction_menu() -> void:
	_open_interaction_menu()

func interact() -> Dictionary:
	_open_interaction_menu()
	return {
		"success": true,
		"message": interaction_prompt,
		"confidence": _confidence
	}

func give_beer() -> Dictionary:
	return _handle_choice_give_beer(true)

func set_debug_label_visible(visible: bool) -> void:
	show_debug_label = visible
	if _label:
		_label.visible = visible
		_update_state_label()

func set_use_gravity(enabled: bool) -> void:
	use_gravity = enabled
	set_physics_process(enabled)
	if not enabled:
		velocity = Vector3.ZERO

func get_confidence() -> float:
	return _confidence

func _physics_process(delta: float) -> void:
	if not use_gravity:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()

func _open_interaction_menu(prompt_override: String = "") -> void:
	if _locked_until_next_day:
		_awaiting_choice = false
		_cancel_prompt_timer()
		var locked_message := dialogue_locked_out
		if _lockout_reason == "passed_out":
			locked_message = dialogue_locked_out_passed_out
		_show_response(locked_message, false)
		return

	if _active_options.is_empty():
		_active_options = [
			{"id": "give_beer", "text": option_text_give_beer},
			{"id": "ask_tip", "text": option_text_request_tip}
		]
		if option_text_nevermind.strip_edges() != "":
			_active_options.append({"id": "cancel", "text": option_text_nevermind})
	_awaiting_choice = true
	_cancel_prompt_timer()
	var prompt = interaction_prompt
	if prompt_override.strip_edges() != "":
		prompt = prompt_override
	_emit_menu(prompt)

func _emit_menu(prompt_text: String) -> void:
	if typeof(EventBus) == TYPE_NIL:
		return
	EventBus.emit_signal("dialogue_requested", display_name, prompt_text, 0.0, _active_options)

func _cancel_prompt_timer() -> void:
	if _prompt_timer and is_instance_valid(_prompt_timer):
		_prompt_timer.queue_free()
	_prompt_timer = null

func _schedule_prompt_reset() -> void:
	if response_duration <= 0.0:
		return
	_cancel_prompt_timer()
	_prompt_timer = Timer.new()
	_prompt_timer.wait_time = max(response_duration, 1.0)
	_prompt_timer.one_shot = true
	_prompt_timer.timeout.connect(func():
		_prompt_timer = null
		if _awaiting_choice:
			_emit_menu(interaction_prompt)
	)
	add_child(_prompt_timer)
	_prompt_timer.start()

func _show_response(text: String, auto_reset: bool = true) -> void:
	if text.strip_edges() == "":
		return
	if _awaiting_choice and not _active_options.is_empty():
		_emit_menu(text)
		if auto_reset:
			_schedule_prompt_reset()
		return
	var duration: float = 0.0
	if auto_reset:
		duration = max(response_duration, 0.0)
	if typeof(EventBus) != TYPE_NIL:
		EventBus.emit_dialogue(display_name, text, duration)

func _handle_choice_give_beer(from_direct_call: bool = false) -> Dictionary:
	var resume_menu := not from_direct_call
	if resume_menu:
		_cancel_prompt_timer()
	var result: Dictionary = {}
	if _locked_until_next_day:
		if resume_menu:
			_awaiting_choice = true
			var locked_message := dialogue_locked_out_give
			if _lockout_reason == "passed_out":
				locked_message = dialogue_passed_out_give
			_show_response(locked_message, false)
		return result
	if _drunk == null:
		if resume_menu:
			_awaiting_choice = true
			_show_response(dialogue_passed_out_tip, false)
		return result
	if _drunk.is_passed_out():
		_lock_out_for_day("passed_out")
		if resume_menu:
			_awaiting_choice = true
			_show_response(dialogue_passed_out_give, false)
		return result
	if typeof(Inventory) == TYPE_NIL:
		if typeof(EventBus) != TYPE_NIL:
			EventBus.emit_notification("Inventory system unavailable.", "danger", 3.0)
		if resume_menu:
			_awaiting_choice = true
			_show_response("Inventory system unavailable.", false)
		return result
	if not Inventory.has_beer():
		if typeof(EventBus) != TYPE_NIL:
			EventBus.emit_notification("You need a beer in your inventory.", "warning", 3.0)
		if resume_menu:
			_awaiting_choice = true
			_show_response(dialogue_need_beer, false)
		return result
	if not _drunk.can_accept_beer():
		_lock_out_for_day("too_drunk")
		if resume_menu:
			_awaiting_choice = true
			_show_response(dialogue_passed_out_give, false)
		return result
	if not Inventory.give_beer():
		if typeof(EventBus) != TYPE_NIL:
			EventBus.emit_notification("Failed to give beer.", "danger", 3.0)
		if resume_menu:
			_awaiting_choice = true
			_show_response("Could not hand over the drink.", false)
		return result

	if typeof(EventBus) != TYPE_NIL:
		EventBus.emit_signal("beer_given_to_npc", String(npc_id))
	result = _drunk.give_beer()
	_confidence = _drunk.confidence
	var message := String(result.get("message", ""))
	var passed_out := bool(result.get("pass_out", false))

	if resume_menu:
		_awaiting_choice = true
		if passed_out:
			_show_response(dialogue_pass_out, false)
			_lock_out_for_day("passed_out")
		else:
			_show_response(message, true)
	else:
		_show_response(message, true)

	return result

func _handle_choice_ask_tip() -> void:
	_cancel_prompt_timer()
	if _locked_until_next_day:
		_awaiting_choice = true
		var locked_message := dialogue_locked_out
		if _lockout_reason == "passed_out":
			locked_message = dialogue_locked_out_passed_out
		_show_response(locked_message, false)
		return
	if _drunk == null:
		_awaiting_choice = true
		_show_response(dialogue_passed_out_tip, false)
		return
	if _drunk.is_passed_out():
		_awaiting_choice = true
		_show_response(dialogue_passed_out_tip, false)
		_lock_out_for_day("passed_out")
		return
	if not _drunk.is_drunk_enough():
		var refuse_msg := dialogue_tip_refusal
		_awaiting_choice = true
		_show_response(refuse_msg, false)
		_lock_out_for_day("not_ready")
		return

	var tip_result: Dictionary = _drunk.give_insider_tip()
	_confidence = _drunk.confidence
	_awaiting_choice = true
	var base_message := String(tip_result.get("message", ""))
	_show_response(base_message, true)

func _cancel_interaction() -> void:
	_cancel_prompt_timer()
	_awaiting_choice = false
	_active_options.clear()
	if typeof(EventBus) != TYPE_NIL:
		EventBus.emit_signal("dialogue_requested", "", "", 0.0, [])

func _on_dialogue_choice(choice_index: int) -> void:
	if not _awaiting_choice:
		return
	var action_id := "cancel"
	if choice_index >= 0 and choice_index < _active_options.size():
		var opt: Dictionary = _active_options[choice_index]
		action_id = String(opt.get("id", "cancel"))
	_awaiting_choice = false
	call_deferred("_process_choice", action_id)

func _process_choice(action_id: String) -> void:
	match action_id:
		"give_beer":
			_handle_choice_give_beer()
		"ask_tip":
			_handle_choice_ask_tip()
		"cancel":
			_cancel_interaction()

func _on_interaction_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_contact_count += 1

func _on_interaction_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_contact_count = max(0, _player_contact_count - 1)
		if _player_contact_count == 0:
			_cancel_interaction()

func _apply_class_config() -> void:
	_class_config = InsiderClasses.get_config(insider_class)
	_confidence = float(_class_config.get("confidence", _confidence))

	if _class_config.has("interaction_prompt") and interaction_prompt == "What do you need?":
		interaction_prompt = String(_class_config["interaction_prompt"])
	if _class_config.has("dialogue_need_beer") and dialogue_need_beer == "You don't even have a drink.":
		dialogue_need_beer = String(_class_config["dialogue_need_beer"])
	if _class_config.has("dialogue_tip_refusal") and dialogue_tip_refusal == DEFAULT_DIALOGUE_TIP_REFUSAL:
		dialogue_tip_refusal = String(_class_config["dialogue_tip_refusal"])
	if _class_config.has("dialogue_pass_out") and dialogue_pass_out == "They slump over the bar, completely out.":
		dialogue_pass_out = String(_class_config["dialogue_pass_out"])
	if _class_config.has("dialogue_passed_out_tip") and dialogue_passed_out_tip == "(They're out cold.)":
		dialogue_passed_out_tip = String(_class_config["dialogue_passed_out_tip"])
	if _class_config.has("dialogue_passed_out_give") and dialogue_passed_out_give == "Can't drink anymore...":
		dialogue_passed_out_give = String(_class_config["dialogue_passed_out_give"])

	if display_name.is_empty():
		var class_title := String(_class_config.get("display_name", "Insider"))
		if company_name.is_empty():
			display_name = class_title
		else:
			display_name = "%s %s" % [company_name, class_title]

	if String(npc_id).is_empty():
		npc_id = StringName("%s_%s" % [company_name.to_lower().replace(" ", "_"), String(insider_class).to_lower()])

	if _label:
		_update_state_label()

func _ensure_drunk_component() -> InsiderDrunkComponent:
	var component := get_node_or_null("InsiderDrunkComponent") as InsiderDrunkComponent
	if component == null:
		component = DRUNK_COMPONENT_SCRIPT.new()
		component.name = "InsiderDrunkComponent"
		add_child(component)
	return component

func _on_drunk_level_changed(level: int, max_level: int) -> void:
	if _drunk == null:
		return
	_confidence = _drunk.confidence
	if level < _drunk.drunk_threshold:
		_ready_hint_shown = false
	if show_debug_label:
		_update_state_label("Drunk %d/%d" % [level, max_level])

func _on_ready_for_tip() -> void:
	if _drunk == null or _drunk.is_passed_out():
		return
	if _locked_until_next_day or _ready_hint_shown:
		return
	_ready_hint_shown = true
	var message := ready_for_tip_dialogue
	if message.strip_edges() != "":
		_show_response(message, true)
	if typeof(EventBus) != TYPE_NIL:
		EventBus.emit_notification("%s looks ready to talk." % display_name, "info", 2.5)
	if show_debug_label:
		_update_state_label("Ready for tip")

func _on_tip_given(ticker: String) -> void:
	var ticker_name := StringName(ticker)
	_ready_hint_shown = false
	if _drunk:
		_confidence = _drunk.confidence
	var message := post_tip_dialogue
	if message.find("%") != -1:
		message = message % ticker
	_show_response(message, true)
	insider_info_given.emit(ticker_name)
	if typeof(EventBus) != TYPE_NIL:
		EventBus.emit_signal("insider_tip_given", ticker_name, String(npc_id))
		EventBus.emit_notification("%s tips: watch %s" % [display_name, ticker], "warning", 4.0)
	if show_debug_label:
		_update_state_label("Tip shared")

func _lock_out_for_day(reason: String = "") -> void:
	if _locked_until_next_day:
		return
	_locked_until_next_day = true
	_lockout_reason = reason
	_ready_hint_shown = false
	_cancel_prompt_timer()
	if typeof(EventBus) != TYPE_NIL:
		var note := "%s is done for tonight." % display_name
		if reason == "passed_out":
			note = "%s passed out and won't talk tonight." % display_name
		elif reason == "not_ready":
			note = "%s shuts you down for the night." % display_name
		EventBus.emit_notification(note, "info", 3.0)
	if show_debug_label:
		_update_state_label("Done for tonight")

func _on_day_advanced(_day: int) -> void:
	_locked_until_next_day = false
	_lockout_reason = ""
	_ready_hint_shown = false
	if show_debug_label:
		_update_state_label()

func _update_state_label(extra: String = "") -> void:
	if _label == null:
		return
	var base := display_name
	if base.strip_edges() == "":
		base = String(npc_id)
	var suffix := extra.strip_edges()
	if _locked_until_next_day:
		if suffix == "":
			suffix = "Done for tonight"
		else:
			suffix = "%s\nDone for tonight" % suffix
	if not show_debug_label:
		_label.text = base
		return
	if suffix != "":
		_label.text = "%s\n%s" % [base, suffix]
	else:
		_label.text = base

func _face_target() -> void:
	if look_target.is_empty():
		return
	var target_node := get_node_or_null(look_target) as Node3D
	if target_node == null:
		return
	var target_pos := target_node.global_position
	var current_pos := global_position
	target_pos.y = current_pos.y
	if current_pos.distance_to(target_pos) <= 0.05:
		return
	look_at(target_pos, Vector3.UP)

func _snap_to_floor() -> void:
	var ray := get_node_or_null("RayCast3D") as RayCast3D
	if ray:
		var prev_enabled := ray.enabled
		ray.enabled = true
		ray.force_raycast_update()
		if ray.is_colliding():
			var hit_position := ray.get_collision_point()
			global_position = hit_position + Vector3.UP * FLOOR_OFFSET_DEFAULT
			velocity = Vector3.ZERO
		ray.enabled = prev_enabled
		return
	var world := get_world_3d()
	if world == null:
		return
	var space_state := world.direct_space_state
	if space_state == null:
		return
	var from := global_position + Vector3.UP * FLOOR_SNAP_UP
	var to := global_position - Vector3.UP * FLOOR_SNAP_DOWN
	var params := PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = to
	params.exclude = [get_rid()]
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var result := space_state.intersect_ray(params)
	if result.has("position"):
		global_position = result["position"] + Vector3.UP * FLOOR_OFFSET_DEFAULT
		velocity = Vector3.ZERO
