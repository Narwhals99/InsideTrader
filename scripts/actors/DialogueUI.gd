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
		await get_tree().create_timer(duration).timeout
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
func notify(text: String, type: String = "info", duration: float = 3.0) -> void:
	"""Show notification popup. Types: info, warning, success, danger"""
	# Check if notification scene exists
	if not notification_scene:
		print("[Notification]: ", text)  # Fallback to console
		return
	
	var notif = notification_scene.instantiate()
	add_child(notif)
	
	var label: Label = notif.get_node("Panel/Label")
	var panel: Panel = notif.get_node("Panel")
	
	if label:
		label.text = text
	
	# Set color based on type
	if panel:
		var color: Color
		match type:
			"success": color = Color(0.2, 0.8, 0.2, 0.9)
			"warning": color = Color(0.8, 0.6, 0.2, 0.9)
			"danger": color = Color(0.8, 0.2, 0.2, 0.9)
			_: color = Color(0.2, 0.2, 0.2, 0.9)
		
		panel.modulate = color
	
	# Position notification
	notification_queue.append(notif)
	_arrange_notifications()
	
	# Auto dismiss
	var tween = create_tween()
	tween.set_delay(duration)
	tween.tween_property(notif, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): _remove_notification(notif))

func _remove_notification(notif: Control) -> void:
	notification_queue.erase(notif)
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
