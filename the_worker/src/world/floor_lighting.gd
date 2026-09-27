# floor_lighting.gd — Luz de la planta: sombra multiplicativa horneada (ambiente + charcos) y tubos que parpadean.
# PROPIETARIO DE: nada (fábrica de nodos de luz; cada textura horneada vive en su nodo Shade).
# ESCUCHA: nada.
class_name FloorLighting
extends RefCounted

## Sin PointLight2D (PASO 40, §20.3): un único lienzo multiplicativo por planta (Shade) por encima de
## suelo, muros, muebles y actores y por debajo del realce de interactivos, puertas-UI y cámaras
## (así el realce discreto no se apaga en la penumbra). Tiene el ambiente de la banda y, si el tipo
## de iluminación lo pide, charcos de luz horneados una vez en una textura pequeña (farolas,
## luminarias en rejilla, luz interior de cada sala del exterior).
## Parámetros: balance mundo.luz.<tipo de art_bands lighting.type> = {ambiente: [r,g,b], radio
## (celdas), energia, cada (una luz de cada n luminarias; 0 = sin charcos), por_sala (bool)};
## art_bands lighting.intensity escala la energía; el color de la luz es la clave "light" de la
## paleta. Parpadeo de tubos (the_pit, lighting.flicker): balance mundo.parpadeo.*.

const Z_SHADE := 15
const Z_LIGHT := 40
const LIGHT_TEXTURE_SIZE := 256
const STREET_LAMP := "street_lamp"
## Desplazamiento de la cabeza de la farola respecto al centro de su celda (fracción de celda).
const LAMP_HEAD := Vector2(0.2, -0.4)

static var _light_texture: GradientTexture2D = null
static var _additive: CanvasItemMaterial = null
static var _multiply: CanvasItemMaterial = null


## Lienzo multiplicativo de la planta: color liso o textura horneada estirada sobre `rect`.
class Shade extends Node2D:
	var texture: Texture2D = null
	var rect: Rect2 = Rect2()
	var color: Color = Color.WHITE

	func _draw() -> void:
		if texture != null:
			draw_texture_rect(texture, rect, false)
		else:
			draw_rect(rect, color)


## Charco de un tubo fluorescente que parpadea de vez en cuando (§14.3 the_pit).
class FlickerLight extends Node2D:
	var radius: float = 96.0
	var color: Color = Color.WHITE
	var alpha: float = 0.1
	var phase: float = 0.0
	var period: float = 5.0
	var burst: float = 0.45
	var rate: float = 55.0
	var low: float = 0.25
	var high: float = 0.9
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		var f: float = fmod(_time + phase, period)
		var target: float = 1.0
		if f < burst:
			target = low if sin(f * rate) > 0.0 else high
		if not is_equal_approx(target, modulate.a):
			modulate.a = target

	func _draw() -> void:
		FloorLighting.draw_light_pool(self, Vector2.ZERO, radius, color, alpha)


# ─── Sombra de planta ─────────────────────────────────────────

## Añade la sombra de la planta a floor_root. `index` = índice de RoomBuilder (nodos de sala).
static func build(plan: Dictionary, floor_root: Node2D, cell: float, index: Dictionary) -> void:
	var record: Dictionary = Database.get_art_band(str(plan.get("band", "")))
	var params: Dictionary = params_for(str(record.get("lighting", {}).get("type", "")))
	if params.is_empty():
		return
	var ambient: Color = _rgb(params.get("ambiente", []))
	var spots: Array[Vector3] = light_spots(plan, params, cell, index)
	if ambient.is_equal_approx(Color.WHITE) and spots.is_empty():
		return
	var shade: Shade = Shade.new()
	shade.name = "Shade"
	shade.rect = FloorBackdrop.outer_rect(plan, cell)
	shade.color = ambient
	shade.z_as_relative = false
	shade.z_index = Z_SHADE
	shade.material = multiply_material()
	shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if not spots.is_empty():
		var energy: float = float(params.get("energia", 1.0)) * float(record.get("lighting", {}).get("intensity", 1.0))
		var lit: Color = Color.WHITE.lerp(RoomPainter.palette_of(record)["light"], 0.45)
		shade.texture = _bake(shade.rect, ambient, lit, spots, energy, cell)
	floor_root.add_child(shade)


## Parámetros de balance de un tipo de iluminación ({} si no hay).
static func params_for(type: String) -> Dictionary:
	var path: String = "mundo.luz." + type
	if type.is_empty() or not Database.has_balance(path):
		return {}
	var value: Variant = Database.get_balance(path)
	return value if value is Dictionary else {}


static func _rgb(values: Variant) -> Color:
	var list: Array = values if values is Array else []
	if list.size() < 3:
		return Color.WHITE
	return Color(float(list[0]), float(list[1]), float(list[2]))


## Luces (x, y en px de planta; z = radio en celdas): farolas, luminarias en rejilla (una de cada
## `cada`) y, con por_sala, una luz que cubre cada sala sin farolas (interiores del exterior).
static func light_spots(plan: Dictionary, params: Dictionary, cell: float, index: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var every: int = int(params.get("cada", 0))
	var radius: float = float(params.get("radio", 0.0))
	if radius <= 0.0 or (every <= 0 and not bool(params.get("por_sala", false))):
		return out
	for room_id: String in plan["order"]:
		var origin: Vector2 = Vector2((plan["rooms"][room_id] as Rect2i).position) * cell
		var lamps: int = _lamps(plan, room_id, origin, cell, radius, out)
		var size: Vector2i = (plan["rooms"][room_id] as Rect2i).size
		if lamps > 0:
			continue
		if bool(params.get("por_sala", false)):
			var c: Vector2 = origin + Vector2(size) * cell * 0.5
			out.append(Vector3(c.x, c.y, maxf(size.x, size.y) * float(params.get("radio_sala", 0.62))))
			continue
		var points: Array[Vector2] = RoomPainter.grid_points(size, room_id == str(plan["corridor_id"]), cell)
		for i: int in points.size():
			if every > 0 and i % every == 0:
				out.append(Vector3(origin.x + points[i].x, origin.y + points[i].y, radius))
	return out


static func _lamps(plan: Dictionary, room_id: String, origin: Vector2, cell: float, radius: float,
		out: Array[Vector3]) -> int:
	var room: RoomData = Database.get_room(room_id)
	if room == null:
		return 0
	var count: int = 0
	for entry: Dictionary in FloorLayout.furniture_of(plan, room):
		if str(entry["type"]) == STREET_LAMP:
			var p: Vector2 = origin + (Vector2(entry["pos"] as Vector2i) + Vector2(0.5, 0.5) + LAMP_HEAD) * cell
			out.append(Vector3(p.x, p.y, radius))
			count += 1
	return count


## Textura de luz: ambiente liso + charcos (1 - d²)² acumulados, tocando solo los téxeles alcanzados.
static func _bake(outer: Rect2, ambient: Color, lit: Color, spots: Array[Vector3], energy: float,
		cell: float) -> ImageTexture:
	var per_cell: float = maxf(0.5, Database.get_balance_float("mundo.luz.texeles_por_celda"))
	var k: float = per_cell / cell
	var w: int = maxi(1, ceili(outer.size.x * k))
	var h: int = maxi(1, ceili(outer.size.y * k))
	var acc: PackedFloat32Array = PackedFloat32Array()
	acc.resize(w * h)
	var touched: PackedInt32Array = PackedInt32Array()
	for spot: Vector3 in spots:
		_splat(acc, touched, w, h, (Vector2(spot.x, spot.y) - outer.position) * k, spot.z * per_cell, energy)
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(ambient)
	for i: int in touched:
		img.set_pixel(i % w, i / w, ambient.lerp(lit, minf(1.0, acc[i])))
	return ImageTexture.create_from_image(img)


static func _splat(acc: PackedFloat32Array, touched: PackedInt32Array, w: int, h: int, c: Vector2, r: float,
		energy: float) -> void:
	for y: int in range(maxi(0, floori(c.y - r)), mini(h, ceili(c.y + r))):
		for x: int in range(maxi(0, floori(c.x - r)), mini(w, ceili(c.x + r))):
			var d2: float = (Vector2(x + 0.5, y + 0.5) - c).length_squared() / (r * r)
			if d2 >= 1.0:
				continue
			var i: int = y * w + x
			if acc[i] <= 0.0:
				touched.append(i)
			acc[i] += energy * (1.0 - d2) * (1.0 - d2)


# ─── Tubos que parpadean ──────────────────────────────────────

## Tubos fluorescentes que parpadean (una de cada mundo.parpadeo.cada luminarias de la sala).
static func add_flicker(walls: RoomPainter, style: Dictionary, node: Node2D) -> void:
	if not bool(style.get("lighting", {}).get("flicker", false)):
		return
	var p: Dictionary = flicker_params()
	for pos: Vector2 in walls.light_points():
		if not is_flicker_point(pos):
			continue
		var light: FlickerLight = FlickerLight.new()
		light.position = pos
		light.radius = walls.cell * float(p["radio"])
		light.color = (style["pal"] as Dictionary).get("light", Color.WHITE)
		light.alpha = float(p["alfa"])
		light.phase = float(absi(hash(pos)) % 997) / 100.0
		light.period = float(p["periodo_min"]) + float(absi(hash(pos) >> 3) % 50) / 50.0 * float(p["periodo_var"])
		light.burst = float(p["duracion"])
		light.rate = float(p["frecuencia"])
		light.low = float(p["bajo"])
		light.high = float(p["alto"])
		light.z_as_relative = false
		light.z_index = Z_LIGHT
		light.material = additive_material()
		node.add_child(light)


static func flicker_params() -> Dictionary:
	var value: Variant = Database.get_balance("mundo.parpadeo")
	return value if value is Dictionary else {}


## Una de cada mundo.parpadeo.cada luminarias (determinista por posición).
static func is_flicker_point(pos: Vector2) -> bool:
	var every: int = maxi(1, Database.get_balance_int("mundo.parpadeo.cada"))
	return int(pos.x * 3.0 + pos.y * 7.0) % every == 0


# ─── Recursos compartidos ─────────────────────────────────────

static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


static func multiply_material() -> CanvasItemMaterial:
	if _multiply == null:
		_multiply = CanvasItemMaterial.new()
		_multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	return _multiply


## Charco de luz suave (textura radial compartida); aditivo si el lienzo usa ese material.
static func draw_light_pool(ci: CanvasItem, c: Vector2, radius: float, col: Color, alpha: float) -> void:
	ci.draw_texture_rect(light_texture(), Rect2(c - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
			false, Color(col.r, col.g, col.b, alpha))


static func light_texture() -> GradientTexture2D:
	if _light_texture != null:
		return _light_texture
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.55))
	_light_texture = GradientTexture2D.new()
	_light_texture.gradient = gradient
	_light_texture.fill = GradientTexture2D.FILL_RADIAL
	_light_texture.fill_from = Vector2(0.5, 0.5)
	_light_texture.fill_to = Vector2(1.0, 0.5)
	_light_texture.width = LIGHT_TEXTURE_SIZE
	_light_texture.height = LIGHT_TEXTURE_SIZE
	return _light_texture
