# social_graph.gd — Vínculos entre personajes y propagación de creencias en los corrillos.
# PROPIETARIO DE: los vínculos entre personajes (siete tipos, §7.7), los rumores plantados por el jugador, los hechos enterrados por kill_rumour, el registro del chat legible por IT y el RNG de propagación (§19.6).
# ESCUCHA: time_band_changed, hour_passed, day_advanced, npc_removed.
class_name SocialGraphSystem
extends Node

## Manual §7.7, §7.13, §8.3, §19.6, §24.3 paso 5, §31; PASO 15; BUILD_NOTES §2, §6, §13.
## DECISIONES (contrato para el resto de sistemas):
##  · Vínculo = arista from → to {type, strength, secret, beneficiary}; una por par ordenado
##    (add_link sustituye). Los tipos con directed = false (social_graph.json) se reflejan en
##    ambos sentidos; hierarchy va del subordinado al superior; debt del deudor al acreedor.
##    "player" puede ser extremo (add_link(npc, "player", "debt", f): el personaje le debe).
##  · get_links(npc) = salientes + entrantes que no son el reflejo de uno saliente, cada uno
##    {from, to, type, strength, directed, secret, beneficiary}. get_neighbours(npc, min) =
##    destinos salientes de cualquier tipo con fuerza >= min, sin "player".
##  · build_initial_graph(): vacía y construye. initial_links de npcs_named.json + §24.3 paso 5
##    para los generados (link_generation de npcs_generation.json: department/friendship/rivalry
##    dentro de su departamento, hierarchy hacia superior_by_room, parejas clandestinas con
##    secret_couple_probability) + fixed_generated_links (pareja de contabilidad entre quienes
##    comparten su corrillo). grafo_social.arquetipos_sin_vinculos (rookie) no recibe aristas
##    (§8.3: Sonia Vail queda aislada aunque npcs_named.json declare la amistad de Debbie),
##    salvo las fijas de diseño. Sin población en NPCDirector solo hay vínculos nominados.
##    Un generado recibe primero su jerarquía y después sortea department/friendship/rivalry
##    entre compañeros con los que aún no tiene vínculo (una relación por par); la pareja
##    clandestina también elige a alguien sin vínculo previo. Fuerzas redondeadas a
##    grafo_social.paso_fuerza.
##  · Propagación (propagate_at_gathering): grafo_social.rondas_por_corrillo rondas; en cada
##    una, cada participante habla con sus vínculos presentes (o ausentes si el tipo está en
##    grafo_social.tipos_alcanzan_ausentes: la información relevante asciende al superior) con
##    probabilidad clamp(fuerza × amplificación del corrillo × propagation_bonus × sociabilidad
##    ÷ grafo_social.sociabilidad_referencia, 0, 1) (tipos_propagacion_total: siempre) y le
##    cuenta lo que sabía al empezar la ronda. Certeza nueva = certeza × get_transfer_factor
##    (degradación del tipo, §7.2/§7.13: 0,35 → 0,26 por departamento; la rivalidad amplifica
##    ×1,15), acotada a 1. No se cuenta un rumor a su sujeto, ni a quien ya lo sabe (con
##    cualquier certeza: sin eco que lo infle entre rivales), ni por debajo de
##    creencias.umbral_olvido. La amplificación del corrillo y la sociabilidad deciden el
##    VOLUMEN (quién habla), no la certeza.
##  · Tipos de propagación: all; negative_only (hechos con BeliefNet.is_negative_fact);
##    relevant_only (negativos o con sujeto "player"); none (deuda).
##  · PROTOCOLO CON BeliefNet (un autoload no muta otro): SocialGraph NO crea creencias. Por
##    cada salto emite rumor_spread(from, to, belief_id) y BeliefNet, suscrito, hace:
##      - from == "player" (inject_rumour): belief_id es sintético ("rumour_N"); crea en `to`
##        la creencia de origen "rumor" descrita por get_injected_rumour(id) {target, subject,
##        fact, certainty, location, day}.
##      - resto: transfer_belief(belief_id, to, get_transfer_factor(from, to, fact, subject)).
##      - ignora los rumores con is_fact_killed(fact) y los olvida en su decaimiento diario.
##    belief_id es la creencia del emisor en BeliefNet (en rondas posteriores se busca su copia
##    con get_beliefs_held_by; si BeliefNet no la creó, se usa el id de origen).
##  · kill_rumour(fact): entierra el hecho grafo_social.dias_rumor_enterrado jornadas
##    (is_fact_killed), deja de propagarse y devuelve cuántas creencias de origen rumor lo
##    afirman.
##  · inject_rumour emite crime_committed("rumour_planted") (quien llame no debe repetirlo).
##  · Calendario: franja concreta (cafeteria_clan: lunch) y "any" → time_band_changed;
##    "all_including_night" (chat_3b) → cada hour_passed; interval_hours (fumadores) →
##    hour_passed cada N horas desde grafo_social.hora_primer_corrillo_periodico hasta
##    tiempo.hora_fin_jornada.
##  · Participantes: personajes en plantilla con el corrillo en NPCRuntime.gatherings; franja
##    concreta → sala programada de esa franja = sala del corrillo; sin sala (chat) → siempre;
##    resto → presentes en el edificio. Tope max_participants: nominados primero y después los
##    generados más sociables.
##  · La deuda suprime la denuncia temporalmente: pierde grafo_social.deuda_decaimiento_diario
##    de fuerza por jornada y desaparece al llegar a 0. npc_removed borra las aristas del
##    retirado.
##  · Los corrillos readable_by_it (chat_3b) dejan cada salto en get_chat_log() (tope
##    grafo_social.max_entradas_chat).

const PLAYER_ID := "player"
const SAVE_VERSION := 1
const RUMOUR_ID_PREFIX := "rumour_"
const CRIME_RUMOUR_PLANTED := "rumour_planted"
const KEY_SEPARATOR := "\u001f"
const TRAIT_SOCIABILITY := "sociability"
const NEUTRAL_BONUS := 1.0

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
const SUPERIOR_OCC_PREFIX := "occ:"
const SUPERIOR_ROLE_PREFIX := "role:"
const NPC_ROLE_GETTER := "get_role"

# Claves de vínculo y de guardado.
const L_TYPE := "type"
const L_STRENGTH := "strength"
const L_SECRET := "secret"
const L_BENEFICIARY := "beneficiary"

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
const B_TRANSMISSION := "creencias.descuento_por_transmision"
const B_AMPLIFICATION_MAX := "creencias.amplificacion_rumor_max"
const B_FORGET := "creencias.umbral_olvido"
const B_DAY_END := "tiempo.hora_fin_jornada"


## Estado transitorio de una sesión de propagation_at_gathering (no se guarda).
class RumourPass extends RefCounted:
	var gathering_id: String = ""
	var amplification: float = 0.0
	var readable: bool = false
	var forget: float = 0.0
	var present: Dictionary[String, bool] = {}
	var active: Dictionary[String, bool] = {}
	## portador → {clave (sujeto, hecho, lugar) → {id, subject, fact, location, certainty}}.
	var knowledge: Dictionary[String, Dictionary] = {}
	## Portadores que recibieron algo en la ronda anterior (su id se resuelve en BeliefNet).
	var fresh: Dictionary[String, bool] = {}
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
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _propagating: bool = false
# Caché de datos estáticos (social_graph.json y listas de balance), recargada en cada partida.
var _config_loaded: bool = false
var _types: Dictionary[String, Dictionary] = {}
var _total_types: Array[String] = []
var _absent_types: Array[String] = []
var _unlinked_archetypes: Array[String] = []


func _ready() -> void:
	EventBus.time_band_changed.connect(_on_time_band_changed)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.npc_removed.connect(_on_npc_removed)


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
	_build_generated_links(npcs, rules.get(GEN_LINKS, {}))
	_build_fixed_links(npcs, rules.get(GEN_FIXED, []))


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


func _build_generated_links(npcs: Array[NPCRuntime], rules: Dictionary) -> void:
	var peers_by_dept: Dictionary = {}
	var active: Dictionary[String, bool] = {}
	for npc: NPCRuntime in npcs:
		active[npc.id] = true
	for npc: NPCRuntime in npcs:
		if _may_link(npc.id, active):
			if not peers_by_dept.has(npc.department):
				peers_by_dept[npc.department] = []
			peers_by_dept[npc.department].append(npc.id)
	var couple_chance: float = float(rules.get(GEN_COUPLE_PROBABILITY, 0.0))
	for npc: NPCRuntime in npcs:
		if npc.is_named or not _may_link(npc.id, active):
			continue
		var peers: Array = peers_by_dept.get(npc.department, [])
		_link_to_superior(npc, rules.get(GEN_HIERARCHY, {}), active)
		for link_type: String in [LINK_DEPARTMENT, LINK_FRIENDSHIP, LINK_RIVALRY]:
			_pick_links(npc.id, peers, link_type, _rule_range(rules, link_type))
		_maybe_secret_couple(npc.id, peers, couple_chance)


## "department" → Vector2i(department_links_min, department_links_max).
static func _rule_range(rules: Dictionary, link_type: String) -> Vector2i:
	return Vector2i(int(rules.get(link_type + GEN_MIN_SUFFIX, 0)),
			int(rules.get(link_type + GEN_MAX_SUFFIX, 0)))


func _pick_links(from: String, peers: Array, link_type: String, amount: Vector2i) -> void:
	var wanted: int = _rng.randi_range(amount.x, amount.y) if amount.y > 0 else 0
	if wanted <= 0:
		return
	for to: String in _shuffled(peers):
		if wanted <= 0:
			return
		if to != from and not _has_any_link(from, to):
			_put(from, to, link_type, _roll_strength(link_type), {})
			wanted -= 1


func _link_to_superior(npc: NPCRuntime, rules: Dictionary,
		active: Dictionary[String, bool]) -> void:
	var superiors: Dictionary = rules.get(GEN_SUPERIORS, {})
	var boss: String = _resolve_superior(str(superiors.get(npc.home_room, "")))
	if boss.is_empty() or boss == npc.id or not _may_link(boss, active):
		return
	var bounds: Array = rules.get(GEN_STRENGTH, [])
	var strength: float = _roll_between(float(bounds[0]), float(bounds[1])) \
			if bounds.size() >= 2 else _roll_strength(LINK_HIERARCHY)
	_put(npc.id, boss, LINK_HIERARCHY, strength, {})


## Valor de superior_by_room: id de personaje, "occ:<ocupación>" o "role:<puesto>".
func _resolve_superior(token: String) -> String:
	if token.begins_with(SUPERIOR_OCC_PREFIX):
		var holder: NPCRuntime = NPCDirector.get_npc_by_occupation(
				token.trim_prefix(SUPERIOR_OCC_PREFIX))
		return holder.id if holder != null else ""
	if token.begins_with(SUPERIOR_ROLE_PREFIX):
		if not NPCDirector.has_method(NPC_ROLE_GETTER):
			return ""
		var role: String = token.trim_prefix(SUPERIOR_ROLE_PREFIX)
		for npc: NPCRuntime in NPCDirector.get_all_npcs():
			if str(NPCDirector.call(NPC_ROLE_GETTER, npc.id)) == role:
				return npc.id
		return ""
	return token


func _maybe_secret_couple(npc_id: String, peers: Array, chance: float) -> void:
	if chance <= 0.0 or _rng.randf() >= chance or _has_link_of_type(npc_id, LINK_COUPLE):
		return
	for to: String in _shuffled(peers):
		if to != npc_id and not _has_any_link(npc_id, to) \
				and not _has_link_of_type(to, LINK_COUPLE):
			_put(npc_id, to, LINK_COUPLE, _roll_strength(LINK_COUPLE), {L_SECRET: true})
			return


## Vínculos fijos de diseño (pareja de contabilidad): entre quienes comparten el corrillo, por
## parejas en orden de plantilla. No aplican arquetipos_sin_vinculos (contenido intencionado).
func _build_fixed_links(npcs: Array[NPCRuntime], specs: Array) -> void:
	for spec: Variant in specs:
		if not (spec is Dictionary):
			continue
		var gathering: String = str(spec.get("gathering", spec.get(G_ID, "")))
		var members: Array[String] = []
		for npc: NPCRuntime in npcs:
			if npc.gatherings.has(gathering):
				members.append(npc.id)
		var flags: Dictionary = {L_SECRET: bool(spec.get(L_SECRET, false))}
		for i: int in range(0, members.size() - 1, 2):
			_put(members[i], members[i + 1], str(spec.get(L_TYPE, "")),
					float(spec.get(L_STRENGTH, 0.0)), flags)


func _roll_strength(link_type: String) -> float:
	var spec: Dictionary = _type_spec(link_type)
	return _roll_between(float(spec.get(T_STRENGTH_MIN, 0.0)), float(spec.get(T_STRENGTH_MAX, 0.0)))


## Fuerza sorteada en [low, high], redondeada a grafo_social.paso_fuerza.
func _roll_between(low: float, high: float) -> float:
	var value: float = _rng.randf_range(low, high)
	var step: float = _bal_f(B_STRENGTH_STEP)
	return clampf(snappedf(value, step), low, high) if step > 0.0 else value


## Copia barajada con el RNG del sistema (Fisher-Yates).
func _shuffled(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(str(value))
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


## Un tipo no dirigido se borra en ambos sentidos; uno dirigido, solo from → to.
func remove_link(from_npc: String, to_npc: String) -> void:
	var link: Dictionary = _get_link(from_npc, to_npc)
	if link.is_empty():
		return
	_erase(from_npc, to_npc)
	var mirror: Dictionary = _get_link(to_npc, from_npc)
	if not _is_directed(str(link[L_TYPE])) and str(mirror.get(L_TYPE, "")) == str(link[L_TYPE]):
		_erase(to_npc, from_npc)


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
## de chantaje). Afecta a ambos sentidos si existen. false si no hay vínculo.
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

func get_gathering_participants(gathering_id: String) -> Array[String]:
	var g: Dictionary = Database.get_gathering(gathering_id)
	var named: Array[String] = []
	var generated: Array[NPCRuntime] = []
	if g.is_empty():
		return named
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not npc.gatherings.has(gathering_id) or not _is_present(npc, g):
			continue
		if npc.is_named:
			named.append(npc.id)
		else:
			generated.append(npc)
	generated.sort_custom(_more_sociable)
	for npc: NPCRuntime in generated:
		named.append(npc.id)
	var cap: int = int(g.get(G_MAX, 0)) if g.get(G_MAX) != null else 0
	if cap > 0 and named.size() > cap:
		named.resize(cap)
	return named


## Devuelve nº de propagaciones (saltos emitidos como rumor_spread).
func propagate_at_gathering(gathering_id: String) -> int:
	var g: Dictionary = Database.get_gathering(gathering_id)
	if g.is_empty() or _propagating:
		return 0
	var p: RumourPass = _begin_pass(gathering_id, g)
	if p.present.is_empty():
		return 0
	_propagating = true
	for _round: int in _bal_i(B_ROUNDS):
		if _run_round(p) == 0:
			break
	_propagating = false
	return p.spreads


func _begin_pass(gathering_id: String, g: Dictionary) -> RumourPass:
	var p: RumourPass = RumourPass.new()
	p.gathering_id = gathering_id
	p.amplification = float(g.get(G_AMPLIFICATION, 0.0))
	p.readable = bool(g.get(G_READABLE, false))
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
		if said[teller].is_empty():
			continue
		for to: String in (_links.get(teller, {}) as Dictionary).keys():
			var link: Dictionary = _get_link(teller, to)
			if not link.is_empty() and _may_hear(p, to, link) and _pair_talks(p, teller, link):
				_tell_all(p, teller, to, str(link[L_TYPE]), said[teller])
	return p.spreads - before


func _may_hear(p: RumourPass, listener: String, link: Dictionary) -> bool:
	if listener == PLAYER_ID or not p.active.has(listener):
		return false
	return p.present.has(listener) or _absent_types.has(str(link[L_TYPE]))


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


func _tell_all(p: RumourPass, teller: String, to: String, link_type: String,
		entries: Array) -> void:
	var heard: Dictionary = _knowledge(p, to)
	for e: Dictionary in entries:
		var key: String = _entry_key(e)
		if str(e["subject"]) == to or heard.has(key):
			continue
		var factor: float = _link_factor(link_type, str(e["fact"]), str(e["subject"]))
		var certainty: float = minf(float(e["certainty"]) * factor, Belief.MAX_CERTAINTY)
		if factor <= 0.0 or certainty < p.forget:
			continue
		heard[key] = _entry(str(e["id"]), str(e["subject"]), str(e["fact"]),
				str(e["location"]), certainty)
		p.fresh[to] = true
		p.spreads += 1
		_log_chat(p, teller, to, e)
		EventBus.rumor_spread.emit(teller, to, str(e["id"]))


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
		var e: Dictionary = _entry(b.id, b.subject, b.fact, b.location, b.certainty)
		var key: String = _entry_key(e)
		if not known.has(key) or float(known[key]["certainty"]) < b.certainty:
			known[key] = e
	p.knowledge[holder] = known
	return known


## Lo que `holder` puede contar al empezar la ronda; lo recibido en la anterior toma el id de la
## copia que BeliefNet haya creado.
func _entries_of(p: RumourPass, holder: String) -> Array:
	var known: Dictionary = _knowledge(p, holder)
	if p.fresh.has(holder):
		for b: Belief in BeliefNet.get_beliefs_held_by(holder):
			var key: String = _key(b.subject, b.fact, b.location)
			if not b.is_record and known.has(key):
				known[key] = _entry(b.id, b.subject, b.fact, b.location,
						maxf(b.certainty, float(known[key]["certainty"])))
	return known.values()


static func _entry(id: String, subject: String, fact: String, location: String,
		certainty: float) -> Dictionary:
	return {"id": id, "subject": subject, "fact": fact, "location": location,
			"certainty": certainty}


static func _entry_key(e: Dictionary) -> String:
	return _key(str(e["subject"]), str(e["fact"]), str(e["location"]))


static func _key(subject: String, fact: String, location: String) -> String:
	return KEY_SEPARATOR.join([subject, fact, location])


func _log_chat(p: RumourPass, teller: String, to: String, e: Dictionary) -> void:
	if not p.readable:
		return
	_chat_log.append({
		"day": GameClock.get_day(), "hour": GameClock.get_hour(), "gathering": p.gathering_id,
		"from": teller, "to": to, "belief_id": str(e["id"]), "subject": str(e["subject"]),
		"fact": str(e["fact"]),
	})
	var cap: int = _bal_i(B_MAX_CHAT)
	while _chat_log.size() > maxi(cap, 0):
		_chat_log.pop_front()


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


# ─── Rumores del jugador y del Director de Comunicación ───────

## El sujeto es el detalle del hecho si es un personaje ("steals_ideas:npc_x" → npc_x); si no,
## el jugador. Devuelve el id sintético ("" si el destino no es un personaje).
func inject_rumour(target_npc: String, fact: String, certainty: float) -> String:
	return inject_rumour_about(target_npc, _subject_of_fact(fact), fact, certainty)


## Extra: inject_rumour con sujeto explícito. Replantar un hecho enterrado lo desentierra.
func inject_rumour_about(target_npc: String, subject: String, fact: String,
		certainty: float) -> String:
	if fact.is_empty() or subject.is_empty() or not _is_character(target_npc):
		return ""
	var id: String = RUMOUR_ID_PREFIX + str(_next_rumour)
	_next_rumour += 1
	_killed.erase(fact)
	_injected[id] = {
		"target": target_npc, "subject": subject, "fact": fact,
		"certainty": clampf(certainty, Belief.MIN_CERTAINTY, Belief.MAX_CERTAINTY),
		"location": "", "day": GameClock.get_day(),
	}
	EventBus.rumor_spread.emit(PLAYER_ID, target_npc, id)
	EventBus.crime_committed.emit(CRIME_RUMOUR_PLANTED, PlayerState.get_room(), {
		"target": target_npc, "subject": subject, "fact": fact, "rumour_id": id,
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
		entry["id"] = id
		out.append(entry)
	return out


## Director de Comunicación. Entierra el hecho (deja de propagarse; BeliefNet olvida sus rumores)
## y devuelve cuántas creencias de origen rumor lo afirman ahora.
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


## Extra (protocolo BeliefNet): true durante grafo_social.dias_rumor_enterrado jornadas tras
## kill_rumour(fact).
func is_fact_killed(belief_fact: String) -> bool:
	if not _killed.has(belief_fact):
		return false
	return GameClock.get_day() - _killed[belief_fact] < _bal_i(B_BURIED_DAYS)


## Extra: hechos enterrados vigentes.
func get_killed_facts() -> Array[String]:
	var out: Array[String] = []
	for fact: String in _killed:
		if is_fact_killed(fact):
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
		"chat_log": _chat_log.duplicate(true),
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


func load_state(data: Dictionary) -> void:
	_clear()
	_load_config()
	for raw: Variant in data.get("links", []):
		if raw is Dictionary:
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
	for raw: Variant in data.get("chat_log", []):
		if raw is Dictionary:
			_chat_log.append(_normalise_chat(raw))
	_next_rumour = maxi(int(data.get("next_rumour", 1)), 1)
	_rng.seed = str(data.get("rng_seed", str(GameClock.get_run_seed()))).to_int()
	_rng.state = str(data.get("rng_state", str(_rng.state))).to_int()


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


static func _normalise_rumour(raw: Dictionary) -> Dictionary:
	return {
		"target": str(raw.get("target", "")), "subject": str(raw.get("subject", "")),
		"fact": str(raw.get("fact", "")), "certainty": float(raw.get("certainty", 0.0)),
		"location": str(raw.get("location", "")), "day": int(raw.get("day", 0)),
	}


static func _normalise_chat(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["gathering", "from", "to", "belief_id", "subject", "fact"]:
		out[key] = str(raw.get(key, ""))
	out["day"] = int(raw.get("day", 0))
	out["hour"] = int(raw.get("hour", 0))
	return out


# ─── Reacciones a EventBus ────────────────────────────────────

func _on_time_band_changed(_old_band: String, new_band: String) -> void:
	for g: Dictionary in Database.get_all_gatherings():
		var band: String = str(g.get(G_BAND, "")) if g.get(G_BAND) != null else ""
		if band == new_band or band == BAND_ANY:
			propagate_at_gathering(str(g.get(G_ID, "")))


func _on_hour_passed(hour: int, _day_number: int) -> void:
	for g: Dictionary in Database.get_all_gatherings():
		var band: String = str(g.get(G_BAND, "")) if g.get(G_BAND) != null else ""
		if band == BAND_CONTINUOUS or _is_interval_hour(g, hour):
			propagate_at_gathering(str(g.get(G_ID, "")))


func _is_interval_hour(g: Dictionary, hour: int) -> bool:
	var interval: int = int(g.get(G_INTERVAL, 0)) if g.get(G_INTERVAL) != null else 0
	if interval <= 0:
		return false
	var first: int = _bal_i(B_FIRST_PERIODIC)
	return hour >= first and hour < _bal_i(B_DAY_END) and (hour - first) % interval == 0


func _on_day_advanced(_day_number: int) -> void:
	_decay_debts()
	for fact: String in _killed.keys():
		if not is_fact_killed(fact):
			_killed.erase(fact)


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


## Un retirado (expulsado o eliminado) deja de socializar: se borran todas sus aristas.
func _on_npc_removed(npc_id: String, _cause: String) -> void:
	_links.erase(npc_id)
	for from: String in _links.keys():
		_erase(from, npc_id)


# ─── Internos ─────────────────────────────────────────────────

func _clear() -> void:
	_links.clear()
	_injected.clear()
	_killed.clear()
	_chat_log.clear()
	_next_rumour = 1
	_propagating = false


func _load_config() -> void:
	_types.clear()
	for spec: Dictionary in Database.get_all_social_link_types():
		_types[str(spec.get(G_ID, ""))] = spec
	_total_types = _bal_strings(B_TOTAL_TYPES)
	_absent_types = _bal_strings(B_ABSENT_TYPES)
	_unlinked_archetypes = _bal_strings(B_UNLINKED)
	_config_loaded = true


func _type_spec(link_type: String) -> Dictionary:
	if not _config_loaded:
		_load_config()
	return _types.get(link_type, {})


func _is_directed(link_type: String) -> bool:
	return bool(_type_spec(link_type).get(T_DIRECTED, false))


## Crea (o sustituye) from → to y su reflejo si el tipo no es dirigido.
func _put(from: String, to: String, link_type: String, strength: float,
		flags: Dictionary) -> bool:
	var spec: Dictionary = _type_spec(link_type)
	if spec.is_empty() or from.is_empty() or to.is_empty() or from == to:
		push_warning("SocialGraph: invalid link %s -> %s (%s)" % [from, to, link_type])
		return false
	var beneficiary: String = str(flags.get(L_BENEFICIARY, ""))
	if beneficiary.is_empty() and bool(spec.get(T_BACKFIRES, false)):
		beneficiary = to
	var link: Dictionary = {
		L_TYPE: link_type, L_STRENGTH: clampf(strength, 0.0, 1.0),
		L_SECRET: bool(flags.get(L_SECRET, false)), L_BENEFICIARY: beneficiary,
	}
	_store(from, to, link)
	if not bool(spec.get(T_DIRECTED, false)):
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
	var outgoing: Dictionary = _links.get(npc_id, {})
	for to: String in outgoing:
		if str(outgoing[to][L_TYPE]) == link_type:
			return true
	return false


func _active_set() -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		out[npc.id] = true
	return out


## Extremo válido al construir: en plantilla (si hay población) y sin arquetipo sin vínculos.
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


func _subject_of_fact(fact: String) -> String:
	var detail: String = BeliefNetSystem.fact_detail_of(fact)
	return detail if _is_character(detail) else PLAYER_ID


## Franja concreta → su sala programada es la del corrillo; sin sala (digital) → siempre;
## "any" / periódico → presente en el edificio.
func _is_present(npc: NPCRuntime, g: Dictionary) -> bool:
	var room: String = str(g[G_ROOM]) if g.get(G_ROOM) is String else ""
	var band: String = str(g[G_BAND]) if g.get(G_BAND) is String else ""
	if room.is_empty() or band == BAND_CONTINUOUS:
		return true
	if not band.is_empty() and band != BAND_ANY:
		var scheduled: String = NPCDirector.get_scheduled_location(npc.id, band)
		return DatabaseSystem.get_room_base_id(scheduled) == room
	return not NPCDirector.get_current_location(npc.id).is_empty()


func _more_sociable(a: NPCRuntime, b: NPCRuntime) -> bool:
	var sa: int = a.get_trait(TRAIT_SOCIABILITY)
	var sb: int = b.get_trait(TRAIT_SOCIABILITY)
	return sa > sb or (sa == sb and a.id < b.id)


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
