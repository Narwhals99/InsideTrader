extends Node3D

@export_enum("outdoor","interior") var profile: String = "outdoor"
@export var sun_orbit: Node3D
@export var sun_tilt: Node3D
@export var sun: DirectionalLight3D
@export var env: WorldEnvironment
@export var control_room_lights: bool = true

# Follow the game clock continuously (set true to get smooth motion)
@export var follow_clock: bool = true

# --- Daily key times (minutes since 00:00). Keep in sync with Game.gd ---
const T_MORNING: int = 6 * 60          # 06:00
const T_MARKET: int = 9 * 60 + 30       # 09:30
const T_AFTERMARKET: int = 16 * 60      # 16:00  (maps to "Evening")
const T_LATENIGHT: int = 20 * 60        # 20:00
const T_CUTOFF: int = 2 * 60            # 02:00  (night end; clock freezes until sleep)

# Keyframe values for angles & lighting at those times
var _times: PackedInt32Array = [T_MORNING, T_MARKET, T_AFTERMARKET, T_LATENIGHT, (24 * 60) + T_CUTOFF]
var _az: PackedFloat32Array = [-60.0, 0.0, 60.0, 180.0, 180.0]
var _el: PackedFloat32Array = [ 15.0, 55.0, 15.0,   5.0,   5.0]

# Lighting presets (outdoor vs interior) at the same key times
var _energy_out: PackedFloat32Array = [1.6, 2.0, 1.2, 0.15, 0.15]
var _energy_in:  PackedFloat32Array = [0.4, 0.3, 0.2, 0.10, 0.10]
var _ambient:    PackedFloat32Array = [0.35, 0.30, 0.25, 0.20, 0.20]

var _color_morn: Color = Color(1.0, 0.95, 0.88)
var _color_noon: Color = Color(1.0, 1.0, 1.0)
var _color_eve:  Color = Color(1.0, 0.85, 0.70)
var _color_nite: Color = Color(0.8, 0.9, 1.0)
# Color keys per time index
var _color_keys: Array = [_color_morn, _color_noon, _color_eve, _color_nite, _color_nite]

func _ready() -> void:
	# keep this script running when the tree is paused (e.g., phone open)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)	# or set_physics_process(true) if you use _physics_process
	if sun_orbit == null: sun_orbit = $SunOrbit
	if sun_tilt == null: sun_tilt = $SunOrbit/SunTilt
	if sun == null: sun = $SunOrbit/SunTilt/Sun
	if env == null: env = $WorldEnv

	# Keep rotation on the light itself neutral; orbit/tilt do the aiming
	if sun:
		sun.rotation_degrees = Vector3.ZERO

	set_process(true)
	# Also listen to phase changes in case follow_clock=false
	if Engine.has_singleton("Game") or true:
		Game.phase_changed.connect(_on_phase_changed)
		Game.day_advanced.connect(func(_d): _apply_from_clock())  # refresh after sleep
	_apply_from_clock()

func _process(_dt: float) -> void:
	if follow_clock:
		_apply_from_clock()

# If you ever flip follow_clock=false, weâ€™ll fall back to phase snaps (still okay)
func _on_phase_changed(_p: StringName, _d: int) -> void:
	if not follow_clock:
		_apply_from_clock()

func _apply_from_clock() -> void:
	# Read minutes with fractional precision when available (smoother motion)
	var minutes: float = float(Game.clock_minutes)
	if Game.has_method("get_world_seconds"):
		minutes = Game.get_world_seconds() / 60.0
	var t_ext: float = minutes
	if minutes < float(T_MORNING):
		t_ext += 24.0 * 60.0

	# Find the current segment [i, i+1]
	var i: int = _times.size() - 2
	for idx in range(_times.size() - 1):
		var t0_candidate: float = float(_times[idx])
		var t1_candidate: float = float(_times[idx + 1])
		if t_ext >= t0_candidate and t_ext < t1_candidate:
			i = idx
			break

	var t0: float = float(_times[i])
	var t1: float = float(_times[i + 1])
	var seg_len: float = t1 - t0
	if seg_len <= 0.0:
		seg_len = 1.0
	var u: float = (t_ext - t0) / seg_len
	u = clamp(u, 0.0, 1.0)

	# Interpolate angles
	var az: float = _lerp(_az[i], _az[i + 1], u)
	var el: float = _lerp(_el[i], _el[i + 1], u)
	_set_angles(az, el)

	# Interpolate lighting
	var amb: float = _lerp(_ambient[i], _ambient[i + 1], u)
	_set_env(amb)

	var col_a: Color = _color_keys[i]
	var col_b: Color = _color_keys[i + 1]
	var col: Color = col_a.lerp(col_b, u)

	if profile == "outdoor":
		var en: float = _lerp(_energy_out[i], _energy_out[i + 1], u)
		_set_sun(en, col)
	else:
		var en_in: float = _lerp(_energy_in[i], _energy_in[i + 1], u)
		_set_sun(en_in, col)

	# Room lights on for Evening/LateNight (phase-based; fine for interiors)
	if control_room_lights:
		var pstr: String = String(Game.phase)
		var want_on: bool = (pstr == "Evening") or (pstr == "LateNight")
		_toggle_room(want_on)
func _set_angles(az_deg: float, el_deg: float) -> void:
	if sun_orbit:
		sun_orbit.rotation_degrees.y = az_deg
	if sun_tilt:
		sun_tilt.rotation_degrees.x = -el_deg  # negative aims down

func _set_sun(energy: float, color: Color) -> void:
	if sun:
		sun.light_energy = energy
		sun.light_color = color

func _set_env(ambient_energy: float) -> void:
	if env and env.environment:
		env.environment.ambient_light_energy = ambient_energy

func _toggle_room(on: bool) -> void:
	for n in get_tree().get_nodes_in_group("room_light"):
		if n is Light3D:
			n.visible = on

func _lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t
