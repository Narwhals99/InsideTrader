# ClubInteractionSystem.gd
# Attach to a Node in your club scene to manage NPC interactions
extends Node

var bartender: Area3D
var ceo: Area3D
var interaction_ui: Control

func _ready() -> void:
	# Find NPCs in scene
	bartender = get_tree().get_first_node_in_group("bartender_npc")
	ceo = get_tree().get_first_node_in_group("ceo_npc")
	
	# Connect signals if NPCs exist
	if bartender and bartender.has_signal("beer_purchased"):
		bartender.beer_purchased.connect(_on_beer_purchased)
	if ceo and ceo.has_signal("insider_info_given"):
		ceo.insider_info_given.connect(_on_insider_info_received)
	
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
	_show_message(result.get("message", ""))
	
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
			_show_message(result.get("message", ""))
			
			if result.get("is_tip", false):
				_show_insider_tip(result)
			
			# Remove beer from player
			if bartender.has_method("player_gave_beer"):
				bartender.player_gave_beer()
	else:
		# Try to talk without beer
		if ceo.has_method("interact"):
			var result: Dictionary = ceo.interact()
			_show_message(result.get("message", ""))

func _on_beer_purchased() -> void:
	"""Handle beer purchase"""
	print("[Club] Player bought a beer")
	_show_message("You bought a beer! Find someone who might want it...")

func _on_insider_info_received(ticker: StringName) -> void:
	"""Handle receiving insider information"""
	print("[Club] INSIDER TIP RECEIVED: ", ticker)
	# Could trigger achievement, update journal, etc.

func _show_message(text: String) -> void:
	"""Display message to player (implement your UI here)"""
	print("[NPC]: ", text)
	# TODO: Show in actual UI label/popup

func _show_insider_tip(info: Dictionary) -> void:
	"""Special display for insider tips"""
	var ticker: String = String(info.get("ticker", "???"))
	print("🔥 INSIDER TIP: ", ticker, " will move big tomorrow!")
	# TODO: Add to player's notes/journal
	# TODO: Show special UI notification
