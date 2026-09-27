# floor_tiles.gd — Mosaicos de suelo generados una vez (moqueta, linóleo, baldosa, hormigón, madera, mármol…).
# PROPIETARIO DE: la caché de texturas de mosaico (por material, color y tamaño de celda).
# ESCUCHA: nada.
class_name FloorTiles
extends RefCounted

## PASO 40: el suelo de cada sala es un único draw_texture_rect en mosaico (con mipmaps para la
## vista de planta) en vez de cientos de rectángulos y líneas por celda. Cada mosaico mide un
## múltiplo de la celda y casa con la rejilla de la sala (su origen es la esquina de la sala).
## Los detalles irregulares por sala (manchas, grietas, vetas, alfombra de pasillo) los sigue
## pintando RoomPainter encima, pocos. Colores: los que RoomPainter saca de la paleta de la banda.

const GROUT := Color(0, 0, 0, 0.09)
const SHADE_STEP := 0.035
const STAIN := Color(0.18, 0.16, 0.08, 0.13)
const STAIN_TILE := Vector2i(7, 5)
const STAINS_PER_TILE := 4
const MARBLE_TILE := 8
const VEINS_PER_TILE := 4
const C_VEIN := Color(0.5, 0.48, 0.44, 0.22)
const C_VEIN_GOLD := Color(0.78, 0.64, 0.33, 0.35)

static var _cache: Dictionary = {}


## Textura de mosaico de `material` con color base `base` (y `extra`: segundo color si aplica).
static func tile(material: String, base: Color, cell: int, extra: Color = Color.BLACK) -> ImageTexture:
	var key: String = "%s|%s|%s|%d" % [material, base.to_html(), extra.to_html(), cell]
	if _cache.has(key):
		return _cache[key]
	var img: Image = _paint(material, base, cell, extra, hash(key))
	img.generate_mipmaps()
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _paint(material: String, base: Color, c: int, extra: Color, seed: int) -> Image:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	match material:
		"carpet":
			return _checker(base, c, 2, base.darkened(SHADE_STEP), 2 * c, rng, 0)
		"linoleum":
			return _checker(base, c, 2, base.lightened(SHADE_STEP), c, rng, 2)
		"tile", "shop_tile":
			return _checker(base, c / 2, 2, base.darkened(0.05), c / 2, rng, 0)
		"concrete":
			return _concrete(base, c, rng)
		"wood":
			return _wood(base, c, rng)
		"marble":
			return _marble(base, c, rng)
		"stone":
			return _stone(base, c, rng)
		"raised":
			return _raised(base, c)
		"rubber":
			return _rubber(base, c, rng)
		"deck":
			return _deck(base, c)
		"asphalt":
			return _asphalt(base, c, rng)
		"pavement":
			return _grid(base, c, c / 2, Color(0, 0, 0, 0.18))
		"stains":
			return _stains(c, rng)
		"sidewalk":
			return _sidewalk(base, c, extra)
		"hazard":
			return _hazard(base, c, extra, maxi(2, c / 3))
		"hazard_thin":
			return _hazard(base, c, extra, maxi(2, c / 8))
	var img: Image = Image.create(c, c, false, Image.FORMAT_RGBA8)
	img.fill(base)
	return img


# ─── Primitivas de imagen ─────────────────────────────────────

static func _blend(img: Image, x: int, y: int, col: Color) -> void:
	var px: int = posmod(x, img.get_width())
	var py: int = posmod(y, img.get_height())
	img.set_pixel(px, py, img.get_pixel(px, py).blend(col))


## Líneas de rejilla cada `step` px en ambos ejes (1 px, color con alfa mezclado).
static func _grid_lines(img: Image, step: int, col: Color, width: int = 1) -> void:
	for x0: int in range(0, img.get_width(), step):
		for k: int in width:
			for y: int in img.get_height():
				_blend(img, x0 + k, y, col)
	for y0: int in range(0, img.get_height(), step):
		for k: int in width:
			for x: int in img.get_width():
				if x % step >= width:
					_blend(img, x, y0 + k, col)


static func _grid(base: Color, c: int, step: int, col: Color) -> Image:
	var img: Image = Image.create(c, c, false, Image.FORMAT_RGBA8)
	img.fill(base)
	_grid_lines(img, step, col)
	return img


static func _disc(img: Image, center: Vector2, r: Vector2, col: Color) -> void:
	for y: int in range(floori(center.y - r.y), ceili(center.y + r.y) + 1):
		for x: int in range(floori(center.x - r.x), ceili(center.x + r.x) + 1):
			var d: Vector2 = (Vector2(x + 0.5, y + 0.5) - center) / r
			if d.length_squared() <= 1.0:
				_blend(img, x, y, col)


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps: int = maxi(1, ceili(a.distance_to(b)))
	for i: int in steps + 1:
		var p: Vector2 = a.lerp(b, float(i) / steps)
		_blend(img, floori(p.x), floori(p.y), col)


# ─── Materiales ───────────────────────────────────────────────

## Damero de `cells`×`cells` casillas de `c` px (casillas alternas `alt`), juntas cada `grout_step`
## y `dots` motas oscuras por casilla.
static func _checker(base: Color, c: int, cells: int, alt: Color, grout_step: int, rng: RandomNumberGenerator,
		dots: int) -> Image:
	var img: Image = Image.create(c * cells, c * cells, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for y: int in cells:
		for x: int in cells:
			if (x + y) % 2 == 0:
				img.fill_rect(Rect2i(x * c, y * c, c, c), alt)
	for i: int in dots * cells * cells:
		_blend(img, rng.randi_range(0, c * cells - 1), rng.randi_range(0, c * cells - 1), Color(base.darkened(0.12), 0.9))
	_grid_lines(img, grout_step, GROUT)
	return img


static func _concrete(base: Color, c: int, rng: RandomNumberGenerator) -> Image:
	var img: Image = Image.create(c * 4, c * 4, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for i: int in 3:
		var col: Color = Color(base.darkened(rng.randf_range(0.03, 0.09)), 1.0)
		var r: float = rng.randf_range(0.3, 1.1) * c
		_disc(img, Vector2(rng.randf() * c * 4, rng.randf() * c * 4), Vector2(r, r * rng.randf_range(0.4, 1.0)), col)
	_grid_lines(img, c * 4, Color(base.darkened(0.18), 1.0), 2)
	return img


## Tarima: filas de lamas de largo aleatorio (1,2-2,6 celdas) en un mosaico de 8×1 celdas.
static func _wood(base: Color, c: int, rng: RandomNumberGenerator) -> Image:
	var w: int = c * 8
	var plank: int = maxi(1, c / 4)
	var img: Image = Image.create(w, c, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for row: int in c / plank:
		var x: int = rng.randi_range(0, c)
		var start: int = x
		while x < start + w:
			var length: int = int(rng.randf_range(1.2, 2.6) * c)
			var tone: Color = base.lightened(rng.randf_range(-0.05, 0.07))
			for k: int in mini(length, start + w - x):
				for dy: int in plank:
					img.set_pixel(posmod(x + k, w), row * plank + dy, tone)
			for dy: int in plank:
				img.set_pixel(posmod(x + length, w), row * plank + dy, base.darkened(0.25))
			x += length
		for k: int in w:
			img.set_pixel(k, row * plank, base.darkened(0.22))
	return img


static func _marble(base: Color, c: int, rng: RandomNumberGenerator) -> Image:
	var size: int = c * MARBLE_TILE
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(0, MARBLE_TILE, 2):
		for x: int in range(0, MARBLE_TILE, 2):
			img.fill_rect(Rect2i(x * c, y * c, c * 2, c * 2), base.lightened(rng.randf_range(-0.03, 0.04)))
	for i: int in VEINS_PER_TILE:
		var p: Vector2 = Vector2(rng.randf() * size, rng.randf() * size)
		var dir: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(-0.5, 0.5) + (PI * 0.25 if i % 2 == 0 else -PI * 0.2))
		for k: int in 10:
			dir = dir.rotated(rng.randf_range(-0.18, 0.18))
			var q: Vector2 = p + dir * c * 0.4
			_line(img, p, q, C_VEIN_GOLD if i % 4 == 0 else C_VEIN)
			p = q
	_grid_lines(img, c * 2, GROUT)
	return img


static func _stone(base: Color, c: int, rng: RandomNumberGenerator) -> Image:
	var img: Image = Image.create(c * 4, c * 4, false, Image.FORMAT_RGBA8)
	for y: int in 4:
		for x: int in 4:
			img.fill_rect(Rect2i(x * c, y * c, c, c), base.lightened(rng.randf_range(-0.04, 0.04)))
	_grid_lines(img, c, GROUT)
	return img


## Suelo técnico: losas con rejilla de ventilación en una de cada cinco (patrón de 5×5 celdas).
static func _raised(base: Color, c: int) -> Image:
	var img: Image = Image.create(c * 5, c * 5, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for y: int in 5:
		for x: int in 5:
			var r: Rect2i = Rect2i(x * c + 2, y * c + 2, c - 4, c - 4)
			img.fill_rect(r, base.lightened(0.04))
			if (x * 7 + y * 3) % 5 == 0:
				for k: int in 3:
					img.fill_rect(Rect2i(r.position.x + 5, r.position.y + 7 + k * 8, r.size.x - 10, 2), base.darkened(0.25))
	return img


static func _rubber(base: Color, c: int, rng: RandomNumberGenerator) -> Image:
	var img: Image = Image.create(c * 2, c * 2, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for i: int in 16:
		_blend(img, rng.randi_range(0, c * 2 - 1), rng.randi_range(0, c * 2 - 1), Color(0.6, 0.6, 0.65, 0.25))
	for y: int in c * 2:
		_blend(img, 0, y, Color(0, 0, 0, 0.3))
		_blend(img, c, y, Color(0, 0, 0, 0.3))
	return img


## Tarima de exterior: seis lamas verticales alternas por cada dos celdas.
static func _deck(base: Color, c: int) -> Image:
	var img: Image = Image.create(c * 2, c * 2, false, Image.FORMAT_RGBA8)
	img.fill(base)
	var plank: int = maxi(1, c / 3)
	for i: int in 6:
		if i % 2 == 0:
			img.fill_rect(Rect2i(i * plank, 0, plank, c * 2), base.lightened(0.04))
		img.fill_rect(Rect2i(i * plank, 0, 1, c * 2), base.darkened(0.25))
	return img


static func _asphalt(base: Color, c: int, rng: RandomNumberGenerator) -> Image:
	var img: Image = Image.create(c * 2, c * 2, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for i: int in 10:
		_disc(img, Vector2(rng.randf() * c * 2, rng.randf() * c * 2), Vector2(1.3, 1.3), base.lightened(0.08))
	return img


## Capa de manchas (transparente) de 7×5 celdas: periodo primo con la rejilla, repite poco.
static func _stains(c: int, rng: RandomNumberGenerator) -> Image:
	var img: Image = Image.create(c * STAIN_TILE.x, c * STAIN_TILE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i: int in STAINS_PER_TILE:
		var center: Vector2 = Vector2(rng.randf() * img.get_width(), rng.randf() * img.get_height())
		var r: float = rng.randf_range(0.12, 0.38) * c
		var squash: float = rng.randf_range(0.5, 0.9)
		_disc(img, center, Vector2(r, r * squash), STAIN)
		_disc(img, center + Vector2(r * 0.4, 0), Vector2(r * 0.5, r * 0.5 * squash), STAIN)
	return img


## Acera: baldosas de una celda con junta oscura; `edge` = bordillo claro en la fila inferior.
static func _sidewalk(base: Color, c: int, edge: Color) -> Image:
	var img: Image = Image.create(c, c, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for y: int in c:
		_blend(img, 0, y, Color(0, 0, 0, 0.2))
	img.fill_rect(Rect2i(0, c - 3, c, 3), edge)
	return img


## Franja de peligro: diagonales `extra` sobre `base` (mosaico horizontal de una celda).
static func _hazard(base: Color, c: int, stripe: Color, h: int) -> Image:
	var img: Image = Image.create(c, h, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for y: int in h:
		for x: int in c:
			if posmod(x + y, c / 2) < c / 4:
				img.set_pixel(x, y, stripe)
	return img
