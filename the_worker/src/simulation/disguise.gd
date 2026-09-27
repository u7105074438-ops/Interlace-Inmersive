# disguise.gd — Disfraces y gestión de identidad (§11.4, §5.3, PASO 38): uniformes, distancia, coherencia de hora y zona, cámaras y pasamontañas.
# PROPIETARIO DE: nada (biblioteca estática; el disfraz puesto es de PlayerState, las grabaciones y el registro de accesos de Security).
# ESCUCHA: nada.
class_name Disguise
extends RefCounted

## Manual §11.4, §5.3, §4.3, §22.3, PASO 38; BUILD_NOTES §12-§13. Balance: disfraz.*,
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
##  · COHERENCIA: el uniforme vale en sus ventanas {desde, hasta, plantas} (disfraz.uniformes); fuera
##    de ellas es incoherente a cualquier distancia: × factor_incoherente (> 1) y suspicious = true
##    (Perception lo hace digno de atención). Un limpiador en P16 a las 14:00 es más sospechoso que
##    el jugador sin disfraz; a las 20:00 no.
##  · PASAMONTAÑAS (§4.3): ocupa el hueco de disfraz (PlayerState.set_disguise(BALACLAVA)). Oculta
##    SIEMPRE la identidad (nadie lo reconoce, a ninguna distancia); dentro del edificio es
##    incoherente (× factor_pasamontanas_edificio), fuera × factor_pasamontanas_exterior. Las cámaras
##    graban "uniform:balaclava" (Security/BeliefNet ya usan get_disguise()).
##  · CÁMARAS: graban el uniforme, no la identidad (camera_subject() = "uniform:<id>"), SALVO que una
##    investigación en fase 2 (evidence_collection) cruce el registro de accesos con el cuadrante de
##    turnos (investigations.json procedures cross_check_uniforms_with_shift_roster): si la tarjeta
##    del jugador consta esa jornada (Security.get_access_log), la grabación se le atribuye con
##    certeza seguridad.certeza_cruce_uniforme. resolve_footage_identity() aplica esa misma regla
##    (Security la ejecuta por su cuenta en la fase 2; esta función es para UI, informes y tests).
##  · Perception ya invoca detection_factor(npc_id, distance_m, room_id) (hora de GameClock,
##    uniforme de PlayerState). sighting_subject() da el sujeto de una creencia de avistamiento:
##    "player" si la identidad es visible, si no "uniform:<id>" (o BeliefNet.UNKNOWN_SUBJECT con
##    pasamontañas).
##  · Obtener un uniforme (vestuarios de S1/S3, interactable uniform_locker): take_uniform() lo mete
##    en el inventario y emite crime_committed("theft_small", sala, {item_id, value, uniform: true}).
##    Es un objeto comprometedor: un registro corporal lo convierte en evidencia definitiva (peso 10,
##    §11.3). Ser VISTO robándolo = flagrancia: el mundo marca el acto (Player.begin_act
##    "theft_small") y Perception emite player_caught_redhanded con certeza plena.
##  · wear()/take_off(): ponerse exige tenerlo (has_item: llevado o entregado por el puesto; el
##    pasamontañas, llevarlo encima). grants_access(uniform, sala): etiquetas de rol de
##    mapa.uniformes contra special_access de la sala y mapa.acceso_por_etiqueta (mapa/HUD).

const BALACLAVA := "balaclava"
const SUBJECT_UNIFORM_PREFIX := InvestigationEngine.SUBJECT_UNIFORM_PREFIX
const PLAYER_SUBJECT := InvestigationEngine.SUBJECT_PLAYER
const CRIME_THEFT := "theft_small"
const PHASE_EVIDENCE_ID := "evidence_collection"
const CROSS_CHECK_PATH := "evidence_collection.cross_check_uniforms_with_shift_roster"
const HOURS_PER_DAY := 24
const TRAIT_PERCEPTION := "perception"
const K_WINDOWS := "ventanas"
const K_FROM := "desde"
const K_TO := "hasta"
const K_FLOORS := "plantas"
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

const B_UNIFORMS := "disfraz.uniformes"
const B_ALIASES := "disfraz.alias_uniforme"
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
const B_MAP_UNIFORMS := "mapa.uniformes"
const B_TAG_ACCESS := "mapa.acceso_por_etiqueta"


# ─── Evaluación (§11.4) ───────────────────────────────────────

## Efecto de `uniform` a la hora `hour` en `room_id` ante `observer_npc` a `distance` metros.
static func evaluate(uniform: String, hour: int, room_id: String, distance: float,
		observer_npc: NPCRuntime = null) -> Dictionary:
	var floor_number: int = room_floor(room_id)
	if uniform == BALACLAVA:
		return _balaclava_result(floor_number)
	var canonical: String = canonical_uniform(uniform)
	if canonical.is_empty() or is_own_uniform(canonical) or _no_effect_floor(floor_number):
		return _result(false, 1.0, false, true)
	var coherent: bool = is_coherent(canonical, hour, floor_number)
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
	var result: Dictionary = evaluate(PlayerState.get_disguise(), GameClock.get_hour(), room_id,
			distance_m, NPCDirector.get_npc(npc_id) if not npc_id.is_empty() else null)
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


## El uniforme cuadra con la hora y la planta (alguna ventana de disfraz.uniformes lo cubre).
static func is_coherent(uniform: String, hour: int, floor_number: int) -> bool:
	var data: Variant = _uniform_data(canonical_uniform(uniform))
	if not data is Dictionary:
		return false
	for window: Variant in (data as Dictionary).get(K_WINDOWS, []):
		if window is Dictionary and _window_covers(window, hour, floor_number):
			return true
	return false


# ─── Identidad, cámaras y creencias ───────────────────────────

## Sujeto de una grabación de cámara ahora mismo (§5.3): el uniforme, no la identidad.
static func camera_subject() -> String:
	var uniform: String = PlayerState.get_disguise()
	return PLAYER_SUBJECT if uniform.is_empty() else SUBJECT_UNIFORM_PREFIX + uniform


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
	var result: Dictionary = evaluate(uniform, GameClock.get_hour(), room_id, distance_m,
			NPCDirector.get_npc(npc_id) if not npc_id.is_empty() else null)
	if not bool(result[R_HIDDEN]):
		return PLAYER_SUBJECT
	return BeliefNetSystem.UNKNOWN_SUBJECT if uniform == BALACLAVA \
			else SUBJECT_UNIFORM_PREFIX + uniform


static func is_masked() -> bool:
	return PlayerState.get_disguise() == BALACLAVA


# ─── Acciones de "manos" ──────────────────────────────────────

## Coge un uniforme de su taquilla (vestuario). false si no es un uniforme o no cabe.
static func take_uniform(uniform_id: String, room_id: String) -> bool:
	if canonical_uniform(uniform_id) != uniform_id or not PlayerState.add_item(uniform_id):
		return false
	var item: ItemData = Database.get_item(uniform_id)
	EventBus.crime_committed.emit(CRIME_THEFT, room_id, {"item_id": uniform_id,
			"value": item.value if item != null else 0, "uniform": true})
	return true


## Se pone el uniforme (o el pasamontañas). false si no lo tiene.
static func wear(uniform_id: String) -> bool:
	var owned: bool = PlayerState.is_carrying(uniform_id) if uniform_id == BALACLAVA \
			else PlayerState.has_item(uniform_id)
	if not owned or (uniform_id != BALACLAVA and canonical_uniform(uniform_id).is_empty()):
		return false
	PlayerState.set_disguise(uniform_id)
	return true


static func take_off() -> void:
	PlayerState.set_disguise("")


## El uniforme abre la sala por su rol (mapa.uniformes → special_access / acceso_por_etiqueta).
static func grants_access(uniform_id: String, room_id: String) -> bool:
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(room_id))
	var tags: Variant = _balance_dict(B_MAP_UNIFORMS).get(uniform_id, [])
	if room == null or not tags is Array:
		return false
	for tag: Variant in tags:
		if room.special_access.has(str(tag)) or _tag_covers(str(tag), room, room_floor(room_id)):
			return true
	return false


# ─── Datos ────────────────────────────────────────────────────

## Id canónico del uniforme (alias de herramienta de puesto → uniforme de vestuario); "" si no es
## uno de los tres uniformes.
static func canonical_uniform(uniform_id: String) -> String:
	var aliases: Dictionary = _balance_dict(B_ALIASES)
	var id: String = str(aliases.get(uniform_id, uniform_id))
	return id if _balance_dict(B_UNIFORMS).has(id) else ""


static func get_uniform_ids() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _balance_dict(B_UNIFORMS):
		if not str(key).begins_with("_"):
			out.append(str(key))
	return out


## El uniforme es del puesto actual del jugador (no es un disfraz).
static func is_own_uniform(uniform_id: String) -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	if occupation == null:
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


static func _balaclava_result(floor_number: int) -> Dictionary:
	if _no_effect_floor(floor_number):
		return _result(true, Database.get_balance_float(B_MASK_OUTSIDE), false, true)
	return _result(true, Database.get_balance_float(B_MASK_BUILDING), false, false)


static func _result(hidden: bool, factor: float, recognised: bool, coherent: bool) -> Dictionary:
	return {R_HIDDEN: hidden, R_MULTIPLIER: factor, R_RECOGNISED: recognised,
			R_COHERENT: coherent, R_SUSPICIOUS: not coherent, R_FACTOR: factor}


static func _window_covers(window: Dictionary, hour: int, floor_number: int) -> bool:
	var floors: Variant = window.get(K_FLOORS, [])
	if not floors is Array or (floors as Array).size() < 2:
		return false
	if floor_number < int(floors[0]) or floor_number > int(floors[1]):
		return false
	var from_hour: int = int(window.get(K_FROM, 0))
	var to_hour: int = int(window.get(K_TO, HOURS_PER_DAY))
	var h: int = posmod(hour, HOURS_PER_DAY)
	if from_hour <= to_hour:
		return h >= from_hour and h < to_hour
	return h >= from_hour or h < to_hour


static func _no_effect_floor(floor_number: int) -> bool:
	var floors: Variant = Database.get_balance(B_NO_EFFECT_FLOORS)
	return floors is Array and _has_int(floors, floor_number)


static func _tag_covers(tag: String, room: RoomData, floor_number: int) -> bool:
	var rule: Variant = _balance_dict(B_TAG_ACCESS).get(tag, {})
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


static func _uniform_data(uniform_id: String) -> Variant:
	return _balance_dict(B_UNIFORMS).get(uniform_id, null)


static func _balance_dict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(path) if Database.has_balance(path) else {}
	return value if value is Dictionary else {}
