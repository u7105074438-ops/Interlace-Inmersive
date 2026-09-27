# furniture_sprites.gd — Sprites de mobiliario horneados una vez por proceso (follaje de plantas).
# PROPIETARIO DE: la caché de texturas de sprites (por tipo, variante y colores).
# ESCUCHA: nada.
class_name FurnitureSprites
extends RefCounted

## PASO 40: el follaje eran 10-20 círculos con contorno por planta (una llamada de dibujo cada uno);
## ahora es una textura con transparencia pintada con discos y contorno, sobremuestreada ×2 para
## bordes suaves, que se dibuja con un solo draw_texture_rect (y se agrupa con las demás plantas).
## Plástico (the_pit, especialistas): pocas hojas grandes de verde saturado y brillo; natural
## (the_power, the_throne): más hojas pequeñas de verdes variados (§14.3).

const FOLIAGE_VARIANTS := 3
## Semiancho del sprite respecto al radio del follaje.
const FOLIAGE_SPAN := 1.35
const TEXELS := 64
const SUPERSAMPLE := 2
const OUTLINE_TEXELS := 2.4
const HIGHLIGHT := Color(1, 1, 1, 0.55)

static var _cache: Dictionary = {}


static func foliage(plastic: bool, variant: int, leaves: Array[Color], outline: Color) -> ImageTexture:
	var key: String = "foliage|%s|%d|%s|%s" % [plastic, variant, leaves[0].to_html(), outline.to_html()]
	if _cache.has(key):
		return _cache[key]
	var size: int = TEXELS * SUPERSAMPLE
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(key)
	var blobs: Array[Vector3] = _blobs(plastic, rng, float(size) * 0.5 / FOLIAGE_SPAN)
	var c: Vector2 = Vector2(size, size) * 0.5
	for b: Vector3 in blobs:
		_disc(img, c + Vector2(b.x, b.y), b.z + OUTLINE_TEXELS * SUPERSAMPLE, outline)
	for i: int in blobs.size():
		var col: Color = leaves[i % leaves.size()] if plastic else leaves[rng.randi_range(0, leaves.size() - 1)]
		_disc(img, c + Vector2(blobs[i].x, blobs[i].y), blobs[i].z, col)
	_disc(img, c, blobs[0].z * 0.8, leaves[0].lightened(0.1))
	if plastic:
		_disc(img, c + Vector2(-0.25, -0.3) * blobs[0].z * 2.0, blobs[0].z * 0.32, HIGHLIGHT)
	img.resize(TEXELS, TEXELS, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Hojas (x, y, radio en téxeles) alrededor del centro; `r` = radio del follaje.
static func _blobs(plastic: bool, rng: RandomNumberGenerator, r: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var count: int = 5 if plastic else 9
	for i: int in count:
		var ang: float = TAU * i / count + rng.randf() * 0.4
		var dist: float = r * (0.45 if plastic else rng.randf_range(0.3, 0.7))
		var rad: float = r * (0.55 if plastic else rng.randf_range(0.35, 0.55))
		out.append(Vector3(cos(ang) * dist, sin(ang) * 0.8 * dist, rad))
	return out


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y: int in range(maxi(0, floori(c.y - r)), mini(img.get_height(), ceili(c.y + r) + 1)):
		for x: int in range(maxi(0, floori(c.x - r)), mini(img.get_width(), ceili(c.x + r) + 1)):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(col))
