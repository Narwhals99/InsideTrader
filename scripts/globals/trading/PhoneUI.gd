extends CanvasLayer

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


func _refresh_insider_info() -> void:
	if insider_list == null:
		return

	insider_list.clear()

	var data: Array = []
	if typeof(InsiderInfo) != TYPE_NIL and InsiderInfo.has_method("get_active_tips"):
		data = InsiderInfo.get_active_tips()

	for t in data:
		var expires := "Day " + str(t.expires_day) + " @ " + str(t.expires_phase).capitalize()
		var line := str(t.ticker) + " — " + str(t.message) + "  (" + expires + ")"
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

		# --- Insider Info tab ---
		_insider_tab_index = _tabs.get_tab_count()
		_tabs.add_tab("Insider Info (0)")

		_tabs.current_tab = 0
		if not _tabs.tab_selected.is_connected(_on_tab_selected):
			_tabs.tab_selected.connect(_on_tab_selected)

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
func _on_tab_selected(idx: int) -> void:
	var show_market: bool = (idx == 0)
	var show_positions: bool = (idx == 1)
	var show_today: bool = (idx == 2)
	var show_insider: bool = (_insider_tab_index >= 0 and idx == _insider_tab_index)

	# hide all
	if _market_scroll: _market_scroll.visible = false
	if _footer: _footer.visible = false
	if _pos_scroll: _pos_scroll.visible = false
	if _pos_header: _pos_header.visible = false
	if _day_scroll: _day_scroll.visible = false
	if _day_header: _day_header.visible = false
	if insider_scroll: insider_scroll.visible = false

	# show the chosen one
	if show_market:
		if _market_scroll: _market_scroll.visible = true
		if _footer: _footer.visible = true
	elif show_positions:
		if _pos_scroll: _pos_scroll.visible = true
		if _pos_header: _pos_header.visible = true
	elif show_today:
		if _day_scroll: _day_scroll.visible = true
		if _day_header: _day_header.visible = true
	elif show_insider:
		if insider_scroll: insider_scroll.visible = true
		_refresh_insider_info()


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
	for child in _pos_list.get_children():
		child.queue_free()
	_pos_rows.clear()

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
		# NEW: make ticker clickable
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		name_label.gui_input.connect(_on_ticker_label_gui_input.bind(sym))

		var qty_label := Label.new()
		qty_label.text = str(shares)
		qty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var _unused := qty_label.size_flags_stretch_ratio
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
		# right-click for partial close
		close_btn.gui_input.connect(_on_close_button_gui_input.bind(sym))

		row.add_child(name_label)
		row.add_child(qty_label)
		row.add_child(avg_label)
		row.add_child(price_label)
		row.add_child(pnl_label)
		row.add_child(close_btn)
		_pos_list.add_child(row)

		_pos_rows[sym] = {
			"qty": qty_label,
			"avg": avg_label,
			"price": price_label,
			"pnl": pnl_label,
			"close": close_btn
		}


func _refresh_positions_values_only() -> void:
	for key in _pos_rows.keys():
		var sym: String = String(key)
		var sym_sn: StringName = StringName(sym)
		var widgets: Dictionary = _pos_rows[sym]
		var pos: Dictionary = Portfolio.get_position(sym_sn)
		var shares: int = int(pos.get("shares", 0))
		if shares <= 0:
			_refresh_positions()
			return
		var avg: float = float(pos.get("avg_cost", 0.0))
		var price: float = MarketSim.get_price(sym_sn)
		var pnl: float = (price - avg) * float(shares)

		var price_label: Label = widgets.get("price", null)
		var pnl_label: Label = widgets.get("pnl", null)
		if price_label != null:
			price_label.text = "$" + String.num(price, 2)
		if pnl_label != null:
			pnl_label.text = String.num(pnl, 2)
			if pnl > 0.0:
				pnl_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			elif pnl < 0.0:
				pnl_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
			else:
				pnl_label.remove_theme_color_override("font_color")

func _on_close_position_pressed(sym: String) -> void:
	if not _is_market_open():
		print("[Phone] Market closed")
		return
	var sym_sn: StringName = StringName(sym)
	var pos: Dictionary = Portfolio.get_position(sym_sn)
	var shares: int = int(pos.get("shares", 0))
	if shares <= 0:
		return
	var px: float = MarketSim.get_price(sym_sn)
	var ok: bool = Portfolio.sell(sym_sn, shares, px)
	print("[Phone CLOSE]", sym, shares, "@", px, " ok=", ok)
	_refresh_positions()
	_refresh_totals()
	_refresh_market_all()
	_refresh_day()

# ------------- Today tab -------------
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
	var cash: float = float(Portfolio.cash)
	var port_val: float = Portfolio.holdings_value()
	var tot: float = cash + port_val
	_qty_label.text = "Cash: $" + String.num(cash, 2) + "  |  Port: $" + String.num(port_val, 2) + "  |  Total: $" + String.num(tot, 2)

# ------------- React to external changes -------------
func _on_prices_changed(_prices: Dictionary = {}) -> void:
	_refresh_market_all()
	if _tabs != null and _tabs.current_tab == 1:
		_refresh_positions_values_only()
	if _tabs != null and _tabs.current_tab == 2:
		_refresh_day_values_only()
	_refresh_totals()
	_update_title_clock()

func _on_phase_changed(_p: StringName, _d: int) -> void:
	_refresh_market_all()
	if _tabs != null and _tabs.current_tab == 1:
		_refresh_positions_values_only()
	if _tabs != null and _tabs.current_tab == 2:
		_refresh_day()
	_update_title_clock()

func _on_portfolio_changed() -> void:
	_refresh_market_all()
	_refresh_positions()
	if _tabs != null and _tabs.current_tab == 2:
		_refresh_day()
	_refresh_totals()

func _on_order_executed(_order: Dictionary) -> void:
	_refresh_market_all()
	_refresh_positions()
	if _tabs != null and _tabs.current_tab == 2:
		_refresh_day()
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
	header.add_child(_make_header_label("Δ%", 1.0, HORIZONTAL_ALIGNMENT_RIGHT))
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

	_details_title.text = sym + " — Details"
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
	return "—"

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
	hdr.add_child(_make_cell("Δ%", 1.0, HORIZONTAL_ALIGNMENT_RIGHT))
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
