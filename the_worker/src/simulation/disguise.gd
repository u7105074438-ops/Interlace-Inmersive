# disguise.gd — Disfraces y gestión de identidad (§11.4, §5.3, PASO 38): uniformes, distancia, coherencia de hora y zona, cámaras y pasamontañas.
# PROPIETARIO DE: nada (biblioteca estática; el disfraz puesto es de PlayerState, las grabaciones y el registro de accesos de Security). Solo una caché de las tablas disfraz.* por fotograma.
# ESCUCHA: nada.
class_name Disguise
extends RefCounted

## Manual §11.4, §5.2, §5.3, §4.3, §22.3, PASO 38; BUILD_NOTES §12-§13. Balance: disfraz.*,
## percepcion.distancia_clasificacion_uniforme / distancia_reconocimiento_disfraz.
## DECISIONES (contrato para Perception, el mundo y la interfaz):
##  · evaluate(uniform, hour, room_id, distance, observer_npc) -> {identity_hidden, suspicion_multiplier,
##    recognised, coherent, suspicious, detection_factor}. suspicion_multiplier (= detection_factor)
##    multiplica la velocidad de llenado de Perception: 0 = invisible, 1 = como sin disfraz, > 1 = más
##    sospechoso que sin disfraz. Sin disfraz (""), con el uniforme del PROPIO puesto (tools de la
##    ocupación del jugador: no es un disfraz) o un uniforme en una planta de disfraz.plantas_sin_efecto
##    (exterior): neutro {false, 1.0, false}.
##  · Distancia d (metros): d > distancia_clasificacion_uniforme → el observador clasifica por el
##    uniforme (identidad oculta): coherente × factor_lejos_coherente (un limpiador a las 20:00 es
##    invisible). d < distancia_reconocimiento_disfraz → quien conoce al jugador
##    (NPCDirector.knows_player) o tiene perspicacia efectiva > disfraz.perspicacia_reconocimiento lo
##    RECONOCE: identidad visible, × factor_reconocido (× factor_incoherente si además es
##    incoherente); los demás, × factor_cerca_coherente. Entre ambas: interpolación lineal cerca → lejos,
##    sin reconocimiento. Un observador que no es personaje de NPCDirector (sintético) usa su rasgo.
##  · COHERENCIA: el uniforme vale en sus ventanas {desde, hasta, plantas, excluir_despachos}
##    (disfraz.uniformes); fuera de ellas es incoherente a cualquier distancia: × factor_incoherente
##    (> 1) y suspicious = true. Un limpiador en P16 a las 14:00 es más sospechoso que el jugador sin
##    disfraz; a las 20:00 no. El vigilante (§5.2 «no permanecer en despachos») es incoherente en los
##    despachos (disfraz.despachos) en horario de oficina: solo su ronda nocturna los cubre.
##    is_coherent() sin sala no aplica esa exclusión (solo hora y planta).
##  · PASAMONTAÑAS (§4.3; id en disfraz.pasamontanas, balaclava_id()): ocupa el hueco de disfraz
##    (PlayerState.set_disguise). Oculta SIEMPRE la identidad (nadie lo reconoce, a ninguna
##    distancia); dentro del edificio es incoherente (× factor_pasamontanas_edificio), fuera
##    × factor_pasamontanas_exterior. Las cámaras graban "uniform:balaclava".
##  · Quitar el objeto (venderlo, esconderlo, desecharlo, requisa, perder el puesto que lo entrega)
##    quita el disfraz: PlayerState lo comprueba en cada salida del inventario.
##  · CÁMARAS: graban el uniforme, no la identidad (camera_subject() = "uniform:<id>"; con el
##    uniforme del propio puesto, "player"), SALVO que una investigación en fase 2
##    (evidence_collection) cruce el registro de accesos con el cuadrante de turnos
##    (cross_check_uniforms_with_shift_roster): si la tarjeta del jugador consta esa jornada, la
##    grabación se le atribuye con certeza seguridad.certeza_cruce_uniforme. Security ejecuta ese
##    cruce en su fase 2 (_review_footage); resolve_footage_identity() da la misma respuesta para
##    la interfaz y los informes.
##  · Perception invoca evaluate() / detection_factor(npc_id, distance_m, room_id) (hora de GameClock,
##    uniforme de PlayerState). sighting_subject() da el sujeto de una creencia de avistamiento:
##    "player" si la identidad es visible, si no "uniform:<id>" (o BeliefNet.UNKNOWN_SUBJECT con
##    pasamontañas). Las tablas disfraz.* se leen una vez por fotograma (clear_cache() las fuerza).
##  · Obtener un uniforme: take_uniform(uniforme, sala, testigos) solo en una sala con un
##    interactable uniform_locker de ESE uniforme (vestuarios de S1/S3, taquillas de P15). Lo mete en
##    el inventario y emite crime_committed("theft_small", sala, {item_id, value, uniform: true,
##    witnessed}). Es un objeto comprometedor (registro corporal = evidencia definitiva, §11.3). SER
##    VISTO sacándolo (§22.3) = evidencia definitiva: por cada testigo on_uniform_theft_witnessed()
##    crea su creencia de flagrancia y una pieza compromising_item (peso
##    investigaciones.pesos_evidencia.objeto_comprometedor) contra el jugador en el caso de la sala
##    (Security.report_incident con el disparador de seguridad.incidentes_por_delito.theft_small),
##    ligada a esa creencia (silenciar al testigo la retira). El mundo pasa los testigos del instante
##    (Perception.witnesses_of) o llama a on_uniform_theft_witnessed si la flagrancia llega después.
##  · wear()/take_off(): ponerse exige tenerlo (has_item: llevado o entregado por el puesto; el
##    pasamontañas, llevarlo encima). grants_access(uniform, sala): etiquetas de rol de
##    mapa.uniformes contra special_access de la sala y mapa.acceso_por_etiqueta (mapa/HUD).

## Id por defecto del pasamontañas (el real: balance disfraz.pasamontanas, balaclava_id()).
const BALACLAVA := "balaclava"
const SUBJECT_UNIFORM_PREFIX := InvestigationEngine.SUBJECT_UNIFORM_PREFIX
const PLAYER_SUBJECT := InvestigationEngine.SUBJECT_PLAYER
const CRIME_THEFT := "theft_small"
const LOCKER_TYPE := "uniform_locker"
const LOCKER_UNIFORM_KEY := "uniform"
const PHASE_EVIDENCE_ID := "evidence_collection"
const CROSS_CHECK_PATH := "evidence_collection.cross_check_uniforms_with_shift_roster"
const HOURS_PER_DAY := 24
const NEUTRAL_FACTOR := 1.0
const TRAIT_PERCEPTION := "perception"
const K_WINDOWS := "ventanas"
const K_FROM := "desde"
const K_TO := "hasta"
const K_FLOORS := "plantas"
const K_EXCLUDE_OFFICES := "excluir_despachos"
const K_FLOORS_TAG := "floors"
const K_ROOMS_TAG := "rooms"
const K_MAX_CLEARANCE := "max_room_clearance"
# Claves del resultado de evaluate().
const R_HIDDEN := "identity_hidden"
const R_MULTIPLIER := "suspicion_multiplier"
const R_RECOGNISED := "recognised"
const R_COHERENT := "coherent"
const R_SUSPICIOUS := "suspicious"
const R_FACTOR := "detection_factor"
# Claves de la caché por fotograma.
const C_UNIFORMS := "uniforms"
const C_ALIASES := "aliases"
const C_NO_EFFECT := "no_effect"
const C_OFFICES := "offices"
const C_BALACLAVA := "balaclava"
const C_MAP_UNIFORMS := "map_uniforms"
const C_TAG_ACCESS := "tag_access"

const B_UNIFORMS := "disfraz.uniformes"
const B_ALIASES := "disfraz.alias_uniforme"
const B_BALACLAVA := "disfraz.pasamontanas"
const B_OFFICES := "disfraz.despachos"
const B_FAR := "disfraz.factor_lejos_coherente"
const B_NEAR := "disfraz.factor_cerca_coherente"
const B_RECOGNISED := "disfraz.factor_reconocido"
const B_INCOHERENT := "disfraz.factor_incoherente"
const B_MASK_BUILDING := "disfraz.factor_pasamontanas_edificio"
const B_MASK_OUTSIDE := "disfraz.factor_pasamontanas_exterior"
const B_RECOGNITION_PERCEPTION := "disfraz.perspicacia_reconocimiento"
const B_NO_EFFECT_FLOORS := "disfraz.plantas_sin_efecto"
const B_CLASSIFY_DISTANCE := "percepcion.distancia_clasificacion_uniforme"
const B_RECOGNISE_DISTANCE := "percepcion.distancia_reconocimiento_disfraz"
const B_CROSS_CERTAINTY := "seguridad.certeza_cruce_uniforme"
const B_THEFT_INCIDENT := "seguridad.incidentes_por_delito.theft_small"
const B_ITEM_WEIGHT := "investigaciones.pesos_evidencia.objeto_comprometedor"
const B_MAP_UNIFORMS := "mapa.uniformes"
const B_TAG_ACCESS := "mapa.acceso_por_etiqueta"

static var _cache: Dictionary = {}
static var _cache_frame: int = -1


# ─── Evaluación (§11.4) ───────────────────────────────────────

## Efecto de `uniform` a la hora `hour` en `room_id` ante `observer_npc` a `distance` metros.
static func evaluate(uniform: String, hour: int, room_id: String, distance: float,
		observer_npc: NPCRuntime = null) -> Dictionary:
	if uniform.is_empty():
		return _result(false, NEUTRAL_FACTOR, false, true)
	var floor_number: int = room_floor(room_id)
	if uniform == balaclava_id():
		return _balaclava_result(floor_number)
	var canonical: String = canonical_uniform(uniform)
	if canonical.is_empty() or is_own_uniform(canonical) or _no_effect_floor(floor_number):
		return _result(false, NEUTRAL_FACTOR, false, true)
	var coherent: bool = is_coherent(canonical, hour, floor_number, room_id)
	if distance < Database.get_balance_float(B_RECOGNISE_DISTANCE) and recognises(observer_npc):
		var factor: float = Database.get_balance_float(B_RECOGNISED)
		if not coherent:
			factor = maxf(factor, Database.get_balance_float(B_INCOHERENT))
		return _result(false, factor, true, coherent)
	if not coherent:
		return _result(true, Database.get_balance_float(B_INCOHERENT), false, false)
	return _result(true, coherent_factor(distance), false, true)


## Lo que invoca Perception (prefiere esta firma): efecto del disfraz ACTUAL del jugador a esta
## hora ante el personaje `npc_id` ("" = observador genérico) a `distance_m` metros.
static func detection_factor(npc_id: String, distance_m: float, room_id: String) -> float:
	var uniform: String = PlayerState.get_disguise()
	if uniform.is_empty():
		return NEUTRAL_FACTOR
	var result: Dictionary = evaluate(uniform, GameClock.get_hour(), room_id, distance_m,
			NPCDirector.get_npc(npc_id) if not npc_id.is_empty() else null)
	return float(result[R_MULTIPLIER])


## Factor de un uniforme coherente a `distance` metros para quien NO reconoce al jugador.
static func coherent_factor(distance: float) -> float:
	var near: float = Database.get_balance_float(B_RECOGNISE_DISTANCE)
	var far: float = Database.get_balance_float(B_CLASSIFY_DISTANCE)
	var near_factor: float = Database.get_balance_float(B_NEAR)
	var far_factor: float = Database.get_balance_float(B_FAR)
	if distance > far:
		return far_factor
	if distance < near or far <= near:
		return near_factor
	return lerpf(near_factor, far_factor, (distance - near) / (far - near))


## ¿Reconoce este observador al jugador de cerca? (lo conoce o perspicacia > umbral).
static func recognises(observer_npc: NPCRuntime) -> bool:
	if observer_npc == null:
		return false
	var registered: bool = NPCDirector.get_npc(observer_npc.id) == observer_npc
	if registered and NPCDirector.knows_player(observer_npc.id):
		return true
	var perception: int = NPCDirector.get_effective_perception(observer_npc.id) if registered \
			else observer_npc.get_trait(TRAIT_PERCEPTION)
	return perception > Database.get_balance_int(B_RECOGNITION_PERCEPTION)


## El uniforme cuadra con la hora, la planta y (si se da) la sala: alguna ventana de
## disfraz.uniformes lo cubre.
static func is_coherent(uniform: String, hour: int, floor_number: int,
		room_id: String = "") -> bool:
	var data: Variant = (_tables()[C_UNIFORMS] as Dictionary).get(canonical_uniform(uniform))
	if not data is Dictionary:
		return false
	var office: bool = is_office(room_id)
	for window: Variant in (data as Dictionary).get(K_WINDOWS, []):
		if window is Dictionary and _window_covers(window, hour, floor_number, office):
			return true
	return false


## La sala es un despacho (disfraz.despachos; copias "id@planta" por su id base).
static func is_office(room_id: String) -> bool:
	return not room_id.is_empty() \
			and (_tables()[C_OFFICES] as Array).has(DatabaseSystem.get_room_base_id(room_id))


# ─── Identidad, cámaras y creencias ───────────────────────────

## Sujeto de una grabación de cámara ahora mismo (§5.3): el uniforme, no la identidad (con el
## uniforme del propio puesto, o sin disfraz, el jugador).
static func camera_subject() -> String:
	var uniform: String = PlayerState.get_disguise()
	if uniform.is_empty():
		return PLAYER_SUBJECT
	if uniform != balaclava_id() and is_own_uniform(canonical_uniform(uniform)):
		return PLAYER_SUBJECT
	return SUBJECT_UNIFORM_PREFIX + uniform


## Regla de identidad de una grabación {subject, day, ...} (Security.get_footage_list) en una
## investigación en `phase`: {subject, certainty, crossed}. Ver DECISIONES.
static func resolve_footage_identity(footage: Dictionary, phase: int) -> Dictionary:
	var subject: String = str(footage.get("subject", ""))
	var out: Dictionary = {"subject": subject, "certainty": Investigation.FULL_CERTAINTY,
			"crossed": false}
	if not subject.begins_with(SUBJECT_UNIFORM_PREFIX) or phase < evidence_phase():
		return out
	if not bool(InvestigationEngine.dig(Database.get_investigation_params(), CROSS_CHECK_PATH,
			false)):
		return out
	for access: Dictionary in Security.get_access_log():
		if str(access.get("card_owner", "")) == PLAYER_SUBJECT \
				and int(access.get("day", -1)) == int(footage.get("day", -2)):
			return {"subject": PLAYER_SUBJECT,
					"certainty": Database.get_balance_float(B_CROSS_CERTAINTY), "crossed": true}
	return out


## Número de la fase de recogida de pruebas (investigations.json phases, id evidence_collection).
static func evidence_phase() -> int:
	var phase: Dictionary = InvestigationEngine.find_by_id(
			Database.get_investigation_params().get("phases", []), PHASE_EVIDENCE_ID)
	return int(phase.get("number", 0))


## Sujeto de la creencia de un avistamiento del jugador disfrazado (para Perception/BeliefNet).
static func sighting_subject(npc_id: String, distance_m: float, room_id: String) -> String:
	var uniform: String = PlayerState.get_disguise()
	if uniform.is_empty():
		return PLAYER_SUBJECT
	var result: Dictionary = evaluate(uniform, GameClock.get_hour(), room_id, distance_m,
			NPCDirector.get_npc(npc_id) if not npc_id.is_empty() else null)
	if not bool(result[R_HIDDEN]):
		return PLAYER_SUBJECT
	return BeliefNetSystem.UNKNOWN_SUBJECT if uniform == balaclava_id() \
			else SUBJECT_UNIFORM_PREFIX + uniform


static func is_masked() -> bool:
	var uniform: String = PlayerState.get_disguise()
	return not uniform.is_empty() and uniform == balaclava_id()


# ─── Acciones de "manos" ──────────────────────────────────────

## Coge un uniforme de su taquilla (sala con un uniform_locker de ese uniforme). `witness_ids`:
## quienes lo ven sacarlo (evidencia definitiva, §22.3). false si no hay taquilla o no cabe.
static func take_uniform(uniform_id: String, room_id: String,
		witness_ids: Array[String] = []) -> bool:
	if canonical_uniform(uniform_id) != uniform_id or not has_locker(room_id, uniform_id):
		return false
	if not PlayerState.add_item(uniform_id):
		return false
	var item: ItemData = Database.get_item(uniform_id)
	EventBus.crime_committed.emit(CRIME_THEFT, room_id, {"item_id": uniform_id,
			"value": item.value if item != null else 0, "uniform": true,
			"witnessed": not witness_ids.is_empty()})
	for witness_id: String in witness_ids:
		on_uniform_theft_witnessed(witness_id, room_id)
	return true


## Un testigo vio al jugador sacar un uniforme de su taquilla: creencia de flagrancia y pieza
## definitiva (compromising_item) contra el jugador ligada a ella. Id del caso ("" si ninguno).
static func on_uniform_theft_witnessed(witness_id: String, room_id: String) -> String:
	if witness_id.is_empty():
		return ""
	var belief_id: String = BeliefNet.create_belief(witness_id, PLAYER_SUBJECT,
			BeliefNetSystem.make_fact(BeliefNetSystem.FACT_CAUGHT_REDHANDED, CRIME_THEFT),
			Investigation.FULL_CERTAINTY, Belief.SOURCE_DIRECT, room_id)
	return Security.report_incident(str(Database.get_balance(B_THEFT_INCIDENT)), 0, room_id, true,
			{"subject": PLAYER_SUBJECT, "witness": witness_id,
			"evidence_type": InvestigationEngine.EV_ITEM,
			"weight": Database.get_balance_float(B_ITEM_WEIGHT), "record_id": belief_id,
			"certainty": Investigation.FULL_CERTAINTY})


## La sala tiene una taquilla (uniform_locker) de ese uniforme.
static func has_locker(room_id: String, uniform_id: String) -> bool:
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(room_id)) \
			if not room_id.is_empty() else null
	if room == null:
		return false
	for entry: Dictionary in room.interactables:
		if str(entry.get("type", "")) == LOCKER_TYPE \
				and str(entry.get(LOCKER_UNIFORM_KEY, "")) == uniform_id:
			return true
	return false


## Se pone el uniforme (o el pasamontañas). false si no lo tiene.
static func wear(uniform_id: String) -> bool:
	var mask: bool = uniform_id == balaclava_id()
	var owned: bool = PlayerState.is_carrying(uniform_id) if mask \
			else PlayerState.has_item(uniform_id)
	if not owned or (not mask and canonical_uniform(uniform_id).is_empty()):
		return false
	PlayerState.set_disguise(uniform_id)
	return true


static func take_off() -> void:
	PlayerState.set_disguise("")


## El uniforme abre la sala por su rol (mapa.uniformes → special_access / acceso_por_etiqueta).
static func grants_access(uniform_id: String, room_id: String) -> bool:
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(room_id))
	var tags: Variant = (_tables()[C_MAP_UNIFORMS] as Dictionary).get(uniform_id, [])
	if room == null or not tags is Array:
		return false
	for tag: Variant in tags:
		if room.special_access.has(str(tag)) or _tag_covers(str(tag), room, room_floor(room_id)):
			return true
	return false


# ─── Datos ────────────────────────────────────────────────────

## Id del pasamontañas (disfraz.pasamontanas).
static func balaclava_id() -> String:
	return str(_tables()[C_BALACLAVA])


## Id canónico del uniforme (alias de herramienta de puesto → uniforme de vestuario); "" si no es
## uno de los tres uniformes.
static func canonical_uniform(uniform_id: String) -> String:
	var tables: Dictionary = _tables()
	var id: String = str((tables[C_ALIASES] as Dictionary).get(uniform_id, uniform_id))
	return id if (tables[C_UNIFORMS] as Dictionary).has(id) else ""


static func get_uniform_ids() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _tables()[C_UNIFORMS]:
		if not str(key).begins_with("_"):
			out.append(str(key))
	return out


## El uniforme es del puesto actual del jugador (no es un disfraz).
static func is_own_uniform(uniform_id: String) -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	if occupation == null or uniform_id.is_empty():
		return false
	for tool: String in occupation.tools:
		if canonical_uniform(tool) == uniform_id:
			return true
	return false


## Planta de una sala (copias transversales "id@planta"); sin sala conocida, la del jugador.
static func room_floor(room_id: String) -> int:
	if room_id.contains(DatabaseSystem.INSTANCE_SEPARATOR):
		return room_id.get_slice(DatabaseSystem.INSTANCE_SEPARATOR, 1).to_int()
	var room: RoomData = Database.get_room(room_id) if not room_id.is_empty() else null
	if room == null or room.floor == RoomData.TRANSVERSAL_FLOOR:
		return PlayerState.get_floor()
	return room.floor


## Vacía la caché de tablas (tras recargar Database fuera del ciclo de fotogramas).
static func clear_cache() -> void:
	_cache = {}
	_cache_frame = -1


## Tablas disfraz.* / mapa.* leídas UNA vez por fotograma: Perception evalúa a cada observador en
## cada fotograma y get_balance devuelve copias profundas.
static func _tables() -> Dictionary:
	var frame: int = Engine.get_process_frames()
	if frame == _cache_frame and not _cache.is_empty():
		return _cache
	_cache_frame = frame
	_cache = {C_UNIFORMS: _balance_dict(B_UNIFORMS), C_ALIASES: _balance_dict(B_ALIASES),
			C_NO_EFFECT: _balance_array(B_NO_EFFECT_FLOORS), C_OFFICES: _balance_array(B_OFFICES),
			C_BALACLAVA: str(Database.get_balance(B_BALACLAVA)) if Database.has_balance(B_BALACLAVA)
					else BALACLAVA,
			C_MAP_UNIFORMS: _balance_dict(B_MAP_UNIFORMS), C_TAG_ACCESS: _balance_dict(B_TAG_ACCESS)}
	return _cache


static func _balaclava_result(floor_number: int) -> Dictionary:
	if _no_effect_floor(floor_number):
		return _result(true, Database.get_balance_float(B_MASK_OUTSIDE), false, true)
	return _result(true, Database.get_balance_float(B_MASK_BUILDING), false, false)


static func _result(hidden: bool, factor: float, recognised: bool, coherent: bool) -> Dictionary:
	return {R_HIDDEN: hidden, R_MULTIPLIER: factor, R_RECOGNISED: recognised,
			R_COHERENT: coherent, R_SUSPICIOUS: not coherent, R_FACTOR: factor}


static func _window_covers(window: Dictionary, hour: int, floor_number: int,
		office: bool) -> bool:
	var floors: Variant = window.get(K_FLOORS, [])
	if not floors is Array or (floors as Array).size() < 2:
		return false
	if floor_number < int(floors[0]) or floor_number > int(floors[1]):
		return false
	if office and bool(window.get(K_EXCLUDE_OFFICES, false)):
		return false
	var from_hour: int = int(window.get(K_FROM, 0))
	var to_hour: int = int(window.get(K_TO, HOURS_PER_DAY))
	var h: int = posmod(hour, HOURS_PER_DAY)
	if from_hour <= to_hour:
		return h >= from_hour and h < to_hour
	return h >= from_hour or h < to_hour


static func _no_effect_floor(floor_number: int) -> bool:
	return _has_int(_tables()[C_NO_EFFECT], floor_number)


static func _tag_covers(tag: String, room: RoomData, floor_number: int) -> bool:
	var rule: Variant = (_tables()[C_TAG_ACCESS] as Dictionary).get(tag, {})
	if not rule is Dictionary:
		return false
	var d: Dictionary = rule
	if d.has(K_MAX_CLEARANCE) and room.clearance_required > int(d[K_MAX_CLEARANCE]):
		return false
	if (d.get(K_ROOMS_TAG, []) as Array).has(room.id):
		return true
	return _has_int(d.get(K_FLOORS_TAG, []), floor_number)


## Los números de balance llegan como float (JSON): comparación entera.
static func _has_int(values: Variant, wanted: int) -> bool:
	if values is Array:
		for value: Variant in values:
			if (value is int or value is float) and int(value) == wanted:
				return true
	return false


static func _balance_dict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(path) if Database.has_balance(path) else {}
	return value if value is Dictionary else {}


static func _balance_array(path: String) -> Array:
	var value: Variant = Database.get_balance(path) if Database.has_balance(path) else []
	return value if value is Array else []
