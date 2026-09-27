# night_ops.gd — Noche avanzada (§4.3, §22.16, PASO 39): seguir a un trabajador hasta su domicilio, allanar y saquear las tres tipologías de vivienda, eliminar al residente en casa y huir antes de la policía.
# PROPIETARIO DE: la operación nocturna en curso (personaje, vivienda, entrada, alarma, residente despierto, testigos, objetos y valor saqueados, lo que no cupo en cada contenedor, llegada de la seguridad privada) y su RNG. El estado de saqueo de cada casa es de NPCDirector.
# ESCUCHA: day_advanced, game_over, run_started.
class_name NightOps
extends Node

## Manual §4.3, §12.2, §13.4, §22.16, PASO 39; BUILD_NOTES §2 (manos), §13. Balance: noche.*.
## Emite: crime_committed ("burglary", "elimination"), notebook_entry_added. Usa Police (grupo
## Police.GROUP) para los testigos y la respuesta policial.
## Contrato para el mundo (InteractionRouter / diálogo de seguimiento):
##   can_follow(npc) → follow_home(npc) | can_visit(npc) → visit_home(npc) → cargar la planta
##   exterior y situar al jugador en la vivienda (room_entered) → break_in(método) →
##   loot_container(id) × N /
##   eliminate_resident(testigos_con_línea_de_visión) → leave_house() al salir → huir (Police).
## DECISIONES:
##  · DOMICILIO CONOCIDO (knows_home_address): nivel de expediente del puesto >=
##    expedientes.nivel_seccion.home (N6-N7) o acceso completo a SU expediente por la misma regla
##    que PERSONNEL (PlayerState.get_full_file_access_reason: puesto de RR. HH. con
##    personnel_files_full, §23 hr_assistant «domicilios de toda la plantilla»; intrusión en
##    RR. HH.; chantaje = agravio "blackmailed"). Sin eso no hay operación.
##  · follow_home (can_follow): en las franjas noche.franjas_seguimiento y solo si su agenda lo
##    sitúa saliendo (noche.salas_salida: tornos, recepción, garaje), fuera del edificio (planta
##    exterior) o ya en casa: a quien sigue trabajando (el vigilante de noche en la sala de
##    monitores) no se le sigue (ERR_NOT_LEAVING). visit_home (can_visit): ir por tu cuenta al
##    domicilio conocido en esas franjas; el residente está si NPCDirector.is_at_home. Ambos
##    avanzan el reloj noche.minutos_seguimiento. Seguido: está en casa si su agenda lo pone fuera.
##  · PASAMONTAÑAS (§4.3 «Exige el uso de pasamontañas, adquirido previamente»): con
##    noche.exige_pasamontanas, break_in y eliminate_resident exigen llevarlo puesto
##    (ERR_NO_BALACLAVA). Quitárselo dentro es posible: cada testigo usa la identidad del momento.
##  · Tipología = noche.viviendas.<sala> (humble | semi | mansion): contenedores = interactables de
##    la sala (data/rooms/exterior.json) de tipo noche.tipos_contenedor con contains; requires
##    (key/combination) exige llevar una herramienta de noche.requisitos_contenedor. Cada objeto de
##    contains aparece con prob_objeto y cada contenedor tira botin_extra (tabla de la tipología).
##    El efectivo pasa al capital (PlayerState.add_item). Lo que no cabe se queda en el contenedor
##    (op.left): volver a saquearlo en la misma operación devuelve esos objetos sin tirar de nuevo.
##    Solo un contenedor vaciado del todo → NPCDirector.mark_house_container_looted (vacío
##    noche.dias_reposicion_botin); uno con restos no queda marcado y otra noche vuelve a tirar su
##    tabla (los restos siguen ahí en valor esperado).
##  · Riesgos: entrada (illegitimate_entries de la sala; forced_lock exige herramienta de forzar)
##    → un vecino (rol noche.rol_vecino) la nota con prob_vecino_entrada × factor_ruido_entrada
##    (testigo PARCIAL); residente en casa despierta con prob_despertar_residente en cada acción
##    ruidosa (testigo DIRECTO: aviso consolidado); mansión: alarma al entrar = Police.report_alarm
##    y la seguridad privada (rol noche.rol_seguridad_privada) llega minutos_seguridad_privada
##    después y se queda: testigo directo en cuanto el jugador esté DENTRO (PlayerState.get_room
##    = la vivienda); si salió sin leave_house no lo ve. Cada testigo pasa por
##    Police.witness_crime (con o sin identidad según el pasamontañas).
##  · leave_house(): emite UNA vez crime_committed("burglary", vivienda, {npc_id, value, items,
##    method, leaves_record}); leaves_record = algún testigo reconoció al jugador (sin pasamontañas
##    el aviso llega al edificio: Security abre object_missing; con él, no). Tracking suma value.
##  · eliminate_resident(witness_ids): como §12.2, deshabilitada con testigos (los que pase el mundo
##    y la seguridad privada ya dentro; el vecino que oyó la entrada no ve el interior). Retira al
##    personaje (NPCDirector.remove_npc "eliminated", cuerpo en la vivienda) y emite
##    crime_committed("elimination", vivienda, {npc_id, at_home: true, leaves_record: false}).
##  · Una operación abierta al cambiar de jornada o al terminar la partida se cierra sola.

const GROUP := "night_ops"
const SAVE_KEY := "NightOps"
const RNG_SALT := "night_ops"
const CRIME_BURGLARY := "burglary"
const CRIME_ELIMINATION := "elimination"
const CAUSE_ELIMINATED := "eliminated"
const ENTRY_FORCED := "forced_lock"
const ERR_BUSY := "busy"
const ERR_UNKNOWN_NPC := "unknown_npc"
const ERR_NO_HOME := "no_home"
const ERR_ADDRESS_UNKNOWN := "address_unknown"
const ERR_WRONG_TIME := "wrong_time"
const ERR_NO_OPERATION := "no_operation"
const ERR_ALREADY_INSIDE := "already_inside"
const ERR_BAD_ENTRY := "bad_entry"
const ERR_NO_TOOL := "no_tool"
const ERR_NOT_INSIDE := "not_inside"
const ERR_UNKNOWN_CONTAINER := "unknown_container"
const ERR_EMPTY := "empty"
const ERR_LOCKED := "locked"
const ERR_NOT_HOME := "not_home"
const ERR_WITNESSES := "witnesses"
const ERR_NOT_LEAVING := "not_leaving"
const ERR_NO_BALACLAVA := "no_balaclava"
const ERR_KEY_FORMAT := "NIGHT_ERR_%s"
const NOTE_CATEGORY := "night"
const NOTE_FOLLOWED := "NIGHT_NOTE_FOLLOWED"
const NOTE_BURGLARY := "NIGHT_NOTE_BURGLARY"
const NOTE_ELIMINATED := "NIGHT_NOTE_ELIMINATED"
const NO_TIME := -1.0
# Campos de la operación.
const K_NPC := "npc_id"
const K_HOUSE := "house"
const K_FOLLOWED := "followed"
const K_ENTERED := "entered"
const K_METHOD := "method"
const K_ALARM := "alarm"
const K_AWAKE := "resident_awake"
const K_VALUE := "value"
const K_ITEMS := "items"
const K_LOOTED := "looted"
const K_WITNESSES := "witnesses"
const K_INSIDE_WITNESSES := "inside_witnesses"
const K_IDENTIFIED := "identified"
const K_SECURITY_AT := "security_at"
const K_ELIMINATED := "eliminated"
const K_LEFT := "left"
# Claves de noche.viviendas.<sala>.
const H_TYPE := "tipo"
const H_ITEM_CHANCE := "prob_objeto"
const H_EXTRA := "botin_extra"
const H_MINUTES := "minutos_por_contenedor"
const H_WAKE := "prob_despertar_residente"
const H_NEIGHBOUR := "prob_vecino_entrada"
const H_ALARM := "alarma"
const H_SECURITY := "seguridad_privada"
const H_SECURITY_MINUTES := "minutos_seguridad_privada"
const E_ITEM := "objeto"
const E_CHANCE := "prob"

const B_HOME_LEVEL := "expedientes.nivel_seccion.home"
const B_FOLLOW_BANDS := "noche.franjas_seguimiento"
const B_FOLLOW_MINUTES := "noche.minutos_seguimiento"
const B_ENTRY_MINUTES := "noche.minutos_entrada"
const B_ENTRY_TOOLS := "noche.herramientas_entrada"
const B_ENTRY_NOISE := "noche.factor_ruido_entrada"
const B_CONTAINER_TYPES := "noche.tipos_contenedor"
const B_REQUIREMENTS := "noche.requisitos_contenedor"
const B_HOUSES := "noche.viviendas"
const B_NEIGHBOUR_ROLE := "noche.rol_vecino"
const B_SECURITY_ROLE := "noche.rol_seguridad_privada"
const B_NEEDS_MASK := "noche.exige_pasamontanas"
const B_EXIT_ROOMS := "noche.salas_salida"
const B_EXTERIOR_FLOOR := "mundo.planta_exterior"
const B_DIRECT := "creencias.certeza_directa_completa"
const B_PARTIAL := "creencias.certeza_parcial"

var _op: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.game_over.connect(func(_c: String, _e: String, _s: Dictionary) -> void: _op = {})
	EventBus.run_started.connect(func(_seed: int) -> void: reset_for_new_run())
	reset_for_new_run()
	add_to_group(SaveSystemNode.SCENE_GROUP)
	var saved: Dictionary = SaveSystem.claim_scene_state(SAVE_KEY)
	if not saved.is_empty():
		load_state(saved)


func _process(_delta: float) -> void:
	if is_active():
		update()


func get_save_key() -> String:
	return SAVE_KEY


func reset_for_new_run() -> void:
	_op = {}
	_rng.seed = GameClock.get_run_seed() ^ RNG_SALT.hash()


# ─── Consultas ────────────────────────────────────────────────

## El jugador conoce el domicilio: expediente N6-N7 o acceso completo a ese expediente (puesto
## de RR. HH., intrusión, chantaje: la regla de PERSONNEL).
static func knows_home_address(npc_id: String) -> bool:
	if house_params(NPCDirector.get_home_address(npc_id)).is_empty():
		return false
	if not PlayerState.get_full_file_access_reason(npc_id).is_empty():
		return true
	return PlayerState.get_personnel_file_level() >= Database.get_balance_int(B_HOME_LEVEL)


## Su agenda de ahora lo sitúa saliendo (noche.salas_salida), fuera del edificio o en casa.
static func is_leaving(npc_id: String) -> bool:
	var room_id: String = NPCDirector.get_location_at(npc_id, GameClock.get_hour(),
			GameClock.get_minute())
	if room_id.is_empty():
		return true
	var base: String = DatabaseSystem.get_room_base_id(room_id)
	if _balance_array(B_EXIT_ROOMS).has(base):
		return true
	var room: RoomData = Database.get_room(base)
	return room != null and room.floor == Database.get_balance_int(B_EXTERIOR_FLOOR)


## Falta el pasamontañas que exige la operación (noche.exige_pasamontanas).
static func needs_balaclava() -> bool:
	return bool(Database.get_balance(B_NEEDS_MASK)) and not Disguise.is_masked()


## noche.viviendas.<sala> ({} si la sala no es una vivienda de personaje).
static func house_params(room_id: String) -> Dictionary:
	var houses: Variant = Database.get_balance(B_HOUSES)
	var base: String = DatabaseSystem.get_room_base_id(room_id)
	if not houses is Dictionary or not (houses as Dictionary).has(base):
		return {}
	return houses[base]


## "humble" | "semi" | "mansion" ("" si no es una vivienda).
static func get_house_type(room_id: String) -> String:
	return str(house_params(room_id).get(H_TYPE, ""))


static func reason_key(code: String) -> String:
	return ERR_KEY_FORMAT % code.to_upper()


## "" si se le puede seguir ahora hasta su casa; si no, el código del motivo (ERR_*).
func can_follow(npc_id: String) -> String:
	var reason: String = can_visit(npc_id)
	if reason.is_empty() and not is_leaving(npc_id):
		return ERR_NOT_LEAVING
	return reason


## "" si se puede ir ahora por cuenta propia a su domicilio; si no, el motivo (ERR_*).
func can_visit(npc_id: String) -> String:
	if is_active():
		return ERR_BUSY
	if not NPCDirector.is_active(npc_id):
		return ERR_UNKNOWN_NPC
	if house_params(NPCDirector.get_home_address(npc_id)).is_empty():
		return ERR_NO_HOME
	if not knows_home_address(npc_id):
		return ERR_ADDRESS_UNKNOWN
	if not _balance_array(B_FOLLOW_BANDS).has(GameClock.get_current_band()):
		return ERR_WRONG_TIME
	return ""


func is_active() -> bool:
	return not _op.is_empty()


func get_operation() -> Dictionary:
	return _op.duplicate(true)


## El residente está en casa ahora (seguido hasta allí, o is_at_home).
func is_resident_home() -> bool:
	if not is_active() or bool(_op.get(K_ELIMINATED, false)):
		return false
	var npc_id: String = str(_op[K_NPC])
	if not NPCDirector.is_active(npc_id):
		return false
	if NPCDirector.is_at_home(npc_id):
		return true
	return bool(_op[K_FOLLOWED]) and NPCDirector.get_location_at(npc_id, GameClock.get_hour(),
			GameClock.get_minute()).is_empty()


## Contenedores de la vivienda en curso: [{id, type, requires, looted, left}] (left = objetos que
## no cupieron y siguen dentro).
func get_containers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_active():
		return out
	for container: Dictionary in _containers(str(_op[K_HOUSE])):
		var id: String = str(container.get("id", ""))
		out.append({"id": id, "type": str(container.get("type", "")),
				"requires": str(container.get("requires", "")), "looted": _is_looted(id),
				"left": _strings((_op[K_LEFT] as Dictionary).get(id, [])).size()})
	return out


# ─── Acciones de "manos" ──────────────────────────────────────

## Sigue al personaje hasta su casa. {ok, reason, house, minutes, resident_home}.
func follow_home(npc_id: String) -> Dictionary:
	return _start(npc_id, true)


## Va por su cuenta al domicilio conocido. {ok, reason, house, minutes, resident_home}.
func visit_home(npc_id: String) -> Dictionary:
	return _start(npc_id, false)


## Allana la vivienda por `method` (forced_lock | window). {ok, reason, alarm, witnesses}.
func break_in(method: String) -> Dictionary:
	if not is_active():
		return _fail(ERR_NO_OPERATION)
	if bool(_op[K_ENTERED]):
		return _fail(ERR_ALREADY_INSIDE)
	if needs_balaclava():
		return _fail(ERR_NO_BALACLAVA)
	var house: String = str(_op[K_HOUSE])
	var room: RoomData = Database.get_room(house)
	if room == null or not room.illegitimate_entries.has(method):
		return _fail(ERR_BAD_ENTRY)
	if not _carries_any(_balance_dict(B_ENTRY_TOOLS).get(method, [])):
		return _fail(ERR_NO_TOOL)
	GameClock.advance_minutes(float(_balance_dict(B_ENTRY_MINUTES).get(method, 0)))
	if not _sync_police():
		return _fail(ERR_NO_OPERATION)
	_op[K_ENTERED] = true
	_op[K_METHOD] = method
	var params: Dictionary = house_params(house)
	var witnesses: Array[String] = []
	if bool(params.get(H_ALARM, false)):
		_trigger_alarm(params)
	_roll_neighbour(params, method, witnesses)
	_roll_resident(params, witnesses)
	return {"ok": true, "reason": "", "alarm": bool(_op[K_ALARM]), "witnesses": witnesses}


## Saquea un contenedor (o recoge lo que no cupo antes). {ok, reason, items, left, value,
## witnesses}.
func loot_container(container_id: String) -> Dictionary:
	var check: String = _loot_check(container_id)
	if not check.is_empty():
		return _fail(check)
	var params: Dictionary = house_params(str(_op[K_HOUSE]))
	GameClock.advance_minutes(float(params.get(H_MINUTES, 0)))
	if not _sync_police():
		return _fail(ERR_NO_OPERATION)
	var leftovers: Dictionary = _op[K_LEFT]
	var loot: Array[String] = _strings(leftovers[container_id]) if leftovers.has(container_id) \
			else _roll_loot(_container(container_id), params)
	var result: Dictionary = _take_items(loot)
	_settle_container(container_id, result["left"])
	var witnesses: Array[String] = []
	_roll_resident(params, witnesses)
	_check_private_security(witnesses)
	result["ok"] = true
	result["reason"] = ""
	result["witnesses"] = witnesses
	return result


## Elimina al residente en su casa (§4.3). Deshabilitada con testigos. {ok, reason}.
func eliminate_resident(witness_ids: Array[String] = []) -> Dictionary:
	if not is_active() or not bool(_op[K_ENTERED]):
		return _fail(ERR_NOT_INSIDE)
	if needs_balaclava():
		return _fail(ERR_NO_BALACLAVA)
	if not is_resident_home():
		return _fail(ERR_NOT_HOME)
	update()
	var npc_id: String = str(_op[K_NPC])
	for witness: String in witness_ids + _strings(_op[K_INSIDE_WITNESSES]):
		if witness != npc_id:
			return _fail(ERR_WITNESSES)
	var house: String = str(_op[K_HOUSE])
	var victim_name: String = _npc_name(npc_id)
	NPCDirector.remove_npc(npc_id, CAUSE_ELIMINATED)
	NPCDirector.move_body(npc_id, house, "")
	_op[K_ELIMINATED] = true
	EventBus.crime_committed.emit(CRIME_ELIMINATION, house, {"npc_id": npc_id, "at_home": true,
			"leaves_record": false})
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_ELIMINATED, [victim_name])
	return {"ok": true, "reason": ""}


## Sale de la vivienda y cierra la operación. {ok, reason, value, identified}.
func leave_house() -> Dictionary:
	if not is_active():
		return _fail(ERR_NO_OPERATION)
	var op: Dictionary = _op
	_op = {}
	var identified: bool = bool(op[K_IDENTIFIED])
	if bool(op[K_ENTERED]):
		var house: String = str(op[K_HOUSE])
		EventBus.crime_committed.emit(CRIME_BURGLARY, house, {"npc_id": op[K_NPC],
				"value": int(op[K_VALUE]), "items": (op[K_ITEMS] as Array).duplicate(),
				"method": op[K_METHOD], "leaves_record": identified})
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_BURGLARY,
				[_npc_name(str(op[K_NPC])), int(op[K_VALUE])])
	return {"ok": true, "reason": "", "value": int(op[K_VALUE]), "identified": identified}


## La seguridad privada llega si le toca (el mundo lo llama en _process; las acciones también).
func update() -> void:
	if is_active():
		_check_private_security([])


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	return {"operation": _op.duplicate(true), "rng_seed": str(_rng.seed),
			"rng_state": str(_rng.state)}


func load_state(data: Dictionary) -> void:
	var op: Variant = data.get("operation", {})
	_op = (op as Dictionary).duplicate(true) if op is Dictionary else {}
	if not _op.is_empty() and not _op.get(K_LEFT) is Dictionary:
		_op[K_LEFT] = {}
	_rng.seed = str(data.get("rng_seed", str(_rng.seed))).to_int()
	_rng.state = str(data.get("rng_state", str(_rng.state))).to_int()


# ─── Internos ─────────────────────────────────────────────────

func _start(npc_id: String, followed: bool) -> Dictionary:
	var reason: String = can_follow(npc_id) if followed else can_visit(npc_id)
	if not reason.is_empty():
		return _fail(reason)
	var minutes: int = Database.get_balance_int(B_FOLLOW_MINUTES)
	GameClock.advance_minutes(float(minutes))
	var house: String = NPCDirector.get_home_address(npc_id)
	_op = {K_NPC: npc_id, K_HOUSE: house, K_FOLLOWED: followed, K_ENTERED: false, K_METHOD: "",
			K_ALARM: false, K_AWAKE: false, K_VALUE: 0, K_ITEMS: [], K_LOOTED: [],
			K_WITNESSES: [], K_INSIDE_WITNESSES: [], K_IDENTIFIED: false,
			K_SECURITY_AT: NO_TIME, K_ELIMINATED: false, K_LEFT: {}}
	if followed:
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_FOLLOWED, [_npc_name(npc_id)])
	return {"ok": true, "reason": "", "house": house, "minutes": minutes,
			"resident_home": is_resident_home()}


func _loot_check(container_id: String) -> String:
	if not is_active() or not bool(_op[K_ENTERED]):
		return ERR_NOT_INSIDE
	var container: Dictionary = _container(container_id)
	if container.is_empty():
		return ERR_UNKNOWN_CONTAINER
	if _is_looted(container_id):
		return ERR_EMPTY
	var need: String = str(container.get("requires", ""))
	if not need.is_empty() and not _carries_any(_balance_dict(B_REQUIREMENTS).get(need, [])):
		return ERR_LOCKED
	return ""


func _is_looted(container_id: String) -> bool:
	return (_op.get(K_LOOTED, []) as Array).has(container_id) \
			or NPCDirector.is_house_container_looted(str(_op.get(K_NPC, "")), container_id)


## Botín del contenedor: cada objeto de contains con prob_objeto + la tabla botin_extra.
func _roll_loot(container: Dictionary, params: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var chance: float = float(params.get(H_ITEM_CHANCE, 0.0))
	for item_id: Variant in container.get("contains", []):
		if _rng.randf() < chance:
			out.append(str(item_id))
	for entry: Variant in params.get(H_EXTRA, []):
		if entry is Dictionary and _rng.randf() < float(entry.get(E_CHANCE, 0.0)):
			out.append(str(entry.get(E_ITEM, "")))
	return out


## Mete el botín en el inventario (el efectivo, al capital). {items, left, value}; left = lo
## que no cupo (los ids que no son objetos se descartan).
func _take_items(loot: Array[String]) -> Dictionary:
	var taken: Array[String] = []
	var left: Array[String] = []
	var value: int = 0
	for item_id: String in loot:
		var item: ItemData = Database.get_item(item_id) if not item_id.is_empty() else null
		if item == null:
			continue
		if not PlayerState.add_item(item_id):
			left.append(item_id)
			continue
		taken.append(item_id)
		value += item.value
	_op[K_VALUE] = int(_op[K_VALUE]) + value
	(_op[K_ITEMS] as Array).append_array(taken)
	return {"items": taken, "left": left, "value": value}


## Vaciado del todo → saqueado (op y NPCDirector); con restos, quedan en op.left.
func _settle_container(container_id: String, left: Array[String]) -> void:
	var leftovers: Dictionary = _op[K_LEFT]
	if not left.is_empty():
		leftovers[container_id] = left.duplicate()
		return
	leftovers.erase(container_id)
	(_op[K_LOOTED] as Array).append(container_id)
	NPCDirector.mark_house_container_looted(str(_op[K_NPC]), container_id)


func _trigger_alarm(params: Dictionary) -> void:
	_op[K_ALARM] = true
	var police: Police = _police()
	if police != null:
		police.report_alarm(str(_op[K_HOUSE]))
	if bool(params.get(H_SECURITY, false)):
		_op[K_SECURITY_AT] = GameClock.get_total_minutes() \
				+ float(params.get(H_SECURITY_MINUTES, 0))


func _roll_neighbour(params: Dictionary, method: String, witnesses: Array[String]) -> void:
	var noise: float = float(_balance_dict(B_ENTRY_NOISE).get(method, 1.0))
	if _rng.randf() >= float(params.get(H_NEIGHBOUR, 0.0)) * noise:
		return
	var neighbour: String = _pick_role(str(Database.get_balance(B_NEIGHBOUR_ROLE)))
	_witness(neighbour, Database.get_balance_float(B_PARTIAL))
	witnesses.append(neighbour)


func _roll_resident(params: Dictionary, witnesses: Array[String]) -> void:
	if bool(_op[K_AWAKE]) or not is_resident_home():
		return
	if _rng.randf() >= float(params.get(H_WAKE, 0.0)):
		return
	_op[K_AWAKE] = true
	var npc_id: String = str(_op[K_NPC])
	_witness(npc_id, Database.get_balance_float(B_DIRECT))
	witnesses.append(npc_id)


## La seguridad privada, ya en la casa, ve al jugador si está dentro (si no, espera dentro).
func _check_private_security(witnesses: Array[String]) -> void:
	var at: float = float(_op.get(K_SECURITY_AT, NO_TIME))
	if at < 0.0 or not bool(_op[K_ENTERED]) or GameClock.get_total_minutes() < at:
		return
	if DatabaseSystem.get_room_base_id(PlayerState.get_room()) \
			!= DatabaseSystem.get_room_base_id(str(_op[K_HOUSE])):
		return
	_op[K_SECURITY_AT] = NO_TIME
	var guard: String = _pick_role(str(Database.get_balance(B_SECURITY_ROLE)))
	_witness(guard, Database.get_balance_float(B_DIRECT))
	(_op[K_INSIDE_WITNESSES] as Array).append(guard)
	witnesses.append(guard)


## Mismo circuito que dentro: creencia del testigo y aviso a la policía (Police).
func _witness(witness_id: String, certainty: float) -> void:
	var house: String = str(_op[K_HOUSE])
	var police: Police = _police()
	var result: Dictionary
	if police != null:
		result = police.witness_crime(witness_id, CRIME_BURGLARY, house, certainty)
	else:
		result = Police.record_witness(witness_id, CRIME_BURGLARY, house, certainty, true)
	(_op[K_WITNESSES] as Array).append(witness_id)
	_op[K_IDENTIFIED] = bool(_op[K_IDENTIFIED]) or bool(result.get("identified", false))


## Un personaje en plantilla con ese rol (departamento exterior); "" si no hay ninguno.
func _pick_role(role: String) -> String:
	var candidates: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.get_role(npc.id) == role:
			candidates.append(npc.id)
	if candidates.is_empty():
		return ""
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _containers(house: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(house))
	if room == null:
		return out
	var types: Array = _balance_array(B_CONTAINER_TYPES)
	for entry: Dictionary in room.interactables:
		var contents: Variant = entry.get("contains", [])
		if types.has(str(entry.get("type", ""))) and contents is Array \
				and not (contents as Array).is_empty():
			out.append(entry)
	return out


func _container(container_id: String) -> Dictionary:
	for entry: Dictionary in _containers(str(_op.get(K_HOUSE, ""))):
		if str(entry.get("id", "")) == container_id:
			return entry
	return {}


## La unidad en camino consume el tiempo que acaba de pasar (puede llegar y arrestar). false si la
## operación terminó (fin de partida).
func _sync_police() -> bool:
	var police: Police = _police()
	if police != null:
		police.update()
	return is_active()


func _police() -> Police:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(Police.GROUP) as Police


static func _carries_any(tools: Variant) -> bool:
	if not tools is Array or (tools as Array).is_empty():
		return true
	for tool: Variant in tools:
		if PlayerState.has_item(str(tool)):
			return true
	return false


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.name if npc != null and not npc.name.is_empty() else npc_id


static func _strings(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for value: Variant in raw:
			out.append(str(value))
	return out


static func _balance_dict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(path)
	return value if value is Dictionary else {}


static func _balance_array(path: String) -> Array:
	var value: Variant = Database.get_balance(path)
	return value if value is Array else []


func _on_day_advanced(_day_number: int) -> void:
	if is_active():
		leave_house()
