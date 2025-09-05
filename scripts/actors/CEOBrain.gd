# CEOBrain.gd – Autoload (Godot 4) - FIXED TIMING
# World-clock schedule with proper time calculations
extends Node

const DAY_SEC: float = 86400.0

# --- Travel durations (seconds) ---
const APT_TO_OFFICE_DUR: float = 600.0   # 10 min = 120 + 300 + 180
const OFFICE_TO_CLUB_DUR: float = 480.0  #  8 min = 120 + 300 +  60
const CLUB_TO_APT_DUR: float = 600.0     # 10 min = 120 + 360 + 120


# --- Anchors (in seconds since midnight) ---
const OFFICE_ARRIVE_AT: float = 9.0 * 3600.0 + 30.0 * 60.0  # 9:30 AM = 34200
const OFFICE_LEAVE_AT:  float = 16.0 * 3600.0               # 4:00 PM = 57600
const CLUB_LEAVE_AT:    float = 23.0 * 3600.0               # 11:00 PM = 82800

var _segments: Array[Dictionary] = []
var _built: bool = false
var _last_ws: float = -1.0
var _last_sig: String = ""   # for one-shot segment logging

# Debug tracking
var _debug_mode: bool = true


func _ready() -> void:
	_build_segments()
	if _debug_mode:
		print("[CEOBrain] Schedule built with ", _segments.size(), " segments")
		_print_schedule()

func _process(_delta: float) -> void:
	var ws: float = get_world_seconds()
	
	# Check for midnight wrap
	if _last_ws >= 0.0 and ws < _last_ws:
		_build_segments() # rebuild at midnight
		if _debug_mode:
			print("[CEOBrain] Midnight - rebuilt schedule")
	_last_ws = ws

# ===== Public =====
func get_world_seconds() -> float:
	if typeof(Game) != TYPE_NIL and Game.has_method("get_world_seconds"):
		return float(Game.get_world_seconds())   # smooth, wraps at 86400
	return 0.0



func get_active_segment() -> Dictionary:
	if not _built or _segments.is_empty():
		_build_segments()
	
	var ws: float = get_world_seconds()
	
	# Debug output every 10 game seconds
	#if _debug_mode and int(ws) % 10 == 0:
		#var time_str: String = _format_time(ws)
		#print("[CEOBrain] Current time: ", time_str, " (", ws, " sec)")
	
	for i in range(_segments.size()):
		var seg: Dictionary = _segments[i]
		var t0: float = float(seg.get("t0", 0.0))
		var t1: float = float(seg.get("t1", 0.0))
		if _time_in_interval(ws, t0, t1):
			var sig: String = String(seg.get("scene","")) + "|" + ",".join(seg.get("waypoints", PackedStringArray()))
			if sig != _last_sig:
				_last_sig = sig
				var t0_str: String = _format_time(t0)
				var t1_str: String = _format_time(t1)
				var scene: String = String(seg.get("scene",""))
				var wp_count: int = seg.get("waypoints", PackedStringArray()).size()
				print("[CEOBrain] NEW SEGMENT #", i, ": ", scene, " [", t0_str, " - ", t1_str, "] with ", wp_count, " waypoints")
				print("           Current time: ", _format_time(ws), " (", ws, " sec)")
			return seg
	
	# Fallback idle at apartment
	if _debug_mode:
		print("[CEOBrain] WARNING: No segment matched for time ", _format_time(ws), " (", ws, " sec)")
		print("           Segments available:")
		for i in range(min(5, _segments.size())):
			var seg: Dictionary = _segments[i]
			var t0: float = float(seg.get("t0", 0.0))
			var t1: float = float(seg.get("t1", 0.0))
			print("           #", i, ": ", _format_time(t0), " - ", _format_time(t1), " in ", String(seg.get("scene","")))
	
	return {
		"scene": "aptlobby",
		"waypoints": PackedStringArray([_AL_APT_DOOR()]),
		"t0": 0.0, "t1": DAY_SEC
	}

func notify_scene_segment_arrived(_scene_key: String) -> void:
	if _debug_mode:
		print("[CEOBrain] CEO arrived at: ", _scene_key)

# ===== Aliases =====
func _AL_APT_DOOR() -> String:         return "Apt_Door|Apartment_Door|AptDoor|ApartmentDoor|CEO_Apt_Door|Spawn_CEO_Apt|CEO_Spawn_Apt"
func _AL_APT_EXIT() -> String:         return "Apt_Exit|Apartment_Exit|AptExit|ApartmentExit|Lobby_Exit|Apt_Lobby_Exit"
func _AL_HUB_FROM_APT() -> String:     return "CEO_Hub_Apt|Hub_Apt|Hub_From_Apt|HubApt|Hub_Apartment"
func _AL_HUB_TO_OFFICE() -> String:    return "CEO_Hub_Office|Hub_Office|Hub_To_Office|HubOffice"
func _AL_OFFICE_DOOR() -> String:      return "CEO_Office_Door|Office_Door|OfficeDoor|Off_Door"
func _AL_OFFICE_DESK() -> String:      return "CEO_Office_Desk|Office_Desk|OfficeDesk|CEO_Desk|Desk_CEO"
func _AL_CLUB_DOOR() -> String:        return "CEO_Club_Door|Club_Door|ClubDoor|Bar_Door"
func _AL_CLUB_TABLE() -> String:       return "CEO_Club_Table|Club_Table|ClubTable|Bar_Table|CEO_Booth"

# ===== Build schedule =====
func _build_segments() -> void:
	_segments.clear()
	
	# Calculate key times
	var depart_apt_for_office: float = OFFICE_ARRIVE_AT - (2.0*60.0 + 5.0*60.0 + 3.0*60.0)  # 10 min total
	var arrive_at_club: float        = OFFICE_LEAVE_AT  + (2.0*60.0 + 5.0*60.0 + 1.0*60.0)  # 8  min total
	var arrive_at_apt: float         = CLUB_LEAVE_AT    + (2.0*60.0 + 6.0*60.0 + 2.0*60.0)  # 10 min total

	
	if _debug_mode:
		print("[CEOBrain] Key times:")
		print("  Depart apt: ", _format_time(depart_apt_for_office))
		print("  Arrive office: ", _format_time(OFFICE_ARRIVE_AT))
		print("  Leave office: ", _format_time(OFFICE_LEAVE_AT))
		print("  Arrive club: ", _format_time(arrive_at_club))
		print("  Leave club: ", _format_time(CLUB_LEAVE_AT))
		print("  Arrive apt: ", _format_time(arrive_at_apt))
	
	# Build the daily schedule
	
	# 1) Morning idle at apartment (from late night arrival until departure for office)
	_append_idle("aptlobby", _AL_APT_DOOR(), 0.0, depart_apt_for_office)
	
	# 2) Commute: Apartment → Office (10 minutes total, split proportionally)
	var t: float = depart_apt_for_office
	# Exit apartment building (2 minutes)
	_append_leg("aptlobby", PackedStringArray([_AL_APT_DOOR(), _AL_APT_EXIT()]), t, t + 120.0)
	t += 120.0
	# Walk through hub (5 minutes)  
	_append_leg("hub", PackedStringArray([_AL_HUB_FROM_APT(), _AL_HUB_TO_OFFICE()]), t, t + 300.0)
	t += 300.0
	# Enter office building (3 minutes)
	_append_leg("office", PackedStringArray([_AL_OFFICE_DOOR(), _AL_OFFICE_DESK()]), t, OFFICE_ARRIVE_AT)
	
	# 3) Work: Idle at office
	_append_idle("office", _AL_OFFICE_DESK(), OFFICE_ARRIVE_AT, OFFICE_LEAVE_AT)
	
	# 4) Commute: Office → Club (8 minutes total)
	t = OFFICE_LEAVE_AT
	# Leave office (2 minutes)
	_append_leg("office", PackedStringArray([_AL_OFFICE_DESK(), _AL_OFFICE_DOOR()]), t, t + 120.0)
	t += 120.0
	# Walk through hub (5 minutes)
	_append_leg("hub", PackedStringArray([_AL_HUB_TO_OFFICE(), "CEO_Hub_Club|Hub_Club|Hub_To_Club|HubClub"]), t, t + 300.0)
	t += 300.0
	# Enter club (1 minute)
	_append_leg("club", PackedStringArray([_AL_CLUB_DOOR(), _AL_CLUB_TABLE()]), t, arrive_at_club)
	
	# 5) Evening: Idle at club
	_append_idle("club", _AL_CLUB_TABLE(), arrive_at_club, CLUB_LEAVE_AT)
	
	# 6) Commute: Club → Apartment (10 minutes total)
	t = CLUB_LEAVE_AT
	# Leave club (2 minutes)
	_append_leg("club", PackedStringArray([_AL_CLUB_TABLE(), _AL_CLUB_DOOR()]), t, t + 120.0)
	t += 120.0
	# Walk through hub (6 minutes)
	_append_leg("hub", PackedStringArray(["CEO_Hub_Club|Hub_Club|Hub_To_Club|HubClub", _AL_HUB_FROM_APT()]), t, t + 360.0)
	t += 360.0
	# Enter apartment (2 minutes)
	_append_leg("aptlobby", PackedStringArray([_AL_APT_EXIT(), _AL_APT_DOOR()]), t, arrive_at_apt)
	
	# 7) Late night: Idle at apartment (until midnight if arrival is before midnight)
	if arrive_at_apt < DAY_SEC:
		_append_idle("aptlobby", _AL_APT_DOOR(), arrive_at_apt, DAY_SEC)
	
	# Sort segments by start time
	_segments.sort_custom(Callable(self, "_cmp_seg"))
	_built = true
	_last_sig = ""  # force first segment print

func _cmp_seg(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("t0", 0.0)) < float(b.get("t0", 0.0))

func _append_leg(scene_key: String, names: PackedStringArray, t0: float, t1: float) -> void:
	var seg: Dictionary = {
		"scene": scene_key,
		"waypoints": names,
		"t0": t0,
		"t1": t1
	}
	_segments.append(seg)

func _append_idle(scene_key: String, node_name_aliases: String, t0: float, t1: float) -> void:
	var seg: Dictionary = {
		"scene": scene_key,
		"waypoints": PackedStringArray([node_name_aliases]),
		"t0": t0,
		"t1": t1
	}
	_segments.append(seg)

func _time_in_interval(ws: float, t0: float, t1: float) -> bool:
	# Handle intervals that don't wrap midnight
	if t0 <= t1:
		return (ws >= t0 and ws < t1)
	# Handle intervals that wrap midnight (shouldn't happen with current schedule)
	return (ws >= t0 or ws < t1)

func _format_time(seconds: float) -> String:
	var total_minutes: int = int(seconds / 60.0)
	var hours: int = int(total_minutes / 60)
	var minutes: int = total_minutes % 60
	var period: String = "AM"
	
	if hours >= 12:
		period = "PM"
		if hours > 12:
			hours -= 12
	elif hours == 0:
		hours = 12
	
	return "%d:%02d %s" % [hours, minutes, period]

func _print_schedule() -> void:
	print("[CEOBrain] Full Schedule:")
	for seg in _segments:
		var t0_str: String = _format_time(float(seg.get("t0", 0.0)))
		var t1_str: String = _format_time(float(seg.get("t1", 0.0)))
		var scene: String = String(seg.get("scene", ""))
		var wps: PackedStringArray = seg.get("waypoints", PackedStringArray())
		var wp_count: int = wps.size()
		print("  ", t0_str, " - ", t1_str, ": ", scene, " (", wp_count, " waypoints)")
