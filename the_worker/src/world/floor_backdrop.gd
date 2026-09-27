# floor_backdrop.gd — Fondo de la planta: vacío alrededor del forjado, tierra, patio o ciudad nocturna.
# PROPIETARIO DE: las texturas de mosaico del fondo (generadas una vez por proceso).
# ESCUCHA: nada.
class_name FloorBackdrop
extends Node2D

## Barato por fotograma (PASO 40): cada motivo es una textura pequeña generada una vez y repetida
## con un solo draw_texture_rect (trama diagonal de la torre, tierra de los sótanos, patio de la
## nave) o un atlas de manzanas nocturnas (exterior, un cuadro por manzana, misma textura).
## Encima: sombra arrojada de cada sala y, en el exterior, la fachada de la sede (landmarks).
## Colores de la paleta de la banda (shadow/wall/outline/accent/light) de art_bands.json.

const EXTRA_CELLS := 30
const BLOCK_CELLS := 9
const Z_BACKDROP := -40
const HATCH_STEP := 36
const EARTH_TILE := 128
const EARTH_SPECKS := 22
const YARD_TILE := 144
const ATLAS_VARIANTS := 4
const BLOCK_TEXELS := 108
const ROOM_SHADOW_ALPHA := 0.42
const C_TREE := Color("#24442d")

var plan: Dictionary = {}
var cell: float = 48.0
var band: String = ""
var pal: Dictionary = {}
static var _tiles: Dictionary = {}


## Rectángulo (px de planta) que cubren el fondo y la sombra de luz: la planta y un margen.
static func outer_rect(p_plan: Dictionary, p_cell: float) -> Rect2:
	var size: Vector2 = Vector2(p_plan.get("size", Vector2i.ONE)) * p_cell
	var extra: Vector2 = Vector2.ONE * EXTRA_CELLS * p_cell
	return Rect2(-extra, size + extra * 2.0)


func setup(p_plan: Dictionary, p_cell: float) -> void:
	plan = p_plan
	cell = p_cell
	band = str(plan.get("band", ""))
	pal = RoomPainter.palette_of(Database.get_art_band(band))
	z_as_relative = false
	z_index = Z_BACKDROP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	name = "Backdrop"


func _draw() -> void:
	var outer: Rect2 = outer_rect(plan, cell)
	match band:
		"the_guts":
			draw_texture_rect(_earth_tile(pal["shadow"].darkened(0.35)), outer, true)
		"exterior":
			_city(outer)
		"factory":
			draw_texture_rect(_yard_tile(pal["shadow"].lightened(0.08)), outer, true)
		_:
			draw_texture_rect(_hatch_tile(_void_color()), outer, true)
	_room_shadows()
	for mark: Dictionary in plan.get("landmarks", []):
		var r: Rect2i = mark["rect"]
		_facade(Rect2(Vector2(r.position) * cell, Vector2(r.size) * cell))


## El vacío alrededor de la torre: oscuro para la banda, claro y aéreo en el trono.
func _void_color() -> Color:
	if band == "the_throne":
		return (pal["window"] as Color).darkened(0.35)
	return (pal["shadow"] as Color).darkened(0.45)


# ─── Mosaicos ─────────────────────────────────────────────────

func _hatch_tile(base: Color) -> ImageTexture:
	var key: String = "hatch_%s" % base.to_html()
	if not _tiles.has(key):
		var img: Image = Image.create(HATCH_STEP, HATCH_STEP, false, Image.FORMAT_RGB8)
		img.fill(base)
		for y: int in HATCH_STEP:
			for d: int in 2:
				img.set_pixel(posmod(y + d, HATCH_STEP), y, base.lightened(0.06))
		_tiles[key] = ImageTexture.create_from_image(img)
	return _tiles[key]


func _earth_tile(base: Color) -> ImageTexture:
	var key: String = "earth_%s" % base.to_html()
	if not _tiles.has(key):
		var img: Image = Image.create(EARTH_TILE, EARTH_TILE, false, Image.FORMAT_RGB8)
		img.fill(base)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash(key)
		for i: int in EARTH_SPECKS:
			var c: Vector2 = Vector2(rng.randf() * EARTH_TILE, rng.randf() * EARTH_TILE)
			_disc(img, c, rng.randf_range(2.0, 6.0), base.lightened(rng.randf_range(0.03, 0.08)))
		_tiles[key] = ImageTexture.create_from_image(img)
	return _tiles[key]


func _yard_tile(base: Color) -> ImageTexture:
	var key: String = "yard_%s" % base.to_html()
	if not _tiles.has(key):
		var img: Image = Image.create(YARD_TILE, 8, false, Image.FORMAT_RGB8)
		img.fill(base)
		img.fill_rect(Rect2i(0, 0, 2, 8), base.lightened(0.05))
		_tiles[key] = ImageTexture.create_from_image(img)
	return _tiles[key]


## Disco relleno con envoltura toroidal (mosaico sin costuras).
static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y: int in range(floori(c.y - r), ceili(c.y + r) + 1):
		for x: int in range(floori(c.x - r), ceili(c.x + r) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				img.set_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()), col)


# ─── Ciudad nocturna (exterior) ───────────────────────────────

## Manzanas vistas desde arriba: un cuadro del atlas por manzana (una sola textura → un lote).
func _city(outer: Rect2) -> void:
	var base: Color = (pal["shadow"] as Color).lerp(pal["floor"], 0.35)
	draw_rect(outer, base)
	var atlas: ImageTexture = _city_atlas(base)
	var step: float = cell * BLOCK_CELLS
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(int(plan.get("floor", 0)))
	var y: float = outer.position.y
	while y < outer.end.y:
		var x: float = outer.position.x
		while x < outer.end.x:
			var v: int = rng.randi_range(0, ATLAS_VARIANTS - 1)
			var src: Rect2 = Rect2((v % 2) * BLOCK_TEXELS, (v / 2) * BLOCK_TEXELS, BLOCK_TEXELS, BLOCK_TEXELS)
			draw_texture_rect_region(atlas, Rect2(x, y, step, step), src)
			x += step
		y += step


func _city_atlas(base: Color) -> ImageTexture:
	var key: String = "city_%s" % base.to_html()
	if _tiles.has(key):
		return _tiles[key]
	var img: Image = Image.create(BLOCK_TEXELS * 2, BLOCK_TEXELS * 2, false, Image.FORMAT_RGB8)
	img.fill(base)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(key)
	for v: int in ATLAS_VARIANTS:
		_paint_block(img, Vector2i((v % 2) * BLOCK_TEXELS, (v / 2) * BLOCK_TEXELS), base, rng)
	_tiles[key] = ImageTexture.create_from_image(img)
	return _tiles[key]


## Una manzana en el atlas: tejado, patio interior, ventanas encendidas y árboles en la acera.
func _paint_block(img: Image, o: Vector2i, base: Color, rng: RandomNumberGenerator) -> void:
	var margin: int = BLOCK_TEXELS / BLOCK_CELLS
	var roof: Rect2i = Rect2i(o + Vector2i(margin, margin), Vector2i.ONE * (BLOCK_TEXELS - margin * 2))
	img.fill_rect(roof, base.lightened(rng.randf_range(0.03, 0.08)))
	img.fill_rect(roof.grow(-margin * 2 / 3), base.lightened(rng.randf_range(0.0, 0.04)))
	var lit: Color = (pal["light"] as Color).darkened(0.2)
	for i: int in 7:
		var w: Vector2i = roof.position + Vector2i(rng.randi_range(2, roof.size.x - 5), rng.randi_range(2, roof.size.y - 5))
		img.fill_rect(Rect2i(w, Vector2i(3, 3)), lit if rng.randf() < 0.55 else base.lightened(0.14))
	for i: int in 2:
		var t: Vector2 = Vector2(o) + Vector2(rng.randf_range(margin * 2.0, BLOCK_TEXELS - margin * 2.0), BLOCK_TEXELS - margin * 0.5)
		_disc_clip(img, t, margin * 0.7, C_TREE, Rect2i(o, Vector2i.ONE * BLOCK_TEXELS))
		_disc_clip(img, t - Vector2(margin * 0.2, margin * 0.2), margin * 0.3, C_TREE.lightened(0.12), Rect2i(o, Vector2i.ONE * BLOCK_TEXELS))


static func _disc_clip(img: Image, c: Vector2, r: float, col: Color, clip: Rect2i) -> void:
	for y: int in range(floori(c.y - r), ceili(c.y + r) + 1):
		for x: int in range(floori(c.x - r), ceili(c.x + r) + 1):
			if clip.has_point(Vector2i(x, y)) and Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				img.set_pixel(x, y, col)


# ─── Sombras de sala y fachada ────────────────────────────────

## Sombra arrojada de cada sala sobre el fondo (maqueta recortada).
func _room_shadows() -> void:
	var offset: Vector2 = Vector2(cell * 0.22, cell * 0.32)
	for r: Rect2i in plan.get("rooms", {}).values():
		var px: Rect2 = Rect2(Vector2(r.position) * cell + offset, Vector2(r.size) * cell)
		draw_rect(px.grow(cell * 0.1), Color(0, 0, 0, ROOM_SHADOW_ALPHA * 0.5))
		draw_rect(px, Color(0, 0, 0, ROOM_SHADOW_ALPHA))


## Fachada de la sede en el exterior: cristal, ventanas encendidas, marquesina y estrella.
func _facade(r: Rect2) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(r)
	var glass: Color = (pal["shadow"] as Color).lerp(pal["wall"], 0.5)
	draw_rect(Rect2(r.position + Vector2(10, 14), r.size), Color(0, 0, 0, 0.45))
	draw_rect(r, (pal["shadow"] as Color).lightened(0.05))
	var band_h: float = cell * 1.1
	for row: int in int((r.size.y - cell) / band_h):
		var strip: Rect2 = Rect2(r.position.x + 8.0, r.position.y + row * band_h + 8.0, r.size.x - 16.0, band_h * 0.62)
		draw_rect(strip, glass)
		var x: float = strip.position.x
		while x < strip.end.x - cell:
			var w: float = cell * rng.randf_range(0.8, 2.4)
			if rng.randf() < 0.4:
				draw_rect(Rect2(x, strip.position.y, minf(w, strip.end.x - x), strip.size.y), (pal["light"] as Color).darkened(0.25))
			x += w
	var canopy: Rect2 = Rect2(r.position.x, r.end.y - cell * 0.7, r.size.x, cell * 0.7)
	draw_rect(canopy, (pal["accent"] as Color).darkened(0.3))
	draw_line(canopy.position, Vector2(canopy.end.x, canopy.position.y), pal["accent"], 3.0)
	draw_rect(r, pal["outline"], false, 3.0)
	_star(Vector2(r.get_center().x, r.position.y + r.size.y * 0.4))


func _star(c: Vector2) -> void:
	var star: PackedVector2Array = []
	for k: int in 10:
		star.append(c + Vector2.UP.rotated(k * TAU / 10.0) * cell * (1.6 if k % 2 == 0 else 0.68))
	draw_colored_polygon(star, pal["accent"])
	var loop: PackedVector2Array = star.duplicate()
	loop.append(star[0])
	draw_polyline(loop, pal["outline"], 2.5)
