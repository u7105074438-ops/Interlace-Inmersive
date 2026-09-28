# body.gd — Cuerpo de un personaje eliminado (§12.2, §14.7): figura tendida sobre una mancha, interactivo "body" para arrastrarlo, esconderlo o hacerlo desaparecer.
# PROPIETARIO DE: su presentación (figura tendida, mancha, postura arrastrada). El registro del cuerpo (sala, escondite, hallado) es de NPCDirector.
# ESCUCHA: nada (SecurityKeeper lo crea, lo mueve mientras se arrastra y lo libera).
class_name BodyNode
extends Interactable

## Vive bajo la capa de actores del FloorStreamer (orden en Y con muebles y personajes). El
## interactivo de tipo TYPE lo atiende el módulo de seguridad (src/world/interactions/security.gd):
## arrastrar / soltar. Mientras se arrastra cede el foco (is_available = false) si hay cerca un
## destino útil para él (escondite que admite cuerpos, bajante, montacargas): así la tecla E sobre
## ese destino lo esconde o lo tira, y lejos de todo E lo suelta.

const TYPE := "body"
const BODY_GROUP := "bodies"
const C_STAIN := Color(0.42, 0.05, 0.06, 0.55)
const C_SHADOW := Color(0.0, 0.0, 0.0, 0.22)
const C_TINT := Color(0.84, 0.82, 0.88)
const STAIN_RATIO := Vector2(0.55, 0.26)
const SHADOW_RATIO := Vector2(0.62, 0.22)
## Núcleo de la mancha (fracción del radio) y su desplazamiento hacia la cabeza (fracción de celda).
const STAIN_CORE := 0.6
const STAIN_SHIFT := 0.1
## Figura tendida: los pies a FIGURE_REACH celdas del centro, en contra de la cabeza; un poco hacia
## abajo (FIGURE_DROP) para que la mancha asome bajo el torso. En reposo la cabeza mira a -x.
const FIGURE_REACH := 0.55
const FIGURE_DROP := 0.12
const REST_HEADING := Vector2.LEFT
## Inclinación máxima (fracción) al arrastrar en vertical y zona muerta horizontal del rumbo.
const HEADING_TILT := 0.45
const HEADING_DEADZONE := 0.2
## Sábana que tapa la figura entera (§3.1: nunca gráfico). Medidas en celdas, en el espacio de la
## figura de pie (pies en el origen, cabeza hacia -y): media anchura, alto y margen bajo los pies.
const C_SHEET := Color(0.78, 0.8, 0.84)
const C_SHEET_FOLD := Color(0.62, 0.64, 0.7)
const SHEET_HALF_W := 0.4
const SHEET_TOP := 1.3
const SHEET_BOTTOM := 0.1
const SHEET_FOLDS := 3

var npc_id: String = ""
var body_id: String = ""
var dragged: bool = false
## Callable() -> bool: hay cerca un destino para el cuerpo (lo fija SecurityKeeper).
var yield_check: Callable = Callable()
var _figure: Figure = null
var _side: float = -1.0


## Figura tendida: el personaje de la víctima girado, pálido.
class Figure extends Node2D:
	var appearance: Dictionary = {}
	var tier: int = 1

	func _draw() -> void:
		if appearance.is_empty():
			return
		CharacterPainter.draw(self, appearance, tier, CharacterPainter.make_pose("idle", 0, Vector2.DOWN))


## Sábana sobre la figura: solo se ve la forma del cuerpo (§3.1).
class Sheet extends Node2D:
	var cell: float = 0.0

	func _draw() -> void:
		var rect: Rect2 = Rect2(-SHEET_HALF_W * cell, -SHEET_TOP * cell,
				SHEET_HALF_W * 2.0 * cell, (SHEET_TOP + SHEET_BOTTOM) * cell)
		draw_rect(rect, C_SHEET)
		draw_circle(Vector2(0.0, rect.position.y), SHEET_HALF_W * cell, C_SHEET)
		for i: int in range(1, SHEET_FOLDS + 1):
			var y: float = rect.position.y + rect.size.y * float(i) / float(SHEET_FOLDS + 1)
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), C_SHEET_FOLD, 1.0)


func setup_body(p_npc_id: String, p_body_id: String, p_room_id: String, p_cell_px: float) -> void:
	npc_id = p_npc_id
	body_id = p_body_id
	setup(TYPE + "_" + p_npc_id, TYPE, p_room_id, {"npc_id": p_npc_id, "body_id": p_body_id}, p_cell_px, Vector2.ZERO)
	add_to_group(BODY_GROUP)
	_figure = Figure.new()
	_figure.name = "Figure"
	_figure.modulate = C_TINT
	var npc: NPCRuntime = NPCDirector.get_npc(p_npc_id)
	if npc != null:
		_figure.appearance = CharacterPainter.appearance_for_npc(npc)
		_figure.tier = clampi(npc.tier, 1, CharacterStyle.OUTFIT_COUNT)
	add_child(_figure)
	var sheet: Sheet = Sheet.new()
	sheet.name = "Sheet"
	sheet.cell = p_cell_px
	_figure.add_child(sheet)
	face(REST_HEADING)


func _ready() -> void:
	z_as_relative = true
	z_index = 0


## Arrastrado: la cabeza queda del lado del jugador (`toward` = dirección hacia él).
func set_dragged(on: bool, toward: Vector2 = REST_HEADING) -> void:
	dragged = on
	face(toward)


## Cabeza hacia el lado de `toward`: la figura (de pie, cabeza hacia -y) queda SIEMPRE tendida en
## horizontal (en la vista 3/4 un cuerpo vertical se leería de pie), apenas inclinada hacia arriba o
## abajo si el jugador tira en vertical.
func face(toward: Vector2) -> void:
	if _figure == null or toward.length_squared() <= 0.0:
		return
	var side: float = signf(toward.x) if absf(toward.x) > HEADING_DEADZONE else _side
	_side = side if side != 0.0 else _side
	var heading: Vector2 = Vector2(_side, clampf(toward.normalized().y, -1.0, 1.0) * HEADING_TILT).normalized()
	_figure.rotation = heading.angle() + PI * 0.5
	_figure.position = -heading * FIGURE_REACH * cell_px + Vector2(0.0, FIGURE_DROP * cell_px)
	_figure.queue_redraw()


func is_available() -> bool:
	if not super.is_available():
		return false
	return not dragged or not yield_check.is_valid() or not bool(yield_check.call())


func get_figure() -> Node2D:
	return _figure


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_RATIO.y / SHADOW_RATIO.x))
	draw_circle(Vector2.ZERO, cell_px * SHADOW_RATIO.x, C_SHADOW)
	draw_set_transform(Vector2(-cell_px * STAIN_SHIFT, 0.0), 0.0, Vector2(1.0, STAIN_RATIO.y / STAIN_RATIO.x))
	draw_circle(Vector2.ZERO, cell_px * STAIN_RATIO.x * STAIN_CORE, C_STAIN)
	draw_set_transform(Vector2.ZERO)
	super._draw()
