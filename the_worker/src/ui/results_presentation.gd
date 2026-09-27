# results_presentation.gd — Pantalla de la presentación trimestral de resultados (§9.5): preparación (cifras reales o ajustadas y aviso de la mecha de auditoría), presentación en la sala de la planta 16 (preguntas de los inversores y nivel de preparación según cómo se produjo el informe) y reacción de cada inversor.
# PROPIETARIO DE: la sesión de ResultsPresentation en curso (fase, inflado elegido, nivel de preparación) y el estado de la pantalla.
# ESCUCHA: nada (conduce src/simulation/results_presentation_logic.gd).
class_name ResultsPresentationScreen
extends Control

## Uso: ResultsPresentationScreen.open(host, trimestre) al recibir results_presentation_due (o al
## interactuar con el atril de results_room). host UIRoot → ventana modal que pausa el reloj.
## API: choose_inflation(f) (solo cargos autorizados, Company.can_set_reported_figures), confirm_figures(),
## available_levels() -> {nivel: bool}, select_preparation(nivel), present() -> resultado de Market,
## finish(). La fase la lleva ResultsPresentation (get_phase()).
## DECISIONES: el nivel de preparación sale de cómo se produjo el informe (§9.5): «sin preparar» y
## «A.S.S.I.S.T.» siempre; «informe robado al COO» si el jugador lleva
## presentacion_ui.objeto_informe_coo o completó un deber de informe (presentacion_ui.subtipos_informe)
## con un método de presentacion_ui.metodos_informe_robado; «trabajo real» si lo completó con un
## método de presentacion_ui.metodos_trabajo_real. La sala usa la paleta de la banda de la planta
## de Market.get_presentation_room(). Las preguntas son decorativas: aliados (sobornados o
## chantajeados) preguntan a favor; el resto, según su estrategia (§9.6).

signal close_requested

const LEVELS: Array[String] = [
	ResultsPresentation.LEVEL_NONE, ResultsPresentation.LEVEL_ASSIST,
	ResultsPresentation.LEVEL_STOLEN_REPORT, ResultsPresentation.LEVEL_REAL_WORK,
]
const FIGURES: Array[String] = ["revenue", "costs", "profit"]
const B_STEP := "presentacion_ui.paso_inflado"
const B_CAP := "mercado.inflado_maximo_reportado"
const B_COO_ITEM := "presentacion_ui.objeto_informe_coo"
const B_REPORT_SUBTYPES := "presentacion_ui.subtipos_informe"
const B_REAL_METHODS := "presentacion_ui.metodos_trabajo_real"
const B_STOLEN_METHODS := "presentacion_ui.metodos_informe_robado"
const B_INVESTOR_TIER := "presentacion_ui.escalon_inversor"
const STATUS_COMPLETED := "completed"
const SIDE_EM := 24.0

var _quarter: int = 0
var _logic: ResultsPresentation
var _inflation: float = 0.0
var _level: String = ResultsPresentation.LEVEL_NONE
var _result: Dictionary = {}
var _message: String = ""
var _in_ui_root: bool = false
var _built: bool = false
var _body: MarginContainer
var _stepper: PhaseStepper


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


func get_phase() -> ResultsPresentation.Phase:
	return _logic.phase


func get_logic() -> ResultsPresentation:
	return _logic


func request_close() -> void:
	close_requested.emit()
	if not _in_ui_root:
		queue_free()


func _build() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, Look.px(1.0))
	col.add_theme_constant_override("separation", Look.px(0.6))
	add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
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
	col.add_child(_body)


func _rebuild() -> void:
	if not _built:
		return
	for child: Node in _body.get_children():
		child.queue_free()
	_stepper.phase = int(_logic.phase)
	_stepper.queue_redraw()
	match _logic.phase:
		ResultsPresentation.Phase.PREPARATION:
			_body.add_child(_build_preparation())
		ResultsPresentation.Phase.PRESENTATION:
			_body.add_child(_build_presentation())
		_:
			_body.add_child(_build_reaction())


# ═══ Fase 1: preparación ══════════════════════════════════════════════

func can_adjust() -> bool:
	return Company.can_set_reported_figures()


func get_inflation() -> float:
	return _inflation


## Elige el inflado de ingresos que se comunicará (0 = cifras reales). false si no está permitido.
func choose_inflation(value: float) -> bool:
	if _logic.phase != ResultsPresentation.Phase.PREPARATION or (value > 0.0 and not can_adjust()):
		return false
	_inflation = clampf(value, 0.0, Database.get_balance_float(B_CAP))
	_rebuild()
	return true


## Cierra la preparación comunicando las cifras elegidas (Company enciende la mecha si divergen).
func confirm_figures() -> bool:
	if _logic.phase != ResultsPresentation.Phase.PREPARATION:
		return false
	var ok: bool = _logic.report_inflated_figures(_inflation) if _inflation > 0.0 else _logic.keep_real_figures()
	_logic.confirm_figures()
	_rebuild()
	return ok


## Aviso de la mecha (§9.2): {divergence, weeks, probability} del inflado elegido.
func audit_preview() -> Dictionary:
	var real: Dictionary = Company.get_fundamentals()
	var divergence: float = CompanySystem.compute_divergence(real,
			ResultsPresentation.inflate_figures(real, _inflation))
	return {"divergence": divergence, "weeks": Company.compute_fuse_weeks(divergence),
			"probability": Company.get_audit_detection_probability()}


func _build_preparation() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", Look.px(1.0))
	var real: Dictionary = _logic.get_quarter_real_figures()
	var shown: Dictionary = ResultsPresentation.inflate_figures(real, _inflation)
	row.add_child(_figure_card(tr("RPRES_REAL"), tr("RPRES_REAL_SUB"), real, {}))
	row.add_child(_figure_card(tr("RPRES_REPORTED"), tr("RPRES_REPORTED_SUB"), shown, real))
	row.add_child(_preparation_side())
	return row


func _figure_card(title: String, subtitle: String, figures: Dictionary, against: Dictionary) -> Control:
	var card: PanelContainer = Look.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	return card


func _preparation_side() -> Control:
	var card: PanelContainer = Look.card()
	card.custom_minimum_size.x = Look.px(SIDE_EM)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.55))
	card.add_child(box)
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
		box.add_child(_inflation_slider(step))
		box.add_child(_audit_box())
	box.add_child(_allies_box())
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var go: Button = Look.button(tr("RPRES_CONFIRM_FIGURES"), true)
	go.pressed.connect(confirm_figures)
	box.add_child(go)
	return card


func _inflation_slider(step: float) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(Look.label(tr("RPRES_INFLATION") % roundi(_inflation * 100.0), Look.V_STRONG))
	var slider: HSlider = HSlider.new()
	slider.min_value = step
	slider.max_value = Database.get_balance_float(B_CAP)
	slider.step = step
	slider.value = _inflation
	slider.drag_ended.connect(func(_changed: bool) -> void: choose_inflation(slider.value))
	box.add_child(slider)
	return box


func _audit_box() -> Control:
	var preview: Dictionary = audit_preview()
	var warn: WarningBox = WarningBox.new()
	warn.title = tr("RPRES_FUSE_TITLE")
	warn.body = tr("RPRES_FUSE_BODY") % [int(preview["weeks"]), roundi(float(preview["probability"]) * 100.0)]
	return warn


func _allies_box() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var allies: Array[String] = Market.get_investor_allies()
	box.add_child(Look.label(tr("RPRES_ALLIES") % allies.size(), Look.V_STRONG))
	var names: PackedStringArray = PackedStringArray()
	for investor_id: String in allies:
		var inv: InvestorData = Market.get_investor(investor_id)
		if inv != null:
			names.append(inv.name)
	box.add_child(Look.wrap(", ".join(names) if not names.is_empty() else tr("RPRES_ALLIES_NONE"), Look.V_SMALL))
	return box


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
func present() -> Dictionary:
	if _logic.phase != ResultsPresentation.Phase.PRESENTATION:
		return {}
	_logic.select_preparation(_level)
	_result = _logic.present()
	if _result.is_empty():
		_message = tr("RPRES_NOT_TODAY") % Market.get_presentation_day()
	_rebuild()
	return _result.duplicate(true)


func _build_presentation() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", Look.px(1.0))
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
				"question": tr("RPRES_Q_ALLY") if ally else tr("RPRES_Q_" + inv.strategy.to_upper())})
	return out


func _presentation_side() -> Control:
	var card: PanelContainer = Look.card()
	card.custom_minimum_size.x = Look.px(SIDE_EM)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.45))
	card.add_child(box)
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
	if not _message.is_empty():
		box.add_child(Look.wrap(_message, Look.V_WARN))
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var go: Button = Look.button(tr("RPRES_PRESENT"), true)
	go.pressed.connect(present)
	box.add_child(go)
	return card


# ═══ Fase 3: reacción ═════════════════════════════════════════════════

func _build_reaction() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", Look.px(1.0))
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
		box.add_child(line)
	row.add_child(table)
	row.add_child(_summary_side())
	return row


func _summary_side() -> Control:
	var card: PanelContainer = Look.card()
	card.custom_minimum_size.x = Look.px(SIDE_EM)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", Look.px(0.45))
	card.add_child(box)
	var summary: Dictionary = _logic.get_summary()
	box.add_child(Look.label(tr("RPRES_VERDICT"), Look.V_HEADING))
	var met: bool = bool(summary.get("meeting_target", false))
	box.add_child(Look.wrap(tr("RPRES_TARGET_MET" if met else "RPRES_TARGET_MISSED"), Look.V_BIG))
	for pair: Array in [["RPRES_SUM_QUALITY", "%.2f" % float(summary.get("quality", 0.0))],
			["RPRES_SUM_CONFIDENCE", "%.1f / %.1f" % [Market.get_aggregate_confidence(), float(summary.get("target", 0.0))]],
			["RPRES_SUM_SENTIMENT", "%+.3f" % float(summary.get("sentiment_delta", 0.0))],
			["RPRES_SUM_ALLIES", str(int(summary.get("allies_present", 0)))]]:
		box.add_child(Look.pair(tr(pair[0]), str(pair[1])))
	var assist: String = str(summary.get("assist_outcome", ""))
	if not assist.is_empty():
		box.add_child(Look.wrap(tr("RPRES_ASSIST_" + assist.to_upper()), Look.V_WARN))
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var done: Button = Look.button(tr("RPRES_LEAVE"), true)
	done.pressed.connect(finish)
	box.add_child(done)
	return card


func finish() -> void:
	_logic.finish()
	request_close()


# ═══ Aspecto: sala de la planta 16 (paleta de su banda) ═══════════════

## Paleta de la banda de la sala, tipografía y tema de la pantalla.
class Look extends RefCounted:
	const V_KICKER := "RpKicker"
	const V_TITLE := "RpTitle"
	const V_HEADING := "RpHeading"
	const V_SMALL := "RpSmall"
	const V_STRONG := "RpStrong"
	const V_BIG := "RpBig"
	const V_WARN := "RpWarn"
	const V_PRIMARY := "RpPrimary"
	const V_CARD := "RpCard"
	const PAPER := Color("#f8f1df")
	const RED := Color("#b8352a")
	const GREEN := Color("#2f7d45")

	static var _themes: Dictionary = {}

	static func base_size() -> int:
		return UITheme.base_font_size(UITheme.current_text_size)

	static func px(em: float) -> int:
		return roundi(base_size() * em)

	static func hall_floor() -> int:
		var room: RoomData = Database.get_room(Market.get_presentation_room())
		return room.floor if room != null else 0

	static func pal(key: String) -> Color:
		return Color(str(UITheme.band_palette_for_floor(hall_floor()).get(key, "#808080")))

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

	static func build_theme() -> Theme:
		var key: String = "%d" % base_size()
		if _themes.has(key):
			return _themes[key]
		var t: Theme = Theme.new()
		t.default_font = UITheme.font(UITheme.FONT_REGULAR)
		t.default_font_size = px(0.8)
		var ink: Color = pal("outline")
		for spec: Array in [[V_KICKER, UITheme.FONT_BOLD, 0.75, pal("light")], [V_TITLE, UITheme.FONT_BOLD, 1.7, PAPER],
				[V_HEADING, UITheme.FONT_BOLD, 0.95, ink], [V_SMALL, UITheme.FONT_REGULAR, 0.72, ink.lightened(0.3)],
				[V_STRONG, UITheme.FONT_SEMIBOLD, 0.82, ink], [V_BIG, UITheme.FONT_BOLD, 1.15, ink],
				[V_WARN, UITheme.FONT_SEMIBOLD, 0.78, RED]]:
			t.set_type_variation(spec[0], "Label")
			t.set_font("font", spec[0], UITheme.font(spec[1]))
			t.set_font_size("font_size", spec[0], px(float(spec[2])))
			t.set_color("font_color", spec[0], spec[3])
		_buttons(t, ink)
		t.set_type_variation(V_CARD, "PanelContainer")
		t.set_stylebox("panel", V_CARD, _box(PAPER, ink, 3, px(0.9)))
		t.set_stylebox("slider", "HSlider", _box(PAPER.darkened(0.1), ink, 2, 4))
		t.set_stylebox("grabber_area", "HSlider", _box(pal("accent"), ink, 2, 4))
		t.set_stylebox("grabber_area_highlight", "HSlider", _box(pal("accent"), ink, 2, 4))
		t.set_color("font_color", "TooltipLabel", ink)
		t.set_stylebox("panel", "TooltipPanel", _box(PAPER, ink, 2, px(0.4)))
		_themes[key] = t
		return t

	static func _buttons(t: Theme, ink: Color) -> void:
		t.set_stylebox("normal", "Button", _box(PAPER, ink, 2, px(0.45)))
		t.set_stylebox("hover", "Button", _box(pal("light"), ink, 2, px(0.45)))
		t.set_stylebox("pressed", "Button", _box(pal("accent"), ink, 3, px(0.45)))
		t.set_stylebox("disabled", "Button", _box(PAPER.darkened(0.12), ink.lightened(0.5), 2, px(0.45)))
		t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
		t.set_font("font", "Button", UITheme.font(UITheme.FONT_SEMIBOLD))
		t.set_font_size("font_size", "Button", px(0.78))
		for name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
				"font_hover_pressed_color"]:
			t.set_color(name, "Button", ink)
		t.set_color("font_disabled_color", "Button", ink.lightened(0.5))
		t.set_type_variation(V_PRIMARY, "Button")
		t.set_stylebox("normal", V_PRIMARY, _box(pal("accent"), ink, 3, px(0.55)))
		t.set_stylebox("hover", V_PRIMARY, _box(pal("accent").lightened(0.15), ink, 3, px(0.55)))
		t.set_stylebox("pressed", V_PRIMARY, _box(pal("accent").darkened(0.15), ink, 3, px(0.55)))
		t.set_font("font", V_PRIMARY, UITheme.font(UITheme.FONT_BOLD))
		t.set_font_size("font_size", V_PRIMARY, px(0.9))

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
		return b

	static func text(c: CanvasItem, pos: Vector2, value: String, bold: bool, fsize: int, color: Color,
			width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		var font: Font = UITheme.font(UITheme.FONT_BOLD if bold else UITheme.FONT_REGULAR)
		var shown: String = PersonnelApp.OsKit.fit(font, value, fsize, width) if width > 0.0 else value
		c.draw_string(font, pos, shown, align, width, fsize, color)


## Indicador de las tres fases.
class PhaseStepper extends Control:
	var phase: int = 0

	func _draw() -> void:
		var count: int = 3
		var w: float = size.x / count
		for i: int in count:
			var r: Rect2 = Rect2(i * w + 4, size.y * 0.15, w - 8, size.y * 0.7)
			var active: bool = i == phase
			var done: bool = i < phase
			draw_colored_polygon(UITheme.rounded_rect_points(r, r.size.y * 0.5),
					Look.pal("accent") if active else (Look.pal("light") if done else Color(0, 0, 0, 0.25)))
			draw_polyline(UITheme.rounded_rect_points(r, r.size.y * 0.5), Look.pal("outline") if active
					else Color(Look.pal("light"), 0.5), 2.0, true)
			var ink: Color = Look.pal("outline") if active or done else Look.pal("light")
			Look.text(self, Vector2(r.position.x, r.get_center().y + Look.px(0.28)), "%d · %s" % [i + 1,
					TranslationServer.translate(ResultsPresentation.PHASE_NAME_KEYS[i])], true, Look.px(0.72), ink,
					r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


## Cifra grande del trimestre (€) con diferencia frente a la real.
class FigureRow extends Control:
	var caption: String = ""
	var value: float = 0.0
	var reference: float = 0.0
	var highlight: bool = false

	func _init() -> void:
		custom_minimum_size.y = Look.px(2.6)

	func _draw() -> void:
		var ink: Color = Look.pal("outline")
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(ink, 0.2), 1.0)
		Look.text(self, Vector2(0, size.y * 0.62), caption, false, Look.px(0.8), ink, size.x * 0.4)
		var big: int = Look.px(1.35 if highlight else 1.1)
		var shown: String = UITheme.format_money(roundi(value))
		var font: Font = UITheme.font(UITheme.FONT_MONO)
		draw_string(font, Vector2(0, size.y * 0.62 + big * 0.1), shown, HORIZONTAL_ALIGNMENT_RIGHT, size.x - Look.px(4.5),
				big, Look.RED if value < 0.0 else ink)
		if not is_equal_approx(value, reference):
			var delta: float = (value - reference) / maxf(absf(reference), 1.0) * 100.0
			draw_string(UITheme.font(UITheme.FONT_BOLD), Vector2(size.x - Look.px(4.2), size.y * 0.62), "%+.0f%%" % delta,
					HORIZONTAL_ALIGNMENT_RIGHT, Look.px(4.2), Look.px(0.8), Look.RED)


## Aviso de la mecha de auditoría: franja de peligro y texto.
class WarningBox extends Control:
	var title: String = ""
	var body: String = ""

	func _init() -> void:
		custom_minimum_size.y = Look.px(4.2)

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("#fff4d6"))
		var stripe: Rect2 = Rect2(0, 0, Look.px(0.6), size.y)
		draw_rect(stripe, UITheme.color("hazard"))
		PersonnelApp.OsKit.draw_hatch(self, stripe, Look.pal("outline"), 10.0, 3.0)
		draw_rect(r, Look.RED, false, 2.5)
		var x: float = float(Look.px(1.0))
		UITheme.draw_icon(self, "hazard", Rect2(x, Look.px(0.35), Look.px(1.1), Look.px(1.1)), Look.RED, 2.5)
		Look.text(self, Vector2(x + Look.px(1.4), Look.px(1.2)), title, true, Look.px(0.8), Look.RED, size.x - x - Look.px(1.6))
		var font: Font = UITheme.font(UITheme.FONT_REGULAR)
		draw_multiline_string(font, Vector2(x, Look.px(2.2)), body, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - Look.px(0.5),
				Look.px(0.68), 3, Look.pal("outline"))


## Calidad de la presentación (§9.5): 0,4 × preparación + 0,3 × reputación + 0,3 × aliados.
class QualityMeter extends Control:
	var preparation: float = 0.0
	var reputation: float = 0.0
	var allies: float = 0.0
	var quality: float = 0.0

	func _init() -> void:
		custom_minimum_size.y = Look.px(5.0)

	func _draw() -> void:
		var ink: Color = Look.pal("outline")
		Look.text(self, Vector2(0, Look.px(0.8)), TranslationServer.translate("RPRES_QUALITY") % quality, true,
				Look.px(0.8), ink, size.x)
		var bar: Rect2 = Rect2(0, Look.px(1.2), size.x, Look.px(1.0))
		draw_rect(bar, Color(ink, 0.12))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(quality, 0.0, 1.0), bar.size.y)), Look.pal("accent"))
		draw_rect(bar, ink, false, 2.0)
		var parts: Array[Array] = [["RPRES_PART_PREP", preparation], ["RPRES_PART_REP", reputation / 100.0],
				["RPRES_PART_ALLIES", allies]]
		var y: float = bar.end.y + Look.px(1.0)
		for part: Array in parts:
			Look.text(self, Vector2(0, y), TranslationServer.translate(str(part[0])) % float(part[1]), false,
					Look.px(0.66), ink.lightened(0.25), size.x)
			y += Look.px(0.95)


## Fila de reacción de un inversor: foto, estrategia, confianza antes → después y delta.
class ReactionRow extends Control:
	var data: Dictionary = {}
	var appearance: Dictionary = {}
	var strategy_name: String = ""

	func _init() -> void:
		custom_minimum_size.y = Look.px(3.0)

	func _draw() -> void:
		var ink: Color = Look.pal("outline")
		var photo: Rect2 = Rect2(0, Look.px(0.2), size.y - Look.px(0.4), size.y - Look.px(0.4))
		CharacterPainter.draw_portrait(self, appearance, photo)
		draw_rect(photo, ink, false, 2.0)
		var x: float = photo.end.x + Look.px(0.6)
		Look.text(self, Vector2(x, Look.px(1.2)), str(data.get("name", "")), true, Look.px(0.85), ink, size.x * 0.3)
		Look.text(self, Vector2(x, Look.px(2.2)), strategy_name, false, Look.px(0.68), ink.lightened(0.3), size.x * 0.3)
		var before: int = int(data.get("before", 0))
		var after: int = int(data.get("after", 0))
		var delta: int = int(data.get("delta", 0))
		var bar: Rect2 = Rect2(x + size.x * 0.28, size.y * 0.3, size.x * 0.42, size.y * 0.4)
		draw_rect(bar, Color(ink, 0.1))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * after / 100.0, bar.size.y)),
				Look.GREEN if delta >= 0 else Look.RED)
		var tick: float = bar.position.x + bar.size.x * before / 100.0
		draw_line(Vector2(tick, bar.position.y - 4), Vector2(tick, bar.end.y + 4), ink, 3.0)
		draw_rect(bar, ink, false, 1.5)
		Look.text(self, Vector2(bar.end.x + Look.px(0.5), size.y * 0.5 + Look.px(0.3)), "%d → %d" % [before, after],
				false, Look.px(0.75), ink, Look.px(4.0))
		var badge: String = ("+%d" % delta) if delta > 0 else str(delta)
		Look.text(self, Vector2(size.x - Look.px(3.0), size.y * 0.5 + Look.px(0.4)), badge, true, Look.px(1.1),
				Look.GREEN if delta > 0 else (Look.RED if delta < 0 else ink), Look.px(3.0), HORIZONTAL_ALIGNMENT_RIGHT)


## La sala de resultados de la planta 16 vista en cenital 3/4: pantalla con las cifras, mesa de
## inversores (sentados, de frente) con sus preguntas y el jugador en el atril, de espaldas.
class HallView extends Control:
	## Alto aproximado de una figura sin escalar, en celdas del mundo (maquetación).
	const FIGURE_CELLS := 1.55
	const CELL_PATH := "mundo.px_por_unidad"
	const PLAYER_SEED_PATH := "jugador.semilla_apariencia"
	const ASK_SECONDS := 2.0

	var seats: Array[Dictionary] = []
	var figures: Dictionary = {}
	var _time: float = 0.0

	func setup_hall(hall_seats: Array[Dictionary], reported: Dictionary) -> void:
		seats = hall_seats
		figures = reported
		custom_minimum_size = Vector2(Look.px(30.0), Look.px(24.0))

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _scale() -> float:
		return size.y / float(Look.px(24.0)) * 1.55

	func _figure_h() -> float:
		return Database.get_balance_float(CELL_PATH) * FIGURE_CELLS * _scale()

	func _asking() -> int:
		return int(_time / ASK_SECONDS) % maxi(seats.size(), 1)

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
		_draw_transcript(Rect2(size.x * 0.015, size.y * 0.66, size.x * 0.25, size.y * 0.32), 0)
		_draw_transcript(Rect2(size.x * 0.735, size.y * 0.66, size.x * 0.25, size.y * 0.32), (seats.size() + 1) / 2)
		draw_rect(r, Look.pal("outline"), false, 4.0)

	func _draw_screen(s: Rect2) -> void:
		var ink: Color = Look.pal("outline")
		draw_rect(s.grow(6), ink)
		draw_rect(s, Color("#fbfbf7"))
		Look.text(self, s.position + Vector2(Look.px(0.5), Look.px(1.0)), TranslationServer.translate("RPRES_SCREEN_TITLE"),
				true, Look.px(0.7), ink, s.size.x - Look.px(1.0))
		var keys: Array[String] = ["revenue", "costs", "profit"]
		var top: float = 1.0
		for key: String in keys:
			top = maxf(top, absf(float(figures.get(key, 0.0))))
		var colors: Array[Color] = [Look.pal("accent"), Look.pal("shadow").lightened(0.35), Look.GREEN]
		var bw: float = s.size.x / 5.0
		for i: int in keys.size():
			var h: float = (s.size.y - Look.px(2.6)) * absf(float(figures.get(keys[i], 0.0))) / top
			var bar: Rect2 = Rect2(s.position.x + bw * (i + 1) - bw * 0.3, s.end.y - Look.px(1.2) - h, bw * 0.8, h)
			draw_rect(bar, colors[i])
			draw_rect(bar, ink, false, 2.0)
			Look.text(self, Vector2(bar.position.x - bw * 0.1, s.end.y - Look.px(0.35)),
					TranslationServer.translate("RPRES_FIG_" + keys[i].to_upper()), false, Look.px(0.55), ink, bw,
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
			var foot: Vector2 = Vector2(_seat_x(i), t.end.y - t.size.y * 0.15)
			var back: Rect2 = Rect2(foot.x - fig_h * 0.42, foot.y - fig_h * 1.05, fig_h * 0.84, fig_h * 0.8)
			draw_colored_polygon(UITheme.rounded_rect_points(back, fig_h * 0.18), Color("#2a1d18"))
			draw_polyline(UITheme.rounded_rect_points(back, fig_h * 0.18), Look.pal("outline"), 2.0, true)
			var anim: String = "chat" if _asking() == i else "sit"
			var frame: int = int(_time * CharacterPainter.anim_fps(anim)) % CharacterPainter.anim_frames(anim)
			CharacterPainter.draw(self, seats[i]["appearance"], tier, CharacterPainter.make_pose(anim, frame,
					Vector2.DOWN, {"seated": true, "scale": _scale(), "origin": foot}))
			_draw_bubble(seats[i], Vector2(foot.x + fig_h * 0.34, foot.y - fig_h * 1.02), _asking() == i)

	func _bubble_color(seat: Dictionary) -> Color:
		if bool(seat["ally"]):
			return Look.GREEN
		return Look.RED if str(seat["strategy"]) == "activist" else Look.pal("accent")

	func _draw_bubble(seat: Dictionary, at: Vector2, asking: bool) -> void:
		var color: Color = _bubble_color(seat)
		var s: float = float(Look.px(1.45 if asking else 1.05))
		var box: Rect2 = Rect2(at - Vector2(0.0, s * 1.2), Vector2(s, s))
		draw_colored_polygon(PackedVector2Array([box.position + Vector2(s * 0.15, s * 0.8),
				box.position + Vector2(s * 0.45, s * 0.8), at + Vector2(-s * 0.1, 0.0)]), color)
		draw_colored_polygon(UITheme.rounded_rect_points(box, s * 0.3), Color.WHITE)
		draw_polyline(UITheme.rounded_rect_points(box, s * 0.3), color, 3.0 if asking else 2.0, true)
		var glyph: String = "✓" if bool(seat["ally"]) else ("!" if color == Look.RED else "?")
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
					Look.px(0.56), ink, plate.size.x, HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_speaker() -> void:
		var tier: int = maxi(PlayerState.get_tier(), 1)
		var app: Dictionary = CharacterPainter.appearance_from_seed(Database.get_balance_int(PLAYER_SEED_PATH), tier,
				false, "")
		var fig_h: float = _figure_h()
		var foot: Vector2 = Vector2(size.x * 0.5, size.y * 0.97)
		var lectern: Rect2 = Rect2(foot.x - fig_h * 0.55, foot.y - fig_h * 1.25, fig_h * 1.1, fig_h * 0.62)
		draw_rect(Rect2(lectern.position + Vector2(0, 6), lectern.size), Color(0, 0, 0, 0.3))
		draw_colored_polygon(UITheme.rounded_rect_points(lectern, Look.px(0.3)), Look.pal("furniture").darkened(0.12))
		draw_polyline(UITheme.rounded_rect_points(lectern, Look.px(0.3)), Look.pal("outline"), 3.0, true)
		draw_rect(Rect2(lectern.position.x + 6, lectern.position.y + 6, lectern.size.x - 12, 6), Look.pal("accent"))
		var frame: int = int(_time * CharacterPainter.anim_fps("idle")) % CharacterPainter.anim_frames("idle")
		CharacterPainter.draw(self, app, tier, CharacterPainter.make_pose("idle", frame, Vector2.UP,
				{"scale": _scale(), "origin": foot}))

	## Transcripción de las preguntas de la sala (tres por lado).
	func _draw_transcript(box: Rect2, first: int) -> void:
		var ink: Color = Look.pal("outline")
		draw_rect(Rect2(box.position + Vector2(3, 4), box.size), Color(0, 0, 0, 0.3))
		draw_rect(box, Look.PAPER)
		draw_rect(box, ink, false, 2.0)
		var pad: float = float(Look.px(0.45))
		var y: float = box.position.y + pad
		var fsize: int = Look.px(0.58)
		var font: Font = UITheme.font(UITheme.FONT_REGULAR)
		for i: int in range(first, mini(first + (seats.size() + 1) / 2, seats.size())):
			var seat: Dictionary = seats[i]
			var color: Color = _bubble_color(seat)
			draw_rect(Rect2(box.position.x + pad, y + 2, 4, fsize * 3.4), color)
			Look.text(self, Vector2(box.position.x + pad * 2.2, y + fsize), str(seat["name"]), true, fsize, color,
					box.size.x - pad * 3.0)
			draw_multiline_string(font, Vector2(box.position.x + pad * 2.2, y + fsize * 2.2), "“%s”" % seat["question"],
					HORIZONTAL_ALIGNMENT_LEFT, box.size.x - pad * 3.2, fsize, 2, ink)
			y += fsize * 4.2
