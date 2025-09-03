# ClubMusic_SimpleResume.gd
# Godot 4.x — attach to AudioStreamPlayer3D
# Keeps music position across areas so the loop doesn't restart.
# Tabs only.

extends AudioStreamPlayer3D

@export var open_in_phases: PackedStringArray = ["Evening", "LateNight"]
@export var target_db_open: float = 0.0
@export var closed_db: float = -20.0
@export var fade_seconds: float = 0.6
@export var debug: bool = true

# Use the same resume_key for every instance that should share the timeline (e.g., "club_track").
# If left empty, we'll use the stream's resource_path (works if both instances reference the SAME resource).
@export var resume_key: String = ""
@export var save_interval_sec: float = 0.5

static var _LAST_POS := {}	# class-wide: { key: seconds }

var _tween: Tween
var _want_playing: bool = false
var _accum := 0.0
var _key := ""
var _pending_seek_pos := -1.0

func _ready() -> void:
	_key = _compute_key()
	_resume_if_available()
	_sync_with_phase()

	if not Game.phase_changed.is_connected(_on_phase_changed):
		Game.phase_changed.connect(_on_phase_changed)
	if not Game.day_advanced.is_connected(_on_day_advanced):
		Game.day_advanced.connect(_on_day_advanced)

func _process(dt: float) -> void:
	if playing and _key != "":
		_accum += dt
		if _accum >= save_interval_sec:
			_accum = 0.0
			_SAVE_POS(_key, get_playback_position())
			_pending_seek_pos = float(_LAST_POS[_key])

func _exit_tree() -> void:
	if _key != "" and playing:
		_SAVE_POS(_key, get_playback_position())

func _on_phase_changed(_p: StringName, _d: int) -> void:
	_sync_with_phase()

func _on_day_advanced(_d: int) -> void:
	_sync_with_phase()

func _sync_with_phase() -> void:
	var is_open := open_in_phases.has(String(Game.phase))
	if debug:
		print("[Music]", name, " phase=", String(Game.phase), " is_open=", is_open, " playing=", playing, " vol_db=", str(volume_db))
	if is_open:
		_fade_to(target_db_open, true)
	else:
		_fade_to(closed_db, false)

func _fade_to(db_target: float, should_play: bool) -> void:
	if _tween and _tween.is_running():
		_tween.kill()

	if should_play and not playing:
		# Start WITHOUT restarting: seek to last known position if we have one
		if _pending_seek_pos >= 0.0:
			play(_pending_seek_pos)
		else:
			# Fallback: if we saved a pos earlier but pending wasn't set yet
			if _key != "" and _LAST_POS.has(_key):
				play(float(_LAST_POS[_key]))
			else:
				play()

	_want_playing = should_play

	if fade_seconds > 0.01:
		_tween = create_tween()
		_tween.tween_property(self, "volume_db", db_target, fade_seconds)
		_tween.finished.connect(_on_tween_done)
	else:
		volume_db = db_target
		_on_tween_done()

func _on_tween_done() -> void:
	if not _want_playing and playing:
		if _key != "":
			_SAVE_POS(_key, get_playback_position())
			_pending_seek_pos = float(_LAST_POS[_key])
		stop()

	if debug:
		print("[Music]", name, " now playing=", playing, " vol_db=", str(volume_db))

func _resume_if_available() -> void:
	# DO NOT start playback here (phase controls that). Just remember where to seek.
	if _key != "" and _LAST_POS.has(_key):
		_pending_seek_pos = float(_LAST_POS[_key])

func _compute_key() -> String:
	if resume_key != "":
		return resume_key
	if stream != null:
		var p := (stream as Resource).resource_path
		if p != "":
			return p
	return ""

static func _SAVE_POS(key: String, pos: float) -> void:
	_LAST_POS[key] = pos
