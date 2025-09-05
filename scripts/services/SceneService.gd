# SceneService.gd
# This wraps and improves your Scenes.gd functionality
# Add as Autoload: "SceneService" (optional - can also use as static resource)
class_name SceneService
extends Node

# Scene registry - easier to maintain than hardcoded paths
var scene_registry: Dictionary = {
	"hub": "res://scenes/levels/hub/hub.tscn",
	"apartment": "res://scenes/levels/apartment/apartment.tscn",
	"aptlobby": "res://scenes/levels/apartment/apartment_lobby.tscn",
	"office": "res://scenes/levels/office/office.tscn",
	"club": "res://scenes/levels/club/club.tscn"
}

var _is_changing: bool = false
var _next_spawn_point: String = ""

# Singleton pattern for static-like access
static var _instance: SceneService = null

func _ready() -> void:
	_instance = self

# ============ STATIC WRAPPER FUNCTIONS ============
static func get_instance() -> SceneService:
	if _instance == null:
		# Try to find it in the tree
		var tree = Engine.get_main_loop() as SceneTree
		if tree:
			for node in tree.root.get_children():
				if node is SceneService:
					_instance = node
					break
	return _instance

static func change_scene_static(scene_key: String, spawn_point: String = "") -> void:
	var instance = get_instance()
	if instance:
		instance.change_scene(scene_key, spawn_point)
	else:
		push_error("[SceneService] No instance found! Add SceneService as an autoload.")

static func get_current_scene_static() -> String:
	var instance = get_instance()
	if instance:
		return instance.get_current_scene()
	return ""

# ============ INSTANCE METHODS ============
func change_scene(scene_key: String, spawn_point: String = "") -> void:
	if _is_changing:
		push_warning("[SceneService] Scene change already in progress")
		return
	
	if not scene_registry.has(scene_key):
		push_error("[SceneService] Unknown scene: " + scene_key)
		return
	
	_is_changing = true
	_next_spawn_point = spawn_point
	
	# Emit event before change
	EventBus.emit_signal("scene_change_requested", scene_key, spawn_point)
	
	# Store in Game autoload for compatibility
	if typeof(Game) != TYPE_NIL:
		Game.next_spawn = spawn_point
	
	# Use Scenes autoload if available (for compatibility)
	if typeof(Scenes) != TYPE_NIL and Scenes.has_method("change_to"):
		Scenes.change_to(scene_key)
	else:
		# Direct scene change
		_do_scene_change(scene_key)

func _do_scene_change(scene_key: String) -> void:
	var path = scene_registry.get(scene_key, "")
	if path == "":
		push_error("[SceneService] No path for scene: " + scene_key)
		_is_changing = false
		return
	
	# Load and change
	var scene = load(path) as PackedScene
	if scene:
		get_tree().change_scene_to_packed(scene)
		
		# Update current scene tracking
		if typeof(Scenes) != TYPE_NIL:
			Scenes.current_key = scene_key
		
		# Emit completion event (deferred to ensure scene is ready)
		call_deferred("_on_scene_change_complete", scene_key)
	else:
		push_error("[SceneService] Failed to load scene: " + path)
		_is_changing = false

func _on_scene_change_complete(scene_key: String) -> void:
	_is_changing = false
	EventBus.emit_signal("scene_loaded", scene_key)
	
	# Handle spawn point
	if _next_spawn_point != "":
		_handle_spawn_point(_next_spawn_point)
		_next_spawn_point = ""

func _handle_spawn_point(spawn_name: String) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player is Node3D:
		return
	
	var spawn_point = _find_spawn_point(spawn_name)
	if spawn_point:
		(player as Node3D).global_transform = spawn_point.global_transform
		print("[SceneService] Spawned player at: ", spawn_name)

func _find_spawn_point(name: String) -> Node3D:
	var root = get_tree().current_scene
	if not root:
		return null
	
	# Try exact name
	var node = root.find_child(name, true, false)
	if node and node is Node3D:
		return node
	
	# Try common variants
	var variants = [
		name,
		"Spawn_" + name,
		name + "_Spawn",
		"Player_" + name
	]
	
	for variant in variants:
		node = root.find_child(variant, true, false)
		if node and node is Node3D:
			return node
	
	return null

# ============ QUERIES ============
func get_current_scene() -> String:
	if typeof(Scenes) != TYPE_NIL and Scenes.has("current_key"):
		return String(Scenes.current_key)
	
	var scene = get_tree().current_scene
	if scene:
		return _extract_scene_key(scene.name)
	
	return ""

func is_in_scene(scene_key: String) -> bool:
	return get_current_scene() == scene_key

func _extract_scene_key(scene_name: String) -> String:
	var name = scene_name.to_lower()
	
	# Try to match against registry keys
	for key in scene_registry.keys():
		if name.contains(key):
			return key
	
	return name

# ============ REGISTRATION ============
func register_scene(key: String, path: String) -> void:
	scene_registry[key] = path
	print("[SceneService] Registered scene: ", key, " -> ", path)

func get_scene_path(key: String) -> String:
	return scene_registry.get(key, "")

func get_all_scene_keys() -> Array:
	return scene_registry.keys()
