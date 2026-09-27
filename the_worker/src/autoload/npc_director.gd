# npc_director.gd — Estado completo de los personajes: población, rutinas, ánimo, registro, LOD y cuerpos.
# PROPIETARIO DE: personajes (NPCRuntime) y perfiles de puesto, ubicación estadística y rutinas, ánimo, mérito, registro de relaciones (§7.9), material de chantaje, cuerpos, nivel de detalle (§19.5, §20), estado de saqueo de los domicilios (§4.3) y vigilancia personal del jugador (§11.8).
# ESCUCHA: day_advanced, time_band_changed, hour_passed, room_entered, floor_changed, belief_created, belief_decayed, bribe_offered, bribe_result, npc_reported_player, seat_vacated, seat_filled, investigation_resolved, suspect_list_formed, case_went_cold, idea_acquired, idea_presented, blackmail_initiated, body_hidden, notebook_entry_added.
class_name NPCDirectorSystem
extends Node

## Manual §7.4-§7.9, §8.1, §19.5, §20, §24.2-§24.5; PASO 9, 16, 17, 40, 44.2; BUILD_NOTES §2, §13.
## DECISIONES (contrato para el resto de sistemas):
##  · get_all_npcs() / get_npcs_* devuelven solo personajes EN PLANTILLA (no retirados).
##    get_npc(id) devuelve cualquiera, también retirados. is_alive() = no eliminado (un expulsado
##    o jubilado sigue vivo); is_active() = vivo y en plantilla.
##  · npc.state es el estado de RUTINA: idle | slacking | absent | removed. Las decisiones de
##    utilidad no lo tocan: get_last_decision(npc) devuelve la última {action, trigger, day, minute}.
##  · Ubicación: current_room = sala de su agenda del día (NPCRoutinePlanner); "" = fuera del
##    edificio (floor = FLOOR_NONE). La agenda se aplica en time_band_changed, hour_passed y un
##    temporizador (LOD 0/1 cada lod.intervalo_medio_segundos, LOD 2 cada
##    lod.intervalo_estadistico_segundos) mientras el reloj corre, SALVO a los personajes que un nodo
##    del mundo sitúa con set_current_location(): esa sala manda hasta release_current_location()
##    o hasta que el personaje baja a LOD 2 (sin nodo, §20.1: posición inferida del horario).
##  · override_routine(npc, franja, sala) vale hasta el cambio de jornada; sala "" la anula. En la
##    franja en curso sitúa ya al personaje (también si lo situaba un nodo).
##  · Utilidad (§7.5) SOLO por eventos: belief_created (portador = personaje, sujeto = jugador,
##    hecho negativo según BeliefNet.is_negative_fact), time_band_changed (personajes presentes en
##    LOD 0/1) y bribe_offered (consultivo: el resultado real es de Bribery, §8.2). El término de
##    creencias suma la certeza de la creencia disparadora y de las demás creencias NEGATIVAS del
##    portador sobre el jugador (las positivas, p. ej. hard_worker, no cuentan). Las creencias
##    "reported:*" (eco de la denuncia), "caught_redhanded:*" (CaughtHandler, §12.2) y
##    "bribe_attempt:*" (Bribery) ni disparan ni suman. Una creencia que CRUZA hacia arriba
##    creencias.certeza_directa_completa por refuerzo (percepción parcial acumulable §7.2;
##    belief_decayed = «certeza cambiada») hace reevaluar a su portador una sola vez, como si
##    naciera con esa certeza (sin señal EXT nueva).
##  · Denuncias: npc_decided(npc, acción, resumen {channel, evidence_type, ...}) y
##    npc_reported_player(npc, tipo, peso, sala). A Seguridad: tipo = pieza "direct_witness"
##    (certeza ≥ creencias.certeza_directa_completa; peso investigaciones.pesos_evidencia.
##    testigo_directo) o "partial_witness" (testigo_parcial). Al superior (§12.2 company_man):
##    testigo directo → tipo = canal "superior" (BeliefNet: +10 y anotación en expediente;
##    Security: pieza × factor del canal); parcial → "partial_witness" con peso × npc.
##    factor_denuncia_superior. Una denuncia por personaje cada npc.dias_entre_denuncias jornadas,
##    cuente quien cuente la denuncia (también CaughtHandler y Blackmail). Deuda > 0 con el jugador
##    (registro o arista de deuda de SocialGraph) retira las denuncias del repertorio y consume
##    registro.deuda_consumida_por_silencio cada vez que calla. Callar solo guarda «silencio con
##    memoria» (Blackmail.add_material) si denunciar estaba disponible.
##  · Registro (§7.9): los agravios no decaen nunca. Causas atribuidas al jugador =
##    CompanySystem.PLAYER_CAUSES (una sola lista). remove_npc(id, causa del jugador) → agravio
##    seat_lost al retirado (si sigue vivo) y friend_sunk a sus amistades/pareja (SocialGraph).
##    seat_filled(ocupación, "player") → agravio promotion_stolen al candidato con mayor mérito ×
##    npc.puntuacion_ascenso_merito + ambición × npc.puntuacion_ascenso_ambicion; el favor de quien
##    asciende por una vacante del jugador lo dicta Company.get_last_fill_context().
##  · Precio del soborno: get_bribe_price_modifier / get_fair_bribe_price delegan en Bribery
##    (ledger_modifier_from, fair_price, offer_ratio): una sola fórmula y un solo juego de claves.
##  · Veredicto "other_guilty": Security.get_case_report(caso).culprit_innocent. Inocente
##    (incriminado o incidente del jugador) → agravio wrongful_conviction, friend_sunk a sus aliados
##    y remove_npc(culpable, "expelled"). Culpable de verdad → remove_npc(culpable, "convicted"):
##    sin agravios y sin vacante atribuida al jugador.
##  · Silla vaciada (seat_vacated) de un personaje EN PLANTILLA por una causa que no es un traslado
##    (CompanySystem.CAUSE_PROMOTED / CAUSE_REASSIGNED): deja la empresa (removed_cause = causa:
##    "retired", "fired"...), con los agravios de arriba si la causa es del jugador, y npc_removed
##    se emite DIFERIDO (al terminar Company su cadena de reposición; Company ya no tiene su silla).
##  · Contrataciones (§6.3 paso 2): seat_filled(ocupación, id) con un id desconocido que
##    Company.is_hire(id) confirma crea un Rookie (NPCPopulationGenerator.create_hire).
##  · Material de chantaje (NPCRuntime.blackmail_material, esquema de Blackmail): sobornos y
##    flagrancia los añaden Bribery y CaughtHandler. blackmail_player solo está disponible con
##    material retenido ("held") cuya exigencia ya vence; la decisión es informativa:
##    Blackmail.process_day emite blackmail_demanded.
##  · Cuerpos: remove_npc(id, "eliminated"|"elimination") crea el registro de cuerpo
##    (body_created) y después emite npc_removed. Cada hora y franja, un cuerpo no oculto en la
##    sala de un personaje presente se descubre (body_discovered). La ausencia la detecta Security.
##  · Perspicacia efectiva = rasgo + sospecha × (mod_sospecha_por_punto ÷ mod_perspicacia_por_punto)
##    + Security.get_guard_perception_bonus() si su ocupación está en npc.ocupaciones_vigilancia
##    (§7.10: el nivel de alerta solo afecta a los vigilantes). Perception no debe sumar ninguno
##    de los dos términos otra vez.
##  · LOD (§20): LOD 0 = sala del jugador y adyacentes (lod.radio_salas_completo) hasta
##    lod.max_agentes_completo; LOD 1 = misma planta hasta lod.max_agentes_medio; LOD 2 = resto.
##    Presupuesto total = SaveSystem.get_setting("max_agents") o lod.max_agentes_total. La sala
##    del jugador parte de PlayerState.get_room()/get_floor(). Siempre LOD 0 (sin contar ubicación
##    ni tope): force_full_lod(), lista corta (suspect_list_formed) y deuda con el jugador (registro
##    o arista de deuda de SocialGraph). set_lod() fija un nivel manual hasta clear_lod() (lo
##    forzado sigue mandando). Objetivos marcados (§13.4): el dueño de la lista es PlayerState; al
##    oír notebook_entry_added de la categoría "targets" (mark_target/unmark_target) se sincroniza
##    el motivo "marked_target" con PlayerState.get_marked_targets() (sync_marked_targets).
##  · Reputación del personaje: además resta la prensa viva que lo señala
##    (NewsFeed.get_suspicion_about(id) × npc.reputacion_por_peso_prensa: escándalo fabricado o
##    campaña activista contra un rival, §9.8/§7.11), lo que también rebaja su credibilidad.
##  · Domicilio (§4.3, NightOps): get_home_address() = npc.home_address (tipo de vivienda exterior).
##    is_at_home(): en plantilla, con domicilio, fuera del edificio según su agenda de ahora
##    (get_location_at vacío, sin nodo del mundo que lo sitúe) y con hora >=
##    noche.hora_llegada_domicilio o < tiempo.hora_inicio_jornada. El saqueo de su casa es estado
##    del personaje: mark_house_container_looted() (manos: NightOps) deja ese contenedor vacío
##    noche.dias_reposicion_botin jornadas (is_house_container_looted); get_house_loot_state() lo
##    expone con los robos sufridos. Se guarda con la partida.
##  · VIGILANCIA PERSONAL (§11.8, la lanza Endgame cuando Pearl Osgood informa a Voss):
##    begin_personal_surveillance(vigilante, jornadas, motivo) → LOD 0 forzado (motivo
##    "personal_surveillance"), + npc.vigilancia_personal.bonus_perspicacia en
##    get_effective_perception y SEGUIMIENTO: en las franjas npc.vigilancia_personal.
##    franjas_seguimiento su sala es la del jugador (dentro del edificio; una sustitución de
##    override_routine, p. ej. una reunión provocada, manda sobre el seguimiento). Con nodo del
##    mundo, el nodo lo hace caminar hacia get_follow_target() ("player"). Dura hasta el cambio de
##    jornada posterior a hoy + jornadas o end_personal_surveillance(). Se guarda con la partida.
##    report_player_to_superior(npc, sala): denuncia deliberada al superior (canal "superior",
##    certeza completa: BeliefNet +10 y anotación; Security pondera el canal).

const PLAYER_ID := "player"
const FLOOR_NONE := NPCRoutinePlanner.NO_FLOOR
const SAVE_CONTEXT := "save → npc_director"
const SAVE_VERSION := 1
const BODY_ID_PREFIX := "body_"
const ELIMINATION_CAUSES: Array[String] = ["eliminated", "elimination"]
## Causas de seat_vacated que no sacan al personaje de la plantilla (cambia de silla).
const STAFF_MOVE_CAUSES: Array[String] = [
	CompanySystem.CAUSE_PROMOTED, CompanySystem.CAUSE_REASSIGNED,
]
## Company: contrataciones de RR. HH. (seat_filled de un id nuevo) y contexto del último relleno.
const HIRE_CHECK := "is_hire"
const FILL_CONTEXT_GETTER := "get_last_fill_context"
const SEAT_GETTER := "get_npc_seat"
const VERDICT_OTHER_GUILTY := "other_guilty"
const STOLEN_IDEA_METHODS: Array[String] = ["overhear", "steal_file"]
## Creencias cuya reacción decide otro módulo: eco de la propia denuncia (BeliefNet),
## flagrancia (CaughtHandler, §12.2) e intento de soborno (Bribery, tabla de rechazo de §8.2).
const IGNORED_FACT_PREFIXES: Array[String] = ["reported", "caught_redhanded", "bribe_attempt"]
## Veredicto "other_guilty": expulsión atribuible al jugador (inocente) o condena justa.
const CAUSE_EXPELLED := "expelled"
const CAUSE_CONVICTED := "convicted"
## Clave del expediente de Security (get_case_report) que marca al condenado como inocente.
const CASE_CULPRIT_INNOCENT := "culprit_innocent"
const PROFILE_REPUTATION_DELTA := "reputation_delta"
const ALLY_LINK_TYPES: Array[String] = ["friendship", "couple"]
const RIVAL_LINK_TYPE := "rivalry"
const SETTING_MAX_AGENTS := "max_agents"
const BRIBE_REPORT_OUTCOMES: Array[String] = [
	"denounce", "denounced", "report", "reported", "denunciation",
]
const BRIBE_SILENT_OUTCOMES: Array[String] = ["silence_with_memory", "silent", "silence"]
## Ofertas que no llegan a producirse (sin fondos, datos inválidos): no tocan el registro.
const BRIBE_VOID_OUTCOMES: Array[String] = ["insufficient_funds", "invalid"]
const BRIBE_COUNTER_OUTCOMES: Array[String] = ["counteroffer", "counter_offer"]

# Tipos de agravio y favor (claves LEDGER_GRIEVANCE_* / LEDGER_FAVOUR_* en strings.csv).
const GRIEVANCE_SEAT_LOST := "seat_lost"
const GRIEVANCE_PROMOTION_STOLEN := "promotion_stolen"
const GRIEVANCE_WRONGFUL_CONVICTION := "wrongful_conviction"
const GRIEVANCE_FRIEND_SUNK := "friend_sunk"
const GRIEVANCE_IDEA_STOLEN := "idea_stolen"
const GRIEVANCE_BLACKMAILED := "blackmailed"
const GRIEVANCE_BRIBE_OFFENCE := "bribe_offence"
const FAVOUR_PROMOTION := "promotion"
const FAVOUR_BRIBE_PAID := "bribe_paid"
const GRIEVANCE_KEY_FORMAT := "LEDGER_GRIEVANCE_%s"
const FAVOUR_KEY_FORMAT := "LEDGER_FAVOUR_%s"
const STATE_KEY_FORMAT := "NPC_STATE_%s"
const LOD_KEY_FORMAT := "NPC_LOD_%d"

const TRIGGER_BELIEF := "belief"
const TRIGGER_BAND := "band"
const TRIGGER_BRIBE := "bribe"
## Disparador de una denuncia que decide la trama (report_player_to_superior).
const TRIGGER_PLOT := "plot"
const CHANNEL_SECURITY := "security"
const CHANNEL_SUPERIOR := "superior"
const EVIDENCE_DIRECT := "direct_witness"
const EVIDENCE_PARTIAL := "partial_witness"
const REASON_DEBT := "debt"
const REASON_SHORTLIST := "shortlist"
const REASON_MARKED_TARGET := "marked_target"
const REASON_SURVEILLANCE := "personal_surveillance"
const ACTIVITY_SURVEILLANCE := "surveillance"
## Claves de una vigilancia personal (también en save_state).
const SV_TARGET := "target"
const SV_UNTIL := "until_day"
const SV_REASON := "reason"
const NOTE_CATEGORY_TARGETS := PlayerStateSystem.NOTE_CATEGORY_TARGETS

const STATE_ABSENT := "absent"
const STATE_SLACKING := "slacking"
const STATE_REMOVED := "removed"
## Rangos del manual (no ajustes): afecto −100..100, temor 0-100 (§7.9), ánimo −1..1,
## reputación de personaje 0-100 (BUILD_NOTES §13).
const AFFECTION_LIMIT := 100
const FEAR_MAX := 100
const MOOD_LIMIT := 1.0
const REPUTATION_MAX := 100.0

# Rutas de balance.json.
const B_AFFECTION_PER_SEVERITY := "registro.afecto_por_gravedad_agravio"
const B_AFFECTION_PER_MAGNITUDE := "registro.afecto_por_magnitud_favor"
const B_SEV_SEAT := "registro.gravedad_silla_perdida"
const B_SEV_PROMOTION := "registro.gravedad_ascenso_arrebatado"
const B_SEV_CONVICTION := "registro.gravedad_condena_injusta"
const B_SEV_FRIEND := "registro.gravedad_amigo_hundido"
const B_SEV_IDEA := "registro.gravedad_idea_robada"
const B_SEV_BLACKMAIL := "registro.gravedad_chantaje_sufrido"
const B_SEV_BRIBE_REPORT := "registro.gravedad_soborno_denunciado"
const B_SEV_BRIBE_REFUSED := "registro.gravedad_soborno_rechazado"
const B_MAG_PROMOTION := "registro.magnitud_ascenso"
const B_MAG_BRIBE := "registro.magnitud_soborno_aceptado"
const B_DEBT_BRIBE := "registro.deuda_por_soborno_aceptado"
const B_DEBT_SILENCE := "registro.deuda_consumida_por_silencio"
const B_FEAR_BLACKMAIL := "registro.temor_por_chantaje"
const B_FEAR_SILENT := "registro.temor_por_silencio_soborno"
const B_MOOD_REGRESSION := "npc.animo_regresion_diaria"
const B_MOOD_PROMOTION := "npc.animo_por_ascenso"
const B_MOOD_SEAT_LOST := "npc.animo_por_silla_perdida"
const B_MOOD_CONVICTION := "npc.animo_por_condena"
const B_MOOD_IDEA := "npc.animo_por_idea_presentada"
## Salto de ánimo del retirado según el agravio que registra.
const REMOVAL_MOOD: Dictionary = {
	GRIEVANCE_SEAT_LOST: B_MOOD_SEAT_LOST, GRIEVANCE_WRONGFUL_CONVICTION: B_MOOD_CONVICTION,
}
const B_MERIT_PER_AMBITION := "npc.merito_diario_por_ambicion"
const B_MERIT_SABOTAGE := "npc.merito_sabotaje"
const B_REP_BASE := "npc.reputacion_base"
const B_REP_PER_TIER := "npc.reputacion_por_escalon"
const B_REP_PER_MERIT := "npc.reputacion_por_merito"
const B_REP_PER_SEVERITY := "npc.reputacion_por_gravedad_agravio"
const B_REP_PER_PRESS := "npc.reputacion_por_peso_prensa"
const B_SUPERIOR_FACTOR := "npc.factor_denuncia_superior"
const B_REPORT_COOLDOWN := "npc.dias_entre_denuncias"
const B_SCORE_MERIT := "npc.puntuacion_ascenso_merito"
const B_SCORE_AMBITION := "npc.puntuacion_ascenso_ambicion"
const B_DIRECT_CERTAINTY := "creencias.certeza_directa_completa"
const B_WEIGHT_DIRECT := "investigaciones.pesos_evidencia.testigo_directo"
const B_WEIGHT_PARTIAL := "investigaciones.pesos_evidencia.testigo_parcial"
const B_PER_POINT := "percepcion.mod_perspicacia_por_punto"
const B_SUSPICION_POINT := "percepcion.mod_sospecha_por_punto"
const B_GUARD_OCCUPATIONS := "npc.ocupaciones_vigilancia"
const B_LEVERAGE_WAIT := "chantaje.dias_espera_min"
const B_LOD_RADIUS := "lod.radio_salas_completo"
const B_LOD_MAX_FULL := "lod.max_agentes_completo"
const B_LOD_MAX_MEDIUM := "lod.max_agentes_medio"
const B_LOD_MAX_TOTAL := "lod.max_agentes_total"
const B_LOD_MEDIUM_SECONDS := "lod.intervalo_medio_segundos"
const B_LOD_STAT_SECONDS := "lod.intervalo_estadistico_segundos"
const B_HOME_ARRIVAL := "noche.hora_llegada_domicilio"
const B_DAY_START := "tiempo.hora_inicio_jornada"
const B_LOOT_RESTOCK := "noche.dias_reposicion_botin"
const B_SURVEILLANCE_BONUS := "npc.vigilancia_personal.bonus_perspicacia"
const B_SURVEILLANCE_BANDS := "npc.vigilancia_personal.franjas_seguimiento"
const B_EXTERIOR_FLOOR := "mundo.planta_exterior"
const HOUSE_LOOTED := "looted"
const HOUSE_BURGLARIES := "burglaries"
const HOUSE_LAST_DAY := "last_day"

## id → NPCRuntime (todos, también retirados).
var _npcs: Dictionary = {}
## Orden estable de iteración (orden de creación).
var _order: Array[String] = []
## id → perfil de puesto (NPCPopulationGenerator).
var _profiles: Dictionary = {}
## npc_id → {body_id, room_id, spot_id, hidden, discovered, discovered_by, day}.
var _bodies: Dictionary = {}
## npc_id → Array de motivos de LOD 0 forzado.
var _forced_lod: Dictionary = {}
## case_id → Array de ids de la lista corta.
var _shortlists: Dictionary = {}
## occupation_id → causa: vacantes abiertas por el jugador pendientes de ocupar.
var _player_vacancies: Dictionary = {}
## npc_id → jornada de su última denuncia (de cualquier sistema).
var _last_report: Dictionary = {}
## npc_id → {action, trigger, day, minute}: última decisión de utilidad.
var _last_decision: Dictionary = {}
## npc_id → nivel fijado con set_lod() hasta clear_lod().
var _lod_pins: Dictionary = {}
## belief_id → true: creencias que ya provocaron la reacción de certeza completa.
var _escalated: Dictionary = {}
## npc_id → {looted: {container_id: jornada}, burglaries: int, last_day: int} (§4.3).
var _house_loot: Dictionary = {}
## vigilante → {target, until_day, reason}: vigilancia personal del jugador (§11.8).
var _surveillance: Dictionary = {}
var _player_room: String = ""
var _player_floor: int = 0
var _day: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Caché de ejecución (se reconstruye; no se guarda).
var _planner: NPCRoutinePlanner = null
## npc_id → {day, plan}.
var _plans: Dictionary = {}
var _adjacency: Dictionary = {}
var _weights: Dictionary = {}
var _scales: Dictionary = {}
var _generation_rules: Dictionary = {}
var _emitting_report: bool = false
## npc_id → true: sala real fijada por un nodo del mundo (set_current_location); no se guarda.
var _world_located: Dictionary = {}
var _timer: Timer = null
var _tick: int = 0
var _statistical_every: int = 1
var _last_medium_minute: int = -1
var _last_statistical_minute: int = -1


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(_on_lod_tick)
	add_child(_timer)
	_connect_signals()


func _connect_signals() -> void:
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.time_band_changed.connect(_on_time_band_changed)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.floor_changed.connect(_on_floor_changed)
	EventBus.belief_created.connect(_on_belief_created)
	EventBus.bribe_offered.connect(_on_bribe_offered)
	EventBus.bribe_result.connect(_on_bribe_result)
	EventBus.npc_reported_player.connect(_on_npc_reported_player)
	EventBus.seat_vacated.connect(_on_seat_vacated)
	EventBus.seat_filled.connect(_on_seat_filled)
	EventBus.investigation_resolved.connect(_on_investigation_resolved)
	EventBus.suspect_list_formed.connect(_on_suspect_list_formed)
	EventBus.case_went_cold.connect(_on_case_went_cold)
	EventBus.idea_acquired.connect(_on_idea_acquired)
	EventBus.idea_presented.connect(_on_idea_presented)
	EventBus.blackmail_initiated.connect(_on_blackmail_initiated)
	EventBus.body_hidden.connect(_on_body_hidden)
	EventBus.belief_decayed.connect(_on_belief_decayed)
	EventBus.notebook_entry_added.connect(func(category: String, _k: String, _a: Array) -> void:
		if category == NOTE_CATEGORY_TARGETS:
			sync_marked_targets())


## Vacía la población. generate_population() la (re)crea.
func reset_for_new_run() -> void:
	_clear_population()
	_seed_player_position()
	_day = GameClock.get_day()
	_rng.seed = GameClock.get_run_seed()


## La sala y la planta del jugador parten de PlayerState (ya reiniciado, BUILD_NOTES §2).
func _seed_player_position() -> void:
	_player_room = PlayerState.get_room()
	_player_floor = PlayerState.get_floor()


func _clear_population() -> void:
	_npcs.clear()
	_order.clear()
	_profiles.clear()
	_bodies.clear()
	_forced_lod.clear()
	_shortlists.clear()
	_player_vacancies.clear()
	_last_report.clear()
	_last_decision.clear()
	_lod_pins.clear()
	_escalated.clear()
	_house_loot.clear()
	_surveillance.clear()
	_world_located.clear()
	_plans.clear()
	_planner = null
	_emitting_report = false
	_last_medium_minute = -1
	_last_statistical_minute = -1
	if _timer != null:
		_timer.stop()


# ─── Población ────────────────────────────────────────────────

## 23 nominados + plantilla generada (§24.3) con el RNG sembrado por la semilla de partida.
func generate_population() -> void:
	_clear_population()
	if not Database.is_loaded():
		push_error("NPCDirector.generate_population: Database no está cargada")
		return
	_day = GameClock.get_day()
	_rng.seed = GameClock.get_run_seed()
	_seed_player_position()
	var rules: Dictionary = Database.get_raw("npcs_generation")
	var generator: NPCPopulationGenerator = NPCPopulationGenerator.new(_rng, rules)
	generator.generate()
	for npc: NPCRuntime in generator.npcs:
		_register(npc, generator.profiles.get(npc.id, {}))
	_setup_runtime(rules, true)


func _register(npc: NPCRuntime, profile: Dictionary) -> void:
	_npcs[npc.id] = npc
	_order.append(npc.id)
	_profiles[npc.id] = profile


func _setup_runtime(rules: Dictionary, place_now: bool) -> void:
	_generation_rules = rules
	_planner = NPCRoutinePlanner.new(rules)
	_weights = UtilityAI.load_weights()
	_scales = UtilityAI.load_relation_scales()
	_build_adjacency()
	if place_now:
		_update_locations(_clock_minute(), NPCRuntime.LOD_FULL, NPCRuntime.LOD_STATISTICAL)
	refresh_lod()
	_configure_timer()


func get_npc(id: String) -> NPCRuntime:
	return _npcs.get(id) as NPCRuntime


## Personajes en plantilla (vivos y no retirados), en orden de creación.
func get_all_npcs() -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for id: String in _order:
		if _is_active(_npcs[id]):
			out.append(_npcs[id])
	return out


## Extra: personajes retirados (expulsados o eliminados).
func get_removed_npcs() -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for id: String in _order:
		if not _is_active(_npcs[id]):
			out.append(_npcs[id])
	return out


func get_npcs_in_room(room_id: String) -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for npc: NPCRuntime in get_all_npcs():
		if npc.current_room == room_id and not room_id.is_empty():
			out.append(npc)
	return out


func get_npcs_by_archetype(archetype: String) -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for npc: NPCRuntime in get_all_npcs():
		if npc.archetype == archetype:
			out.append(npc)
	return out


## Titular en plantilla con esa ocupación (el de menor índice de silla).
func get_npc_by_occupation(occupation_id: String) -> NPCRuntime:
	var holders: Array[NPCRuntime] = get_npcs_by_occupation(occupation_id)
	return holders[0] if not holders.is_empty() else null


## Extra: todos los titulares de una ocupación, ordenados por índice de silla.
func get_npcs_by_occupation(occupation_id: String) -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for npc: NPCRuntime in get_all_npcs():
		if npc.occupation_id == occupation_id and not occupation_id.is_empty():
			out.append(npc)
	out.sort_custom(func(a: NPCRuntime, b: NPCRuntime) -> bool:
		return get_seat_index(a.id) < get_seat_index(b.id))
	return out


## Extra: perfil de puesto {role, seat_index, shift, daily_wage, clearance, future_occupation,
## future_occupation_day, zone_floors, external, secrets, blackmail_secrets,
## knows_safe_combination, special}. Copia.
func get_profile(npc_id: String) -> Dictionary:
	return (_profiles.get(npc_id, {}) as Dictionary).duplicate(true)


## Extra: puesto no jugable (roles de npcs_generation.json); "" si ocupa una silla jugable.
func get_role(npc_id: String) -> String:
	return str(_profiles.get(npc_id, {}).get("role", ""))


func get_daily_wage(npc_id: String) -> int:
	return int(_profiles.get(npc_id, {}).get("daily_wage", 0))


func get_clearance(npc_id: String) -> int:
	return int(_profiles.get(npc_id, {}).get("clearance", 0))


## Extra: índice de silla dentro de su ocupación (-1 si no ocupa silla jugable).
func get_seat_index(npc_id: String) -> int:
	return int(_profiles.get(npc_id, {}).get("seat_index", -1))


## Extra: "day" | "night" para vigilantes; "" en el resto.
func get_shift(npc_id: String) -> String:
	return str(_profiles.get(npc_id, {}).get("shift", ""))


# ─── Rasgos ───────────────────────────────────────────────────

func get_trait(npc_id: String, trait_name: String) -> int:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.get_trait(trait_name) if npc != null else 0


func get_all_traits(npc_id: String) -> Dictionary:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.traits.duplicate() if npc != null else {}


## Perspicacia + sospecha × (mod_sospecha_por_punto ÷ mod_perspicacia_por_punto) (§7.10) + la
## bonificación de alerta de Security si es vigilante (npc.ocupaciones_vigilancia). Nunca < 0.
## Ya incluye ambos términos: Perception no debe volver a sumarlos.
func get_effective_perception(npc_id: String) -> int:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return 0
	var per_point: float = Database.get_balance_float(B_PER_POINT)
	var ratio: float = Database.get_balance_float(B_SUSPICION_POINT) / per_point \
			if per_point > 0.0 else 0.0
	var value: float = float(npc.get_trait("perception")) + PlayerState.get_suspicion() * ratio
	if is_guard(npc_id):
		value += float(Security.get_guard_perception_bonus())
	if _surveillance.has(npc_id):
		value += Database.get_balance_float(B_SURVEILLANCE_BONUS)
	return maxi(roundi(value), Validate.TRAIT_MIN)


## Extra: vigilante (ocupación en npc.ocupaciones_vigilancia): le afecta el nivel de alerta.
func is_guard(npc_id: String) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	var guards: Variant = Database.get_balance(B_GUARD_OCCUPATIONS)
	return npc != null and guards is Array and (guards as Array).has(npc.occupation_id)


# ─── Registro de relaciones (§7.9, PASO 17) ───────────────────

## Copia del registro: {affection, fear, debt, grievances[{type, severity, day}],
## favours[{type, magnitude, day}]}.
func get_ledger(npc_id: String) -> Dictionary:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.ledger.duplicate(true) if npc != null else {}


## Agravio permanente: reduce la afección y emite grievance_added.
func add_grievance(npc_id: String, type: String, severity: int) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return
	(npc.ledger["grievances"] as Array).append(
			{"type": type, "severity": severity, "day": _current_day()})
	_shift_affection(npc, -roundi(severity * Database.get_balance_float(B_AFFECTION_PER_SEVERITY)))
	EventBus.grievance_added.emit(npc_id, type, severity)


## Favor: aumenta la afección y emite favour_added.
func add_favour(npc_id: String, type: String, magnitude: int) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return
	(npc.ledger["favours"] as Array).append(
			{"type": type, "magnitude": magnitude, "day": _current_day()})
	_shift_affection(npc, roundi(magnitude * Database.get_balance_float(B_AFFECTION_PER_MAGNITUDE)))
	EventBus.favour_added.emit(npc_id, type, magnitude)


func get_affection(npc_id: String) -> int:
	return _ledger_int(npc_id, "affection")


func get_fear(npc_id: String) -> int:
	return _ledger_int(npc_id, "fear")


## Positiva: el personaje debe al jugador; negativa: el jugador le debe.
func get_debt(npc_id: String) -> int:
	return _ledger_int(npc_id, "debt")


## Extra (manos del juego): ajustes directos del registro.
func add_affection(npc_id: String, delta: int) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc != null:
		_shift_affection(npc, delta)


func add_fear(npc_id: String, delta: int) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc != null:
		npc.ledger["fear"] = clampi(int(npc.ledger["fear"]) + delta, 0, FEAR_MAX)


func add_debt(npc_id: String, delta: int) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return
	npc.ledger["debt"] = int(npc.ledger["debt"]) + delta
	refresh_lod()


## Extra: Σ gravedad de los agravios / Σ magnitud de los favores.
func get_grievance_total(npc_id: String) -> int:
	return _entries_total(npc_id, "grievances", "severity")


func get_favour_total(npc_id: String) -> int:
	return _entries_total(npc_id, "favours", "magnitude")


## Extra: multiplicador del precio justo del soborno (§7.9): los agravios lo encarecen y los
## favores lo abaratan. Fórmula única de Bribery.ledger_modifier_from sobre el registro
## (clamp(1 + Σgravedad × registro.precio_por_gravedad_agravio − Σmagnitud ×
## registro.precio_por_magnitud_favor, min, max)). 1 si no es un personaje.
func get_bribe_price_modifier(npc_id: String) -> float:
	var npc: NPCRuntime = get_npc(npc_id)
	return Bribery.ledger_modifier_from(npc.ledger) if npc != null else 1.0


## Extra: precio justo del favor (§8.2) tal como lo calcula Bribery.fair_price (salario ×
## multiplicador × registro × dificultad × sospecha). 0 si no es un personaje.
func get_fair_bribe_price(npc_id: String, favour_type: String) -> int:
	var npc: NPCRuntime = get_npc(npc_id)
	return Bribery.fair_price(npc, favour_type) if npc != null else 0


## Extra: contribución del registro a la utilidad de denunciar (término relación de §7.5 para
## report_to_security). Positiva = acelera la denuncia (agravios); negativa = la frena (favores,
## deuda, temor, afecto).
func get_denunciation_bias(npc_id: String) -> float:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return 0.0
	var w: Dictionary = _utility_weights().get(UtilityAI.REPORT_TO_SECURITY, {})
	return UtilityAI.relation_term(w, npc.ledger, _relation_scales())


# ─── Ánimo, mérito y material de chantaje ─────────────────────

## Extra: ánimo −1..1 (0 neutro). IdeaPool y Company (descontento) lo leen.
func get_mood(npc_id: String) -> float:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.mood if npc != null else 0.0


## Extra: ánimo medio de la plantilla hasta un escalón (descontento §11.7: escalones 1-3).
func get_average_mood(max_tier: int) -> float:
	var total: float = 0.0
	var count: int = 0
	for npc: NPCRuntime in get_all_npcs():
		if npc.tier <= max_tier:
			total += npc.mood
			count += 1
	return total / count if count > 0 else 0.0


func get_merit(npc_id: String) -> int:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.merit if npc != null else 0


## Extra (manos del juego): suma o resta mérito a un personaje (nunca por debajo de 0).
func add_merit(npc_id: String, amount: int) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc != null:
		npc.merit = maxi(npc.merit + amount, 0)


## Extra: material de chantaje del personaje contra el jugador ({type, day, ...}).
func add_blackmail_material(npc_id: String, material: Dictionary) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return
	var entry: Dictionary = material.duplicate(true)
	if not entry.has("day"):
		entry["day"] = _current_day()
	npc.blackmail_material.append(entry)


func get_blackmail_material(npc_id: String) -> Array:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.blackmail_material.duplicate(true) if npc != null else []


func has_leverage(npc_id: String) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc != null and not npc.blackmail_material.is_empty()


# ─── Rutinas y ubicación (§24.5) ──────────────────────────────

func get_current_location(npc_id: String) -> String:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.current_room if npc != null else ""


## Sala principal de la franja hoy (sin baño, café, fotocopiadora ni escaqueo); "" = ausente.
func get_scheduled_location(npc_id: String, band: String) -> String:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or _planner == null:
		return ""
	return str(_location_at(npc, _planner.representative_minute(band), false)["room"])


## Sustituye la sala de una franja hasta el cambio de jornada ("" anula la sustitución). Si es la
## franja en curso, sitúa ya al personaje (orden de una escena, p. ej. sentar a los asistentes de
## Aurora) aunque un nodo lo estuviera situando.
func override_routine(npc_id: String, band: String, location: String) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return
	if location.is_empty():
		npc.schedule_override.erase(band)
	else:
		npc.schedule_override[band] = location
	if _planner != null and _planner.band_of_minute(_clock_minute()) == band:
		_world_located.erase(npc_id)
		var loc: Dictionary = _location_at(npc, _clock_minute(), true)
		_place(npc, str(loc["room"]), str(loc["activity"]))


func is_slacker(npc_id: String) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc != null and npc.is_slacker


## Extra: true si ahora mismo se está escaqueando (fuera de su puesto, §24.5).
func is_slacking(npc_id: String) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc != null and npc.state == STATE_SLACKING


## Extra: sala de la agenda de hoy a una hora concreta (incluye pausas y escaqueo).
func get_location_at(npc_id: String, hour: int, minute: int) -> String:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or _planner == null:
		return ""
	var m: int = hour * NPCRoutinePlanner.MINUTES_PER_HOUR + minute
	return str(_location_at(npc, m, true)["room"])


## Extra: agenda del día (depuración / mapa): [{start, end, room, activity, kind, priority}].
func get_day_plan(npc_id: String) -> Array:
	var npc: NPCRuntime = get_npc(npc_id)
	return _plan_for(npc).duplicate(true) if npc != null and _planner != null else []


## Extra (§11.8 agenda del CEO): agenda de la plantilla para una jornada concreta (determinista;
## hoy = get_day_plan). No incluye sustituciones de override_routine ni seguimientos.
func get_day_plan_for_day(npc_id: String, day: int) -> Array:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or _planner == null:
		return []
	if day == _current_day():
		return get_day_plan(npc_id)
	return _planner.build_plan(npc, _profiles.get(npc.id, {}), day, GameClock.get_run_seed())


## Extra (nodos del mundo, §20.1): sala real de un personaje con nodo (LOD 0/1). La agenda deja
## de moverlo hasta release_current_location() o hasta que baje a LOD 2.
func set_current_location(npc_id: String, room_id: String) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc != null and _is_active(npc):
		npc.current_room = room_id
		npc.floor = _floor_of(room_id, npc)
		_world_located[npc_id] = true


## Extra (nodos del mundo): el nodo desaparece; la agenda vuelve a situar al personaje.
func release_current_location(npc_id: String) -> void:
	_world_located.erase(npc_id)


## Extra: true si un nodo del mundo manda sobre su sala (set_current_location).
func is_world_located(npc_id: String) -> bool:
	return _world_located.has(npc_id)


func _location_at(npc: NPCRuntime, minute: int, include_minor: bool) -> Dictionary:
	if not _is_active(npc):
		return {"room": "", "activity": STATE_REMOVED}
	var band: String = _planner.band_of_minute(minute)
	if npc.schedule_override.has(band):
		return {"room": str(npc.schedule_override[band]), "activity": "override"}
	if _follows_player_in(npc.id, band):
		return {"room": _player_room, "activity": ACTIVITY_SURVEILLANCE}
	var iv: Dictionary = NPCRoutinePlanner.pick(_plan_for(npc), minute, include_minor)
	if iv.is_empty():
		return {"room": npc.home_room, "activity": ""}
	return {"room": str(iv["room"]), "activity": str(iv["activity"])}


func _plan_for(npc: NPCRuntime) -> Array:
	var cached: Dictionary = _plans.get(npc.id, {})
	if not cached.is_empty() and int(cached["day"]) == _current_day():
		return cached["plan"]
	var plan: Array = _planner.build_plan(npc, _profiles.get(npc.id, {}), _current_day(),
			GameClock.get_run_seed())
	_plans[npc.id] = {"day": _current_day(), "plan": plan}
	return plan


## Recoloca según la hora a los personajes cuyo LOD está en [min_level, max_level], salvo los
## que sitúa un nodo del mundo (set_current_location).
func _update_locations(minute: int, min_level: int, max_level: int) -> void:
	if _planner == null:
		return
	for id: String in _order:
		var npc: NPCRuntime = _npcs[id]
		if not _is_active(npc) or npc.lod < min_level or npc.lod > max_level \
				or _world_located.has(id):
			continue
		var loc: Dictionary = _location_at(npc, minute, true)
		_place(npc, str(loc["room"]), str(loc["activity"]))


## Sala y estado de rutina (idle | slacking | absent); las decisiones no tocan el estado.
func _place(npc: NPCRuntime, room: String, activity: String) -> void:
	npc.current_room = room
	npc.floor = _floor_of(room, npc)
	if room.is_empty():
		npc.state = STATE_ABSENT
	elif activity == NPCRoutinePlanner.ACTIVITY_SLACKING:
		npc.state = STATE_SLACKING
	else:
		npc.state = NPCRuntime.STATE_IDLE


func _floor_of(room: String, npc: NPCRuntime) -> int:
	if room.is_empty() or _planner == null:
		return FLOOR_NONE
	var f: int = _planner.room_floor(room)
	if f == NPCRoutinePlanner.NO_FLOOR or f == RoomData.TRANSVERSAL_FLOOR:
		f = _planner.room_floor(npc.home_room)
	return FLOOR_NONE if f == RoomData.TRANSVERSAL_FLOOR else f


# ─── Estado vital y cuerpos ───────────────────────────────────

## Expulsión o eliminación. Con causa del jugador (CompanySystem.PLAYER_CAUSES): agravio
## seat_lost al retirado si sigue vivo y friend_sunk a sus aliados (§7.9). "eliminated" /
## "elimination" crea el cuerpo (body_created) antes de emitir npc_removed; Company vacía la
## silla al oírlo.
func remove_npc(npc_id: String, cause: String) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or not _is_active(npc):
		return
	_grieve_removal(npc, cause, GRIEVANCE_SEAT_LOST, B_SEV_SEAT)
	_take_off_staff(npc, cause)
	EventBus.npc_removed.emit(npc_id, cause)


## Extra: true si la causa de una vacante o retirada es obra del jugador (lista de Company).
static func is_player_cause(cause: String) -> bool:
	return CompanySystem.PLAYER_CAUSES.has(cause)


## §7.9 «expulsión» y «hundir a un amigo»: solo si la causa es del jugador. El retirado registra
## el agravio indicado (si sigue vivo) y sus amistades/pareja en plantilla, friend_sunk.
func _grieve_removal(npc: NPCRuntime, cause: String, grievance: String,
		severity_key: String) -> void:
	if not is_player_cause(cause):
		return
	if not ELIMINATION_CAUSES.has(cause):
		add_grievance(npc.id, grievance, Database.get_balance_int(severity_key))
		_shift_mood(npc, Database.get_balance_float(str(REMOVAL_MOOD.get(grievance,
				B_MOOD_SEAT_LOST))))
	for ally: String in _allies_of(npc.id):
		add_grievance(ally, GRIEVANCE_FRIEND_SUNK, Database.get_balance_int(B_SEV_FRIEND))


## Amistades y pareja en plantilla (SocialGraph, aristas en ambos sentidos, sin repetir).
func _allies_of(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for link: Dictionary in SocialGraph.get_links(npc_id):
		var ally: String = _link_target(link, npc_id)
		if ALLY_LINK_TYPES.has(_link_type(link)) and ally != npc_id and is_active(ally) \
				and not out.has(ally):
			out.append(ally)
	return out


## Deja la plantilla (estado propio): cuerpo si es eliminación; sin sala, sin LOD forzado ni fijado.
func _take_off_staff(npc: NPCRuntime, cause: String) -> void:
	var room: String = _elimination_room(npc)
	npc.removed_cause = cause
	npc.state = STATE_REMOVED
	npc.lod = NPCRuntime.LOD_STATISTICAL
	_forced_lod.erase(npc.id)
	_lod_pins.erase(npc.id)
	_world_located.erase(npc.id)
	if ELIMINATION_CAUSES.has(cause):
		npc.alive = false
		_create_body(npc, room)
	npc.current_room = ""
	npc.floor = FLOOR_NONE
	refresh_lod()


## Company vació la silla de un personaje en plantilla sin darle otra (jubilación, despido...):
## deja la empresa. npc_removed se anuncia diferido, cuando Company ha terminado su cadena.
func _end_employment(npc: NPCRuntime, cause: String) -> void:
	_grieve_removal(npc, cause, GRIEVANCE_SEAT_LOST, B_SEV_SEAT)
	_take_off_staff(npc, cause)
	_announce_removal.call_deferred(npc.id, cause)


func _announce_removal(npc_id: String, cause: String) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc != null and npc.removed_cause == cause:
		EventBus.npc_removed.emit(npc_id, cause)


func is_alive(npc_id: String) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc != null and npc.alive


## Extra: vivo y en plantilla.
func is_active(npc_id: String) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc != null and _is_active(npc)


## {body_id, room_id, spot_id, hidden, discovered, discovered_by, day}; {} si no hay cuerpo.
func get_body_info(npc_id: String) -> Dictionary:
	return (_bodies.get(npc_id, {}) as Dictionary).duplicate(true)


## Traslado del cuerpo; con spot_id no vacío queda oculto en ese escondite.
func move_body(npc_id: String, room_id: String, spot_id: String) -> void:
	if not _bodies.has(npc_id):
		return
	var body: Dictionary = _bodies[npc_id]
	body["room_id"] = room_id
	body["spot_id"] = spot_id
	body["hidden"] = not spot_id.is_empty()


## Extra: npc_id del cuerpo (body_id = "body_" + npc_id); "" si no existe.
func get_body_npc(body_id: String) -> String:
	var npc_id: String = body_id.trim_prefix(BODY_ID_PREFIX)
	return npc_id if _bodies.has(npc_id) else ""


## Extra: todos los cuerpos (copias).
func get_all_bodies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for npc_id: String in _bodies:
		var body: Dictionary = (_bodies[npc_id] as Dictionary).duplicate(true)
		body["npc_id"] = npc_id
		out.append(body)
	return out


func _create_body(npc: NPCRuntime, room: String) -> void:
	var body_id: String = BODY_ID_PREFIX + npc.id
	_bodies[npc.id] = {"body_id": body_id, "room_id": room, "spot_id": "", "hidden": false,
			"discovered": false, "discovered_by": "", "day": _current_day()}
	EventBus.body_created.emit(body_id, npc.id, room)


## La eliminación ocurre junto al jugador: su sala si el personaje está a su alcance (LOD 0).
func _elimination_room(npc: NPCRuntime) -> String:
	if npc.lod == NPCRuntime.LOD_FULL and not _player_room.is_empty():
		return _player_room
	return npc.current_room if not npc.current_room.is_empty() else _player_room


## Un cuerpo no oculto se descubre cuando un personaje presente comparte su sala.
func _check_bodies() -> void:
	for npc_id: String in _bodies:
		var body: Dictionary = _bodies[npc_id]
		if bool(body["hidden"]) or bool(body["discovered"]):
			continue
		var room: String = str(body["room_id"])
		for other: NPCRuntime in get_all_npcs():
			if not room.is_empty() and _same_room(other.current_room, room):
				body["discovered"] = true
				body["discovered_by"] = other.id
				EventBus.body_discovered.emit(str(body["body_id"]), room)
				break


# ─── Domicilio y robos nocturnos (§4.3, NightOps) ─────────────

## Extra: tipo de vivienda exterior del personaje (sala npc_house_*); "" si no tiene.
func get_home_address(npc_id: String) -> String:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.home_address if npc != null else ""


## Extra: en plantilla, con domicilio, fuera del edificio según su agenda de ahora y en la franja
## doméstica (hora >= noche.hora_llegada_domicilio o < tiempo.hora_inicio_jornada).
func is_at_home(npc_id: String) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or not _is_active(npc) or npc.home_address.is_empty() \
			or _world_located.has(npc_id):
		return false
	var hour: int = GameClock.get_hour()
	if hour < Database.get_balance_int(B_HOME_ARRIVAL) \
			and hour >= Database.get_balance_int(B_DAY_START):
		return false
	return get_location_at(npc_id, hour, GameClock.get_minute()).is_empty()


## Extra: {looted: {container_id: jornada}, burglaries, last_day} (copia; {} si nunca le robaron).
func get_house_loot_state(npc_id: String) -> Dictionary:
	return (_house_loot.get(npc_id, {}) as Dictionary).duplicate(true)


## Extra: el contenedor de la casa del personaje sigue vacío (saqueado hace menos de
## noche.dias_reposicion_botin jornadas).
func is_house_container_looted(npc_id: String, container_id: String) -> bool:
	var looted: Dictionary = (_house_loot.get(npc_id, {}) as Dictionary).get(HOUSE_LOOTED, {})
	if not looted.has(container_id):
		return false
	var age: int = GameClock.get_day() - int(looted[container_id])
	return age < Database.get_balance_int(B_LOOT_RESTOCK)


## Extra (manos: NightOps): vacía ese contenedor de la casa del personaje hoy. Cuenta un robo
## sufrido por jornada.
func mark_house_container_looted(npc_id: String, container_id: String) -> void:
	if get_npc(npc_id) == null or container_id.is_empty():
		return
	var state: Dictionary = _house_loot.get(npc_id, {HOUSE_LOOTED: {}, HOUSE_BURGLARIES: 0,
			HOUSE_LAST_DAY: 0})
	if int(state[HOUSE_LAST_DAY]) != GameClock.get_day():
		state[HOUSE_BURGLARIES] = int(state[HOUSE_BURGLARIES]) + 1
		state[HOUSE_LAST_DAY] = GameClock.get_day()
	(state[HOUSE_LOOTED] as Dictionary)[container_id] = GameClock.get_day()
	_house_loot[npc_id] = state


## {vigilante: {target, until_day, reason}} de JSON → tipos propios.
static func _typed_surveillance(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for watcher: Variant in raw:
		var entry: Variant = raw[watcher]
		if entry is Dictionary:
			out[str(watcher)] = {SV_TARGET: str(entry.get(SV_TARGET, PLAYER_ID)),
					SV_UNTIL: int(entry.get(SV_UNTIL, 0)), SV_REASON: str(entry.get(SV_REASON, ""))}
	return out


static func _typed_house_loot(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		return out
	for npc_id: Variant in raw:
		var entry: Variant = raw[npc_id]
		if not entry is Dictionary:
			continue
		var looted: Dictionary = {}
		var raw_looted: Variant = (entry as Dictionary).get(HOUSE_LOOTED, {})
		if raw_looted is Dictionary:
			for container_id: Variant in raw_looted:
				looted[str(container_id)] = int(raw_looted[container_id])
		out[str(npc_id)] = {HOUSE_LOOTED: looted,
				HOUSE_BURGLARIES: int(entry.get(HOUSE_BURGLARIES, 0)),
				HOUSE_LAST_DAY: int(entry.get(HOUSE_LAST_DAY, 0))}
	return out


# ─── Nivel de detalle (§20, PASO 40) ──────────────────────────

## 0 completo, 1 medio, 2 estadístico. Fija el nivel (fuera del presupuesto por ubicación)
## hasta clear_lod(); un LOD 0 forzado por trama (force_full_lod, lista corta, deuda) manda.
func set_lod(npc_id: String, level: int) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or not _is_active(npc):
		return
	_lod_pins[npc_id] = clampi(level, NPCRuntime.LOD_FULL, NPCRuntime.LOD_STATISTICAL)
	if not _is_forced(npc):
		npc.lod = int(_lod_pins[npc_id])


## Extra: retira el nivel fijado con set_lod() y reasigna niveles.
func clear_lod(npc_id: String) -> void:
	if _lod_pins.erase(npc_id):
		refresh_lod()


func get_lod(npc_id: String) -> int:
	var npc: NPCRuntime = get_npc(npc_id)
	return npc.lod if npc != null else NPCRuntime.LOD_STATISTICAL


## Trama activa (§20.2): LOD 0 siempre, con independencia de la ubicación, hasta
## release_full_lod(npc, motivo).
func force_full_lod(npc_id: String, reason: String) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or not _is_active(npc):
		return
	var reasons: Array = _forced_lod.get(npc_id, [])
	if not reasons.has(reason):
		reasons.append(reason)
	_forced_lod[npc_id] = reasons
	npc.lod = NPCRuntime.LOD_FULL


## Extra: retira un motivo de LOD 0 forzado y reasigna niveles.
func release_full_lod(npc_id: String, reason: String) -> void:
	var reasons: Array = _forced_lod.get(npc_id, [])
	reasons.erase(reason)
	if reasons.is_empty():
		_forced_lod.erase(npc_id)
	refresh_lod()


## Extra: motivos de LOD 0 forzado (incluye "debt" si hay deuda con el jugador).
func get_full_lod_reasons(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for reason: Variant in _forced_lod.get(npc_id, []):
		out.append(str(reason))
	var npc: NPCRuntime = get_npc(npc_id)
	if npc != null and _has_debt_with_player(npc) and not out.has(REASON_DEBT):
		out.append(REASON_DEBT)
	return out


## Extra: el motivo "marked_target" sigue la lista de PlayerState (dueña de los objetivos, §13.4).
func sync_marked_targets() -> void:
	var marked: Array[String] = PlayerState.get_marked_targets()
	for npc_id: String in marked:
		force_full_lod(npc_id, REASON_MARKED_TARGET)
	for npc_id: Variant in _forced_lod.keys():
		if not marked.has(str(npc_id)) \
				and (_forced_lod[npc_id] as Array).has(REASON_MARKED_TARGET):
			release_full_lod(str(npc_id), REASON_MARKED_TARGET)


## Extra (§11.8): el vigilante sigue al jugador durante `days` jornadas más la de hoy (se suma a
## una vigilancia en curso: vale el plazo más largo). LOD 0 forzado y bonificación de perspicacia.
func begin_personal_surveillance(watcher_id: String, days: int, reason: String) -> void:
	var npc: NPCRuntime = get_npc(watcher_id)
	if npc == null or not _is_active(npc) or days <= 0:
		return
	var until: int = maxi(_current_day() + days,
			int(get_personal_surveillance(watcher_id).get(SV_UNTIL, 0)))
	_surveillance[watcher_id] = {SV_TARGET: PLAYER_ID, SV_UNTIL: until, SV_REASON: reason}
	force_full_lod(watcher_id, REASON_SURVEILLANCE)
	_relocate_by_schedule(npc)


## Extra: termina la vigilancia (plazo cumplido, un intermediario tranquiliza al vigilante...).
func end_personal_surveillance(watcher_id: String) -> void:
	if not _surveillance.erase(watcher_id):
		return
	release_full_lod(watcher_id, REASON_SURVEILLANCE)
	var npc: NPCRuntime = get_npc(watcher_id)
	if npc != null:
		_relocate_by_schedule(npc)


## Extra: {target, until_day, reason} de la vigilancia del personaje ({} si no vigila).
func get_personal_surveillance(watcher_id: String) -> Dictionary:
	return (_surveillance.get(watcher_id, {}) as Dictionary).duplicate()


## Extra: ids de quienes vigilan personalmente al jugador ahora.
func get_surveillance_watchers() -> Array[String]:
	var out: Array[String] = []
	for watcher: Variant in _surveillance:
		out.append(str(watcher))
	return out


func is_player_under_surveillance() -> bool:
	return not _surveillance.is_empty()


## Extra (nodo del mundo): a quién debe seguir el personaje ahora ("player" o "").
func get_follow_target(npc_id: String) -> String:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or _planner == null or not _follows_player_in(npc_id,
			_planner.band_of_minute(_clock_minute())):
		return ""
	return str(_surveillance[npc_id].get(SV_TARGET, PLAYER_ID))


## Extra (§11.8 Pearl Osgood, §12.2 company_man): denuncia deliberada al superior con certeza
## completa (canal "superior"). No mira el plazo entre denuncias: es un acto de la trama.
## `reason` = disparador anotado en npc_decided y en get_last_decision().
func report_player_to_superior(npc_id: String, location: String,
		reason: String = TRIGGER_PLOT) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or not _is_active(npc):
		return false
	var summary: Dictionary = {"trigger": reason, "channel": CHANNEL_SUPERIOR,
			"evidence_type": EVIDENCE_DIRECT, "certainty": Belief.MAX_CERTAINTY, "location": location}
	_last_decision[npc_id] = {"action": UtilityAI.REPORT_TO_SUPERIOR, "trigger": reason,
			"day": _current_day(), "minute": _clock_minute()}
	EventBus.npc_decided.emit(npc_id, UtilityAI.REPORT_TO_SUPERIOR, summary)
	_report(npc, CHANNEL_SUPERIOR, Belief.MAX_CERTAINTY, location)
	return true


## Seguimiento estadístico: en las franjas de seguimiento, con el jugador dentro del edificio.
func _follows_player_in(npc_id: String, band: String) -> bool:
	if not _surveillance.has(npc_id) or _player_room.is_empty() or _planner == null:
		return false
	var bands: Variant = Database.get_balance(B_SURVEILLANCE_BANDS)
	if not (bands is Array and (bands as Array).has(band)):
		return false
	var f: int = _planner.room_floor(_player_room)
	return f != NPCRoutinePlanner.NO_FLOOR and f != Database.get_balance_int(B_EXTERIOR_FLOOR)


## Sitúa ya al personaje según su agenda (salvo que lo sitúe un nodo del mundo).
func _relocate_by_schedule(npc: NPCRuntime) -> void:
	if _planner == null or _world_located.has(npc.id) or not _is_active(npc):
		return
	var loc: Dictionary = _location_at(npc, _clock_minute(), true)
	_place(npc, str(loc["room"]), str(loc["activity"]))


func _move_watchers() -> void:
	for watcher: Variant in _surveillance:
		var npc: NPCRuntime = get_npc(str(watcher))
		if npc != null:
			_relocate_by_schedule(npc)


## Cambio de jornada: caducan las vigilancias cuyo plazo ya pasó.
func _expire_surveillance(day_number: int) -> void:
	for watcher: Variant in _surveillance.keys():
		if int((_surveillance[watcher] as Dictionary).get(SV_UNTIL, 0)) < day_number:
			end_personal_surveillance(str(watcher))


## Extra: presupuesto de agentes (perfil "max_agents" o lod.max_agentes_total).
func get_max_agents() -> int:
	var setting: Variant = SaveSystem.get_setting(SETTING_MAX_AGENTS)
	if (setting is int or setting is float) and int(setting) > 0:
		return int(setting)
	return Database.get_balance_int(B_LOD_MAX_TOTAL)


## Extra: segundos entre actualizaciones de un nivel (0 = cada fotograma, §20.1).
func get_lod_update_interval(level: int) -> float:
	match level:
		NPCRuntime.LOD_MEDIUM:
			return Database.get_balance_float(B_LOD_MEDIUM_SECONDS)
		NPCRuntime.LOD_STATISTICAL:
			return Database.get_balance_float(B_LOD_STAT_SECONDS)
	return 0.0


## Extra: reasigna los tres niveles. max_agents > 0 sustituye al presupuesto configurado. Quien
## acaba en LOD 2 pierde la sala fijada por su nodo (ya no lo tiene, §20.1).
func refresh_lod(max_agents: int = -1) -> void:
	if not Database.is_loaded() or _order.is_empty():
		return
	var budget: int = max_agents if max_agents > 0 else get_max_agents()
	var forced: Array[NPCRuntime] = []
	var close: Array[NPCRuntime] = []
	var same_floor: Array[NPCRuntime] = []
	_fill_lod_pools(forced, close, same_floor)
	close.sort_custom(_closer_first)
	var full_cap: int = mini(Database.get_balance_int(B_LOD_MAX_FULL), budget)
	var full_count: int = _assign_level(forced, NPCRuntime.LOD_FULL, forced.size())
	var free_full: int = maxi(full_cap - full_count, 0)
	full_count += _assign_level(close, NPCRuntime.LOD_FULL, free_full)
	var medium_pool: Array[NPCRuntime] = close.slice(mini(free_full, close.size()))
	medium_pool.append_array(same_floor)
	var medium_cap: int = mini(Database.get_balance_int(B_LOD_MAX_MEDIUM),
			maxi(budget - full_count, 0))
	_assign_level(medium_pool, NPCRuntime.LOD_MEDIUM, medium_cap)
	for npc: NPCRuntime in get_all_npcs():
		if npc.lod == NPCRuntime.LOD_STATISTICAL:
			_world_located.erase(npc.id)


## Reparte la plantilla en forzados, cercanos (sala del jugador y adyacentes) y misma planta; los
## niveles fijados con set_lod() se aplican aquí y no entran en ningún grupo.
func _fill_lod_pools(forced: Array[NPCRuntime], close: Array[NPCRuntime],
		same_floor: Array[NPCRuntime]) -> void:
	var near: Dictionary = _near_rooms(_player_room)
	for npc: NPCRuntime in get_all_npcs():
		npc.lod = NPCRuntime.LOD_STATISTICAL
		if _is_forced(npc):
			forced.append(npc)
		elif _lod_pins.has(npc.id):
			npc.lod = int(_lod_pins[npc.id])
		elif _on_player_floor(npc) and near.has(_base_room(npc.current_room)):
			close.append(npc)
		elif _on_player_floor(npc):
			same_floor.append(npc)


func _assign_level(npcs: Array[NPCRuntime], level: int, limit: int) -> int:
	var count: int = mini(limit, npcs.size())
	for i: int in count:
		npcs[i].lod = level
	return count


func _closer_first(a: NPCRuntime, b: NPCRuntime) -> bool:
	var a_here: bool = _same_room(a.current_room, _player_room)
	var b_here: bool = _same_room(b.current_room, _player_room)
	if a_here != b_here:
		return a_here
	return _order.find(a.id) < _order.find(b.id)


func _is_forced(npc: NPCRuntime) -> bool:
	return _forced_lod.has(npc.id) or _has_debt_with_player(npc)


## §20.2 «mantener deuda con el jugador»: registro (en cualquier sentido) o arista de deuda de
## SocialGraph hacia el jugador.
func _has_debt_with_player(npc: NPCRuntime) -> bool:
	return int(npc.ledger.get("debt", 0)) != 0 \
			or SocialGraph.is_denunciation_suppressed(npc.id, PLAYER_ID)


func _on_player_floor(npc: NPCRuntime) -> bool:
	return not npc.current_room.is_empty() and npc.floor == _player_floor


## Salas (id base) a distancia ≤ lod.radio_salas_completo de la sala dada.
func _near_rooms(room_id: String) -> Dictionary:
	var out: Dictionary = {}
	if room_id.is_empty():
		return out
	var frontier: Array = [_base_room(room_id)]
	out[frontier[0]] = true
	for _step: int in Database.get_balance_int(B_LOD_RADIUS):
		var next: Array = []
		for current: Variant in frontier:
			for neighbour: Variant in _adjacency.get(current, []):
				if not out.has(neighbour):
					out[neighbour] = true
					next.append(neighbour)
		frontier = next
	return out


func _build_adjacency() -> void:
	_adjacency.clear()
	for room: RoomData in Database.get_all_rooms():
		for other: String in room.connects_to:
			_link_rooms(room.id, _base_room(other))


func _link_rooms(a: String, b: String) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var list: Array = _adjacency.get(pair[0], [])
		if not list.has(pair[1]):
			list.append(pair[1])
		_adjacency[pair[0]] = list


func _configure_timer() -> void:
	var medium: float = Database.get_balance_float(B_LOD_MEDIUM_SECONDS)
	var statistical: float = Database.get_balance_float(B_LOD_STAT_SECONDS)
	if _timer == null or medium <= 0.0:
		return
	_statistical_every = maxi(roundi(statistical / medium), 1)
	_tick = 0
	_timer.wait_time = medium
	_timer.start()


## Temporizador: LOD 0/1 cada intervalo medio y LOD 2 cada intervalo estadístico, solo si el
## reloj corre y la hora ha cambiado (nunca por fotograma).
func _on_lod_tick() -> void:
	if GameClock.is_paused() or _planner == null:
		return
	var minute: int = _clock_minute()
	_tick += 1
	if minute != _last_medium_minute:
		_last_medium_minute = minute
		_update_locations(minute, NPCRuntime.LOD_FULL, NPCRuntime.LOD_MEDIUM)
	if _tick % _statistical_every == 0 and minute != _last_statistical_minute:
		_last_statistical_minute = minute
		_update_locations(minute, NPCRuntime.LOD_STATISTICAL, NPCRuntime.LOD_STATISTICAL)
		refresh_lod()


# ─── Consultas sociales (BUILD_NOTES §13) ─────────────────────

## 0-100: base + escalón × k + mérito × k − Σgravedad de agravios × k + ajustes
## (modify_npc_reputation). Credibilidad del portador
## (BeliefNet) y reputación del acusador. 0 si no es un personaje.
func get_npc_reputation(npc_id: String) -> float:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return 0.0
	var value: float = Database.get_balance_float(B_REP_BASE) \
			+ npc.tier * Database.get_balance_float(B_REP_PER_TIER) \
			+ npc.merit * Database.get_balance_float(B_REP_PER_MERIT) \
			- get_grievance_total(npc_id) * Database.get_balance_float(B_REP_PER_SEVERITY) \
			- NewsFeed.get_suspicion_about(npc_id) * Database.get_balance_float(B_REP_PER_PRESS) \
			+ float(_profiles.get(npc_id, {}).get(PROFILE_REPUTATION_DELTA, 0.0))
	return clampf(value, 0.0, REPUTATION_MAX)


## Extra (IdeaPresentation §11.2): ajuste permanente de la reputación del personaje.
func modify_npc_reputation(npc_id: String, delta: float, _reason: String) -> void:
	if not _profiles.has(npc_id):
		return
	var profile: Dictionary = _profiles[npc_id]
	profile[PROFILE_REPUTATION_DELTA] = float(profile.get(PROFILE_REPUTATION_DELTA, 0.0)) + delta


@warning_ignore("shadowed_global_identifier")
func get_npcs_on_floor(floor: int) -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for npc: NPCRuntime in get_all_npcs():
		if npc.floor == floor and not npc.current_room.is_empty():
			out.append(npc)
	return out


## Compañeros de departamento o de sala del jugador, y cualquiera con registro o creencias sobre él.
func knows_player(npc_id: String) -> bool:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return false
	if _ledger_has_entries(npc.ledger):
		return true
	for belief: Belief in BeliefNet.get_beliefs_held_by(npc_id):
		if belief.subject == PLAYER_ID:
			return true
	var occupation: OccupationData = PlayerState.get_occupation()
	if occupation == null:
		return false
	return npc.home_room == occupation.office_room \
			or npc.department == str(occupation.extra.get("department", ""))


func get_player_room() -> String:
	return _player_room


## Personajes en la sala dada y en sus adyacentes (misma planta).
func get_npcs_near(room_id: String) -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	var near: Dictionary = _near_rooms(room_id)
	var room_floor: int = _planner.room_floor(room_id) if _planner != null else FLOOR_NONE
	var check_floor: bool = room_floor != FLOOR_NONE and room_floor != RoomData.TRANSVERSAL_FLOOR
	for npc: NPCRuntime in get_all_npcs():
		if npc.current_room.is_empty() or not near.has(_base_room(npc.current_room)):
			continue
		if check_floor and npc.floor != room_floor:
			continue
		out.append(npc)
	return out


# ─── Decisión por utilidad (§7.5, PASO 16) ────────────────────

## Extra: evalúa a un personaje ante un disparador (TRIGGER_BELIEF | TRIGGER_BAND |
## TRIGGER_BRIBE) sin aplicar la decisión. {action, score, scores}; {} si no está en plantilla.
func decide(npc_id: String, trigger: String, extra: Dictionary = {}) -> Dictionary:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or not _is_active(npc):
		return {}
	return UtilityAI.evaluate(npc, build_context(npc_id, trigger, extra))


## Extra: contexto de utilidad con los valores actuales del mundo; `extra` los sobrescribe
## (p. ej. {"player_rank": 28} en tests o en el panel de depuración).
func build_context(npc_id: String, trigger: String, extra: Dictionary = {}) -> Dictionary:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null:
		return {}
	var ctx: Dictionary = {
		UtilityAI.CTX_ACTIONS: _candidates(npc, trigger),
		UtilityAI.CTX_BELIEFS: _belief_certainties(npc_id, extra),
		UtilityAI.CTX_RANK: PlayerState.get_rank(),
		UtilityAI.CTX_SUSPICION: PlayerState.get_suspicion(),
		UtilityAI.CTX_REPUTATION: PlayerState.get_reputation(),
		UtilityAI.CTX_LEDGER: npc.ledger, UtilityAI.CTX_MOOD: npc.mood,
		UtilityAI.CTX_WEIGHTS: _utility_weights(), UtilityAI.CTX_SCALES: _relation_scales(),
		"trigger": trigger,
	}
	ctx.merge(extra, true)
	return ctx


## Repertorio disponible según el disparador (disponibilidad, nunca preferencia).
func _candidates(npc: NPCRuntime, trigger: String) -> Array[String]:
	var out: Array[String] = []
	match trigger:
		TRIGGER_BELIEF:
			out = UtilityAI.REACTION_ACTIONS.duplicate()
			if not _can_report(npc):
				for action: String in UtilityAI.REPORT_ACTIONS:
					out.erase(action)
			if npc.tier >= OccupationData.MAX_TIER:
				out.erase(UtilityAI.REPORT_TO_SUPERIOR)
		TRIGGER_BAND:
			out = UtilityAI.IDLE_ACTIONS.duplicate()
			if _ready_leverage_index(npc) < 0:
				out.erase(UtilityAI.BLACKMAIL_PLAYER)
			if find_rival(npc.id).is_empty():
				out.erase(UtilityAI.SABOTAGE_RIVAL)
		TRIGGER_BRIBE:
			out = UtilityAI.BRIBE_ACTIONS.duplicate()
	return out


## Certezas relevantes (§7.5): la creencia disparadora más las demás creencias NEGATIVAS del
## personaje sobre el jugador (verle trabajar no acerca a nadie a denunciarle).
func _belief_certainties(npc_id: String, extra: Dictionary) -> Array:
	var out: Array = []
	if extra.has("certainty"):
		out.append(float(extra["certainty"]))
	var trigger_id: String = str(extra.get("belief_id", ""))
	for belief: Belief in BeliefNet.get_beliefs_held_by(npc_id):
		if belief.subject != PLAYER_ID or belief.id == trigger_id or belief.is_record \
				or not _should_react_to(belief.fact):
			continue
		out.append(belief.certainty)
	return out


func _can_report(npc: NPCRuntime) -> bool:
	return not is_report_suppressed(npc.id) and _report_cooldown_over(npc)


## Una denuncia cada npc.dias_entre_denuncias jornadas por personaje.
func _report_cooldown_over(npc: NPCRuntime) -> bool:
	if not _last_report.has(npc.id):
		return true
	return _current_day() - int(_last_report[npc.id]) >= Database.get_balance_int(B_REPORT_COOLDOWN)


## Extra: la deuda con el jugador suprime la denuncia (§7.7): registro propio o arista de deuda
## de SocialGraph.
func is_report_suppressed(npc_id: String) -> bool:
	return get_debt(npc_id) > 0 or SocialGraph.is_denunciation_suppressed(npc_id, PLAYER_ID)


## Extra: última decisión de utilidad {action, trigger, day, minute}; {} si no ha decidido.
func get_last_decision(npc_id: String) -> Dictionary:
	return (_last_decision.get(npc_id, {}) as Dictionary).duplicate()


## Extra: rival del personaje (arista de rivalidad en SocialGraph, o el jugador si comparten
## departamento y escalón); "" si no tiene.
func find_rival(npc_id: String) -> String:
	for link: Dictionary in SocialGraph.get_links(npc_id):
		var other: String = _link_target(link, npc_id)
		if _link_type(link) == RIVAL_LINK_TYPE and is_active(other):
			return other
	var npc: NPCRuntime = get_npc(npc_id)
	var occupation: OccupationData = PlayerState.get_occupation()
	if npc != null and occupation != null and occupation.tier == npc.tier \
			and str(occupation.extra.get("department", "")) == npc.department:
		return PLAYER_ID
	return ""


## Aplica y anuncia una decisión: npc_decided y, si denuncia, npc_reported_player.
func _apply_decision(npc: NPCRuntime, decision: Dictionary, trigger: String,
		extra: Dictionary) -> void:
	var action: String = str(decision.get("action", ""))
	if action.is_empty():
		return
	var summary: Dictionary = {"trigger": trigger, "score": float(decision.get("score", 0.0))}
	for key: String in ["belief_id", "certainty", "location", "amount", "favour_type", "advisory",
			"report_available"]:
		if extra.has(key):
			summary[key] = extra[key]
	_last_decision[npc.id] = {"action": action, "trigger": trigger, "day": _current_day(),
			"minute": _clock_minute()}
	_apply_action_effects(npc, action, summary)
	EventBus.npc_decided.emit(npc.id, action, summary)
	if UtilityAI.REPORT_ACTIONS.has(action):
		_report(npc, str(summary["channel"]), float(extra.get("certainty", 0.0)),
				str(extra.get("location", npc.current_room)))


func _apply_action_effects(npc: NPCRuntime, action: String, summary: Dictionary) -> void:
	match action:
		UtilityAI.REPORT_TO_SECURITY:
			summary["channel"] = CHANNEL_SECURITY
			summary["evidence_type"] = _evidence_for(float(summary.get("certainty", 0.0)))
		UtilityAI.REPORT_TO_SUPERIOR:
			summary["channel"] = CHANNEL_SUPERIOR
			summary["evidence_type"] = _evidence_for(float(summary.get("certainty", 0.0)))
		UtilityAI.STAY_SILENT:
			_keep_silence_material(npc, summary)
		UtilityAI.SABOTAGE_RIVAL:
			summary["target"] = find_rival(npc.id)
			if summary["target"] != PLAYER_ID:
				add_merit(str(summary["target"]), -Database.get_balance_int(B_MERIT_SABOTAGE))
		UtilityAI.BLACKMAIL_PLAYER:
			var index: int = _ready_leverage_index(npc)
			if index >= 0:
				summary["leverage"] = str(npc.blackmail_material[index].get("kind", ""))


## «Silencio con memoria» (§8.2, §12.2): quien calla ante lo que vio con claridad lo guarda.
## Solo si callar fue una elección: con la denuncia retirada (deuda, ya denunció hoy) no.
func _keep_silence_material(npc: NPCRuntime, summary: Dictionary) -> void:
	var certainty: float = float(summary.get("certainty", 0.0))
	if certainty < Database.get_balance_float(B_DIRECT_CERTAINTY) \
			or not bool(summary.get("report_available", false)):
		return
	var belief: Belief = BeliefNet.get_belief(str(summary.get("belief_id", "")))
	var fact: String = belief.fact if belief != null else ""
	var entry: Dictionary = Blackmail.add_material(npc, Blackmail.KIND_SILENCE_MEMORY,
			fact.get_slice(":", 1) if fact.contains(":") else fact, _current_day())
	summary["blackmail"] = true
	summary["demand_day"] = entry.get("demand_day", _current_day())


## Testigo directo si la certeza alcanza creencias.certeza_directa_completa (0,9); si no, parcial.
func _evidence_for(certainty: float) -> String:
	if certainty >= Database.get_balance_float(B_DIRECT_CERTAINTY):
		return EVIDENCE_DIRECT
	return EVIDENCE_PARTIAL


## npc_reported_player(npc, tipo, peso, sala). A Seguridad, tipo = pieza (evidence_types de
## investigations.json) con su peso. Al superior, testigo directo → canal "superior" (§12.2
## company_man: BeliefNet suma +10 y anota el expediente; Security pondera el canal); parcial →
## pieza parcial con peso × npc.factor_denuncia_superior. El peso emitido siempre es el de la
## pieza (× factor si va al superior).
func _report(npc: NPCRuntime, channel: String, certainty: float, location: String) -> void:
	var evidence: String = _evidence_for(certainty)
	var weight: float = Database.get_balance_float(
			B_WEIGHT_DIRECT if evidence == EVIDENCE_DIRECT else B_WEIGHT_PARTIAL)
	var report_type: String = evidence
	if channel == CHANNEL_SUPERIOR:
		weight *= Database.get_balance_float(B_SUPERIOR_FACTOR)
		if evidence == EVIDENCE_DIRECT:
			report_type = CHANNEL_SUPERIOR
	_last_report[npc.id] = _current_day()
	_emitting_report = true
	EventBus.npc_reported_player.emit(npc.id, report_type, weight, location)
	_emitting_report = false


## Índice del material retenido ("held") cuya exigencia ya vence (demand_day, o antigüedad ≥
## chantaje.dias_espera_min si la entrada no la trae); -1 si no hay.
func _ready_leverage_index(npc: NPCRuntime) -> int:
	var today: int = _current_day()
	var wait: int = Database.get_balance_int(B_LEVERAGE_WAIT)
	for i: int in npc.blackmail_material.size():
		var entry: Variant = npc.blackmail_material[i]
		if not (entry is Dictionary):
			continue
		if str(entry.get("status", Blackmail.STATUS_HELD)) != Blackmail.STATUS_HELD:
			continue
		if today >= int(entry.get("demand_day", int(entry.get("day", today)) + wait)):
			return i
	return -1


# ─── Reacciones a señales ─────────────────────────────────────

## Una creencia nueva sobre el jugador hace que su portador reevalúe (§7.5).
func _on_belief_created(belief_id: String, holder: String, subject: String,
		certainty: float) -> void:
	if _emitting_report or subject != PLAYER_ID:
		return
	var npc: NPCRuntime = get_npc(holder)
	if npc == null or not _is_active(npc):
		return
	var belief: Belief = BeliefNet.get_belief(belief_id)
	if belief != null and not _should_react_to(belief.fact):
		return
	if certainty >= Database.get_balance_float(B_DIRECT_CERTAINTY):
		_escalated[belief_id] = true
	var location: String = belief.location if belief != null and not belief.location.is_empty() \
			else npc.current_room
	var extra: Dictionary = {"belief_id": belief_id, "certainty": certainty, "location": location,
			"report_available": _can_report(npc)}
	var decision: Dictionary = decide(holder, TRIGGER_BELIEF, extra)
	_consume_debt_if_silenced(npc, extra)
	_apply_decision(npc, decision, TRIGGER_BELIEF, extra)


## Refuerzo que cruza la certeza completa (§7.2 acumulable): el portador reevalúa una vez.
func _on_belief_decayed(belief_id: String, new_certainty: float) -> void:
	if _emitting_report or _escalated.has(belief_id) \
			or new_certainty < Database.get_balance_float(B_DIRECT_CERTAINTY):
		return
	var belief: Belief = BeliefNet.get_belief(belief_id)
	if belief == null or belief.is_record or belief.subject != PLAYER_ID:
		return
	_on_belief_created(belief_id, belief.holder, belief.subject, new_certainty)


## Cualquier denuncia (CaughtHandler, Blackmail...) cuenta para el plazo entre denuncias; las
## propias ya se anotaron en _report().
func _on_npc_reported_player(npc_id: String, _report_type: String, _weight: float,
		_location: String) -> void:
	if not _emitting_report and _npcs.has(npc_id):
		_last_report[npc_id] = _current_day()


## Si la deuda impidió una denuncia que el personaje habría hecho, la deuda se consume (§7.7:
## supresión temporal).
func _consume_debt_if_silenced(npc: NPCRuntime, extra: Dictionary) -> void:
	if get_debt(npc.id) <= 0 or not _report_cooldown_over(npc):
		return
	var ctx: Dictionary = build_context(npc.id, TRIGGER_BELIEF, extra)
	ctx[UtilityAI.CTX_ACTIONS] = UtilityAI.REACTION_ACTIONS
	var free_choice: String = str(UtilityAI.evaluate(npc, ctx).get("action", ""))
	if UtilityAI.REPORT_ACTIONS.has(free_choice):
		var consumed: int = mini(Database.get_balance_int(B_DEBT_SILENCE), get_debt(npc.id))
		add_debt(npc.id, -consumed)


## Evaluación de franja: personajes presentes en LOD 0/1 (§20.1: LOD 2 no decide).
func _evaluate_idle() -> void:
	for npc: NPCRuntime in get_all_npcs():
		if npc.lod > NPCRuntime.LOD_MEDIUM or npc.current_room.is_empty():
			continue
		_apply_decision(npc, decide(npc.id, TRIGGER_BAND), TRIGGER_BAND, {})


## Consultivo: la inclinación del personaje ante la oferta (Bribery resuelve con §8.2).
func _on_bribe_offered(npc_id: String, amount: int, favour_type: String) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or not _is_active(npc):
		return
	var ratio: float = Bribery.offer_ratio(amount, get_fair_bribe_price(npc_id, favour_type))
	var extra: Dictionary = {UtilityAI.CTX_OFFER: ratio, "amount": amount,
			"favour_type": favour_type, "advisory": true}
	_apply_decision(npc, decide(npc_id, TRIGGER_BRIBE, extra), TRIGGER_BRIBE, extra)


## §7.9: pagar es un favor y deja deuda; denunciar u ofenderse deja agravio; callar deja temor.
## El material de chantaje de los sobornos lo guarda Bribery (Blackmail.add_material).
func _on_bribe_result(npc_id: String, accepted: bool, outcome: String) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or BRIBE_VOID_OUTCOMES.has(outcome):
		return
	if accepted:
		add_favour(npc_id, FAVOUR_BRIBE_PAID, Database.get_balance_int(B_MAG_BRIBE))
		add_debt(npc_id, Database.get_balance_int(B_DEBT_BRIBE))
	elif BRIBE_REPORT_OUTCOMES.has(outcome):
		add_grievance(npc_id, GRIEVANCE_BRIBE_OFFENCE, Database.get_balance_int(B_SEV_BRIBE_REPORT))
	elif BRIBE_SILENT_OUTCOMES.has(outcome):
		add_fear(npc_id, Database.get_balance_int(B_FEAR_SILENT))
	elif not BRIBE_COUNTER_OUTCOMES.has(outcome):
		add_grievance(npc_id, GRIEVANCE_BRIBE_OFFENCE,
				Database.get_balance_int(B_SEV_BRIBE_REFUSED))


## Anota la vacante del jugador (favor a quien la ocupe) y quita la ocupación al saliente. Si
## seguía en plantilla y la causa no es un traslado (ascenso, reasignación), deja la empresa
## (jubilación, despido...): ver _end_employment. Una retirada previa (remove_npc) ya lo hizo.
func _on_seat_vacated(occupation_id: String, previous_holder: String, cause: String) -> void:
	if is_player_cause(cause):
		_player_vacancies[occupation_id] = cause
	var npc: NPCRuntime = get_npc(previous_holder)
	if npc == null:
		return
	if npc.occupation_id == occupation_id:
		npc.occupation_id = ""
	if _is_active(npc) and not STAFF_MOVE_CAUSES.has(cause):
		_end_employment(npc, cause)


## §6.3: favor a quien asciende por obra del jugador; agravio a quien pierde el ascenso cuando la
## silla la ocupa el jugador. Manda el contexto de Company (get_last_fill_context) si describe
## este relleno; si no, las vacantes anotadas en seat_vacated. Un id desconocido que Company
## declara contratado (is_hire) se crea como Rookie.
func _on_seat_filled(occupation_id: String, new_holder: String) -> void:
	var context: Dictionary = _fill_context(occupation_id, new_holder)
	var by_player: bool = bool(context.get("player_caused", _player_vacancies.has(occupation_id)))
	_player_vacancies.erase(occupation_id)
	if new_holder == PLAYER_ID:
		if context.is_empty():
			var best: NPCRuntime = _passed_over_candidate(occupation_id)
			context["grievance_to"] = best.id if best != null else ""
		_grieve_passed_over(str(context.get("grievance_to", "")))
		return
	var npc: NPCRuntime = get_npc(new_holder) if _npcs.has(new_holder) \
			else _hire(new_holder, occupation_id)
	if npc == null:
		return
	_assign_occupation(npc, occupation_id)
	_shift_mood(npc, Database.get_balance_float(B_MOOD_PROMOTION))
	if by_player:
		add_favour(new_holder, FAVOUR_PROMOTION, Database.get_balance_int(B_MAG_PROMOTION))


func _fill_context(occupation_id: String, holder: String) -> Dictionary:
	if not Company.has_method(FILL_CONTEXT_GETTER):
		return {}
	var context: Variant = Company.call(FILL_CONTEXT_GETTER)
	if context is Dictionary and str(context.get("occupation_id", "")) == occupation_id \
			and str(context.get("holder", "")) == holder:
		return (context as Dictionary).duplicate()
	return {}


func _grieve_passed_over(npc_id: String) -> void:
	var npc: NPCRuntime = get_npc(npc_id)
	if npc == null or not _is_active(npc):
		return
	add_grievance(npc_id, GRIEVANCE_PROMOTION_STOLEN, Database.get_balance_int(B_SEV_PROMOTION))
	_shift_mood(npc, Database.get_balance_float(B_MOOD_SEAT_LOST))


## Sin contexto de Company: quien habría ascendido (su ocupación lleva a la silla en promotes_to)
## con mayor mérito × npc.puntuacion_ascenso_merito + ambición × npc.puntuacion_ascenso_ambicion.
func _passed_over_candidate(occupation_id: String) -> NPCRuntime:
	var best: NPCRuntime = null
	var best_score: float = -INF
	var w_merit: float = Database.get_balance_float(B_SCORE_MERIT)
	var w_ambition: float = Database.get_balance_float(B_SCORE_AMBITION)
	for npc: NPCRuntime in get_all_npcs():
		var occ: OccupationData = Database.get_occupation(npc.occupation_id)
		if occ == null or not occ.promotes_to.has(occupation_id):
			continue
		var score: float = npc.merit * w_merit + npc.get_trait("ambition") * w_ambition
		if score > best_score:
			best_score = score
			best = npc
	return best


## Rookie contratado por Company (§6.3 paso 2): se crea con el RNG de la partida.
func _hire(npc_id: String, occupation_id: String) -> NPCRuntime:
	if _planner == null or not Company.has_method(HIRE_CHECK) \
			or not bool(Company.call(HIRE_CHECK, npc_id)):
		return null
	var names: Dictionary = {}
	for id: String in _order:
		names[(_npcs[id] as NPCRuntime).name] = true
	var generator: NPCPopulationGenerator = NPCPopulationGenerator.new(_rng, _generation_rules)
	var npc: NPCRuntime = generator.create_hire(npc_id, occupation_id, names)
	_register(npc, generator.profiles.get(npc_id, {}))
	var loc: Dictionary = _location_at(npc, _clock_minute(), true)
	_place(npc, str(loc["room"]), str(loc["activity"]))
	refresh_lod()
	return npc


func _assign_occupation(npc: NPCRuntime, occupation_id: String) -> void:
	npc.occupation_id = occupation_id
	var occ: OccupationData = Database.get_occupation(occupation_id)
	if occ == null:
		return
	npc.tier = occ.tier
	if not occ.office_room.is_empty():
		npc.home_room = occ.office_room
		npc.desk_position = occ.desk_position
	npc.department = str(occ.extra.get("department", npc.department))
	var template: String = str(occ.extra.get("routine_template", ""))
	if not template.is_empty():
		npc.routine_template = template
	var profile: Dictionary = _profiles.get(npc.id, {})
	profile["role"] = ""
	profile["daily_wage"] = occ.daily_wage
	profile["clearance"] = occ.clearance
	if Company.has_method(SEAT_GETTER):
		var seat: Variant = Company.call(SEAT_GETTER, npc.id)
		if seat is Dictionary and (seat as Dictionary).has("seat_index"):
			profile["seat_index"] = int(seat["seat_index"])
	_profiles[npc.id] = profile
	_plans.erase(npc.id)


## Veredicto "other_guilty" (§12.3 fase 5). Security sabe si el condenado era inocente
## (incriminado o incidente del jugador): entonces guarda un agravio permanente, sus aliados se
## vuelven hostiles y la expulsión cuenta como obra del jugador. Si era culpable, se le condena
## sin agravios y la vacante no se atribuye al jugador.
func _on_investigation_resolved(case_id: String, verdict: String, culprit: String) -> void:
	_release_case(case_id)
	var npc: NPCRuntime = get_npc(culprit)
	if verdict != VERDICT_OTHER_GUILTY or npc == null or not _is_active(npc):
		return
	if not bool(Security.get_case_report(case_id).get(CASE_CULPRIT_INNOCENT, false)):
		remove_npc(culprit, CAUSE_CONVICTED)
		return
	_grieve_removal(npc, CAUSE_EXPELLED, GRIEVANCE_WRONGFUL_CONVICTION, B_SEV_CONVICTION)
	_take_off_staff(npc, CAUSE_EXPELLED)
	EventBus.npc_removed.emit(culprit, CAUSE_EXPELLED)


func _on_suspect_list_formed(case_id: String, suspects: Array) -> void:
	var listed: Array = []
	for suspect: Variant in suspects:
		if is_active(str(suspect)):
			listed.append(str(suspect))
			force_full_lod(str(suspect), REASON_SHORTLIST)
	_shortlists[case_id] = listed


func _on_case_went_cold(case_id: String) -> void:
	_release_case(case_id)


func _release_case(case_id: String) -> void:
	var listed: Array = _shortlists.get(case_id, [])
	_shortlists.erase(case_id)
	for npc_id: Variant in listed:
		if not _still_shortlisted(str(npc_id)):
			release_full_lod(str(npc_id), REASON_SHORTLIST)


func _still_shortlisted(npc_id: String) -> bool:
	for case_id: String in _shortlists:
		if (_shortlists[case_id] as Array).has(npc_id):
			return true
	return false


func _on_idea_acquired(idea_id: String, method: String) -> void:
	if not STOLEN_IDEA_METHODS.has(method):
		return
	var idea: Idea = IdeaPool.get_idea(idea_id)
	if idea != null and is_active(idea.owner):
		add_grievance(idea.owner, GRIEVANCE_IDEA_STOLEN, Database.get_balance_int(B_SEV_IDEA))


func _on_idea_presented(_idea_id: String, presenter: String, merit_gained: int) -> void:
	var npc: NPCRuntime = get_npc(presenter)
	if npc == null or not _is_active(npc):
		return
	add_merit(presenter, merit_gained)
	_shift_mood(npc, Database.get_balance_float(B_MOOD_IDEA))


## El jugador chantajea a un personaje: temor y agravio (si el chantajista es un personaje contra
## el jugador, target = "player", no cambia el registro).
func _on_blackmail_initiated(npc_id: String, target: String, _leverage: String) -> void:
	var victim: String = target if is_active(target) else npc_id
	if target == PLAYER_ID or not is_active(victim):
		return
	add_fear(victim, Database.get_balance_int(B_FEAR_BLACKMAIL))
	add_grievance(victim, GRIEVANCE_BLACKMAILED, Database.get_balance_int(B_SEV_BLACKMAIL))


func _on_body_hidden(body_id: String, spot_id: String) -> void:
	var npc_id: String = get_body_npc(body_id)
	if npc_id.is_empty():
		return
	_bodies[npc_id]["spot_id"] = spot_id
	_bodies[npc_id]["hidden"] = true


func _on_day_advanced(day_number: int) -> void:
	_day = day_number
	var regression: float = Database.get_balance_float(B_MOOD_REGRESSION)
	var merit_factor: float = Database.get_balance_float(B_MERIT_PER_AMBITION)
	for npc: NPCRuntime in get_all_npcs():
		npc.schedule_override.clear()
		npc.merit += roundi(npc.get_trait("ambition") * merit_factor)
		npc.mood = clampf(npc.mood * (1.0 - regression), -MOOD_LIMIT, MOOD_LIMIT)
	_plans.clear()
	_expire_surveillance(day_number)
	_update_locations(_clock_minute(), NPCRuntime.LOD_FULL, NPCRuntime.LOD_STATISTICAL)
	refresh_lod()
	_prune_escalated()


## Olvida las marcas de reacción de creencias que BeliefNet ya no conserva.
func _prune_escalated() -> void:
	for belief_id: Variant in _escalated.keys():
		if BeliefNet.get_belief(str(belief_id)) == null:
			_escalated.erase(belief_id)


func _on_time_band_changed(_old_band: String, new_band: String) -> void:
	if _planner == null:
		return
	var minute: int = _clock_minute()
	if _planner.band_of_minute(minute) != new_band:
		minute = _planner.band_start_minute(new_band)
	_update_locations(minute, NPCRuntime.LOD_FULL, NPCRuntime.LOD_STATISTICAL)
	refresh_lod()
	_evaluate_idle()
	_check_bodies()


func _on_hour_passed(hour: int, day_number: int) -> void:
	if day_number > 0:
		_day = day_number
	_update_locations(hour * NPCRoutinePlanner.MINUTES_PER_HOUR, NPCRuntime.LOD_FULL,
			NPCRuntime.LOD_STATISTICAL)
	refresh_lod()
	_check_bodies()


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if not by_player:
		return
	_player_room = room_id
	if _planner != null:
		var f: int = _planner.room_floor(room_id)
		if f != NPCRoutinePlanner.NO_FLOOR and f != RoomData.TRANSVERSAL_FLOOR:
			_player_floor = f
	_move_watchers()
	refresh_lod()


func _on_floor_changed(_old_floor: int, new_floor: int) -> void:
	_player_floor = new_floor
	refresh_lod()


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	var npcs: Array = []
	for id: String in _order:
		npcs.append((_npcs[id] as NPCRuntime).to_dict())
	return {
		"version": SAVE_VERSION, "npcs": npcs, "profiles": _profiles.duplicate(true),
		"bodies": _bodies.duplicate(true), "forced_lod": _forced_lod.duplicate(true),
		"shortlists": _shortlists.duplicate(true),
		"player_vacancies": _player_vacancies.duplicate(true),
		"last_report": _last_report.duplicate(true), "player_room": _player_room,
		"last_decision": _last_decision.duplicate(true), "lod_pins": _lod_pins.duplicate(),
		"escalated_beliefs": _escalated.keys(), "house_loot": _house_loot.duplicate(true),
		"surveillance": _surveillance.duplicate(true),
		"player_floor": _player_floor, "day": _day,
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


func load_state(data: Dictionary) -> void:
	_clear_population()
	for raw: Variant in data.get("npcs", []):
		if raw is Dictionary:
			var npc: NPCRuntime = NPCRuntime.from_dict(raw, SAVE_CONTEXT)
			npc.blackmail_material = NPCPopulationGenerator.json_ints(npc.blackmail_material)
			_register(npc, _typed_profile(data.get("profiles", {}).get(npc.id, {})))
	_bodies = _typed_bodies(data.get("bodies", {}))
	_forced_lod = (data.get("forced_lod", {}) as Dictionary).duplicate(true)
	_shortlists = (data.get("shortlists", {}) as Dictionary).duplicate(true)
	_player_vacancies = (data.get("player_vacancies", {}) as Dictionary).duplicate(true)
	_last_report = _int_map(data.get("last_report", {}))
	_lod_pins = _int_map(data.get("lod_pins", {}))
	for belief_id: Variant in data.get("escalated_beliefs", []):
		_escalated[str(belief_id)] = true
	_house_loot = _typed_house_loot(data.get("house_loot", {}))
	_surveillance = _typed_surveillance(data.get("surveillance", {}))
	var decisions: Variant = data.get("last_decision", {})
	_last_decision = NPCPopulationGenerator.json_ints(decisions) if decisions is Dictionary else {}
	_player_room = str(data.get("player_room", ""))
	_player_floor = int(data.get("player_floor", 0))
	_day = int(data.get("day", GameClock.get_day()))
	_rng.seed = str(data.get("rng_seed", "0")).to_int()
	_rng.state = str(data.get("rng_state", "0")).to_int()
	if Database.is_loaded():
		_setup_runtime(Database.get_raw("npcs_generation"), false)


## {clave: número} de JSON → {String: int}.
static func _int_map(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in raw:
			out[str(key)] = int(raw[key])
	return out


## JSON devuelve números como float: se restauran los enteros del perfil.
static func _typed_profile(raw: Variant) -> Dictionary:
	var profile: Dictionary = (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	for key: String in ["seat_index", "daily_wage", "clearance", "future_occupation_day"]:
		if profile.has(key):
			profile[key] = int(profile[key])
	var floors: Array[int] = []
	for f: Variant in profile.get("zone_floors", []):
		floors.append(int(f))
	profile["zone_floors"] = floors
	profile["special"] = NPCPopulationGenerator.json_ints(profile.get("special", {}))
	return profile


static func _typed_bodies(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for npc_id: Variant in raw:
		var body: Dictionary = (raw[npc_id] as Dictionary).duplicate(true)
		body["day"] = int(body.get("day", 0))
		body["hidden"] = bool(body.get("hidden", false))
		body["discovered"] = bool(body.get("discovered", false))
		out[str(npc_id)] = body
	return out


# ─── Claves de texto (panel F1, expediente) ───────────────────

## Extra: tr() de un tipo de agravio ("seat_lost" → "LEDGER_GRIEVANCE_SEAT_LOST").
static func grievance_name_key(grievance_type: String) -> String:
	return GRIEVANCE_KEY_FORMAT % grievance_type.to_upper()


static func favour_name_key(favour_type: String) -> String:
	return FAVOUR_KEY_FORMAT % favour_type.to_upper()


## Extra: tr() del estado de un personaje (NPCRuntime.state).
static func state_name_key(state: String) -> String:
	return STATE_KEY_FORMAT % state.to_upper()


static func lod_name_key(level: int) -> String:
	return LOD_KEY_FORMAT % level


# ─── Utilidades internas ──────────────────────────────────────

static func _is_active(npc: NPCRuntime) -> bool:
	return npc.alive and npc.removed_cause.is_empty()


func _current_day() -> int:
	return _day if _day > 0 else GameClock.get_day()


func _clock_minute() -> int:
	return GameClock.get_hour() * NPCRoutinePlanner.MINUTES_PER_HOUR + GameClock.get_minute()


func _utility_weights() -> Dictionary:
	if _weights.is_empty():
		_weights = UtilityAI.load_weights()
	return _weights


func _relation_scales() -> Dictionary:
	if _scales.is_empty():
		_scales = UtilityAI.load_relation_scales()
	return _scales


func _ledger_int(npc_id: String, key: String) -> int:
	var npc: NPCRuntime = get_npc(npc_id)
	return int(npc.ledger.get(key, 0)) if npc != null else 0


func _entries_total(npc_id: String, list_key: String, value_key: String) -> int:
	var npc: NPCRuntime = get_npc(npc_id)
	var total: int = 0
	if npc != null:
		for entry: Variant in npc.ledger.get(list_key, []):
			if entry is Dictionary:
				total += int((entry as Dictionary).get(value_key, 0))
	return total


func _shift_affection(npc: NPCRuntime, delta: int) -> void:
	npc.ledger["affection"] = clampi(int(npc.ledger["affection"]) + delta, -AFFECTION_LIMIT,
			AFFECTION_LIMIT)


func _shift_mood(npc: NPCRuntime, delta: float) -> void:
	npc.mood = clampf(npc.mood + delta, -MOOD_LIMIT, MOOD_LIMIT)


static func _ledger_has_entries(ledger: Dictionary) -> bool:
	for key: String in ["affection", "fear", "debt"]:
		if int(ledger.get(key, 0)) != 0:
			return true
	return not (ledger.get("grievances", []) as Array).is_empty() \
			or not (ledger.get("favours", []) as Array).is_empty()


## Solo los hechos negativos que no gestiona otro módulo disparan la evaluación y suman en el
## término de creencias (§7.5): verte trabajar o ser competente no es motivo de denuncia.
func _should_react_to(fact: String) -> bool:
	return not _is_ignored_fact(fact) and BeliefNet.is_negative_fact(fact)


static func _is_ignored_fact(fact: String) -> bool:
	var kind: String = fact.get_slice(":", 0)
	return IGNORED_FACT_PREFIXES.has(kind)


static func _base_room(room_id: String) -> String:
	return DatabaseSystem.get_room_base_id(room_id)


## Misma sala; una copia transversal ("corridors_low@3") coincide con su id base sin planta.
static func _same_room(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if a == b:
		return true
	var suffix: String = DatabaseSystem.INSTANCE_SEPARATOR
	return (not a.contains(suffix) or not b.contains(suffix)) and _base_room(a) == _base_room(b)


static func _link_target(link: Dictionary, self_id: String) -> String:
	var to: String = str(link.get("to", link.get("target", "")))
	if to == self_id:
		return str(link.get("from", ""))
	return to


static func _link_type(link: Dictionary) -> String:
	return str(link.get("type", link.get("link_type", "")))
