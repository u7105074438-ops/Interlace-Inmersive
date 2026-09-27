# interactable.gd — Punto interactivo de una sala (cajón, ordenador, panel, salida…) con realce discreto.
# PROPIETARIO DE: su disponibilidad y su estado de realce (presentación).
# ESCUCHA: nada (consulta la posición del jugador del grupo "player" para el realce).
class_name Interactable
extends Area2D

## Contrato BUILD_NOTES §14: Area2D en la capa física 6, grupo "interactables".
##   interact_id, interact_type, room_id, data (la entrada de datos tal cual + extras de tránsito)
##   get_prompt_key() → "UI_INTERACT_<TIPO>" (o UI_INTERACT_GENERIC si no hay texto propio)
##   is_available() → false si alguien lo ha deshabilitado con set_available(false)
## El jugador elige el más cercano dentro del radio de uso (su CollisionShape2D, mundo.radio_uso_
## interactivo); InteractionRouter despacha por interact_type. El realce (§14.8 "realce discreto")
## aparece al acercarse (mundo.radio_realce_interactivo) y se refuerza con set_focused(true).

signal availability_changed(interactable: Interactable, available: bool)

const GROUP := "interactables"
const PLAYER_GROUP := "player"
const LAYER_INTERACTABLES := 6
const PROMPT_PREFIX := "UI_INTERACT_"
const PROMPT_GENERIC := "UI_INTERACT_GENERIC"
const Z_HIGHLIGHT := 20
const FADE_SPEED := 5.0
const BOB_SPEED := 3.2
const BOB_PX := 3.0
const MARK_SIZE := 7.0
const C_MARK := Color(1.0, 0.96, 0.78)
const C_MARK_FOCUS := Color(1.0, 0.85, 0.35)
const C_OUTLINE := Color(0.08, 0.08, 0.1, 0.9)

var interact_id: String = ""
var interact_type: String = ""
var room_id: String = ""
var data: Dictionary = {}
var cell_px: float = 48.0
var _available: bool = true
var _focused: bool = false
var _glow: float = 0.0
var _time: float = 0.0
var _highlight_radius: float = 0.0
var _player: Node2D = null


## Configura el punto; `center_px` es el centro de la celda de uso en coordenadas del padre.
func setup(p_id: String, p_type: String, p_room_id: String, p_data: Dictionary, p_cell_px: float,
		center_px: Vector2) -> void:
	interact_id = p_id
	interact_type = p_type
	room_id = p_room_id
	data = p_data
	cell_px = p_cell_px
	position = center_px
	name = "I_%s" % p_id.validate_node_name()
	collision_layer = 1 << (LAYER_INTERACTABLES - 1)
	collision_mask = 0
	monitoring = false
	monitorable = true
	z_as_relative = false
	z_index = Z_HIGHLIGHT
	_highlight_radius = Database.get_balance_float("mundo.radio_realce_interactivo") * cell_px
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = Database.get_balance_float("mundo.radio_uso_interactivo") * cell_px
	shape.shape = circle
	add_child(shape)
	add_to_group(GROUP)


func get_prompt_key() -> String:
	var key: String = PROMPT_PREFIX + interact_type.to_upper()
	return key if tr(key) != key else PROMPT_GENERIC


func is_available() -> bool:
	return _available


func set_available(available: bool) -> void:
	if available == _available:
		return
	_available = available
	availability_changed.emit(self, available)
	queue_redraw()


## El jugador marca así su objetivo actual (realce reforzado).
func set_focused(focused: bool) -> void:
	_focused = focused
	queue_redraw()


func is_focused() -> bool:
	return _focused


## Radio de uso en px (el de su forma de colisión).
func get_use_radius() -> float:
	return Database.get_balance_float("mundo.radio_uso_interactivo") * cell_px


func _process(delta: float) -> void:
	_time += delta
	var target: float = 0.0
	if _available and _player_near():
		target = 1.0
	var before: float = _glow
	_glow = move_toward(_glow, target, delta * FADE_SPEED)
	if _glow > 0.0 or before > 0.0:
		queue_redraw()


func _player_near() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
		if _player == null:
			return false
	return global_position.distance_to(_player.global_position) <= _highlight_radius


func _draw() -> void:
	if _glow <= 0.0:
		return
	var strength: float = _glow * (1.0 if _focused else 0.6)
	var col: Color = C_MARK_FOCUS if _focused else C_MARK
	var ring: float = cell_px * 0.42
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.35 * strength), 2.0)
	var bob: float = sin(_time * BOB_SPEED) * BOB_PX
	var tip: Vector2 = Vector2(0, -cell_px * 0.62 + bob)
	var s: float = MARK_SIZE
	var mark: PackedVector2Array = [tip + Vector2(-s, -s * 1.3), tip + Vector2(s, -s * 1.3), tip]
	draw_colored_polygon(mark, Color(col.r, col.g, col.b, strength))
	var loop: PackedVector2Array = mark.duplicate()
	loop.append(mark[0])
	draw_polyline(loop, Color(C_OUTLINE.r, C_OUTLINE.g, C_OUTLINE.b, C_OUTLINE.a * strength), 1.5)
