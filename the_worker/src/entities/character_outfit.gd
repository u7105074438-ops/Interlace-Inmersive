# character_outfit.gd — Torso y vestuario por escalón / uniforme en cenital 3/4 (§14.4 capa 5, §14.5).
# PROPIETARIO DE: nada (funciones puras de dibujo sobre un CharacterRig).
# ESCUCHA: nada.
class_name CharacterOutfit
extends RefCounted

## Vestuarios: hoodie (1) · polo (2) · shirt_tie (3) · blazer (4) · suit (5, hombreras) ·
## suit_vest (6) · lux_suit (7, oro) · lux_coat (8, abrigo oscuro sobre los hombros, cuello de
## terciopelo con muesca y forro de seda; las mangas del traje quedan por delante) y uniformes
## security / cleaning / maintenance / factory (disfraz o vestuario de oficio).

const O := CharacterStyle.OUTLINE
const SHOULDER_DEPTH := 5.0
const HIP_DEPTH := 3.5
const BACK_VIEW := -0.3
const SUITS: Array[String] = ["blazer", "suit", "suit_vest", "lux_suit", "lux_coat"]
const RADIO := Color("#1b1c20")


static func draw_torso(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var top: Color = rig.colors["top"]
	if rig.outfit == "hoodie":
		_hood(canvas, rig, rig.front < BACK_VIEW)
	CharacterStyle.fill(canvas, torso_points(rig), top)
	_shoulder_shade(canvas, rig)
	if rig.front < BACK_VIEW:
		_back_details(canvas, rig)
		return
	if SUITS.has(rig.outfit):
		_suit_front(canvas, rig)
	else:
		_casual_front(canvas, rig)


## Contorno del torso: arco (o hombreras angulosas) arriba, cadera abajo.
static func torso_points(rig: CharacterRig) -> PackedVector2Array:
	var sry: float = SHOULDER_DEPTH + maxf(rig.hunch, 0.0) * 0.5
	var top_c: Vector2 = rig.shoulder_c + Vector2(0.0, sry * 0.9)
	var hh: float = rig.hip_half * (1.0 + rig.loose)
	var exponent: float = 2.0 + rig.pad * 4.0
	var pts: PackedVector2Array = PackedVector2Array()
	var e: float = 2.0 / exponent
	for i: int in 13:
		var a: float = lerpf(PI, TAU, float(i) / 12.0)
		var c: float = cos(a)
		var s: float = sin(a)
		pts.append(top_c + Vector2(signf(c) * pow(absf(c), e) * rig.shoulder_half,
				signf(s) * pow(absf(s), e) * sry))
	pts.append_array(CharacterStyle.arc(rig.hip_c + Vector2(0, -1), Vector2(hh, HIP_DEPTH), 0.0, PI, 8))
	return pts


## Luz y sombra plana: los hombros (vistos desde arriba) más claros.
static func _shoulder_shade(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var sry: float = SHOULDER_DEPTH + maxf(rig.hunch, 0.0) * 0.5
	var c: Vector2 = rig.shoulder_c + Vector2(0.0, sry * 0.9)
	var light: PackedVector2Array = CharacterStyle.arc(c, Vector2(rig.shoulder_half - 1.2, sry - 1.0),
			PI * 1.08, PI * 1.92, 10)
	canvas.draw_polyline(light, (rig.colors["top"] as Color).lightened(0.22), 2.0, true)


## Punto central del pecho, desplazado hacia donde mira (perfil y diagonales).
static func chest(rig: CharacterRig, t: float) -> Vector2:
	return rig.shoulder_c.lerp(rig.hip_c, t) + Vector2(rig.facing.x * rig.shoulder_half * 0.35, 0.0)


static func _suit_front(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var top: Color = rig.colors["top"]
	var narrow: float = 1.0 - rig.side * 0.45
	var neck: Vector2 = chest(rig, 0.0) + Vector2(0, 1.5)
	var v_bottom: Vector2 = chest(rig, 0.52)
	var w: float = rig.shoulder_half * 0.38 * narrow
	var v: PackedVector2Array = [neck + Vector2(-w, 0), neck + Vector2(w, 0), v_bottom]
	CharacterStyle.fill(canvas, v, rig.colors["shirt"], O, 1.0)
	if rig.outfit == "suit_vest":
		var vest: PackedVector2Array = [neck + Vector2(-w * 0.8, 3), neck + Vector2(w * 0.8, 3),
				v_bottom + Vector2(0, 3)]
		CharacterStyle.fill(canvas, vest, top.darkened(0.25), O, 1.0)
	_tie(canvas, rig, neck, v_bottom + Vector2(0, 2))
	var lapel: Color = top.darkened(0.35 if rig.outfit.begins_with("lux") else 0.2)
	var lw: float = 3.2 * narrow
	CharacterStyle.fill(canvas, PackedVector2Array([neck + Vector2(-w, 0), neck + Vector2(-w - lw, 1),
			v_bottom + Vector2(-1, 1), v_bottom]), lapel, O, 1.0)
	CharacterStyle.fill(canvas, PackedVector2Array([neck + Vector2(w, 0), neck + Vector2(w + lw, 1),
			v_bottom + Vector2(1, 1), v_bottom]), lapel, O, 1.0)
	_buttons(canvas, rig, v_bottom)
	if rig.outfit != "blazer":
		_pocket_square(canvas, rig)


static func _tie(canvas: CharacterCanvas, rig: CharacterRig, neck: Vector2, bottom: Vector2) -> void:
	var tie: Color = rig.colors["tie"]
	var tw: float = 2.2 * (1.0 - rig.side * 0.4)
	var knot: Vector2 = neck + Vector2(0, 1.5)
	var pts: PackedVector2Array = [knot + Vector2(-tw * 0.7, 0), knot + Vector2(tw * 0.7, 0),
			bottom.lerp(knot, 0.2) + Vector2(tw, 0), bottom, bottom.lerp(knot, 0.2) + Vector2(-tw, 0)]
	CharacterStyle.fill(canvas, pts, tie, O, 1.0)
	if rig.outfit.begins_with("lux"):
		var bar: Vector2 = knot.lerp(bottom, 0.45)
		canvas.draw_line(bar + Vector2(-tw - 0.8, 0), bar + Vector2(tw + 0.8, 0), CharacterStyle.GOLD, 1.4)


static func _buttons(canvas: CharacterCanvas, rig: CharacterRig, v_bottom: Vector2) -> void:
	var col: Color = CharacterStyle.GOLD if rig.outfit.begins_with("lux") else \
			(rig.colors["top"] as Color).darkened(0.45)
	var rows: int = 2 if rig.outfit == "lux_coat" else 1
	for i: int in 2:
		for j: int in rows:
			var off: Vector2 = Vector2(float(j * 2 - rows + 1) * 2.4, 3.0 + float(i) * 3.2)
			canvas.draw_circle(v_bottom + off, 0.95, col)


static func _pocket_square(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var at: Vector2 = chest(rig, 0.28) - rig.lat * rig.shoulder_half * 0.5
	var col: Color = CharacterStyle.GOLD if rig.outfit.begins_with("lux") else CharacterStyle.WHITE_SHIRT
	CharacterStyle.fill(canvas, PackedVector2Array([at + Vector2(-2, 1), at + Vector2(-0.5, -1.5),
			at + Vector2(1, -0.5), at + Vector2(2, 1)]), col, O, 0.8)


static func _casual_front(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var top: Color = rig.colors["top"]
	var neck: Vector2 = chest(rig, 0.0) + Vector2(0, 1.5)
	match rig.outfit:
		"hoodie":
			var pocket: Rect2 = Rect2(chest(rig, 0.62) + Vector2(-5.5, -2), Vector2(11, 5.5))
			canvas.draw_rect(pocket, top.darkened(0.16))
			canvas.draw_line(neck + Vector2(-2, 1), neck + Vector2(-2.4, 7), Color.WHITE, 1.0, true)
			canvas.draw_line(neck + Vector2(2, 1), neck + Vector2(2.4, 7), Color.WHITE, 1.0, true)
		"polo":
			_collar(canvas, neck, top.lightened(0.18))
			canvas.draw_line(neck + Vector2(0, 2), neck + Vector2(0, 7), top.darkened(0.3), 1.0)
		"shirt_tie":
			_collar(canvas, neck, CharacterStyle.WHITE_SHIRT)
			_tie(canvas, rig, neck, chest(rig, 0.82))
			canvas.draw_rect(Rect2(chest(rig, 0.3) - rig.lat * rig.shoulder_half * 0.5 + Vector2(-2, -1),
					Vector2(4, 3.5)), top.darkened(0.1))
		_:
			_uniform_front(canvas, rig, neck)


static func _collar(canvas: CharacterCanvas, neck: Vector2, color: Color) -> void:
	CharacterStyle.fill(canvas, PackedVector2Array([neck + Vector2(-4.5, -1), neck + Vector2(0, 1.2),
			neck + Vector2(-2.2, 3.2)]), color, O, 1.0)
	CharacterStyle.fill(canvas, PackedVector2Array([neck + Vector2(4.5, -1), neck + Vector2(0, 1.2),
			neck + Vector2(2.2, 3.2)]), color, O, 1.0)


static func _uniform_front(canvas: CharacterCanvas, rig: CharacterRig, neck: Vector2) -> void:
	var trim: Color = rig.colors["trim"]
	match rig.outfit:
		"security":
			_collar(canvas, neck, (rig.colors["top"] as Color).darkened(0.2))
			var badge: Vector2 = chest(rig, 0.3) - rig.lat * rig.shoulder_half * 0.45
			CharacterStyle.fill(canvas, PackedVector2Array([badge + Vector2(-2.2, -2.4),
					badge + Vector2(2.2, -2.4), badge + Vector2(2.2, 0.6), badge + Vector2(0, 2.8),
					badge + Vector2(-2.2, 0.6)]), trim, O, 0.9)
			canvas.draw_rect(Rect2(rig.sh_r + Vector2(-2, -4), Vector2(4, 5)), RADIO)
			_epaulettes(canvas, rig)
		"cleaning":
			_collar(canvas, neck, trim)
			canvas.draw_rect(Rect2(chest(rig, 0.55) + Vector2(-6, -1), Vector2(12, 7)),
					(rig.colors["top"] as Color).darkened(0.15))
		"maintenance":
			var y: float = chest(rig, 0.45).y
			canvas.draw_line(Vector2(rig.hip_c.x - rig.hip_half, y), Vector2(rig.hip_c.x + rig.hip_half, y),
					trim, 2.4)
			canvas.draw_line(neck + Vector2(0, 1), chest(rig, 0.9), (rig.colors["top"] as Color).darkened(0.3), 1.0)
		"factory":
			var l: Vector2 = chest(rig, 0.05) + rig.lat * rig.shoulder_half * 0.45
			var r: Vector2 = chest(rig, 0.05) - rig.lat * rig.shoulder_half * 0.45
			canvas.draw_line(l, l + Vector2(0, 16), trim, 3.0)
			canvas.draw_line(r, r + Vector2(0, 16), trim, 3.0)
			canvas.draw_line(chest(rig, 0.7) - Vector2(rig.hip_half, 0), chest(rig, 0.7) + Vector2(rig.hip_half, 0),
					trim, 2.2)


static func _epaulettes(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var col: Color = (rig.colors["top"] as Color).darkened(0.35)
	for sh: Vector2 in [rig.sh_l, rig.sh_r]:
		var inner: Vector2 = sh.lerp(rig.shoulder_c, 0.55)
		canvas.draw_line(sh + Vector2(0, -2.5), inner + Vector2(0, -2.5), col, 2.2, true)


static func _hood(canvas: CharacterCanvas, rig: CharacterRig, back: bool) -> void:
	var col: Color = (rig.colors["top"] as Color).darkened(0.12)
	if back:
		return
	var c: Vector2 = rig.shoulder_c + Vector2(0, 1) - rig.fwd * 3.0
	CharacterStyle.fill(canvas, CharacterStyle.ellipse(c, Vector2(rig.shoulder_half * 0.62, 5.0), 16), col)


static func _back_details(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var top: Color = rig.colors["top"]
	match rig.outfit:
		"hoodie":
			var c: Vector2 = rig.shoulder_c + Vector2(0, 5)
			CharacterStyle.fill(canvas, CharacterStyle.ellipse(c, Vector2(rig.shoulder_half * 0.55, 6.5), 16),
					top.darkened(0.12))
		"security":
			_epaulettes(canvas, rig)
		"suit", "suit_vest", "lux_suit", "blazer":
			canvas.draw_line(rig.shoulder_c + Vector2(0, 6), rig.hip_c + Vector2(0, -2), top.darkened(0.25), 1.0)
		"maintenance", "factory":
			var y: float = rig.shoulder_c.lerp(rig.hip_c, 0.45).y
			canvas.draw_line(Vector2(rig.hip_c.x - rig.hip_half, y), Vector2(rig.hip_c.x + rig.hip_half, y),
					rig.colors["trim"], 2.4)


## Abrigo sobre los hombros del escalón 8: la silueta más ancha y estática (§14.5). Se dibuja
## antes de los brazos cercanos para que las mangas del traje se vean por encima.
static func draw_coat(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	if rig.outfit != "lux_coat":
		return
	if rig.front < BACK_VIEW:
		_coat_back(canvas, rig)
		return
	var gap: float = rig.shoulder_half * 0.42 * (1.0 - rig.side * 0.5)
	var shift: float = rig.facing.x * rig.shoulder_half * 0.35
	for s: float in [-1.0, 1.0]:
		_coat_panel(canvas, rig, s, gap, shift)


## Un faldón delantero: paño, forro en el borde abierto y solapa de terciopelo con muesca.
static func _coat_panel(canvas: CharacterCanvas, rig: CharacterRig, s: float, gap: float, shift: float) -> void:
	var sh: float = rig.shoulder_half + 3.0
	var top: Vector2 = rig.shoulder_c + Vector2(0, 1)
	var hem_y: float = rig.hip_c.y + 5.0
	var neck: Vector2 = top + Vector2(s * gap + shift, -1.0)
	var hem_in: Vector2 = Vector2(rig.hip_c.x + s * gap * 1.25 + shift, hem_y)
	var panel: PackedVector2Array = [neck, top + Vector2(s * sh * 0.6, -3.5), top + Vector2(s * sh, 2.5),
			Vector2(rig.hip_c.x + s * (sh + 3.0), hem_y), hem_in]
	CharacterStyle.fill(canvas, panel, rig.colors["coat"])
	canvas.draw_line(neck + Vector2(s * 1.1, 3.0), hem_in + Vector2(s * 1.1, -1.5),
			CharacterStyle.LUX_COAT_LINING, 1.6, true)
	var chest_pt: Vector2 = neck.lerp(hem_in, 0.45)
	var collar: PackedVector2Array = [neck + Vector2(0, -1.5), top + Vector2(s * sh * 0.62, -3.5),
			neck.lerp(chest_pt, 0.3) + Vector2(s * sh * 0.45, 0.0), chest_pt + Vector2(s * 4.0, -3.0),
			chest_pt + Vector2(s * 2.2, -1.0), chest_pt]
	CharacterStyle.fill(canvas, collar, CharacterStyle.LUX_COAT_COLLAR, O, 1.2)
	canvas.draw_line(top + Vector2(s * sh * 0.72, 1.0), Vector2(rig.hip_c.x + s * (sh + 1.5), hem_y - 1.0),
			(rig.colors["coat"] as Color).lightened(0.12), 1.2, true)


## De espaldas: el abrigo cubre la espalda (cuello, abertura trasera y media trabilla dorada).
static func _coat_back(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var coat: Color = rig.colors["coat"]
	var sh: float = rig.shoulder_half + 3.0
	var top: Vector2 = rig.shoulder_c + Vector2(0, 1)
	var hem_y: float = rig.hip_c.y + 5.0
	CharacterStyle.fill(canvas, PackedVector2Array([top + Vector2(-sh, 2.5), top + Vector2(-sh * 0.6, -3.5),
			top + Vector2(sh * 0.6, -3.5), top + Vector2(sh, 2.5), Vector2(rig.hip_c.x + sh + 3.0, hem_y),
			Vector2(rig.hip_c.x - sh - 3.0, hem_y)]), coat)
	CharacterStyle.fill(canvas, PackedVector2Array([top + Vector2(-sh * 0.58, -3.5), top + Vector2(sh * 0.58, -3.5),
			top + Vector2(sh * 0.42, 2.0), top + Vector2(-sh * 0.42, 2.0)]), CharacterStyle.LUX_COAT_COLLAR, O, 1.2)
	var waist: float = rig.shoulder_c.lerp(rig.hip_c, 0.7).y
	canvas.draw_line(Vector2(rig.hip_c.x, waist + 3.0), Vector2(rig.hip_c.x, hem_y), coat.darkened(0.4), 1.2)
	canvas.draw_line(Vector2(rig.hip_c.x - 6.0, waist), Vector2(rig.hip_c.x + 6.0, waist), coat.darkened(0.3), 2.4)
	for x: float in [-4.5, 4.5]:
		canvas.draw_circle(Vector2(rig.hip_c.x + x, waist), 1.1, CharacterStyle.GOLD)
