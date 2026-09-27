# belief_net.gd — Almacena y gestiona todas las creencias del mundo, los registros y la sospecha.
# PROPIETARIO DE: creencias y registros (§7.2, §7.6), su decaimiento, registros diferidos, la clasificación de registros neutros/incriminatorios, las marcas de delito por sala y la sospecha.
# ESCUCHA: player_seen_partially, player_caught_redhanded, camera_recorded_player, card_reader_logged, npc_reported_player, crime_committed, body_discovered, npc_removed, rumor_spread, evidence_added, reputation_changed, grievance_added, merit_gained, seat_filled, seat_vacated, occupation_changed, news_published, news_buried, day_advanced, run_loaded.
class_name BeliefNetSystem
extends Node

## DECISIONES (contrato para el resto de sistemas; PASO 13-14, manual §7.2, §7.6, §7.10, §12.4):
## - Hecho (`fact`): "<tipo>" o "<tipo>:<detalle>" ("caught_redhanded:theft_small",
##   "footage:cam_p03_1"). Su peso en la sospecha: creencias.peso_tipo[<tipo>]; un tipo ausente
##   usa "default" = 0 (NEUTRO: no pesa ni es negativo) y se avisa una vez.
## - Sujeto del jugador: PLAYER_ID. Los registros los sostiene RECORD_HOLDER ("archive").
## - Sospecha = clamp(Σ certeza × credibilidad_portador × peso × 100 / divisor, 0, 100) (§7.2,
##   sin factor de origen). credibilidad = NPCDirector.get_npc_reputation × mod_credibilidad; los
##   portadores que no son personajes (archive, "", ids sin NPCRuntime) usan la reputación por
##   defecto (50). Una reputación real de 0 da credibilidad 0. peso = weight propio (denuncias,
##   registros) o peso_tipo del hecho.
## - REGISTROS NEUTROS: documentan sin incriminar; su weight (§12.4) vale para las investigaciones
##   pero en la sospecha pesan × creencias.factor_registro_neutro (0). Son: lecturas RUTINARIAS de
##   cámaras y lectores del jugador (salvo sala vetada a su acreditación, franja sospechosa o un
##   delito visible en la misma sala a ±ventana horas), documentos falsificados SIN VERIFICAR
##   (§5.3: se verifican cuando una investigación los usa como pieza, evidence_added, o con
##   confirm_record) y anotaciones de expediente (§12.2). create_record() nunca crea neutros.
## - Cada sensor (cámara/lector) cuenta UNA vez por jornada en la sospecha (la mayor lectura);
##   los registros siguen siendo uno por grabación para ir a la par con Security.
## - npc_reported_player: report_type de creencias.tipos_denuncia_con_peso_evidencia
##   (NPCDirector: "direct_witness"/"partial_witness", weight = peso §12.4 × factor del
##   superior) → puntos = weight × puntos_por_peso_evidencia_denuncia (4,0 → +20, 2,0 → +10);
##   cualquier otro (CaughtHandler/Blackmail: security, superior, anonymous_tip) → puntos de
##   creencias.puntos_denuncia (weight ignorado). Los puntos se convierten en weight de la
##   creencia "reported:<tipo>" (weight_for_suspicion_points: exactos con credibilidad por
##   defecto). "superior" deja además una anotación en expediente (stamped_document neutro).
## - Fusión: igual (holder, subject, fact, location) → una creencia. Directa refuerza
##   (restablece la certeza de referencia y suma); rumor solo eleva; el weight queda en el mayor.
##   Todo cambio de certeza sin olvido emite belief_decayed(id, nueva_certeza) (= «certeza
##   cambiada»: decaimiento, refuerzo o fusión).
## - Rumores: rumor_spread según el protocolo de social_graph.gd (plantados por el jugador vía
##   get_injected_rumour; resto transfer_belief con get_transfer_factor); los hechos enterrados
##   (is_fact_killed) no prenden y sus rumores se olvidan en el decaimiento diario.
## - Decaimiento diario: creencias ordinarias − decaimiento_diario × dificultad
##   ("decaimiento_sospecha"); las que pesan en la sospecha del jugador × (1 + mod × reputación).
## - Cuerpo hallado: registro con sujeto "unknown" (no nombra a nadie; la «sospecha máxima» de
##   §7.11/§12.3 es la alerta de Security y su marca del veredicto leve, no esta suma).
## - CAPA COMPARTIDA DE NOTICIAS (§7.11, PASO 35): la sospecha suma además el peso social vivo de
##   la prensa sobre el jugador y la compañía (NewsFeed.get_suspicion_contribution(), 0-100 ×
##   creencias.factor_peso_social_noticias puntos). No es una creencia: en get_suspicion_breakdown()
##   figura como una entrada sintética (belief_id NEWS_ENTRY_ID, holder NEWS_HOLDER). Así el mismo
##   news_published sube la sospecha y hunde la cotización, y news_buried baja las dos. Se recalcula
##   al oír news_published / news_buried y, por el decaimiento de NewsFeed (que escucha day_advanced
##   después de BeliefNet), también en diferido tras day_advanced.
## - Sin aleatoriedad: el sistema es determinista y no necesita RandomNumberGenerator.

const PLAYER_ID := "player"
const RECORD_HOLDER := "archive"
const UNKNOWN_SUBJECT := "unknown"
## Una cámara que graba al jugador disfrazado registra el uniforme, no la identidad (§5.3).
const DISGUISE_SUBJECT_PREFIX := "uniform:"
const FACT_SEPARATOR := ":"
const MERGE_KEY_SEPARATOR := "\u001f"
const BELIEF_ID_PREFIX := "belief_"
const RECORD_ID_PREFIX := "record_"
const LABEL_KEY_PREFIX := "BELIEF_FACT_"
const LABEL_KEY_UNKNOWN := "BELIEF_FACT_UNKNOWN"
const SOURCE_LABEL_KEY_PREFIX := "BELIEF_SOURCE_"
const SAVE_CONTEXT := "save/belief_net"
## Escala del medidor de sospecha (0–100, §7.2): rango del medidor, no un ajuste.
const SUSPICION_MAX := 100.0
const WEIGHT_DEFAULT_KEY := "default"
const PATH_SEPARATOR := "."
const NEUTRAL_MULTIPLIER := 1.0
const DIFFICULTY_DECAY_KEY := "decaimiento_sospecha"
const NO_HOUR := -1
# Entrada sintética de la prensa en el desglose (capa compartida §7.11).
const NEWS_ENTRY_ID := "news_coverage"
const NEWS_HOLDER := "press"
const NEWS_FACT := "news_coverage"
const NEWS_SOURCE := "news"

# Motivos de un registro neutro (get_neutral_reason).
const NEUTRAL_ROUTINE := "routine"
const NEUTRAL_UNVERIFIED := "unverified"
const NEUTRAL_ANNOTATION := "annotation"
const FILE_ANNOTATION_DETAIL := "file_annotation"

# Tipos de hecho de creencias ordinarias.
const FACT_SEEN_PARTIALLY := "seen_partially"
const FACT_CAUGHT_REDHANDED := "caught_redhanded"
const FACT_REPORTED := "reported"
const FACT_STEALS_IDEAS := "steals_ideas"
const FACT_HARD_WORKER := "hard_worker"
const FACT_COMPETENT := "competent"
## Bribery: "bribe_attempt:<refused|insulting|remembered|overheard|witnessed>".
const FACT_BRIBE_ATTEMPT := "bribe_attempt"
# Tipos de registro (§7.6) más el registro digital de chat (§7.7 chat legible por IT; Bribery).
const RECORD_BODY_FOUND := "body_found"
const RECORD_SIGNED_EXPULSION := "signed_expulsion"
const RECORD_FOOTAGE := "footage"
const RECORD_BOARD_MINUTES := "board_minutes"
const RECORD_ACCOUNTING_ENTRY := "accounting_entry"
const RECORD_CARD_LOG := "card_log"
const RECORD_STAMPED_DOCUMENT := "stamped_document"
const RECORD_CHAT_LOG := "chat_log"
const RECORD_TYPES: Array[String] = [
	RECORD_BODY_FOUND, RECORD_SIGNED_EXPULSION, RECORD_FOOTAGE, RECORD_BOARD_MINUTES,
	RECORD_ACCOUNTING_ENTRY, RECORD_CARD_LOG, RECORD_STAMPED_DOCUMENT, RECORD_CHAT_LOG,
]
const KNOWN_FACT_TYPES: Array[String] = [
	FACT_SEEN_PARTIALLY, FACT_CAUGHT_REDHANDED, FACT_REPORTED, FACT_STEALS_IDEAS,
	FACT_HARD_WORKER, FACT_COMPETENT, FACT_BRIBE_ATTEMPT, RECORD_BODY_FOUND,
	RECORD_SIGNED_EXPULSION, RECORD_FOOTAGE, RECORD_BOARD_MINUTES, RECORD_ACCOUNTING_ENTRY,
	RECORD_CARD_LOG, RECORD_STAMPED_DOCUMENT, RECORD_CHAT_LOG, NEWS_FACT,
]
# crime_committed que destruyen registros (sala de monitores; servidores: registros digitales).
const CRIME_FOOTAGE_DELETED := "footage_deleted"
const CRIME_RECORDS_DELETED := "records_deleted"
const DESTRUCTION_BY_CRIME: Dictionary = {
	CRIME_FOOTAGE_DELETED: [RECORD_FOOTAGE],
	CRIME_RECORDS_DELETED: [RECORD_CARD_LOG, RECORD_CHAT_LOG],
}
## §22 server_room: «el acceso queda registrado en el propio servidor».
const CRIMES_WITH_ACCESS_TRACE: Array[String] = [CRIME_RECORDS_DELETED]
const DETAIL_KEY_BY_RECORD: Dictionary = {
	RECORD_FOOTAGE: "camera_id", RECORD_CARD_LOG: "reader_id",
}

# Claves de crime_committed.details.
const D_RECORD_IDS := "record_ids"
const D_ROOM := "room_id"
const D_DAY := "day"
const D_HOUR := "hour"
const D_SUBJECT := "subject"
const D_METHOD := "method"
const D_FOOTAGE_ID := "footage_id"
const D_LEAVES_RECORD := "leaves_record"
const D_WEIGHT := "weight"
const D_VERIFIED := "verified"
# Claves de creencias.registros_por_delito.<delito>.
const S_RECORD_TYPE := "record_type"
const S_WEIGHT_KEY := "peso"
const S_DELAY := "retardo_dias"
const S_UNVERIFIED := "sin_verificar"
# Claves de un registro diferido.
const P_RECORD_TYPE := "record_type"
const P_SUBJECT := "subject"
const P_WEIGHT := "weight"
const P_LOCATION := "location"
const P_FACT := "fact"
const P_DUE_DAY := "due_day"
const P_UNVERIFIED := "unverified"
# Claves de SocialGraph.get_injected_rumour y de una pieza de Investigation.
const R_SUBJECT := "subject"
const R_FACT := "fact"
const R_CERTAINTY := "certainty"
const R_LOCATION := "location"
const E_RECORD_ID := "record_id"
# Marca de delito por sala.
const M_DAY := "day"
const M_HOUR := "hour"
# Guardado.
const K_BELIEFS := "beliefs"
const K_PENDING := "pending_records"
const K_NEXT_ID := "next_id"
const K_PLAYER_REP := "player_reputation"
const K_NEUTRAL := "neutral_records"
const K_LOG_HOURS := "log_hours"
const K_CRIME_MARKS := "crime_marks"
const K_WEIGHT := "weight"
const K_PEAK := "peak"
const K_DECAY_DAYS := "decay_days"
# Entradas de get_suspicion_breakdown.
const BK_ID := "belief_id"
const BK_HOLDER := "holder"
const BK_FACT := "fact"
const BK_CERTAINTY := "certainty"
const BK_CREDIBILITY := "credibility"
const BK_WEIGHT := "weight"
const BK_SOURCE := "source"
const BK_IS_RECORD := "is_record"
const BK_CONTRIBUTION := "contribution"

# Rutas de balance.json.
const B_CERTEZA_DIRECTA := "creencias.certeza_directa_completa"
const B_CERTEZA_PARCIAL := "creencias.certeza_parcial"
const B_CERTEZA_DENUNCIA := "creencias.certeza_denuncia"
const B_AMPLIFICACION_MAX := "creencias.amplificacion_rumor_max"
const B_DECAIMIENTO := "creencias.decaimiento_diario"
const B_UMBRAL_OLVIDO := "creencias.umbral_olvido"
const B_MOD_CREDIBILIDAD := "creencias.mod_credibilidad_por_reputacion"
const B_MOD_CERTEZA_INICIAL := "creencias.mod_certeza_inicial_por_reputacion_jugador"
const B_MOD_DECAIMIENTO_REP := "creencias.mod_decaimiento_por_reputacion_jugador"
const B_REP_DEFECTO := "creencias.reputacion_portador_por_defecto"
const B_PESO_TIPO := "creencias.peso_tipo"
const B_DIVISOR := "creencias.divisor_normalizacion"
const B_REGISTROS_POR_DELITO := "creencias.registros_por_delito"
const B_FACTOR_NEUTRO := "creencias.factor_registro_neutro"
const B_FRANJAS_INCRIMINATORIAS := "creencias.franjas_registro_incriminatorio"
const B_VENTANA_DELITO := "creencias.horas_ventana_delito_registro"
const B_DELITOS_SIN_RASTRO := "creencias.delitos_sin_rastro_visual"
const B_PUNTOS_DENUNCIA := "creencias.puntos_denuncia"
const B_TIPOS_DENUNCIA_EVIDENCIA := "creencias.tipos_denuncia_con_peso_evidencia"
const B_PUNTOS_POR_PESO := "creencias.puntos_por_peso_evidencia_denuncia"
const B_DENUNCIAS_ANOTACION := "creencias.denuncias_con_anotacion"
const B_PESO_ANOTACION := "creencias.peso_anotacion_expediente"
const B_CAUSAS_EXPULSION := "creencias.causas_expulsion_firmada"
const B_FACTOR_NOTICIAS := "creencias.factor_peso_social_noticias"
const B_PESOS_EVIDENCIA := "investigaciones.pesos_evidencia"
const W_GRABACION := "grabacion_camara"
const W_TARJETA := "registro_tarjeta"
const W_CUERPO := "cuerpo_hallado"

## id → Belief (orden de inserción = orden de creación).
var _beliefs: Dictionary[String, Belief] = {}
## id → certeza de referencia que restablece un refuerzo (la del nacimiento o último refuerzo).
var _peaks: Dictionary[String, float] = {}
## id → jornadas transcurridas desde el nacimiento o el último refuerzo (reloj de decaimiento).
var _decay_days: Dictionary[String, int] = {}
## Índices derivados (se reconstruyen en _store/_remove; no se guardan): ids con sujeto el jugador
## y clave de fusión (holder, subject, fact, location) → id de la creencia ordinaria.
var _player_ids: Dictionary[String, bool] = {}
var _by_merge_key: Dictionary[String, String] = {}
## Registros neutros: id → motivo (NEUTRAL_*).
var _neutral: Dictionary[String, String] = {}
## Lecturas de sensores (cámaras y lectores): id → hora de juego de la lectura.
var _log_hours: Dictionary[String, int] = {}
## Último delito visible por sala (id exacto: "corridors_low@3" no marca otras plantas):
## sala → {day, hour}.
var _crime_marks: Dictionary[String, Dictionary] = {}
## Registros que afloran con retardo: {record_type, subject, weight, location, fact, due_day,
## unverified}.
var _pending_records: Array[Dictionary] = []
var _next_id: int = 1
## Último valor publicado (PlayerState lo guarda en caché).
var _suspicion: float = 0.0
## Reputación del jugador, actualizada por reputation_changed (moduladores de §7.10).
var _player_reputation: float = 0.0
## Tipos de hecho sin peso_tipo ya avisados (no se guarda).
var _warned_types: Dictionary[String, bool] = {}
var _refresh_queued: bool = false


func _ready() -> void:
	EventBus.player_seen_partially.connect(_on_player_seen_partially)
	EventBus.player_caught_redhanded.connect(_on_player_caught_redhanded)
	EventBus.camera_recorded_player.connect(_on_camera_recorded_player)
	EventBus.card_reader_logged.connect(_on_card_reader_logged)
	EventBus.npc_reported_player.connect(_on_npc_reported_player)
	EventBus.crime_committed.connect(_on_crime_committed)
	EventBus.body_discovered.connect(_on_body_discovered)
	EventBus.npc_removed.connect(_on_npc_removed)
	EventBus.rumor_spread.connect(_on_rumor_spread)
	EventBus.evidence_added.connect(_on_evidence_added)
	EventBus.reputation_changed.connect(_on_reputation_changed)
	EventBus.news_published.connect(func(_id: String, _s: float, _sc: bool) -> void:
		_refresh_suspicion())
	EventBus.news_buried.connect(func(_id: String, _by: String) -> void: _refresh_suspicion())
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.run_loaded.connect(_on_run_loaded)
	_connect_credibility_signals()


## La credibilidad de los portadores sigue su reputación viva (escalón, mérito, agravios): estas
## señales la cambian. Recalcula diferido: NPCDirector actualiza el puesto del personaje en su
## propio manejador, que corre después del de BeliefNet.
func _connect_credibility_signals() -> void:
	EventBus.grievance_added.connect(func(_n: String, _t: String, _s: int) -> void:
		_queue_refresh())
	EventBus.merit_gained.connect(func(_s: String, _a: int) -> void: _queue_refresh())
	EventBus.seat_filled.connect(func(_o: String, _h: String) -> void: _queue_refresh())
	EventBus.seat_vacated.connect(func(_o: String, _h: String, _c: String) -> void:
		_queue_refresh())
	EventBus.occupation_changed.connect(func(_o: String, _n: String, _r: String) -> void:
		_queue_refresh())


func reset_for_new_run() -> void:
	var old_value: float = _suspicion
	_clear()
	_player_reputation = PlayerState.get_reputation()
	PlayerState._set_suspicion_from_beliefnet(_suspicion)
	if not is_equal_approx(old_value, _suspicion):
		EventBus.suspicion_changed.emit(old_value, _suspicion)


# ─── Creación ─────────────────────────────────────────────────

## Devuelve el id de la creencia (el de la existente si se fusiona) o "" si no es válida.
func create_belief(holder: String, subject: String, fact: String,
		certainty: float, source: String, location: String) -> String:
	if source == Belief.SOURCE_RECORD:
		var rec: Belief = _insert_record(holder, fact_type_of(fact), subject,
				get_fact_weight(fact), location, fact, _today())
		_refresh_suspicion()
		return rec.id
	return _create(holder, subject, fact, certainty, source, location, 0.0)


## Registro explícito de otro sistema: pesa en la sospecha con `weight` (o peso_tipo si es 0).
func create_record(record_type: String, subject: String,
		weight: float, location: String) -> String:
	var own: float = weight if weight > 0.0 else get_fact_weight(record_type)
	var rec: Belief = _insert_record(RECORD_HOLDER, record_type, subject, own, location,
			record_type, _today())
	_refresh_suspicion()
	return rec.id


# ─── Consulta ─────────────────────────────────────────────────

## EXTRA (SocialGraph.kill_rumour): creencias de origen rumor que afirman `fact` (un recorrido).
func count_rumours(fact: String) -> int:
	var count: int = 0
	for b: Belief in _beliefs.values():
		if b.source == Belief.SOURCE_RUMOR and b.fact == fact:
			count += 1
	return count


## Creencias ordinarias (no registros) sobre `subject`, en orden de creación.
func get_beliefs_about(subject: String) -> Array[Belief]:
	var out: Array[Belief] = []
	for b: Belief in _beliefs.values():
		if b.subject == subject and not b.is_record:
			out.append(b)
	return out


## Todo lo que sostiene `holder` (los registros los sostiene RECORD_HOLDER).
func get_beliefs_held_by(holder: String) -> Array[Belief]:
	var out: Array[Belief] = []
	for b: Belief in _beliefs.values():
		if b.holder == holder:
			out.append(b)
	return out


func get_belief(id: String) -> Belief:
	return _beliefs.get(id, null)


func get_records_about(subject: String) -> Array[Belief]:
	var out: Array[Belief] = []
	for b: Belief in _beliefs.values():
		if b.subject == subject and b.is_record:
			out.append(b)
	return out


## Creencias ordinarias sobre `subject` con certeza >= min_certainty (sin registros).
func count_credible_beliefs_about(subject: String, min_certainty: float) -> int:
	var count: int = 0
	for b: Belief in get_beliefs_about(subject):
		if b.certainty >= min_certainty:
			count += 1
	return count


## EXTRA: true si el registro existe y no pesa en la sospecha (ver DECISIONES).
func is_record_neutral(id: String) -> bool:
	return _neutral.has(id)


## EXTRA: motivo del registro neutro (NEUTRAL_ROUTINE | _UNVERIFIED | _ANNOTATION) o "".
func get_neutral_reason(id: String) -> String:
	return _neutral.get(id, "")


# ─── Modificación ─────────────────────────────────────────────

## Restablece la certeza de referencia, le suma `additional_certainty` y reinicia el reloj de
## decaimiento (emite belief_decayed con la nueva certeza). Un refuerzo negativo que la deja bajo
## el umbral de olvido la olvida.
func reinforce_belief(id: String, additional_certainty: float) -> void:
	var b: Belief = get_belief(id)
	if b == null or b.is_record:
		return
	_apply_reinforcement(b, additional_certainty)
	if _beliefs.has(id):
		EventBus.belief_decayed.emit(id, b.certainty)
	_refresh_suspicion()


func destroy_record(id: String, method: String) -> bool:
	var destroyed: bool = _destroy_record_silently(id, method)
	if destroyed:
		_refresh_suspicion()
	return destroyed


## Copia la creencia a `to_holder` como rumor con certeza = certeza_emisor × degradation.
## `degradation` es el MULTIPLICADOR de transmisión (0,75 = transmisión oral estándar; > 1
## amplifica), acotado a [0, amplificacion_rumor_max]. Devuelve el id de la creencia del receptor
## (la copia nueva, o la que ya tenía aunque este relato no la eleve) o "" si no prende (certeza
## bajo el umbral de olvido, receptor vacío o el propio portador).
func transfer_belief(id: String, to_holder: String, degradation: float) -> String:
	var src: Belief = get_belief(id)
	if src == null or to_holder.is_empty() or to_holder == src.holder:
		return ""
	var factor: float = clampf(degradation, 0.0, _bal_f(B_AMPLIFICACION_MAX))
	var certainty: float = minf(src.certainty * factor, Belief.MAX_CERTAINTY)
	if certainty < _bal_f(B_UMBRAL_OLVIDO):
		return ""
	return _create(to_holder, src.subject, src.fact, certainty, Belief.SOURCE_RUMOR,
			src.location, 0.0)


## EXTRA: olvida una creencia ordinaria (emite belief_forgotten). false si no existe o es registro.
func forget_belief(id: String) -> bool:
	var b: Belief = get_belief(id)
	if b == null or b.is_record:
		return false
	_forget(b)
	_refresh_suspicion()
	return true


## EXTRA: olvida las creencias de origen rumor con ese hecho exacto. Devuelve cuántas.
func forget_rumours(fact: String) -> int:
	var victims: Array[Belief] = []
	for b: Belief in _beliefs.values():
		if b.source == Belief.SOURCE_RUMOR and b.fact == fact:
			victims.append(b)
	for b: Belief in victims:
		_forget(b)
	if not victims.is_empty():
		_refresh_suspicion()
	return victims.size()


## EXTRA (manos: notaría, escena que verifica un documento o prueba una grabación): el registro
## neutro pasa a pesar en la sospecha. false si no existe o no era neutro.
func confirm_record(id: String) -> bool:
	if not _neutral.has(id):
		return false
	_neutral.erase(id)
	_refresh_suspicion()
	return true


# ─── Sospecha ─────────────────────────────────────────────────

func calculate_player_suspicion() -> float:
	var total: float = 0.0
	for entry: Dictionary in _contribution_entries():
		total += float(entry[BK_CONTRIBUTION])
	return clampf(total, 0.0, SUSPICION_MAX)


## EXTRA (§7.11): puntos de sospecha que aporta la prensa viva sobre el jugador y la compañía.
func get_news_contribution() -> float:
	return maxf(NewsFeed.get_suspicion_contribution(), 0.0) * _bal_f(B_FACTOR_NOTICIAS)


## Para el panel de depuración: [{belief_id, holder, fact, certainty, credibility, weight,
## contribution, source, is_record}] ordenado por contribución (en puntos de sospecha) descendente.
## La prensa (si pesa) es la entrada sintética NEWS_ENTRY_ID.
func get_suspicion_breakdown() -> Array[Dictionary]:
	var entries: Array[Dictionary] = _contribution_entries()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a[BK_CONTRIBUTION]) > float(b[BK_CONTRIBUTION]))
	return entries


## EXTRA: credibilidad de un portador = reputación × mod_credibilidad_por_reputacion. La
## reputación viene de NPCDirector.get_npc_reputation (BUILD_NOTES §13; 0 es una reputación real).
## Quien no es un personaje (RECORD_HOLDER, "", ids sin NPCRuntime) usa la de por defecto.
func get_credibility(holder: String) -> float:
	if _is_generic_holder(holder) or NPCDirector.get_npc(holder) == null:
		return get_default_credibility()
	return NPCDirector.get_npc_reputation(holder) * _bal_f(B_MOD_CREDIBILIDAD)


## EXTRA: credibilidad de un portador sin reputación propia (registros, portadores genéricos).
func get_default_credibility() -> float:
	return _bal_f(B_REP_DEFECTO) * _bal_f(B_MOD_CREDIBILIDAD)


## EXTRA: peso de una creencia directa de certeza `certainty` que, sostenida por un portador de
## credibilidad por defecto, aporta exactamente `points` puntos de sospecha (sin reducciones).
func weight_for_suspicion_points(points: float, certainty: float) -> float:
	var per_weight: float = certainty * get_default_credibility() * SUSPICION_MAX
	if per_weight <= 0.0:
		return 0.0
	return maxf(points, 0.0) * _bal_f(B_DIVISOR) / per_weight


## EXTRA: puntos de sospecha que representa una denuncia (ver DECISIONES).
func get_report_points(report_type: String, weight: float) -> float:
	if _bal_strings(B_TIPOS_DENUNCIA_EVIDENCIA).has(report_type):
		return maxf(weight, 0.0) * _bal_f(B_PUNTOS_POR_PESO)
	var path: String = B_PUNTOS_DENUNCIA + PATH_SEPARATOR + report_type
	if not Database.has_balance(path):
		path = B_PUNTOS_DENUNCIA + PATH_SEPARATOR + WEIGHT_DEFAULT_KEY
	return _bal_f(path)


## EXTRA: peso de un tipo de hecho en la sospecha (creencias.peso_tipo; "default" = neutro si
## falta, con un aviso por tipo).
func get_fact_weight(fact: String) -> float:
	var fact_type: String = fact_type_of(fact)
	var path: String = B_PESO_TIPO + PATH_SEPARATOR + fact_type
	if Database.has_balance(path):
		return _bal_f(path)
	if not _warned_types.has(fact_type):
		_warned_types[fact_type] = true
		push_warning("BeliefNet: fact type '%s' has no creencias.peso_tipo entry" % fact_type)
	return _bal_f(B_PESO_TIPO + PATH_SEPARATOR + WEIGHT_DEFAULT_KEY)


## EXTRA: peso con el que una creencia entra en la sospecha: su weight propio o el peso_tipo de su
## hecho; un registro neutro × creencias.factor_registro_neutro.
func get_suspicion_weight(b: Belief) -> float:
	return _weight_in_suspicion(b, _bal_f(B_FACTOR_NEUTRO))


## EXTRA: un hecho es negativo si pesa en la sospecha (SocialGraph: la rivalidad solo propaga
## hechos negativos; §7.10: solo las creencias negativas nacen reducidas y decaen antes).
func is_negative_fact(fact: String) -> bool:
	return get_fact_weight(fact) > 0.0


## EXTRA: true si la sala exige más acreditación que la del jugador y ninguna de sus etiquetas
## special_access la abre (criterio de la zona vetada del HUD). Sala desconocida → false.
func is_room_forbidden_for_player(room_id: String) -> bool:
	var room: RoomData = Database.get_room(room_id) if not room_id.is_empty() else null
	if room == null or PlayerState.get_clearance() >= room.clearance_required:
		return false
	var occupation: OccupationData = PlayerState.get_occupation()
	var tags: Array[String] = []
	if occupation != null:
		tags = occupation.special_access
	for tag: String in room.special_access:
		if tags.has(tag):
			return false
	return true


# ─── Mantenimiento ────────────────────────────────────────────

## Invocado por day_advanced. Los registros no decaen jamás (§7.6); los rumores de un hecho
## enterrado por SocialGraph.kill_rumour se olvidan.
func apply_daily_decay() -> void:
	var threshold: float = _bal_f(B_UMBRAL_OLVIDO)
	var rate: float = _bal_f(B_DECAIMIENTO) \
			* Database.get_difficulty_modifier(DIFFICULTY_DECAY_KEY)
	var player_rate: float = rate * _player_decay_multiplier()
	var forgotten: Array[Belief] = []
	for b: Belief in _beliefs.values():
		if b.is_record:
			continue
		if _is_killed_rumour(b):
			forgotten.append(b)
			continue
		var loss: float = player_rate if _is_suspicion_belief(b) else rate
		b.certainty = maxf(b.certainty - loss, Belief.MIN_CERTAINTY)
		_decay_days[b.id] = _decay_days.get(b.id, 0) + 1
		if b.certainty < threshold:
			forgotten.append(b)
		else:
			EventBus.belief_decayed.emit(b.id, b.certainty)
	for b: Belief in forgotten:
		_forget(b)
	_refresh_suspicion()


## EXTRA: jornadas desde el nacimiento o el último refuerzo (-1 si no existe).
func get_days_since_reinforced(id: String) -> int:
	return _decay_days.get(id, -1)


## EXTRA: registros diferidos pendientes de aflorar (copia).
func get_pending_records() -> Array[Dictionary]:
	return _pending_records.duplicate(true)


# ─── Utilidades de hechos (estáticas) ─────────────────────────

static func make_fact(fact_type: String, detail: String) -> String:
	if detail.is_empty():
		return fact_type
	return fact_type + FACT_SEPARATOR + detail


static func fact_type_of(fact: String) -> String:
	return fact.get_slice(FACT_SEPARATOR, 0)


static func fact_detail_of(fact: String) -> String:
	var cut: int = fact.find(FACT_SEPARATOR)
	return "" if cut < 0 else fact.substr(cut + FACT_SEPARATOR.length())


## Clave de texto del tipo de hecho para la interfaz (BELIEF_FACT_*).
static func fact_label_key(fact: String) -> String:
	var fact_type: String = fact_type_of(fact)
	if not KNOWN_FACT_TYPES.has(fact_type):
		return LABEL_KEY_UNKNOWN
	return LABEL_KEY_PREFIX + fact_type.to_upper()


## Clave de texto del origen para la interfaz (BELIEF_SOURCE_DIRECT | _RUMOR | _RECORD | _NEWS).
static func source_label_key(source: String) -> String:
	return SOURCE_LABEL_KEY_PREFIX + source.to_upper()


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	var entries: Array[Dictionary] = []
	for b: Belief in _beliefs.values():
		var entry: Dictionary = b.to_dict()
		entry[K_WEIGHT] = b.weight
		entry[K_PEAK] = _peaks.get(b.id, b.certainty)
		entry[K_DECAY_DAYS] = _decay_days.get(b.id, 0)
		entries.append(entry)
	return {
		K_BELIEFS: entries, K_PENDING: _pending_records.duplicate(true), K_NEXT_ID: _next_id,
		K_PLAYER_REP: _player_reputation, K_NEUTRAL: _neutral.duplicate(),
		K_LOG_HOURS: _log_hours.duplicate(), K_CRIME_MARKS: _crime_marks.duplicate(true),
	}


## La sospecha se recalcula (y se vuelve a calcular en run_loaded, cuando NPCDirector ya cargó
## las reputaciones de los portadores).
func load_state(data: Dictionary) -> void:
	var live: float = _suspicion
	_clear()
	_next_id = int(data.get(K_NEXT_ID, _next_id))
	_player_reputation = float(data.get(K_PLAYER_REP, PlayerState.get_reputation()))
	var entries: Variant = data.get(K_BELIEFS, [])
	if entries is Array:
		for i: int in (entries as Array).size():
			if entries[i] is Dictionary:
				_load_entry(entries[i], i)
	for pending: Variant in data.get(K_PENDING, []):
		if pending is Dictionary:
			_pending_records.append(_make_pending(pending))
	_load_record_meta(data)
	_suspicion = live
	_refresh_suspicion()


# ─── Reacciones a EventBus ────────────────────────────────────

func _on_player_seen_partially(npc_id: String, certainty: float, location: String) -> void:
	var c: float = certainty if certainty > 0.0 else _bal_f(B_CERTEZA_PARCIAL)
	create_belief(npc_id, PLAYER_ID, FACT_SEEN_PARTIALLY, c, Belief.SOURCE_DIRECT, location)


func _on_player_caught_redhanded(npc_id: String, crime_type: String, _witnesses: int) -> void:
	create_belief(npc_id, PLAYER_ID, make_fact(FACT_CAUGHT_REDHANDED, crime_type),
			_bal_f(B_CERTEZA_DIRECTA), Belief.SOURCE_DIRECT, _player_room())


func _on_camera_recorded_player(camera_id: String, room_id: String, day: int) -> void:
	var rec: Belief = _insert_record(RECORD_HOLDER, RECORD_FOOTAGE, _recorded_subject(),
			_evidence_weight(W_GRABACION), room_id, make_fact(RECORD_FOOTAGE, camera_id), day)
	_classify_sensor_log(rec, GameClock.get_hour())
	_refresh_suspicion()


## BeliefNet asume que card_reader_logged solo se emite por lecturas del jugador: con su tarjeta
## (card_owner = PLAYER_ID) o con una tarjeta ajena (el registro señala al titular, §5.3).
func _on_card_reader_logged(reader_id: String, card_owner: String, day: int, hour: int) -> void:
	var subject: String = PLAYER_ID if card_owner.is_empty() else card_owner
	var room: String = _player_room()
	var rec: Belief = _insert_record(RECORD_HOLDER, RECORD_CARD_LOG, subject,
			_evidence_weight(W_TARJETA), reader_id if room.is_empty() else room,
			make_fact(RECORD_CARD_LOG, reader_id), day)
	_classify_sensor_log(rec, hour)
	_refresh_suspicion()


## La denuncia es una creencia del denunciante con weight = puntos convertidos (ver DECISIONES).
func _on_npc_reported_player(npc_id: String, report_type: String, weight: float,
		location: String) -> void:
	var certainty: float = _bal_f(B_CERTEZA_DENUNCIA)
	var points: float = get_report_points(report_type, weight)
	_create(npc_id, PLAYER_ID, make_fact(FACT_REPORTED, report_type), certainty,
			Belief.SOURCE_DIRECT, location, weight_for_suspicion_points(points, certainty))
	if not _bal_strings(B_DENUNCIAS_ANOTACION).has(report_type):
		return
	var note: Belief = _insert_record(RECORD_HOLDER, RECORD_STAMPED_DOCUMENT, PLAYER_ID,
			_bal_f(B_PESO_ANOTACION), location,
			make_fact(RECORD_STAMPED_DOCUMENT, FILE_ANNOTATION_DETAIL), _today())
	_neutral[note.id] = NEUTRAL_ANNOTATION
	_refresh_suspicion()


func _on_crime_committed(crime_type: String, room_id: String, details: Dictionary) -> void:
	if DESTRUCTION_BY_CRIME.has(crime_type):
		_destroy_by_crime(crime_type, details)
		_leave_access_trace(crime_type, room_id)
	else:
		_record_from_crime(crime_type, room_id, details)
	_mark_crime(crime_type, room_id)
	_refresh_suspicion()


func _on_body_discovered(body_id: String, room_id: String) -> void:
	_insert_record(RECORD_HOLDER, RECORD_BODY_FOUND, UNKNOWN_SUBJECT,
			_evidence_weight(W_CUERPO), room_id, make_fact(RECORD_BODY_FOUND, body_id), _today())
	_refresh_suspicion()


## Un testigo expulsado o eliminado se lleva sus creencias (§12.4); los rumores ya propagados
## y los registros permanecen. Una expulsión deja «una expulsión firmada» (§7.6) sobre él.
func _on_npc_removed(npc_id: String, cause: String) -> void:
	for b: Belief in get_beliefs_held_by(npc_id):
		if not b.is_record:
			_forget(b)
	if _bal_strings(B_CAUSAS_EXPULSION).has(cause):
		var fact: String = make_fact(RECORD_SIGNED_EXPULSION, npc_id)
		_insert_record(RECORD_HOLDER, RECORD_SIGNED_EXPULSION, npc_id, get_fact_weight(fact), "",
				fact, _today())
	_refresh_suspicion()


## Protocolo de social_graph.gd: un salto from → to. "player" = rumor plantado (id sintético).
func _on_rumor_spread(from_npc: String, to_npc: String, belief_id: String) -> void:
	if from_npc == PLAYER_ID:
		_plant_rumour(to_npc, SocialGraph.get_injected_rumour(belief_id))
		return
	var src: Belief = get_belief(belief_id)
	if src == null or src.is_record or SocialGraph.is_fact_killed(src.fact):
		return
	transfer_belief(belief_id, to_npc,
			SocialGraph.get_transfer_factor(from_npc, to_npc, src.fact, src.subject))


## §5.3 «definitivo si se verifica»: un documento sin verificar que una investigación toma como
## pieza queda verificado y pasa a pesar en la sospecha.
func _on_evidence_added(case_id: String, _evidence_type: String, _weight: float,
		_points_to: String) -> void:
	if not _neutral.values().has(NEUTRAL_UNVERIFIED):
		return
	var inv: Investigation = Security.get_investigation(case_id)
	if inv == null:
		return
	for piece: Dictionary in inv.evidence:
		var id: String = str(piece.get(E_RECORD_ID, ""))
		if _neutral.get(id, "") == NEUTRAL_UNVERIFIED:
			_neutral.erase(id)
	_refresh_suspicion()


func _on_reputation_changed(_old_value: float, new_value: float) -> void:
	_player_reputation = new_value


## El decaimiento de la prensa (NewsFeed oye day_advanced después) entra con el recálculo diferido.
func _on_day_advanced(day_number: int) -> void:
	_release_pending_records(day_number)
	_prune_crime_marks(day_number)
	apply_daily_decay()
	_queue_refresh()


func _on_run_loaded(_day_number: int) -> void:
	_refresh_suspicion()


# ─── Internos: creación y almacenamiento ──────────────────────

func _create(holder: String, subject: String, fact: String, certainty: float, source: String,
		location: String, weight: float) -> String:
	if not Belief.SOURCES.has(source):
		push_error("BeliefNet: unknown belief source '%s'" % source)
		return ""
	var born: float = _birth_certainty(subject, fact, certainty, source, weight)
	var existing: Belief = _find_same(holder, subject, fact, location)
	if existing != null:
		if _merge(existing, born, source, weight):
			EventBus.belief_decayed.emit(existing.id, existing.certainty)
		_refresh_suspicion()
		return existing.id
	var b: Belief = Belief.make(_new_id(BELIEF_ID_PREFIX), holder, subject, fact, born, source,
			location, _today())
	b.weight = maxf(weight, 0.0)
	b.evidence_strength = b.weight if b.weight > 0.0 else get_fact_weight(fact)
	_store(b)
	EventBus.belief_created.emit(b.id, holder, subject, born)
	_refresh_suspicion()
	return b.id


func _plant_rumour(target: String, rumour: Dictionary) -> void:
	var fact: String = str(rumour.get(R_FACT, ""))
	if fact.is_empty() or SocialGraph.is_fact_killed(fact):
		return
	_create(target, str(rumour.get(R_SUBJECT, PLAYER_ID)), fact,
			float(rumour.get(R_CERTAINTY, 0.0)), Belief.SOURCE_RUMOR,
			str(rumour.get(R_LOCATION, "")), 0.0)


## Crea y almacena un registro (certeza 1,00, weight tal cual) y emite record_created, sin
## recalcular la sospecha.
func _insert_record(holder: String, record_type: String, subject: String, weight: float,
		location: String, fact: String, day: int) -> Belief:
	if not RECORD_TYPES.has(record_type):
		push_warning("BeliefNet: record type '%s' is not one of §7.6" % record_type)
	var rec: Belief = Belief.make(_new_id(RECORD_ID_PREFIX),
			RECORD_HOLDER if holder.is_empty() else holder, subject, fact,
			Belief.MAX_CERTAINTY, Belief.SOURCE_RECORD, location, day)
	rec.record_type = record_type
	rec.weight = maxf(weight, 0.0)
	rec.evidence_strength = rec.weight
	_store(rec)
	EventBus.record_created.emit(rec.id, record_type, rec.weight)
	return rec


## §7.10: las creencias negativas de primera mano sobre el jugador nacen con certeza reducida
## en mod_certeza_inicial_por_reputacion_jugador × reputación (valor absoluto, acotado a 0–1).
func _birth_certainty(subject: String, fact: String, certainty: float, source: String,
		weight: float) -> float:
	var c: float = clampf(certainty, Belief.MIN_CERTAINTY, Belief.MAX_CERTAINTY)
	if source != Belief.SOURCE_DIRECT or subject != PLAYER_ID:
		return c
	if weight <= 0.0 and not is_negative_fact(fact):
		return c
	var delta: float = _bal_f(B_MOD_CERTEZA_INICIAL) * _player_reputation
	return clampf(c + delta, Belief.MIN_CERTAINTY, Belief.MAX_CERTAINTY)


func _find_same(holder: String, subject: String, fact: String, location: String) -> Belief:
	var id: String = _by_merge_key.get(_merge_key(holder, subject, fact, location), "")
	return get_belief(id) if not id.is_empty() else null


static func _merge_key(holder: String, subject: String, fact: String, location: String) -> String:
	return MERGE_KEY_SEPARATOR.join([holder, subject, fact, location])


## Directa: refuerzo acumulable (percepción parcial acumulable, §7.2). Rumor: solo eleva. El
## weight propio queda en el mayor. true si la certeza cambió y la creencia sigue viva.
func _merge(existing: Belief, certainty: float, source: String, weight: float) -> bool:
	var before: float = existing.certainty
	if weight > existing.weight:
		existing.weight = weight
		existing.evidence_strength = weight
	if source == Belief.SOURCE_DIRECT:
		existing.source = Belief.SOURCE_DIRECT
		_apply_reinforcement(existing, certainty)
	elif certainty > existing.certainty:
		_set_fresh(existing, certainty)
	return _beliefs.has(existing.id) and not is_equal_approx(before, existing.certainty)


func _apply_reinforcement(b: Belief, additional: float) -> void:
	var base: float = _peaks.get(b.id, b.certainty)
	var c: float = clampf(base + additional, Belief.MIN_CERTAINTY, Belief.MAX_CERTAINTY)
	if c < _bal_f(B_UMBRAL_OLVIDO):
		_forget(b)
	else:
		_set_fresh(b, c)


func _set_fresh(b: Belief, certainty: float) -> void:
	b.certainty = certainty
	_peaks[b.id] = certainty
	_decay_days[b.id] = 0


func _store(b: Belief) -> void:
	_beliefs[b.id] = b
	_peaks[b.id] = b.certainty
	_decay_days[b.id] = 0
	if b.subject == PLAYER_ID:
		_player_ids[b.id] = true
	if not b.is_record:
		_by_merge_key[_merge_key(b.holder, b.subject, b.fact, b.location)] = b.id


func _remove(id: String) -> void:
	var b: Belief = get_belief(id)
	if b != null and not b.is_record:
		_by_merge_key.erase(_merge_key(b.holder, b.subject, b.fact, b.location))
	_beliefs.erase(id)
	_peaks.erase(id)
	_decay_days.erase(id)
	_player_ids.erase(id)
	_neutral.erase(id)
	_log_hours.erase(id)


func _forget(b: Belief) -> void:
	_remove(b.id)
	EventBus.belief_forgotten.emit(b.id)


func _destroy_record_silently(id: String, method: String) -> bool:
	var b: Belief = get_belief(id)
	if b == null or not b.is_record:
		return false
	_remove(id)
	EventBus.record_destroyed.emit(id, method)
	return true


func _new_id(prefix: String) -> String:
	var id: String = "%s%d" % [prefix, _next_id]
	_next_id += 1
	return id


func _clear() -> void:
	_beliefs.clear()
	_peaks.clear()
	_decay_days.clear()
	_player_ids.clear()
	_by_merge_key.clear()
	_neutral.clear()
	_log_hours.clear()
	_crime_marks.clear()
	_pending_records.clear()
	_next_id = 1
	_suspicion = 0.0


# ─── Internos: registros neutros e incriminatorios ────────────

## Lectura de un sensor (cámara o lector): guarda su hora y la deja neutra (rutinaria) salvo
## contexto incriminatorio.
func _classify_sensor_log(rec: Belief, hour: int) -> void:
	_log_hours[rec.id] = hour
	if not _is_incriminating_context(rec.location, rec.timestamp, hour):
		_neutral[rec.id] = NEUTRAL_ROUTINE


## Sala vetada a la acreditación del jugador, franja sospechosa (§5.6 nocturno) o delito visible
## en la misma sala a ±creencias.horas_ventana_delito_registro horas el mismo día.
func _is_incriminating_context(room_id: String, day: int, hour: int) -> bool:
	if is_room_forbidden_for_player(room_id):
		return true
	if _bal_strings(B_FRANJAS_INCRIMINATORIAS).has(GameClock.get_current_band()):
		return true
	var mark: Dictionary = _crime_marks.get(room_id, {})
	return not mark.is_empty() and _within_crime_window(mark, day, hour)


func _within_crime_window(mark: Dictionary, day: int, hour: int) -> bool:
	if hour == NO_HOUR or int(mark[M_DAY]) != day:
		return false
	return absi(int(mark[M_HOUR]) - hour) <= _bal_i(B_VENTANA_DELITO)


## Un delito visible marca su sala y vuelve incriminatorias sus lecturas rutinarias cercanas.
func _mark_crime(crime_type: String, room_id: String) -> void:
	if room_id.is_empty() or _bal_strings(B_DELITOS_SIN_RASTRO).has(crime_type):
		return
	var mark: Dictionary = {M_DAY: _today(), M_HOUR: GameClock.get_hour()}
	_crime_marks[room_id] = mark
	for id: String in _neutral.keys():
		if _neutral[id] != NEUTRAL_ROUTINE or _beliefs[id].location != room_id:
			continue
		if _within_crime_window(mark, _beliefs[id].timestamp, _log_hours.get(id, NO_HOUR)):
			_neutral.erase(id)


func _prune_crime_marks(day_number: int) -> void:
	for room: String in _crime_marks.keys():
		if int(_crime_marks[room][M_DAY]) < day_number:
			_crime_marks.erase(room)


# ─── Internos: delitos y registros ────────────────────────────

func _destroy_by_crime(crime_type: String, details: Dictionary) -> void:
	var method: String = str(details.get(D_METHOD, crime_type))
	for record_type: String in DESTRUCTION_BY_CRIME[crime_type]:
		for id: String in _destruction_targets(record_type, details):
			_destroy_record_silently(id, method)


## Un footage_id (Security.delete_footage) borra UNA grabación, la copia de ese clip
## (preferentemente una incriminatoria); sin footage_id se borran todas las seleccionadas.
func _destruction_targets(record_type: String, details: Dictionary) -> Array[String]:
	var ids: Array[String] = _matching_record_ids(record_type, details)
	if not details.has(D_FOOTAGE_ID) or ids.size() <= 1:
		return ids
	var chosen: Array[String] = [ids[0]]
	for id: String in ids:
		if not _neutral.has(id):
			chosen[0] = id
			break
	return chosen


## §22 server_room: el borrado deja un registro de acceso en el servidor, clasificado como
## cualquier lectura (incriminatorio si la sala está vetada al jugador).
func _leave_access_trace(crime_type: String, room_id: String) -> void:
	if not CRIMES_WITH_ACCESS_TRACE.has(crime_type):
		return
	var rec: Belief = _insert_record(RECORD_HOLDER, RECORD_CARD_LOG, PLAYER_ID,
			_evidence_weight(W_TARJETA), room_id, make_fact(RECORD_CARD_LOG, room_id), _today())
	_classify_sensor_log(rec, GameClock.get_hour())


## creencias.registros_por_delito: {crimen: {record_type, peso, retardo_dias, sin_verificar}}.
## details admite "subject" (a quién señala el documento), "weight" (sustituye al peso),
## "leaves_record" y "verified" (el documento nace verificado).
func _record_from_crime(crime_type: String, room_id: String, details: Dictionary) -> void:
	var path: String = B_REGISTROS_POR_DELITO + PATH_SEPARATOR + crime_type
	if not Database.has_balance(path) or not bool(details.get(D_LEAVES_RECORD, true)):
		return
	var spec: Dictionary = _bal_dict(path)
	var record_type: String = str(spec.get(S_RECORD_TYPE, ""))
	var weight: Variant = details.get(D_WEIGHT)
	if weight == null:
		weight = _evidence_weight(str(spec.get(S_WEIGHT_KEY, "")))
	var pending: Dictionary = _make_pending({
		P_RECORD_TYPE: record_type, P_SUBJECT: details.get(D_SUBJECT, PLAYER_ID),
		P_WEIGHT: weight, P_LOCATION: room_id, P_FACT: make_fact(record_type, crime_type),
		P_DUE_DAY: _today() + int(spec.get(S_DELAY, 0)),
		P_UNVERIFIED: bool(spec.get(S_UNVERIFIED, false))
				and not bool(details.get(D_VERIFIED, false)),
	})
	if int(pending[P_DUE_DAY]) <= _today():
		_materialize(pending, _today())
	else:
		_pending_records.append(pending)


## Registro diferido con tipos normalizados (también al cargar desde JSON).
func _make_pending(d: Dictionary) -> Dictionary:
	return {
		P_RECORD_TYPE: str(d.get(P_RECORD_TYPE, "")),
		P_SUBJECT: str(d.get(P_SUBJECT, PLAYER_ID)), P_WEIGHT: float(d.get(P_WEIGHT, 0.0)),
		P_LOCATION: str(d.get(P_LOCATION, "")), P_FACT: str(d.get(P_FACT, "")),
		P_DUE_DAY: int(d.get(P_DUE_DAY, 0)), P_UNVERIFIED: bool(d.get(P_UNVERIFIED, false)),
	}


func _release_pending_records(day_number: int) -> void:
	var still_pending: Array[Dictionary] = []
	for pending: Dictionary in _pending_records:
		if int(pending.get(P_DUE_DAY, 0)) <= day_number:
			_materialize(pending, day_number)
		else:
			still_pending.append(pending)
	_pending_records = still_pending


func _materialize(pending: Dictionary, day: int) -> void:
	var rec: Belief = _insert_record(RECORD_HOLDER, pending[P_RECORD_TYPE], pending[P_SUBJECT],
			pending[P_WEIGHT], pending[P_LOCATION], pending[P_FACT], day)
	if bool(pending[P_UNVERIFIED]):
		_neutral[rec.id] = NEUTRAL_UNVERIFIED


## Selección por details: "record_ids" (lista exacta) o filtros combinables sobre los registros
## del tipo: detalle del hecho (camera_id / reader_id), "room_id", "day", "hour", "subject". Sin
## ningún criterio no se destruye nada.
func _matching_record_ids(record_type: String, details: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if details.has(D_RECORD_IDS):
		for id: Variant in details[D_RECORD_IDS]:
			var b: Belief = get_belief(str(id))
			if b != null and b.record_type == record_type:
				out.append(b.id)
		return out
	var detail_key: String = DETAIL_KEY_BY_RECORD.get(record_type, "")
	var filters: Array[String] = [detail_key, D_ROOM, D_DAY, D_HOUR, D_SUBJECT]
	if not filters.any(func(k: String) -> bool: return details.has(k)):
		return out
	for b: Belief in _beliefs.values():
		if b.is_record and b.record_type == record_type and _record_matches(b, details, detail_key):
			out.append(b.id)
	return out


func _record_matches(b: Belief, details: Dictionary, detail_key: String) -> bool:
	if details.has(detail_key) and fact_detail_of(b.fact) != str(details[detail_key]):
		return false
	if details.has(D_ROOM) and b.location != str(details[D_ROOM]):
		return false
	if details.has(D_DAY) and b.timestamp != int(details[D_DAY]):
		return false
	if details.has(D_HOUR) and _log_hours.get(b.id, NO_HOUR) != int(details[D_HOUR]):
		return false
	return not details.has(D_SUBJECT) or b.subject == str(details[D_SUBJECT])


func _load_entry(entry: Dictionary, index: int) -> void:
	var b: Belief = Belief.from_dict(entry, Validate.entry(SAVE_CONTEXT, index))
	if b.id.is_empty():
		return
	_store(b)
	_peaks[b.id] = float(entry.get(K_PEAK, b.certainty))
	_decay_days[b.id] = int(entry.get(K_DECAY_DAYS, 0))


func _load_record_meta(data: Dictionary) -> void:
	var neutral: Variant = data.get(K_NEUTRAL, {})
	if neutral is Dictionary:
		for id: Variant in neutral:
			if _beliefs.has(str(id)):
				_neutral[str(id)] = str(neutral[id])
	var hours: Variant = data.get(K_LOG_HOURS, {})
	if hours is Dictionary:
		for id: Variant in hours:
			if _beliefs.has(str(id)):
				_log_hours[str(id)] = int(hours[id])
	var marks: Variant = data.get(K_CRIME_MARKS, {})
	if marks is Dictionary:
		for room: Variant in marks:
			var mark: Variant = marks[room]
			if mark is Dictionary:
				_crime_marks[str(room)] = {M_DAY: int(mark.get(M_DAY, 0)),
						M_HOUR: int(mark.get(M_HOUR, 0))}


# ─── Internos: sospecha ───────────────────────────────────────

func _contribution_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var divisor: float = _bal_f(B_DIVISOR)
	if divisor <= 0.0:
		return out
	var neutral_factor: float = _bal_f(B_FACTOR_NEUTRO)
	var credibility: Dictionary[String, float] = {}
	var by_sensor: Dictionary[String, int] = {}
	for id: String in _player_ids.keys():
		var b: Belief = _beliefs[id]
		var weight: float = _weight_in_suspicion(b, neutral_factor)
		if weight <= 0.0:
			continue
		if not credibility.has(b.holder):
			credibility[b.holder] = get_credibility(b.holder)
		var entry: Dictionary = _make_entry(b, weight, credibility[b.holder], divisor)
		_append_entry(out, entry, _sensor_key(b), by_sensor)
	_append_news_entry(out)
	return out


## Capa compartida (§7.11): la prensa viva como una entrada más (certeza y credibilidad neutras).
func _append_news_entry(out: Array[Dictionary]) -> void:
	var points: float = get_news_contribution()
	if points <= 0.0:
		return
	out.append({
		BK_ID: NEWS_ENTRY_ID, BK_HOLDER: NEWS_HOLDER, BK_FACT: NEWS_FACT,
		BK_CERTAINTY: Belief.MAX_CERTAINTY, BK_CREDIBILITY: NEUTRAL_MULTIPLIER, BK_WEIGHT: points,
		BK_SOURCE: NEWS_SOURCE, BK_IS_RECORD: false, BK_CONTRIBUTION: points,
	})


## Registros neutros primero (miles de lecturas rutinarias en una partida larga: salida rápida).
func _weight_in_suspicion(b: Belief, neutral_factor: float) -> float:
	var neutral: bool = b.is_record and _neutral.has(b.id)
	if neutral and neutral_factor <= 0.0:
		return 0.0
	var weight: float = b.weight if b.weight > 0.0 else get_fact_weight(b.fact)
	return weight * neutral_factor if neutral else weight


func _make_entry(b: Belief, weight: float, credibility: float, divisor: float) -> Dictionary:
	return {
		BK_ID: b.id, BK_HOLDER: b.holder, BK_FACT: b.fact, BK_CERTAINTY: b.certainty,
		BK_CREDIBILITY: credibility, BK_WEIGHT: weight, BK_SOURCE: b.source,
		BK_IS_RECORD: b.is_record,
		BK_CONTRIBUTION: b.certainty * credibility * weight * SUSPICION_MAX / divisor,
	}


## Cada sensor cuenta una vez por jornada: de sus lecturas queda la de mayor contribución.
func _append_entry(out: Array[Dictionary], entry: Dictionary, sensor_key: String,
		by_sensor: Dictionary[String, int]) -> void:
	if sensor_key.is_empty():
		out.append(entry)
	elif not by_sensor.has(sensor_key):
		by_sensor[sensor_key] = out.size()
		out.append(entry)
	elif float(entry[BK_CONTRIBUTION]) > float(out[by_sensor[sensor_key]][BK_CONTRIBUTION]):
		out[by_sensor[sensor_key]] = entry


func _sensor_key(b: Belief) -> String:
	if not _log_hours.has(b.id):
		return ""
	return MERGE_KEY_SEPARATOR.join([b.fact, str(b.timestamp)])


## Recalcula (por evento, nunca por fotograma), publica en PlayerState y emite suspicion_changed.
func _refresh_suspicion() -> void:
	var old_value: float = _suspicion
	_suspicion = calculate_player_suspicion()
	# Única excepción documentada (§19.3 / PASO 6): BeliefNet escribe la caché de PlayerState.
	PlayerState._set_suspicion_from_beliefnet(_suspicion)
	if not is_equal_approx(old_value, _suspicion):
		EventBus.suspicion_changed.emit(old_value, _suspicion)


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()


func _flush_refresh() -> void:
	_refresh_queued = false
	_refresh_suspicion()


func _is_suspicion_belief(b: Belief) -> bool:
	return b.subject == PLAYER_ID and get_suspicion_weight(b) > 0.0


func _is_killed_rumour(b: Belief) -> bool:
	return b.source == Belief.SOURCE_RUMOR and SocialGraph.is_fact_killed(b.fact)


## Aceleración del decaimiento de la sospecha por reputación del jugador (§7.10).
func _player_decay_multiplier() -> float:
	return NEUTRAL_MULTIPLIER + _bal_f(B_MOD_DECAIMIENTO_REP) * _player_reputation


# ─── Internos: lecturas de otros sistemas y de balance ────────

## Portadores que no son personajes (registros, "" de IdeaPresentation): no se consulta NPCDirector.
func _is_generic_holder(holder: String) -> bool:
	return holder.is_empty() or holder == RECORD_HOLDER


func _today() -> int:
	return GameClock.get_day()


func _player_room() -> String:
	return PlayerState.get_room()


func _recorded_subject() -> String:
	var uniform: String = PlayerState.get_disguise()
	return PLAYER_ID if uniform.is_empty() else DISGUISE_SUBJECT_PREFIX + uniform


func _evidence_weight(key: String) -> float:
	return _bal_f(B_PESOS_EVIDENCIA + PATH_SEPARATOR + key)


func _bal_f(path: String) -> float:
	return Database.get_balance_float(path)


func _bal_i(path: String) -> int:
	return Database.get_balance_int(path)


func _bal_dict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(path)
	return value if value is Dictionary else {}


func _bal_strings(path: String) -> Array[String]:
	var out: Array[String] = []
	var value: Variant = Database.get_balance(path)
	if value is Array:
		for item: Variant in value:
			out.append(str(item))
	return out
