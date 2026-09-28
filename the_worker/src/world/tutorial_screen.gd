# tutorial_screen.gd — La pared de monitores de la sala de formación mientras pasa el vídeo de bienvenida (§13.8): se enciende como una sola imagen con el Voss de 2011, brilla sobre la sala y acaba en nieve de cinta.
# PROPIETARIO DE: su estado de encendido y su brillo.
# ESCUCHA: nada (TutorialDirector la enciende y la apaga).
class_name TutorialScreen
extends Node2D

## Se coloca sobre el mueble "monitor_wall" de la sala (misma geometría que FurniturePainter:
## huella menos 2 px de referencia, marco de 24 px de alto a 12 px del borde inferior), en la capa de
## actores del FloorStreamer con el origen al pie de la huella: tapa los monitores y quien pasa por
## delante la tapa a ella (orden Y).
## Sin monitor en la sala, en el centro de su pared superior.

const MONITOR_TYPE := "monitor_wall"
const REFERENCE_CELL := 48.0
const INSET_REF := 2.0
const FRAME_H_REF := 24.0
const FRAME_BOTTOM_REF := 12.0
const EXTRA_UP := 0.35
## Origen (orden Y) justo al pie de la huella del mueble: se dibuja SOBRE los monitores, y quien pasa
## por delante (siempre más abajo: la fila del mueble no es transitable) la tapa.
const ORIGIN_BELOW_PX := 1.0
const GLOW_PX := 10.0
const REDRAW_HZ := 10.0
const FLICKER_HZ := 3.1
const FLICKER_AMOUNT := 0.12
const C_SCREEN := Color("#1e4d8f")
const C_GLOW := Color(0.55, 0.78, 1.0, 0.35)
const C_STAR := Color("#ffd35c")
const C_BAR := Color("#5fd38d")
const C_OFF := Color("#15181c")
const STATE_OFF := "off"
const STATE_ON := "on"
const STATE_END := "end"

var _screen: Rect2 = Rect2()
var _state: String = STATE_OFF
var _app: Dictionary = {}
var _time: float = 0.0
var _redraw_left: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Crea la pantalla de `room_id` en la planta cargada (null si la sala no está cargada).
static func create(streamer: FloorStreamer, room_id: String, appearance: Dictionary) -> TutorialScreen:
	var rect: Rect2 = streamer.get_room_rect_px(room_id)
	if rect.size == Vector2.ZERO:
		return null
	var node: TutorialScreen = TutorialScreen.new()
	node.name = "TutorialScreen"
	node._app = appearance
	node._place(rect, Database.get_room(room_id), RoomBuilder.cell_px())
	streamer.get_actor_layer().add_child(node)
	return node


func _place(room_rect: Rect2, room: RoomData, cell: float) -> void:
	var s: float = cell / REFERENCE_CELL
	var foot: Rect2 = Rect2(room_rect.position + Vector2(room_rect.size.x * 0.35, 0.0), Vector2(room_rect.size.x * 0.3, cell))
	if room != null:
		for entry: Dictionary in room.furniture:
			if str(entry.get("type", "")) == MONITOR_TYPE:
				var fp: Rect2i = FurniturePainter.footprint(entry)
				foot = Rect2(room_rect.position + Vector2(fp.position) * cell, Vector2(fp.size) * cell)
				break
	var d: Rect2 = foot.grow(-INSET_REF * s)
	var bottom: float = d.end.y - FRAME_BOTTOM_REF * s
	var top: float = bottom - FRAME_H_REF * s - EXTRA_UP * cell
	var origin_y: float = foot.end.y + ORIGIN_BELOW_PX
	global_position = Vector2(d.get_center().x, origin_y)
	_screen = Rect2(Vector2(-d.size.x * 0.5, top - origin_y), Vector2(d.size.x, bottom - top))


func turn_on() -> void:
	_state = STATE_ON
	queue_redraw()


func show_end() -> void:
	_state = STATE_END
	queue_redraw()


func turn_off() -> void:
	_state = STATE_OFF
	queue_redraw()


func get_state() -> String:
	return _state


## Rectángulo de la imagen en coordenadas globales (pruebas / encuadre).
func get_screen_rect() -> Rect2:
	return Rect2(global_position + _screen.position, _screen.size)


func _process(delta: float) -> void:
	if _state == STATE_OFF:
		return
	_time += delta
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = 1.0 / REDRAW_HZ
		queue_redraw()


func _draw() -> void:
	if _state == STATE_OFF:
		return
	var flicker: float = 1.0 - FLICKER_AMOUNT * (0.5 + 0.5 * sin(_time * TAU * FLICKER_HZ))
	draw_rect(_screen.grow(GLOW_PX), Color(C_GLOW, C_GLOW.a * flicker))
	if _state == STATE_END:
		_draw_snow()
		return
	draw_rect(_screen, C_SCREEN)
	var h: float = _screen.size.y
	var face: Rect2 = Rect2(_screen.position + Vector2(h * 0.1, h * 0.05), Vector2(h * 0.9, h * 0.9))
	if not _app.is_empty():
		CharacterPainter.draw_portrait(self, _app, face)
	var star_c: Vector2 = Vector2(face.end.x + h * 0.6, _screen.get_center().y)
	draw_circle(star_c, h * 0.22, C_STAR)
	var bars: int = 5
	for i: int in bars:
		var bh: float = h * (0.2 + 0.13 * i)
		var x: float = star_c.x + h * 0.6 + i * h * 0.3
		if x + h * 0.2 < _screen.end.x:
			draw_rect(Rect2(x, _screen.end.y - bh - h * 0.06, h * 0.2, bh), C_BAR)
	draw_rect(_screen, C_OFF, false, 2.0)


func _draw_snow() -> void:
	draw_rect(_screen, Color.BLACK)
	_rng.seed = int(_time * REDRAW_HZ)
	var cells: int = 24
	var step: Vector2 = Vector2(_screen.size.x / cells, _screen.size.y / (cells * 0.25))
	for y: int in int(cells * 0.25):
		for x: int in cells:
			var v: float = _rng.randf()
			if v > 0.5:
				draw_rect(Rect2(_screen.position + Vector2(x, y) * step, step), Color(v, v, v, 0.8))
