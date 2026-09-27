# interrogation_scene.gd — Interrogatorio en la sala de P15 (§12.5, PASO 29): el investigador presenta las piezas de una en una, cinco respuestas, el peso del caso contra la línea de 7,0 y el detalle de tono (disculpa o portazo).
# PROPIETARIO DE: la sesión Interrogation en curso (la crea la escena), el paso de la escena, la pieza mostrada, el resultado final mostrado y el registro de efectos de sonido pedidos.
# ESCUCHA: nada.
class_name InterrogationScene
extends Control

## API: InterrogationScene.open(host, case_id, context := {}) → la escena (modal que pausa el reloj
## si host es UIRoot; si no, hija de host). context es el de Interrogation.new (reputation,
## suspicion, alibi, has_legal_contact, verification_roll): vacío en el juego, forzado en QA/tests.
## Pasos: STEP_INTRO (tono de §12.5: reputación > 85 → disculpa con café y luz cálida; sospecha > 70
## → la puerta se cierra de golpe: animación, sacudida y sonido) → STEP_PIECE (la pieza sobre la
## mesa espera respuesta) ⇄ STEP_REACT → STEP_END (Interrogation.finish(): éxito si el peso < 7,0;
## veredicto o caso congelado) → leave() → closed().
## Cada respuesta llama a Interrogation.answer(), que aplica los efectos (Security, NPCDirector,
## BeliefNet) y emite interrogation_answered; la escena solo lo representa y emite answered().
## Maquetación: la sala a la izquierda (cámara), la ficha de la pieza junto a la mesa y el panel
## lateral (SceneStage.Dock) con el medidor del caso fijo arriba y, debajo, las respuestas, la
## reacción o el final. El medidor crece su escala si el peso supera la inicial (coartada falsa ×2).
## Esc: adelanta hasta el siguiente punto de lectura (la reacción a cada respuesta, la pieza
## siguiente), cierra el selector o, al final, sale.
## DECISIONES: no se puede salir a mitad; si la escena se retira sin terminar, Security caduca el
## interrogatorio abandonado. «Acusar a otro» cambia el panel por un selector (las respuestas no
## quedan pulsables detrás): sospechosos del caso, quien ronda la sala del incidente y colegas que
## conocen al jugador (máx. escenas.max_acusables); sin población, nominados del catálogo. Si nadie
## ocupa Auditoría o Seguridad (Security no da investigador, o el suyo ya no está), interroga un
## vigilante sin nombre. Portazo: se pide "door_slam" a SfxBank; mientras no exista, suena el golpe
## seco con el hilo musical cortado y la escena publica su propio subtítulo de la puerta.

signal closed()
signal answered(answer_id: String, result: Dictionary)

const STEP_INTRO := "intro"
const STEP_PIECE := "piece"
const STEP_REACT := "react"
const STEP_END := "end"
const PLAYER := SceneStage.PLAYER_ID
const PRESENT_PREFIX := "INTERROGATION_PRESENT_"
const REACT_PREFIX := "INTERROGATION_REACT_"
const SAY_KEYS: Dictionary = {
	Interrogation.ANSWER_DENY: "INTERROGATION_SAY_DENY", Interrogation.ANSWER_EXPLAIN: "INTERROGATION_SAY_EXPLAIN",
	Interrogation.ANSWER_ACCUSE: "INTERROGATION_SAY_ACCUSE", Interrogation.ANSWER_SILENCE: "INTERROGATION_SAY_SILENCE",
	Interrogation.ANSWER_LAWYER: "INTERROGATION_SAY_LAWYER",
}
## Gesto del jugador (sentado) al responder.
const SAY_ANIMS: Dictionary = {
	Interrogation.ANSWER_DENY: "chat", Interrogation.ANSWER_EXPLAIN: "chat",
	Interrogation.ANSWER_ACCUSE: "point", Interrogation.ANSWER_SILENCE: "sit",
	Interrogation.ANSWER_LAWYER: "phone",
}
## Presentación de cada tipo de pieza (color de la paleta de interfaz e icono), como los iconos de
## UITheme por tipo de interactivo; un tipo nuevo cae en el acento y el icono de documento.
const TYPE_COLORS: Dictionary = {
	"direct_witness": "warn", "partial_witness": "det_partial", "camera_footage": "sus",
	"card_log": "rep", "compromising_item": "danger", "accounting_trail": "gain",
	"unsourced_rumour": "muted", "body_found": "det_flagrant", "forged_document": "hazard",
}
const TYPE_ICONS: Dictionary = {
	"direct_witness": "eye", "partial_witness": "eye_partial", "camera_footage": "camera",
	"card_log": "card", "unsourced_rumour": "rumour", "accounting_trail": "ledger",
}
## Sello de cada resultado: texto y color de la paleta de interfaz (tinta sobre el papel de la ficha).
const STAMPS: Dictionary = {
	Interrogation.OUTCOME_PIECE_REMOVED: ["INTERROGATION_STAMP_STRUCK", "gain"],
	Interrogation.OUTCOME_ALIBI_ACCEPTED: ["INTERROGATION_STAMP_CLEARED", "gain"],
	Interrogation.OUTCOME_ALIBI_FALSE: ["INTERROGATION_STAMP_DOUBLED", "loss"],
	Interrogation.OUTCOME_PIECE_TRANSFERRED: ["INTERROGATION_STAMP_MOVED", "rep"],
	Interrogation.OUTCOME_CASE_FROZEN: ["INTERROGATION_STAMP_FROZEN", "rep"],
}
const STAMP_DEFAULT: Array = ["INTERROGATION_STAMP_NOTED", "loss"]
const SFX_DOOR := "door_slam"
const SFX_DOOR_FALLBACK := "caught_thud"
const SUB_DOOR := "INTERROGATION_SUB_DOOR_SLAM"
const SFX_GOOD: Array[String] = ["ui_confirm"]
const SFX_BAD: Array[String] = ["ui_error"]
const B_PAUSE := "escenas.pausa_segundos"
const B_CARD := "escenas.tarjeta_segundos"
const B_METER := "escenas.medidor_segundos"
const B_SLAM_WAIT := "escenas.portazo_espera_segundos"
const B_SLAM := "escenas.portazo_segundos"
const B_SHAKE_PX := "escenas.temblor_px"
const B_SHAKE_S := "escenas.temblor_segundos"
const B_MAX_ACCUSE := "escenas.max_acusables"
const PERCENT := 100.0
const CARD_SIZE := Vector2(400, 268)
## Los ids de caso son "case_<n>" (Security.CASE_ID_FORMAT): la cabecera muestra el número.
const CASE_ID_SEPARATOR := "_"
## Rapidez con que la ficha en reposo sigue su sitio si la cámara se mueve (1/s).
const CARD_FOLLOW := 12.0
## Presentación (no ajustes de juego): la ficha nace pequeña sobre la mesa y queda algo inclinada;
## el medidor deja margen sobre el peso; el rechazo sacude la ficha a pasos cortos; la tinta de los
## sellos se oscurece para leerse sobre papel.
const CARD_START_SCALE := 0.3
const CARD_TILT := -0.05
const CARD_SHAKE_STEP := 0.05
const STAMP_INK_DARKEN := 0.3
const METER_HEADROOM := 1.18
const SLAM_POP_FROM := 0.2
const PICKER_COLUMNS := 2
const HEADER_GAP := 12.0
## Saltar animaciones: un paso de tween mayor que cualquier animación de la escena; las que nacen al
## terminar otra (el portazo lanza la onomatopeya) se completan en pasadas sucesivas.
const FORWARD_STEP := 1000.0
const MAX_FORWARD_PASSES := 4

var instant: bool = false
var case_id: String = ""

var _context: Dictionary = {}
var _session: Interrogation
var _intro: Dictionary = {}
var _tone: String = Interrogation.TONE_NEUTRAL
var _investigator: String = ""
var _step: String = STEP_INTRO
var _stage: SceneStage
var _dock: SceneStage.Dock
var _timeline: SceneStage.Timeline = SceneStage.Timeline.new()
var _tweens: Array[Tween] = []
var _card_layer: Control
var _card: EvidenceCard
var _meter: CaseMeter
var _header: PanelContainer
var _header_sub: Label
var _caption_panel: PanelContainer
var _caption: Label
var _caption_text: String = ""
var _notice: Label
var _piece: Dictionary = {}
var _weight_before: float = 0.0
var _last_result: Dictionary = {}
var _end_result: Dictionary = {}
var _end_title: String = ""
var _end_lines: Array[String] = []
var _sfx_requests: Array[String] = []
var _door_slammed: bool = false
var _card_resting: bool = false
var _picker_open: bool = false
var _done: bool = false


## Ficha de la pieza: tipo, peso, certeza y lo que cuenta (peso × certeza), con sello.
class EvidenceCard extends Control:
	var type_id: String = ""
	var type_name: String = ""
	var exhibit: String = ""
	var weight: float = 0.0
	var certainty: float = 1.0
	var accent: Color = Color.GRAY
	var captions: Array[String] = ["", "", ""]
	var stamp: String = ""
	var stamp_color: Color = Color.RED

	func _init() -> void:
		custom_minimum_size = InterrogationScene.CARD_SIZE
		size = InterrogationScene.CARD_SIZE
		pivot_offset = InterrogationScene.CARD_SIZE * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink: Color = SceneStage.ink()
		var body: Rect2 = Rect2(Vector2.ZERO, size)
		draw_colored_polygon(SceneStage.rounded_rect(Rect2(Vector2(7, 9), size), 12.0), UITheme.color("shadow"))
		draw_colored_polygon(SceneStage.rounded_rect(body, 12.0), SceneStage.C_SHEET)
		draw_rect(Rect2(3, 3, size.x - 6, 46), accent)
		var loop: PackedVector2Array = SceneStage.rounded_rect(body, 12.0)
		loop.append(loop[0])
		draw_polyline(loop, ink, 3.0, true)
		var bold: Font = UITheme.font(UITheme.FONT_BOLD)
		var semi: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		draw_string(bold, Vector2(18, 34), exhibit, HORIZONTAL_ALIGNMENT_LEFT, size.x - 90, 18, UITheme.readable_on(accent))
		_draw_clip(Vector2(size.x - 52, -12))
		InterrogationScene.draw_evidence_icon(self, type_id, Rect2(18, 64, 72, 72), accent)
		draw_multiline_string(bold, Vector2(106, 90), type_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 124, 25, 2, ink)
		draw_line(Vector2(18, 156), Vector2(size.x - 18, 156), Color(ink, 0.25), 2.0)
		var values: Array[String] = [SceneStage.decimal(weight),
				"%d%%" % roundi(certainty * InterrogationScene.PERCENT), SceneStage.decimal(weight * certainty)]
		var col_w: float = (size.x - 36.0) / 3.0
		for i: int in 3:
			var x: float = 18.0 + col_w * float(i)
			draw_string(semi, Vector2(x, 186), captions[i].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, col_w - 8.0,
					15, Color(ink, 0.6))
			draw_string(bold, Vector2(x, 232), values[i], HORIZONTAL_ALIGNMENT_LEFT, col_w - 8.0, 34,
					accent.darkened(0.35) if i == 2 else ink)
		_draw_stamp(bold)

	func _draw_clip(at: Vector2) -> void:
		var pts: PackedVector2Array = SceneStage.rounded_rect(Rect2(at, Vector2(22, 54)), 11.0)
		pts.append(pts[0])
		draw_polyline(pts, SceneStage.C_STEEL, 4.0, true)

	func _draw_stamp(font: Font) -> void:
		if stamp.is_empty():
			return
		var fs: int = 38
		var w: float = minf(font.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, size.x - 60.0)
		draw_set_transform(size * 0.5 + Vector2(0, -6), -0.18, Vector2.ONE)
		var box: Rect2 = Rect2(-w * 0.5 - 18, -34, w + 36, 58)
		draw_rect(box, Color(stamp_color, 0.12))
		draw_rect(box, stamp_color, false, 5.0)
		draw_string(font, Vector2(-w * 0.5, 12), stamp, HORIZONTAL_ALIGNMENT_LEFT, w, fs, stamp_color)
		draw_set_transform(Vector2.ZERO)


## Medidor del peso del caso contra el jugador: una barra por pieza (peso × certeza), las
## circunstancias (acceso, móvil, último en salir) rayadas y la línea de éxito (7,0). Su escala
## crece (animada) si el total supera la que tenía: nada se sale de la barra.
class CaseMeter extends Control:
	var segments: Array[Dictionary] = []
	var bonus: float = 0.0
	var bonus_shown: float = 0.0
	var threshold: float = 7.0
	var span: float = 14.0
	var span_target: float = 14.0
	var rate: float = 10.0
	var highlight: String = ""
	var title: String = ""
	var line_text: String = ""
	var extra_text: String = ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size.y = 104.0 * SceneStage.ui_scale()

	## pieces: [{id, value, color}] en orden; los que faltan se encogen hasta desaparecer.
	func set_targets(pieces: Array[Dictionary], p_bonus: float) -> void:
		for seg: Dictionary in segments:
			seg["target"] = 0.0
		for piece: Dictionary in pieces:
			var seg: Dictionary = _find(str(piece["id"]))
			if seg.is_empty():
				seg = {"id": piece["id"], "shown": float(piece["value"]), "color": piece["color"]}
				segments.append(seg)
			seg["target"] = float(piece["value"])
		bonus = p_bonus
		queue_redraw()

	func snap() -> void:
		for seg: Dictionary in segments:
			seg["shown"] = seg["target"]
		bonus_shown = bonus
		span = span_target
		queue_redraw()

	func total_shown() -> float:
		var total: float = bonus_shown
		for seg: Dictionary in segments:
			total += float(seg["shown"])
		return total

	func total_target() -> float:
		var total: float = bonus
		for seg: Dictionary in segments:
			total += float(seg["target"])
		return total

	func _find(id: String) -> Dictionary:
		for seg: Dictionary in segments:
			if str(seg["id"]) == id:
				return seg
		return {}

	func _process(delta: float) -> void:
		var step: float = rate * delta
		var moved: bool = not is_equal_approx(bonus_shown, bonus) or not is_equal_approx(span, span_target)
		bonus_shown = move_toward(bonus_shown, bonus, step)
		span = move_toward(span, span_target, step)
		for seg: Dictionary in segments:
			moved = moved or not is_equal_approx(float(seg["shown"]), float(seg["target"]))
			seg["shown"] = move_toward(float(seg["shown"]), float(seg["target"]), step)
		if moved:
			queue_redraw()

	func _draw() -> void:
		var k: float = SceneStage.ui_scale()
		var bold: Font = UITheme.font(UITheme.FONT_BOLD)
		var semi: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		var bar: Rect2 = Rect2(0, 42 * k, size.x, 28 * k)
		var per: float = size.x / maxf(span, 0.001)
		var line_x: float = threshold * per
		draw_rect(Rect2(bar.position, Vector2(line_x, bar.size.y)), UITheme.color("gain").darkened(0.62))
		draw_rect(Rect2(bar.position.x + line_x, bar.position.y, bar.size.x - line_x, bar.size.y), UITheme.color("sus_track"))
		var x: float = _draw_segments(bar, per)
		_draw_bonus(bar, per, x, k)
		draw_rect(bar, UITheme.color("line"), false, 2.0)
		draw_line(Vector2(line_x, bar.position.y - 8), Vector2(line_x, bar.end.y + 8), UITheme.color("paper"), 4.0)
		var fs: int = roundi(17 * k)
		draw_string(semi, Vector2(0, 26 * k), title, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.7, fs, UITheme.color("muted"))
		var total: float = total_shown()
		var total_text: String = SceneStage.decimal(total)
		var big: int = roundi(34 * k)
		var tw: float = bold.get_string_size(total_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		draw_string(bold, Vector2(size.x - tw, 32 * k), total_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big,
				UITheme.color("gain") if total < threshold else UITheme.color("loss"))
		var lw: float = semi.get_string_size(line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(semi, Vector2(clampf(line_x - lw * 0.5, 0, size.x - lw), bar.end.y + 26 * k), line_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.color("paper"))

	func _draw_segments(bar: Rect2, per: float) -> float:
		var x: float = bar.position.x
		for seg: Dictionary in segments:
			var w: float = minf(float(seg["shown"]) * per, bar.end.x - x)
			if w <= 0.5:
				continue
			var r: Rect2 = Rect2(x, bar.position.y + 3, w, bar.size.y - 6)
			var col: Color = seg["color"]
			draw_rect(r, col if str(seg["id"]) == highlight else col.darkened(0.3))
			draw_rect(r, UITheme.color("ink"), false, 2.0)
			if str(seg["id"]) == highlight:
				draw_rect(r.grow(2.0), UITheme.color("focus"), false, 3.0)
			x += w
		return x

	func _draw_bonus(bar: Rect2, per: float, x: float, k: float) -> void:
		var w: float = minf(bonus_shown * per, bar.end.x - x)
		if w <= 0.5:
			return
		var r: Rect2 = Rect2(x, bar.position.y + 3, w, bar.size.y - 6)
		draw_rect(r, UITheme.color("faint"))
		for i: int in int(r.size.x / 9.0):
			var hx: float = r.position.x + 4.0 + i * 9.0
			draw_line(Vector2(hx, r.end.y), Vector2(hx + 7, r.position.y), Color(UITheme.color("paper"), 0.3), 2.0)
		var semi: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		draw_string(semi, Vector2(0, bar.end.y + 26 * k), extra_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				roundi(15 * k), UITheme.color("muted"))


static func open(host: Node, p_case_id: String, context: Dictionary = {}) -> InterrogationScene:
	var scene: InterrogationScene = InterrogationScene.new(p_case_id, context)
	if host.has_method("open_modal"):
		host.call("open_modal", scene, true)
	else:
		host.add_child(scene)
	return scene


func _init(p_case_id: String = "", context: Dictionary = {}) -> void:
	name = "InterrogationScene"
	case_id = p_case_id
	_context = context.duplicate(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta(UIRoot.META_DIM, false)
	_stage = SceneStage.new()
	add_child(_stage)
	_card_layer = Control.new()
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_card_layer)
	_header = _build_header()
	add_child(_header)
	_caption_panel = _build_caption()
	add_child(_caption_panel)
	_dock = SceneStage.Dock.new()
	_meter = CaseMeter.new()
	_dock.fixed_top.add_child(_meter)
	add_child(_dock)


func _ready() -> void:
	SceneStage.ensure_theme(self)
	_dock.instant = instant
	_dock.layout_changed.connect(_relayout)
	resized.connect(_relayout)
	_header.resized.connect(_relayout)
	_caption_panel.resized.connect(_place_caption)
	_stage.configure(SceneStage.SET_INTERROGATION)
	_session = Interrogation.new(case_id, _context)
	_intro = _session.start()
	_investigator = _pick_investigator()
	_cast()
	_dress()
	_relayout()
	if _intro.is_empty():
		_show_no_case()
		return
	_tone = str(_intro.get("tone", Interrogation.TONE_NEUTRAL))
	_refresh_meter(true)
	_play_intro()


## Al salir del árbol se detienen las animaciones propias (ninguna llama a la escena ya retirada).
func _exit_tree() -> void:
	for t: Tween in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()


func _process(delta: float) -> void:
	_timeline.tick(delta)
	if _card_resting and _card != null:
		_card.position = _card.position.lerp(_card_target(), minf(delta * CARD_FOLLOW, 1.0))
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


func get_session() -> Interrogation:
	return _session


func get_tone() -> String:
	return _tone


func get_intro() -> Dictionary:
	return _intro.duplicate(true)


func get_investigator() -> String:
	return _investigator


func is_door_closed() -> bool:
	return float(_stage.get_prop("door", 0.0)) <= 0.0


func has_door_slammed() -> bool:
	return _door_slammed


## Efectos de sonido pedidos por la escena, en orden (el primero de cada petición).
func get_sfx_requests() -> Array[String]:
	return _sfx_requests.duplicate()


## La pieza que está sobre la mesa ({} si ninguna).
func get_shown_piece() -> Dictionary:
	return _piece.duplicate()


func get_card() -> EvidenceCard:
	return _card


func get_card_stamp() -> String:
	return _card.stamp if _card != null else ""


## Lo que la escena narra ahora: el tono de apertura, el resultado de la última respuesta o un
## rechazo por requisito ("" mientras la pieza espera respuesta).
func get_caption() -> String:
	return _caption_text


func get_last_result() -> Dictionary:
	return _last_result.duplicate()


func get_end_result() -> Dictionary:
	return _end_result.duplicate()


func get_end_title() -> String:
	return _end_title


func get_end_lines() -> Array[String]:
	return _end_lines.duplicate()


## Peso total del caso contra el jugador según Security (piezas × certeza + circunstancias).
func get_case_weight() -> float:
	return Security.get_case_weight_against(PLAYER, case_id)


func get_meter_weight() -> float:
	return _meter.total_target()


func get_meter() -> CaseMeter:
	return _meter


func get_visible_texts() -> Array[String]:
	var out: Array[String] = []
	SceneStage.collect_texts(self, out)
	return out


func available_answers() -> Array[String]:
	return _session.available_answers() if _session != null else [] as Array[String]


func is_finished() -> bool:
	return _step == STEP_END


func is_picker_open() -> bool:
	return _picker_open


## Responde a la pieza sobre la mesa con Interrogation.answer(). `accused` solo para acusar.
func answer(answer_id: String, accused: String = "") -> Dictionary:
	if _step != STEP_PIECE:
		return {}
	var piece: Dictionary = _piece.duplicate()
	_weight_before = get_case_weight()
	var result: Dictionary = _session.answer(answer_id, accused)
	_last_result = result
	answered.emit(answer_id, result.duplicate())
	if not bool(result.get("consumes_turn", true)):
		_requirement_missing(result)
		return result
	_step = STEP_REACT
	_picker_open = false
	var line: String = tr(str(SAY_KEYS.get(answer_id, "")))
	if answer_id == Interrogation.ANSWER_ACCUSE:
		line = line % IdeaPool.get_npc_display_name(accused)
	_show_waiting(answer_id)
	_stage.set_anim(PLAYER, str(SAY_ANIMS.get(answer_id, "sit")), _player_gesture_facing(answer_id))
	_stage.say(PLAYER, line)
	_timeline.then(SceneStage.reading_time(line), _react.bind(answer_id, accused, result, piece), true)
	_timeline.then(SceneStage.reading_time(_outcome_text(str(result["outcome"]))), _next)
	_settle()
	return result


## Acusables para «acusar a otro» (ver DECISIONES).
func accuse_candidates() -> Array[String]:
	var out: Array[String] = []
	var limit: int = Database.get_balance_int(B_MAX_ACCUSE)
	var inv: Investigation = Security.get_investigation(case_id)
	if inv != null:
		for id: String in inv.suspects:
			_add_candidate(out, id, limit)
		for npc: NPCRuntime in NPCDirector.get_npcs_near(inv.location):
			_add_candidate(out, npc.id, limit)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if out.size() >= limit:
			break
		if NPCDirector.knows_player(npc.id):
			_add_candidate(out, npc.id, limit)
	if out.is_empty():
		for named: NPCData in Database.get_all_named_npcs():
			_add_candidate(out, named.id, limit)
	return out


## El panel pasa a ser el selector de acusados (las respuestas dejan de estar a la vista).
func open_accuse_picker() -> void:
	if _step != STEP_PIECE:
		return
	_picker_open = true
	var candidates: Array[String] = accuse_candidates()
	var box: VBoxContainer = _dock.open(tr("INTERROGATION_ACCUSE_TITLE"))
	var body: String = "INTERROGATION_ACCUSE_BODY" if not candidates.is_empty() else "INTERROGATION_ACCUSE_NOBODY"
	box.add_child(SceneStage.ui_label(tr(body), "", true))
	var grid: GridContainer = GridContainer.new()
	grid.columns = PICKER_COLUMNS
	for id: String in candidates:
		grid.add_child(_candidate_tile(id))
	box.add_child(grid)
	_dock.add_buttons([SceneStage.ui_button(tr("INTERROGATION_CANCEL"), "", close_picker)])


func close_picker() -> void:
	if not _picker_open:
		return
	_picker_open = false
	if _step == STEP_PIECE:
		_show_answers()


## QA/tests: hace avanzar la línea de tiempo `seconds` sin depender del reloj real.
func advance(seconds: float) -> void:
	_timeline.tick(seconds)


## Adelanta hasta el siguiente punto de lectura (Esc): termina animaciones y ejecuta golpes hasta la
## reacción a la respuesta o la pieza siguiente, sin saltárselas.
func skip_ahead() -> void:
	_timeline.skip()
	_stage.finish_moves()
	_finish_tweens()


## Todo de golpe (modo instantáneo, tests): golpes, animaciones, medidor y cámara.
func fast_forward() -> void:
	_timeline.flush()
	_stage.finish_moves()
	_finish_tweens()
	_meter.snap()
	_stage.snap_camera()


## Esc: adelanta la animación, cierra el selector o, al final, sale. A mitad no se puede salir.
func request_close() -> void:
	if _is_animating():
		skip_ahead()
	elif _picker_open:
		close_picker()
	elif _step == STEP_END:
		leave()


func leave() -> void:
	if _done:
		return
	_done = true
	var owned: bool = closed.get_connections().is_empty()
	closed.emit()
	if owned:
		queue_free()


## UIRoot la llama al retirar la ventana: un interrogatorio sin terminar lo caduca Security.
func cancel() -> void:
	_done = true


## Investigador de la sesión: el que da Security si sigue en plantilla; si no hay (nadie ocupa
## Auditoría o Seguridad) o ya no está, el vigilante genérico (SceneStage.GUARD_ID).
static func choose_investigator(candidate: String) -> String:
	if candidate.is_empty() or candidate == PLAYER:
		return SceneStage.GUARD_ID
	var npc: NPCRuntime = NPCDirector.get_npc(candidate)
	if npc != null:
		return candidate if NPCDirector.is_active(candidate) else SceneStage.GUARD_ID
	return candidate if Database.get_named_npc(candidate) != null else SceneStage.GUARD_ID


# ─── Montaje ──────────────────────────────────────────────────

func _build_header() -> PanelContainer:
	var pill: PanelContainer = PanelContainer.new()
	pill.theme_type_variation = UITheme.V_PANEL
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = Vector2(SceneStage.Dock.MARGIN, SceneStage.Dock.MARGIN)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	pill.add_child(box)
	box.add_child(SceneStage.ui_label(tr("INTERROGATION_HEADER"), UITheme.V_HEADING))
	_header_sub = SceneStage.ui_label("", UITheme.V_CAPTION)
	box.add_child(_header_sub)
	return pill


func _build_caption() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = UITheme.V_SUBTITLE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	_caption = SceneStage.ui_label("", UITheme.V_STRONG, true)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_caption)
	return panel


## Zona libre de la sala = pantalla menos la cabecera y el panel lateral.
func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_header.reset_size()
	_dock.fit_width(size)
	_stage.set_safe_rect(_dock.free_rect(size, _header.get_rect().end.y + HEADER_GAP))
	_place_caption()


## Narración arriba y al centro de la zona libre (no tapa cabeceras ni panel).
func _place_caption() -> void:
	var safe: Rect2 = _stage.safe_rect()
	_caption.custom_minimum_size.x = minf(safe.size.x * 0.8, 760.0 * SceneStage.ui_scale())
	_caption_panel.reset_size()
	_caption_panel.position = Vector2(safe.get_center().x - _caption_panel.size.x * 0.5, safe.position.y)


func _pick_investigator() -> String:
	var id: String = str(_intro.get("interrogator", ""))
	if _intro.is_empty():
		id = Security.get_interrogator(case_id)
	return choose_investigator(id)


func _cast() -> void:
	var spots: Dictionary = SceneStage.interrogation_spots()
	_stage.add_actor(_investigator, SceneStage.cast_member(_investigator), {"pos": spots["investigator"],
			"facing": Vector2.DOWN, "seated": true, "chair_style": SceneStage.CHAIR_LEATHER})
	_stage.add_actor(PLAYER, SceneStage.cast_member(PLAYER), {"pos": spots["player"],
			"facing": Vector2.UP, "seated": true, "chair_style": SceneStage.CHAIR_STEEL})


func _dress() -> void:
	_stage.set_prop("nameplate", str(_stage.get_actor(_investigator).get("name", "")))
	_stage.set_prop("poster", tr("INTERROGATION_POSTER"))
	_stage.set_prop("clock", Vector2i(GameClock.get_hour(), GameClock.get_minute()))
	_stage.set_prop("slam_text", tr("INTERROGATION_SLAM"))
	_stage.set_prop("door", 0.0)
	var inv: Investigation = Security.get_investigation(case_id)
	var incident: String = tr("EVIDENCE_GENERIC")
	if inv != null:
		var key: String = InvestigationEngine.evidence_name_key(Database.get_investigation_params(), inv.incident_type)
		incident = tr(key) if not key.is_empty() else incident
	_header_sub.text = tr("INTERROGATION_HEADER_CASE") % [case_id.get_slice(CASE_ID_SEPARATOR, 1), incident]
	var rules: Dictionary = _session.get_rules()
	_meter.threshold = float(rules.get("success_below", 0.0))
	_meter.title = tr("INTERROGATION_METER_TITLE")
	_meter.line_text = tr("INTERROGATION_METER_LINE") % SceneStage.decimal(_meter.threshold)


func _show_no_case() -> void:
	_step = STEP_END
	_stage.set_prop("lamp", SceneStage.LAMP_NEUTRAL)
	_end_title = tr("INTERROGATION_NO_CASE")
	_stage.set_anim(_investigator, "check_watch", Vector2.DOWN, "sit")
	_meter.visible = false
	_stage.frame(SceneStage.FRAME_INTERROGATION_TABLE)
	_stage.snap_camera()
	_dock.open(_end_title)
	_dock.add_buttons([SceneStage.ui_button(tr("INTERROGATION_LEAVE"), UITheme.V_PRIMARY, leave)])


# ─── Tono de apertura (§12.5) ─────────────────────────────────

func _play_intro() -> void:
	_step = STEP_INTRO
	var text: String = tr(str(_intro.get("intro_key", "")))
	match _tone:
		Interrogation.TONE_APOLOGY:
			_intro_apology(text)
		Interrogation.TONE_DOOR_SLAM:
			_intro_door_slam(text)
		_:
			_stage.frame(SceneStage.FRAME_INTERROGATION)
			_stage.set_prop("lamp", SceneStage.LAMP_NEUTRAL)
			_stage.set_anim(_investigator, "chat")
			_stage.say(_investigator, text)
			_timeline.then(SceneStage.reading_time(text), _present_piece, true)
	_stage.snap_camera()
	_settle()


## Reputación > 85: el investigador se levanta, se disculpa y te ha servido un café (primer plano).
func _intro_apology(text: String) -> void:
	_stage.frame(SceneStage.FRAME_INTERROGATION_CLOSE)
	_stage.set_prop("lamp", SceneStage.LAMP_WARM)
	_stage.set_prop("coffee", true)
	_stage.set_seated(_investigator, false)
	var standing: Vector2 = SceneStage.interrogation_spots()["investigator_standing"]
	_stage.move_actor(_investigator, standing)
	_stage.set_anim(_investigator, "chat", Vector2(-0.7, 0.7))
	_stage.say(_investigator, text)
	var read: float = SceneStage.reading_time(text)
	_timeline.then(read, _stage.walk_to.bind(_investigator, _stage.seat_point(_investigator), _pause(),
			Vector2.DOWN, "idle"))
	_timeline.then(_pause(), _stage.set_seated.bind(_investigator, true))
	_timeline.then(0.0, _present_piece, true)


## Sospecha > 70: la puerta abierta se cierra de golpe (animación, sacudida y sonido).
func _intro_door_slam(text: String) -> void:
	_stage.frame(SceneStage.FRAME_INTERROGATION_DOOR)
	_stage.set_prop("lamp", SceneStage.LAMP_HARSH)
	_stage.set_prop("door", 1.0)
	_stage.set_anim(_investigator, "sit")
	_timeline.then(Database.get_balance_float(B_SLAM_WAIT), _slam_door)
	_timeline.then(_pause(), _narrate.bind(text), true)
	_timeline.then(SceneStage.reading_time(text), _present_piece, true)


func _slam_door() -> void:
	var t: Tween = _tween_prop("door", 1.0, 0.0, Database.get_balance_float(B_SLAM))
	if t != null:
		t.tween_callback(_on_door_shut)
	else:
		_on_door_shut()


func _on_door_shut() -> void:
	_door_slammed = true
	_stage.set_prop("door", 0.0)
	_stage.shake(Database.get_balance_float(B_SHAKE_PX), Database.get_balance_float(B_SHAKE_S))
	_slam_sound()
	_stage.set_anim(PLAYER, "startle", Vector2.UP, "sit")
	var t: Tween = _tween_prop("slam", SLAM_POP_FROM, 1.0, Database.get_balance_float(B_SLAM))
	if t != null:
		t.tween_interval(Database.get_balance_float(B_SHAKE_S))
		t.tween_method(func(v: float) -> void: _stage.set_prop("slam", v), 1.0, 0.0, _pause())


## El portazo suena con "door_slam" si SfxBank lo tiene; si no, golpe seco con el hilo musical
## cortado (su subtítulo es cierto) y el subtítulo propio de la puerta (§13.10).
func _slam_sound() -> void:
	_sfx_requests.append(SFX_DOOR)
	var door: Array[String] = [SFX_DOOR]
	if not SceneStage.play_sfx(self, door).is_empty():
		return
	var thud: Array[String] = [SFX_DOOR_FALLBACK]
	if not SceneStage.play_sfx(self, thud).is_empty():
		SceneStage.cut_music(self, Database.get_balance_float(B_SHAKE_S))
	SceneStage.post_subtitle(self, SUB_DOOR)


func _tween_prop(prop: String, from: float, to: float, seconds: float) -> Tween:
	if instant or seconds <= 0.0:
		_stage.set_prop(prop, to)
		return null
	var t: Tween = create_tween()
	t.tween_method(func(v: float) -> void: _stage.set_prop(prop, v), from, to, seconds)
	_tweens.append(t)
	return t


func _sfx(ids: Array[String]) -> void:
	if not ids.is_empty():
		_sfx_requests.append(ids[0])
	SceneStage.play_sfx(self, ids)


# ─── Piezas ───────────────────────────────────────────────────

func _present_piece() -> void:
	_narrate("")
	_piece = _session.current_piece()
	if _piece.is_empty() or _session.is_finished():
		_end()
		return
	_step = STEP_PIECE
	_stage.frame(SceneStage.FRAME_INTERROGATION_TABLE)
	var type_id: String = str(_piece.get("type", ""))
	var key: String = PRESENT_PREFIX + type_id.to_upper()
	var line: String = tr(key) if tr(key) != key else tr(PRESENT_PREFIX + "GENERIC")
	var card_spot: Vector2 = SceneStage.interrogation_spots()["card"]
	_stage.set_anim(_investigator, "point", card_spot - _stage.actor_feet(_investigator), "sit")
	_stage.say(_investigator, line)
	_stage.set_prop("paper", true)
	_stage.set_anim(PLAYER, "sit", Vector2.UP)
	_show_answers()
	_show_card(_piece)
	_meter.highlight = str(_piece.get("record_id", ""))
	_meter.queue_redraw()


func _show_card(piece: Dictionary) -> void:
	_finish_tweens()
	if _card != null:
		_card.queue_free()
	_card = EvidenceCard.new()
	var type_id: String = str(piece.get("type", ""))
	_card.type_id = type_id
	_card.type_name = _type_name(type_id)
	_card.exhibit = tr("INTERROGATION_EXHIBIT") % [_session.get_current_index() + 1, _session.get_piece_count()]
	_card.weight = float(piece.get("weight", 0.0))
	_card.certainty = float(piece.get("certainty", Investigation.FULL_CERTAINTY))
	_card.accent = type_color(type_id)
	_card.captions = [tr("INTERROGATION_CARD_WEIGHT"), tr("INTERROGATION_CARD_CERTAINTY"),
			tr("INTERROGATION_CARD_COUNTS")]
	_card_layer.add_child(_card)
	var k: float = SceneStage.ui_scale()
	_card.position = _stage.to_screen(SceneStage.interrogation_spots()["card"]) - CARD_SIZE * 0.5
	_card.scale = Vector2.ONE * CARD_START_SCALE * k
	_card.rotation = 0.0
	_animate_card(_card_target(), Vector2(k, k), CARD_TILT, 1.0)


## Posición (sin escalar, pivote en el centro) de la ficha junto a la mesa, dentro de la zona libre.
func _card_target() -> Vector2:
	var k: float = SceneStage.ui_scale()
	var shown: Vector2 = CARD_SIZE * k
	var safe: Rect2 = _stage.safe_rect()
	var top_left: Vector2 = _stage.to_screen(SceneStage.interrogation_spots()["card"]) - shown * 0.5
	top_left.x = clampf(top_left.x, safe.position.x, maxf(safe.end.x - shown.x, safe.position.x))
	top_left.y = clampf(top_left.y, safe.position.y, maxf(safe.end.y - shown.y, safe.position.y))
	return top_left - CARD_SIZE * 0.5 * (1.0 - k)


func _animate_card(pos: Vector2, card_scale: Vector2, rot: float, alpha: float) -> void:
	var seconds: float = Database.get_balance_float(B_CARD)
	_card_resting = false
	if instant or seconds <= 0.0:
		_card.position = pos
		_card.scale = card_scale
		_card.rotation = rot
		_card.modulate.a = alpha
		_card_resting = alpha > 0.0
		return
	var t: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "position", pos, seconds)
	t.tween_property(_card, "scale", card_scale, seconds)
	t.tween_property(_card, "rotation", rot, seconds)
	t.tween_property(_card, "modulate:a", alpha, seconds)
	if alpha > 0.0:
		t.chain().tween_callback(func() -> void: _card_resting = true)
	_tweens.append(t)


func _type_name(type_id: String) -> String:
	var key: String = InvestigationEngine.evidence_name_key(Database.get_investigation_params(), type_id)
	if key.is_empty():
		key = "EVIDENCE_" + type_id.to_upper()
	return tr(key) if tr(key) != key else tr("EVIDENCE_GENERIC")


static func type_color(type_id: String) -> Color:
	return UITheme.color(str(TYPE_COLORS.get(type_id, "accent")))


func _refresh_meter(first: bool) -> void:
	var inv: Investigation = Security.get_investigation(case_id)
	var pieces: Array[Dictionary] = []
	var sum: float = 0.0
	if inv != null:
		for piece: Dictionary in InvestigationEngine.pieces_against(inv, PLAYER):
			var value: float = float(piece.get("weight", 0.0)) * float(piece.get("certainty", 1.0))
			sum += value
			pieces.append({"id": str(piece.get("record_id", "")), "value": value,
					"color": type_color(str(piece.get("type", "")))})
	var total: float = get_case_weight()
	var extra: float = maxf(total - sum, 0.0)
	_meter.extra_text = tr("INTERROGATION_METER_EXTRA") % SceneStage.decimal(extra) if extra > 0.0 else ""
	var need: float = maxf(total, _meter.threshold) * METER_HEADROOM
	if first or need > _meter.span_target:
		_meter.span_target = need
	if first:
		_meter.rate = need / maxf(Database.get_balance_float(B_METER), 0.001)
	_meter.set_targets(pieces, extra)
	if first or instant:
		_meter.snap()


# ─── Respuestas ───────────────────────────────────────────────

func _show_answers() -> void:
	var box: VBoxContainer = _dock.open(tr("INTERROGATION_PROMPT"))
	_notice = SceneStage.ui_label("", UITheme.V_STRONG, true, UITheme.color("warn"))
	_notice.visible = false
	box.add_child(_notice)
	var usable: Array[String] = _session.available_answers()
	for id: String in Interrogation.ANSWERS:
		box.add_child(_answer_row(id, usable.has(id)))


func _answer_row(answer_id: String, usable: bool) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var action: Callable = answer.bind(answer_id)
	if answer_id == Interrogation.ANSWER_ACCUSE:
		action = open_accuse_picker
	var variation: String = UITheme.V_PRIMARY if usable else ""
	var b: Button = SceneStage.ui_button(tr(_session.get_answer_key(answer_id)), variation, action)
	b.disabled = not usable
	b.name = "Answer_" + answer_id
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(b)
	box.add_child(SceneStage.ui_label(_hint(answer_id, usable), UITheme.V_SMALL, true,
			UITheme.color("muted" if usable else "warn")))
	return box


func _hint(answer_id: String, usable: bool) -> String:
	var rules: Dictionary = _session.get_rules()
	match answer_id:
		Interrogation.ANSWER_DENY:
			return tr("INTERROGATION_HINT_DENY") % [roundi(float(rules["deny_reputation_above"])),
					SceneStage.decimal(float(rules["deny_weight_below"]))]
		Interrogation.ANSWER_EXPLAIN:
			return tr("INTERROGATION_HINT_EXPLAIN") if usable else tr("INTERROGATION_REQ_ALIBI")
		Interrogation.ANSWER_ACCUSE:
			return tr("INTERROGATION_HINT_ACCUSE")
		Interrogation.ANSWER_SILENCE:
			return tr("INTERROGATION_HINT_SILENCE") % int(rules["silence_suspicion"])
	return tr("INTERROGATION_HINT_LAWYER") % _freeze_days() if usable else tr("INTERROGATION_REQ_LAWYER")


func _freeze_days() -> int:
	return int(_session.get_rules().get("freeze_days", 0))


func _requirement_missing(result: Dictionary) -> void:
	_caption_text = _outcome_text(str(result.get("outcome", "")))
	if _notice != null and is_instance_valid(_notice):
		_notice.text = _caption_text
		_notice.visible = true
	_sfx(SFX_BAD)
	if _card == null or instant:
		return
	_card_resting = false
	var t: Tween = create_tween()
	for dx: float in [12.0, -12.0, 8.0, -8.0, 0.0]:
		t.tween_property(_card, "position:x", _card_target().x + dx, CARD_SHAKE_STEP)
	t.tween_callback(func() -> void: _card_resting = true)
	_tweens.append(t)


func _player_gesture_facing(answer_id: String) -> Vector2:
	return Vector2(0.7, -0.7) if answer_id == Interrogation.ANSWER_ACCUSE else Vector2.UP


func _add_candidate(out: Array[String], id: String, limit: int) -> void:
	if out.size() >= limit or out.has(id) or id == PLAYER or id == _investigator:
		return
	if not InvestigationEngine.is_identified(id):
		return
	if NPCDirector.get_npc(id) != null and not NPCDirector.is_active(id):
		return
	out.append(id)


func _candidate_tile(npc_id: String) -> Control:
	var member: Dictionary = SceneStage.cast_member(npc_id)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var photo: SceneStage.PortraitBox = SceneStage.PortraitBox.new(member["appearance"],
			Vector2(120, 120) * SceneStage.ui_scale())
	photo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(photo)
	var b: Button = SceneStage.ui_button(str(member["name"]), "", answer.bind(Interrogation.ANSWER_ACCUSE, npc_id))
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(b)
	return box


## Mientras el jugador habla, el panel muestra su respuesta y al investigador tomando nota.
func _show_waiting(answer_id: String) -> void:
	var box: VBoxContainer = _dock.open(tr(_session.get_answer_key(answer_id)))
	var who: String = str(_stage.get_actor(_investigator).get("name", ""))
	box.add_child(SceneStage.ui_label(tr("INTERROGATION_WAITING") % who, UITheme.V_SMALL, true))


# ─── Reacción y final ─────────────────────────────────────────

func _outcome_text(outcome: String) -> String:
	if outcome == Interrogation.OUTCOME_CASE_FROZEN:
		return tr("INTERROGATION_CAPTION_CASE_FROZEN") % _freeze_days()
	return tr(Interrogation.outcome_key(outcome))


func _react(answer_id: String, accused: String, result: Dictionary, piece: Dictionary) -> void:
	var outcome: String = str(result.get("outcome", ""))
	_caption_text = _outcome_text(outcome)
	_stage.say(PLAYER, "")
	_stage.set_anim(PLAYER, "sit", Vector2.UP)
	_stage.set_anim(_investigator, _investigator_anim(outcome), Vector2.DOWN, "sit")
	_stage.say(_investigator, _react_line(outcome, accused))
	_stamp_card(outcome, accused, piece)
	var delta: int = int(result.get("suspicion_delta", 0))
	if delta > 0:
		_stage.badge(PLAYER, tr("INTERROGATION_SUSPICION_BADGE") % delta, UITheme.color("sus"))
	var good: bool = outcome in [Interrogation.OUTCOME_PIECE_REMOVED, Interrogation.OUTCOME_ALIBI_ACCEPTED]
	_sfx(SFX_GOOD if good else SFX_BAD)
	_refresh_meter(false)
	_show_reaction(good, delta)
	if answer_id == Interrogation.ANSWER_LAWYER:
		_stage.set_prop("lamp", SceneStage.LAMP_NEUTRAL)


func _react_line(outcome: String, accused: String) -> String:
	var react: String = tr(REACT_PREFIX + outcome.to_upper())
	match outcome:
		Interrogation.OUTCOME_PIECE_TRANSFERRED:
			return react % IdeaPool.get_npc_display_name(accused)
		Interrogation.OUTCOME_CASE_FROZEN:
			return react % _freeze_days()
	return react


## Panel de la reacción: el resultado, el cambio de peso y de sospecha, y «Siguiente».
func _show_reaction(good: bool, suspicion: int) -> void:
	var box: VBoxContainer = _dock.open("")
	box.add_child(SceneStage.ui_label(_caption_text, UITheme.V_HEADING, true,
			UITheme.color("gain") if good else UITheme.color("loss")))
	box.add_child(SceneStage.ui_label(tr("INTERROGATION_WEIGHT_CHANGE") % [SceneStage.decimal(_weight_before),
			SceneStage.decimal(get_case_weight())], UITheme.V_STRONG, true))
	if suspicion > 0:
		box.add_child(SceneStage.ui_label(tr("INTERROGATION_SUSPICION_BADGE") % suspicion, UITheme.V_SMALL, true,
				UITheme.color("sus")))
	var key: String = "INTERROGATION_NEXT" if not _session.is_finished() else "INTERROGATION_TO_VERDICT"
	_dock.add_buttons([SceneStage.ui_button(tr(key), UITheme.V_PRIMARY, skip_ahead)])


func _investigator_anim(outcome: String) -> String:
	match outcome:
		Interrogation.OUTCOME_CASE_FROZEN:
			return "check_watch"
		Interrogation.OUTCOME_ALIBI_FALSE, Interrogation.OUTCOME_DENIAL_REJECTED:
			return "chat"
		Interrogation.OUTCOME_PIECE_TRANSFERRED:
			return "suspicion"
	return "sit"


func _stamp_card(outcome: String, accused: String, piece: Dictionary) -> void:
	if _card == null:
		return
	var stamp: Array = STAMPS.get(outcome, STAMP_DEFAULT)
	var text: String = tr(str(stamp[0]))
	match outcome:
		Interrogation.OUTCOME_ALIBI_FALSE:
			var factor: float = float(_session.get_rules().get("false_alibi_multiplier", 1.0))
			_card.weight = float(piece.get("weight", 0.0)) * factor
			text = text % SceneStage.decimal(factor)
		Interrogation.OUTCOME_PIECE_TRANSFERRED:
			text = text % IdeaPool.get_npc_display_name(accused)
	_card.stamp = text
	_card.stamp_color = UITheme.color(str(stamp[1])).darkened(STAMP_INK_DARKEN)
	_card.queue_redraw()


func _next() -> void:
	_stage.say(_investigator, "")
	_stage.badge(PLAYER, "", Color.WHITE)
	_stage.set_prop("paper", false)
	if _card != null:
		var away: Vector2 = Vector2(-CARD_SIZE.x * 1.2, _card.position.y + 60.0)
		_animate_card(away, Vector2(0.8, 0.8), -0.3, 0.0)
	if _session.is_finished():
		_timeline.then(_pause(), _end, true)
	else:
		_timeline.then(_pause(), _present_piece, true)


func _end() -> void:
	_step = STEP_END
	_piece = {}
	_narrate("")
	_meter.highlight = ""
	_end_result = _session.finish()
	var frozen: bool = str(_last_result.get("outcome", "")) == Interrogation.OUTCOME_CASE_FROZEN
	var success: bool = bool(_end_result.get("success", false))
	_end_title = tr("INTERROGATION_FROZEN_TITLE") if frozen \
			else tr("INTERROGATION_SUCCESS" if success else "INTERROGATION_FAILURE")
	_end_lines = _compose_end_lines(frozen)
	_refresh_meter(false)
	_stage.set_anim(_investigator, "sit", Vector2.DOWN)
	_stage.set_anim(PLAYER, "sit" if success or frozen else "caught", Vector2.UP)
	if success and not frozen:
		_stage.set_prop("lamp", SceneStage.LAMP_WARM)
	var box: VBoxContainer = _dock.open(_end_title)
	for line: String in _end_lines:
		box.add_child(SceneStage.ui_label(line, UITheme.V_STRONG, true,
				UITheme.color("gain") if success or frozen else UITheme.color("loss")))
	_dock.add_buttons([SceneStage.ui_button(tr("INTERROGATION_LEAVE"), UITheme.V_PRIMARY, leave)])


func _compose_end_lines(frozen: bool) -> Array[String]:
	var out: Array[String] = []
	var threshold: String = SceneStage.decimal(_meter.threshold)
	var total: float = float(_end_result.get("total_weight", get_case_weight()))
	out.append(tr("INTERROGATION_END_WEIGHT") % [SceneStage.decimal(total), threshold])
	var verdict: String = str(_end_result.get("verdict", ""))
	if not verdict.is_empty():
		out.append(tr("INTERROGATION_END_VERDICT") % tr(_verdict_key(verdict)))
	if _session.get_suspicion_delta() > 0:
		out.append(tr("INTERROGATION_END_SUSPICION") % _session.get_suspicion_delta())
	if frozen:
		out.append(tr("INTERROGATION_END_FROZEN_HINT") % _freeze_days())
	return out


static func _verdict_key(verdict: String) -> String:
	var params: Dictionary = Database.get_investigation_params()
	var data_id: String = str(InvestigationEngine.VERDICT_DATA_IDS.get(verdict, verdict))
	var entry: Dictionary = InvestigationEngine.find_by_id(params.get("verdicts", []), data_id)
	return str(entry.get("name_key", "VERDICT_" + verdict.to_upper()))


# ─── Ritmo ────────────────────────────────────────────────────

func _narrate(text: String) -> void:
	_caption_text = text
	_caption.text = text
	_caption_panel.visible = not text.is_empty()
	_place_caption()


func _is_animating() -> bool:
	if _timeline.is_busy() or _stage.is_moving():
		return true
	for t: Tween in _tweens:
		if t != null and t.is_valid() and t.is_running():
			return true
	return false


func _finish_tweens() -> void:
	for _pass: int in MAX_FORWARD_PASSES:
		if _tweens.is_empty():
			break
		var running: Array[Tween] = _tweens.duplicate()
		_tweens.clear()
		for t: Tween in running:
			if t != null and t.is_valid() and t.is_running():
				t.custom_step(FORWARD_STEP)


func _settle() -> void:
	if instant:
		fast_forward()


func _pause() -> float:
	return Database.get_balance_float(B_PAUSE)


# ─── Iconos de las piezas (vector) ────────────────────────────

static func draw_evidence_icon(ci: CanvasItem, type_id: String, r: Rect2, accent: Color) -> void:
	var ink: Color = SceneStage.ink()
	var c: Vector2 = r.get_center()
	ci.draw_circle(c, r.size.x * 0.5, accent.lightened(0.55))
	ci.draw_arc(c, r.size.x * 0.5, 0.0, TAU, 36, ink, 3.0, true)
	match str(TYPE_ICONS.get(type_id, "")):
		"eye", "eye_partial":
			_icon_eye(ci, c, r.size.x * 0.34, ink, str(TYPE_ICONS[type_id]) == "eye_partial")
		"camera":
			_icon_camera(ci, c, ink)
		"card":
			_icon_card(ci, c, ink, accent)
		"rumour":
			_icon_rumour(ci, c, ink)
		"ledger":
			_icon_ledger(ci, c, ink)
		_:
			_icon_document(ci, c, ink, accent)


static func _icon_eye(ci: CanvasItem, c: Vector2, w: float, ink: Color, partial: bool) -> void:
	var pts: PackedVector2Array = []
	for i: int in 24:
		var t: float = TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(t) * w, sin(t) * w * 0.55 * absf(sin(t)) + sin(t) * w * 0.1))
	ci.draw_colored_polygon(pts, SceneStage.C_SHEET)
	pts.append(pts[0])
	ci.draw_polyline(pts, ink, 3.0, true)
	ci.draw_circle(c, w * 0.32, ink)
	ci.draw_circle(c + Vector2(-3, -3), w * 0.1, SceneStage.C_SHEET)
	if partial:
		ci.draw_rect(Rect2(c.x - w, c.y - w * 0.7, w * 2.0, w * 0.55), Color(ink, 0.55))


static func _icon_camera(ci: CanvasItem, c: Vector2, ink: Color) -> void:
	var body: Rect2 = Rect2(c + Vector2(-20, -12), Vector2(32, 24))
	ci.draw_rect(body, SceneStage.C_STEEL_DARK)
	ci.draw_rect(body, ink, false, 3.0)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(12, -6), c + Vector2(24, -12),
			c + Vector2(24, 12), c + Vector2(12, 6)]), SceneStage.C_STEEL_DARK)
	ci.draw_circle(c + Vector2(-6, 0), 6.0, SceneStage.C_SCREEN_GLOW)
	ci.draw_circle(c + Vector2(-16, -16), 4.0, SceneStage.C_RED_LED)


static func _icon_card(ci: CanvasItem, c: Vector2, ink: Color, accent: Color) -> void:
	var card: Rect2 = Rect2(c + Vector2(-22, -15), Vector2(44, 30))
	ci.draw_rect(card, SceneStage.C_SHEET)
	ci.draw_rect(Rect2(card.position, Vector2(card.size.x, 8)), accent)
	ci.draw_rect(card, ink, false, 3.0)
	ci.draw_rect(Rect2(card.position + Vector2(5, 12), Vector2(12, 13)), SceneStage.C_CARDBOARD.lightened(0.2))
	for i: int in 2:
		ci.draw_line(card.position + Vector2(21, 15 + i * 7), card.position + Vector2(39, 15 + i * 7), ink, 2.0)


static func _icon_rumour(ci: CanvasItem, c: Vector2, ink: Color) -> void:
	var bubble: PackedVector2Array = SceneStage.rounded_rect(Rect2(c + Vector2(-22, -16), Vector2(44, 28)), 10.0)
	ci.draw_colored_polygon(bubble, SceneStage.C_SHEET)
	bubble.append(bubble[0])
	ci.draw_polyline(bubble, ink, 3.0, true)
	for i: int in 3:
		ci.draw_circle(c + Vector2(-11 + i * 11, -2), 3.0, ink)


static func _icon_ledger(ci: CanvasItem, c: Vector2, ink: Color) -> void:
	var page: Rect2 = Rect2(c + Vector2(-18, -22), Vector2(36, 44))
	ci.draw_rect(page, SceneStage.C_SHEET)
	ci.draw_rect(page, ink, false, 3.0)
	for i: int in 4:
		ci.draw_line(page.position + Vector2(6, 10 + i * 9), page.position + Vector2(30, 10 + i * 9), ink, 2.0)
	ci.draw_circle(c + Vector2(16, 16), 9.0, SceneStage.C_GOLD)
	ci.draw_arc(c + Vector2(16, 16), 9.0, 0.0, TAU, 18, ink, 2.0, true)


static func _icon_document(ci: CanvasItem, c: Vector2, ink: Color, accent: Color) -> void:
	var page: Rect2 = Rect2(c + Vector2(-17, -22), Vector2(34, 44))
	ci.draw_rect(page, SceneStage.C_SHEET)
	ci.draw_rect(page, ink, false, 3.0)
	for i: int in 3:
		ci.draw_line(page.position + Vector2(6, 10 + i * 8), page.position + Vector2(28, 10 + i * 8), ink, 2.0)
	ci.draw_circle(c + Vector2(8, 12), 8.0, accent)
	ci.draw_arc(c + Vector2(8, 12), 8.0, 0.0, TAU, 16, ink, 2.0, true)
