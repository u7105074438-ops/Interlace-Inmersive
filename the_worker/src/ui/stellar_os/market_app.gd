# market_app.gd — MARKET de StellarOS (desde R25): cotización e histórico, calendario de resultados, inversores con su confianza y los tratos con ellos (soplo, soborno, chantaje, campaña), cartera (compra/venta), noticias anticipadas (R25/R28) y paquete accionarial R30 con confirmación (§13.3, §9.3–§9.11, PASO 25 y 34).
# PROPIETARIO DE: el estado de la ventana (cantidad de la orden, operación o trato pendiente de confirmar, último aviso y vista compacta).
# ESCUCHA: stock_price_updated, investor_confidence_changed, money_changed (solo mientras está abierta, para refrescar).
class_name MarketApp
extends OSApp

## API pública: is_available() (rango ≥ shares.player_trading_min_rank de market.json),
## snapshot() -> Dictionary con todo lo que pinta la ventana, open(host, context).
## Tratos con inversores (también los usa la pantalla de resultados): investor_actions(id) ->
## [{id, enabled, price|payment|leverage|targets}], perform_investor_action(id, acción, objetivo)
## -> {ok, text}; acciones ACT_TIP (MarketTrading.sell_tip), ACT_BRIBE
## (ResultsPresentation.bribe_investor por teléfono, precio = investor_bribe_price), ACT_BLACKMAIL
## (ResultsPresentation.blackmail_investor con un objeto de presentacion_ui.objetos_chantaje_inversor)
## y ACT_CAMPAIGN (Market.direct_activist contra quien ocupa uno de tus próximos puestos).
## Ventana: set_quantity(n), buy(), sell(), buy_stake(), request_investor_action(id, acción,
## objetivo), has_pending_confirmation(), confirm_pending(), cancel_pending(), get_notice().
## DECISIONES: el efectivo lo mueve MarketTrading (Market no toca PlayerState). Toda operación
## que Market.is_trade_informed() marca como privilegiada (§9.8), la compra del paquete R30 (§9.11)
## y todo trato con un inversor piden confirmación explícita (§13.7); las demás órdenes se
## ejecutan al pulsar. Cada orden o trato deja un aviso (éxito o motivo del rechazo). El medidor del
## patrón privilegiado es DIFUSO (tres tramos, mercado_ui.tramos_patron): la cifra real incluye la
## perspicacia oculta del Auditor Jefe. Colores del terminal: mercado_ui.colores_terminal (datos;
## en alto contraste, los de UITheme). Por debajo del rango mínimo la ventana muestra «acceso
## denegado» (la carcasa oculta el icono con is_available()). Vista compacta (móvil): todo apilado
## en un desplazamiento vertical.

const APP_ID := "market"
const TITLE_KEY := "MARKET_APP_TITLE"
const ICON := "market"
const Kit := PersonnelApp.OsKit
const B_CHART_DAYS := "mercado_ui.dias_grafico"
const B_CALENDAR_DAYS := "mercado_ui.dias_calendario"
const B_LOTS := "mercado_ui.lotes"
const B_PATTERN_BANDS := "mercado_ui.tramos_patron"
const B_TERMINAL := "mercado_ui.colores_terminal"
const B_INSIDER_THRESHOLD := "mercado.umbral_patron_insider"
const B_INVESTOR_TIER := "presentacion_ui.escalon_inversor"
const B_LEVERAGE_ITEMS := "presentacion_ui.objetos_chantaje_inversor"
const ACTION_BUY := "buy"
const ACTION_SELL := "sell"
const ACTION_STAKE := "stake"
const ACT_TIP := "tip"
const ACT_BRIBE := "bribe"
const ACT_BLACKMAIL := "blackmail"
const ACT_CAMPAIGN := "campaign"
const DAILY_EVENT := "daily"
const QUARTERLY_EVENT := "quarterly"
const STRATEGY_ACTIVIST := "activist"
## Maquetación (em): columna de inversores, alto de la fila inferior y ancho de la vista compacta.
const SIDE_EM := 25.0
const BOTTOM_EM := 13.5
const COMPACT_EM := 64.0

var _standalone: bool = false
var _in_ui_root: bool = false
var _embedded: bool = false
var _built: bool = false
var _dirty: bool = false
var _compact: bool = false
var _quantity: int = 0
var _pending: String = ""
var _pending_deal: Dictionary = {}
var _last_result: bool = false
var _notice: String = ""
var _notice_ok: bool = true
var _window: PersonnelApp.OsWindow
var _frame_root: Control
var _ticker: Ticker
var _chart: PriceChart
var _investors: VBoxContainer
var _calendar: VBoxContainer
var _portfolio: VBoxContainer
var _news: VBoxContainer
var _pf_values: Dictionary = {}
var _cash_box: HBoxContainer
var _cash_label: Label
var _qty_edit: LineEdit
var _buy_btn: Button
var _sell_btn: Button
var _stake_box: VBoxContainer
var _notice_label: Label
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
				"campaign": PersonnelApp.other_name(Market.get_activist_target(inv.id))
						if not Market.get_activist_target(inv.id).is_empty() else "",
				"target": Market.get_quarterly_target()})
	return out


static func _calendar_horizon() -> int:
	var calendar: Variant = Database.get_market_params().get("calendar", {})
	var year: int = int((calendar as Dictionary).get("days_per_fiscal_year", 0)) if calendar is Dictionary else 0
	return maxi(Database.get_balance_int(B_CALENDAR_DAYS), year)


## Próxima cita de cada evento del calendario (sin la cotización diaria):
## [{day, in_days, id, name, periodicity, results}]; results = solo la presentación trimestral.
static func calendar_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var today: int = Market.get_current_day()
	for ev: Dictionary in Market.get_calendar(_calendar_horizon()):
		var periodicity: String = str(ev.get("periodicity", ""))
		var event_id: String = str(ev.get("id", ""))
		if periodicity == DAILY_EVENT or seen.has(event_id):
			continue
		seen[event_id] = true
		out.append({"day": int(ev["day"]), "in_days": int(ev["day"]) - today, "id": event_id,
				"name": UITheme.trf(str(ev["name_key"])), "periodicity": periodicity,
				"results": periodicity == QUARTERLY_EVENT})
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
			"stake_rank": stake_min_rank(), "pattern_band": pattern_band()}


## Tramo DIFUSO del patrón privilegiado (0 tranquilo · 1 llama la atención · 2 en el punto de mira).
static func pattern_band() -> int:
	var limit: float = maxf(Database.get_balance_float(B_INSIDER_THRESHOLD), 0.001)
	var ratio: float = Market.get_insider_pattern_score() / limit
	var band: int = 0
	var bands: Variant = Database.get_balance(B_PATTERN_BANDS)
	for edge: Variant in (bands if bands is Array else []):
		if ratio >= float(edge):
			band += 1
	return band


# ═══ Tratos con los inversores (§9.5–§9.8) ═════════════════════════════

## Material de chantaje que lleva el jugador ("" si ninguno).
static func leverage_item() -> String:
	var items: Variant = Database.get_balance(B_LEVERAGE_ITEMS)
	for item_id: Variant in (items if items is Array else []):
		if PlayerState.has_item(str(item_id)):
			return str(item_id)
	return ""


## Rivales contra los que se puede dirigir a la activista: quienes ocupan tus próximos puestos.
static func campaign_targets() -> Array[String]:
	var out: Array[String] = []
	var wanted: Array[String] = Company.get_promotion_targets()
	for seat: Dictionary in Company.get_all_seats():
		var holder: String = str(seat.get("holder", ""))
		if wanted.has(str(seat.get("occupation_id", ""))) and not holder.is_empty() \
				and holder != PLAYER_ID and not out.has(holder):
			out.append(holder)
	return out


## Tratos posibles con un inversor: [{id, enabled, …}] (soplo, soborno, chantaje, campaña).
static func investor_actions(investor_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Market.accepts_tips(investor_id):
		out.append({"id": ACT_TIP, "enabled": true, "payment": Market.get_tip_payment(investor_id)})
	if Market.is_investor_bribable(investor_id) and not Market.is_investor_ally(investor_id):
		var price: int = ResultsPresentation.investor_bribe_price(investor_id)
		out.append({"id": ACT_BRIBE, "enabled": PlayerState.can_afford(price), "price": price})
	if Market.is_investor_blackmailable(investor_id) and not Market.is_investor_coerced(investor_id):
		out.append({"id": ACT_BLACKMAIL, "enabled": not leverage_item().is_empty(),
				"leverage": leverage_item()})
	var inv: InvestorData = Market.get_investor(investor_id)
	if inv != null and inv.strategy == STRATEGY_ACTIVIST and Market.is_investor_coerced(investor_id) \
			and Market.get_activist_target(investor_id).is_empty():
		var targets: Array[String] = campaign_targets()
		out.append({"id": ACT_CAMPAIGN, "enabled": not targets.is_empty(), "targets": targets})
	return out


## Texto del botón o entrada de menú de un trato.
static func action_label(action: Dictionary) -> String:
	match str(action["id"]):
		ACT_TIP:
			return UITheme.trf("MARKET_ACT_TIP", [UITheme.format_money(int(action["payment"]))])
		ACT_BRIBE:
			return UITheme.trf("MARKET_ACT_BRIBE", [UITheme.format_money(int(action["price"]))])
		ACT_BLACKMAIL:
			return UITheme.trf("MARKET_ACT_BLACKMAIL" if bool(action["enabled"]) else "MARKET_ACT_NO_LEVERAGE")
	return UITheme.trf("MARKET_ACT_CAMPAIGN")


## Texto de la confirmación de un trato (todos son irreversibles y dejan rastro).
static func action_confirm_text(investor_id: String, action: String, target: String) -> String:
	var inv: InvestorData = Market.get_investor(investor_id)
	var who: String = inv.name if inv != null else investor_id
	match action:
		ACT_TIP:
			return UITheme.trf("MARKET_CONFIRM_TIP", [who, UITheme.format_money(Market.get_tip_payment(investor_id))])
		ACT_BRIBE:
			return UITheme.trf("MARKET_CONFIRM_BRIBE", [who,
					UITheme.format_money(ResultsPresentation.investor_bribe_price(investor_id))])
		ACT_BLACKMAIL:
			var item: ItemData = Database.get_item(leverage_item())
			return UITheme.trf("MARKET_CONFIRM_BLACKMAIL", [UITheme.trf(item.name_key) if item != null else "", who])
	return UITheme.trf("MARKET_CONFIRM_CAMPAIGN", [who, PersonnelApp.other_name(target)])


## Personajes en la misma sala que el jugador: oyen la llamada del soborno (canal phone_call).
static func room_listeners() -> Array[String]:
	var out: Array[String] = []
	var room: String = PlayerState.get_room()
	for npc: NPCRuntime in NPCDirector.get_npcs_near(room):
		if npc.current_room == room:
			out.append(npc.id)
	return out


## Ejecuta un trato YA confirmado. {ok, text} (text = aviso para el jugador).
static func perform_investor_action(investor_id: String, action: String, target: String = "") -> Dictionary:
	var inv: InvestorData = Market.get_investor(investor_id)
	if inv == null:
		return {"ok": false, "text": ""}
	match action:
		ACT_TIP:
			var tip: Dictionary = MarketTrading.sell_tip(investor_id)
			if not bool(tip.get("ok", false)):
				return {"ok": false, "text": UITheme.trf("MARKET_MSG_TIP_FAIL", [inv.name])}
			return {"ok": true, "text": UITheme.trf("MARKET_MSG_TIP_OK",
					[inv.name, UITheme.format_money(int(tip.get("paid", 0))), int(tip.get("delta", 0))])}
		ACT_BRIBE:
			var offer: Dictionary = ResultsPresentation.bribe_investor(investor_id,
					ResultsPresentation.investor_bribe_price(investor_id), Bribery.CHANNEL_PHONE_CALL,
					{"listeners": room_listeners()})
			return {"ok": bool(offer.get("accepted", false)), "text": UITheme.trf("MARKET_MSG_DEAL_FMT",
					[inv.name, UITheme.trf(str(offer.get("text_key", "BRIBE_OUTCOME_INVALID")))])}
		ACT_BLACKMAIL:
			var coerced: bool = ResultsPresentation.blackmail_investor(investor_id, leverage_item())
			return {"ok": coerced, "text": UITheme.trf("MARKET_MSG_BLACKMAIL_OK" if coerced
					else "MARKET_MSG_BLACKMAIL_FAIL", [inv.name])}
		ACT_CAMPAIGN:
			var aimed: bool = Market.direct_activist(investor_id, target)
			return {"ok": aimed, "text": UITheme.trf("MARKET_MSG_CAMPAIGN_OK" if aimed
					else "MARKET_MSG_CAMPAIGN_FAIL", [inv.name, PersonnelApp.other_name(target)])}
	return {"ok": false, "text": ""}


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
	_update_layout.call_deferred()
	EventBus.stock_price_updated.connect(_on_price_updated)
	EventBus.investor_confidence_changed.connect(_on_confidence_changed)
	EventBus.money_changed.connect(_on_money_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()


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


func is_compact() -> bool:
	return _compact


func _update_layout() -> void:
	if not _built:
		return
	var compact: bool = size.x > 0.0 and size.x < Kit.px(COMPACT_EM)
	if compact != _compact:
		_compact = compact
		_rebuild_content()
		refresh()


func _build_content() -> void:
	var body: Control = _frame()
	if not is_available():
		body.add_child(_denied())
		return
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(0.4))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _compact:
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(scroll)
		scroll.add_child(col)
	else:
		body.add_child(col)
	_ticker = Ticker.new()
	col.add_child(_ticker)
	var middle: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", Kit.px(0.4))
	_chart = PriceChart.new()
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(_chart)
	_investors = _panel(middle, "MARKET_SEC_INVESTORS", 0 if _compact else Kit.px(SIDE_EM), true)
	col.add_child(middle)
	var bottom: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	bottom.add_theme_constant_override("separation", Kit.px(0.4))
	bottom.custom_minimum_size.y = 0 if _compact else Kit.px(BOTTOM_EM)
	_calendar = _panel(bottom, "MARKET_SEC_CALENDAR", 0, false)
	_portfolio = _panel(bottom, "MARKET_SEC_PORTFOLIO", 0, false)
	_build_portfolio()
	_news = _panel(bottom, "MARKET_SEC_NEWS", 0, false)
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
	_qty_edit = null
	_build_content()


## Panel con cabecera. `scroll`: el contenido se desplaza (lista de inversores con sus tratos).
func _panel(parent: BoxContainer, title_key: String, width: int, scroll: bool) -> VBoxContainer:
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
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", Kit.px(0.2))
	if scroll and not _compact:
		var holder: ScrollContainer = ScrollContainer.new()
		holder.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(holder)
		holder.add_child(content)
	else:
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
	Kit.use(pal, int(context.get("base", 0)))
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
	_update_portfolio(snap["portfolio"])
	_fill_news(snap["news"], snap["portfolio"])
	Kit.show_status(self, _window, [tr("MARKET_STATUS_WALLET") % UITheme.format_money(PlayerState.get_money()),
			tr("MARKET_STATUS_SHARES") % Market.get_player_shares(),
			tr("PERS_STATUS_CLOCK") % [GameClock.get_day(), GameClock.get_time_string()]])


func _clear(box: VBoxContainer) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


## Fila por inversor: retrato, confianza y (si hay tratos posibles) el menú «Tratos».
func _fill_investors(rows: Array) -> void:
	_clear(_investors)
	for row: Dictionary in rows:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", Kit.px(0.3))
		var item: InvestorRow = InvestorRow.new()
		item.data = row
		item.appearance = investor_appearance(str(row["id"]))
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(item)
		line.add_child(_deals_menu(str(row["id"]), investor_actions(str(row["id"]))))
		_investors.add_child(line)


func _deals_menu(investor_id: String, actions: Array[Dictionary]) -> MenuButton:
	var menu: MenuButton = MenuButton.new()
	menu.text = tr("MARKET_DEALS")
	menu.flat = false
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.disabled = actions.is_empty()
	menu.tooltip_text = tr("MARKET_DEALS_NONE") if actions.is_empty() else tr("MARKET_DEALS_TIP")
	var popup: PopupMenu = menu.get_popup()
	var entries: Array[Array] = []
	for action: Dictionary in actions:
		if str(action["id"]) == ACT_CAMPAIGN:
			for target: String in action["targets"]:
				popup.add_item(tr("MARKET_ACT_CAMPAIGN_AT") % PersonnelApp.other_name(target))
				entries.append([ACT_CAMPAIGN, target])
			if (action["targets"] as Array).is_empty():
				popup.add_item(tr("MARKET_ACT_NO_RIVALS"))
				popup.set_item_disabled(popup.item_count - 1, true)
				entries.append(["", ""])
			continue
		popup.add_item(action_label(action))
		popup.set_item_disabled(popup.item_count - 1, not bool(action["enabled"]))
		entries.append([str(action["id"]), ""])
	popup.id_pressed.connect(func(index: int) -> void:
		if index < entries.size() and not str(entries[index][0]).is_empty():
			request_investor_action(investor_id, str(entries[index][0]), str(entries[index][1])))
	return menu


## Apariencia estable de un inversor (no son personajes de NPCDirector).
static func investor_appearance(investor_id: String) -> Dictionary:
	return CharacterPainter.appearance_from_seed(absi(hash(investor_id)),
			Database.get_balance_int(B_INVESTOR_TIER), false, "")


func _fill_calendar(rows: Array) -> void:
	_clear(_calendar)
	if rows.is_empty():
		_calendar.add_child(Kit.label(tr("MARKET_CALENDAR_EMPTY"), Kit.V_SMALL))
	for row: Dictionary in rows:
		var in_days: int = int(row["in_days"])
		var when: String = tr("MARKET_CAL_TODAY") % int(row["day"]) if in_days <= 0 \
				else tr("MARKET_CAL_IN_DAYS") % [int(row["day"]), in_days]
		var line: HBoxContainer = Kit.field_row(when, str(row["name"]),
				Kit.V_STRONG if bool(row["results"]) else Kit.V_BODY)
		(line.get_child(0) as Label).custom_minimum_size.x = Kit.px(8.5)
		if bool(row["results"]):
			(line.get_child(1) as Label).add_theme_color_override("font_color", Kit.green())
		_calendar.add_child(line)


# ─── Cartera (controles fijos; refresh solo cambia textos: no roba el foco) ───

func _build_portfolio() -> void:
	_pf_values.clear()
	for key: String in ["MARKET_SHARES", "MARKET_VALUE", "MARKET_GAIN", "MARKET_DIVIDEND", "MARKET_VOTES"]:
		var row: HBoxContainer = Kit.field_row(tr(key), "", Kit.V_MONO)
		_pf_values[key] = row.get_child(1)
		_portfolio.add_child(row)
	_cash_box = Kit.field_row(tr("MARKET_BROKER_CASH"), "", Kit.V_MONO)
	_cash_label = _cash_box.get_child(1)
	var withdraw: Button = Kit.button(tr("MARKET_WITHDRAW"), "cash")
	withdraw.pressed.connect(collect_cash)
	_cash_box.add_child(withdraw)
	_portfolio.add_child(_cash_box)
	_portfolio.add_child(_order_row())
	_stake_box = VBoxContainer.new()
	_portfolio.add_child(_stake_box)
	_notice_label = Kit.wrap_label("", Kit.V_STRONG)
	_portfolio.add_child(_notice_label)


func _update_portfolio(p: Dictionary) -> void:
	var values: Dictionary = {
		"MARKET_SHARES": str(int(p["shares"])),
		"MARKET_VALUE": UITheme.format_money(roundi(float(p["value"]))),
		"MARKET_GAIN": UITheme.format_signed_money(roundi(float(p["gain"]))),
		"MARKET_DIVIDEND": UITheme.format_money(int(p["dividend"])),
		"MARKET_VOTES": str(int(p["votes"])),
	}
	for key: String in values:
		(_pf_values[key] as Label).text = str(values[key])
	_cash_box.visible = int(p["cash"]) > 0
	_cash_label.text = UITheme.format_money(int(p["cash"]))
	_update_order_buttons()
	_clear(_stake_box)
	_stake_box.add_child(_stake_row(p))
	_show_notice_label()


func _order_row() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var line: HFlowContainer = HFlowContainer.new()
	line.add_theme_constant_override("h_separation", Kit.px(0.25))
	_qty_edit = LineEdit.new()
	_qty_edit.text = str(_quantity)
	_qty_edit.custom_minimum_size.x = Kit.px(4.5)
	_qty_edit.text_changed.connect(_on_quantity_typed)
	_qty_edit.text_submitted.connect(func(_text: String) -> void: buy())
	line.add_child(_qty_edit)
	var lots: Variant = Database.get_balance(B_LOTS)
	for lot: Variant in (lots if lots is Array else []):
		var add: Button = Kit.button("+%d" % int(lot))
		add.pressed.connect(func() -> void: set_quantity(_quantity + int(lot)))
		line.add_child(add)
	box.add_child(line)
	var actions: HFlowContainer = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", Kit.px(0.25))
	_buy_btn = Kit.button("", "plus", Kit.V_PRIMARY)
	_buy_btn.pressed.connect(buy)
	_sell_btn = Kit.button(tr("MARKET_SELL"), "arrow")
	_sell_btn.pressed.connect(sell)
	actions.add_child(_buy_btn)
	actions.add_child(_sell_btn)
	box.add_child(actions)
	return box


func _update_order_buttons() -> void:
	if _buy_btn == null:
		return
	_buy_btn.text = tr("MARKET_BUY") % UITheme.format_money(Market.get_buy_cost(_quantity))
	_buy_btn.disabled = _quantity <= 0
	_sell_btn.disabled = _quantity <= 0 or _quantity > Market.get_player_shares()


## Cantidad tecleada: vale al momento (no hace falta pulsar Intro); lo que no es un número, 0.
func _on_quantity_typed(text: String) -> void:
	var clean: String = text.strip_edges()
	_quantity = maxi(clean.to_int(), 0) if clean.is_valid_int() else 0
	_update_order_buttons()


## Retira todo el efectivo de la cuenta de valores (MarketTrading). Devuelve el importe.
func collect_cash() -> int:
	var amount: int = MarketTrading.collect_broker_cash()
	_set_notice(tr("MARKET_MSG_WITHDRAW") % UITheme.format_money(amount), amount > 0)
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
	meter.band = int(p["pattern_band"])
	_news.add_child(meter)


# ─── Avisos ───────────────────────────────────────────────────────────

func _set_notice(text: String, ok: bool) -> void:
	_notice = text
	_notice_ok = ok
	_show_notice_label()
	if not text.is_empty():
		post_status(text)


func _show_notice_label() -> void:
	if _notice_label == null:
		return
	_notice_label.text = _notice
	_notice_label.visible = not _notice.is_empty()
	_notice_label.add_theme_color_override("font_color", Kit.green() if _notice_ok else Kit.red())


## Último aviso de una orden o trato ("" si no hubo).
func get_notice() -> String:
	return _notice


# ─── Órdenes ──────────────────────────────────────────────────────────

func set_quantity(value: int) -> void:
	_quantity = maxi(value, 0)
	if _qty_edit != null:
		_qty_edit.text = str(_quantity)
	_update_order_buttons()


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
	if _qty_edit != null:
		_on_quantity_typed(_qty_edit.text)
	if action != ACTION_STAKE and _quantity <= 0:
		return
	if needs_confirmation:
		_pending = action
		_pending_deal = {}
		_show_confirm()
	else:
		_execute(action)


## Trato con un inversor: siempre con confirmación (§13.7).
func request_investor_action(investor_id: String, action: String, target: String = "") -> void:
	_pending = action
	_pending_deal = {"investor": investor_id, "action": action, "target": target}
	_show_confirm()


func has_pending_confirmation() -> bool:
	return not _pending.is_empty()


func confirm_pending() -> bool:
	var action: String = _pending
	var deal: Dictionary = _pending_deal
	cancel_pending()
	if action.is_empty():
		return false
	if not deal.is_empty():
		var outcome: Dictionary = perform_investor_action(str(deal["investor"]), action, str(deal["target"]))
		_last_result = bool(outcome["ok"])
		_set_notice(str(outcome["text"]), _last_result)
		refresh()
		return _last_result
	return _execute(action)


func cancel_pending() -> void:
	_pending = ""
	_pending_deal = {}
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = null


func get_last_result() -> bool:
	return _last_result


func _execute(action: String) -> bool:
	var cost: int = Market.get_buy_cost(_quantity)
	match action:
		ACTION_BUY:
			_last_result = MarketTrading.buy(_quantity)
			_set_notice(tr("MARKET_MSG_BUY_OK") % _quantity if _last_result
					else tr("MARKET_MSG_BUY_FAIL") % UITheme.format_money(cost), _last_result)
		ACTION_SELL:
			_last_result = MarketTrading.sell(_quantity)
			_set_notice(tr("MARKET_MSG_SELL_OK") % _quantity if _last_result
					else tr("MARKET_MSG_SELL_FAIL") % _quantity, _last_result)
		ACTION_STAKE:
			_last_result = MarketTrading.buy_board_stake()
			_set_notice(tr("MARKET_MSG_STAKE_OK") if _last_result else tr("MARKET_MSG_STAKE_FAIL")
					% [stake_min_rank(), UITheme.format_money(Market.get_board_stake_price())], _last_result)
		_:
			_last_result = false
	refresh()
	return _last_result


func _show_confirm() -> void:
	var body: String = tr("MARKET_CONFIRM_INSIDER")
	if _pending == ACTION_STAKE:
		body = tr("MARKET_CONFIRM_STAKE") % UITheme.format_money(Market.get_board_stake_price())
	elif not _pending_deal.is_empty():
		body = action_confirm_text(str(_pending_deal["investor"]), _pending, str(_pending_deal["target"]))
	var title: String = tr("MARKET_DEAL_TITLE") if not _pending_deal.is_empty() else tr("MARKET_CONFIRM_TITLE")
	var yes: String = tr("MARKET_DEAL_YES") if not _pending_deal.is_empty() else tr("MARKET_CONFIRM_YES")
	_confirm = PortalApp.ConfirmOverlay.make(title, body, yes, tr("UI_CANCEL"))
	_confirm.connect("answered", func(accepted: bool) -> void:
		if accepted:
			confirm_pending()
		else:
			cancel_pending())
	add_child(_confirm)


# ═══ Piezas dibujadas ═════════════════════════════════════════════════

## Colores del terminal bursátil (datos: mercado_ui.colores_terminal; alto contraste: UITheme).
class Terminal extends RefCounted:
	const CONTRAST_KEYS: Dictionary = {"screen": "ink", "grid": "line", "up": "gain", "down": "loss",
			"amber": "hazard"}

	static func col(key: String) -> Color:
		if UITheme.current_high_contrast:
			var mapped: Color = UITheme.color(str(CONTRAST_KEYS.get(key, "paper")))
			return mapped.darkened(0.6) if key == "grid" else mapped
		var colors: Variant = Database.get_balance(B_TERMINAL)
		if colors is Dictionary and (colors as Dictionary).has(key):
			return Color(str(colors[key]))
		return Kit.ink()


## Cinta de cotización: símbolo, precio, variación, confianza agregada frente al objetivo.
class Ticker extends Control:
	var snap: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Kit.px(3.6)

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		Kit.draw_bevel(self, r, Terminal.col("screen"), true)
		if snap.is_empty():
			return
		var big: int = Kit.px(2.0)
		var base_y: float = size.y * 0.5 + big * 0.36
		var x: float = float(Kit.px(0.8))
		x = _segment(x, base_y, TranslationServer.translate("MARKET_SYMBOL"), Kit.font_black(), big, Terminal.col("amber"))
		x = _segment(x, base_y, "%.2f" % float(snap["price"]), Kit.font_mono(), big, Terminal.col("up"))
		var change: float = float(snap["change"]) * 100.0
		var up: bool = change >= 0.0
		x = _segment(x, base_y, ("▲ %+.2f%%" if up else "▼ %+.2f%%") % change, Kit.font_mono(), Kit.px(1.1),
				Terminal.col("up") if up else Terminal.col("down"))
		_draw_gauge(Rect2(x + Kit.px(0.6), size.y * 0.2, size.x - x - Kit.px(1.4), size.y * 0.6))

	## Dibuja un tramo de la cinta y devuelve la x siguiente.
	func _segment(x: float, base_y: float, value: String, font: Font, fsize: int, color: Color) -> float:
		draw_string(font, Vector2(x, base_y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
		return x + font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + Kit.px(1.2)

	func _draw_gauge(r: Rect2) -> void:
		if r.size.x < Kit.px(6.0):
			return
		var fsize: int = Kit.px(0.72)
		var aggregate: float = float(snap["aggregate"])
		var target: float = float(snap["target"])
		var label: String = TranslationServer.translate("MARKET_CONFIDENCE_FMT") % [aggregate, target,
				int(snap["quarter"])]
		Kit.text(self, Vector2(r.position.x, r.position.y + fsize), label,
				Kit.font_bold(), fsize, Terminal.col("amber"), r.size.x)
		var bar: Rect2 = Rect2(r.position.x, r.position.y + fsize * 1.6, r.size.x, r.size.y - fsize * 1.6)
		draw_rect(bar, Terminal.col("grid"))
		var fill: Color = Terminal.col("up") if aggregate >= target else Terminal.col("down")
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(aggregate / 100.0, 0.0, 1.0), bar.size.y)), fill)
		var tx: float = bar.position.x + bar.size.x * clampf(target / 100.0, 0.0, 1.0)
		draw_line(Vector2(tx, bar.position.y - 4), Vector2(tx, bar.end.y + 4), Terminal.col("amber"), 3.0)


## Gráfico de cotización estilo terminal bursátil (fósforo verde) con rejilla y último precio.
class PriceChart extends Control:
	const GRID_LINES := 5

	var history: Array[float] = []
	var price: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(Kit.px(20.0), Kit.px(12.0))

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		Kit.draw_bevel(self, r, Terminal.col("screen"), true)
		var plot: Rect2 = Rect2(Kit.px(0.8), Kit.px(1.8), size.x - Kit.px(5.6), size.y - Kit.px(3.4))
		var fsize: int = Kit.px(0.72)
		Kit.text(self, Vector2(Kit.px(0.8), Kit.px(1.2)),
				TranslationServer.translate("MARKET_CHART_TITLE") % maxi(history.size(), 1),
				Kit.font_mono(), fsize, Terminal.col("amber"), size.x)
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
		var grid: Color = Terminal.col("grid")
		for i: int in GRID_LINES + 1:
			var t: float = float(i) / GRID_LINES
			var y: float = plot.end.y - plot.size.y * t
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid, 1.0)
			Kit.text(self, Vector2(plot.end.x + 6, y + fsize * 0.35), "%.2f" % lerpf(lo, hi, t),
					Kit.font_mono(), fsize, Color(Terminal.col("up"), 0.6), -1.0)
		for i: int in GRID_LINES * 2 + 1:
			var x: float = plot.position.x + plot.size.x * float(i) / (GRID_LINES * 2)
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(grid, 0.6), 1.0)

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
		var ink: Color = Terminal.col("up")
		draw_colored_polygon(area, Color(ink, 0.12))
		draw_polyline(line, Color(ink, 0.35), 7.0, true)
		draw_polyline(line, ink, 3.0, true)
		var last: Vector2 = line[line.size() - 1]
		draw_circle(last, 7.0, Terminal.col("screen"))
		draw_circle(last, 5.0, Terminal.col("amber"))


## Fila de inversor: foto, nombre, estrategia (o su estado: aliado, coaccionado, campaña),
## confianza (0–100) y marca de aliado.
class InvestorRow extends Control:
	var data: Dictionary = {}
	var appearance: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Kit.px(2.9)

	func _status() -> Array:
		if not str(data.get("campaign", "")).is_empty():
			return [TranslationServer.translate("MARKET_INV_CAMPAIGN") % str(data["campaign"]), Kit.red()]
		if bool(data.get("coerced", false)):
			return [TranslationServer.translate("MARKET_INV_COERCED"), Kit.amber()]
		if bool(data.get("ally", false)):
			return [TranslationServer.translate("MARKET_INV_ALLY"), Kit.green()]
		return [str(data.get("strategy_name", "")), Kit.soft()]

	func _draw() -> void:
		var photo: Rect2 = Rect2(0, Kit.px(0.2), size.y - Kit.px(0.4), size.y - Kit.px(0.4))
		CharacterPainter.draw_portrait(self, appearance, photo)
		draw_rect(photo, Kit.ink(), false, 1.5)
		var x: float = photo.end.x + Kit.px(0.4)
		var w: float = size.x - x
		Kit.text(self, Vector2(x, Kit.px(1.1)), str(data.get("name", "")),
				Kit.font_bold(), Kit.px(0.9), Kit.ink(), w * 0.55)
		var status: Array = _status()
		Kit.text(self, Vector2(x + w * 0.55, Kit.px(1.1)), str(status[0]), Kit.font_regular(), Kit.px(0.72),
				status[1], w * 0.45, HORIZONTAL_ALIGNMENT_RIGHT)
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
		mouse_filter = Control.MOUSE_FILTER_PASS
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


## Patrón de operaciones privilegiadas (§9.8), DIFUSO: tres casillas y una palabra, nunca la cifra.
class PatternMeter extends Control:
	const WORD_KEYS: Array[String] = ["MARKET_PATTERN_QUIET", "MARKET_PATTERN_NOTICED", "MARKET_PATTERN_HOT"]

	var band: int = 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Kit.px(2.4)

	func _draw() -> void:
		var fsize: int = Kit.px(0.7)
		Kit.text(self, Vector2(0, fsize), TranslationServer.translate("MARKET_PATTERN"),
				Kit.font_black(), fsize, Kit.red(), size.x)
		var level: int = clampi(band, 0, WORD_KEYS.size() - 1)
		var word: String = TranslationServer.translate(WORD_KEYS[level])
		var word_w: float = Kit.font_bold().get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + Kit.px(0.5)
		var top: float = fsize * 1.5
		var cell_w: float = (size.x - word_w) / WORD_KEYS.size()
		var colors: Array[Color] = [Kit.green(), Kit.amber(), Kit.red()]
		for i: int in WORD_KEYS.size():
			var cell: Rect2 = Rect2(i * cell_w, top, cell_w - Kit.px(0.2), size.y - top - Kit.px(0.2))
			Kit.draw_bevel(self, cell, colors[i] if i <= level else Kit.field(), i > level)
		Kit.text(self, Vector2(size.x - word_w + Kit.px(0.4), top + (size.y - top) * 0.5 + fsize * 0.2), word,
				Kit.font_bold(), fsize, colors[level], word_w)
