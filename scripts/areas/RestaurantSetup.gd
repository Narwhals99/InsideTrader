# RestaurantSetup.gd
# Save as res://scripts/areas/RestaurantSetup.gd
# This script helps you quickly set up a restaurant vendor in your scene
extends Node

# This creates some default food items you can use
# You can also create FoodData resources in the Inspector for more control
static func create_default_menu() -> Array[FoodData]:
	var menu: Array[FoodData] = []
	
	# === MEALS ===
	var burger := FoodData.new()
	burger.item_id = "burger"
	burger.display_name = "Classic Burger"
	burger.description = "Juicy beef patty with lettuce, tomato, and special sauce"
	burger.category = "meal"
	burger.base_price = 25.0
	burger.hunger_restore = 40.0
	burger.consume_message = "That burger really hit the spot!"
	menu.append(burger)
	
	var fries := FoodData.new()
	fries.item_id = "fries"
	fries.display_name = "French Fries"
	fries.description = "Crispy golden fries with sea salt"
	fries.category = "side"
	fries.base_price = 10.0
	fries.hunger_restore = 15.0
	fries.consume_message = "The fries were perfectly crispy!"
	menu.append(fries)
	
	
	# === DRINKS ===
	var soda := FoodData.new()
	soda.item_id = "soda"
	soda.display_name = "Soda"
	soda.description = "Ice-cold cola"
	soda.category = "drink"
	soda.base_price = 5.0
	soda.hunger_restore = 5.0
	soda.energy_restore = 10.0
	soda.consume_message = "The cold soda is refreshing!"
	menu.append(soda)
	
	var coffee := FoodData.new()
	coffee.item_id = "coffee"
	coffee.display_name = "Coffee"
	coffee.description = "Strong black coffee"
	coffee.category = "drink"
	coffee.base_price = 8.0
	coffee.energy_restore = 30.0
	coffee.buff_duration = 60.0  # 1 minute speed boost
	coffee.speed_multiplier = 1.15  # 15% speed boost
	coffee.consume_message = "The coffee gives you a nice energy boost!"
	coffee.required_phase = ""  # Available all day
	menu.append(coffee)
	

	return menu

# Helper function to set up a vendor quickly in code
static func setup_vendor(vendor_area: Area3D, vendor_name: String = "Restaurant") -> void:
	# Add the FoodVendor script if not already attached
	var script_path = "res://scripts/components/FoodVendor.gd"
	if not vendor_area.has_method("open_menu"):
		var script = load(script_path)
		if script:
			vendor_area.set_script(script)
	
	# Configure the vendor
	vendor_area.vendor_name = vendor_name
	vendor_area.vendor_id = vendor_name.to_lower().replace(" ", "_")
	vendor_area.greeting_message = "Welcome to %s! What can I get for you?" % vendor_name
	vendor_area.menu_items = create_default_menu()
	vendor_area.show_wallet_balance = true
	vendor_area.show_nutrition_info = true
	
	print("[RestaurantSetup] Configured vendor: ", vendor_name)
