# ClubStrobeController.gd
# Godot 4.x — attach to any Node/Node3D in your scene
# Controls all OmniLight3D in the given group.

extends Node

@export var light_group: StringName = &"ClubStrobe"	# put your OmniLight3D lights in this group
@export var bpm: float = 120.0						# beats per minute
@export var changes_per_beat: float = 1.0			# 1 = every beat, 2 = twice per beat, 0.5 = every 2 beats
@export_enum("Step","Lerp") var mode: String = "Step"	# hard step vs smooth lerp
@export var palette: Array[Color] = [
	Color(1,0,0),		# red
	Color(1,0,1),		# magenta
	Color(0,0,1),		# blue
	Color(0,1,1),		# cyan
	Color(0,1,0),		# green
	Color(1,1,0)		# yellow
]
@export var per_light_step_offset: int = 0			# how many palette steps to offset each successive light
@export var enabled: bool = true

var _lights: Array = []
var _interval := 0.5
var _t_accum := 0.0
var _idx := 0

func _ready() -> void:
	_scan_lights()
	_recalc_interval()

func _process(dt: float) -> void:
	if not enabled or palette.is_empty() or _lights.is_empty():
		return

	_t_accum += dt
	if mode == "Step":
		if _t_accum >= _interval:
			var steps := int(_t_accum / _interval)
			_t_accum -= _interval * steps
			_idx = (_idx + steps) % palette.size()
			_apply_step()
	else: # Lerp
		var t := _t_accum / _interval
		if t >= 1.0:
			_t_accum -= _interval * floor(t)
			_idx = (_idx + int(floor(t))) % palette.size()
			t = _t_accum / _interval
		_apply_lerp(t)

# --- Controls ---
func rescan_lights() -> void:
	_scan_lights()

func set_bpm(new_bpm: float) -> void:
	bpm = max(1.0, new_bpm)
	_recalc_interval()

func set_changes_per_beat(cpb: float) -> void:
	changes_per_beat = max(0.01, cpb)
	_recalc_interval()

# --- Internals ---
func _scan_lights() -> void:
	_lights.clear()
	for n in get_tree().get_nodes_in_group(light_group):
		var l := n as OmniLight3D
		if l != null:
			_lights.append(l)

func _recalc_interval() -> void:
	_interval = 60.0 / (max(1.0, bpm) * max(0.01, changes_per_beat))

func _apply_step() -> void:
	var n := palette.size()
	for i in _lights.size():
		var off := (i * per_light_step_offset) % n
		var c := palette[(_idx + off) % n]
		(_lights[i] as OmniLight3D).light_color = c

func _apply_lerp(t: float) -> void:
	var n := palette.size()
	var i0 := _idx
	var i1 := (i0 + 1) % n
	for i in _lights.size():
		var off := (i * per_light_step_offset) % n
		var c0 := palette[(i0 + off) % n]
		var c1 := palette[(i1 + off) % n]
		(_lights[i] as OmniLight3D).light_color = c0.lerp(c1, clamp(t, 0.0, 1.0))
