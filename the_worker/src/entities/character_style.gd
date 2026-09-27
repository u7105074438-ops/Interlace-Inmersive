# character_style.gd — Tablas de arte de personajes (§14.4, §14.5) y primitivas vectoriales con contorno.
# PROPIETARIO DE: nada (constantes de arte de solo lectura y funciones puras de dibujo).
# ESCUCHA: nada.
class_name CharacterStyle
extends RefCounted

## Todas las medidas en píxeles a escala 1 (1 celda = 48 px). Son constantes de arte (como los
## márgenes de UI), no parámetros de juego. Las usan CharacterPainter, CharacterRig,
## CharacterProps y CharacterPortrait.

const OUTLINE := Color("#1d1a22")
const OUTLINE_WIDTH := 1.6
const SHADOW := Color(0.05, 0.04, 0.08, 0.28)
const GOLD := Color("#d8b04a")
const GOLD_DARK := Color("#9c7a24")
const WHITE_SHIRT := Color("#f4f4f1")
const EYE := Color("#231f26")
const MOUTH := Color("#6b2b2b")
const BLUSH := Color(0.85, 0.35, 0.35, 0.22)
const ELLIPSE_SEGMENTS := 22
## Proyección cenital 3/4: el plano del suelo se ve comprimido; lo vertical, entero.
const GROUND_Y := 0.5
const LATERAL_Y := 0.35

## §14.4 capas y número de variantes.
const BUILD_COUNT := 6
const HEAD_COUNT := 20
const HAIR_COUNT := 25
const SKIN_COUNT := 8
const OUTFIT_COUNT := 8
const ACCESSORY_COUNT := 15
const PALETTE_COUNT := 12
## Combinaciones reservadas a los nominados (§14.4): cabezas y peinados finales.
const RESERVED_HEADS := 2
const RESERVED_HAIRS := 3

const SKIN_TONES: Array[Color] = [
	Color("#f7dcc8"), Color("#efc3a2"), Color("#e2ab86"), Color("#cc9068"),
	Color("#ab714c"), Color("#8b5738"), Color("#6c4129"), Color("#4b2d1d"),
]
const HAIR_COLORS: Array[Color] = [
	Color("#231c19"), Color("#3f2c21"), Color("#6e4b2f"), Color("#8f3d1f"),
	Color("#dcb660"), Color("#c96d2c"), Color("#9d9a95"), Color("#e8e4dc"),
]
const HAIR_GREY := 6
const HAIR_WHITE := 7

## [ancho, alto] por constitución.
const BUILDS: Array[Vector2] = [
	Vector2(0.9, 0.93), Vector2(1.1, 0.94), Vector2(0.93, 1.0),
	Vector2(1.02, 1.0), Vector2(0.94, 1.07), Vector2(1.13, 1.05),
]
## Formas de cabeza: [radio x, radio y, exponente de superelipse]. Cabeza = forma + 5 × edad.
const HEAD_SHAPES: Array[Vector3] = [
	Vector3(1.0, 1.0, 2.0), Vector3(0.93, 1.06, 2.0), Vector3(1.0, 0.98, 3.0),
	Vector3(0.89, 1.1, 2.4), Vector3(1.07, 0.95, 2.3),
]
const HEAD_AGES := 4

## Silueta por escalón (§14.5). shoulder/hip = semianchos; hunch = encorvamiento (negativo =
## pecho fuera); loose = holgura de la ropa; pad = hombreras angulosas; stride/swing = zancada
## y balanceo de brazos; leg = altura de cadera.
const TIER_SHAPES: Array[Dictionary] = [
	{},
	{"shoulder": 12.5, "hip": 13.5, "torso": 20.0, "hunch": 5.0, "loose": 0.2, "pad": 0.0,
		"stride": 0.7, "swing": 0.55, "leg": 14.5, "head": 11.8},
	{"shoulder": 13.0, "hip": 13.0, "torso": 20.5, "hunch": 3.8, "loose": 0.15, "pad": 0.0,
		"stride": 0.78, "swing": 0.7, "leg": 15.0, "head": 11.6},
	{"shoulder": 14.0, "hip": 11.0, "torso": 22.0, "hunch": 0.6, "loose": 0.0, "pad": 0.0,
		"stride": 1.0, "swing": 1.0, "leg": 16.0, "head": 11.4},
	{"shoulder": 16.2, "hip": 11.6, "torso": 22.5, "hunch": 0.0, "loose": 0.0, "pad": 0.45,
		"stride": 1.0, "swing": 0.8, "leg": 16.5, "head": 11.4},
	{"shoulder": 17.8, "hip": 12.0, "torso": 23.0, "hunch": -0.6, "loose": 0.0, "pad": 1.0,
		"stride": 1.3, "swing": 1.05, "leg": 17.0, "head": 11.4},
	{"shoulder": 18.8, "hip": 12.6, "torso": 23.5, "hunch": -0.8, "loose": 0.0, "pad": 1.0,
		"stride": 1.35, "swing": 1.05, "leg": 17.0, "head": 11.5},
	{"shoulder": 20.5, "hip": 16.0, "torso": 24.5, "hunch": -1.2, "loose": 0.06, "pad": 0.8,
		"stride": 0.95, "swing": 0.35, "leg": 17.0, "head": 11.8},
	{"shoulder": 22.0, "hip": 17.5, "torso": 25.5, "hunch": -1.4, "loose": 0.08, "pad": 0.8,
		"stride": 0.9, "swing": 0.25, "leg": 17.0, "head": 12.0},
]
## Vestuario por escalón (§14.4 capa "vestuario por rango").
const TIER_OUTFITS: Array[String] = [
	"", "hoodie", "polo", "shirt_tie", "blazer", "suit", "suit_vest", "lux_suit", "lux_coat",
]
## Objeto transportado por escalón (§14.5): 1–2 cajas o papeles, 3 carpeta, 4+ manos libres.
const TIER_CARRY: Array[Array] = [
	[], ["box", "papers", ""], ["papers", "box", ""], ["folder"], [""], [""], [""], [""], [""],
]

## Paletas de vestuario (12): variación individual dentro del uniforme de clase.
const PALETTES: Array[Dictionary] = [
	{"casual": Color("#d8a33e"), "shirt": Color("#eef1f4"), "tie": Color("#8a2433"),
		"blazer": Color("#6d7482"), "suit": Color("#2c313c"), "trousers": Color("#353a45"),
		"coat": Color("#b88f5a")},
	{"casual": Color("#3f8390"), "shirt": Color("#dbe8f3"), "tie": Color("#213f78"),
		"blazer": Color("#46607f"), "suit": Color("#1f2b46"), "trousers": Color("#2a3244"),
		"coat": Color("#1d1d22")},
	{"casual": Color("#9a3f3f"), "shirt": Color("#f3eee4"), "tie": Color("#2f6040"),
		"blazer": Color("#7b6a58"), "suit": Color("#39393e"), "trousers": Color("#303036"),
		"coat": Color("#c49a62")},
	{"casual": Color("#5c6e94"), "shirt": Color("#e5edf7"), "tie": Color("#a07c1c"),
		"blazer": Color("#58647a"), "suit": Color("#4a5059"), "trousers": Color("#3b4048"),
		"coat": Color("#2a2a30")},
	{"casual": Color("#6b8f40"), "shirt": Color("#f5f4ee"), "tie": Color("#62307a"),
		"blazer": Color("#8a8070"), "suit": Color("#2f2a28"), "trousers": Color("#2b2624"),
		"coat": Color("#a88455")},
	{"casual": Color("#a0689f"), "shirt": Color("#e8f0e6"), "tie": Color("#b8432f"),
		"blazer": Color("#55555c"), "suit": Color("#1c1d23"), "trousers": Color("#1f2026"),
		"coat": Color("#23232a")},
	{"casual": Color("#cf7a4c"), "shirt": Color("#f2e6ee"), "tie": Color("#22436a"),
		"blazer": Color("#8c6b4f"), "suit": Color("#56473a"), "trousers": Color("#40362d"),
		"coat": Color("#c9a26c")},
	{"casual": Color("#56616c"), "shirt": Color("#fbfbfb"), "tie": Color("#a83c6e"),
		"blazer": Color("#3f4f5e"), "suit": Color("#263a48"), "trousers": Color("#27313b"),
		"coat": Color("#1f1f24")},
	{"casual": Color("#b3a843"), "shirt": Color("#e3eef4"), "tie": Color("#3a3a3f"),
		"blazer": Color("#6b7788"), "suit": Color("#3e4b5e"), "trousers": Color("#333d4c"),
		"coat": Color("#b28a58")},
	{"casual": Color("#2f4c78"), "shirt": Color("#f7f1e6"), "tie": Color("#bf8e2c"),
		"blazer": Color("#5e4f66"), "suit": Color("#2b2331"), "trousers": Color("#2a2430"),
		"coat": Color("#1c1b20")},
	{"casual": Color("#a84b41"), "shirt": Color("#ecf2fb"), "tie": Color("#3a5c37"),
		"blazer": Color("#606770"), "suit": Color("#46494f"), "trousers": Color("#3a3d42"),
		"coat": Color("#c0955f")},
	{"casual": Color("#70847a"), "shirt": Color("#fff8ec"), "tie": Color("#7e2e2e"),
		"blazer": Color("#4d5d53"), "suit": Color("#20302b"), "trousers": Color("#232d29"),
		"coat": Color("#26262b")},
]
const JEANS: Array[Color] = [Color("#3e5070"), Color("#2f3b52"), Color("#56647c")]
const KHAKI: Array[Color] = [Color("#9b8d6c"), Color("#6a6d72"), Color("#7d6a55")]
const SNEAKER := Color("#ece9e2")
const SHOE_DARK := Color("#221c1c")
const SHOE_BROWN := Color("#4a3325")

## Uniformes (disfraz §10.4 y vestuario de oficio): cuerpo, pantalón, detalle, guantes.
const UNIFORMS: Dictionary = {
	"security": {"top": Color("#2b3d5e"), "bottom": Color("#1d2433"), "trim": Color("#d8b04a"),
		"cap": Color("#1c2638"), "hands": Color()},
	"cleaning": {"top": Color("#3f9f9c"), "bottom": Color("#2f7c7a"), "trim": Color("#e9f4f2"),
		"cap": Color(), "hands": Color("#f0c43a")},
	"maintenance": {"top": Color("#c9692a"), "bottom": Color("#8e4a1f"), "trim": Color("#e8d15a"),
		"cap": Color("#5b6068"), "hands": Color()},
	"factory": {"top": Color("#4d5b6b"), "bottom": Color("#39424e"), "trim": Color("#e6e04a"),
		"cap": Color(), "hands": Color()},
}

## Accesorios genéricos (15). Los de mano solo se ven en escalones 1–3 (§14.5: el 4 va sin nada).
const ACCESSORIES: Array[String] = [
	"", "glasses", "lanyard", "mug", "folder", "headphones", "cart", "phone", "backpack",
	"scarf", "watch", "pen_pocket", "tablet", "shoulder_bag", "coffee_cup",
]
const HANDHELD: Array[String] = ["mug", "folder", "phone", "tablet", "coffee_cup", "cart"]
const HANDS_FREE_TIER := 4

## Peinados (25): [estilo, vello facial]. Los tres últimos están reservados a los nominados.
const HAIRS: Array[PackedStringArray] = [
	["bald", ""], ["bald", "full_beard"], ["buzz", ""], ["buzz", "stubble"],
	["short_side", ""], ["short_side", "moustache"], ["crew", ""], ["quiff", ""],
	["slick", ""], ["slick", "goatee"], ["curly", ""], ["afro", ""], ["bob", ""],
	["long", ""], ["ponytail", ""], ["bun", ""], ["pixie", ""], ["wavy", ""],
	["receding", ""], ["receding", "full_beard"], ["comb_over", "moustache"], ["braids", ""],
	["bouffant", ""], ["silver_mane", ""], ["mullet", "moustache"],
]
## Parámetros de cada estilo. hl = altura de la línea del pelo (0 flequillo bajo, 1 frente
## despejada); vol = volumen; sides = hasta dónde bajan los laterales (1 = mandíbula);
## back = melena por detrás (1 = hombros); part = raya (-1..1); bumpy = contorno rizado.
const HAIR_STYLES: Dictionary = {
	"bald": {"cap": false, "hl": 1.0, "vol": 0.0, "sides": 0.0, "back": 0.0, "part": 0.0},
	"buzz": {"cap": true, "hl": 0.62, "vol": 0.02, "sides": 0.25, "back": 0.0, "part": 0.0},
	"short_side": {"cap": true, "hl": 0.5, "vol": 0.07, "sides": 0.3, "back": 0.0, "part": 0.7},
	"crew": {"cap": true, "hl": 0.55, "vol": 0.05, "sides": 0.25, "back": 0.0, "part": 0.0},
	"quiff": {"cap": true, "hl": 0.58, "vol": 0.12, "sides": 0.25, "back": 0.0, "part": 0.3,
		"extra": "quiff"},
	"slick": {"cap": true, "hl": 0.66, "vol": 0.05, "sides": 0.3, "back": 0.1, "part": 0.0,
		"extra": "shine"},
	"curly": {"cap": true, "hl": 0.45, "vol": 0.16, "sides": 0.45, "back": 0.1, "part": 0.0,
		"bumpy": true},
	"afro": {"cap": true, "hl": 0.5, "vol": 0.38, "sides": 0.6, "back": 0.25, "part": 0.0,
		"bumpy": true},
	"bob": {"cap": true, "hl": 0.35, "vol": 0.12, "sides": 1.0, "back": 0.45, "part": -0.4},
	"long": {"cap": true, "hl": 0.45, "vol": 0.08, "sides": 1.2, "back": 1.25, "part": 0.0},
	"ponytail": {"cap": true, "hl": 0.55, "vol": 0.05, "sides": 0.3, "back": 0.0, "part": 0.0,
		"extra": "ponytail"},
	"bun": {"cap": true, "hl": 0.58, "vol": 0.05, "sides": 0.3, "back": 0.0, "part": 0.0,
		"extra": "bun"},
	"pixie": {"cap": true, "hl": 0.38, "vol": 0.08, "sides": 0.4, "back": 0.0, "part": -0.8},
	"wavy": {"cap": true, "hl": 0.42, "vol": 0.14, "sides": 1.1, "back": 1.0, "part": 0.5,
		"bumpy": true},
	"receding": {"cap": true, "hl": 0.85, "vol": 0.03, "sides": 0.3, "back": 0.0, "part": 0.0,
		"extra": "receding"},
	"comb_over": {"cap": true, "hl": 0.8, "vol": 0.02, "sides": 0.3, "back": 0.0, "part": 1.0,
		"extra": "comb_over"},
	"braids": {"cap": true, "hl": 0.55, "vol": 0.06, "sides": 0.9, "back": 1.3, "part": 0.0,
		"extra": "braids"},
	"bouffant": {"cap": true, "hl": 0.42, "vol": 0.3, "sides": 0.9, "back": 0.5, "part": 0.6,
		"extra": "bouffant"},
	"silver_mane": {"cap": true, "hl": 0.7, "vol": 0.14, "sides": 0.45, "back": 0.25,
		"part": 0.0, "extra": "shine"},
	"mullet": {"cap": true, "hl": 0.5, "vol": 0.08, "sides": 0.35, "back": 0.8, "part": 0.0},
}

## Banda de la foto de personal por escalón (fondo con la paleta de art_bands.json).
const PORTRAIT_BANDS: Array[String] = [
	"the_pit", "the_pit", "the_pit", "the_pit", "the_specialists", "the_specialists",
	"the_power", "the_power", "the_throne",
]


# ─── Primitivas ────────────────────────────────────────────────

static func ellipse(center: Vector2, radii: Vector2, segments: int = ELLIPSE_SEGMENTS) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in segments:
		var a: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts


## Superelipse (exponente 2 = elipse; mayor = más cuadrada).
static func superellipse(center: Vector2, radii: Vector2, exponent: float,
		segments: int = ELLIPSE_SEGMENTS) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var e: float = 2.0 / maxf(exponent, 0.5)
	for i: int in segments:
		var a: float = TAU * float(i) / float(segments)
		var c: float = cos(a)
		var s: float = sin(a)
		pts.append(center + Vector2(signf(c) * pow(absf(c), e) * radii.x,
				signf(s) * pow(absf(s), e) * radii.y))
	return pts


## Arco de elipse de a0 a a1 (radianes) como lista de puntos.
static func arc(center: Vector2, radii: Vector2, a0: float, a1: float, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in segments + 1:
		var a: float = lerpf(a0, a1, float(i) / float(segments))
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts


## Polígono relleno con contorno cerrado (estilo vectorial plano con contorno, §14.2).
static func fill(canvas: CanvasItem, pts: PackedVector2Array, color: Color,
		outline: Color = OUTLINE, width: float = OUTLINE_WIDTH) -> void:
	if pts.size() < 3:
		return
	canvas.draw_colored_polygon(pts, color)
	if width <= 0.0:
		return
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	canvas.draw_polyline(closed, outline, width, true)


static func circle(canvas: CanvasItem, center: Vector2, radius: float, color: Color,
		outline: Color = OUTLINE, width: float = OUTLINE_WIDTH) -> void:
	canvas.draw_circle(center, radius, color, true, -1.0, true)
	if width > 0.0:
		canvas.draw_arc(center, radius, 0.0, TAU, ELLIPSE_SEGMENTS, outline, width, true)


## Miembro con extremos redondeados: contorno más ancho debajo y relleno encima.
static func limb(canvas: CanvasItem, points: PackedVector2Array, thickness: float, color: Color,
		outline: Color = OUTLINE, width: float = OUTLINE_WIDTH) -> void:
	var outer: float = thickness + width * 2.0
	for i: int in points.size():
		canvas.draw_circle(points[i], outer * 0.5, outline, true, -1.0, true)
		if i > 0:
			canvas.draw_line(points[i - 1], points[i], outline, outer, true)
	for i: int in points.size():
		canvas.draw_circle(points[i], thickness * 0.5, color, true, -1.0, true)
		if i > 0:
			canvas.draw_line(points[i - 1], points[i], color, thickness, true)


## Intersección de dos polígonos simples (el trozo con más vértices; vacío si no se tocan).
static func clip(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var parts: Array[PackedVector2Array] = Geometry2D.intersect_polygons(a, b)
	var best: PackedVector2Array = PackedVector2Array()
	for part: PackedVector2Array in parts:
		if part.size() > best.size():
			best = part
	return best


## Color de la paleta de una banda de art_bands.json (vía Database); `fallback` si no existe.
static func band_color(band_id: String, key: String, fallback: Color) -> Color:
	var band: Dictionary = Database.get_art_band(band_id)
	var palette: Dictionary = band.get("palette", {})
	if not palette.has(key):
		return fallback
	return Color(str(palette[key]))


## Proyección de una dirección del suelo a pantalla (compresión cenital 3/4).
static func ground(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * GROUND_Y)


## Proyección de un desplazamiento lateral a la altura de los hombros.
static func lateral(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * LATERAL_Y)
