# assist_app.gd — A.S.S.I.S.T. de StellarOS (§10.4, PASO 22): elige un deber automatizable, lanza la lotería de DutySystem y muestra el trabajo «generado», con su rastro digital.
# PROPIETARIO DE: nada de juego (la lotería, sus efectos y el registro de usos son de DutySystem; aquí solo el texto mostrado, la animación de escritura y una caché de solo lectura subtipo → nombre de deber).
# ESCUCHA: duty_completed, duty_failed, day_advanced (mientras está abierta, para refrescar la lista).
class_name AssistApp
extends OSApp

## DECISIONES:
##  · Generar = DutySystem.use_assist(deber): lotería exacta 60/25/15, minutos de
##    assist_time_cost_minutes × fracción pendiente, mérito si es excelente, detección del fallo
##    evidente por Perspicacia > 60 y assist_used (rastro digital acumulado, get_assist_log).
##  · generate(forced) fuerza un resultado con DutySystem.apply_assist_outcome (solo QA/capturas).
##  · El texto generado es jerga corporativa ensamblada con claves traducidas (ASSIST_OK_*,
##    ASSIST_EX_*, ASSIST_FAIL_*, ASSIST_NOUN_*, ASSIST_FAIL_NOUN_*), con semilla estable por deber,
##    jornada y número de uso: el mismo uso produce el mismo texto.
##  · La escritura progresiva va a ordenador.asistente_caracteres_por_segundo_por_nivel: la IA
##    del R1 teclea despacio; la del R33 escupe el informe de golpe.
##  · El rastro digital (get_assist_log) guarda el subtipo del deber y la hora en punto: se muestra
##    con el nombre traducido del deber (task_name) y la hora como «10 h», sin inventar minutos.
##  · Columna izquierda desplazable: en móvil la lista de deberes conserva su altura (hasta
##    LIST_MAX_ROWS filas completas) y la mascota se encoge o desaparece antes que ella.

const ACCEPTABLE := DutySystem.ASSIST_ACCEPTABLE
const EXCELLENT := DutySystem.ASSIST_EXCELLENT
const FAILURE := DutySystem.ASSIST_FAILURE
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"
const B_TYPE_SPEED := "ordenador.asistente_caracteres_por_segundo_por_nivel"
## Contenido (no ajustes): número de piezas de jerga traducidas.
const NOUN_COUNT := 12
const FAIL_NOUN_COUNT := 10
const OK_SENTENCES := 6
const EX_POINTS := 6
const FAIL_SENTENCES := 6
const LOG_SHOWN := 4
const QUIP_COUNT := 4
const LIST_MIN_ROWS := 1
const LIST_MAX_ROWS := 4
const EXCELLENT_COLOR := Color("#d9a53a")
const PERCENT := 100.0

var _selected_duty: String = ""
var _duty_list: VBoxContainer
var _rows: Dictionary = {}
var _generate: Button
var _risk: Label
var _trace: Label
var _log: Label
var _badge_holder: HBoxContainer
var _summary: Label
var _output: Label
var _stats: Label
var _detected: Label
var _typing: float = 0.0
var _last_result: Dictionary = {}
var _working: bool = false
var _mascot: AssistMascot
var _duty_scroll: ScrollContainer

## subtipo de deber → clave de nombre (primer deber de occupations.json con ese subtipo). Caché de
## datos de solo lectura.
static var _task_names: Dictionary = {}


## La mascota de A.S.S.I.S.T. con su bocadillo (la frase cambia con el resultado).
class AssistMascot extends Control:
	var pal: Dictionary = {}
	var base: int = 24
	var quip: String = ""

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func say(text: String) -> void:
		quip = text
		queue_redraw()

	## Sin sitio (móvil) la mascota se calla antes que quitarle altura a la lista de deberes.
	func _draw() -> void:
		if size.y < base * 3.5:
			return
		var side: float = minf(size.y * 0.72, base * 6.5)
		var bot: Rect2 = Rect2(Vector2(base * 0.4, (size.y - side) * 0.6), Vector2(side, side))
		OSTheme.draw_icon(self, "assist", bot, pal)
		var f: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		var fs: int = roundi(base * 0.8)
		var left: float = bot.end.x + base * 0.5
		var width: float = maxf(size.x - left - base * 0.4, base * 4.0)
		var text_h: float = f.get_multiline_string_size(quip, HORIZONTAL_ALIGNMENT_LEFT, width - base, fs, 4).y
		var h: float = text_h + base * 1.0
		var y: float = clampf(bot.position.y - h * 0.4, base * 0.3, maxf(size.y - h - base * 0.3, base * 0.3))
		var bubble: Rect2 = Rect2(Vector2(left, y), Vector2(width, h))
		var tail: PackedVector2Array = [bubble.position + Vector2(base * 0.6, h - 2.0),
				bubble.position + Vector2(base * 1.8, h - 2.0), bot.position + Vector2(side * 0.9, side * 0.3)]
		draw_colored_polygon(tail, OSTheme.col(pal, "field"))
		draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), OSTheme.col(pal, "shadow").darkened(0.3), 1.5, true)
		OSTheme.draw_panel(self, bubble, pal, OSTheme.col(pal, "field"))
		draw_line(tail[0] + Vector2(1.5, 0), tail[1] - Vector2(1.5, 0), OSTheme.col(pal, "field"), 3.0)
		draw_multiline_string(f, bubble.position + Vector2(base * 0.5, base * 0.35 + fs), quip, HORIZONTAL_ALIGNMENT_LEFT,
				width - base, fs, 4, OSTheme.col(pal, "text"))


## Barra de la lotería §10.4: tres tramos proporcionales a deberes.assist_prob_* con su porcentaje.
class AssistOdds extends Control:
	var pal: Dictionary = {}
	var base: int = 24

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		custom_minimum_size = Vector2(0, base * 1.35)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var weights: Array[float] = [Database.get_balance_float(DutySystem.B_ASSIST_P_OK),
				Database.get_balance_float(DutySystem.B_ASSIST_P_EXCELLENT),
				Database.get_balance_float(DutySystem.B_ASSIST_P_FAILURE)]
		var colors: Array[Color] = [OSTheme.col(pal, "good"), AssistApp.EXCELLENT_COLOR, OSTheme.col(pal, "bad")]
		var total: float = maxf(weights[0] + weights[1] + weights[2], 0.001)
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		OSTheme.draw_bevel(self, r, pal, true, base)
		var inner: Rect2 = r.grow(-OSTheme.bevel_width(base) * 1.5)
		var x: float = inner.position.x
		var f: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = roundi(base * OSTheme.RATIO_SMALL)
		for i: int in weights.size():
			var w: float = inner.size.x * weights[i] / total
			draw_rect(Rect2(x, inner.position.y, w, inner.size.y), colors[i])
			var label: String = "%d%%" % roundi(weights[i] / total * AssistApp.PERCENT)
			draw_string(f, Vector2(x, inner.get_center().y + fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, w, fs,
					UITheme.readable_on(colors[i]))
			x += w


# ─── Texto generado (puro) ────────────────────────────────────────

## Documento «generado» para un resultado de la lotería. Determinista para la semilla.
static func compose(outcome: String, duty_name: String, seed_value: int) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	match outcome:
		EXCELLENT:
			return _compose_excellent(rng, duty_name)
		FAILURE:
			return _compose_failure(rng, duty_name)
		_:
			return _compose_ok(rng, duty_name)


static func _compose_ok(rng: RandomNumberGenerator, duty_name: String) -> String:
	var lines: PackedStringArray = [t("ASSIST_GEN_OK_HEAD", [duty_name]), ""]
	for i: int in _pick(rng, OK_SENTENCES, 2):
		lines.append(t("ASSIST_OK_%d" % i, [_noun(rng), _noun(rng)]))
	lines.append("")
	lines.append(t("ASSIST_GEN_OK_SIGN"))
	return "\n".join(lines)


static func _compose_excellent(rng: RandomNumberGenerator, duty_name: String) -> String:
	var lines: PackedStringArray = [t("ASSIST_GEN_EX_HEAD", [duty_name]), "", t("ASSIST_EX_INTRO", [_noun(rng)])]
	for i: int in _pick(rng, EX_POINTS, 3):
		lines.append("  • " + t("ASSIST_EX_%d" % i, [_noun(rng)]))
	lines.append("")
	lines.append(t("ASSIST_GEN_EX_SIGN"))
	return "\n".join(lines)


static func _compose_failure(rng: RandomNumberGenerator, duty_name: String) -> String:
	var lines: PackedStringArray = [t("ASSIST_GEN_FAIL_HEAD", [duty_name]), ""]
	for i: int in _pick(rng, FAIL_SENTENCES, 3):
		lines.append(t("ASSIST_FAIL_%d" % i, [t("ASSIST_FAIL_NOUN_%d" % rng.randi_range(1, FAIL_NOUN_COUNT)),
				_noun(rng)]))
	lines.append("")
	lines.append(t("ASSIST_GEN_FAIL_SIGN"))
	return "\n".join(lines)


static func _noun(rng: RandomNumberGenerator) -> String:
	return t("ASSIST_NOUN_%d" % rng.randi_range(1, NOUN_COUNT))


## `count` índices distintos de 1..`total` en orden aleatorio.
static func _pick(rng: RandomNumberGenerator, total: int, count: int) -> Array[int]:
	var pool: Array[int] = []
	for i: int in range(1, total + 1):
		pool.append(i)
	var out: Array[int] = []
	for _n: int in mini(count, total):
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


# ─── Construcción ─────────────────────────────────────────────────

func build() -> void:
	var h: HBoxContainer = HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(h)
	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.8
	h.add_child(left_scroll)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)
	left.add_child(_brand())
	left.add_child(make_section(t("ASSIST_PICK_TASK")))
	_duty_scroll = make_scroll_list()
	_duty_scroll.size_flags_vertical = Control.SIZE_FILL
	_duty_list = _duty_scroll.get_child(0) as VBoxContainer
	left.add_child(_duty_scroll)
	_mascot = AssistMascot.new(pal, base)
	_mascot.say(t("ASSIST_QUIP_IDLE_%d" % (GameClock.get_day() % QUIP_COUNT + 1)))
	left.add_child(_mascot)
	_build_controls(left)
	h.add_child(_output_panel())
	EventBus.duty_completed.connect(_on_duty_event.unbind(3))
	EventBus.duty_failed.connect(_on_duty_event.unbind(2))
	EventBus.day_advanced.connect(_on_duty_event.unbind(1))


## Probabilidades, aviso de riesgo, botón y rastro digital (pie de la columna izquierda).
func _build_controls(left: VBoxContainer) -> void:
	left.add_child(make_section(t("ASSIST_ODDS")))
	left.add_child(AssistOdds.new(pal, base))
	_risk = make_label("", OSTheme.V_SMALL, true)
	_risk.add_theme_color_override("font_color", c("bad"))
	left.add_child(_risk)
	_generate = make_button(t("ASSIST_GENERATE"), _on_generate, OSTheme.V_PRIMARY)
	_generate.custom_minimum_size.y = base * 2.2
	left.add_child(_generate)
	left.add_child(_trace_panel())


func _brand() -> HBoxContainer:
	var brand: HBoxContainer = HBoxContainer.new()
	brand.add_child(make_icon("assist", 3.4))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	brand.add_child(col)
	var title: Label = make_label(t("ASSIST_BRAND"), OSTheme.V_BIG)
	title.add_theme_color_override("font_color", c("select"))
	col.add_child(title)
	col.add_child(make_label(t("ASSIST_EXPANSION"), OSTheme.V_MUTED, true))
	return brand


func _trace_panel() -> PanelContainer:
	var panel: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var h: HBoxContainer = HBoxContainer.new()
	col.add_child(h)
	h.add_child(make_icon("warning", 1.3))
	_trace = make_label("", OSTheme.V_HEADING, true)
	_trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_trace)
	_log = make_label("", OSTheme.V_MONO, true)
	_log.add_theme_color_override("font_color", c("muted"))
	col.add_child(_log)
	return panel


func _output_panel() -> PanelContainer:
	var panel: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.45
	var col: VBoxContainer = VBoxContainer.new()
	panel.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	col.add_child(head)
	var title: Label = make_section(t("ASSIST_OUTPUT"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_badge_holder = HBoxContainer.new()
	head.add_child(_badge_holder)
	_summary = make_label(t("ASSIST_IDLE"), OSTheme.V_TITLE, true)
	col.add_child(_summary)
	col.add_child(HSeparator.new())
	var scroll: ScrollContainer = make_scroll_list()
	col.add_child(scroll)
	_output = make_label(t("ASSIST_IDLE_BODY"), OSTheme.V_MONO, true)
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(scroll.get_child(0) as VBoxContainer).add_child(_output)
	_stats = make_label("", OSTheme.V_HEADING, true)
	col.add_child(_stats)
	_detected = make_label("", OSTheme.V_HEADING, true)
	_detected.add_theme_color_override("font_color", c("bad"))
	col.add_child(_detected)
	return panel


func _ready() -> void:
	refresh()


func get_title_key() -> String:
	return "ASSIST_WINDOW_TITLE"


# ─── Estado ───────────────────────────────────────────────────────

func refresh() -> void:
	var ds: DutySystem = duty_system()
	OSApp.clear_children(_duty_list)
	_rows.clear()
	var candidates: Array[String] = get_automatable_duties()
	if not candidates.has(_selected_duty):
		_selected_duty = candidates[0] if not candidates.is_empty() else ""
	for duty: Dictionary in PlayerState.get_todays_duties():
		_add_duty_row(ds, duty, candidates.has(str(duty.get("id", ""))))
	if _rows.is_empty():
		_duty_list.add_child(make_label(t("ASSIST_NO_DUTIES"), OSTheme.V_MUTED, true))
	_fit_duty_list()
	_refresh_controls(ds)


## La lista mide sus filas (entre LIST_MIN_ROWS y LIST_MAX_ROWS): nunca se aplasta a una rendija.
func _fit_duty_list() -> void:
	var sep: float = float(_duty_list.get_theme_constant("separation"))
	var h: float = 0.0
	var shown: int = 0
	for child: Node in _duty_list.get_children():
		if shown >= LIST_MAX_ROWS:
			break
		h += (child as Control).get_combined_minimum_size().y + (sep if shown > 0 else 0.0)
		shown += 1
	_duty_scroll.custom_minimum_size.y = maxf(h, base * 2.4 * LIST_MIN_ROWS)


## Deberes de hoy pendientes que A.S.S.I.S.T. puede hacer.
func get_automatable_duties() -> Array[String]:
	var out: Array[String] = []
	var ds: DutySystem = duty_system()
	for duty: Dictionary in PlayerState.get_pending_duties():
		var id: String = str(duty.get("id", ""))
		if ds != null and ds.register_duty(id) and _is_automatable(ds.get_session(id)):
			out.append(id)
	return out


func get_selected_duty() -> String:
	return _selected_duty


func select_duty(duty_id: String) -> void:
	if get_automatable_duties().has(duty_id):
		_selected_duty = duty_id
	refresh()


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func get_output_text() -> String:
	return _output.text


## Texto del panel de rastro digital (pruebas).
func get_trace_text() -> String:
	return _trace.text + "\n" + _log.text


## Alto real de la lista de deberes y de su primera fila (pruebas de maquetación en móvil).
func get_duty_list_height() -> float:
	return _duty_scroll.size.y


func get_duty_row_height() -> float:
	return (_duty_list.get_child(0) as Control).get_combined_minimum_size().y if _duty_list.get_child_count() > 0 else 0.0


## Lanza la lotería sobre el deber seleccionado (forced: resultado impuesto, solo QA). Devuelve el
## resultado de DutySystem más {text}. Usar con await.
func generate(forced_outcome: String = "") -> Dictionary:
	if _selected_duty.is_empty() or _working:
		return {"ok": false, "error": "no_duty"}
	_working = true
	_generate.disabled = true
	_summary.text = t("ASSIST_THINKING")
	_output.text = t("ASSIST_THINKING_BODY")
	_mascot.say(t("ASSIST_QUIP_THINKING"))
	await wait_action(StellarOS.ACTION_GENERATE)
	var ds: DutySystem = duty_system()
	var result: Dictionary = ds.use_assist(_selected_duty) if forced_outcome.is_empty() \
			else ds.apply_assist_outcome(_selected_duty, forced_outcome)
	_working = false
	if not bool(result.get("ok", false)):
		post_status(t(str(result.get("error_key", ""))))
		refresh()
		return result
	result["text"] = compose(str(result["outcome"]), _duty_name(_selected_duty),
			hash("%s:%d:%d" % [_selected_duty, GameClock.get_day(), ds.get_assist_count()]))
	show_result(result)
	refresh()
	return result


## Muestra un resultado (outcome, text_key, minutes, quality, merit, detected_by, reputation_delta, text).
func show_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	OSApp.clear_children(_badge_holder)
	var outcome: String = str(result.get("outcome", ACCEPTABLE))
	_badge_holder.add_child(make_badge(t("ASSIST_BADGE_" + outcome.to_upper()), _outcome_color(outcome)))
	_summary.text = t(str(result.get("text_key", "")))
	_output.text = str(result.get("text", ""))
	_mascot.say(t("ASSIST_QUIP_" + outcome.to_upper()))
	_output.visible_characters = 0 if _typing_speed() > 0.0 else -1
	_typing = 0.0
	var stats: String = t("ASSIST_STATS", [int(result.get("minutes", 0)), roundi(float(result.get("quality", 0.0)) * PERCENT)])
	if int(result.get("merit", 0)) > 0:
		stats += "  " + t("ASSIST_MERIT", [int(result["merit"])])
	_stats.text = stats
	var witness: String = str(result.get("detected_by", ""))
	_detected.text = t("ASSIST_DETECTED", [npc_name(witness), str(snappedf(float(result.get("reputation_delta", 0.0)), 0.1))]) \
			if not witness.is_empty() else (t("ASSIST_UNDETECTED") if outcome == FAILURE else "")
	post_status(t("ASSIST_STATUS_DONE", [int(result.get("minutes", 0))]))


## Termina de golpe la escritura progresiva (capturas).
func finish_typing() -> void:
	_output.visible_characters = -1


func _process(delta: float) -> void:
	if _output == null or _output.visible_characters < 0:
		return
	_typing += delta * _typing_speed()
	_output.visible_characters = floori(_typing)
	if _output.visible_characters >= _output.get_total_character_count():
		_output.visible_characters = -1


func _typing_speed() -> float:
	if shell != null and shell.is_instant():
		return 0.0
	return OSTheme.per_tier(B_TYPE_SPEED, get_tier())


# ─── Vista ────────────────────────────────────────────────────────

func _add_duty_row(ds: DutySystem, duty: Dictionary, automatable: bool) -> void:
	var id: String = str(duty.get("id", ""))
	var status: String = str(duty.get("status", ""))
	var tag: String = t("ASSIST_TAG_MANUAL")
	var tag_color: Color = c("muted")
	if status == STATUS_COMPLETED:
		tag = t("ASSIST_TAG_DONE")
		tag_color = c("good")
	elif status == STATUS_FAILED:
		tag = t("ASSIST_TAG_FAILED")
		tag_color = c("bad")
	elif automatable:
		tag = t("ASSIST_TAG_MINUTES", [int(ds.get_session(id).get("assist_cost", 0))])
		tag_color = c("select")
	var row: OSApp.OSRow = make_row("assist" if automatable else ("check" if status == STATUS_COMPLETED else "lock"),
			_duty_name(id), t(str(duty.get("description_key", ""))) if duty.has("description_key") else "", tag)
	row.set_tag_color(tag_color)
	row.set_selected(id == _selected_duty)
	if automatable:
		row.pressed.connect(select_duty.bind(id))
	_duty_list.add_child(row)
	_rows[id] = row


func _refresh_controls(ds: DutySystem) -> void:
	_generate.disabled = _selected_duty.is_empty() or _working
	var s: Dictionary = ds.get_session(_selected_duty) if ds != null and not _selected_duty.is_empty() else {}
	_risk.text = t("ASSIST_HIGH_RISK") if bool(s.get("high_risk", false)) else ""
	_risk.visible = not _risk.text.is_empty()
	var count: int = ds.get_assist_count() if ds != null else 0
	_trace.text = t("ASSIST_TRACE", [count])
	var lines: PackedStringArray = []
	var entries: Array[Dictionary] = []
	if ds != null:
		entries = ds.get_assist_log()
	for i: int in range(entries.size() - 1, maxi(entries.size() - LOG_SHOWN, 0) - 1, -1):
		var e: Dictionary = entries[i]
		lines.append(t("ASSIST_LOG_LINE", [int(e.get("day", 0)), int(e.get("hour", 0)),
				task_name(str(e.get("task_type", ""))), t("ASSIST_BADGE_" + str(e.get("result", "")).to_upper())]))
	_log.text = "\n".join(lines) if not lines.is_empty() else t("ASSIST_LOG_EMPTY")


func _is_automatable(session: Dictionary) -> bool:
	return bool(session.get("automatable", false)) and int(session.get("assist_cost", -1)) > 0 \
			and not str(session.get("status", "")) in [STATUS_COMPLETED, STATUS_FAILED]


## Nombre traducido de un tipo de tarea del rastro (subtipo de deber: "emails" → «Contestar correos»).
static func task_name(task_type: String) -> String:
	if _task_names.is_empty():
		for occ: OccupationData in Database.get_all_occupations():
			for duty: Dictionary in occ.duties:
				var subtype: String = str(duty.get("subtype", ""))
				if not subtype.is_empty() and not _task_names.has(subtype):
					_task_names[subtype] = str(duty.get("name_key", ""))
	var key: String = str(_task_names.get(task_type, ""))
	return t(key) if not key.is_empty() else t("ASSIST_TASK_UNKNOWN")


func _duty_name(duty_id: String) -> String:
	var duty: Dictionary = PlayerState.get_duty(duty_id)
	return t(str(duty.get("name_key", duty_id)))


func _outcome_color(outcome: String) -> Color:
	match outcome:
		EXCELLENT:
			return EXCELLENT_COLOR
		FAILURE:
			return c("bad")
		_:
			return c("good")


func _on_generate() -> void:
	await generate()


func _on_duty_event() -> void:
	if not _working:
		request_refresh()
