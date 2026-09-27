# interrogation_scene_case.gd — Cuerpo de test_interrogation_scene: la escena de P15 (§12.5, PASO 29) presenta las piezas una a una, cada respuesta llama a Interrogation, finales de éxito, fracaso, congelación y sin caso, las tres variantes de tono (disculpa, portazo con su sonido y subtítulo, neutro), Esc por puntos de lectura, el selector de acusados, el vigilante sin nombre, la ventana modal de UIRoot y la maquetación en móvil.
# PROPIETARIO DE: nada.
# ESCUCHA: interrogation_answered, investigation_resolved, game_over (vía SignalLog) y subtitle_posted (conexión del caso).
extends TestCase

const Fx := preload("res://tests/cases/security_fixtures.gd")
const EPS := 0.001
const ROSE := "npc_rose_miller"
const PHONE_SCREEN := Vector2(2400, 1080)
## La ficha va algo inclinada: su caja puede asomar unos píxeles del rectángulo sin girar.
const TILT_SLACK := 12.0
const AUDIO_DRAIN_STEPS := 300
const AUDIO_DRAIN_STEP_S := 0.1

var _log: Fx.SignalLog
var _answered: Array = []
var _subtitles: Array[String] = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "database loaded")
	await _check_tone_apology()
	await _check_tone_door_slam()
	await _check_tone_neutral()
	await _check_sequential_failure()
	await _check_success()
	await _check_requirement_missing()
	await _check_lawyer_frozen()
	await _check_no_case()
	await _check_populated_investigator()
	await _check_escape_beats()
	await _check_picker_is_modal()
	await _check_guard_fallback()
	await _check_uiroot_modal()
	await _check_phone_layout()
	_log.stop()


func _fresh(populated: bool = false) -> void:
	if _log != null:
		_log.stop()
	new_run(DEFAULT_SEED, populated)
	_answered.clear()
	_log = Fx.SignalLog.new().watch(["interrogation_answered", "investigation_resolved", "game_over"])


## Testigo 4,0 · parcial 0,8 · grabación 4,5 (· tarjeta 2,5) contra el jugador, en fase 4.
func _case(with_card: bool) -> String:
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	Security.add_evidence(case_id, "partial_witness", 0.8, Fx.PLAYER)
	Security.add_evidence(case_id, "camera_footage", 4.5, Fx.PLAYER)
	if with_card:
		Security.add_evidence(case_id, "card_log", 2.5, Fx.PLAYER)
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_INTERROGATION)
	return case_id


func _open(case_id: String, context: Dictionary, instant: bool = true) -> InterrogationScene:
	var scene: InterrogationScene = InterrogationScene.new(case_id, context)
	scene.instant = instant
	scene.closed.connect(func() -> void: pass)
	scene.answered.connect(func(id: String, result: Dictionary) -> void: _answered.append([id, result["outcome"]]))
	add_child(scene)
	await wait_frames(2)
	return scene


func _close(scene: InterrogationScene) -> void:
	scene.queue_free()
	await wait_frames(1)


func _shows(scene: InterrogationScene, text: String) -> bool:
	return scene.get_visible_texts().has(text)


# ─── Tono (§12.5) ───────────────────────────────────────────────────────

func _check_tone_apology() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 90.0, "suspicion": 10.0}, false)
	var investigator: String = scene.get_investigator()
	check_eq(scene.get_tone(), Interrogation.TONE_APOLOGY, "reputation 90 → apology")
	check_eq(scene.get_stage().bubble_text(investigator), tr("INTERROGATION_INTRO_APOLOGY"),
			"the investigator opens by apologising")
	check(not bool(scene.get_stage().get_actor(investigator)["seated"]), "…standing up to greet you")
	check(bool(scene.get_stage().get_prop("coffee", false)), "…with a coffee on the table")
	check_eq(scene.get_stage().get_prop("lamp"), SceneStage.LAMP_WARM, "warm light")
	check(not scene.has_door_slammed(), "no door slam")
	scene.fast_forward()
	check(scene.get_step() == InterrogationScene.STEP_PIECE
			and bool(scene.get_stage().get_actor(investigator)["seated"]), "then sits down and presents")
	await _close(scene)


func _check_tone_door_slam() -> void:
	_fresh()
	var director: AudioDirector = AudioDirector.new()
	add_child(director)
	await wait_frames(2)
	_subtitles.clear()
	EventBus.subtitle_posted.connect(_on_subtitle)
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 90.0, "suspicion": 80.0}, false)
	check_eq(scene.get_tone(), Interrogation.TONE_DOOR_SLAM, "suspicion 80 → door slam (even at reputation 90)")
	check(not scene.is_door_closed() and not scene.has_door_slammed(), "the door starts open")
	check_eq(scene.get_stage().get_prop("lamp"), SceneStage.LAMP_HARSH, "harsh light")
	var wait: float = Database.get_balance_float("escenas.portazo_espera_segundos")
	scene.advance(wait + Database.get_balance_float("escenas.pausa_segundos") + 0.01)
	check_eq(scene.get_caption(), tr("INTERROGATION_INTRO_DOOR_SLAM"), "the slam line is narrated")
	scene.fast_forward()
	check(scene.is_door_closed() and scene.has_door_slammed(), "the door slams shut")
	check(scene.get_sfx_requests().has(InterrogationScene.SFX_DOOR), "the slam asks AudioDirector for its sound")
	var door_sub: String = SfxBank.subtitle_key(InterrogationScene.SFX_DOOR) if SfxBank.has_sfx(InterrogationScene.SFX_DOOR) \
			else InterrogationScene.SUB_DOOR
	check(_subtitles.has(door_sub), "…with a subtitle that describes the door (%s)" % door_sub)
	check_eq(scene.get_step(), InterrogationScene.STEP_PIECE, "then the first piece is presented")
	EventBus.subtitle_posted.disconnect(_on_subtitle)
	await _close(scene)
	await _drain_audio(director)
	remove_child(director)
	director.free()
	await _drain_audio(null)


## Recoge los renders de audio en segundo plano (hilo musical, ambiente, efectos) antes de seguir:
## un trabajo pendiente del WorkerThreadPool al salir aborta el proceso.
func _drain_audio(director: AudioDirector) -> void:
	for _i: int in AUDIO_DRAIN_STEPS:
		MuzakLibrary.poll()
		Ambience.poll_jobs()
		SfxBank.poll_prewarm()
		var ambience: Ambience = director.get_ambience() if director != null else null
		var busy: bool = ambience != null and ambience.is_busy()
		if not MuzakLibrary.is_rendering() and not busy and SfxBank.is_prewarmed():
			return
		await get_tree().create_timer(AUDIO_DRAIN_STEP_S).timeout


func _on_subtitle(key: String, _position: Vector2, _importance: int) -> void:
	_subtitles.append(key)


func _check_tone_neutral() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 10.0}, false)
	check_eq(scene.get_tone(), Interrogation.TONE_NEUTRAL, "neutral tone")
	check_eq(scene.get_stage().bubble_text(scene.get_investigator()), tr("INTERROGATION_INTRO_NEUTRAL"),
			"neutral opening line")
	check(not bool(scene.get_stage().get_prop("coffee", false)) and not scene.has_door_slammed(),
			"no coffee, no slam")
	await _close(scene)


# ─── Flujo secuencial ───────────────────────────────────────────────────

func _check_sequential_failure() -> void:
	_fresh()
	var case_id: String = _case(true)
	var records: Array[String] = []
	for piece: Dictionary in InvestigationEngine.pieces_against(Security.get_investigation(case_id), Fx.PLAYER):
		records.append(str(piece["record_id"]))
	var scene: InterrogationScene = await _open(case_id, {"reputation": 65.0, "suspicion": 0.0,
			"alibi": {"provider": "npc_liar", "genuine": false}, "verification_roll": 0.1,
			"has_legal_contact": false})
	check_eq(scene.get_shown_piece().get("record_id"), records[0], "exhibit 1 is the first piece")
	check_near(scene.get_meter_weight(), scene.get_case_weight(), EPS, "the meter shows Security's weight")
	check_near(scene.get_case_weight(), 11.8, EPS, "11.8 against you")
	check_eq(scene.answer(Interrogation.ANSWER_SILENCE)["outcome"], "silence_kept", "silence")
	check_eq(scene.get_shown_piece().get("record_id"), records[1], "exhibit 2 follows, one at a time")
	check_eq(scene.answer(Interrogation.ANSWER_DENY)["outcome"], "piece_removed", "weak piece denied")
	check_near(scene.get_meter_weight(), 11.0, EPS, "the meter drops by 0.8")
	check_eq(scene.answer(Interrogation.ANSWER_EXPLAIN)["outcome"], "alibi_false", "the bought alibi is caught")
	check_near(scene.get_case_weight(), 15.5, EPS, "the footage now weighs double (9.0)")
	check(scene.get_meter().span >= scene.get_meter_weight(), "the meter's scale grows: nothing overflows the bar")
	check(not scene.available_answers().has(Interrogation.ANSWER_EXPLAIN), "the burnt alibi is gone")
	check_eq(scene.get_shown_piece().get("record_id"), records[3], "exhibit 4")
	check_eq(scene.answer(Interrogation.ANSWER_DENY)["outcome"], "denial_rejected", "denying 2.5 fails")
	var indices: Array = []
	for args: Array in _log.of("interrogation_answered"):
		indices.append(args[1])
	check_eq(indices, [0, 1, 2, 3], "each answer goes through Interrogation (interrogation_answered 0..3)")
	check_eq(_answered.size(), 4, "the scene emits answered() for each answer")
	check_eq(scene.get_step(), InterrogationScene.STEP_END, "all pieces answered → end")
	check_eq(scene.get_end_title(), tr("INTERROGATION_FAILURE"), "failure end state")
	check(scene.get_end_lines().has(tr("INTERROGATION_END_VERDICT") % tr("VERDICT_PLAYER_MAJOR")),
			"the verdict is shown: serious")
	check(scene.get_end_lines().has(tr("INTERROGATION_END_SUSPICION") % 13), "suspicion added: +5 +8")
	check_eq(_log.count("game_over"), 1, "Security ends the run (weight 15.5 > 10)")
	check(scene.answer(Interrogation.ANSWER_DENY).is_empty(), "no more answers after the end")
	await _close(scene)


func _check_success() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	Security.add_evidence(case_id, "camera_footage", 4.5, Fx.PLAYER)
	Security.register_camera_footage("turnstiles", d0, 10)
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_INTERROGATION)
	var scene: InterrogationScene = await _open(case_id, {"reputation": 50.0, "suspicion": 0.0})
	var candidates: Array[String] = scene.accuse_candidates()
	check(not candidates.is_empty() and not candidates.has(Fx.PLAYER)
			and not candidates.has(scene.get_investigator()), "someone to blame (never you or the investigator)")
	scene.open_accuse_picker()
	check(_shows(scene, tr("INTERROGATION_ACCUSE_TITLE")), "the accuse picker opens")
	check_eq(scene.answer(Interrogation.ANSWER_ACCUSE, Fx.SCAPEGOAT)["outcome"], "piece_transferred",
			"the witness piece is pinned on a colleague")
	check_eq(scene.answer(Interrogation.ANSWER_EXPLAIN)["outcome"], "alibi_accepted", "a real alibi")
	check(bool(scene.get_end_result().get("success", false)), "weight below 7.0 → success")
	check_eq(scene.get_end_title(), tr("INTERROGATION_SUCCESS"), "success end state")
	check(scene.get_end_lines().has(tr("INTERROGATION_END_VERDICT") % tr("VERDICT_COLD")), "cold verdict shown")
	check(scene.get_meter_weight() < 7.0, "the meter ends below the line")
	await _close(scene)


func _check_requirement_missing() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 0.0,
			"has_legal_contact": false})
	var first: String = str(scene.get_shown_piece().get("record_id", ""))
	var explain: Button = scene.find_child("Answer_explain", true, false) as Button
	var lawyer: Button = scene.find_child("Answer_request_lawyer", true, false) as Button
	check(explain != null and explain.disabled and lawyer != null and lawyer.disabled,
			"explain and lawyer are disabled without alibi / P9 contact")
	check(_shows(scene, tr("INTERROGATION_REQ_ALIBI")) and _shows(scene, tr("INTERROGATION_REQ_LAWYER")),
			"the requirements are shown")
	check_eq(scene.answer(Interrogation.ANSWER_EXPLAIN)["outcome"], "requirement_missing", "explain refused")
	check(scene.get_step() == InterrogationScene.STEP_PIECE
			and str(scene.get_shown_piece().get("record_id")) == first, "the same piece stays on the table")
	check_eq(scene.get_caption(), tr("INTERROGATION_OUTCOME_REQUIREMENT_MISSING"), "and the refusal is narrated")
	await _close(scene)


func _check_lawyer_frozen() -> void:
	_fresh()
	var case_id: String = _case(false)
	var scene: InterrogationScene = await _open(case_id, {"reputation": 50.0, "suspicion": 0.0,
			"has_legal_contact": true})
	check(scene.available_answers().has(Interrogation.ANSWER_LAWYER), "a P9 contact enables the lawyer")
	check_eq(scene.answer(Interrogation.ANSWER_LAWYER)["outcome"], "case_frozen", "lawyer requested")
	check_eq(scene.get_end_title(), tr("INTERROGATION_FROZEN_TITLE"), "frozen end state")
	check(Security.get_investigation(case_id).is_frozen(Security.get_current_day()), "logic: the case is frozen")
	var days: int = int(scene.get_session().get_rules()["freeze_days"])
	check(scene.get_end_lines().has(tr("INTERROGATION_END_FROZEN_HINT") % days), "the hint uses freeze_days (%d)" % days)
	await _close(scene)


func _check_no_case() -> void:
	_fresh()
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	var scene: InterrogationScene = await _open(case_id, {"reputation": 50.0, "suspicion": 0.0})
	check_eq(scene.get_step(), InterrogationScene.STEP_END, "a case still collecting evidence: nothing to ask")
	check_eq(scene.get_end_title(), tr("INTERROGATION_NO_CASE"), "the scene says so")
	var closed: Array[int] = [0]
	scene.closed.connect(func() -> void: closed[0] += 1)
	scene.request_close()
	check_eq(closed[0], 1, "and can be left")
	await _close(scene)


func _check_populated_investigator() -> void:
	_fresh(true)
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 0.0})
	check_eq(scene.get_investigator(), "npc_rose_miller", "Rose Miller interrogates by default")
	check(scene.get_stage().has_actor("npc_rose_miller") and scene.get_stage().has_actor("player"),
			"both sit at the table")
	check_eq(scene.get_stage().get_prop("nameplate"), NPCDirector.get_npc("npc_rose_miller").name,
			"her nameplate is on the table")
	scene.request_close()
	check_eq(scene.get_step(), InterrogationScene.STEP_PIECE, "Esc does not get you out of an interrogation")
	await _close(scene)


# ─── Esc por puntos de lectura ──────────────────────────────────────────

## Un Esc tras responder muestra la reacción (resultado, sello, réplica) y se queda ahí; el
## siguiente trae la pieza siguiente.
func _check_escape_beats() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 0.0}, false)
	var investigator: String = scene.get_investigator()
	scene.request_close()
	check_eq(scene.get_step(), InterrogationScene.STEP_PIECE, "Esc during the opening line → the first exhibit")
	scene.answer(Interrogation.ANSWER_SILENCE)
	check_eq(scene.get_step(), InterrogationScene.STEP_REACT, "the player answers")
	scene.request_close()
	check_eq(scene.get_caption(), tr(Interrogation.outcome_key(Interrogation.OUTCOME_SILENCE)),
			"one Esc: the outcome is shown")
	check_eq(scene.get_card_stamp(), tr("INTERROGATION_STAMP_NOTED"), "…the card is stamped")
	check_eq(scene.get_stage().bubble_text(investigator), tr("INTERROGATION_REACT_SILENCE_KEPT"),
			"…the investigator reacts")
	check(scene.get_step() == InterrogationScene.STEP_REACT and _shows(scene, tr("INTERROGATION_NEXT")),
			"…and the scene waits there (Next exhibit)")
	scene.request_close()
	check(scene.get_step() == InterrogationScene.STEP_PIECE and scene.get_caption().is_empty()
			and scene.get_session().get_current_index() == 1, "second Esc: the next exhibit")
	await _close(scene)


# ─── Selector de acusados ───────────────────────────────────────────────

## El selector sustituye a las respuestas: no quedan botones pulsables detrás.
func _check_picker_is_modal() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 0.0})
	check(scene.find_child("Answer_deny", true, false) != null, "the answers are on the panel")
	scene.open_accuse_picker()
	check(scene.is_picker_open() and scene.find_child("Answer_deny", true, false) == null,
			"the picker replaces the answers (nothing clickable behind it)")
	scene.request_close()
	check(not scene.is_picker_open() and scene.find_child("Answer_deny", true, false) != null,
			"Esc closes the picker and brings the answers back")
	await _close(scene)


# ─── Investigador: nunca un ausente ─────────────────────────────────────

func _check_guard_fallback() -> void:
	_fresh(true)
	check_eq(InterrogationScene.choose_investigator(""), SceneStage.GUARD_ID,
			"nobody in Audit or Security → the unnamed guard")
	check_eq(InterrogationScene.choose_investigator(ROSE), ROSE, "Rose Miller while she is on staff")
	var guard: Dictionary = SceneStage.cast_member(SceneStage.GUARD_ID)
	check_eq(str(guard["name"]), tr(SceneStage.GUARD_NAME_KEY), "the guard has a localised name")
	check_eq((guard["appearance"] as Dictionary).get("uniform"), SceneStage.GUARD_UNIFORM, "…and a uniform")
	NPCDirector.remove_npc(ROSE, "expelled")
	check_eq(InterrogationScene.choose_investigator(ROSE), SceneStage.GUARD_ID, "a removed Rose never comes back")
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 0.0})
	check(scene.get_investigator() != ROSE and scene.get_stage().has_actor(scene.get_investigator()),
			"the scene casts whoever is left (%s)" % scene.get_investigator())
	await _close(scene)


# ─── Ventana modal de UIRoot ────────────────────────────────────────────

func _esc(ui: UIRoot) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "pause_menu"
	ev.pressed = true
	ui._unhandled_input(ev)


func _check_uiroot_modal() -> void:
	_fresh()
	var ui: UIRoot = UIRoot.new()
	add_child(ui)
	await wait_frames(2)
	var was_paused: bool = GameClock.is_paused()
	GameClock.resume()
	var scene: InterrogationScene = InterrogationScene.open(ui, _case(false),
			{"reputation": 50.0, "suspicion": 0.0, "has_legal_contact": true})
	await wait_frames(2)
	check(ui.get_top_modal() == scene and GameClock.is_paused(), "InterrogationScene.open(UIRoot): modal, clock paused")
	scene.fast_forward()
	_esc(ui)
	check(ui.get_top_modal() == scene and scene.get_step() == InterrogationScene.STEP_PIECE,
			"Esc through UIRoot does not end the interrogation")
	scene.answer(Interrogation.ANSWER_LAWYER)
	scene.fast_forward()
	check_eq(scene.get_step(), InterrogationScene.STEP_END, "frozen: the end panel")
	_esc(ui)
	await wait_frames(2)
	check(not ui.has_modal() and not GameClock.is_paused(), "Esc at the end leaves: modal closed, clock resumed")
	if was_paused:
		GameClock.pause()
	ui.queue_free()
	await wait_frames(1)


# ─── Maquetación en móvil (texto grande y escala táctil) ────────────────

func _check_phone_layout() -> void:
	_fresh()
	var saved: Array = [UITheme.touch_scale_active, UITheme.current_text_size]
	UITheme.touch_scale_active = true
	UITheme.current_text_size = UITheme.TEXT_LARGE
	var host: Control = Control.new()
	host.size = PHONE_SCREEN
	add_child(host)
	var scene: InterrogationScene = InterrogationScene.new(_case(true), {"reputation": 50.0, "suspicion": 0.0})
	scene.instant = true
	host.add_child(scene)
	await wait_frames(6)
	var screen: Rect2 = Rect2(Vector2.ZERO, PHONE_SCREEN)
	var panel: Rect2 = scene.get_dock().panel.get_global_rect()
	check(screen.encloses(panel), "phone: the answer panel stays on screen (%s)" % panel)
	var card: EvidenceCardProbe = EvidenceCardProbe.new(scene.get_card())
	check(scene.get_stage().safe_rect().grow(TILT_SLACK).encloses(card.rect), "phone: the exhibit card sits in the room")
	check(not card.rect.intersects(panel), "phone: the card does not hide under the panel")
	scene.queue_free()
	host.queue_free()
	UITheme.touch_scale_active = saved[0]
	UITheme.current_text_size = saved[1]
	await wait_frames(1)


## Caja visible de la ficha (escala con pivote en el centro, sin contar la leve inclinación).
class EvidenceCardProbe extends RefCounted:
	var rect: Rect2 = Rect2()

	func _init(card: Control) -> void:
		if card == null:
			return
		var shown: Vector2 = card.size * card.scale
		rect = Rect2(card.position + card.pivot_offset * (Vector2.ONE - card.scale), shown)
