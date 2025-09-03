# CEO_NPC.gd - Fixed version without await issues
extends Area3D

signal drunk_level_changed(level: int)
signal insider_info_given(ticker: StringName)

@export var drunk_threshold: int = 3  # beers needed to spill info
@export var max_drunk_level: int = 5  # max before passing out
@export var sober_up_time: float = 120.0  # seconds to lose 1 drunk level
@export var insider_boost_pct: float = 0.05  # 5% move instead of normal 2%
@export var insider_certainty: float = 0.9  # 90% chance info is correct

var drunk_level: int = 0
var _sober_timer: float = 0.0
var _player_near: bool = false
var _has_given_tip_today: bool = false
var _planned_ticker: StringName = &""

func _ready() -> void:
	add_to_group("ceo_npc")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if typeof(Game) != TYPE_NIL:
		Game.day_advanced.connect(_on_day_advanced)
		Game.phase_changed.connect(_on_phase_changed)

	
	# Pre-roll today's insider info
	_roll_insider_info()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = true
		var status = "CEO - Drunk level: " + str(drunk_level) + "/" + str(drunk_threshold)
		DialogueUI.notify(status, "info", 2.0)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_near = false

func _process(delta: float) -> void:
	# Slowly sober up
	if drunk_level > 0:
		_sober_timer += delta
		if _sober_timer >= sober_up_time:
			_sober_timer = 0.0
			drunk_level -= 1
			emit_signal("drunk_level_changed", drunk_level)
			DialogueUI.notify("CEO is sobering up... Level: " + str(drunk_level), "info", 2.0)

func give_beer() -> Dictionary:
	"""Called when player gives CEO a beer"""
	if drunk_level >= max_drunk_level:
		DialogueUI.show_npc_dialogue("CEO", "I can't... *hiccup* ...drink anymore... come back tomorrow...")
		return {
			"success": false,
			"message": "He's had enough... maybe tomorrow."
		}
	
	drunk_level += 1
	_sober_timer = 0.0  # Reset sober timer
	emit_signal("drunk_level_changed", drunk_level)
	
	DialogueUI.notify("CEO drunk level: " + str(drunk_level) + "/" + str(drunk_threshold), "info", 2.0)
	
	# Check if drunk enough to spill info
	if drunk_level >= drunk_threshold and not _has_given_tip_today:
		return _give_insider_info()
	elif drunk_level < drunk_threshold:
		var beers_needed: int = drunk_threshold - drunk_level
		
		# Different responses based on drunk level
		var responses = [
			"Thanks for the drink! *takes a sip*",
			"You're a real pal, you know that? *hiccup*",
			"One more and I might tell you something interesting..."
		]
		
		if drunk_level <= responses.size():
			DialogueUI.show_npc_dialogue("CEO", responses[drunk_level - 1])
		else:
			DialogueUI.show_npc_dialogue("CEO", "Thanks... *hiccup*")
		
		DialogueUI.notify("Needs " + str(beers_needed) + " more beer(s)", "warning", 2.0)
		
		return {
			"success": true,
			"message": "Thanks for the drink!",
			"hint": "Needs " + str(beers_needed) + " more beer(s)..."
		}
	else:
		DialogueUI.show_npc_dialogue("CEO", "I already told you everything I know tonight!")
		return {
			"success": true,
			"message": "I've said too much already..."
		}

func _give_insider_info() -> Dictionary:
	"""CEO spills the beans about tomorrow's mover"""
	if _has_given_tip_today:
		DialogueUI.show_npc_dialogue("CEO", "I've said too much already... *looks around nervously*")
		return {
			"success": false,
			"message": "I've said too much already..."
		}
	
	_has_given_tip_today = true
	
	# Determine if info is accurate (90% chance by default)
	var is_accurate: bool = randf() <= insider_certainty
	var ticker_to_reveal: StringName
	
	if is_accurate and _planned_ticker != &"":
		ticker_to_reveal = _planned_ticker
	else:
		# Give random/wrong ticker as false info
		ticker_to_reveal = _get_random_ticker()
	
	# Schedule the insider move for tomorrow
	_schedule_insider_move(ticker_to_reveal, is_accurate)
	
	emit_signal("insider_info_given", ticker_to_reveal)
	
	# Use the new sequence helper instead of await
	var messages := [
		{"speaker": "CEO", "text": "Listen... *leans in conspiratorially*"},
		{"speaker": "CEO", "text": "I heard " + String(ticker_to_reveal) + " is gonna make BIG moves tomorrow."},
		{"speaker": "CEO", "text": "Don't tell anyone I told you!"}
	]
	
	DialogueUI.show_dialogue_sequence(messages, 2.5)
	
	# Show special insider notification
	DialogueUI.show_insider_tip(String(ticker_to_reveal))
	
	return {
		"success": true,
		"message": "Listen... I heard " + String(ticker_to_reveal) + " is gonna make big moves tomorrow.",
		"ticker": ticker_to_reveal,
		"is_tip": true
	}

func _roll_insider_info() -> void:
	"""Pre-determine which ticker will actually move tomorrow"""
	if MarketSim.symbols.size() > 0:
		var idx: int = randi() % MarketSim.symbols.size()
		_planned_ticker = MarketSim.symbols[idx]
		print("[CEO] Insider info rolled for tomorrow: ", _planned_ticker)

func _schedule_insider_move(ticker: StringName, is_accurate: bool) -> void:
	"""Tell MarketSim to force this ticker as tomorrow's big mover"""
	if not MarketSim.has_method("force_next_mover"):
		push_warning("[CEO] MarketSim needs force_next_mover() method")
		return
	
	var move_size: float = insider_boost_pct if is_accurate else MarketSim.mover_target_max_pct
	MarketSim.call("force_next_mover", ticker, move_size)
	print("[CEO] Scheduled ", ticker, " as tomorrow's mover (", move_size * 100, "% target)")

func _get_random_ticker() -> StringName:
	"""Get a random ticker for false tips"""
	if MarketSim.symbols.size() > 0:
		var idx: int = randi() % MarketSim.symbols.size()
		return MarketSim.symbols[idx]
	return &"ACME"

func _on_day_advanced(_day: int) -> void:
	"""Reset for new day"""
	_has_given_tip_today = false
	drunk_level = 0
	_sober_timer = 0.0
	_roll_insider_info()
	emit_signal("drunk_level_changed", drunk_level)

func _on_phase_changed(phase: StringName, _day: int) -> void:
	"""Reset tip availability when entering Evening phase"""
	if phase == &"Evening":
		_has_given_tip_today = false

func interact() -> Dictionary:
	"""Main interaction point for player (without beer)"""
	if drunk_level < drunk_threshold:
		var beers_needed: int = drunk_threshold - drunk_level
		DialogueUI.show_npc_dialogue("CEO", "Buy me a drink first, will ya?")
		DialogueUI.notify("Needs " + str(beers_needed) + " beer(s)", "warning", 2.0)
		return {
			"success": false,
			"message": "Buy me a drink first, will ya?",
			"hint": "Needs " + str(beers_needed) + " beer(s)"
		}
	else:
		return _give_insider_info()
