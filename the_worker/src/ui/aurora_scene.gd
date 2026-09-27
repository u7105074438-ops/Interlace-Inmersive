# aurora_scene.gd — Sala Aurora (§11.2, PASO 24): fuera de la reunión, ensayo en la sala vacía (preparación real ×1,0 o A.S.S.I.S.T.); en la reunión semanal, elegir idea y preparación, presentarla, el choque de credibilidad dramatizado y las presentaciones de los demás.
# PROPIETARIO DE: el paso de la escena, la idea y la preparación elegidas, el resultado mostrado y la lista de presentaciones ajenas (solo presentación: la lógica vive en IdeaPresentation e IdeaPool).
# ESCUCHA: idea_presented (solo mientras la escena cierra la reunión, para escenificar las ideas ajenas).
class_name AuroraScene
extends Control

## API: AuroraScene.open(host) → la escena (modal que pausa el reloj si host es UIRoot; si no,
## hija de host). Emite presentation_resolved(result) y, al terminar, closed().
## Se abre a cualquier hora desde la sala Aurora (atril o puerta, InteractionRouter):
##  · SIN reunión abierta → STEP_REHEARSE: la sala vacía para ensayar una idea de verdad
##    (IdeaPresentation.prepare_detailed "real": gasta ideas.minutos_preparacion_real de reloj) o
##    encargarla a A.S.S.I.S.T. La preparación queda en IdeaPool y la reunión la reutiliza (×1,0
##    sin gastar más tiempo). Si el ensayo cruza la hora de la reunión, take_seat() entra en ella.
##  · CON reunión: STEP_INTRO → STEP_PICK (ideas del jugador) → STEP_PREPARE (improvisar ·
##    A.S.S.I.S.T. · preparación real) → STEP_RESULT (discurso, acusación y choque con las dos
##    barras de credibilidad y sus consecuencias exactas) → STEP_OTHERS (los asistentes presentan
##    lo suyo al cerrar la reunión) → STEP_WRAP → closed().
## Maquetación: la sala a la izquierda (la cámara la encuadra en lo que deja libre el panel lateral)
## y el panel (SceneStage.Dock) a la derecha, con contenido desplazable y botones siempre visibles;
## en los golpes de acción el panel se retira y la cámara se acerca (acusación: primer plano).
## Esc/request_close: adelanta la animación hasta el siguiente punto de lectura; sin nada en marcha,
## vuelve atrás, no presenta o continúa.
## Contrato de IdeaPresentation: al abrir, summon_attendees() si la reunión está abierta y aún sin
## escenificar; se presenta SIEMPRE con present_player_idea(); al cerrar, get_meeting_invitees()
## → IdeaPool.close_meeting() → release_attendees().
## QA/tests: instant (sin esperas), clash_overrides (claves forzadas de build_context, p. ej.
## {"player_reputation": 60, "allies": 1, "accuser_reputation": 40, "believers": 0}) y
## assist_outcome (resultado forzado de A.S.S.I.S.T.).
## DECISIONES: dentro de la reunión la preparación real solo se ofrece si cabe antes de su fin (con
## el balance por defecto, una hora de reunión y 60 min de preparación, nunca: la tarjeta remite al
## ensayo previo en esta misma sala). Una preparación ya hecha se reutiliza sin repetirla
## (A.S.S.I.S.T. no vuelve a sortear). La escena cierra la reunión al terminar. El jugador ocupa la
## cabecera izquierda de la mesa. Las insignias «Lo sabe» marcan solo a los presentes que conocen la
## idea; el desglose dice cuántos la conocen en total (la fórmula los cuenta a todos).

signal closed()
signal presentation_resolved(result: Dictionary)

const STEP_REHEARSE := "rehearse"
const STEP_INTRO := "intro"
const STEP_PICK := "pick"
const STEP_PREPARE := "prepare"
const STEP_RESULT := "result"
const STEP_OTHERS := "others"
const STEP_WRAP := "wrap"
const STEP_DONE := "done"
const PLAYER := SceneStage.PLAYER_ID
const PLAYER_SEAT := 6
const SEAT_FORMAT := "seat_%d"
## Orden de ocupación: fila del fondo de dentro afuera (caras a cámara), cabecera, fila delantera.
const SEAT_ORDER: Array[int] = [2, 3, 1, 4, 0, 5, 7, 9, 10, 8, 11, 12, 13]
const STANDING_SPOT := Vector2(1640, 820)
const ACCUSE_KEYS: Array[String] = ["AURORA_ACCUSE_1", "AURORA_ACCUSE_2", "AURORA_ACCUSE_3"]
const TITLE_KEYS: Dictionary = {
	IdeaPresentation.RESULT_WIN: "AURORA_RESULT_WIN", IdeaPresentation.RESULT_TIE: "AURORA_RESULT_TIE",
	IdeaPresentation.RESULT_LOSS: "AURORA_RESULT_LOSS",
}
const REHEARSE_PREPS: Array[String] = [IdeaPresentation.PREP_REAL, IdeaPresentation.PREP_ASSIST]
const SFX_STAND: Array[String] = ["chair_creak"]
const SFX_CONFIRM: Array[String] = ["ui_confirm"]
const B_WALK := "escenas.paseo_segundos"
const B_PAUSE := "escenas.pausa_segundos"
const B_METER := "escenas.medidor_segundos"
const B_MAX_IDEAS := "escenas.max_ideas_listadas"
const PERCENT := 100.0
const MINUTES_PER_HOUR := 60.0
## Penalización de orden para asistentes de espaldas (más que cualquier distancia del lienzo).
const DESIGN_FAR := 10000.0
## Separación del pasillo respecto a la fila de sillas (px del lienzo de diseño).
const AISLE_OFFSET := 40.0
## Escala del tira y afloja: margen sobre la diferencia y ancho mínimo en múltiplos del umbral.
const METER_HEADROOM := 1.25
const METER_MIN_BANDS := 3.0
## Barras de credibilidad: la escala llega al menos a la reputación máxima (0–100) con margen.
const CRED_SCALE_MIN := 100.0
const CRED_HEADROOM := 1.05
## Encuadres (lienzo de diseño): la mesa y la pantalla cuando el panel ocupa la derecha; el primer
## plano de la acusación deja este margen alrededor del orador y el acusador.
const FRAME_TABLE := Rect2(370, 0, 1200, 872)
const FRAME_CLASH := Rect2(190, 0, 1390, 872)
const FRAME_REHEARSAL := Rect2(150, 0, 1440, 872)
const CLOSEUP_PAD := Vector2(170, 150)
const HEADER_GAP := 12.0

var instant: bool = false
var clash_overrides: Dictionary = {}
var assist_outcome: String = ""

var _stage: SceneStage
var _dock: SceneStage.Dock
var _header: PanelContainer
var _header_sub: Label
var _timeline: SceneStage.Timeline = SceneStage.Timeline.new()
var _step: String = STEP_INTRO
var _attendees: Array[String] = []
var _chair_id: String = ""
var _idea_id: String = ""
var _prep: Dictionary = {}
var _result: Dictionary = {}
var _others: Array[Dictionary] = []
var _result_title: String = ""
var _result_lines: Array[String] = []
var _prep_lines: Array[String] = []
var _meter: ClashMeter
var _bars: Array[CredBar] = []
var _done: bool = false


## Tira y afloja del choque: diferencia de credibilidad contra la banda de empate (±umbral).
class ClashMeter extends Control:
	var threshold: float = 20.0
	var difference: float = 0.0
	var progress: float = 0.0
	var duration: float = 1.0
	var span: float = 60.0
	var texts: Array[String] = ["", "", ""]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	## Alto: pista, número de la aguja y dos filas de rótulos con la letra vigente.
	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			var fs: float = float(get_theme_font_size("font_size", "Label"))
			custom_minimum_size.y = 64.0 * SceneStage.ui_scale() + fs * 2.0 + 16.0

	func _process(delta: float) -> void:
		if progress >= 1.0:
			return
		progress = minf(progress + delta / maxf(duration, 0.001), 1.0)
		queue_redraw()

	func snap() -> void:
		progress = 1.0
		queue_redraw()

	func eased() -> float:
		return 1.0 - pow(1.0 - progress, 3.0)

	func _draw() -> void:
		var k: float = SceneStage.ui_scale()
		var font: Font = get_theme_font("font", "Label")
		var fs: int = get_theme_font_size("font_size", "Label")
		var track: Rect2 = Rect2(0, 38 * k, size.x, 26 * k)
		var cx: float = size.x * 0.5
		var per: float = cx / maxf(span, 1.0)
		var band: Rect2 = Rect2(cx - threshold * per, track.position.y, threshold * per * 2.0, track.size.y)
		draw_rect(Rect2(track.position, Vector2(band.position.x, track.size.y)), UITheme.color("loss").darkened(0.25))
		draw_rect(Rect2(band.end.x, track.position.y, size.x - band.end.x, track.size.y), UITheme.color("gain").darkened(0.3))
		draw_rect(band, UITheme.color("faint"))
		for i: int in int(band.size.x / 12.0):
			var x: float = band.position.x + 6.0 + i * 12.0
			draw_line(Vector2(x, track.end.y - 2), Vector2(x + 10, track.position.y + 2), Color(UITheme.color("paper"), 0.18), 2.0)
		draw_rect(track, UITheme.color("paper"), false, 2.0)
		_draw_needle(font, fs, track, cx + clampf(difference * eased(), -span, span) * per)
		var row1: float = track.end.y + fs + 4
		_draw_caption(font, fs, texts[0], Vector2(2, row1), HORIZONTAL_ALIGNMENT_LEFT)
		_draw_caption(font, fs, texts[2], Vector2(size.x - 2, row1), HORIZONTAL_ALIGNMENT_RIGHT)
		_draw_caption(font, fs, texts[1], Vector2(cx, row1 + fs + 2), HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_needle(font: Font, fs: int, track: Rect2, x: float) -> void:
		var ink: Color = UITheme.color("paper")
		draw_line(Vector2(x, track.position.y - 8), Vector2(x, track.end.y + 8), UITheme.color("ink"), 8.0)
		draw_line(Vector2(x, track.position.y - 8), Vector2(x, track.end.y + 8), ink, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 11, track.position.y - 20),
				Vector2(x + 11, track.position.y - 20), Vector2(x, track.position.y - 6)]), ink)
		var label: String = "%+d" % roundi(difference * eased())
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(clampf(x - w * 0.5, 0, size.x - w), track.position.y - 24), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

	func _draw_caption(font: Font, fs: int, text: String, at: Vector2, align: HorizontalAlignment) -> void:
		var small: int = roundi(fs * UITheme.RATIO_SMALL)
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var x: float = at.x
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			x -= w * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			x -= w
		draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, small, UITheme.color("muted"))


## Barra de credibilidad de un contendiente: un tramo por término de la fórmula (reputación, +20 por
## creyente, +15 por aliado) y la sospecha como mordisco rayado al final; crece con la cuenta del
## número (number) durante `duration`.
class CredBar extends Control:
	var terms: Array[Dictionary] = []
	var penalty: float = 0.0
	var total: float = 0.0
	var span: float = 100.0
	var progress: float = 0.0
	var duration: float = 1.0
	var number: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size.y = 24.0 * SceneStage.ui_scale()

	func _process(delta: float) -> void:
		if progress >= 1.0:
			return
		progress = minf(progress + delta / maxf(duration, 0.001), 1.0)
		_update_number()
		queue_redraw()

	func snap() -> void:
		progress = 1.0
		_update_number()
		queue_redraw()

	func eased() -> float:
		return 1.0 - pow(1.0 - progress, 3.0)

	func _update_number() -> void:
		if number != null:
			number.text = "%d" % roundi(total * eased())

	func _draw() -> void:
		var bar: Rect2 = Rect2(Vector2.ZERO, size)
		var per: float = size.x / maxf(span, 1.0)
		var e: float = eased()
		draw_rect(bar, UITheme.color("slot"))
		var x: float = 0.0
		for term: Dictionary in terms:
			var w: float = minf(maxf(float(term["value"]), 0.0) * per * e, size.x - x)
			if w <= 0.5:
				continue
			draw_rect(Rect2(x, 0, w, size.y), term["color"])
			draw_line(Vector2(x + w, 0), Vector2(x + w, size.y), UITheme.color("ink"), 2.0)
			x += w
		_draw_penalty(x, per * e)
		draw_rect(bar, UITheme.color("line"), false, 2.0)

	func _draw_penalty(end_x: float, per: float) -> void:
		var bite: float = minf(penalty * per, end_x)
		if bite <= 0.5:
			return
		var r: Rect2 = Rect2(end_x - bite, 0, bite, size.y)
		draw_rect(r, UITheme.color("sus_track"))
		for i: int in int(r.size.x / 8.0) + 1:
			var hx: float = r.position.x + i * 8.0
			draw_line(Vector2(hx, size.y), Vector2(minf(hx + 6.0, r.end.x), 0), UITheme.color("loss"), 2.0)
		draw_rect(r, UITheme.color("loss"), false, 2.0)


static func open(host: Node) -> AuroraScene:
	var scene: AuroraScene = AuroraScene.new()
	if host.has_method("open_modal"):
		host.call("open_modal", scene, true)
	else:
		host.add_child(scene)
	return scene


func _init() -> void:
	name = "AuroraScene"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta(UIRoot.META_DIM, false)
	_stage = SceneStage.new()
	add_child(_stage)
	_header = _build_header()
	add_child(_header)
	_dock = SceneStage.Dock.new()
	add_child(_dock)


func _ready() -> void:
	SceneStage.ensure_theme(self)
	_dock.instant = instant
	_dock.layout_changed.connect(_relayout)
	resized.connect(_relayout)
	_header.resized.connect(_relayout)
	_stage.configure(SceneStage.SET_AURORA)
	_cast_room()
	_dress_room()
	if IdeaPool.is_meeting_open():
		_begin_meeting()
	else:
		_rehearsal()
	_relayout()


func _process(delta: float) -> void:
	_timeline.tick(delta)
	if SceneStage.refresh_theme(self):
		_relayout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_relayout.call_deferred()


# ─── API ──────────────────────────────────────────────────────

func get_step() -> String:
	return _step


func get_stage() -> SceneStage:
	return _stage


func get_dock() -> SceneStage.Dock:
	return _dock


func get_attendees() -> Array[String]:
	return _attendees.duplicate()


func is_rehearsal() -> bool:
	return _step == STEP_REHEARSE


## Ideas vivas del jugador que puede presentar (las que lista el panel).
func get_player_ideas() -> Array[Idea]:
	var out: Array[Idea] = []
	for idea: Idea in IdeaPool.get_player_ideas():
		if out.size() < Database.get_balance_int(B_MAX_IDEAS):
			out.append(idea)
	return out


func get_result() -> Dictionary:
	return _result.duplicate(true)


func get_result_title() -> String:
	return _result_title


func get_result_lines() -> Array[String]:
	return _result_lines.duplicate()


func get_preparation_lines() -> Array[String]:
	return _prep_lines.duplicate()


func get_other_presentations() -> Array[Dictionary]:
	return _others.duplicate(true)


## Textos visibles ahora mismo en la interfaz de la escena (panel, cabecera y bocadillos).
func get_visible_texts() -> Array[String]:
	var out: Array[String] = []
	SceneStage.collect_texts(self, out)
	return out


func is_clash_visible() -> bool:
	return _meter != null and is_instance_valid(_meter) and _meter.is_visible_in_tree()


## Las dos barras de credibilidad del choque en pantalla (acusador, jugador); vacío sin choque.
func get_credibility_bars() -> Array[CredBar]:
	var out: Array[CredBar] = []
	for bar: CredBar in _bars:
		if is_instance_valid(bar):
			out.append(bar)
	return out


## "present" (en la sala) · "absent" · "consented" (compra o cesión) · "gone" (ya no está).
func owner_status(idea: Idea) -> String:
	if IdeaPool.CONSENTED_METHODS.has(idea.acquisition_method):
		return "consented"
	if IdeaPool.is_owner_gone(idea.owner):
		return "gone"
	return "present" if _attendees.has(idea.owner) else "absent"


func choose_idea(idea_id: String) -> bool:
	var idea: Idea = IdeaPool.get_idea(idea_id)
	if _step != STEP_PICK or idea == null or not IdeaPool.get_player_ideas().has(idea):
		return false
	_idea_id = idea_id
	SceneStage.play_sfx(self, SFX_CONFIRM)
	_show_prepare()
	return true


## [{id, factor, merit, available, ready, note}] para "none", "assist" y "real".
func preparation_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var idea: Idea = IdeaPool.get_idea(_idea_id)
	if idea == null:
		return out
	var current: String = IdeaPool.get_preparation(_idea_id)
	var minutes: float = Database.get_balance_float(IdeaPresentation.B_REAL_PREP_MINUTES)
	for prep: String in IdeaPresentation.PREPARATIONS:
		var ready: bool = prep != IdeaPresentation.PREP_NONE and current == prep
		var fits: bool = prep != IdeaPresentation.PREP_REAL or ready or minutes < _minutes_left()
		out.append({"id": prep, "factor": IdeaPresentation.presentation_factor(prep),
				"merit": IdeaPresentation.compute_merit(idea.quality, prep, _player_reputation()),
				"available": fits, "ready": ready, "note": _prep_note(prep, ready, fits, minutes)})
	return out


## Prepara (si hace falta), presenta con present_player_idea() y escenifica. → resultado.
func choose_preparation(preparation: String) -> Dictionary:
	if _step != STEP_PREPARE or not _option_available(preparation):
		return {}
	_step = STEP_RESULT
	_prep = _apply_preparation(preparation)
	_result = IdeaPresentation.present_player_idea(_idea_id, clash_overrides)
	_compose_result()
	presentation_resolved.emit(_result.duplicate(true))
	_dock.close()
	_stage_presentation()
	_settle()
	return _result.duplicate(true)


## Ensayo en la sala vacía (STEP_REHEARSE): "real" o "assist" para una idea del jugador. Devuelve
## el detalle de IdeaPresentation ({ok, preparation, minutes, outcome...}); {} si no procede.
func rehearse(idea_id: String, preparation: String) -> Dictionary:
	var idea: Idea = IdeaPool.get_idea(idea_id)
	if _step != STEP_REHEARSE or idea == null or not IdeaPool.get_player_ideas().has(idea) \
			or not REHEARSE_PREPS.has(preparation) or IdeaPool.get_preparation(idea_id) == preparation:
		return {}
	_idea_id = idea_id
	_prep = _apply_preparation(preparation)
	_prep_lines = _preparation_lines()
	_rehearsal_beat(idea)
	_show_rehearsal()
	return _prep.duplicate(true)


## Tras un ensayo que cruzó la hora de la reunión: el jugador se sienta y empieza la reunión.
func take_seat() -> bool:
	if _step != STEP_REHEARSE or not IdeaPool.is_meeting_open():
		return false
	_stage.clear_bubbles()
	_stage.set_seated(PLAYER, true)
	_prep_lines.clear()
	_begin_meeting()
	return true


## No presentar nada: la reunión sigue con las ideas de los demás.
func skip_presenting() -> void:
	if _step in [STEP_INTRO, STEP_PICK, STEP_PREPARE]:
		_timeline.clear()
		_run_others()


func back_to_pick() -> void:
	if _step == STEP_PREPARE:
		_show_pick()


## Botón «Continuar»: resultado → presentaciones ajenas → cierre → fin.
func continue_scene() -> void:
	if _timeline.is_busy():
		skip_ahead()
		return
	match _step:
		STEP_RESULT:
			_run_others()
		STEP_OTHERS:
			_show_wrap()
		STEP_WRAP, STEP_REHEARSE:
			finish()


## QA/tests: hace avanzar la línea de tiempo `seconds` sin depender del reloj real.
func advance(seconds: float) -> void:
	_timeline.tick(seconds)


## Adelanta hasta el siguiente punto de lectura (Esc): termina paseos y ejecuta golpes hasta uno
## marcado como parada (la acusación, el choque, el veredicto, cada presentación ajena).
func skip_ahead() -> void:
	_timeline.skip()
	_stage.finish_moves()


## Todo de golpe (modo instantáneo, tests): golpes, paseos, contadores y cámara.
func fast_forward() -> void:
	_timeline.flush()
	_stage.finish_moves()
	_snap_meters()
	_stage.snap_camera()


## Esc: adelanta la animación en curso o avanza al paso siguiente.
func request_close() -> void:
	if _timeline.is_busy() or _stage.is_moving():
		skip_ahead()
	elif _step == STEP_PREPARE:
		back_to_pick()
	elif _step in [STEP_INTRO, STEP_PICK]:
		skip_presenting()
	else:
		continue_scene()


## Fin: cierra la reunión si sigue abierta (los asistentes presentan lo suyo) y emite closed().
func finish() -> void:
	if _done:
		return
	_done = true
	_step = STEP_DONE
	if IdeaPool.is_meeting_open():
		_others.append_array(_close_meeting())
	var owned: bool = closed.get_connections().is_empty()
	closed.emit()
	if owned:
		queue_free()


## UIRoot la llama al retirar la ventana (también tras closed()): nunca deja la reunión a medias.
func cancel() -> void:
	if _done:
		return
	_done = true
	_step = STEP_DONE
	if IdeaPool.is_meeting_open():
		_close_meeting()


# ─── Montaje ──────────────────────────────────────────────────

func _build_header() -> PanelContainer:
	var pill: PanelContainer = PanelContainer.new()
	pill.theme_type_variation = UITheme.V_PANEL
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = Vector2(SceneStage.Dock.MARGIN, SceneStage.Dock.MARGIN)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	pill.add_child(box)
	box.add_child(SceneStage.ui_label(tr("AURORA_HEADER"), UITheme.V_HEADING))
	_header_sub = SceneStage.ui_label("", UITheme.V_CAPTION)
	box.add_child(_header_sub)
	return pill


## Zona libre de la sala = pantalla menos la cabecera y el panel lateral.
func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_header.reset_size()
	_dock.fit_width(size)
	_stage.set_safe_rect(_dock.free_rect(size, _header.get_rect().end.y + HEADER_GAP))


## Las 14 sillas de la sala (con o sin ocupante) y el jugador en la cabecera izquierda.
func _cast_room() -> void:
	var seats: Array[Dictionary] = SceneStage.aurora_seats()
	for i: int in seats.size():
		_stage.add_chair(SEAT_FORMAT % i, seats[i]["center"], seats[i]["facing"], SceneStage.CHAIR_EXEC)
	var mine: Dictionary = seats[PLAYER_SEAT]
	_stage.add_actor(PLAYER, SceneStage.cast_member(PLAYER), {"pos": mine["center"], "facing": mine["facing"],
			"seated": true, "chair_id": SEAT_FORMAT % PLAYER_SEAT})


func _begin_meeting() -> void:
	_prepare_meeting()
	_cast_attendees()
	_dress_meeting()
	_intro()


## Summon (contrato de IdeaPresentation) y lista de presentes.
func _prepare_meeting() -> void:
	if not IdeaPool.is_meeting_open():
		return
	if not IdeaPool.is_meeting_staged():
		IdeaPresentation.summon_attendees()
	_attendees = IdeaPool.get_meeting_attendees()


func _cast_attendees() -> void:
	var order: Array[String] = _seating_order()
	for i: int in order.size():
		if _stage.has_actor(order[i]):
			continue
		var member: Dictionary = SceneStage.cast_member(order[i])
		if i < SEAT_ORDER.size():
			var seat: Dictionary = SceneStage.aurora_seats()[SEAT_ORDER[i]]
			_stage.add_actor(order[i], member, {"pos": seat["center"], "facing": seat["facing"],
					"seated": true, "chair_id": SEAT_FORMAT % SEAT_ORDER[i]})
		else:
			var spot: Vector2 = STANDING_SPOT - Vector2(96.0 * (i - SEAT_ORDER.size()), 0)
			_stage.add_actor(order[i], member, {"pos": spot, "facing": Vector2(-0.4, -1)})
	_chair_id = order[0] if not order.is_empty() else ""
	for id: String in order:
		if int(_stage.get_actor(id)["tier"]) > int(_stage.get_actor(_chair_id)["tier"]):
			_chair_id = id


## Primero los dueños de las ideas del jugador (al fondo, de cara), luego por escalón.
func _seating_order() -> Array[String]:
	var owners: Array[String] = []
	for idea: Idea in IdeaPool.get_player_ideas():
		owners.append(idea.owner)
	var out: Array[String] = _attendees.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var oa: bool = owners.has(a)
		if oa != owners.has(b):
			return oa
		return _tier_of(a) > _tier_of(b))
	return out


func _tier_of(npc_id: String) -> int:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.tier if npc != null else 1


func _dress_room() -> void:
	_stage.set_prop("poster", tr("AURORA_POSTER"))
	_stage.set_prop("flip_left", tr("AURORA_FLIP_THEIRS"))
	_stage.set_prop("flip_right", tr("AURORA_FLIP_MINE"))
	_stage.set_prop("flip_mid", tr("AURORA_FLIP_MID"))
	_stage.set_prop("screen_sub", "")
	_update_clock()


func _dress_meeting() -> void:
	_stage.set_prop("screen_kicker", tr("AURORA_SCREEN_KICKER"))
	_stage.set_prop("screen_title", tr("AURORA_SCREEN_AGENDA"))
	_stage.set_prop("screen_sub", "")
	_update_clock()
	_header_sub.text = tr("AURORA_HEADER_SUB") % GameClock.get_time_string()


func _update_clock() -> void:
	_stage.set_prop("clock", Vector2i(GameClock.get_hour(), GameClock.get_minute()))


func _intro() -> void:
	_step = STEP_INTRO
	_dock.close()
	_stage.frame(SceneStage.FRAME_AURORA)
	if _chair_id.is_empty():
		_stage.say(PLAYER, tr("AURORA_EMPTY_ROOM"), SceneStage.STYLE_WHISPER)
	else:
		_stage.set_anim(_chair_id, "chat")
		_stage.say(_chair_id, tr("AURORA_CHAIR_OPEN"))
	_timeline.then(SceneStage.reading_time(tr("AURORA_CHAIR_OPEN")), _show_pick, true)
	_settle()


# ─── Ensayo (sin reunión) ─────────────────────────────────────

func _rehearsal() -> void:
	_step = STEP_REHEARSE
	_stage.frame(FRAME_REHEARSAL)
	_stage.move_actor(PLAYER, SceneStage.aurora_podium_spot())
	_stage.set_anim(PLAYER, "idle", Vector2(0.45, 1))
	_stage.set_prop("screen_kicker", tr("AURORA_SCREEN_REHEARSAL"))
	_stage.set_prop("screen_title", _next_meeting_text())
	_stage.say(PLAYER, tr("AURORA_REHEARSE_MUTTER"), SceneStage.STYLE_WHISPER, 0.0)
	_header_sub.text = tr("AURORA_HEADER_SUB_EMPTY") % GameClock.get_time_string()
	_show_rehearsal()
	_settle()


func _next_meeting_text() -> String:
	var schedule: Dictionary = IdeaPool.get_meeting_schedule()
	var day: int = IdeaPool.get_next_meeting_day(GameClock.get_day())
	if day == GameClock.get_day() and GameClock.get_hour() >= int(schedule.get("hour", 0)):
		day = IdeaPool.get_next_meeting_day(GameClock.get_day() + 1)
	return tr("AURORA_SCREEN_NEXT") % [day, IdeaPool.HOUR_FORMAT % int(schedule.get("hour", 0))]


func _show_rehearsal() -> void:
	var box: VBoxContainer = _dock.open(tr("AURORA_REHEARSE_TITLE"))
	for line: String in _prep_lines:
		box.add_child(SceneStage.ui_label(line, UITheme.V_STRONG, true, UITheme.color("gain")))
	var ideas: Array[Idea] = get_player_ideas()
	box.add_child(SceneStage.ui_label(tr("AURORA_NO_MEETING"), UITheme.V_SMALL, true))
	var body: String = tr("AURORA_REHEARSE_BODY") % [_next_meeting_text(),
			_factor_text(IdeaPresentation.presentation_factor(IdeaPresentation.PREP_REAL))]
	box.add_child(SceneStage.ui_label(body if not ideas.is_empty() else tr("AURORA_REHEARSE_NONE"), "", true))
	for idea: Idea in ideas:
		box.add_child(_rehearse_card(idea))
	var buttons: Array[Button] = [SceneStage.ui_button(tr("AURORA_LEAVE"), "", finish)]
	if IdeaPool.is_meeting_open():
		box.add_child(SceneStage.ui_label(tr("AURORA_REHEARSE_MEETING_NOW") % GameClock.get_time_string(),
				UITheme.V_STRONG, true, UITheme.color("warn")))
		buttons.append(SceneStage.ui_button(tr("AURORA_TAKE_SEAT"), UITheme.V_PRIMARY, take_seat))
	_dock.add_buttons(buttons)


func _rehearse_card(idea: Idea) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = UITheme.V_CARD
	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)
	box.add_child(SceneStage.ui_label("“%s”" % _idea_title(idea), UITheme.V_STRONG, true))
	var current: String = IdeaPool.get_preparation(idea.id)
	var factor: String = _factor_text(IdeaPresentation.presentation_factor(current))
	var status: Label = SceneStage.ui_label(tr("AURORA_REHEARSE_STATUS_" + current.to_upper()) % factor,
			UITheme.V_SMALL, true, UITheme.color("gain") if current != IdeaPresentation.PREP_NONE else UITheme.color("muted"))
	box.add_child(status)
	var row: HFlowContainer = HFlowContainer.new()
	var minutes: int = roundi(Database.get_balance_float(IdeaPresentation.B_REAL_PREP_MINUTES))
	for prep: String in REHEARSE_PREPS:
		var label: String = tr("AURORA_REHEARSE_REAL") % minutes if prep == IdeaPresentation.PREP_REAL \
				else tr("AURORA_REHEARSE_ASSIST")
		var b: Button = SceneStage.ui_button(label, UITheme.V_PRIMARY if prep == IdeaPresentation.PREP_REAL else "",
				rehearse.bind(idea.id, prep))
		b.disabled = current == prep
		row.add_child(b)
	box.add_child(row)
	return card


## El jugador ensaya en el atril ante sillas vacías; la pantalla muestra su borrador.
func _rehearsal_beat(idea: Idea) -> void:
	_stage.set_prop("screen_title", _idea_title(idea))
	_stage.set_prop("screen_sub", tr("AURORA_SCREEN_DRAFT"))
	_stage.set_anim(PLAYER, "chat", Vector2(0.45, 1))
	_stage.say(PLAYER, tr("AURORA_REHEARSE_LINE"), SceneStage.STYLE_SAY, 0.0)
	_update_clock()
	_header_sub.text = tr("AURORA_HEADER_SUB_EMPTY") % GameClock.get_time_string()
	var detector: String = str(_prep.get("detected_by", ""))
	if not detector.is_empty():
		_stage.badge(PLAYER, tr("AURORA_BADGE_REP") % roundi(float(_prep.get("reputation_delta", 0.0))),
				UITheme.color("loss"))


# ─── Paneles de la reunión ────────────────────────────────────

func _show_pick() -> void:
	_step = STEP_PICK
	_stage.frame(FRAME_TABLE)
	var ideas: Array[Idea] = get_player_ideas()
	var box: VBoxContainer = _dock.open(tr("AURORA_PICK_TITLE"))
	box.add_child(SceneStage.ui_label(tr("AURORA_PICK_BODY" if not ideas.is_empty() else "AURORA_PICK_NONE"), "", true))
	for idea: Idea in ideas:
		box.add_child(_idea_card(idea))
	_dock.add_buttons([SceneStage.ui_button(tr("AURORA_SKIP"), "", skip_presenting)])


func _idea_card(idea: Idea) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = UITheme.V_CARD
	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)
	box.add_child(SceneStage.ui_label("“%s”" % _idea_title(idea), UITheme.V_STRONG, true))
	var facts: String = "%s · %s · %s" % [tr("AURORA_IDEA_QUALITY") % idea.quality,
			tr("AURORA_IDEA_FRESH") % idea.freshness, tr("IDEA_METHOD_" + idea.acquisition_method.to_upper())]
	box.add_child(SceneStage.ui_label(facts, UITheme.V_SMALL, true))
	var status: String = owner_status(idea)
	box.add_child(SceneStage.ui_label(_owner_text(idea, status), UITheme.V_SMALL, true,
			UITheme.color("loss") if status == "present" else UITheme.color("muted")))
	var row: HBoxContainer = HBoxContainer.new()
	var low: int = IdeaPresentation.compute_merit(idea.quality, IdeaPresentation.PREP_NONE, _player_reputation())
	var high: int = IdeaPresentation.compute_merit(idea.quality, IdeaPresentation.PREP_REAL, _player_reputation())
	var merit: Label = SceneStage.ui_label(tr("AURORA_IDEA_MERIT_RANGE") % [low, high], UITheme.V_CAPTION)
	merit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(merit)
	row.add_child(SceneStage.ui_button(tr("AURORA_PRESENT_THIS"), UITheme.V_PRIMARY, choose_idea.bind(idea.id)))
	box.add_child(row)
	return card


func _owner_text(idea: Idea, status: String) -> String:
	var owner_name: String = IdeaPool.get_npc_display_name(idea.owner)
	match status:
		"present":
			return tr("AURORA_OWNER_IN_ROOM") % owner_name
		"consented":
			return tr("AURORA_OWNER_CONSENTED") % owner_name
		"gone":
			return tr("AURORA_OWNER_GONE") % owner_name
	return tr("AURORA_OWNER_ABSENT") % owner_name


func _show_prepare() -> void:
	_step = STEP_PREPARE
	var idea: Idea = IdeaPool.get_idea(_idea_id)
	var box: VBoxContainer = _dock.open(tr("AURORA_PREP_TITLE"))
	box.add_child(SceneStage.ui_label("“%s”" % _idea_title(idea), UITheme.V_CAPTION, true))
	for option: Dictionary in preparation_options():
		box.add_child(_prep_card(option))
	_dock.add_buttons([SceneStage.ui_button(tr("AURORA_BACK"), "", back_to_pick)])


func _prep_card(option: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = UITheme.V_CARD
	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)
	var prep: String = str(option["id"])
	var top: HBoxContainer = HBoxContainer.new()
	var name_label: Label = SceneStage.ui_label(tr("AURORA_PREP_" + prep.to_upper()), UITheme.V_HEADING)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	top.add_child(SceneStage.ui_label(tr("AURORA_PREP_MERIT") % int(option["merit"]), UITheme.V_STRONG))
	box.add_child(top)
	var note: Label = SceneStage.ui_label(str(option["note"]), UITheme.V_SMALL, true)
	if bool(option["ready"]):
		note.add_theme_color_override("font_color", UITheme.color("gain"))
	elif not bool(option["available"]):
		note.add_theme_color_override("font_color", UITheme.color("warn"))
	box.add_child(note)
	var b: Button = SceneStage.ui_button(tr("AURORA_PREP_CHOOSE"), UITheme.V_PRIMARY, choose_preparation.bind(prep))
	b.disabled = not bool(option["available"])
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(b)
	return card


func _prep_note(prep: String, ready: bool, fits: bool, minutes: float) -> String:
	var factor: String = _factor_text(IdeaPresentation.presentation_factor(prep))
	if ready:
		return tr("AURORA_PREP_READY")
	match prep:
		IdeaPresentation.PREP_ASSIST:
			return tr("AURORA_PREP_ASSIST_HINT") % factor
		IdeaPresentation.PREP_REAL:
			if not fits:
				return tr("AURORA_PREP_NO_TIME") % [roundi(minutes), _meeting_end_text()]
			return tr("AURORA_PREP_REAL_HINT") % [factor, roundi(minutes)]
	return tr("AURORA_PREP_NONE_HINT") % factor


static func _factor_text(factor: float) -> String:
	return SceneStage.decimal(factor)


func _option_available(preparation: String) -> bool:
	for option: Dictionary in preparation_options():
		if str(option["id"]) == preparation:
			return bool(option["available"])
	return false


func _minutes_left() -> float:
	if not IdeaPool.is_meeting_open():
		return 0.0
	var end_hour: int = int(IdeaPool.get_current_meeting().get("end_hour", GameClock.get_hour()))
	return float(end_hour) * MINUTES_PER_HOUR - GameClock.get_day_minutes()


func _meeting_end_text() -> String:
	return IdeaPool.HOUR_FORMAT % int(IdeaPool.get_current_meeting().get("end_hour", 0))


func _player_reputation() -> float:
	return float(clash_overrides.get("player_reputation", PlayerState.get_reputation()))


func _apply_preparation(preparation: String) -> Dictionary:
	if preparation != IdeaPresentation.PREP_NONE and IdeaPool.get_preparation(_idea_id) == preparation:
		return {"ok": true, "preparation": preparation, "minutes": 0.0, "reused": true}
	if preparation == IdeaPresentation.PREP_ASSIST and not assist_outcome.is_empty():
		return IdeaPresentation.apply_assist_preparation(_idea_id, assist_outcome)
	return IdeaPresentation.prepare_detailed(_idea_id, preparation)


func _idea_title(idea: Idea) -> String:
	if idea == null or idea.text_key.is_empty():
		return tr("AURORA_IDEA_UNTITLED")
	return tr(idea.text_key)


# ─── Resultado (textos exactos de las consecuencias) ──────────

func _compose_result() -> void:
	_prep_lines = _preparation_lines()
	_result_lines.clear()
	if str(_result.get("status", "")) != IdeaPool.STATUS_OK:
		_result_title = tr("AURORA_RESULT_FAILED")
		_result_lines.append(tr("AURORA_LINE_STATUS") % _status_text(str(_result.get("status", ""))))
		return
	if not bool(_result.get("contested", false)):
		_result_title = tr("AURORA_RESULT_PRESENTED")
		_result_lines.append(tr("AURORA_LINE_MERIT") % int(_result.get("merit", 0)))
		return
	var outcome: String = str(_result.get("contest_result", ""))
	_result_title = tr(str(TITLE_KEYS.get(outcome, "AURORA_RESULT_FAILED")))
	match outcome:
		IdeaPresentation.RESULT_WIN:
			_compose_win()
		IdeaPresentation.RESULT_TIE:
			_compose_tie()
		IdeaPresentation.RESULT_LOSS:
			_compose_loss()


func _compose_win() -> void:
	_result_lines.append(tr("AURORA_LINE_MERIT") % int(_result.get("merit", 0)))
	for effect: Dictionary in _effects("npc_reputation"):
		_result_lines.append(tr("AURORA_LINE_USURPER") % [_accuser_name(), roundi(float(effect["delta"]))])


func _compose_tie() -> void:
	_result_lines.append(tr("AURORA_LINE_NO_MERIT"))
	var records: Array[Dictionary] = _effects("suspicion_record")
	var points: float = float(records[0]["points"]) if not records.is_empty() \
			else Database.get_balance_float(IdeaPresentation.B_TIE_SUSPICION)
	_result_lines.append(tr("AURORA_LINE_TIE_SUSPICION") % [roundi(points), _accuser_name()])


func _compose_loss() -> void:
	_result_lines.append(tr("AURORA_LINE_REVERTS") % _accuser_name())
	for effect: Dictionary in _effects("player_reputation"):
		_result_lines.append(tr("AURORA_LINE_REPUTATION") % roundi(float(effect["delta"])))
	var beliefs: Array[Dictionary] = _effects("belief")
	if not beliefs.is_empty():
		var certainty: int = roundi(float(beliefs[0]["certainty"]) * PERCENT)
		_result_lines.append(tr("AURORA_LINE_BELIEF") % [beliefs.size(), certainty])


func _preparation_lines() -> Array[String]:
	var out: Array[String] = []
	if float(_prep.get("minutes", 0.0)) > 0.0:
		out.append(tr("AURORA_PREP_SPENT") % roundi(float(_prep["minutes"])))
	var outcome: String = str(_prep.get("outcome", ""))
	if outcome.is_empty():
		return out
	out.append(tr(str(DutySystem.ASSIST_RESULT_KEYS.get(outcome, "AURORA_STATUS_GENERIC"))))
	if int(_prep.get("merit", 0)) > 0:
		out.append(tr("AURORA_ASSIST_MERIT") % int(_prep["merit"]))
	if not str(_prep.get("detected_by", "")).is_empty():
		out.append(tr("AURORA_ASSIST_DETECTED") % [IdeaPool.get_npc_display_name(str(_prep["detected_by"])),
				roundi(float(_prep.get("reputation_delta", 0.0)))])
	return out


func _status_text(status: String) -> String:
	var key: String = "AURORA_STATUS_" + status.to_upper()
	var text: String = tr(key)
	return text if text != key else tr("AURORA_STATUS_GENERIC")


func _effects(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect: Variant in _result.get("effects", []):
		if effect is Dictionary and str((effect as Dictionary).get("kind", "")) == kind:
			out.append(effect)
	return out


func _accuser() -> String:
	return str(_result.get("accuser", ""))


func _accuser_name() -> String:
	return IdeaPool.get_npc_display_name(_accuser())


# ─── Escenificación de la presentación ────────────────────────

func _stage_presentation() -> void:
	var idea: Idea = IdeaPool.get_idea(_idea_id)
	_stage.clear_bubbles()
	_stage.frame(SceneStage.FRAME_AURORA)
	_stage.set_prop("screen_title", _idea_title(idea))
	_stage.set_prop("screen_sub", tr("AURORA_SCREEN_BY") % PlayerState.get_player_name())
	_stage.set_seated(PLAYER, false)
	_stage.walk_to(PLAYER, SceneStage.aurora_podium_spot(), _walk(), Vector2(0.45, 1), "chat")
	for id: String in _attendees:
		_stage.look_at_actor(id, PLAYER)
	_timeline.then(_walk(), _pitch)
	var after: float = SceneStage.reading_time(tr("AURORA_PITCH"))
	if bool(_result.get("contested", false)):
		_timeline.then(after, _accuse, true)
		_timeline.then(SceneStage.reading_time(tr(_accuse_key())), _show_clash, true)
		_timeline.then(_meter_seconds(), _reveal_result, true)
	else:
		_timeline.then(after, _reveal_result, true)


func _pitch() -> void:
	_stage.say(PLAYER, tr("AURORA_PITCH"))
	var detector: String = str(_prep.get("detected_by", ""))
	if _stage.has_actor(detector):
		_stage.set_anim(detector, "suspicion")
		_stage.say(detector, tr("AURORA_ASSIST_WHISPER"), SceneStage.STYLE_WHISPER)


func _accuse_key() -> String:
	return ACCUSE_KEYS[posmod(hash(_idea_id), ACCUSE_KEYS.size())]


## La acusación, en primer plano: el acusador se levanta y señala; el orador se sobresalta.
func _accuse() -> void:
	var accuser: String = _accuser()
	if not _stage.has_actor(accuser):
		_stage.add_actor(accuser, SceneStage.cast_member(accuser), {"pos": STANDING_SPOT, "facing": Vector2.LEFT})
	_stage.clear_bubbles()
	_stage.badge(PLAYER, "", Color.WHITE)
	_stage.set_seated(accuser, false)
	var aim: Vector2 = _stage.actor_feet(PLAYER) - _stage.actor_feet(accuser)
	_stage.set_anim(accuser, "point", aim)
	_stage.set_marker(accuser, UITheme.color("loss"))
	_stage.say(accuser, tr(_accuse_key()), SceneStage.STYLE_SHOUT)
	_stage.set_anim(PLAYER, "startle", Vector2(0.6, 1), "idle")
	for id: String in _attendees:
		if id != accuser:
			_stage.look_at_actor(id, accuser)
	var both: Array[String] = [PLAYER, accuser]
	_stage.frame(_stage.actors_rect(both, CLOSEUP_PAD))
	SceneStage.play_sfx(self, SFX_STAND)


## El choque ocupa el panel lateral: las dos barras de credibilidad crecen con su cuenta y el tira y
## afloja marca la diferencia; la sala (acusador en pie, insignias) queda a la vista a la izquierda.
func _show_clash() -> void:
	_stage.say(_accuser(), "")
	_stage.frame(FRAME_CLASH)
	var box: VBoxContainer = _dock.open(tr("AURORA_CLASH_TITLE"))
	box.add_child(SceneStage.ui_label("“%s”" % _idea_title(IdeaPool.get_idea(_idea_id)), UITheme.V_CAPTION, true))
	var span: float = _credibility_span()
	box.add_child(_contender(_accuser(), _accuser_terms(), 0.0, span, _accuser_breakdown()))
	var vs: Label = SceneStage.ui_label(tr("AURORA_CLASH_VS"), UITheme.V_CAPTION)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(vs)
	var penalty: float = float(_result.get("player_suspicion", 0.0)) * Database.get_balance_float(IdeaPresentation.B_PER_SUSPICION)
	box.add_child(_contender(PLAYER, _player_terms(), penalty, span, _player_breakdown()))
	box.add_child(_build_meter())
	_badge_supporters()


func _build_meter() -> ClashMeter:
	_meter = ClashMeter.new()
	_meter.threshold = Database.get_balance_float(IdeaPresentation.B_CLASH_THRESHOLD)
	_meter.difference = float(_result.get("difference", 0.0))
	_meter.span = maxf(absf(_meter.difference) * METER_HEADROOM, _meter.threshold * METER_MIN_BANDS)
	_meter.duration = _meter_seconds()
	_meter.texts = [tr("AURORA_CLASH_SIDE_ACCUSER") % _accuser_name(),
			tr("AURORA_CLASH_TIE_BAND") % roundi(_meter.threshold), tr("AURORA_CLASH_SIDE_YOU")]
	return _meter


## Un contendiente: foto, nombre, desglose de la fórmula, cifra que cuenta y su barra.
func _contender(actor_id: String, terms: Array[Dictionary], penalty: float, span: float,
		breakdown: Array[String]) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var top: HBoxContainer = HBoxContainer.new()
	var member: Dictionary = SceneStage.cast_member(actor_id)
	top.add_child(SceneStage.PortraitBox.new(member["appearance"], Vector2(64, 72) * SceneStage.ui_scale()))
	var id_box: VBoxContainer = VBoxContainer.new()
	id_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_box.add_theme_constant_override("separation", 0)
	id_box.add_child(SceneStage.ui_label(tr("AURORA_CLASH_YOU") if actor_id == PLAYER else str(member["name"]), UITheme.V_STRONG))
	for line: String in breakdown:
		id_box.add_child(SceneStage.ui_label(line, UITheme.V_SMALL, true))
	top.add_child(id_box)
	var number: Label = SceneStage.ui_label("0", UITheme.V_NUMBER)
	top.add_child(number)
	box.add_child(top)
	var bar: CredBar = CredBar.new()
	bar.terms = terms
	bar.penalty = penalty
	bar.span = span
	bar.duration = _meter_seconds()
	bar.number = number
	bar.total = float(_result.get("player_credibility" if actor_id == PLAYER else "accuser_credibility", 0.0))
	_bars.append(bar)
	box.add_child(bar)
	return box


func _accuser_terms() -> Array[Dictionary]:
	var believers: float = float(_result.get("believers", 0)) * Database.get_balance_float(IdeaPresentation.B_PER_BELIEVER)
	return [{"value": float(_result.get("accuser_reputation", 0.0)), "color": UITheme.color("rep")},
			{"value": believers, "color": UITheme.color("loss")}]


func _player_terms() -> Array[Dictionary]:
	var allies: float = float(_result.get("allies", 0)) * Database.get_balance_float(IdeaPresentation.B_PER_ALLY)
	return [{"value": float(_result.get("player_reputation", 0.0)), "color": UITheme.color("rep")},
			{"value": allies, "color": UITheme.color("gain")}]


func _credibility_span() -> float:
	var top: float = maxf(CRED_SCALE_MIN, maxf(_positive_sum(_accuser_terms()), _positive_sum(_player_terms())))
	return top * CRED_HEADROOM


static func _positive_sum(terms: Array[Dictionary]) -> float:
	var sum: float = 0.0
	for term: Dictionary in terms:
		sum += maxf(float(term["value"]), 0.0)
	return sum


func _player_breakdown() -> Array[String]:
	var allies: int = int(_result.get("allies", 0))
	var suspicion: float = float(_result.get("player_suspicion", 0.0))
	return [tr("AURORA_CLASH_REPUTATION") % roundi(float(_result.get("player_reputation", 0.0))),
		tr("AURORA_CLASH_ALLIES") % [allies, roundi(allies * Database.get_balance_float(IdeaPresentation.B_PER_ALLY))],
		tr("AURORA_CLASH_SUSPICION") % [roundi(suspicion),
			roundi(suspicion * Database.get_balance_float(IdeaPresentation.B_PER_SUSPICION))]]


func _accuser_breakdown() -> Array[String]:
	var believers: int = int(_result.get("believers", 0))
	return [tr("AURORA_CLASH_REPUTATION") % roundi(float(_result.get("accuser_reputation", 0.0))),
		tr("AURORA_CLASH_BELIEVERS") % [believers, _believers_here().size(),
			roundi(believers * Database.get_balance_float(IdeaPresentation.B_PER_BELIEVER))]]


## Presentes (sin el acusador) que conocen la idea: los únicos con insignia «Lo sabe». Nunca más
## que los creyentes que cuenta la fórmula (una cifra forzada en QA manda).
func _believers_here() -> Array[String]:
	var out: Array[String] = []
	var idea: Idea = IdeaPool.get_idea(_idea_id)
	var limit: int = int(_result.get("believers", 0))
	if idea == null:
		return out
	for id: String in _attendees:
		if out.size() < limit and id != _accuser() and idea.known_by.has(id):
			out.append(id)
	return out


## Insignias de la fórmula sobre la sala: aliados presentes (+15) y presentes que saben que es suya (+20).
func _badge_supporters() -> void:
	var allies: int = int(_result.get("allies", 0))
	var ally_pts: int = roundi(Database.get_balance_float(IdeaPresentation.B_PER_ALLY))
	var believer_pts: int = roundi(Database.get_balance_float(IdeaPresentation.B_PER_BELIEVER))
	var here: Array[String] = _believers_here()
	for id: String in _attendees:
		if id == _accuser():
			continue
		if allies > 0 and IdeaPresentation.is_ally(id):
			allies -= 1
			_stage.badge(id, tr("AURORA_BADGE_ALLY") % ally_pts, UITheme.color("gain"))
			_stage.set_marker(id, UITheme.color("gain"))
		elif here.has(id):
			_stage.badge(id, tr("AURORA_BADGE_BELIEVER") % believer_pts, UITheme.color("loss"))


## Veredicto: reacciones en la sala, sello y consecuencias exactas en el panel.
func _reveal_result() -> void:
	_react()
	_snap_meters()
	var box: VBoxContainer
	var first: Control = null
	if is_clash_visible():
		box = _dock.content
		first = _add_stamp(box)
	else:
		_stage.frame(FRAME_CLASH)
		box = _dock.open(_result_title)
	for line: String in _prep_lines:
		box.add_child(SceneStage.ui_label(line, UITheme.V_SMALL, true))
	for line: String in _result_lines:
		var label: Label = SceneStage.ui_label(line, UITheme.V_STRONG, true, _line_color())
		box.add_child(label)
		if first == null:
			first = label
	_dock.add_buttons([SceneStage.ui_button(tr("AURORA_CONTINUE"), UITheme.V_PRIMARY, continue_scene)])
	_dock.reveal_later(first)


func _add_stamp(box: VBoxContainer) -> Label:
	var stamp: Label = SceneStage.ui_label(_result_title.to_upper(), UITheme.V_TITLE, true, _line_color())
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stamp)
	return stamp


func _snap_meters() -> void:
	if _meter != null and is_instance_valid(_meter):
		_meter.snap()
	for bar: CredBar in get_credibility_bars():
		bar.snap()


func _line_color() -> Color:
	match str(_result.get("contest_result", "")):
		IdeaPresentation.RESULT_WIN:
			return UITheme.color("gain")
		IdeaPresentation.RESULT_TIE:
			return UITheme.color("warn")
		IdeaPresentation.RESULT_LOSS:
			return UITheme.color("loss")
	return UITheme.color("gain") if int(_result.get("merit", 0)) > 0 else UITheme.color("paper")


## Reacciones de la sala al resultado (mismo sistema, distinta coreografía).
func _react() -> void:
	_stage.clear_bubbles()
	var merit: int = int(_result.get("merit", 0))
	if merit > 0:
		_stage.badge(PLAYER, tr("AURORA_BADGE_MERIT") % merit, UITheme.color("gain"))
	if str(_result.get("status", "")) != IdeaPool.STATUS_OK:
		return
	if not bool(_result.get("contested", false)):
		_applause()
		return
	match str(_result.get("contest_result", "")):
		IdeaPresentation.RESULT_WIN:
			_react_win()
		IdeaPresentation.RESULT_TIE:
			_react_tie()
		IdeaPresentation.RESULT_LOSS:
			_react_loss()


func _applause() -> void:
	var keys: Array[String] = ["AURORA_REACT_APPLAUSE", "AURORA_REACT_APPLAUSE_2"]
	var used: Array[String] = []
	for key: String in keys:
		var speaker: String = _visible_other(used)
		if speaker.is_empty():
			return
		used.append(speaker)
		_stage.set_anim(speaker, "chat")
		_stage.say(speaker, tr(key), SceneStage.STYLE_SAY, 0.0)


func _react_win() -> void:
	var accuser: String = _accuser()
	_stage.set_seated(accuser, true)
	_stage.say(accuser, tr("AURORA_REACT_WIN_ACCUSER"), SceneStage.STYLE_WHISPER, 0.0)
	var delta: float = Database.get_balance_float(IdeaPresentation.B_ACCUSER_REPUTATION)
	_stage.badge(accuser, tr("AURORA_BADGE_REP") % roundi(delta), UITheme.color("loss"))
	for id: String in _attendees:
		if id != accuser:
			_stage.look_at_actor(id, accuser)
	var witness: String = _visible_other([accuser])
	if not witness.is_empty():
		_stage.say(witness, tr("AURORA_REACT_WIN_ROOM"), SceneStage.STYLE_WHISPER, 0.0)
	_stage.set_anim(PLAYER, "chat", Vector2(0.45, 1))


func _react_tie() -> void:
	var accuser: String = _accuser()
	var points: int = roundi(Database.get_balance_float(IdeaPresentation.B_TIE_SUSPICION))
	_stage.set_seated(accuser, true)
	_stage.badge(accuser, tr("AURORA_BADGE_SUSPICION") % points, UITheme.color("warn"))
	_stage.badge(PLAYER, tr("AURORA_BADGE_SUSPICION") % points, UITheme.color("warn"))
	var chair: String = _visible_other([accuser])
	if not chair.is_empty():
		_stage.set_anim(chair, "chat")
		_stage.say(chair, tr("AURORA_REACT_TIE_CHAIR"), SceneStage.STYLE_SAY, 0.0)
	_stage.set_anim(PLAYER, "idle", Vector2(0.45, 1))


func _react_loss() -> void:
	var accuser: String = _accuser()
	var delta: float = Database.get_balance_float(IdeaPresentation.B_LOSS_REPUTATION)
	_stage.set_anim(accuser, "chat", Vector2(-0.6, 0.4))
	_stage.say(accuser, tr("AURORA_REACT_LOSS_ACCUSER"), SceneStage.STYLE_SAY, 0.0)
	_stage.set_anim(PLAYER, "caught", Vector2(0.45, 1))
	_stage.say(PLAYER, tr("AURORA_REACT_LOSS_PLAYER"), SceneStage.STYLE_WHISPER, 0.0)
	_stage.badge(PLAYER, tr("AURORA_BADGE_REP") % roundi(delta), UITheme.color("loss"))
	for effect: Dictionary in _effects("belief"):
		var holder: String = str(effect["holder"])
		if holder != accuser and _stage.has_actor(holder):
			_stage.set_anim(holder, "suspicion")
			_stage.look_at_actor(holder, PLAYER)
	_stage.set_prop("screen_sub", tr("AURORA_SCREEN_BY") % _accuser_name())


## Un asistente de la fila del fondo (de cara a cámara) fuera de `excluded`, el más alejado de
## ellos para que los bocadillos no se pisen.
func _visible_other(excluded: Array[String]) -> String:
	var best: String = ""
	var best_score: float = -INF
	for id: String in _attendees:
		if excluded.has(id) or not _stage.has_actor(id):
			continue
		var score: float = 0.0 if (_stage.get_actor(id)["facing"] as Vector2).y > 0.5 else -DESIGN_FAR
		for other: String in excluded:
			score += absf(_stage.actor_feet(id).x - _stage.actor_feet(other).x)
		if score > best_score:
			best_score = score
			best = id
	return best


# ─── Presentaciones ajenas y cierre ───────────────────────────

func _run_others() -> void:
	_step = STEP_OTHERS
	_timeline.clear()
	_dock.close()
	_meter = null
	_bars.clear()
	_stage.clear_bubbles()
	_stage.clear_badges()
	_stage.clear_markers()
	_stage.frame(SceneStage.FRAME_AURORA)
	_return_to_seat()
	_others = _close_meeting()
	var delay: float = _walk()
	for entry: Dictionary in _others:
		delay = _schedule_other(entry, delay)
	if _others.is_empty() and not _chair_id.is_empty():
		_timeline.then(delay, _stage.say.bind(_chair_id, tr("AURORA_OTHERS_NONE"), SceneStage.STYLE_SAY, 0.0))
		delay = _pause()
	_timeline.then(delay, _show_others_panel, true)
	_settle()


func _return_to_seat() -> void:
	if _stage.get_actor(PLAYER).get("seated", true):
		return
	_stage.walk_to(PLAYER, _stage.seat_point(PLAYER), _walk(), Vector2.RIGHT, "idle")
	_timeline.then(_walk(), _stage.set_seated.bind(PLAYER, true))


## Cierre de la reunión (contrato): convocados → close_meeting (recoge idea_presented ajenos)
## → release_attendees. → [{idea_id, owner, merit, title}].
func _close_meeting() -> Array[Dictionary]:
	var captured: Array[Dictionary] = []
	if not IdeaPool.is_meeting_open():
		return captured
	var invitees: Array[String] = IdeaPool.get_meeting_invitees()
	var listener: Callable = func(idea_id: String, presenter: String, merit: int) -> void:
		if presenter != PLAYER:
			captured.append({"idea_id": idea_id, "owner": presenter, "merit": merit,
					"title": _idea_title(IdeaPool.get_idea(idea_id))})
	EventBus.idea_presented.connect(listener)
	IdeaPool.close_meeting()
	EventBus.idea_presented.disconnect(listener)
	IdeaPresentation.release_attendees(invitees)
	return captured


## Cada presentador va al atril, presenta (pantalla, bocadillo, mérito) y vuelve a su silla.
## Devuelve la espera hasta el siguiente golpe.
func _schedule_other(entry: Dictionary, delay: float) -> float:
	var presenter: String = str(entry["owner"])
	var pitch: String = tr("AURORA_OTHER_PITCH") % str(entry["title"])
	_timeline.then(delay, _walk_to_podium.bind(presenter, entry))
	if not _stage.has_actor(presenter):
		return SceneStage.reading_time(pitch)
	_timeline.then(_walk(), _pitch_other.bind(presenter, entry, pitch), true)
	_timeline.then(SceneStage.reading_time(pitch), _walk_back.bind(presenter))
	_timeline.then(_walk(), _stage.set_seated.bind(presenter, true))
	return _pause()


func _walk_to_podium(presenter: String, entry: Dictionary) -> void:
	_stage.clear_bubbles()
	_stage.clear_badges()
	_stage.set_prop("screen_title", str(entry["title"]))
	_stage.set_prop("screen_sub", tr("AURORA_SCREEN_BY") % IdeaPool.get_npc_display_name(presenter))
	if _stage.has_actor(presenter):
		_stage.walk_to(presenter, SceneStage.aurora_podium_spot(), _walk(), Vector2(0.45, 1), "chat",
				_aisle(presenter))


func _pitch_other(presenter: String, entry: Dictionary, pitch: String) -> void:
	_stage.say(presenter, pitch, SceneStage.STYLE_SAY, 0.0)
	_stage.badge(presenter, tr("AURORA_BADGE_MERIT") % int(entry["merit"]), UITheme.color("gain"))
	for id: String in _attendees:
		if id != presenter:
			_stage.look_at_actor(id, presenter)


func _walk_back(presenter: String) -> void:
	_stage.say(presenter, "")
	_stage.badge(presenter, "", Color.WHITE)
	var back: Array[Vector2] = _aisle(presenter)
	back.reverse()
	_stage.walk_to(presenter, _stage.seat_point(presenter), _walk(), Vector2.DOWN, "idle", back)


## Pasillo para rodear la mesa entre la silla de `actor_id` y el atril (por el lado izquierdo).
func _aisle(actor_id: String) -> Array[Vector2]:
	var seat: Vector2 = _stage.seat_point(actor_id)
	var x: float = SceneStage.aurora_podium_spot().x + AISLE_OFFSET
	if seat.y > SceneStage.AURORA_TABLE.get_center().y:
		return [Vector2(seat.x, seat.y + AISLE_OFFSET), Vector2(x, seat.y + AISLE_OFFSET)]
	return [Vector2(seat.x, seat.y - AISLE_OFFSET), Vector2(x, seat.y - AISLE_OFFSET)]


func _show_others_panel() -> void:
	_stage.frame(FRAME_TABLE)
	var box: VBoxContainer = _dock.open(tr("AURORA_OTHERS_TITLE"))
	if _others.is_empty():
		box.add_child(SceneStage.ui_label(tr("AURORA_OTHERS_NONE"), "", true))
	for entry: Dictionary in _others:
		var line: String = tr("AURORA_OTHER_LINE") % [IdeaPool.get_npc_display_name(str(entry["owner"])),
				str(entry["title"]), int(entry["merit"])]
		box.add_child(SceneStage.ui_label(line, "", true))
	_dock.add_buttons([SceneStage.ui_button(tr("AURORA_CONTINUE"), UITheme.V_PRIMARY, continue_scene)])


func _show_wrap() -> void:
	_step = STEP_WRAP
	_stage.clear_bubbles()
	_stage.clear_badges()
	for id: String in _stage.actor_ids():
		if _stage.has_chair(str(_stage.get_actor(id).get("seat", ""))):
			_stage.set_seated(id, true)
	if not _chair_id.is_empty():
		_stage.say(_chair_id, tr("AURORA_CHAIR_CLOSE"), SceneStage.STYLE_SAY, 0.0)
	var yours: String = tr("AURORA_WRAP_SILENT") if _result.is_empty() else tr("AURORA_WRAP_YOURS") % _result_title
	var box: VBoxContainer = _dock.open(tr("AURORA_WRAP_TITLE"))
	box.add_child(SceneStage.ui_label(yours, "", true))
	box.add_child(SceneStage.ui_label(tr("AURORA_WRAP_OTHERS") % _others.size(), UITheme.V_SMALL, true))
	box.add_child(SceneStage.ui_label(tr("AURORA_WRAP_ACTIONS"), UITheme.V_SMALL, true))
	_dock.add_buttons([SceneStage.ui_button(tr("AURORA_LEAVE"), UITheme.V_PRIMARY, finish)])


# ─── Ritmo ────────────────────────────────────────────────────

func _settle() -> void:
	if instant:
		fast_forward()


func _walk() -> float:
	return Database.get_balance_float(B_WALK)


func _pause() -> float:
	return Database.get_balance_float(B_PAUSE)


func _meter_seconds() -> float:
	return Database.get_balance_float(B_METER)
