# tutorial_video.gd — La imagen del vídeo corporativo de bienvenida (§13.8): un Harlan Voss quince años más joven hablando ante un decorado de empresa, con grano de cinta, marca de reproducción y fin de cinta.
# PROPIETARIO DE: el estado de reproducción visible (modo, fotograma del orador, tiempo de cinta).
# ESCUCHA: nada (Tutorial le cambia el modo; se anima sola en _process).
class_name TutorialVideoFeed
extends Control

## Dibujo vectorial propio (sin recursos externos): degradado corporativo, estrella del logotipo,
## gráfica que solo sube, el orador (CharacterPainter.draw, plano medio: se recorta por abajo),
## líneas de barrido, franja de seguimiento que baja, marca «▶ REPR.» y contador de cinta. En modo
## MODE_END: nieve de cinta y el rótulo de fin de grabación. Los textos son claves de strings.csv.
## Voss joven: su dirección de arte (NAMED_LOOKS) con la cabeza una edad más joven, el pelo aún
## oscuro y sin el volumen de consejero delegado de hoy (young_voss_appearance()).

const MODE_TALK := "talk"
const MODE_PRAISE := "praise"
const MODE_END := "end"
const ANIM_TALK := "chat"
const ANIM_PRAISE := "bribe"
const VOSS_ID := "npc_harlan_voss"
## Dirección de arte del Voss de 2011 (cabeza: forma + 5 × edad, una edad menos; pelo oscuro).
const YOUNG_AGE_STEP := 5
const YOUNG_HAIR_COLOR := 1
const YOUNG_VOLUME := 1.0
const TAPE_KEY_PLAY := "TUT_VIDEO_PLAY"
const TAPE_KEY_END := "TUT_VIDEO_END"
const TAGLINE_KEY := "TUT_VIDEO_TAGLINE"
const BRAND_KEY := "UI_COMPANY_NAME"
const C_SKY_TOP := Color("#1e4d8f")
const C_SKY_BOTTOM := Color("#0b1a33")
const C_STAR := Color("#ffd35c")
const C_BAR := Color(1.0, 1.0, 1.0, 0.12)
const C_BAR_TOP := Color("#5fd38d")
const C_SCAN := Color(0.0, 0.0, 0.0, 0.16)
const C_TRACK := Color(1.0, 1.0, 1.0, 0.07)
const C_TEXT := Color("#f4f1ea")
const C_PLAY := Color("#5dff8a")
## Proporciones del dibujo (fracciones del alto del cuadro): no son ajustes de juego.
const SPEAKER_SCALE := 0.0142
const SPEAKER_DROP := 0.3
const STAR_R := 0.075
const BRAND_SIZE := 0.075
const TAGLINE_SIZE := 0.045
const TAPE_SIZE := 0.05
const SCAN_STEP := 3.0
const TRACK_H := 0.06
const TRACK_SPEED := 0.22
const NOISE_CELLS := 36
const BAR_COUNT := 6
const STAR_POINTS := 5
const REDRAW_HZ := 12.0

var _mode: String = MODE_TALK
var _app: Dictionary = {}
var _tier: int = 8
var _frame: int = 0
var _anim_clock: float = 0.0
var _time: float = 0.0
var _redraw_left: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	name = "VideoFeed"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## El orador de 2011: su apariencia de hoy rejuvenecida.
static func young_voss_appearance() -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(VOSS_ID)
	var app: Dictionary = {}
	if npc != null:
		app = CharacterPainter.appearance_for_npc(npc).duplicate()
	else:
		var data: NPCData = Database.get_named_npc(VOSS_ID)
		if data == null:
			return CharacterPainter.appearance_from_seed(0, CharacterStyle.OUTFIT_COUNT, false, "")
		app = CharacterPainter.appearance_for_named(data, CharacterStyle.OUTFIT_COUNT)
	app["head"] = maxi(int(app.get("head", 0)) - YOUNG_AGE_STEP, 0)
	app["hair_color"] = YOUNG_HAIR_COLOR
	app["volume"] = YOUNG_VOLUME
	return app


func set_speaker(appearance: Dictionary, tier: int) -> void:
	_app = appearance
	_tier = clampi(tier, 1, CharacterStyle.OUTFIT_COUNT)
	queue_redraw()


func set_mode(mode: String) -> void:
	if mode != _mode:
		_mode = mode
		_frame = 0
		_anim_clock = 0.0
		queue_redraw()


func get_mode() -> String:
	return _mode


func _process(delta: float) -> void:
	_time += delta
	var anim: String = ANIM_PRAISE if _mode == MODE_PRAISE else ANIM_TALK
	_anim_clock += delta
	var fps: float = CharacterPainter.anim_fps(anim)
	while fps > 0.0 and _anim_clock >= 1.0 / fps:
		_anim_clock -= 1.0 / fps
		var next: int = CharacterAnim.next_frame(anim, _frame)
		_frame = next if next >= 0 else _frame
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = 1.0 / REDRAW_HZ
		queue_redraw()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	if _mode == MODE_END:
		_draw_snow(r)
		_draw_centered(r, tr(TAPE_KEY_END), r.size.y * 0.5, r.size.y * TAPE_SIZE * 1.6)
		return
	_draw_backdrop(r)
	_draw_speaker(r)
	_draw_tape_overlay(r)


# ─── Decorado ─────────────────────────────────────────────────

func _draw_backdrop(r: Rect2) -> void:
	var pts: PackedVector2Array = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([C_SKY_TOP, C_SKY_TOP, C_SKY_BOTTOM, C_SKY_BOTTOM]))
	var bar_w: float = r.size.x * 0.05
	for i: int in BAR_COUNT:
		var h: float = r.size.y * (0.18 + 0.1 * i)
		var x: float = r.size.x * 0.6 + i * bar_w * 1.35
		draw_rect(Rect2(x, r.end.y - h, bar_w, h), C_BAR)
		draw_rect(Rect2(x, r.end.y - h, bar_w, r.size.y * 0.012), C_BAR_TOP)
	var star_c: Vector2 = Vector2(r.size.y * 0.13, r.size.y * 0.13)
	draw_colored_polygon(_star(star_c, r.size.y * STAR_R), C_STAR)
	var f: Font = UITheme.font(UITheme.FONT_BOLD)
	draw_string(f, Vector2(r.size.y * 0.24, r.size.y * 0.16), tr(BRAND_KEY).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, int(r.size.y * BRAND_SIZE), C_TEXT)
	draw_string(UITheme.font(UITheme.FONT_REGULAR), Vector2(r.size.y * 0.24, r.size.y * 0.23), tr(TAGLINE_KEY),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(r.size.y * TAGLINE_SIZE), Color(C_TEXT, 0.8))


func _star(c: Vector2, radius: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in STAR_POINTS * 2:
		var rr: float = radius if i % 2 == 0 else radius * 0.45
		out.append(c + Vector2.from_angle(-PI * 0.5 + i * PI / STAR_POINTS) * rr)
	return out


func _draw_speaker(r: Rect2) -> void:
	if _app.is_empty():
		return
	var anim: String = ANIM_PRAISE if _mode == MODE_PRAISE else ANIM_TALK
	var s: float = r.size.y * SPEAKER_SCALE
	var origin: Vector2 = Vector2(r.size.x * 0.42, r.end.y + r.size.y * SPEAKER_DROP)
	var pose: Dictionary = CharacterPainter.make_pose(anim, _frame, Vector2.DOWN, {"origin": origin, "scale": s})
	CharacterPainter.draw(self, _app, _tier, pose)


# ─── Cinta ────────────────────────────────────────────────────

func _draw_tape_overlay(r: Rect2) -> void:
	var y: float = 0.0
	while y < r.size.y:
		draw_rect(Rect2(0.0, y, r.size.x, 1.0), C_SCAN)
		y += SCAN_STEP
	var band_y: float = fmod(_time * TRACK_SPEED, 1.0) * (r.size.y * (1.0 + TRACK_H)) - r.size.y * TRACK_H
	draw_rect(Rect2(0.0, band_y, r.size.x, r.size.y * TRACK_H), C_TRACK)
	var f: Font = UITheme.font(UITheme.FONT_MONO)
	var fs: int = int(r.size.y * TAPE_SIZE)
	var blink: bool = int(_time * 2.0) % 2 == 0
	if blink:
		draw_string(f, Vector2(r.size.x - r.size.y * 0.42, r.size.y * 0.1), tr(TAPE_KEY_PLAY), HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, fs, C_PLAY)
	var secs: int = int(_time)
	var stamp: String = "%02d:%02d:%02d" % [floori(_time / 3600.0), floori(_time / 60.0) % 60, secs % 60]
	draw_string(f, Vector2(r.size.x - r.size.y * 0.42, r.end.y - r.size.y * 0.05), stamp, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, fs, C_TEXT)


func _draw_snow(r: Rect2) -> void:
	draw_rect(r, Color.BLACK)
	_rng.seed = int(_time * REDRAW_HZ)
	var cell: Vector2 = r.size / float(NOISE_CELLS)
	for y: int in NOISE_CELLS:
		for x: int in NOISE_CELLS:
			var v: float = _rng.randf()
			if v > 0.55:
				draw_rect(Rect2(Vector2(x, y) * cell, cell), Color(v, v, v, 0.55))


func _draw_centered(r: Rect2, text: String, y: float, font_size: float) -> void:
	var f: Font = UITheme.font(UITheme.FONT_BOLD)
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(font_size)).x
	draw_rect(Rect2((r.size.x - w) * 0.5 - font_size * 0.4, y - font_size, w + font_size * 0.8, font_size * 1.4),
			Color(0.0, 0.0, 0.0, 0.7))
	draw_string(f, Vector2((r.size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(font_size), C_TEXT)
