# player_camera.gd — Cámara del jugador: seguimiento suave con anticipación hacia la mirada y niveles de zoom.
# PROPIETARIO DE: el encuadre de la partida (posición, anticipación y nivel de zoom de la cámara).
# ESCUCHA: nada (lee get_facing()/is_still() de su objetivo cada fotograma).
class_name PlayerCamera
extends Camera2D

## Manual PASO 8 ("cámara con seguimiento y desplazamiento hacia la dirección de mirada") y §14.1.
## Por defecto sigue a su padre (el Player la crea como hija con top_level). Los niveles de zoom
## (camara.zoom_niveles) son el ajuste de cámara que puede exponer el menú de opciones.
## Sin interpolación física el seguimiento corre en _physics_process, al mismo ritmo que
## move_and_slide del jugador (sin tirones a más de 60 Hz); con physics_interpolation activada
## corre en _process sobre la posición interpolada del objetivo.

const CELL_PATH := "mundo.px_por_unidad"
const ZOOM_LEVELS_PATH := "camara.zoom_niveles"
const DEFAULT_LEVEL_PATH := "camara.zoom_nivel_por_defecto"
const MOBILE_LEVEL_PATH := "camara.zoom_nivel_movil"
const LOOKAHEAD_PATH := "camara.anticipacion_celdas"
const IDLE_LOOKAHEAD_PATH := "camara.anticipacion_quieto"
const FOLLOW_RATE_PATH := "camara.velocidad_seguimiento"
const LOOK_RATE_PATH := "camara.velocidad_anticipacion"
const VERTICAL_PATH := "camara.desplazamiento_vertical_celdas"

signal zoom_level_changed(level: int)

var target: Node2D = null
var _look: Vector2 = Vector2.ZERO
var _zoom_level: int = 0
var _zoom_levels: Array[float] = []
var _interpolated: bool = false
var _lookahead_px: float = 0.0
var _idle_factor: float = 0.0
var _follow_rate: float = 0.0
var _look_rate: float = 0.0
var _vertical_px: float = 0.0


func _ready() -> void:
	top_level = true
	position_smoothing_enabled = false
	_load_tunables()
	_interpolated = get_tree().is_physics_interpolation_enabled()
	if _interpolated:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(_interpolated)
	set_physics_process(not _interpolated)
	if target == null and get_parent() is Node2D:
		target = get_parent() as Node2D
	set_zoom_level(default_zoom_level())
	snap_to_target()
	make_current()


func _load_tunables() -> void:
	var cell: float = Database.get_balance_float(CELL_PATH)
	_zoom_levels.clear()
	var levels: Array = []
	if Database.get_balance(ZOOM_LEVELS_PATH) is Array:
		levels = Database.get_balance(ZOOM_LEVELS_PATH)
	for i: int in levels.size():
		_zoom_levels.append(float(levels[i]))
	_lookahead_px = Database.get_balance_float(LOOKAHEAD_PATH) * cell
	_idle_factor = Database.get_balance_float(IDLE_LOOKAHEAD_PATH)
	_follow_rate = Database.get_balance_float(FOLLOW_RATE_PATH)
	_look_rate = Database.get_balance_float(LOOK_RATE_PATH)
	_vertical_px = Database.get_balance_float(VERTICAL_PATH) * cell


func _process(delta: float) -> void:
	follow(delta)


func _physics_process(delta: float) -> void:
	follow(delta)


## Avanza el seguimiento `delta` segundos (suavizado exponencial, independiente de los FPS).
func follow(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var facing: Vector2 = target.call("get_facing") if target.has_method("get_facing") else Vector2.ZERO
	var moving: bool = not bool(target.call("is_still")) if target.has_method("is_still") else false
	var wanted: Vector2 = facing * _lookahead_px * (1.0 if moving else _idle_factor)
	_look = _look.lerp(wanted, 1.0 - exp(-_look_rate * delta))
	var desired: Vector2 = _target_position() + Vector2(0.0, -_vertical_px) + _look
	global_position = global_position.lerp(desired, 1.0 - exp(-_follow_rate * delta))


func _target_position() -> Vector2:
	if _interpolated:
		return target.get_global_transform_interpolated().origin
	return target.global_position


## Coloca la cámara sobre el objetivo sin suavizado (al cargar planta o teletransportar).
func snap_to_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	_look = Vector2.ZERO
	global_position = target.global_position + Vector2(0.0, -_vertical_px)
	reset_physics_interpolation()


## Nivel inicial: en móvil, más cerca (pantalla pequeña, §13.7); en PC, el por defecto.
static func default_zoom_level() -> int:
	return Database.get_balance_int(MOBILE_LEVEL_PATH if OS.has_feature("mobile") else DEFAULT_LEVEL_PATH)


func set_zoom_level(level: int) -> void:
	if _zoom_levels.is_empty():
		return
	_zoom_level = clampi(level, 0, _zoom_levels.size() - 1)
	var z: float = _zoom_levels[_zoom_level]
	zoom = Vector2(z, z)
	zoom_level_changed.emit(_zoom_level)


func get_zoom_level() -> int:
	return _zoom_level


func get_zoom_level_count() -> int:
	return _zoom_levels.size()


## Límites de la planta cargada (FloorStreamer) para no enseñar el vacío.
func set_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)
