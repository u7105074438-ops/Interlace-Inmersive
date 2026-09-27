# social_graph.gd — Vínculos entre personajes y propagación de creencias en los corrillos.
# PROPIETARIO DE: los vínculos entre personajes (siete tipos, §7.7), la jerarquía que espera al próximo titular de cada silla, los rumores plantados por el jugador, los hechos enterrados por kill_rumour, el registro del chat legible por IT, la última sesión de cada corrillo y el RNG de propagación (§19.6).
# ESCUCHA: time_band_changed, hour_passed, day_advanced, npc_removed, seat_vacated, seat_filled.
class_name SocialGraphSystem
extends Node

## Manual §7.2, §7.7, §7.13, §8.3, §19.6, §24.3 paso 5, §31; PASO 15; BUILD_NOTES §2, §6, §13.
## DECISIONES (contrato para el resto de sistemas):
##  · Vínculo = arista from → to {type, strength, secret, beneficiary}; una por par ordenado. Un
##    tipo no dirigido (social_graph.json) se refleja en to → from salvo que esa dirección tenga
##    un vínculo dirigido (hierarchy: subordinado → superior; debt: deudor → acreedor), que se
##    conserva («reflejo tapado»); remove_link del dirigido restituye entonces el reflejo.
##    add_link acota la fuerza al intervalo del tipo (§31). "player" puede ser destino
##    (add_link(npc, "player", "debt", f): el personaje le debe).
##  · get_links(npc) = salientes + entrantes que no son reflejo de un saliente, cada uno
##    {from, to, type, strength, directed, secret, beneficiary}. get_neighbours(npc, min) =
##    destinos salientes de cualquier tipo con fuerza >= min, sin "player".
##  · build_initial_graph(): vacía y construye. initial_links de npcs_named.json; después
##    fixed_generated_links (pareja de contabilidad: miembros del corrillo con su sala, departamento
##    y `count`); después §24.3 paso 5 para cada generado: jerarquía hacia superior_by_room y, por
##    tipo (department/friendship/rivalry), un objetivo sorteado en [min, max] de link_generation
##    del que se descuentan los vínculos de ese tipo que ya tiene (también los reflejos creados
##    por otros), eligiendo compañeros de su departamento sin vínculo previo que no hayan llegado
##    al máximo del tipo; nadie (nominado incluido) supera ese máximo por vínculos generados.
##    Pareja clandestina con secret_couple_probability. grafo_social.arquetipos_sin_vinculos
##    (rookie) no recibe aristas, tampoco la jerarquía (§8.3: Sonia Vail aislada aunque
##    npcs_named.json declare la amistad de Debbie), salvo las fijas de diseño.
##  · Sillas (Company emite seat_vacated/seat_filled; NPCDirector ya actualizó al personaje): quien
##    deja una silla (retirado o cambio de puesto) deja en ella su jerarquía: los subordinados que
##    le reportaban y su propio superior esperan al próximo titular personaje (el jugador y los
##    rookie no la heredan: sigue esperando). Sin superior heredado, el nuevo titular recibe el de
##    superior_by_room de su sala. Un personaje que cambia de puesto pierde además sus vínculos de
##    departamento (§7.7: reasignarlo como jefe de ala lo aísla); amistad, pareja, rivalidad, deuda
##    y enchufe le acompañan. npc_removed borra todas las aristas del retirado.
##  · Propagación (propagate_at_gathering): grafo_social.rondas_por_corrillo rondas; en cada una,
##    cada participante habla con sus vínculos presentes (en corrillos presenciales, también con
##    los ausentes si el tipo está en grafo_social.tipos_alcanzan_ausentes: la información
##    relevante asciende al superior; el chat digital no llega a quien no está en él) con
##    probabilidad clamp(fuerza × amplificación del corrillo × propagation_bonus × sociabilidad ÷
##    grafo_social.sociabilidad_referencia, 0, 1) (tipos_propagacion_total: siempre) y le cuenta
##    lo que sabía al empezar la ronda. Certeza nueva = certeza × get_transfer_factor (degradación
##    del tipo, §7.2/§7.13: 0,35 → 0,26 por departamento; la rivalidad amplifica ×1,15), factor
##    acotado a creencias.amplificacion_rumor_max y certeza a 1. Solo se cuenta si ELEVA la
##    certeza del oyente, y a quien ya lo sabía antes de la sesión solo lo eleva un testigo de
##    primera mano (creencia "direct": refresca una creencia débil, §7.6); lo oído en la misma
##    sesión lo eleva cualquiera (el rival que llega después con ×1,15 gana al primero). Nunca se
##    devuelve a quien se lo contó en la sesión, ni se cuenta al sujeto, ni por debajo de
##    creencias.umbral_olvido: los rumores no se inflan entre sesiones (el chat es horario) por eco
##    entre rivales. La amplificación del corrillo y la sociabilidad deciden el VOLUMEN (quién
##    habla), no la certeza (§7.13: en la cafetería, amplificación 1,4, George recibe 0,26).
##  · Tipos de propagación: all; negative_only (BeliefNet.is_negative_fact); relevant_only
##    (negativos o con sujeto "player"); none (deuda).
##  · PROTOCOLO CON BeliefNet (un autoload no muta otro): SocialGraph NO crea creencias. Por cada
##    salto emite rumor_spread(from, to, belief_id) y BeliefNet, suscrito, hace:
##      - from == "player" (inject_rumour): belief_id es sintético ("rumour_N"); crea en `to` la
##        creencia de origen "rumor" descrita por get_injected_rumour(id) {target, subject, fact,
##        certainty, location, day}.
##      - resto: transfer_belief(belief_id, to, get_transfer_factor(from, to, fact, subject)).
##      - ignora los hechos con is_fact_killed(fact) y olvida en su decaimiento diario las
##        creencias de origen rumor con un hecho enterrado.
##    belief_id es la creencia del emisor en BeliefNet (en rondas posteriores se busca su copia con
##    get_beliefs_held_by; si BeliefNet no la creó, se usa el id de origen).
##  · kill_rumour(fact): entierra el hecho hasta el cambio de jornada número
##    grafo_social.dias_rumor_enterrado (1 = el siguiente). Mientras, no se propaga ni se planta;
##    en ese cambio BeliefNet (day_advanced) olvida sus creencias de origen rumor y SocialGraph lo
##    desentierra en el primer hour_passed de la jornada nueva: los testigos de primera mano
##    conservan lo que vieron y vuelven a contarlo (no hay veto duradero sobre hechos genéricos
##    como "seen_partially"). Devuelve cuántas creencias de origen rumor lo afirman (las que
##    BeliefNet olvidará). Las manos pueden llamar además BeliefNet.forget_rumours(fact) para
##    un efecto inmediato. inject_rumour de un hecho enterrado lo desentierra.
##  · inject_rumour emite crime_committed("rumour_planted") (quien llame no debe repetirlo); el
##    destino debe ser un personaje en plantilla.
##  · Calendario: franja concreta (cafeteria_clan: lunch) → al TERMINAR la franja
##    (time_band_changed con old_band = franja; §7.13: lo visto a las 13:42 llega a George antes
##    de las 14:00 y cubre lo sabido por la mañana); "any" → en cada cambio de franja;
##    "all_including_night" (chat_3b) → cada hour_passed; interval_hours (fumadores) →
##    hour_passed cada N horas desde grafo_social.hora_primer_corrillo_periodico hasta
##    tiempo.hora_fin_jornada (10, 12, 14, 16, 18).
##  · Participantes: personajes en plantilla con el corrillo en NPCRuntime.gatherings y presentes
##    en su sala: franja concreta → sala programada de esa franja; "any" → pasó por la sala durante
##    la franja que acaba (o la franja en curso hasta ahora); periódico → salió a la sala en las
##    últimas N horas (cuenta la visita que EMPIEZA en (ahora − N h, ahora]: cada salida a fumar,
##    en una sola sesión); sin sala (chat) → siempre. Agenda de NPCDirector (get_day_plan +
##    get_location_at); sin agenda, sala actual. Tope max_participants: nominados primero y
##    después los generados más sociables.
##  · Corrillo secreto (is_secret, pareja de contabilidad): su amplificación (0: nula hacia fuera)
##    rige mientras algún vínculo clandestino una a dos de sus miembros; descubierto
##    (set_link_secret false), grafo_social.amplificacion_secreto_descubierto.
##  · La deuda suprime la denuncia temporalmente: pierde grafo_social.deuda_decaimiento_diario de
##    fuerza por jornada (baja incluso por debajo de strength_min) y desaparece al llegar a 0.
##  · Los corrillos readable_by_it (chat_3b) dejan en get_chat_log() cada salto entre presentes
##    (tope grafo_social.max_entradas_chat). get_last_session(id) describe la última sesión.

const PLAYER_ID := "player"
const SAVE_VERSION := 2
const RUMOUR_ID_PREFIX := "rumour_"
const CRIME_RUMOUR_PLANTED := "rumour_planted"
const KEY_SEPARATOR := "\u001f"
const TRAIT_SOCIABILITY := "sociability"
const NEUTRAL_BONUS := 1.0
## Una pareja (vínculos fijos) y un intervalo [mínimo, máximo] (fuerza de la jerarquía).
const PAIR_SIZE := 2
const MINUTES_PER_HOUR := NPCRoutinePlanner.MINUTES_PER_HOUR

# Esquema de social_graph.json (§31).
const T_DIRECTED := "directed"
const T_PROPAGATES := "propagates"
const T_DEGRADATION := "degradation"
const T_STRENGTH_MIN := "strength_min"
const T_STRENGTH_MAX := "strength_max"
const T_SUPPRESSES := "suppresses_denunciation"
const T_BLACKMAIL := "blackmail_material"
const T_BACKFIRES := "accusation_backfires"
const G_ID := "id"
const G_ROOM := "room"
const G_BAND := "band"
const G_INTERVAL := "interval_hours"
const G_AMPLIFICATION := "amplification"
const G_MAX := "max_participants"
const G_READABLE := "readable_by_it"
const G_SECRET := "is_secret"
const PROPAGATES_ALL := "all"
const PROPAGATES_NONE := "none"
const PROPAGATES_NEGATIVE := "negative_only"
const PROPAGATES_RELEVANT := "relevant_only"
const BAND_ANY := "any"
const BAND_CONTINUOUS := "all_including_night"
const LINK_DEPARTMENT := "department"
const LINK_FRIENDSHIP := "friendship"
const LINK_RIVALRY := "rivalry"
const LINK_HIERARCHY := "hierarchy"
const LINK_COUPLE := "couple"
const GENERATED_TYPES: Array[String] = [LINK_DEPARTMENT, LINK_FRIENDSHIP, LINK_RIVALRY]

# npcs_generation.json (§30, §24.3 paso 5).
const GEN_FILE := "npcs_generation"
const GEN_LINKS := "link_generation"
const GEN_FIXED := "fixed_generated_links"
const GEN_HIERARCHY := "hierarchy"
const GEN_SUPERIORS := "superior_by_room"
const GEN_STRENGTH := "strength"
const GEN_COUPLE_PROBABILITY := "secret_couple_probability"
const GEN_MIN_SUFFIX := "_links_min"
const GEN_MAX_SUFFIX := "_links_max"
const FIXED_GATHERING := "gathering"
const FIXED_ROOM := "room"
const FIXED_DEPARTMENT := "department"
const FIXED_COUNT := "count"
const SUPERIOR_OCC_PREFIX := "occ:"
const SUPERIOR_ROLE_PREFIX := "role:"

# Agenda de NPCDirector (get_day_plan) y silla de Company (get_npc_seat).
const PLAN_START := "start"
const PLAN_END := "end"
const PLAN_ROOM := "room"
const SEAT_OCCUPATION := "occupation_id"

# Claves de vínculo, de entradas de conocimiento, de sillas, de sesiones y de guardado.
const L_TYPE := "type"
const L_STRENGTH := "strength"
const L_SECRET := "secret"
const L_BENEFICIARY := "beneficiary"
const E_ID := "id"
const E_SUBJECT := "subject"
const E_FACT := "fact"
const E_LOCATION := "location"
const E_CERTAINTY := "certainty"
const E_SOURCE := "source"
const E_IN_SESSION := "in_session"
const S_SUBORDINATES := "subordinates"
const S_SUPERIOR := "superior"
const S_TO := "to"
const S_OCCUPATION := "occupation"
const K_DAY := "day"
const K_HOUR := "hour"
const K_MINUTE := "minute"
const K_PARTICIPANTS := "participants"
const K_SPREADS := "spreads"

# Rutas de balance.json.
const B_ROUNDS := "grafo_social.rondas_por_corrillo"
const B_SOC_REF := "grafo_social.sociabilidad_referencia"
const B_TOTAL_TYPES := "grafo_social.tipos_propagacion_total"
const B_ABSENT_TYPES := "grafo_social.tipos_alcanzan_ausentes"
const B_UNLINKED := "grafo_social.arquetipos_sin_vinculos"
const B_MIN_LINKS := "grafo_social.min_vinculos_no_aislado"
const B_FIRST_PERIODIC := "grafo_social.hora_primer_corrillo_periodico"
const B_DEBT_DECAY := "grafo_social.deuda_decaimiento_diario"
const B_BURIED_DAYS := "grafo_social.dias_rumor_enterrado"
const B_MAX_CHAT := "grafo_social.max_entradas_chat"
const B_STRENGTH_STEP := "grafo_social.paso_fuerza"
const B_DISCOVERED_AMP := "grafo_social.amplificacion_secreto_descubierto"
const B_TRANSMISSION := "creencias.descuento_por_transmision"
const B_AMPLIFICATION_MAX := "creencias.amplificacion_rumor_max"
const B_FORGET := "creencias.umbral_olvido"
const B_DAY_END := "tiempo.hora_fin_jornada"
const B_BAND_STARTS := "tiempo.franjas_hora_inicio"


## Estado transitorio de una sesión de propagate_at_gathering (no se guarda).
class RumourPass extends RefCounted:
	var gathering_id: String = ""
	var amplification: float = 0.0
	var readable: bool = false
	var in_person: bool = false
	var forget: float = 0.0
	var present: Dictionary[String, bool] = {}
	var active: Dictionary[String, bool] = {}
	## portador → {clave (sujeto, hecho, lugar) → {id, subject, fact, location, certainty,
	## source, in_session}}; in_session = lo supo en esta sesión.
	var knowledge: Dictionary[String, Dictionary] = {}
	## Portadores que recibieron algo en la ronda anterior (su id se resuelve en BeliefNet).
	var fresh: Dictionary[String, bool] = {}
	## clave de entrada + emisor + oyente → true: el oyente no se lo devuelve al emisor.
	var told: Dictionary[String, bool] = {}
	var teller_factor: Dictionary[String, float] = {}
	var spreads: int = 0


## from → {to → {type, strength, secret, beneficiary}}.
var _links: Dictionary[String, Dictionary] = {}
## id sintético → {target, subject, fact, certainty, location, day}.
var _injected: Dictionary[String, Dictionary] = {}
var _next_rumour: int = 1
## hecho enterrado → jornada en que se enterró.
var _killed: Dictionary[String, int] = {}
## [{day, hour, gathering, from, to, belief_id, subject, fact}], el más antiguo primero.
var _chat_log: Array[Dictionary] = []
## ocupación → {subordinates: {id → {strength, occupation}}, superior: {to, occupation,
## strength}}: jerarquía que espera al próximo titular de la silla.
var _seat_links: Dictionary[String, Dictionary] = {}
## corrillo → {day, hour, minute, participants, spreads} de su última sesión.
var _sessions: Dictionary[String, Dictionary] = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _propagating: bool = false
# Caché de datos estáticos (social_graph.json, npcs_generation.json y balance), por partida.
var _config_loaded: bool = false
var _types: Dictionary[String, Dictionary] = {}
var _total_types: Array[String] = []
var _absent_types: Array[String] = []
var _unlinked_archetypes: Array[String] = []
var _superiors_by_room: Dictionary[String, String] = {}
var _hierarchy_strength: Array[float] = []
## franja → minuto del día en que empieza.
var _band_starts: Dictionary[String, int] = {}


func _ready() -> void:
	EventBus.time_band_changed.connect(_on_time_band_changed)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.npc_removed.connect(_on_npc_removed)
	EventBus.seat_vacated.connect(_on_seat_vacated)
	EventBus.seat_filled.connect(_on_seat_filled)


## Vacía el grafo. build_initial_graph() lo (re)construye.
func reset_for_new_run() -> void:
	_clear()
	_rng.seed = GameClock.get_run_seed()
	_load_config()


# ─── Construcción (§24.3 paso 5) ──────────────────────────────

func build_initial_graph() -> void:
	reset_for_new_run()
	var active: Dictionary[String, bool] = _active_set()
	_build_named_links(active)
	var npcs: Array[NPCRuntime] = NPCDirector.get_all_npcs()
	if npcs.is_empty():
		return
	var rules: Dictionary = Database.get_raw(GEN_FILE)
	var fixed: Variant = rules.get(GEN_FIXED, [])
	if fixed is Array:
		for spec: Variant in fixed:
			if spec is Dictionary:
				_build_fixed_spec(npcs, spec)
	var link_rules: Variant = rules.get(GEN_LINKS, {})
	_build_generated_links(npcs, link_rules if link_rules is Dictionary else {}, active)


func _build_named_links(active: Dictionary[String, bool]) -> void:
	for named: NPCData in Database.get_all_named_npcs():
		for link: Dictionary in named.initial_links:
			var to: String = str(link.get("to", ""))
			if not _may_link(named.id, active) or not _may_link(to, active):
				continue
			var flags: Dictionary = {
				L_SECRET: bool(link.get(L_SECRET, false)),
				L_BENEFICIARY: str(link.get(L_BENEFICIARY, "")),
			}
			_put(named.id, to, str(link.get(L_TYPE, "")), float(link.get(L_STRENGTH, 0.0)), flags)


## Vínculos fijos de diseño (pareja de contabilidad): miembros del corrillo con su sala y
## departamento, hasta `count`, por parejas en orden de plantilla. No aplican
## arquetipos_sin_vinculos (contenido intencionado). Se crean antes que los generados.
func _build_fixed_spec(npcs: Array[NPCRuntime], spec: Dictionary) -> void:
	var members: Array[String] = _fixed_members(npcs, spec)
	var flags: Dictionary = {L_SECRET: bool(spec.get(L_SECRET, false))}
	for i: int in range(0, members.size() - 1, PAIR_SIZE):
		_put(members[i], members[i + 1], str(spec.get(L_TYPE, "")),
				float(spec.get(L_STRENGTH, 0.0)), flags)


func _fixed_members(npcs: Array[NPCRuntime], spec: Dictionary) -> Array[String]:
	var gathering: String = str(spec.get(FIXED_GATHERING, spec.get(G_ID, "")))
	var room: String = _text(spec, FIXED_ROOM)
	var department: String = _text(spec, FIXED_DEPARTMENT)
	var count: int = _whole(spec, FIXED_COUNT)
	var out: Array[String] = []
	for npc: NPCRuntime in npcs:
		if count > 0 and out.size() >= count:
			break
		if not npc.gatherings.has(gathering):
			continue
		if not room.is_empty() and DatabaseSystem.get_room_base_id(npc.home_room) != room:
			continue
		if department.is_empty() or npc.department == department:
			out.append(npc.id)
	return out


func _build_generated_links(npcs: Array[NPCRuntime], rules: Dictionary,
		active: Dictionary[String, bool]) -> void:
	var peers_by_dept: Dictionary[String, Array] = _peers_by_department(npcs, active)
	var couple_chance: float = float(rules.get(GEN_COUPLE_PROBABILITY, 0.0))
	for npc: NPCRuntime in npcs:
		if npc.is_named or not _may_link(npc.id, active):
			continue
		var peers: Array[String] = []
		if peers_by_dept.has(npc.department):
			peers = peers_by_dept[npc.department]
		_link_to_superior(npc, active)
		for link_type: String in GENERATED_TYPES:
			_pick_links(npc.id, peers, link_type, _rule_range(rules, link_type))
		_maybe_secret_couple(npc.id, peers, couple_chance)


func _peers_by_department(npcs: Array[NPCRuntime],
		active: Dictionary[String, bool]) -> Dictionary[String, Array]:
	var out: Dictionary[String, Array] = {}
	for npc: NPCRuntime in npcs:
		if not _may_link(npc.id, active):
			continue
		if not out.has(npc.department):
			var fresh: Array[String] = []
			out[npc.department] = fresh
		out[npc.department].append(npc.id)
	return out


## "department" → Vector2i(department_links_min, department_links_max).
static func _rule_range(rules: Dictionary, link_type: String) -> Vector2i:
	return Vector2i(int(rules.get(link_type + GEN_MIN_SUFFIX, 0)),
			int(rules.get(link_type + GEN_MAX_SUFFIX, 0)))


## §24.3 paso 5: sortea cuántos vínculos del tipo tendrá `from`, descuenta los que ya tiene
## (reflejos creados por otros incluidos) y completa con compañeros sin vínculo previo que aún no
## llegan al máximo del tipo.
func _pick_links(from: String, peers: Array[String], link_type: String, amount: Vector2i) -> void:
	if amount.y <= 0:
		return
	var wanted: int = _rng.randi_range(amount.x, amount.y) - _count_of_type(from, link_type)
	if wanted <= 0:
		return
	for to: String in _shuffled(peers):
		if wanted <= 0:
			return
		if to != from and not _has_any_link(from, to) \
				and _count_of_type(to, link_type) < amount.y:
			_put(from, to, link_type, _roll_strength(link_type), {})
			wanted -= 1


## Jerarquía hacia el superior de su sala (superior_by_room), si existe y puede tener vínculos.
func _link_to_superior(npc: NPCRuntime, active: Dictionary[String, bool]) -> void:
	var token: String = _superiors_by_room.get(DatabaseSystem.get_room_base_id(npc.home_room), "")
	var boss: String = _resolve_superior(token)
	if boss.is_empty() or boss == npc.id or not _may_link(boss, active) \
			or not _may_link(npc.id, active):
		return
	var strength: float = _roll_between(_hierarchy_strength[0], _hierarchy_strength[1]) \
			if _hierarchy_strength.size() >= PAIR_SIZE else _roll_strength(LINK_HIERARCHY)
	_put(npc.id, boss, LINK_HIERARCHY, strength, {})


## Valor de superior_by_room: id de personaje, "occ:<ocupación>" o "role:<puesto>". Un nominado
## que ya no ocupa su puesto de npcs_named.json cede el lugar al titular actual de ese puesto.
func _resolve_superior(token: String) -> String:
	if token.begins_with(SUPERIOR_OCC_PREFIX):
		return _holder_of(token.trim_prefix(SUPERIOR_OCC_PREFIX))
	if token.begins_with(SUPERIOR_ROLE_PREFIX):
		var role: String = token.trim_prefix(SUPERIOR_ROLE_PREFIX)
		for npc: NPCRuntime in NPCDirector.get_all_npcs():
			if NPCDirector.get_role(npc.id) == role:
				return npc.id
		return ""
	var named: NPCData = Database.get_named_npc(token)
	if named == null or named.occupation.is_empty():
		return token
	var npc: NPCRuntime = NPCDirector.get_npc(token)
	if npc != null and NPCDirector.is_active(token) and npc.occupation_id == named.occupation:
		return token
	return _holder_of(named.occupation)


func _holder_of(occupation_id: String) -> String:
	var holder: NPCRuntime = NPCDirector.get_npc_by_occupation(occupation_id)
	return holder.id if holder != null else ""


func _maybe_secret_couple(npc_id: String, peers: Array[String], chance: float) -> void:
	if chance <= 0.0 or _rng.randf() >= chance or _has_link_of_type(npc_id, LINK_COUPLE):
		return
	for to: String in _shuffled(peers):
		if to != npc_id and not _has_any_link(npc_id, to) \
				and not _has_link_of_type(to, LINK_COUPLE):
			_put(npc_id, to, LINK_COUPLE, _roll_strength(LINK_COUPLE), {L_SECRET: true})
			return


func _roll_strength(link_type: String) -> float:
	var spec: Dictionary = _type_spec(link_type)
	return _roll_between(float(spec.get(T_STRENGTH_MIN, 0.0)), float(spec.get(T_STRENGTH_MAX, 0.0)))


## Fuerza sorteada en [low, high], redondeada a grafo_social.paso_fuerza.
func _roll_between(low: float, high: float) -> float:
	var value: float = _rng.randf_range(low, high)
	var step: float = _bal_f(B_STRENGTH_STEP)
	return clampf(snappedf(value, step), low, high) if step > 0.0 else value


## Copia barajada con el RNG del sistema (Fisher-Yates).
func _shuffled(values: Array[String]) -> Array[String]:
	var out: Array[String] = values.duplicate()
	for i: int in range(out.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: String = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


# ─── Aristas (§19.6) ──────────────────────────────────────────

func add_link(from_npc: String, to_npc: String, link_type: String, strength: float) -> void:
	_put(from_npc, to_npc, link_type, strength, {})


## Extra: add_link con indicadores {secret: bool (pareja clandestina), beneficiary: String
## (enchufe; por defecto el destino)}. false si el tipo no existe o los extremos no son válidos.
func add_link_with_flags(from_npc: String, to_npc: String, link_type: String, strength: float,
		flags: Dictionary) -> bool:
	return _put(from_npc, to_npc, link_type, strength, flags)


## Borra from → to. Un tipo no dirigido se borra también en to → from si allí está su reflejo; un
## dirigido que tapaba el reflejo de un no dirigido to → from lo restituye (queda la relación
## no dirigida del par).
func remove_link(from_npc: String, to_npc: String) -> void:
	var link: Dictionary = _get_link(from_npc, to_npc)
	if link.is_empty():
		return
	_erase(from_npc, to_npc)
	var back: Dictionary = _get_link(to_npc, from_npc)
	if back.is_empty():
		return
	if not _is_directed(str(link[L_TYPE])):
		if str(back[L_TYPE]) == str(link[L_TYPE]):
			_erase(to_npc, from_npc)
	elif not _is_directed(str(back[L_TYPE])):
		_store(from_npc, to_npc, back.duplicate())


func get_links(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var outgoing: Dictionary = _links.get(npc_id, {})
	for to: String in outgoing:
		out.append(_describe(npc_id, to, outgoing[to]))
	for from: String in _links:
		if from == npc_id or not _links[from].has(npc_id):
			continue
		var link: Dictionary = _links[from][npc_id]
		var back: Dictionary = outgoing.get(from, {})
		var is_mirror: bool = not _is_directed(str(link[L_TYPE])) \
				and str(back.get(L_TYPE, "")) == str(link[L_TYPE])
		if not is_mirror:
			out.append(_describe(from, npc_id, link))
	return out


func get_link_strength(from_npc: String, to_npc: String) -> float:
	return float(_get_link(from_npc, to_npc).get(L_STRENGTH, 0.0))


func get_neighbours(npc_id: String, min_strength: float) -> Array[String]:
	var out: Array[String] = []
	var outgoing: Dictionary = _links.get(npc_id, {})
	for to: String in outgoing:
		if to != PLAYER_ID and float(outgoing[to][L_STRENGTH]) >= min_strength:
			out.append(to)
	return out


## Extra: tipo del vínculo from → to ("" si no hay).
func get_link_type(from_npc: String, to_npc: String) -> String:
	return str(_get_link(from_npc, to_npc).get(L_TYPE, ""))


## Extra: todas las aristas almacenadas (ambos sentidos de las no dirigidas), para depuración
## y mapa.
func get_all_links() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for from: String in _links:
		for to: String in _links[from]:
			out.append(_describe(from, to, _links[from][to]))
	return out


# ─── Comportamiento por tipo de vínculo (§7.7) ────────────────

## Extra (protocolo BeliefNet): multiplicador de certeza de un rumor from → to. 0 si no hay vínculo,
## si el tipo no propaga ese hecho (none / negative_only / relevant_only) o si está enterrado.
## Degradación del tipo (sin ella, creencias.descuento_por_transmision), acotada a
## [0, creencias.amplificacion_rumor_max]. `subject` hace falta para relevant_only (jerarquía).
func get_transfer_factor(from_npc: String, to_npc: String, belief_fact: String,
		subject: String = "") -> float:
	var link: Dictionary = _get_link(from_npc, to_npc)
	if link.is_empty() or is_fact_killed(belief_fact):
		return 0.0
	return _link_factor(str(link[L_TYPE]), belief_fact, subject)


## Extra (§7.7 deuda): una arista de deuda npc → acreedor suprime su denuncia hacia el acreedor
## ("player" incluido) mientras exista.
func is_denunciation_suppressed(npc_id: String, creditor: String) -> bool:
	var link: Dictionary = _get_link(npc_id, creditor)
	if link.is_empty() or float(link[L_STRENGTH]) <= 0.0:
		return false
	return bool(_type_spec(str(link[L_TYPE])).get(T_SUPPRESSES, false))


## Extra (§7.7 enchufe): acusar al beneficiario de un vínculo de parentesco corporativo se vuelve
## contra el acusador (salvo que el acusador sea su propio padrino).
func accusation_backfires(accuser: String, accused: String) -> bool:
	for link: Dictionary in get_links(accused):
		var other: String = str(link["to"]) if str(link["from"]) == accused else str(link["from"])
		if other == accuser or str(link[L_BENEFICIARY]) != accused:
			continue
		if bool(_type_spec(str(link[L_TYPE])).get(T_BACKFIRES, false)):
			return true
	return false


## Extra (§7.7 pareja): una pareja clandestina es material de chantaje.
func is_blackmail_material(npc_a: String, npc_b: String) -> bool:
	return _is_blackmail_link(_get_link(npc_a, npc_b)) \
			or _is_blackmail_link(_get_link(npc_b, npc_a))


## Extra: vínculos de npc_id que son material de chantaje (parejas clandestinas).
func get_blackmail_links(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for link: Dictionary in get_links(npc_id):
		if _is_blackmail_link(link):
			out.append(link)
	return out


## Extra: marca un vínculo como clandestino o público (la pareja descubierta deja de ser material
## de chantaje y su corrillo secreto deja de ser nulo hacia fuera). Afecta a ambos sentidos si
## existen. false si no hay vínculo.
func set_link_secret(npc_a: String, npc_b: String, secret: bool) -> bool:
	var changed: bool = false
	for pair: Array in [[npc_a, npc_b], [npc_b, npc_a]]:
		var link: Dictionary = _get_link(str(pair[0]), str(pair[1]))
		if not link.is_empty():
			link[L_SECRET] = secret
			changed = true
	return changed


## Pocas o ninguna arista saliente que propague (§7.7: aislar a una víctima reduce testigos).
func is_isolated(npc_id: String) -> bool:
	var count: int = 0
	var outgoing: Dictionary = _links.get(npc_id, {})
	for to: String in outgoing:
		var spec: Dictionary = _type_spec(str(outgoing[to][L_TYPE]))
		if to != PLAYER_ID and str(spec.get(T_PROPAGATES, PROPAGATES_ALL)) != PROPAGATES_NONE:
			count += 1
	return count < _bal_i(B_MIN_LINKS)


# ─── Corrillos y propagación ──────────────────────────────────

## Participantes de la sesión que se celebraría ahora (ver DECISIONES: presencia por corrillo).
func get_gathering_participants(gathering_id: String) -> Array[String]:
	var g: Dictionary = Database.get_gathering(gathering_id)
	var out: Array[String] = []
	if g.is_empty():
		return out
	var window: Vector2i = _session_window(g)
	var generated: Array[NPCRuntime] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not npc.gatherings.has(gathering_id) or not _is_present(npc, g, window):
			continue
		if npc.is_named:
			out.append(npc.id)
		else:
			generated.append(npc)
	generated.sort_custom(_more_sociable)
	for npc: NPCRuntime in generated:
		out.append(npc.id)
	var cap: int = _whole(g, G_MAX)
	if cap > 0 and out.size() > cap:
		out.resize(cap)
	return out


## Devuelve nº de propagaciones (saltos emitidos como rumor_spread).
func propagate_at_gathering(gathering_id: String) -> int:
	var g: Dictionary = Database.get_gathering(gathering_id)
	if g.is_empty() or _propagating:
		return 0
	var p: RumourPass = _begin_pass(gathering_id, g)
	_propagating = true
	if not p.present.is_empty():
		for _round: int in _bal_i(B_ROUNDS):
			if _run_round(p) == 0:
				break
	_propagating = false
	_note_session(p)
	return p.spreads


## Extra (depuración, mapa, tests): última sesión del corrillo {day, hour, minute, participants,
## spreads} ({} si aún no se ha reunido). Copia.
func get_last_session(gathering_id: String) -> Dictionary:
	return _sessions.get(gathering_id, {}).duplicate(true)


## Extra: amplificación vigente del corrillo (un corrillo secreto descubierto usa
## grafo_social.amplificacion_secreto_descubierto). 0 si no existe.
func get_gathering_amplification(gathering_id: String) -> float:
	var g: Dictionary = Database.get_gathering(gathering_id)
	var value: Variant = g.get(G_AMPLIFICATION)
	var base: float = float(value) if value is float or value is int else 0.0
	if not bool(g.get(G_SECRET, false)) or _has_hidden_pair(gathering_id):
		return base
	return _bal_f(B_DISCOVERED_AMP)


func _has_hidden_pair(gathering_id: String) -> bool:
	var members: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.gatherings.has(gathering_id):
			members.append(npc.id)
	for a: String in members:
		for b: String in members:
			if a != b and bool(_get_link(a, b).get(L_SECRET, false)):
				return true
	return false


func _begin_pass(gathering_id: String, g: Dictionary) -> RumourPass:
	var p: RumourPass = RumourPass.new()
	p.gathering_id = gathering_id
	p.amplification = get_gathering_amplification(gathering_id)
	p.readable = bool(g.get(G_READABLE, false))
	p.in_person = not _text(g, G_ROOM).is_empty()
	p.forget = _bal_f(B_FORGET)
	p.active = _active_set()
	for npc_id: String in get_gathering_participants(gathering_id):
		p.present[npc_id] = true
	return p


## Una ronda = un salto: cada participante cuenta lo que sabía al empezar. Devuelve los saltos.
func _run_round(p: RumourPass) -> int:
	var said: Dictionary[String, Array] = {}
	for teller: String in p.present:
		said[teller] = _entries_of(p, teller)
	p.fresh.clear()
	var before: int = p.spreads
	for teller: String in p.present:
		var entries: Array[Dictionary] = said[teller]
		if entries.is_empty():
			continue
		for to: String in (_links.get(teller, {}) as Dictionary).keys():
			var link: Dictionary = _get_link(teller, to)
			if not link.is_empty() and _may_hear(p, to, link) and _pair_talks(p, teller, link):
				_tell_all(p, teller, to, str(link[L_TYPE]), entries)
	return p.spreads - before


func _may_hear(p: RumourPass, listener: String, link: Dictionary) -> bool:
	if listener == PLAYER_ID or not p.active.has(listener):
		return false
	if p.present.has(listener):
		return true
	return p.in_person and _absent_types.has(str(link[L_TYPE]))


func _pair_talks(p: RumourPass, teller: String, link: Dictionary) -> bool:
	var chance: float = 1.0
	if not _total_types.has(str(link[L_TYPE])):
		chance = float(link[L_STRENGTH]) * p.amplification * _teller_factor(p, teller)
	if chance >= 1.0:
		return true
	if chance <= 0.0:
		return false
	return _rng.randf() < chance


## propagation_bonus del arquetipo × sociabilidad ÷ sociabilidad_referencia (§7.4 Sociabilidad).
func _teller_factor(p: RumourPass, teller: String) -> float:
	if p.teller_factor.has(teller):
		return p.teller_factor[teller]
	var npc: NPCRuntime = NPCDirector.get_npc(teller)
	var factor: float = 0.0
	if npc != null:
		var archetype: ArchetypeData = Database.get_archetype(npc.archetype)
		var bonus: float = archetype.propagation_bonus if archetype != null else NEUTRAL_BONUS
		var reference: float = _bal_f(B_SOC_REF)
		factor = bonus * float(npc.get_trait(TRAIT_SOCIABILITY)) / reference \
				if reference > 0.0 else bonus
	p.teller_factor[teller] = factor
	return factor


## Cuenta cada entrada que eleva la certeza del oyente (nunca de vuelta a quien se la contó).
func _tell_all(p: RumourPass, teller: String, to: String, link_type: String,
		entries: Array[Dictionary]) -> void:
	var heard: Dictionary = _knowledge(p, to)
	for e: Dictionary in entries:
		var key: String = _entry_key(e)
		if str(e[E_SUBJECT]) == to or p.told.has(_echo_key(key, to, teller)):
			continue
		var factor: float = _link_factor(link_type, str(e[E_FACT]), str(e[E_SUBJECT]))
		var certainty: float = minf(float(e[E_CERTAINTY]) * factor, Belief.MAX_CERTAINTY)
		if factor <= 0.0 or certainty < p.forget:
			continue
		if heard.has(key) and not _may_raise(heard[key], e, certainty):
			continue
		heard[key] = _heard_entry(heard.get(key, {}), e, certainty)
		p.told[_echo_key(key, teller, to)] = true
		p.fresh[to] = true
		p.spreads += 1
		if p.present.has(to):
			_log_chat(p, teller, to, e)
		EventBus.rumor_spread.emit(teller, to, str(e[E_ID]))


## Eleva la certeza; lo sabido antes de la sesión solo lo eleva un testigo de primera mano.
static func _may_raise(old: Dictionary, teller_entry: Dictionary, certainty: float) -> bool:
	var before: float = float(old[E_CERTAINTY])
	if certainty <= before or is_equal_approx(certainty, before):
		return false
	return bool(old[E_IN_SESSION]) or str(teller_entry[E_SOURCE]) == Belief.SOURCE_DIRECT


## Lo que el oyente sabe tras el salto (conserva su id, su origen y si lo sabía de antes).
static func _heard_entry(old: Dictionary, e: Dictionary, certainty: float) -> Dictionary:
	if old.is_empty():
		return _entry(str(e[E_ID]), str(e[E_SUBJECT]), str(e[E_FACT]), str(e[E_LOCATION]),
				certainty, Belief.SOURCE_RUMOR, true)
	return _entry(str(old[E_ID]), str(e[E_SUBJECT]), str(e[E_FACT]), str(e[E_LOCATION]),
			certainty, str(old[E_SOURCE]), bool(old[E_IN_SESSION]))


func _link_factor(link_type: String, fact: String, subject: String) -> float:
	var spec: Dictionary = _type_spec(link_type)
	if spec.is_empty():
		return 0.0
	match str(spec.get(T_PROPAGATES, PROPAGATES_ALL)):
		PROPAGATES_NONE:
			return 0.0
		PROPAGATES_NEGATIVE:
			if not BeliefNet.is_negative_fact(fact):
				return 0.0
		PROPAGATES_RELEVANT:
			if subject != PLAYER_ID and not BeliefNet.is_negative_fact(fact):
				return 0.0
	var degradation: float = float(spec[T_DEGRADATION]) if spec.has(T_DEGRADATION) \
			else _bal_f(B_TRANSMISSION)
	return clampf(degradation, 0.0, _bal_f(B_AMPLIFICATION_MAX))


## Lo que sabe `holder` (creencias ordinarias de BeliefNet no enterradas + lo oído en esta sesión).
func _knowledge(p: RumourPass, holder: String) -> Dictionary:
	if p.knowledge.has(holder):
		return p.knowledge[holder]
	var known: Dictionary = {}
	for b: Belief in BeliefNet.get_beliefs_held_by(holder):
		if b.is_record or is_fact_killed(b.fact):
			continue
		var e: Dictionary = _entry(b.id, b.subject, b.fact, b.location, b.certainty, b.source,
				false)
		var key: String = _entry_key(e)
		if not known.has(key) or float(known[key][E_CERTAINTY]) < b.certainty:
			known[key] = e
	p.knowledge[holder] = known
	return known


## Lo que `holder` puede contar al empezar la ronda; lo recibido en la anterior toma el id de la
## copia que BeliefNet haya creado o elevado.
func _entries_of(p: RumourPass, holder: String) -> Array[Dictionary]:
	var known: Dictionary = _knowledge(p, holder)
	if p.fresh.has(holder):
		for b: Belief in BeliefNet.get_beliefs_held_by(holder):
			var key: String = _key(b.subject, b.fact, b.location)
			if not b.is_record and known.has(key):
				var old: Dictionary = known[key]
				known[key] = _entry(b.id, b.subject, b.fact, b.location,
						maxf(b.certainty, float(old[E_CERTAINTY])), str(old[E_SOURCE]),
						bool(old[E_IN_SESSION]))
	var out: Array[Dictionary] = []
	for e: Dictionary in known.values():
		out.append(e)
	return out


static func _entry(id: String, subject: String, fact: String, location: String,
		certainty: float, source: String, in_session: bool) -> Dictionary:
	return {E_ID: id, E_SUBJECT: subject, E_FACT: fact, E_LOCATION: location,
			E_CERTAINTY: certainty, E_SOURCE: source, E_IN_SESSION: in_session}


static func _entry_key(e: Dictionary) -> String:
	return _key(str(e[E_SUBJECT]), str(e[E_FACT]), str(e[E_LOCATION]))


static func _key(subject: String, fact: String, location: String) -> String:
	return KEY_SEPARATOR.join([subject, fact, location])


## "`teller` se lo contó a `listener`" para una entrada.
static func _echo_key(entry_key: String, teller: String, listener: String) -> String:
	return KEY_SEPARATOR.join([entry_key, teller, listener])


func _log_chat(p: RumourPass, teller: String, to: String, e: Dictionary) -> void:
	if not p.readable:
		return
	_chat_log.append({
		K_DAY: GameClock.get_day(), K_HOUR: GameClock.get_hour(), "gathering": p.gathering_id,
		"from": teller, "to": to, "belief_id": str(e[E_ID]), E_SUBJECT: str(e[E_SUBJECT]),
		E_FACT: str(e[E_FACT]),
	})
	var cap: int = _bal_i(B_MAX_CHAT)
	while _chat_log.size() > maxi(cap, 0):
		_chat_log.pop_front()


func _note_session(p: RumourPass) -> void:
	var participants: Array[String] = []
	for npc_id: String in p.present:
		participants.append(npc_id)
	_sessions[p.gathering_id] = {
		K_DAY: GameClock.get_day(), K_HOUR: GameClock.get_hour(),
		K_MINUTE: GameClock.get_minute(), K_PARTICIPANTS: participants, K_SPREADS: p.spreads,
	}


## Extra (IT, §7.7 chat legible por IT): saltos registrados en corrillos readable_by_it
## (copia, el más antiguo primero). `gathering_id` "" = todos.
func get_chat_log(gathering_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _chat_log:
		if gathering_id.is_empty() or str(entry["gathering"]) == gathering_id:
			out.append(entry.duplicate())
	return out


## Extra (manos: borrado en los servidores de IT): vacía el registro del chat. Devuelve cuántas
## entradas había.
func purge_chat_log() -> int:
	var count: int = _chat_log.size()
	_chat_log.clear()
	return count


# ─── Presencia en los corrillos ───────────────────────────────

## Franja concreta → su sala programada es la del corrillo; sin sala (digital) → siempre;
## "any" / periódico → visitó la sala dentro de la ventana de la sesión.
func _is_present(npc: NPCRuntime, g: Dictionary, window: Vector2i) -> bool:
	var room: String = _text(g, G_ROOM)
	var band: String = _text(g, G_BAND)
	if room.is_empty() or band == BAND_CONTINUOUS:
		return true
	if not band.is_empty() and band != BAND_ANY:
		var scheduled: String = NPCDirector.get_scheduled_location(npc.id, band)
		return DatabaseSystem.get_room_base_id(scheduled) == room
	return _visited(npc.id, room, window, _whole(g, G_INTERVAL) > 0)


## Minutos del día [x, y) de la sesión que acaba ahora: periódico → (ahora − N h, ahora];
## "any" → desde el inicio de la franja que contiene el minuto anterior (la que acaba en un cambio
## de franja) hasta ahora.
func _session_window(g: Dictionary) -> Vector2i:
	var now: int = GameClock.get_hour() * MINUTES_PER_HOUR + GameClock.get_minute()
	var interval: int = _whole(g, G_INTERVAL)
	if interval > 0:
		return Vector2i(now - interval * MINUTES_PER_HOUR + 1, now + 1)
	return Vector2i(_band_start_before(now - 1), now)


## Inicio de la franja en curso en `minute`; 0 si empezó el día anterior (noche).
func _band_start_before(minute: int) -> int:
	var best: int = 0
	for band: String in _band_starts:
		var start: int = _band_starts[band]
		if start <= minute and start > best:
			best = start
	return best


## ¿Estuvo en `room` dentro de [window.x, window.y)? by_start: solo cuentan las visitas que
## EMPIEZAN en la ventana. La agenda propone; get_location_at confirma (prioridades,
## sustituciones de franja). Sin agenda: sala actual.
func _visited(npc_id: String, room: String, window: Vector2i, by_start: bool) -> bool:
	var plan: Array = NPCDirector.get_day_plan(npc_id)
	if plan.is_empty():
		return DatabaseSystem.get_room_base_id(NPCDirector.get_current_location(npc_id)) == room
	for entry: Variant in plan:
		var iv: Dictionary = entry
		var start: int = int(iv.get(PLAN_START, 0))
		var probe: int = start if by_start else maxi(start, window.x)
		if probe < window.x or probe >= window.y or int(iv.get(PLAN_END, 0)) <= probe:
			continue
		if DatabaseSystem.get_room_base_id(str(iv.get(PLAN_ROOM, ""))) == room \
				and _room_at(npc_id, probe) == room:
			return true
	return false


func _room_at(npc_id: String, minute: int) -> String:
	var hour: int = floori(float(minute) / MINUTES_PER_HOUR)
	var location: String = NPCDirector.get_location_at(npc_id, hour, minute - hour * MINUTES_PER_HOUR)
	return DatabaseSystem.get_room_base_id(location)


func _more_sociable(a: NPCRuntime, b: NPCRuntime) -> bool:
	var sa: int = a.get_trait(TRAIT_SOCIABILITY)
	var sb: int = b.get_trait(TRAIT_SOCIABILITY)
	return sa > sb or (sa == sb and a.id < b.id)


# ─── Rumores del jugador y del Director de Comunicación ───────

## El sujeto es el detalle del hecho si es un personaje ("steals_ideas:npc_x" → npc_x); si no,
## el jugador. Devuelve el id sintético ("" si el destino no es un personaje en plantilla).
func inject_rumour(target_npc: String, fact: String, certainty: float) -> String:
	return inject_rumour_about(target_npc, _subject_of_fact(fact), fact, certainty)


## Extra: inject_rumour con sujeto explícito. Replantar un hecho enterrado lo desentierra.
func inject_rumour_about(target_npc: String, subject: String, fact: String,
		certainty: float) -> String:
	if fact.is_empty() or subject.is_empty() or not _is_active_character(target_npc):
		return ""
	var id: String = RUMOUR_ID_PREFIX + str(_next_rumour)
	_next_rumour += 1
	_killed.erase(fact)
	_injected[id] = {
		"target": target_npc, E_SUBJECT: subject, E_FACT: fact,
		E_CERTAINTY: clampf(certainty, Belief.MIN_CERTAINTY, Belief.MAX_CERTAINTY),
		E_LOCATION: "", K_DAY: GameClock.get_day(),
	}
	EventBus.rumor_spread.emit(PLAYER_ID, target_npc, id)
	EventBus.crime_committed.emit(CRIME_RUMOUR_PLANTED, PlayerState.get_room(), {
		"target": target_npc, E_SUBJECT: subject, E_FACT: fact, "rumour_id": id,
	})
	return id


## Extra (protocolo BeliefNet): rumor plantado por el jugador ({} si no existe; copia).
func get_injected_rumour(rumour_id: String) -> Dictionary:
	return _injected.get(rumour_id, {}).duplicate()


## Extra (cuaderno): todos los rumores plantados, con su "id", en orden.
func get_injected_rumours() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _injected:
		var entry: Dictionary = _injected[id].duplicate()
		entry[E_ID] = id
		out.append(entry)
	return out


## Director de Comunicación. Entierra el hecho hasta el cambio de jornada (ver DECISIONES) y
## devuelve cuántas creencias de origen rumor lo afirman (las que BeliefNet olvidará entonces).
func kill_rumour(belief_fact: String) -> int:
	if belief_fact.is_empty():
		return 0
	_killed[belief_fact] = GameClock.get_day()
	var count: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		for b: Belief in BeliefNet.get_beliefs_held_by(npc.id):
			if b.source == Belief.SOURCE_RUMOR and b.fact == belief_fact:
				count += 1
	return count


## Extra (protocolo BeliefNet): true desde kill_rumour(fact) hasta el primer hour_passed de la
## jornada kill + grafo_social.dias_rumor_enterrado (BeliefNet ya decayó en ese day_advanced).
func is_fact_killed(belief_fact: String) -> bool:
	return _killed.has(belief_fact)


## Extra: hechos enterrados vigentes.
func get_killed_facts() -> Array[String]:
	var out: Array[String] = []
	for fact: String in _killed:
		out.append(fact)
	return out


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	var links: Array[Dictionary] = []
	for from: String in _links:
		for to: String in _links[from]:
			var link: Dictionary = _links[from][to]
			links.append({
				"from": from, "to": to, L_TYPE: link[L_TYPE], L_STRENGTH: link[L_STRENGTH],
				L_SECRET: link[L_SECRET], L_BENEFICIARY: link[L_BENEFICIARY],
			})
	return {
		"version": SAVE_VERSION, "links": links, "injected": _injected.duplicate(true),
		"next_rumour": _next_rumour, "killed": _killed.duplicate(),
		"chat_log": _chat_log.duplicate(true), "seat_links": _seat_links.duplicate(true),
		"sessions": _sessions.duplicate(true),
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


## Acepta guardados de versión <= SAVE_VERSION (la 1 no tenía seat_links ni sessions); una
## versión posterior se carga lo mejor posible con un aviso.
func load_state(data: Dictionary) -> void:
	_clear()
	_load_config()
	if int(data.get("version", SAVE_VERSION)) > SAVE_VERSION:
		push_warning("SocialGraph: save version %s is newer than %d" % [
				str(data.get("version")), SAVE_VERSION])
	for raw: Dictionary in _dicts_in(data.get("links")):
		_load_link(raw)
	var injected: Variant = data.get("injected", {})
	if injected is Dictionary:
		for id: Variant in injected:
			if injected[id] is Dictionary:
				_injected[str(id)] = _normalise_rumour(injected[id])
	var killed: Variant = data.get("killed", {})
	if killed is Dictionary:
		for fact: Variant in killed:
			_killed[str(fact)] = int(killed[fact])
	for raw: Dictionary in _dicts_in(data.get("chat_log")):
		_chat_log.append(_normalise_chat(raw))
	_load_seat_links(data.get("seat_links"))
	_load_sessions(data.get("sessions"))
	_next_rumour = maxi(int(data.get("next_rumour", 1)), 1)
	_rng.seed = str(data.get("rng_seed", str(GameClock.get_run_seed()))).to_int()
	_rng.state = str(data.get("rng_state", str(_rng.state))).to_int()


## Diccionarios de un Array guardado ([] si no es un Array).
static func _dicts_in(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				out.append(item)
	return out


func _load_link(raw: Dictionary) -> void:
	var from: String = str(raw.get("from", ""))
	var to: String = str(raw.get("to", ""))
	var link_type: String = str(raw.get(L_TYPE, ""))
	if from.is_empty() or to.is_empty() or _type_spec(link_type).is_empty():
		return
	_store(from, to, {
		L_TYPE: link_type, L_STRENGTH: float(raw.get(L_STRENGTH, 0.0)),
		L_SECRET: bool(raw.get(L_SECRET, false)), L_BENEFICIARY: str(raw.get(L_BENEFICIARY, "")),
	})


func _load_seat_links(value: Variant) -> void:
	if not (value is Dictionary):
		return
	for occupation_id: Variant in value:
		var raw: Variant = value[occupation_id]
		if not (raw is Dictionary):
			continue
		var parked: Dictionary = {}
		var subs: Dictionary = {}
		var raw_subs: Variant = raw.get(S_SUBORDINATES, {})
		if raw_subs is Dictionary:
			for sub: Variant in raw_subs:
				if raw_subs[sub] is Dictionary:
					subs[str(sub)] = _normalise_ref(raw_subs[sub])
		if not subs.is_empty():
			parked[S_SUBORDINATES] = subs
		if raw.get(S_SUPERIOR) is Dictionary:
			parked[S_SUPERIOR] = _normalise_ref(raw[S_SUPERIOR])
		if not parked.is_empty():
			_seat_links[str(occupation_id)] = parked


func _load_sessions(value: Variant) -> void:
	if not (value is Dictionary):
		return
	for gathering_id: Variant in value:
		var raw: Variant = value[gathering_id]
		if not (raw is Dictionary):
			continue
		var participants: Array[String] = []
		if raw.get(K_PARTICIPANTS) is Array:
			for npc_id: Variant in raw[K_PARTICIPANTS]:
				participants.append(str(npc_id))
		_sessions[str(gathering_id)] = {
			K_DAY: int(raw.get(K_DAY, 0)), K_HOUR: int(raw.get(K_HOUR, 0)),
			K_MINUTE: int(raw.get(K_MINUTE, 0)), K_PARTICIPANTS: participants,
			K_SPREADS: int(raw.get(K_SPREADS, 0)),
		}


static func _normalise_ref(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {
		S_OCCUPATION: str(raw.get(S_OCCUPATION, "")), L_STRENGTH: float(raw.get(L_STRENGTH, 0.0)),
	}
	if raw.has(S_TO):
		out[S_TO] = str(raw[S_TO])
	return out


static func _normalise_rumour(raw: Dictionary) -> Dictionary:
	return {
		"target": str(raw.get("target", "")), E_SUBJECT: str(raw.get(E_SUBJECT, "")),
		E_FACT: str(raw.get(E_FACT, "")), E_CERTAINTY: float(raw.get(E_CERTAINTY, 0.0)),
		E_LOCATION: str(raw.get(E_LOCATION, "")), K_DAY: int(raw.get(K_DAY, 0)),
	}


static func _normalise_chat(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["gathering", "from", "to", "belief_id", E_SUBJECT, E_FACT]:
		out[key] = str(raw.get(key, ""))
	out[K_DAY] = int(raw.get(K_DAY, 0))
	out[K_HOUR] = int(raw.get(K_HOUR, 0))
	return out


# ─── Reacciones a EventBus ────────────────────────────────────

## Franja concreta: la sesión se celebra al terminar la franja; "any": en cada cambio de franja.
func _on_time_band_changed(old_band: String, _new_band: String) -> void:
	for g: Dictionary in Database.get_all_gatherings():
		var band: String = _text(g, G_BAND)
		if band == BAND_ANY or (not band.is_empty() and band == old_band):
			propagate_at_gathering(str(g.get(G_ID, "")))


func _on_hour_passed(hour: int, day_number: int) -> void:
	_expire_burials(day_number)
	for g: Dictionary in Database.get_all_gatherings():
		if _text(g, G_BAND) == BAND_CONTINUOUS or _is_interval_hour(g, hour):
			propagate_at_gathering(str(g.get(G_ID, "")))


func _is_interval_hour(g: Dictionary, hour: int) -> bool:
	var interval: int = _whole(g, G_INTERVAL)
	if interval <= 0:
		return false
	var first: int = _bal_i(B_FIRST_PERIODIC)
	return hour >= first and hour < _bal_i(B_DAY_END) and (hour - first) % interval == 0


## Desentierra los hechos cuyo plazo venció (tras el day_advanced en que BeliefNet los olvidó).
func _expire_burials(day_number: int) -> void:
	var days: int = _bal_i(B_BURIED_DAYS)
	for fact: String in _killed.keys():
		if day_number - _killed[fact] >= days:
			_killed.erase(fact)


func _on_day_advanced(_day_number: int) -> void:
	_decay_debts()


## §7.7: la deuda suprime la denuncia temporalmente.
func _decay_debts() -> void:
	var rate: float = _bal_f(B_DEBT_DECAY)
	if rate <= 0.0:
		return
	for from: String in _links.keys():
		for to: String in (_links.get(from, {}) as Dictionary).keys():
			var link: Dictionary = _get_link(from, to)
			if link.is_empty() or not bool(_type_spec(str(link[L_TYPE])).get(T_SUPPRESSES, false)):
				continue
			var strength: float = float(link[L_STRENGTH]) - rate
			if strength <= 0.0 or is_zero_approx(strength):
				_erase(from, to)
			else:
				link[L_STRENGTH] = strength


## Un retirado (expulsado o eliminado) deja su jerarquía en su silla (Company aún la tiene a su
## nombre: su manejador corre después) y se borran todas sus aristas.
func _on_npc_removed(npc_id: String, _cause: String) -> void:
	var occupation_id: String = str(Company.get_npc_seat(npc_id).get(SEAT_OCCUPATION, ""))
	if not occupation_id.is_empty():
		_detach_from_seat(npc_id, occupation_id)
	_links.erase(npc_id)
	for from: String in _links.keys():
		_erase(from, npc_id)


## Un personaje en plantilla que deja su silla cambia de puesto: deja la jerarquía de la silla y
## a sus compañeros de departamento (§7.7).
func _on_seat_vacated(occupation_id: String, previous_holder: String, _cause: String) -> void:
	if previous_holder == PLAYER_ID or not NPCDirector.is_active(previous_holder):
		return
	_detach_from_seat(previous_holder, occupation_id)
	for link: Dictionary in get_links(previous_holder):
		if str(link[L_TYPE]) == LINK_DEPARTMENT:
			remove_link(str(link["from"]), str(link["to"]))


## El nuevo titular hereda la jerarquía que esperaba la silla (el jugador y los rookie no: sigue
## esperando).
func _on_seat_filled(occupation_id: String, new_holder: String) -> void:
	var active: Dictionary[String, bool] = _active_set()
	if new_holder == PLAYER_ID or not _may_link(new_holder, active):
		return
	var parked: Dictionary = _seat_links.get(occupation_id, {})
	_seat_links.erase(occupation_id)
	for link: Dictionary in get_links(new_holder):
		if str(link[L_TYPE]) == LINK_HIERARCHY and str(link["from"]) == new_holder:
			remove_link(new_holder, str(link["to"]))
	var subs: Dictionary = parked.get(S_SUBORDINATES, {})
	for sub: String in subs:
		var ref: Dictionary = subs[sub]
		if sub != new_holder and _may_link(sub, active) \
				and _occupation_of(sub) == str(ref[S_OCCUPATION]):
			_put(sub, new_holder, LINK_HIERARCHY, float(ref[L_STRENGTH]), {})
	_attach_superior(new_holder, parked.get(S_SUPERIOR, {}), active)


## Guarda en la silla los subordinados de `npc_id` y su superior, y borra esas jerarquías.
func _detach_from_seat(npc_id: String, occupation_id: String) -> void:
	var parked: Dictionary = _seat_links.get(occupation_id, {})
	var subs: Dictionary = parked.get(S_SUBORDINATES, {})
	for link: Dictionary in get_links(npc_id):
		if str(link[L_TYPE]) != LINK_HIERARCHY:
			continue
		var from: String = str(link["from"])
		var to: String = str(link["to"])
		if to == npc_id:
			subs[from] = {S_OCCUPATION: _occupation_of(from), L_STRENGTH: link[L_STRENGTH]}
		else:
			parked[S_SUPERIOR] = {S_TO: to, S_OCCUPATION: _occupation_of(to),
					L_STRENGTH: link[L_STRENGTH]}
		remove_link(from, to)
	if not subs.is_empty():
		parked[S_SUBORDINATES] = subs
	if not parked.is_empty():
		_seat_links[occupation_id] = parked


## Superior heredado: su titular sigue en su puesto → él; si no, el titular actual de ese puesto;
## si el puesto está vacante, el nuevo titular espera en él como subordinado. Sin superior
## heredado: superior_by_room de su sala.
func _attach_superior(holder: String, ref: Dictionary, active: Dictionary[String, bool]) -> void:
	var occupation_id: String = str(ref.get(S_OCCUPATION, ""))
	var boss: String = str(ref.get(S_TO, ""))
	if not NPCDirector.is_active(boss) or _occupation_of(boss) != occupation_id:
		boss = _holder_of(occupation_id) if not occupation_id.is_empty() else ""
	if boss.is_empty() and not occupation_id.is_empty():
		var parked: Dictionary = _seat_links.get(occupation_id, {})
		var subs: Dictionary = parked.get(S_SUBORDINATES, {})
		subs[holder] = {S_OCCUPATION: _occupation_of(holder), L_STRENGTH: ref.get(L_STRENGTH, 0.0)}
		parked[S_SUBORDINATES] = subs
		_seat_links[occupation_id] = parked
	elif not boss.is_empty():
		if boss != holder and _may_link(boss, active):
			_put(holder, boss, LINK_HIERARCHY, float(ref.get(L_STRENGTH, 0.0)), {})
	else:
		var npc: NPCRuntime = NPCDirector.get_npc(holder)
		if npc != null:
			_link_to_superior(npc, active)


func _occupation_of(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.occupation_id if npc != null else ""


# ─── Internos ─────────────────────────────────────────────────

func _clear() -> void:
	_links.clear()
	_injected.clear()
	_killed.clear()
	_chat_log.clear()
	_seat_links.clear()
	_sessions.clear()
	_next_rumour = 1
	_propagating = false


func _load_config() -> void:
	_types.clear()
	for spec: Dictionary in Database.get_all_social_link_types():
		_types[str(spec.get(G_ID, ""))] = spec
	_total_types = _bal_strings(B_TOTAL_TYPES)
	_absent_types = _bal_strings(B_ABSENT_TYPES)
	_unlinked_archetypes = _bal_strings(B_UNLINKED)
	_load_hierarchy_rules()
	_band_starts.clear()
	var starts: Variant = Database.get_balance(B_BAND_STARTS)
	if starts is Dictionary:
		for band: Variant in starts:
			if starts[band] is int or starts[band] is float:
				_band_starts[str(band)] = int(starts[band]) * MINUTES_PER_HOUR
	_config_loaded = true


## superior_by_room y el intervalo de fuerza de la jerarquía de npcs_generation.json.
func _load_hierarchy_rules() -> void:
	_superiors_by_room.clear()
	_hierarchy_strength.clear()
	var rules: Variant = Database.get_raw(GEN_FILE).get(GEN_LINKS, {})
	var hierarchy: Variant = rules.get(GEN_HIERARCHY, {}) if rules is Dictionary else {}
	if not (hierarchy is Dictionary):
		return
	var superiors: Variant = hierarchy.get(GEN_SUPERIORS, {})
	if superiors is Dictionary:
		for room: Variant in superiors:
			_superiors_by_room[str(room)] = str(superiors[room])
	var bounds: Variant = hierarchy.get(GEN_STRENGTH, [])
	if bounds is Array:
		for value: Variant in bounds:
			_hierarchy_strength.append(float(value))


func _type_spec(link_type: String) -> Dictionary:
	if not _config_loaded:
		_load_config()
	return _types.get(link_type, {})


func _is_directed(link_type: String) -> bool:
	return bool(_type_spec(link_type).get(T_DIRECTED, false))


## Crea (o sustituye) from → to con la fuerza acotada al intervalo del tipo (§31) y su reflejo si
## el tipo no es dirigido, salvo que to → from sea un vínculo dirigido (se conserva).
func _put(from: String, to: String, link_type: String, strength: float,
		flags: Dictionary) -> bool:
	var spec: Dictionary = _type_spec(link_type)
	if spec.is_empty() or from.is_empty() or to.is_empty() or from == to:
		push_warning("SocialGraph: invalid link %s -> %s (%s)" % [from, to, link_type])
		return false
	var beneficiary: String = str(flags.get(L_BENEFICIARY, ""))
	if beneficiary.is_empty() and bool(spec.get(T_BACKFIRES, false)):
		beneficiary = to
	var low: float = float(spec.get(T_STRENGTH_MIN, 0.0))
	var high: float = float(spec.get(T_STRENGTH_MAX, 1.0))
	var link: Dictionary = {
		L_TYPE: link_type, L_STRENGTH: clampf(strength, low, high),
		L_SECRET: bool(flags.get(L_SECRET, false)), L_BENEFICIARY: beneficiary,
	}
	_store(from, to, link)
	var back: Dictionary = _get_link(to, from)
	if not bool(spec.get(T_DIRECTED, false)) \
			and (back.is_empty() or not _is_directed(str(back[L_TYPE]))):
		_store(to, from, link.duplicate())
	return true


func _store(from: String, to: String, link: Dictionary) -> void:
	if not _links.has(from):
		_links[from] = {}
	_links[from][to] = link


func _erase(from: String, to: String) -> void:
	if not _links.has(from):
		return
	(_links[from] as Dictionary).erase(to)
	if (_links[from] as Dictionary).is_empty():
		_links.erase(from)


## Vínculo almacenado (referencia interna; no exponer).
func _get_link(from: String, to: String) -> Dictionary:
	return (_links.get(from, {}) as Dictionary).get(to, {})


func _describe(from: String, to: String, link: Dictionary) -> Dictionary:
	return {
		"from": from, "to": to, L_TYPE: link[L_TYPE], L_STRENGTH: link[L_STRENGTH],
		"directed": _is_directed(str(link[L_TYPE])), L_SECRET: link[L_SECRET],
		L_BENEFICIARY: link[L_BENEFICIARY],
	}


func _is_blackmail_link(link: Dictionary) -> bool:
	if link.is_empty() or not bool(link.get(L_SECRET, false)):
		return false
	return bool(_type_spec(str(link[L_TYPE])).get(T_BLACKMAIL, false))


func _has_any_link(a: String, b: String) -> bool:
	return not _get_link(a, b).is_empty() or not _get_link(b, a).is_empty()


func _has_link_of_type(npc_id: String, link_type: String) -> bool:
	return _count_of_type(npc_id, link_type) > 0


## Vínculos salientes de ese tipo (los no dirigidos cuentan también los reflejos).
func _count_of_type(npc_id: String, link_type: String) -> int:
	var count: int = 0
	var outgoing: Dictionary = _links.get(npc_id, {})
	for to: String in outgoing:
		if str(outgoing[to][L_TYPE]) == link_type:
			count += 1
	return count


func _active_set() -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		out[npc.id] = true
	return out


## Extremo válido: en plantilla (si hay población) y sin arquetipo sin vínculos.
func _may_link(npc_id: String, active: Dictionary[String, bool]) -> bool:
	if npc_id.is_empty() or (not active.is_empty() and not active.has(npc_id)):
		return false
	return not _unlinked_archetypes.has(_archetype_of(npc_id))


func _archetype_of(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null:
		return npc.archetype
	var named: NPCData = Database.get_named_npc(npc_id)
	return named.archetype if named != null else ""


func _is_character(npc_id: String) -> bool:
	if npc_id.is_empty() or npc_id == PLAYER_ID:
		return false
	return NPCDirector.get_npc(npc_id) != null or Database.get_named_npc(npc_id) != null


## Destino de un rumor: personaje en plantilla (sin población: un nominado de npcs_named.json).
func _is_active_character(npc_id: String) -> bool:
	if not _is_character(npc_id):
		return false
	if NPCDirector.get_npc(npc_id) != null:
		return NPCDirector.is_active(npc_id)
	return NPCDirector.get_all_npcs().is_empty()


func _subject_of_fact(fact: String) -> String:
	var detail: String = BeliefNetSystem.fact_detail_of(fact)
	return detail if _is_character(detail) else PLAYER_ID


## Texto de un campo de datos ("" si falta o es null).
static func _text(d: Dictionary, key: String) -> String:
	return str(d[key]) if d.get(key) is String else ""


## Entero de un campo de datos (0 si falta o es null).
static func _whole(d: Dictionary, key: String) -> int:
	var value: Variant = d.get(key)
	return int(value) if value is int or value is float else 0


func _bal_f(path: String) -> float:
	return Database.get_balance_float(path)


func _bal_i(path: String) -> int:
	return Database.get_balance_int(path)


func _bal_strings(path: String) -> Array[String]:
	var out: Array[String] = []
	var value: Variant = Database.get_balance(path)
	if value is Array:
		for item: Variant in value:
			out.append(str(item))
	return out
