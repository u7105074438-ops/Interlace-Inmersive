# character_portrait.gd — Foto de PERSONNEL: busto frontal vectorial de un personaje (§13.4, §14.4).
# PROPIETARIO DE: nada (funciones puras de dibujo; la caché de fotos grabadas es de CharacterPainter).
# ESCUCHA: nada.
class_name CharacterPortrait
extends RefCounted

## El busto se graba (record) en un espacio de diseño de DESIGN × DESIGN unidades y se reproduce
## escalado y centrado en `rect` (design_transform). Fondo con la paleta de la banda del escalón
## (art_bands.json), dibujado aparte en cada foto: el rango se lee hasta en la foto.
## Las coordenadas de la cara son relativas a HEAD_C (cuello corto: la barbilla casi toca el cuello).

const O := CharacterStyle.OUTLINE
const DESIGN := 100.0
const LINE := 1.6
const HEAD_C := Vector2(50, 46)
const HEAD_R := Vector2(17.5, 20.5)
const EYE_Y := HEAD_C.y + 2.0
const EYE_DX := 7.4
const BROW_Y := HEAD_C.y - 5.5
const MOUTH_Y := HEAD_C.y + 14.0
const NECK_TOP := HEAD_C.y + 12.0
const NECK_HALF := 7.5
const SHOULDER_Y := 76.0
const BG_FALLBACK := Color("#b5b8a8")
## Encuadre: el busto se amplía respecto al centro inferior para que la cara llene la foto.
const ZOOM := 1.12
const PIVOT := Vector2(50, 100)
const MAX_HALF := 41.0
const COAT_EXTRA := 6.0


## Transformación del espacio de diseño (100 × 100) a `rect`: busto centrado abajo y ampliado.
static func design_transform(rect: Rect2) -> Transform2D:
	var s: float = minf(rect.size.x, rect.size.y) / DESIGN
	var origin: Vector2 = rect.position + Vector2((rect.size.x - DESIGN * s) * 0.5, rect.size.y - DESIGN * s)
	return Transform2D(0.0, Vector2(s, s) * ZOOM, 0.0, origin + PIVOT * s * (1.0 - ZOOM))


## Graba el busto frontal en el espacio de diseño.
static func record(canvas: CharacterCanvas, appearance: Dictionary) -> void:
	var tier: int = clampi(int(appearance.get("tier", 1)), 1, CharacterStyle.OUTFIT_COUNT)
	var rig: CharacterRig = CharacterRig.build(appearance, tier, {"anim": "idle", "frame": 0})
	var style: Dictionary = CharacterHead.style_of(rig)
	var head_r: Vector2 = HEAD_R * Vector2(rig.head_radii.x / rig.head_radii.y, 1.0)
	_draw_back_hair(canvas, rig, style, head_r)
	_draw_body(canvas, rig)
	_draw_head(canvas, rig, head_r)
	_draw_face(canvas, rig, head_r)
	_draw_front_hair(canvas, rig, style, head_r)
	_draw_head_wear(canvas, rig, head_r)
	_draw_held(canvas, rig)


## Fondo de la foto (banda del escalón): se dibuja directamente en cada foto.
static func draw_background(canvas: CanvasItem, rect: Rect2, tier: int) -> void:
	var band: String = CharacterStyle.PORTRAIT_BANDS[tier]
	var wall: Color = CharacterStyle.band_color(band, "wall", BG_FALLBACK)
	var light: Color = CharacterStyle.band_color(band, "light", wall.lightened(0.3))
	var accent: Color = CharacterStyle.band_color(band, "accent", wall.darkened(0.3))
	canvas.draw_rect(rect, wall)
	var glow: PackedVector2Array = CharacterStyle.ellipse(rect.get_center() + Vector2(0, -rect.size.y * 0.08),
			rect.size * Vector2(0.42, 0.42), 28)
	canvas.draw_colored_polygon(glow, Color(light, 0.55))
	canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * 0.9), Vector2(rect.size.x, rect.size.y * 0.1)),
			Color(accent, 0.35))


## Punto de la cara relativo al centro de la cabeza.
static func _h(x: float, dy: float) -> Vector2:
	return Vector2(x, HEAD_C.y + dy)


# ─── Cuerpo ────────────────────────────────────────────────────

static func _draw_body(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var half: float = (24.0 + float(rig.tier) * 2.3 + rig.pad * 3.0) * rig.width_scale
	half = minf(half, MAX_HALF - (COAT_EXTRA if rig.outfit == "lux_coat" else 0.0))
	var skin: Color = rig.colors["skin"]
	var neck_h: float = SHOULDER_Y + 4.0 - NECK_TOP
	canvas.draw_rect(Rect2(Vector2(50 - NECK_HALF - 1.5, NECK_TOP), Vector2(NECK_HALF * 2 + 3, neck_h)), O)
	canvas.draw_rect(Rect2(Vector2(50 - NECK_HALF, NECK_TOP), Vector2(NECK_HALF * 2, neck_h)), skin)
	canvas.draw_rect(Rect2(Vector2(50 - NECK_HALF, NECK_TOP + 6), Vector2(NECK_HALF * 2, 3)), skin.darkened(0.15))
	var corner: float = 14.0 - rig.pad * 9.0
	var torso: PackedVector2Array = PackedVector2Array([Vector2(50 - half, 100)])
	torso.append_array(CharacterStyle.arc(Vector2(50 - half + corner, SHOULDER_Y + corner),
			Vector2(corner, corner), PI, PI * 1.5, 5))
	torso.append_array(CharacterStyle.arc(Vector2(50 + half - corner, SHOULDER_Y + corner),
			Vector2(corner, corner), PI * 1.5, TAU, 5))
	torso.append(Vector2(50 + half, 100))
	CharacterStyle.fill(canvas, torso, rig.colors["top"], O, LINE)
	if rig.outfit == "lux_coat":
		_coat(canvas, rig, half)
	_outfit(canvas, rig, half)
	_torso_wear(canvas, rig)


static func _outfit(canvas: CharacterCanvas, rig: CharacterRig, half: float) -> void:
	var top: Color = rig.colors["top"]
	match rig.outfit:
		"hoodie":
			CharacterStyle.fill(canvas, CharacterStyle.arc(Vector2(50, 76), Vector2(14, 6), 0.0, PI, 10),
					top.darkened(0.15), O, 1.2)
			canvas.draw_line(Vector2(46, 79), Vector2(45, 92), Color.WHITE, 1.4, true)
			canvas.draw_line(Vector2(54, 79), Vector2(55, 92), Color.WHITE, 1.4, true)
		"polo":
			_collar(canvas, top.lightened(0.2))
			canvas.draw_line(Vector2(50, 80), Vector2(50, 92), top.darkened(0.3), 1.2)
		"shirt_tie":
			_collar(canvas, CharacterStyle.WHITE_SHIRT)
			_tie(canvas, rig, 100.0)
		"blazer", "suit", "suit_vest", "lux_suit", "lux_coat":
			_suit(canvas, rig)
		_:
			_uniform(canvas, rig, half)


static func _collar(canvas: CharacterCanvas, color: Color) -> void:
	CharacterStyle.fill(canvas, PackedVector2Array([Vector2(42, 75), Vector2(50, 79), Vector2(45, 85)]),
			color, O, 1.2)
	CharacterStyle.fill(canvas, PackedVector2Array([Vector2(58, 75), Vector2(50, 79), Vector2(55, 85)]),
			color, O, 1.2)


static func _tie(canvas: CharacterCanvas, rig: CharacterRig, bottom: float) -> void:
	var tie: Color = rig.colors["tie"]
	CharacterStyle.fill(canvas, PackedVector2Array([Vector2(47.5, 79), Vector2(52.5, 79), Vector2(51.5, 83),
			Vector2(48.5, 83)]), tie, O, 1.2)
	CharacterStyle.fill(canvas, PackedVector2Array([Vector2(48.5, 83), Vector2(51.5, 83), Vector2(54, bottom - 8),
			Vector2(50, bottom), Vector2(46, bottom - 8)]), tie, O, 1.2)
	if rig.outfit.begins_with("lux"):
		canvas.draw_line(Vector2(46.5, 91), Vector2(53.5, 91), CharacterStyle.GOLD, 1.8)


static func _suit(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var top: Color = rig.colors["top"]
	CharacterStyle.fill(canvas, PackedVector2Array([Vector2(41, 75), Vector2(59, 75), Vector2(50, 99.5)]),
			rig.colors["shirt"], O, 1.2)
	if rig.outfit == "suit_vest":
		CharacterStyle.fill(canvas, PackedVector2Array([Vector2(43, 84), Vector2(57, 84), Vector2(50, 99.5)]),
				top.darkened(0.25), O, 1.2)
	_collar(canvas, rig.colors["shirt"])
	_tie(canvas, rig, 100.0)
	var lapel: Color = top.darkened(0.35 if rig.outfit.begins_with("lux") else 0.2)
	CharacterStyle.fill(canvas, PackedVector2Array([Vector2(41, 75), Vector2(35, 79), Vector2(40, 88),
			Vector2(37, 90), Vector2(50, 100)]), lapel, O, 1.2)
	CharacterStyle.fill(canvas, PackedVector2Array([Vector2(59, 75), Vector2(65, 79), Vector2(60, 88),
			Vector2(63, 90), Vector2(50, 100)]), lapel, O, 1.2)
	if rig.outfit != "blazer":
		var sq: Color = CharacterStyle.GOLD if rig.outfit.begins_with("lux") else CharacterStyle.WHITE_SHIRT
		CharacterStyle.fill(canvas, PackedVector2Array([Vector2(66, 92), Vector2(68, 88.5), Vector2(70, 90),
				Vector2(72, 88), Vector2(73, 92)]), sq, O, 1.0)


## Abrigo de lujo: paño oscuro, forro de seda en el borde y solapa de terciopelo con muesca.
static func _coat(canvas: CharacterCanvas, rig: CharacterRig, half: float) -> void:
	var coat: Color = rig.colors["coat"]
	for s: float in [-1.0, 1.0]:
		CharacterStyle.fill(canvas, PackedVector2Array([Vector2(50 + s * 16, 74), Vector2(50 + s * (half - 4), 75),
				Vector2(50 + s * (half + COAT_EXTRA - 1.0), 84), Vector2(50 + s * (half + COAT_EXTRA), 100),
				Vector2(50 + s * 20, 100)]), coat, O, LINE)
		canvas.draw_line(Vector2(50 + s * 17.2, 77), Vector2(50 + s * 21.2, 100), CharacterStyle.LUX_COAT_LINING, 1.8, true)
		CharacterStyle.fill(canvas, PackedVector2Array([Vector2(50 + s * 14.5, 72.5), Vector2(50 + s * (half - 3), 74.5),
				Vector2(50 + s * (half - 7), 82), Vector2(50 + s * 25, 86), Vector2(50 + s * 27.5, 90.5),
				Vector2(50 + s * 20.5, 94)]), CharacterStyle.LUX_COAT_COLLAR, O, 1.3)


static func _uniform(canvas: CharacterCanvas, rig: CharacterRig, half: float) -> void:
	var trim: Color = rig.colors["trim"]
	var top: Color = rig.colors["top"]
	match rig.outfit:
		"security":
			_collar(canvas, top.darkened(0.25))
			CharacterStyle.fill(canvas, PackedVector2Array([Vector2(33, 86), Vector2(39, 86), Vector2(39, 92),
					Vector2(36, 95), Vector2(33, 92)]), trim, O, 1.1)
			canvas.draw_line(Vector2(50 - half + 6, 79), Vector2(40, 77), top.darkened(0.35), 3.0)
			canvas.draw_line(Vector2(50 + half - 6, 79), Vector2(60, 77), top.darkened(0.35), 3.0)
		"cleaning":
			_collar(canvas, trim)
			canvas.draw_rect(Rect2(Vector2(58, 86), Vector2(9, 8)), top.darkened(0.15))
		"maintenance":
			canvas.draw_rect(Rect2(Vector2(50 - half + 2, 88), Vector2(half * 2 - 4, 4)), trim)
			canvas.draw_line(Vector2(50, 78), Vector2(50, 100), top.darkened(0.3), 1.4)
		"factory":
			canvas.draw_rect(Rect2(Vector2(38, 76), Vector2(5, 26)), trim)
			canvas.draw_rect(Rect2(Vector2(57, 76), Vector2(5, 26)), trim)


static func _torso_wear(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var gold: Color = CharacterStyle.GOLD
	match rig.accessory:
		"lanyard":
			_lanyard(canvas, CharacterProps.LANYARD_COLORS[int(rig.appearance.get("palette", 0)) % 3])
		"pen_pocket":
			for i: int in 3:
				canvas.draw_line(Vector2(64 + i * 2.2, 86), Vector2(64 + i * 2.2, 82), [Color("#2f6fd0"),
						CharacterProps.RED_PEN, O][i], 1.6)
		"scarf":
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(Vector2(50, 77), Vector2(15, 5), 16),
					(CharacterStyle.PALETTES[(int(rig.appearance.get("palette", 0)) + 5) % 12]["tie"] as Color))
	match rig.unique:
		"visitor_lanyard":
			_lanyard(canvas, CharacterProps.VISITOR)
		"employee_of_month_pin", "gold_lapel_pin":
			_star(canvas, Vector2(37, 84), 4.2, gold)
		"thirty_year_pin":
			CharacterStyle.circle(canvas, Vector2(37, 84), 3.2, gold, O, 1.1)
		"statement_necklace":
			for i: int in 7:
				var a: float = PI * (0.15 + 0.7 * float(i) / 6.0)
				var p: Vector2 = Vector2(50, 70) + Vector2(cos(a) * 13.0, sin(a) * 10.0)
				CharacterStyle.circle(canvas, p, 2.2, gold if i % 2 == 0 else Color("#c0392b"), O, 1.0)
		"stopwatch":
			canvas.draw_polyline([Vector2(44, 74), Vector2(50, 88), Vector2(56, 74)], O, 1.0, true)
			CharacterStyle.circle(canvas, Vector2(50, 90), 3.6, CharacterProps.METAL, O, 1.1)
		"pocket_ledger":
			canvas.draw_rect(Rect2(Vector2(62, 82), Vector2(6, 8)), Color("#1d1d1f"))


static func _lanyard(canvas: CharacterCanvas, color: Color) -> void:
	canvas.draw_line(Vector2(44, 75), Vector2(48, 92), color, 2.0, true)
	canvas.draw_line(Vector2(56, 75), Vector2(52, 92), color, 2.0, true)
	CharacterStyle.fill(canvas, PackedVector2Array([Vector2(45, 92), Vector2(55, 92), Vector2(55, 100),
			Vector2(45, 100)]), Color.WHITE, O, 1.1)
	canvas.draw_rect(Rect2(Vector2(45, 92), Vector2(10, 3)), color)


static func _star(canvas: CharacterCanvas, c: Vector2, r: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var a: float = -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	CharacterStyle.fill(canvas, pts, color, O, 1.0)


# ─── Cabeza ────────────────────────────────────────────────────

static func _head_points(rig: CharacterRig, head_r: Vector2) -> PackedVector2Array:
	return CharacterStyle.superellipse(HEAD_C, head_r, rig.head_exp, 32)


static func _draw_head(canvas: CharacterCanvas, rig: CharacterRig, head_r: Vector2) -> void:
	var skin: Color = rig.colors["skin"]
	for s: float in [-1.0, 1.0]:
		CharacterStyle.circle(canvas, HEAD_C + Vector2(s * head_r.x * 0.98, 3), 4.2, skin, O, LINE)
		canvas.draw_circle(HEAD_C + Vector2(s * head_r.x * 0.98, 3), 2.0, skin.darkened(0.15))
	CharacterStyle.fill(canvas, _head_points(rig, head_r), skin, O, LINE)


static func _draw_face(canvas: CharacterCanvas, rig: CharacterRig, head_r: Vector2) -> void:
	var brow: Color = (rig.colors["hair"] as Color).darkened(0.35)
	for s: float in [-1.0, 1.0]:
		var e: Vector2 = Vector2(50 + s * EYE_DX, EYE_Y)
		CharacterStyle.fill(canvas, CharacterStyle.ellipse(e, Vector2(3.4, 2.5), 14), Color.WHITE, O, 1.1)
		canvas.draw_circle(e + Vector2(0, 0.2), 1.8, CharacterStyle.EYE)
		canvas.draw_circle(e + Vector2(-0.6, -0.5), 0.6, Color.WHITE)
		canvas.draw_line(Vector2(50 + s * (EYE_DX - 3.5), BROW_Y + 0.6), Vector2(50 + s * (EYE_DX + 3.2), BROW_Y - 0.4),
				brow, 2.0, true)
	var nose: Color = (rig.colors["skin"] as Color).darkened(0.22)
	canvas.draw_polyline([_h(50.5, 4.0), _h(52, 9.0), _h(49.5, 9.8)], nose, 1.4, true)
	canvas.draw_polyline([Vector2(46.5, MOUTH_Y - 0.5), Vector2(50, MOUTH_Y + 1.0), Vector2(53.5, MOUTH_Y - 0.5)],
			CharacterStyle.MOUTH, 1.5, true)
	if rig.age >= 2:
		var w: Color = CharacterHead.WRINKLE
		canvas.draw_line(_h(44, -11.0), _h(56, -11.0), w, 1.0, true)
		canvas.draw_line(_h(43.5, 9.0), _h(45, 14.0), w, 1.0, true)
		canvas.draw_line(_h(56.5, 9.0), _h(55, 14.0), w, 1.0, true)
	if rig.age >= 3:
		canvas.draw_line(_h(45, -13.5), _h(55, -13.5), CharacterHead.WRINKLE, 1.0, true)
	_facial_hair(canvas, rig, head_r)


static func _facial_hair(canvas: CharacterCanvas, rig: CharacterRig, head_r: Vector2) -> void:
	var hair: Color = rig.colors["hair"]
	match CharacterHead.facial_of(rig):
		"stubble":
			var s: PackedVector2Array = CharacterStyle.ellipse(_h(50, 15.0), Vector2(head_r.x * 0.8, 8), 20)
			canvas.draw_colored_polygon(CharacterStyle.clip(s, _head_points(rig, head_r)), Color(hair, 0.3))
		"moustache":
			CharacterStyle.fill(canvas, PackedVector2Array([_h(44.5, 12.5), _h(50, 10.0), _h(55.5, 12.5),
					_h(53, 13.5), _h(50, 12.4), _h(47, 13.5)]), hair, O, 1.0)
		"goatee":
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(_h(50, 18.0), Vector2(3.5, 3.0), 12), hair, O, 1.0)
		"full_beard":
			var b: PackedVector2Array = CharacterStyle.ellipse(_h(50, 13.0), Vector2(head_r.x * 1.02, 11), 24)
			var jaw: PackedVector2Array = CharacterStyle.superellipse(HEAD_C + Vector2(0, 1.5), head_r * 1.04,
					rig.head_exp, 32)
			var beard: PackedVector2Array = CharacterStyle.clip(b, jaw)
			CharacterStyle.fill(canvas, beard, hair, O, 1.2)
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(Vector2(50, MOUTH_Y), Vector2(3.4, 1.4), 12),
					CharacterStyle.MOUTH, O, 0.8)


# ─── Pelo frontal ──────────────────────────────────────────────

static func _draw_back_hair(canvas: CharacterCanvas, rig: CharacterRig, style: Dictionary, head_r: Vector2) -> void:
	var back: float = float(style["back"])
	var vol: float = float(style["vol"])
	var hair: Color = rig.colors["hair"]
	if back < 0.05 and float(style["sides"]) < 0.9 and vol < 0.2:
		return
	var w: float = head_r.x * float(style.get("back_w", 1.12 + vol * 0.9))
	var top: float = HEAD_C.y - head_r.y * (1.0 + vol * 0.6)
	var bottom: float = HEAD_C.y + head_r.y * (0.35 + back * 1.1)
	var shape: PackedVector2Array = CharacterStyle.arc(Vector2(50, top + w), Vector2(w, w), PI, TAU, 14)
	shape.append(Vector2(50 + w + back * 3.0, bottom))
	shape.append(Vector2(50 - w - back * 3.0, bottom))
	CharacterStyle.fill(canvas, shape, hair.darkened(0.12), O, LINE)


static func _draw_front_hair(canvas: CharacterCanvas, rig: CharacterRig, style: Dictionary, head_r: Vector2) -> void:
	if not bool(style["cap"]):
		return
	var hair: Color = rig.colors["hair"]
	var vol: float = float(style["vol"])
	var mass_c: Vector2 = HEAD_C + Vector2(0, -head_r.y * vol * 0.5)
	var mass: PackedVector2Array = CharacterStyle.superellipse(mass_c, head_r * (1.0 + vol) + Vector2(0.8, 0.8),
			rig.head_exp, 32)
	var cap: PackedVector2Array = CharacterStyle.clip(mass, _hair_cutter(style, head_r))
	if bool(style.get("bumpy", false)):
		for p: Vector2 in CharacterStyle.arc(mass_c, head_r * (1.0 + vol) * 0.95, PI * 0.95, PI * 2.05, 9):
			CharacterStyle.circle(canvas, p, head_r.x * 0.28, hair, O, LINE)
	CharacterStyle.fill(canvas, cap, hair, O, LINE)
	_front_extras(canvas, rig, style, head_r)


## Polígono por encima de la línea del pelo (con laterales hasta `sides`, raya y entradas).
static func _hair_cutter(style: Dictionary, head_r: Vector2) -> PackedVector2Array:
	var hl_y: float = HEAD_C.y + head_r.y * (0.08 - float(style["hl"]) * 0.85)
	var part: float = float(style["part"])
	var receding: bool = str(style.get("extra", "")) == "receding"
	var side_bottom: float = HEAD_C.y + head_r.y * (float(style["sides"]) * 0.95 - 0.25)
	var inner: float = head_r.x * 0.8
	var pts: PackedVector2Array = [Vector2(50 - head_r.x * 3, 0), Vector2(50 + head_r.x * 3, 0)]
	var line: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var t: float = lerpf(1.0, -1.0, float(i) / 12.0)
		var y: float = hl_y + part * 0.2 * head_r.y * t + 0.14 * head_r.y * t * t
		if receding:
			y -= 0.22 * head_r.y * absf(t) - 0.08 * head_r.y
		line.append(Vector2(50 + t * inner, y))
	var right_y: float = maxf(side_bottom, line[0].y)
	var left_y: float = maxf(side_bottom, line[line.size() - 1].y)
	pts.append(Vector2(50 + head_r.x * 3, right_y))
	pts.append(Vector2(50 + inner, right_y))
	pts.append_array(line)
	pts.append(Vector2(50 - inner, left_y))
	pts.append(Vector2(50 - head_r.x * 3, left_y))
	return pts


static func _front_extras(canvas: CharacterCanvas, rig: CharacterRig, style: Dictionary, head_r: Vector2) -> void:
	var hair: Color = rig.colors["hair"]
	var top: Vector2 = HEAD_C + Vector2(0, -head_r.y)
	match str(style.get("extra", "")):
		"bun":
			CharacterStyle.circle(canvas, top + Vector2(0, -4), 7.0, hair, O, LINE)
		"quiff":
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(top + Vector2(3, 1), Vector2(10, 5.5), 16),
					hair, O, LINE)
		"shine", "comb_over":
			canvas.draw_polyline(CharacterStyle.arc(HEAD_C, head_r * 0.8, PI * 1.25, PI * 1.55, 6),
					hair.lightened(0.4), 2.0, true)
		"bouffant":
			canvas.draw_polyline(CharacterStyle.arc(HEAD_C + Vector2(0, -4), head_r * 0.95, PI * 1.2, PI * 1.6, 6),
					hair.lightened(0.3), 2.0, true)
		"braids":
			for s: float in [-1.0, 1.0]:
				var a: Vector2 = HEAD_C + Vector2(s * head_r.x * 0.95, 6)
				CharacterStyle.limb(canvas, PackedVector2Array([a, a + Vector2(s * 3, 30)]), 5.0, hair, O, LINE)
		"swept":
			_swept_strands(canvas, style, head_r, hair)


## Melena plateada peinada hacia atrás: mechones curvos de la línea del pelo a la coronilla.
static func _swept_strands(canvas: CharacterCanvas, style: Dictionary, head_r: Vector2, hair: Color) -> void:
	var hl_y: float = HEAD_C.y + head_r.y * (0.08 - float(style["hl"]) * 0.85)
	var crown_y: float = HEAD_C.y - head_r.y * (1.0 + float(style["vol"]))
	for i: int in 5:
		var t: float = float(i) - 2.0
		var a: Vector2 = Vector2(50 + t * 5.5, hl_y + 1.0 - absf(t) * 0.6)
		var ctrl: Vector2 = Vector2(50 + t * 8.5, hl_y - 8.0)
		var b: Vector2 = Vector2(50 + t * 6.0, crown_y + 3.0 + absf(t) * 1.5)
		var pts: PackedVector2Array = PackedVector2Array()
		for k: int in 7:
			var u: float = float(k) / 6.0
			pts.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
		canvas.draw_polyline(pts, hair.darkened(0.3) if i % 2 == 0 else hair.lightened(0.35), 1.6, true)


static func _draw_head_wear(canvas: CharacterCanvas, rig: CharacterRig, head_r: Vector2) -> void:
	var items: Array[String] = CharacterProps.head_wear_of(rig)
	var cap: Color = rig.colors["cap"]
	if cap.a > 0.0:
		CharacterStyle.fill(canvas, CharacterStyle.arc(HEAD_C + Vector2(0, -6),
				Vector2(head_r.x * 1.08, head_r.y * 0.9),
				PI, TAU, 16), cap, O, LINE)
		CharacterStyle.fill(canvas, CharacterStyle.ellipse(HEAD_C + Vector2(0, -5), Vector2(head_r.x * 1.15, 3.2), 16),
				cap.darkened(0.3), O, LINE)
	for item: String in items:
		match item:
			"glasses", "glasses_chain", "designer_sunglasses":
				_glasses(canvas, item)
			"headphones", "noise_cancelling_headphones":
				_headphones(canvas, head_r, item == "noise_cancelling_headphones")
			"hard_hat":
				CharacterStyle.fill(canvas, CharacterStyle.arc(HEAD_C + Vector2(0, -8),
						Vector2(head_r.x * 1.12, head_r.y * 0.95),
						PI, TAU, 16), CharacterProps.HARD_HAT, O, LINE)
				CharacterStyle.fill(canvas, CharacterStyle.ellipse(HEAD_C + Vector2(0, -8),
						Vector2(head_r.x * 1.35, 3.0), 16),
						CharacterProps.HARD_HAT.darkened(0.12), O, LINE)


static func _glasses(canvas: CharacterCanvas, item: String) -> void:
	var dark: bool = item == "designer_sunglasses"
	var rim: Color = CharacterStyle.GOLD if dark else O
	for s: float in [-1.0, 1.0]:
		var e: Vector2 = Vector2(50 + s * EYE_DX, EYE_Y)
		if dark:
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(e, Vector2(5.2, 4.2), 16), Color("#15151a"), rim, 1.4)
		else:
			canvas.draw_arc(e, 4.8, 0.0, TAU, 18, rim, 1.4, true)
	canvas.draw_line(Vector2(50 - EYE_DX + 5, EYE_Y - 0.5), Vector2(50 + EYE_DX - 5, EYE_Y - 0.5), rim, 1.3)
	if item == "glasses_chain":
		canvas.draw_polyline([Vector2(50 - EYE_DX - 5, EYE_Y), _h(31, 21.0), Vector2(36, 78)],
				CharacterStyle.GOLD, 1.0, true)
		canvas.draw_polyline([Vector2(50 + EYE_DX + 5, EYE_Y), _h(69, 21.0), Vector2(64, 78)],
				CharacterStyle.GOLD, 1.0, true)


static func _headphones(canvas: CharacterCanvas, head_r: Vector2, big: bool) -> void:
	canvas.draw_arc(HEAD_C + Vector2(0, -2), head_r.x * 1.12, PI * 1.02, PI * 1.98, 20, O, 5.0, true)
	canvas.draw_arc(HEAD_C + Vector2(0, -2), head_r.x * 1.12, PI * 1.02, PI * 1.98, 20, Color("#2a2d34"), 3.0, true)
	var cup: Color = Color("#e24b4b") if big else Color("#3a3f4a")
	for s: float in [-1.0, 1.0]:
		var c: Vector2 = HEAD_C + Vector2(s * head_r.x * 1.08, 3)
		CharacterStyle.fill(canvas, CharacterStyle.ellipse(c, Vector2(4.5 if big else 3.6, 7.0 if big else 5.5), 14),
				cup, O, LINE)


## Objetos que asoman en la foto (taza enorme, portátil abrazado, bolígrafo rojo tras la oreja...).
static func _draw_held(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	match rig.unique:
		"oversized_mug":
			CharacterStyle.fill(canvas, PackedVector2Array([Vector2(66, 82), Vector2(82, 82), Vector2(81, 99.5),
					Vector2(67, 99.5)]), CharacterProps.BIG_MUG, O, LINE)
			canvas.draw_arc(Vector2(83, 91), 5.0, -PI * 0.5, PI * 0.5, 10, O, 2.6, true)
		"clutched_laptop", "colour_coded_planner":
			var col: Color = CharacterProps.METAL if rig.unique == "clutched_laptop" else CharacterProps.PLANNER
			CharacterStyle.fill(canvas, PackedVector2Array([Vector2(33, 88), Vector2(67, 86), Vector2(69, 100),
					Vector2(31, 100)]), col, O, LINE)
		"red_pen":
			canvas.draw_line(_h(66, -11.0), _h(74, 3.0), O, 3.6, true)
			canvas.draw_line(_h(66, -11.0), _h(74, 3.0), CharacterProps.RED_PEN, 2.2, true)
		"twin_phones":
			for s: float in [-1.0, 1.0]:
				CharacterStyle.fill(canvas, PackedVector2Array([_h(50 + s * 18, -7.0), _h(50 + s * 25, -8.0),
						_h(50 + s * 27, 9.0), _h(50 + s * 20, 10.0)]), CharacterProps.DEVICE, O, LINE)
				canvas.draw_colored_polygon(PackedVector2Array([_h(50 + s * 19.5, -5.0), _h(50 + s * 24, -5.8),
						_h(50 + s * 25.5, 6.5), _h(50 + s * 21, 7.2)]), CharacterProps.SCREEN)
		"heavy_flashlight":
			CharacterStyle.limb(canvas, PackedVector2Array([Vector2(70, 100), Vector2(82, 72)]), 6.0,
					Color("#26282c"), O, LINE)
		"paperback_novel", "steno_pad":
			CharacterStyle.fill(canvas, PackedVector2Array([Vector2(62, 90), Vector2(78, 88), Vector2(79, 100),
					Vector2(63, 100)]), CharacterProps.PAPER, O, LINE)
