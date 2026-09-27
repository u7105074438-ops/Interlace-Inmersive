# market_app.gd — MARKET de StellarOS (desde R25): cotización e histórico, calendario de resultados, inversores con su confianza, cartera (compra/venta), noticias anticipadas (R25/R28) y paquete accionarial R30 con confirmación (§13.3, §9.3–§9.11, PASO 25 y 34).
# PROPIETARIO DE: el estado de la ventana (cantidad de la orden y operación pendiente de confirmar).
# ESCUCHA: stock_price_updated, investor_confidence_changed, money_changed (solo mientras está abierta, para refrescar).
class_name MarketApp
extends OSApp

## API pública: is_available() (rango ≥ shares.player_trading_min_rank de market.json),
## snapshot() -> Dictionary con todo lo que pinta la ventana, open(host, context).
## Ventana: set_quantity(n), buy(), sell(), buy_stake(), has_pending_confirmation(),
## confirm_pending(), cancel_pending().
## DECISIONES: el efectivo lo mueve MarketTrading (Market no toca PlayerState). Toda operación
## que Market.is_trade_informed() marca como privilegiada (§9.8) y la compra del paquete R30
## (§9.11) piden confirmación explícita (§13.7); las demás órdenes se ejecutan al pulsar.
## Por debajo del rango mínimo la ventana muestra «acceso denegado» (la carcasa debe ocultar el
## icono con is_available()).

const APP_ID := "market"
const TITLE_KEY := "MARKET_APP_TITLE"
const ICON := "market"
const Kit := PersonnelApp.OsKit
const B_CHART_DAYS := "mercado_ui.dias_grafico"
const B_CALENDAR_DAYS := "mercado_ui.dias_calendario"
const B_LOTS := "mercado_ui.lotes"
const B_INSIDER_THRESHOLD := "mercado.umbral_patron_insider"
const B_INVESTOR_TIER := "presentacion_ui.escalon_inversor"
const ACTION_BUY := "buy"
const ACTION_SELL := "sell"
const ACTION_STAKE := "stake"
const DAILY_EVENT := "daily"
const SIDE_EM := 25.0

var _standalone: bool = false
var _in_ui_root: bool = false
var _embedded: bool = false
var _built: bool = false
var _dirty: bool = false
var _quantity: int = 0
var _pending: String = ""
var _last_result: bool = false
var _window: PersonnelApp.OsWindow
var _frame_root: Control
var _ticker: Ticker
var _chart: PriceChart
var _investors: VBoxContainer
var _calendar: VBoxContainer
var _portfolio: VBoxContainer
var _news: VBoxContainer
var _qty_edit: LineEdit
var _confirm: Control


# ═══ Datos ════════════════════════════════════════════════════════════

static func _shares_cfg(key: String) -> int:
	var shares: Variant = Database.get_market_params().get("shares", {})
	return int((shares as Dictionary).get(key, 0)) if shares is Dictionary else 0


static func min_rank() -> int:
	return _shares_cfg("player_trading_min_rank")


static func stake_min_rank() -> int:
	return _shares_cfg("share_package_min_rank")


## La aplicación existe desde R25 (§13.3).
static func is_available() -> bool:
	return PlayerState.get_rank() >= min_rank()


static func news_days() -> int:
	var insider: Variant = Database.get_market_params().get("insider_detection", {})
	return int((insider as Dictionary).get("news_lead_days_max", 0)) if insider is Dictionary else 0


## Todo lo que muestra la ventana (también para tests y el móvil).
static func snapshot() -> Dictionary:
	var history: Array[float] = Market.get_price_history(Database.get_balance_int(B_CHART_DAYS))
	var last_close: float = history.back() if not history.is_empty() else Market.get_price()
	var price: float = Market.get_price()
	return {
		"price": price, "history": history,
		"change": (price - last_close) / last_close if last_close > 0.0 else 0.0,
		"aggregate": Market.get_aggregate_confidence(), "target": Market.get_quarterly_target(),
		"quarter": Market.quarter_of(Market.get_current_day()), "investors": investor_rows(),
		"calendar": calendar_rows(), "news": news_rows(), "portfolio": portfolio(),
	}


static func investor_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var allies: Array[String] = Market.get_investor_allies()
	for inv: InvestorData in Market.get_investors():
		out.append({"id": inv.id, "name": inv.name, "strategy": inv.strategy,
				"strategy_name": UITheme.trf("INV_STRATEGY_" + inv.strategy.to_upper()),
				"confidence": Market.get_investor_confidence(inv.id), "capital": inv.capital,
				"ally": allies.has(inv.id), "coerced": Market.is_investor_coerced(inv.id),
				"target": Market.get_quarterly_target()})
	return out


## Calendario sin la cotización diaria (ruido): [{day, name, periodicity, results}].
static func calendar_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in Market.get_calendar(Database.get_balance_int(B_CALENDAR_DAYS)):
		if str(ev.get("periodicity", "")) == DAILY_EVENT:
			continue
		out.append({"day": int(ev["day"]), "name": UITheme.trf(str(ev["name_key"])),
				"periodicity": str(ev["periodicity"]), "results": int(ev["day"]) == Market.get_presentation_day()})
	return out


## Noticias que el jugador ya conoce (R25+; R28+ añade el sentido de los resultados).
static func news_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var headlines: Array[String] = Market.get_upcoming_news(news_days())
	var directions: Array[int] = Market.get_upcoming_news_directions(news_days())
	for i: int in headlines.size():
		out.append({"headline": UITheme.trf(headlines[i]),
				"direction": directions[i] if i < directions.size() else 0})
	return out


static func portfolio() -> Dictionary:
	var shares: int = Market.get_player_shares()
	var value: float = Market.get_portfolio_value()
	var invested: float = Market.get_invested_capital()
	return {"shares": shares, "value": value, "invested": invested, "gain": value - invested,
			"cash": Market.get_broker_cash(), "wallet": PlayerState.get_money(),
			"dividend": Market.get_dividend_income(), "votes": Market.get_board_votes(),
			"stake": Market.has_board_stake(), "stake_price": Market.get_board_stake_price(),
			"stake_rank": stake_min_rank(), "pattern": Market.get_insider_pattern_score(),
			"pattern_limit": Database.get_balance_float(B_INSIDER_THRESHOLD)}


# ═══ Ventana ══════════════════════════════════════════════════════════

static func open(host: Node, context: Dictionary = {}) -> MarketApp:
	var app: MarketApp = MarketApp.new()
	app.set_standalone(true)
	app.setup(context)
	if host is UIRoot:
		app._in_ui_root = true
		(host as UIRoot).open_modal(app, false)
	elif host != null:
		host.add_child(app)
	return app


func get_title_key() -> String:
	return TITLE_KEY


func set_standalone(on: bool) -> void:
	_standalone = on


func set_embedded(on: bool) -> void:
	_embedded = on


func request_close() -> void:
	close_requested.emit()
	if _standalone and not _in_ui_root:
		queue_free()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	if not _built:
		setup(context)
	refresh.call_deferred()
	EventBus.stock_price_updated.connect(_on_price_updated)
	EventBus.investor_confidence_changed.connect(_on_confidence_changed)
	EventBus.money_changed.connect(_on_money_changed)


func _draw() -> void:
	if _standalone and not _embedded:
		Kit.draw_desktop(self, Rect2(Vector2.ZERO, size))


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		refresh()


func _on_price_updated(_price: float, _delta_percent: float) -> void:
	_dirty = true


func _on_confidence_changed(_investor_id: String, _old_value: int, _new_value: int) -> void:
	_dirty = true


func _on_money_changed(_old_value: int, _new_value: int, _reason: String) -> void:
	_dirty = true


## OSApp: construye la interfaz (o el aviso de acceso denegado por debajo del rango mínimo).
func build() -> void:
	Kit.use(pal, int(context.get("base", 0)))
	theme = Kit.build_theme()
	_build_content()
	_built = true
	refresh()


func _build_content() -> void:
	var body: Control = _frame()
	if not is_available():
		body.add_child(_denied())
		return
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(0.4))
	body.add_child(col)
	_ticker = Ticker.new()
	col.add_child(_ticker)
	var middle: HBoxContainer = HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", Kit.px(0.4))
	_chart = PriceChart.new()
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(_chart)
	_investors = _panel(middle, "MARKET_SEC_INVESTORS", Kit.px(SIDE_EM))
	col.add_child(middle)
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", Kit.px(0.4))
	bottom.custom_minimum_size.y = Kit.px(13.5)
	_calendar = _panel(bottom, "MARKET_SEC_CALENDAR", 0)
	_portfolio = _panel(bottom, "MARKET_SEC_PORTFOLIO", 0)
	_news = _panel(bottom, "MARKET_SEC_NEWS", 0)
	col.add_child(bottom)


func _frame() -> Control:
	if _standalone and not _embedded:
		_window = Kit.make_window(self, tr(TITLE_KEY), ICON)
		_window.close_pressed.connect(request_close)
		_frame_root = _window
		return _window.body
	_frame_root = Kit.make_holder(self)
	return _frame_root


func _rebuild_content() -> void:
	if _frame_root != null:
		remove_child(_frame_root)
		_frame_root.queue_free()
	_window = null
	_ticker = null
	_build_content()


func _panel(parent: HBoxContainer, title_key: String, width: int) -> VBoxContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.theme_type_variation = Kit.V_PAPER
	if width > 0:
		frame.custom_minimum_size.x = width
	else:
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(0.25))
	frame.add_child(box)
	var head: PersonnelApp.SectionHead = PersonnelApp.SectionHead.new()
	head.text = tr(title_key)
	box.add_child(head)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", Kit.px(0.2))
	box.add_child(content)
	return content


func _denied() -> Control:
	var center: CenterContainer = CenterContainer.new()
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	box.add_child(Kit.label(tr("MARKET_DENIED_TITLE"), Kit.V_BIG))
	box.add_child(Kit.label(tr("MARKET_DENIED_BODY") % min_rank(), Kit.V_BODY))
	return center


## Vuelve a leer Market y repinta la ventana (la reconstruye si el acceso cambió con el rango).
func refresh() -> void:
	if not _built:
		return
	if (_ticker != null) != is_available():
		_rebuild_content()
	if not is_available():
		return
	var snap: Dictionary = snapshot()
	_ticker.snap = snap
	_ticker.queue_redraw()
	_chart.history = snap["history"]
	_chart.price = float(snap["price"])
	_chart.queue_redraw()
	_fill_investors(snap["investors"])
	_fill_calendar(snap["calendar"])
	_fill_portfolio(snap["portfolio"])
	_fill_news(snap["news"], snap["portfolio"])
	Kit.show_status(self, _window, [tr("MARKET_STATUS_WALLET") % UITheme.format_money(PlayerState.get_money()),
			tr("MARKET_STATUS_SHARES") % Market.get_player_shares(),
			tr("PERS_STATUS_CLOCK") % [GameClock.get_day(), GameClock.get_time_string()]])


func _clear(box: VBoxContainer) -> void:
	for child: Node in box.get_children():
		child.queue_free()


func _fill_investors(rows: Array) -> void:
	_clear(_investors)
	for row: Dictionary in rows:
		var line: InvestorRow = InvestorRow.new()
		line.data = row
		line.appearance = investor_appearance(str(row["id"]))
		_investors.add_child(line)


## Apariencia estable de un inversor (no son personajes de NPCDirector).
static func investor_appearance(investor_id: String) -> Dictionary:
	return CharacterPainter.appearance_from_seed(absi(hash(investor_id)),
			Database.get_balance_int(B_INVESTOR_TIER), false, "")


func _fill_calendar(rows: Array) -> void:
	_clear(_calendar)
	if rows.is_empty():
		_calendar.add_child(Kit.label(tr("MARKET_CALENDAR_EMPTY"), Kit.V_SMALL))
	for row: Dictionary in rows:
		var line: HBoxContainer = Kit.field_row(tr("PORTAL_DAY_FMT") % int(row["day"]), str(row["name"]),
				Kit.V_STRONG if bool(row["results"]) else Kit.V_BODY)
		if bool(row["results"]):
			(line.get_child(1) as Label).add_theme_color_override("font_color", Kit.green())
		_calendar.add_child(line)


func _fill_portfolio(p: Dictionary) -> void:
	_clear(_portfolio)
	var rows: Array[Array] = [
		["MARKET_SHARES", str(int(p["shares"]))],
		["MARKET_VALUE", UITheme.format_money(roundi(float(p["value"])))],
		["MARKET_GAIN", UITheme.format_signed_money(roundi(float(p["gain"])))],
		["MARKET_DIVIDEND", UITheme.format_money(int(p["dividend"]))],
		["MARKET_VOTES", str(int(p["votes"]))],
	]
	for row: Array in rows:
		_portfolio.add_child(Kit.field_row(tr(row[0]), str(row[1]), Kit.V_MONO))
	if int(p["cash"]) > 0:
		_portfolio.add_child(_cash_row(int(p["cash"])))
	_portfolio.add_child(_order_row())
	_portfolio.add_child(_stake_row(p))


func _order_row() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", Kit.px(0.25))
	_qty_edit = LineEdit.new()
	_qty_edit.text = str(_quantity)
	_qty_edit.custom_minimum_size.x = Kit.px(4.5)
	_qty_edit.text_submitted.connect(func(text: String) -> void: set_quantity(text.to_int()))
	line.add_child(_qty_edit)
	var lots: Variant = Database.get_balance(B_LOTS)
	for lot: Variant in (lots if lots is Array else []):
		var add: Button = Kit.button("+%d" % int(lot))
		add.pressed.connect(func() -> void: set_quantity(_quantity + int(lot)))
		line.add_child(add)
	box.add_child(line)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", Kit.px(0.25))
	var buy_btn: Button = Kit.button(tr("MARKET_BUY") % UITheme.format_money(Market.get_buy_cost(_quantity)),
			"plus", Kit.V_PRIMARY)
	buy_btn.disabled = _quantity <= 0
	buy_btn.pressed.connect(buy)
	var sell_btn: Button = Kit.button(tr("MARKET_SELL"), "arrow")
	sell_btn.disabled = _quantity <= 0 or _quantity > Market.get_player_shares()
	sell_btn.pressed.connect(sell)
	actions.add_child(buy_btn)
	actions.add_child(sell_btn)
	box.add_child(actions)
	return box


## Cuenta de valores (ventas y dividendos de la junta anual): retirar al bolsillo.
func _cash_row(cash: int) -> Control:
	var row: HBoxContainer = Kit.field_row(tr("MARKET_BROKER_CASH"), UITheme.format_money(cash), Kit.V_MONO)
	var withdraw: Button = Kit.button(tr("MARKET_WITHDRAW"), "cash")
	withdraw.pressed.connect(collect_cash)
	row.add_child(withdraw)
	return row


## Retira todo el efectivo de la cuenta de valores (MarketTrading). Devuelve el importe.
func collect_cash() -> int:
	var amount: int = MarketTrading.collect_broker_cash()
	refresh()
	return amount


func _stake_row(p: Dictionary) -> Control:
	if bool(p["stake"]):
		return Kit.wrap_label(tr("MARKET_STAKE_OWNED"), Kit.V_STRONG)
	if PlayerState.get_rank() < int(p["stake_rank"]):
		return Kit.wrap_label(tr("MARKET_STAKE_LOCKED") % int(p["stake_rank"]), Kit.V_SMALL)
	var btn: Button = Kit.button(tr("MARKET_STAKE_BUY") % UITheme.format_money(int(p["stake_price"])),
			"star", Kit.V_DANGER)
	btn.pressed.connect(buy_stake)
	return btn


func _fill_news(rows: Array, p: Dictionary) -> void:
	_clear(_news)
	_news.add_child(Kit.wrap_label(tr("MARKET_NEWS_INTRO"), Kit.V_SMALL))
	if rows.is_empty():
		_news.add_child(Kit.label(tr("MARKET_NEWS_NONE"), Kit.V_NOTE))
	for row: Dictionary in rows:
		var line: NewsRow = NewsRow.new()
		line.headline = str(row["headline"])
		line.direction = int(row["direction"])
		_news.add_child(line)
	var meter: PatternMeter = PatternMeter.new()
	meter.value = float(p["pattern"])
	meter.limit = float(p["pattern_limit"])
	_news.add_child(meter)


# ─── Órdenes ──────────────────────────────────────────────────────────

func set_quantity(value: int) -> void:
	_quantity = maxi(value, 0)
	if _built and is_available():
		_fill_portfolio(portfolio())


func get_quantity() -> int:
	return _quantity


## Compra la cantidad de la orden (con confirmación si sería privilegiada, §9.8).
func buy() -> void:
	_order(ACTION_BUY, Market.is_trade_informed(MarketSystem.TRADE_BUY))


func sell() -> void:
	_order(ACTION_SELL, Market.is_trade_informed(MarketSystem.TRADE_SELL))


## Paquete accionarial R30 (~250.000 €): siempre con confirmación (irreversible, §13.7).
func buy_stake() -> void:
	_order(ACTION_STAKE, true)


func _order(action: String, needs_confirmation: bool) -> void:
	if needs_confirmation:
		_pending = action
		_show_confirm()
	else:
		_execute(action)


func has_pending_confirmation() -> bool:
	return not _pending.is_empty()


func confirm_pending() -> bool:
	var action: String = _pending
	cancel_pending()
	return _execute(action) if not action.is_empty() else false


func cancel_pending() -> void:
	_pending = ""
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = null


func get_last_result() -> bool:
	return _last_result


func _execute(action: String) -> bool:
	match action:
		ACTION_BUY:
			_last_result = MarketTrading.buy(_quantity)
		ACTION_SELL:
			_last_result = MarketTrading.sell(_quantity)
		ACTION_STAKE:
			_last_result = MarketTrading.buy_board_stake()
		_:
			_last_result = false
	refresh()
	return _last_result


func _show_confirm() -> void:
	var stake: bool = _pending == ACTION_STAKE
	var body: String = tr("MARKET_CONFIRM_STAKE") % UITheme.format_money(Market.get_board_stake_price()) \
			if stake else tr("MARKET_CONFIRM_INSIDER")
	_confirm = PortalApp.ConfirmOverlay.make(tr("MARKET_CONFIRM_TITLE"), body, tr("MARKET_CONFIRM_YES"),
			tr("UI_CANCEL"))
	_confirm.connect("answered", func(yes: bool) -> void:
		if yes:
			confirm_pending()
		else:
			cancel_pending())
	add_child(_confirm)


# ═══ Piezas dibujadas ═════════════════════════════════════════════════

## Cinta de cotización: símbolo, precio, variación, confianza agregada frente al objetivo.
class Ticker extends Control:
	var snap: Dictionary = {}

	func _init() -> void:
		custom_minimum_size.y = Kit.px(3.6)

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		Kit.draw_bevel(self, r, PriceChart.SCREEN, true)
		if snap.is_empty():
			return
		var big: int = Kit.px(2.0)
		var base: float = size.y * 0.5 + big * 0.36
		var x: float = float(Kit.px(0.8))
		x = _segment(x, base, TranslationServer.translate("MARKET_SYMBOL"), Kit.font_black(), big, PriceChart.AMBER_INK)
		x = _segment(x, base, "%.2f" % float(snap["price"]), Kit.font_mono(), big, PriceChart.GREEN_INK)
		var change: float = float(snap["change"]) * 100.0
		var up: bool = change >= 0.0
		x = _segment(x, base, ("▲ %+.2f%%" if up else "▼ %+.2f%%") % change, Kit.font_mono(), Kit.px(1.1),
				PriceChart.GREEN_INK if up else PriceChart.RED_INK)
		_draw_gauge(Rect2(x + Kit.px(0.6), size.y * 0.2, size.x - x - Kit.px(1.4), size.y * 0.6))

	## Dibuja un tramo de la cinta y devuelve la x siguiente.
	func _segment(x: float, base: float, value: String, font: Font, fsize: int, color: Color) -> float:
		draw_string(font, Vector2(x, base), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
		return x + font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + Kit.px(1.2)

	func _draw_gauge(r: Rect2) -> void:
		var fsize: int = Kit.px(0.72)
		var aggregate: float = float(snap["aggregate"])
		var target: float = float(snap["target"])
		var label: String = TranslationServer.translate("MARKET_CONFIDENCE_FMT") % [aggregate, target,
				int(snap["quarter"])]
		Kit.text(self, Vector2(r.position.x, r.position.y + fsize), label,
				Kit.font_bold(), fsize, PriceChart.AMBER_INK, r.size.x)
		var bar: Rect2 = Rect2(r.position.x, r.position.y + fsize * 1.6, r.size.x, r.size.y - fsize * 1.6)
		draw_rect(bar, PriceChart.GRID)
		var fill: Color = PriceChart.GREEN_INK if aggregate >= target else PriceChart.RED_INK
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(aggregate / 100.0, 0.0, 1.0), bar.size.y)), fill)
		var tx: float = bar.position.x + bar.size.x * clampf(target / 100.0, 0.0, 1.0)
		draw_line(Vector2(tx, bar.position.y - 4), Vector2(tx, bar.end.y + 4), PriceChart.AMBER_INK, 3.0)


## Gráfico de cotización estilo terminal bursátil (fósforo verde) con rejilla y último precio.
class PriceChart extends Control:
	const SCREEN := Color("#0f1d19")
	const GRID := Color("#20382f")
	const GREEN_INK := Color("#62f29a")
	const RED_INK := Color("#ff6b5b")
	const AMBER_INK := Color("#ffc857")
	const GRID_LINES := 5

	var history: Array[float] = []
	var price: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(Kit.px(20.0), Kit.px(12.0))

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		Kit.draw_bevel(self, r, SCREEN, true)
		var plot: Rect2 = Rect2(Kit.px(0.8), Kit.px(1.8), size.x - Kit.px(5.6), size.y - Kit.px(3.4))
		var fsize: int = Kit.px(0.72)
		Kit.text(self, Vector2(Kit.px(0.8), Kit.px(1.2)),
				TranslationServer.translate("MARKET_CHART_TITLE") % maxi(history.size(), 1),
				Kit.font_mono(), fsize, AMBER_INK, size.x)
		var points: Array[float] = history.duplicate()
		points.append(price)
		var lo: float = points.min()
		var hi: float = points.max()
		var pad: float = maxf((hi - lo) * 0.15, hi * 0.01)
		lo -= pad
		hi += pad
		_draw_grid(plot, lo, hi, fsize)
		_draw_series(plot, points, lo, hi)

	func _draw_grid(plot: Rect2, lo: float, hi: float, fsize: int) -> void:
		for i: int in GRID_LINES + 1:
			var t: float = float(i) / GRID_LINES
			var y: float = plot.end.y - plot.size.y * t
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1.0)
			Kit.text(self, Vector2(plot.end.x + 6, y + fsize * 0.35), "%.2f" % lerpf(lo, hi, t),
					Kit.font_mono(), fsize, Color(GREEN_INK, 0.6), -1.0)
		for i: int in GRID_LINES * 2 + 1:
			var x: float = plot.position.x + plot.size.x * float(i) / (GRID_LINES * 2)
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(GRID, 0.6), 1.0)

	func _draw_series(plot: Rect2, points: Array[float], lo: float, hi: float) -> void:
		var n: int = points.size()
		var line: PackedVector2Array = PackedVector2Array()
		for i: int in n:
			var x: float = plot.position.x + (plot.size.x * float(i) / float(maxi(n - 1, 1)))
			var y: float = plot.end.y - plot.size.y * inverse_lerp(lo, hi, points[i])
			line.append(Vector2(x, y))
		if n == 1:
			line.append(line[0] + Vector2(plot.size.x, 0))
		var area: PackedVector2Array = line.duplicate()
		area.append(Vector2(line[line.size() - 1].x, plot.end.y))
		area.append(Vector2(line[0].x, plot.end.y))
		draw_colored_polygon(area, Color(GREEN_INK, 0.12))
		draw_polyline(line, Color(GREEN_INK, 0.35), 7.0, true)
		draw_polyline(line, GREEN_INK, 3.0, true)
		var last: Vector2 = line[line.size() - 1]
		draw_circle(last, 7.0, SCREEN)
		draw_circle(last, 5.0, AMBER_INK)


## Fila de inversor: foto, nombre, estrategia, confianza (0–100) y marca de aliado.
class InvestorRow extends Control:
	var data: Dictionary = {}
	var appearance: Dictionary = {}

	func _init() -> void:
		custom_minimum_size.y = Kit.px(2.9)

	func _draw() -> void:
		var photo: Rect2 = Rect2(0, Kit.px(0.2), size.y - Kit.px(0.4), size.y - Kit.px(0.4))
		CharacterPainter.draw_portrait(self, appearance, photo)
		draw_rect(photo, Kit.ink(), false, 1.5)
		var x: float = photo.end.x + Kit.px(0.4)
		var w: float = size.x - x
		Kit.text(self, Vector2(x, Kit.px(1.1)), str(data.get("name", "")),
				Kit.font_bold(), Kit.px(0.9), Kit.ink(), w * 0.62)
		Kit.text(self, Vector2(x + w * 0.62, Kit.px(1.1)), str(data.get("strategy_name", "")),
				Kit.font_regular(), Kit.px(0.72), Kit.soft(), w * 0.38,
				HORIZONTAL_ALIGNMENT_RIGHT)
		var bar: Rect2 = Rect2(x, Kit.px(1.5), w - Kit.px(2.4), Kit.px(0.85))
		Kit.draw_bevel(self, bar, Kit.field(), true)
		var confidence: int = int(data.get("confidence", 0))
		var target: float = float(data.get("target", 0.0))
		var fill: Color = Kit.green() if confidence >= target else Kit.red()
		draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * confidence / 100.0, bar.size.y - 4)), fill)
		Kit.text(self, Vector2(bar.end.x + Kit.px(0.3), bar.end.y - 2), str(confidence),
				Kit.font_mono(), Kit.px(0.85), Kit.ink(), Kit.px(2.0))
		if bool(data.get("ally", false)):
			UITheme.draw_icon(self, "check", Rect2(photo.end.x - Kit.px(0.9), photo.end.y - Kit.px(0.9),
					Kit.px(0.9), Kit.px(0.9)), Kit.green(), 2.5)


## Titular anticipado con flecha de sentido.
class NewsRow extends Control:
	var headline: String = ""
	var direction: int = 0

	func _init() -> void:
		custom_minimum_size.y = Kit.px(1.6)

	func _draw() -> void:
		var color: Color = Kit.green() if direction > 0 else (Kit.red() if direction < 0
				else Kit.ink_soft())
		var glyph: String = "▲" if direction > 0 else ("▼" if direction < 0 else "■")
		var fsize: int = Kit.px(0.82)
		Kit.text(self, Vector2(0, size.y * 0.5 + fsize * 0.36), glyph, Kit.font_black(),
				fsize, color, -1.0)
		Kit.text(self, Vector2(Kit.px(1.1), size.y * 0.5 + fsize * 0.36), headline,
				Kit.font_regular(), fsize, Kit.ink(), size.x - Kit.px(1.1))


## Medidor del patrón de operaciones privilegiadas frente al umbral de investigación (§9.8).
class PatternMeter extends Control:
	var value: float = 0.0
	var limit: float = 1.0

	func _init() -> void:
		custom_minimum_size.y = Kit.px(2.2)

	func _draw() -> void:
		var fsize: int = Kit.px(0.7)
		Kit.text(self, Vector2(0, fsize), TranslationServer.translate("MARKET_PATTERN"),
				Kit.font_black(), fsize, Kit.red(), size.x)
		var bar: Rect2 = Rect2(0, fsize * 1.5, size.x, size.y - fsize * 1.7)
		Kit.draw_bevel(self, bar, Kit.field(), true)
		var ratio: float = clampf(value / maxf(limit, 0.001), 0.0, 1.0)
		draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * ratio, bar.size.y - 4)),
				Kit.red().lerp(Kit.amber(), 1.0 - ratio))
		Kit.draw_hatch(self, Rect2(bar.end.x - Kit.px(1.0), bar.position.y, Kit.px(1.0) - 2,
				bar.size.y), Kit.red(), 6.0, 2.0)
