# InsiderInfo.gd (only the relevant parts)

extends Node

signal tips_changed()
enum TipType { MOVE_TOMORROW = 0, GENERAL = 1 }

var tips: Array = []	# { id, ticker, type, created_day, expires_day, expires_phase, message }

func _ready() -> void:
	# Only track phase changes; don't purge on day advance
	if typeof(Game) != TYPE_NIL:
		# Game.phase_changed emits (new_phase: StringName, day: int)
		Game.phase_changed.connect(_on_phase_changed)

func add_move_tomorrow_tip(ticker: String, message: String = "") -> void:
	var created_day = 0
	if typeof(Game) != TYPE_NIL:
		created_day = Game.day
	var tip = {
		"id": str(Time.get_unix_time_from_system()) + "_" + ticker,
		"ticker": ticker,
		"type": TipType.MOVE_TOMORROW,
		"created_day": created_day,
		"expires_day": created_day + 1,	# effective tomorrow
		"expires_phase": "close",			# semantic tag; purge when market closes
		"message": (message if message != "" else "Move expected tomorrow for " + ticker)
	}
	tips.append(tip)
	emit_signal("tips_changed")

func get_active_tips() -> Array:
	var out: Array = []
	for t in tips:
		if not _is_expired(t):
			out.append(t)
	return out

func _is_expired(tip: Dictionary) -> bool:
	# Runtime check used by get_active_tips(); mirrors purge rules
	if typeof(Game) == TYPE_NIL:
		return false
	var cur_day = Game.day
	var ph = String(Game.phase).to_lower()
	# Expire once we leave Market on the expires_day (i.e., hit a post-market phase)
	if cur_day == int(tip.expires_day):
		if _is_post_market(ph):
			return true
		return false
	# Anything after expires_day is definitely expired (safety)
	return cur_day > int(tip.expires_day)

func _on_phase_changed(new_phase: StringName, day: int) -> void:
	var ph = String(new_phase).to_lower()
	if not _is_post_market(ph):
		return
	# We just crossed market close; purge tips whose expires_day == today,
	# and also anything older as a safety net.
	var before = tips.size()
	tips = tips.filter(func(t):
		return not (int(t.expires_day) <= day)
	)
	if tips.size() != before:
		emit_signal("tips_changed")

func _is_post_market(phase_lc: String) -> bool:
	# Treat any of these as "after market close". Adjust to your actual phase names if needed.
	return phase_lc == "evening" or phase_lc == "afterhours" or phase_lc == "close" or phase_lc == "closed"
