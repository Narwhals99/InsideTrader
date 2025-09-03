extends Node

var db: Dictionary = {
	"hub": preload("res://scenes/areas/hub.tscn"),
	"apartment": preload("res://scenes/areas/apartment.tscn"),
	"office": preload("res://scenes/areas/office.tscn"),
	"club": preload("res://scenes/areas/club.tscn"),
	"aptlobby": preload("res://scenes/areas/apartment_lobby.tscn")
}

func scene_for(key: String) -> PackedScene:
	return db.get(key, null)

func change_to(key: String) -> void:
	var p: PackedScene = scene_for(key)
	if p:
		get_tree().call_deferred("change_scene_to_packed", p)	# <- important
	else:
		push_error("Unknown scene key: %s" % key)
