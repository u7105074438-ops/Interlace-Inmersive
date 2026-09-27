# police.gd — Respuesta policial en el exterior (§4.3, §22.16, PASO 39): testigos y creencias fuera del edificio, aviso consolidado, unidad despachada desde la comisaría, llegada, persecución por callejones y cerco.
# PROPIETARIO DE: el aviso en curso (certeza acumulada, sala, identidad conocida, registro enviado al edificio), la unidad despachada (comisaría de origen, minutos hasta la llegada), la persecución (búsqueda, cerco, tramos de callejón, ocultación) y la marca de fin de partida enviada.
# ESCUCHA: npc_reported_player, room_entered, day_advanced, game_over, run_started.
class_name Police
extends Node

## Manual §4.3, §7.10, §12.2, §22.16, PASO 39; BUILD_NOTES §2 (manos), §11 (police_arrived,
## police_evaded), §13. Balance: policia.*. Emite: police_dispatched, police_arrived, police_evaded,
## game_over ("arrested_by_police"), subtitle_posted, notebook_entry_added.
## game_root añade este nodo (grupo GROUP); NightOps y el mundo lo encuentran en ese grupo.
## DECISIONES:
##  · TIEMPO en minutos de juego: el nodo lee GameClock.get_total_minutes() (update() en _process y
##    tras cada acción); las acciones que avanzan el reloj (NightOps: forzar, saquear) consumen el
##    margen de la unidad. La pausa del reloj detiene la persecución. response_time de
##    police_dispatched está en minutos de juego.
##  · MISMA LÓGICA DE TESTIGOS QUE DENTRO: witness_crime(testigo, delito, sala, certeza) crea la
##    creencia del testigo en BeliefNet (certeza >= creencias.certeza_directa_completa →
##    "caught_redhanded:<delito>", si no "seen_partially"). SIN PASAMONTAÑAS (Disguise.is_masked
##    falso) el testigo reconoce al jugador: sujeto "player" y el aviso deja UN registro en el
##    edificio (denuncia policial = stamped_document de peso policia.peso_registro_identificado,
##    BeliefNet.create_record: pesa en la sospecha y Security lo usa como papel). CON pasamontañas
##    la creencia no tiene sujeto determinado (BeliefNet.UNKNOWN_SUBJECT) y no hay registro.
##    Los testigos que ve el mundo (Perception) siguen el flujo normal (flagrancia §12.2, utilidad):
##    si deciden denunciar (npc_reported_player) en una sala exterior, eso es la llamada a la
##    policía (certeza plena si es testigo directo o canal, parcial si partial_witness); sin
##    pasamontañas deja el mismo registro único en el edificio que witness_crime.
##  · AVISO CONSOLIDADO: suma de certezas >= policia.umbral_aviso_consolidado (un testigo directo o
##    varios parciales) o report_alarm() (alarma de una mansión) → dispatch: la unidad sale de
##    policia.sala_comisaria (get_origin(): el mundo la hace aparecer allí y la lleva a
##    get_target() en get_eta() minutos), llegada = minutos_respuesta_base ×
##    factor_respuesta_por_sala[sala] (police_dispatched + subtítulo de sirenas). Un aviso sin consolidar caduca al cambiar de jornada.
##  · LLEGADA (police_arrived(sala del aviso)): jugador aún en esa sala → arresto. Si no, búsqueda
##    de minutos_busqueda. Expuesto (calle, tiendas, viviendas...) consume minutos_cerco: a cero,
##    el cerco se cierra (police_arrived(sala del jugador) + arresto). En callejones (sala con
##    evasion_zone) cada TRAMO (entrar en la zona o esconderse en un escondite distinto con
##    enter_hiding) da minutos_por_callejon, con policia.callejones tramos por persecución: agotar
##    el tramo actual o entrar sin tramos libres cierra el cerco. Los tramos solo cuentan durante
##    la búsqueda: moverse mientras la unidad viene no gasta ninguno (a la llegada, el callejón
##    donde esté el jugador es el primer tramo). salas_refugio (casa) y el interior
##    del edificio ocultan sin límite de tramos SOLO si la identidad no se conoce (con la identidad
##    conocida la policía sabe dónde vives). minutos_evasion ocultos, o el fin de la búsqueda sin
##    ser visto, = evasión (police_evaded). Arresto = game_over("arrested_by_police") con
##    Tracking.evaluate_ending_for_cause / get_snapshot_for_cause (THE FILE, §12.9).
##  · is_active() (unidad en camino o búsqueda) impide dormir (HomeCycle.can_sleep).

const GROUP := "police"
const SAVE_KEY := "Police"
const STATE_IDLE := "idle"
const STATE_ALERTED := "alerted"
const STATE_DISPATCHED := "dispatched"
const STATE_SEARCHING := "searching"
const STATE_ARRESTED := "arrested"
const COVER_EXPOSED := "exposed"
const COVER_ALLEY := "alley"
const COVER_REFUGE := "refuge"
const CAUSE_ARREST := "arrested_by_police"
const PLAYER_ID := BeliefNetSystem.PLAYER_ID
const EVASION_ZONE_KEY := "evasion_zone"
const PARTIAL_REPORT_TYPES: Array[String] = ["partial_witness"]
const NOTE_CATEGORY := "police"
const NOTE_DISPATCHED := "POLICE_NOTE_DISPATCHED"
const NOTE_EVADED := "POLICE_NOTE_EVADED"
const NOTE_IDENTIFIED := "POLICE_NOTE_IDENTIFIED"
const SUB_SIREN := "SUB_POLICE_SIREN"
const SUB_ALARM := "SUB_HOUSE_ALARM"
const SUBTITLE_IMPORTANCE := 2
const EPSILON := 0.0001

const B_STATION := "policia.sala_comisaria"
const B_THRESHOLD := "policia.umbral_aviso_consolidado"
const B_RESPONSE := "policia.minutos_respuesta_base"
const B_RESPONSE_FACTORS := "policia.factor_respuesta_por_sala"
const B_SEARCH := "policia.minutos_busqueda"
const B_CORDON := "policia.minutos_cerco"
const B_ALLEYS := "policia.callejones"
const B_PER_ALLEY := "policia.minutos_por_callejon"
const B_EVASION := "policia.minutos_evasion"
const B_REFUGES := "policia.salas_refugio"
const B_RECORD_WEIGHT := "policia.peso_registro_identificado"
const B_DIRECT := "creencias.certeza_directa_completa"
const B_PARTIAL := "creencias.certeza_parcial"
const B_EXTERIOR_FLOOR := "mundo.planta_exterior"

var _state: String = STATE_IDLE
var _origin: String = ""
var _target: String = ""
var _certainty: float = 0.0
var _identified: bool = false
var _record_id: String = ""
var _eta: float = 0.0
var _search_left: float = 0.0
var _cordon_left: float = 0.0
var _hidden: float = 0.0
var _alleys_used: int = 0
var _alley_left: float = 0.0
var _segment: String = ""
var _last_minutes: float = -1.0
var _game_over_sent: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.npc_reported_player.connect(_on_npc_reported_player)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.game_over.connect(_on_game_over)
	EventBus.run_started.connect(func(_seed: int) -> void: reset_for_new_run())
	reset_for_new_run()
	add_to_group(SaveSystemNode.SCENE_GROUP)
	var saved: Dictionary = SaveSystem.claim_scene_state(SAVE_KEY)
	if not saved.is_empty():
		load_state(saved)


func _process(_delta: float) -> void:
	if is_active():
		update()


## Clave con la que SaveSystem guarda este nodo en la partida (grupo SaveSystemNode.SCENE_GROUP).
func get_save_key() -> String:
	return SAVE_KEY


func reset_for_new_run() -> void:
	_clear_alert()
	_game_over_sent = false


# ─── Testigos y avisos ────────────────────────────────────────

## Un testigo del exterior vio un delito: creencia (con o sin identidad) y aviso a la policía.
## {belief_id, identified, record_id, dispatched}.
func witness_crime(witness_id: String, crime_type: String, location: String,
		certainty: float = -1.0) -> Dictionary:
	var c: float = certainty if certainty > 0.0 else Database.get_balance_float(B_DIRECT)
	var result: Dictionary = record_witness(witness_id, crime_type, location, c,
			_record_id.is_empty())
	if bool(result["identified"]):
		_identified = true
		if not str(result["record_id"]).is_empty():
			_record_id = str(result["record_id"])
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_IDENTIFIED, [_npc_name(witness_id)])
	_add_report(location, c)
	result["dispatched"] = is_active()
	return result


## Creencia del testigo (sin avisar a la policía). Sin pasamontañas: sujeto "player" y, si
## `with_record`, registro en el edificio. {belief_id, identified, record_id}.
static func record_witness(witness_id: String, crime_type: String, location: String,
		certainty: float, with_record: bool) -> Dictionary:
	var identified: bool = not Disguise.is_masked()
	var subject: String = PLAYER_ID if identified else BeliefNetSystem.UNKNOWN_SUBJECT
	var fact: String = BeliefNetSystem.FACT_SEEN_PARTIALLY
	if certainty + EPSILON >= Database.get_balance_float(B_DIRECT):
		fact = BeliefNetSystem.make_fact(BeliefNetSystem.FACT_CAUGHT_REDHANDED, crime_type)
	var belief_id: String = BeliefNet.create_belief(witness_id, subject, fact, certainty,
			Belief.SOURCE_DIRECT, location)
	var record_id: String = ""
	if identified and with_record:
		record_id = BeliefNet.create_record(BeliefNetSystem.RECORD_STAMPED_DOCUMENT, PLAYER_ID,
				Database.get_balance_float(B_RECORD_WEIGHT), location)
	return {"belief_id": belief_id, "identified": identified, "record_id": record_id}


## Alarma (mansión): aviso consolidado en el acto. true si despacha ahora.
func report_alarm(location: String) -> bool:
	EventBus.subtitle_posted.emit(SUB_ALARM, Vector2.INF, SUBTITLE_IMPORTANCE)
	if is_active() or _state == STATE_ARRESTED:
		return false
	dispatch(location)
	return true


## Despacha una unidad desde la comisaría hacia `location` (ignorado si ya hay una en marcha).
func dispatch(location: String) -> void:
	if is_active() or _state == STATE_ARRESTED:
		return
	_reset_pursuit()
	_state = STATE_DISPATCHED
	_origin = station()
	_target = location
	_eta = response_time_for(location)
	_last_minutes = GameClock.get_total_minutes()
	EventBus.police_dispatched.emit(location, _eta)
	EventBus.subtitle_posted.emit(SUB_SIREN, Vector2.INF, SUBTITLE_IMPORTANCE)
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_DISPATCHED, [])


## Sala de la comisaría de la que sale cada unidad (policia.sala_comisaria).
static func station() -> String:
	return str(Database.get_balance(B_STATION))


## Minutos de juego desde la comisaría hasta `location` (base × factor de la sala).
static func response_time_for(location: String) -> float:
	var factors: Variant = Database.get_balance(B_RESPONSE_FACTORS)
	var base_id: String = DatabaseSystem.get_room_base_id(location)
	var factor: float = 1.0
	if factors is Dictionary and (factors as Dictionary).has(base_id):
		factor = float(factors[base_id])
	return Database.get_balance_float(B_RESPONSE) * factor


# ─── Persecución ──────────────────────────────────────────────

## Aplica los minutos de juego transcurridos desde la última llamada (llegada, búsqueda, cerco).
func update() -> void:
	var now: float = GameClock.get_total_minutes()
	if _last_minutes < 0.0 or not is_active():
		_last_minutes = now
		return
	var elapsed: float = now - _last_minutes
	_last_minutes = now
	var left: float = elapsed
	while left > EPSILON and is_active():
		left = _step_dispatched(left) if _state == STATE_DISPATCHED else _step_search(left)


## El jugador se esconde en `spot_id` (contenedor del callejón...): tramo nuevo si es una zona de
## evasión y un escondite distinto del actual.
func enter_hiding(spot_id: String) -> void:
	if not is_active() or not _is_evasion_zone(PlayerState.get_room()):
		return
	update()
	if _state == STATE_SEARCHING:
		_claim_segment(spot_id)


func is_active() -> bool:
	return _state == STATE_DISPATCHED or _state == STATE_SEARCHING


func get_state() -> String:
	return _state


func get_target() -> String:
	return _target


## Comisaría de la que salió la unidad en curso ("" sin unidad).
func get_origin() -> String:
	return _origin


func get_eta() -> float:
	return _eta


func get_alert_certainty() -> float:
	return _certainty


func is_identified() -> bool:
	return _identified


func get_search_minutes_left() -> float:
	return _search_left


func get_cordon_minutes_left() -> float:
	return _cordon_left


func get_hidden_minutes() -> float:
	return _hidden


func get_alleys_left() -> int:
	return maxi(Database.get_balance_int(B_ALLEYS) - _alleys_used, 0)


func get_alley_minutes_left() -> float:
	return _alley_left


## Cobertura del jugador ahora: COVER_EXPOSED | COVER_ALLEY | COVER_REFUGE.
func get_cover() -> String:
	var room: String = PlayerState.get_room()
	if _is_evasion_zone(room):
		return COVER_ALLEY
	if not _identified and _is_refuge(room):
		return COVER_REFUGE
	return COVER_EXPOSED


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	return {
		"state": _state, "origin": _origin, "target": _target, "certainty": _certainty,
		"identified": _identified, "record_id": _record_id, "eta": _eta,
		"search_left": _search_left, "cordon_left": _cordon_left, "hidden": _hidden,
		"alleys_used": _alleys_used, "alley_left": _alley_left, "segment": _segment,
		"game_over_sent": _game_over_sent,
	}


func load_state(data: Dictionary) -> void:
	_state = str(data.get("state", STATE_IDLE))
	_origin = str(data.get("origin", ""))
	_target = str(data.get("target", ""))
	_certainty = float(data.get("certainty", 0.0))
	_identified = bool(data.get("identified", false))
	_record_id = str(data.get("record_id", ""))
	_eta = float(data.get("eta", 0.0))
	_search_left = float(data.get("search_left", 0.0))
	_cordon_left = float(data.get("cordon_left", 0.0))
	_hidden = float(data.get("hidden", 0.0))
	_alleys_used = int(data.get("alleys_used", 0))
	_alley_left = float(data.get("alley_left", 0.0))
	_segment = str(data.get("segment", ""))
	_game_over_sent = bool(data.get("game_over_sent", false))
	_last_minutes = GameClock.get_total_minutes()


# ─── Internos ─────────────────────────────────────────────────

func _add_report(location: String, certainty: float) -> void:
	if is_active() or _state == STATE_ARRESTED or _game_over_sent:
		return
	if _state == STATE_IDLE:
		_state = STATE_ALERTED
		_target = location
	_certainty += certainty
	if _certainty + EPSILON >= Database.get_balance_float(B_THRESHOLD):
		dispatch(_target)


func _step_dispatched(left: float) -> float:
	var used: float = minf(left, _eta)
	_eta -= used
	if _eta <= EPSILON:
		_arrive()
	return left - used


func _arrive() -> void:
	_eta = 0.0
	EventBus.police_arrived.emit(_target)
	if _same_room(PlayerState.get_room(), _target):
		_arrest()
		return
	_state = STATE_SEARCHING
	_search_left = Database.get_balance_float(B_SEARCH)
	_cordon_left = Database.get_balance_float(B_CORDON)
	_hidden = 0.0
	_alleys_used = 0
	_alley_left = 0.0
	_segment = ""


## Un tramo de búsqueda con la cobertura actual hasta el siguiente hito (cerco, fin de tramo,
## evasión o fin de la búsqueda). Devuelve los minutos que quedan por aplicar.
func _step_search(left: float) -> float:
	var cover: String = get_cover()
	if cover == COVER_ALLEY and _segment.is_empty():
		_claim_segment(PlayerState.get_room())
	var dt: float = minf(left, _search_left)
	if cover == COVER_EXPOSED:
		dt = minf(dt, _cordon_left)
	else:
		dt = minf(dt, _evasion_left())
	if cover == COVER_ALLEY:
		dt = minf(dt, _alley_left)
	dt = maxf(dt, 0.0)
	_search_left -= dt
	if cover == COVER_EXPOSED:
		_cordon_left -= dt
	else:
		_hidden += dt
	if cover == COVER_ALLEY:
		_alley_left -= dt
	_resolve_search(cover)
	return left - dt


func _resolve_search(cover: String) -> void:
	if cover == COVER_EXPOSED and _cordon_left <= EPSILON:
		_arrest()
	elif _evasion_left() <= EPSILON or _search_left <= EPSILON:
		_evade()
	elif cover == COVER_ALLEY and _alley_left <= EPSILON:
		_arrest()


func _evasion_left() -> float:
	return Database.get_balance_float(B_EVASION) - _hidden


## Tramo de callejón nuevo (clave distinta de la actual): consume uno de policia.callejones; sin
## tramos libres el tramo no cubre nada (el cerco se cierra en el siguiente paso de búsqueda).
func _claim_segment(key: String) -> void:
	if key == _segment:
		return
	_segment = key
	if _alleys_used >= Database.get_balance_int(B_ALLEYS):
		_alley_left = 0.0
		return
	_alleys_used += 1
	_alley_left = Database.get_balance_float(B_PER_ALLEY)


func _arrest() -> void:
	if _game_over_sent:
		return
	_state = STATE_ARRESTED
	_game_over_sent = true
	var where: String = PlayerState.get_room()
	if not _same_room(where, _target):
		EventBus.police_arrived.emit(where)
	EventBus.game_over.emit(CAUSE_ARREST, Tracking.evaluate_ending_for_cause(CAUSE_ARREST),
			Tracking.get_snapshot_for_cause(CAUSE_ARREST))


func _evade() -> void:
	_clear_alert()
	EventBus.police_evaded.emit()
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_EVADED, [])


func _clear_alert() -> void:
	_state = STATE_IDLE
	_origin = ""
	_target = ""
	_certainty = 0.0
	_identified = false
	_record_id = ""
	_reset_pursuit()


func _reset_pursuit() -> void:
	_eta = 0.0
	_search_left = 0.0
	_cordon_left = 0.0
	_hidden = 0.0
	_alleys_used = 0
	_alley_left = 0.0
	_segment = ""
	_last_minutes = -1.0


func _is_evasion_zone(room_id: String) -> bool:
	var room: RoomData = _room(room_id)
	return room != null and bool(room.extra.get(EVASION_ZONE_KEY, false))


## Casa (policia.salas_refugio) o cualquier sala del edificio (no exterior).
func _is_refuge(room_id: String) -> bool:
	var room: RoomData = _room(room_id)
	if room == null:
		return false
	var refuges: Variant = Database.get_balance(B_REFUGES)
	if refuges is Array and (refuges as Array).has(room.id):
		return true
	return not _is_exterior(room_id)


static func _is_exterior(room_id: String) -> bool:
	var room: RoomData = _room(room_id)
	return room != null and room.floor == Database.get_balance_int(B_EXTERIOR_FLOOR)


static func _room(room_id: String) -> RoomData:
	if room_id.is_empty():
		return null
	return Database.get_room(DatabaseSystem.get_room_base_id(room_id))


static func _same_room(a: String, b: String) -> bool:
	return not a.is_empty() and DatabaseSystem.get_room_base_id(a) \
			== DatabaseSystem.get_room_base_id(b)


static func _npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.name if npc != null and not npc.name.is_empty() else npc_id


# ─── Oyentes ──────────────────────────────────────────────────

## Un testigo del mundo decidió denunciar (§12.2 inacción, utilidad) estando el jugador fuera:
## eso es la llamada a la policía.
func _on_npc_reported_player(npc_id: String, report_type: String, _weight: float,
		location: String) -> void:
	if not _is_exterior(location) or _state == STATE_ARRESTED or _game_over_sent:
		return
	var partial: bool = PARTIAL_REPORT_TYPES.has(report_type)
	if not Disguise.is_masked():
		_note_identified(npc_id, location)
	_add_report(location, Database.get_balance_float(B_PARTIAL if partial else B_DIRECT))


## Un testigo del mundo reconoció al jugador: UN registro (denuncia policial) por aviso.
func _note_identified(witness_id: String, location: String) -> void:
	_identified = true
	if _record_id.is_empty():
		_record_id = BeliefNet.create_record(BeliefNetSystem.RECORD_STAMPED_DOCUMENT, PLAYER_ID,
				Database.get_balance_float(B_RECORD_WEIGHT), location)
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_IDENTIFIED, [_npc_name(witness_id)])


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if not by_player or not is_active():
		return
	update()
	if _state != STATE_SEARCHING:
		return
	if _is_evasion_zone(room_id):
		_claim_segment(room_id)
	else:
		_segment = ""


## Un aviso sin consolidar no sobrevive a la noche.
func _on_day_advanced(_day_number: int) -> void:
	if _state == STATE_ALERTED:
		_clear_alert()


func _on_game_over(_cause: String, _ending_id: String, _snapshot: Dictionary) -> void:
	_game_over_sent = true
	if is_active():
		_state = STATE_IDLE
