extends CanvasLayer
const OptionMarketService = preload("res://scripts/services/OptionMarketService.gd")

const OptionContract = preload("res://scripts/resources/OptionContract.gd")


@export var pause_game_on_open: bool = true
@export var show_market_eta: bool = true
@export var refresh_interval_sec: float = 0.5

# MARKET: Row widgets per symbol: { "price": Label, "buy": Button, "sell": Button }
var _rows: Dictionary = {}
# POSITIONS: Row widgets per symbol: { "qty": Label, "avg": Label, "price": Label, "pnl": Label, "close": Button }
var _pos_rows: Dictionary = {}
# TODAY: Row widgets per symbol: { "open": Label, "price": Label, "chg": Label, "close": Label }
var _day_rows: Dictionary = {}

@onready var _title_label: Label = $Root/Panel/VBox/Title/Label
@onready var _close_btn: Button = $Root/Panel/VBox/Title/CloseBtn
@onready var _tabs: TabBar = $Root/Panel/VBox/Tabs

@onready var _market_scroll: ScrollContainer = $Root/Panel/VBox/Scroll
@onready var _list: VBoxContainer = $Root/Panel/VBox/Scroll/List

@onready var _pos_scroll: ScrollContainer = $Root/Panel/VBox/PosScroll
@onready var _pos_list: VBoxContainer = $Root/Panel/VBox/PosScroll/PosList

@onready var _day_scroll: ScrollContainer = $Root/Panel/VBox/DayScroll
@onready var _day_list: VBoxContainer = $Root/Panel/VBox/DayScroll/DayList

@onready var _footer: HBoxContainer = $Root/Panel/VBox/Footer
@onready var _qty_label: Label = $Root/Panel/VBox/Footer/QtyLabel
@onready var _qty_spin: SpinBox = $Root/Panel/VBox/Footer/QtySpin

# --- new for Insider Info ---
@onready var insider_scroll: ScrollContainer = $Root/Panel/VBox/InsiderScroll
@onready var insider_list: ItemList = $Root/Panel/VBox/InsiderScroll/InsiderList
var _insider_tab_index: int = -1

var _options_tab_index: int = -1
@onready var _options_scroll: ScrollContainer = $Root/Panel/VBox/OptionsScroll
@onready var _options_vbox: VBoxContainer = $Root/Panel/VBox/OptionsScroll/OptionsVbox
@onready var _options_filters: HBoxContainer = $Root/Panel/VBox/OptionsScroll/OptionsVbox/OptionsFilters
@onready var _symbol_select: OptionButton = $Root/Panel/VBox/OptionsScroll/OptionsVbox/OptionsFilters/SymbolSelect
@onready var _expiry_select: OptionButton = $Root/Panel/VBox/OptionsScroll/OptionsVbox/OptionsFilters/ExpirySelect
@onready var _strike_select: OptionButton = $Root/Panel/VBox/OptionsScroll/OptionsVbox/OptionsFilters/StrikeSelect
@onready var _type_toggle: Button = $Root/Panel/VBox/OptionsScroll/OptionsVbox/OptionsFilters/TypeToggle
@onready var _options_list: VBoxContainer = $Root/Panel/VBox/OptionsScroll/OptionsVbox/OptionsList
@onready var _options_footer: HBoxContainer = $Root/Panel/VBox/Footer/OptionsFooter
@onready var _contracts_spin: SpinBox = $Root/Panel/VBox/Footer/OptionsFooter/ContractsSpin
@onready var _premium_preview: Label = $Root/Panel/VBox/Footer/OptionsFooter/PremiumPreview
@onready var _place_option_btn: Button = $Root/Panel/VBox/Footer/OptionsFooter/PlaceOrderBtn

var _selected_option_id: String = ""
var _selected_quote: Dictionary = {}
var _selected_option_button: Button = null
var _selected_expiry_day: int = -1
var _selected_strike_value: float = -1.0
var _options_type: int = OptionContract.OptionType.CALL
var _option_menu: PopupMenu = null
var _option_buttons: Dictionary = {}
var _options_filters_initialized: bool = false
var _options_symbol: String = ""
var _selected_option_row: PanelContainer = null
var _option_chain: Dictionary = {}


var _clock_accum: float = 0.0
var _pos_header: HBoxContainer = null
var _day_header: HBoxContainer = null

# Partial-close popup
var _close_popup: PopupPanel = null
var _close_popup_spin: SpinBox = null
var _close_popup_sym: String = ""

# --- Ticker details popup ---
var _details_popup: PopupPanel = null
var _details_title: Label = null
var _details_sector: Label = null
var _details_list: VBoxContainer = null

# === ADD THESE MEMBER VARIABLES AT THE TOP ===
var _banking_tab_index: int = -1
@onready var banking_scroll: ScrollContainer = null  # Will be created dynamically
@onready var banking_container: VBoxContainer = null  # Will be created dynamically
var _bank_balance_label: Label = null
var _portfolio_cash_label: Label = null
var _transfer_amount_spin: SpinBox = null
var _transaction_list: VBoxContainer = null

func _refresh_insider_info() -> void:
	if insider_list == null:
		return

	insider_list.clear()

	var data: Array = []
	if typeof(InsiderInfo) != TYPE_NIL and InsiderInfo.has_method("get_active_tips"):
		data = InsiderInfo.get_active_tips()

	for t in data:
		var expires := "Day " + str(t.expires_day) + " @ " + str(t.expires_phase).capitalize()
		var line := str(t.ticker) + " - " + str(t.message) + "  (" + expires + ")"
		insider_list.add_item(line)

	if _tabs and _insider_tab_index >= 0:
		_tabs.set_tab_title(_insider_tab_index, "Insider Info (" + str(data.size()) + ")")

func _on_close_button_gui_input(event: InputEvent, sym: String) -> void:
	# Right-click opens partial close popup
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Get current shares for this symbol
		var sym_sn: StringName = StringName(sym)
		var pos: Dictionary = Portfolio.get_position(sym_sn)
		var shares: int = int(pos.get("shares", 0))
		if shares <= 0:
			return
		_close_popup_sym = sym
		_close_popup_spin.max_value = shares
		_close_popup_spin.value = shares	# default to all; user can dial it down

		# Show near mouse; fallback to centered
		var mouse := get_viewport().get_mouse_position()
		_close_popup.popup(Rect2(mouse, Vector2(220, 110)))

func _on_close_popup_ok() -> void:
	if _close_popup_sym == "":
		_close_popup.hide()
		return
	# Market open check
	if not _is_market_open():
		print("[Phone] Market closed")
		_close_popup.hide()
		return

	var qty: int = int(_close_popup_spin.value)
	if qty <= 0:
		_close_popup.hide()
		return

	var sym_sn: StringName = StringName(_close_popup_sym)
	var pos: Dictionary = Portfolio.get_position(sym_sn)
	var shares: int = int(pos.get("shares", 0))
	if shares <= 0:
		_close_popup.hide()
		return
	qty = clamp(qty, 1, shares)

	var px: float = MarketSim.get_price(sym_sn)
	var ok: bool = Portfolio.sell(sym_sn, qty, px)
	print("[Phone CLOSE-PARTIAL]", _close_popup_sym, qty, "@", px, " ok=", ok)

	_close_popup.hide()
	# Refresh affected views
	_refresh_positions()
	_refresh_totals()
	_refresh_market_all()
	_refresh_day()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Tabs setup
	if _tabs != null:
		_tabs.clear_tabs()
		_tabs.add_tab("Market")
		_tabs.add_tab("Positions")
		_tabs.add_tab("Today")

		_options_tab_index = _tabs.get_tab_count()
		_tabs.add_tab("Options")

		# --- Insider Info tab ---
		_insider_tab_index = _tabs.get_tab_count()
		_tabs.add_tab("Insider Info (0)")

		# NEW: Banking tab
		_banking_tab_index = _tabs.get_tab_count()
		_tabs.add_tab("Banking")

		_tabs.current_tab = 0
		if not _tabs.tab_changed.is_connected(_on_tab_selected):
			_tabs.tab_changed.connect(_on_tab_selected)
		if not _tabs.tab_selected.is_connected(_on_tab_selected):
			_tabs.tab_selected.connect(_on_tab_selected)
		_on_tab_selected(_tabs.current_tab)
			
	# Add banking UI creation
	_create_banking_ui()
	_init_options_ui()

	# Connect to bank service
	if typeof(BankService) != TYPE_NIL:
		if not BankService.bank_balance_changed.is_connected(_on_bank_balance_changed):
			BankService.bank_balance_changed.connect(_on_bank_balance_changed)

	# Build initial market rows and wire signals
	_build_market_rows()
	_wire_signals()

	# Ensure headers (placed just above their scrolls)
	_ensure_pos_header()
	_ensure_day_header()

	# Hide Insider section by default
	if insider_scroll:
		insider_scroll.visible = false

	# --- listen for tip updates ---
	if typeof(InsiderInfo) != TYPE_NIL and not InsiderInfo.tips_changed.is_connected(_refresh_insider_info):
		InsiderInfo.tips_changed.connect(_refresh_insider_info)

	# --- Partial Close popup (build once) ---
	_close_popup = PopupPanel.new()
	_close_popup.name = "ClosePopup"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Close quantity"
	_close_popup_spin = SpinBox.new()
	_close_popup_spin.min_value = 1
	_close_popup_spin.step = 1
	_close_popup_spin.value = 1
	_close_popup_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ok := Button.new()
	ok.text = "Close"
	var cancel := Button.new()
	cancel.text = "Cancel"
	hb.add_child(ok)
	hb.add_child(cancel)
	vb.add_child(title)
	vb.add_child(_close_popup_spin)
	vb.add_child(hb)
	_close_popup.add_child(vb)
	add_child(_close_popup)
	ok.pressed.connect(_on_close_popup_ok)
	cancel.pressed.connect(func() -> void: _close_popup.hide())

		# --- Ticker Details popup (build once) ---
	_details_popup = PopupPanel.new()
	_details_popup.name = "TickerDetails"

	# NEW: solid background so text is easy to read
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)  # dark gray, 95% opaque
	style.border_color = Color(0.25, 0.25, 0.25)

	# Godot 4 requires setting border widths per side:
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2

	_details_popup.add_theme_stylebox_override("panel", style)


	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)

	_details_title = Label.new()
	_details_title.add_theme_font_size_override("font_size", 16)

	_details_sector = Label.new()  # "Sector: X"

	var sep := HSeparator.new()

	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_details_list = VBoxContainer.new()
	_details_list.add_theme_constant_override("separation", 4)
	_details_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(_details_list)

	var close_row := HBoxContainer.new()
	close_row.add_theme_constant_override("separation", 8)
	var details_close := Button.new()
	details_close.text = "Close"
	details_close.pressed.connect(func() -> void: _details_popup.hide())
	close_row.add_child(details_close)

	dv.add_child(_details_title)
	dv.add_child(_details_sector)
	dv.add_child(sep)
	dv.add_child(sc)
	dv.add_child(close_row)

	_details_popup.add_child(dv)
	add_child(_details_popup)



	# Default to Market tab visibility
	_on_tab_selected(0)

	_refresh_market_all()
	_refresh_totals()
	_update_title_clock()

	# Initial paint of insider list
	_refresh_insider_info()


func open() -> void:
	visible = true
	if pause_game_on_open:
		get_tree().paused = true
		process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	else:
		process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_market_all()
	_refresh_positions()
	_refresh_day()
	_refresh_totals()
	_update_title_clock()
	if _tabs != null and _tabs.current_tab == _options_tab_index:
		_refresh_option_filters()
		_refresh_option_chain()

func close() -> void:
	if pause_game_on_open:
		get_tree().paused = false
		process_mode = Node.PROCESS_MODE_INHERIT
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_close() -> void:
	close()

func _process(dt: float) -> void:
	if not visible:
		return
	_clock_accum += dt
	if _clock_accum >= refresh_interval_sec:
		_clock_accum = 0.0
		_update_title_clock()
		# live PnL refresh when on Positions tab
		if _tabs != null and _tabs.current_tab == 1:
			_refresh_positions_values_only()
		# live Today tab refresh
		if _tabs != null and _tabs.current_tab == 2:
			_refresh_day_values_only()

# ---------------- Tabs ----------------
# === UPDATE _on_tab_selected FUNCTION ===
func _on_tab_selected(idx: int) -> void:
	var show_market: bool = (idx == 0)
	var show_positions: bool = (idx == 1)
	var show_today: bool = (idx == 2)
	var show_options: bool = (_options_tab_index >= 0 and idx == _options_tab_index)
	var show_insider: bool = (_insider_tab_index >= 0 and idx == _insider_tab_index)
	var show_banking: bool = (_banking_tab_index >= 0 and idx == _banking_tab_index)

	if _market_scroll: _market_scroll.visible = false
	if _pos_scroll: _pos_scroll.visible = false
	if _pos_header: _pos_header.visible = false
	if _day_scroll: _day_scroll.visible = false
	if _day_header: _day_header.visible = false
	if insider_scroll: insider_scroll.visible = false
	if banking_scroll: banking_scroll.visible = false
	if _options_scroll: _options_scroll.visible = false
	if _footer: _footer.visible = false
	if _options_footer: _options_footer.visible = false
	if _qty_label: _qty_label.visible = true
	if _qty_spin: _qty_spin.visible = true

	if show_market:
		if _market_scroll: _market_scroll.visible = true
		if _footer: _footer.visible = true
	elif show_positions:
		if _pos_scroll: _pos_scroll.visible = true
		if _pos_header: _pos_header.visible = true
	elif show_today:
		if _day_scroll: _day_scroll.visible = true
		if _day_header: _day_header.visible = true
	elif show_options:
		if _options_scroll: _options_scroll.visible = true
		if _footer: _footer.visible = true
		if _options_footer: _options_footer.visible = true
		if _qty_label: _qty_label.visible = false
		if _qty_spin: _qty_spin.visible = false
		_refresh_option_filters()
		_refresh_option_chain()
	elif show_insider:
		if insider_scroll: insider_scroll.visible = true
		_refresh_insider_info()
	elif show_banking:
		if banking_scroll: banking_scroll.visible = true
		_refresh_banking_tab()

# ------------- Signals wiring -------------
func _wire_signals() -> void:
	if _close_btn != null and not _close_btn.pressed.is_connected(_on_close):
		_close_btn.pressed.connect(_on_close)

	if typeof(MarketSim) != TYPE_NIL:
		if not MarketSim.prices_changed.is_connected(_on_prices_changed):
			MarketSim.prices_changed.connect(_on_prices_changed)
	if typeof(Game) != TYPE_NIL:
		if Game.has_signal("phase_changed") and not Game.phase_changed.is_connected(_on_phase_changed):
			Game.phase_changed.connect(_on_phase_changed)
	if typeof(Portfolio) != TYPE_NIL:
		if not Portfolio.portfolio_changed.is_connected(_on_portfolio_changed):
			Portfolio.portfolio_changed.connect(_on_portfolio_changed)
		if not Portfolio.order_executed.is_connected(_on_order_executed):
			Portfolio.order_executed.connect(_on_order_executed)

# ------------- Market tab (existing flow) -------------
func _build_market_rows() -> void:
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()

	for sn in MarketSim.symbols:
		var sym: String = String(sn)

		var row := HBoxContainer.new()
		row.name = "Row_" + sym
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_FILL

		var name_label := Label.new()
		name_label.text = sym
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# NEW: make ticker clickable on Market tab
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		name_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		name_label.gui_input.connect(_on_ticker_label_gui_input.bind(sym))

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
		_list.add_child(row)

		_rows[sym] = {"price": price_label, "buy": buy_btn, "sell": sell_btn}


func _refresh_market_all() -> void:
	var market_open: bool = _is_market_open()
	for sn in MarketSim.symbols:
		var sym: String = String(sn)
		var price: float = MarketSim.get_price(StringName(sym))
		_update_market_row(sym, price, market_open)

func _update_market_row(sym: String, price: float, market_open: bool) -> void:
	var price_label: Label = _rows.get(sym, {}).get("price", null)
	if price_label != null:
		price_label.text = "$" + String.num(price, 2)
	var buy_btn: Button = _rows.get(sym, {}).get("buy", null)
	if buy_btn != null:
		buy_btn.disabled = not market_open
	var sell_btn: Button = _rows.get(sym, {}).get("sell", null)
	if sell_btn != null:
		sell_btn.disabled = not market_open

func _on_buy_pressed(sym: String) -> void:
	if not _is_market_open():
		print("[Phone] Market closed")
		return
	var qty: int = int(_qty_spin.value)
	if qty <= 0:
		return
	var px: float = MarketSim.get_price(StringName(sym))
	var ok: bool = Portfolio.buy(StringName(sym), qty, px)
	print("[Phone BUY]", sym, qty, "@", px, " ok=", ok)
	_refresh_market_all()
	_refresh_totals()
	_refresh_positions()
	_refresh_day()

func _on_sell_pressed(sym: String) -> void:
	if not _is_market_open():
		print("[Phone] Market closed")
		return
	var qty: int = int(_qty_spin.value)
	if qty <= 0:
		return
	var px: float = MarketSim.get_price(StringName(sym))
	var ok: bool = Portfolio.sell(StringName(sym), qty, px)
	print("[Phone SELL]", sym, qty, "@", px, " ok=", ok)
	_refresh_market_all()
	_refresh_totals()
	_refresh_positions()
	_refresh_day()

# ------------- Positions tab -------------
func _refresh_positions() -> void:
	if _pos_list == null or typeof(Portfolio) == TYPE_NIL:
		return
	for child in _pos_list.get_children():
		child.queue_free()
	_pos_rows.clear()

	if typeof(MarketSim) != TYPE_NIL:
		for sn in MarketSim.symbols:
			var sym_sn: StringName = sn
			var sym: String = String(sym_sn)
			var pos: Dictionary = Portfolio.get_position(sym_sn)
			var shares: int = int(pos.get("shares", 0))
			if shares <= 0:
				continue

			var avg: float = float(pos.get("avg_cost", 0.0))
			var price: float = MarketSim.get_price(sym_sn)
			var pnl: float = (price - avg) * float(shares)

			var row := HBoxContainer.new()
			row.name = "Pos_" + sym
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.size_flags_vertical = Control.SIZE_FILL

			var name_label := Label.new()
			name_label.text = sym
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.size_flags_stretch_ratio = 2.0
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_label.mouse_filter = Control.MOUSE_FILTER_STOP
			name_label.gui_input.connect(_on_ticker_label_gui_input.bind(sym))

			var qty_label := Label.new()
			qty_label.text = str(shares)
			qty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			qty_label.size_flags_stretch_ratio = 1.0
			qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

			var avg_label := Label.new()
			avg_label.text = "$" + String.num(avg, 2)
			avg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			avg_label.size_flags_stretch_ratio = 1.2
			avg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

			var price_label := Label.new()
			price_label.text = "$" + String.num(price, 2)
			price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			price_label.size_flags_stretch_ratio = 1.2
			price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

			var pnl_label := Label.new()
			pnl_label.text = String.num(pnl, 2)
			pnl_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pnl_label.size_flags_stretch_ratio = 1.2
			pnl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if pnl > 0.0:
				pnl_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			elif pnl < 0.0:
				pnl_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))

			var close_btn := Button.new()
			close_btn.text = "Close"
			close_btn.name = "Close_" + sym
			close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			close_btn.size_flags_stretch_ratio = 1.0
			close_btn.pressed.connect(_on_close_position_pressed.bind(sym))
			close_btn.gui_input.connect(_on_close_button_gui_input.bind(sym))

			row.add_child(name_label)
			row.add_child(qty_label)
			row.add_child(avg_label)
			row.add_child(price_label)
			row.add_child(pnl_label)
			row.add_child(close_btn)
			_pos_list.add_child(row)

			var stock_key := "stock:" + sym
			_pos_rows[stock_key] = {
				"entry_type": "stock",
				"symbol": sym,
				"qty": qty_label,
				"avg": avg_label,
				"price": price_label,
				"pnl": pnl_label,
				"close": close_btn
			}

	if typeof(Portfolio) != TYPE_NIL:
		var option_positions: Dictionary = Portfolio.get_all_option_positions()
		var option_ids: Array = option_positions.keys()
		option_ids.sort()
		for option_id_any in option_ids:
			var option_id: String = String(option_id_any)
			var pos: Dictionary = option_positions[option_id]
			var contracts: int = int(pos.get("contracts", 0))
			if contracts <= 0:
				continue
			var details: Dictionary = pos.get("details", {})
			var underlying := String(details.get("underlying", ""))
			var strike := float(details.get("strike", 0.0))
			var option_type := int(details.get("option_type", OptionContract.OptionType.CALL))
			var type_text := "Call" if option_type == OptionContract.OptionType.CALL else "Put"
			var name_text := underlying if underlying != "" else option_id
			name_text += " " + type_text + " $" + String.num(strike, 2)
			var expiry_day := int(details.get("expiry_day", -1))
			if expiry_day >= 0:
				if typeof(Game) != TYPE_NIL and Game.day > expiry_day:
					if Portfolio.close_option_position(option_id):
						_refresh_totals()
					continue
				name_text += " D" + str(expiry_day)

			var multiplier: int = int(details.get("multiplier", pos.get("multiplier", 100)))
			var avg_premium: float = float(pos.get("avg_premium", 0.0))
			var market_value: float = Portfolio.option_market_value(option_id)
			var mark_price: float = 0.0
			if contracts > 0 and multiplier > 0:
				mark_price = market_value / (float(multiplier) * float(contracts))
			if mark_price <= 0.0 and typeof(OptionMarketService) != TYPE_NIL and OptionMarketService.has_option(option_id):
				var quote := OptionMarketService.get_option_quote(option_id)
				if not quote.is_empty():
					mark_price = float(quote.get("mark", mark_price))
			var option_pnl: float = (mark_price - avg_premium) * float(multiplier) * float(contracts)

			var opt_row := HBoxContainer.new()
			opt_row.name = "PosOpt_" + option_id
			opt_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			opt_row.size_flags_vertical = Control.SIZE_FILL

			var opt_name_label := Label.new()
			opt_name_label.text = name_text
			opt_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			opt_name_label.size_flags_stretch_ratio = 2.0
			opt_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

			var contracts_label := Label.new()
			contracts_label.text = str(contracts)
			contracts_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			contracts_label.size_flags_stretch_ratio = 1.0
			contracts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

			var avg_label_opt := Label.new()
			avg_label_opt.text = "$" + String.num(avg_premium, 2)
			avg_label_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			avg_label_opt.size_flags_stretch_ratio = 1.2
			avg_label_opt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

			var mark_label_opt := Label.new()
			mark_label_opt.text = "$" + String.num(mark_price, 2)
			mark_label_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mark_label_opt.size_flags_stretch_ratio = 1.2
			mark_label_opt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

			var pnl_label_opt := Label.new()
			pnl_label_opt.text = String.num(option_pnl, 2)
			pnl_label_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pnl_label_opt.size_flags_stretch_ratio = 1.2
			pnl_label_opt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if option_pnl > 0.0:
				pnl_label_opt.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			elif option_pnl < 0.0:
				pnl_label_opt.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))

			var close_option_btn := Button.new()
			close_option_btn.text = "Sell"
			close_option_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			close_option_btn.size_flags_stretch_ratio = 1.0
			close_option_btn.pressed.connect(_on_close_option_pressed.bind(option_id))

			opt_row.add_child(opt_name_label)
			opt_row.add_child(contracts_label)
			opt_row.add_child(avg_label_opt)
			opt_row.add_child(mark_label_opt)
			opt_row.add_child(pnl_label_opt)
			opt_row.add_child(close_option_btn)
			_pos_list.add_child(opt_row)

			var option_key := "option:" + option_id
			_pos_rows[option_key] = {
				"entry_type": "option",
				"option_id": option_id,
				"name": opt_name_label,
				"qty": contracts_label,
				"avg": avg_label_opt,
				"price": mark_label_opt,
				"pnl": pnl_label_opt,
				"close": close_option_btn,
				"multiplier": multiplier
			}

func _refresh_positions_values_only() -> void:
	if typeof(Portfolio) == TYPE_NIL:
		return
	for key in _pos_rows.keys():
		var entry: Dictionary = _pos_rows[key]
		var entry_type: String = entry.get("entry_type", "stock")
		if entry_type == "stock":
			var sym: String = entry.get("symbol", "")
			if sym == "":
				continue
			var sym_sn: StringName = StringName(sym)
			var pos: Dictionary = Portfolio.get_position(sym_sn)
			var shares: int = int(pos.get("shares", 0))
			if shares <= 0:
				_refresh_positions()
				return
			var avg: float = float(pos.get("avg_cost", 0.0))
			var price: float = avg
			if typeof(MarketSim) != TYPE_NIL:
				price = MarketSim.get_price(sym_sn)
			var pnl: float = (price - avg) * float(shares)

			var qty_label: Label = entry.get("qty", null)
			if qty_label != null:
				qty_label.text = str(shares)
			var avg_label: Label = entry.get("avg", null)
			if avg_label != null:
				avg_label.text = "$" + String.num(avg, 2)
			var price_label: Label = entry.get("price", null)
			if price_label != null:
				price_label.text = "$" + String.num(price, 2)
			var pnl_label: Label = entry.get("pnl", null)
			if pnl_label != null:
				pnl_label.text = String.num(pnl, 2)
				if pnl > 0.0:
					pnl_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
				elif pnl < 0.0:
					pnl_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
				else:
					pnl_label.remove_theme_color_override("font_color")
		elif entry_type == "option":
			var option_id: String = entry.get("option_id", "")
			if option_id == "":
				continue
			var pos_opt: Dictionary = Portfolio.get_option_position(option_id)
			var details_opt: Dictionary = pos_opt.get("details", {})
			var expiry_day_opt: int = int(details_opt.get("expiry_day", -1))
			if expiry_day_opt >= 0 and typeof(Game) != TYPE_NIL and Game.day > expiry_day_opt:
				Portfolio.close_option_position(option_id)
				_refresh_positions()
				return
			var contracts: int = int(pos_opt.get("contracts", 0))
			if contracts <= 0:
				_refresh_positions()
				return
			var multiplier: int = int(pos_opt.get("multiplier", entry.get("multiplier", 100)))
			var avg_premium: float = float(pos_opt.get("avg_premium", 0.0))
			var market_value_opt: float = Portfolio.option_market_value(option_id)
			var mark_price: float = 0.0
			if contracts > 0 and multiplier > 0:
				mark_price = market_value_opt / (float(multiplier) * float(contracts))
			if mark_price <= 0.0 and typeof(OptionMarketService) != TYPE_NIL and OptionMarketService.has_option(option_id):
				var quote_opt := OptionMarketService.get_option_quote(option_id)
				if not quote_opt.is_empty():
					mark_price = float(quote_opt.get("mark", mark_price))
			var name_label_opt: Label = entry.get("name", null)
			if name_label_opt != null:
				var underlying_opt := String(details_opt.get("underlying", ""))
				var type_opt := int(details_opt.get("option_type", OptionContract.OptionType.CALL))
				var strike_opt := float(details_opt.get("strike", 0.0))
				var name_text_opt := underlying_opt if underlying_opt != "" else option_id
				name_text_opt += " " + ("Call" if type_opt == OptionContract.OptionType.CALL else "Put") + " $" + String.num(strike_opt, 2)
				if expiry_day_opt >= 0:
					name_text_opt += " D" + str(expiry_day_opt)
				name_label_opt.text = name_text_opt
			var pnl_opt: float = (mark_price - avg_premium) * float(multiplier) * float(contracts)

			var qty_label_opt: Label = entry.get("qty", null)
			if qty_label_opt != null:
				qty_label_opt.text = str(contracts)
			var avg_label_opt: Label = entry.get("avg", null)
			if avg_label_opt != null:
				avg_label_opt.text = "$" + String.num(avg_premium, 2)
			var price_label_opt: Label = entry.get("price", null)
			if price_label_opt != null:
				price_label_opt.text = "$" + String.num(mark_price, 2)
			var pnl_label_opt: Label = entry.get("pnl", null)
			if pnl_label_opt != null:
				pnl_label_opt.text = String.num(pnl_opt, 2)
				if pnl_opt > 0.0:
					pnl_label_opt.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
				elif pnl_opt < 0.0:
					pnl_label_opt.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
				else:
					pnl_label_opt.remove_theme_color_override("font_color")
			entry["multiplier"] = multiplier

func _on_close_position_pressed(sym: String) -> void:
	if not _is_market_open():
		print("[Phone] Market closed")
		return
	var sym_sn: StringName = StringName(sym)
	var pos: Dictionary = Portfolio.get_position(sym_sn)
	var shares: int = int(pos.get("shares", 0))
	if shares <= 0:
		return
	var px: float = 0.0
	if typeof(MarketSim) != TYPE_NIL:
		px = MarketSim.get_price(sym_sn)
	var ok: bool = Portfolio.sell(sym_sn, shares, px)
	print("[Phone CLOSE]", sym, shares, "@", px, " ok=", ok)
	_refresh_positions()
	_refresh_totals()
	_refresh_market_all()
	_refresh_day()

func _on_close_option_pressed(option_id: String) -> void:
	if typeof(Portfolio) == TYPE_NIL:
		return
	var pos: Dictionary = Portfolio.get_option_position(option_id)
	var contracts: int = int(pos.get("contracts", 0))
	if contracts <= 0:
		return
	var handled := false
	if _is_market_open() and typeof(TradingService) != TYPE_NIL:
		var result := TradingService.execute_option_sell(option_id, contracts, -1.0)
		handled = bool(result.get("success", false))
		_handle_option_trade_result(result)
	if not handled:
		var ok := Portfolio.close_option_position(option_id)
		if ok:
			_refresh_option_chain()
			_refresh_positions()
			_refresh_totals()
func _refresh_day() -> void:
	for child in _day_list.get_children():
		child.queue_free()
	_day_rows.clear()

	for sn in MarketSim.symbols:
		var sym_sn: StringName = sn
		var sym: String = String(sym_sn)
		var open_px: float = MarketSim.get_today_open(sym_sn)
		if open_px <= 0.0:
			continue	# only show once day has an open

		var last_px: float = MarketSim.get_price(sym_sn)
		var chg_pct: float = MarketSim.get_today_change_pct(sym_sn)
		var close_px: float = MarketSim.get_today_close(sym_sn)

		var row := HBoxContainer.new()
		row.name = "Day_" + sym
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_FILL

		var name_label := Label.new()
		name_label.text = sym
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_stretch_ratio = 2.0
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# NEW: make ticker clickable
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		name_label.gui_input.connect(_on_ticker_label_gui_input.bind(sym))

		var open_label := Label.new()
		open_label.text = "$" + String.num(open_px, 2)
		open_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open_label.size_flags_stretch_ratio = 1.2
		open_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		var price_label := Label.new()
		price_label.text = "$" + String.num(last_px, 2)
		price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		price_label.size_flags_stretch_ratio = 1.2
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		var chg_label := Label.new()
		var chg_str: String = String.num(chg_pct, 2) + "%"
		if chg_pct > 0.0:
			chg_str = "+" + chg_str
		chg_label.text = chg_str
		chg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chg_label.size_flags_stretch_ratio = 1.0
		chg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if chg_pct > 0.0:
			chg_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
		elif chg_pct < 0.0:
			chg_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))

		var close_label := Label.new()
		if close_px > 0.0:
			close_label.text = "$" + String.num(close_px, 2)
		else:
			close_label.text = "-"
		close_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		close_label.size_flags_stretch_ratio = 1.2
		close_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		row.add_child(name_label)
		row.add_child(open_label)
		row.add_child(price_label)
		row.add_child(chg_label)
		row.add_child(close_label)
		_day_list.add_child(row)

		_day_rows[sym] = {
			"open": open_label,
			"price": price_label,
			"chg": chg_label,
			"close": close_label
		}


func _refresh_day_values_only() -> void:
	for key in _day_rows.keys():
		var sym: String = String(key)
		var sym_sn: StringName = StringName(sym)
		var widgets: Dictionary = _day_rows[sym]
		var open_px: float = MarketSim.get_today_open(sym_sn)
		if open_px <= 0.0:
			_refresh_day()
			return
		var last_px: float = MarketSim.get_price(sym_sn)
		var chg_pct: float = MarketSim.get_today_change_pct(sym_sn)
		var close_px: float = MarketSim.get_today_close(sym_sn)

		var open_label: Label = widgets.get("open", null)
		var price_label: Label = widgets.get("price", null)
		var chg_label: Label = widgets.get("chg", null)
		var close_label: Label = widgets.get("close", null)

		if open_label != null:
			open_label.text = "$" + String.num(open_px, 2)
		if price_label != null:
			price_label.text = "$" + String.num(last_px, 2)
		if chg_label != null:
			var chg_str: String = String.num(chg_pct, 2) + "%"
			if chg_pct > 0.0:
				chg_str = "+" + chg_str
			chg_label.text = chg_str
			if chg_pct > 0.0:
				chg_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			elif chg_pct < 0.0:
				chg_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
			else:
				chg_label.remove_theme_color_override("font_color")
		if close_label != null:
			if close_px > 0.0:
				close_label.text = "$" + String.num(close_px, 2)
			else:
				close_label.text = "-"

# ------------- Totals / Footer -------------
func _refresh_totals() -> void:
	var portfolio_cash: float = float(Portfolio.cash)
	var holdings_val: float = Portfolio.holdings_value()
	var wallet: float = 0.0
	
	if typeof(BankService) != TYPE_NIL:
		wallet = BankService.get_balance()
	
	var portfolio_total: float = portfolio_cash + holdings_val
	var net_worth: float = portfolio_total + wallet
	
	# Show wallet separately from portfolio
	_qty_label.text = "[W] $" + String.num(wallet, 2) + " | [P] $" + String.num(portfolio_cash, 2) + " + $" + String.num(holdings_val, 2) + " | Net: $" + String.num(net_worth, 2)

# ------------- React to external changes -------------
func _on_prices_changed(_prices: Dictionary = {}) -> void:
	_refresh_market_all()
	if _tabs != null and _tabs.current_tab == 1:
		_refresh_positions_values_only()
	if _tabs != null and _tabs.current_tab == 2:
		_refresh_day_values_only()
	if _tabs != null and _options_tab_index >= 0:
		if _tabs.current_tab == _options_tab_index:
			_refresh_option_chain()
		elif _selected_option_id != "":
			_update_selected_option_quote()
	_refresh_totals()
	_update_title_clock()

func _on_phase_changed(_p: StringName, _d: int) -> void:
	_refresh_market_all()
	if _tabs != null and _tabs.current_tab == 1:
		_refresh_positions_values_only()
	if _tabs != null and _tabs.current_tab == 2:
		_refresh_day()
	if _tabs != null and _options_tab_index >= 0:
		if _tabs.current_tab == _options_tab_index:
			_refresh_option_chain()
		elif _selected_option_id != "":
			_update_selected_option_quote()
	_update_title_clock()

func _on_portfolio_changed() -> void:
	_refresh_market_all()
	_refresh_positions()
	if _tabs != null and _tabs.current_tab == 2:
		_refresh_day()
	if _tabs != null and _options_tab_index >= 0:
		if _tabs.current_tab == _options_tab_index:
			_refresh_option_chain()
		elif _selected_option_id != "":
			_update_selected_option_quote()
	_refresh_totals()

func _on_order_executed(_order: Dictionary) -> void:
	_refresh_market_all()
	_refresh_positions()
	if _tabs != null and _tabs.current_tab == 2:
		_refresh_day()
	if _tabs != null and _options_tab_index >= 0:
		if _tabs.current_tab == _options_tab_index:
			_refresh_option_chain()
		elif _selected_option_id != "":
			_update_selected_option_quote()
	_refresh_totals()

# ---------------- Clock / Title ----------------
func _update_title_clock() -> void:
	if _title_label == null:
		return
	var time_str: String = _time_string_safe()
	var suffix: String = ""
	if show_market_eta:
		if _is_market_open():
			var left: int = _minutes_until_close_safe()
			if left >= 0:
				suffix = "  (" + str(left) + "m left)"
			else:
				suffix = "  (Market)"
		else:
			suffix = "  (Closed)"
	_title_label.text = "Phone  " + time_str + suffix

func _time_string_safe() -> String:
	if typeof(Game) != TYPE_NIL and Game.has_method("get_time_string"):
		return String(Game.get_time_string())
	if typeof(Game) != TYPE_NIL and Game.has_method("get_hour") and Game.has_method("get_minute"):
		var h: int = int(Game.get_hour())
		var m: int = int(Game.get_minute())
		var is_am: bool = h < 12
		var h12: int = h % 12
		if h12 == 0:
			h12 = 12
		var hh: String = str(h12).pad_zeros(2)
		var mm: String = str(m).pad_zeros(2)
		var suf: String = " AM"
		if not is_am:
			suf = " PM"
		return hh + ":" + mm + suf
	return "??:??"

func _is_market_open() -> bool:
	if typeof(Game) == TYPE_NIL:
		return false
	if Game.has_method("is_market_open"):
		return bool(Game.is_market_open())
	return String(Game.phase) == "Market"

func _minutes_until_close_safe() -> int:
	if typeof(Game) == TYPE_NIL:
		return -1
	if Game.has_method("minutes_until_market_close"):
		return int(Game.minutes_until_market_close())
	return -1

# ---------------- Headers ----------------
func _ensure_pos_header() -> void:
	if _pos_header != null:
		return
	var vbox: VBoxContainer = $Root/Panel/VBox
	if vbox == null:
		push_warning("[PhoneUI] VBox not found at $Root/Panel/VBox")
		return

	var existing: HBoxContainer = vbox.get_node_or_null("PosHeader") as HBoxContainer
	if existing != null:
		_pos_header = existing
		_pos_header.visible = false
		return

	var header := HBoxContainer.new()
	header.name = "PosHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.size_flags_vertical = 0
	header.custom_minimum_size = Vector2(0, 22)
	header.visible = false

	header.add_child(_make_header_label("Ticker", 2.0, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(_make_header_label("Qty", 1.0, HORIZONTAL_ALIGNMENT_CENTER))
	header.add_child(_make_header_label("Avg", 1.2, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_header_label("Price", 1.2, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_header_label("PnL", 1.2, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_header_label("Close", 1.0, HORIZONTAL_ALIGNMENT_CENTER))

	var insert_index: int = vbox.get_child_count()
	if _pos_scroll != null:
		insert_index = _pos_scroll.get_index()
	vbox.add_child(header)
	vbox.move_child(header, insert_index)

	_pos_header = header

func _ensure_day_header() -> void:
	if _day_header != null:
		return
	var vbox: VBoxContainer = $Root/Panel/VBox
	if vbox == null:
		push_warning("[PhoneUI] VBox not found at $Root/Panel/VBox")
		return

	var existing: HBoxContainer = vbox.get_node_or_null("DayHeader") as HBoxContainer
	if existing != null:
		_day_header = existing
		_day_header.visible = false
		return

	var header := HBoxContainer.new()
	header.name = "DayHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.size_flags_vertical = 0
	header.custom_minimum_size = Vector2(0, 22)
	header.visible = false

	header.add_child(_make_header_label("Ticker", 2.0, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(_make_header_label("Open", 1.2, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_header_label("Price", 1.2, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_header_label("??%", 1.0, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_header_label("Close", 1.2, HORIZONTAL_ALIGNMENT_RIGHT))

	var insert_index: int = vbox.get_child_count()
	if _day_scroll != null:
		insert_index = _day_scroll.get_index()
	vbox.add_child(header)
	vbox.move_child(header, insert_index)

	_day_header = header

func _make_header_label(text: String, ratio: float, align: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = 0
	lbl.size_flags_stretch_ratio = ratio
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", 12)
	return lbl

func _on_ticker_label_gui_input(event: InputEvent, sym: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_ticker_details(sym)

func _open_ticker_details(sym: String) -> void:
	if _details_popup == null:
		return

	_details_title.text = sym + " ??? Details"
	_details_sector.text = "Sector: " + _fetch_sector(sym)
	_fill_last5(sym)

	# Centered, roomy
	_details_popup.popup_centered(Vector2(420, 360))


func _fetch_sector(sym: String) -> String:
	if typeof(MarketSim) != TYPE_NIL:
		# try common patterns, degrade gracefully
		if MarketSim.has_method("get_sector"):
			return String(MarketSim.get_sector(StringName(sym)))
		if "sectors" in MarketSim and MarketSim.sectors.has(StringName(sym)):
			return String(MarketSim.sectors[StringName(sym)])
	return "???"

func _fill_last5(sym: String) -> void:
	# clear old rows
	for c in _details_list.get_children():
		c.queue_free()

	var rows: Array = _get_last5_rows(sym)
	if rows.is_empty():
		var lbl := Label.new()
		lbl.text = "No history available."
		_details_list.add_child(lbl)
		return

	# header
	var hdr := HBoxContainer.new()
	hdr.add_child(_make_cell("Day", 1.0, HORIZONTAL_ALIGNMENT_LEFT))
	hdr.add_child(_make_cell("Open", 1.0, HORIZONTAL_ALIGNMENT_RIGHT))
	hdr.add_child(_make_cell("Close", 1.0, HORIZONTAL_ALIGNMENT_RIGHT))
	hdr.add_child(_make_cell("??%", 1.0, HORIZONTAL_ALIGNMENT_RIGHT))
	_details_list.add_child(hdr)

	for r in rows:
		var row := HBoxContainer.new()
		row.add_child(_make_cell("Day " + str(r.day), 1.0, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(_make_cell("$" + String.num(r.open, 2), 1.0, HORIZONTAL_ALIGNMENT_RIGHT))
		row.add_child(_make_cell("$" + String.num(r.close, 2), 1.0, HORIZONTAL_ALIGNMENT_RIGHT))

		var chg := 0.0
		if r.open != 0.0:
			chg = ((r.close - r.open) / r.open) * 100.0
		var chg_lbl := _make_cell(String.num(chg, 2) + "%", 1.0, HORIZONTAL_ALIGNMENT_RIGHT)
		if chg > 0.0:
			chg_lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
		elif chg < 0.0:
			chg_lbl.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
		row.add_child(chg_lbl)

		_details_list.add_child(row)

func _make_cell(text: String, ratio: float, align: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_stretch_ratio = ratio
	lbl.horizontal_alignment = align
	return lbl

func _get_last5_rows(sym: String) -> Array:
	var out: Array = []

	if typeof(MarketSim) == TYPE_NIL:
		return out

	var sn: StringName = StringName(sym)

	# Preferred: a direct history API
	if MarketSim.has_method("get_last_n_days"):
		var arr: Array = MarketSim.get_last_n_days(sn, 5) as Array
		for i in arr.size():
			var di: Dictionary = arr[i] as Dictionary
			out.append({
				"day": int(di.get("day", 0)),
				"open": float(di.get("open", 0.0)),
				"close": float(di.get("close", 0.0))
			})
		return out

	# Alternate: property-based history like: MarketSim.history[sn] = [{day,open,close}, ...]
	if "history" in MarketSim and MarketSim.history is Dictionary and MarketSim.history.has(sn):
		var hist: Array = MarketSim.history[sn] as Array
		var start: int = max(0, hist.size() - 5)
		for i in range(start, hist.size()):
			var dj: Dictionary = hist[i] as Dictionary
			out.append({
				"day": int(dj.get("day", 0)),
				"open": float(dj.get("open", 0.0)),
				"close": float(dj.get("close", 0.0))
			})
		return out

	# Fallback: today-only
	if MarketSim.has_method("get_today_open") and MarketSim.has_method("get_today_close"):
		var today: int = 0
		if typeof(Game) != TYPE_NIL:
			today = int(Game.day)
		out.append({
			"day": today,
			"open": float(MarketSim.get_today_open(sn)),
			"close": float(MarketSim.get_today_close(sn))
		})
		return out

	return out


	# Fallback: today-only (if you expose today open/close)
	if MarketSim.has_method("get_today_open") and MarketSim.has_method("get_today_close"):
		var today := 0
		if typeof(Game) != TYPE_NIL:
			today = int(Game.day)
		out.append({
			"day": today,
			"open": float(MarketSim.get_today_open(sn)),
			"close": float(MarketSim.get_today_close(sn))
		})
		return out

	return out

func _create_banking_ui() -> void:
	# Create ScrollContainer if it doesn't exist
	if banking_scroll == null:
		banking_scroll = ScrollContainer.new()
		banking_scroll.name = "BankingScroll"
		banking_scroll.visible = false
		banking_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		banking_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		$Root/Panel/VBox.add_child(banking_scroll)
	
	# Create container
	if banking_container == null:
		banking_container = VBoxContainer.new()
		banking_container.name = "BankingContainer"
		banking_container.add_theme_constant_override("separation", 16)
		banking_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		banking_scroll.add_child(banking_container)
	
	# Clear existing content
	for child in banking_container.get_children():
		child.queue_free()
	
	# === Title Section ===
	var title = Label.new()
	title.text = "Bank Account"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	banking_container.add_child(title)
	
	# === Balance Display ===
	var balance_panel = PanelContainer.new()
	var balance_vbox = VBoxContainer.new()
	balance_vbox.add_theme_constant_override("separation", 8)
	balance_panel.add_child(balance_vbox)
	banking_container.add_child(balance_panel)
	
	# Wallet Balance (for spending)
	var wallet_row = HBoxContainer.new()
	var wallet_icon = Label.new()
	wallet_icon.text = "[W]"
	wallet_icon.add_theme_font_size_override("font_size", 16)
	var wallet_label = Label.new()
	wallet_label.text = "Wallet (Spending):"
	wallet_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bank_balance_label = Label.new()
	_bank_balance_label.text = "$0.00"
	_bank_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bank_balance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bank_balance_label.add_theme_font_size_override("font_size", 20)
	_bank_balance_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
	wallet_row.add_child(wallet_icon)
	wallet_row.add_child(wallet_label)
	wallet_row.add_child(_bank_balance_label)
	balance_vbox.add_child(wallet_row)
	
	# Portfolio Balance (for trading)
	var portfolio_row = HBoxContainer.new()
	var portfolio_icon = Label.new()
	portfolio_icon.text = "[P]"
	portfolio_icon.add_theme_font_size_override("font_size", 16)
	var portfolio_label = Label.new()
	portfolio_label.text = "Portfolio (Trading):"
	portfolio_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portfolio_cash_label = Label.new()
	_portfolio_cash_label.text = "$0.00"
	_portfolio_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_portfolio_cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portfolio_cash_label.add_theme_font_size_override("font_size", 20)
	portfolio_row.add_child(portfolio_icon)
	portfolio_row.add_child(portfolio_label)
	portfolio_row.add_child(_portfolio_cash_label)
	balance_vbox.add_child(portfolio_row)
	
	# Divider
	banking_container.add_child(HSeparator.new())
	
	# === Transfer Section ===
	var transfer_label = Label.new()
	transfer_label.text = "Transfer Funds"
	transfer_label.add_theme_font_size_override("font_size", 14)
	banking_container.add_child(transfer_label)
	
	# Amount input
	var amount_row = HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 8)
	var amount_label = Label.new()
	amount_label.text = "Amount: $"
	amount_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_transfer_amount_spin = SpinBox.new()
	_transfer_amount_spin.min_value = 0
	_transfer_amount_spin.max_value = 10000
	_transfer_amount_spin.step = 50
	_transfer_amount_spin.value = 100
	_transfer_amount_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(amount_label)
	amount_row.add_child(_transfer_amount_spin)
	banking_container.add_child(amount_row)
	
	# Transfer buttons
	var button_row = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	
	var withdraw_btn = Button.new()
	withdraw_btn.text = "<- To Wallet"
	withdraw_btn.tooltip_text = "Transfer from Portfolio to Wallet for spending"
	withdraw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	withdraw_btn.add_theme_font_size_override("font_size", 14)
	withdraw_btn.pressed.connect(_on_withdraw_pressed)
	button_row.add_child(withdraw_btn)
	
	var deposit_btn = Button.new()
	deposit_btn.text = "To Portfolio ->"
	deposit_btn.tooltip_text = "Transfer from Wallet to Portfolio for trading"
	deposit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deposit_btn.add_theme_font_size_override("font_size", 14)
	deposit_btn.pressed.connect(_on_deposit_pressed)
	button_row.add_child(deposit_btn)
	
	banking_container.add_child(button_row)
	
	# Quick transfer buttons
	var quick_label = Label.new()
	quick_label.text = "Quick Transfer:"
	quick_label.add_theme_font_size_override("font_size", 11)
	quick_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	banking_container.add_child(quick_label)
	
	var quick_row = HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 4)
	for amount in [100, 500, 1000, 2500]:
		var quick_btn = Button.new()
		quick_btn.text = "$" + str(amount)
		quick_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick_btn.add_theme_font_size_override("font_size", 11)
		quick_btn.pressed.connect(func(): _transfer_amount_spin.value = amount)
		quick_row.add_child(quick_btn)
	banking_container.add_child(quick_row)
	
	# Daily limits info
	var limits_label = Label.new()
	limits_label.name = "LimitsLabel"
	limits_label.text = "Daily Limits: $5000 each way"
	limits_label.add_theme_font_size_override("font_size", 10)
	limits_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	banking_container.add_child(limits_label)
	
	banking_container.add_child(HSeparator.new())
	
	# === Recent Activity ===
	var activity_label = Label.new()
	activity_label.text = "Recent Activity"
	activity_label.add_theme_font_size_override("font_size", 14)
	banking_container.add_child(activity_label)
	
	_transaction_list = VBoxContainer.new()
	_transaction_list.add_theme_constant_override("separation", 4)
	banking_container.add_child(_transaction_list)
	
	# Help text
	var help_label = RichTextLabel.new()
	help_label.bbcode_enabled = true
	help_label.fit_content = true
	help_label.text = "[color=#888888][i]Tip: Keep funds in your Wallet for purchases (beer, items)\nKeep funds in Portfolio for trading stocks[/i][/color]"
	help_label.add_theme_font_size_override("normal_font_size", 11)
	banking_container.add_child(help_label)
	
	# Initial refresh
	_refresh_banking_tab()

# ---------------- Options helpers ----------------
func _init_options_ui() -> void:
	_options_filters_initialized = false
	_option_buttons.clear()
	_option_chain.clear()
	_options_symbol = ""
	_selected_option_id = ""
	_selected_quote = {}
	_selected_option_row = null
	if _options_scroll:
		_options_scroll.visible = false
	if _options_footer:
		_options_footer.visible = false
	if _symbol_select:
		if _symbol_select.is_inside_tree():
			pass
		_symbol_select.clear()
		if not _symbol_select.item_selected.is_connected(_on_option_symbol_selected):
			_symbol_select.item_selected.connect(_on_option_symbol_selected)
	if _expiry_select:
		_expiry_select.clear()
		if not _expiry_select.item_selected.is_connected(_on_option_expiry_selected):
			_expiry_select.item_selected.connect(_on_option_expiry_selected)
	if _strike_select:
		_strike_select.clear()
		if not _strike_select.item_selected.is_connected(_on_option_strike_selected):
			_strike_select.item_selected.connect(_on_option_strike_selected)
	if _type_toggle:
		_type_toggle.toggle_mode = true
		_type_toggle.button_pressed = (_options_type == OptionContract.OptionType.PUT)
		if not _type_toggle.toggled.is_connected(_on_option_type_toggled):
			_type_toggle.toggled.connect(_on_option_type_toggled)
		_update_option_type_toggle()
	if _contracts_spin:
		_contracts_spin.min_value = 1
		_contracts_spin.step = 1
		if _contracts_spin.value < 1:
			_contracts_spin.value = 1
		if not _contracts_spin.value_changed.is_connected(_on_option_contracts_changed):
			_contracts_spin.value_changed.connect(_on_option_contracts_changed)
	if _place_option_btn:
		_place_option_btn.disabled = true
		if not _place_option_btn.pressed.is_connected(_on_option_place_pressed):
			_place_option_btn.pressed.connect(_on_option_place_pressed)
	var has_symbols := _populate_option_symbols()
	_options_filters_initialized = true
	if has_symbols:
		_refresh_option_filters()
	else:
		_clear_option_list("No symbols available")
		call_deferred("_retry_populate_option_symbols", 1)
	_update_option_footer()

func _populate_option_symbols() -> bool:
	if _symbol_select == null:
		return false
	var previous: String = _options_symbol
	_symbol_select.clear()
	if typeof(MarketSim) != TYPE_NIL:
		var seen := {}
		for sn in MarketSim.symbols:
			var sym := String(sn)
			if sym.strip_edges() == "":
				continue
			if seen.has(sym):
				continue
			_symbol_select.add_item(sym)
			seen[sym] = true
	var count := _symbol_select.get_item_count()
	if count == 0:
		_options_symbol = ""
		return false
	if previous != "":
		for i in range(count):
			if _symbol_select.get_item_text(i) == previous:
				_symbol_select.select(i)
				_options_symbol = previous
				return true
	_symbol_select.select(0)
	_options_symbol = _symbol_select.get_item_text(0)
	return true

func _retry_populate_option_symbols(attempt: int = 0) -> void:
	if _symbol_select == null or _symbol_select.get_item_count() > 0:
		return
	if attempt >= 60:
		return
	if typeof(MarketSim) == TYPE_NIL or MarketSim.symbols.is_empty():
		call_deferred("_retry_populate_option_symbols", attempt + 1)
		return
	var has_symbols := _populate_option_symbols()
	if has_symbols:
		_refresh_option_filters()
		_update_option_footer()
	else:
		call_deferred("_retry_populate_option_symbols", attempt + 1)

func _get_selected_option_symbol() -> String:
	if _symbol_select == null or _symbol_select.get_item_count() == 0:
		return ""
	var idx := _symbol_select.selected
	if idx < 0:
		idx = 0
	return _symbol_select.get_item_text(idx)

func _refresh_option_filters() -> void:
	if _options_scroll:
		_options_scroll.visible = true
	if not _options_filters_initialized and _options_symbol != "":
		return
	var symbol := _get_selected_option_symbol()
	if symbol == "":
		_options_symbol = ""
		_option_chain.clear()
		_clear_option_list("No symbols available")
		_update_option_footer()
		return
	_options_filters_initialized = false
	_options_symbol = symbol
	_ensure_option_chain(symbol)
	_populate_option_expiries()
	_populate_option_strikes()
	_options_filters_initialized = true

func _ensure_option_chain(symbol: String) -> void:
	_option_chain.clear()
	if typeof(OptionMarketService) == TYPE_NIL:
		return
	var symbol_sn := StringName(symbol)
	var price: float = 0.0
	if typeof(MarketSim) != TYPE_NIL:
		price = float(MarketSim.get_price(symbol_sn))
	var current_day: int = 0
	var phase_sn: StringName = &"market"
	if typeof(Game) != TYPE_NIL:
		current_day = int(Game.day)
		if Game.phase is StringName:
			phase_sn = Game.phase
		else:
			phase_sn = StringName(String(Game.phase))
	OptionMarketService.refresh_symbol(symbol_sn, price, current_day, phase_sn)
	_option_chain = OptionMarketService.get_chain(symbol_sn)

func _populate_option_expiries() -> void:
	if _expiry_select == null:
		return
	_expiry_select.clear()
	var expiry_days: Array[int] = []
	for key in _option_chain.keys():
		expiry_days.append(int(key))
	expiry_days.sort()
	var current_day: int = int(Game.day) if typeof(Game) != TYPE_NIL else 0
	for day in expiry_days:
		var label: String = "Day %d" % day
		if typeof(Game) != TYPE_NIL:
			var date_info: Dictionary = Game.get_calendar_date_for_day(day)
			var weekday_name: String = String(date_info.get("weekday_name", ""))
			var month_name: String = String(date_info.get("month_name", ""))
			var day_value: int = int(date_info.get("day", day))
			var short_weekday: String = weekday_name
			if short_weekday.length() > 3:
				short_weekday = short_weekday.substr(0, 3)
			var short_month: String = month_name
			if short_month.length() > 3:
				short_month = short_month.substr(0, 3)
			label = "%s %s %d" % [short_weekday, short_month, day_value]
		var remaining: int = day - current_day
		if remaining < 0:
			remaining = 0
		label += " (%dd)" % remaining
		_expiry_select.add_item(label, day)
	if expiry_days.is_empty():
		_selected_expiry_day = -1
		_populate_option_strikes()
		return
	var select_idx := expiry_days.find(_selected_expiry_day)
	if select_idx == -1:
		select_idx = 0
		_selected_expiry_day = expiry_days[0]
	_expiry_select.select(select_idx)
	_selected_expiry_day = expiry_days[select_idx]

func _populate_option_strikes() -> void:
	if _strike_select == null:
		return
	_strike_select.clear()
	if _selected_expiry_day == -1 or not _option_chain.has(_selected_expiry_day):
		_selected_strike_value = -1.0
		return
	var strikes: Array[float] = []
	var seen := {}
	var quotes: Array = _option_chain[_selected_expiry_day]
	for quote in quotes:
		var strike := float(quote.get("strike", 0.0))
		if not seen.has(strike):
			seen[strike] = true
			strikes.append(strike)
	strikes.sort()
	for strike in strikes:
		var text := "$" + String.num(strike, 2)
		_strike_select.add_item(text)
	if strikes.is_empty():
		_selected_strike_value = -1.0
		return
	var idx := -1
	for i in range(strikes.size()):
		if abs(strikes[i] - _selected_strike_value) < 0.0001:
			idx = i
			break
	if idx == -1:
		idx = 0
		_selected_strike_value = strikes[0]
	_strike_select.select(idx)
	_selected_strike_value = strikes[idx]
func _parse_option_strike_text(text: String) -> float:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("$"):
		cleaned = cleaned.substr(1, cleaned.length() - 1)
	return float(cleaned)

func _refresh_option_chain(preserve_selection: bool = true) -> void:
	if _options_list == null:
		return
	if _options_symbol == "":
		_clear_option_list("Select a symbol")
		_clear_option_selection()
		return
	_ensure_option_chain(_options_symbol)
	if _selected_expiry_day != -1 and not _option_chain.has(_selected_expiry_day):
		_selected_expiry_day = -1
	if _selected_expiry_day == -1:
		_populate_option_expiries()
		if _selected_expiry_day == -1:
			_clear_option_list("No contracts available")
			_clear_option_selection()
			return
	if _selected_strike_value > 0.0:
		var has_match := false
		if _option_chain.has(_selected_expiry_day):
			for quote in _option_chain[_selected_expiry_day]:
				if abs(float(quote.get("strike", 0.0)) - _selected_strike_value) < 0.0001:
					has_match = true
					break
		if not has_match:
			_selected_strike_value = -1.0
			_populate_option_strikes()
	for child in _options_list.get_children():
		child.queue_free()
	_option_buttons.clear()
	var retained_id := _selected_option_id if preserve_selection else ""
	var rows_built := 0
	if _option_chain.has(_selected_expiry_day):
		for quote in _option_chain[_selected_expiry_day]:
			var strike := float(quote.get("strike", 0.0))
			if _selected_strike_value > 0.0 and abs(strike - _selected_strike_value) > 0.0001:
				continue
			var q_type := int(quote.get("option_type", 0))
			if q_type != _options_type:
				continue
			var row := _build_option_row(quote)
			_options_list.add_child(row)
			rows_built += 1
	if rows_built == 0:
		_clear_option_selection()
		_clear_option_list("No contracts for filters")
	else:
		if retained_id != "" and _option_buttons.has(retained_id):
			_set_selected_option(retained_id, _option_buttons[retained_id]["quote"])
		elif _selected_option_id != "" and _option_buttons.has(_selected_option_id):
			_set_selected_option(_selected_option_id, _option_buttons[_selected_option_id]["quote"])
		else:
			_clear_option_selection()
		_update_option_footer()

func _clear_option_list(message: String = "") -> void:
	if _options_list == null:
		return
	for child in _options_list.get_children():
		child.queue_free()
	if message != "":
		var lbl := Label.new()
		lbl.text = message
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_options_list.add_child(lbl)

func _build_option_row(quote: Dictionary) -> PanelContainer:
	var option_id := String(quote.get("id", ""))
	var panel := PanelContainer.new()
	panel.name = option_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_option_row_gui_input.bind(option_id))

	var layout := HBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)

	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_theme_constant_override("separation", 2)
	layout.add_child(info_col)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_child(header)

	var strike_label := Label.new()
	strike_label.text = "$" + String.num(float(quote.get("strike", 0.0)), 2)
	strike_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strike_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(strike_label)

	var option_type := int(quote.get("option_type", OptionContract.OptionType.CALL))
	var type_label := Label.new()
	type_label.text = "(" + ("Call" if option_type == OptionContract.OptionType.CALL else "Put") + ")"
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(type_label)

	var mark_label := Label.new()
	mark_label.text = "Mark $" + String.num(float(quote.get("mark", 0.0)), 2)
	mark_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_col.add_child(mark_label)

	var bid_label := Label.new()
	bid_label.text = "Bid $" + String.num(float(quote.get("bid", 0.0)), 2)
	bid_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_col.add_child(bid_label)

	var ask_label := Label.new()
	ask_label.text = "Ask $" + String.num(float(quote.get("ask", 0.0)), 2)
	ask_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ask_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_col.add_child(ask_label)

	var delta_label := Label.new()
	delta_label.text = "Delta " + String.num(float(quote.get("delta", 0.0)), 2)
	delta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_col.add_child(delta_label)

	var theta_label := Label.new()
	theta_label.text = "Theta/day " + String.num(float(quote.get("theta_per_day", 0.0)), 2)
	theta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_col.add_child(theta_label)

	var buttons_col := VBoxContainer.new()
	buttons_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons_col.add_theme_constant_override("separation", 4)
	layout.add_child(buttons_col)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.size_flags_horizontal = Control.SIZE_FILL
	buy_btn.pressed.connect(_on_option_buy_pressed.bind(option_id))
	buttons_col.add_child(buy_btn)

	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.size_flags_horizontal = Control.SIZE_FILL
	sell_btn.pressed.connect(_on_option_sell_pressed.bind(option_id))
	buttons_col.add_child(sell_btn)

	_option_buttons[option_id] = {
		"panel": panel,
		"quote": quote.duplicate(true),
		"mark_label": mark_label,
		"bid_label": bid_label,
		"ask_label": ask_label,
		"delta_label": delta_label,
		"theta_label": theta_label,
		"buy": buy_btn,
		"sell": sell_btn
	}

	return panel

func _set_selected_option(option_id: String, quote: Dictionary) -> void:
	if _selected_option_row and is_instance_valid(_selected_option_row):
		_selected_option_row.modulate = Color(1, 1, 1, 1)
	_selected_option_id = option_id
	_selected_quote = quote.duplicate(true)
	_selected_option_row = null
	if _option_buttons.has(option_id):
		var entry: Dictionary = _option_buttons[option_id]
		if entry.has("panel"):
			_selected_option_row = entry["panel"]
			if is_instance_valid(_selected_option_row):
				_selected_option_row.modulate = Color(0.85, 0.9, 1.0, 1.0)
		entry["quote"] = _selected_quote.duplicate(true)
	_update_option_footer()

func _clear_option_selection() -> void:
	if _selected_option_row and is_instance_valid(_selected_option_row):
		_selected_option_row.modulate = Color(1, 1, 1, 1)
	_selected_option_id = ""
	_selected_quote = {}
	_selected_option_row = null
	if _place_option_btn:
		_place_option_btn.disabled = true
	if _premium_preview:
		_premium_preview.text = "Select a contract"

func _on_option_row_gui_input(event: InputEvent, option_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_option_from_buttons(option_id)

func _select_option_from_buttons(option_id: String) -> void:
	if not _option_buttons.has(option_id):
		return
	var entry: Dictionary = _option_buttons[option_id]
	var quote: Dictionary = entry.get("quote", {})
	if quote.is_empty() and typeof(TradingService) != TYPE_NIL:
		quote = TradingService.get_option_quote(option_id)
		entry["quote"] = quote.duplicate(true)
	_set_selected_option(option_id, quote)

func _on_option_symbol_selected(_index: int) -> void:
	if not _options_filters_initialized:
		return
	_clear_option_selection()
	_refresh_option_filters()
	_refresh_option_chain(false)

func _on_option_expiry_selected(_index: int) -> void:
	if not _options_filters_initialized:
		return
	if _expiry_select:
		var id := _expiry_select.get_item_id(_expiry_select.selected)
		_selected_expiry_day = int(id)
	_populate_option_strikes()
	_refresh_option_chain(false)

func _on_option_strike_selected(_index: int) -> void:
	if not _options_filters_initialized:
		return
	if _strike_select:
		var idx := _strike_select.selected
		if idx >= 0:
			var text := _strike_select.get_item_text(idx)
			_selected_strike_value = _parse_option_strike_text(text)
		else:
			_selected_strike_value = -1.0
	_refresh_option_chain(false)

func _on_option_type_toggled(pressed: bool) -> void:
	_options_type = OptionContract.OptionType.PUT if pressed else OptionContract.OptionType.CALL
	_update_option_type_toggle()
	_refresh_option_chain(true)

func _update_option_type_toggle() -> void:
	if _type_toggle == null:
		return
	if _options_type == OptionContract.OptionType.PUT:
		_type_toggle.text = "Puts"
	else:
		_type_toggle.text = "Calls"

func _on_option_contracts_changed(_value: float) -> void:
	_update_option_footer()

func _on_option_place_pressed() -> void:
	if _selected_option_id == "":
		return
	var contracts := int(_contracts_spin.value)
	if contracts <= 0:
		contracts = 1
	_execute_option_trade_auto(_selected_option_id, contracts)

func _on_option_buy_pressed(option_id: String) -> void:
	_select_option_from_buttons(option_id)
	var contracts := int(_contracts_spin.value)
	if contracts <= 0:
		contracts = 1
	_execute_option_trade(option_id, contracts, true)

func _on_option_sell_pressed(option_id: String) -> void:
	_select_option_from_buttons(option_id)
	var contracts := int(_contracts_spin.value)
	if contracts <= 0:
		contracts = 1
	_execute_option_trade(option_id, contracts, false)

func _execute_option_trade(option_id: String, contracts: int, buy: bool = true) -> void:
	if typeof(TradingService) == TYPE_NIL:
		return
	var quote: Dictionary = _option_buttons[option_id].get("quote", {}) if _option_buttons.has(option_id) else {}
	if quote.is_empty():
		quote = TradingService.get_option_quote(option_id)
	if quote.is_empty():
		return
	var premium: float = float(quote.get("ask", quote.get("mark", 0.0))) if buy else float(quote.get("bid", quote.get("mark", 0.0)))
	if buy:
		var buy_result := TradingService.execute_option_buy(option_id, contracts, premium)
		_handle_option_trade_result(buy_result)
	else:
		var sell_result := TradingService.execute_option_sell(option_id, contracts, premium)
		_handle_option_trade_result(sell_result)

func _execute_option_trade_auto(option_id: String, contracts: int) -> void:
	var has_position := false
	if typeof(Portfolio) != TYPE_NIL:
		has_position = Portfolio.has_option_position(option_id)
	_execute_option_trade(option_id, contracts, not has_position)

func _handle_option_trade_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	var success := bool(result.get("success", false))
	if success:
		_refresh_option_filters()
		_refresh_option_chain()
		_refresh_positions()
		_refresh_totals()
	else:
		_update_option_footer()
func _update_selected_option_quote() -> void:
	if _selected_option_id == "":
		return
	var quote: Dictionary = {}
	if typeof(TradingService) != TYPE_NIL:
		quote = TradingService.get_option_quote(_selected_option_id)
	elif typeof(OptionMarketService) != TYPE_NIL:
		quote = OptionMarketService.get_option_quote(_selected_option_id)
	if quote.is_empty():
		return
	_selected_quote = quote.duplicate(true)
	if _option_buttons.has(_selected_option_id):
		_option_buttons[_selected_option_id]["quote"] = _selected_quote.duplicate(true)
	_update_option_footer()

func _update_option_footer() -> void:
	if _premium_preview == null:
		return
	if _selected_option_id == "":
		_premium_preview.text = "Select a contract"
		if _place_option_btn:
			_place_option_btn.disabled = true
		return
	var quote: Dictionary = _selected_quote
	if quote.is_empty():
		if typeof(TradingService) != TYPE_NIL:
			quote = TradingService.get_option_quote(_selected_option_id)
		elif typeof(OptionMarketService) != TYPE_NIL:
			quote = OptionMarketService.get_option_quote(_selected_option_id)
		if not quote.is_empty():
			_selected_quote = quote.duplicate(true)
	if _option_buttons.has(_selected_option_id):
		_option_buttons[_selected_option_id]["quote"] = _selected_quote.duplicate(true)
	var strike := float(_selected_quote.get("strike", 0.0))
	var mark := float(_selected_quote.get("mark", 0.0))
	var bid := float(_selected_quote.get("bid", mark))
	var ask := float(_selected_quote.get("ask", mark))
	var multiplier := int(_selected_quote.get("multiplier", 100))
	var contracts := int(_contracts_spin.value) if _contracts_spin else 1
	if contracts <= 0:
		contracts = 1
		if _contracts_spin:
			_contracts_spin.value = 1
	var notional := mark * float(multiplier) * float(contracts)
	var side_text := "Put" if _options_type == OptionContract.OptionType.PUT else "Call"
	var preview := "%s %.2f | mark $%.2f (bid %.2f / ask %.2f)" % [side_text, strike, mark, bid, ask]
	preview += " | %d x %d ~ $%.2f" % [contracts, multiplier, notional]
	_premium_preview.text = preview
	var has_position := false
	var owned_contracts := 0
	if typeof(Portfolio) != TYPE_NIL:
		var pos := Portfolio.get_option_position(_selected_option_id)
		if not pos.is_empty():
			owned_contracts = int(pos.get("contracts", 0))
			has_position = owned_contracts > 0
	if _contracts_spin:
		if has_position:
			_contracts_spin.max_value = max(owned_contracts, 1)
			if _contracts_spin.value > owned_contracts:
				_contracts_spin.value = owned_contracts
		else:
			_contracts_spin.max_value = 99
	if _place_option_btn:
		_place_option_btn.disabled = false
		_place_option_btn.text = "Sell" if has_position else "Buy"

func _on_withdraw_pressed() -> void:
	"""Move money from Portfolio to Wallet"""
	var amount = float(_transfer_amount_spin.value)
	if amount <= 0:
		return
	
	if typeof(BankService) != TYPE_NIL:
		var result = BankService.withdraw_from_portfolio(amount)
		if result.success:
			_transfer_amount_spin.value = 100  # Reset to default
		_refresh_banking_tab()
		_refresh_totals()

func _on_deposit_pressed() -> void:
	"""Move money from Wallet to Portfolio"""
	var amount = float(_transfer_amount_spin.value)
	if amount <= 0:
		return
	
	if typeof(BankService) != TYPE_NIL:
		var result = BankService.deposit_to_portfolio(amount)
		if result.success:
			_transfer_amount_spin.value = 100  # Reset to default
		_refresh_banking_tab()
		_refresh_totals()

func _refresh_banking_tab() -> void:
	if typeof(BankService) == TYPE_NIL:
		return
	
	# Update balances
	if _bank_balance_label:
		var bank_bal = BankService.get_balance()
		_bank_balance_label.text = "$" + String.num(bank_bal, 2)
		# Color code based on balance
		if bank_bal < 50:
			_bank_balance_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
		elif bank_bal < 200:
			_bank_balance_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
		else:
			_bank_balance_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
	
	if _portfolio_cash_label and typeof(Portfolio) != TYPE_NIL:
		_portfolio_cash_label.text = "$" + String.num(Portfolio.cash, 2)
	
	# Update spinbox limits
	if _transfer_amount_spin:
		_transfer_amount_spin.max_value = max(
			BankService.get_available_to_withdraw(),
			BankService.get_available_to_deposit()
		)
	
	# Update daily limits display
	var limits = BankService.get_daily_limits_status()
	var limits_label = banking_container.get_node_or_null("LimitsLabel")
	if limits_label:
		limits_label.text = "Remaining today: <- $%.0f | $%.0f ->" % [
			limits.withdraw_remaining,
			limits.deposit_remaining
		]
	
	# Update transaction history
	if _transaction_list:
		for child in _transaction_list.get_children():
			child.queue_free()
		
		var history = BankService.get_transaction_history(5)
		for trans in history:
			var trans_row = HBoxContainer.new()
			
			# Icon based on type
			var icon = Label.new()
			match trans.type:
				"withdraw": icon.text = "<"
				"deposit": icon.text = ">"
				"purchase": icon.text = "[B]"
				"income": icon.text = "[$]"
				_: icon.text = "*"
			
			var desc_label = Label.new()
			var desc_text = trans.type.capitalize()
			if trans.has("description") and trans.description != "":
				desc_text = trans.description
			desc_label.text = desc_text
			desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var amount_label = Label.new()
			var amount_text = "$" + String.num(trans.amount, 2)
			if trans.type in ["deposit", "purchase"]:
				amount_text = "-" + amount_text
				amount_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
			elif trans.type in ["withdraw", "income"]:
				amount_text = "+" + amount_text
				amount_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			amount_label.text = amount_text
			amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			
			var time_label = Label.new()
			time_label.text = trans.get("time_string", "")
			time_label.add_theme_font_size_override("font_size", 9)
			time_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			
			trans_row.add_child(icon)
			trans_row.add_child(desc_label)
			trans_row.add_child(amount_label)
			trans_row.add_child(time_label)
			_transaction_list.add_child(trans_row)
		
		if history.is_empty():
			var empty_label = Label.new()
			empty_label.text = "No recent transactions"
			empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			_transaction_list.add_child(empty_label)

func _on_bank_balance_changed(_new_balance: float) -> void:
	if _tabs and _tabs.current_tab == _banking_tab_index:
		_refresh_banking_tab()
