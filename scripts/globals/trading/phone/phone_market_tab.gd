extends "res://scripts/globals/trading/phone/phone_tab.gd"
class_name PhoneMarketTab

var list_container: VBoxContainer
var qty_spin: SpinBox
var footer: Control
var rows: Dictionary = {}

func _init(phone_ui: Node, market_scroll: ScrollContainer, list_container: VBoxContainer, qty_spin: SpinBox, footer: Control) -> void:
	self.phone_ui = phone_ui
	self.root = market_scroll
	self.list_container = list_container
	self.qty_spin = qty_spin
	self.footer = footer

func build_rows(symbols: Array) -> void:
	if list_container == null:
		return
	for child in list_container.get_children():
		child.queue_free()
	rows.clear()

	for sn in symbols:
		var sym := String(sn)
		var row := HBoxContainer.new()
		row.name = "Row_" + sym
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_FILL

		var name_label := Label.new()
		name_label.text = sym
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		name_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if phone_ui and phone_ui.has_method("_on_ticker_label_gui_input"):
			name_label.gui_input.connect(Callable(phone_ui, "_on_ticker_label_gui_input").bind(sym))

		var price_label := Label.new()
		price_label.text = "$0.00"
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.name = "Buy_" + sym
		buy_btn.pressed.connect(_on_buy_pressed.bind(sym))

		var sell_btn := Button.new()
		sell_btn.text = "Sell"
		sell_btn.name = "Sell_" + sym
		sell_btn.pressed.connect(_on_sell_pressed.bind(sym))

		row.add_child(name_label)
		row.add_child(price_label)
		row.add_child(buy_btn)
		row.add_child(sell_btn)
		list_container.add_child(row)

		rows[sym] = {"price": price_label, "buy": buy_btn, "sell": sell_btn}

	refresh_full()

func refresh_full() -> void:
	if typeof(MarketSim) == TYPE_NIL:
		return
	var market_open := false
	if phone_ui and phone_ui.has_method("is_market_open"):
		market_open = bool(phone_ui.call("is_market_open"))
	for sn in MarketSim.symbols:
		var sym := String(sn)
		var price: float = float(MarketSim.get_price(StringName(sym)))
		_update_market_row(sym, price, market_open)

func _update_market_row(sym: String, price: float, market_open: bool) -> void:
	if not rows.has(sym):
		return
	var price_label: Label = rows[sym].get("price")
	if price_label:
		price_label.text = "$" + String.num(price, 2)
	var buy_btn: Button = rows[sym].get("buy")
	if buy_btn:
		buy_btn.disabled = not market_open
	var sell_btn: Button = rows[sym].get("sell")
	if sell_btn:
		sell_btn.disabled = not market_open

func _on_buy_pressed(sym: String) -> void:
	if phone_ui and phone_ui.has_method("is_market_open"):
		if not bool(phone_ui.call("is_market_open")):
			print("[Phone] Market closed")
			return
	var qty := _selected_quantity()
	if qty <= 0:
		return
	var price: float = float(MarketSim.get_price(StringName(sym)))
	var ok := Portfolio.buy(StringName(sym), qty, price)
	print("[Phone BUY]", sym, qty, "@", price, " ok=", ok)
	refresh_full()
	if phone_ui and phone_ui.has_method("after_equity_trade"):
		phone_ui.call("after_equity_trade")

func _on_sell_pressed(sym: String) -> void:
	if phone_ui and phone_ui.has_method("is_market_open"):
		if not bool(phone_ui.call("is_market_open")):
			print("[Phone] Market closed")
			return
	var qty := _selected_quantity()
	if qty <= 0:
		return
	var price: float = float(MarketSim.get_price(StringName(sym)))
	var ok := Portfolio.sell(StringName(sym), qty, price)
	print("[Phone SELL]", sym, qty, "@", price, " ok=", ok)
	refresh_full()
	if phone_ui and phone_ui.has_method("after_equity_trade"):
		phone_ui.call("after_equity_trade")

func _selected_quantity() -> int:
	if qty_spin == null:
		return 0
	return int(qty_spin.value)
