# character_props.gd — Objetos y accesorios de los personajes en vista cenital 3/4 (§14.4, §14.5, §14.7).
# PROPIETARIO DE: nada (funciones puras de dibujo sobre un CharacterRig).
# ESCUCHA: nada.
class_name CharacterProps
extends RefCounted

## Objeto del escalón (caja, papeles, carpeta), accesorios genéricos (15), accesorio único de
## cada nominado (§24.2, `unique_accessory`), objetos de animación (móvil, sobre, tarjeta...),
## objetos de escenario de la pose (cajón) y efectos (!, ?, sudor, zzz, líneas de velocidad).
## Los accesorios únicos y la carpeta del escalón 3 se dibujan grandes y en colores de contraste:
## deben leerse a la escala de juego (silueta antes que detalle, §14.2). Colores: constantes de arte.

const O := CharacterStyle.OUTLINE
const W := CharacterStyle.OUTLINE_WIDTH
const CARDBOARD := Color("#c99a5f")
const TAPE := Color("#e8cf8c")
const PAPER := Color("#f7f5ee")
const PAPER_LINE := Color("#b9c0c9")
const MANILA := Color("#e3c276")
const SCREEN := Color("#8fd3ff")
const DEVICE := Color("#2a2d34")
const METAL := Color("#c3c8cf")
const MUG_COLORS: Array[Color] = [Color("#e9e6df"), Color("#d8574a"), Color("#4f86c6")]
const BIG_MUG := Color("#f08fb0")
const RED_PEN := Color("#d23a2f")
const LANYARD_COLORS: Array[Color] = [Color("#2f6fd0"), Color("#c8353d"), Color("#2f9a62")]
const VISITOR := Color("#f28c1c")
const STEEL := Color("#8d949c")
const HARD_HAT := Color("#f4c534")
const BUCKET := Color("#3a7fd0")
const LEATHER := Color("#6b4428")
const BEAM := Color(1.0, 0.94, 0.6, 0.22)
const FX_YELLOW := Color("#ffd23f")
const FX_WHITE := Color("#fbfbf7")
const SWEAT := Color("#8fd0ff")
const MONEY := Color("#5fae5a")
const BEEP := Color("#6cf08a")
const GLOW := Color(0.55, 0.85, 1.0, 0.28)
const PLANNER_TABS: Array[Color] = [Color("#e84a5f"), Color("#f7b32b"), Color("#3fa7d6"), Color("#59cd90")]
const PLANNER := Color("#c2334d")
## Carpeta del escalón 3 (§14.5): colores vivos que contrastan con camisa y piel.
const FOLDER_COLORS: Array[Color] = [Color("#2f6fd0"), Color("#d8453a"), Color("#2f9a62"), Color("#8a4fc2")]
const DRAWER := Color("#8d949c")
const SPEED := Color(1.0, 1.0, 1.0, 0.85)
## Accesorios únicos que se llevan en el pecho: el nominado no carga caja ni papeles que los tapen.
const CHEST_UNIQUES: Array[String] = [
	"employee_of_month_pin", "thirty_year_pin", "gold_lapel_pin", "statement_necklace", "stopwatch",
	"pocket_ledger", "visitor_lanyard",
]

## Cómo sostiene cada accesorio único (los demás se llevan puestos).
const UNIQUE_HOLDS: Dictionary = {
	"oversized_mug": "right", "red_pen": "right", "paperback_novel": "right",
	"heavy_flashlight": "right", "steno_pad": "right", "clutched_laptop": "both",
	"twin_phones": "both_up", "cleaning_cart": "cart", "colour_coded_planner": "hug",
}
const HEAD_WEAR: Array[String] = [
	"glasses", "headphones", "noise_cancelling_headphones", "hard_hat", "designer_sunglasses",
	"glasses_chain",
]


static func unique_hold(unique: String) -> String:
	return str(UNIQUE_HOLDS.get(unique, ""))


## true si el objeto de esa mano queda detrás del cuerpo (de espaldas o mano del lado lejano).
static func hand_is_far(rig: CharacterRig, right: bool) -> bool:
	var l: Vector2 = rig.lat if right else -rig.lat
	return rig.front < -0.3 or (rig.side > 0.6 and l.y < 0.0)


# ─── Objetos en las manos ──────────────────────────────────────

## Dibuja los objetos de mano del lado pedido (lejanos antes del cuerpo, cercanos después).
static func draw_hand_items(canvas: CharacterCanvas, rig: CharacterRig, far: bool) -> void:
	if hand_is_far(rig, true) == far:
		_draw_right_item(canvas, rig)
		_draw_anim_prop(canvas, rig, str(rig.p["prop_r"]), rig.hand_r)
	if hand_is_far(rig, false) == far:
		_draw_left_item(canvas, rig)
		_draw_anim_prop(canvas, rig, str(rig.p["prop_l"]), rig.hand_l)
	var both_far: bool = rig.front < -0.3
	if both_far == far:
		_draw_both_hands_item(canvas, rig)


static func _draw_right_item(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var h: Vector2 = rig.hand_r
	match rig.held:
		"mug":
			_mug(canvas, h, 3.2, MUG_COLORS[int(rig.appearance.get("carry_pick", 0)) % 3])
		"oversized_mug":
			_mug(canvas, h, 5.0, BIG_MUG)
		"coffee_cup":
			_cup(canvas, h)
		"phone":
			_phone(canvas, h, true)
		"tablet":
			_rect_item(canvas, h + Vector2(0, -2), Vector2(9, 12), DEVICE, SCREEN)
		"folder":
			_rect_item(canvas, h + Vector2(0, -3), Vector2(11, 13), MANILA, CharacterStyle.NONE)
		"red_pen":
			canvas.draw_line(h + Vector2(-1, 3), h + Vector2(3, -6), O, 3.4, true)
			canvas.draw_line(h + Vector2(-1, 3), h + Vector2(3, -6), RED_PEN, 2.0, true)
		"paperback_novel":
			_book(canvas, h + Vector2(0, -3))
		"heavy_flashlight":
			_flashlight(canvas, rig, h)
		"steno_pad":
			_rect_item(canvas, h + Vector2(0, -3), Vector2(8, 11), PAPER, CharacterStyle.NONE)
			canvas.draw_line(h + Vector2(-4, -8), h + Vector2(4, -8), STEEL, 1.5, true)


static func _draw_left_item(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	match rig.carry:
		"papers":
			var c: Vector2 = rig.hand_l + Vector2(0, -2)
			for i: int in 3:
				var off: Vector2 = Vector2(float(i) * 1.2 - 1.2, float(-i) * 1.4)
				_rect_item(canvas, c + off, Vector2(11, 13), PAPER, CharacterStyle.NONE)
			for i: int in 3:
				canvas.draw_line(c + Vector2(-3, -4 + i * 3), c + Vector2(3, -4 + i * 3), PAPER_LINE, 1.0)


static func _draw_both_hands_item(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var mid: Vector2 = rig.hand_l.lerp(rig.hand_r, 0.5)
	if rig.carry == "box":
		_box(canvas, rig, mid)
	elif rig.held == "cart" or rig.unique_hold == "cart":
		_cart(canvas, rig, mid, rig.unique == "cleaning_cart")
	elif rig.unique == "clutched_laptop":
		_rect_item(canvas, mid + Vector2(0, -3), Vector2(16, 11), METAL, CharacterStyle.NONE)
		CharacterStyle.circle(canvas, mid + Vector2(0, -3), 1.4, Color.WHITE, O, 0.0)
	elif rig.unique == "twin_phones":
		_phone(canvas, rig.hand_l + Vector2(-1, -4), true, 1.45)
		_phone(canvas, rig.hand_r + Vector2(1, -4), true, 1.45)


static func _draw_anim_prop(canvas: CharacterCanvas, rig: CharacterRig, prop: String, h: Vector2) -> void:
	match prop:
		"phone":
			_phone(canvas, h + Vector2(0, -3), rig.front > -0.3)
		"card":
			_rect_item(canvas, h + Vector2(0, -2), Vector2(8, 5.5), Color.WHITE, Color("#2f6fd0"))
		"envelope":
			_rect_item(canvas, h + Vector2(0, -2), Vector2(11, 7), Color("#efe3c2"), CharacterStyle.NONE)
			canvas.draw_polyline([h + Vector2(-5, -5), h + Vector2(0, -1.5), h + Vector2(5, -5)],
					Color("#a89060"), 1.0, true)
		"loot":
			_rect_item(canvas, h + Vector2(0, -2), Vector2(7, 6), Color("#ffd166"), CharacterStyle.NONE)
		"document":
			_rect_item(canvas, h + Vector2(0, -3), Vector2(9, 11), PAPER, CharacterStyle.NONE)
		"watch":
			CharacterStyle.circle(canvas, h + Vector2(0, 1), 2.4, METAL, O, 1.0)


## Carpeta (escalón 3, §14.5) o agenda abrazada contra el pecho con el brazo cercano, delante del
## cuerpo; de espaldas asoma por el costado (behind = se dibuja antes del torso).
static func draw_hugged(canvas: CharacterCanvas, rig: CharacterRig, behind: bool) -> void:
	if rig.carry != "folder" and rig.carry != "planner":
		return
	if (rig.front < -0.3) != behind:
		return
	var c: Vector2 = hug_point(rig)
	var size: Vector2 = Vector2(11.0 + 3.0 * rig.side, 15.0)
	var planner: bool = rig.carry == "planner"
	var col: Color = PLANNER if planner else FOLDER_COLORS[int(rig.appearance.get("carry_pick", 0)) % FOLDER_COLORS.size()]
	_rect_item(canvas, c, size, col, CharacterStyle.NONE)
	if planner:
		for i: int in PLANNER_TABS.size():
			canvas.draw_rect(Rect2(c + Vector2(size.x * 0.5 - 0.5, -6.0 + float(i) * 3.4), Vector2(2.6, 2.4)),
					PLANNER_TABS[i])
		return
	_rect_item(canvas, c + Vector2(0, -2.5), Vector2(size.x * 0.6, 3.6), PAPER, CharacterStyle.NONE)
	canvas.draw_line(c + Vector2(-size.x * 0.5, 4.0), c + Vector2(size.x * 0.5, 4.0), col.lightened(0.35), 1.2)


static func hug_point(rig: CharacterRig) -> Vector2:
	var s: float = 1.0 if rig.hug_right else -1.0
	var lateral: float = rig.shoulder_half * (0.95 if rig.front < -0.3 else 0.5)
	return rig.shoulder_c.lerp(rig.hip_c, 0.52) + rig.lat * s * lateral + rig.fwd * 4.0


## Objeto de escenario de la pose (cajón de la mesa a la altura de la cadera, hacia donde mira).
## in_front: de frente o de perfil se dibuja delante del cuerpo (la mano entra en él); de
## espaldas, detrás.
static func draw_scene_prop(canvas: CharacterCanvas, rig: CharacterRig, in_front: bool) -> void:
	var prop: String = str(rig.p["scene_prop"])
	if prop.is_empty() or (rig.fwd.y > -0.05) != in_front:
		return
	var c: Vector2 = Vector2(0.0, -rig.leg_h * 0.62) + rig.fwd * 19.0
	var along_x: bool = absf(rig.fwd.x) >= absf(rig.fwd.y) * 2.0
	var size: Vector2 = Vector2(16, 13) if along_x else Vector2(20, 11)
	var box: Rect2 = Rect2(c - size * 0.5, size)
	canvas.draw_rect(box.grow(W * 0.6), O)
	canvas.draw_rect(box, DRAWER)
	if prop == "drawer_open":
		canvas.draw_rect(box.grow(-2.2), DRAWER.darkened(0.5))
		for i: int in 3:
			var t: float = (float(i) + 0.5) / 3.0
			var tab: Vector2 = box.position + box.size * Vector2(t, 0.5) if not along_x \
					else box.position + box.size * Vector2(0.5, t)
			_rect_item(canvas, tab, Vector2(3.5, 6.5) if not along_x else Vector2(6.5, 3.5),
					[PAPER, MANILA, PAPER][i], CharacterStyle.NONE)
	var near: Vector2 = c - rig.fwd.normalized() * (size.x if along_x else size.y) * 0.5
	var bar: Vector2 = Vector2(3.0, size.y + 2.0) if along_x else Vector2(size.x + 2.0, 3.0)
	_rect_item(canvas, near, bar, DRAWER.lightened(0.15), CharacterStyle.NONE)


# ─── Formas de objetos ─────────────────────────────────────────

static func _rect_item(canvas: CharacterCanvas, center: Vector2, size: Vector2, color: Color, inner: Color) -> void:
	var r: Rect2 = Rect2(center - size * 0.5, size)
	canvas.draw_rect(r.grow(W * 0.5), O)
	canvas.draw_rect(r, color)
	if inner.a > 0.0:
		canvas.draw_rect(r.grow(-1.6), inner)


static func _mug(canvas: CharacterCanvas, h: Vector2, r: float, color: Color) -> void:
	var c: Vector2 = h + Vector2(0, -r * 0.6)
	canvas.draw_arc(c + Vector2(r * 0.95, 0), r * 0.5, -PI * 0.5, PI * 0.5, 8, O, 2.4, true)
	canvas.draw_arc(c + Vector2(r * 0.95, 0), r * 0.5, -PI * 0.5, PI * 0.5, 8, color, 1.2, true)
	var body: PackedVector2Array = [c + Vector2(-r, -r * 0.4), c + Vector2(r, -r * 0.4),
			c + Vector2(r * 0.9, r), c + Vector2(-r * 0.9, r)]
	CharacterStyle.fill(canvas, body, color)
	CharacterStyle.fill(canvas, CharacterStyle.ellipse(c + Vector2(0, -r * 0.4), Vector2(r, r * 0.4), 12),
			Color("#5a3a26"))


static func _cup(canvas: CharacterCanvas, h: Vector2) -> void:
	var c: Vector2 = h + Vector2(0, -3)
	var body: PackedVector2Array = [c + Vector2(-2.6, -3), c + Vector2(2.6, -3), c + Vector2(2.0, 4),
			c + Vector2(-2.0, 4)]
	CharacterStyle.fill(canvas, body, PAPER)
	canvas.draw_rect(Rect2(c + Vector2(-2.3, -0.5), Vector2(4.6, 2.2)), Color("#8a5a3a"))
	CharacterStyle.fill(canvas, CharacterStyle.ellipse(c + Vector2(0, -3.2), Vector2(3.2, 1.3), 10),
			Color("#4a3a32"))


static func _phone(canvas: CharacterCanvas, h: Vector2, lit: bool, size: float = 1.0) -> void:
	_rect_item(canvas, h, Vector2(5, 8) * size, DEVICE, SCREEN if lit else DEVICE)


static func _book(canvas: CharacterCanvas, c: Vector2) -> void:
	var left: PackedVector2Array = [c + Vector2(-7, -4), c + Vector2(0, -3), c + Vector2(0, 5),
			c + Vector2(-7, 4)]
	var right: PackedVector2Array = [c + Vector2(0, -3), c + Vector2(7, -4), c + Vector2(7, 4),
			c + Vector2(0, 5)]
	CharacterStyle.fill(canvas, left, PAPER)
	CharacterStyle.fill(canvas, right, PAPER)
	canvas.draw_line(c + Vector2(-5, -1), c + Vector2(-2, -0.5), PAPER_LINE, 1.0)
	canvas.draw_line(c + Vector2(2, -0.5), c + Vector2(5, -1), PAPER_LINE, 1.0)


static func _flashlight(canvas: CharacterCanvas, rig: CharacterRig, h: Vector2) -> void:
	var tip: Vector2 = h + rig.facing * 11.0 + Vector2(0, -2)
	var beam_end: Vector2 = tip + rig.facing * 34.0
	var side: Vector2 = Vector2(-rig.facing.y, rig.facing.x) * 12.0
	canvas.draw_colored_polygon(PackedVector2Array([tip, beam_end + side, beam_end - side]), BEAM)
	CharacterStyle.limb(canvas, PackedVector2Array([h + Vector2(0, -2), tip]), 3.6, Color("#26282c"))
	CharacterStyle.circle(canvas, tip, 2.2, Color("#fff4b8"), O, 1.0)


static func _box(canvas: CharacterCanvas, rig: CharacterRig, mid: Vector2) -> void:
	var c: Vector2 = mid + Vector2(0, -1)
	var half: Vector2 = Vector2(12.5, 8.5)
	var top: PackedVector2Array = [c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y),
			c + Vector2(half.x, -half.y + 5), c + Vector2(-half.x, -half.y + 5)]
	var front_face: PackedVector2Array = [c + Vector2(-half.x, -half.y + 5), c + Vector2(half.x, -half.y + 5),
			c + Vector2(half.x, half.y), c + Vector2(-half.x, half.y)]
	CharacterStyle.fill(canvas, front_face, CARDBOARD.darkened(0.12))
	CharacterStyle.fill(canvas, top, CARDBOARD)
	canvas.draw_line(c + Vector2(0, -half.y), c + Vector2(0, -half.y + 5), TAPE, 2.2)
	canvas.draw_line(c + Vector2(-4, 1), c + Vector2(4, 1), CARDBOARD.darkened(0.3), 1.0)
	CharacterStyle.circle(canvas, rig.hand_l, CharacterRig.HAND_RADIUS, rig.colors["skin"])
	CharacterStyle.circle(canvas, rig.hand_r, CharacterRig.HAND_RADIUS, rig.colors["skin"])


static func _cart(canvas: CharacterCanvas, rig: CharacterRig, mid: Vector2, cleaning: bool) -> void:
	var c: Vector2 = mid + rig.fwd * 10.0 + Vector2(0, 3)
	canvas.draw_line(mid, c + Vector2(0, -4), O, 3.2, true)
	canvas.draw_line(mid, c + Vector2(0, -4), STEEL, 1.6, true)
	var front_face: PackedVector2Array = [c + Vector2(-12, -2), c + Vector2(12, -2), c + Vector2(12, 7),
			c + Vector2(-12, 7)]
	var top: PackedVector2Array = [c + Vector2(-12, -9), c + Vector2(12, -9), c + Vector2(12, -2),
			c + Vector2(-12, -2)]
	CharacterStyle.fill(canvas, front_face, STEEL.darkened(0.2))
	CharacterStyle.fill(canvas, top, STEEL.lightened(0.2))
	for x: float in [-9.0, 9.0]:
		CharacterStyle.circle(canvas, c + Vector2(x, 8), 1.8, Color("#26272b"), O, 1.0)
	if cleaning:
		_cleaning_load(canvas, c)
	else:
		_rect_item(canvas, c + Vector2(-4, -7), Vector2(9, 7), CARDBOARD, CharacterStyle.NONE)
		_rect_item(canvas, c + Vector2(6, -6), Vector2(6, 7), PAPER, CharacterStyle.NONE)


## Carrito de limpieza de Connie Marks: cubo amarillo, fregona, bolsa de basura y pulverizador.
static func _cleaning_load(canvas: CharacterCanvas, c: Vector2) -> void:
	var bucket: Vector2 = c + Vector2(-5, -6)
	CharacterStyle.fill(canvas, PackedVector2Array([bucket + Vector2(-5, -1), bucket + Vector2(5, -1),
			bucket + Vector2(4, 6), bucket + Vector2(-4, 6)]), HARD_HAT)
	CharacterStyle.fill(canvas, CharacterStyle.ellipse(bucket + Vector2(0, -1), Vector2(5, 2), 12), BUCKET)
	CharacterStyle.limb(canvas, PackedVector2Array([bucket + Vector2(1, 0), bucket + Vector2(4, -20)]), 1.8, LEATHER)
	CharacterStyle.fill(canvas, CharacterStyle.ellipse(c + Vector2(6, -7), Vector2(5, 4.5), 12), Color("#2a2b30"))
	CharacterStyle.fill(canvas, PackedVector2Array([c + Vector2(10, -16), c + Vector2(13, -16), c + Vector2(13, -8),
			c + Vector2(10, -8)]), Color("#7fd0f0"))


# ─── Accesorios puestos ────────────────────────────────────────

## Accesorios sobre el torso (solo visibles de frente o de perfil).
static func draw_torso_wear(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	if rig.front < -0.3:
		_draw_back_wear(canvas, rig)
		return
	var chest: Vector2 = rig.shoulder_c.lerp(rig.hip_c, 0.4) + Vector2(rig.facing.x * rig.shoulder_half * 0.3, 0)
	var pin_at: Vector2 = chest + rig.lat * (-rig.shoulder_half * 0.42) + Vector2(0, -3)
	match rig.accessory:
		"lanyard":
			_lanyard(canvas, rig, LANYARD_COLORS[int(rig.appearance.get("palette", 0)) % 3], false)
		"pen_pocket":
			_pen_pocket(canvas, pin_at + Vector2(0, 2))
		"scarf":
			_scarf(canvas, rig)
		"backpack", "shoulder_bag":
			_straps(canvas, rig, rig.accessory == "shoulder_bag")
	_draw_unique_torso(canvas, rig, chest, pin_at)


static func _draw_unique_torso(canvas: CharacterCanvas, rig: CharacterRig, chest: Vector2, pin_at: Vector2) -> void:
	match rig.unique:
		"visitor_lanyard":
			_lanyard(canvas, rig, VISITOR, true)
		"employee_of_month_pin":
			_ribbon(canvas, pin_at, Color("#2f6fd0"))
			_star(canvas, pin_at, 5.0, CharacterStyle.GOLD)
		"thirty_year_pin":
			_ribbon(canvas, pin_at, Color("#8a2433"))
			CharacterStyle.circle(canvas, pin_at, 4.0, CharacterStyle.GOLD, O, 1.2)
			CharacterStyle.circle(canvas, pin_at, 1.8, Color("#8a2433"), O, 0.0)
		"gold_lapel_pin":
			_star(canvas, pin_at, 4.6, CharacterStyle.GOLD)
			canvas.draw_line(pin_at + Vector2(2, 2), pin_at + Vector2(6, 7), CharacterStyle.GOLD, 1.6, true)
		"statement_necklace":
			_necklace(canvas, rig)
		"stopwatch":
			canvas.draw_polyline([rig.shoulder_c + Vector2(-4, 0), chest, rig.shoulder_c + Vector2(4, 0)],
					Color("#2a2a2a"), 1.2, true)
			CharacterStyle.circle(canvas, chest + Vector2(0, -2.8), 1.4, METAL, O, 1.0)
			CharacterStyle.circle(canvas, chest + Vector2(0, 2), 4.6, METAL, O, 1.3)
			canvas.draw_line(chest + Vector2(0, 2), chest + Vector2(1.6, -0.6), O, 1.1, true)
		"pocket_ledger":
			_rect_item(canvas, pin_at + Vector2(0, 2), Vector2(7, 9), Color("#1d1d1f"), CharacterStyle.NONE)
			canvas.draw_line(pin_at + Vector2(-3.5, -1.5), pin_at + Vector2(3.5, -1.5), CharacterStyle.GOLD, 1.4)
		"tool_belt":
			_tool_belt(canvas, rig)


## Cinta de medalla bajo un pin (dos colas).
static func _ribbon(canvas: CharacterCanvas, at: Vector2, color: Color) -> void:
	for s: float in [-1.0, 1.0]:
		CharacterStyle.fill(canvas, PackedVector2Array([at + Vector2(s * 0.5, 0), at + Vector2(s * 3.4, 1),
				at + Vector2(s * 3.0, 7.5), at + Vector2(s * 1.8, 6.2), at + Vector2(s * 0.9, 7.5)]), color, O, 1.0)


static func _draw_back_wear(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	if rig.accessory == "backpack":
		var c: Vector2 = rig.shoulder_c.lerp(rig.hip_c, 0.45)
		var r: Rect2 = Rect2(c - Vector2(8, 8), Vector2(16, 15))
		canvas.draw_rect(r.grow(W * 0.5), O)
		canvas.draw_rect(r, Color("#3a4a5c"))
		canvas.draw_rect(Rect2(c + Vector2(-5, 1), Vector2(10, 5)), Color("#2c3947"))
	if rig.unique == "tool_belt":
		_tool_belt(canvas, rig)


static func _lanyard(canvas: CharacterCanvas, rig: CharacterRig, color: Color, visitor: bool) -> void:
	var neck: Vector2 = rig.shoulder_c + Vector2(0, -1)
	var badge: Vector2 = rig.shoulder_c.lerp(rig.hip_c, 0.5) + Vector2(rig.facing.x * 3.0, 0)
	canvas.draw_line(neck + Vector2(-4, 0), badge, color, 1.6, true)
	canvas.draw_line(neck + Vector2(4, 0), badge, color, 1.6, true)
	var size: Vector2 = Vector2(7, 9) if visitor else Vector2(6, 7.5)
	_rect_item(canvas, badge + Vector2(0, 3), size, Color.WHITE, CharacterStyle.NONE)
	canvas.draw_rect(Rect2(badge + Vector2(-size.x * 0.5, -1), Vector2(size.x, 2.5)), color)


static func _pen_pocket(canvas: CharacterCanvas, at: Vector2) -> void:
	canvas.draw_rect(Rect2(at + Vector2(-3, -1), Vector2(6, 5)), Color(0, 0, 0, 0.15))
	var pens: Array[Color] = [Color("#2f6fd0"), RED_PEN, Color("#1d1d1f")]
	for i: int in pens.size():
		canvas.draw_line(at + Vector2(-2 + i * 2, -1), at + Vector2(-2 + i * 2, -4), pens[i], 1.4)


static func _scarf(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var pal: Dictionary = CharacterStyle.PALETTES[(int(rig.appearance.get("palette", 0)) + 5) % 12]
	var c: Color = pal["tie"]
	var neck: PackedVector2Array = CharacterStyle.ellipse(rig.shoulder_c + Vector2(0, -1),
			Vector2(rig.shoulder_half * 0.55, 3.2), 14)
	CharacterStyle.fill(canvas, neck, c)
	var tail: Vector2 = rig.shoulder_c + Vector2(rig.shoulder_half * 0.25, 1)
	CharacterStyle.limb(canvas, PackedVector2Array([tail, tail + Vector2(1, 9)]), 4.0, c)


static func _straps(canvas: CharacterCanvas, rig: CharacterRig, diagonal: bool) -> void:
	var strap: Color = Color("#2c3947")
	if diagonal:
		canvas.draw_line(rig.sh_l, rig.hip_c + rig.lat * rig.hip_half, strap, 2.2, true)
		return
	canvas.draw_line(rig.sh_l + Vector2(0, -1), rig.sh_l.lerp(rig.hip_c, 0.6), strap, 2.2, true)
	canvas.draw_line(rig.sh_r + Vector2(0, -1), rig.sh_r.lerp(rig.hip_c, 0.6), strap, 2.2, true)


static func _necklace(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var beads: PackedVector2Array = CharacterStyle.arc(rig.shoulder_c + Vector2(0, -2),
			Vector2(rig.shoulder_half * 0.42, 6.0), 0.15 * PI, 0.85 * PI, 6)
	for i: int in beads.size():
		var col: Color = CharacterStyle.GOLD if i % 2 == 0 else Color("#c0392b")
		CharacterStyle.circle(canvas, beads[i], 1.9, col, O, 0.9)


static func _tool_belt(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var y: float = rig.hip_c.y - 2.0
	var half: float = rig.hip_half * 1.08
	canvas.draw_line(Vector2(rig.hip_c.x - half, y), Vector2(rig.hip_c.x + half, y), O, 4.6)
	canvas.draw_line(Vector2(rig.hip_c.x - half, y), Vector2(rig.hip_c.x + half, y), LEATHER, 3.0)
	var pouch: Color = LEATHER.darkened(0.2)
	_rect_item(canvas, Vector2(rig.hip_c.x - half * 0.6, y + 3), Vector2(5, 6), pouch, CharacterStyle.NONE)
	_rect_item(canvas, Vector2(rig.hip_c.x + half * 0.6, y + 3), Vector2(5, 6), pouch, CharacterStyle.NONE)
	canvas.draw_line(Vector2(rig.hip_c.x + half * 0.6, y), Vector2(rig.hip_c.x + half * 0.7, y - 6), STEEL, 1.8)


static func _star(canvas: CharacterCanvas, c: Vector2, r: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var a: float = -PI * 0.5 + PI * float(i) / 5.0
		var rr: float = r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	CharacterStyle.fill(canvas, pts, color, O, 1.0)


## Muñeca: reloj, reloj de oro, sello (sobre la mano). Se dibuja tras las manos.
static func draw_wrist_wear(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	if rig.accessory == "watch":
		CharacterStyle.circle(canvas, rig.hand_l + Vector2(0, -3.2), 1.8, Color("#2a2a2a"), O, 0.8)
	match rig.unique:
		"gold_watch":
			CharacterStyle.circle(canvas, rig.hand_l + Vector2(0, -3.4), 2.9, CharacterStyle.GOLD, O, 1.1)
			canvas.draw_circle(rig.hand_l + Vector2(0, -3.4), 1.3, Color("#fff6d8"))
		"signet_ring":
			CharacterStyle.circle(canvas, rig.hand_r + Vector2(1.8, 0.6), 2.2, CharacterStyle.GOLD, O, 1.0)
			canvas.draw_circle(rig.hand_r + Vector2(1.2, 0.0), 0.7, Color("#fff6d8"))
	if rig.outfit == "lux_suit" or rig.outfit == "lux_coat":
		canvas.draw_circle(rig.hand_l + Vector2(0, -3.0), 1.1, CharacterStyle.GOLD)
		canvas.draw_circle(rig.hand_r + Vector2(0, -3.0), 1.1, CharacterStyle.GOLD)


# ─── Cabeza ────────────────────────────────────────────────────

static func head_wear_of(rig: CharacterRig) -> Array[String]:
	var out: Array[String] = []
	if HEAD_WEAR.has(rig.accessory):
		out.append(rig.accessory)
	if HEAD_WEAR.has(rig.unique):
		out.append(rig.unique)
	if rig.tic == CharacterRig.OBLIVIOUS_TIC and not out.has("noise_cancelling_headphones"):
		out.append("headphones")
	return out


## Gafas, auriculares, casco... sobre la cabeza ya dibujada. `eyes` = posiciones de los ojos.
static func draw_head_wear(canvas: CharacterCanvas, rig: CharacterRig, eyes: PackedVector2Array,
		visible_face: bool) -> void:
	for item: String in head_wear_of(rig):
		match item:
			"glasses", "glasses_chain":
				if visible_face:
					_glasses(canvas, rig, eyes, false)
				if item == "glasses_chain":
					_glasses_chain(canvas, rig)
			"designer_sunglasses":
				if visible_face:
					_glasses(canvas, rig, eyes, true)
			"headphones", "noise_cancelling_headphones":
				_headphones(canvas, rig, item == "noise_cancelling_headphones")
			"hard_hat":
				_hard_hat(canvas, rig)


static func _glasses(canvas: CharacterCanvas, rig: CharacterRig, eyes: PackedVector2Array, dark: bool) -> void:
	var r: float = rig.head_radii.x * 0.24
	var rim: Color = CharacterStyle.GOLD if dark else Color("#2b2b30")
	for e: Vector2 in eyes:
		if dark:
			canvas.draw_circle(e, r, Color("#15151a"), true, -1.0, true)
		canvas.draw_arc(e, r, 0.0, TAU, 14, rim, 1.1, true)
	if eyes.size() == 2 and eyes[0].distance_to(eyes[1]) > r * 2.0:
		var dir: Vector2 = (eyes[1] - eyes[0]).normalized()
		canvas.draw_line(eyes[0] + dir * r, eyes[1] - dir * r, rim, 1.0, true)


static func _glasses_chain(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var l: Vector2 = rig.head_c + Vector2(-rig.head_radii.x * 0.9, rig.head_radii.y * 0.1)
	var r: Vector2 = rig.head_c + Vector2(rig.head_radii.x * 0.9, rig.head_radii.y * 0.1)
	var low: Vector2 = rig.shoulder_c + Vector2(0, 3)
	canvas.draw_polyline([l, l.lerp(low, 0.5) + Vector2(-3, 2), low, r.lerp(low, 0.5) + Vector2(3, 2), r],
			CharacterStyle.GOLD, 0.9, true)


static func _headphones(canvas: CharacterCanvas, rig: CharacterRig, big: bool) -> void:
	var hc: Vector2 = rig.head_c
	var rx: float = rig.head_radii.x
	var band_col: Color = Color("#2a2d34")
	var cup_col: Color = Color("#e24b4b") if big else Color("#3a3f4a")
	canvas.draw_arc(hc + Vector2(0, -1), rx * 1.02, PI * 1.05, PI * 1.95, 14, O, 4.2, true)
	canvas.draw_arc(hc + Vector2(0, -1), rx * 1.02, PI * 1.05, PI * 1.95, 14, band_col, 2.4, true)
	var side: Vector2 = Vector2(-rig.look.y, rig.look.x)
	var cup_r: float = rx * (0.36 if big else 0.28)
	for s: float in [-1.0, 1.0]:
		var at: Vector2 = hc + Vector2(side.x * s * rx, side.y * s * rx * 0.35 + rig.head_radii.y * 0.05)
		if absf(side.x) < 0.3 and s * side.y < 0.0:
			continue
		CharacterStyle.circle(canvas, at, cup_r, cup_col)


static func _hard_hat(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var hc: Vector2 = rig.head_c + Vector2(0, -rig.head_radii.y * 0.3)
	var brim: PackedVector2Array = CharacterStyle.ellipse(hc + Vector2(0, rig.head_radii.y * 0.25),
			Vector2(rig.head_radii.x * 1.3, rig.head_radii.y * 0.55), 18)
	CharacterStyle.fill(canvas, brim, HARD_HAT.darkened(0.1))
	var dome: PackedVector2Array = CharacterStyle.ellipse(hc, rig.head_radii * Vector2(1.05, 0.85), 18)
	CharacterStyle.fill(canvas, dome, HARD_HAT)
	canvas.draw_line(hc + Vector2(0, -rig.head_radii.y * 0.8), hc + Vector2(0, rig.head_radii.y * 0.5),
			HARD_HAT.lightened(0.3), 2.0, true)


# ─── Efectos ───────────────────────────────────────────────────

## Efectos detrás del cuerpo: líneas de velocidad del esprint (opuestas a la dirección de avance).
static func draw_fx_behind(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	if str(rig.p["fx"]) != "speed":
		return
	var dir: Vector2 = CharacterStyle.ground(-rig.facing).normalized()
	var across: Vector2 = Vector2(-dir.y, dir.x)
	var base: Vector2 = rig.shoulder_c.lerp(rig.hip_c, 0.55)
	for i: int in 3:
		var off: float = (float(i) - 1.0) * (rig.shoulder_half * 0.75)
		var start: Vector2 = base + dir * (rig.shoulder_half * 0.9 + 3.0 + absf(off) * 0.25) + across * off
		var end: Vector2 = start + dir * (11.0 - absf(off) * 0.25)
		canvas.draw_line(start, end, O, 3.6, true)
		canvas.draw_line(start, end, SPEED, 1.8, true)


## Efectos sobre la cabeza: exclamación, interrogación, sudor, zzz, dinero, pitido, brillo.
static func draw_fx(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var fx: String = str(rig.p["fx"])
	var top: Vector2 = rig.head_c + Vector2(0, -rig.head_radii.y - 11.0)
	match fx:
		"exclaim":
			_bubble(canvas, top, FX_YELLOW)
			canvas.draw_line(top + Vector2(0, -5), top + Vector2(0, 1), O, 2.6, true)
			canvas.draw_circle(top + Vector2(0, 4.2), 1.5, O)
		"question":
			_bubble(canvas, top, FX_WHITE)
			canvas.draw_arc(top + Vector2(0, -2.2), 2.8, PI * 1.05, PI * 2.5, 10, O, 2.0, true)
			canvas.draw_circle(top + Vector2(0, 4.2), 1.3, O)
		"sweat":
			_drop(canvas, rig.head_c + Vector2(rig.head_radii.x * 1.05, -rig.head_radii.y * 0.3))
			_drop(canvas, rig.head_c + Vector2(-rig.head_radii.x * 1.15, -rig.head_radii.y * 0.1))
		"zzz":
			_zzz(canvas, rig.head_c + Vector2(rig.head_radii.x * 0.9, -rig.head_radii.y * 1.2))
		_:
			_draw_hand_fx(canvas, rig, fx)


static func _draw_hand_fx(canvas: CharacterCanvas, rig: CharacterRig, fx: String) -> void:
	match fx:
		"money":
			var at: Vector2 = rig.hand_r + Vector2(0, -8)
			_rect_item(canvas, at, Vector2(12, 6), MONEY, MONEY.lightened(0.25))
			canvas.draw_circle(at, 1.5, MONEY.darkened(0.3))
		"beep":
			for i: int in 6:
				var d: Vector2 = Vector2.from_angle(TAU * float(i) / 6.0)
				canvas.draw_line(rig.hand_r + d * 5.0, rig.hand_r + d * 8.0, BEEP, 1.6, true)
		"phone_glow":
			if rig.front > -0.3:
				canvas.draw_colored_polygon(CharacterStyle.ellipse(rig.head_c + Vector2(0, 2),
						rig.head_radii * 0.9, 14), GLOW)


static func _bubble(canvas: CharacterCanvas, c: Vector2, color: Color) -> void:
	CharacterStyle.fill(canvas, CharacterStyle.ellipse(c, Vector2(6.5, 7.5), 16), color)
	CharacterStyle.fill(canvas, PackedVector2Array([c + Vector2(-2, 6.5), c + Vector2(2, 6.5),
			c + Vector2(0, 10)]), color, O, 0.0)


static func _drop(canvas: CharacterCanvas, c: Vector2) -> void:
	var pts: PackedVector2Array = PackedVector2Array([c + Vector2(0, -3.5)])
	pts.append_array(CharacterStyle.arc(c, Vector2(2.0, 2.0), -0.1, PI + 0.1, 8))
	CharacterStyle.fill(canvas, pts, SWEAT, O, 1.0)


static func _zzz(canvas: CharacterCanvas, c: Vector2) -> void:
	for i: int in 3:
		var s: float = 2.0 + float(i)
		var o: Vector2 = c + Vector2(float(i) * 4.0, float(-i) * 5.0)
		canvas.draw_polyline([o + Vector2(-s, -s), o + Vector2(s, -s), o + Vector2(-s, s),
				o + Vector2(s, s)], FX_WHITE, 1.6, true)
