# ClubInteractionSystem.gd — DROP-IN (no Variant inference warnings)
extends Node

var bartender: Area3D
var ceo: CharacterBody3D

func _ready() -> void:
	# Find NPCs present (for signals/diagnostics; targeting is resolved per press)
	bartender = get_tree().get_first_node_in_group("bartender_npc") as Area3D
	ceo = get_tree().get_first_node_in_group("ceo_npc") as CharacterBody3D

	# Connect signals if NPCs exist
	if bartender != null and bartender.has_signal("beer_purchased"):
		bartender.beer_purchased.connect(_on_beer_purchased)
	if ceo != null and ceo.has_signal("insider_info_given"):
		ceo.insider_info_given.connect(_on_insider_info_received)

	# Ensure interact action exists
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)

	print("[ClubSystem] Initialized. Bartender: ", bartender != null, ", CEO: ", ceo != null)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	# -------- Nearest bartender (<= 3m) --------
	var nearest_bartender: Node3D = null
	var nearest_bartender_dist: float = 3.0
	for bartender_node in get_tree().get_nodes_in_group("bartender_npc"):
		if bartender_node is Node3D:
			var d: float = player.global_position.distance_to((bartender_node as Node3D).global_position)
			if d < nearest_bartender_dist:
				nearest_bartender_dist = d
				nearest_bartender = bartender_node as Node3D

	# -------- Pick CEO: prefer one whose InteractionArea contains player --------
	var picked_ceo: Node3D = null
	for ceo_node in get_tree().get_nodes_in_group("ceo_npc"):
		if ceo_node is Node3D:
			var ia: Area3D = (ceo_node as Node3D).get_node_or_null("InteractionArea") as Area3D
			var inside: bool = false
			if ia != null:
				var bodies: Array = ia.get_overlapping_bodies()
				inside = bodies.has(player)
			if inside:
				picked_ceo = ceo_node as Node3D
				break

	# Fallback: nearest CEO (<= 3m)
	if picked_ceo == null:
		var nearest_ceo_dist: float = 3.0
		for ceo_node in get_tree().get_nodes_in_group("ceo_npc"):
			if ceo_node is Node3D:
				var d2: float = player.global_position.distance_to((ceo_node as Node3D).global_position)
				if d2 < nearest_ceo_dist:
					nearest_ceo_dist = d2
					picked_ceo = ceo_node as Node3D

	# -------- Decide target --------
	if picked_ceo != null:
		_interact_with_ceo_instance(picked_ceo)
	elif nearest_bartender != null:
		_interact_with_bartender_instance(nearest_bartender)
	# else: nothing in range

func _interact_with_bartender_instance(bartender_node: Node) -> void:
	if bartender_node == null or not bartender_node.has_method("interact"):
		return
	var result_variant: Variant = bartender_node.call("interact")
	var result: Dictionary = (result_variant as Dictionary) if typeof(result_variant) == TYPE_DICTIONARY else {}
	if bool(result.get("success", false)):
		print("[Club] Beer purchased!")

func _interact_with_ceo_instance(ceo_node: Node) -> void:
	if ceo_node == null:
		return

	# UPDATED: Check inventory first, then fall back to bartender
	var has_beer: bool = false
	
	# Check new inventory system first
	if typeof(Inventory) != TYPE_NIL:
		has_beer = Inventory.has_beer()
	else:
		# Fallback to old bartender check
		var bartender_node: Node = get_tree().get_first_node_in_group("bartender_npc")
		if bartender_node != null and bartender_node.has_method("has_beer"):
			var has_beer_var: Variant = bartender_node.call("has_beer")
			has_beer = bool(has_beer_var)

	if has_beer and ceo_node.has_method("give_beer"):
		var give_result_var: Variant = ceo_node.call("give_beer")
		var result: Dictionary = (give_result_var as Dictionary) if typeof(give_result_var) == TYPE_DICTIONARY else {}
		var accepted: bool = bool(result.get("success", false)) or bool(result.get("is_tip", false))
		
		# UPDATED: Use inventory system if available
		if accepted:
			if typeof(Inventory) != TYPE_NIL:
				Inventory.remove_item("beer", 1)
				EventBus.emit_signal("beer_given_to_npc", "ceo")
			else:
				# Fallback to old method
				var bartender_node: Node = get_tree().get_first_node_in_group("bartender_npc")
				if bartender_node != null and bartender_node.has_method("player_gave_beer"):
					bartender_node.call("player_gave_beer")
	elif ceo_node.has_method("interact"):
		var _talk_result_unused: Variant = ceo_node.call("interact")

# ----- Signals -----

func _on_beer_purchased() -> void:
	print("[Club] Player bought a beer")
	# UPDATED: Use EventBus instead of direct DialogueUI call
	EventBus.emit_notification("You bought a beer! Find someone who might want it...", "info", 3.0)

func _on_insider_info_received(ticker: StringName) -> void:
	print("[Club] INSIDER TIP RECEIVED: ", ticker)
