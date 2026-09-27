# interrogation_scene.gd — Interrogatorio en la sala de P15 (§12.5, PASO 29): el investigador presenta las piezas de una en una, cinco respuestas, el peso del caso contra la línea de 7,0 y el detalle de tono (disculpa o portazo).
# PROPIETARIO DE: la sesión Interrogation en curso (la crea la escena), el paso de la escena, la pieza mostrada y el resultado final mostrado.
# ESCUCHA: nada.
class_name InterrogationScene
extends Control

## API: InterrogationScene.open(host, case_id, context := {}) → la escena (modal que pausa el reloj
## si host es UIRoot; si no, hija de host). context es el de Interrogation.new (reputation,
## suspicion, alibi, has_legal_contact, verification_roll): vacío en el juego, forzado en QA/tests.
## Pasos: STEP_INTRO (tono de §12.5: reputación > 85 → disculpa con café y luz cálida; sospecha > 70
## → la puerta se cierra de golpe: animación, sacudida y AudioDirector.play_sfx) → STEP_PIECE (la
## pieza sobre la mesa espera respuesta) ⇄ STEP_REACT → STEP_END (Interrogation.finish(): éxito si
## el peso < 7,0; veredicto o caso congelado) → leave() → closed().
## Cada respuesta llama a Interrogation.answer(), que aplica los efectos (Security, NPCDirector,
## BeliefNet) y emite interrogation_answered; la escena solo lo representa y emite answered().
## DECISIONES: no se puede salir a mitad (Esc solo salta animaciones o cierra el selector); si la
## escena se retira sin terminar, Security caduca el interrogatorio abandonado. «Acusar a otro»
## abre un selector: sospechosos del caso, quien ronda la sala del incidente y colegas que conocen
## al jugador (máx. escenas.max_acusables); sin población, nominados del catálogo.

signal closed()
signal answered(answer_id: String, result: Dictionary)

const STEP_INTRO := "intro"
const STEP_PIECE := "piece"
const STEP_REACT := "react"
const STEP_END := "end"
const PLAYER := SceneStage.PLAYER_ID
const INVESTIGATOR_FALLBACK := "security_staff"
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
## Color de cada tipo de pieza (paleta de la interfaz): tarjeta y segmento del medidor.
const TYPE_COLORS: Dictionary = {
	"direct_witness": "warn", "partial_witness": "det_partial", "camera_footage": "sus",
	"card_log": "rep", "compromising_item": "danger", "accounting_trail": "gain",
	"unsourced_rumour": "muted", "body_found": "det_flagrant", "forged_document": "hazard",
}
const SFX_SLAM: Array[String] = ["door_slam", "caught_thud"]
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

var instant: bool = false
var case_id: String = ""

var _context: Dictionary = {}
var _session: Interrogation
var _intro: Dictionary = {}
var _tone: String = Interrogation.TONE_NEUTRAL
var _investigator: String = ""
var _step: String = STEP_INTRO
var _stage: SceneStage
var _timeline: SceneStage.Timeline = SceneStage.Timeline.new()
var _tweens: Array[Tween] = []
var _card_layer: Control
var _card: EvidenceCard
var _meter: CaseMeter
var _caption_panel: PanelContainer
var _caption: Label
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _picker: PanelContainer
var _header_sub: Label
var _piece: Dictionary = {}
var _last_result: Dictionary = {}
var _end_result: Dictionary = {}
var _end_title: String = ""
var _end_lines: Array[String] = []
var _door_slammed: bool = false
var _done: bool = false


## Tarjeta de la pieza: tipo, peso, certeza y lo que cuenta (peso × certeza), con sello.
class EvidenceCard extends Control:
	var type_id: String = ""
	var type_name: String = ""
	var exhibit: String = ""
	var weight: float = 0.0
	var certainty: float = 1.0
	var accent: Color = Color.GRAY
	var captions: Array[String] = ["", "", ""]
	var stamp: String = ""
	var stamp_color: Color = Color("#c0392b")

	func _init() -> void:
		custom_minimum_size = InterrogationScene.CARD_SIZE
		size = InterrogationScene.CARD_SIZE
		pivot_offset = InterrogationScene.CARD_SIZE * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink: Color = SceneStage.C_INK
		var body: Rect2 = Rect2(Vector2.ZERO, size)
		draw_colored_polygon(SceneStage.rounded_rect(Rect2(Vector2(7, 9), size), 12.0), Color(0, 0, 0, 0.35))
		draw_colored_polygon(SceneStage.rounded_rect(body, 12.0), SceneStage.C_PAPER)
		draw_rect(Rect2(3, 3, size.x - 6, 46), accent)
		var loop: PackedVector2Array = SceneStage.rounded_rect(body, 12.0)
		loop.append(loop[0])
		draw_polyline(loop, ink, 3.0, true)
		var bold: Font = UITheme.font(UITheme.FONT_BOLD)
		var semi: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		draw_string(bold, Vector2(18, 34), exhibit, HORIZONTAL_ALIGNMENT_LEFT, size.x - 90, 18,
				SceneStage.C_PAPER if accent.get_luminance() < 0.55 else ink)
		_draw_clip(Vector2(size.x - 52, -12))
		InterrogationScene.draw_evidence_icon(self, type_id, Rect2(18, 64, 72, 72), accent)
		draw_multiline_string(bold, Vector2(106, 90), type_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 124, 25, 2, ink)
		draw_line(Vector2(18, 156), Vector2(size.x - 18, 156), Color(ink, 0.25), 2.0)
		var values: Array[String] = [SceneStage.decimal(weight),
				"%d%%" % roundi(certainty * InterrogationScene.PERCENT),
				SceneStage.decimal(weight * certainty)]
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
		draw_polyline(pts, Color("#8a9097"), 4.0, true)

	func _draw_stamp(font: Font) -> void:
		if stamp.is_empty():
			return
		var fs: int = 38
		var w: float = font.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(size * 0.5 + Vector2(0, -6), -0.18, Vector2.ONE)
		var box: Rect2 = Rect2(-w * 0.5 - 18, -34, w + 36, 58)
		draw_rect(box, Color(stamp_color, 0.12))
		draw_rect(box, stamp_color, false, 5.0)
		draw_string(font, Vector2(-w * 0.5, 12), stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, stamp_color)
		draw_set_transform(Vector2.ZERO)


## Medidor del peso del caso contra el jugador: una barra por pieza (peso × certeza), las
## circunstancias (acceso, móvil, último en salir) rayadas y la línea de éxito (7,0).
class CaseMeter extends Control:
	var segments: Array[Dictionary] = []
	var bonus: float = 0.0
	var bonus_shown: float = 0.0
	var threshold: float = 7.0
	var span: float = 14.0
	var rate: float = 10.0
	var highlight: String = ""
	var title: String = ""
	var line_text: String = ""
	var extra_text: String = ""
	var k: float = 1.0

	func _init() -> void:
		k = SceneStage.ui_scale()
		custom_minimum_size = Vector2(700, 108) * k
		mouse_filter = Control.MOUSE_FILTER_IGNORE

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
		var moved: bool = not is_equal_approx(bonus_shown, bonus)
		bonus_shown = move_toward(bonus_shown, bonus, step)
		for seg: Dictionary in segments:
			moved = moved or not is_equal_approx(float(seg["shown"]), float(seg["target"]))
			seg["shown"] = move_toward(float(seg["shown"]), float(seg["target"]), step)
		if moved:
			queue_redraw()

	func _draw() -> void:
		var bold: Font = UITheme.font(UITheme.FONT_BOLD)
		var semi: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		var bar: Rect2 = Rect2(0, 42 * k, size.x, 30 * k)
		var per: float = size.x / maxf(span, 0.001)
		var line_x: float = threshold * per
		draw_rect(Rect2(bar.position, Vector2(line_x, bar.size.y)), UITheme.color("gain").darkened(0.62))
		draw_rect(Rect2(bar.position.x + line_x, bar.position.y, bar.size.x - line_x, bar.size.y),
				UITheme.color("sus_track"))
		var x: float = _draw_segments(bar, per)
		_draw_bonus(bar, per, x)
		draw_rect(bar, UITheme.color("line"), false, 2.0)
		draw_line(Vector2(line_x, bar.position.y - 8), Vector2(line_x, bar.end.y + 8), UITheme.color("paper"), 4.0)
		var fs: int = roundi(18 * k)
		draw_string(semi, Vector2(0, 28 * k), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.color("muted"))
		var total: float = total_shown()
		var total_text: String = SceneStage.decimal(total)
		var big: int = roundi(36 * k)
		var tw: float = bold.get_string_size(total_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		draw_string(bold, Vector2(size.x - tw, 32 * k), total_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big,
				UITheme.color("gain") if total < threshold else UITheme.color("loss"))
		var lw: float = semi.get_string_size(line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(semi, Vector2(clampf(line_x - lw * 0.5, 0, size.x - lw), bar.end.y + 28 * k), line_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.color("paper"))

	func _draw_segments(bar: Rect2, per: float) -> float:
		var x: float = bar.position.x
		for seg: Dictionary in segments:
			var w: float = float(seg["shown"]) * per
			if w <= 0.5:
				continue
			var r: Rect2 = Rect2(x, bar.position.y + 3, minf(w, bar.end.x - x), bar.size.y - 6)
			var col: Color = seg["color"]
			draw_rect(r, col if str(seg["id"]) == highlight else col.darkened(0.3))
			draw_rect(r, UITheme.color("ink"), false, 2.0)
			if str(seg["id"]) == highlight:
				draw_rect(r.grow(2.0), UITheme.color("focus"), false, 3.0)
			x += w
		return x

	func _draw_bonus(bar: Rect2, per: float, x: float) -> void:
		var w: float = bonus_shown * per
		if w <= 0.5:
			return
		var r: Rect2 = Rect2(x, bar.position.y + 3, minf(w, bar.end.x - x), bar.size.y - 6)
		draw_rect(r, UITheme.color("faint"))
		for i: int in int(r.size.x / 9.0):
			var hx: float = r.position.x + 4.0 + i * 9.0
			draw_line(Vector2(hx, r.end.y), Vector2(hx + 7, r.position.y), Color(1, 1, 1, 0.3), 2.0)
		var semi: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		draw_string(semi, Vector2(0, bar.end.y + 28 * k), extra_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				roundi(16 * k), UITheme.color("muted"))


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
	_build_layout()


func _ready() -> void:
	SceneStage.ensure_theme(self)
	resized.connect(_fit_panel)
	_stage.configure(SceneStage.SET_INTERROGATION)
	_session = Interrogation.new(case_id, _context)
	_intro = _session.start()
	_investigator = _pick_investigator()
	_cast()
	_dress()
	if _intro.is_empty():
		_show_no_case()
		return
	_tone = str(_intro.get("tone", Interrogation.TONE_NEUTRAL))
	_refresh_meter(true)
	_play_intro()


func _process(delta: float) -> void:
	_timeline.tick(delta)


# ─── API ──────────────────────────────────────────────────────

func get_step() -> String:
	return _step


func get_stage() -> SceneStage:
	return _stage


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


## La pieza que está sobre la mesa ({} si ninguna).
func get_shown_piece() -> Dictionary:
	return _piece.duplicate()


func get_card_stamp() -> String:
	return _card.stamp if _card != null else ""


func get_caption() -> String:
	return _caption.text if _caption_panel.visible else ""


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


func get_visible_texts() -> Array[String]:
	var out: Array[String] = []
	SceneStage.collect_texts(self, out)
	return out


func available_answers() -> Array[String]:
	return _session.available_answers() if _session != null else [] as Array[String]


func is_finished() -> bool:
	return _step == STEP_END


## Responde a la pieza sobre la mesa con Interrogation.answer(). `accused` solo para acusar.
func answer(answer_id: String, accused: String = "") -> Dictionary:
	if _step != STEP_PIECE:
		return {}
	var piece: Dictionary = _piece.duplicate()
	var result: Dictionary = _session.answer(answer_id, accused)
	_last_result = result
	answered.emit(answer_id, result.duplicate())
	if not bool(result.get("consumes_turn", true)):
		_requirement_missing(result)
		return result
	_step = STEP_REACT
	_close_picker()
	_clear_panel()
	var line: String = tr(str(SAY_KEYS.get(answer_id, "")))
	if answer_id == Interrogation.ANSWER_ACCUSE:
		line = line % IdeaPool.get_npc_display_name(accused)
	_stage.set_anim(PLAYER, str(SAY_ANIMS.get(answer_id, "sit")), _player_gesture_facing(answer_id))
	_stage.say(PLAYER, line)
	_timeline.then(SceneStage.reading_time(line), _react.bind(answer_id, accused, result, piece))
	_timeline.then(SceneStage.reading_time(tr(Interrogation.outcome_key(str(result["outcome"])))), _next)
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


func open_accuse_picker() -> void:
	if _step != STEP_PIECE:
		return
	_close_picker()
	_picker = _build_picker(accuse_candidates())
	add_child(_picker)
	UITheme.center_fitted(_picker)


func fast_forward() -> void:
	_timeline.flush()
	_stage.finish_moves()
	for t: Tween in _tweens:
		if t != null and t.is_valid() and t.is_running():
			t.custom_step(1000.0)
	_tweens.clear()
	if _meter != null:
		_meter.snap()


## Esc: salta la animación, cierra el selector o, al final, sale. A mitad no se puede salir.
func request_close() -> void:
	if _timeline.is_busy() or _stage.is_moving():
		fast_forward()
	elif _picker != null:
		_close_picker()
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


# ─── Montaje ──────────────────────────────────────────────────

func _build_layout() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	column.add_child(_build_top_row())
	_caption_panel = PanelContainer.new()
	_caption_panel.theme_type_variation = UITheme.V_SUBTITLE
	_caption_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_caption_panel.visible = false
	_caption = SceneStage.ui_label("", UITheme.V_STRONG, true)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.custom_minimum_size.x = 760
	_caption_panel.add_child(_caption)
	column.add_child(_caption_panel)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = UITheme.V_MODAL
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.visible = false
	column.add_child(_panel)
	_panel_box = VBoxContainer.new()
	_panel.add_child(_panel_box)


func _build_top_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill: PanelContainer = PanelContainer.new()
	pill.theme_type_variation = UITheme.V_PANEL
	pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	pill.add_child(box)
	box.add_child(SceneStage.ui_label(tr("INTERROGATION_HEADER"), UITheme.V_HEADING))
	_header_sub = SceneStage.ui_label("", UITheme.V_CAPTION)
	box.add_child(_header_sub)
	row.add_child(pill)
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var meter_panel: PanelContainer = PanelContainer.new()
	meter_panel.theme_type_variation = UITheme.V_PANEL
	_meter = CaseMeter.new()
	meter_panel.add_child(_meter)
	row.add_child(meter_panel)
	return row


func _fit_panel() -> void:
	_panel.custom_minimum_size.x = minf(1440.0, maxf(size.x - 80.0, 600.0))


func _pick_investigator() -> String:
	var id: String = str(_intro.get("interrogator", ""))
	if id.is_empty():
		id = Security.get_interrogator(case_id)
	if id.is_empty():
		id = str(InvestigationEngine.dig(Database.get_investigation_params(),
				"interrogation.default_interrogator", ""))
	return id if not id.is_empty() else INVESTIGATOR_FALLBACK


func _cast() -> void:
	var spots: Dictionary = SceneStage.interrogation_spots()
	var member: Dictionary = SceneStage.cast_member(_investigator)
	if _investigator == INVESTIGATOR_FALLBACK:
		(member["appearance"] as Dictionary)["uniform"] = "security"
	_stage.add_actor(_investigator, member, {"pos": spots["investigator"], "facing": Vector2.DOWN,
			"seated": true, "chair_style": SceneStage.CHAIR_LEATHER})
	_stage.add_actor(PLAYER, SceneStage.cast_member(PLAYER), {"pos": spots["player"],
			"facing": Vector2.UP, "seated": true, "chair_style": SceneStage.CHAIR_STEEL})


func _dress() -> void:
	_stage.set_prop("nameplate", str(_stage.get_actor(_investigator).get("name", "")))
	_stage.set_prop("poster", tr("INTERROGATION_POSTER"))
	_stage.set_prop("clock", Vector2i(GameClock.get_hour(), GameClock.get_minute()))
	_stage.set_prop("slam_text", tr("INTERROGATION_SLAM"))
	_stage.set_prop("door", 0.0)
	var inv: Investigation = Security.get_investigation(case_id)
	var incident: String = ""
	if inv != null:
		incident = tr(InvestigationEngine.evidence_name_key(Database.get_investigation_params(), inv.incident_type))
	_header_sub.text = tr("INTERROGATION_HEADER_CASE") % [case_id, incident]
	var rules: Dictionary = _session.get_rules()
	_meter.threshold = float(rules.get("success_below", 0.0))
	_meter.title = tr("INTERROGATION_METER_TITLE")
	_meter.line_text = tr("INTERROGATION_METER_LINE") % SceneStage.decimal(_meter.threshold)


func _show_no_case() -> void:
	_step = STEP_END
	_stage.set_prop("lamp", SceneStage.LAMP_NEUTRAL)
	_end_title = tr("INTERROGATION_NO_CASE")
	_stage.set_anim(_investigator, "check_watch", Vector2.DOWN, "sit")
	_open_panel(_end_title)
	_button_row([SceneStage.ui_button(tr("INTERROGATION_LEAVE"), UITheme.V_PRIMARY, leave)])


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
			_stage.set_prop("lamp", SceneStage.LAMP_NEUTRAL)
			_stage.set_anim(_investigator, "chat")
			_stage.say(_investigator, text)
			_timeline.then(SceneStage.reading_time(text), _present_piece)
	_settle()


## Reputación > 85: el investigador se levanta, se disculpa y te ha servido un café.
func _intro_apology(text: String) -> void:
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
	_timeline.then(0.0, _present_piece)


## Sospecha > 70: la puerta abierta se cierra de golpe (animación, sacudida y sonido).
func _intro_door_slam(text: String) -> void:
	_stage.set_prop("lamp", SceneStage.LAMP_HARSH)
	_stage.set_prop("door", 1.0)
	_stage.set_anim(_investigator, "sit")
	_timeline.then(Database.get_balance_float(B_SLAM_WAIT), _slam_door)
	_timeline.then(_pause(), _set_caption.bind(text))
	_timeline.then(SceneStage.reading_time(text), _present_piece)


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
	SceneStage.play_sfx(self, SFX_SLAM)
	_stage.set_anim(PLAYER, "startle", Vector2.UP, "sit")
	var t: Tween = _tween_prop("slam", 0.2, 1.0, Database.get_balance_float(B_SLAM))
	if t != null:
		t.tween_interval(Database.get_balance_float(B_SHAKE_S))
		t.tween_method(func(v: float) -> void: _stage.set_prop("slam", v), 1.0, 0.0, _pause())


func _tween_prop(prop: String, from: float, to: float, seconds: float) -> Tween:
	if instant or seconds <= 0.0:
		_stage.set_prop(prop, to)
		return null
	var t: Tween = create_tween()
	t.tween_method(func(v: float) -> void: _stage.set_prop(prop, v), from, to, seconds)
	_tweens.append(t)
	return t


# ─── Piezas ───────────────────────────────────────────────────

func _present_piece() -> void:
	_set_caption("")
	_piece = _session.current_piece()
	if _piece.is_empty() or _session.is_finished():
		_end()
		return
	_step = STEP_PIECE
	var type_id: String = str(_piece.get("type", ""))
	var key: String = PRESENT_PREFIX + type_id.to_upper()
	var line: String = tr(key) if tr(key) != key else tr(PRESENT_PREFIX + "GENERIC")
	var card_spot: Vector2 = SceneStage.interrogation_spots()["card"]
	_stage.set_anim(_investigator, "point", card_spot - _stage.actor_feet(_investigator), "sit")
	_stage.say(_investigator, line)
	_stage.set_prop("paper", true)
	_stage.set_anim(PLAYER, "sit", Vector2.UP)
	_show_card(_piece)
	_meter.highlight = str(_piece.get("record_id", ""))
	_meter.queue_redraw()
	_show_answers()


func _show_card(piece: Dictionary) -> void:
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
	_card.scale = Vector2(0.3, 0.3) * k
	_card.rotation = 0.0
	_animate_card(_card_target(), Vector2(k, k), -0.05, 1.0)


## Posición (sin escalar, pivote en el centro) que deja la tarjeta a la izquierda de la mesa.
func _card_target() -> Vector2:
	var k: float = SceneStage.ui_scale()
	var visual_top_left: Vector2 = Vector2(40.0, maxf(size.y * 0.5 - CARD_SIZE.y * k * 0.62, 150.0 * k))
	return visual_top_left - CARD_SIZE * 0.5 * (1.0 - k)


func _animate_card(pos: Vector2, card_scale: Vector2, rot: float, alpha: float) -> void:
	var seconds: float = Database.get_balance_float(B_CARD)
	if instant or seconds <= 0.0:
		_card.position = pos
		_card.scale = card_scale
		_card.rotation = rot
		_card.modulate.a = alpha
		return
	var t: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "position", pos, seconds)
	t.tween_property(_card, "scale", card_scale, seconds)
	t.tween_property(_card, "rotation", rot, seconds)
	t.tween_property(_card, "modulate:a", alpha, seconds)
	_tweens.append(t)


func _type_name(type_id: String) -> String:
	var key: String = InvestigationEngine.evidence_name_key(Database.get_investigation_params(), type_id)
	if key.is_empty():
		key = "EVIDENCE_" + type_id.to_upper()
	return tr(key) if tr(key) != key else type_id.capitalize()


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
	var extra: float = maxf(get_case_weight() - sum, 0.0)
	_meter.extra_text = tr("INTERROGATION_METER_EXTRA") % SceneStage.decimal(extra) if extra > 0.0 else ""
	if first:
		_meter.span = maxf(get_case_weight(), _meter.threshold) * 1.18
		_meter.rate = _meter.span / maxf(Database.get_balance_float(B_METER), 0.001)
	_meter.set_targets(pieces, extra)
	if first or instant:
		_meter.snap()


# ─── Respuestas ───────────────────────────────────────────────

func _show_answers() -> void:
	_open_panel(tr("INTERROGATION_PROMPT"))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var usable: Array[String] = _session.available_answers()
	for id: String in Interrogation.ANSWERS:
		row.add_child(_answer_tile(id, usable.has(id)))
	_panel_box.add_child(row)


func _answer_tile(answer_id: String, usable: bool) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var action: Callable = answer.bind(answer_id)
	if answer_id == Interrogation.ANSWER_ACCUSE:
		action = open_accuse_picker
	var variation: String = UITheme.V_PRIMARY if usable else ""
	var b: Button = SceneStage.ui_button(tr(_session.get_answer_key(answer_id)), variation, action)
	b.disabled = not usable
	b.name = "Answer_" + answer_id
	box.add_child(b)
	var hint: Label = SceneStage.ui_label(_hint(answer_id, usable), UITheme.V_SMALL, true,
			UITheme.color("paper" if usable else "warn"))
	hint.custom_minimum_size.x = 230 * SceneStage.ui_scale()
	box.add_child(hint)
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
	return tr("INTERROGATION_HINT_LAWYER") % int(rules["freeze_days"]) if usable \
			else tr("INTERROGATION_REQ_LAWYER")


func _requirement_missing(result: Dictionary) -> void:
	_set_caption(tr(Interrogation.outcome_key(str(result.get("outcome", "")))))
	SceneStage.play_sfx(self, SFX_BAD)
	if _card != null and not instant:
		var t: Tween = create_tween()
		for dx: float in [12.0, -12.0, 8.0, -8.0, 0.0]:
			t.tween_property(_card, "position:x", _card_target().x + dx, 0.05)
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


func _build_picker(candidates: Array[String]) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = UITheme.V_MODAL
	var box: VBoxContainer = VBoxContainer.new()
	panel.add_child(box)
	box.add_child(SceneStage.ui_label(tr("INTERROGATION_ACCUSE_TITLE"), UITheme.V_TITLE))
	var body: String = "INTERROGATION_ACCUSE_BODY" if not candidates.is_empty() else "INTERROGATION_ACCUSE_NOBODY"
	box.add_child(SceneStage.ui_label(tr(body), "", true))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	for id: String in candidates:
		grid.add_child(_candidate_tile(id))
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(SceneStage.ui_button(tr("INTERROGATION_CANCEL"), "", _close_picker))
	box.add_child(row)
	return panel


func _candidate_tile(npc_id: String) -> Control:
	var member: Dictionary = SceneStage.cast_member(npc_id)
	var box: VBoxContainer = VBoxContainer.new()
	var photo: SceneStage.PortraitBox = SceneStage.PortraitBox.new(member["appearance"],
			Vector2(150, 150) * SceneStage.ui_scale())
	photo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(photo)
	var b: Button = SceneStage.ui_button(str(member["name"]), "",
			answer.bind(Interrogation.ANSWER_ACCUSE, npc_id))
	b.custom_minimum_size.x = 200 * SceneStage.ui_scale()
	box.add_child(b)
	return box


func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null


# ─── Reacción y final ─────────────────────────────────────────

func _react(answer_id: String, accused: String, result: Dictionary, piece: Dictionary) -> void:
	var outcome: String = str(result.get("outcome", ""))
	_set_caption(tr(Interrogation.outcome_key(outcome)))
	var react: String = tr(REACT_PREFIX + outcome.to_upper())
	if outcome == Interrogation.OUTCOME_PIECE_TRANSFERRED:
		react = react % IdeaPool.get_npc_display_name(accused)
	_stage.say(PLAYER, "")
	_stage.set_anim(PLAYER, "sit", Vector2.UP)
	_stage.set_anim(_investigator, _investigator_anim(outcome), Vector2.DOWN, "sit")
	_stage.say(_investigator, react)
	_stamp_card(outcome, accused, piece)
	var delta: int = int(result.get("suspicion_delta", 0))
	if delta > 0:
		_stage.badge(PLAYER, tr("INTERROGATION_SUSPICION_BADGE") % delta, UITheme.color("sus"))
	var good: bool = outcome in [Interrogation.OUTCOME_PIECE_REMOVED, Interrogation.OUTCOME_ALIBI_ACCEPTED]
	SceneStage.play_sfx(self, SFX_GOOD if good else SFX_BAD)
	_refresh_meter(false)
	if answer_id == Interrogation.ANSWER_LAWYER:
		_stage.set_prop("lamp", SceneStage.LAMP_NEUTRAL)


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
	var loss: Color = Color("#c0392b")
	match outcome:
		Interrogation.OUTCOME_PIECE_REMOVED:
			_set_stamp(tr("INTERROGATION_STAMP_STRUCK"), Color("#2e7d4f"))
		Interrogation.OUTCOME_ALIBI_ACCEPTED:
			_set_stamp(tr("INTERROGATION_STAMP_CLEARED"), Color("#2e7d4f"))
		Interrogation.OUTCOME_ALIBI_FALSE:
			var factor: float = float(_session.get_rules().get("false_alibi_multiplier", 1.0))
			_card.weight = float(piece.get("weight", 0.0)) * factor
			_set_stamp(tr("INTERROGATION_STAMP_DOUBLED") % SceneStage.decimal(factor), loss)
		Interrogation.OUTCOME_PIECE_TRANSFERRED:
			_set_stamp(tr("INTERROGATION_STAMP_MOVED") % IdeaPool.get_npc_display_name(accused), Color("#2f5fa8"))
		Interrogation.OUTCOME_CASE_FROZEN:
			_set_stamp(tr("INTERROGATION_STAMP_FROZEN"), Color("#2a8fb8"))
		_:
			_set_stamp(tr("INTERROGATION_STAMP_NOTED"), loss)


func _set_stamp(text: String, color: Color) -> void:
	_card.stamp = text
	_card.stamp_color = color
	_card.queue_redraw()


func _next() -> void:
	_stage.say(_investigator, "")
	_stage.badge(PLAYER, "", Color.WHITE)
	_stage.set_prop("paper", false)
	if _card != null:
		var away: Vector2 = Vector2(-CARD_SIZE.x * 1.2, _card.position.y + 60.0)
		_animate_card(away, Vector2(0.8, 0.8), -0.3, 0.0)
	if _session.is_finished():
		_timeline.then(_pause(), _end)
	else:
		_timeline.then(_pause(), _present_piece)


func _end() -> void:
	_step = STEP_END
	_piece = {}
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
	_open_panel(_end_title)
	for line: String in _end_lines:
		_panel_box.add_child(SceneStage.ui_label(line, UITheme.V_STRONG, true,
				UITheme.color("gain") if success else UITheme.color("loss")))
	_button_row([SceneStage.ui_button(tr("INTERROGATION_LEAVE"), UITheme.V_PRIMARY, leave)])


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
		out.append(tr("INTERROGATION_END_FROZEN_HINT"))
	return out


static func _verdict_key(verdict: String) -> String:
	var params: Dictionary = Database.get_investigation_params()
	var data_id: String = str(InvestigationEngine.VERDICT_DATA_IDS.get(verdict, verdict))
	var entry: Dictionary = InvestigationEngine.find_by_id(params.get("verdicts", []), data_id)
	return str(entry.get("name_key", "VERDICT_" + verdict.to_upper()))


# ─── Paneles y ritmo ──────────────────────────────────────────

func _clear_panel() -> void:
	SceneStage.clear_children(_panel_box)
	_panel.visible = false


func _open_panel(title: String) -> void:
	_clear_panel()
	_panel.visible = true
	_fit_panel()
	_panel_box.add_child(SceneStage.ui_label(title, UITheme.V_TITLE, true))


func _button_row(buttons: Array[Button]) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	for b: Button in buttons:
		row.add_child(b)
	_panel_box.add_child(row)
	if not buttons.is_empty():
		buttons.back().call_deferred("grab_focus")


func _set_caption(text: String) -> void:
	_caption.text = text
	_caption_panel.visible = not text.is_empty()


func _settle() -> void:
	if instant:
		fast_forward()


func _pause() -> float:
	return Database.get_balance_float(B_PAUSE)


# ─── Iconos de las piezas (vector) ────────────────────────────

static func draw_evidence_icon(ci: CanvasItem, type_id: String, r: Rect2, accent: Color) -> void:
	var ink: Color = SceneStage.C_INK
	var c: Vector2 = r.get_center()
	ci.draw_circle(c, r.size.x * 0.5, accent.lightened(0.55))
	ci.draw_arc(c, r.size.x * 0.5, 0.0, TAU, 36, ink, 3.0, true)
	match type_id:
		"direct_witness", "partial_witness":
			_icon_eye(ci, c, r.size.x * 0.34, ink, type_id == "partial_witness")
		"camera_footage":
			_icon_camera(ci, c, ink)
		"card_log":
			_icon_card(ci, c, ink, accent)
		"unsourced_rumour":
			_icon_rumour(ci, c, ink)
		"accounting_trail":
			_icon_ledger(ci, c, ink)
		_:
			_icon_document(ci, c, ink, accent)


static func _icon_eye(ci: CanvasItem, c: Vector2, w: float, ink: Color, partial: bool) -> void:
	var pts: PackedVector2Array = []
	for i: int in 24:
		var t: float = TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(t) * w, sin(t) * w * 0.55 * absf(sin(t)) + sin(t) * w * 0.1))
	ci.draw_colored_polygon(pts, SceneStage.C_PAPER)
	pts.append(pts[0])
	ci.draw_polyline(pts, ink, 3.0, true)
	ci.draw_circle(c, w * 0.32, ink)
	ci.draw_circle(c + Vector2(-3, -3), w * 0.1, SceneStage.C_PAPER)
	if partial:
		ci.draw_rect(Rect2(c.x - w, c.y - w * 0.7, w * 2.0, w * 0.55), Color(ink, 0.55))


static func _icon_camera(ci: CanvasItem, c: Vector2, ink: Color) -> void:
	var body: Rect2 = Rect2(c + Vector2(-20, -12), Vector2(32, 24))
	ci.draw_rect(body, Color("#3b4247"))
	ci.draw_rect(body, ink, false, 3.0)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(12, -6), c + Vector2(24, -12),
			c + Vector2(24, 12), c + Vector2(12, 6)]), Color("#3b4247"))
	ci.draw_circle(c + Vector2(-6, 0), 6.0, Color("#9fd8f0"))
	ci.draw_circle(c + Vector2(-16, -16), 4.0, SceneStage.C_RED_LED)


static func _icon_card(ci: CanvasItem, c: Vector2, ink: Color, accent: Color) -> void:
	var card: Rect2 = Rect2(c + Vector2(-22, -15), Vector2(44, 30))
	ci.draw_rect(card, SceneStage.C_PAPER)
	ci.draw_rect(Rect2(card.position, Vector2(card.size.x, 8)), accent)
	ci.draw_rect(card, ink, false, 3.0)
	ci.draw_rect(Rect2(card.position + Vector2(5, 12), Vector2(12, 13)), Color("#c8a079"))
	for i: int in 2:
		ci.draw_line(card.position + Vector2(21, 15 + i * 7), card.position + Vector2(39, 15 + i * 7), ink, 2.0)


static func _icon_rumour(ci: CanvasItem, c: Vector2, ink: Color) -> void:
	var bubble: PackedVector2Array = SceneStage.rounded_rect(Rect2(c + Vector2(-22, -16), Vector2(44, 28)), 10.0)
	ci.draw_colored_polygon(bubble, SceneStage.C_PAPER)
	bubble.append(bubble[0])
	ci.draw_polyline(bubble, ink, 3.0, true)
	for i: int in 3:
		ci.draw_circle(c + Vector2(-11 + i * 11, -2), 3.0, ink)


static func _icon_ledger(ci: CanvasItem, c: Vector2, ink: Color) -> void:
	var page: Rect2 = Rect2(c + Vector2(-18, -22), Vector2(36, 44))
	ci.draw_rect(page, SceneStage.C_PAPER)
	ci.draw_rect(page, ink, false, 3.0)
	for i: int in 4:
		ci.draw_line(page.position + Vector2(6, 10 + i * 9), page.position + Vector2(30, 10 + i * 9), ink, 2.0)
	ci.draw_circle(c + Vector2(16, 16), 9.0, Color("#d8b04a"))
	ci.draw_arc(c + Vector2(16, 16), 9.0, 0.0, TAU, 18, ink, 2.0, true)


static func _icon_document(ci: CanvasItem, c: Vector2, ink: Color, accent: Color) -> void:
	var page: Rect2 = Rect2(c + Vector2(-17, -22), Vector2(34, 44))
	ci.draw_rect(page, SceneStage.C_PAPER)
	ci.draw_rect(page, ink, false, 3.0)
	for i: int in 3:
		ci.draw_line(page.position + Vector2(6, 10 + i * 8), page.position + Vector2(28, 10 + i * 8), ink, 2.0)
	ci.draw_circle(c + Vector2(8, 12), 8.0, accent)
	ci.draw_arc(c + Vector2(8, 12), 8.0, 0.0, TAU, 16, ink, 2.0, true)
