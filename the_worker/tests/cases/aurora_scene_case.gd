# aurora_scene_case.gd — Cuerpo de test_aurora_scene: la escena Aurora (§11.2, PASO 24) con los tres resultados forzados del choque muestra el texto correcto y llama a la lógica; presentación sin choque, presentaciones ajenas, preparación, A.S.S.I.S.T., no presentar y sin reunión.
# PROPIETARIO DE: nada.
# ESCUCHA: idea_contested, idea_presented, assist_used (conexiones del caso).
extends TestCase

const OWNER := "npc_claudia_reeves"
const CONFIDANT := "npc_nate_brackley"
const WITNESSES: Array[String] = ["npc_debbie_foyle", "npc_george_penn"]
const BELIEVERS: Array[String] = ["npc_sonia_vail", "npc_ray_cudmore"]
const PRESENTER := "npc_tom_iverson"
const ABSENT_OWNER := "npc_amelia_cole"
const EPS := 0.0001
const WIN: Dictionary = {"player_reputation": 60.0, "player_suspicion": 0.0, "allies": 1,
	"accuser_reputation": 40.0, "believers": 0}
const TIE: Dictionary = {"player_reputation": 50.0, "player_suspicion": 20.0, "allies": 0,
	"accuser_reputation": 45.0, "believers": 0}
const LOSS: Dictionary = {"player_reputation": 30.0, "player_suspicion": 40.0, "allies": 0,
	"accuser_reputation": 40.0}

var _contested: Array = []
var _presented: Array = []
var _assists: Array = []
var _closed: int = 0


func run_case() -> void:
	check(new_run(), "Database loads the data files")
	EventBus.idea_contested.connect(_on_contested)
	EventBus.idea_presented.connect(_on_presented)
	EventBus.assist_used.connect(_on_assist)
	await _check_win()
	await _check_tie()
	await _check_loss()
	await _check_uncontested_and_others()
	await _check_preparation_options()
	await _check_assist()
	await _check_skip()
	await _check_no_meeting()
	EventBus.idea_contested.disconnect(_on_contested)
	EventBus.idea_presented.disconnect(_on_presented)
	EventBus.assist_used.disconnect(_on_assist)


func _on_contested(id: String, accuser: String, result: String) -> void:
	_contested.append([id, accuser, result])


func _on_presented(id: String, who: String, merit: int) -> void:
	_presented.append([id, who, merit])


func _on_assist(task: String, quality: String) -> void:
	_assists.append([task, quality])


# ─── Ayudas ─────────────────────────────────────────────────────────────

func _open_meeting() -> void:
	GameClock.set_time(1, 11, 0)
	if IdeaPool.is_meeting_open():
		IdeaPool.close_meeting()
	IdeaPool.start_meeting()


## Idea de `owner` escuchada por el jugador (nadie más que el confidente la conoce).
func _stolen_idea(owner: String) -> String:
	var id: String = IdeaPool.generate_idea(owner, "design")
	while IdeaPool.get_idea(id).known_by.size() > 1:
		id = IdeaPool.generate_idea(owner, "design")
	var room: String = NPCDirector.get_current_location(owner)
	if room.is_empty():
		room = NPCDirector.get_npc(owner).home_room
		NPCDirector.set_current_location(owner, room)
	IdeaPool.share_idea(id, CONFIDANT)
	EventBus.room_entered.emit(room, true)
	check(IdeaPool.acquire(id, IdeaPool.METHOD_OVERHEAR), "the player overhears %s's idea" % owner)
	return id


func _seat(ids: Array) -> void:
	for npc_id: Variant in ids:
		IdeaPresentation.seat_attendee(str(npc_id))


func _open_scene(overrides: Dictionary) -> AuroraScene:
	var scene: AuroraScene = AuroraScene.new()
	scene.instant = true
	scene.clash_overrides = overrides
	scene.closed.connect(func() -> void: _closed += 1)
	add_child(scene)
	await wait_frames(2)
	return scene


func _shows(scene: AuroraScene, text: String) -> bool:
	return scene.get_visible_texts().has(text)


func _lines_have(scene: AuroraScene, text: String) -> bool:
	return scene.get_result_lines().has(text)


func _effects(result: Dictionary, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect: Variant in result.get("effects", []):
		if effect is Dictionary and str((effect as Dictionary).get("kind", "")) == kind:
			out.append(effect)
	return out


## Continúa hasta el final (presentaciones ajenas → cierre → closed()) y retira la escena.
func _finish(scene: AuroraScene) -> void:
	var before: int = _closed
	scene.continue_scene()
	check_eq(scene.get_step(), AuroraScene.STEP_OTHERS, "Continue → the others present their ideas")
	scene.continue_scene()
	check_eq(scene.get_step(), AuroraScene.STEP_WRAP, "Continue → meeting adjourned")
	check(_shows(scene, tr("AURORA_WRAP_TITLE")), "the wrap-up panel is shown")
	scene.continue_scene()
	check(_closed == before + 1 and not IdeaPool.is_meeting_open(),
			"leaving emits closed() and the meeting is closed")
	scene.queue_free()
	await wait_frames(1)


# ─── Los tres resultados forzados ───────────────────────────────────────

func _check_win() -> void:
	_open_meeting()
	var id: String = _stolen_idea(OWNER)
	_seat([OWNER] + WITNESSES)
	var rep_before: float = NPCDirector.get_npc_reputation(OWNER)
	var scene: AuroraScene = await _open_scene(WIN)
	var idea: Idea = IdeaPool.get_idea(id)
	var owner_name: String = IdeaPool.get_npc_display_name(OWNER)
	check_eq(scene.get_step(), AuroraScene.STEP_PICK, "the scene opens on the idea picker")
	check(scene.get_player_ideas().has(idea), "the stolen idea is offered")
	check_eq(scene.owner_status(idea), "present", "the owner is flagged as present")
	check(_shows(scene, tr("AURORA_OWNER_IN_ROOM") % owner_name), "the in-the-room warning is shown")
	check(scene.get_stage().has_actor(OWNER), "the owner is seated on stage")
	check(scene.choose_idea(id) and scene.get_step() == AuroraScene.STEP_PREPARE, "idea chosen → preparation")
	var result: Dictionary = scene.choose_preparation(IdeaPresentation.PREP_NONE)
	check_eq(result.get("contest_result"), IdeaPresentation.RESULT_WIN, "forced win (75 vs 40)")
	check_eq(scene.get_result_title(), tr("AURORA_RESULT_WIN"), "win title")
	check(scene.is_clash_visible() and _shows(scene, tr("AURORA_RESULT_WIN").to_upper()),
			"the clash panel shows the stamp")
	check(_shows(scene, "75") and _shows(scene, "40"), "both credibilities are displayed")
	var merit: int = IdeaPresentation.compute_merit(idea.quality, IdeaPresentation.PREP_NONE, 60.0)
	check(_lines_have(scene, tr("AURORA_LINE_MERIT") % merit), "win line: merit +%d" % merit)
	check(_lines_have(scene, tr("AURORA_LINE_USURPER") % [owner_name, -15]), "win line: usurper −15")
	check(idea.presented and _contested.back() == [id, OWNER, "win"], "logic: the idea is spent, idea_contested win")
	check_near(rep_before - NPCDirector.get_npc_reputation(OWNER), 15.0, EPS, "logic: usurper reputation −15")
	check_eq(scene.get_stage().badge_text(OWNER), tr("AURORA_BADGE_REP") % -15, "stage: the usurper badge")
	check_eq(_presented.back(), [id, "player", merit], "idea_presented(player, merit)")
	await _finish(scene)
	check(NPCDirector.get_current_location(WITNESSES[0]) != "aurora_room", "attendees are released")


func _check_tie() -> void:
	_open_meeting()
	var id: String = _stolen_idea(OWNER)
	_seat([OWNER] + WITNESSES)
	var scene: AuroraScene = await _open_scene(TIE)
	scene.choose_idea(id)
	var result: Dictionary = scene.choose_preparation(IdeaPresentation.PREP_NONE)
	var owner_name: String = IdeaPool.get_npc_display_name(OWNER)
	check_eq(result.get("contest_result"), IdeaPresentation.RESULT_TIE, "forced tie (40 vs 45)")
	check_eq(scene.get_result_title(), tr("AURORA_RESULT_TIE"), "tie title")
	check(_lines_have(scene, tr("AURORA_LINE_NO_MERIT")), "tie line: nobody earns merit")
	check(_lines_have(scene, tr("AURORA_LINE_TIE_SUSPICION") % [10, owner_name]), "tie line: +10 suspicion each")
	check(int(result.get("merit", -1)) == 0 and IdeaPool.get_idea(id).presented, "logic: no merit, idea burnt")
	check_eq(_effects(result, "suspicion_record").size(), 2, "logic: minutes recorded for both parties")
	check_eq(scene.get_stage().badge_text("player"), tr("AURORA_BADGE_SUSPICION") % 10, "stage: suspicion badge")
	await _finish(scene)


func _check_loss() -> void:
	_open_meeting()
	var id: String = _stolen_idea(OWNER)
	for npc_id: String in BELIEVERS:
		IdeaPool.share_idea(id, npc_id)
	_seat([OWNER] + WITNESSES)
	PlayerState.modify_reputation(50.0 - PlayerState.get_reputation(), "test")
	var rep_before: float = PlayerState.get_reputation()
	var scene: AuroraScene = await _open_scene(LOSS)
	scene.choose_idea(id)
	var result: Dictionary = scene.choose_preparation(IdeaPresentation.PREP_NONE)
	var owner_name: String = IdeaPool.get_npc_display_name(OWNER)
	check_eq(result.get("contest_result"), IdeaPresentation.RESULT_LOSS, "forced loss (10 vs 100)")
	check_eq(scene.get_result_title(), tr("AURORA_RESULT_LOSS"), "loss title")
	check(_lines_have(scene, tr("AURORA_LINE_REVERTS") % owner_name), "loss line: the idea returns")
	check(_lines_have(scene, tr("AURORA_LINE_REPUTATION") % -20), "loss line: reputation −20")
	var beliefs: int = _effects(result, "belief").size()
	check(beliefs >= 3 and _lines_have(scene, tr("AURORA_LINE_BELIEF") % [beliefs, 85]),
			"loss line: %d people believe it at 85%%" % beliefs)
	check(IdeaPool.get_idea(id).acquired_by.is_empty(), "logic: the idea reverts to its owner")
	check_near(rep_before - PlayerState.get_reputation(), 20.0, EPS, "logic: player reputation −20")
	check_eq(scene.get_stage().get_actor(WITNESSES[0]).get("anim"), "suspicion", "stage: the room turns suspicious")
	await _finish(scene)


# ─── Sin choque, presentaciones ajenas y preparación ────────────────────

func _check_uncontested_and_others() -> void:
	_open_meeting()
	var id: String = _stolen_idea(ABSENT_OWNER)
	var theirs: String = IdeaPool.generate_idea(PRESENTER, "marketing")
	_seat([PRESENTER] + WITNESSES)
	var scene: AuroraScene = await _open_scene({})
	check_eq(scene.owner_status(IdeaPool.get_idea(id)), "absent", "absent owner flagged")
	scene.choose_idea(id)
	var result: Dictionary = scene.choose_preparation(IdeaPresentation.PREP_NONE)
	var merit: int = IdeaPresentation.compute_merit(IdeaPool.get_idea(id).quality,
			IdeaPresentation.PREP_NONE, PlayerState.get_reputation())
	check(not bool(result.get("contested", true)) and not scene.is_clash_visible(), "no owner, no clash")
	check_eq(scene.get_result_title(), tr("AURORA_RESULT_PRESENTED"), "presented title")
	check(_lines_have(scene, tr("AURORA_LINE_MERIT") % merit), "merit line by the formula")
	scene.continue_scene()
	var others: Array[Dictionary] = scene.get_other_presentations()
	var found: bool = others.any(func(e: Dictionary) -> bool: return e["idea_id"] == theirs and e["owner"] == PRESENTER)
	check(found, "the attending owner presents their idea when the meeting closes")
	check(IdeaPool.get_idea(theirs).presented and not IdeaPool.is_meeting_open(), "logic: close_meeting ran")
	var line: String = tr("AURORA_OTHER_LINE") % [IdeaPool.get_npc_display_name(PRESENTER),
			tr(IdeaPool.get_idea(theirs).text_key), int(others[0]["merit"]) if found else 0]
	check(_shows(scene, line), "the others panel lists the presentation")
	scene.continue_scene()
	scene.continue_scene()
	check_eq(scene.get_step(), AuroraScene.STEP_DONE, "done")
	scene.queue_free()
	await wait_frames(1)


func _check_preparation_options() -> void:
	_open_meeting()
	var id: String = _stolen_idea(ABSENT_OWNER)
	var scene: AuroraScene = await _open_scene({"player_reputation": 50.0})
	scene.choose_idea(id)
	var real: Dictionary = _option(scene, IdeaPresentation.PREP_REAL)
	check(not bool(real["available"]), "real preparation does not fit in a one-hour meeting")
	check_eq(real["note"], tr("AURORA_PREP_NO_TIME") % "12:00", "…and the card says why")
	check(scene.choose_preparation(IdeaPresentation.PREP_REAL).is_empty(), "an unavailable option is refused")
	check_near(float(_option(scene, IdeaPresentation.PREP_ASSIST)["factor"]), 0.8, EPS, "A.S.S.I.S.T. ×0.8")
	check(IdeaPool.set_preparation(id, IdeaPresentation.PREP_REAL), "prepared earlier (outside the meeting)")
	scene.back_to_pick()
	scene.choose_idea(id)
	real = _option(scene, IdeaPresentation.PREP_REAL)
	check(bool(real["ready"]) and bool(real["available"]), "an earlier real preparation is ready")
	var minutes: float = GameClock.get_total_minutes()
	var result: Dictionary = scene.choose_preparation(IdeaPresentation.PREP_REAL)
	var quality: int = IdeaPool.get_idea(id).quality
	check_eq(result.get("merit"), IdeaPresentation.compute_merit(quality, "real", 50.0), "factor 1.0 applied")
	check_near(GameClock.get_total_minutes() - minutes, 0.0, EPS, "a ready preparation costs no more time")
	scene.finish()
	scene.queue_free()
	await wait_frames(1)


func _option(scene: AuroraScene, prep: String) -> Dictionary:
	for option: Dictionary in scene.preparation_options():
		if option["id"] == prep:
			return option
	return {}


func _check_assist() -> void:
	_open_meeting()
	var id: String = _stolen_idea(ABSENT_OWNER)
	var scene: AuroraScene = await _open_scene({"player_reputation": 50.0})
	scene.assist_outcome = DutySystem.ASSIST_FAILURE
	scene.choose_idea(id)
	var result: Dictionary = scene.choose_preparation(IdeaPresentation.PREP_ASSIST)
	check_eq(_assists.back(), ["idea_presentation", "evident_failure"], "A.S.S.I.S.T. leaves its trace")
	check(scene.get_preparation_lines().has(tr("ASSIST_RESULT_EVIDENT_FAILURE")), "the failed deck is reported")
	check_eq(result.get("preparation"), IdeaPresentation.PREP_ASSIST, "presented with factor 0.8")
	check(_shows(scene, tr("ASSIST_RESULT_EVIDENT_FAILURE")), "…and shown in the result panel")
	scene.finish()
	scene.queue_free()
	await wait_frames(1)


func _check_skip() -> void:
	_open_meeting()
	_stolen_idea(OWNER)
	_seat([OWNER])
	var scene: AuroraScene = await _open_scene({})
	scene.request_close()
	check_eq(scene.get_step(), AuroraScene.STEP_OTHERS, "Esc at the picker: just nod along")
	check(scene.get_result().is_empty(), "nothing presented")
	scene.continue_scene()
	check(_shows(scene, tr("AURORA_WRAP_SILENT")), "the wrap-up notes your silence")
	scene.continue_scene()
	scene.queue_free()
	await wait_frames(1)


func _check_no_meeting() -> void:
	if IdeaPool.is_meeting_open():
		IdeaPool.close_meeting()
	var before: int = _closed
	var scene: AuroraScene = await _open_scene({})
	check(_shows(scene, tr("AURORA_NO_MEETING")), "no meeting: the room says so")
	scene.request_close()
	check_eq(_closed, before + 1, "and the scene can be left")
	scene.queue_free()
	await wait_frames(1)
