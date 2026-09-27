# scene_stage.gd — Plató compartido de las escenas Aurora (P12) e interrogatorio (P15): sala dibujada por código con cámara, reparto sentado con CharacterPainter, bocadillos, insignias, panel lateral (Dock), temblor y línea de tiempo de golpes de guion.
# PROPIETARIO DE: el reparto en escena (actores, sillas, poses, marcas), sus bocadillos e insignias, los accesorios del decorado, la cámara y el temblor.
# ESCUCHA: nada.
class_name SceneStage
extends Control

## Lienzo de diseño DESIGN (1920×1080). Una CÁMARA encuadra un rectángulo del lienzo (frame) en la
## zona libre del control (set_safe_rect: lo que no tapan la cabecera ni el Dock) y llega a él con
## suavidad; suelo, paredes y pasillo se prolongan fuera del lienzo para cualquier encuadre.
## Capas, sin repintar cada fotograma: _back (suelo y paredes: se repinta al configurar o si la vista
## sale de lo ya pintado), _sorted (orden Y: muebles, sillas, actores y accesorios; cada uno es su
## propio CanvasItem: un actor se repinta al cambiar de fotograma y se desplaza sin repintarse; los
## LED y cintas se repintan a escenas.fps_accesorios) y _front (luz y viñeta del interrogatorio).
## Decorados (configure): SET_AURORA (sala acristalada de aurora_room: ventanal, pantalla, atril,
## rotafolio, mesa de juntas de 14 sillas) y SET_INTERROGATION (sala desnuda de interrogation_room:
## espejo espía, puerta, mesa metálica, lámpara, destructora). La banda de color sale de la planta de
## la sala (Database) y su paleta de data/art_bands.json; los materiales universales, de FurniturePainter.
## Accesorios (set_prop): screen_kicker / screen_title / screen_sub, poster, clock (Vector2i),
## flip_left / flip_right / flip_mid (rotafolio), door (1 abierta … 0 cerrada), lamp ("warm" |
## "neutral" | "harsh"), coffee (bool), slam (0..1), slam_text, paper (bool), nameplate.
## Actores: add_actor(id, cast_member(id), spot) con spot {pos, facing, seated, anim, chair (bool),
## chair_id (silla ya creada con add_chair), chair_style}. Con silla, pos es el centro del asiento.
## head_point(id) da el punto sobre la cabeza en coordenadas del control: bocadillos (say) e
## insignias (badge) son Control y se mantienen dentro de la zona libre.

signal camera_moved()

const DESIGN := Vector2(1920, 1080)
const SET_AURORA := "aurora"
const SET_INTERROGATION := "interrogation"
const ROOM_AURORA := "aurora_room"
const ROOM_INTERROGATION := "interrogation_room"
const PLAYER_ID := "player"
## Personal de Seguridad sin nombre (nadie ocupa Auditoría ni Seguridad, §12.5).
const GUARD_ID := "security_staff"
const GUARD_TIER := 2
const GUARD_NAME_KEY := "OCC_SECURITY_GUARD"
const GUARD_UNIFORM := "security"
const UNKNOWN_NAME_KEY := "SCENE_UNKNOWN_COLLEAGUE"
const STYLE_SAY := "say"
const STYLE_SHOUT := "shout"
const STYLE_WHISPER := "whisper"
const STYLE_NARRATE := "narrate"
const LAMP_WARM := "warm"
const LAMP_NEUTRAL := "neutral"
const LAMP_HARSH := "harsh"
const CHAIR_EXEC := "exec"
const CHAIR_LEATHER := "leather"
const CHAIR_STEEL := "steel"
## Alturas de la cabeza sobre los pies en px a escala 1 (arte de CharacterPainter).
const HEAD_STANDING := 74.0
const HEAD_SEATED := 60.0
const SEAT_PATH := "jugador.semilla_apariencia"
const B_SCALE_AURORA := "escenas.aurora_escala_personajes"
const B_SCALE_INTERROGATION := "escenas.interrogatorio_escala_personajes"
const B_BUBBLE_BASE := "escenas.bocadillo_segundos_base"
const B_BUBBLE_PER_CHAR := "escenas.bocadillo_segundos_por_caracter"
const B_BUBBLE_MAX := "escenas.bocadillo_segundos_max"
const B_CAMERA_RATE := "escenas.camara_suavizado"
const B_CAMERA_ZOOM := "escenas.camara_zoom_max"
const B_PROP_FPS := "escenas.fps_accesorios"
const B_DOCK_EM := "escenas.panel_ancho_em"
const B_DOCK_FRACTION := "escenas.panel_fraccion_max"
const B_DOCK_SECONDS := "escenas.panel_segundos"
const META_PRIVATE_THEME := "scene_private_theme"
## Materiales universales (no dependen de la banda): los de FurniturePainter, una sola fuente.
const C_STEEL := FurniturePainter.C_METAL
const C_STEEL_DARK := FurniturePainter.C_STEEL_DARK
const C_GLASS_DARK := FurniturePainter.C_SCREEN_DARK
const C_SCREEN_GLOW := FurniturePainter.C_SCREEN
const C_RED_LED := FurniturePainter.C_RED_LED
const C_GREEN_LED := FurniturePainter.C_GREEN_LED
const C_GOLD := FurniturePainter.C_GOLD
const C_CERAMIC := FurniturePainter.C_CERAMIC
const C_CARDBOARD := FurniturePainter.C_CARDBOARD
const C_WOOD := FurniturePainter.C_WOOD
const C_SHEET := FurniturePainter.C_PAPER
const C_WATER := FurniturePainter.C_WATER
## El lema del cartel encoge hasta caber (los textos en español son más largos).
const POSTER_FONT_MAX := 15
const POSTER_FONT_MIN := 10
## Margen (px de diseño) que el fondo pinta fuera de la vista: la cámara se mueve sin repintarlo.
const BACK_MARGIN := 640.0
## Orden Y de lo que cuelga de la pared (antes que cualquier mueble o actor).
const WALL_SORT := -100000.0
## Separación de bocadillos e insignias respecto al borde de la zona libre.
const OVERLAY_MARGIN := 12.0

## Sala Aurora (maquetación de diseño; 14 sillas como rooms/p12.json).
const AURORA_WALL_Y := 300.0
const AURORA_TABLE := Rect2(470, 596, 980, 132)
const AURORA_PODIUM := Vector2(356, 492)
const AURORA_RUG := Rect2(372, 520, 1176, 400)
const AURORA_SCREEN := Rect2(700, 30, 520, 236)
const AURORA_FLIPCHART := Rect2(1566, 380, 132, 190)
## Encuadre de la sala entera: pantalla, atril, rotafolio, mesa y fila delantera.
const FRAME_AURORA := Rect2(190, 0, 1530, 872)
const INTERROGATION_WALL_Y := 336.0
const INTERROGATION_TABLE := Rect2(690, 590, 540, 132)
const INTERROGATION_LAMP := Vector2(960, 250)
const INTERROGATION_DOOR := Rect2(1452, 70, 176, 266)
## Encuadres del interrogatorio: la sala (con el hueco de la ficha a la izquierda de la mesa), la
## puerta del portazo y el primer plano de la disculpa.
const FRAME_INTERROGATION := Rect2(110, 30, 1570, 840)
const FRAME_INTERROGATION_DOOR := Rect2(560, 20, 1110, 850)
const FRAME_INTERROGATION_CLOSE := Rect2(540, 170, 960, 700)
## Con el panel abierto: la mesa, el investigador y el hueco de la ficha (la puerta queda fuera).
const FRAME_INTERROGATION_TABLE := Rect2(100, 40, 1240, 820)

var set_kind: String = SET_AURORA
var band_id: String = ""
var char_scale: float = 1.0
var pal: Dictionary = {}
var _world: Node2D
var _back: Node2D
var _sorted: Node2D
var _front: Node2D
var _overlay: Control
var _actors: Dictionary = {}
var _actor_items: Dictionary = {}
var _chairs: Dictionary = {}
var _props: Dictionary = {}
var _prop_watchers: Dictionary = {}
var _animated: Array[StageItem] = []
var _set_items: Array[Node] = []
var _prop_clock: float = 0.0
var _prop_step: float = 0.1
var _bubbles: Dictionary = {}
var _badges: Dictionary = {}
var _furniture: FurniturePainter
var _vignette: GradientTexture2D
var _skyline: Array = []
var _moves: Dictionary = {}
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_px: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0
var _safe: Rect2 = Rect2()
var _frame: Rect2 = Rect2(Vector2.ZERO, DESIGN)
var _cam_scale: float = 1.0
var _cam_pos: Vector2 = Vector2.ZERO
var _cam_ready: bool = false
var _cam_rate: float = 1.0
var _cam_zoom: float = 1.0
var _back_bounds: Rect2 = Rect2()
var _overlays_dirty: bool = true
var _back_paints: int = 0


## Pieza del decorado en la capa ordenada por Y: painter(canvas) dibuja en coordenadas del lienzo de
## diseño (un hijo desplazado deshace la posición de orden). Solo se repinta con refresh().
class StageItem extends Node2D:
	var painter: Callable
	var _canvas: Node2D

	func _init(sort_y: float, p_painter: Callable) -> void:
		position = Vector2(0.0, sort_y)
		painter = p_painter
		_canvas = Node2D.new()
		_canvas.position = Vector2(0.0, -sort_y)
		_canvas.draw.connect(_on_draw)
		add_child(_canvas)

	func refresh() -> void:
		_canvas.queue_redraw()

	func _on_draw() -> void:
		painter.call(_canvas)


## Un personaje: se coloca en sus pies (orden Y) y se dibuja en su espacio local.
class ActorItem extends Node2D:
	var stage: SceneStage
	var actor_id: String = ""

	func _draw() -> void:
		stage.draw_actor(self, actor_id)


## Bocadillo de diálogo: panel con texto y cola dibujada hacia el personaje.
class Bubble extends PanelContainer:
	const TAIL := 18.0
	## Primer fotograma: el texto aún no tiene su alto; se mide, y se muestra en el siguiente.
	const FIRST_FRAME := -1.0
	var pending_hold: float = 0.0
	var style_id: String = SceneStage.STYLE_SAY
	var tail_x: float = 0.5
	var fill: Color = Color.WHITE
	var hold: float = 0.0
	var max_width: float = 0.0
	var sized: bool = false
	var _label: Label

	func _init(text: String, p_style: String, p_max_width: float) -> void:
		style_id = p_style
		max_width = p_max_width
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill = SceneStage.bubble_fill(p_style)
		add_theme_stylebox_override("panel", SceneStage.bubble_box(fill))
		_label = Label.new()
		_label.text = text
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var ink: Color = SceneStage.paper() if p_style == SceneStage.STYLE_NARRATE else SceneStage.ink()
		_label.add_theme_color_override("font_color", ink)
		if p_style == SceneStage.STYLE_SHOUT:
			_label.add_theme_font_override("font", UITheme.font(UITheme.FONT_BOLD))
		add_child(_label)

	func _ready() -> void:
		var natural: float = SceneStage.text_width(_label.text, _label)
		_label.custom_minimum_size.x = minf(max_width, natural + 2.0)
		modulate.a = 0.0

	func get_text() -> String:
		return _label.text

	func _draw() -> void:
		if style_id == SceneStage.STYLE_NARRATE:
			return
		var x: float = clampf(size.x * tail_x, 22.0, size.x - 22.0)
		var tip: Vector2 = Vector2(x + (size.x * 0.5 - x) * 0.15, size.y + TAIL)
		var pts: PackedVector2Array = [Vector2(x - 12, size.y - 3), Vector2(x + 12, size.y - 3), tip]
		draw_colored_polygon(pts, fill)
		draw_polyline(PackedVector2Array([pts[0], tip, pts[1]]), SceneStage.ink(), 3.0, true)


## Insignia sobre la cabeza (+15 aliado, −20 reputación...).
class Badge extends PanelContainer:
	func _init(text: String, color: Color) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box: StyleBoxFlat = SceneStage.bubble_box(color)
		box.set_corner_radius_all(16)
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		add_theme_stylebox_override("panel", box)
		var label: Label = Label.new()
		label.text = text
		label.add_theme_font_override("font", UITheme.font(UITheme.FONT_BOLD))
		label.add_theme_color_override("font_color", UITheme.readable_on(color))
		add_child(label)


## Foto de carné de un personaje (CharacterPainter.draw_portrait) para paneles de interfaz.
class PortraitBox extends Control:
	var appearance: Dictionary = {}
	var frame_color: Color = Color.BLACK

	func _init(p_appearance: Dictionary, min_size: Vector2) -> void:
		appearance = p_appearance
		custom_minimum_size = min_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame_color = SceneStage.ink()

	func _draw() -> void:
		if appearance.is_empty():
			return
		CharacterPainter.draw_portrait(self, appearance, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(Vector2.ZERO, size), frame_color, false, 3.0)


## Línea de tiempo de golpes de guion: then(espera, acción, parada) encadena; tick() ejecuta a su
## hora; flush() ejecuta todo ya (modo instantáneo de los tests); skip() adelanta hasta el siguiente
## golpe marcado como parada (incluido) — Esc salta la animación sin saltarse lo que hay que leer.
class Timeline extends RefCounted:
	var _beats: Array[Dictionary] = []
	var _clock: float = 0.0
	var _cursor: float = 0.0

	func then(delay: float, action: Callable, hold: bool = false) -> Timeline:
		_cursor = maxf(_cursor, _clock) + maxf(delay, 0.0)
		_beats.append({"at": _cursor, "fn": action, "hold": hold})
		return self

	func tick(delta: float) -> void:
		_clock += delta
		while not _beats.is_empty() and float(_beats[0]["at"]) <= _clock:
			var beat: Dictionary = _beats.pop_front()
			(beat["fn"] as Callable).call()

	func flush() -> void:
		while not _beats.is_empty():
			_run_next()

	func skip() -> void:
		while not _beats.is_empty():
			if _run_next():
				return

	func _run_next() -> bool:
		var beat: Dictionary = _beats.pop_front()
		_clock = maxf(_clock, float(beat["at"]))
		(beat["fn"] as Callable).call()
		return bool(beat["hold"])

	func is_busy() -> bool:
		return not _beats.is_empty()

	func clear() -> void:
		_beats.clear()
		_cursor = _clock


## Panel lateral derecho de las escenas: cabecera fija opcional (el medidor del interrogatorio),
## título, contenido desplazable (MenuScroll, abraza su contenido y solo desplaza si no cabe) y fila
## de botones fija. Al abrirse o cerrarse emite layout_changed: la cámara reencuadra la sala en lo
## que queda libre. Ancho: escenas.panel_ancho_em × tamaño de texto, con tope en fracción de pantalla.
class Dock extends MarginContainer:
	signal layout_changed()
	const MARGIN := 20
	var panel: PanelContainer
	var fixed_top: VBoxContainer
	var title: Label
	var content: VBoxContainer
	var footer: HBoxContainer
	var scroll: MenuScroll
	var instant: bool = false
	var _open: bool = false
	var _tween: Tween

	func _init() -> void:
		name = "Dock"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["left", "right", "top", "bottom"]:
			add_theme_constant_override("margin_" + side, MARGIN)
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var spacer: Control = Control.new()
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		panel = PanelContainer.new()
		panel.theme_type_variation = UITheme.V_MODAL
		panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		panel.visible = false
		row.add_child(panel)
		panel.add_child(_build_column())

	func _build_column() -> VBoxContainer:
		var column: VBoxContainer = VBoxContainer.new()
		fixed_top = VBoxContainer.new()
		column.add_child(fixed_top)
		title = SceneStage.ui_label("", UITheme.V_TITLE, true)
		column.add_child(title)
		scroll = MenuScroll.new()
		content = VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.set_content(content)
		column.add_child(scroll)
		footer = HBoxContainer.new()
		footer.alignment = BoxContainer.ALIGNMENT_END
		column.add_child(footer)
		return column

	func _ready() -> void:
		scroll.fit_to(self, panel)
		scroll.fade_color = UITheme.color("ink")

	## Vacía el panel, pone el título y lo muestra. Devuelve la caja del contenido.
	func open(title_text: String) -> VBoxContainer:
		SceneStage.clear_children(content)
		SceneStage.clear_children(footer)
		title.text = title_text
		title.visible = not title_text.is_empty()
		scroll.scroll.scroll_vertical = 0
		if not _open:
			_open = true
			panel.visible = true
			_animate_in()
			layout_changed.emit()
		return content

	func close() -> void:
		if not _open:
			return
		_open = false
		panel.visible = false
		SceneStage.clear_children(content)
		SceneStage.clear_children(footer)
		layout_changed.emit()

	func is_open() -> bool:
		return _open

	func add_buttons(buttons: Array[Button]) -> void:
		for b: Button in buttons:
			footer.add_child(b)
		if not buttons.is_empty():
			SceneStage.focus_later(buttons.back())

	## Ancho del panel para una pantalla de `host` (tamaño de texto vigente y tope de fracción).
	func fit_width(host: Vector2) -> void:
		var em: float = Database.get_balance_float(SceneStage.B_DOCK_EM) * SceneStage.font_px()
		var cap: float = host.x * Database.get_balance_float(SceneStage.B_DOCK_FRACTION)
		panel.custom_minimum_size.x = minf(em, cap)

	## Zona libre para la sala en una pantalla `host` con la cabecera hasta `top`.
	func free_rect(host: Vector2, top: float) -> Rect2:
		var right: float = host.x - MARGIN
		if _open:
			right -= panel.custom_minimum_size.x + MARGIN
		return Rect2(MARGIN, top, maxf(right - MARGIN, 1.0), maxf(host.y - top - MARGIN, 1.0))

	func _animate_in() -> void:
		var seconds: float = Database.get_balance_float(SceneStage.B_DOCK_SECONDS)
		if instant or seconds <= 0.0 or not is_inside_tree():
			panel.modulate.a = 1.0
			return
		if _tween != null and _tween.is_valid():
			_tween.kill()
		panel.modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_property(panel, "modulate:a", 1.0, seconds)


func _init() -> void:
	name = "SceneStage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_world = Node2D.new()
	add_child(_world)
	_back = Node2D.new()
	_back.draw.connect(_paint_back.bind(_back))
	_world.add_child(_back)
	_sorted = Node2D.new()
	_sorted.y_sort_enabled = true
	_world.add_child(_sorted)
	_front = Node2D.new()
	_front.draw.connect(_paint_front.bind(_front))
	_world.add_child(_front)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	resized.connect(_on_resized)


func _process(delta: float) -> void:
	_time += delta
	for id: String in _actors:
		_advance_actor(id, delta)
	_advance_moves(delta)
	var moved: bool = _update_camera(delta)
	_update_shake(delta)
	_tick_props(delta)
	_expire_bubbles(delta)
	if moved:
		camera_moved.emit()
	if _overlays_dirty:
		_place_overlays()


func _on_resized() -> void:
	_overlays_dirty = true


# ─── Configuración ────────────────────────────────────────────

## Decorado y banda de color (planta de la sala → data/art_bands.json) del plató.
func configure(p_set: String) -> void:
	set_kind = p_set
	var record: Dictionary = band_record(ROOM_INTERROGATION if p_set == SET_INTERROGATION else ROOM_AURORA)
	band_id = str(record.get("id", ""))
	pal = RoomPainter.palette_of(record)
	var path: String = B_SCALE_INTERROGATION if p_set == SET_INTERROGATION else B_SCALE_AURORA
	char_scale = Database.get_balance_float(path)
	_cam_rate = Database.get_balance_float(B_CAMERA_RATE)
	_cam_zoom = Database.get_balance_float(B_CAMERA_ZOOM)
	_prop_step = 1.0 / maxf(Database.get_balance_float(B_PROP_FPS), 1.0)
	var style: Dictionary = {"band": band_id, "pal": pal, "room_id": "stage_" + p_set,
			"cell": FurniturePainter.REFERENCE_CELL * char_scale, "kit": "",
			"plastic": bool(record.get("plants_are_plastic", true)), "lighting": {}}
	_furniture = FurniturePainter.new(style)
	_vignette = _make_vignette()
	_skyline = _make_skyline()
	_frame = FRAME_INTERROGATION if p_set == SET_INTERROGATION else FRAME_AURORA
	_build_set()
	_back.queue_redraw()
	_front.queue_redraw()


## Registro de art_bands.json de la sala: su banda declarada o la de su planta.
static func band_record(room_id: String) -> Dictionary:
	var room: RoomData = Database.get_room(room_id)
	if room == null:
		return {}
	if not room.art_band.is_empty():
		var named: Dictionary = Database.get_art_band(room.art_band)
		if not named.is_empty():
			return named
	return Database.get_art_band_for_floor(room.floor)


func set_prop(prop: String, value: Variant) -> void:
	_props[prop] = value
	var watchers: Array = _prop_watchers.get(prop, [])
	for refresh: Callable in watchers:
		refresh.call()
	if watchers.is_empty():
		_back.queue_redraw()
		_front.queue_redraw()


func get_prop(prop: String, fallback: Variant = null) -> Variant:
	return _props.get(prop, fallback)


func band_color(key: String) -> Color:
	return pal.get(key, Color.GRAY)


## Sillas de la sala Aurora en el orden de rooms/p12.json: 6 al fondo (miran al sur), 2 en las
## cabeceras y 6 delante (de espaldas). {center: Vector2, facing: Vector2}.
static func aurora_seats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t: Rect2 = AURORA_TABLE
	for i: int in 6:
		out.append({"center": Vector2(t.position.x + t.size.x * (i + 0.5) / 6.0, t.position.y - 18.0),
				"facing": Vector2.DOWN})
	out.append({"center": Vector2(t.position.x - 58.0, t.get_center().y + 20.0), "facing": Vector2.RIGHT})
	out.append({"center": Vector2(t.end.x + 58.0, t.get_center().y + 20.0), "facing": Vector2.LEFT})
	for i: int in 6:
		out.append({"center": Vector2(t.position.x + t.size.x * (i + 0.5) / 6.0, t.end.y + 64.0),
				"facing": Vector2.UP})
	return out


## Punto de pie del orador junto al atril (a su izquierda y un paso atrás, mirando a la sala).
static func aurora_podium_spot() -> Vector2:
	return AURORA_PODIUM + Vector2(-86, -20)


static func interrogation_spots() -> Dictionary:
	var t: Rect2 = INTERROGATION_TABLE
	return {
		"investigator": Vector2(t.get_center().x, t.position.y - 22.0),
		"player": Vector2(t.get_center().x, t.end.y + 74.0),
		"investigator_standing": Vector2(t.end.x + 70.0, t.position.y + 8.0),
		"card": Vector2(t.position.x - 290.0, t.get_center().y - 40.0),
	}


# ─── Cámara ───────────────────────────────────────────────────

## Zona libre del control (sus coordenadas) donde encuadrar; vacía = todo el control.
func set_safe_rect(rect: Rect2) -> void:
	if rect == _safe:
		return
	_safe = rect
	_overlays_dirty = true


func safe_rect() -> Rect2:
	if _safe.size.x < 1.0 or _safe.size.y < 1.0:
		return Rect2(Vector2.ZERO, size)
	return _safe


## Encuadra `design_rect` (del lienzo) en la zona libre; la cámara llega con suavidad.
func frame(design_rect: Rect2) -> void:
	_frame = design_rect


func get_frame() -> Rect2:
	return _frame


## Rectángulo (del lienzo) que contiene a esos actores de pies a cabeza, con margen `pad`.
func actors_rect(ids: Array[String], pad: Vector2) -> Rect2:
	var box: Rect2 = Rect2()
	var first: bool = true
	for id: String in ids:
		if not _actors.has(id):
			continue
		var feet: Vector2 = actor_feet(id)
		var r: Rect2 = Rect2(feet - Vector2(0, HEAD_STANDING * char_scale), Vector2(0, HEAD_STANDING * char_scale))
		box = r if first else box.merge(r)
		first = false
	return box.grow_individual(pad.x, pad.y, pad.x, pad.y * 0.5)


func snap_camera() -> void:
	if safe_rect().size.x < 1.0 or safe_rect().size.y < 1.0:
		_cam_ready = false
		return
	_cam_scale = _goal_scale()
	_cam_pos = _goal_position(_cam_scale)
	_cam_ready = true
	_apply_camera()


func is_camera_settled() -> bool:
	var gs: float = _goal_scale()
	return is_equal_approx(_cam_scale, gs) and _cam_pos.is_equal_approx(_goal_position(gs))


func _goal_scale() -> float:
	var safe: Rect2 = safe_rect()
	var s: float = minf(safe.size.x / maxf(_frame.size.x, 1.0), safe.size.y / maxf(_frame.size.y, 1.0))
	return clampf(s, 0.05, maxf(_cam_zoom, 0.05))


## Centra el encuadre en la zona libre; si sobra alto, el sobrante va al suelo (abajo) antes que al
## vacío sobre la pared del fondo (el lienzo no dibuja nada por encima de y = 0).
func _goal_position(s: float) -> Vector2:
	var safe: Rect2 = safe_rect()
	var pos: Vector2 = safe.get_center() - _frame.get_center() * s
	if pos.y > safe.position.y:
		pos.y = safe.position.y
	return pos


func _update_camera(delta: float) -> bool:
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	if not _cam_ready:
		snap_camera()
		return true
	var gs: float = _goal_scale()
	var gp: Vector2 = _goal_position(gs)
	if is_equal_approx(_cam_scale, gs) and _cam_pos.is_equal_approx(gp):
		return false
	var k: float = 1.0 - exp(-_cam_rate * delta)
	_cam_scale = lerpf(_cam_scale, gs, k)
	_cam_pos = _cam_pos.lerp(gp, k)
	if absf(_cam_scale - gs) < 0.0005 and _cam_pos.distance_to(gp) < 0.5:
		_cam_scale = gs
		_cam_pos = gp
	_apply_camera()
	return true


func _apply_camera() -> void:
	_world.scale = Vector2(_cam_scale, _cam_scale)
	_world.position = _cam_pos + _shake_offset
	_overlays_dirty = true
	var view: Rect2 = view_rect()
	if _back_bounds.encloses(view):
		return
	_back_bounds = view.grow(BACK_MARGIN * maxf(1.0, 1.0 / maxf(_cam_scale, 0.1)))
	_back.queue_redraw()
	_front.queue_redraw()


## Coordenadas de diseño → coordenadas del control.
func to_screen(design_point: Vector2) -> Vector2:
	return _world.position + design_point * _cam_scale


func screen_scale() -> float:
	return _cam_scale


## Rectángulo del lienzo de diseño visible en el control (puede exceder DESIGN).
func view_rect() -> Rect2:
	var s: float = maxf(_cam_scale, 0.001)
	return Rect2(-_cam_pos / s, size / s)


# ─── Reparto ──────────────────────────────────────────────────

## {appearance, tier, name} de un personaje: el jugador (semilla fija y escalón actual), un NPC en
## ejecución, un nominado del catálogo, el vigilante genérico o, en último caso, uno por semilla.
static func cast_member(npc_id: String) -> Dictionary:
	if npc_id == PLAYER_ID:
		var tier: int = maxi(1, PlayerState.get_tier())
		var me: Dictionary = CharacterPainter.appearance_from_seed(
				Database.get_balance_int(SEAT_PATH), tier, false, "")
		me["uniform"] = CharacterPainter.uniform_for_disguise(PlayerState.get_disguise())
		return {"appearance": me, "tier": tier, "name": PlayerState.get_player_name()}
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null:
		return {"appearance": CharacterPainter.appearance_for_npc(npc), "tier": npc.tier, "name": npc.name}
	var named: NPCData = Database.get_named_npc(npc_id)
	if named != null:
		var occ: OccupationData = Database.get_occupation(named.occupation)
		var t: int = occ.tier if occ != null else int(named.extra.get("tier", 1))
		return {"appearance": CharacterPainter.appearance_for_named(named, t), "tier": t, "name": named.name}
	if npc_id == GUARD_ID:
		var guard: Dictionary = CharacterPainter.appearance_from_seed(hash(npc_id), GUARD_TIER, false, "")
		guard["uniform"] = GUARD_UNIFORM
		return {"appearance": guard, "tier": GUARD_TIER, "name": TranslationServer.translate(GUARD_NAME_KEY)}
	return {"appearance": CharacterPainter.appearance_from_seed(hash(npc_id), 1, false, ""),
			"tier": 1, "name": TranslationServer.translate(UNKNOWN_NAME_KEY)}


## spot: {pos, facing, seated (bool), anim, chair (bool), chair_id, chair_style}.
func add_actor(actor_id: String, member: Dictionary, spot: Dictionary) -> void:
	var seated: bool = bool(spot.get("seated", false))
	var pos: Vector2 = spot.get("pos", Vector2.ZERO)
	var seat: String = str(spot.get("chair_id", ""))
	if seat.is_empty() and bool(spot.get("chair", seated)):
		seat = actor_id
		add_chair(seat, pos, spot.get("facing", Vector2.DOWN), str(spot.get("chair_style", CHAIR_EXEC)))
	if _chairs.has(seat) and seated:
		pos = _chairs[seat]["center"]
	_actors[actor_id] = {"id": actor_id, "app": member.get("appearance", {}),
		"tier": int(member.get("tier", 1)), "name": str(member.get("name", actor_id)),
		"pos": pos, "facing": spot.get("facing", Vector2.DOWN), "look": Vector2.ZERO,
		"seated": seated, "seat": seat, "anim": str(spot.get("anim", "sit" if seated else "idle")),
		"frame": 0, "t": 0.0, "then": "", "marker": Color.TRANSPARENT}
	var item: ActorItem = ActorItem.new()
	item.stage = self
	item.actor_id = actor_id
	_actor_items[actor_id] = item
	_sorted.add_child(item)
	_sync_actor(actor_id)


func has_actor(actor_id: String) -> bool:
	return _actors.has(actor_id)


func get_actor(actor_id: String) -> Dictionary:
	return _actors.get(actor_id, {})


func actor_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _actors:
		out.append(id)
	return out


func set_actor_visible(actor_id: String, shown: bool) -> void:
	if _actor_items.has(actor_id):
		(_actor_items[actor_id] as Node2D).visible = shown
		_overlays_dirty = true


## Silla (con o sin ocupante). Se dibuja en dos pasadas ordenadas por Y: asiento y respaldo trasero
## antes del ocupante; el respaldo que queda delante (silla de espaldas a cámara) después.
func add_chair(chair_id: String, center: Vector2, facing: Vector2, chair_style: String) -> void:
	if _chairs.has(chair_id):
		return
	var chair: Dictionary = {"center": center, "facing": facing, "style": chair_style}
	_chairs[chair_id] = chair
	var s: float = char_scale
	_add_item(center.y - 30.0 * s, _paint_chair.bind(chair, false))
	if facing.y < -0.5:
		_add_item(center.y + 30.0 * s, _paint_chair.bind(chair, true))


func has_chair(chair_id: String) -> bool:
	return _chairs.has(chair_id)


## Cambia la animación (y, si se da, el rumbo). `then`: animación a la que vuelve al acabar una
## animación sin bucle ("" = se queda en el último fotograma).
func set_anim(actor_id: String, anim: String, facing: Vector2 = Vector2.ZERO, then: String = "") -> void:
	var a: Dictionary = _actors.get(actor_id, {})
	if a.is_empty():
		return
	a["anim"] = anim
	a["frame"] = 0
	a["t"] = 0.0
	a["then"] = then
	if facing != Vector2.ZERO:
		a["facing"] = facing.normalized()
	_redraw_actor(actor_id)


func set_look(actor_id: String, look: Vector2) -> void:
	if _actors.has(actor_id):
		_actors[actor_id]["look"] = look
		_redraw_actor(actor_id)


## Mira a otro actor (o deja de mirar con target vacío).
func look_at_actor(actor_id: String, target_id: String) -> void:
	if not _actors.has(actor_id):
		return
	var look: Vector2 = Vector2.ZERO
	if _actors.has(target_id) and target_id != actor_id:
		look = (actor_feet(target_id) - actor_feet(actor_id)).normalized()
	set_look(actor_id, look)


## De pie junto a su silla (seated = false) o de vuelta a ella (mirando como la silla).
func set_seated(actor_id: String, seated: bool) -> void:
	var a: Dictionary = _actors.get(actor_id, {})
	if a.is_empty() or not _chairs.has(str(a["seat"])):
		return
	_moves.erase(actor_id)
	var chair: Dictionary = _chairs[a["seat"]]
	a["seated"] = seated
	a["pos"] = chair["center"] if seated else chair["center"] - chair["facing"] * 14.0 * char_scale
	set_anim(actor_id, "sit" if seated else "idle", chair["facing"])
	_sync_actor(actor_id)


## Punto de pie delante de la silla del actor (para volver andando a sentarse).
func seat_point(actor_id: String) -> Vector2:
	var a: Dictionary = _actors.get(actor_id, {})
	if a.is_empty() or not _chairs.has(str(a["seat"])):
		return actor_feet(actor_id)
	var chair: Dictionary = _chairs[a["seat"]]
	return (chair["center"] as Vector2) - (chair["facing"] as Vector2) * 14.0 * char_scale


func move_actor(actor_id: String, pos: Vector2) -> void:
	if _actors.has(actor_id):
		_actors[actor_id]["pos"] = pos
		_actors[actor_id]["seated"] = false
		_sync_actor(actor_id)
		_redraw_actor(actor_id)


## Camina de su posición a `target` en `seconds` (animación walk), pasando por `via` si se da (rodear
## la mesa), y al llegar mira a `end_facing` con `end_anim`. finish_moves() completa los paseos.
func walk_to(actor_id: String, target: Vector2, seconds: float, end_facing: Vector2,
		end_anim: String = "idle", via: Array[Vector2] = []) -> void:
	var a: Dictionary = _actors.get(actor_id, {})
	if a.is_empty():
		return
	var points: Array[Vector2] = [_origin_of(a)]
	points.append_array(via)
	points.append(target)
	a["seated"] = false
	a["pos"] = points[0]
	a["look"] = Vector2.ZERO
	set_anim(actor_id, "walk", points[1] - points[0])
	_moves[actor_id] = {"points": points, "t": 0.0, "dur": maxf(seconds, 0.001),
			"facing": end_facing, "anim": end_anim, "leg": 0}
	_sync_actor(actor_id)


func is_moving() -> bool:
	return not _moves.is_empty()


func finish_moves() -> void:
	for id: String in _moves.keys():
		_end_move(id)


func _advance_moves(delta: float) -> void:
	for id: String in _moves.keys():
		var m: Dictionary = _moves[id]
		m["t"] = float(m["t"]) + delta
		var k: float = clampf(float(m["t"]) / float(m["dur"]), 0.0, 1.0)
		var at: Dictionary = path_point(m["points"], k)
		_actors[id]["pos"] = at["pos"]
		if int(at["leg"]) != int(m["leg"]):
			m["leg"] = at["leg"]
			_actors[id]["facing"] = (at["dir"] as Vector2)
			_redraw_actor(id)
		_sync_actor(id)
		if k >= 1.0:
			_end_move(id)


## Punto a la fracción `k` (0..1) de una polilínea, por longitud: {pos, leg, dir}.
static func path_point(points: Array[Vector2], k: float) -> Dictionary:
	var total: float = 0.0
	for i: int in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var goal: float = total * k
	for i: int in points.size() - 1:
		var seg: float = points[i].distance_to(points[i + 1])
		if goal <= seg or i == points.size() - 2:
			var f: float = clampf(goal / maxf(seg, 0.001), 0.0, 1.0)
			return {"pos": points[i].lerp(points[i + 1], f), "leg": i,
					"dir": (points[i + 1] - points[i]).normalized()}
		goal -= seg
	return {"pos": points.back(), "leg": 0, "dir": Vector2.DOWN}


func _end_move(actor_id: String) -> void:
	var m: Dictionary = _moves[actor_id]
	_moves.erase(actor_id)
	if not _actors.has(actor_id):
		return
	_actors[actor_id]["pos"] = (m["points"] as Array).back()
	set_anim(actor_id, str(m["anim"]), m["facing"])
	_sync_actor(actor_id)


## Marca de color bajo los pies (acusador, aliados...). TRANSPARENT la quita.
func set_marker(actor_id: String, color: Color) -> void:
	if _actors.has(actor_id):
		_actors[actor_id]["marker"] = color
		_redraw_actor(actor_id)


func clear_markers() -> void:
	for id: String in _actors:
		set_marker(id, Color.TRANSPARENT)


func actor_feet(actor_id: String) -> Vector2:
	var a: Dictionary = _actors.get(actor_id, {})
	if a.is_empty():
		return Vector2.ZERO
	return _origin_of(a)


## Punto sobre la cabeza del actor en coordenadas de este control.
func head_point(actor_id: String) -> Vector2:
	var a: Dictionary = _actors.get(actor_id, {})
	if a.is_empty():
		return size * 0.5
	var head: float = (HEAD_SEATED if bool(a["seated"]) else HEAD_STANDING) * char_scale
	head *= sqrt(float((a["app"] as Dictionary).get("volume", 1.0)))
	return to_screen(_origin_of(a) - Vector2(0, head))


func _origin_of(a: Dictionary) -> Vector2:
	if not bool(a["seated"]):
		return a["pos"]
	var offset: Vector2 = CharacterPainter.seat_origin(Vector2.ZERO, a["app"], int(a["tier"]))
	return (a["pos"] as Vector2) + offset * char_scale


func _sync_actor(actor_id: String) -> void:
	var item: ActorItem = _actor_items.get(actor_id)
	if item != null:
		item.position = _origin_of(_actors[actor_id])
		_overlays_dirty = true


func _redraw_actor(actor_id: String) -> void:
	var item: ActorItem = _actor_items.get(actor_id)
	if item != null:
		item.queue_redraw()


func _advance_actor(actor_id: String, delta: float) -> void:
	var a: Dictionary = _actors[actor_id]
	var fps: float = CharacterPainter.anim_fps(str(a["anim"]))
	if fps <= 0.0:
		return
	a["t"] = float(a["t"]) + delta
	while float(a["t"]) >= 1.0 / fps:
		a["t"] = float(a["t"]) - 1.0 / fps
		var next: int = CharacterAnim.next_frame(str(a["anim"]), int(a["frame"]))
		if next < 0 or (next == int(a["frame"]) and not str(a["then"]).is_empty()):
			if not str(a["then"]).is_empty():
				set_anim(actor_id, str(a["then"]))
			return
		if next != int(a["frame"]):
			a["frame"] = next
			_redraw_actor(actor_id)


func draw_actor(ci: CanvasItem, actor_id: String) -> void:
	var a: Dictionary = _actors[actor_id]
	var marker: Color = a["marker"]
	if marker.a > 0.0:
		var r: Vector2 = Vector2(26.0, 11.0) * char_scale
		ci.draw_colored_polygon(CharacterStyle.ellipse(Vector2.ZERO, r), Color(marker, 0.45))
		ci.draw_polyline(_closed(CharacterStyle.ellipse(Vector2.ZERO, r)), marker, 3.0, true)
	var extra: Dictionary = {"seated": bool(a["seated"])}
	if (a["look"] as Vector2) != Vector2.ZERO:
		extra["look"] = a["look"]
	var pose: Dictionary = CharacterPainter.make_pose(str(a["anim"]), int(a["frame"]), a["facing"], extra)
	pose["origin"] = Vector2.ZERO
	pose["scale"] = char_scale
	CharacterPainter.draw(ci, a["app"], int(a["tier"]), pose)


# ─── Bocadillos e insignias ───────────────────────────────────

## Bocadillo sobre el actor. seconds < 0 → tiempo de lectura; 0 → hasta que se retire. "" lo quita.
func say(actor_id: String, text: String, style: String = STYLE_SAY, seconds: float = -1.0) -> void:
	if _bubbles.has(actor_id):
		(_bubbles[actor_id] as Node).queue_free()
		_bubbles.erase(actor_id)
	if text.is_empty() or not _actors.has(actor_id):
		return
	var bubble: Bubble = Bubble.new(text, style, 460.0 * ui_scale())
	bubble.pending_hold = reading_time(text) if seconds < 0.0 else seconds
	bubble.hold = Bubble.FIRST_FRAME
	_overlay.add_child(bubble)
	_bubbles[actor_id] = bubble
	_overlays_dirty = true


## Segundos de lectura de un texto (balance escenas.bocadillo_*).
static func reading_time(text: String) -> float:
	var t: float = Database.get_balance_float(B_BUBBLE_BASE) \
			+ Database.get_balance_float(B_BUBBLE_PER_CHAR) * float(text.length())
	return minf(t, Database.get_balance_float(B_BUBBLE_MAX))


func bubble_text(actor_id: String) -> String:
	var bubble: Bubble = _bubbles.get(actor_id) as Bubble
	return bubble.get_text() if bubble != null and is_instance_valid(bubble) else ""


## Rectángulo (coordenadas del control) del bocadillo de un actor; vacío si no habla.
func bubble_rect(actor_id: String) -> Rect2:
	var bubble: Bubble = _bubbles.get(actor_id) as Bubble
	return bubble.get_rect() if bubble != null and is_instance_valid(bubble) else Rect2()


func clear_bubbles() -> void:
	for id: String in _bubbles.keys():
		say(id, "")


func badge(actor_id: String, text: String, color: Color) -> void:
	if _badges.has(actor_id):
		(_badges[actor_id] as Node).queue_free()
		_badges.erase(actor_id)
	if text.is_empty() or not _actors.has(actor_id):
		return
	var b: Badge = Badge.new(text, color)
	_overlay.add_child(b)
	b.reset_size()
	_badges[actor_id] = b
	_overlays_dirty = true


func badge_text(actor_id: String) -> String:
	var b: Badge = _badges.get(actor_id) as Badge
	if b == null or not is_instance_valid(b) or b.get_child_count() == 0:
		return ""
	return (b.get_child(0) as Label).text


## Rectángulo (coordenadas del control) de la insignia de un actor; vacío si no tiene.
func badge_rect(actor_id: String) -> Rect2:
	var b: Badge = _badges.get(actor_id) as Badge
	return b.get_rect() if b != null and is_instance_valid(b) else Rect2()


func clear_badges() -> void:
	for id: String in _badges.keys():
		badge(id, "", Color.WHITE)


func _expire_bubbles(delta: float) -> void:
	for id: String in _bubbles.keys():
		var bubble: Bubble = _bubbles[id]
		if bubble.hold <= 0.0 or bubble.hold == Bubble.FIRST_FRAME:
			continue
		bubble.hold -= delta
		if bubble.hold <= 0.0:
			say(id, "")


## Coloca insignias y bocadillos sobre las cabezas, siempre dentro de la zona libre.
func _place_overlays() -> void:
	_overlays_dirty = false
	var safe: Rect2 = safe_rect().grow(-OVERLAY_MARGIN)
	for id: String in _badges:
		var b: Control = _badges[id]
		var head: Vector2 = head_point(id)
		var bx: float = clampf(head.x - b.size.x * 0.5, safe.position.x, maxf(safe.end.x - b.size.x, safe.position.x))
		b.position = Vector2(bx, maxf(head.y - b.size.y - 6.0, safe.position.y))
	for id: String in _bubbles:
		_place_bubble(id, safe)


func _place_bubble(actor_id: String, safe: Rect2) -> void:
	var bubble: Bubble = _bubbles[actor_id]
	if bubble.hold == Bubble.FIRST_FRAME:
		bubble.reset_size()
		bubble.hold = bubble.pending_hold
		_overlays_dirty = true
		return
	if not bubble.sized:
		bubble.reset_size()
		bubble.sized = true
	var head: Vector2 = head_point(actor_id) - Vector2(0, Bubble.TAIL + 6.0)
	if _badges.has(actor_id):
		head.y = minf(head.y, (_badges[actor_id] as Control).position.y - Bubble.TAIL - 4.0)
	var x: float = clampf(head.x - bubble.size.x * 0.5, safe.position.x,
			maxf(safe.end.x - bubble.size.x, safe.position.x))
	var y: float = maxf(head.y - bubble.size.y, safe.position.y)
	bubble.position = Vector2(x, y)
	bubble.tail_x = (head.x - x) / maxf(bubble.size.x, 1.0)
	bubble.modulate.a = 1.0
	bubble.queue_redraw()


static func bubble_fill(style: String) -> Color:
	match style:
		STYLE_SHOUT:
			return UITheme.color("focus")
		STYLE_WHISPER:
			return paper().lerp(UITheme.color("muted"), 0.3)
		STYLE_NARRATE:
			return Color(ink(), 0.92)
	return paper()


static func bubble_box(fill: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = ink()
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_color = UITheme.color("shadow")
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 3)
	box.anti_aliasing = true
	return box


# ─── Utilidades de interfaz (compartidas por las escenas) ─────

static func ink() -> Color:
	return UITheme.color("ink")


static func paper() -> Color:
	return UITheme.color("paper")


## Factor de la interfaz dibujada a mano respecto al texto medio (tamaño de texto).
static func ui_scale() -> float:
	var medium: float = float(maxi(UITheme.base_font_size(UITheme.TEXT_MEDIUM), 1))
	return maxf(float(UITheme.base_font_size(UITheme.current_text_size)) / medium, 1.0)


## Tamaño base del texto vigente en px (incluye la escala táctil).
static func font_px() -> float:
	return float(UITheme.base_font_size(UITheme.current_text_size))


## Número con un decimal y el separador del idioma (4.5 / 4,5).
static func decimal(value: float) -> String:
	var text: String = "%.1f" % value
	return text.replace(".", ",") if TranslationServer.get_locale().begins_with("es") else text


## Ancho natural de una línea de texto con la fuente del label.
static func text_width(text: String, label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else 0.0


static func ui_label(text: String, variation: String = "", wrap: bool = false,
		color: Color = Color.TRANSPARENT) -> Label:
	var l: Label = Label.new()
	l.text = text
	if not variation.is_empty():
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


static func ui_button(text: String, variation: String, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = variation
	b.custom_minimum_size.y = MenuKit.MIN_TOUCH
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(action)
	return b


## Da el foco a `control` al final del fotograma si sigue en pantalla (referencia débil: el panel
## puede haberse rehecho y liberado el control antes).
static func focus_later(control: Control) -> void:
	var ref: WeakRef = weakref(control)
	var grab: Callable = func() -> void:
		var target: Control = ref.get_ref() as Control
		if target != null and target.is_inside_tree() and target.is_visible_in_tree():
			target.grab_focus()
	grab.call_deferred()


static func clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Textos visibles (Label, Button y bocadillos) bajo `node`, en orden de árbol (tests y QA).
static func collect_texts(node: Node, out: Array[String]) -> void:
	for child: Node in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		collect_texts(child, out)


## Reproduce el primer efecto de `ids` que exista en SfxBank si hay AudioDirector (con su subtítulo,
## §13.10). Devuelve el id reproducido ("" si ninguno o sin director).
static func play_sfx(host: Node, ids: Array[String]) -> String:
	var director: AudioDirector = _director(host)
	if director == null:
		return ""
	for id: String in ids:
		if SfxBank.has_sfx(id):
			director.play_sfx(id)
			return id
	return ""


## Subtítulo propio de la escena en el canal de subtítulos (§13.10). false sin AudioDirector.
static func post_subtitle(host: Node, key: String) -> bool:
	var director: AudioDirector = _director(host)
	return director != null and director.post_subtitle(key, AudioDirector.NO_POSITION, SfxBank.IMPORTANCE_INFO)


## Corta el hilo musical `seconds` (el golpe de efecto del portazo).
static func cut_music(host: Node, seconds: float) -> void:
	var director: AudioDirector = _director(host)
	if director != null:
		director.interrupt_muzak(seconds)


static func _director(host: Node) -> AudioDirector:
	if host == null or not host.is_inside_tree():
		return null
	return AudioDirector.find(host.get_tree())


## Aplica el tema de la interfaz si ningún antecesor (UIRoot) lo da ya; ese tema propio se
## reconstruye (refresh_theme) si cambian el tamaño de texto o el contraste.
static func ensure_theme(ctrl: Control) -> void:
	var node: Node = ctrl.get_parent()
	while node != null:
		if node is Control and (node as Control).theme != null:
			return
		if node is Window and (node as Window).theme != null:
			return
		node = node.get_parent()
	ctrl.theme = UITheme.build(UITheme.current_text_size, UITheme.current_high_contrast)
	ctrl.set_meta(META_PRIVATE_THEME, _theme_key())


## Reconstruye el tema propio si los ajustes de texto cambiaron. true si lo reconstruyó.
static func refresh_theme(ctrl: Control) -> bool:
	if not ctrl.has_meta(META_PRIVATE_THEME) or int(ctrl.get_meta(META_PRIVATE_THEME)) == _theme_key():
		return false
	ctrl.theme = UITheme.build(UITheme.current_text_size, UITheme.current_high_contrast)
	ctrl.set_meta(META_PRIVATE_THEME, _theme_key())
	return true


static func _theme_key() -> int:
	return UITheme.base_font_size(UITheme.current_text_size) * 2 + (1 if UITheme.current_high_contrast else 0)


# ─── Temblor ──────────────────────────────────────────────────

func shake(px: float, seconds: float) -> void:
	_shake_px = px
	_shake_total = maxf(seconds, 0.001)
	_shake_left = seconds


func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		if _shake_offset != Vector2.ZERO:
			_shake_offset = Vector2.ZERO
			_apply_camera()
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	var amount: float = _shake_px * _shake_left / _shake_total
	_shake_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * amount
	_apply_camera()


# ─── Montaje del decorado ─────────────────────────────────────

func _add_item(sort_y: float, painter: Callable, watch: Array[String] = [], animated: bool = false) -> StageItem:
	var item: StageItem = StageItem.new(sort_y, painter)
	_sorted.add_child(item)
	_set_items.append(item)
	for prop: String in watch:
		var list: Array = _prop_watchers.get(prop, [])
		list.append(item.refresh)
		_prop_watchers[prop] = list
	if animated:
		_animated.append(item)
	return item


func _watch_layer(props: Array[String], layer: Node2D) -> void:
	for prop: String in props:
		var list: Array = _prop_watchers.get(prop, [])
		list.append(layer.queue_redraw)
		_prop_watchers[prop] = list


func _build_set() -> void:
	for node: Node in _set_items:
		node.queue_free()
	_set_items.clear()
	_animated.clear()
	_prop_watchers.clear()
	if set_kind == SET_INTERROGATION:
		_build_interrogation_set()
	else:
		_build_aurora_set()


func _build_aurora_set() -> void:
	var t: Rect2 = AURORA_TABLE
	_add_item(WALL_SORT, _paint_aurora_wall, ["screen_kicker", "screen_title", "screen_sub", "poster", "clock"])
	_add_item(WALL_SORT + 1.0, _paint_camera_dome.bind(Vector2(DESIGN.x - 70.0, 34.0)), [], true)
	_add_item(t.get_center().y + 40.0, _paint_meeting_table)
	_add_item(t.get_center().y + 41.0, _paint_conference_phone.bind(t.get_center() + Vector2(0, 2)), [], true)
	_add_item(AURORA_PODIUM.y, _paint_podium)
	_add_item(AURORA_FLIPCHART.end.y, _paint_flipchart, ["flip_left", "flip_right", "flip_mid"])
	_add_item(440.0, _paint_furniture.bind("plant", Rect2(84, 330, 110, 110)))
	_add_item(1010.0, _paint_furniture.bind("plant", Rect2(84, 900, 110, 110)))
	_add_item(1010.0, _paint_furniture.bind("plant", Rect2(1726, 900, 110, 110)))
	_add_item(770.0, _paint_furniture.bind("water_cooler", Rect2(1740, 660, 110, 110)))
	_add_item(720.0, _paint_furniture.bind("coffee_machine", Rect2(60, 610, 110, 110)))


func _build_interrogation_set() -> void:
	var t: Rect2 = INTERROGATION_TABLE
	_add_item(WALL_SORT, _paint_door, ["door"])
	_add_item(WALL_SORT + 1.0, _paint_camera_dome.bind(Vector2(DESIGN.x - 70.0, 34.0)), [], true)
	_add_item(WALL_SORT + 2.0, _paint_furniture.bind("fire_extinguisher", Rect2(1390, 200, 44, 110)))
	_add_item(t.get_center().y + 20.0, _paint_steel_table, ["paper", "nameplate"])
	_add_item(t.get_center().y + 21.0, _paint_recorder.bind(Vector2(t.end.x - 110, t.position.y + 40)), [], true)
	_add_item(t.get_center().y + 22.0, _paint_coffee.bind(Vector2(t.get_center().x + 92, t.end.y - 40)),
			["coffee"], true)
	_add_item(590.0, _paint_furniture.bind("filing_cabinet", Rect2(1716, 470, 110, 120)))
	_add_item(600.0, _paint_shredder.bind(Rect2(1586, 506, 96, 94)), [], true)
	_add_item(470.0, _paint_dead_plant.bind(Vector2(160, 470)))
	_add_item(462.0, _paint_side_chair.bind(Vector2(330, 440)))
	_watch_layer(["lamp", "slam", "slam_text"], _front)


func _tick_props(delta: float) -> void:
	if _animated.is_empty():
		return
	_prop_clock += delta
	if _prop_clock < _prop_step:
		return
	_prop_clock = fmod(_prop_clock, _prop_step)
	for item: StageItem in _animated:
		item.refresh()


# ─── Dibujo común ─────────────────────────────────────────────

## Veces que se ha pintado el fondo (diagnóstico: no debe repintarse cada fotograma).
func back_paint_count() -> int:
	return _back_paints


func _paint_back(ci: Node2D) -> void:
	if pal.is_empty():
		return
	_back_paints += 1
	if set_kind == SET_INTERROGATION:
		_paint_interrogation_back(ci, _back_bounds)
	else:
		_paint_aurora_back(ci, _back_bounds)


func _paint_front(ci: Node2D) -> void:
	if pal.is_empty() or set_kind != SET_INTERROGATION:
		return
	_paint_interrogation_front(ci, _back_bounds)


func _paint_furniture(ci: CanvasItem, type: String, r: Rect2) -> void:
	_furniture.draw_item(ci, {"type": type, "rotation": 0, "pos": Vector2i(r.position)}, r)


func _paint_chair(ci: CanvasItem, chair: Dictionary, front: bool) -> void:
	var s: float = char_scale
	var c: Vector2 = chair["center"]
	var f: Vector2 = chair["facing"]
	var col: Color = _chair_color(str(chair["style"]))
	if front:
		_chair_back(ci, Rect2(c + Vector2(-16, -2) * s, Vector2(32, 18) * s), col, s)
		return
	ci.draw_colored_polygon(CharacterStyle.ellipse(c + Vector2(0, 12) * s, Vector2(20, 7) * s), _floor_shadow())
	ci.draw_line(c + Vector2(0, 8) * s, c + Vector2(0, 15) * s, C_STEEL_DARK, 3.0 * s)
	ci.draw_line(c + Vector2(-10, 15) * s, c + Vector2(10, 15) * s, C_STEEL_DARK, 2.0 * s)
	if f.y > 0.5:
		_chair_back(ci, Rect2(c + Vector2(-16, -42) * s, Vector2(32, 34) * s), col, s)
	elif absf(f.x) > 0.5:
		var bx: float = -f.x * 14.0 - 4.0
		_chair_back(ci, Rect2(c + Vector2(bx, -38) * s, Vector2(8, 42) * s), col, s)
	_rounded_box(ci, Rect2(c + Vector2(-16, -8) * s, Vector2(32, 18) * s), 6.0 * s, col, band_color("outline"), s)
	ci.draw_rect(Rect2(c + Vector2(-13, 6) * s, Vector2(26, 3) * s), col.darkened(0.3))


## Respaldo: panel acolchado con reborde claro arriba (se lee como silla a cualquier escala).
func _chair_back(ci: CanvasItem, r: Rect2, col: Color, s: float) -> void:
	_rounded_box(ci, r, 7.0 * s, col.lightened(0.08), band_color("outline"), s)
	var inner: Rect2 = r.grow(-3.5 * s)
	if inner.size.x > 4.0 and inner.size.y > 4.0:
		ci.draw_colored_polygon(rounded_rect(inner, 5.0 * s), col.darkened(0.08))
	ci.draw_line(r.position + Vector2(6, 3) * s, Vector2(r.end.x - 6.0 * s, r.position.y + 3.0 * s),
			Color(band_color("light"), 0.22), 2.0 * s)


## Tapizado de la silla según su estilo, con los tonos de la banda (cuero de la madera de la banda,
## ejecutiva del perfil de la banda) o el acero universal.
func _chair_color(chair_style: String) -> Color:
	match chair_style:
		CHAIR_LEATHER:
			return band_color("furniture").darkened(0.45)
		CHAIR_STEEL:
			return C_STEEL.darkened(0.18)
	return band_color("outline").lightened(0.2)


func _floor_shadow() -> Color:
	return Color(band_color("outline"), 0.28)


func _rounded_box(ci: CanvasItem, r: Rect2, radius: float, fill: Color, outline: Color, s: float) -> void:
	var pts: PackedVector2Array = rounded_rect(r, radius)
	ci.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	ci.draw_polyline(pts, outline, maxf(1.6 * s * 0.6, 1.5), true)


static func rounded_rect(r: Rect2, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var rad: float = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners: Array[Vector2] = [r.position + Vector2(r.size.x - rad, rad), r.end - Vector2(rad, rad),
			r.position + Vector2(rad, r.size.y - rad), r.position + Vector2(rad, rad)]
	for i: int in 4:
		for step: int in 5:
			var ang: float = -PI * 0.5 + (float(i) + float(step) / 4.0) * PI * 0.5
			pts.append(corners[i] + Vector2(cos(ang), sin(ang)) * rad)
	return pts


func _outline_rect(ci: CanvasItem, r: Rect2, fill: Color, width: float = 3.0) -> void:
	ci.draw_rect(r, fill)
	ci.draw_rect(r, band_color("outline"), false, width)


func _font(bold: bool) -> Font:
	return UITheme.font(UITheme.FONT_BOLD if bold else UITheme.FONT_SEMIBOLD)


func _text(ci: CanvasItem, text: String, pos: Vector2, width: float, font_size: int, color: Color,
		bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	ci.draw_multiline_string(_font(bold), pos, text, align, width, font_size, -1, color)


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


func _paint_tiles(ci: CanvasItem, area: Rect2, tint: Color, tile: float) -> void:
	var x0: int = floori(area.position.x / tile)
	var y0: int = floori(area.position.y / tile)
	for gx: int in range(x0, ceili(area.end.x / tile)):
		for gy: int in range(y0, ceili(area.end.y / tile)):
			if posmod(gx + gy, 2) == 0:
				continue
			var r: Rect2 = Rect2(Vector2(gx, gy) * tile, Vector2(tile, tile)).intersection(area)
			ci.draw_rect(r, Color(tint, 0.35))


func _paint_clock(ci: CanvasItem, c: Vector2, radius: float) -> void:
	var ol: Color = band_color("outline")
	ci.draw_circle(c + Vector2(3, 4), radius, _floor_shadow())
	ci.draw_circle(c, radius, C_CERAMIC)
	ci.draw_arc(c, radius, 0.0, TAU, 40, ol, 4.0, true)
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0
		ci.draw_line(c + Vector2.from_angle(a) * radius * 0.8, c + Vector2.from_angle(a) * radius * 0.92, ol, 2.0)
	var hm: Vector2i = _props.get("clock", Vector2i(11, 0))
	var minute_a: float = TAU * float(hm.y) / 60.0 - PI * 0.5
	var hour_a: float = TAU * (float(hm.x % 12) + float(hm.y) / 60.0) / 12.0 - PI * 0.5
	ci.draw_line(c, c + Vector2.from_angle(hour_a) * radius * 0.5, ol, 4.0, true)
	ci.draw_line(c, c + Vector2.from_angle(minute_a) * radius * 0.78, ol, 3.0, true)
	ci.draw_circle(c, 3.5, C_RED_LED)


func _paint_poster(ci: CanvasItem, r: Rect2) -> void:
	_outline_rect(ci, r, band_color("furniture"))
	var art: Rect2 = Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, r.size.y * 0.52))
	ci.draw_rect(art, band_color("accent").darkened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(art.position.x, art.end.y),
			Vector2(art.get_center().x - 10, art.position.y + 22), Vector2(art.end.x, art.end.y)]),
			band_color("window").lightened(0.3))
	ci.draw_circle(art.position + Vector2(art.size.x * 0.75, 20), 9.0, C_GOLD.lightened(0.2))
	var text: String = str(_props.get("poster", ""))
	var room: Vector2 = Vector2(r.size.x - 12.0, r.end.y - art.end.y - 8.0)
	var font_size: int = POSTER_FONT_MAX
	while font_size > POSTER_FONT_MIN and _font(true).get_multiline_string_size(text,
			HORIZONTAL_ALIGNMENT_CENTER, room.x, font_size).y > room.y:
		font_size -= 1
	_text(ci, text, Vector2(r.position.x + 6, art.end.y + 6 + font_size), room.x, font_size, band_color("outline"), true)


## Cámara domo en la esquina: el edificio mira (§12.4). Su LED parpadea.
func _paint_camera_dome(ci: CanvasItem, c: Vector2) -> void:
	ci.draw_rect(Rect2(c.x - 26, c.y - 22, 52, 12), C_STEEL_DARK)
	ci.draw_circle(c, 20.0, C_STEEL_DARK.darkened(0.35))
	ci.draw_arc(c, 20.0, 0.0, PI, 20, band_color("outline"), 3.0, true)
	ci.draw_circle(c + Vector2(-6, 4), 6.0, C_STEEL.darkened(0.4))
	var blink: bool = fmod(_time, 1.2) < 0.7
	ci.draw_circle(c + Vector2(9, -2), 3.5, C_RED_LED if blink else C_RED_LED.darkened(0.6))


# ─── Decorado Aurora (aurora_room) ────────────────────────────

func _paint_aurora_back(ci: CanvasItem, view: Rect2) -> void:
	var carpet: Color = band_color("carpet")
	ci.draw_rect(view, carpet)
	_paint_tiles(ci, Rect2(view.position.x, AURORA_WALL_Y, view.size.x, view.end.y - AURORA_WALL_Y),
			carpet.lightened(0.07), 96.0)
	_paint_corridors(ci, view)
	_paint_rug(ci, AURORA_RUG)
	_paint_window_wall(ci, view)
	_paint_glass_side(ci, 0.0, view)
	_paint_glass_side(ci, DESIGN.x - 16.0, view)


## Pasillo de moqueta clara al otro lado de los tabiques de cristal (encuadres más anchos).
func _paint_corridors(ci: CanvasItem, view: Rect2) -> void:
	var hall: Color = band_color("floor")
	if view.position.x < 0.0:
		ci.draw_rect(Rect2(view.position.x, view.position.y, -view.position.x, view.size.y), hall)
	if view.end.x > DESIGN.x:
		ci.draw_rect(Rect2(DESIGN.x, view.position.y, view.end.x - DESIGN.x, view.size.y), hall)


## Ventanal de doble altura: si el encuadre enseña más arriba del lienzo, los paños siguen subiendo
## (con un travesaño a la altura del techo del diseño) en lugar de dejar un vacío.
func _paint_window_wall(ci: CanvasItem, view: Rect2) -> void:
	var wall: Color = band_color("wall")
	var top: float = minf(view.position.y, 0.0)
	ci.draw_rect(Rect2(0, top, DESIGN.x, AURORA_WALL_Y - top), wall)
	for i: int in _skyline.size():
		_paint_window_pane(ci, i, top)
	ci.draw_rect(Rect2(0, 14, DESIGN.x, 12), wall.darkened(0.08))
	ci.draw_line(Vector2(0, 26), Vector2(DESIGN.x, 26), band_color("outline"), 2.0)
	ci.draw_rect(Rect2(0, 250, DESIGN.x, 16), wall.darkened(0.06))
	ci.draw_rect(Rect2(0, AURORA_WALL_Y - 16.0, DESIGN.x, 16), band_color("accent").darkened(0.2))
	ci.draw_line(Vector2(0, AURORA_WALL_Y), Vector2(DESIGN.x, AURORA_WALL_Y), band_color("outline"), 3.0)


## Siluetas de la ciudad de cada paño del ventanal, calculadas una vez (deterministas por índice).
func _make_skyline() -> Array:
	var out: Array = []
	var panes: int = 8
	var pane_w: float = (DESIGN.x - 60.0) / float(panes)
	var city: Color = band_color("window").darkened(0.22)
	var sky_low: Color = band_color("window")
	for i: int in panes:
		var r: Rect2 = Rect2(30.0 + pane_w * i + 6.0, 34, pane_w - 12.0, 214)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = i * 7919 + 17
		var blocks: Array = []
		var x: float = r.position.x
		while x < r.end.x:
			var w: float = rng.randf_range(26, 58)
			var h: float = rng.randf_range(40, 150)
			blocks.append([Rect2(x, r.end.y - h, minf(w, r.end.x - x), h), city.lerp(sky_low, rng.randf_range(0.0, 0.35))])
			x += w + rng.randf_range(2, 10)
		out.append({"rect": r, "blocks": blocks})
	return out


func _paint_window_pane(ci: CanvasItem, index: int, top: float) -> void:
	var pane: Dictionary = _skyline[index]
	var r: Rect2 = pane["rect"]
	r = Rect2(r.position.x, minf(r.position.y, top + 14.0), r.size.x, r.end.y - minf(r.position.y, top + 14.0))
	var sky_top: Color = band_color("light").lerp(band_color("window"), 0.25)
	var sky_low: Color = band_color("window")
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)]), PackedColorArray([sky_top, sky_top, sky_low, sky_low]))
	for block: Array in pane["blocks"]:
		ci.draw_rect(block[0], block[1])
	ci.draw_rect(Rect2(r.position.x + 8, r.position.y + 8, 10, r.size.y - 16), Color(band_color("light"), 0.22))
	ci.draw_rect(r, band_color("outline"), false, 3.0)


## Pantalla, cartel y reloj de la pared del ventanal (cambian con sus accesorios).
func _paint_aurora_wall(ci: CanvasItem) -> void:
	_paint_screen(ci)
	_paint_poster(ci, Rect2(1290, 58, 150, 196))
	_paint_clock(ci, Vector2(560, 112), 30.0)


func _paint_screen(ci: CanvasItem) -> void:
	var r: Rect2 = AURORA_SCREEN
	var ol: Color = band_color("outline")
	ci.draw_rect(Rect2(r.position + Vector2(8, 10), r.size), _floor_shadow())
	_outline_rect(ci, r, band_color("light"))
	_outline_rect(ci, Rect2(r.position.x - 22, r.position.y - 16, r.size.x + 44, 18), C_STEEL_DARK)
	var band: Rect2 = Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 38))
	ci.draw_rect(band, band_color("accent"))
	_text(ci, str(_props.get("screen_kicker", "")), band.position + Vector2(18, 26), band.size.x - 36,
			17, band_color("light"), true, HORIZONTAL_ALIGNMENT_LEFT)
	_text(ci, str(_props.get("screen_title", "")), r.position + Vector2(26, 84), r.size.x - 52, 27, ol, true)
	_paint_chart(ci, Rect2(r.position.x + 26, r.end.y - 62, 110, 48))
	_text(ci, str(_props.get("screen_sub", "")), Vector2(r.position.x + 150, r.end.y - 22),
			r.size.x - 176, 16, band_color("shadow"), false, HORIZONTAL_ALIGNMENT_RIGHT)
	ci.draw_rect(Rect2(r.position.x - 4, r.end.y - 2, r.size.x + 8, 8), ol)


## El gráfico que sube siempre (toda diapositiva corporativa lleva uno).
func _paint_chart(ci: CanvasItem, r: Rect2) -> void:
	var accent: Color = band_color("accent")
	for i: int in 4:
		var h: float = r.size.y * (0.3 + 0.22 * float(i))
		ci.draw_rect(Rect2(r.position.x + i * 26.0, r.end.y - h, 18, h), accent.lightened(0.15 * i))
	ci.draw_line(Vector2(r.position.x - 4, r.end.y - 6), Vector2(r.end.x + 6, r.position.y - 4), C_RED_LED, 4.0, true)
	ci.draw_line(Vector2(r.position.x - 4, r.end.y), Vector2(r.end.x + 8, r.end.y), band_color("outline"), 2.0)


func _paint_glass_side(ci: CanvasItem, x: float, view: Rect2) -> void:
	var glass: Color = Color(band_color("window"), 0.85)
	var top: float = minf(view.position.y, 0.0)
	var bottom: float = maxf(view.end.y, DESIGN.y)
	ci.draw_rect(Rect2(x, top, 16, bottom - top), glass)
	ci.draw_rect(Rect2(x + 3, top, 3, bottom - top), Color(band_color("light"), 0.5))
	for y: int in range(int(floorf(top / 180.0)) * 180, int(bottom), 180):
		ci.draw_rect(Rect2(x - 3, float(y), 22, 10), C_STEEL_DARK)
	ci.draw_line(Vector2(x, top), Vector2(x, bottom), band_color("outline"), 2.0)
	ci.draw_line(Vector2(x + 16, top), Vector2(x + 16, bottom), band_color("outline"), 2.0)


func _paint_meeting_table(ci: CanvasItem) -> void:
	var t: Rect2 = AURORA_TABLE
	var h: float = 8.0 * char_scale
	var top_col: Color = band_color("light").lerp(band_color("furniture"), 0.35)
	var ol: Color = band_color("outline")
	ci.draw_rect(Rect2(t.position + Vector2(10, 16), t.size + Vector2(0, h)), _floor_shadow())
	var front: Rect2 = Rect2(t.position.x, t.end.y - 4.0, t.size.x, h + 4.0)
	_rounded_box(ci, front, 10.0, top_col.darkened(0.3), ol, 2.0)
	_rounded_box(ci, t, 18.0, top_col, ol, 2.0)
	ci.draw_polyline(_closed(rounded_rect(t.grow(-12.0), 10.0)), band_color("accent").lerp(top_col, 0.45), 2.0, true)
	for i: int in 6:
		var x: float = t.position.x + t.size.x * (i + 0.5) / 6.0
		_paint_table_setting(ci, Vector2(x, t.position.y + 26), i, true)
		_paint_table_setting(ci, Vector2(x, t.end.y - 30), i + 6, false)
	for fx: float in [0.25, 0.75]:
		_paint_water_jug(ci, Vector2(t.position.x + t.size.x * fx, t.get_center().y + 2))
	_paint_phone_body(ci, t.get_center() + Vector2(0, 2))


## Portátil, papeles o taza delante de cada silla (variación determinista por puesto) y su tarjetón.
func _paint_table_setting(ci: CanvasItem, c: Vector2, index: int, far_side: bool) -> void:
	var ol: Color = band_color("outline")
	match index % 3:
		0:
			var lid: Rect2 = Rect2(c.x - 24, c.y - 8, 48, 16)
			_outline_rect(ci, lid, C_STEEL.lightened(0.3), 2.0)
			ci.draw_rect(lid.grow(-3.0), C_GLASS_DARK if far_side else C_SCREEN_GLOW)
		1:
			_outline_rect(ci, Rect2(c.x - 18, c.y - 10, 30, 20), C_SHEET, 2.0)
			_outline_rect(ci, Rect2(c.x - 12, c.y - 6, 30, 20), C_SHEET, 2.0)
		_:
			ci.draw_circle(c, 9.0, C_CERAMIC)
			ci.draw_arc(c, 9.0, 0.0, TAU, 20, ol, 2.0, true)
			ci.draw_circle(c, 5.5, C_WOOD.darkened(0.4))
	var tent: Rect2 = Rect2(c.x + (32.0 if far_side else -50.0), c.y - 5, 18, 10)
	_outline_rect(ci, tent, C_SHEET, 1.5)
	ci.draw_rect(Rect2(tent.position + Vector2(1, 1), Vector2(tent.size.x - 2, 3)), band_color("accent"))


func _paint_water_jug(ci: CanvasItem, c: Vector2) -> void:
	var ol: Color = band_color("outline")
	var jug: PackedVector2Array = CharacterStyle.ellipse(c, Vector2(13, 11))
	ci.draw_colored_polygon(jug, Color(C_WATER, 0.75))
	ci.draw_polyline(_closed(jug), ol, 2.0, true)
	ci.draw_arc(c + Vector2(12, -2), 6.0, -PI * 0.5, PI * 0.5, 8, ol, 2.0, true)
	for dx: float in [-30.0, 26.0]:
		ci.draw_circle(c + Vector2(dx, 10), 6.0, Color(C_WATER, 0.45))
		ci.draw_arc(c + Vector2(dx, 10), 6.0, 0.0, TAU, 14, ol, 1.5, true)


func _paint_phone_body(ci: CanvasItem, c: Vector2) -> void:
	var pts: PackedVector2Array = []
	for i: int in 3:
		var a: float = -PI * 0.5 + TAU * float(i) / 3.0
		pts.append(c + Vector2(cos(a), sin(a) * 0.6) * 30.0)
	ci.draw_colored_polygon(pts, C_STEEL_DARK.darkened(0.2))
	ci.draw_polyline(_closed(pts), band_color("outline"), 2.0, true)


## LED del teléfono de conferencias (accesorio animado).
func _paint_conference_phone(ci: CanvasItem, c: Vector2) -> void:
	ci.draw_circle(c, 6.0, C_GREEN_LED if fmod(_time, 2.0) < 1.6 else C_GREEN_LED.darkened(0.55))


func _paint_podium(ci: CanvasItem) -> void:
	var s: float = char_scale
	var base: Vector2 = AURORA_PODIUM
	var ol: Color = band_color("outline")
	var wood: Color = band_color("furniture")
	var front: PackedVector2Array = [base + Vector2(-22, -34) * s, base + Vector2(22, -34) * s,
			base + Vector2(17, 0) * s, base + Vector2(-17, 0) * s]
	ci.draw_colored_polygon(CharacterStyle.ellipse(base + Vector2(0, 2) * s, Vector2(24, 7) * s), _floor_shadow())
	ci.draw_colored_polygon(front, wood.darkened(0.08))
	ci.draw_polyline(_closed(front), ol, 3.0, true)
	var top: PackedVector2Array = [base + Vector2(-26, -44) * s, base + Vector2(26, -44) * s,
			base + Vector2(23, -34) * s, base + Vector2(-23, -34) * s]
	ci.draw_colored_polygon(top, wood.lightened(0.1))
	ci.draw_polyline(_closed(top), ol, 3.0, true)
	ci.draw_rect(Rect2(base + Vector2(-17, -24) * s, Vector2(34, 6) * s), band_color("accent"))
	ci.draw_circle(base + Vector2(0, -12) * s, 5.0 * s, C_GOLD)
	ci.draw_arc(base + Vector2(0, -12) * s, 5.0 * s, 0.0, TAU, 16, ol, 2.0, true)
	ci.draw_line(base + Vector2(-12, -44) * s, base + Vector2(-18, -58) * s, C_STEEL_DARK, 2.0 * s, true)
	ci.draw_circle(base + Vector2(-18, -59) * s, 3.0 * s, ol)


## Rotafolio con el diagrama de Venn de la casa: «SUYAS» ∩ «MÍAS» (textos de los accesorios).
func _paint_flipchart(ci: CanvasItem) -> void:
	var r: Rect2 = AURORA_FLIPCHART
	var ol: Color = band_color("outline")
	var foot: Vector2 = Vector2(r.get_center().x, r.end.y)
	ci.draw_colored_polygon(CharacterStyle.ellipse(foot, Vector2(r.size.x * 0.45, 9)), _floor_shadow())
	for leg: Vector2 in [Vector2(-r.size.x * 0.4, 0), Vector2(r.size.x * 0.4, 0), Vector2(0, -8)]:
		ci.draw_line(Vector2(foot.x, r.position.y + 40) + leg * 0.2, foot + leg, C_STEEL_DARK, 5.0, true)
	var pad: Rect2 = Rect2(r.position + Vector2(4, 8), Vector2(r.size.x - 8, r.size.y * 0.62))
	_outline_rect(ci, Rect2(pad.position - Vector2(6, 10), Vector2(pad.size.x + 12, 14)), C_STEEL_DARK, 2.0)
	_outline_rect(ci, pad, C_SHEET, 3.0)
	var c: Vector2 = pad.get_center() + Vector2(0, -4)
	var rad: float = pad.size.x * 0.27
	var left: Color = band_color("accent")
	ci.draw_circle(c - Vector2(rad * 0.62, 0), rad, Color(left, 0.25))
	ci.draw_circle(c + Vector2(rad * 0.62, 0), rad, Color(C_RED_LED, 0.25))
	ci.draw_arc(c - Vector2(rad * 0.62, 0), rad, 0.0, TAU, 28, left, 3.0, true)
	ci.draw_arc(c + Vector2(rad * 0.62, 0), rad, 0.0, TAU, 28, C_RED_LED, 3.0, true)
	var fs: int = 13
	_text(ci, str(_props.get("flip_left", "")), c + Vector2(-rad * 1.6, -rad - 4), rad * 1.9, fs, left.darkened(0.2), true)
	_text(ci, str(_props.get("flip_right", "")), c + Vector2(-rad * 0.3, -rad - 4), rad * 1.9, fs, C_RED_LED.darkened(0.2), true)
	_text(ci, str(_props.get("flip_mid", "")), c + Vector2(-rad * 1.4, rad + 16), rad * 2.8, fs, ol, true)


## Alfombra bajo la mesa (acento de banda) para enmarcar la escena.
func _paint_rug(ci: CanvasItem, r: Rect2) -> void:
	var rug: Color = band_color("carpet").darkened(0.18)
	ci.draw_rect(Rect2(r.position + Vector2(6, 8), r.size), _floor_shadow())
	ci.draw_rect(r, rug)
	ci.draw_rect(r.grow(-16.0), band_color("accent").lerp(rug, 0.55), false, 4.0)
	ci.draw_rect(r.grow(-28.0), band_color("accent").lerp(rug, 0.75), false, 2.0)
	ci.draw_rect(r, band_color("outline"), false, 2.0)


# ─── Decorado del interrogatorio (interrogation_room) ─────────

func _paint_interrogation_back(ci: CanvasItem, view: Rect2) -> void:
	var floor_col: Color = band_color("carpet").lerp(band_color("shadow"), 0.35)
	ci.draw_rect(view, floor_col)
	_paint_tiles(ci, Rect2(view.position.x, INTERROGATION_WALL_Y, view.size.x,
			view.end.y - INTERROGATION_WALL_Y), floor_col.lightened(0.08), 120.0)
	_paint_panel_wall(ci, view)
	_paint_mirror(ci, Rect2(240, 78, 470, 176))
	_paint_poster(ci, Rect2(1088, 64, 132, 176))
	_paint_clock(ci, Vector2(1320, 132), 30.0)
	_paint_notice(ci, Rect2(810, 96, 96, 124))
	_paint_vent(ci, Rect2(60, 60, 110, 56))


func _paint_panel_wall(ci: CanvasItem, view: Rect2) -> void:
	var wall: Color = band_color("wall").darkened(0.12)
	var wood: Color = band_color("furniture")
	var top: float = minf(view.position.y, 0.0)
	var left: float = view.position.x
	ci.draw_rect(Rect2(left, top, view.size.x, INTERROGATION_WALL_Y - top), wall)
	ci.draw_rect(Rect2(left, top, view.size.x, 18.0 - top), band_color("shadow").lerp(wall, 0.3))
	var dado: Rect2 = Rect2(left, 262, view.size.x, INTERROGATION_WALL_Y - 262)
	ci.draw_rect(dado, wood.darkened(0.1))
	for x: int in range(int(floorf(left / 160.0)) * 160, int(view.end.x), 160):
		ci.draw_rect(Rect2(x + 14, 276, 132, 46), wood.darkened(0.2), false, 3.0)
	ci.draw_rect(Rect2(left, 256, view.size.x, 8), band_color("accent"))
	ci.draw_line(Vector2(left, INTERROGATION_WALL_Y), Vector2(view.end.x, INTERROGATION_WALL_Y),
			band_color("outline"), 3.0)


## Espejo espía: cristal oscuro con reflejos; al otro lado, quien sea.
func _paint_mirror(ci: CanvasItem, r: Rect2) -> void:
	_outline_rect(ci, r.grow(10.0), band_color("furniture").darkened(0.25))
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)]), PackedColorArray([C_GLASS_DARK.lightened(0.12),
			C_GLASS_DARK, C_GLASS_DARK.darkened(0.3), C_GLASS_DARK]))
	for i: int in 3:
		var x: float = r.position.x + 60.0 + 120.0 * i
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, r.position.y), Vector2(x + 34, r.position.y),
				Vector2(x - 40, r.end.y), Vector2(x - 74, r.end.y)]), Color(band_color("light"), 0.06))
	ci.draw_circle(Vector2(r.position.x + r.size.x * 0.78, r.position.y + 70), 7.0, Color(band_color("light"), 0.35))
	ci.draw_rect(r, band_color("outline"), false, 3.0)


## Hoja de «normas de la sala» clavada en la pared (renglones ilegibles, sello rojo).
func _paint_notice(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(Rect2(r.position + Vector2(4, 5), r.size), _floor_shadow())
	_outline_rect(ci, r, C_SHEET, 2.0)
	ci.draw_rect(Rect2(r.position.x + 10, r.position.y + 12, r.size.x - 20, 8), band_color("outline"))
	for i: int in 6:
		var w: float = (r.size.x - 20.0) * (0.95 - 0.12 * float(i % 3))
		ci.draw_rect(Rect2(r.position.x + 10, r.position.y + 32 + i * 12, w, 4), Color(band_color("outline"), 0.4))
	ci.draw_arc(r.end - Vector2(24, 22), 12.0, 0.0, TAU, 20, C_RED_LED.darkened(0.2), 3.0, true)
	ci.draw_circle(r.position + Vector2(r.size.x * 0.5, 4), 4.0, C_RED_LED)


func _paint_vent(ci: CanvasItem, r: Rect2) -> void:
	_outline_rect(ci, r, C_STEEL.darkened(0.1), 2.0)
	for i: int in 5:
		var y: float = r.position.y + 9.0 + i * 9.0
		ci.draw_line(Vector2(r.position.x + 8, y), Vector2(r.end.x - 8, y), C_STEEL_DARK, 3.0)


## Puerta de la pared norte: `door` 1 = abierta (hoja girada hacia dentro, luz del pasillo).
func _paint_door(ci: CanvasItem) -> void:
	var open: float = float(_props.get("door", 0.0))
	var r: Rect2 = INTERROGATION_DOOR
	var ol: Color = band_color("outline")
	var wood: Color = band_color("furniture").lightened(0.05)
	_outline_rect(ci, r.grow(10.0), band_color("furniture").darkened(0.35))
	ci.draw_rect(r, band_color("light") if open > 0.02 else wood)
	if open > 0.02:
		ci.draw_rect(Rect2(r.position.x, r.end.y - 60, r.size.x, 60), band_color("light").darkened(0.12))
		_paint_door_light(ci, open)
	var angle: float = open * PI * 0.42
	var w: float = r.size.x * cos(angle)
	var drop: float = r.size.x * sin(angle) * 0.5
	var hinge_x: float = r.end.x
	var leaf: PackedVector2Array = [Vector2(hinge_x - w, r.position.y + drop), Vector2(hinge_x, r.position.y),
			Vector2(hinge_x, r.end.y), Vector2(hinge_x - w, r.end.y + drop)]
	ci.draw_colored_polygon(leaf, wood.darkened(0.12 * open))
	ci.draw_polyline(_closed(leaf), ol, 3.0, true)
	var knob: Vector2 = Vector2(hinge_x - w * 0.86, r.get_center().y + drop * 0.6)
	ci.draw_circle(knob, 8.0, band_color("accent"))
	ci.draw_arc(knob, 8.0, 0.0, TAU, 16, ol, 2.0, true)
	if open <= 0.02:
		var pane: Rect2 = Rect2(r.position.x + 40, r.position.y + 30, r.size.x - 80, 60)
		_outline_rect(ci, pane, C_GLASS_DARK.lightened(0.2), 3.0)
		ci.draw_line(pane.position, pane.end, Color(band_color("light"), 0.1), 2.0)


func _paint_door_light(ci: CanvasItem, open: float) -> void:
	var r: Rect2 = INTERROGATION_DOOR
	var spread: float = 160.0 * open
	var light: Color = Color(band_color("light"), 0.28 * open)
	ci.draw_polygon(PackedVector2Array([Vector2(r.position.x, INTERROGATION_WALL_Y),
			Vector2(r.end.x, INTERROGATION_WALL_Y), Vector2(r.end.x + spread, 760),
			Vector2(r.position.x - spread * 1.6, 760)]),
			PackedColorArray([light, light, Color(light, 0.0), Color(light, 0.0)]))


func _paint_steel_table(ci: CanvasItem) -> void:
	var t: Rect2 = INTERROGATION_TABLE
	var h: float = 9.0 * char_scale
	var ol: Color = band_color("outline")
	ci.draw_rect(Rect2(t.position + Vector2(12, 18), t.size + Vector2(0, h)), _floor_shadow())
	_rounded_box(ci, Rect2(t.position.x, t.end.y - 4.0, t.size.x, h + 4.0), 6.0, C_STEEL.darkened(0.35), ol, 2.0)
	_rounded_box(ci, t, 10.0, C_STEEL, ol, 2.0)
	ci.draw_rect(Rect2(t.position.x + 10, t.position.y + 8, t.size.x - 20, 6), Color(band_color("light"), 0.25))
	for corner: Vector2 in [t.position + Vector2(14, 14), Vector2(t.end.x - 14, t.position.y + 14),
			Vector2(t.position.x + 14, t.end.y - 14), t.end - Vector2(14, 14)]:
		ci.draw_circle(corner, 3.5, C_STEEL_DARK)
	_paint_folder(ci, Rect2(t.position.x + 60, t.position.y + 18, 150, 74))
	_paint_tissues(ci, Rect2(t.position.x + 26, t.end.y - 44, 58, 32))
	_paint_nameplate(ci, Vector2(t.end.x - 90, t.end.y - 24))
	if bool(_props.get("paper", false)):
		var paper_r: Rect2 = Rect2(t.get_center().x - 58, t.position.y + 46, 86, 60)
		_outline_rect(ci, paper_r, C_SHEET, 2.0)
		ci.draw_rect(Rect2(paper_r.position + Vector2(10, 12), Vector2(50, 5)), C_RED_LED.darkened(0.3))


func _paint_folder(ci: CanvasItem, r: Rect2) -> void:
	_outline_rect(ci, r, C_CARDBOARD.lightened(0.25), 2.0)
	_outline_rect(ci, Rect2(r.position + Vector2(10, 8), Vector2(r.size.x * 0.46, r.size.y - 16)), C_SHEET, 2.0)
	for i: int in 4:
		ci.draw_line(r.position + Vector2(18, 20 + i * 11), r.position + Vector2(r.size.x * 0.46, 20 + i * 11),
				Color(band_color("outline"), 0.45), 2.0)
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.6, r.position.y + 14, 40, 40), C_STEEL.darkened(0.3))


## Caja de pañuelos: la empresa piensa en todo.
func _paint_tissues(ci: CanvasItem, r: Rect2) -> void:
	_outline_rect(ci, r, band_color("accent").lightened(0.2), 2.0)
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.3, r.position.y + 6, r.size.x * 0.4, 6), band_color("outline"))
	var puff: PackedVector2Array = [r.position + Vector2(r.size.x * 0.34, 8), r.position + Vector2(r.size.x * 0.45, -12),
			r.position + Vector2(r.size.x * 0.58, -4), r.position + Vector2(r.size.x * 0.66, 8)]
	ci.draw_colored_polygon(puff, C_SHEET)
	ci.draw_polyline(puff, band_color("outline"), 2.0, true)


## Grabadora de cinta: las bobinas giran (accesorio animado).
func _paint_recorder(ci: CanvasItem, c: Vector2) -> void:
	var body: Rect2 = Rect2(c - Vector2(40, 18), Vector2(80, 36))
	_outline_rect(ci, body, C_STEEL_DARK.darkened(0.2), 2.0)
	for dx: float in [-18.0, 18.0]:
		ci.draw_circle(c + Vector2(dx, 0), 9.0, C_STEEL.darkened(0.1))
		ci.draw_line(c + Vector2(dx, 0), c + Vector2(dx, 0) + Vector2.from_angle(_time * 3.0) * 8.0,
				band_color("outline"), 2.0)
	ci.draw_circle(c + Vector2(30, -10), 3.0, C_RED_LED if fmod(_time, 1.0) < 0.6 else C_RED_LED.darkened(0.6))


func _paint_nameplate(ci: CanvasItem, c: Vector2) -> void:
	var plate: Rect2 = Rect2(c - Vector2(66, 14), Vector2(132, 28))
	_outline_rect(ci, plate, band_color("accent"), 2.0)
	_text(ci, str(_props.get("nameplate", "")), plate.position + Vector2(4, 20), plate.size.x - 8, 15,
			band_color("shadow"), true)


## Café de la disculpa (§12.5), con vapor animado. Sin café no dibuja nada.
func _paint_coffee(ci: CanvasItem, c: Vector2) -> void:
	if not bool(_props.get("coffee", false)):
		return
	var ol: Color = band_color("outline")
	ci.draw_colored_polygon(CharacterStyle.ellipse(c, Vector2(26, 11)), C_CERAMIC)
	ci.draw_polyline(_closed(CharacterStyle.ellipse(c, Vector2(26, 11))), ol, 2.0, true)
	var cup: Vector2 = c + Vector2(0, -8)
	ci.draw_circle(cup, 13.0, C_CERAMIC)
	ci.draw_arc(cup, 13.0, 0.0, TAU, 20, ol, 2.0, true)
	ci.draw_circle(cup, 9.0, C_WOOD.darkened(0.4))
	ci.draw_arc(cup + Vector2(15, 0), 5.0, -PI * 0.5, PI * 0.5, 8, ol, 3.0, true)
	for i: int in 2:
		var x: float = cup.x - 5.0 + i * 10.0
		var wave: float = sin(_time * 3.0 + i) * 3.0
		ci.draw_line(Vector2(x, cup.y - 18), Vector2(x + wave, cup.y - 34), Color(band_color("light"), 0.5), 2.0, true)


## Destructora de papel con su piloto encendido: a mano, por si acaso.
func _paint_shredder(ci: CanvasItem, r: Rect2) -> void:
	var ol: Color = band_color("outline")
	ci.draw_colored_polygon(CharacterStyle.ellipse(Vector2(r.get_center().x, r.end.y), Vector2(r.size.x * 0.55, 8)),
			_floor_shadow())
	var bin: Rect2 = Rect2(r.position.x + 6, r.position.y + 26, r.size.x - 12, r.size.y - 26)
	_outline_rect(ci, bin, C_STEEL_DARK, 2.0)
	for i: int in 4:
		var x: float = bin.position.x + 12.0 + i * (bin.size.x - 24.0) / 3.0
		ci.draw_line(Vector2(x, bin.position.y + 14), Vector2(x, bin.end.y - 10), C_SHEET.darkened(0.15), 3.0)
	var head: Rect2 = Rect2(r.position.x, r.position.y + 6, r.size.x, 24)
	_rounded_box(ci, head, 6.0, C_STEEL.darkened(0.25), ol, 1.5)
	ci.draw_rect(Rect2(head.position.x + 14, head.position.y + 8, head.size.x - 36, 5), ol)
	var on: bool = fmod(_time, 1.6) < 1.2
	ci.draw_circle(Vector2(head.end.x - 12, head.get_center().y), 4.0, C_GREEN_LED if on else C_GREEN_LED.darkened(0.5))


## Planta de la sala, olvidada desde el último recorte de presupuesto.
func _paint_dead_plant(ci: CanvasItem, base: Vector2) -> void:
	var ol: Color = band_color("outline")
	var pot: PackedVector2Array = [base + Vector2(-26, -44), base + Vector2(26, -44), base + Vector2(19, 0),
			base + Vector2(-19, 0)]
	ci.draw_colored_polygon(CharacterStyle.ellipse(base + Vector2(0, 2), Vector2(30, 8)), _floor_shadow())
	var stem_col: Color = C_WOOD.darkened(0.2)
	for i: int in 5:
		var a: float = -PI * 0.5 + (float(i) - 2.0) * 0.38
		var tip: Vector2 = base + Vector2(0, -44) + Vector2.from_angle(a) * 70.0
		var droop: Vector2 = tip + Vector2((float(i) - 2.0) * 14.0, 26.0)
		ci.draw_polyline(PackedVector2Array([base + Vector2(0, -44), tip, droop]), stem_col, 4.0, true)
		ci.draw_colored_polygon(CharacterStyle.ellipse(droop, Vector2(9, 5)), C_CARDBOARD.darkened(0.1))
	ci.draw_colored_polygon(pot, band_color("accent").darkened(0.3))
	ci.draw_polyline(_closed(pot), ol, 3.0, true)
	ci.draw_rect(Rect2(base + Vector2(-28, -50), Vector2(56, 10)), band_color("accent").darkened(0.15))


## Silla de espera contra la pared (de cara a la sala, vacía).
func _paint_side_chair(ci: CanvasItem, c: Vector2) -> void:
	_paint_chair(ci, {"center": c, "facing": Vector2.DOWN, "style": CHAIR_STEEL}, false)


## Lámpara colgante, cono de luz y viñeta; después, la onomatopeya del portazo.
func _paint_interrogation_front(ci: CanvasItem, view: Rect2) -> void:
	var lamp: String = str(_props.get("lamp", LAMP_NEUTRAL))
	var light: Color = _lamp_color(lamp)
	var cone_a: float = 0.13
	if lamp == LAMP_HARSH:
		cone_a = 0.2
	elif lamp == LAMP_WARM:
		cone_a = 0.22
	var c: Vector2 = INTERROGATION_LAMP
	ci.draw_polygon(PackedVector2Array([c + Vector2(-70, 40), c + Vector2(70, 40), Vector2(1330, 800),
			Vector2(590, 800)]), PackedColorArray([Color(light, cone_a), Color(light, cone_a),
			Color(light, 0.0), Color(light, 0.0)]))
	var dark: Color = _lamp_darkness(lamp)
	var vignette: Rect2 = Rect2(c.x - 1500.0, c.y - 1040.0, 3000.0, 2300.0)
	ci.draw_texture_rect(_vignette, vignette, false, dark)
	_fill_outside(ci, view, vignette, dark)
	ci.draw_line(Vector2(c.x, minf(view.position.y, 0.0)), c + Vector2(0, -6), band_color("outline"), 4.0)
	var shade: PackedVector2Array = [c + Vector2(-26, -8), c + Vector2(26, -8), c + Vector2(72, 42),
			c + Vector2(-72, 42)]
	ci.draw_colored_polygon(shade, band_color("accent").darkened(0.55))
	ci.draw_polyline(_closed(shade), band_color("outline"), 3.0, true)
	ci.draw_colored_polygon(CharacterStyle.ellipse(c + Vector2(0, 42), Vector2(66, 12)), light.lightened(0.4))
	_paint_slam(ci, float(_props.get("slam", 0.0)))


func _fill_outside(ci: CanvasItem, view: Rect2, inner: Rect2, dark: Color) -> void:
	if view.position.x < inner.position.x:
		ci.draw_rect(Rect2(view.position.x, view.position.y, inner.position.x - view.position.x, view.size.y), dark)
	if view.end.x > inner.end.x:
		ci.draw_rect(Rect2(inner.end.x, view.position.y, view.end.x - inner.end.x, view.size.y), dark)
	if view.position.y < inner.position.y:
		ci.draw_rect(Rect2(inner.position.x, view.position.y, inner.size.x, inner.position.y - view.position.y), dark)
	if view.end.y > inner.end.y:
		ci.draw_rect(Rect2(inner.position.x, inner.end.y, inner.size.x, view.end.y - inner.end.y), dark)


## Luz de la lámpara según el tono: cálida (banda), neutra o fría y dura (cristal de la banda).
func _lamp_color(lamp: String) -> Color:
	match lamp:
		LAMP_WARM:
			return band_color("light")
		LAMP_HARSH:
			return band_color("window").lerp(Color.WHITE, 0.75)
	return band_color("light").lerp(Color.WHITE, 0.5)


## Oscuridad de los bordes según el tono: la disculpa ilumina la sala; el portazo la hunde.
func _lamp_darkness(lamp: String) -> Color:
	var shadow: Color = band_color("shadow")
	match lamp:
		LAMP_WARM:
			return Color(shadow.lerp(band_color("furniture"), 0.25), 0.3)
		LAMP_HARSH:
			return Color(shadow.darkened(0.75), 0.9)
	return Color(shadow.darkened(0.3), 0.72)


func _make_vignette() -> GradientTexture2D:
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	g.add_point(0.22, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.75))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.0, 0.45)
	tex.width = 256
	tex.height = 256
	return tex


## Estallido de cómic con «¡PUM!» junto a la puerta (slam 0..1: escala de entrada).
func _paint_slam(ci: CanvasItem, amount: float) -> void:
	if amount <= 0.01:
		return
	var c: Vector2 = INTERROGATION_DOOR.get_center() + Vector2(-230, 30)
	var pts: PackedVector2Array = []
	var spikes: int = 14
	for i: int in spikes * 2:
		var a: float = TAU * float(i) / float(spikes * 2) + 0.2
		var rad: float = (150.0 if i % 2 == 0 else 96.0) * amount
		pts.append(c + Vector2(cos(a), sin(a) * 0.72) * rad)
	ci.draw_colored_polygon(pts, UITheme.color("focus"))
	ci.draw_polyline(_closed(pts), ink(), 5.0, true)
	ci.draw_set_transform(c, -0.12, Vector2(amount, amount))
	var text: String = str(_props.get("slam_text", ""))
	var font_size: int = 64
	var w: float = _font(true).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	ci.draw_string_outline(_font(true), Vector2(-w * 0.5, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, 10, ink())
	ci.draw_string(_font(true), Vector2(-w * 0.5, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			UITheme.color("danger"))
	ci.draw_set_transform(Vector2.ZERO)
