extends CanvasLayer

var dialogue_scene: PackedScene = preload("res://scenes/globals/UI/dialogue_box.tscn")
var notification_scene: PackedScene = preload("res://scenes/globals/UI/notification.tscn")

var current_dialogue: Control = null
var notification_queue: Array[Control] = []
var max_notifications: int = 3

var _pending_choices: Array = []
var _choice_buttons: Array[Button] = []

@export var enable_choice_hotkeys: bool = false

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	if typeof(EventBus) != TYPE_NIL:
		EventBus.notification_requested.connect(_on_notification_requested)
		EventBus.dialogue_requested.connect(_on_dialogue_requested)

func _on_notification_requested(text: String, type: String, duration: float) -> void:
	notify(text, type, duration)

func _on_dialogue_requested(speaker: String, text: String, duration: float, options: Array) -> void:
	if options.is_empty():
		show_dialogue(speaker, text, duration)
	else:
		show_choices(speaker, text, options)

func show_dialogue(speaker: String, text: String, duration: float = 0.0) -> void:
	if current_dialogue:
		current_dialogue.queue_free()

	current_dialogue = dialogue_scene.instantiate()
	add_child(current_dialogue)

	_pending_choices.clear()
	_choice_buttons.clear()

	var speaker_label: Label = current_dialogue.get_node("Panel/VBox/SpeakerName")
	var text_label: RichTextLabel = current_dialogue.get_node("Panel/VBox/DialogueText")
	var vbox: VBoxContainer = current_dialogue.get_node("Panel/VBox")
	var existing_choice := vbox.get_node_or_null("ChoiceContainer")
	if existing_choice:
		existing_choice.queue_free()

	if speaker_label:
		speaker_label.text = speaker
	if text_label:
		text_label.text = text

	if duration > 0.0:
		var timer := Timer.new()
		timer.wait_time = duration
		timer.one_shot = true
		timer.timeout.connect(_on_dialogue_timeout)
		add_child(timer)
		timer.start()

func _on_dialogue_timeout() -> void:
	hide_dialogue()

func hide_dialogue() -> void:
	_pending_choices.clear()
	_choice_buttons.clear()
	if current_dialogue:
		var tween := create_tween()
		tween.tween_property(current_dialogue, "modulate:a", 0.0, 0.3)
		tween.tween_callback(current_dialogue.queue_free)
		current_dialogue = null

func show_choices(speaker: String, text: String, options: Array) -> void:
	show_dialogue(speaker, text, 0.0)
	_pending_choices = options.duplicate(true)
	_choice_buttons.clear()
	if current_dialogue == null:
		return

	var vbox: VBoxContainer = current_dialogue.get_node("Panel/VBox")
	var choice_container := VBoxContainer.new()
	choice_container.name = "ChoiceContainer"
	choice_container.add_theme_constant_override("separation", 8)
	vbox.add_child(choice_container)

	for i in range(options.size()):
		var entry: Variant = options[i]
		var label: String = "Option %d" % (i + 1)
		if entry is Dictionary:
			label = String(entry.get("text", label))
		else:
			label = String(entry)
		var button: Button = Button.new()
		button.text = "%d) %s" % [i + 1, label]
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(Callable(self, "_on_choice_selected").bind(i))
		choice_container.add_child(button)
		_choice_buttons.append(button)

	call_deferred("_focus_choice_button", 0)

func _focus_choice_button(index: int) -> void:
	if index >= 0 and index < _choice_buttons.size():
		var btn := _choice_buttons[index]
		if is_instance_valid(btn):
			btn.grab_focus()

func notify(text: String, type: String = "info", duration: float = 5.0) -> void:
	if notification_scene == null:
		print("[Notification]", text)
		return

	var notif := notification_scene.instantiate()
	add_child(notif)

	var label := notif.get_node_or_null("Panel/Label")
	var panel := notif.get_node_or_null("Panel")

	if label:
		label.text = text

	if panel:
		var color := Color(0.2, 0.2, 0.2, 0.9)
		match type:
			"success": color = Color(0.2, 0.8, 0.2, 0.9)
			"warning": color = Color(0.8, 0.6, 0.2, 0.9)
			"danger": color = Color(0.8, 0.2, 0.2, 0.9)
		(panel as Panel).self_modulate = color

	notif.modulate = Color(1, 1, 1, 1)
	call_deferred("_force_notif_label_white", notif)

	notification_queue.append(notif)
	_arrange_notifications()
	var tween := get_tree().create_tween()
	tween.tween_interval(duration)
	tween.tween_property(notif, "modulate:a", 0.0, 0.5)
	tween.tween_callback(Callable(self, "_remove_notification").bind(notif))

func _remove_notification(notif: Control) -> void:
	notification_queue.erase(notif)
	if is_instance_valid(notif):
		notif.queue_free()
	_arrange_notifications()

func _arrange_notifications() -> void:
	var base_y := 100.0
	for i in range(notification_queue.size()):
		var notif := notification_queue[i]
		if notif:
			var target := base_y + float(i) * 80.0
			var tween := create_tween()
			tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(notif, "position:y", target, 0.3)

func _force_notif_label_white(notif: Node) -> void:
	var lbl := notif.get_node_or_null("Panel/Label")
	if lbl is Label:
		lbl.modulate = Color(1, 1, 1, 1)
		lbl.add_theme_color_override("font_color", Color.WHITE)

func _input(event: InputEvent) -> void:
	if enable_choice_hotkeys and current_dialogue and not _pending_choices.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			var idx := _choice_index_from_key(event)
			if idx >= 0 and idx < _pending_choices.size():
				_on_choice_selected(idx)
				get_viewport().set_input_as_handled()
				return
	if current_dialogue and _pending_choices.is_empty() and event.is_action_pressed("ui_accept"):
		hide_dialogue()
		get_viewport().set_input_as_handled()

func _choice_index_from_key(event: InputEventKey) -> int:
	match event.physical_keycode:
		KEY_1, KEY_KP_1: return 0
		KEY_2, KEY_KP_2: return 1
		KEY_3, KEY_KP_3: return 2
		KEY_4, KEY_KP_4: return 3
		KEY_5, KEY_KP_5: return 4
		_: return -1

func _on_choice_selected(index: int) -> void:
	EventBus.emit_signal("dialogue_completed", index)
	hide_dialogue()
