extends Node

var db: Dictionary = {
	"hub": preload("res://scenes/areas/hub.tscn"),
	"apartment": preload("res://scenes/areas/apartment.tscn"),
	"office": preload("res://scenes/areas/office.tscn"),
	"club": preload("res://scenes/areas/club.tscn"),
	"aptlobby": preload("res://scenes/areas/apartment_lobby.tscn")
}

var current_key: String = ""            # <— update on load
var _is_changing: bool = false

func change_to(key: String) -> void:
	if _is_changing:
		return
	if not db.has(key):
		push_warning("[Scenes] Unknown key: %s" % key)
		return
	_is_changing = true
	call_deferred("_do_change", key)

func _do_change(key: String) -> void:
	get_tree().change_scene_to_packed(db[key])
	current_key = key
	_is_changing = false
