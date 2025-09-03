# ClubInteractionSystem.gd - Fixed version
extends Node

var bartender: Area3D
var ceo: Area3D

func _ready() -> void:
	# Find NPCs in scene
	bartender = get_tree().get_first_node_in_group("bartender_npc")
	ceo = get_tree().get_first_node_in_group("ceo_npc")
	
	# Connect signals if NPCs exist
	if bartender and bartender.has_signal("beer_purchased"):
		bartender.beer_purchased.connect(_on_beer_purchased)
	if ceo and ceo.has_signal("insider_info_given"):
		ceo.insider_info_given.connect(_on_insider_info_received)
	
	# Ensure interact action exists
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)
	
	print("[ClubSystem] Initialized. Bartender: ", bartender != null, ", CEO: ", ceo != null)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	"""Check what the player can interact with"""
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	# Check distance to NPCs and interact with closest
	var min_dist: float = 3.0  # Max interaction distance
	var closest_npc: Node = null
	var closest_dist: float = min_dist
	
	for npc in [bartender, ceo]:
		if npc and npc is Node3D and player is Node3D:
			var dist: float = player.global_position.distance_to(npc.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_npc = npc
	
	if closest_npc == bartender:
		_interact_with_bartender()
	elif closest_npc == ceo:
		_interact_with_ceo()

func _interact_with_bartender() -> void:
	"""Handle bartender interaction"""
	if not bartender or not bartender.has_method("interact"):
		return
	
	var result: Dictionary = bartender.interact()
	
	if result.get("success", false):
		print("[Club] Beer purchased!")

func _interact_with_ceo() -> void:
	"""Handle CEO interaction"""
	if not ceo:
		return
	
	# Check if player has beer
	if bartender and bartender.has_method("has_beer") and bartender.has_beer():
		# Give beer to CEO
		if ceo.has_method("give_beer"):
			var result: Dictionary = ceo.give_beer()
			
			# Only remove beer if CEO actually accepted it
			if result.get("success", false) or result.get("is_tip", false):
				# Remove beer from player
				if bartender.has_method("player_gave_beer"):
					bartender.player_gave_beer()
	else:
		# Try to talk without beer
		if ceo.has_method("interact"):
			var result: Dictionary = ceo.interact()

func _on_beer_purchased() -> void:
	"""Handle beer purchase"""
	print("[Club] Player bought a beer")
	DialogueUI.notify("You bought a beer! Find someone who might want it...", "info", 3.0)

func _on_insider_info_received(ticker: StringName) -> void:
	"""Handle receiving insider information"""
	print("[Club] INSIDER TIP RECEIVED: ", ticker)
	# Could trigger achievement, update journal, etc.
