extends Node

signal npc_spawned(npc_id: StringName, npc: Node)
signal npc_despawned(npc_id: StringName)

@export var managed_npcs: Array[Dictionary] = [
	{
		"id": "acme_exec_asst",
		"scene_path": "res://scenes/actors/TimmyInsider.tscn",
		"scene_key": "club",
		"phase": "Evening",
		"spawn_marker": "CFO_Spawn"
	}
]

@export var poll_interval_sec: float = 0.5
@export var debug_logging: bool = false

var _spawned: Dictionary = {}
var _last_scene_key: StringName = StringName()
var _current_phase: StringName = &"Morning"
var _poll_accum: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_last_scene_key = _get_current_scene_key()
	_current_phase = _get_current_phase()
	_connect_phase_signal()
	_refresh_spawns("ready")

func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < poll_interval_sec:
		return
	_poll_accum = 0.0

	var now_key: StringName = _get_current_scene_key()
	if now_key != _last_scene_key:
		_last_scene_key = now_key
		_refresh_spawns("scene_changed")

func _get_current_phase() -> StringName:
	if typeof(Game) != TYPE_NIL:
		return Game.phase
	return StringName()

func _connect_phase_signal() -> void:
	if typeof(Game) == TYPE_NIL:
		return
	var cb := Callable(self, "_on_phase_changed")
	if not Game.phase_changed.is_connected(cb):
		Game.phase_changed.connect(cb)

func _on_phase_changed(phase: StringName, _day: int) -> void:
	_current_phase = phase
	_refresh_spawns("phase_changed")

func _refresh_spawns(reason: String = "") -> void:
	if debug_logging:
		print("[NPCSpawnManager] refresh reason=", reason, " scene=", _last_scene_key, " phase=", _current_phase)

	for id_any in _spawned.keys():
		var id: StringName = StringName(id_any)
		var cfg: Dictionary = _config_for(id)
		if cfg.is_empty() or not _should_spawn(cfg):
			if debug_logging:
				print("[NPCSpawnManager] despawn", id)
			_despawn(id)

	for cfg in managed_npcs:
		var id2: StringName = StringName(cfg.get("id", ""))
		if id2 == StringName():
			continue
		if _spawned.has(id2):
			continue
		if _should_spawn(cfg):
			if debug_logging:
				print("[NPCSpawnManager] spawn", id2)
			_spawn_npc(id2, cfg)
		elif debug_logging and id2 == StringName("cfo"):
			print("[NPCSpawnManager] skip spawn for", id2)

func _should_spawn(cfg: Dictionary) -> bool:
	var required_scene: StringName = StringName(cfg.get("scene_key", ""))
	if required_scene != StringName() and required_scene != _last_scene_key:
		if debug_logging and StringName(cfg.get("id", "")) == StringName("cfo"):
			print("[NPCSpawnManager] scene mismatch required=", required_scene, " current=", _last_scene_key)
		return false

	var required_phase: StringName = StringName(cfg.get("phase", ""))
	if required_phase != StringName() and required_phase != _current_phase:
		if debug_logging and StringName(cfg.get("id", "")) == StringName("cfo"):
			print("[NPCSpawnManager] phase mismatch required=", required_phase, " current=", _current_phase)
		return false

	return true

func _spawn_npc(npc_id: StringName, cfg: Dictionary) -> void:
	var scene_path: String = String(cfg.get("scene_path", ""))
	if scene_path == "":
		push_warning("[NPCSpawnManager] Missing scene_path for %s" % [npc_id])
		return
	var packed_res: Resource = load(scene_path)
	var packed: PackedScene = packed_res as PackedScene
	if packed == null:
		push_warning("[NPCSpawnManager] Could not load scene for %s" % [npc_id])
		return

	var npc: Node = packed.instantiate()
	_spawned[npc_id] = npc

	var root: Node = get_tree().current_scene
	if root == null:
		add_child(npc)
	else:
		root.add_child(npc)

	npc.tree_exited.connect(_on_npc_tree_exited.bind(npc_id))

	if npc is Node3D:
		_place_npc(npc as Node3D, cfg)

	emit_signal("npc_spawned", npc_id, npc)

func _place_npc(npc: Node3D, cfg: Dictionary) -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		return

	var marker_name: String = String(cfg.get("spawn_marker", ""))
	if marker_name != "":
		var marker: Node = root.find_child(marker_name, true, false)
		if marker and marker is Node3D:
			npc.global_transform = (marker as Node3D).global_transform
			return

	var group_name: String = String(cfg.get("spawn_group", ""))
	if group_name != "":
		var nodes: Array = root.get_tree().get_nodes_in_group(group_name)
		for n in nodes:
			if n is Node3D:
				npc.global_transform = (n as Node3D).global_transform
				return

	var fallback: Array = root.get_tree().get_nodes_in_group("npc_spawn")
	for n2 in fallback:
		if n2 is Node3D:
			npc.global_transform = (n2 as Node3D).global_transform
			return

func _despawn(npc_id: StringName) -> void:
	if not _spawned.has(npc_id):
		return
	var instance: Variant = _spawned.get(npc_id, null)
	_spawned.erase(npc_id)
	if instance != null and is_instance_valid(instance):
		var node: Node = instance as Node
		if node != null:
			node.queue_free()
	emit_signal("npc_despawned", npc_id)

func _on_npc_tree_exited(npc_id: StringName) -> void:
	if _spawned.has(npc_id):
		var v: Variant = _spawned.get(npc_id, null)
		if v == null or not is_instance_valid(v):
			_spawned.erase(npc_id)

func _config_for(npc_id: StringName) -> Dictionary:
	for cfg in managed_npcs:
		if StringName(cfg.get("id", "")) == npc_id:
			return cfg
	return {}

func _get_current_scene_key() -> StringName:
	if has_node("/root/SceneService"):
		var svc: Node = get_node("/root/SceneService")
		if "current_key" in svc:
			return StringName(svc.current_key)
		if svc.has_method("get_current_key"):
			return StringName(svc.call("get_current_key"))
	if has_node("/root/Scenes"):
		var sc: Node = get_node("/root/Scenes")
		if "current_key" in sc:
			return StringName(sc.current_key)
	var cs: Node = get_tree().current_scene
	if cs != null and cs.scene_file_path != "":
		return StringName(cs.scene_file_path.get_file().get_basename())
	return StringName()
