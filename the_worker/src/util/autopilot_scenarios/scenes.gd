# scenes.gd (escenario) — Capturas de las escenas Aurora (antes del choque y sus tres resultados) e interrogatorio (disculpa, portazo, piezas sobre la mesa, acusación, final).
# PROPIETARIO DE: nada (monta una partida con población, prepara ideas y casos de QA y fotografía).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_scenes scenes
## Capturas: aurora_pick, aurora_prepare, aurora_accusation, aurora_win, aurora_tie, aurora_loss,
## aurora_others, interrogation_apology, interrogation_door_slam, interrogation_mid,
## interrogation_stamp, interrogation_accuse, interrogation_end, aurora_phone, interrogation_phone,
## aurora_tie_es, interrogation_es (textos más largos en español).
## Los choques usan claves forzadas (clash_overrides) para fijar cada resultado; los
## interrogatorios, contexto forzado (reputación, sospecha) para cada tono.

const RUN_SEED := 12345
const LIFECYCLE: Array[String] = ["GameClock", "PlayerState", "NPCDirector", "SocialGraph",
	"BeliefNet", "Security", "Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem"]
const OWNER := "npc_claudia_reeves"
const CONFIDANT := "npc_nate_brackley"
## Vende una idea al jugador (cesión consentida: no acusa).
const SELLER := "npc_bernard_lasker"
const ROOM_EXTRAS: Array[String] = ["npc_debbie_foyle", "npc_george_penn", "npc_sonia_vail",
	"npc_ray_cudmore", "npc_tom_iverson", "npc_ludmila_petrova", "npc_amelia_cole",
	"npc_bernard_lasker", "npc_connie_marks"]
const WIN: Dictionary = {"player_reputation": 62.0, "player_suspicion": 8.0, "allies": 2,
	"accuser_reputation": 45.0, "believers": 0}
const TIE: Dictionary = {"player_reputation": 50.0, "player_suspicion": 20.0, "allies": 1,
	"accuser_reputation": 52.0, "believers": 0}
const LOSS: Dictionary = {"player_reputation": 30.0, "player_suspicion": 40.0, "allies": 0,
	"accuser_reputation": 40.0}
const PHONE := Vector2i(960, 432)
const DESKTOP := Vector2i(1600, 900)
## Salas de acreditación 6-7 (el jugador no tiene acceso): cada caso de QA en una distinta para
## que Security no fusione los incidentes en el mismo expediente.
const CASE_ROOMS: Array[String] = ["ceo_office", "boardroom", "vice_ceo_office", "crisis_room",
	"trading_room", "results_room", "board_confidential_archive"]
## Asistentes con ideas propias pendientes: las presentan al cerrar la reunión.
const PRESENTERS: Array[String] = ["npc_sonia_vail", "npc_tom_iverson"]

var _pilot: Autopilot
var _case_index: int = 0


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	_new_run()
	await pilot.frames(3)
	await _aurora_run(WIN, "aurora_win", true)
	await _aurora_run(TIE, "aurora_tie", false)
	await _aurora_run(LOSS, "aurora_loss", false)
	await _interrogation_tone({"reputation": 91.0, "suspicion": 12.0}, "interrogation_apology", 2.2)
	await _interrogation_tone({"reputation": 48.0, "suspicion": 82.0}, "interrogation_door_slam", 1.75)
	await _interrogation_flow()
	await _phone_shots()
	await _spanish_shots()


func _new_run() -> void:
	Database.load_all()
	GameClock.set_run_seed(RUN_SEED)
	for system_name: String in LIFECYCLE:
		var node: Node = get_tree().root.get_node_or_null(NodePath(system_name))
		if node == null:
			continue
		node.call("reset_for_new_run")
		if system_name == "GameClock":
			GameClock.set_run_seed(RUN_SEED)
		elif system_name == "NPCDirector":
			NPCDirector.generate_population()
		elif system_name == "SocialGraph":
			SocialGraph.build_initial_graph()
	PlayerState.set_player_name("Doreen Bramwell")


# ─── Aurora ───────────────────────────────────────────────────

## Idea del propietario escuchada por el jugador (se la cuenta a un confidente en su sala).
func _stolen_idea(owner_id: String) -> String:
	var id: String = IdeaPool.generate_idea(owner_id, "design")
	var room: String = NPCDirector.get_current_location(owner_id)
	if room.is_empty():
		room = NPCDirector.get_npc(owner_id).home_room
		NPCDirector.set_current_location(owner_id, room)
	IdeaPool.share_idea(id, CONFIDANT)
	EventBus.room_entered.emit(room, true)
	IdeaPool.acquire(id, IdeaPool.METHOD_OVERHEAR)
	return id


func _open_meeting(believers: int) -> String:
	GameClock.set_time(3, 11, 0)
	if not IdeaPool.is_meeting_open():
		IdeaPool.start_meeting()
	var id: String = _stolen_idea(OWNER)
	for i: int in believers:
		IdeaPool.share_idea(id, ROOM_EXTRAS[i])
	IdeaPresentation.seat_attendee(OWNER)
	for npc_id: String in ROOM_EXTRAS:
		IdeaPresentation.seat_attendee(npc_id)
	for npc_id: String in PRESENTERS:
		IdeaPool.generate_idea(npc_id, "marketing")
	return id


func _aurora_run(overrides: Dictionary, shot_name: String, full: bool) -> void:
	var idea_id: String = _open_meeting(2 if overrides == LOSS else 0)
	if full:
		var bought: String = IdeaPool.generate_idea(SELLER, "sales")
		IdeaPool.acquire(bought, IdeaPool.METHOD_PURCHASE)
	var scene: AuroraScene = AuroraScene.new()
	scene.clash_overrides = overrides
	scene.closed.connect(func() -> void: pass)
	add_child(scene)
	await _pilot.seconds(1.6)
	if full:
		await _pilot.shot("aurora_pick")
	scene.choose_idea(idea_id)
	await _pilot.seconds(0.4)
	if full:
		await _pilot.shot("aurora_prepare")
	scene.choose_preparation(IdeaPresentation.PREP_NONE)
	var walk: float = Database.get_balance_float("escenas.paseo_segundos")
	await _pilot.seconds(walk + SceneStage.reading_time(tr("AURORA_PITCH")) + 1.0)
	if full:
		await _pilot.shot("aurora_accusation")
	scene.fast_forward()
	await _pilot.seconds(0.5)
	await _pilot.shot(shot_name)
	if full:
		scene.continue_scene()
		await _pilot.seconds(walk * 3.0 + 1.0)
		await _pilot.shot("aurora_others")
	scene.finish()
	scene.queue_free()
	await _pilot.frames(2)


# ─── Interrogatorio ───────────────────────────────────────────

## Caso en fase 4 con testigo 4,0 · parcial 0,8 · grabación 4,5 · tarjeta 2,5 contra el jugador.
func _open_case() -> String:
	var room: String = CASE_ROOMS[_case_index % CASE_ROOMS.size()]
	_case_index += 1
	var case_id: String = Security.report_incident("direct_witness_report", 1, room, true, {
		"subject": "player", "witness": "npc_george_penn", "evidence_type": "direct_witness", "hour": 22})
	Security.add_evidence(case_id, "partial_witness", 0.8, "player")
	Security.add_evidence(case_id, "camera_footage", 4.5, "player")
	Security.add_evidence(case_id, "card_log", 2.5, "player")
	var inv: Investigation = Security.get_investigation(case_id)
	var guard: int = Investigation.MAX_PHASE
	while inv != null and inv.is_active() and inv.phase < InvestigationEngine.PHASE_INTERROGATION and guard > 0:
		Security.advance_phase(case_id)
		guard -= 1
	return case_id


func _interrogation_tone(context: Dictionary, shot_name: String, wait: float) -> void:
	var scene: InterrogationScene = InterrogationScene.new(_open_case(), context)
	scene.closed.connect(func() -> void: pass)
	add_child(scene)
	await _pilot.seconds(wait)
	await _pilot.shot(shot_name)
	scene.queue_free()
	await _pilot.frames(2)


func _interrogation_flow() -> void:
	var context: Dictionary = {"reputation": 66.0, "suspicion": 30.0, "has_legal_contact": false,
		"alibi": {"provider": "npc_bernard_lasker", "genuine": false}, "verification_roll": 0.1}
	var scene: InterrogationScene = InterrogationScene.new(_open_case(), context)
	scene.closed.connect(func() -> void: pass)
	add_child(scene)
	await _pilot.seconds(4.2)
	scene.fast_forward()
	scene.answer(Interrogation.ANSWER_SILENCE)
	scene.fast_forward()
	scene.answer(Interrogation.ANSWER_DENY)
	scene.fast_forward()
	await _pilot.seconds(1.6)
	await _pilot.shot("interrogation_mid")
	scene.answer(Interrogation.ANSWER_EXPLAIN)
	await _pilot.seconds(3.2)
	await _pilot.shot("interrogation_stamp")
	scene.fast_forward()
	scene.open_accuse_picker()
	await _pilot.seconds(0.5)
	await _pilot.shot("interrogation_accuse")
	var candidates: Array[String] = scene.accuse_candidates()
	scene.answer(Interrogation.ANSWER_ACCUSE, candidates[0] if not candidates.is_empty() else "")
	scene.fast_forward()
	await _pilot.seconds(1.5)
	await _pilot.shot("interrogation_end")
	scene.queue_free()
	await _pilot.frames(2)


# ─── Móvil ────────────────────────────────────────────────────

## Móvil: ventana 20:9 con el texto grande y la escala táctil que aplica UIRoot en un teléfono.
func _phone_shots() -> void:
	get_window().size = PHONE
	UITheme.touch_scale_active = true
	UITheme.current_text_size = UITheme.TEXT_LARGE
	await _pilot.frames(4)
	var idea_id: String = _open_meeting(0)
	var scene: AuroraScene = AuroraScene.new()
	scene.clash_overrides = WIN
	scene.closed.connect(func() -> void: pass)
	add_child(scene)
	await _pilot.seconds(1.6)
	scene.choose_idea(idea_id)
	await _pilot.seconds(0.3)
	await _pilot.shot("aurora_phone")
	scene.finish()
	scene.queue_free()
	var inter: InterrogationScene = InterrogationScene.new(_open_case(), {"reputation": 66.0, "suspicion": 30.0})
	inter.closed.connect(func() -> void: pass)
	add_child(inter)
	await _pilot.seconds(5.0)
	await _pilot.shot("interrogation_phone")
	inter.queue_free()
	UITheme.touch_scale_active = false
	UITheme.current_text_size = UITheme.TEXT_MEDIUM
	get_window().size = DESKTOP
	await _pilot.frames(2)


# ─── Español ──────────────────────────────────────────────────

func _spanish_shots() -> void:
	TranslationServer.set_locale("es")
	await _aurora_run(TIE, "aurora_tie_es", false)
	var scene: InterrogationScene = InterrogationScene.new(_open_case(), {"reputation": 66.0,
			"suspicion": 30.0, "has_legal_contact": true})
	scene.closed.connect(func() -> void: pass)
	add_child(scene)
	await _pilot.seconds(5.0)
	await _pilot.shot("interrogation_es")
	scene.queue_free()
	TranslationServer.set_locale("en")
	await _pilot.frames(2)
