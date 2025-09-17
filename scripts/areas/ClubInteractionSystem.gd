extends Node

var bartender: Area3D
var insider: CharacterBody3D

func _ready() -> void:
	bartender = get_tree().get_first_node_in_group("bartender_npc") as Area3D
	insider = get_tree().get_first_node_in_group("ceo_npc") as CharacterBody3D

	if bartender != null and bartender.has_signal("beer_purchased"):
		bartender.beer_purchased.connect(_on_beer_purchased)

	if insider != null and insider.has_signal("insider_info_given"):
		insider.insider_info_given.connect(_on_insider_info_received)

	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)

	print("[ClubSystem] bartender=", bartender != null, " insider=", insider != null)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return

	var target := _find_insider(player)
	if target != null:
		if target.has_method("show_interaction_menu"):
			target.call("show_interaction_menu")
		elif target.has_method("interact"):
			target.call("interact")
		return

	var bar := _find_bartender(player)
	if bar != null and bar.has_method("interact"):
		bar.call("interact")

func _find_insider(player: Node3D) -> Node:
	var best: Node = null
	var best_dist := 3.0
	for node in get_tree().get_nodes_in_group("ceo_npc"):
		if node is Node3D:
			var actor := node as Node3D
			var area := actor.get_node_or_null("InteractionArea") as Area3D
			if area and area.get_overlapping_bodies().has(player):
				return actor
			var dist := player.global_position.distance_to(actor.global_position)
			if dist < best_dist:
				best_dist = dist
				best = actor
	return best

func _find_bartender(player: Node3D) -> Node:
	var best: Node = null
	var best_dist := 3.0
	for node in get_tree().get_nodes_in_group("bartender_npc"):
		if node is Node3D:
			var actor := node as Node3D
			var dist := player.global_position.distance_to(actor.global_position)
			if dist < best_dist:
				best = actor
	return best

func _on_beer_purchased() -> void:
	print("[Club] beer purchased")
	EventBus.emit_notification("You bought a beer!", "info", 2.0)

func _on_insider_info_received(ticker: StringName) -> void:
	print("[Club] tip signaled for", ticker)