# DialogueUI.gd
# Save as Autoload (Project Settings > Autoload > Add this script as "DialogueUI")
extends CanvasLayer

var dialogue_scene: PackedScene = preload("res://scenes/globals/UI/dialogue_box.tscn")
var notification_scene: PackedScene = preload("res://scenes/globals/UI/notification.tscn")

var current_dialogue: Control = null
var notification_queue: Array[Control] = []
var max_notifications: int = 3

func _ready() -> void:
	layer = 10  # Always on top
	process_mode = Node.PROCESS_MODE_ALWAYS

# ============ DIALOGUE SYSTEM ============
func show_dialogue(speaker: String, text: String, duration: float = 0.0) -> void:
	"""Show dialogue box with speaker name. Duration 0 = manual dismiss"""
	if current_dialogue:
		current_dialogue.queue_free()
	
	current_dialogue = dialogue_scene.instantiate()
	add_child(current_dialogue)
	
	var speaker_label: Label = current_dialogue.get_node("Panel/VBox/SpeakerName")
	var text_label: RichTextLabel = current_dialogue.get_node("Panel/VBox/DialogueText")
	
	if speaker_label:
		speaker_label.text = speaker
	if text_label:
		text_label.text = text
	
	if duration > 0:
		# Create timer without await
		var timer := Timer.new()
		timer.wait_time = duration
		timer.one_shot = true
		timer.timeout.connect(_on_dialogue_timeout)
		add_child(timer)
		timer.start()

func _on_dialogue_timeout() -> void:
	hide_dialogue()

func hide_dialogue() -> void:
	"""Hide current dialogue"""
	if current_dialogue:
		var tween = create_tween()
		tween.tween_property(current_dialogue, "modulate:a", 0.0, 0.3)
		tween.tween_callback(current_dialogue.queue_free)
		current_dialogue = null

func show_choices(speaker: String, text: String, choices: Array[String]) -> int:
	"""Show dialogue with choices, returns index of selected choice"""
	# TODO: Implementation for choice-based dialogue
	show_dialogue(speaker, text)
	# This is a placeholder for future choice system
	# For now, just return 0
	return 0

# ============ NOTIFICATION SYSTEM ============
func notify(text: String, type: String = "info", duration: float = 5.0) -> void:
	if notification_scene == null:
		print("[Notification]: ", text)
		return

	var notif = notification_scene.instantiate()
	add_child(notif)

	var label = notif.get_node_or_null("Panel/Label")
	var panel = notif.get_node_or_null("Panel")

	# text
	if label and label is Label:
		(label as Label).text = text

	# bg color (unchanged logic)
	if panel and panel is Panel:
		var color = Color(0.2, 0.2, 0.2, 0.9)
		match type:
			"success": color = Color(0.2, 0.8, 0.2, 0.9)
			"warning": color = Color(0.8, 0.6, 0.2, 0.9)
			"danger":  color = Color(0.8, 0.2, 0.2, 0.9)
			_: pass
		(panel as Panel).self_modulate = color

	# ensure no inherited tint
	notif.modulate = Color(1, 1, 1, 1)

	# force white after theme/_ready
	call_deferred("_force_notif_label_white", notif)

	# stack & fade (unchanged)
	notif.modulate.a = 1.0
	notification_queue.append(notif)
	_arrange_notifications()
	var t = get_tree().create_tween()
	t.tween_interval(duration)
	t.tween_property(notif, "modulate:a", 0.0, 0.5)
	t.tween_callback(Callable(self, "_remove_notification").bind(notif))


func _force_notif_label_white(notif: Node) -> void:
	var lbl = notif.get_node_or_null("Panel/Label")
	if lbl and lbl is Label:
		lbl.modulate = Color(1, 1, 1, 1)  # clear any tint
		lbl.add_theme_color_override("font_color", Color.WHITE)


func _force_notif_text_white(root: Node) -> void:
	# Ensure all Labels (and RichTextLabels) render white, even if a Theme tries to override
	if root is Label:
		root.add_theme_color_override("font_color", Color.WHITE)
	elif root is RichTextLabel:
		root.add_theme_color_override("default_color", Color.WHITE)
	for child in root.get_children():
		_force_notif_text_white(child)

func _remove_notification(notif: Control) -> void:
	notification_queue.erase(notif)
	if is_instance_valid(notif):
		notif.queue_free()
	_arrange_notifications()

func _arrange_notifications() -> void:
	"""Stack notifications vertically"""
	var y_offset: float = 100
	for i in range(notification_queue.size()):
		var notif = notification_queue[i]
		if notif:
			var target_y = y_offset + (i * 80)
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(notif, "position:y", target_y, 0.3)

# ============ SEQUENCE HELPERS ============
func show_dialogue_sequence(messages: Array, delay_between: float = 2.5) -> void:
	"""Show a sequence of dialogue messages"""
	if messages.is_empty():
		return
	
	var current_index := 0
	_show_next_in_sequence(messages, current_index, delay_between)

func _show_next_in_sequence(messages: Array, index: int, delay: float) -> void:
	if index >= messages.size():
		return
	
	var msg = messages[index]
	if msg is Dictionary:
		show_npc_dialogue(msg.get("speaker", ""), msg.get("text", ""))
	elif msg is String:
		show_npc_dialogue("", msg)
	
	if index < messages.size() - 1:
		var timer := Timer.new()
		timer.wait_time = delay
		timer.one_shot = true
		timer.timeout.connect(func(): _show_next_in_sequence(messages, index + 1, delay))
		add_child(timer)
		timer.start()

# ============ QUICK HELPERS ============
func show_npc_dialogue(npc_name: String, text: String) -> void:
	"""Convenience for NPC dialogue"""
	show_dialogue(npc_name, text, 4.0)

func show_insider_tip(ticker: String) -> void:
	"""Special notification for insider tips"""
	notify("🔥 INSIDER TIP: " + ticker + " will move tomorrow!", "warning", 5.0)

func show_trade_result(success: bool, message: String) -> void:
	"""Show trade success/failure"""
	notify(message, "success" if success else "danger", 3.0)

# ============ INPUT HANDLING ============
func _input(event: InputEvent) -> void:
	# Dismiss dialogue on click/enter
	if current_dialogue and event.is_action_pressed("ui_accept"):
		hide_dialogue()
		get_viewport().set_input_as_handled()
