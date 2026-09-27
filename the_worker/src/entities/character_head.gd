# character_head.gd — Cabeza en cenital 3/4: cráneo, pelo encima, cara hacia la mirada, vello y gorras.
# PROPIETARIO DE: nada (funciones puras de dibujo sobre un CharacterRig).
# ESCUCHA: nada.
class_name CharacterHead
extends RefCounted

## La cabeza se ve desde arriba y delante: el pelo cubre la coronilla y la nuca; la cara ocupa la
## parte de la cabeza orientada hacia `rig.look` (de espaldas no se ve). Capas §14.4: cabeza
## (forma + edad), peinado y vello (25), tono de piel (8).

const O := CharacterStyle.OUTLINE
const FACE_HIDDEN := -0.45
const SIDE_PROFILE := 0.5
const EYE_RADII := Vector2(1.45, 1.95)
const WRINKLE := Color(0, 0, 0, 0.22)
## En las pieles más oscuras los ojos llevan esclerótica clara para leerse a escala de juego.
const DARK_SKIN_LUMINANCE := 0.3
const SCLERA := Color("#f3efe8")


static func style_of(rig: CharacterRig) -> Dictionary:
	return CharacterStyle.HAIR_STYLES.get(style_name(rig), CharacterStyle.HAIR_STYLES["bald"])


static func style_name(rig: CharacterRig) -> String:
	var hair: Array = CharacterStyle.HAIRS[int(rig.appearance.get("hair", 0))]
	return str(hair[0])


## Vello facial del peinado; nunca en presentación "f".
static func facial_of(rig: CharacterRig) -> String:
	if str(rig.appearance.get("presentation", "")) == CharacterStyle.PRESENTATION_F:
		return ""
	var hair: Array = CharacterStyle.HAIRS[int(rig.appearance.get("hair", 0))]
	return str(hair[1])


## Proyección de la mirada al plano de pantalla (cenital 3/4).
static func look_screen(rig: CharacterRig) -> Vector2:
	return Vector2(rig.look.x, rig.look.y * 0.5)


static func draw(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var style: Dictionary = style_of(rig)
	var skin: Color = rig.colors["skin"]
	var head: PackedVector2Array = CharacterStyle.superellipse(rig.head_c, rig.head_radii, rig.head_exp)
	_draw_profile_bits(canvas, rig, skin)
	CharacterStyle.fill(canvas, head, skin)
	var eyes: PackedVector2Array = eye_positions(rig)
	var visible: bool = rig.look.y > FACE_HIDDEN
	if visible:
		_draw_face(canvas, rig, eyes)
		_draw_facial_hair(canvas, rig, head)
	if bool(style["cap"]):
		_draw_curtains(canvas, rig, style)
		_draw_hair_mass(canvas, rig, style)
		_draw_nape(canvas, rig, style, head)
	_draw_hair_extras(canvas, rig, style)
	_draw_uniform_cap(canvas, rig)
	CharacterProps.draw_head_wear(canvas, rig, eyes, visible)


static func _wears_cap(rig: CharacterRig) -> bool:
	return (rig.colors["cap"] as Color).a > 0.0


## Nariz de perfil y orejas (se dibujan antes del cráneo para que sobresalgan).
static func _draw_profile_bits(canvas: CharacterCanvas, rig: CharacterRig, skin: Color) -> void:
	var r: Vector2 = rig.head_radii
	if absf(rig.look.x) > SIDE_PROFILE and rig.look.y > FACE_HIDDEN:
		var nose: Vector2 = rig.head_c + Vector2(signf(rig.look.x) * r.x * 0.96, r.y * 0.22)
		CharacterStyle.circle(canvas, nose, r.x * 0.17, skin)
	if absf(rig.look.y) > SIDE_PROFILE:
		for s: float in [-1.0, 1.0]:
			CharacterStyle.circle(canvas, rig.head_c + Vector2(s * r.x * 0.97, r.y * 0.12), r.x * 0.2, skin)


## Normal de la línea del pelo: el pelo queda "detrás" de ella (coronilla y nuca), la cara delante.
static func hairline_normal(rig: CharacterRig, style: Dictionary) -> Vector2:
	var n: Vector2 = Vector2(rig.look.x, rig.look.y * 0.5 + 0.55).normalized()
	return n.rotated(float(style["part"]) * 0.22)


## Distancia de la línea del pelo al centro de la cabeza (en la normal). De espaldas lo cubre todo.
static func hairline_distance(rig: CharacterRig, style: Dictionary) -> float:
	var front_d: float = rig.head_radii.y * (0.45 - 0.9 * float(style["hl"]))
	var back: float = smoothstep(-0.1, -0.6, rig.look.y)
	return lerpf(front_d, rig.head_radii.y * 2.2, back)


## Masa de pelo: cabeza ampliada por el volumen y recortada por una línea del pelo curva.
static func _draw_hair_mass(canvas: CharacterCanvas, rig: CharacterRig, style: Dictionary) -> void:
	var vol: float = float(style["vol"])
	var hair: Color = rig.colors["hair"]
	var c: Vector2 = rig.head_c + Vector2(0, -rig.head_radii.y * vol * 0.45)
	var radii: Vector2 = rig.head_radii * (1.0 + vol) + Vector2(0.4, 0.4)
	var n: Vector2 = hairline_normal(rig, style)
	var d: float = hairline_distance(rig, style)
	var big: float = rig.head_radii.x * 4.0
	var cutter: PackedVector2Array = CharacterStyle.ellipse(rig.head_c + n * (d - big), Vector2(big, big), 48)
	var mass: PackedVector2Array = CharacterStyle.clip(
			CharacterStyle.superellipse(c, radii, rig.head_exp, 28), cutter)
	if bool(style.get("bumpy", false)):
		var bump: float = radii.x * 0.3
		for p: Vector2 in CharacterStyle.ellipse(c, radii * 0.93, 12):
			if (p - rig.head_c).dot(n) < d - bump * 0.7:
				CharacterStyle.circle(canvas, p, bump, hair)
	CharacterStyle.fill(canvas, mass, hair)


## Mechones laterales (melena, media melena): enmarcan la cara sin taparla.
static func _draw_curtains(canvas: CharacterCanvas, rig: CharacterRig, style: Dictionary) -> void:
	var sides: float = float(style["sides"])
	if sides < 0.6 or rig.look.y < -0.35:
		return
	var r: Vector2 = rig.head_radii
	var across: Vector2 = Vector2(-rig.look.y, rig.look.x)
	var across_s: Vector2 = Vector2(across.x, across.y * 0.35)
	var height: float = r.y * (0.35 + 0.45 * minf(sides, 1.3))
	for s: float in [-1.0, 1.0]:
		var top: Vector2 = rig.head_c + across_s * s * r.x * 0.84 - look_screen(rig) * r.x * 0.35
		var c: Vector2 = top + Vector2(0, height * 0.55)
		CharacterStyle.fill(canvas, CharacterStyle.ellipse(c, Vector2(r.x * 0.32, height), 14),
				rig.colors["hair"])


## De espaldas con pelo corto se ve la nuca.
static func _draw_nape(canvas: CharacterCanvas, rig: CharacterRig, style: Dictionary, head: PackedVector2Array) -> void:
	if rig.look.y > -0.3 or float(style["back"]) > 0.05 or float(style["vol"]) > 0.2:
		return
	var r: Vector2 = rig.head_radii
	var nape: PackedVector2Array = CharacterStyle.ellipse(rig.head_c + Vector2(0, r.y * 0.95),
			Vector2(r.x * 0.5, r.y * 0.35), 14)
	CharacterStyle.fill(canvas, CharacterStyle.clip(nape, head), rig.colors["skin"], O, 1.0)


static func eye_positions(rig: CharacterRig) -> PackedVector2Array:
	var r: Vector2 = rig.head_radii
	var center: Vector2 = rig.head_c + look_screen(rig) * r.x * 0.62 + Vector2(0, r.y * 0.14)
	var across: Vector2 = Vector2(-rig.look.y, rig.look.x)
	var offset: Vector2 = Vector2(across.x, across.y * 0.3) * r.x * 0.38
	if absf(across.x) < 0.3:
		return PackedVector2Array([center + Vector2(0, 0.5)])
	return PackedVector2Array([center + offset, center - offset])


static func _draw_face(canvas: CharacterCanvas, rig: CharacterRig, eyes: PackedVector2Array) -> void:
	var expr: String = str(rig.p["expr"])
	var r: Vector2 = rig.head_radii
	for e: Vector2 in eyes:
		_draw_eye(canvas, rig, e, expr)
		_draw_brow(canvas, e + Vector2(0, -r.y * 0.3), expr, e.x < rig.head_c.x)
	var mouth: Vector2 = rig.head_c + look_screen(rig) * r.x * 0.62 + Vector2(0, r.y * 0.56)
	_draw_mouth(canvas, mouth, expr)
	if rig.age >= 2 and rig.look.y > 0.3:
		var c: Vector2 = rig.head_c + Vector2(0, r.y * 0.4)
		canvas.draw_line(c + Vector2(-r.x * 0.55, 0), c + Vector2(-r.x * 0.4, r.y * 0.18), WRINKLE, 1.0, true)
		canvas.draw_line(c + Vector2(r.x * 0.55, 0), c + Vector2(r.x * 0.4, r.y * 0.18), WRINKLE, 1.0, true)
	if expr == "guilty" or expr == "caught":
		canvas.draw_circle(mouth + Vector2(-r.x * 0.5, -r.y * 0.2), r.x * 0.2, CharacterStyle.BLUSH)
		canvas.draw_circle(mouth + Vector2(r.x * 0.5, -r.y * 0.2), r.x * 0.2, CharacterStyle.BLUSH)


static func _draw_eye(canvas: CharacterCanvas, rig: CharacterRig, e: Vector2, expr: String) -> void:
	match expr:
		"blink", "yawn", "proud":
			canvas.draw_line(e + Vector2(-1.6, 0), e + Vector2(1.6, 0), CharacterStyle.EYE, 1.3, true)
		"surprised", "caught":
			CharacterStyle.circle(canvas, e, 2.3, Color.WHITE, CharacterStyle.EYE, 1.0)
			canvas.draw_circle(e, 1.1, CharacterStyle.EYE)
		"stare":
			canvas.draw_colored_polygon(CharacterStyle.ellipse(e, Vector2(2.0, 2.3), 12), Color.WHITE)
			canvas.draw_colored_polygon(CharacterStyle.ellipse(e + look_screen(rig) * 0.5, Vector2(1.3, 1.6), 10),
					CharacterStyle.EYE)
		"bored", "strain":
			canvas.draw_colored_polygon(CharacterStyle.ellipse(e, EYE_RADII, 10), CharacterStyle.EYE)
			canvas.draw_line(e + Vector2(-2.0, -0.6), e + Vector2(2.0, -0.6), rig.colors["skin"], 1.6, true)
		"guilty":
			var side: Vector2 = Vector2(signf(rig.look.x + 0.001) * -0.8, 0)
			canvas.draw_colored_polygon(CharacterStyle.ellipse(e + side, EYE_RADII, 10), CharacterStyle.EYE)
		_:
			if (rig.colors["skin"] as Color).get_luminance() < DARK_SKIN_LUMINANCE:
				canvas.draw_colored_polygon(CharacterStyle.ellipse(e, EYE_RADII * 1.45, 12), SCLERA)
			canvas.draw_colored_polygon(CharacterStyle.ellipse(e, EYE_RADII, 10), CharacterStyle.EYE)
			canvas.draw_circle(e + Vector2(-0.4, -0.6), 0.45, Color(1, 1, 1, 0.85))


static func _draw_brow(canvas: CharacterCanvas, at: Vector2, expr: String, left: bool) -> void:
	var inner: float = 0.0
	match expr:
		"angry", "focus", "strain":
			inner = 1.3
		"worried", "guilty", "caught":
			inner = -1.3
		"surprised", "stare":
			at.y -= 1.2
		"suspicious", "sly":
			inner = 1.2 if left else -1.0
		"":
			return
	var sgn: float = 1.0 if left else -1.0
	canvas.draw_line(at + Vector2(-1.8 * sgn, -inner * 0.3), at + Vector2(1.8 * sgn, inner * 0.7),
			CharacterStyle.EYE, 1.1, true)


static func _draw_mouth(canvas: CharacterCanvas, m: Vector2, expr: String) -> void:
	match expr:
		"talk":
			canvas.draw_colored_polygon(CharacterStyle.ellipse(m, Vector2(1.6, 1.2), 8), CharacterStyle.MOUTH)
		"yawn":
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(m + Vector2(0, 0.5), Vector2(2.2, 2.8), 10),
					CharacterStyle.MOUTH, O, 0.9)
		"surprised", "caught":
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(m, Vector2(1.3, 1.6), 8), CharacterStyle.MOUTH, O, 0.8)
		"sly", "proud":
			canvas.draw_polyline([m + Vector2(-1.8, -0.4), m + Vector2(0.2, 0.6), m + Vector2(2.0, -0.8)],
					CharacterStyle.EYE, 1.0, true)
		"angry", "strain", "firm", "worried":
			canvas.draw_line(m + Vector2(-1.8, 0), m + Vector2(1.8, 0), CharacterStyle.EYE, 1.0, true)


static func _draw_facial_hair(canvas: CharacterCanvas, rig: CharacterRig, head: PackedVector2Array) -> void:
	var facial: String = facial_of(rig)
	if facial.is_empty():
		return
	var r: Vector2 = rig.head_radii
	var hair: Color = rig.colors["hair"]
	var m: Vector2 = rig.head_c + look_screen(rig) * r.x * 0.62 + Vector2(0, r.y * 0.5)
	match facial:
		"stubble":
			var s: PackedVector2Array = CharacterStyle.ellipse(m + Vector2(0, r.y * 0.1),
					Vector2(r.x * 0.7, r.y * 0.38), 16)
			canvas.draw_colored_polygon(CharacterStyle.clip(s, head), Color(hair, 0.35))
		"moustache":
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(m + Vector2(0, -r.y * 0.1),
					Vector2(r.x * 0.32, r.y * 0.12), 12), hair, O, 0.9)
		"goatee":
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(m + Vector2(0, r.y * 0.22),
					Vector2(r.x * 0.2, r.y * 0.16), 10), hair, O, 0.9)
		"full_beard":
			var b: PackedVector2Array = CharacterStyle.ellipse(m + Vector2(0, r.y * 0.12),
					Vector2(r.x * 0.78, r.y * 0.46), 18)
			CharacterStyle.fill(canvas, CharacterStyle.clip(b, CharacterStyle.ellipse(rig.head_c,
					r * 1.06, 20)), hair, O, 1.0)
			canvas.draw_line(m + Vector2(-1.5, -0.4), m + Vector2(1.5, -0.4), CharacterStyle.MOUTH, 1.0)


static func _draw_hair_extras(canvas: CharacterCanvas, rig: CharacterRig, style: Dictionary) -> void:
	var r: Vector2 = rig.head_radii
	var hair: Color = rig.colors["hair"]
	var extra: String = str(style.get("extra", ""))
	var ls: Vector2 = look_screen(rig)
	match extra:
		"bun":
			CharacterStyle.circle(canvas, rig.head_c + Vector2(0, -r.y * 0.95) - ls * r.x * 0.35, r.x * 0.38, hair)
		"quiff":
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(rig.head_c + ls * r.x * 0.35 + Vector2(0, -r.y * 0.85),
					Vector2(r.x * 0.5, r.y * 0.3), 14), hair)
		"shine", "comb_over":
			var arc: PackedVector2Array = CharacterStyle.arc(rig.head_c + Vector2(0, -r.y * 0.1),
					r * 0.72, PI * 1.2, PI * 1.55, 6)
			canvas.draw_polyline(arc, hair.lightened(0.35), 1.4, true)
		"swept":
			_draw_swept(canvas, rig)
		"receding":
			var crown_c: Vector2 = rig.head_c + Vector2(0, -r.y * 0.45) - ls * r.x * 0.15
			var crown: PackedVector2Array = CharacterStyle.ellipse(crown_c,
					Vector2(r.x * 0.42, r.y * 0.3), 12)
			canvas.draw_colored_polygon(crown, (rig.colors["skin"] as Color).darkened(0.04))
	if rig.look.y < -0.3:
		_draw_back_extras(canvas, rig, extra)


## Melena plateada peinada hacia atrás: mechones curvos de la frente a la coronilla.
static func _draw_swept(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var r: Vector2 = rig.head_radii
	var hair: Color = rig.colors["hair"]
	var ls: Vector2 = look_screen(rig)
	for i: int in 4:
		var t: float = float(i) / 3.0 - 0.5
		var c: Vector2 = rig.head_c + Vector2(t * r.x * 0.9, -r.y * 0.05) - ls * r.x * 0.2
		var strand: PackedVector2Array = CharacterStyle.arc(c, Vector2(r.x * 0.55, r.y * 0.85),
				PI * (1.15 + 0.08 * t), PI * (1.72 + 0.08 * t), 6)
		var col: Color = hair.darkened(0.35) if i % 2 == 0 else hair.lightened(0.45)
		canvas.draw_polyline(strand, col, 1.3, true)


static func _draw_back_extras(canvas: CharacterCanvas, rig: CharacterRig, extra: String) -> void:
	var r: Vector2 = rig.head_radii
	var hair: Color = rig.colors["hair"]
	if extra == "ponytail":
		var base: Vector2 = rig.head_c + Vector2(0, r.y * 0.35)
		CharacterStyle.limb(canvas, PackedVector2Array([base, base + Vector2(0, r.y * 0.9)]), r.x * 0.45, hair)


## Pelo que cuelga por detrás (melena, trenzas, coleta, afro): antes del torso si mira a cámara,
## después si está de espaldas.
static func draw_back_hair(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var style: Dictionary = style_of(rig)
	var back: float = float(style["back"])
	var extra: String = str(style.get("extra", ""))
	var r: Vector2 = rig.head_radii
	var hair: Color = rig.colors["hair"]
	if _wears_cap(rig) and back < 0.5:
		return
	if back > 0.05:
		var width: float = r.x * (1.7 + float(style["vol"]))
		var top: Vector2 = rig.head_c + Vector2(0, r.y * 0.1)
		var bottom: Vector2 = top + Vector2(0, r.y * (0.6 + back * 1.1))
		CharacterStyle.limb(canvas, PackedVector2Array([top, bottom]), width, hair)
	if extra == "braids":
		for s: float in [-1.0, 1.0]:
			var a: Vector2 = rig.head_c + Vector2(s * r.x * 0.85, r.y * 0.3)
			CharacterStyle.limb(canvas, PackedVector2Array([a, a + Vector2(s * 1.5, r.y * 1.6)]), 3.4, hair)
	if extra == "ponytail" and rig.look.y >= -0.3:
		var tail: Vector2 = rig.head_c - look_screen(rig) * r.x * 1.1 + Vector2(0, r.y * 0.1)
		CharacterStyle.limb(canvas, PackedVector2Array([tail + Vector2(0, -r.y * 0.4), tail + Vector2(0, r.y * 0.5)]),
				r.x * 0.5, hair)


## Gorra del uniforme (vigilante, mantenimiento): tapa la coronilla; visera hacia la mirada.
static func _draw_uniform_cap(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	if not _wears_cap(rig):
		return
	var cap: Color = rig.colors["cap"]
	var r: Vector2 = rig.head_radii
	var ls: Vector2 = look_screen(rig)
	var crown: PackedVector2Array = CharacterStyle.ellipse(rig.head_c + Vector2(0, -r.y * 0.42) - ls * r.x * 0.12,
			Vector2(r.x * 1.04, r.y * 0.66), 18)
	var visor: PackedVector2Array = CharacterStyle.ellipse(rig.head_c + ls * r.x * 0.62 + Vector2(0, -r.y * 0.3),
			Vector2(r.x * (0.8 - 0.25 * absf(rig.look.x)), r.y * 0.26), 14)
	if rig.look.y > FACE_HIDDEN:
		CharacterStyle.fill(canvas, crown, cap)
		CharacterStyle.fill(canvas, visor, cap.darkened(0.3))
	else:
		CharacterStyle.fill(canvas, visor, cap.darkened(0.3))
		CharacterStyle.fill(canvas, crown, cap)
	if rig.outfit == "security" and rig.look.y > FACE_HIDDEN:
		canvas.draw_circle(rig.head_c + ls * r.x * 0.35 + Vector2(0, -r.y * 0.62), 1.6, rig.colors["trim"])
