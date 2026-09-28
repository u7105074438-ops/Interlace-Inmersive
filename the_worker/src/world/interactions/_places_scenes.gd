# _places_scenes.gd — Las salas con escena: atril Aurora (§11.2), mesa de interrogatorios (§12.5), estrado de resultados (§9.5), mesa del consejo (§22.14), notaría (§11.8) y la pantalla de formación (§13.8).
# PROPIETARIO DE: nada (reuniones de IdeaPool, casos de Security, trimestre de Market, sillas de Company, misión de Endgame; «ya hoy», banderas places.*).
# ESCUCHA: nada.
class_name PlacesScenes
extends RefCounted

## · "aurora_podium": con la reunión semanal abierta (IdeaPool.is_meeting_open) abre AuroraScene; sin
##   ella dice cuándo es la próxima y ofrece ensayar (la misma escena, paso de ensayo).
## · "interrogation_table": con una citación vigente (PlacesKeeper.due_summons) el jugador puede
##   sentarse y empezar ya (InterrogationScene); si no, la sala vacía.
## · "results_stage": desde lugares.resultados.rango_minimo (R28) abre ResultsPresentationScreen del
##   trimestre (el propio estrado solo deja presentar el día de resultados); por debajo, quién sube.
## · "board_table": con voto (puestos lugares.consejo.ocupaciones_voto o paquete accionarial:
##   Market.get_board_votes) una votación por jornada: apoyar tu ascenso (mérito), votar la expulsión
##   de un directivo (probabilidad base + por voto; si falla, agravio) o abstenerse. Cumple el deber
##   de voto del día (subtipo lugares.consejo.subtipo_deber).
## · "notary_desk": antes de la revelación, una notaría; después, la previsión del notario y la
##   formalización confirmada (Endgame.request_notarisation: firma o plazo de comprobación).
## · "training_screen": training_hook (Callable(item, player, ctx), lo pone el tutorial) o el vídeo
##   corporativo por defecto (lugares.minutos.video_formacion).

const T_AURORA := "aurora_podium"
const T_INTERROGATION := "interrogation_table"
const T_RESULTS := "results_stage"
const T_BOARD := "board_table"
const T_NOTARY := "notary_desk"
const T_TRAINING := "training_screen"
const TYPES: Array[String] = [T_AURORA, T_INTERROGATION, T_RESULTS, T_BOARD, T_NOTARY, T_TRAINING]
const BOARD_KEY := "board_vote"
const MERIT_SOURCE := "board_vote"
const GRIEVANCE_BOARD := "board_vote"
const CAUSE_EXPULSION := "expulsion"
const METHOD_HONEST := "honest"
const STATUS_WAITING := "waiting"
const NOTARY_BODY_FORMAT := "PLACES_NOTARY_BODY_%s"
const TRAINING_LINES: Array[String] = ["PLACES_TRAINING_LINE_1", "PLACES_TRAINING_LINE_2", "PLACES_TRAINING_LINE_3"]
const OPT_PROMOTE := 0
const OPT_EXPEL := 1
const OPT_ABSTAIN := 2
const B_RESULTS_RANK := "lugares.resultados.rango_minimo"
const B_VOTERS := "lugares.consejo.ocupaciones_voto"
const B_DUTY_SUBTYPE := "lugares.consejo.subtipo_deber"
const B_DUTY_QUALITY := "lugares.consejo.calidad_deber"
const B_MERIT := "lugares.consejo.merito"
const B_TARGET_TIER := "lugares.consejo.escalon_min_objetivo"
const B_MAX_TARGETS := "lugares.consejo.max_objetivos"
const B_PROB_BASE := "lugares.consejo.prob_base"
const B_PROB_VOTE := "lugares.consejo.prob_por_voto"
const B_PROB_MAX := "lugares.consejo.prob_max"
const B_GRIEVANCE := "lugares.consejo.gravedad_agravio"
const ANIM_SIT := "sit"
const PERCENT := 100.0
const ANIM_POINT := "point"

## Tutorial (§13.8): func(item: Interactable, player: Node, ctx: Dictionary) -> void. Sin él, el
## vídeo corporativo por defecto.
static var training_hook: Callable = Callable()


static func handles(kind: String) -> bool:
	return TYPES.has(kind)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		T_AURORA:
			await aurora(ctx)
		T_INTERROGATION:
			await interrogation(item, ctx)
		T_RESULTS:
			await results(ctx)
		T_BOARD:
			await board(player, ctx)
		T_NOTARY:
			await notary(ctx)
		T_TRAINING:
			await training(item, player, ctx)


# ─── Aurora ───────────────────────────────────────────────────

static func aurora(ctx: Dictionary) -> void:
	var view: UIRoot = PlacesKit.ui(ctx)
	if view == null:
		return
	if IdeaPool.is_meeting_open():
		await PlacesKit.await_closed(AuroraScene.open(view))
		return
	var schedule: Dictionary = IdeaPool.get_meeting_schedule()
	var args: Array = [next_meeting_day(), UITheme.format_hour(int(schedule.get("hour", 0)))]
	var index: int = await PlacesKit.choose(ctx, "PLACES_AURORA_TITLE", "PLACES_AURORA_BODY",
			["PLACES_AURORA_REHEARSE", "PLACES_CLOSE"], args)
	if index == 0:
		await PlacesKit.await_closed(AuroraScene.open(view))


## Jornada de la próxima reunión Aurora (la de hoy si aún no ha terminado).
static func next_meeting_day() -> int:
	var today: int = GameClock.get_day()
	var day: int = IdeaPool.get_next_meeting_day(today)
	var schedule: Dictionary = IdeaPool.get_meeting_schedule()
	var over: int = int(schedule.get("hour", 0)) + int(schedule.get("duration_hours", 0))
	if day == today and GameClock.get_hour() >= over:
		day = IdeaPool.get_next_meeting_day(today + 1)
	return day


# ─── Interrogatorio ───────────────────────────────────────────

static func interrogation(item: Interactable, ctx: Dictionary) -> void:
	var view: UIRoot = PlacesKit.ui(ctx)
	var case_id: String = PlacesKeeper.due_summons(PlacesKit.tree_of(item))
	if case_id.is_empty() or view == null:
		PlacesKit.say(ctx, "PLACES_INTERROGATION_EMPTY")
		return
	var who: String = PlacesKit.npc_name(Security.get_interrogator(case_id))
	var index: int = await PlacesKit.choose(ctx, "PLACES_INTERROGATION_TITLE", "PLACES_INTERROGATION_BODY",
			["PLACES_INTERROGATION_SIT", "PLACES_NOT_NOW"], [who])
	if index == 0:
		await PlacesKit.await_closed(InterrogationScene.open(view, case_id))


# ─── Resultados trimestrales ──────────────────────────────────

static func results(ctx: Dictionary) -> void:
	var view: UIRoot = PlacesKit.ui(ctx)
	var rank: int = Database.get_balance_int(B_RESULTS_RANK)
	if PlayerState.get_rank() < rank or view == null:
		PlacesKit.say(ctx, "PLACES_RESULTS_RANK", [rank, Market.get_presentation_day()])
		return
	await PlacesKit.await_closed(ResultsPresentationScreen.open(view, GameClock.get_quarter()))


# ─── Consejo ──────────────────────────────────────────────────

static func can_vote() -> bool:
	return PlacesKit.bal_strings(B_VOTERS).has(PlayerState.get_occupation_id()) or Market.get_board_votes() > 0


static func board(player: Node, ctx: Dictionary) -> void:
	if not can_vote():
		PlacesKit.say(ctx, "PLACES_BOARD_NO_SEAT")
		return
	if PlacesKit.used_today(BOARD_KEY):
		PlacesKit.say(ctx, "PLACES_BOARD_ALREADY")
		return
	var votes: int = maxi(Market.get_board_votes(), 1)
	var options: Array = ["PLACES_BOARD_PROMOTE", "PLACES_BOARD_EXPEL", "PLACES_BOARD_ABSTAIN", "PLACES_CLOSE"]
	var index: int = await PlacesKit.choose(ctx, "PLACES_BOARD_TITLE", "PLACES_BOARD_BODY", options, [votes])
	match index:
		OPT_PROMOTE:
			Company.register_merit(MERIT_SOURCE, Database.get_balance_int(B_MERIT))
			PlacesKit.good(ctx, "PLACES_BOARD_PROMOTE_DONE")
		OPT_EXPEL:
			if not await expel_vote(player, ctx, votes):
				return
		OPT_ABSTAIN:
			PlacesKit.say(ctx, "PLACES_BOARD_ABSTAINED")
		_:
			return
	cast_vote(ctx)


## El voto cuenta como el deber del día y cuesta su tiempo de sesión.
static func cast_vote(ctx: Dictionary) -> void:
	PlacesKit.mark_today(BOARD_KEY)
	PlacesKit.spend_minutes("consejo")
	var subtype: String = str(Database.get_balance(B_DUTY_SUBTYPE))
	for duty: Dictionary in PlayerState.get_pending_duties():
		if str(duty.get(PlayerStateSystem.D_SUBTYPE, "")) == subtype:
			PlayerState.complete_duty(str(duty[PlayerStateSystem.D_ID]), Database.get_balance_float(B_DUTY_QUALITY), METHOD_HONEST)
			PlacesKit.good(ctx, "PLACES_BOARD_DUTY_DONE")
			return


## Directivos expulsables (escalón ≥ lugares.consejo.escalon_min_objetivo), de mayor a menor.
static func expel_targets() -> Array[String]:
	var found: Array[NPCRuntime] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.is_active(npc.id) and npc.tier >= Database.get_balance_int(B_TARGET_TIER):
			found.append(npc)
	found.sort_custom(func(a: NPCRuntime, b: NPCRuntime) -> bool: return a.tier > b.tier or (a.tier == b.tier and a.id < b.id))
	var out: Array[String] = []
	for npc: NPCRuntime in found.slice(0, Database.get_balance_int(B_MAX_TARGETS)):
		out.append(npc.id)
	return out


static func expel_chance(votes: int) -> float:
	return clampf(Database.get_balance_float(B_PROB_BASE) + Database.get_balance_float(B_PROB_VOTE) * votes,
			0.0, Database.get_balance_float(B_PROB_MAX))


## Votar la expulsión de un directivo. true si se votó (salga o no).
static func expel_vote(player: Node, ctx: Dictionary, votes: int) -> bool:
	var targets: Array[String] = expel_targets()
	var options: Array = []
	for npc_id: String in targets:
		options.append({"text_key": "PLACES_BOARD_TARGET", "args": [PlacesKit.npc_name(npc_id)]})
	options.append("PLACES_CLOSE")
	var chance: int = roundi(expel_chance(votes) * PERCENT)
	var index: int = await PlacesKit.choose(ctx, "PLACES_BOARD_TITLE", "PLACES_BOARD_EXPEL_BODY", options, [chance])
	if index < 0 or index >= targets.size():
		return false
	var target: String = targets[index]
	if not await PlacesKit.confirm(ctx, "PLACES_BOARD_TITLE", "PLACES_BOARD_EXPEL_CONFIRM", "PLACES_BOARD_EXPEL_GO",
			[PlacesKit.npc_name(target), chance]):
		return false
	PlacesKit.play(player, ANIM_POINT)
	resolve_expulsion(ctx, target, votes)
	return true


static func resolve_expulsion(ctx: Dictionary, target: String, votes: int) -> void:
	var name: String = PlacesKit.npc_name(target)
	if PlacesKit.rng(BOARD_KEY + target).randf() < expel_chance(votes):
		NPCDirector.remove_npc(target, CAUSE_EXPULSION)
		PlacesKit.good(ctx, "PLACES_BOARD_EXPELLED", [name])
		return
	NPCDirector.add_grievance(target, GRIEVANCE_BOARD, Database.get_balance_int(B_GRIEVANCE))
	PlacesKit.bad(ctx, "PLACES_BOARD_EXPEL_FAILED", [name])


# ─── Notaría ──────────────────────────────────────────────────

static func notary(ctx: Dictionary) -> void:
	if not Endgame.is_objective_revealed():
		PlacesKit.say(ctx, "PLACES_NOTARY_IDLE")
		return
	if Endgame.is_verification_pending():
		PlacesKit.say(ctx, "PLACES_NOTARY_PENDING", [Endgame.get_verification_days_left()], ToastStack.KIND_WARN)
		return
	var body: String = NOTARY_BODY_FORMAT % Endgame.preview_notary_decision().to_upper()
	var index: int = await PlacesKit.choose(ctx, "PLACES_NOTARY_TITLE", body, ["PLACES_NOTARY_REQUEST", "PLACES_CLOSE"],
			[Endgame.get_verification_days()])
	if index != 0 or not await PlacesKit.confirm(ctx, "PLACES_NOTARY_TITLE", "PLACES_NOTARY_CONFIRM", "PLACES_NOTARY_GO"):
		return
	PlacesKit.spend_minutes("notaria")
	var result: Dictionary = Endgame.request_notarisation()
	if not bool(result.get("ok", false)):
		PlacesKit.refuse(ctx, Endgame.reason_key(str(result.get("reason", ""))))
	elif str(result.get("outcome", "")) == Endgame.NOTARY_VERIFY:
		PlacesKit.say(ctx, "PLACES_NOTARY_VERIFYING", [Endgame.get_verification_days_left()], ToastStack.KIND_WARN)
	else:
		PlacesKit.good(ctx, "PLACES_NOTARY_SIGNED")


# ─── Formación ────────────────────────────────────────────────

static func training(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if training_hook.is_valid():
		await training_hook.call(item, player, ctx)
		return
	PlacesKit.play(player, ANIM_SIT)
	PlacesKit.spend_minutes("video_formacion")
	var lines: Array[String] = []
	for key: String in TRAINING_LINES:
		lines.append(PlacesKit.tr_key(key))
	await PlacesKit.show_lines(ctx, "PLACES_TRAINING_TITLE", lines)
	PlacesKit.play(player, "")
	PlacesKit.say(ctx, "PLACES_TRAINING_DONE")
