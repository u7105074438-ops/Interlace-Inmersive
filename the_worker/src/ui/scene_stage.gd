# scene_stage.gd — Plató compartido de las escenas Aurora (P12) e interrogatorio (P15): sala dibujada por código, reparto sentado con CharacterPainter, bocadillos, insignias, temblor y línea de tiempo de golpes de guion.
# PROPIETARIO DE: el reparto en escena (actores, sillas, poses, marcas), sus bocadillos e insignias, los accesorios del decorado y el temblor de cámara.
# ESCUCHA: nada.
class_name SceneStage
extends Control

## Lienzo de diseño DESIGN (1920×1080, el lienzo base del juego) ajustado sin recorte al tamaño del
## control; suelo y paredes se prolongan para cubrir pantallas más anchas (móvil 20:9) o más altas.
## Decorados (configure): SET_AURORA (sala acristalada de P12, banda the_specialists: ventanal,
## pantalla de proyección, atril, mesa de juntas de 14 sillas) y SET_INTERROGATION (sala desnuda de
## P15, banda the_power: espejo espía, puerta, mesa metálica, lámpara colgante). Funciones _paint_*.
## Accesorios (set_prop): screen_kicker / screen_title / screen_sub (pantalla de Aurora), clock,
## door (1 abierta … 0 cerrada), lamp ("warm" | "neutral" | "harsh"), coffee (bool), slam (0..1,
## onomatopeya del portazo), paper (bool: pieza sobre la mesa), nameplate (texto).
## Actores: add_actor(id, cast_member(id), spot) con spot {pos, facing, seated, anim, chair}.
## Con chair = true, pos es el centro del asiento; si no, los pies. head_point(id) da el punto sobre
## la cabeza en coordenadas del control: bocadillos (say) e insignias (badge) son Control.

const DESIGN := Vector2(1920, 1080)
const SET_AURORA := "aurora"
const SET_INTERROGATION := "interrogation"
const BAND_AURORA := "the_specialists"
const BAND_INTERROGATION := "the_power"
const PLAYER_ID := "player"
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
## Tintas fijas del decorado (no dependen de la banda): pantalla, cristal, metal, papel.
const C_INK := Color("#1d1a22")
const C_PAPER := Color("#fbfaf6")
const C_SCREEN := Color("#fbfcfd")
const C_STEEL := Color("#9aa3a8")
const C_STEEL_DARK := Color("#3b4247")
const C_GLASS_DARK := Color("#1d2733")
const C_RED_LED := Color("#ff4d4d")
const C_MANILA := Color("#d9b77a")
const C_SHOUT := Color("#ffe25a")
const C_WHISPER := Color("#e3e6ea")
const C_NARRATE := Color("#12151a")
const C_SHADOW := Color(0.02, 0.02, 0.05, 0.28)

## Mesa de juntas y sillas de Aurora (maquetación de diseño; 14 sillas como rooms/p12.json).
const AURORA_WALL_Y := 300.0
const AURORA_TABLE := Rect2(470, 596, 980, 132)
const AURORA_PODIUM := Vector2(292, 452)
const AURORA_SCREEN := Rect2(700, 30, 520, 236)
const INTERROGATION_WALL_Y := 336.0
const INTERROGATION_TABLE := Rect2(690, 590, 540, 132)
const INTERROGATION_LAMP := Vector2(960, 250)
const INTERROGATION_DOOR := Rect2(1452, 70, 176, 266)

var set_kind: String = SET_AURORA
var band_id: String = BAND_AURORA
var char_scale: float = 1.0
var pal: Dictionary = {}
var _canvas: StageCanvas
var _overlay: Control
var _actors: Dictionary = {}
var _chairs: Dictionary = {}
var _props: Dictionary = {}
var _bubbles: Dictionary = {}
var _badges: Dictionary = {}
var _furniture: FurniturePainter
var _vignette: GradientTexture2D
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_px: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0


## Lienzo del decorado: delega el dibujo en el plató (así el ajuste de escala es su transform).
class StageCanvas extends Node2D:
	var stage: SceneStage

	func _draw() -> void:
		stage.paint(self)


## Bocadillo de diálogo: panel con texto y cola dibujada hacia el personaje.
class Bubble extends PanelContainer:
	const TAIL := 18.0
	var style_id: String = SceneStage.STYLE_SAY
	var tail_x: float = 0.5
	var fill: Color = SceneStage.C_PAPER
	var hold: float = 0.0
	var max_width: float = 0.0
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
		var ink: Color = SceneStage.C_PAPER if p_style == SceneStage.STYLE_NARRATE else SceneStage.C_INK
		_label.add_theme_color_override("font_color", ink)
		if p_style == SceneStage.STYLE_SHOUT:
			_label.add_theme_font_override("font", UITheme.font(UITheme.FONT_BOLD))
		add_child(_label)

	func _ready() -> void:
		var natural: float = SceneStage.text_width(_label.text, _label)
		_label.custom_minimum_size.x = minf(max_width, natural + 2.0)

	func get_text() -> String:
		return _label.text

	func _draw() -> void:
		if style_id == SceneStage.STYLE_NARRATE:
			return
		var x: float = clampf(size.x * tail_x, 22.0, size.x - 22.0)
		var tip: Vector2 = Vector2(x + (size.x * 0.5 - x) * 0.15, size.y + TAIL)
		var pts: PackedVector2Array = [Vector2(x - 12, size.y - 3), Vector2(x + 12, size.y - 3), tip]
		draw_colored_polygon(pts, fill)
		draw_polyline(PackedVector2Array([pts[0], tip, pts[1]]), SceneStage.C_INK, 3.0, true)


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
		var dark: bool = color.get_luminance() < 0.55
		label.add_theme_color_override("font_color", SceneStage.C_PAPER if dark else SceneStage.C_INK)
		add_child(label)


## Foto de carné de un personaje (CharacterPainter.draw_portrait) para paneles de interfaz.
class PortraitBox extends Control:
	var appearance: Dictionary = {}
	var frame_color: Color = SceneStage.C_INK

	func _init(p_appearance: Dictionary, min_size: Vector2) -> void:
		appearance = p_appearance
		custom_minimum_size = min_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if appearance.is_empty():
			return
		CharacterPainter.draw_portrait(self, appearance, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(Vector2.ZERO, size), frame_color, false, 3.0)


## Línea de tiempo de golpes de guion: then(espera, acción) encadena; tick() ejecuta a su hora;
## flush() ejecuta todo ya (modo instantáneo de los tests, Esc para saltar la animación).
class Timeline extends RefCounted:
	var _beats: Array[Dictionary] = []
	var _clock: float = 0.0
	var _cursor: float = 0.0

	func then(delay: float, action: Callable) -> Timeline:
		_cursor = maxf(_cursor, _clock) + maxf(delay, 0.0)
		_beats.append({"at": _cursor, "fn": action})
		return self

	func tick(delta: float) -> void:
		_clock += delta
		while not _beats.is_empty() and float(_beats[0]["at"]) <= _clock:
			var beat: Dictionary = _beats.pop_front()
			(beat["fn"] as Callable).call()

	func flush() -> void:
		while not _beats.is_empty():
			var beat: Dictionary = _beats.pop_front()
			_clock = maxf(_clock, float(beat["at"]))
			(beat["fn"] as Callable).call()

	func is_busy() -> bool:
		return not _beats.is_empty()

	func clear() -> void:
		_beats.clear()


func _init() -> void:
	name = "SceneStage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_canvas = StageCanvas.new()
	_canvas.stage = self
	add_child(_canvas)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	resized.connect(_fit)


func _ready() -> void:
	_fit()


func _process(delta: float) -> void:
	_time += delta
	for id: String in _actors:
		_advance_actor(_actors[id], delta)
	_update_shake(delta)
	_expire_bubbles(delta)
	_place_overlays()
	_canvas.queue_redraw()


# ─── Configuración ────────────────────────────────────────────

## Decorado y banda de color (paleta de data/art_bands.json) del plató.
func configure(p_set: String) -> void:
	set_kind = p_set
	band_id = BAND_INTERROGATION if p_set == SET_INTERROGATION else BAND_AURORA
	var record: Dictionary = Database.get_art_band(band_id)
	pal = RoomPainter.palette_of(record)
	var path: String = B_SCALE_INTERROGATION if p_set == SET_INTERROGATION else B_SCALE_AURORA
	char_scale = Database.get_balance_float(path)
	var style: Dictionary = {"band": band_id, "pal": pal, "room_id": "stage_" + p_set,
			"cell": FurniturePainter.REFERENCE_CELL * char_scale, "kit": "",
			"plastic": bool(record.get("plants_are_plastic", true)), "lighting": {}}
	_furniture = FurniturePainter.new(style)
	_vignette = _make_vignette()
	_canvas.queue_redraw()


func set_prop(prop: String, value: Variant) -> void:
	_props[prop] = value
	_canvas.queue_redraw()


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


## Punto de pie del orador en el atril (detrás del atril, mirando a la sala).
static func aurora_podium_spot() -> Vector2:
	return AURORA_PODIUM + Vector2(0, -26)


static func interrogation_spots() -> Dictionary:
	var t: Rect2 = INTERROGATION_TABLE
	return {
		"investigator": Vector2(t.get_center().x, t.position.y - 22.0),
		"player": Vector2(t.get_center().x, t.end.y + 74.0),
		"investigator_standing": Vector2(t.end.x + 70.0, t.position.y + 8.0),
		"card": Vector2(t.position.x + t.size.x * 0.3, t.get_center().y),
	}


# ─── Reparto ──────────────────────────────────────────────────

## {appearance, tier, name} de un personaje: el jugador (semilla fija y escalón actual), un NPC en
## ejecución, un nominado del catálogo o, en último caso, uno genérico por semilla del id.
static func cast_member(npc_id: String) -> Dictionary:
	if npc_id == PLAYER_ID:
		var tier: int = maxi(1, PlayerState.get_tier())
		var me: Dictionary = CharacterPainter.appearance_from_seed(
				Database.get_balance_int(SEAT_PATH), tier, false, "")
		me["uniform"] = CharacterPainter.uniform_for_disguise(PlayerState.get_disguise())
		return {"appearance": me, "tier": tier, "name": PlayerState.get_player_name()}
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null:
		return {"appearance": CharacterPainter.appearance_for_npc(npc), "tier": npc.tier,
				"name": npc.name}
	var named: NPCData = Database.get_named_npc(npc_id)
	if named != null:
		var occ: OccupationData = Database.get_occupation(named.occupation)
		var t: int = occ.tier if occ != null else int(named.extra.get("tier", 1))
		return {"appearance": CharacterPainter.appearance_for_named(named, t), "tier": t,
				"name": named.name}
	return {"appearance": CharacterPainter.appearance_from_seed(hash(npc_id), 1, false, ""),
			"tier": 1, "name": npc_id}


## spot: {pos, facing, seated (bool), anim, chair (bool), chair_style}.
func add_actor(actor_id: String, member: Dictionary, spot: Dictionary) -> void:
	var seated: bool = bool(spot.get("seated", false))
	var pos: Vector2 = spot.get("pos", Vector2.ZERO)
	if bool(spot.get("chair", seated)):
		add_chair(actor_id, pos, spot.get("facing", Vector2.DOWN),
				str(spot.get("chair_style", CHAIR_EXEC)))
	_actors[actor_id] = {"id": actor_id, "app": member.get("appearance", {}),
		"tier": int(member.get("tier", 1)), "name": str(member.get("name", actor_id)),
		"pos": pos, "facing": spot.get("facing", Vector2.DOWN), "look": Vector2.ZERO,
		"seated": seated, "seat": actor_id if seated else "",
		"anim": str(spot.get("anim", "sit" if seated else "idle")), "frame": 0, "t": 0.0,
		"then": "", "marker": Color.TRANSPARENT, "visible": true}


func has_actor(actor_id: String) -> bool:
	return _actors.has(actor_id)


func get_actor(actor_id: String) -> Dictionary:
	return _actors.get(actor_id, {})


func actor_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _actors:
		out.append(id)
	return out


func add_chair(chair_id: String, center: Vector2, facing: Vector2, chair_style: String) -> void:
	_chairs[chair_id] = {"center": center, "facing": facing, "style": chair_style}


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


func set_look(actor_id: String, look: Vector2) -> void:
	if _actors.has(actor_id):
		_actors[actor_id]["look"] = look


## Mira a otro actor (o deja de mirar con target vacío).
func look_at_actor(actor_id: String, target_id: String) -> void:
	if not _actors.has(actor_id):
		return
	var look: Vector2 = Vector2.ZERO
	if _actors.has(target_id) and target_id != actor_id:
		look = (actor_feet(target_id) - actor_feet(actor_id)).normalized()
	_actors[actor_id]["look"] = look


## De pie junto a su silla (seated = false) o de vuelta a ella.
func set_seated(actor_id: String, seated: bool) -> void:
	var a: Dictionary = _actors.get(actor_id, {})
	if a.is_empty() or str(a["seat"]).is_empty():
		return
	var chair: Dictionary = _chairs[a["seat"]]
	a["seated"] = seated
	a["pos"] = chair["center"] if seated else chair["center"] - chair["facing"] * 14.0 * char_scale
	set_anim(actor_id, "sit" if seated else "idle")


func move_actor(actor_id: String, pos: Vector2) -> void:
	if _actors.has(actor_id):
		_actors[actor_id]["pos"] = pos
		_actors[actor_id]["seated"] = false


## Marca de color bajo los pies (acusador, aliados...). TRANSPARENT la quita.
func set_marker(actor_id: String, color: Color) -> void:
	if _actors.has(actor_id):
		_actors[actor_id]["marker"] = color


func clear_markers() -> void:
	for id: String in _actors:
		_actors[id]["marker"] = Color.TRANSPARENT


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


## Coordenadas de diseño → coordenadas del control.
func to_screen(design_point: Vector2) -> Vector2:
	return _canvas.position + design_point * _canvas.scale.x


func screen_scale() -> float:
	return _canvas.scale.x


## Rectángulo del lienzo de diseño visible en el control (puede exceder DESIGN).
func view_rect() -> Rect2:
	var s: float = maxf(_canvas.scale.x, 0.001)
	return Rect2(-(_canvas.position - _shake_offset) / s, size / s)


func _origin_of(a: Dictionary) -> Vector2:
	if not bool(a["seated"]):
		return a["pos"]
	var offset: Vector2 = CharacterPainter.seat_origin(Vector2.ZERO, a["app"], int(a["tier"]))
	return (a["pos"] as Vector2) + offset * char_scale


func _advance_actor(a: Dictionary, delta: float) -> void:
	var fps: float = CharacterPainter.anim_fps(str(a["anim"]))
	if fps <= 0.0:
		return
	a["t"] = float(a["t"]) + delta
	while float(a["t"]) >= 1.0 / fps:
		a["t"] = float(a["t"]) - 1.0 / fps
		var next: int = CharacterAnim.next_frame(str(a["anim"]), int(a["frame"]))
		if next < 0 or (next == int(a["frame"]) and not str(a["then"]).is_empty()):
			if not str(a["then"]).is_empty():
				set_anim(str(a["id"]), str(a["then"]))
			return
		a["frame"] = next


# ─── Bocadillos e insignias ───────────────────────────────────

## Bocadillo sobre el actor. seconds < 0 → tiempo de lectura; 0 → hasta que se retire. "" lo quita.
func say(actor_id: String, text: String, style: String = STYLE_SAY, seconds: float = -1.0) -> void:
	if _bubbles.has(actor_id):
		(_bubbles[actor_id] as Node).queue_free()
		_bubbles.erase(actor_id)
	if text.is_empty() or not _actors.has(actor_id):
		return
	var bubble: Bubble = Bubble.new(text, style, 460.0)
	bubble.hold = reading_time(text) if seconds < 0.0 else seconds
	_overlay.add_child(bubble)
	_bubbles[actor_id] = bubble
	_place_overlays()


## Segundos de lectura de un texto (balance escenas.bocadillo_*).
static func reading_time(text: String) -> float:
	var t: float = Database.get_balance_float(B_BUBBLE_BASE) \
			+ Database.get_balance_float(B_BUBBLE_PER_CHAR) * float(text.length())
	return minf(t, Database.get_balance_float(B_BUBBLE_MAX))


func bubble_text(actor_id: String) -> String:
	var bubble: Bubble = _bubbles.get(actor_id) as Bubble
	return bubble.get_text() if bubble != null and is_instance_valid(bubble) else ""


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
	_badges[actor_id] = b
	_place_overlays()


func badge_text(actor_id: String) -> String:
	var b: Badge = _badges.get(actor_id) as Badge
	if b == null or not is_instance_valid(b) or b.get_child_count() == 0:
		return ""
	return (b.get_child(0) as Label).text


func clear_badges() -> void:
	for id: String in _badges.keys():
		badge(id, "", Color.WHITE)


func _expire_bubbles(delta: float) -> void:
	for id: String in _bubbles.keys():
		var bubble: Bubble = _bubbles[id]
		if bubble.hold <= 0.0:
			continue
		bubble.hold -= delta
		if bubble.hold <= 0.0:
			say(id, "")


func _place_overlays() -> void:
	var margin: float = 12.0
	for id: String in _badges:
		var b: Control = _badges[id]
		b.reset_size()
		var head: Vector2 = head_point(id)
		b.position = head - Vector2(b.size.x * 0.5, b.size.y + 6.0)
	for id: String in _bubbles:
		var bubble: Bubble = _bubbles[id]
		bubble.reset_size()
		var head: Vector2 = head_point(id) - Vector2(0, Bubble.TAIL + 6.0)
		if _badges.has(id):
			head.y -= (_badges[id] as Control).size.y + 4.0
		var x: float = clampf(head.x - bubble.size.x * 0.5, margin, size.x - bubble.size.x - margin)
		var y: float = maxf(head.y - bubble.size.y, margin)
		bubble.position = Vector2(x, y)
		bubble.tail_x = (head.x - x) / maxf(bubble.size.x, 1.0)
		bubble.queue_redraw()


static func bubble_fill(style: String) -> Color:
	match style:
		STYLE_SHOUT:
			return C_SHOUT
		STYLE_WHISPER:
			return C_WHISPER
		STYLE_NARRATE:
			return Color(C_NARRATE, 0.92)
	return C_PAPER


static func bubble_box(fill: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = C_INK
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_color = Color(0, 0, 0, 0.25)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 3)
	box.anti_aliasing = true
	return box


## Ancho natural de una línea de texto con la fuente del label.
static func text_width(text: String, label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x if font != null else 0.0


# ─── Temblor y ajuste ─────────────────────────────────────────

func shake(px: float, seconds: float) -> void:
	_shake_px = px
	_shake_total = maxf(seconds, 0.001)
	_shake_left = seconds


func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		if _shake_offset != Vector2.ZERO:
			_shake_offset = Vector2.ZERO
			_fit()
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	var amount: float = _shake_px * _shake_left / _shake_total
	_shake_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * amount
	_fit()


func _fit() -> void:
	if _canvas == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var s: float = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_canvas.scale = Vector2(s, s)
	_canvas.position = (size - DESIGN * s) * 0.5 + _shake_offset
	_overlay.position = _shake_offset


# ─── Dibujo ───────────────────────────────────────────────────

func paint(ci: Node2D) -> void:
	if pal.is_empty():
		return
	var view: Rect2 = view_rect()
	if set_kind == SET_INTERROGATION:
		_paint_interrogation_back(ci, view)
	else:
		_paint_aurora_back(ci, view)
	var items: Array[Dictionary] = _set_pieces()
	for id: String in _chairs:
		items.append_array(_chair_items(id))
	for id: String in _actors:
		if bool(_actors[id]["visible"]):
			items.append({"y": _origin_of(_actors[id]).y, "fn": _draw_actor.bind(id)})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["y"]) < float(b["y"]))
	for item: Dictionary in items:
		(item["fn"] as Callable).call(ci)
	if set_kind == SET_INTERROGATION:
		_paint_interrogation_front(ci, view)


func _set_pieces() -> Array[Dictionary]:
	if set_kind == SET_INTERROGATION:
		return [
			{"y": INTERROGATION_TABLE.get_center().y + 20.0, "fn": _paint_steel_table},
			{"y": 640.0, "fn": _paint_furniture.bind("filing_cabinet", Rect2(1716, 470, 110, 120))},
		]
	return [
		{"y": AURORA_TABLE.get_center().y + 40.0, "fn": _paint_meeting_table},
		{"y": AURORA_PODIUM.y, "fn": _paint_podium},
		{"y": 420.0, "fn": _paint_furniture.bind("plant", Rect2(84, 330, 110, 110))},
		{"y": 420.0, "fn": _paint_furniture.bind("plant", Rect2(1726, 330, 110, 110))},
		{"y": 760.0, "fn": _paint_furniture.bind("water_cooler", Rect2(1740, 660, 110, 110))},
		{"y": 700.0, "fn": _paint_furniture.bind("coffee_machine", Rect2(60, 610, 110, 110))},
	]


func _paint_furniture(ci: CanvasItem, type: String, r: Rect2) -> void:
	_furniture.draw_item(ci, {"type": type, "rotation": 0, "pos": Vector2i(r.position)}, r)


func _draw_actor(ci: CanvasItem, actor_id: String) -> void:
	var a: Dictionary = _actors[actor_id]
	var origin: Vector2 = _origin_of(a)
	var marker: Color = a["marker"]
	if marker.a > 0.0:
		var r: Vector2 = Vector2(26.0, 11.0) * char_scale
		ci.draw_colored_polygon(CharacterStyle.ellipse(origin, r), Color(marker, 0.45))
		ci.draw_polyline(CharacterStyle.ellipse(origin, r), marker, 3.0, true)
	var extra: Dictionary = {"seated": bool(a["seated"])}
	if (a["look"] as Vector2) != Vector2.ZERO:
		extra["look"] = a["look"]
	var pose: Dictionary = CharacterPainter.make_pose(str(a["anim"]), int(a["frame"]), a["facing"], extra)
	pose["origin"] = origin
	pose["scale"] = char_scale
	CharacterPainter.draw(ci, a["app"], int(a["tier"]), pose)


## Una silla se dibuja en dos pasadas ordenadas por Y: asiento y respaldo trasero antes del
## ocupante; el respaldo que queda delante (silla de espaldas a cámara) después.
func _chair_items(chair_id: String) -> Array[Dictionary]:
	var chair: Dictionary = _chairs[chair_id]
	var c: Vector2 = chair["center"]
	var facing: Vector2 = chair["facing"]
	var s: float = char_scale
	var out: Array[Dictionary] = [{"y": c.y - 30.0 * s, "fn": _paint_chair.bind(chair, false)}]
	if facing.y < -0.5:
		out.append({"y": c.y + 30.0 * s, "fn": _paint_chair.bind(chair, true)})
	return out


func _paint_chair(ci: CanvasItem, chair: Dictionary, front: bool) -> void:
	var s: float = char_scale
	var c: Vector2 = chair["center"]
	var f: Vector2 = chair["facing"]
	var col: Color = _chair_color(str(chair["style"]))
	var ol: Color = band_color("outline")
	if front:
		_rounded_box(ci, Rect2(c + Vector2(-17, -6) * s, Vector2(34, 22) * s), 6.0 * s, col.lightened(0.1), ol, s)
		return
	ci.draw_colored_polygon(CharacterStyle.ellipse(c + Vector2(0, 12) * s, Vector2(20, 7) * s), C_SHADOW)
	if f.y > 0.5:
		_rounded_box(ci, Rect2(c + Vector2(-17, -44) * s, Vector2(34, 36) * s), 7.0 * s, col.lightened(0.1), ol, s)
	elif absf(f.x) > 0.5:
		var bx: float = -f.x * 14.0 - 4.0
		_rounded_box(ci, Rect2(c + Vector2(bx, -40) * s, Vector2(8, 44) * s), 3.0 * s, col.lightened(0.1), ol, s)
	_rounded_box(ci, Rect2(c + Vector2(-16, -8) * s, Vector2(32, 18) * s), 6.0 * s, col, ol, s)
	ci.draw_line(c + Vector2(0, 10) * s, c + Vector2(0, 16) * s, C_STEEL_DARK, 3.0 * s)


func _chair_color(chair_style: String) -> Color:
	match chair_style:
		CHAIR_LEATHER:
			return Color("#4a2a1c")
		CHAIR_STEEL:
			return Color("#7d868c")
	return Color("#2f3640")


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


func _text(ci: CanvasItem, text: String, pos: Vector2, width: float, size: int, color: Color,
		bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	ci.draw_multiline_string(_font(bold), pos, text, align, width, size, -1, color)


# ─── Decorado Aurora (P12, the_specialists) ───────────────────

func _paint_aurora_back(ci: CanvasItem, view: Rect2) -> void:
	var carpet: Color = band_color("carpet")
	ci.draw_rect(view, carpet)
	_paint_tiles(ci, Rect2(view.position.x, AURORA_WALL_Y, view.size.x, view.end.y - AURORA_WALL_Y),
			carpet.lightened(0.07), 96.0)
	_paint_corridors(ci, view)
	_paint_window_wall(ci, view)
	_paint_screen(ci)
	_paint_poster(ci, Rect2(1290, 58, 150, 196))
	_paint_clock(ci, Vector2(560, 112), 30.0)
	_paint_camera_dome(ci, Vector2(minf(view.end.x, DESIGN.x) - 70.0, 34.0))
	_paint_glass_side(ci, 0.0)
	_paint_glass_side(ci, DESIGN.x - 16.0)


func _paint_tiles(ci: CanvasItem, area: Rect2, tint: Color, tile: float) -> void:
	var x0: int = floori(area.position.x / tile)
	var y0: int = floori(area.position.y / tile)
	for gx: int in range(x0, ceili(area.end.x / tile)):
		for gy: int in range(y0, ceili(area.end.y / tile)):
			if (gx + gy) % 2 == 0:
				continue
			var r: Rect2 = Rect2(Vector2(gx, gy) * tile, Vector2(tile, tile)).intersection(area)
			ci.draw_rect(r, Color(tint, 0.35))


## Pasillo de moqueta clara al otro lado de los tabiques de cristal (pantallas más anchas).
func _paint_corridors(ci: CanvasItem, view: Rect2) -> void:
	var hall: Color = band_color("floor")
	if view.position.x < 0.0:
		ci.draw_rect(Rect2(view.position.x, 0, -view.position.x, view.size.y + view.position.y), hall)
	if view.end.x > DESIGN.x:
		ci.draw_rect(Rect2(DESIGN.x, 0, view.end.x - DESIGN.x, view.size.y + view.position.y), hall)


func _paint_window_wall(ci: CanvasItem, view: Rect2) -> void:
	var wall: Color = band_color("wall")
	var top: float = minf(view.position.y, 0.0)
	ci.draw_rect(Rect2(0, top, DESIGN.x, AURORA_WALL_Y - top), wall)
	ci.draw_rect(Rect2(0, top, DESIGN.x, 20.0 - top), band_color("shadow").lerp(wall, 0.35))
	var panes: int = 8
	var pane_w: float = (DESIGN.x - 60.0) / float(panes)
	for i: int in panes:
		_paint_window_pane(ci, Rect2(30.0 + pane_w * i + 6.0, 34, pane_w - 12.0, 214), i)
	ci.draw_rect(Rect2(0, 250, DESIGN.x, 16), wall.darkened(0.06))
	ci.draw_rect(Rect2(0, AURORA_WALL_Y - 16.0, DESIGN.x, 16), band_color("accent").darkened(0.2))
	ci.draw_line(Vector2(0, AURORA_WALL_Y), Vector2(DESIGN.x, AURORA_WALL_Y), band_color("outline"), 3.0)


## Un paño del ventanal: cielo en degradado y siluetas de la ciudad (deterministas por índice).
func _paint_window_pane(ci: CanvasItem, r: Rect2, index: int) -> void:
	var sky_top: Color = band_color("light").lerp(band_color("window"), 0.25)
	var sky_low: Color = band_color("window")
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)]), PackedColorArray([sky_top, sky_top, sky_low, sky_low]))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = index * 7919 + 17
	var x: float = r.position.x
	var city: Color = band_color("window").darkened(0.22)
	while x < r.end.x:
		var w: float = rng.randf_range(26, 58)
		var h: float = rng.randf_range(40, 150)
		var b: Rect2 = Rect2(x, r.end.y - h, minf(w, r.end.x - x), h)
		ci.draw_rect(b, city.lerp(sky_low, rng.randf_range(0.0, 0.35)))
		x += w + rng.randf_range(2, 10)
	ci.draw_rect(Rect2(r.position.x + 8, r.position.y + 8, 10, r.size.y - 16), Color(1, 1, 1, 0.22))
	ci.draw_rect(r, band_color("outline"), false, 3.0)


func _paint_screen(ci: CanvasItem) -> void:
	var r: Rect2 = AURORA_SCREEN
	var ol: Color = band_color("outline")
	ci.draw_rect(Rect2(r.position + Vector2(8, 10), r.size), Color(0, 0, 0, 0.18))
	_outline_rect(ci, r, C_SCREEN)
	_outline_rect(ci, Rect2(r.position.x - 22, r.position.y - 16, r.size.x + 44, 18), C_STEEL_DARK)
	var band: Rect2 = Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 38))
	ci.draw_rect(band, band_color("accent"))
	_text(ci, str(_props.get("screen_kicker", "")), band.position + Vector2(18, 26), band.size.x - 36,
			17, C_PAPER, true, HORIZONTAL_ALIGNMENT_LEFT)
	_text(ci, str(_props.get("screen_title", "")), r.position + Vector2(26, 84), r.size.x - 52, 27,
			C_INK, true)
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
	ci.draw_line(Vector2(r.position.x - 4, r.end.y - 6), Vector2(r.end.x + 6, r.position.y - 4),
			Color("#e24b3b"), 4.0, true)
	ci.draw_line(Vector2(r.position.x - 4, r.end.y), Vector2(r.end.x + 8, r.end.y), band_color("outline"), 2.0)


func _paint_poster(ci: CanvasItem, r: Rect2) -> void:
	_outline_rect(ci, r, band_color("furniture"))
	var art: Rect2 = Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, r.size.y * 0.52))
	ci.draw_rect(art, band_color("accent").darkened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(art.position.x, art.end.y),
			Vector2(art.get_center().x - 10, art.position.y + 22), Vector2(art.end.x, art.end.y)]),
			band_color("window").lightened(0.3))
	ci.draw_circle(art.position + Vector2(art.size.x * 0.75, 20), 9.0, Color("#ffd85a"))
	_text(ci, str(_props.get("poster", "")), Vector2(r.position.x + 6, art.end.y + 24), r.size.x - 12,
			15, C_INK, true)


func _paint_clock(ci: CanvasItem, c: Vector2, radius: float) -> void:
	var ol: Color = band_color("outline")
	ci.draw_circle(c + Vector2(3, 4), radius, Color(0, 0, 0, 0.15))
	ci.draw_circle(c, radius, C_PAPER)
	ci.draw_arc(c, radius, 0.0, TAU, 40, ol, 4.0, true)
	var hm: Vector2i = _props.get("clock", Vector2i(11, 0))
	var minute_a: float = TAU * float(hm.y) / 60.0 - PI * 0.5
	var hour_a: float = TAU * (float(hm.x % 12) + float(hm.y) / 60.0) / 12.0 - PI * 0.5
	ci.draw_line(c, c + Vector2.from_angle(hour_a) * radius * 0.5, ol, 4.0, true)
	ci.draw_line(c, c + Vector2.from_angle(minute_a) * radius * 0.78, ol, 3.0, true)
	ci.draw_circle(c, 3.5, C_RED_LED)


## Cámara domo en la esquina: el edificio mira (§12.4).
func _paint_camera_dome(ci: CanvasItem, c: Vector2) -> void:
	ci.draw_rect(Rect2(c.x - 26, c.y - 22, 52, 12), C_STEEL_DARK)
	ci.draw_circle(c, 20.0, Color("#23282e"))
	ci.draw_arc(c, 20.0, 0.0, PI, 20, band_color("outline"), 3.0, true)
	ci.draw_circle(c + Vector2(-6, 4), 6.0, Color("#56606a"))
	var blink: bool = fmod(_time, 1.2) < 0.7
	ci.draw_circle(c + Vector2(9, -2), 3.5, C_RED_LED if blink else C_RED_LED.darkened(0.6))


func _paint_glass_side(ci: CanvasItem, x: float) -> void:
	var glass: Color = Color(band_color("window"), 0.85)
	var bottom: float = DESIGN.y + 400.0
	ci.draw_rect(Rect2(x, 0, 16, bottom), glass)
	ci.draw_rect(Rect2(x + 3, 0, 3, bottom), Color(1, 1, 1, 0.5))
	for y: int in range(0, int(bottom), 180):
		ci.draw_rect(Rect2(x - 3, float(y), 22, 10), C_STEEL_DARK)
	ci.draw_rect(Rect2(x, 560, 16, 70), Color(1, 1, 1, 0.55))
	ci.draw_line(Vector2(x, 0), Vector2(x, bottom), band_color("outline"), 2.0)
	ci.draw_line(Vector2(x + 16, 0), Vector2(x + 16, bottom), band_color("outline"), 2.0)


func _paint_meeting_table(ci: CanvasItem) -> void:
	var t: Rect2 = AURORA_TABLE
	var h: float = 8.0 * char_scale
	var top_col: Color = Color("#f7f9fb")
	var ol: Color = band_color("outline")
	ci.draw_rect(Rect2(t.position + Vector2(10, 16), t.size + Vector2(0, h)), C_SHADOW)
	var front: Rect2 = Rect2(t.position.x, t.end.y - 4.0, t.size.x, h + 4.0)
	_rounded_box(ci, front, 10.0, top_col.darkened(0.3), ol, 2.0)
	_rounded_box(ci, t, 18.0, top_col, ol, 2.0)
	ci.draw_polyline(_closed(rounded_rect(t.grow(-12.0), 10.0)), band_color("accent").lerp(top_col, 0.45), 2.0, true)
	for i: int in 6:
		var x: float = t.position.x + t.size.x * (i + 0.5) / 6.0
		_paint_table_setting(ci, Vector2(x, t.position.y + 26), i, true)
		_paint_table_setting(ci, Vector2(x, t.end.y - 30), i + 6, false)
	_paint_conference_phone(ci, t.get_center() + Vector2(0, 2))


## Portátil, papeles o taza delante de cada silla (variación determinista por puesto).
func _paint_table_setting(ci: CanvasItem, c: Vector2, index: int, far_side: bool) -> void:
	var ol: Color = band_color("outline")
	match index % 3:
		0:
			var lid: Rect2 = Rect2(c.x - 24, c.y - 8, 48, 16)
			_outline_rect(ci, lid, Color("#c9ced3"), 2.0)
			ci.draw_rect(lid.grow(-3.0), C_GLASS_DARK if far_side else Color("#9fd8f0"))
		1:
			_outline_rect(ci, Rect2(c.x - 18, c.y - 10, 30, 20), C_PAPER, 2.0)
			_outline_rect(ci, Rect2(c.x - 12, c.y - 6, 30, 20), C_PAPER, 2.0)
		_:
			ci.draw_circle(c, 9.0, Color("#eef1f2"))
			ci.draw_arc(c, 9.0, 0.0, TAU, 20, ol, 2.0, true)
			ci.draw_circle(c, 5.5, Color("#6b4226"))


func _paint_conference_phone(ci: CanvasItem, c: Vector2) -> void:
	var pts: PackedVector2Array = []
	for i: int in 3:
		var a: float = -PI * 0.5 + TAU * float(i) / 3.0
		pts.append(c + Vector2(cos(a), sin(a) * 0.6) * 30.0)
	ci.draw_colored_polygon(pts, Color("#2b2f36"))
	ci.draw_polyline(_closed(pts), band_color("outline"), 2.0, true)
	ci.draw_circle(c, 6.0, Color("#5dff8a") if fmod(_time, 2.0) < 1.6 else Color("#2b6b42"))


func _paint_podium(ci: CanvasItem) -> void:
	var s: float = char_scale
	var base: Vector2 = AURORA_PODIUM
	var ol: Color = band_color("outline")
	var wood: Color = band_color("furniture")
	var front: PackedVector2Array = [base + Vector2(-26, -44) * s, base + Vector2(26, -44) * s,
			base + Vector2(20, 0) * s, base + Vector2(-20, 0) * s]
	ci.draw_colored_polygon(CharacterStyle.ellipse(base + Vector2(0, 2) * s, Vector2(26, 7) * s), C_SHADOW)
	ci.draw_colored_polygon(front, wood.darkened(0.08))
	ci.draw_polyline(_closed(front), ol, 3.0, true)
	var top: PackedVector2Array = [base + Vector2(-30, -56) * s, base + Vector2(30, -56) * s,
			base + Vector2(27, -44) * s, base + Vector2(-27, -44) * s]
	ci.draw_colored_polygon(top, wood.lightened(0.1))
	ci.draw_polyline(_closed(top), ol, 3.0, true)
	ci.draw_rect(Rect2(base + Vector2(-20, -30) * s, Vector2(40, 8) * s), band_color("accent"))
	ci.draw_circle(base + Vector2(0, -16) * s, 6.0 * s, Color("#d8b04a"))
	ci.draw_line(base + Vector2(10, -56) * s, base + Vector2(4, -70) * s, C_STEEL_DARK, 2.0 * s, true)
	ci.draw_circle(base + Vector2(4, -71) * s, 3.0 * s, C_INK)


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


# ─── Decorado del interrogatorio (P15, the_power) ─────────────

func _paint_interrogation_back(ci: CanvasItem, view: Rect2) -> void:
	var floor_col: Color = band_color("carpet").lerp(band_color("shadow"), 0.35)
	ci.draw_rect(view, floor_col)
	_paint_tiles(ci, Rect2(view.position.x, INTERROGATION_WALL_Y, view.size.x,
			view.end.y - INTERROGATION_WALL_Y), floor_col.lightened(0.08), 120.0)
	_paint_panel_wall(ci, view)
	_paint_mirror(ci, Rect2(240, 78, 470, 176))
	_paint_poster(ci, Rect2(1088, 64, 132, 176))
	_paint_clock(ci, Vector2(1320, 132), 30.0)
	_paint_door(ci, float(_props.get("door", 0.0)))
	_paint_camera_dome(ci, Vector2(DESIGN.x - 70.0, 34.0))
	_paint_door_light(ci, float(_props.get("door", 0.0)))


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
				Vector2(x - 40, r.end.y), Vector2(x - 74, r.end.y)]), Color(1, 1, 1, 0.06))
	ci.draw_circle(Vector2(r.position.x + r.size.x * 0.78, r.position.y + 70), 7.0, Color(band_color("light"), 0.35))
	ci.draw_rect(r, band_color("outline"), false, 3.0)


## Puerta de la pared norte: `open` 1 = abierta (hoja girada hacia dentro, pasillo iluminado).
func _paint_door(ci: CanvasItem, open: float) -> void:
	var r: Rect2 = INTERROGATION_DOOR
	var ol: Color = band_color("outline")
	var wood: Color = band_color("furniture").lightened(0.05)
	_outline_rect(ci, r.grow(10.0), band_color("furniture").darkened(0.35))
	ci.draw_rect(r, band_color("light") if open > 0.02 else wood)
	if open > 0.02:
		ci.draw_rect(Rect2(r.position.x, r.end.y - 60, r.size.x, 60), band_color("light").darkened(0.12))
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
		ci.draw_line(pane.position, pane.end, Color(1, 1, 1, 0.1), 2.0)


func _paint_door_light(ci: CanvasItem, open: float) -> void:
	if open <= 0.02:
		return
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
	ci.draw_rect(Rect2(t.position + Vector2(12, 18), t.size + Vector2(0, h)), C_SHADOW)
	_rounded_box(ci, Rect2(t.position.x, t.end.y - 4.0, t.size.x, h + 4.0), 6.0, C_STEEL.darkened(0.35), ol, 2.0)
	_rounded_box(ci, t, 10.0, C_STEEL, ol, 2.0)
	ci.draw_rect(Rect2(t.position.x + 10, t.position.y + 8, t.size.x - 20, 6), Color(1, 1, 1, 0.25))
	for corner: Vector2 in [t.position + Vector2(14, 14), Vector2(t.end.x - 14, t.position.y + 14),
			Vector2(t.position.x + 14, t.end.y - 14), t.end - Vector2(14, 14)]:
		ci.draw_circle(corner, 3.5, C_STEEL_DARK)
	_paint_folder(ci, Rect2(t.position.x + 60, t.position.y + 18, 150, 74))
	_paint_recorder(ci, Vector2(t.end.x - 110, t.position.y + 40))
	_paint_nameplate(ci, Vector2(t.get_center().x + 120, t.end.y - 26))
	if bool(_props.get("coffee", false)):
		_paint_coffee(ci, Vector2(t.get_center().x - 110, t.end.y - 34))
	if bool(_props.get("paper", false)):
		var paper: Rect2 = Rect2(t.get_center().x - 58, t.position.y + 46, 86, 60)
		_outline_rect(ci, paper, C_PAPER, 2.0)
		ci.draw_rect(Rect2(paper.position + Vector2(10, 12), Vector2(50, 5)), Color("#b0463c"))


func _paint_folder(ci: CanvasItem, r: Rect2) -> void:
	_outline_rect(ci, r, C_MANILA, 2.0)
	_outline_rect(ci, Rect2(r.position + Vector2(10, 8), Vector2(r.size.x * 0.46, r.size.y - 16)), C_PAPER, 2.0)
	for i: int in 4:
		ci.draw_line(r.position + Vector2(18, 20 + i * 11), r.position + Vector2(r.size.x * 0.46, 20 + i * 11),
				Color(C_INK, 0.45), 2.0)
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.6, r.position.y + 14, 40, 40), Color("#6e6f73"))


func _paint_recorder(ci: CanvasItem, c: Vector2) -> void:
	var body: Rect2 = Rect2(c - Vector2(40, 18), Vector2(80, 36))
	_outline_rect(ci, body, Color("#2b2f36"), 2.0)
	for dx: float in [-18.0, 18.0]:
		ci.draw_circle(c + Vector2(dx, 0), 9.0, Color("#8a8f96"))
		ci.draw_line(c + Vector2(dx, 0), c + Vector2(dx, 0) + Vector2.from_angle(_time * 3.0) * 8.0, C_INK, 2.0)
	ci.draw_circle(c + Vector2(30, -10), 3.0, C_RED_LED if fmod(_time, 1.0) < 0.6 else C_RED_LED.darkened(0.6))


func _paint_nameplate(ci: CanvasItem, c: Vector2) -> void:
	var plate: Rect2 = Rect2(c - Vector2(78, 14), Vector2(156, 28))
	_outline_rect(ci, plate, band_color("accent"), 2.0)
	_text(ci, str(_props.get("nameplate", "")), plate.position + Vector2(4, 20), plate.size.x - 8, 15,
			band_color("shadow"), true)


func _paint_coffee(ci: CanvasItem, c: Vector2) -> void:
	var ol: Color = band_color("outline")
	ci.draw_colored_polygon(CharacterStyle.ellipse(c, Vector2(26, 11)), C_PAPER)
	ci.draw_polyline(_closed(CharacterStyle.ellipse(c, Vector2(26, 11))), ol, 2.0, true)
	var cup: Vector2 = c + Vector2(0, -8)
	ci.draw_circle(cup, 13.0, C_PAPER)
	ci.draw_arc(cup, 13.0, 0.0, TAU, 20, ol, 2.0, true)
	ci.draw_circle(cup, 9.0, Color("#6b4226"))
	ci.draw_arc(cup + Vector2(15, 0), 5.0, -PI * 0.5, PI * 0.5, 8, ol, 3.0, true)
	for i: int in 2:
		var x: float = cup.x - 5.0 + i * 10.0
		var wave: float = sin(_time * 3.0 + i) * 3.0
		ci.draw_line(Vector2(x, cup.y - 18), Vector2(x + wave, cup.y - 34), Color(1, 1, 1, 0.5), 2.0, true)


## Lámpara colgante, cono de luz y viñeta; después, la onomatopeya del portazo.
func _paint_interrogation_front(ci: CanvasItem, view: Rect2) -> void:
	var lamp: String = str(_props.get("lamp", LAMP_NEUTRAL))
	var light: Color = _lamp_color(lamp)
	var cone_a: float = 0.2 if lamp == LAMP_HARSH else 0.13
	var c: Vector2 = INTERROGATION_LAMP
	ci.draw_polygon(PackedVector2Array([c + Vector2(-70, 40), c + Vector2(70, 40), Vector2(1330, 800),
			Vector2(590, 800)]), PackedColorArray([Color(light, cone_a), Color(light, cone_a),
			Color(light, 0.0), Color(light, 0.0)]))
	var dark: Color = _lamp_darkness(lamp)
	ci.draw_texture_rect(_vignette, Rect2(c.x - 1500.0, c.y - 1040.0, 3000.0, 2300.0), false, dark)
	_fill_outside(ci, view, Rect2(c.x - 1500.0, c.y - 1040.0, 3000.0, 2300.0), dark)
	ci.draw_line(Vector2(c.x, view.position.y), c + Vector2(0, -6), C_INK, 4.0)
	var shade: PackedVector2Array = [c + Vector2(-26, -8), c + Vector2(26, -8), c + Vector2(72, 42),
			c + Vector2(-72, 42)]
	ci.draw_colored_polygon(shade, Color("#2e3b35"))
	ci.draw_polyline(_closed(shade), C_INK, 3.0, true)
	ci.draw_colored_polygon(CharacterStyle.ellipse(c + Vector2(0, 42), Vector2(66, 12)), light.lightened(0.4))
	_paint_slam(ci, float(_props.get("slam", 0.0)))


func _fill_outside(ci: CanvasItem, view: Rect2, inner: Rect2, dark: Color) -> void:
	var tint: Color = Color(dark, dark.a)
	if view.position.x < inner.position.x:
		ci.draw_rect(Rect2(view.position.x, view.position.y, inner.position.x - view.position.x, view.size.y), tint)
	if view.end.x > inner.end.x:
		ci.draw_rect(Rect2(inner.end.x, view.position.y, view.end.x - inner.end.x, view.size.y), tint)


func _lamp_color(lamp: String) -> Color:
	match lamp:
		LAMP_WARM:
			return band_color("light")
		LAMP_HARSH:
			return Color("#eef6ff")
	return band_color("light").lerp(Color.WHITE, 0.5)


## Oscuridad de los bordes según el tono: la disculpa ilumina la sala; el portazo la hunde.
func _lamp_darkness(lamp: String) -> Color:
	var shadow: Color = band_color("shadow")
	match lamp:
		LAMP_WARM:
			return Color(shadow, 0.5)
		LAMP_HARSH:
			return Color(Color("#05070c"), 0.9)
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
	ci.draw_colored_polygon(pts, C_SHOUT)
	ci.draw_polyline(_closed(pts), C_INK, 5.0, true)
	ci.draw_set_transform(c, -0.12, Vector2(amount, amount))
	var text: String = str(_props.get("slam_text", ""))
	var size: int = 64
	var w: float = _font(true).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string_outline(_font(true), Vector2(-w * 0.5, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, C_INK)
	ci.draw_string(_font(true), Vector2(-w * 0.5, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("#e2382b"))
	ci.draw_set_transform(Vector2.ZERO)
