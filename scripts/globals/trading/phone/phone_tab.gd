extends RefCounted
class_name PhoneTab

var phone_ui: Node
var root: Control

func _init(phone_ui: Node, root: Control = null) -> void:
	self.phone_ui = phone_ui
	self.root = root

func set_root(control: Control) -> void:
	root = control

func show() -> void:
	if root:
		root.visible = true

func hide() -> void:
	if root:
		root.visible = false

func on_tab_selected() -> void:
	refresh_full()

func refresh_full() -> void:
	pass

func refresh_partial() -> void:
	pass
