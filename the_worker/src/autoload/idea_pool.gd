# idea_pool.gd — Las ideas vivas del mundo: generación, señalización, adquisición, reunión Aurora y caducidad.
# PROPIETARIO DE: las ideas vivas (§11.1, §19.11), su RNG, las señales de generación visibles, la preparación declarada, los propietarios desaparecidos y la reunión semanal Aurora (§11.2).
# ESCUCHA: day_advanced, hour_passed, npc_removed.
class_name IdeaPoolSystem
extends Node

## Manual §11.1, §11.2, §19.11, §32.3, PASO 23-24; BUILD_NOTES §2, §6, §12-§13.
## Regla de comunicación: este autoload no llama a métodos mutadores de otros autoloads. Deja
## rastros emitiendo señales (player_seen_partially, crime_committed) y la escena Aurora aplica las
## consecuencias del choque mediante IdeaPresentation (manos).
## GENERACIÓN (§11.1): al empezar cada jornada, cada personaje vivo con ambición ≥
##   ideas.ambicion_minima_generacion tira p = (0,12 + 0,004 × ambición) × modificador de Company
##   (get_idea_generation_modifier, si existe). Si sale, la idea nace a una hora laborable aleatoria
##   [ideas.hora_generacion_min, _max]: idea_generated + señal visible (get_signalling_npcs) con uno
##   de tres comportamientos: "agitation", "to_computer" o "tell_colleague" (comunica la idea a un
##   confidente, que pasa a known_by: es el momento en que se puede escuchar).
##   calidad = 20 + aleatorio(0, 80) proyectada sobre el rango de la plantilla del departamento
##   (o special.idea_quality_range del personaje nominado); frescura = aleatorio(3, 10).
## CADUCIDAD: cada jornada la frescura baja 1; a 0 la idea se retira (idea_expired si no se había
##   presentado). Si el propietario la presenta antes que el jugador, presented = true: no vale nada.
## ADQUISICIÓN (§11.1): overhear → player_seen_partially(propietario) (sabe que estabas presente);
##   steal_file → crime_committed("file_copied") (registro digital); inherit → solo si el
##   propietario ya no está (npc_removed); purchase → el propietario lo sabe todo (sigue en known_by,
##   no acusa); gifted → sin rastro.
## AURORA (§11.2): reunión semanal en aurora_room el día ideas.aurora_dia_semana (0 = primer día de
##   la semana; jornada 1 = día 0) a ideas.aurora_hora durante ideas.aurora_duracion_horas.
##   Al abrirse: aurora_meeting_started + asistencia de los propietarios con ideas vivas
##   (p = ambición × ideas.prob_presentar_por_punto_ambicion). Durante la reunión el jugador presenta
##   (present / IdeaPresentation.present_player_idea). Al cerrarse, los propietarios asistentes
##   presentan sus ideas pendientes (idea_presented con presenter = propietario).

const PLAYER_ID := "player"
const AURORA_ROOM := "aurora_room"
const METHOD_OVERHEAR := "overhear"
const METHOD_STEAL_FILE := "steal_file"
const METHOD_INHERIT := "inherit"
const METHOD_PURCHASE := "purchase"
const METHOD_GIFTED := "gifted"
const METHODS: Array[String] = [
	METHOD_OVERHEAR, METHOD_STEAL_FILE, METHOD_INHERIT, METHOD_PURCHASE, METHOD_GIFTED,
]
## Vías con consentimiento del propietario: no acusa en la sala Aurora.
const CONSENTED_METHODS: Array[String] = [METHOD_PURCHASE, METHOD_GIFTED]
const STATUS_OK := "ok"
const STATUS_NOT_FOUND := "not_found"
const STATUS_NOT_HELD := "not_held"
const STATUS_ALREADY_PRESENTED := "already_presented"
const STATUS_EXPIRED := "expired"
const STATUS_NO_MEETING := "no_meeting"
const BEHAVIOUR_AGITATION := "agitation"
const BEHAVIOUR_TO_COMPUTER := "to_computer"
const BEHAVIOUR_TELL := "tell_colleague"
const CRIME_FILE_COPIED := "file_copied"
const TRAIT_AMBITION := "ambition"
const KEY_SPECIAL := "special"
const KEY_QUALITY_RANGE := "idea_quality_range"
const KEY_DEPARTMENT := "department"
const KEY_METHOD_ID := "id"
const KEY_TRACE := "leaves_trace"
const ID_FORMAT := "idea_%d"
const MEETING_ID_FORMAT := "aurora_d%d"
const HOUR_FORMAT := "%02d:00"
const RNG_SALT := "idea_pool"
const SAVE_CONTEXT := "save/idea_pool"
const NOTE_CATEGORY := "ideas"
const NOTE_MEETING_TODAY := "NOTE_AURORA_MEETING_TODAY"
const NOTE_OWNER_PRESENTED := "NOTE_IDEA_OWNER_PRESENTED"
const COMPANY_MODIFIER_GETTER := "get_idea_generation_modifier"

const B_PROB_BASE := "ideas.prob_generacion_diaria_base"
const B_PROB_PER_AMBITION := "ideas.mod_prob_por_ambicion"
const B_MIN_AMBITION := "ideas.ambicion_minima_generacion"
const B_MAX_LIVE := "ideas.max_ideas_vivas_por_personaje"
const B_FRESH_MIN := "ideas.frescura_min_jornadas"
const B_FRESH_MAX := "ideas.frescura_max_jornadas"
const B_QUALITY_MIN := "ideas.calidad_min"
const B_QUALITY_MAX := "ideas.calidad_max"
const B_HOUR_MIN := "ideas.hora_generacion_min"
const B_HOUR_MAX := "ideas.hora_generacion_max"
const B_SIGNAL_HOURS := "ideas.horas_senal"
const B_BEHAVIOUR_WEIGHTS := "ideas.pesos_comportamiento_senal"
const B_CONFIDANT_STRENGTH := "ideas.fuerza_minima_confidente"
const B_TEMPLATE_BY_DEPT := "ideas.plantilla_por_departamento"
const B_TEMPLATE_BY_OCC := "ideas.plantilla_por_ocupacion"
const B_AURORA_WEEKDAY := "ideas.aurora_dia_semana"
const B_AURORA_HOUR := "ideas.aurora_hora"
const B_AURORA_HOURS := "ideas.aurora_duracion_horas"
const B_PRESENT_PER_AMBITION := "ideas.prob_presentar_por_punto_ambicion"
const B_DAYS_PER_WEEK := "tiempo.jornadas_por_semana"
const B_PARTIAL_CERTAINTY := "creencias.certeza_parcial"

## id → Idea viva (orden de inserción = orden de generación).
var _ideas: Dictionary[String, Idea] = {}
var _next_id: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## npc_id → {npc_id, idea_id, behaviour, confidant, day, until_hour}.
var _signals: Dictionary[String, Dictionary] = {}
## npc_id → hora de hoy a la que nacerá su idea.
var _pending_generation: Dictionary[String, int] = {}
## npc_id → causa (expulsión o eliminación): sus ideas quedan sin reclamar.
var _removed_owners: Dictionary[String, String] = {}
## idea_id → "none" | "assist" | "real".
var _preparation: Dictionary[String, String] = {}
## {id, day, start_hour, end_hour, open, attendees: Array[String]}; {} si nunca hubo reunión.
var _meeting: Dictionary = {}
var _last_meeting_day: int = -1
## Detalle numérico del último choque (UI y depuración).
var _last_contest: Dictionary = {}


func _ready() -> void:
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.npc_removed.connect(_on_npc_removed)


func reset_for_new_run() -> void:
	_ideas.clear()
	_next_id = 1
	_signals.clear()
	_pending_generation.clear()
	_removed_owners.clear()
	_preparation.clear()
	_meeting = {}
	_last_meeting_day = -1
	_last_contest = {}
	_rng.seed = hash("%d:%s" % [GameClock.get_run_seed(), RNG_SALT])


# ─── Generación (§11.1) ───────────────────────────────────────

## Genera ya una idea para el personaje (sin tirada). "" si no existe o ya no está en plantilla.
func generate_for_npc(npc_id: String) -> String:
	var profile: Dictionary = _npc_profile(npc_id)
	if profile.is_empty():
		return ""
	return _create_idea(npc_id, profile)


## EXTRA: genera una idea para `owner` con la plantilla de ideas.json `template_department`
## (guiones, tutorial, tests). La calidad sigue la fórmula de §11.1.
func generate_idea(owner: String, template_department: String) -> String:
	var template: Dictionary = Database.get_idea_template(template_department)
	return _create_idea(owner, {
		"department": str(template.get(KEY_DEPARTMENT, template_department)),
		"quality_min": int(template.get("quality_min", Database.get_balance_int(B_QUALITY_MIN))),
		"quality_max": int(template.get("quality_max", Database.get_balance_int(B_QUALITY_MAX))),
	})


## EXTRA: probabilidad diaria = (0,12 + 0,004 × ambición) × modificador, acotada a [0, 1].
func get_generation_probability(ambition: int) -> float:
	var p: float = Database.get_balance_float(B_PROB_BASE) \
			+ Database.get_balance_float(B_PROB_PER_AMBITION) * float(ambition)
	return clampf(p * get_generation_modifier(), 0.0, 1.0)


## EXTRA: modificador global de Company (§9.10: la expulsión de talento reduce la generación).
func get_generation_modifier() -> float:
	if Company.has_method(COMPANY_MODIFIER_GETTER):
		return float(Company.call(COMPANY_MODIFIER_GETTER))
	return 1.0


## EXTRA: solo generan ideas los personajes de ambición media o alta.
func is_ambitious_enough(ambition: int) -> bool:
	return ambition >= Database.get_balance_int(B_MIN_AMBITION)


## EXTRA: una tirada diaria con el RNG del sistema (sin comprobar elegibilidad).
func roll_generation(ambition: int) -> bool:
	return _rng.randf() < get_generation_probability(ambition)


## EXTRA: calidad = 20 + aleatorio(0, 80), proyectada linealmente sobre [quality_min, quality_max].
func roll_quality(quality_min: int, quality_max: int) -> int:
	var base_min: int = Database.get_balance_int(B_QUALITY_MIN)
	var base_max: int = Database.get_balance_int(B_QUALITY_MAX)
	var base: int = _rng.randi_range(base_min, base_max)
	var t: float = float(base - base_min) / float(maxi(base_max - base_min, 1))
	return clampi(roundi(lerpf(float(quality_min), float(quality_max), t)),
			Idea.MIN_QUALITY, Idea.MAX_QUALITY)


## EXTRA: tirada diaria sobre toda la plantilla. Devuelve cuántas ideas quedan programadas hoy.
func run_daily_generation() -> int:
	var scheduled: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not _can_generate(npc):
			continue
		if roll_generation(npc.get_trait(TRAIT_AMBITION)):
			_pending_generation[npc.id] = _rng.randi_range(
					Database.get_balance_int(B_HOUR_MIN), Database.get_balance_int(B_HOUR_MAX))
			scheduled += 1
	return scheduled


## EXTRA: plantilla de ideas.json para una ocupación / departamento (balance
## ideas.plantilla_por_ocupacion → ideas.plantilla_por_departamento → el propio departamento).
func resolve_template_department(occupation_id: String, department: String) -> String:
	var by_occupation: Dictionary = _balance_dict(B_TEMPLATE_BY_OCC)
	if by_occupation.has(occupation_id):
		return str(by_occupation[occupation_id])
	var by_department: Dictionary = _balance_dict(B_TEMPLATE_BY_DEPT)
	var occupation: OccupationData = Database.get_occupation(occupation_id)
	if occupation != null:
		var occ_department: String = str(occupation.extra.get(KEY_DEPARTMENT, ""))
		if by_department.has(occ_department):
			return str(by_department[occ_department])
	if by_department.has(department):
		return str(by_department[department])
	return department


## EXTRA (visuales §11.1): [{npc_id, idea_id, behaviour, confidant, day, until_hour}].
func get_signalling_npcs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _signals.values():
		out.append(entry.duplicate())
	return out


## EXTRA: el propietario cuenta su idea a otro personaje (pasa a creer «la idea era suya»).
func share_idea(idea_id: String, npc_id: String) -> bool:
	var idea: Idea = _ideas.get(idea_id)
	if idea == null or npc_id.is_empty() or idea.known_by.has(npc_id):
		return false
	idea.known_by.append(npc_id)
	return true


# ─── Consulta ─────────────────────────────────────────────────

func get_idea(idea_id: String) -> Idea:
	return _ideas.get(idea_id)


func get_ideas_by_owner(npc_id: String) -> Array[Idea]:
	var out: Array[Idea] = []
	for idea: Idea in _ideas.values():
		if idea.owner == npc_id:
			out.append(idea)
	return out


## Ideas vivas que el jugador aún puede adquirir.
func get_available_ideas() -> Array[Idea]:
	var out: Array[Idea] = []
	for idea: Idea in _ideas.values():
		if _is_live(idea) and idea.acquired_by.is_empty():
			out.append(idea)
	return out


## De personajes eliminados o expulsados antes de presentarlas (vía "inherit").
func get_unclaimed_ideas() -> Array[Idea]:
	var out: Array[Idea] = []
	for idea: Idea in get_available_ideas():
		if is_owner_gone(idea.owner):
			out.append(idea)
	return out


## EXTRA: ideas vivas en poder del jugador.
func get_player_ideas() -> Array[Idea]:
	var out: Array[Idea] = []
	for idea: Idea in _ideas.values():
		if _is_live(idea) and idea.acquired_by == PLAYER_ID:
			out.append(idea)
	return out


## EXTRA: true si el personaje fue expulsado o eliminado (npc_removed).
func is_owner_gone(npc_id: String) -> bool:
	return _removed_owners.has(npc_id)


## EXTRA: rastro de la vía de adquisición según ideas.json (leaves_trace); "" si no se adquirió.
func get_acquisition_trace(idea_id: String) -> String:
	var idea: Idea = _ideas.get(idea_id)
	if idea == null or idea.acquisition_method.is_empty():
		return ""
	for method: Variant in Database.get_raw("ideas").get("acquisition_methods", []):
		if method is Dictionary and str(method.get(KEY_METHOD_ID, "")) == idea.acquisition_method:
			return str(method.get(KEY_TRACE, ""))
	return ""


## EXTRA: nombre propio del personaje (NPCDirector, si no el catálogo de nominados, si no su id).
func get_npc_display_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null and not npc.name.is_empty():
		return npc.name
	var named: NPCData = Database.get_named_npc(npc_id)
	return named.name if named != null else npc_id


# ─── Adquisición (§11.1) ──────────────────────────────────────

func acquire(idea_id: String, method: String) -> bool:
	var idea: Idea = _ideas.get(idea_id)
	if not _can_acquire(idea, method):
		return false
	idea.acquired_by = PLAYER_ID
	idea.acquisition_method = method
	if not idea.known_by.has(PLAYER_ID):
		idea.known_by.append(PLAYER_ID)
	_leave_trace(idea, method)
	EventBus.idea_acquired.emit(idea.id, method)
	return true


## EXTRA (manos: DutySystem): la idea robada se usa como material de una entrega (§10.2). Deja de
## poder presentarse. Devuelve su calidad o -1 si el jugador no la posee viva.
func use_as_material(idea_id: String) -> int:
	var idea: Idea = _ideas.get(idea_id)
	if idea == null or not _is_live(idea) or idea.acquired_by != PLAYER_ID:
		return -1
	idea.presented = true
	return idea.quality


# ─── Presentación (§11.2) ─────────────────────────────────────

## EXTRA: preparación declarada para la próxima presentación ("none" | "assist" | "real").
func set_preparation(idea_id: String, preparation: String) -> bool:
	var idea: Idea = _ideas.get(idea_id)
	if idea == null or idea.acquired_by != PLAYER_ID \
			or not IdeaPresentation.PREPARATIONS.has(preparation):
		return false
	_preparation[idea_id] = preparation
	return true


func get_preparation(idea_id: String) -> String:
	return _preparation.get(idea_id, IdeaPresentation.PREP_NONE)


## Presentación del jugador con el contexto real. Devuelve { merit, contested, contest_result }
## más: status, idea_id, quality, preparation, reputation, accuser, attendees y, si hubo choque,
## player_credibility, accuser_credibility, difference, allies, believers.
## No aplica consecuencias en otros sistemas: IdeaPresentation.present_player_idea lo hace.
func present(idea_id: String) -> Dictionary:
	return present_with_context(idea_id, {})


## EXTRA: como present(), con claves de contexto forzadas (ver IdeaPresentation.build_context;
## además "preparation" y "accuser_present").
func present_with_context(idea_id: String, overrides: Dictionary) -> Dictionary:
	var idea: Idea = _ideas.get(idea_id)
	var result: Dictionary = {
		"merit": 0, "contested": false, "contest_result": "", "idea_id": idea_id,
		"status": _presentation_status(idea), "accuser": "", "attendees": get_meeting_attendees(),
	}
	if result["status"] != STATUS_OK:
		return result
	var accuser: String = _find_accuser(idea, overrides)
	if not accuser.is_empty():
		result["contested"] = true
		result["accuser"] = accuser
		result["contest_result"] = contest_with_context(idea_id, accuser, overrides)
		result.merge(_last_contest, false)
		result["attendees"] = _last_contest.get("attendees", result["attendees"])
	if not result["contested"] or result["contest_result"] == IdeaPresentation.RESULT_WIN:
		_grant_player_merit(idea, overrides, result)
	return result


func contest(idea_id: String, accuser: String) -> String:
	return contest_with_context(idea_id, accuser, {})


## EXTRA: choque de credibilidad con claves de contexto forzadas. Registra el resultado en la idea
## (derrota: revierte al propietario; empate: quemada) y emite idea_contested.
func contest_with_context(idea_id: String, accuser: String, overrides: Dictionary) -> String:
	var idea: Idea = _ideas.get(idea_id)
	if idea == null or accuser.is_empty():
		return ""
	var context: Dictionary = IdeaPresentation.build_context(idea, accuser, get_meeting_attendees())
	context.merge(overrides, true)
	var outcome: Dictionary = IdeaPresentation.resolve_contest(context)
	var result: String = str(outcome["result"])
	_apply_contest_to_idea(idea, result)
	_last_contest = context.duplicate(true)
	_last_contest.merge(outcome, true)
	_last_contest["idea_id"] = idea_id
	_last_contest["accuser"] = accuser
	EventBus.idea_contested.emit(idea_id, accuser, result)
	return result


func get_last_contest() -> Dictionary:
	return _last_contest.duplicate(true)


## EXTRA: el propietario presenta su idea (cierre de la reunión). Devuelve el mérito obtenido.
func present_for_owner(idea_id: String) -> int:
	var idea: Idea = _ideas.get(idea_id)
	if idea == null or not _is_live(idea) or is_owner_gone(idea.owner):
		return 0
	var merit: int = IdeaPresentation.compute_merit(idea.quality, IdeaPresentation.PREP_REAL,
			IdeaPresentation.npc_reputation(idea.owner))
	idea.presented = true
	EventBus.idea_presented.emit(idea.id, idea.owner, merit)
	if idea.acquired_by == PLAYER_ID:
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_OWNER_PRESENTED,
				[get_npc_display_name(idea.owner)])
	return merit


# ─── Reunión semanal Aurora (§11.2) ───────────────────────────

## EXTRA: {room, weekday, hour, duration_hours} para el calendario y PORTAL.
func get_meeting_schedule() -> Dictionary:
	return {
		"room": AURORA_ROOM, "weekday": Database.get_balance_int(B_AURORA_WEEKDAY),
		"hour": Database.get_balance_int(B_AURORA_HOUR),
		"duration_hours": Database.get_balance_int(B_AURORA_HOURS),
	}


## EXTRA: la jornada 1 es el primer día de la semana (weekday 0).
func is_meeting_day(day: int) -> bool:
	var per_week: int = maxi(Database.get_balance_int(B_DAYS_PER_WEEK), 1)
	return posmod(day - 1, per_week) == Database.get_balance_int(B_AURORA_WEEKDAY)


## EXTRA: primera jornada ≥ from_day con reunión Aurora.
func get_next_meeting_day(from_day: int) -> int:
	var per_week: int = maxi(Database.get_balance_int(B_DAYS_PER_WEEK), 1)
	for offset: int in per_week:
		if is_meeting_day(from_day + offset):
			return from_day + offset
	return from_day


func is_meeting_open() -> bool:
	return bool(_meeting.get("open", false))


## EXTRA: {id, day, start_hour, end_hour, open, attendees} de la reunión en curso o la última.
func get_current_meeting() -> Dictionary:
	return _meeting.duplicate(true)


## EXTRA: asistentes de la reunión abierta: los propietarios que acudieron, los que la escena
## añadió y los personajes que NPCDirector sitúa en aurora_room.
func get_meeting_attendees() -> Array[String]:
	var out: Array[String] = []
	if not is_meeting_open():
		return out
	for npc_id: Variant in _meeting.get("attendees", []):
		out.append(str(npc_id))
	for npc: NPCRuntime in NPCDirector.get_npcs_in_room(AURORA_ROOM):
		if not out.has(npc.id):
			out.append(npc.id)
	return out


## EXTRA: un personaje entra en la reunión abierta (la escena Aurora, guiones o tests).
func add_meeting_attendee(npc_id: String) -> bool:
	if not is_meeting_open() or npc_id.is_empty() or is_owner_gone(npc_id):
		return false
	var attendees: Array = _meeting.get("attendees", [])
	if not attendees.has(npc_id):
		attendees.append(npc_id)
	_meeting["attendees"] = attendees
	return true


## EXTRA: abre la reunión ahora (el reloj lo hace solo a la hora programada). Devuelve su id.
func start_meeting() -> String:
	if is_meeting_open():
		return str(_meeting["id"])
	var start: int = GameClock.get_hour()
	return _open_meeting(GameClock.get_day(), start, start + Database.get_balance_int(B_AURORA_HOURS))


## EXTRA: cierra la reunión: los propietarios asistentes presentan sus ideas pendientes.
## Devuelve cuántas ideas se presentaron.
func close_meeting() -> int:
	if not is_meeting_open():
		return 0
	var presented: int = 0
	for npc_id: String in get_meeting_attendees():
		for idea: Idea in get_ideas_by_owner(npc_id):
			if _owner_can_present(idea):
				present_for_owner(idea.id)
				presented += 1
	_meeting["open"] = false
	return presented


## EXTRA: lógica horaria (generación programada, señales, reunión). El reloj la invoca con
## hour_passed; es idempotente para una misma hora.
func process_hour(hour: int, day: int) -> void:
	_release_pending_generation(hour)
	_expire_signals(hour, day)
	_update_meeting(hour, day)


## EXTRA: lógica de cambio de jornada (day_advanced): envejece, caduca y tira la generación.
func process_new_day(day: int) -> void:
	if is_meeting_open():
		close_meeting()
	for npc_id: String in _pending_generation.keys():
		generate_for_npc(npc_id)
	_pending_generation.clear()
	_signals.clear()
	for idea: Idea in _ideas.values():
		idea.freshness -= 1
	expire_stale_ideas()
	run_daily_generation()
	if is_meeting_day(day):
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_MEETING_TODAY,
				[HOUR_FORMAT % Database.get_balance_int(B_AURORA_HOUR)])


## Retira las ideas sin frescura. Emite idea_expired por cada una que no llegó a presentarse y
## devuelve cuántas caducaron así. (El descuento diario de frescura lo hace process_new_day.)
func expire_stale_ideas() -> int:
	var expired: int = 0
	for idea_id: String in _ideas.keys():
		var idea: Idea = _ideas[idea_id]
		if not idea.is_expired():
			continue
		_ideas.erase(idea_id)
		_preparation.erase(idea_id)
		if not idea.presented:
			expired += 1
			EventBus.idea_expired.emit(idea_id)
	return expired


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	var ideas: Array = []
	for idea: Idea in _ideas.values():
		ideas.append(idea.to_dict())
	return {
		"ideas": ideas, "next_id": _next_id, "rng_seed": str(_rng.seed),
		"rng_state": str(_rng.state), "signals": _signals.duplicate(true),
		"pending_generation": _pending_generation.duplicate(),
		"removed_owners": _removed_owners.duplicate(), "preparation": _preparation.duplicate(),
		"meeting": _meeting.duplicate(true), "last_meeting_day": _last_meeting_day,
	}


func load_state(data: Dictionary) -> void:
	reset_for_new_run()
	for entry: Variant in data.get("ideas", []):
		if entry is Dictionary:
			var idea: Idea = Idea.from_dict(entry, SAVE_CONTEXT)
			_ideas[idea.id] = idea
	_next_id = int(data.get("next_id", _next_id))
	_rng.seed = str(data.get("rng_seed", str(_rng.seed))).to_int()
	_rng.state = str(data.get("rng_state", str(_rng.state))).to_int()
	_load_maps(data)
	_meeting = _load_meeting(data.get("meeting", {}))
	_last_meeting_day = int(data.get("last_meeting_day", -1))


# ─── Internos: generación ─────────────────────────────────────

func _can_generate(npc: NPCRuntime) -> bool:
	if not npc.alive or is_owner_gone(npc.id) or _pending_generation.has(npc.id):
		return false
	if not is_ambitious_enough(npc.get_trait(TRAIT_AMBITION)):
		return false
	var live: int = 0
	for idea: Idea in get_ideas_by_owner(npc.id):
		if _is_live(idea):
			live += 1
	return live < Database.get_balance_int(B_MAX_LIVE)


## {department (plantilla), quality_min, quality_max} o {} si el personaje no existe o ya no está.
func _npc_profile(npc_id: String) -> Dictionary:
	if is_owner_gone(npc_id):
		return {}
	var occupation: String = ""
	var department: String = ""
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null:
		if not npc.alive:
			return {}
		occupation = npc.occupation_id
		department = npc.department
	var named: NPCData = Database.get_named_npc(npc_id)
	if npc == null and named == null:
		return {}
	if named != null:
		occupation = named.occupation if occupation.is_empty() else occupation
		department = str(named.extra.get(KEY_DEPARTMENT, "")) if department.is_empty() \
				else department
	var template_department: String = resolve_template_department(occupation, department)
	var template: Dictionary = Database.get_idea_template(template_department)
	var quality: Vector2i = _quality_range(named, template)
	return {"department": str(template.get(KEY_DEPARTMENT, template_department)),
			"quality_min": quality.x, "quality_max": quality.y}


func _quality_range(named: NPCData, template: Dictionary) -> Vector2i:
	if named != null:
		var special: Variant = named.extra.get(KEY_SPECIAL)
		if special is Dictionary and (special as Dictionary).get(KEY_QUALITY_RANGE) is Array:
			var pair: Array = (special as Dictionary)[KEY_QUALITY_RANGE]
			if pair.size() == 2:
				return Vector2i(int(pair[0]), int(pair[1]))
	return Vector2i(int(template.get("quality_min", Database.get_balance_int(B_QUALITY_MIN))),
			int(template.get("quality_max", Database.get_balance_int(B_QUALITY_MAX))))


func _create_idea(owner: String, profile: Dictionary) -> String:
	var idea: Idea = Idea.new()
	idea.id = ID_FORMAT % _next_id
	_next_id += 1
	idea.owner = owner
	idea.department = str(profile["department"])
	idea.quality = roll_quality(int(profile["quality_min"]), int(profile["quality_max"]))
	idea.freshness = _rng.randi_range(Database.get_balance_int(B_FRESH_MIN),
			Database.get_balance_int(B_FRESH_MAX))
	idea.known_by.append(owner)
	idea.text_key = _pick_text_key(idea.department)
	idea.created_day = GameClock.get_day()
	_ideas[idea.id] = idea
	_start_signal(idea)
	EventBus.idea_generated.emit(idea.id, owner, idea.quality, idea.department)
	return idea.id


func _pick_text_key(template_department: String) -> String:
	var keys: Variant = Database.get_idea_template(template_department).get("text_keys", [])
	if not (keys is Array) or (keys as Array).is_empty():
		return ""
	return str(keys[_rng.randi_range(0, (keys as Array).size() - 1)])


## Señalización (§11.1): indicador visual + cambio de comportamiento observable.
func _start_signal(idea: Idea) -> void:
	var behaviour: String = _weighted_pick(_balance_dict(B_BEHAVIOUR_WEIGHTS))
	var confidant: String = ""
	if behaviour == BEHAVIOUR_TELL:
		confidant = _pick_confidant(idea.owner)
		if confidant.is_empty():
			behaviour = BEHAVIOUR_AGITATION
		else:
			share_idea(idea.id, confidant)
	_signals[idea.owner] = {
		"npc_id": idea.owner, "idea_id": idea.id, "behaviour": behaviour, "confidant": confidant,
		"day": GameClock.get_day(),
		"until_hour": GameClock.get_hour() + Database.get_balance_int(B_SIGNAL_HOURS),
	}


func _pick_confidant(owner: String) -> String:
	var candidates: Array[String] = []
	for npc_id: String in SocialGraph.get_neighbours(owner,
			Database.get_balance_float(B_CONFIDANT_STRENGTH)):
		if npc_id != owner and npc_id != PLAYER_ID and not is_owner_gone(npc_id):
			candidates.append(npc_id)
	if candidates.is_empty():
		for npc: NPCRuntime in NPCDirector.get_npcs_in_room(NPCDirector.get_current_location(owner)):
			if npc.id != owner and npc.alive:
				candidates.append(npc.id)
	if candidates.is_empty():
		return ""
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _weighted_pick(weights: Dictionary) -> String:
	var total: float = 0.0
	for key: Variant in weights:
		if not str(key).begins_with("_"):
			total += maxf(float(weights[key]), 0.0)
	var roll: float = _rng.randf() * total
	var last: String = ""
	for key: Variant in weights:
		if str(key).begins_with("_"):
			continue
		last = str(key)
		roll -= maxf(float(weights[key]), 0.0)
		if roll < 0.0:
			return last
	return last


func _release_pending_generation(hour: int) -> void:
	for npc_id: String in _pending_generation.keys():
		if hour >= _pending_generation[npc_id]:
			_pending_generation.erase(npc_id)
			generate_for_npc(npc_id)


func _expire_signals(hour: int, day: int) -> void:
	for npc_id: String in _signals.keys():
		var entry: Dictionary = _signals[npc_id]
		if int(entry["day"]) != day or hour >= int(entry["until_hour"]):
			_signals.erase(npc_id)


# ─── Internos: adquisición y presentación ─────────────────────

func _is_live(idea: Idea) -> bool:
	return not idea.presented and not idea.is_expired()


func _can_acquire(idea: Idea, method: String) -> bool:
	if idea == null or not METHODS.has(method) or not _is_live(idea):
		return false
	if not idea.acquired_by.is_empty():
		return false
	# Herencia solo si el propietario ya no está; el resto exige que siga en plantilla.
	return is_owner_gone(idea.owner) == (method == METHOD_INHERIT)


func _leave_trace(idea: Idea, method: String) -> void:
	match method:
		METHOD_OVERHEAR:
			EventBus.player_seen_partially.emit(idea.owner,
					Database.get_balance_float(B_PARTIAL_CERTAINTY), _owner_location(idea.owner))
		METHOD_STEAL_FILE:
			EventBus.crime_committed.emit(CRIME_FILE_COPIED, _owner_desk_room(idea.owner),
					{"idea_id": idea.id, "owner": idea.owner, "subject": PLAYER_ID})
		_:
			pass  # inherit: el rastro es el de la desaparición; purchase/gifted: ninguno documental.


func _owner_location(npc_id: String) -> String:
	var location: String = NPCDirector.get_current_location(npc_id)
	return location if not location.is_empty() else _owner_desk_room(npc_id)


func _owner_desk_room(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null and not npc.home_room.is_empty():
		return npc.home_room
	var named: NPCData = Database.get_named_npc(npc_id)
	return named.home_room if named != null else ""


func _presentation_status(idea: Idea) -> String:
	if idea == null:
		return STATUS_NOT_FOUND
	if idea.acquired_by != PLAYER_ID:
		return STATUS_NOT_HELD
	if idea.presented:
		return STATUS_ALREADY_PRESENTED
	if idea.is_expired():
		return STATUS_EXPIRED
	if not is_meeting_open():
		return STATUS_NO_MEETING
	return STATUS_OK


func _find_accuser(idea: Idea, overrides: Dictionary) -> String:
	if CONSENTED_METHODS.has(idea.acquisition_method) or is_owner_gone(idea.owner):
		return ""
	var present: bool = bool(overrides.get("accuser_present",
			get_meeting_attendees().has(idea.owner)))
	return idea.owner if present else ""


func _grant_player_merit(idea: Idea, overrides: Dictionary, result: Dictionary) -> void:
	var preparation: String = str(overrides.get("preparation", get_preparation(idea.id)))
	var reputation: float = float(overrides.get("player_reputation", PlayerState.get_reputation()))
	var merit: int = IdeaPresentation.compute_merit(idea.quality, preparation, reputation)
	idea.presented = true
	result.merge({"merit": merit, "quality": idea.quality, "preparation": preparation,
			"reputation": reputation}, true)
	EventBus.idea_presented.emit(idea.id, PLAYER_ID, merit)


func _apply_contest_to_idea(idea: Idea, result: String) -> void:
	match result:
		IdeaPresentation.RESULT_LOSS:
			idea.acquired_by = ""
			idea.acquisition_method = ""
			_preparation.erase(idea.id)
		IdeaPresentation.RESULT_TIE:
			idea.presented = true
		_:
			pass  # victoria: present() concede el mérito y marca la idea presentada.


func _owner_can_present(idea: Idea) -> bool:
	return _is_live(idea) and not CONSENTED_METHODS.has(idea.acquisition_method)


func _roll_attendance() -> Array[String]:
	var out: Array[String] = []
	var per_point: float = Database.get_balance_float(B_PRESENT_PER_AMBITION)
	for idea: Idea in _ideas.values():
		if out.has(idea.owner) or not _owner_can_present(idea) or is_owner_gone(idea.owner):
			continue
		if _rng.randf() < per_point * float(_ambition_of(idea.owner)):
			out.append(idea.owner)
	return out


func _ambition_of(npc_id: String) -> int:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null:
		return npc.get_trait(TRAIT_AMBITION)
	var named: NPCData = Database.get_named_npc(npc_id)
	return int(named.traits.get(TRAIT_AMBITION, 0)) if named != null else 0


func _open_meeting(day: int, start_hour: int, end_hour: int) -> String:
	_meeting = {
		"id": MEETING_ID_FORMAT % day, "day": day, "start_hour": start_hour,
		"end_hour": end_hour, "open": true, "attendees": _roll_attendance(),
	}
	_last_meeting_day = day
	EventBus.aurora_meeting_started.emit(str(_meeting["id"]))
	return str(_meeting["id"])


func _update_meeting(hour: int, day: int) -> void:
	var start: int = Database.get_balance_int(B_AURORA_HOUR)
	if not is_meeting_open() and is_meeting_day(day) and _last_meeting_day != day and hour >= start:
		_open_meeting(day, start, start + Database.get_balance_int(B_AURORA_HOURS))
	if is_meeting_open() and (hour >= int(_meeting["end_hour"]) or day != int(_meeting["day"])):
		close_meeting()


# ─── Internos: señales y persistencia ─────────────────────────

func _on_day_advanced(day_number: int) -> void:
	process_new_day(day_number)


func _on_hour_passed(hour: int, day_number: int) -> void:
	process_hour(hour, day_number)


func _on_npc_removed(npc_id: String, cause: String) -> void:
	_removed_owners[npc_id] = cause
	_signals.erase(npc_id)
	_pending_generation.erase(npc_id)
	if is_meeting_open():
		var attendees: Array = _meeting.get("attendees", [])
		attendees.erase(npc_id)
		_meeting["attendees"] = attendees


func _load_maps(data: Dictionary) -> void:
	for key: Variant in data.get("signals", {}):
		var entry: Dictionary = (data["signals"][key] as Dictionary).duplicate(true)
		entry["day"] = int(entry.get("day", 0))
		entry["until_hour"] = int(entry.get("until_hour", 0))
		_signals[str(key)] = entry
	for key: Variant in data.get("pending_generation", {}):
		_pending_generation[str(key)] = int(data["pending_generation"][key])
	for key: Variant in data.get("removed_owners", {}):
		_removed_owners[str(key)] = str(data["removed_owners"][key])
	for key: Variant in data.get("preparation", {}):
		_preparation[str(key)] = str(data["preparation"][key])


func _load_meeting(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var d: Dictionary = raw
	var attendees: Array[String] = []
	for npc_id: Variant in d.get("attendees", []):
		attendees.append(str(npc_id))
	return {
		"id": str(d.get("id", "")), "day": int(d.get("day", 0)),
		"start_hour": int(d.get("start_hour", 0)), "end_hour": int(d.get("end_hour", 0)),
		"open": bool(d.get("open", false)), "attendees": attendees,
	}


func _balance_dict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(path)
	return value if value is Dictionary else {}
