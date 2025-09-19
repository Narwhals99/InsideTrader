# FoodData.gd
# Save as res://scripts/resources/FoodData.gd
# This is a Resource that defines a food item's properties
class_name FoodData
extends Resource

@export_group("Basic Info")
@export var item_id: String = "food_item"
@export var display_name: String = "Food Item"
@export var description: String = "A tasty treat"
@export var icon_path: String = ""  # Optional texture path
@export var category: String = "meal"  # meal, snack, drink, dessert

@export_group("Economics")
@export var base_price: float = 10.0
@export var is_available: bool = true
@export var required_phase: String = ""  # Empty = always available, or "Morning", "Evening" etc

@export_group("Needs Effects")
@export var hunger_restore: float = 25.0  # How much hunger it restores
@export var energy_restore: float = 0.0   # How much energy it restores (coffee, energy drinks)
@export var health_restore: float = 0.0   # Future health system
@export var mood_boost: float = 0.0       # Future mood system

@export_group("Consumption")
@export var consume_time: float = 0.0     # 0 = instant, >0 = eating animation time
@export var stackable: bool = true        # Can buy multiple to inventory
@export var max_stack: int = 10          # Max quantity in inventory
@export var consume_message: String = "You ate {name}!"  # {name} gets replaced
@export var full_message: String = "You're too full to eat this right now."

@export_group("Special Effects")
@export var buff_duration: float = 0.0    # Temporary effects duration in seconds
@export var speed_multiplier: float = 1.0 # Temporary speed boost (coffee = 1.2)
@export var special_effect: String = ""    # Custom effect ID for special items

# Get the final price (can be modified by time of day, etc)
func get_current_price() -> float:
	# You could add dynamic pricing here
	# e.g., breakfast items cheaper in morning
	return base_price

# Check if available at current time
func is_available_now() -> bool:
	if not is_available:
		return false
	
	if required_phase == "":
		return true
	
	if typeof(Game) != TYPE_NIL:
		return String(Game.phase) == required_phase
	
	return true

# Get formatted consume message
func get_consume_message() -> String:
	return consume_message.replace("{name}", display_name)

# Calculate total restoration value (for sorting/comparing)
func get_total_value() -> float:
	return hunger_restore + energy_restore + health_restore + (mood_boost * 0.5)
