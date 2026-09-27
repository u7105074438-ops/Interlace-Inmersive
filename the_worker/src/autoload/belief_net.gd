# belief_net.gd — Almacena y gestiona todas las creencias del mundo, los registros y la sospecha.
# PROPIETARIO DE: creencias y registros (§7.2, §7.6), su decaimiento, registros diferidos y la sospecha.
# ESCUCHA: player_seen_partially, player_caught_redhanded, camera_recorded_player, card_reader_logged, npc_reported_player, crime_committed, body_discovered, npc_removed, reputation_changed, day_advanced.
class_name BeliefNetSystem
extends Node

## CONVENCIONES (decisiones de construcción, ver informe del PASO 13):
## - Hecho (`fact`): "<tipo>" o "<tipo>:<detalle>" (p. ej. "caught_redhanded:theft_small",
##   "footage:cam_p03_1"). El peso en la sospecha se busca por <tipo> en creencias.peso_tipo.
## - Sujeto del jugador: PLAYER_ID. Los registros los sostiene RECORD_HOLDER ("archive").
## - Sospecha = clamp(Σ certeza × credibilidad_portador × peso_tipo × 100 / divisor, 0, 100),
##   con credibilidad = reputación_portador × mod_credibilidad_por_reputacion y
##   peso_tipo = (peso propio si > 0, si no creencias.peso_tipo[tipo]) × creencias.peso_origen[source].
## - get_beliefs_about / count_credible_beliefs_about excluyen registros; get_records_about los da.
## - Dos creencias ordinarias con igual (holder, subject, fact, location) se fusionan: una fuente
##   directa refuerza (restablece la certeza de referencia y suma); un rumor solo eleva al máximo.
## - npc_reported_player.weight son PUNTOS de sospecha (CaughtHandler, Blackmail); se guardan como
##   peso de creencia con weight_for_suspicion_points. card_reader_logged solo lo emiten lecturas
##   del jugador (card_owner ajeno = tarjeta robada: el registro señala al titular).
## - Registros diferidos (creencias.registros_por_delito.retardo_dias) afloran en day_advanced.
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
const NPC_REPUTATION_GETTER := "get_npc_reputation"

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
	RECORD_CARD_LOG, RECORD_STAMPED_DOCUMENT, RECORD_CHAT_LOG,
]
# crime_committed que destruyen registros (sala de monitores; servidores: registros digitales)
# y claves de details con las que se seleccionan.
const CRIME_FOOTAGE_DELETED := "footage_deleted"
const CRIME_RECORDS_DELETED := "records_deleted"
const DESTRUCTION_BY_CRIME: Dictionary = {
	CRIME_FOOTAGE_DELETED: [RECORD_FOOTAGE],
	CRIME_RECORDS_DELETED: [RECORD_CARD_LOG, RECORD_CHAT_LOG],
}
const DETAIL_KEY_BY_RECORD: Dictionary = {
	RECORD_FOOTAGE: "camera_id", RECORD_CARD_LOG: "reader_id",
}

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
const B_PESO_ORIGEN := "creencias.peso_origen"
const B_DIVISOR := "creencias.divisor_normalizacion"
const B_REGISTROS_POR_DELITO := "creencias.registros_por_delito"
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
## Registros que afloran con retardo: {record_type, subject, weight, location, fact, due_day}.
var _pending_records: Array[Dictionary] = []
var _next_id: int = 1
## Último valor publicado (PlayerState lo guarda en caché).
var _suspicion: float = 0.0
## Reputación del jugador, actualizada por reputation_changed (moduladores de §7.10).
var _player_reputation: float = 0.0


func _ready() -> void:
	EventBus.player_seen_partially.connect(_on_player_seen_partially)
	EventBus.player_caught_redhanded.connect(_on_player_caught_redhanded)
	EventBus.camera_recorded_player.connect(_on_camera_recorded_player)
	EventBus.card_reader_logged.connect(_on_card_reader_logged)
	EventBus.npc_reported_player.connect(_on_npc_reported_player)
	EventBus.crime_committed.connect(_on_crime_committed)
	EventBus.body_discovered.connect(_on_body_discovered)
	EventBus.npc_removed.connect(_on_npc_removed)
	EventBus.reputation_changed.connect(_on_reputation_changed)
	EventBus.day_advanced.connect(_on_day_advanced)


func reset_for_new_run() -> void:
	_clear()
	_player_reputation = PlayerState.get_reputation()
	PlayerState._set_suspicion_from_beliefnet(_suspicion)


# ─── Creación ─────────────────────────────────────────────────

## Devuelve el id de la creencia (el de la existente si se fusiona) o "" si no es válida.
func create_belief(holder: String, subject: String, fact: String,
		certainty: float, source: String, location: String) -> String:
	if source == Belief.SOURCE_RECORD:
		var rec: Belief = _insert_record(holder, fact_type_of(fact), subject, 0.0, location,
				fact, _today())
		_refresh_suspicion()
		return rec.id
	return _create(holder, subject, fact, certainty, source, location, 0.0)


func create_record(record_type: String, subject: String,
		weight: float, location: String) -> String:
	var rec: Belief = _insert_record(RECORD_HOLDER, record_type, subject, weight, location,
			record_type, _today())
	_refresh_suspicion()
	return rec.id


# ─── Consulta ─────────────────────────────────────────────────

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


# ─── Modificación ─────────────────────────────────────────────

## Restablece la certeza de referencia, le suma `additional_certainty` y reinicia el reloj de
## decaimiento. Un refuerzo negativo que la deja bajo el umbral de olvido la olvida.
func reinforce_belief(id: String, additional_certainty: float) -> void:
	var b: Belief = get_belief(id)
	if b == null or b.is_record:
		return
	_apply_reinforcement(b, additional_certainty)
	_refresh_suspicion()


func destroy_record(id: String, method: String) -> bool:
	var destroyed: bool = _destroy_record_silently(id, method)
	if destroyed:
		_refresh_suspicion()
	return destroyed


## Copia la creencia a `to_holder` como rumor con certeza = certeza_emisor × degradation.
## `degradation` es el MULTIPLICADOR de transmisión (0,75 = transmisión oral estándar; > 1
## amplifica), acotado a [0, amplificacion_rumor_max]. Devuelve el id de la copia (o de la
## creencia que ya tenía el receptor) o "" si no prende (certeza bajo el umbral de olvido).
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


## EXTRA (SocialGraph.kill_rumour): olvida las creencias de origen rumor con ese hecho exacto.
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


# ─── Sospecha ─────────────────────────────────────────────────

func calculate_player_suspicion() -> float:
	var total: float = 0.0
	for entry: Dictionary in _contribution_entries():
		total += float(entry["contribution"])
	return clampf(total, 0.0, SUSPICION_MAX)


## Para el panel de depuración: [{belief_id, holder, fact, certainty, credibility, weight,
## contribution, source, is_record}] ordenado por contribución (en puntos de sospecha) descendente.
func get_suspicion_breakdown() -> Array[Dictionary]:
	var entries: Array[Dictionary] = _contribution_entries()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["contribution"]) > float(b["contribution"]))
	return entries


## EXTRA: credibilidad de un portador = reputación × mod_credibilidad_por_reputacion. La
## reputación viene de NPCDirector.get_npc_reputation (BUILD_NOTES §13); si falta o es 0 se usa
## creencias.reputacion_portador_por_defecto (portadores no personaje, como RECORD_HOLDER).
func get_credibility(holder: String) -> float:
	var reputation: float = 0.0
	if not _is_generic_holder(holder) and NPCDirector.has_method(NPC_REPUTATION_GETTER):
		reputation = float(NPCDirector.call(NPC_REPUTATION_GETTER, holder))
	if reputation <= 0.0:
		return get_default_credibility()
	return reputation * _bal_f(B_MOD_CREDIBILIDAD)


## EXTRA: credibilidad de un portador sin reputación propia (registros, portadores genéricos).
func get_default_credibility() -> float:
	return _bal_f(B_REP_DEFECTO) * _bal_f(B_MOD_CREDIBILIDAD)


## EXTRA: peso de una creencia directa de certeza `certainty` que, sostenida por un portador de
## credibilidad por defecto, aporta exactamente `points` puntos de sospecha (sin reducciones).
func weight_for_suspicion_points(points: float, certainty: float) -> float:
	var per_weight: float = certainty * get_default_credibility() \
			* get_source_weight(Belief.SOURCE_DIRECT) * SUSPICION_MAX
	if per_weight <= 0.0:
		return 0.0
	return maxf(points, 0.0) * _bal_f(B_DIVISOR) / per_weight


## EXTRA: peso de un tipo de hecho en la sospecha (creencias.peso_tipo, "default" si falta).
func get_fact_weight(fact: String) -> float:
	var path: String = B_PESO_TIPO + PATH_SEPARATOR + fact_type_of(fact)
	if not Database.has_balance(path):
		path = B_PESO_TIPO + PATH_SEPARATOR + WEIGHT_DEFAULT_KEY
	return _bal_f(path)


## EXTRA: multiplicador por origen (creencias.peso_origen; neutro si el origen no figura).
func get_source_weight(source: String) -> float:
	var path: String = B_PESO_ORIGEN + PATH_SEPARATOR + source
	return _bal_f(path) if Database.has_balance(path) else NEUTRAL_MULTIPLIER


## EXTRA: un hecho es negativo si pesa en la sospecha (SocialGraph: la rivalidad solo propaga
## hechos negativos; §7.10: solo las creencias negativas nacen reducidas y decaen antes).
func is_negative_fact(fact: String) -> bool:
	return get_fact_weight(fact) > 0.0


# ─── Mantenimiento ────────────────────────────────────────────

## Invocado por day_advanced. Los registros no decaen jamás (§7.6).
func apply_daily_decay() -> void:
	var threshold: float = _bal_f(B_UMBRAL_OLVIDO)
	var base_rate: float = _bal_f(B_DECAIMIENTO)
	var player_rate: float = base_rate * _player_decay_multiplier()
	var forgotten: Array[Belief] = []
	for b: Belief in _beliefs.values():
		if b.is_record:
			continue
		var rate: float = player_rate if _is_suspicion_belief(b) else base_rate
		b.certainty = maxf(b.certainty - rate, Belief.MIN_CERTAINTY)
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


## Clave de texto del origen para la interfaz (BELIEF_SOURCE_DIRECT | _RUMOR | _RECORD).
static func source_label_key(source: String) -> String:
	return SOURCE_LABEL_KEY_PREFIX + source.to_upper()


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	var entries: Array[Dictionary] = []
	for b: Belief in _beliefs.values():
		var entry: Dictionary = b.to_dict()
		entry["weight"] = b.weight
		entry["peak"] = _peaks.get(b.id, b.certainty)
		entry["decay_days"] = _decay_days.get(b.id, 0)
		entries.append(entry)
	return {
		"beliefs": entries, "pending_records": _pending_records.duplicate(true),
		"next_id": _next_id, "suspicion": _suspicion, "player_reputation": _player_reputation,
	}


func load_state(data: Dictionary) -> void:
	_clear()
	_next_id = int(data.get("next_id", _next_id))
	_suspicion = float(data.get("suspicion", 0.0))
	_player_reputation = float(data.get("player_reputation", PlayerState.get_reputation()))
	var entries: Array = data.get("beliefs", [])
	for i: int in entries.size():
		if entries[i] is Dictionary:
			_load_entry(entries[i], i)
	for pending: Variant in data.get("pending_records", []):
		if pending is Dictionary:
			_pending_records.append(_make_pending(pending))
	_refresh_suspicion()


# ─── Reacciones a EventBus ────────────────────────────────────

func _on_player_seen_partially(npc_id: String, certainty: float, location: String) -> void:
	var c: float = certainty if certainty > 0.0 else _bal_f(B_CERTEZA_PARCIAL)
	create_belief(npc_id, PLAYER_ID, FACT_SEEN_PARTIALLY, c, Belief.SOURCE_DIRECT, location)


func _on_player_caught_redhanded(npc_id: String, crime_type: String, _witnesses: int) -> void:
	create_belief(npc_id, PLAYER_ID, make_fact(FACT_CAUGHT_REDHANDED, crime_type),
			_bal_f(B_CERTEZA_DIRECTA), Belief.SOURCE_DIRECT, _player_room())


func _on_camera_recorded_player(camera_id: String, room_id: String, day: int) -> void:
	_insert_record(RECORD_HOLDER, RECORD_FOOTAGE, _recorded_subject(),
			_evidence_weight(W_GRABACION), room_id, make_fact(RECORD_FOOTAGE, camera_id), day)
	_refresh_suspicion()


## BeliefNet asume que card_reader_logged solo se emite por lecturas del jugador: con su tarjeta
## (card_owner = PLAYER_ID) o con una tarjeta ajena (el registro señala al titular, §5.3).
func _on_card_reader_logged(reader_id: String, card_owner: String, day: int, _hour: int) -> void:
	var subject: String = PLAYER_ID if card_owner.is_empty() else card_owner
	var room: String = _player_room()
	_insert_record(RECORD_HOLDER, RECORD_CARD_LOG, subject, _evidence_weight(W_TARJETA),
			reader_id if room.is_empty() else room, make_fact(RECORD_CARD_LOG, reader_id), day)
	_refresh_suspicion()


## La denuncia es una creencia del denunciante. El `weight` de la señal son PUNTOS de sospecha
## (§12.2: Security +20, superior +10; así la emiten CaughtHandler y Blackmail) y se convierte en
## peso de creencia con weight_for_suspicion_points (20 puntos → peso 4,0, la «denuncia de un
## testigo directo» de §12.3 con la calibración por defecto).
func _on_npc_reported_player(npc_id: String, report_type: String, weight: float,
		location: String) -> void:
	var certainty: float = _bal_f(B_CERTEZA_DENUNCIA)
	_create(npc_id, PLAYER_ID, make_fact(FACT_REPORTED, report_type), certainty,
			Belief.SOURCE_DIRECT, location, weight_for_suspicion_points(weight, certainty))


func _on_crime_committed(crime_type: String, room_id: String, details: Dictionary) -> void:
	if not DESTRUCTION_BY_CRIME.has(crime_type):
		_record_from_crime(crime_type, room_id, details)
		return
	var method: String = str(details.get("method", crime_type))
	var destroyed: int = 0
	for record_type: String in DESTRUCTION_BY_CRIME[crime_type]:
		for id: String in _matching_record_ids(record_type, details):
			if _destroy_record_silently(id, method):
				destroyed += 1
	if destroyed > 0:
		_refresh_suspicion()


func _on_body_discovered(body_id: String, room_id: String) -> void:
	_insert_record(RECORD_HOLDER, RECORD_BODY_FOUND, UNKNOWN_SUBJECT,
			_evidence_weight(W_CUERPO), room_id, make_fact(RECORD_BODY_FOUND, body_id), _today())
	_refresh_suspicion()


## Un testigo expulsado o eliminado se lleva sus creencias (§12.4); los rumores ya propagados
## y los registros permanecen.
func _on_npc_removed(npc_id: String, _cause: String) -> void:
	var held: Array[Belief] = get_beliefs_held_by(npc_id)
	for b: Belief in held:
		if not b.is_record:
			_forget(b)
	if not held.is_empty():
		_refresh_suspicion()


func _on_reputation_changed(_old_value: float, new_value: float) -> void:
	_player_reputation = new_value


func _on_day_advanced(day_number: int) -> void:
	_release_pending_records(day_number)
	apply_daily_decay()


# ─── Internos: creación y almacenamiento ──────────────────────

func _create(holder: String, subject: String, fact: String, certainty: float, source: String,
		location: String, weight: float) -> String:
	if not Belief.SOURCES.has(source):
		push_error("BeliefNet: unknown belief source '%s'" % source)
		return ""
	var born: float = _birth_certainty(subject, fact, certainty, source, weight)
	var existing: Belief = _find_same(holder, subject, fact, location)
	if existing != null:
		_merge(existing, born, source)
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


## Crea y almacena un registro (certeza 1,00) y emite record_created, sin recalcular sospecha.
func _insert_record(holder: String, record_type: String, subject: String, weight: float,
		location: String, fact: String, day: int) -> Belief:
	if not RECORD_TYPES.has(record_type):
		push_warning("BeliefNet: record type '%s' is not one of §7.6" % record_type)
	var rec: Belief = Belief.make(_new_id(RECORD_ID_PREFIX),
			RECORD_HOLDER if holder.is_empty() else holder, subject, fact,
			Belief.MAX_CERTAINTY, Belief.SOURCE_RECORD, location, day)
	rec.record_type = record_type
	rec.weight = weight if weight > 0.0 else get_fact_weight(fact)
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


## Directa: refuerzo acumulable (percepción parcial acumulable, §7.2). Rumor: solo eleva.
func _merge(existing: Belief, certainty: float, source: String) -> void:
	if source == Belief.SOURCE_DIRECT:
		existing.source = Belief.SOURCE_DIRECT
		_apply_reinforcement(existing, certainty)
	elif certainty > existing.certainty:
		_set_fresh(existing, certainty)


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
	_pending_records.clear()
	_next_id = 1
	_suspicion = 0.0


# ─── Internos: delitos y registros ────────────────────────────

## creencias.registros_por_delito: {crimen: {record_type, peso, retardo_dias}}. details admite
## "subject" (a quién señala el documento), "weight" (sustituye al peso) y "leaves_record".
func _record_from_crime(crime_type: String, room_id: String, details: Dictionary) -> void:
	var path: String = B_REGISTROS_POR_DELITO + PATH_SEPARATOR + crime_type
	if not Database.has_balance(path) or not bool(details.get("leaves_record", true)):
		return
	var spec: Dictionary = _bal_dict(path)
	var record_type: String = str(spec.get("record_type", ""))
	var weight: Variant = details.get("weight")
	if weight == null:
		weight = _evidence_weight(str(spec.get("peso", "")))
	var pending: Dictionary = _make_pending({
		"record_type": record_type, "subject": details.get("subject", PLAYER_ID),
		"weight": weight, "location": room_id, "fact": make_fact(record_type, crime_type),
		"due_day": _today() + int(spec.get("retardo_dias", 0)),
	})
	if int(pending["due_day"]) <= _today():
		_materialize(pending, _today())
		_refresh_suspicion()
	else:
		_pending_records.append(pending)


## Registro diferido con tipos normalizados (también al cargar desde JSON).
func _make_pending(d: Dictionary) -> Dictionary:
	return {
		"record_type": str(d.get("record_type", "")), "subject": str(d.get("subject", PLAYER_ID)),
		"weight": float(d.get("weight", 0.0)), "location": str(d.get("location", "")),
		"fact": str(d.get("fact", "")), "due_day": int(d.get("due_day", 0)),
	}


func _release_pending_records(day_number: int) -> void:
	var still_pending: Array[Dictionary] = []
	for pending: Dictionary in _pending_records:
		if int(pending.get("due_day", 0)) <= day_number:
			_materialize(pending, day_number)
		else:
			still_pending.append(pending)
	_pending_records = still_pending


func _materialize(pending: Dictionary, day: int) -> void:
	_insert_record(RECORD_HOLDER, pending["record_type"], pending["subject"], pending["weight"],
			pending["location"], pending["fact"], day)


## Selección por details: "record_ids" (lista exacta) o filtros combinables sobre los registros
## del tipo: detalle del hecho (camera_id / reader_id), "room_id", "day", "subject". Sin
## ningún criterio no se destruye nada.
func _matching_record_ids(record_type: String, details: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if details.has("record_ids"):
		for id: Variant in details["record_ids"]:
			var b: Belief = get_belief(str(id))
			if b != null and b.record_type == record_type:
				out.append(b.id)
		return out
	var detail_key: String = DETAIL_KEY_BY_RECORD.get(record_type, "")
	var filters: Array[String] = [detail_key, "room_id", "day", "subject"]
	if not filters.any(func(k: String) -> bool: return details.has(k)):
		return out
	for b: Belief in _beliefs.values():
		if not b.is_record or b.record_type != record_type:
			continue
		if _record_matches(b, details, detail_key):
			out.append(b.id)
	return out


func _record_matches(b: Belief, details: Dictionary, detail_key: String) -> bool:
	if details.has(detail_key) and fact_detail_of(b.fact) != str(details[detail_key]):
		return false
	if details.has("room_id") and b.location != str(details["room_id"]):
		return false
	if details.has("day") and b.timestamp != int(details["day"]):
		return false
	return not details.has("subject") or b.subject == str(details["subject"])


func _load_entry(entry: Dictionary, index: int) -> void:
	var b: Belief = Belief.from_dict(entry, Validate.entry(SAVE_CONTEXT, index))
	if b.id.is_empty():
		return
	_store(b)
	_peaks[b.id] = float(entry.get("peak", b.certainty))
	_decay_days[b.id] = int(entry.get("decay_days", 0))


# ─── Internos: sospecha ───────────────────────────────────────

func _contribution_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var divisor: float = _bal_f(B_DIVISOR)
	if divisor <= 0.0:
		return out
	for id: String in _player_ids.keys():
		var b: Belief = _beliefs[id]
		var weight: float = _base_weight(b) * get_source_weight(b.source)
		if weight <= 0.0:
			continue
		var credibility: float = get_credibility(b.holder)
		out.append({
			"belief_id": b.id, "holder": b.holder, "fact": b.fact, "certainty": b.certainty,
			"credibility": credibility, "weight": weight, "source": b.source,
			"is_record": b.is_record,
			"contribution": b.certainty * credibility * weight * SUSPICION_MAX / divisor,
		})
	return out


func _base_weight(b: Belief) -> float:
	return b.weight if b.weight > 0.0 else get_fact_weight(b.fact)


## Recalcula (por evento, nunca por fotograma), publica en PlayerState y emite suspicion_changed.
func _refresh_suspicion() -> void:
	var old_value: float = _suspicion
	_suspicion = calculate_player_suspicion()
	# Única excepción documentada (§19.3 / PASO 6): BeliefNet escribe la caché de PlayerState.
	PlayerState._set_suspicion_from_beliefnet(_suspicion)
	if not is_equal_approx(old_value, _suspicion):
		EventBus.suspicion_changed.emit(old_value, _suspicion)


func _is_suspicion_belief(b: Belief) -> bool:
	return b.subject == PLAYER_ID and _base_weight(b) > 0.0


## Dificultad (preset "decaimiento_sospecha") × aceleración por reputación del jugador (§7.10).
func _player_decay_multiplier() -> float:
	var difficulty: float = Database.get_difficulty_modifier(DIFFICULTY_DECAY_KEY)
	return difficulty * (NEUTRAL_MULTIPLIER + _bal_f(B_MOD_DECAIMIENTO_REP) * _player_reputation)


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


func _bal_dict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(path)
	return value if value is Dictionary else {}
