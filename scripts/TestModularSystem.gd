# TestModularSystem.gd
# Attach this to any Node in your scene to test the new systems
extends Node

func _ready() -> void:
	print("\n=== TESTING MODULAR SYSTEMS ===\n")
	
	# Test 1: EventBus
	print("1. Testing EventBus...")
	if typeof(EventBus) != TYPE_NIL:
		print("   ✓ EventBus found")
		EventBus.emit_notification("Test notification from modular system!", "success", 3.0)
		print("   ✓ Notification sent (you should see it on screen)")
	else:
		print("   ✗ EventBus NOT FOUND - Check autoload settings")
	
	# Test 2: TradingService
	print("\n2. Testing TradingService...")
	var cash = TradingService.get_cash()
	var market_open = TradingService.is_market_open()
	print("   ✓ Cash: $", cash)
	print("   ✓ Market Open: ", market_open)
	print("   ✓ TradingService working")
	
	# Test 3: TimeService
	print("\n3. Testing TimeService...")
	var time_info = TimeService.get_current_time()
	print("   ✓ Current time: ", time_info.time_string)
	print("   ✓ Phase: ", time_info.phase)
	print("   ✓ Day: ", time_info.day)
	print("   ✓ TimeService working")
	
	# Test 4: Services can talk to existing autoloads
	print("\n4. Testing integration with existing systems...")
	if typeof(Portfolio) != TYPE_NIL:
		print("   ✓ Portfolio accessible: $", Portfolio.cash)
	if typeof(MarketSim) != TYPE_NIL:
		print("   ✓ MarketSim accessible: ", MarketSim.symbols.size(), " symbols")
	if typeof(Game) != TYPE_NIL:
		print("   ✓ Game accessible: Phase = ", Game.phase)
	
	# Test 5: Component classes exist
	print("\n5. Testing component classes...")
	var test_movement = NPCMovementComponent.new()
	if test_movement:
		print("   ✓ NPCMovementComponent can be created")
		test_movement.queue_free()
	
	var test_interaction = InteractionComponent.new()
	if test_interaction:
		print("   ✓ InteractionComponent can be created")
		test_interaction.queue_free()
	
	print("\n=== ALL TESTS COMPLETE ===\n")
	print("If you see notifications on screen and no errors above,")
	print("the modular system is working correctly!")
	print("\nPress 'K' to emit a test event through EventBus")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") or (event is InputEventKey and event.pressed and event.keycode == KEY_K):
		print("\n[TEST] Emitting test events...")
		EventBus.emit_notification("Test from K key!", "info", 2.0)
		EventBus.emit_signal("trade_requested", "ACME", 10, true, 100.0)
		print("[TEST] Events emitted - check if they appear")
