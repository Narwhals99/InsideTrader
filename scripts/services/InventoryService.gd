# InventoryService.gd
# Add this as an Autoload called "Inventory"
# Manages player's items across all NPCs
extends Node

signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal inventory_changed()

# Simple inventory - item_id -> quantity
var items: Dictionary = {}

func _ready() -> void:
	print("[Inventory] Service initialized")

# ============ QUERIES ============
func has_item(item_id: String) -> bool:
	return items.has(item_id) and items[item_id] > 0

func get_quantity(item_id: String) -> int:
	return items.get(item_id, 0)

func has_beer() -> bool:
	"""Convenience method for beer checks"""
	return has_item("beer")

# ============ MUTATIONS ============
func add_item(item_id: String, quantity: int = 1) -> void:
	if quantity <= 0:
		return
	
	if not items.has(item_id):
		items[item_id] = 0
	
	items[item_id] += quantity
	
	emit_signal("item_added", item_id, quantity)
	emit_signal("inventory_changed")
	
	print("[Inventory] Added %d %s (total: %d)" % [quantity, item_id, items[item_id]])

func remove_item(item_id: String, quantity: int = 1) -> bool:
	if not has_item(item_id):
		return false
	
	var current = items[item_id]
	if quantity > current:
		return false
	
	items[item_id] -= quantity
	
	if items[item_id] <= 0:
		items.erase(item_id)
	
	emit_signal("item_removed", item_id, quantity)
	emit_signal("inventory_changed")
	
	print("[Inventory] Removed %d %s (remaining: %d)" % [
		quantity, item_id, items.get(item_id, 0)
	])
	
	return true

func give_beer() -> bool:
	"""Convenience method for giving beer to NPCs"""
	return remove_item("beer", 1)

func clear_all() -> void:
	items.clear()
	emit_signal("inventory_changed")

# ============ DEBUG ============
func debug_print() -> void:
	print("[Inventory] Current items:")
	for item_id in items:
		print("  - %s: %d" % [item_id, items[item_id]])
