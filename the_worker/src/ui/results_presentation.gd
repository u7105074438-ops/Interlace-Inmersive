# results_presentation.gd — Pantalla de la presentación trimestral de resultados (§9.5): preparación (cifras reales o ajustadas, aviso de la mecha de auditoría y tratos con los inversores de la sala), presentación en la sala de la planta 16 (preguntas de los inversores y nivel de preparación según cómo se produjo el informe) y reacción de cada inversor.
# PROPIETARIO DE: la sesión de ResultsPresentation en curso (fase, inflado elegido, nivel de preparación), la confirmación pendiente y el estado de la pantalla.
# ESCUCHA: nada (conduce src/simulation/results_presentation_logic.gd).
class_name ResultsPresentationScreen
extends Control

## Uso: ResultsPresentationScreen.open(host, trimestre) al recibir results_presentation_due (o al
## interactuar con el atril de results_room). host UIRoot → ventana modal que pausa el reloj.
## API: choose_inflation(f) (solo cargos autorizados, Company.can_set_reported_figures),
## request_lock_figures() (abre la confirmación) / confirm_figures() (ejecuta), available_levels()
## -> {nivel: bool}, select_preparation(nivel), request_present() / present() -> resultado de
## Market, request_deal(inversor, acción) (soborno o chantaje), has_pending_confirmation(),
## confirm_pending(), cancel_pending(), step_away() (salir sin comprometer nada), finish().
## DECISIONES:
##  · §13.7: cerrar las cifras (con inflado enciende la mecha) y salir a escena (mueve la confianza
##    de todos y cierra el trimestre) son irreversibles: los botones abren una confirmación que
##    repite el aviso de la mecha. Los tratos con inversores también se confirman.
##  · El estrado solo abre el día de resultados (Market.can_present_results): cualquier otro día
##    se pueden estudiar las cifras, pero no cerrarlas (no se quema la mecha para nada).
##  · Manipulación (§9.5, §9.6): en la preparación, «Quién hay en la sala» ofrece por inversor el
##    soborno de una pregunta amable (precio justo, por teléfono) o el chantaje con material del
##    jugador (MarketApp.investor_actions/perform_investor_action). Los aliados suben la calidad.
##  · Nivel de preparación según cómo se produjo el informe: «sin preparar» y «A.S.S.I.S.T.»
##    siempre; «informe robado al COO» si lleva presentacion_ui.objeto_informe_coo o completó hoy
##    un deber de informe con un método de metodos_informe_robado; «trabajo real» si lo completó hoy
##    con uno de metodos_trabajo_real. El deber trimestral se asigna el mismo día de resultados:
##    «Salir un momento» cierra la pantalla sin comprometer nada para terminarlo y volver.
##  · Aspecto: la sala usa la paleta de la banda de la planta de Market.get_presentation_room();
##    los colores de interfaz salen de presentacion_ui.colores (datos) y, con alto contraste, de
##    UITheme (negro, blanco y amarillo). La sala se repinta al ritmo de la animación (8–12 fps).

signal close_requested

const LEVELS: Array[String] = [
	ResultsPresentation.LEVEL_NONE, ResultsPresentation.LEVEL_ASSIST,
	ResultsPresentation.LEVEL_STOLEN_REPORT, ResultsPresentation.LEVEL_REAL_WORK,
]
const FIGURES: Array[String] = ["revenue", "costs", "profit"]
const DEAL_ACTIONS: Array[String] = [MarketApp.ACT_BRIBE, MarketApp.ACT_BLACKMAIL]
const B_STEP := "presentacion_ui.paso_inflado"
const B_CAP := "mercado.inflado_maximo_reportado"
const B_COO_ITEM := "presentacion_ui.objeto_informe_coo"
const B_REPORT_SUBTYPES := "presentacion_ui.subtipos_informe"
const B_REAL_METHODS := "presentacion_ui.metodos_trabajo_real"
const B_STOLEN_METHODS := "presentacion_ui.metodos_informe_robado"
const B_INVESTOR_TIER := "presentacion_ui.escalon_inversor"
const STATUS_COMPLETED := "completed"
const PENDING_LOCK := "lock"
const PENDING_PRESENT := "present"
const PENDING_DEAL := "deal"
const SIDE_EM := 21.0

var _quarter: int = 0
var _logic: ResultsPresentation
var _inflation: float = 0.0
var _level: String = ResultsPresentation.LEVEL_NONE
var _result: Dictionary = {}
var _aggregate_before: float = 0.0
var _message: String = ""
var _deal_message: String = ""
var _deal_ok: bool = true
var _pending: String = ""
var _pending_deal: Dictionary = {}
var _in_ui_root: bool = false
var _built: bool = false
var _narrow: bool = false
var _body: MarginContainer
var _stepper: PhaseStepper
var _figures_row: HBoxContainer
var _adjust_box: VBoxContainer
var _headline: HeadlinePreview
var _headline_key: String = ""
var _confirm: ConfirmDialog


static func open(host: Node, quarter: int) -> ResultsPresentationScreen:
	var screen: ResultsPresentationScreen = ResultsPresentationScreen.new()
	screen.setup({"quarter": quarter})
	if host is UIRoot:
		screen._in_ui_root = true
		(host as UIRoot).open_modal(screen, true)
	elif host != null:
		host.add_child(screen)
	return screen


## context: {quarter?: trimestre (por defecto el del reloj)}.
func setup(context: Dictionary) -> void:
	_quarter = int(context.get("quarter", GameClock.get_quarter()))
	_logic = ResultsPresentation.new(_quarter)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	if _logic == null:
		setup({})
	theme = Look.build_theme()
	_build()
	_built = true
	_rebuild()


func _draw() -> void:
	Look.draw_backdrop(self, Rect2(Vector2.ZERO, size))


## Pantalla estrecha (teléfono): la tarjeta lateral pasa debajo del contenido.
func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED or not _built:
		return
	var narrow: bool = size.x > 0.0 and size.x < Look.px(Look.NARROW_EM)
	if narrow != _narrow:
		_narrow = narrow
		_rebuild()


func get_phase() -> ResultsPresentation.Phase:
	return _logic.phase


func get_logic() -> ResultsPresentation:
	return _logic


func request_close() -> void:
	close_requested.emit()
	if not _in_ui_root:
		queue_free()


## Sale de la sala sin comprometer nada (fases 1 y 2): se puede volver antes de que acabe el día.
func step_away() -> void:
	cancel_pending()
	request_close()


func _build() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, Look.px(1.0))
	col.add_theme_constant_override("separation", Look.px(0.6))
	add_child(col)
	var head: HFlowContainer = HFlowContainer.new()
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(Look.label(tr("RPRES_KICKER") % Look.hall_floor(), Look.V_KICKER))
	titles.add_child(Look.label(tr("RPRES_TITLE") % _quarter, Look.V_TITLE))
	head.add_child(titles)
	_stepper = PhaseStepper.new()
	_stepper.custom_minimum_size = Vector2(Look.px(26.0), Look.px(3.0))
	head.add_child(_stepper)
	col.add_child(head)
	_body = MarginContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_body)


func _rebuild() -> void:
	if not _built:
		return
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_figures_row = null
	_adjust_box = null
	_headline = null
	_stepper.phase = int(_logic.phase)
	_stepper.queue_redraw()
	match _logic.phase:
		ResultsPresentation.Phase.PREPARATION:
			_body.add_child(_build_preparation())
		ResultsPresentation.Phase.PRESENTATION:
			_body.add_child(_build_presentation())
		_:
			_body.add_child(_build_reaction())


## Fila principal: contenido a la izquierda y tarjeta lateral; en pantallas estrechas, apiladas.
func _main_row() -> BoxContainer:
	_narrow = size.x > 0.0 and size.x < Look.px(Look.NARROW_EM)
	var row: BoxContainer = VBoxContainer.new() if _narrow else HBoxContainer.new()
	row.add_theme_constant_override("separation", Look.px(1.0))
	return row


func _side_card() -> VBoxContainer:
	var card: PanelContainer = Look.card()
	card.custom_minimum_size.x = Look.px(SIDE_EM)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.5))
	card.add_child(box)
	return box


## Columna principal desplazable (la tarjeta lateral queda fija con sus botones a la vista).
func _scroll_column(content: Control) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _spacer() -> Control:
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer


# ═══ Fase 1: preparación ══════════════════════════════════════════════

func can_adjust() -> bool:
	return Company.can_set_reported_figures()


func get_inflation() -> float:
	return _inflation


## El estrado solo abre el día de resultados (y una vez por trimestre).
func stage_open() -> bool:
	return Market.can_present_results()


## Elige el inflado de ingresos que se comunicará (0 = cifras reales). false si no está permitido.
func choose_inflation(value: float) -> bool:
	if _logic.phase != ResultsPresentation.Phase.PREPARATION or (value > 0.0 and not can_adjust()):
		return false
	var was_adjusted: bool = _inflation > 0.0
	_inflation = clampf(value, 0.0, Database.get_balance_float(B_CAP))
	if was_adjusted != (_inflation > 0.0) or _figures_row == null:
		_rebuild()
	else:
		_update_inflation_views()
	return true


## Cierra la preparación comunicando las cifras elegidas (Company enciende la mecha si divergen).
## Ejecución directa: la interfaz pasa por request_lock_figures() (confirmación). false con el
## estrado cerrado (otro día) o fuera de la fase 1.
func confirm_figures() -> bool:
	if _logic.phase != ResultsPresentation.Phase.PREPARATION or not stage_open():
		return false
	var ok: bool = _logic.report_inflated_figures(_inflation) if _inflation > 0.0 else _logic.keep_real_figures()
	_logic.confirm_figures()
	_rebuild()
	return ok


## Botón «Cerrar las cifras»: pide confirmación (con el aviso de la mecha si hay inflado).
func request_lock_figures() -> void:
	if _logic.phase != ResultsPresentation.Phase.PREPARATION or not stage_open():
		return
	var body: String = tr("RPRES_CONFIRM_LOCK_REAL")
	if _inflation > 0.0:
		var preview: Dictionary = audit_preview()
		body = tr("RPRES_CONFIRM_LOCK_INFLATED") % [roundi(_inflation * 100.0), int(preview["weeks"]),
				roundi(float(preview["probability"]) * 100.0)]
	_ask(PENDING_LOCK, {}, body, tr("RPRES_CONFIRM_LOCK_YES"))


## Aviso de la mecha (§9.2): {divergence, weeks, probability} del inflado elegido.
func audit_preview() -> Dictionary:
	var real: Dictionary = Company.get_fundamentals()
	var divergence: float = CompanySystem.compute_divergence(real,
			ResultsPresentation.inflate_figures(real, _inflation))
	return {"divergence": divergence, "weeks": Company.compute_fuse_weeks(divergence),
			"probability": Company.get_audit_detection_probability()}


func _build_preparation() -> Control:
	var row: BoxContainer = _main_row()
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", Look.px(1.0))
	_figures_row = HBoxContainer.new()
	_figures_row.add_theme_constant_override("separation", Look.px(1.0))
	left.add_child(_figures_row)
	_fill_figures()
	left.add_child(_room_card())
	row.add_child(_scroll_column(left))
	row.add_child(_preparation_side())
	return row


## Tarjetas «cifras reales» y «lo que vas a comunicar» con expectativas, costes y titular.
func _fill_figures() -> void:
	for child: Node in _figures_row.get_children():
		_figures_row.remove_child(child)
		child.queue_free()
	var real: Dictionary = _logic.get_quarter_real_figures()
	var shown: Dictionary = ResultsPresentation.inflate_figures(real, _inflation)
	var cards: Array[VBoxContainer] = [
		_figure_card(tr("RPRES_REAL"), tr("RPRES_REAL_SUB"), real, {}),
		_figure_card(tr("RPRES_REPORTED"), tr("RPRES_REPORTED_SUB"), shown, real),
	]
	for i: int in cards.size():
		var chart: ExpectationChart = ExpectationChart.new()
		chart.expected = Market.get_expected_quarter_profit()
		chart.value = float((real if i == 0 else shown).get("profit", 0.0))
		chart.score = Market.figures_score_for(chart.value, chart.expected)
		chart.band = Database.get_balance_float(ExpectationChart.B_BAND)
		cards[i].add_child(chart)
		_headline_key = chart.headline_key()
	var costs: CostBreakdown = CostBreakdown.new()
	costs.fundamentals = Company.get_fundamentals()
	cards[0].add_child(costs)
	cards[1].add_child(_audit_box())
	if _headline != null:
		_headline.headline = tr(_headline_key)
		_headline.queue_redraw()


func _figure_card(title: String, subtitle: String, figures: Dictionary, against: Dictionary) -> VBoxContainer:
	var card: PanelContainer = Look.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_figures_row.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.5))
	card.add_child(box)
	box.add_child(Look.label(title, Look.V_HEADING))
	box.add_child(Look.label(subtitle, Look.V_SMALL))
	for key: String in FIGURES:
		var figure: FigureRow = FigureRow.new()
		figure.caption = tr("RPRES_FIG_" + key.to_upper())
		figure.value = float(figures.get(key, 0.0))
		figure.reference = float(against.get(key, figure.value)) if not against.is_empty() else figure.value
		figure.highlight = key == "profit"
		box.add_child(figure)
	box.add_child(Look.label(tr("RPRES_DAYS") % int(figures.get("days", 0)), Look.V_SMALL))
	return box


func _preparation_side() -> Control:
	var box: VBoxContainer = _side_card()
	box.add_child(Look.label(tr("RPRES_DECIDE"), Look.V_HEADING))
	var real_btn: Button = Look.button(tr("PRES_FIGURES_REAL"), _inflation <= 0.0)
	real_btn.pressed.connect(func() -> void: choose_inflation(0.0))
	box.add_child(real_btn)
	var step: float = Database.get_balance_float(B_STEP)
	var adjust: Button = Look.button(tr("PRES_FIGURES_INFLATED"), _inflation > 0.0)
	adjust.disabled = not can_adjust()
	adjust.pressed.connect(func() -> void: choose_inflation(maxf(_inflation, step)))
	box.add_child(adjust)
	if not can_adjust():
		box.add_child(Look.wrap(tr("RPRES_NOT_AUTHORISED"), Look.V_SMALL))
	elif _inflation > 0.0:
		_adjust_box = _inflation_slider(step)
		box.add_child(_adjust_box)
	if not stage_open():
		box.add_child(_closed_notice())
	_headline = HeadlinePreview.new()
	_headline.headline = tr(_headline_key)
	_headline.size_flags_vertical = Control.SIZE_FILL
	box.add_child(_headline)
	box.add_child(_spacer())
	box.add_child(_step_away_button())
	var go: Button = Look.button(tr("RPRES_CONFIRM_FIGURES"), true)
	go.disabled = not stage_open()
	go.pressed.connect(request_lock_figures)
	box.add_child(go)
	return box.get_parent()


## Deslizador del inflado: vale al moverlo con ratón, teclado o mando (value_changed); solo se
## repintan las cifras y el aviso, el deslizador sigue vivo.
func _inflation_slider(step: float) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(Look.label(tr("RPRES_INFLATION") % roundi(_inflation * 100.0), Look.V_STRONG))
	var slider: HSlider = HSlider.new()
	slider.min_value = step
	slider.max_value = Database.get_balance_float(B_CAP)
	slider.step = step
	slider.value = _inflation
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(func(value: float) -> void: choose_inflation(value))
	box.add_child(slider)
	return box


func _update_inflation_views() -> void:
	if _figures_row == null:
		return
	_fill_figures()
	if _adjust_box != null:
		(_adjust_box.get_child(0) as Label).text = tr("RPRES_INFLATION") % roundi(_inflation * 100.0)


## Bajo las cifras comunicadas: la mecha de auditoría si hay inflado; si no, libros limpios.
func _audit_box() -> Control:
	if _inflation <= 0.0:
		var clean: WarningBox = WarningBox.new()
		clean.calm = true
		clean.title = tr("RPRES_CLEAN_TITLE")
		clean.body = tr("RPRES_CLEAN_BODY")
		return clean
	var preview: Dictionary = audit_preview()
	var warn: WarningBox = WarningBox.new()
	warn.title = tr("RPRES_FUSE_TITLE")
	warn.body = tr("RPRES_FUSE_BODY") % [int(preview["weeks"]), roundi(float(preview["probability"]) * 100.0)]
	return warn


## Estrado cerrado: otro día (o trimestre ya presentado). Las cifras se pueden mirar, no cerrar.
func _closed_notice() -> Control:
	var warn: WarningBox = WarningBox.new()
	warn.title = tr("RPRES_STAGE_CLOSED_TITLE")
	warn.body = tr("RPRES_STAGE_DONE") if Market.has_presented_this_quarter() \
			else tr("RPRES_STAGE_CLOSED_BODY") % Market.get_presentation_day()
	return warn


func _step_away_button() -> Button:
	var btn: Button = Look.button(tr("RPRES_STEP_AWAY"), false)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.tooltip_text = tr("RPRES_STEP_AWAY_TIP")
	btn.pressed.connect(step_away)
	return btn


# ─── Quién hay en la sala: tratos (§9.5, §9.6) ─────────────────────────

func _room_card() -> Control:
	var card: PanelContainer = Look.card()
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.5))
	card.add_child(box)
	var head: HBoxContainer = HBoxContainer.new()
	var title: Label = Look.label(tr("RPRES_ROOM"), Look.V_HEADING)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Look.label(tr("RPRES_ALLIES") % Market.get_investor_allies().size(), Look.V_STRONG))
	box.add_child(head)
	if _deal_message.is_empty():
		box.add_child(Look.wrap(tr("RPRES_ROOM_SUB") % roundi(Look.weight("weight_allies") * 100.0), Look.V_SMALL))
	else:
		box.add_child(Look.wrap(_deal_message, Look.V_GOOD if _deal_ok else Look.V_WARN))
	var tiles: HFlowContainer = HFlowContainer.new()
	tiles.add_theme_constant_override("h_separation", Look.px(0.5))
	tiles.add_theme_constant_override("v_separation", Look.px(0.5))
	for inv: InvestorData in Market.get_investors():
		tiles.add_child(_investor_tile(inv))
	box.add_child(tiles)
	return card


## Ficha de inversor: nombre arriba (ancho completo), retrato con estrategia y confianza, y el trato.
func _investor_tile(inv: InvestorData) -> Control:
	var tile: PanelContainer = Look.tile(Market.is_investor_ally(inv.id))
	tile.custom_minimum_size.x = Look.px(Look.TILE_EM)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var strategy: String = tr("INV_STRATEGY_" + inv.strategy.to_upper())
	tile.tooltip_text = "%s · %s" % [inv.name, strategy]
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.3))
	tile.add_child(box)
	box.add_child(Look.fit_label(inv.name, Look.V_STRONG))
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", Look.px(0.4))
	var photo: Portrait = Portrait.new()
	photo.appearance = MarketApp.investor_appearance(inv.id)
	photo.custom_minimum_size = Vector2(Look.px(Look.PORTRAIT_EM), Look.px(Look.PORTRAIT_EM))
	head.add_child(photo)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(Look.fit_label(strategy, Look.V_SMALL))
	var meter: MiniMeter = MiniMeter.new()
	meter.value = Market.get_investor_confidence(inv.id)
	meter.target = Market.get_quarterly_target()
	meter.tooltip_text = tr("RPRES_CONFIDENCE_FMT") % meter.value
	text.add_child(meter)
	head.add_child(text)
	box.add_child(head)
	box.add_child(_deal_control(inv.id))
	return tile


## Botón del trato (soborno o chantaje), o su estado: aliado, o «no se deja comprar».
func _deal_control(investor_id: String) -> Control:
	if Market.is_investor_ally(investor_id):
		return Look.label(tr("RPRES_DEAL_ALLY"), Look.V_GOOD)
	var actions: Array[Dictionary] = deal_actions(investor_id)
	if actions.is_empty():
		return Look.label(tr("RPRES_DEAL_NONE"), Look.V_SMALL)
	var action: Dictionary = actions[0]
	var bribe: bool = str(action["id"]) == MarketApp.ACT_BRIBE
	var btn: Button = Look.button(tr("RPRES_DEAL_BRIBE") % UITheme.format_money(int(action["price"])) if bribe
			else tr("RPRES_DEAL_BLACKMAIL"), false)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.disabled = not bool(action["enabled"]) or _logic.phase == ResultsPresentation.Phase.REACTION
	btn.tooltip_text = tr("RPRES_DEAL_BRIBE_TIP") if bribe else tr("RPRES_DEAL_NEED_MATERIAL")
	btn.pressed.connect(request_deal.bind(investor_id, str(action["id"])))
	return btn


## Tratos de la sala (soborno de la pregunta amable, chantaje) posibles con un inversor.
func deal_actions(investor_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for action: Dictionary in MarketApp.investor_actions(investor_id):
		if DEAL_ACTIONS.has(str(action["id"])):
			out.append(action)
	return out


## Pide un trato con un inversor (siempre con confirmación).
func request_deal(investor_id: String, action: String) -> void:
	if not DEAL_ACTIONS.has(action) or _logic.phase == ResultsPresentation.Phase.REACTION:
		return
	_ask(PENDING_DEAL, {"investor": investor_id, "action": action},
			MarketApp.action_confirm_text(investor_id, action, ""), tr("MARKET_DEAL_YES"))


func get_deal_message() -> String:
	return _deal_message


# ═══ Fase 2: la presentación ══════════════════════════════════════════

## {nivel: disponible} según cómo se produjo el informe (ver DECISIONES).
func available_levels() -> Dictionary:
	return {
		ResultsPresentation.LEVEL_NONE: true, ResultsPresentation.LEVEL_ASSIST: true,
		ResultsPresentation.LEVEL_STOLEN_REPORT: PlayerState.has_item(str(Database.get_balance(B_COO_ITEM)))
				or _report_duty_done(B_STOLEN_METHODS),
		ResultsPresentation.LEVEL_REAL_WORK: _report_duty_done(B_REAL_METHODS),
	}


func _report_duty_done(methods_path: String) -> bool:
	var subtypes: Variant = Database.get_balance(B_REPORT_SUBTYPES)
	var methods: Variant = Database.get_balance(methods_path)
	if not (subtypes is Array and methods is Array):
		return false
	for duty: Dictionary in PlayerState.get_todays_duties():
		if str(duty.get("status", "")) == STATUS_COMPLETED and (subtypes as Array).has(str(duty.get("subtype", ""))) \
				and (methods as Array).has(str(duty.get("method", ""))):
			return true
	return false


func select_preparation(level: String) -> bool:
	if not bool(available_levels().get(level, false)) or not _logic.select_preparation(level):
		return false
	_level = level
	_rebuild()
	return true


## Sale a escena: Market calcula calidad y reacción. {} si hoy no es el día de resultados.
## Ejecución directa: la interfaz pasa por request_present() (confirmación).
func present() -> Dictionary:
	if _logic.phase != ResultsPresentation.Phase.PRESENTATION:
		return {}
	_logic.select_preparation(_level)
	_aggregate_before = Market.get_aggregate_confidence()
	_result = _logic.present()
	if _result.is_empty():
		_message = tr("RPRES_NOT_TODAY") % Market.get_presentation_day()
	_rebuild()
	return _result.duplicate(true)


## Botón «Salir al estrado»: pide confirmación (mueve la confianza de todos; una vez por trimestre).
func request_present() -> void:
	if _logic.phase != ResultsPresentation.Phase.PRESENTATION:
		return
	_ask(PENDING_PRESENT, {}, tr("RPRES_CONFIRM_PRESENT") % [tr("PRES_LEVEL_" + _level.to_upper()),
			_logic.get_quality_preview()], tr("RPRES_CONFIRM_PRESENT_YES"))


func _build_presentation() -> Control:
	var row: BoxContainer = _main_row()
	var hall: HallView = HallView.new()
	hall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hall.setup_hall(_hall_seats(), ResultsPresentation.inflate_figures(_logic.get_quarter_real_figures(), _inflation))
	row.add_child(hall)
	row.add_child(_presentation_side())
	return row


## Asientos de la sala: [{id, name, strategy, ally, appearance, question}].
func _hall_seats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var allies: Array[String] = Market.get_investor_allies()
	for inv: InvestorData in Market.get_investors():
		var ally: bool = allies.has(inv.id)
		out.append({"id": inv.id, "name": inv.name, "strategy": inv.strategy, "ally": ally,
				"appearance": MarketApp.investor_appearance(inv.id),
				"question": tr("RPRES_Q_ALLY") if ally else question_for(inv)})
	return out


## Pregunta del inversor: la suya propia si existe (RPRES_Q_<ID>), si no la de su estrategia.
static func question_for(inv: InvestorData) -> String:
	var own: String = "RPRES_Q_" + inv.id.to_upper()
	var text: String = TranslationServer.translate(own)
	return text if text != own else TranslationServer.translate("RPRES_Q_" + inv.strategy.to_upper())


func _presentation_side() -> Control:
	var box: VBoxContainer = _side_card()
	box.add_child(Look.label(tr("RPRES_PREPARATION"), Look.V_HEADING))
	var levels: Dictionary = available_levels()
	var values: Dictionary = _logic.get_preparation_levels()
	for level: String in LEVELS:
		var text: String = "%s  ·  %.1f" % [tr("PRES_LEVEL_" + level.to_upper()), float(values.get(level, 0.0))]
		var btn: Button = Look.button(text, level == _level)
		btn.disabled = not bool(levels[level])
		btn.tooltip_text = tr("RPRES_LEVEL_HINT_" + level.to_upper())
		btn.pressed.connect(select_preparation.bind(level))
		box.add_child(btn)
	var quality: QualityMeter = QualityMeter.new()
	quality.preparation = _logic.get_preparation_value()
	quality.reputation = PlayerState.get_reputation()
	quality.allies = Market.get_allies_ratio(_logic.get_allies_present())
	quality.quality = _logic.get_quality_preview()
	box.add_child(quality)
	box.add_child(_allies_list())
	if not _message.is_empty():
		box.add_child(Look.wrap(_message, Look.V_WARN))
	box.add_child(_spacer())
	box.add_child(_step_away_button())
	var go: Button = Look.button(tr("RPRES_PRESENT"), true)
	go.pressed.connect(request_present)
	box.add_child(go)
	return box.get_parent()


## Lista compacta de la fase 2: aliados y tratos aún posibles antes de salir.
func _allies_list() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.25))
	box.add_child(Look.label(tr("RPRES_ALLIES") % Market.get_investor_allies().size(), Look.V_STRONG))
	for inv: InvestorData in Market.get_investors():
		var line: HBoxContainer = HBoxContainer.new()
		var who: Label = Look.label(inv.name, Look.V_SMALL)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(who)
		line.add_child(_deal_control(inv.id))
		box.add_child(line)
	if not _deal_message.is_empty():
		box.add_child(Look.wrap(_deal_message, Look.V_STRONG if _deal_ok else Look.V_WARN))
	return box


# ═══ Fase 3: reacción ═════════════════════════════════════════════════

func _build_reaction() -> Control:
	var row: BoxContainer = _main_row()
	var table: PanelContainer = Look.card()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.3))
	table.add_child(box)
	box.add_child(Look.label(tr("RPRES_REACTION"), Look.V_HEADING))
	for data: Dictionary in _logic.get_reaction_rows():
		var line: ReactionRow = ReactionRow.new()
		line.data = data
		line.appearance = MarketApp.investor_appearance(str(data["investor_id"]))
		line.strategy_name = tr("INV_STRATEGY_" + str(data["strategy"]).to_upper())
		line.quip = quip_for(str(data["investor_id"]), int(data["delta"]))
		box.add_child(line)
	row.add_child(table)
	row.add_child(_summary_side())
	return row


## Frase de reacción según el estilo del inversor (sub_strategy o estrategia) y el signo del cambio.
static func quip_for(investor_id: String, delta: int) -> String:
	var inv: InvestorData = Market.get_investor(investor_id)
	var mood: String = "UP" if delta > 0 else ("DOWN" if delta < 0 else "FLAT")
	var style: String = ""
	if inv != null:
		style = str(inv.extra.get("sub_strategy", inv.strategy))
	var key: String = "RPRES_QUIP_%s_%s" % [mood, style.to_upper()]
	var text: String = TranslationServer.translate(key)
	return text if text != key else TranslationServer.translate("RPRES_QUIP_" + mood)


func _summary_side() -> Control:
	var box: VBoxContainer = _side_card()
	var summary: Dictionary = _logic.get_summary()
	box.add_child(Look.label(tr("RPRES_VERDICT"), Look.V_HEADING))
	var met: bool = bool(summary.get("meeting_target", false))
	box.add_child(Look.wrap(tr("RPRES_TARGET_MET" if met else "RPRES_TARGET_MISSED"), Look.V_BIG))
	var meter: AggregateMeter = AggregateMeter.new()
	meter.before = _aggregate_before
	meter.after = Market.get_aggregate_confidence()
	meter.target = float(summary.get("target", 0.0))
	box.add_child(meter)
	for pair: Array in [["RPRES_SUM_QUALITY", "%.2f" % float(summary.get("quality", 0.0))],
			["RPRES_SUM_CONFIDENCE", "%.1f / %.1f" % [Market.get_aggregate_confidence(), float(summary.get("target", 0.0))]],
			["RPRES_SUM_SENTIMENT", "%+.3f" % float(summary.get("sentiment_delta", 0.0))],
			["RPRES_SUM_ALLIES", str(int(summary.get("allies_present", 0)))]]:
		box.add_child(Look.pair(tr(pair[0]), str(pair[1])))
	var assist: String = str(summary.get("assist_outcome", ""))
	if not assist.is_empty():
		box.add_child(Look.wrap(tr("RPRES_ASSIST_" + assist.to_upper()),
				Look.V_WARN if assist == ResultsPresentation.ASSIST_FAILURE else Look.V_STRONG))
	var paper: HeadlinePreview = HeadlinePreview.new()
	paper.headline = tr(ExpectationChart.key_for(float(summary.get("figures_score", ExpectationChart.NEUTRAL)),
			Database.get_balance_float(ExpectationChart.B_BAND)))
	box.add_child(paper)
	box.add_child(_spacer())
	var done: Button = Look.button(tr("RPRES_LEAVE"), true)
	done.pressed.connect(finish)
	box.add_child(done)
	return box.get_parent()


func finish() -> void:
	_logic.finish()
	request_close()


# ═══ Confirmaciones (§13.7) ═══════════════════════════════════════════

func has_pending_confirmation() -> bool:
	return not _pending.is_empty()


func _ask(kind: String, data: Dictionary, body: String, yes_text: String) -> void:
	cancel_pending()
	_pending = kind
	_pending_deal = data
	_confirm = ConfirmDialog.make(tr("RPRES_CONFIRM_TITLE"), body, yes_text, tr("UI_CANCEL"))
	_confirm.answered.connect(func(yes: bool) -> void:
		if yes:
			confirm_pending()
		else:
			cancel_pending())
	add_child(_confirm)


## Ejecuta lo confirmado. true si salió adelante.
func confirm_pending() -> bool:
	var kind: String = _pending
	var deal: Dictionary = _pending_deal
	cancel_pending()
	match kind:
		PENDING_LOCK:
			return confirm_figures()
		PENDING_PRESENT:
			return not present().is_empty()
		PENDING_DEAL:
			var outcome: Dictionary = MarketApp.perform_investor_action(str(deal["investor"]), str(deal["action"]))
			_deal_ok = bool(outcome["ok"])
			_deal_message = str(outcome["text"])
			_rebuild()
			return _deal_ok
	return false


func cancel_pending() -> void:
	_pending = ""
	_pending_deal = {}
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = null


# ═══ Aspecto: sala de la planta 16 (paleta de su banda) ═══════════════

## Paleta de la banda de la sala, colores de interfaz (datos o alto contraste) y tema.
class Look extends RefCounted:
	const V_KICKER := "RpKicker"
	const V_TITLE := "RpTitle"
	const V_HEADING := "RpHeading"
	const V_SMALL := "RpSmall"
	const V_STRONG := "RpStrong"
	const V_BIG := "RpBig"
	const V_WARN := "RpWarn"
	const V_GOOD := "RpGood"
	const V_PRIMARY := "RpPrimary"
	const V_CARD := "RpCard"
	const V_TILE := "RpTile"
	const V_TILE_ALLY := "RpTileAlly"
	const B_COLORS := "presentacion_ui.colores"
	## Maquetación (em): ancho de las fichas de inversor y ancho por debajo del cual se apila.
	const TILE_EM := 7.0
	const PORTRAIT_EM := 2.2
	const NARROW_EM := 48.0
	## Alto contraste: rol de color de la interfaz → color de la paleta de UITheme.
	const CONTRAST_ROLES: Dictionary = {
		"paper": "ink", "ink": "paper", "red": "loss", "green": "gain", "warn_bg": "ink",
		"newsprint": "ink", "screen": "ink", "scandal": "det_partial", "accent": "hazard",
	}
	## Alto contraste: clave de la paleta de banda → color de UITheme (la sala en negro y blanco).
	const CONTRAST_BAND: Dictionary = {
		"carpet": "ink", "floor": "slot", "wall": "ink", "furniture": "button_hover", "shadow": "faint",
		"light": "paper", "outline": "paper", "accent": "hazard", "window": "button",
	}

	static var _themes: Dictionary = {}

	static func base_size() -> int:
		return UITheme.base_font_size(UITheme.current_text_size)

	static func px(em: float) -> int:
		return roundi(base_size() * em)

	static func hall_floor() -> int:
		var room: RoomData = Database.get_room(Market.get_presentation_room())
		return room.floor if room != null else 0

	## Color de la banda de la sala (alto contraste: negro, blanco y amarillo).
	static func pal(key: String) -> Color:
		if UITheme.current_high_contrast:
			return UITheme.color(str(CONTRAST_BAND.get(key, "paper")))
		return Color(str(UITheme.band_palette_for_floor(hall_floor()).get(key, "#808080")))

	## Color de interfaz por rol: presentacion_ui.colores (datos) o UITheme con alto contraste.
	static func role(key: String) -> Color:
		if UITheme.current_high_contrast:
			return UITheme.color(str(CONTRAST_ROLES.get(key, "paper")))
		if key == "ink":
			return pal("outline")
		if key == "accent":
			return pal("accent")
		var colors: Variant = Database.get_balance(B_COLORS)
		if colors is Dictionary and (colors as Dictionary).has(key):
			return Color(str(colors[key]))
		return pal("light")

	static func ink() -> Color:
		return role("ink")

	static func paper() -> Color:
		return role("paper")

	static func red() -> Color:
		return role("red")

	static func green() -> Color:
		return role("green")

	static func accent() -> Color:
		return role("accent")

	## Peso de la fórmula de calidad (market.json presentation.weight_*).
	static func weight(key: String) -> float:
		var presentation: Variant = Database.get_market_params().get("presentation", {})
		return float((presentation as Dictionary).get(key, 0.0)) if presentation is Dictionary else 0.0

	static func draw_backdrop(c: CanvasItem, r: Rect2) -> void:
		c.draw_rect(r, pal("carpet"))
		var step: float = float(px(2.2))
		var y: float = r.position.y
		var row: int = 0
		while y < r.end.y + step:
			var x: float = r.position.x + (step * 0.5 if row % 2 == 1 else 0.0)
			while x < r.end.x + step:
				var d: PackedVector2Array = PackedVector2Array([Vector2(x, y - step * 0.18), Vector2(x + step * 0.18, y),
						Vector2(x, y + step * 0.18), Vector2(x - step * 0.18, y)])
				c.draw_colored_polygon(d, Color(pal("accent"), 0.09))
				x += step
			y += step * 0.5
			row += 1
		c.draw_rect(Rect2(r.position, Vector2(r.size.x, px(5.2))), pal("floor"))
		c.draw_rect(Rect2(r.position.x, r.position.y + px(5.2), r.size.x, px(0.25)), pal("accent"))

	## Tema de la pantalla (caché por tamaño de texto y alto contraste).
	static func build_theme() -> Theme:
		var key: String = "%d_%s_%d" % [base_size(), str(UITheme.current_high_contrast), hall_floor()]
		if _themes.has(key):
			return _themes[key]
		var t: Theme = Theme.new()
		t.default_font = UITheme.font(UITheme.FONT_REGULAR)
		t.default_font_size = px(0.8)
		var title_ink: Color = UITheme.readable_on(pal("floor"))
		for spec: Array in [[V_KICKER, UITheme.FONT_BOLD, 0.75, pal("light")], [V_TITLE, UITheme.FONT_BOLD, 1.7, title_ink],
				[V_HEADING, UITheme.FONT_BOLD, 0.95, ink()], [V_SMALL, UITheme.FONT_REGULAR, 0.72, ink().lerp(paper(), 0.3)],
				[V_STRONG, UITheme.FONT_SEMIBOLD, 0.82, ink()], [V_BIG, UITheme.FONT_BOLD, 1.15, ink()],
				[V_WARN, UITheme.FONT_SEMIBOLD, 0.78, red()], [V_GOOD, UITheme.FONT_SEMIBOLD, 0.78, green()]]:
			t.set_type_variation(spec[0], "Label")
			t.set_font("font", spec[0], UITheme.font(spec[1]))
			t.set_font_size("font_size", spec[0], px(float(spec[2])))
			t.set_color("font_color", spec[0], spec[3])
		_buttons(t)
		_panels(t)
		_themes[key] = t
		return t

	static func _panels(t: Theme) -> void:
		t.set_type_variation(V_CARD, "PanelContainer")
		t.set_stylebox("panel", V_CARD, _box(paper(), ink(), 3, px(0.9)))
		t.set_type_variation(V_TILE, "PanelContainer")
		t.set_stylebox("panel", V_TILE, _box(paper().lerp(pal("light"), 0.35), ink().lerp(paper(), 0.4), 2, px(0.5)))
		t.set_type_variation(V_TILE_ALLY, "PanelContainer")
		t.set_stylebox("panel", V_TILE_ALLY, _box(paper().lerp(green(), 0.12), green(), 3, px(0.5)))
		t.set_stylebox("slider", "HSlider", _box(paper().darkened(0.1), ink(), 2, 4))
		t.set_stylebox("grabber_area", "HSlider", _box(accent(), ink(), 2, 4))
		t.set_stylebox("grabber_area_highlight", "HSlider", _box(accent(), ink(), 2, 4))
		t.set_color("font_color", "TooltipLabel", ink())
		t.set_stylebox("panel", "TooltipPanel", _box(paper(), ink(), 2, px(0.4)))

	static func _buttons(t: Theme) -> void:
		t.set_stylebox("normal", "Button", _box(paper(), ink(), 2, px(0.45)))
		t.set_stylebox("hover", "Button", _box(paper().lerp(pal("light"), 0.5), ink(), 2, px(0.45)))
		t.set_stylebox("pressed", "Button", _box(accent(), ink(), 3, px(0.45)))
		t.set_stylebox("disabled", "Button", _box(paper().lerp(ink(), 0.12), ink().lerp(paper(), 0.5), 2, px(0.45)))
		t.set_stylebox("focus", "Button", _focus_box())
		t.set_font("font", "Button", UITheme.font(UITheme.FONT_SEMIBOLD))
		t.set_font_size("font_size", "Button", px(0.78))
		for name: String in ["font_color", "font_hover_color", "font_focus_color"]:
			t.set_color(name, "Button", ink())
		for name: String in ["font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(name, "Button", UITheme.readable_on(accent()))
		t.set_color("font_disabled_color", "Button", ink().lerp(paper(), 0.5))
		t.set_type_variation(V_PRIMARY, "Button")
		t.set_stylebox("normal", V_PRIMARY, _box(accent(), ink(), 3, px(0.55)))
		t.set_stylebox("hover", V_PRIMARY, _box(accent().lightened(0.15), ink(), 3, px(0.55)))
		t.set_stylebox("pressed", V_PRIMARY, _box(accent().darkened(0.15), ink(), 3, px(0.55)))
		t.set_font("font", V_PRIMARY, UITheme.font(UITheme.FONT_BOLD))
		t.set_font_size("font_size", V_PRIMARY, px(0.9))
		for name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
				"font_hover_pressed_color"]:
			t.set_color(name, V_PRIMARY, UITheme.readable_on(accent()))

	## Foco visible para teclado y mando (§13.10).
	static func _focus_box() -> StyleBoxFlat:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = UITheme.color("focus") if UITheme.current_high_contrast else accent().darkened(0.35)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(px(0.3))
		return sb

	static func _box(bg: Color, border: Color, width: int, pad: float) -> StyleBoxFlat:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(width)
		sb.set_corner_radius_all(px(0.3))
		sb.set_content_margin_all(pad)
		sb.shadow_color = Color(0, 0, 0, 0.3)
		sb.shadow_offset = Vector2(3, 4)
		sb.shadow_size = 1
		return sb

	static func card() -> PanelContainer:
		var c: PanelContainer = PanelContainer.new()
		c.theme_type_variation = V_CARD
		return c

	static func tile(ally: bool) -> PanelContainer:
		var c: PanelContainer = PanelContainer.new()
		c.theme_type_variation = V_TILE_ALLY if ally else V_TILE
		return c

	static func label(text: String, variation: String) -> Label:
		var l: Label = Label.new()
		l.text = text
		l.theme_type_variation = variation
		return l

	static func wrap(text: String, variation: String) -> Label:
		var l: Label = label(text, variation)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = px(8.0)
		return l

	## Etiqueta de una línea que se recorta con «…» (no fuerza el ancho de su contenedor).
	static func fit_label(text: String, variation: String) -> Label:
		var l: Label = label(text, variation)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return l

	static func pair(caption: String, value: String) -> HBoxContainer:
		var row: HBoxContainer = HBoxContainer.new()
		var cap: Label = label(caption, V_SMALL)
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cap)
		row.add_child(label(value, V_STRONG))
		return row

	static func button(text: String, primary: bool) -> Button:
		var b: Button = Button.new()
		b.text = text
		b.theme_type_variation = V_PRIMARY if primary else ""
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT if not primary else HORIZONTAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		return b

	static func text(c: CanvasItem, pos: Vector2, value: String, bold: bool, fsize: int, color: Color,
			width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		var font: Font = UITheme.font(UITheme.FONT_BOLD if bold else UITheme.FONT_REGULAR)
		var shown: String = PersonnelApp.OsKit.fit(font, value, fsize, width) if width > 0.0 else value
		c.draw_string(font, pos, shown, align, width, fsize, color)


## Confirmación dentro de la pantalla (acciones irreversibles, §13.7): velo, tarjeta y dos botones.
class ConfirmDialog extends Control:
	signal answered(yes: bool)

	const WIDTH_EM := 26.0

	static func make(title: String, body: String, yes_text: String, no_text: String) -> ConfirmDialog:
		var dialog: ConfirmDialog = ConfirmDialog.new()
		dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dialog.mouse_filter = Control.MOUSE_FILTER_STOP
		var center: CenterContainer = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dialog.add_child(center)
		var card: PanelContainer = Look.card()
		card.custom_minimum_size.x = Look.px(WIDTH_EM)
		center.add_child(card)
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", Look.px(0.8))
		card.add_child(col)
		col.add_child(Look.label(title, Look.V_HEADING))
		col.add_child(Look.wrap(body, Look.V_STRONG))
		var buttons: HBoxContainer = HBoxContainer.new()
		buttons.alignment = BoxContainer.ALIGNMENT_END
		buttons.add_theme_constant_override("separation", Look.px(0.6))
		var no: Button = Look.button(no_text, false)
		no.pressed.connect(func() -> void: dialog.answered.emit(false))
		var yes: Button = Look.button(yes_text, true)
		yes.pressed.connect(func() -> void: dialog.answered.emit(true))
		buttons.add_child(no)
		buttons.add_child(yes)
		col.add_child(buttons)
		no.call_deferred("grab_focus")
		return dialog

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			accept_event()
			answered.emit(false)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.55))


## Confianza de un inversor en miniatura: barra (verde si llega al objetivo) y cifra.
class MiniMeter extends Control:
	const HEIGHT_EM := 1.0
	const NUMBER_EM := 1.6

	var value: int = 0
	var target: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Look.px(HEIGHT_EM)

	func _draw() -> void:
		var ink: Color = Look.ink()
		var num_w: float = float(Look.px(NUMBER_EM))
		var bar: Rect2 = Rect2(0, size.y * 0.25, maxf(size.x - num_w, 1.0), size.y * 0.5)
		draw_rect(bar, Color(ink, 0.12))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(value / 100.0, 0.0, 1.0), bar.size.y)),
				Look.green() if value >= target else Look.red())
		draw_rect(bar, ink, false, 1.0)
		Look.text(self, Vector2(bar.end.x, size.y * 0.5 + Look.px(0.25)), str(value), true, Look.px(0.7), ink, num_w,
				HORIZONTAL_ALIGNMENT_RIGHT)


## Retrato de inversor (ficha de la sala).
class Portrait extends Control:
	var appearance: Dictionary = {}

	## Solo dibujo: deja pasar el arrastre al ScrollContainer (táctil).
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(r, Look.pal("light"))
		CharacterPainter.draw_portrait(self, appearance, r)
		draw_rect(r, Look.ink(), false, 2.0)


## Indicador de las tres fases.
class PhaseStepper extends Control:
	var phase: int = 0

	## Solo dibujo: deja pasar el arrastre al ScrollContainer (táctil).
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var count: int = 3
		var w: float = size.x / count
		for i: int in count:
			var r: Rect2 = Rect2(i * w + 4, size.y * 0.15, w - 8, size.y * 0.7)
			var active: bool = i == phase
			var done: bool = i < phase
			var fill: Color = Look.accent() if active else (Look.pal("light") if done else Color(0, 0, 0, 0.25))
			draw_colored_polygon(UITheme.rounded_rect_points(r, r.size.y * 0.5), fill)
			draw_polyline(UITheme.rounded_rect_points(r, r.size.y * 0.5), Look.ink() if active
					else Color(Look.pal("light"), 0.5), 2.0, true)
			var ink: Color = UITheme.readable_on(fill) if active or done else Look.pal("light")
			Look.text(self, Vector2(r.position.x, r.get_center().y + Look.px(0.28)), "%d · %s" % [i + 1,
					TranslationServer.translate(ResultsPresentation.PHASE_NAME_KEYS[i])], true, Look.px(0.72), ink,
					r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


## Cifra grande del trimestre (€) con diferencia frente a la real. Si la etiqueta y la cifra no
## caben en una línea (tarjeta estrecha), la cifra baja a una segunda línea.
class FigureRow extends Control:
	const ROW_EM := 2.2
	const STACKED_EM := 3.3
	const DELTA_EM := 4.2

	var caption: String = ""
	var value: float = 0.0
	var reference: float = 0.0
	var highlight: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Look.px(ROW_EM)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			var need: float = float(Look.px(STACKED_EM if _stacked() else ROW_EM))
			if not is_equal_approx(custom_minimum_size.y, need):
				custom_minimum_size.y = need

	func _big() -> int:
		return Look.px(1.35 if highlight else 1.1)

	func _stacked() -> bool:
		var cap_w: float = UITheme.font(UITheme.FONT_REGULAR).get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1,
				Look.px(0.8)).x
		var money_w: float = UITheme.font(UITheme.FONT_MONO).get_string_size(UITheme.format_money(roundi(value)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _big()).x
		return cap_w + money_w + Look.px(DELTA_EM + 1.0) > size.x

	func _draw() -> void:
		var ink: Color = Look.ink()
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(ink, 0.2), 1.0)
		var stacked: bool = _stacked()
		var cap_y: float = Look.px(0.9) if stacked else size.y * 0.62
		var value_y: float = size.y * 0.8 if stacked else size.y * 0.62 + _big() * 0.1
		Look.text(self, Vector2(0, cap_y), caption, false, Look.px(0.8), ink, size.x * (1.0 if stacked else 0.4))
		var font: Font = UITheme.font(UITheme.FONT_MONO)
		draw_string(font, Vector2(0, value_y), UITheme.format_money(roundi(value)), HORIZONTAL_ALIGNMENT_RIGHT,
				size.x - Look.px(DELTA_EM + 0.3), _big(), Look.red() if value < 0.0 else ink)
		if not is_equal_approx(value, reference):
			var delta: float = (value - reference) / maxf(absf(reference), 1.0) * 100.0
			draw_string(UITheme.font(UITheme.FONT_BOLD), Vector2(size.x - Look.px(DELTA_EM), value_y), "%+.0f%%" % delta,
					HORIZONTAL_ALIGNMENT_RIGHT, Look.px(DELTA_EM), Look.px(0.8), Look.red())


## Aviso (mecha de auditoría, estrado cerrado): franja de peligro y texto que se mide solo.
class WarningBox extends Control:
	const BODY_EM := 0.68
	const TOP_EM := 2.2

	var title: String = ""
	var body: String = ""
	## Variante tranquila (verde, sin franja de peligro): libros limpios.
	var calm: bool = false

	## Solo dibujo: deja pasar el arrastre al ScrollContainer (táctil).
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_fit_height()

	func _fit_height() -> void:
		var x: float = float(Look.px(1.0))
		var h: float = UITheme.font(UITheme.FONT_REGULAR).get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT,
				maxf(size.x - x - Look.px(0.5), 1.0), Look.px(BODY_EM)).y
		var need: float = Look.px(TOP_EM) + h + Look.px(0.5)
		if absf(custom_minimum_size.y - need) > 1.0:
			custom_minimum_size.y = need

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var tone: Color = Look.green() if calm else Look.red()
		draw_rect(r, Look.paper().lerp(tone, 0.08) if calm else Look.role("warn_bg"))
		var stripe: Rect2 = Rect2(0, 0, Look.px(0.6), size.y)
		draw_rect(stripe, tone if calm else UITheme.color("hazard"))
		if not calm:
			PersonnelApp.OsKit.draw_hatch(self, stripe, UITheme.color("hazard_ink"), 10.0, 3.0)
		draw_rect(r, tone, false, 2.5)
		var x: float = float(Look.px(1.0))
		UITheme.draw_icon(self, "check" if calm else "hazard", Rect2(x, Look.px(0.35), Look.px(1.1), Look.px(1.1)),
				tone, 2.5)
		Look.text(self, Vector2(x + Look.px(1.4), Look.px(1.2)), title, true, Look.px(0.8), tone, size.x - x - Look.px(1.6))
		var font: Font = UITheme.font(UITheme.FONT_REGULAR)
		draw_multiline_string(font, Vector2(x, Look.px(TOP_EM)), body, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - Look.px(0.5),
				Look.px(BODY_EM), -1, Look.ink())


## Calidad de la presentación (§9.5): pesos de market.json × preparación, reputación y aliados.
class QualityMeter extends Control:
	var preparation: float = 0.0
	var reputation: float = 0.0
	var allies: float = 0.0
	var quality: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Look.px(5.0)

	func _draw() -> void:
		var ink: Color = Look.ink()
		Look.text(self, Vector2(0, Look.px(0.8)), TranslationServer.translate("RPRES_QUALITY") % quality, true,
				Look.px(0.8), ink, size.x)
		var bar: Rect2 = Rect2(0, Look.px(1.2), size.x, Look.px(1.0))
		draw_rect(bar, Color(ink, 0.12))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(quality, 0.0, 1.0), bar.size.y)), Look.accent())
		draw_rect(bar, ink, false, 2.0)
		var parts: Array[Array] = [["RPRES_PART_PREP", "weight_preparation", preparation],
				["RPRES_PART_REP", "weight_reputation", reputation / 100.0], ["RPRES_PART_ALLIES", "weight_allies", allies]]
		var y: float = bar.end.y + Look.px(1.0)
		for part: Array in parts:
			Look.text(self, Vector2(0, y), TranslationServer.translate(str(part[0])) % [Look.weight(str(part[1])),
					float(part[2])], false, Look.px(0.66), ink.lerp(Look.paper(), 0.25), size.x)
			y += Look.px(0.95)


## Fila de reacción de un inversor: foto, estrategia, confianza antes → después y delta.
class ReactionRow extends Control:
	var data: Dictionary = {}
	var appearance: Dictionary = {}
	var strategy_name: String = ""
	var quip: String = ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Look.px(3.8)

	func _draw() -> void:
		var ink: Color = Look.ink()
		var photo: Rect2 = Rect2(0, Look.px(0.2), size.y - Look.px(0.4), size.y - Look.px(0.4))
		CharacterPainter.draw_portrait(self, appearance, photo)
		draw_rect(photo, ink, false, 2.0)
		var x: float = photo.end.x + Look.px(0.6)
		Look.text(self, Vector2(x, Look.px(1.2)), str(data.get("name", "")), true, Look.px(0.85), ink, size.x * 0.3)
		Look.text(self, Vector2(x, Look.px(2.2)), strategy_name, false, Look.px(0.68), ink.lerp(Look.paper(), 0.3), size.x * 0.3)
		var before: int = int(data.get("before", 0))
		var after: int = int(data.get("after", 0))
		var delta: int = int(data.get("delta", 0))
		var bar: Rect2 = Rect2(x + size.x * 0.28, size.y * 0.16, size.x * 0.42, size.y * 0.34)
		Look.text(self, Vector2(bar.position.x, size.y * 0.86), quip, false, Look.px(0.66), ink.lerp(Look.paper(), 0.3),
				bar.size.x + Look.px(4.0))
		draw_rect(bar, Color(ink, 0.1))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * after / 100.0, bar.size.y)),
				Look.green() if delta >= 0 else Look.red())
		var tick: float = bar.position.x + bar.size.x * before / 100.0
		draw_line(Vector2(tick, bar.position.y - 4), Vector2(tick, bar.end.y + 4), ink, 3.0)
		draw_rect(bar, ink, false, 1.5)
		Look.text(self, Vector2(bar.end.x + Look.px(0.5), bar.get_center().y + Look.px(0.3)), "%d → %d" % [before, after],
				false, Look.px(0.75), ink, Look.px(4.0))
		var badge: String = ("+%d" % delta) if delta > 0 else str(delta)
		Look.text(self, Vector2(size.x - Look.px(3.0), size.y * 0.5 + Look.px(0.4)), badge, true, Look.px(1.1),
				Look.green() if delta > 0 else (Look.red() if delta < 0 else ink), Look.px(3.0), HORIZONTAL_ALIGNMENT_RIGHT)


## La sala de resultados de la planta 16 vista en cenital 3/4: pantalla con las cifras, mesa de
## inversores (sentados, de frente) con sus preguntas y el jugador en el atril, de espaldas.
## Se repinta solo cuando cambia el fotograma de la animación o el inversor que pregunta.
class HallView extends Control:
	## Alto aproximado de una figura sin escalar, en celdas del mundo (maquetación).
	const FIGURE_CELLS := 1.55
	const CELL_PATH := "mundo.px_por_unidad"
	const PLAYER_SEED_PATH := "jugador.semilla_apariencia"
	const B_ASK_SECONDS := "presentacion_ui.segundos_por_pregunta"
	const ANIMS: Array[String] = ["chat", "sit", "idle"]

	var seats: Array[Dictionary] = []
	var figures: Dictionary = {}
	var _time: float = 0.0
	var _tick_fps: float = 1.0
	var _last_key: int = -1

	## Solo dibujo: deja pasar el arrastre al ScrollContainer (táctil).
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func setup_hall(hall_seats: Array[Dictionary], reported: Dictionary) -> void:
		seats = hall_seats
		figures = reported
		custom_minimum_size = Vector2(Look.px(30.0), Look.px(24.0))
		for anim: String in ANIMS:
			_tick_fps = maxf(_tick_fps, CharacterPainter.anim_fps(anim))

	func _process(delta: float) -> void:
		_time += delta
		var key: int = int(_time * _tick_fps) * 100 + _asking()
		if key != _last_key:
			_last_key = key
			queue_redraw()

	func _scale() -> float:
		return size.y / float(Look.px(24.0)) * 1.55

	func _figure_h() -> float:
		return Database.get_balance_float(CELL_PATH) * FIGURE_CELLS * _scale()

	func _asking() -> int:
		return int(_time / maxf(Database.get_balance_float(B_ASK_SECONDS), 0.1)) % maxi(seats.size(), 1)

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(r, Look.pal("carpet"))
		var wall: Rect2 = Rect2(0, 0, size.x, size.y * 0.3)
		draw_rect(wall, Look.pal("wall"))
		draw_rect(Rect2(0, wall.end.y - size.y * 0.06, size.x, size.y * 0.06), Look.pal("furniture"))
		draw_rect(Rect2(0, wall.end.y - 3, size.x, 6), Look.pal("accent"))
		_draw_screen(Rect2(size.x * 0.3, size.y * 0.03, size.x * 0.4, size.y * 0.22))
		_draw_stage()
		_draw_investors()
		_draw_table()
		_draw_speaker()
		_draw_transcript(Rect2(size.x * 0.015, size.y * 0.7, size.x * 0.25, size.y * 0.28), 0)
		_draw_transcript(Rect2(size.x * 0.735, size.y * 0.7, size.x * 0.25, size.y * 0.28), ceili(seats.size() / 2.0))
		draw_rect(r, Look.pal("outline"), false, 4.0)

	func _draw_screen(s: Rect2) -> void:
		var ink: Color = Look.pal("outline")
		draw_rect(s.grow(6), ink)
		draw_rect(s, Look.role("screen"))
		var text_ink: Color = UITheme.readable_on(Look.role("screen"))
		Look.text(self, s.position + Vector2(Look.px(0.5), Look.px(1.0)), TranslationServer.translate("RPRES_SCREEN_TITLE"),
				true, Look.px(0.7), text_ink, s.size.x - Look.px(1.0))
		var keys: Array[String] = ["revenue", "costs", "profit"]
		var top: float = 1.0
		for key: String in keys:
			top = maxf(top, absf(float(figures.get(key, 0.0))))
		var colors: Array[Color] = [Look.pal("accent"), Look.pal("shadow").lightened(0.35), Look.green()]
		var bw: float = s.size.x / 5.0
		for i: int in keys.size():
			var h: float = (s.size.y - Look.px(2.6)) * absf(float(figures.get(keys[i], 0.0))) / top
			var bar: Rect2 = Rect2(s.position.x + bw * (i + 1) - bw * 0.3, s.end.y - Look.px(1.2) - h, bw * 0.8, h)
			draw_rect(bar, colors[i])
			draw_rect(bar, text_ink, false, 2.0)
			Look.text(self, Vector2(bar.position.x - bw * 0.1, s.end.y - Look.px(0.35)),
					TranslationServer.translate("RPRES_FIG_" + keys[i].to_upper()), false, Look.px(0.55), text_ink, bw,
					HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_stage() -> void:
		var stage: Rect2 = Rect2(size.x * 0.28, size.y * 0.7, size.x * 0.44, size.y * 0.3)
		draw_rect(stage, Look.pal("floor"))
		var plank: float = float(Look.px(0.9))
		var y: float = stage.position.y + plank
		while y < stage.end.y:
			draw_line(Vector2(stage.position.x, y), Vector2(stage.end.x, y), Color(Look.pal("shadow"), 0.35), 1.5)
			y += plank
		draw_rect(stage, Look.pal("outline"), false, 3.0)
		draw_rect(Rect2(stage.position.x, stage.position.y, stage.size.x, 5), Look.pal("accent"))

	func _table_rect() -> Rect2:
		return Rect2(size.x * 0.06, size.y * 0.5, size.x * 0.88, size.y * 0.1)

	func _seat_x(i: int) -> float:
		var t: Rect2 = _table_rect()
		return t.position.x + t.size.x * (float(i) + 0.5) / float(maxi(seats.size(), 1))

	func _draw_investors() -> void:
		var tier: int = Database.get_balance_int(ResultsPresentationScreen.B_INVESTOR_TIER)
		var t: Rect2 = _table_rect()
		var fig_h: float = _figure_h()
		for i: int in seats.size():
			var foot: Vector2 = Vector2(_seat_x(i), t.position.y + t.size.y * 0.3)
			var back: Rect2 = Rect2(foot.x - fig_h * 0.34, foot.y - fig_h * 0.92, fig_h * 0.68, fig_h * 0.56)
			draw_colored_polygon(UITheme.rounded_rect_points(back, fig_h * 0.14), Look.pal("shadow").lightened(0.1))
			draw_polyline(UITheme.rounded_rect_points(back, fig_h * 0.14), Look.pal("outline"), 2.0, true)
			var anim: String = "chat" if _asking() == i else "sit"
			var frame: int = int(_time * CharacterPainter.anim_fps(anim)) % CharacterPainter.anim_frames(anim)
			CharacterPainter.draw(self, seats[i]["appearance"], tier, CharacterPainter.make_pose(anim, frame,
					Vector2.DOWN, {"seated": true, "scale": _scale(), "origin": foot}))
			_draw_bubble(seats[i], Vector2(foot.x + fig_h * 0.3, foot.y - fig_h * 0.95), _asking() == i)

	func _bubble_color(seat: Dictionary) -> Color:
		if bool(seat["ally"]):
			return Look.green()
		return Look.red() if str(seat["strategy"]) == "activist" else Look.pal("accent")

	func _draw_bubble(seat: Dictionary, at: Vector2, asking: bool) -> void:
		var color: Color = _bubble_color(seat)
		var s: float = float(Look.px(1.45 if asking else 1.05))
		var box: Rect2 = Rect2(at - Vector2(0.0, s * 1.2), Vector2(s, s))
		draw_colored_polygon(PackedVector2Array([box.position + Vector2(s * 0.15, s * 0.8),
				box.position + Vector2(s * 0.45, s * 0.8), at + Vector2(-s * 0.1, 0.0)]), color)
		draw_colored_polygon(UITheme.rounded_rect_points(box, s * 0.3), Look.paper())
		draw_polyline(UITheme.rounded_rect_points(box, s * 0.3), color, 3.0 if asking else 2.0, true)
		var glyph: String = "✓" if bool(seat["ally"]) else ("!" if str(seat["strategy"]) == "activist" else "?")
		Look.text(self, Vector2(box.position.x, box.get_center().y + s * 0.26), glyph, true, roundi(s * 0.72), color, s,
				HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_table() -> void:
		var t: Rect2 = _table_rect()
		var ink: Color = Look.pal("outline")
		draw_rect(Rect2(t.position + Vector2(0, 8), t.size), Color(0, 0, 0, 0.3))
		draw_colored_polygon(UITheme.rounded_rect_points(t, Look.px(0.6)), Look.pal("furniture"))
		draw_polyline(UITheme.rounded_rect_points(t, Look.px(0.6)), ink, 3.0, true)
		draw_line(t.position + Vector2(Look.px(0.6), 5), Vector2(t.end.x - Look.px(0.6), t.position.y + 5),
				Color(Look.pal("light"), 0.35), 3.0)
		for i: int in seats.size():
			var plate: Rect2 = Rect2(_seat_x(i) - Look.px(2.5), t.position.y + t.size.y * 0.42, Look.px(5.0), t.size.y * 0.42)
			draw_rect(plate, Look.pal("accent"))
			draw_rect(plate, ink, false, 1.5)
			Look.text(self, Vector2(plate.position.x, plate.get_center().y + Look.px(0.22)), str(seats[i]["name"]), true,
					Look.px(0.56), UITheme.readable_on(Look.pal("accent")), plate.size.x, HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_speaker() -> void:
		var tier: int = maxi(PlayerState.get_tier(), 1)
		var app: Dictionary = CharacterPainter.appearance_from_seed(Database.get_balance_int(PLAYER_SEED_PATH), tier,
				false, "")
		var fig_h: float = _figure_h()
		var foot: Vector2 = Vector2(size.x * 0.5, size.y * 0.97)
		var lectern: Rect2 = Rect2(foot.x - fig_h * 0.4, foot.y - fig_h * 1.16, fig_h * 0.8, fig_h * 0.4)
		draw_line(Vector2(foot.x + fig_h * 0.18, lectern.position.y), Vector2(foot.x + fig_h * 0.1,
				lectern.position.y - fig_h * 0.14), Look.pal("outline"), 3.0)
		draw_circle(Vector2(foot.x + fig_h * 0.1, lectern.position.y - fig_h * 0.14), 5.0, Look.pal("outline"))
		draw_rect(Rect2(lectern.position + Vector2(0, 6), lectern.size), Color(0, 0, 0, 0.3))
		draw_colored_polygon(UITheme.rounded_rect_points(lectern, Look.px(0.3)), Look.pal("furniture").darkened(0.12))
		draw_polyline(UITheme.rounded_rect_points(lectern, Look.px(0.3)), Look.pal("outline"), 3.0, true)
		draw_rect(Rect2(lectern.position.x + 6, lectern.position.y + 6, lectern.size.x - 12, 6), Look.pal("accent"))
		var frame: int = int(_time * CharacterPainter.anim_fps("idle")) % CharacterPainter.anim_frames("idle")
		CharacterPainter.draw(self, app, tier, CharacterPainter.make_pose("idle", frame, Vector2.UP,
				{"scale": _scale(), "origin": foot}))

	## Transcripción de las preguntas de la sala (tres por lado).
	func _draw_transcript(box: Rect2, first: int) -> void:
		var ink: Color = Look.ink()
		draw_rect(Rect2(box.position + Vector2(3, 4), box.size), Color(0, 0, 0, 0.3))
		draw_rect(box, Look.paper())
		draw_rect(box, ink, false, 2.0)
		var pad: float = float(Look.px(0.45))
		var y: float = box.position.y + pad
		var fsize: int = Look.px(0.58)
		var font: Font = UITheme.font(UITheme.FONT_REGULAR)
		for i: int in range(first, mini(first + ceili(seats.size() / 2.0), seats.size())):
			var seat: Dictionary = seats[i]
			var color: Color = _bubble_color(seat)
			draw_rect(Rect2(box.position.x + pad, y + 2, 4, fsize * 3.4), color)
			Look.text(self, Vector2(box.position.x + pad * 2.2, y + fsize), str(seat["name"]), true, fsize, color,
					box.size.x - pad * 3.0)
			draw_multiline_string(font, Vector2(box.position.x + pad * 2.2, y + fsize * 2.2), "“%s”" % seat["question"],
					HORIZONTAL_ALIGNMENT_LEFT, box.size.x - pad * 3.2, fsize, 2, ink)
			y += fsize * 4.2


## Beneficio del trimestre frente a lo que espera el mercado (§9.5: la nota de cifras).
class ExpectationChart extends Control:
	const B_BAND := "mercado.presentacion_banda_neutra"
	const NEUTRAL := 0.5

	var expected: float = 0.0
	var value: float = 0.0
	var score: float = NEUTRAL
	var band: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Look.px(5.6)

	## Titular que publicará la prensa según la sorpresa (claves de Market).
	func headline_key() -> String:
		return key_for(score, band)

	static func key_for(figures_score: float, neutral_band: float) -> String:
		if figures_score > NEUTRAL + neutral_band:
			return MarketSystem.HEADLINE_RESULTS_BEAT
		if figures_score < NEUTRAL - neutral_band:
			return MarketSystem.HEADLINE_RESULTS_MISS
		return MarketSystem.HEADLINE_RESULTS_INLINE

	func _verdict() -> Array:
		if expected <= 0.0:
			return ["RPRES_EXPECT_NONE", Look.ink()]
		if score > NEUTRAL + band:
			return ["RPRES_EXPECT_BEAT", Look.green()]
		if score < NEUTRAL - band:
			return ["RPRES_EXPECT_MISS", Look.red()]
		return ["RPRES_EXPECT_INLINE", Look.accent().darkened(0.2)]

	func _draw() -> void:
		var ink: Color = Look.ink()
		var top: float = maxf(maxf(absf(expected), absf(value)), 1.0)
		var y: float = float(Look.px(0.6))
		var bar_w: float = size.x - Look.px(6.5)
		var rows: Array[Array] = [["RPRES_EXPECT_MARKET", expected, Color(ink, 0.35)],
				["RPRES_EXPECT_YOURS", value, Look.accent()]]
		for row: Array in rows:
			Look.text(self, Vector2(0, y + Look.px(0.75)), TranslationServer.translate(str(row[0])), false, Look.px(0.66),
					ink, Look.px(6.2))
			var bar: Rect2 = Rect2(Look.px(6.5), y, bar_w * clampf(absf(float(row[1])) / top, 0.0, 1.0), Look.px(1.0))
			draw_rect(bar, row[2])
			draw_rect(bar, ink, false, 1.5)
			y += Look.px(1.5)
		var verdict: Array = _verdict()
		var chip: Rect2 = Rect2(0, y + Look.px(0.4), size.x, Look.px(1.6))
		draw_rect(chip, Color(verdict[1], 0.14))
		draw_rect(chip, verdict[1], false, 2.0)
		Look.text(self, Vector2(0, chip.get_center().y + Look.px(0.3)), TranslationServer.translate(str(verdict[0])),
				true, Look.px(0.8), verdict[1], size.x, HORIZONTAL_ALIGNMENT_CENTER)


## Confianza agregada antes → después frente al objetivo trimestral (§9.7).
class AggregateMeter extends Control:
	var before: float = 0.0
	var after: float = 0.0
	var target: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Look.px(3.4)

	func _draw() -> void:
		var ink: Color = Look.ink()
		Look.text(self, Vector2(0, Look.px(0.8)), TranslationServer.translate("RPRES_AGGREGATE") % [before, after],
				true, Look.px(0.72), ink, size.x)
		var bar: Rect2 = Rect2(0, Look.px(1.3), size.x, Look.px(1.2))
		draw_rect(bar, Color(ink, 0.1))
		var fill: Color = Look.green() if after >= target else Look.red()
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(after / 100.0, 0.0, 1.0), bar.size.y)), fill)
		var ghost: float = bar.position.x + bar.size.x * clampf(before / 100.0, 0.0, 1.0)
		draw_line(Vector2(ghost, bar.position.y), Vector2(ghost, bar.end.y), ink, 3.0)
		var tx: float = bar.position.x + bar.size.x * clampf(target / 100.0, 0.0, 1.0)
		draw_line(Vector2(tx, bar.position.y - 6), Vector2(tx, bar.end.y + 6), Look.accent().darkened(0.3), 4.0)
		draw_rect(bar, ink, false, 2.0)
		Look.text(self, Vector2(tx - Look.px(3.0), bar.end.y + Look.px(0.85)), TranslationServer.translate("RPRES_TARGET_TICK"),
				false, Look.px(0.6), ink, Look.px(6.0), HORIZONTAL_ALIGNMENT_CENTER)


## Desglose de los costes reales (por jornada) en una barra apilada con leyenda (§9.2, §9.10).
## Colores: la paleta de la banda de la sala y los roles de datos (alto contraste: UITheme).
class CostBreakdown extends Control:
	const BLOCK_EM := 6.0
	const KEYS: Array[String] = ["materials", "payroll", "overheads", "legal", "theft_losses", "scandal_costs"]
	const BAND_KEYS: Array[String] = ["furniture", "accent", "window", "carpet", "", ""]
	const ROLE_KEYS: Array[String] = ["", "", "", "", "red", "scandal"]
	const CONTRAST_KEYS: Array[String] = ["paper", "hazard", "rep", "faint", "loss", "det_partial"]

	var fundamentals: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Look.px(BLOCK_EM)
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	static func color_of(i: int) -> Color:
		if UITheme.current_high_contrast:
			return UITheme.color(CONTRAST_KEYS[i])
		return Look.pal(BAND_KEYS[i]) if not BAND_KEYS[i].is_empty() else Look.role(ROLE_KEYS[i])

	func _draw() -> void:
		var ink: Color = Look.ink()
		Look.text(self, Vector2(0, Look.px(0.9)), TranslationServer.translate("RPRES_COSTS_TITLE"), true,
				Look.px(0.72), ink, size.x)
		var total: float = 0.0
		for key: String in KEYS:
			total += maxf(float(fundamentals.get(key, 0.0)), 0.0)
		var bar: Rect2 = Rect2(0, Look.px(1.3), size.x, Look.px(1.1))
		var x: float = bar.position.x
		for i: int in KEYS.size():
			var w: float = bar.size.x * maxf(float(fundamentals.get(KEYS[i], 0.0)), 0.0) / maxf(total, 1.0)
			draw_rect(Rect2(x, bar.position.y, w, bar.size.y), color_of(i))
			x += w
		draw_rect(bar, ink, false, 2.0)
		var col_w: float = size.x / 2.0
		for i: int in KEYS.size():
			var at: Vector2 = Vector2(col_w * (i % 2), bar.end.y + Look.px(0.9) + Look.px(0.95) * floori(i / 2.0))
			draw_rect(Rect2(at + Vector2(0, -Look.px(0.55)), Vector2(Look.px(0.6), Look.px(0.6))), color_of(i))
			var share: float = maxf(float(fundamentals.get(KEYS[i], 0.0)), 0.0) / maxf(total, 1.0) * 100.0
			Look.text(self, at + Vector2(Look.px(0.9), 0), TranslationServer.translate("RPRES_COST_" + KEYS[i].to_upper())
					+ "  %.0f%%" % share, false, Look.px(0.62), ink, col_w - Look.px(1.0))


## Portada del diario financiero de mañana con el titular que provocarán las cifras. Su alto sale
## del titular medido (cabecera, doble filete, titular y tres líneas de texto de relleno).
class HeadlinePreview extends Control:
	const PAD_EM := 0.6
	const MAST_EM := 0.8
	const HEAD_EM := 0.9
	const FILLER_EM := 0.45
	const FILLER_LINES := 3

	var headline: String = ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size.y = Look.px(PAD_EM * 2.0 + MAST_EM * 2.0 + HEAD_EM * 2.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			var need: float = _layout_height()
			if absf(custom_minimum_size.y - need) > 1.0:
				custom_minimum_size.y = need

	func _headline_h() -> float:
		var width: float = maxf(size.x - Look.px(PAD_EM) * 2.0, 1.0)
		return UITheme.font(UITheme.FONT_BOLD).get_multiline_string_size(headline, HORIZONTAL_ALIGNMENT_LEFT,
				width, Look.px(HEAD_EM)).y

	func _layout_height() -> float:
		return Look.px(PAD_EM) * 2.0 + Look.px(MAST_EM * 1.7) + _headline_h() \
				+ Look.px(FILLER_EM) * (FILLER_LINES + 1) + Look.px(0.3)

	func _draw() -> void:
		var ink: Color = Look.ink()
		var r: Rect2 = Rect2(0, Look.px(0.15), size.x, size.y - Look.px(0.3))
		draw_set_transform(r.get_center(), -0.015, Vector2.ONE)
		var local: Rect2 = Rect2(-r.size * 0.5, r.size)
		draw_rect(Rect2(local.position + Vector2(4, 5), local.size), Color(0, 0, 0, 0.18))
		draw_rect(local, Look.role("newsprint"))
		draw_rect(local, ink, false, 1.5)
		var pad: float = float(Look.px(PAD_EM))
		var width: float = local.size.x - pad * 2.0
		Look.text(self, local.position + Vector2(pad, pad + Look.px(MAST_EM)), TranslationServer.translate("RPRES_PAPER"),
				true, Look.px(MAST_EM), ink, width, HORIZONTAL_ALIGNMENT_CENTER)
		var rule_y: float = local.position.y + pad + Look.px(MAST_EM * 1.35)
		draw_line(Vector2(local.position.x + pad, rule_y), Vector2(local.end.x - pad, rule_y), ink, 2.0)
		draw_line(Vector2(local.position.x + pad, rule_y + 4), Vector2(local.end.x - pad, rule_y + 4), ink, 1.0)
		draw_multiline_string(UITheme.font(UITheme.FONT_BOLD), Vector2(local.position.x + pad, rule_y + Look.px(HEAD_EM * 1.25)),
				headline, HORIZONTAL_ALIGNMENT_LEFT, width, Look.px(HEAD_EM), -1, ink)
		for i: int in FILLER_LINES:
			var y: float = local.end.y - pad - Look.px(FILLER_EM) * float(i)
			draw_line(Vector2(local.position.x + pad, y), Vector2(local.end.x - pad - Look.px(2.0) * i, y),
					Color(ink, 0.25), 3.0)
		draw_set_transform(Vector2.ZERO)
