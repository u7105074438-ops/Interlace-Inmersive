# endgame.gd — Secuencia final de apropiación (§2.2, §11.8, §12.9, PASO 45): revelación, combinación, ventana temporal, documentos, notaría y resolución.
# PROPIETARIO DE: nada propio (BUILD_NOTES §12): el estado de la misión vive en las banderas de PlayerState (claves "endgame.*", se guardan con PlayerState); la vigilancia personal de Voss, en NPCDirector; la notaría y los ejes, en Tracking.
# ESCUCHA: occupation_changed, day_advanced, quarter_closed, room_entered, npc_removed, item_disposed (diferida) — solo el nodo que añade game_root.
class_name Endgame
extends Node

## Manual §2.2, §5.3, §7.10, §8.3, §9.11, §11.8, §12.4, §12.9, §15.3; PASO 45; BUILD_NOTES §2, §12-§14.
## Emite: ownership_documents_obtained, ownership_notarised, game_over (victoria y THE FIGUREHEAD),
## crime_committed (file_copied, lock_forced, forgery, records_deleted), blackmail_initiated,
## noise_emitted, player_seen_partially (Pearl en estadístico), notebook_entry_added (categoría
## final.categoria_cuaderno).
## USO: API ESTÁTICA (la llaman la interacción del mundo, la interfaz y las pruebas). El nodo
## (Endgame.new() hijo de la escena de juego) escucha el calendario y el mundo: sin él no hay
## revelación automática en el ascenso, ni investigación del día siguiente, ni plazo de notaría, ni
## mandato, ni corte de la visita a los archivos al salir del despacho, ni anulación inmediata si el
## notario deja la plantilla, ni recuperación inmediata de los documentos perdidos (process_day
## repasa estas dos cada jornada). Toda acción devuelve {ok: bool, reason: String, ...}; ok = el
## paso se completó. reason_key(r) = ENDGAME_REASON_<R>. Endgame no avanza el reloj salvo
## retrieve_documents (InventoryRules.retrieve_from_stash cobra los minutos del alijo): los demás
## tiempos van en el resultado (minutes) y los actos largos se informan por tramos con los minutos
## que el mundo midió.
## DECISIONES (contrato):
##  · FASE 1: is_objective_revealed() = bandera o rango ≥ el de final.ocupacion_revelacion
##    (legal_director, R26). Se revela UNA vez (ENDGAME_NOTE_REVEALED) y no se olvida al descender.
##    Antes, toda acción de la misión devuelve "objective_hidden" salvo register_office_entry (gancho
##    de movimiento del mundo: los accesos existen antes de la revelación; solo informa de testigo y
##    minutos). get_phase() / get_objective_text_key() (OBJECTIVE_<FASE>) / get_objective_args().
##  · FASE 2, tres vías. PEARL: approach_pearl("blackmail" | "favour" | "bribe"). Soborno
##    inviable (fracasa siempre). Chantaje: con su secreto (knows_pearl_secret: expediente completo
##    de RR. HH. o un puesto con final.pearl.acceso_expediente) funciona SIEMPRE (emite
##    blackmail_initiated → temor y agravio); sin él fracasa. Favor: uno del registro de magnitud ≥
##    magnitud_favor_extraordinario; do_pearl_favour(tipo) lo produce (final.pearl.favores:
##    bury_annex = retirar el anexo de su expediente en hr_office, delito records_deleted;
##    ratify_signatures = convalidarlo como legal_director en legal_archive). Ambos exigen su
##    secreto y lo cubren: después ya no hay material de chantaje. get_pearl_favours() para la
##    interfaz. FRACASO → Pearl informa al ocupante del despacho: denuncia al superior
##    (NPCDirector.report_player_to_superior) solo si no está ya vigilando por su palabra, y
##    begin_personal_surveillance(ocupante, dias_vigilancia) (renueva el plazo): LOD 0,
##    perspicacia + bonus y seguimiento. ARCHIVOS: search_voss_files(minutos, observado) en el
##    despacho: minutos_requeridos sin testigos en UNA visita (salir del despacho, entrar por un
##    acceso, cambiar de jornada o ser visto —alguien dentro, `observed`, o Pearl que se asoma:
##    tirada por minuto— ponen el progreso a 0); al terminar crime_committed("file_copied").
##    FÍSICA: work_on_safe(minutos, posición) con puesto (security_director actual o ejercido,
##    maintenance_aide actual o uniforme de mantenimiento) Y herramienta de forzado encima
##    (cutting_tools / angle_grinder): ruido de radio_ruido por tramo; al terminar
##    crime_committed("lock_forced") y, a la jornada siguiente, investigación segura (object_missing
##    en el despacho, exenta de respiro, con el jugador entre los sospechosos por móvil:
##    register_motive; el bonus de acceso lo calcula Security por acreditación y registro de
##    tarjetas). Ocupar la silla NO da la combinación (§11.8).
##  · FASE 3: get_voss_absence_windows(día) = huecos del ocupante del despacho dentro de su horario
##    (npcs_named special.office_hours de Voss, 10:00-17:00): [{start, end, room}] en minutos del
##    día según su AGENDA (hoy con sustituciones, sin el seguimiento de la vigilancia personal:
##    is_office_holder_following() avisa de que ahora mismo va detrás del jugador).
##    provoke_long_meeting(franja, vía) lo encierra la franja entera en final.reunion.sala: el
##    jugador si ocupa u ocupó meeting_coordinator, o un aliado (titular del puesto con afecto o
##    deuda; Preston mientras es aliado táctico); una por jornada y solo franjas que no hayan
##    terminado. Tres accesos (get_access_routes: {id, name_key, from_room, interactable, minutes,
##    pearl_witness}; register_office_entry): puerta principal, cornisa de la terraza y conducto.
##  · FASE 4: los documentos (ownership_documents, comprometedor): open_safe() (combinación) o la
##    vía física. Llevarlos a un registro corporal con sospecha > 0 es condena grave (InventoryRules);
##    hide_documents / retrieve_documents usan los alijos de PlayerState. are_documents_at_risk().
##    PERDIDOS fuera de la notaría (tirados, requisados, hallados en un alijo): check_documents_lost()
##    los devuelve a la caja (la empresa los recupera; la combinación sigue valiendo) con nota.
##  · FASE 5: request_notarisation() en la notaría con los documentos ENCIMA, título —ocupar el cargo
##    (final.ocupacion_cargo) o llevar una forged_authorization (forge_authorization(): estampa +
##    reputación ≥ reputacion_minima, rebajada si se ocupa u ocupó c10_director; delito "forgery" →
##    registro neutro sin verificar de BeliefNet)— y el NOTARIO EN SU SALA (final.sala_notaria;
##    si no, "notary_absent"). Notario: sospecha efectiva (Security) ≥ sospecha_verificacion →
##    comprueba (gana a la reputación); si no, reputación ≥ reputacion_sin_verificacion o deuda del
##    notario → firma; si no, comprueba con su perspicacia. COMPROBACIÓN: documentos (y
##    autorización) en custodia (Tracking los sigue contando), plazo verification_days de la mesa
##    (3 jornadas) de MÁXIMA VULNERABILIDAD: cada caso activo contra el jugador recibe una pieza
##    file_annotation de bonus_peso_investigacion. Si el notario deja la plantilla, la comprobación
##    se anula y devuelve los papeles (y la autorización sin comprobar). Al vencer, con el título
##    de ese momento: ocupar la silla → firma (supera a una autorización falsa, que no se examina);
##    autorización falsa → BeliefNet la confirma y Security abre un caso forged_document (pieza
##    documento_falsificado, 5,0) contra el jugador y los documentos vuelven a la caja; cargo
##    perdido → los devuelve.
##  · FASE 6: firmar = ownership_notarised y en el acto game_over("ownership_notarised", final de
##    Tracking.evaluate_ending_for_cause, snapshot + {notary_title, combination_source}). R33 → final
##    por eje dominante; por debajo (autorización falsa) → THE OWNER IN EXILE. THE FIGUREHEAD:
##    endings.json figurehead_term_quarters trimestres COMPLETOS en el cargo sin notariar →
##    game_over("ceo_term_without_ownership"). Nada se emite tras un fin de partida.
##  · VOSS «nadie le dice la verdad»: reassure_voss_via(npc) levanta su vigilancia si el
##    intermediario llega a él (escalón o vínculo) y quiere (afecto, deuda o temor).
##    PRESTON VAILE III: get_preston_stance() aliado táctico mientras Voss ocupa la silla y el
##    jugador está por debajo de vice_ceo; después rival (una vez: agravio rival_for_chair y nota).
##    Ganchos para Aurora/utilidad: is_hostile_rival(id), is_bribe_viable(id) (Pearl: false).
## Pruebas: `roll_source` (Callable → float en [0, 1)) sustituye la tirada sembrada.

const PLAYER_ID := "player"
const VOSS_ID := "npc_harlan_voss"
const PEARL_ID := "npc_pearl_osgood"
const PRESTON_ID := "npc_preston_vaile"
const OWNERSHIP_ITEM := TrackingSystem.OWNERSHIP_ITEM
const FORGED_ITEM := "forged_authorization"
const STAMP_ITEM := "stamp"
const CAUSE_NOTARISED := TrackingSystem.CAUSE_NOTARISED
const CAUSE_FIGUREHEAD := "ceo_term_without_ownership"
const ENDINGS_FILE := "endings"
const E_FIGUREHEAD_TERM := "figurehead_term_quarters"
const OFFICE_HOURS_KEY := "office_hours"
const SPECIAL_KEY := "special"
const NOTARY_DESK_TYPE := "notary_desk"
const VERIFICATION_DAYS_KEY := "verification_days"
const COMMENT_PREFIX := "_"
const PERCENT := 100.0
const NO_DAY := -1
const MINUTES_PER_HOUR := 60
const RNG_SALT := "endgame"
const SEED_FORMAT := "%d|%s|%d"

# Fases (get_phase) y títulos de la notaría.
const PHASE_HIDDEN := "hidden"
const PHASE_COMBINATION := "combination"
const PHASE_SAFE := "safe"
const PHASE_CUSTODY := "custody"
const PHASE_VERIFICATION := "verification"
const PHASE_RESOLVED := "resolved"
const TITLE_CHAIR := "ceo"
const TITLE_FORGED := "forged"
# Vías de la combinación y de apertura.
const SOURCE_PEARL := "pearl"
const SOURCE_FILES := "voss_files"
const SOURCE_CHAIR := "ceo_chair"
const METHOD_BLACKMAIL := "blackmail"
const METHOD_FAVOUR := "favour"
const METHOD_BRIBE := "bribe"
const PEARL_METHODS: Array[String] = [METHOD_BLACKMAIL, METHOD_FAVOUR, METHOD_BRIBE]
const ROUTE_COMBINATION := "combination"
const ROUTE_PHYSICAL := "physical"
const ACCESS_MAIN_DOOR := "main_door"
const ACCESS_ROOF_LEDGE := "roof_ledge"
const ACCESS_VENT := "vent"
const STANCE_ALLY := "ally"
const STANCE_HOSTILE := "hostile"
const STANCE_NEUTRAL := "neutral"
# Estado de los documentos (get_documents_state).
const DOCS_NONE := "none"
const DOCS_CARRIED := "carried"
const DOCS_HIDDEN := "hidden"
const DOCS_WITH_NOTARY := "with_notary"
const DOCS_NOTARISED := "notarised"
# Resultados de la notaría.
const NOTARY_SIGNED := "signed"
const NOTARY_VERIFY := "verification"
const DECISION_UNCERTAIN := "uncertain"

# Motivos (reason) → ENDGAME_REASON_<R>.
const R_OVER := "run_over"
const R_HIDDEN := "objective_hidden"
const R_INVALID := "invalid_method"
const R_NOT_IN_OFFICE := "not_in_office"
const R_NOT_AT_NOTARY := "not_at_notary"
const R_ALREADY_KNOWN := "already_known"
const R_UNAVAILABLE := "unavailable"
const R_UNBRIBABLE := "unbribable"
const R_NO_MATERIAL := "no_material"
const R_FAVOUR_TOO_SMALL := "favour_too_small"
const R_NO_SECRET := "no_secret"
const R_ALREADY_DONE := "already_done"
const R_WRONG_ROOM := "wrong_room"
const R_OBSERVED := "observed"
const R_IN_PROGRESS := "in_progress"
const R_OCCUPIED := "occupied"
const R_NO_COMBINATION := "no_combination"
const R_NO_MEANS := "no_means"
const R_NO_TOOLS := "no_tools"
const R_ALREADY_TAKEN := "already_taken"
const R_INVENTORY_FULL := "inventory_full"
const R_NO_STAMP := "no_stamp"
const R_LOW_REPUTATION := "low_reputation"
const R_NO_DOCUMENTS := "no_documents"
const R_NO_TITLE := "no_title"
const R_NO_NOTARY := "no_notary"
const R_NOTARY_ABSENT := "notary_absent"
const R_PENDING := "verification_pending"
const R_BAD_BAND := "invalid_band"
const R_BAND_OVER := "band_over"
const R_NO_AUTHORITY := "no_authority"
const R_NO_TARGET := "no_target"
const R_ALREADY_TODAY := "already_today"
const R_UNKNOWN_ROUTE := "unknown_route"
const R_NOT_WATCHED := "not_watched"
const R_NO_ACCESS := "no_access"
const R_UNWILLING := "unwilling"
const REASON_KEY_FORMAT := "ENDGAME_REASON_%s"
const OBJECTIVE_KEY_FORMAT := "OBJECTIVE_%s"
const ACCESS_KEY_FORMAT := "ENDGAME_ACCESS_%s"
const STANCE_KEY_FORMAT := "ENDGAME_STANCE_%s"
const FAVOUR_KEY_FORMAT := "ENDGAME_FAVOUR_%s"

# Claves de los resultados.
const K_OK := "ok"
const K_REASON := "reason"
const K_PROGRESS := "progress"
const K_REQUIRED := "required"
const K_SOURCE := "source"
const K_WITNESS := "witness"
const K_ROUTE := "route"
const K_MINUTES := "minutes"
const K_OUTCOME := "outcome"
const K_TITLE := "title"
const K_DAYS := "days"
const K_RECORD := "record_id"
const K_INFORMED := "informed_voss"
const K_WINDOW := "window"
const K_MAGNITUDE := "magnitude"
const K_OCCUPATION := "occupation"
const K_AVAILABLE := "available"
# Ventanas y accesos (salida en inglés; entrada: claves de balance final.accesos).
const W_START := "start"
const W_END := "end"
const W_ROOM := "room"
const A_ID := "id"
const A_NAME_KEY := "name_key"
const A_FROM := "from_room"
const A_INTERACTABLE := "interactable"
const A_MINUTES := "minutes"
const A_PEARL := "pearl_witness"
const BA_FROM := "desde"
const BA_INTERACTABLE := "interactivo"
const BA_MINUTES := "minutos"
const BA_PEARL := "testigo_pearl"
# Tabla final.pearl.favores.
const FV_ROOM := "sala"
const FV_OCCUPATION := "ocupacion"
const FV_CRIME := "delito"
const FV_MAGNITUDE := "magnitud"
const FAVOUR_COVERED_SECRET := "covered_secret"
const M_DAY := "day"
const M_BAND := "band"
const M_VIA := "via"
# Comprobación notarial (bandera F_VERIFICATION).
const V_START := "start_day"
const V_END := "end_day"
const V_TITLE := "title"
const V_NOTARY := "notary"
const V_RECORD := "record_id"
const V_CASES := "bonus_cases"
# Snapshot de la victoria.
const S_TITLE := "notary_title"
const S_COMBINATION := "combination_source"

# Banderas de PlayerState (estado de la misión, se guardan con PlayerState).
const F_REVEALED := "endgame.revealed"
const F_REVEALED_DAY := "endgame.revealed_day"
const F_COMBINATION := "endgame.combination_source"
const F_PEARL_FAILED := "endgame.pearl_failed_day"
const F_PEARL_COVERED := "endgame.pearl_secret_covered"
const F_FILES_MINUTES := "endgame.files_minutes"
const F_FILES_DAY := "endgame.files_day"
const F_SAFE_MINUTES := "endgame.safe_minutes"
const F_DOCS_TAKEN := "endgame.documents_taken"
const F_DOCS_DAY := "endgame.documents_day"
const F_DOCS_ROUTE := "endgame.documents_route"
const F_DOCS_LOST_DAY := "endgame.documents_lost_day"
const F_DOCS_LODGED := TrackingSystem.DOCS_LODGED_FLAG
const F_SAFE_FORCED_DAY := "endgame.safe_forced_day"
const F_SAFE_FORCED_HOUR := "endgame.safe_forced_hour"
const F_SAFE_CASE := "endgame.safe_case"
const F_FORGERY_CASE := "endgame.forgery_case"
const F_HELD := "endgame.held_occupations"
const F_MEETINGS := "endgame.meetings"
const F_ENTRY_ROUTE := "endgame.last_entry_route"
const F_FORGED_RECORDS := "endgame.forged_records"
const F_VERIFICATION := "endgame.verification"
const F_CEO_SINCE := "endgame.ceo_since_day"
const F_CEO_QUARTERS := "endgame.ceo_full_quarters"
const F_PRESTON_HOSTILE := "endgame.preston_hostile"
const F_ROLLS := "endgame.rolls"
const F_LAST_DAY := "endgame.last_processed_day"
const F_LAST_QUARTER := "endgame.last_processed_quarter"

# Señales de otros dominios.
const CRIME_FILE_COPIED := "file_copied"
const CRIME_LOCK_FORCED := "lock_forced"
const CRIME_FORGERY := "forgery"
const D_TARGET := "target"
const D_DOCUMENT := "document"
const FILES_TARGET := "voss_files"
const SAFE_TARGET := "ceo_safe_main"
const PEARL_SECRET_TARGET := "pearl_secret"
const LEVERAGE_FILE := "personnel_file"
const NOISE_SOURCE_SAFE := "safe_forced"
const SURVEILLANCE_REASON := "pearl_report"
const GRIEVANCE_RIVAL := "rival_for_chair"
const INCIDENT_SAFE := "object_missing"
const INCIDENT_FORGED := "forged_document"
const EV_FORGED := "forged_document"
const LEDGER_FAVOURS := "favours"
const LEDGER_MAGNITUDE := "magnitude"
const TRAIT_PERCEPTION := "perception"
const I_ALWAYS_OPENS := "always_opens"
const I_SUBJECT := "subject"
const I_EVIDENCE := "evidence_type"
const I_WEIGHT := "weight"
const I_RECORD := "record_id"
const I_CULPRIT := "player_culprit"
const I_DAY := "day"
const I_HOUR := "hour"
const I_FROM_DAY := "evidence_from_day"

# Cuaderno.
const NOTE_REVEALED := "ENDGAME_NOTE_REVEALED"
const NOTE_PEARL_BLACKMAIL := "ENDGAME_NOTE_PEARL_BLACKMAIL"
const NOTE_PEARL_FAVOUR := "ENDGAME_NOTE_PEARL_FAVOUR"
const NOTE_PEARL_COVERED := "ENDGAME_NOTE_PEARL_SECRET_COVERED"
const NOTE_PEARL_INFORMED := "ENDGAME_NOTE_PEARL_INFORMED"
const NOTE_FILES_FOUND := "ENDGAME_NOTE_FILES_FOUND"
const NOTE_MEETING := "ENDGAME_NOTE_MEETING"
const NOTE_DOCUMENTS := "ENDGAME_NOTE_DOCUMENTS"
const NOTE_DOCUMENTS_LOST := "ENDGAME_NOTE_DOCUMENTS_LOST"
const NOTE_SAFE_FORCED := "ENDGAME_NOTE_SAFE_FORCED"
const NOTE_FORGED := "ENDGAME_NOTE_FORGED"
const NOTE_VERIFICATION := "ENDGAME_NOTE_VERIFICATION"
const NOTE_FORGERY_DETECTED := "ENDGAME_NOTE_FORGERY_DETECTED"
const NOTE_TITLE_LOST := "ENDGAME_NOTE_TITLE_LOST"
const NOTE_NOTARY_GONE := "ENDGAME_NOTE_NOTARY_GONE"
const NOTE_NOTARISED := "ENDGAME_NOTE_NOTARISED"
const NOTE_PRESTON_HOSTILE := "ENDGAME_NOTE_PRESTON_HOSTILE"
const NOTE_VOSS_REASSURED := "ENDGAME_NOTE_VOSS_REASSURED"

# Rutas de balance.json.
const B_REVEAL_OCC := "final.ocupacion_revelacion"
const B_CHAIR := "final.ocupacion_cargo"
const B_RIVAL_OCC := "final.ocupacion_rival_hostil"
const B_COORDINATOR := "final.ocupacion_coordinador"
const B_CREDIBLE_FORGER := "final.ocupacion_verosimil_falsificacion"
const B_OFFICE := "final.sala_despacho"
const B_SECRETARIAT := "final.sala_secretaria"
const B_NOTARY_ROOM := "final.sala_notaria"
const B_NOTARY_ROLE := "final.rol_notario"
const B_NOTE_CATEGORY := "final.categoria_cuaderno"
const B_WINDOW_STEP := "final.ventana.minutos_muestra"
const B_WINDOW_MIN := "final.ventana.minutos_minimos"
const B_PEARL_ACCESS := "final.pearl.acceso_expediente"
const B_PEARL_FAVOUR := "final.pearl.magnitud_favor_extraordinario"
const B_PEARL_FAVOURS := "final.pearl.favores"
const B_PEARL_DAYS := "final.pearl.dias_vigilancia"
const B_FILES_MINUTES := "final.archivos_voss.minutos_requeridos"
const B_FILES_PEARL_CHANCE := "final.archivos_voss.prob_pearl_por_minuto"
const B_FILES_PEARL_CERTAINTY := "final.archivos_voss.certeza_pearl"
const B_PHYS_HELD := "final.apertura_fisica.ocupaciones_ejercidas"
const B_PHYS_CURRENT := "final.apertura_fisica.ocupaciones_actuales"
const B_PHYS_DISGUISES := "final.apertura_fisica.disfraces"
const B_PHYS_TOOLS := "final.apertura_fisica.herramientas"
const B_PHYS_MINUTES := "final.apertura_fisica.minutos_requeridos"
const B_PHYS_NOISE := "final.apertura_fisica.radio_ruido"
const B_PHYS_SEVERITY := "final.apertura_fisica.gravedad_investigacion"
const B_MEETING_BANDS := "final.reunion.franjas"
const B_MEETING_ROOM := "final.reunion.sala"
const B_MEETING_AFFECTION := "final.reunion.afecto_aliado"
const B_MEETING_DEBT := "final.reunion.deuda_consumida"
const B_MEETING_MAX := "final.reunion.max_por_dia"
const B_ACCESSES := "final.accesos"
const B_DOOR_CERTAINTY := "final.certeza_pearl_puerta"
const B_FORGE_REPUTATION := "final.falsificacion.reputacion_minima"
const B_FORGE_DISCOUNT := "final.falsificacion.rebaja_verosimil"
const B_NOTARY_SUSPICION := "final.notaria.sospecha_verificacion"
const B_NOTARY_REPUTATION := "final.notaria.reputacion_sin_verificacion"
const B_NOTARY_TRAIT := "final.notaria.factor_rasgo_verificacion"
const B_NOTARY_DAYS := "final.notaria.dias_verificacion"
const B_NOTARY_BONUS := "final.notaria.bonus_peso_investigacion"
const B_NOTARY_SEVERITY := "final.notaria.gravedad_falsificacion"
const B_VOSS_TIER := "final.voss.escalon_min_intermediario"
const B_VOSS_AFFECTION := "final.voss.afecto_min_intermediario"
const B_VOSS_FEAR := "final.voss.temor_min_intermediario"
const B_VOSS_DEBT := "final.voss.deuda_consumida"
const B_PRESTON_SEVERITY := "final.preston.gravedad_rivalidad"
const B_FORGED_WEIGHT := "investigaciones.pesos_evidencia.documento_falsificado"
const B_DAYS_QUARTER := "tiempo.jornadas_por_trimestre"
const B_DAY_START := "tiempo.hora_inicio_jornada"
const B_DAY_END := "tiempo.hora_fin_jornada"

## Pruebas: sustituye la tirada sembrada (Callable sin argumentos → float en [0, 1)).
static var roll_source: Callable = Callable()


func _ready() -> void:
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.quarter_closed.connect(_on_quarter_closed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.npc_removed.connect(_on_npc_removed)
	# Diferida: una requisa emite item_disposed antes de sacar el objeto del inventario.
	EventBus.item_disposed.connect(_on_item_disposed, CONNECT_DEFERRED)
	note_occupation(PlayerState.get_occupation_id())


func _on_occupation_changed(_old_id: String, new_id: String, _reason: String) -> void:
	note_occupation(new_id)


func _on_day_advanced(day_number: int) -> void:
	process_day(day_number)


func _on_quarter_closed(quarter_number: int) -> void:
	process_quarter(quarter_number)


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if by_player:
		note_player_room(room_id)


func _on_npc_removed(npc_id: String, _cause: String) -> void:
	note_npc_removed(npc_id)


func _on_item_disposed(item_id: String, _method: String) -> void:
	if item_id == OWNERSHIP_ITEM:
		check_documents_lost()


# ═══ Fase 1: revelación y objetivo ════════════════════════════════════

static func is_objective_revealed() -> bool:
	return bool(PlayerState.get_flag(F_REVEALED, false)) \
			or PlayerState.get_rank() >= get_revelation_rank()


## Rango de final.ocupacion_revelacion (legal_director = R26).
static func get_revelation_rank() -> int:
	return _rank_of(_bal_s(B_REVEAL_OCC))


## hidden | combination | safe | custody | verification | resolved.
static func get_phase() -> String:
	if _is_over():
		return PHASE_RESOLVED
	if not is_objective_revealed():
		return PHASE_HIDDEN
	if is_verification_pending():
		return PHASE_VERIFICATION
	if has_documents():
		return PHASE_CUSTODY
	if knows_combination() or has_physical_means():
		return PHASE_SAFE
	return PHASE_COMBINATION


static func get_objective_text_key() -> String:
	return OBJECTIVE_KEY_FORMAT % get_phase().to_upper()


## Argumentos del texto del objetivo (jornadas de comprobación que faltan).
static func get_objective_args() -> Array:
	return [get_verification_days_left()] if is_verification_pending() else []


static func reason_key(reason: String) -> String:
	return REASON_KEY_FORMAT % reason.to_upper()


## Oyente del nodo (y de pruebas): puestos ejercidos, revelación, mandato en la silla y Preston.
static func note_occupation(occupation_id: String) -> void:
	var held: Array = _flag_array(F_HELD)
	if not occupation_id.is_empty() and not held.has(occupation_id):
		held.append(occupation_id)
		PlayerState.set_flag(F_HELD, held)
	_ensure_revealed()
	_track_chair(occupation_id)
	_check_preston()


static func has_held(occupation_id: String) -> bool:
	return PlayerState.get_occupation_id() == occupation_id \
			or _flag_array(F_HELD).has(occupation_id)


## Oyente del nodo (y de pruebas): salir del despacho corta la visita a los archivos de Voss.
static func note_player_room(room_id: String) -> void:
	if Database.get_room_base_id(room_id) != _bal_s(B_OFFICE):
		_reset_files_progress()


## Oyente del nodo: si el notario que comprobaba deja la plantilla, la comprobación se anula ya.
static func note_npc_removed(npc_id: String) -> void:
	var v: Dictionary = get_verification()
	if not _is_over() and not v.is_empty() and str(v.get(V_NOTARY, "")) == npc_id:
		_cancel_verification(v)


# ═══ Fase 2: la combinación ═══════════════════════════════════════════

static func knows_combination() -> bool:
	return not get_combination_source().is_empty()


## "pearl" | "voss_files" | "". §11.8: solo Voss conoce la combinación; ocupar la silla NO la
## revela (las tres vías siguen siendo obligatorias; la silla solo cambia el título de fase 5).
static func get_combination_source() -> String:
	return str(PlayerState.get_flag(F_COMBINATION, ""))


## Gancho de Bribery/interfaz: Pearl Osgood no se compra (§11.8).
static func is_bribe_viable(npc_id: String) -> bool:
	return npc_id != PEARL_ID


## Su secreto (el anexo sellado de su expediente): expediente completo o un puesto con acceso a
## todos los expedientes (final.pearl.acceso_expediente).
static func knows_pearl_secret() -> bool:
	if PlayerState.has_full_file(PEARL_ID):
		return true
	var occupation: OccupationData = PlayerState.get_occupation()
	return occupation != null and occupation.special_access.has(_bal_s(B_PEARL_ACCESS))


## Un favor extraordinario ya cubrió su secreto: no queda material de chantaje.
static func is_pearl_secret_covered() -> bool:
	return PlayerState.has_flag(F_PEARL_COVERED)


## Vía Pearl Osgood. Fracaso (soborno, sin material, favor pequeño) → informa al ocupante del despacho.
static func approach_pearl(method: String) -> Dictionary:
	var blocked: String = _pearl_block(method)
	if not blocked.is_empty():
		return _fail(blocked)
	var refusal: String = _pearl_refusal(method)
	if not refusal.is_empty():
		_pearl_informs_voss()
		return _fail(refusal, {K_INFORMED: true})
	if method == METHOD_BLACKMAIL:
		EventBus.blackmail_initiated.emit(PLAYER_ID, PEARL_ID, LEVERAGE_FILE)
	_learn_combination(SOURCE_PEARL,
			NOTE_PEARL_BLACKMAIL if method == METHOD_BLACKMAIL else NOTE_PEARL_FAVOUR)
	return _ok({K_SOURCE: SOURCE_PEARL})


## Favor de magnitud extraordinaria (final.pearl.favores): cubrir su secreto. Deja el favor en su
## registro (approach_pearl("favour") lo cobra) y agota el material de chantaje. {ok, magnitude}.
static func do_pearl_favour(kind: String) -> Dictionary:
	var blocked: String = _pearl_favour_block(kind)
	if not blocked.is_empty():
		return _fail(blocked)
	var spec: Dictionary = _favour_spec(kind)
	var crime: String = str(spec.get(FV_CRIME, ""))
	if not crime.is_empty():
		EventBus.crime_committed.emit(crime, PlayerState.get_room(), {D_TARGET: PEARL_SECRET_TARGET})
	var magnitude: int = int(spec.get(FV_MAGNITUDE, 0))
	NPCDirector.add_favour(PEARL_ID, FAVOUR_COVERED_SECRET, magnitude)
	PlayerState.set_flag(F_PEARL_COVERED, kind)
	_note(NOTE_PEARL_COVERED, [_npc_name(PEARL_ID)])
	return _ok({K_MAGNITUDE: magnitude})


## Para la interfaz: [{id, name_key, room, occupation, magnitude, available, reason}].
static func get_pearl_favours() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: Variant in _bal_dict(B_PEARL_FAVOURS):
		var spec: Dictionary = _favour_spec(str(kind))
		if spec.is_empty():
			continue
		var reason: String = _pearl_favour_block(str(kind))
		out.append({A_ID: str(kind), A_NAME_KEY: FAVOUR_KEY_FORMAT % str(kind).to_upper(),
				W_ROOM: str(spec.get(FV_ROOM, "")), K_OCCUPATION: str(spec.get(FV_OCCUPATION, "")),
				K_MAGNITUDE: int(spec.get(FV_MAGNITUDE, 0)), K_AVAILABLE: reason.is_empty(),
				K_REASON: reason})
	return out


## Vía archivos de Voss: tramo de búsqueda de `minutes` minutos en su despacho (una sola visita).
static func search_voss_files(minutes: int, observed: bool = false) -> Dictionary:
	var blocked: String = _office_block()
	if blocked.is_empty() and knows_combination():
		blocked = R_ALREADY_KNOWN
	if not blocked.is_empty():
		return _fail(blocked)
	var required: int = _bal_i(B_FILES_MINUTES)
	var witness: String = _office_witness(minutes)
	if observed or not witness.is_empty():
		_reset_files_progress()
		return _fail(R_OBSERVED, {K_WITNESS: witness, K_PROGRESS: 0, K_REQUIRED: required})
	var total: int = get_files_progress() + maxi(minutes, 0)
	PlayerState.set_flag(F_FILES_MINUTES, total)
	PlayerState.set_flag(F_FILES_DAY, GameClock.get_day())
	if total < required:
		return _fail(R_IN_PROGRESS, {K_PROGRESS: total, K_REQUIRED: required})
	EventBus.crime_committed.emit(CRIME_FILE_COPIED, _bal_s(B_OFFICE), {D_TARGET: FILES_TARGET})
	_learn_combination(SOURCE_FILES, NOTE_FILES_FOUND)
	return _ok({K_PROGRESS: total, K_REQUIRED: required, K_SOURCE: SOURCE_FILES})


## Minutos acumulados en la visita en curso a los archivos (0 si es otra jornada).
static func get_files_progress() -> int:
	if _flag_int(F_FILES_DAY, NO_DAY) != GameClock.get_day():
		return 0
	return _flag_int(F_FILES_MINUTES)


## Medios materiales de apertura: puesto de apertura_fisica Y herramienta de forzado encima.
static func has_physical_means() -> bool:
	return has_forcing_post() and has_forcing_tool()


## Director de Seguridad (actual o ejercido), mantenimiento actual o su uniforme.
static func has_forcing_post() -> bool:
	for occupation: Variant in _bal_array(B_PHYS_HELD):
		if has_held(str(occupation)):
			return true
	if _bal_array(B_PHYS_CURRENT).has(PlayerState.get_occupation_id()):
		return true
	var disguise: String = PlayerState.get_disguise()
	return not disguise.is_empty() and _bal_array(B_PHYS_DISGUISES).has(disguise)


## Herramienta de forzado (final.apertura_fisica.herramientas) en el inventario.
static func has_forcing_tool() -> bool:
	for tool: Variant in _bal_array(B_PHYS_TOOLS):
		if PlayerState.is_carrying(str(tool)):
			return true
	return false


# ═══ Fase 3: la ventana temporal ══════════════════════════════════════

## NPC que ocupa el despacho (titular activo del cargo); "" si es el jugador o no hay nadie.
static func get_office_holder() -> String:
	if _holds_chair():
		return ""
	var holder: NPCRuntime = NPCDirector.get_npc_by_occupation(_bal_s(B_CHAIR))
	return holder.id if holder != null else ""


## Horario de despacho (minutos del día): special.office_hours de Voss o la jornada laboral.
static func get_office_hours() -> Vector2i:
	var fallback: Vector2i = Vector2i(_bal_i(B_DAY_START), _bal_i(B_DAY_END)) * MINUTES_PER_HOUR
	var voss: NPCData = Database.get_named_npc(VOSS_ID)
	if voss == null:
		return fallback
	var hours: Variant = _dict(voss.extra.get(SPECIAL_KEY, {})).get(OFFICE_HOURS_KEY, [])
	if not (hours is Array) or (hours as Array).size() < 2:
		return fallback
	return Vector2i(NPCRoutinePlanner.parse_time(str(hours[0])),
			NPCRoutinePlanner.parse_time(str(hours[1])))


## Huecos del ocupante dentro de su horario según su agenda: [{start, end, room}] (minutos;
## room = dónde estará). Hoy incluye las sustituciones (reuniones provocadas), no el seguimiento.
static func get_voss_absence_windows(day: int) -> Array[Dictionary]:
	var hours: Vector2i = get_office_hours()
	var holder: String = get_office_holder()
	if holder.is_empty():
		return [{W_START: hours.x, W_END: hours.y, W_ROOM: ""}]
	var plan: Array = NPCDirector.get_day_plan_for_day(holder, day)
	var today: bool = day == GameClock.get_day()
	var step: int = maxi(_bal_i(B_WINDOW_STEP), 1)
	var rooms: Array[String] = []
	for minute: int in range(hours.x, hours.y, step):
		rooms.append(_holder_room_at(holder, plan, minute, today))
	return _windows_from(rooms, hours, step)


static func is_voss_in_office() -> bool:
	var holder: String = get_office_holder()
	return not holder.is_empty() and _npc_in(holder, _bal_s(B_OFFICE))


## El ocupante vigila ahora al jugador: su agenda no dice dónde estará (va detrás de él en las
## franjas de seguimiento). La interfaz lo advierte junto a las ventanas.
static func is_office_holder_following() -> bool:
	var holder: String = get_office_holder()
	return not holder.is_empty() and not NPCDirector.get_personal_surveillance(holder).is_empty()


## Reunión prolongada: el ocupante pasa la franja entera en final.reunion.sala (solo hoy).
static func provoke_long_meeting(band: String, via_npc_id: String = "") -> Dictionary:
	var blocked: String = _meeting_block(band, via_npc_id)
	if not blocked.is_empty():
		return _fail(blocked)
	NPCDirector.override_routine(get_office_holder(), band, _bal_s(B_MEETING_ROOM))
	if not via_npc_id.is_empty() and NPCDirector.get_debt(via_npc_id) > 0:
		NPCDirector.add_debt(via_npc_id,
				-mini(_bal_i(B_MEETING_DEBT), NPCDirector.get_debt(via_npc_id)))
	var meetings: Array = _flag_array(F_MEETINGS)
	meetings.append({M_DAY: GameClock.get_day(), M_BAND: band, M_VIA: via_npc_id})
	PlayerState.set_flag(F_MEETINGS, meetings)
	_note(NOTE_MEETING, [_npc_name(get_office_holder()), GameClock.get_band_name_key(band)])
	return _ok({K_WINDOW: _band_window(band)})


## Los tres accesos: [{id, name_key, from_room, interactable, minutes, pearl_witness}].
static func get_access_routes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for route: Variant in _bal_dict(B_ACCESSES):
		var spec: Dictionary = _route_spec(str(route))
		if spec.is_empty():
			continue
		out.append({A_ID: str(route), A_NAME_KEY: ACCESS_KEY_FORMAT % str(route).to_upper(),
				A_FROM: str(spec.get(BA_FROM, "")), A_INTERACTABLE: str(spec.get(BA_INTERACTABLE, "")),
				A_MINUTES: int(spec.get(BA_MINUTES, 0)), A_PEARL: bool(spec.get(BA_PEARL, false))})
	return out


## El jugador entra al despacho por `route` (gancho de movimiento: también antes de la revelación;
## cada entrada es una visita nueva a los archivos). Por la puerta, Pearl lo ve pasar si no tiene
## acreditación (sin nodo que la simule). {ok, minutes (el mundo los gasta), witness}.
static func register_office_entry(route: String) -> Dictionary:
	var spec: Dictionary = _route_spec(route)
	if spec.is_empty():
		return _fail(R_UNKNOWN_ROUTE)
	PlayerState.set_flag(F_ENTRY_ROUTE, route)
	_reset_files_progress()
	var witness: String = ""
	if bool(spec.get(BA_PEARL, false)) and _pearl_sees_entry():
		witness = PEARL_ID
		EventBus.player_seen_partially.emit(PEARL_ID, _bal_f(B_DOOR_CERTAINTY),
				_bal_s(B_SECRETARIAT))
	return _ok({K_ROUTE: route, K_MINUTES: int(spec.get(BA_MINUTES, 0)), K_WITNESS: witness})


# ═══ Fase 4: los documentos ═══════════════════════════════════════════

## Abre la caja con la combinación (instantáneo; el mundo puede añadir su animación).
static func open_safe() -> Dictionary:
	var blocked: String = _safe_block()
	if blocked.is_empty() and not knows_combination():
		blocked = R_NO_COMBINATION
	if not blocked.is_empty():
		return _fail(blocked)
	return _take_documents(ROUTE_COMBINATION)


## Vía física: tramo de `minutes` forzando la caja (ruido en `position`, píxeles del mundo).
static func work_on_safe(minutes: int, position: Vector2 = Vector2.ZERO) -> Dictionary:
	var blocked: String = _safe_block()
	if blocked.is_empty() and not has_forcing_post():
		blocked = R_NO_MEANS
	if blocked.is_empty() and not has_forcing_tool():
		blocked = R_NO_TOOLS
	if not blocked.is_empty():
		return _fail(blocked)
	EventBus.noise_emitted.emit(position, _bal_f(B_PHYS_NOISE), NOISE_SOURCE_SAFE)
	var total: int = _flag_int(F_SAFE_MINUTES) + maxi(minutes, 0)
	PlayerState.set_flag(F_SAFE_MINUTES, total)
	var required: int = _bal_i(B_PHYS_MINUTES)
	if total < required:
		return _fail(R_IN_PROGRESS, {K_PROGRESS: total, K_REQUIRED: required})
	EventBus.crime_committed.emit(CRIME_LOCK_FORCED, _bal_s(B_OFFICE), {D_TARGET: SAFE_TARGET})
	PlayerState.set_flag(F_SAFE_FORCED_DAY, GameClock.get_day())
	PlayerState.set_flag(F_SAFE_FORCED_HOUR, GameClock.get_hour())
	PlayerState.set_flag(F_SAFE_MINUTES, 0)
	_note(NOTE_SAFE_FORCED, [])
	return _take_documents(ROUTE_PHYSICAL)


static func has_documents() -> bool:
	return Tracking.has_ownership_documents()


## none | carried | hidden | with_notary | notarised.
static func get_documents_state() -> String:
	if Tracking.is_notarised():
		return DOCS_NOTARISED
	if bool(PlayerState.get_flag(F_DOCS_LODGED, false)):
		return DOCS_WITH_NOTARY
	if PlayerState.is_carrying(OWNERSHIP_ITEM):
		return DOCS_CARRIED
	return DOCS_HIDDEN if has_documents() else DOCS_NONE


## Llevarlos encima cuando Security ya puede registrar = perder en el siguiente registro.
static func are_documents_at_risk() -> bool:
	return PlayerState.is_carrying(OWNERSHIP_ITEM) and Security.can_search_player()


static func hide_documents(spot_id: String, room_id: String) -> bool:
	return PlayerState.stash_item(OWNERSHIP_ITEM, spot_id, room_id)


## Recupera del alijo. ÚNICA acción que avanza el reloj: InventoryRules cobra los minutos de la
## ubicación. −1 si falla.
static func retrieve_documents(spot_id: String) -> int:
	return InventoryRules.retrieve_from_stash(spot_id, OWNERSHIP_ITEM)


## Documentos perdidos fuera de la notaría (tirados, requisados en un registro, hallados en un
## alijo): la empresa los recupera y vuelven a la caja del despacho (la combinación sigue
## valiendo). Idempotente: el nodo la llama tras item_disposed y process_day cada jornada.
static func check_documents_lost() -> bool:
	if _is_over() or not bool(PlayerState.get_flag(F_DOCS_TAKEN, false)) or has_documents() \
			or is_verification_pending():
		return false
	PlayerState.set_flag(F_DOCS_TAKEN, false)
	PlayerState.set_flag(F_DOCS_LOST_DAY, GameClock.get_day())
	_note(NOTE_DOCUMENTS_LOST, [])
	return true


# ═══ Fase 5: la notaría ═══════════════════════════════════════════════

## Reputación exigida para falsificar (rebajada si se ocupa u ocupó el puesto verosímil).
static func forgery_reputation_required() -> float:
	var required: float = _bal_f(B_FORGE_REPUTATION)
	if has_held(_bal_s(B_CREDIBLE_FORGER)):
		required -= _bal_f(B_FORGE_DISCOUNT)
	return required


## Autorización falsificada con la estampa del escritorio (delito "forgery").
static func forge_authorization() -> Dictionary:
	var blocked: String = _forge_block()
	if not blocked.is_empty():
		return _fail(blocked)
	PlayerState.add_item(FORGED_ITEM)
	var room: String = PlayerState.get_room()
	EventBus.crime_committed.emit(CRIME_FORGERY, room, {D_DOCUMENT: FORGED_ITEM})
	var record: String = _latest_forgery_record(room)
	if not record.is_empty():
		var records: Array = _flag_array(F_FORGED_RECORDS)
		records.append(record)
		PlayerState.set_flag(F_FORGED_RECORDS, records)
	_note(NOTE_FORGED, [])
	return _ok({K_RECORD: record})


## Notario de la plantilla (rol final.rol_notario) en activo, antes el que está en su sala;
## "" si no queda ninguno.
static func get_notary_id() -> String:
	var role: String = _bal_s(B_NOTARY_ROLE)
	var found: String = ""
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.get_role(npc.id) != role:
			continue
		if _npc_in(npc.id, _bal_s(B_NOTARY_ROOM)):
			return npc.id
		if found.is_empty():
			found = npc.id
	return found


## El notario está en la notaría (sin él no hay formalización: "notary_absent").
static func is_notary_present() -> bool:
	var notary: String = get_notary_id()
	return not notary.is_empty() and _npc_in(notary, _bal_s(B_NOTARY_ROOM))


## Plazo de comprobación: verification_days de la mesa de la notaría (o final.notaria).
static func get_verification_days() -> int:
	var room: RoomData = Database.get_room(_bal_s(B_NOTARY_ROOM))
	if room != null:
		for entry: Dictionary in room.interactables:
			if str(entry.get("type", "")) == NOTARY_DESK_TYPE and entry.has(VERIFICATION_DAYS_KEY):
				return int(entry[VERIFICATION_DAYS_KEY])
	return _bal_i(B_NOTARY_DAYS)


## Sin tirar: "signed" | "verification" | "uncertain" (dependerá de la perspicacia del notario).
static func preview_notary_decision() -> String:
	if Security.get_effective_suspicion() >= _bal_f(B_NOTARY_SUSPICION):
		return NOTARY_VERIFY
	if PlayerState.get_reputation() >= _bal_f(B_NOTARY_REPUTATION) \
			or NPCDirector.get_debt(get_notary_id()) > 0:
		return NOTARY_SIGNED
	return DECISION_UNCERTAIN


## Formalización: firma (y fase 6 en el acto) o abre el plazo de comprobación.
static func request_notarisation() -> Dictionary:
	var blocked: String = _notary_block()
	if not blocked.is_empty():
		return _fail(blocked)
	var title: String = TITLE_CHAIR if _holds_chair() else TITLE_FORGED
	var notary: String = get_notary_id()
	if _notary_verifies(notary):
		return _open_verification(title, notary)
	_note(NOTE_NOTARISED, [])
	_resolve_ownership(title)
	return _ok({K_OUTCOME: NOTARY_SIGNED, K_TITLE: title})


static func is_verification_pending() -> bool:
	return not get_verification().is_empty()


## {start_day, end_day, title, notary, record_id, bonus_cases} o {}.
static func get_verification() -> Dictionary:
	var raw: Variant = PlayerState.get_flag(F_VERIFICATION, {})
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var v: Dictionary = (raw as Dictionary).duplicate(true)
	v[V_START] = int(v.get(V_START, NO_DAY))
	v[V_END] = int(v.get(V_END, NO_DAY))
	return v


static func get_verification_days_left() -> int:
	var v: Dictionary = get_verification()
	return maxi(int(v.get(V_END, 0)) - GameClock.get_day(), 0) if not v.is_empty() else 0


## Máxima vulnerabilidad (§11.8): mientras el notario comprueba.
static func is_player_max_vulnerable() -> bool:
	return is_verification_pending()


# ═══ Fase 6 y calendario ══════════════════════════════════════════════

## Cambio de jornada (el nodo lo llama; idempotente por jornada): investigación de la caja
## forzada y plazo notarial.
static func process_day(day: int) -> void:
	if _is_over() or day <= _flag_int(F_LAST_DAY, NO_DAY):
		return
	PlayerState.set_flag(F_LAST_DAY, day)
	_open_safe_investigation(day)
	_tick_verification(day)
	check_documents_lost()


## Cierre de trimestre (idempotente): THE FIGUREHEAD tras figurehead_term_quarters trimestres
## completos en el cargo sin notariar.
static func process_quarter(quarter: int) -> void:
	if _is_over() or not _holds_chair() or quarter <= _flag_int(F_LAST_QUARTER, NO_DAY):
		return
	PlayerState.set_flag(F_LAST_QUARTER, quarter)
	var first_day: int = (quarter - 1) * _bal_i(B_DAYS_QUARTER) + 1
	if _flag_int(F_CEO_SINCE, GameClock.get_day()) > first_day:
		return
	var count: int = _flag_int(F_CEO_QUARTERS) + 1
	PlayerState.set_flag(F_CEO_QUARTERS, count)
	if count < int(Database.get_raw(ENDINGS_FILE).get(E_FIGUREHEAD_TERM, count + 1)):
		return
	EventBus.game_over.emit(CAUSE_FIGUREHEAD, Tracking.evaluate_ending_for_cause(CAUSE_FIGUREHEAD),
			Tracking.get_snapshot_for_cause(CAUSE_FIGUREHEAD))


static func get_figurehead_quarters() -> int:
	return _flag_int(F_CEO_QUARTERS)


# ═══ Personajes: Voss y Preston ═══════════════════════════════════════

## ally | hostile | neutral (Preston Vaile III, §8.3).
static func get_preston_stance() -> String:
	if not NPCDirector.is_active(PRESTON_ID):
		return STANCE_NEUTRAL
	if bool(PlayerState.get_flag(F_PRESTON_HOSTILE, false)) \
			or PlayerState.get_rank() >= _rank_of(_bal_s(B_RIVAL_OCC)):
		return STANCE_HOSTILE
	return STANCE_ALLY if get_office_holder() == VOSS_ID else STANCE_HOSTILE


static func stance_key(stance: String) -> String:
	return STANCE_KEY_FORMAT % stance.to_upper()


## Gancho Aurora/utilidad: el personaje compite abiertamente con el jugador por la silla.
static func is_hostile_rival(npc_id: String) -> bool:
	return npc_id == PRESTON_ID and get_preston_stance() == STANCE_HOSTILE


## Voss cree a sus intermediarios: uno con acceso y dispuesto levanta su vigilancia.
static func reassure_voss_via(npc_id: String) -> Dictionary:
	var watchers: Array[String] = NPCDirector.get_surveillance_watchers()
	if watchers.is_empty():
		return _fail(R_NOT_WATCHED)
	if not _reaches_voss(npc_id):
		return _fail(R_NO_ACCESS)
	if not _is_willing(npc_id):
		return _fail(R_UNWILLING)
	if NPCDirector.get_debt(npc_id) > 0:
		NPCDirector.add_debt(npc_id, -mini(_bal_i(B_VOSS_DEBT), NPCDirector.get_debt(npc_id)))
	for watcher: String in watchers:
		NPCDirector.end_personal_surveillance(watcher)
	_note(NOTE_VOSS_REASSURED, [_npc_name(npc_id), _npc_name(watchers[0])])
	return _ok({})


# ═══ Interno: revelación, silla y Preston ═════════════════════════════

## Revela (una vez, con nota) si el rango ya lo permite. Devuelve is_objective_revealed().
static func _ensure_revealed() -> bool:
	if bool(PlayerState.get_flag(F_REVEALED, false)):
		return true
	if PlayerState.get_rank() < get_revelation_rank():
		return false
	PlayerState.set_flag(F_REVEALED, true)
	PlayerState.set_flag(F_REVEALED_DAY, GameClock.get_day())
	_note(NOTE_REVEALED, [])
	return true


static func _track_chair(occupation_id: String) -> void:
	if occupation_id != _bal_s(B_CHAIR):
		PlayerState.set_flag(F_CEO_SINCE, null)
		PlayerState.set_flag(F_CEO_QUARTERS, null)
	elif not PlayerState.has_flag(F_CEO_SINCE):
		PlayerState.set_flag(F_CEO_SINCE, GameClock.get_day())
		PlayerState.set_flag(F_CEO_QUARTERS, 0)


static func _check_preston() -> void:
	if bool(PlayerState.get_flag(F_PRESTON_HOSTILE, false)) \
			or PlayerState.get_rank() < _rank_of(_bal_s(B_RIVAL_OCC)):
		return
	PlayerState.set_flag(F_PRESTON_HOSTILE, true)
	if NPCDirector.is_active(PRESTON_ID):
		NPCDirector.add_grievance(PRESTON_ID, GRIEVANCE_RIVAL, _bal_i(B_PRESTON_SEVERITY))
		_note(NOTE_PRESTON_HOSTILE, [_npc_name(PRESTON_ID)])


static func _holds_chair() -> bool:
	return PlayerState.get_occupation_id() == _bal_s(B_CHAIR)


## Fin de partida ya declarado (Tracking registra la causa, también la notaría).
static func _is_over() -> bool:
	return not Tracking.get_terminal_cause().is_empty()


# ═══ Interno: vías de la combinación ══════════════════════════════════

static func _pearl_block(method: String) -> String:
	if _is_over():
		return R_OVER
	if not _ensure_revealed():
		return R_HIDDEN
	if not PEARL_METHODS.has(method):
		return R_INVALID
	if not NPCDirector.is_active(PEARL_ID):
		return R_UNAVAILABLE
	return R_ALREADY_KNOWN if knows_combination() else ""


## "" = accede; si no, el motivo del fracaso.
static func _pearl_refusal(method: String) -> String:
	match method:
		METHOD_BLACKMAIL:
			return "" if knows_pearl_secret() and not is_pearl_secret_covered() else R_NO_MATERIAL
		METHOD_FAVOUR:
			return "" if _largest_favour(PEARL_ID) >= _bal_i(B_PEARL_FAVOUR) \
					else R_FAVOUR_TOO_SMALL
	return R_UNBRIBABLE


## Pearl informa al ocupante del despacho: denuncia al superior (una sola mientras él ya vigila
## por su palabra) y vigilancia personal del jugador (cada fracaso renueva el plazo).
static func _pearl_informs_voss() -> void:
	PlayerState.set_flag(F_PEARL_FAILED, GameClock.get_day())
	var watcher: String = get_office_holder()
	if not _watching_on_pearls_word(watcher):
		var room: String = NPCDirector.get_current_location(PEARL_ID)
		NPCDirector.report_player_to_superior(PEARL_ID,
				room if not room.is_empty() else _bal_s(B_SECRETARIAT), SURVEILLANCE_REASON)
	if not watcher.is_empty():
		NPCDirector.begin_personal_surveillance(watcher, _bal_i(B_PEARL_DAYS), SURVEILLANCE_REASON)
	_note(NOTE_PEARL_INFORMED, [_npc_name(watcher if not watcher.is_empty() else VOSS_ID)])


static func _watching_on_pearls_word(watcher: String) -> bool:
	return not watcher.is_empty() and str(NPCDirector.get_personal_surveillance(watcher).get(
			NPCDirectorSystem.SV_REASON, "")) == SURVEILLANCE_REASON


static func _pearl_favour_block(kind: String) -> String:
	if _is_over():
		return R_OVER
	if not _ensure_revealed():
		return R_HIDDEN
	var spec: Dictionary = _favour_spec(kind)
	if spec.is_empty():
		return R_INVALID
	if not NPCDirector.is_active(PEARL_ID):
		return R_UNAVAILABLE
	if knows_combination():
		return R_ALREADY_KNOWN
	if is_pearl_secret_covered():
		return R_ALREADY_DONE
	if not knows_pearl_secret():
		return R_NO_SECRET
	var occupation: String = str(spec.get(FV_OCCUPATION, ""))
	if not occupation.is_empty() and PlayerState.get_occupation_id() != occupation:
		return R_NO_AUTHORITY
	return "" if _player_in(str(spec.get(FV_ROOM, ""))) else R_WRONG_ROOM


static func _favour_spec(kind: String) -> Dictionary:
	if kind.is_empty() or kind.begins_with(COMMENT_PREFIX):
		return {}
	return _dict(_bal_dict(B_PEARL_FAVOURS).get(kind, {}))


static func _learn_combination(source: String, note_key: String) -> void:
	PlayerState.set_flag(F_COMBINATION, source)
	_note(note_key, [])


static func _largest_favour(npc_id: String) -> int:
	var best: int = 0
	for entry: Variant in NPCDirector.get_ledger(npc_id).get(LEDGER_FAVOURS, []):
		if entry is Dictionary:
			best = maxi(best, int((entry as Dictionary).get(LEDGER_MAGNITUDE, 0)))
	return best


static func _reset_files_progress() -> void:
	if PlayerState.has_flag(F_FILES_MINUTES):
		PlayerState.set_flag(F_FILES_MINUTES, null)
		PlayerState.set_flag(F_FILES_DAY, null)


static func _office_block() -> String:
	if _is_over():
		return R_OVER
	if not _ensure_revealed():
		return R_HIDDEN
	return "" if _player_in(_bal_s(B_OFFICE)) else R_NOT_IN_OFFICE


## Quien ve al jugador en el despacho: alguien dentro, o Pearl que se asoma (tirada por minuto).
static func _office_witness(minutes: int) -> String:
	var inside: Array[NPCRuntime] = NPCDirector.get_npcs_in_room(_bal_s(B_OFFICE))
	if not inside.is_empty():
		return inside[0].id
	if not _npc_in(PEARL_ID, _bal_s(B_SECRETARIAT)):
		return ""
	var chance: float = 1.0 - pow(1.0 - _bal_f(B_FILES_PEARL_CHANCE), float(maxi(minutes, 0)))
	if _roll() >= chance:
		return ""
	EventBus.player_seen_partially.emit(PEARL_ID, _bal_f(B_FILES_PEARL_CERTAINTY), _bal_s(B_OFFICE))
	return PEARL_ID


# ═══ Interno: ventana y accesos ═══════════════════════════════════════

static func _holder_room_at(holder: String, plan: Array, minute: int, today: bool) -> String:
	if today:
		return NPCDirector.get_agenda_location_at(holder,
				floori(float(minute) / MINUTES_PER_HOUR), minute % MINUTES_PER_HOUR)
	var iv: Dictionary = NPCRoutinePlanner.pick(plan, minute, true)
	if iv.is_empty():
		var npc: NPCRuntime = NPCDirector.get_npc(holder)
		return npc.home_room if npc != null else ""
	return str(iv.get(W_ROOM, ""))


## Muestras consecutivas fuera del despacho → ventanas (se descartan las de menos de minutos_minimos).
static func _windows_from(rooms: Array[String], hours: Vector2i, step: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var office: String = _bal_s(B_OFFICE)
	var begin: int = NO_DAY
	for i: int in rooms.size() + 1:
		var away: bool = i < rooms.size() and Database.get_room_base_id(rooms[i]) != office
		if away and begin < 0:
			begin = i
		elif not away and begin >= 0:
			var from: int = hours.x + begin * step
			var to: int = mini(hours.x + i * step, hours.y)
			if to - from >= _bal_i(B_WINDOW_MIN):
				out.append({W_START: from, W_END: to, W_ROOM: rooms[begin]})
			begin = NO_DAY
	return out


static func _meeting_block(band: String, via_npc_id: String) -> String:
	if _is_over():
		return R_OVER
	if not _ensure_revealed():
		return R_HIDDEN
	if not _bal_array(B_MEETING_BANDS).has(band):
		return R_BAD_BAND
	if int(_band_window(band)[W_END]) <= floori(GameClock.get_day_minutes()):
		return R_BAND_OVER
	if get_office_holder().is_empty():
		return R_NO_TARGET
	if _meetings_today() >= _bal_i(B_MEETING_MAX):
		return R_ALREADY_TODAY
	var allowed: bool = has_held(_bal_s(B_COORDINATOR)) if via_npc_id.is_empty() \
			else _is_meeting_ally(via_npc_id)
	return "" if allowed else R_NO_AUTHORITY


static func _meetings_today() -> int:
	var count: int = 0
	for entry: Variant in _flag_array(F_MEETINGS):
		if entry is Dictionary and int((entry as Dictionary).get(M_DAY, NO_DAY)) == GameClock.get_day():
			count += 1
	return count


## Aliado que convoca: el titular de meeting_coordinator con afecto o deuda, o Preston aliado.
static func _is_meeting_ally(npc_id: String) -> bool:
	if not NPCDirector.is_active(npc_id):
		return false
	if npc_id == PRESTON_ID and get_preston_stance() == STANCE_ALLY:
		return true
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.occupation_id == _bal_s(B_COORDINATOR) \
			and (NPCDirector.get_affection(npc_id) >= _bal_i(B_MEETING_AFFECTION) \
			or NPCDirector.get_debt(npc_id) > 0)


## {start, end} en minutos de la franja (hasta el inicio de la siguiente).
static func _band_window(band: String) -> Dictionary:
	var order: Array[String] = GameClock.get_band_order()
	var start: int = GameClock.get_band_start_hour(band) * MINUTES_PER_HOUR
	var index: int = order.find(band)
	var next: String = order[(index + 1) % order.size()] if index >= 0 else band
	return {W_START: start, W_END: GameClock.get_band_start_hour(next) * MINUTES_PER_HOUR}


static func _route_spec(route: String) -> Dictionary:
	if route.is_empty() or route.begins_with(COMMENT_PREFIX):
		return {}
	return _dict(_bal_dict(B_ACCESSES).get(route, {}))


## Pearl en su mesa ve pasar a quien no tiene acreditación del despacho (sin nodo que la simule).
static func _pearl_sees_entry() -> bool:
	if not _npc_in(PEARL_ID, _bal_s(B_SECRETARIAT)) or NPCDirector.is_world_located(PEARL_ID):
		return false
	var office: RoomData = Database.get_room(_bal_s(B_OFFICE))
	return office != null and PlayerState.get_clearance() < office.clearance_required


# ═══ Interno: caja y documentos ═══════════════════════════════════════

static func _safe_block() -> String:
	var blocked: String = _office_block()
	if not blocked.is_empty():
		return blocked
	if bool(PlayerState.get_flag(F_DOCS_TAKEN, false)) and not check_documents_lost():
		return R_ALREADY_TAKEN
	if not NPCDirector.get_npcs_in_room(_bal_s(B_OFFICE)).is_empty():
		return R_OCCUPIED
	return R_INVENTORY_FULL if PlayerState.get_free_slots() <= 0 else ""


static func _take_documents(route: String) -> Dictionary:
	if not PlayerState.add_item(OWNERSHIP_ITEM):
		return _fail(R_INVENTORY_FULL)
	PlayerState.set_flag(F_DOCS_TAKEN, true)
	PlayerState.set_flag(F_DOCS_DAY, GameClock.get_day())
	PlayerState.set_flag(F_DOCS_ROUTE, route)
	EventBus.ownership_documents_obtained.emit()
	_note(NOTE_DOCUMENTS, [])
	return _ok({K_ROUTE: route})


## Jornada siguiente a forzar la caja: investigación segura en el despacho (exenta de respiro).
static func _open_safe_investigation(day: int) -> void:
	var forced_day: int = _flag_int(F_SAFE_FORCED_DAY, NO_DAY)
	if forced_day < 0 or day <= forced_day:
		return
	var case_id: String = Security.report_incident(INCIDENT_SAFE, _bal_i(B_PHYS_SEVERITY),
			_bal_s(B_OFFICE), true, {I_ALWAYS_OPENS: true, I_DAY: forced_day,
			I_HOUR: _flag_int(F_SAFE_FORCED_HOUR, NO_DAY), I_FROM_DAY: forced_day})
	if not case_id.is_empty():
		Security.register_motive(case_id, PLAYER_ID)  # sospechoso por móvil; el acceso lo calcula Security
	PlayerState.set_flag(F_SAFE_CASE, case_id)
	PlayerState.set_flag(F_SAFE_FORCED_DAY, null)


# ═══ Interno: notaría y resolución ════════════════════════════════════

static func _forge_block() -> String:
	if _is_over():
		return R_OVER
	if not _ensure_revealed():
		return R_HIDDEN
	if not PlayerState.has_item(STAMP_ITEM):
		return R_NO_STAMP
	if PlayerState.get_reputation() < forgery_reputation_required():
		return R_LOW_REPUTATION
	if PlayerState.get_free_slots() <= 0 and not PlayerState.is_carrying(FORGED_ITEM):
		return R_INVENTORY_FULL
	return ""


## Registro neutro "stamped_document:forgery" que BeliefNet acaba de crear en esa sala.
static func _latest_forgery_record(room: String) -> String:
	var fact: String = BeliefNetSystem.make_fact(BeliefNetSystem.RECORD_STAMPED_DOCUMENT,
			CRIME_FORGERY)
	var known: Array = _flag_array(F_FORGED_RECORDS)
	var found: String = ""
	for record: Belief in BeliefNet.get_records_about(PLAYER_ID):
		if record.fact == fact and record.location == room and not known.has(record.id):
			found = record.id
	return found


static func _notary_block() -> String:
	if _is_over():
		return R_OVER
	if is_verification_pending():
		return R_PENDING
	if not _ensure_revealed():
		return R_HIDDEN
	if not _player_in(_bal_s(B_NOTARY_ROOM)):
		return R_NOT_AT_NOTARY
	if not PlayerState.is_carrying(OWNERSHIP_ITEM):
		return R_NO_DOCUMENTS
	if not _holds_chair() and not PlayerState.is_carrying(FORGED_ITEM):
		return R_NO_TITLE
	if get_notary_id().is_empty():
		return R_NO_NOTARY
	return "" if is_notary_present() else R_NOTARY_ABSENT


## Sospecha alta → comprueba; reputación alta o deuda → firma; si no, su perspicacia decide.
static func _notary_verifies(notary: String) -> bool:
	var decision: String = preview_notary_decision()
	if decision != DECISION_UNCERTAIN:
		return decision == NOTARY_VERIFY
	var chance: float = float(NPCDirector.get_trait(notary, TRAIT_PERCEPTION)) / PERCENT \
			* _bal_f(B_NOTARY_TRAIT)
	return _roll() < chance


static func _open_verification(title: String, notary: String) -> Dictionary:
	PlayerState.set_flag(F_DOCS_LODGED, true)
	PlayerState.remove_item(OWNERSHIP_ITEM)
	var record: String = ""
	if title == TITLE_FORGED:
		PlayerState.remove_item(FORGED_ITEM)
		var records: Array = _flag_array(F_FORGED_RECORDS)
		record = str(records.back()) if not records.is_empty() else ""
	var days: int = get_verification_days()
	var today: int = GameClock.get_day()
	PlayerState.set_flag(F_VERIFICATION, {V_START: today, V_END: today + days, V_TITLE: title,
			V_NOTARY: notary, V_RECORD: record, V_CASES: []})
	_note(NOTE_VERIFICATION, [days])
	_apply_vulnerability()
	return _ok({K_OUTCOME: NOTARY_VERIFY, K_TITLE: title, K_DAYS: days})


## Plazo de comprobación. Al vencer decide el título de ESE momento: la silla firma (y supera a
## una autorización falsa, que ya no se examina); si no, la falsa se destapa; si no, cargo perdido.
static func _tick_verification(day: int) -> void:
	var v: Dictionary = get_verification()
	if v.is_empty():
		return
	if not NPCDirector.is_active(str(v.get(V_NOTARY, ""))):
		_cancel_verification(v)
		return
	if day < int(v[V_END]):
		_apply_vulnerability()
		return
	PlayerState.set_flag(F_VERIFICATION, null)
	if _holds_chair():
		_note(NOTE_NOTARISED, [])
		_resolve_ownership(TITLE_CHAIR)
	elif str(v.get(V_TITLE, "")) == TITLE_FORGED:
		PlayerState.set_flag(F_DOCS_LODGED, null)
		_expose_forgery(str(v.get(V_RECORD, "")))
	else:
		_return_documents(NOTE_TITLE_LOST)


## El notario que comprobaba dejó la plantilla: ni comprobación ni firma. Devuelve los papeles y
## la autorización (sin comprobar: no pasa a pesar).
static func _cancel_verification(v: Dictionary) -> void:
	PlayerState.set_flag(F_VERIFICATION, null)
	_return_documents(NOTE_NOTARY_GONE)
	if str(v.get(V_TITLE, "")) == TITLE_FORGED:
		PlayerState.add_item(FORGED_ITEM)


## Plazo abierto: una pieza file_annotation por caso activo contra el jugador (una vez por caso).
static func _apply_vulnerability() -> void:
	var v: Dictionary = get_verification()
	if v.is_empty():
		return
	var done: Array = (v.get(V_CASES, []) as Array).duplicate()
	for inv: Investigation in Security.get_active_investigations():
		if done.has(inv.id) or not (inv.suspects.has(PLAYER_ID)
				or Security.get_case_weight_against(PLAYER_ID, inv.id) > 0.0):
			continue
		Security.add_evidence(inv.id, InvestigationEngine.EV_FILE_NOTE, _bal_f(B_NOTARY_BONUS),
				PLAYER_ID)
		done.append(inv.id)
	v[V_CASES] = done
	PlayerState.set_flag(F_VERIFICATION, v)


## La comprobación destapa la autorización falsa: pieza de 5,0 contra el jugador y los
## documentos vuelven a la caja del despacho.
static func _expose_forgery(record_id: String) -> void:
	if not record_id.is_empty():
		BeliefNet.confirm_record(record_id)
	var case_id: String = Security.report_incident(INCIDENT_FORGED, _bal_i(B_NOTARY_SEVERITY),
			_bal_s(B_NOTARY_ROOM), true, {I_ALWAYS_OPENS: true, I_SUBJECT: PLAYER_ID,
			I_EVIDENCE: EV_FORGED, I_WEIGHT: _bal_f(B_FORGED_WEIGHT), I_RECORD: record_id,
			I_CULPRIT: true})
	PlayerState.set_flag(F_FORGERY_CASE, case_id)
	PlayerState.set_flag(F_DOCS_TAKEN, false)
	_note(NOTE_FORGERY_DETECTED, [])


## La notaría devuelve los papeles (cargo perdido o notario desaparecido): al inventario, o a la
## caja del despacho si no caben.
static func _return_documents(note_key: String) -> void:
	if not PlayerState.add_item(OWNERSHIP_ITEM):
		PlayerState.set_flag(F_DOCS_TAKEN, false)
	PlayerState.set_flag(F_DOCS_LODGED, null)
	_note(note_key, [])


## Fase 6: ownership_notarised y el final que decide Tracking (victoria también por game_over).
static func _resolve_ownership(title: String) -> void:
	PlayerState.set_flag(F_DOCS_LODGED, null)
	EventBus.ownership_notarised.emit()
	var snapshot: Dictionary = Tracking.get_snapshot_for_cause(CAUSE_NOTARISED).duplicate(true)
	snapshot[S_TITLE] = title
	snapshot[S_COMBINATION] = get_combination_source()
	EventBus.game_over.emit(CAUSE_NOTARISED, Tracking.evaluate_ending_for_cause(CAUSE_NOTARISED),
			snapshot)


# ═══ Interno: Voss ════════════════════════════════════════════════════

## Llega a Voss: escalón ≥ escalon_min_intermediario o un vínculo con él.
static func _reaches_voss(npc_id: String) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or npc_id == VOSS_ID or not NPCDirector.is_active(npc_id):
		return false
	return npc.tier >= _bal_i(B_VOSS_TIER) \
			or not SocialGraph.get_link_type(npc_id, VOSS_ID).is_empty() \
			or not SocialGraph.get_link_type(VOSS_ID, npc_id).is_empty()


static func _is_willing(npc_id: String) -> bool:
	return NPCDirector.get_affection(npc_id) >= _bal_i(B_VOSS_AFFECTION) \
			or NPCDirector.get_debt(npc_id) > 0 \
			or NPCDirector.get_fear(npc_id) >= _bal_i(B_VOSS_FEAR)


# ═══ Utilidades ═══════════════════════════════════════════════════════

## Tirada sembrada con la semilla de partida y un contador guardado (reproducible tras cargar).
static func _roll() -> float:
	if roll_source.is_valid():
		return float(roll_source.call())
	var count: int = _flag_int(F_ROLLS)
	PlayerState.set_flag(F_ROLLS, count + 1)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (SEED_FORMAT % [GameClock.get_run_seed(), RNG_SALT, count]).hash()
	return rng.randf()


static func _note(text_key: String, args: Array) -> void:
	EventBus.notebook_entry_added.emit(_bal_s(B_NOTE_CATEGORY), text_key, args)


static func _ok(extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {K_OK: true, K_REASON: ""}
	out.merge(extra, true)
	return out


static func _fail(reason: String, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {K_OK: false, K_REASON: reason}
	out.merge(extra, true)
	return out


static func _player_in(room_id: String) -> bool:
	return Database.get_room_base_id(PlayerState.get_room()) == room_id


static func _npc_in(npc_id: String, room_id: String) -> bool:
	return NPCDirector.is_active(npc_id) \
			and Database.get_room_base_id(NPCDirector.get_current_location(npc_id)) == room_id


static func _npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.name if npc != null else npc_id


## Rango de una ocupación; si no existe, uno inalcanzable (el del cargo + 1).
static func _rank_of(occupation_id: String) -> int:
	var occupation: OccupationData = Database.get_occupation(occupation_id)
	if occupation != null:
		return occupation.rank
	var chair: OccupationData = Database.get_occupation(_bal_s(B_CHAIR))
	return (chair.rank if chair != null else 0) + 1


static func _flag_int(key: String, default_value: int = 0) -> int:
	return int(PlayerState.get_flag(key, default_value))


static func _flag_array(key: String) -> Array:
	var raw: Variant = PlayerState.get_flag(key, [])
	return (raw as Array).duplicate(true) if raw is Array else []


static func _bal_s(path: String) -> String:
	return str(Database.get_balance(path))


static func _bal_i(path: String) -> int:
	return Database.get_balance_int(path)


static func _bal_f(path: String) -> float:
	return Database.get_balance_float(path)


static func _bal_array(path: String) -> Array:
	var raw: Variant = Database.get_balance(path)
	return raw if raw is Array else []


static func _bal_dict(path: String) -> Dictionary:
	return _dict(Database.get_balance(path))


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
