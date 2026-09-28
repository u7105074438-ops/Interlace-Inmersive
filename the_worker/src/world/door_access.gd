# door_access.gd — Política de puertas del jugador y registro de pasos con tarjeta al CRUZAR (no al acercarse): lectores, tornos y la regla de la sala de trabajo propia.
# PROPIETARIO DE: los pasos concedidos pendientes de cruce (puerta, lado de partida) de la planta actual.
# ESCUCHA: FloorStreamer.floor_loaded (olvida los pasos pendientes de la planta anterior).
class_name DoorAccess
extends Node

## GameRoot lo añade con setup(streamer, player) y registra policy() con FloorStreamer.set_door_policy.
## REGLAS (static allows(door), sin efectos):
##  · Cerradura antigua: nunca (la abre el interactivo lock_old con su llave).
##  · Sala de trabajo propia (MapView.is_room_allowed: el despacho del puesto siempre se abre, varios
##    puestos lo tienen por encima de su acreditación): solo la puerta cuya sala interior (room_b, la
##    que la puerta protege) es ese despacho. Una puerta del despacho hacia una sala interior más
##    restringida (caja fuerte, despacho del jefe) sigue la regla general.
##  · General: acreditación del jugador ≥ la de la puerta; con special_access, modo and/or de la sala.
## REGISTRO (BUILD_NOTES §15, docs_integration_todo «card readers»): conceder el paso ARMA la puerta;
## Security.log_card_access (→ card_reader_logged, pitido y subtítulo) se emite cuando el jugador
## pasa al otro lado del hueco. Acercarse y darse la vuelta no deja rastro. Las puertas de servicio
## no tienen lector. Mientras el paso está armado y el jugador sigue en el sensor, la hoja se
## mantiene abierta (quedarse ante un torno ya validado no lo cierra en la cara).
## swipe(door): pasar la tarjeta a mano (tecla E ante un torno): mismas reglas; true si abre.

signal swipe_logged(door_id: String, room_id: String)

const GROUP := "door_access"
const PLAYER_CARD := "player"
const MODE_AND := "and"
const MODE_OR := "or"
const LOGGED_KINDS: Array[String] = [Door.KIND_READER, Door.KIND_TURNSTILE]
const B_SENSOR := "mundo.puertas.sensor"
const B_OPEN := "mundo.puertas.apertura_s"
const B_CROSS_MARGIN := "puentes.margen_cruce_celdas"
const B_DISARM := "puentes.distancia_desarme_celdas"

var _streamer: FloorStreamer = null
var _player: Node2D = null
## door_id → {door: WeakRef, side: float}
var _armed: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)


func setup(streamer: FloorStreamer, player: Node2D) -> void:
	_streamer = streamer
	_player = player
	_streamer.floor_loaded.connect(func(_floor: int) -> void: _armed.clear())
	_streamer.set_door_policy(policy)


static func find(tree: SceneTree) -> DoorAccess:
	return tree.get_first_node_in_group(GROUP) as DoorAccess if tree != null else null


# ─── Política ─────────────────────────────────────────────────

## Callable de FloorStreamer.set_door_policy: decide y, si concede, arma el registro del cruce.
func policy(door: Door, body: Node2D) -> bool:
	if not allows(door):
		return false
	arm(door, body)
	return true


## ¿Puede pasar el jugador? (sin registrar nada).
static func allows(door: Door) -> bool:
	if door == null:
		return false
	# §5.2: el puesto con la etiqueta de la sala tiene su llave (también de cerradura antigua).
	if occupation_tag_grants(door, PlayerState.get_occupation()):
		return true
	if door.kind == Door.KIND_OLD_LOCK:
		return false
	if is_own_office_door(door):
		return true
	return meets_door(door)


## Puerta que protege la sala de trabajo del puesto (su sala interior es el despacho).
static func is_own_office_door(door: Door) -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	if occupation == null or occupation.office_room.is_empty() or door.kind == Door.KIND_TURNSTILE:
		return false
	return DatabaseSystem.get_room_base_id(door.room_b) == occupation.office_room


## Acreditación y acceso especial (misma regla que FloorStreamer.default_door_policy).
static func meets_door(door: Door) -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	if occupation_tag_grants(door, occupation):
		return true
	var level_ok: bool = PlayerState.get_clearance() >= door.clearance
	if door.special_access.is_empty():
		return level_ok
	var special_ok: bool = false
	for tag: String in door.special_access:
		special_ok = special_ok or (occupation != null and occupation.special_access.has(tag))
	if door.special_mode == MODE_OR:
		return level_ok or special_ok
	return level_ok and special_ok if door.special_mode == MODE_AND else level_ok


## §5.2: una etiqueta del puesto con regla de mapa (balance mapa.acceso_por_etiqueta: sótanos,
## planta de fábrica, archivo activo, llaves maestras…) abre la puerta de la sala que concede, igual
## que la pinta en verde MapView.is_room_allowed (mapa y puertas no pueden discrepar).
static func occupation_tag_grants(door: Door, occupation: OccupationData) -> bool:
	if occupation == null or door.room_b.is_empty():
		return false
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(door.room_b))
	if room == null:
		return false
	for tag: String in occupation.special_access:
		if MapView.tag_grants(tag, room):
			return true
	return false


## Tarjeta a mano (E ante un torno o un lector): abre y arma el registro. false = denegada.
func swipe(door: Door) -> bool:
	if door == null or not allows(door):
		return false
	door.open_for(Database.get_balance_float(B_OPEN))
	arm(door, _player)
	return true


# ─── Registro al cruzar ───────────────────────────────────────

func arm(door: Door, body: Node2D) -> void:
	if body == null or not LOGGED_KINDS.has(door.kind) or _armed.has(door.door_id):
		return
	var side: float = signf(across(door, body.global_position))
	if side == 0.0:
		return
	_armed[door.door_id] = {"door": weakref(door), "side": side}


func is_armed(door_id: String) -> bool:
	return _armed.has(door_id)


func _physics_process(_delta: float) -> void:
	if _armed.is_empty() or _player == null or not is_instance_valid(_player):
		return
	for door_id: String in _armed.keys():
		_track(door_id, _armed[door_id])


func _track(door_id: String, entry: Dictionary) -> void:
	var door: Door = (entry["door"] as WeakRef).get_ref() as Door
	if door == null or not door.is_inside_tree():
		_armed.erase(door_id)
		return
	var cell: float = door.cell_px
	var offset: float = across(door, _player.global_position)
	if signf(offset) != float(entry["side"]) and absf(offset) >= Database.get_balance_float(B_CROSS_MARGIN) * cell:
		_armed.erase(door_id)
		_log(door)
		return
	var distance: float = _distance_to_gap(door)
	if distance > Database.get_balance_float(B_DISARM) * cell:
		_armed.erase(door_id)
	elif not door.is_open() and distance <= Database.get_balance_float(B_SENSOR) * cell:
		door.open_for(Database.get_balance_float(B_OPEN))


func _log(door: Door) -> void:
	var room: String = _streamer.get_room_at(_player.global_position) if _streamer != null else door.room_b
	if room.is_empty():
		room = door.room_b
	Security.log_card_access(door.door_id, PLAYER_CARD, GameClock.get_day(), GameClock.get_hour(), room)
	swipe_logged.emit(door.door_id, room)


## Distancia con signo al eje del hueco, perpendicular a la puerta (px; el signo es el lado).
static func across(door: Door, world_pos: Vector2) -> float:
	var local: Vector2 = door.to_local(world_pos)
	var centre: Vector2 = door.gap_rect().get_center()
	return local.x - centre.x if door.vertical else local.y - centre.y


func _distance_to_gap(door: Door) -> float:
	var gap: Rect2 = door.gap_rect()
	var local: Vector2 = door.to_local(_player.global_position)
	var clamped: Vector2 = Vector2(clampf(local.x, gap.position.x, gap.end.x), clampf(local.y, gap.position.y, gap.end.y))
	return local.distance_to(clamped)
