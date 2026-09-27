# aurora_scene_case.gd — Cuerpo de test_aurora_scene: la escena Aurora (§11.2, PASO 24) con los tres resultados forzados del choque muestra el texto correcto y llama a la lógica; barras de credibilidad, Esc por puntos de lectura, ensayo previo (preparación real alcanzable), la ventana modal de UIRoot, la maquetación con seis ideas y texto grande, y el plató sin repintados por fotograma.
# PROPIETARIO DE: nada.
# ESCUCHA: idea_contested, idea_presented, assist_used (conexiones del caso).
extends TestCase

const OWNER := "npc_claudia_reeves"
const CONFIDANT := "npc_nate_brackley"
const WITNESSES: Array[String] = ["npc_debbie_foyle", "npc_george_penn"]
const BELIEVERS: Array[String] = ["npc_sonia_vail", "npc_ray_cudmore"]
const PRESENTER := "npc_tom_iverson"
const ABSENT_OWNER := "npc_amelia_cole"
const SELLERS: Array[String] = ["npc_bernard_lasker", "npc_connie_marks", "npc_ludmila_petrova",
	"npc_tom_iverson", "npc_sonia_vail"]
const EPS := 0.0001
const WIN: Dictionary = {"player_reputation": 60.0, "player_suspicion": 0.0, "allies": 1,
	"accuser_reputation": 40.0, "believers": 0}
const TIE: Dictionary = {"player_reputation": 50.0, "player_suspicion": 20.0, "allies": 0,
	"accuser_reputation": 45.0, "believers": 0}
const LOSS: Dictionary = {"player_reputation": 30.0, "player_suspicion": 40.0, "allies": 0,
	"accuser_reputation": 40.0}
const NO_CLASH: Dictionary = {"player_reputation": 50.0, "accuser_present": false}
const PHONE_SCREEN := Vector2(2400, 1080)
const DESKTOP_SCREEN := Vector2(1920, 1080)
const IDLE_FRAMES := 12

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
	await _check_escape_beats()
	await _check_rehearsal()
	await _check_uiroot_modal()
	await _check_layout(PHONE_SCREEN, true)
	await _check_layout(DESKTOP_SCREEN, false)
	await _check_idle_stage()
	_check_timeline()
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


func _bought_idea(seller: String) -> String:
	var id: String = IdeaPool.generate_idea(seller, "sales")
	IdeaPool.acquire(id, IdeaPool.METHOD_PURCHASE)
	return id


func _seat(ids: Array) -> void:
	for npc_id: Variant in ids:
		IdeaPresentation.seat_attendee(str(npc_id))


func _open_scene(overrides: Dictionary, instant: bool = true) -> AuroraScene:
	var scene: AuroraScene = AuroraScene.new()
	scene.instant = instant
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


func _button(scene: Node, text: String) -> Button:
	for node: Node in scene.find_children("*", "Button", true, false):
		if (node as Button).text == text and (node as Button).is_visible_in_tree():
			return node as Button
	return null


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
	_check_bars(scene, result)
	var merit: int = IdeaPresentation.compute_merit(idea.quality, IdeaPresentation.PREP_NONE, 60.0)
	check(_lines_have(scene, tr("AURORA_LINE_MERIT") % merit), "win line: merit +%d" % merit)
	check(_lines_have(scene, tr("AURORA_LINE_USURPER") % [owner_name, -15]), "win line: usurper −15")
	check(idea.presented and _contested.back() == [id, OWNER, "win"], "logic: the idea is spent, idea_contested win")
	check_near(rep_before - NPCDirector.get_npc_reputation(OWNER), 15.0, EPS, "logic: usurper reputation −15")
	check_eq(scene.get_stage().badge_text(OWNER), tr("AURORA_BADGE_REP") % -15, "stage: the usurper badge")
	check_eq(_presented.back(), [id, "player", merit], "idea_presented(player, merit)")
	await _finish(scene)
	check(NPCDirector.get_current_location(WITNESSES[0]) != "aurora_room", "attendees are released")


## Las dos barras de credibilidad: una por contendiente, con el total de la fórmula.
func _check_bars(scene: AuroraScene, result: Dictionary) -> void:
	var bars: Array[AuroraScene.CredBar] = scene.get_credibility_bars()
	check_eq(bars.size(), 2, "two credibility bars")
	if bars.size() == 2:
		check_near(bars[0].total, float(result["accuser_credibility"]), EPS, "accuser bar = accuser credibility")
		check_near(bars[1].total, float(result["player_credibility"]), EPS, "player bar = player credibility")
		check(bars[0].progress >= 1.0 and bars[1].progress >= 1.0, "the bars have finished growing")


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
	_seat([OWNER] + WITNESSES + [BELIEVERS[0]])
	PlayerState.modify_reputation(50.0 - PlayerState.get_reputation(), "test")
	var rep_before: float = PlayerState.get_reputation()
	var scene: AuroraScene = await _open_scene(LOSS)
	scene.choose_idea(id)
	var result: Dictionary = scene.choose_preparation(IdeaPresentation.PREP_NONE)
	var owner_name: String = IdeaPool.get_npc_display_name(OWNER)
	check_eq(result.get("contest_result"), IdeaPresentation.RESULT_LOSS, "forced loss")
	check_eq(scene.get_result_title(), tr("AURORA_RESULT_LOSS"), "loss title")
	check(_lines_have(scene, tr("AURORA_LINE_REVERTS") % owner_name), "loss line: the idea returns")
	check(_lines_have(scene, tr("AURORA_LINE_REPUTATION") % -20), "loss line: reputation −20")
	var beliefs: int = _effects(result, "belief").size()
	check(beliefs >= 3 and _lines_have(scene, tr("AURORA_LINE_BELIEF") % [beliefs, 85]),
			"loss line: %d people believe it at 85%%" % beliefs)
	check(IdeaPool.get_idea(id).acquired_by.is_empty(), "logic: the idea reverts to its owner")
	check_near(rep_before - PlayerState.get_reputation(), 20.0, EPS, "logic: player reputation −20")
	check_eq(scene.get_stage().get_actor(WITNESSES[0]).get("anim"), "suspicion", "stage: the room turns suspicious")
	_check_believer_badges(scene, id, int(result.get("believers", 0)))
	await _finish(scene)


## «Lo sabe» solo sobre los presentes que conocen la idea; el desglose dice cuántos hay en total.
func _check_believer_badges(scene: AuroraScene, id: String, believers: int) -> void:
	var here: int = 0
	for npc_id: String in scene.get_attendees():
		if npc_id != OWNER and IdeaPool.get_idea(id).known_by.has(npc_id):
			here += 1
	check(believers > here and here >= 1, "more people know it (%d) than are in the room (%d)" % [believers, here])
	var line: String = tr("AURORA_CLASH_BELIEVERS") % [believers, here,
			believers * roundi(Database.get_balance_float(IdeaPresentation.B_PER_BELIEVER))]
	check(_shows(scene, line), "the breakdown says how many know and how many are here")


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
	check_eq(real["note"], tr("AURORA_PREP_NO_TIME") % [60, "12:00"], "…and the card points to the rehearsal")
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
	check(scene.is_rehearsal(), "no meeting: the empty room is for rehearsing")
	check(_shows(scene, tr("AURORA_NO_MEETING")), "no meeting: the room says so")
	scene.request_close()
	check_eq(_closed, before + 1, "and the scene can be left")
	scene.queue_free()
	await wait_frames(1)


# ─── Esc por puntos de lectura ──────────────────────────────────────────

## Sin modo instantáneo: cada Esc adelanta hasta el siguiente golpe que hay que leer (acusación →
## choque → veredicto), nunca se los salta todos de una vez.
func _check_escape_beats() -> void:
	_open_meeting()
	var id: String = _stolen_idea(OWNER)
	_seat([OWNER] + WITNESSES)
	var scene: AuroraScene = await _open_scene(WIN, false)
	scene.request_close()
	check_eq(scene.get_step(), AuroraScene.STEP_PICK, "Esc during the chair's opening line → the picker")
	scene.choose_idea(id)
	scene.choose_preparation(IdeaPresentation.PREP_NONE)
	scene.request_close()
	var accusations: Array[String] = []
	for key: String in AuroraScene.ACCUSE_KEYS:
		accusations.append(tr(key))
	check(accusations.has(scene.get_stage().bubble_text(OWNER)) and not scene.is_clash_visible(),
			"Esc during the walk stops at the accusation")
	scene.request_close()
	check(scene.is_clash_visible() and _button(scene, tr("AURORA_CONTINUE")) == null,
			"next Esc: the clash (bars growing), no verdict yet")
	scene.request_close()
	check(_shows(scene, tr("AURORA_RESULT_WIN").to_upper()) and _button(scene, tr("AURORA_CONTINUE")) != null,
			"next Esc: the verdict and its consequences")
	scene.finish()
	scene.queue_free()
	await wait_frames(1)


# ─── Ensayo previo: la preparación real (×1,0) es alcanzable ────────────

func _check_rehearsal() -> void:
	if IdeaPool.is_meeting_open():
		IdeaPool.close_meeting()
	var day: int = IdeaPool.get_next_meeting_day(GameClock.get_day() + 1)
	GameClock.set_time(day, IdeaPool.get_meeting_schedule()["hour"] - 1, 30)
	var id: String = _stolen_idea(ABSENT_OWNER)
	var scene: AuroraScene = await _open_scene(NO_CLASH)
	check_eq(scene.get_step(), AuroraScene.STEP_REHEARSE, "before the meeting: rehearsal in the empty room")
	check(_shows(scene, tr("AURORA_REHEARSE_TITLE")), "the rehearsal panel is shown")
	var before: float = GameClock.get_total_minutes()
	var prep: Dictionary = scene.rehearse(id, IdeaPresentation.PREP_REAL)
	var minutes: float = Database.get_balance_float(IdeaPresentation.B_REAL_PREP_MINUTES)
	check(bool(prep.get("ok", false)) and IdeaPool.get_preparation(id) == IdeaPresentation.PREP_REAL,
			"logic: IdeaPresentation.prepare_detailed(real)")
	check_near(GameClock.get_total_minutes() - before, minutes, EPS, "real preparation costs its minutes")
	check(scene.rehearse(id, IdeaPresentation.PREP_REAL).is_empty(), "no need to rehearse twice")
	check(IdeaPool.is_meeting_open() and _shows(scene, tr("AURORA_TAKE_SEAT")),
			"the rehearsal ran into the weekly meeting: take your seat")
	check(scene.take_seat() and scene.get_step() == AuroraScene.STEP_PICK, "…into the meeting")
	scene.choose_idea(id)
	var real: Dictionary = _option(scene, IdeaPresentation.PREP_REAL)
	check(bool(real["ready"]) and bool(real["available"]), "the rehearsed idea is ready at ×1.0")
	before = GameClock.get_total_minutes()
	var result: Dictionary = scene.choose_preparation(IdeaPresentation.PREP_REAL)
	check_eq(result.get("merit"), IdeaPresentation.compute_merit(IdeaPool.get_idea(id).quality,
			IdeaPresentation.PREP_REAL, 50.0), "presented with the real factor 1.0")
	check_near(GameClock.get_total_minutes() - before, 0.0, EPS, "no extra time at the meeting")
	scene.finish()
	scene.queue_free()
	await wait_frames(1)


# ─── Ventana modal de UIRoot ────────────────────────────────────────────

func _esc(ui: UIRoot) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "pause_menu"
	ev.pressed = true
	ui._unhandled_input(ev)


func _check_uiroot_modal() -> void:
	var ui: UIRoot = UIRoot.new()
	add_child(ui)
	await wait_frames(2)
	var was_paused: bool = GameClock.is_paused()
	GameClock.resume()
	_open_meeting()
	_stolen_idea(OWNER)
	_seat([OWNER] + WITNESSES)
	var scene: AuroraScene = AuroraScene.open(ui)
	await wait_frames(2)
	check(ui.get_top_modal() == scene and GameClock.is_paused() and ui.is_clock_paused_by_ui(),
			"AuroraScene.open(UIRoot): modal, clock paused")
	scene.fast_forward()
	_esc(ui)
	check_eq(scene.get_step(), AuroraScene.STEP_OTHERS, "UIRoot routes Esc to request_close (nod along)")
	check(not IdeaPool.is_meeting_open(), "the meeting was closed by the scene")
	_open_meeting()
	_seat([OWNER] + WITNESSES)
	var second: AuroraScene = AuroraScene.open(ui)
	await wait_frames(2)
	second.fast_forward()
	var attendees: Array[String] = second.get_attendees()
	ui.close_modal()
	ui.close_modal()
	await wait_frames(2)
	check(not ui.has_modal() and not GameClock.is_paused(), "closing the modals restores the clock")
	if was_paused:
		GameClock.pause()
	check(not IdeaPool.is_meeting_open(), "close_modal → cancel() closes the meeting")
	var band: String = GameClock.get_current_band()
	var released: bool = attendees.all(func(npc_id: String) -> bool:
		return str(NPCDirector.get_npc(npc_id).schedule_override.get(band, "")).is_empty())
	check(not attendees.is_empty() and released, "…and releases the attendees")
	ui.queue_free()
	await wait_frames(1)


# ─── Maquetación: seis ideas con texto grande (móvil y escritorio) ──────

func _check_layout(screen: Vector2, touch: bool) -> void:
	_open_meeting()
	_stolen_idea(OWNER)
	for seller: String in SELLERS:
		_bought_idea(seller)
	_seat([OWNER] + WITNESSES)
	var saved: Array = [UITheme.touch_scale_active, UITheme.current_text_size]
	UITheme.touch_scale_active = touch
	UITheme.current_text_size = UITheme.TEXT_LARGE
	var host: Control = Control.new()
	host.size = screen
	add_child(host)
	var scene: AuroraScene = AuroraScene.new()
	scene.instant = true
	host.add_child(scene)
	await wait_frames(6)
	_check_panel_fits(scene, Rect2(Vector2.ZERO, screen), "%dx%d" % [int(screen.x), int(screen.y)])
	scene.finish()
	host.queue_free()
	UITheme.touch_scale_active = saved[0]
	UITheme.current_text_size = saved[1]
	await wait_frames(1)


func _check_panel_fits(scene: AuroraScene, screen: Rect2, label: String) -> void:
	var dock: SceneStage.Dock = scene.get_dock()
	var panel: Rect2 = dock.panel.get_global_rect()
	check_eq(scene.get_player_ideas().size(), Database.get_balance_int(AuroraScene.B_MAX_IDEAS),
			"%s: the picker lists the maximum of ideas" % label)
	check(screen.encloses(panel), "%s: the idea panel stays on screen (%s)" % [label, panel])
	var skip: Button = _button(scene, tr("AURORA_SKIP"))
	check(skip != null and screen.encloses(skip.get_global_rect()), "%s: 'Just nod along' is reachable" % label)
	check(dock.scroll.has_more_below(), "%s: the idea list scrolls instead of overflowing" % label)
	check(not panel.intersects(scene.get_stage().safe_rect()), "%s: the room is framed beside the panel" % label)


# ─── Rendimiento del plató y línea de tiempo ────────────────────────────

## Con la escena quieta, el fondo no se repinta cada fotograma (solo actores y LED).
func _check_idle_stage() -> void:
	_open_meeting()
	_stolen_idea(OWNER)
	_seat([OWNER] + WITNESSES)
	var scene: AuroraScene = await _open_scene({})
	await wait_frames(4)
	var stage: SceneStage = scene.get_stage()
	var paints: int = stage.back_paint_count()
	await wait_frames(IDLE_FRAMES)
	check_eq(stage.back_paint_count(), paints, "idle stage: the backdrop is not repainted every frame")
	scene.finish()
	scene.queue_free()
	await wait_frames(1)


func _check_timeline() -> void:
	var calls: Array = []
	var timeline: SceneStage.Timeline = SceneStage.Timeline.new()
	timeline.then(5.0, func() -> void: calls.append("late"))
	timeline.tick(1.0)
	timeline.clear()
	timeline.then(0.0, func() -> void: calls.append("now"))
	timeline.tick(0.01)
	check_eq(calls, ["now"], "Timeline.clear() resets the schedule (no leftover delay)")
	timeline.then(1.0, func() -> void: calls.append("a"))
	timeline.then(1.0, func() -> void: calls.append("hold"), true)
	timeline.then(1.0, func() -> void: calls.append("b"))
	timeline.skip()
	check_eq(calls, ["now", "a", "hold"], "Timeline.skip() stops at the next hold beat")
	timeline.flush()
	check_eq(calls, ["now", "a", "hold", "b"], "Timeline.flush() runs the rest")
