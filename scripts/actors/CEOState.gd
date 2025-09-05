# CEOState.gd – Autoload (Godot 4)
# Spawns CEO only in the active segment's scene and drives him by world time.
extends Node

@export var ceo_scene_path: String = "res://scenes/actors/CEO_NPC.tscn"

var _packed: PackedScene
var _spawning: bool = false
var _last_sig: String = ""

func _ready() -> void:
	if ceo_scene_path != "":
		_packed = load(ceo_scene_path)

func _process(_delta: float) -> void:
	if typeof(CEOBrain) == TYPE_NIL:
		return
	var seg: Dictionary = CEOBrain.get_active_segment()

	var seg_scene: String = _norm(String(seg.get("scene","")))
	var here: String = _current_scene_key_norm()

	if here == seg_scene:
		_spawn_or_update(seg)
	else:
		_despawn_here()

func _spawn_or_update(seg: Dictionary) -> void:
	var root := get_tree().current_scene
	if root == null or _packed == null:
		return

	var ceo := get_tree().get_first_node_in_group("ceo_npc")
	if ceo == null or not root.is_ancestor_of(ceo):
		if _spawning:
			return
		_spawning = true
		_despawn_here()
		var inst := _packed.instantiate()
		if inst == null:
			_spawning = false
			return
		root.add_child(inst)
		if not inst.is_in_group("ceo_npc"):
			inst.add_to_group("ceo_npc")

		# spawn EXACTLY at the first waypoint of the active segment
		var names: PackedStringArray = seg.get("waypoints", PackedStringArray())
		if names.size() > 0 and inst is Node3D:
			# Try to resolve the first waypoint using aliases
			var first_waypoint := _resolve_waypoint_with_aliases(root, names[0])
			if first_waypoint != null:
				(inst as Node3D).global_transform = first_waypoint.global_transform

		_spawning = false
		ceo = inst

	var names2: PackedStringArray = seg.get("waypoints", PackedStringArray())
	var t0: float = float(seg.get("t0", 0.0))
	var t1: float = float(seg.get("t1", 0.0))
	var ws: float = CEOBrain.get_world_seconds()

	if ceo and ceo.has_method("apply_time_segment"):
		ceo.call("apply_time_segment", _current_scene_key_norm(), names2, t0, t1, ws)

	_last_sig = _make_sig(String(seg.get("scene","")), names2, t0, t1)

func _despawn_here() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	for n in get_tree().get_nodes_in_group("ceo_npc"):
		if root.is_ancestor_of(n):
			n.queue_free()

func _current_scene_key_norm() -> String:
	var cs := get_tree().current_scene
	if cs == null:
		return ""
	var key: String = ""
	if typeof(Scenes) != TYPE_NIL and "current_key" in Scenes and str(Scenes.current_key) != "":
		key = str(Scenes.current_key)
	else:
		key = cs.name
	return _norm(key)

# FIXED: Consistent normalization with underscores properly handled
func _norm(raw: String) -> String:
	var s: String = raw.strip_edges().to_lower().replace("_","").replace("-","")
	# Handle all apartment variants
	if s == "apartment" or s == "apt" or s == "apartmentlobby" or s == "aptlobby":
		return "aptlobby"
	# Handle all office variants
	if s == "office" or s == "officelobby" or s == "hq":
		return "office"
	# Handle hub variants
	if s == "hub" or s == "plaza" or s == "square":
		return "hub"
	# Handle club variants
	if s == "club" or s == "bar":
		return "club"
	return s

func _make_sig(seg_scene: String, names: PackedStringArray, t0: float, t1: float) -> String:
	return _norm(seg_scene) + "|" + ",".join(names) + "|" + str(t0) + ">" + str(t1)

# Helper to resolve waypoint with pipe-separated aliases (same as CEO_NPC)
func _resolve_waypoint_with_aliases(root: Node, raw: String) -> Node3D:
	var options: PackedStringArray = raw.split("|", false)
	
	for opt in options:
		# Try exact path first
		var node: Node = root.get_node_or_null(opt)
		if node and node is Node3D:
			return node as Node3D
		
		# Try recursive find
		node = root.find_child(opt, true, false)
		if node and node is Node3D:
			return node as Node3D
	
	# Try normalized matching for all options
	for opt in options:
		var norm_opt: String = opt.to_lower().replace("_","").replace("-","").replace(" ","")
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is Node3D:
				if cur.name.to_lower().replace("_","").replace("-","").replace(" ","") == norm_opt:
					return cur as Node3D
			for c in cur.get_children():
				stack.append(c)
	
	return null
