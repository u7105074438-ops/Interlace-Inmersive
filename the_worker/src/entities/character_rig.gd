# character_rig.gd — Esqueleto 2D de un personaje en una pose: articulaciones, medidas y colores resueltos.
# PROPIETARIO DE: nada (estructura de cálculo efímera; la construye CharacterPainter en cada dibujo).
# ESCUCHA: nada.
class_name CharacterRig
extends RefCounted

## Origen = centro de los pies sobre el suelo; +y hacia abajo (hacia la cámara). Cenital 3/4:
## las direcciones del suelo se comprimen (CharacterStyle.GROUND_Y) y lo vertical no.
## `facing` orienta el cuerpo; `look` la cabeza (tic, pose.look o head_turn).

const NECK := 1.5
const ARM_WIDTH := 6.0
const LEG_WIDTH := 7.0
const HAND_RADIUS := 3.3
const HAND_DROP := 0.78
const ARM_LENGTH := 0.92
const SIDE_NARROW_SHOULDER := 0.36
const SIDE_NARROW_HIP := 0.3
const HEAD_TURN_MAX := 1.15
const OBLIVIOUS_TIC := "headphones_never_turns_head"
const STARE_TIC := "stares_at_anomalies"
const RIGHT_HOLDS: Array[String] = ["right"]
const BOTH_HOLDS: Array[String] = ["both", "both_up", "cart"]
const HUG_HOLD := "hug"

var tier: int = 1
var appearance: Dictionary = {}
var p: Dictionary = {}
var facing: Vector2 = Vector2.DOWN
var look: Vector2 = Vector2.DOWN
var fwd: Vector2 = Vector2.ZERO
var side_dir: Vector2 = Vector2.ZERO
var lat: Vector2 = Vector2.ZERO
var lat_g: Vector2 = Vector2.ZERO
var side: float = 0.0
var front: float = 1.0
var width_scale: float = 1.0
var height_scale: float = 1.0
var shoulder_half: float = 0.0
var hip_half: float = 0.0
var torso_h: float = 0.0
var leg_h: float = 0.0
var hunch: float = 0.0
var loose: float = 0.0
var pad: float = 0.0
var head_radii: Vector2 = Vector2.ONE
var head_exp: float = 2.0
var age: int = 0
var hip_c: Vector2 = Vector2.ZERO
var shoulder_c: Vector2 = Vector2.ZERO
var head_c: Vector2 = Vector2.ZERO
var hip_l: Vector2 = Vector2.ZERO
var hip_r: Vector2 = Vector2.ZERO
var knee_l: Vector2 = Vector2.ZERO
var knee_r: Vector2 = Vector2.ZERO
var foot_l: Vector2 = Vector2.ZERO
var foot_r: Vector2 = Vector2.ZERO
var sh_l: Vector2 = Vector2.ZERO
var sh_r: Vector2 = Vector2.ZERO
var elbow_l: Vector2 = Vector2.ZERO
var elbow_r: Vector2 = Vector2.ZERO
var hand_l: Vector2 = Vector2.ZERO
var hand_r: Vector2 = Vector2.ZERO
var outfit: String = ""
var uniform: String = ""
var colors: Dictionary = {}
var short_sleeves: bool = false
var carry: String = ""
var held: String = ""
var unique: String = ""
var unique_hold: String = ""
var accessory: String = ""
var tic: String = ""


static func build(app: Dictionary, char_tier: int, pose: Dictionary) -> CharacterRig:
	var r: CharacterRig = CharacterRig.new()
	r._setup_basics(app, char_tier, pose)
	r._setup_dims()
	r._setup_vertical()
	r._setup_legs()
	r._setup_items()
	r._setup_arms()
	r._setup_colors()
	return r


## true si el brazo derecho (o izquierdo) queda en el lado lejano del cuerpo (se dibuja detrás).
func arm_is_far(right: bool) -> bool:
	var l: Vector2 = lat if right else -lat
	return l.y < -0.05


func _setup_basics(app: Dictionary, char_tier: int, pose: Dictionary) -> void:
	appearance = app
	tier = clampi(char_tier, 1, CharacterStyle.OUTFIT_COUNT)
	var anim: String = str(pose.get("anim", CharacterAnim.DEFAULT_ANIM))
	var frame: int = int(pose.get("frame", 0))
	p = CharacterAnim.params(anim, frame, tier)
	tic = str(pose.get("tic", ""))
	CharacterAnim.apply_tic(p, anim, tic, int(pose.get("tic_frame", frame)))
	var f: Vector2 = pose.get("facing", Vector2.DOWN)
	facing = f.normalized() if f.length_squared() > 0.0001 else Vector2.DOWN
	fwd = CharacterStyle.ground(facing)
	side_dir = Vector2(-facing.y, facing.x)
	lat = CharacterStyle.lateral(side_dir)
	lat_g = CharacterStyle.ground(side_dir)
	side = absf(facing.x)
	front = facing.y
	_setup_look(pose)


func _setup_look(pose: Dictionary) -> void:
	var base: Vector2 = facing
	var wanted: Vector2 = pose.get("look", Vector2.ZERO)
	if tic != OBLIVIOUS_TIC and wanted.length_squared() > 0.0001:
		base = wanted.normalized()
	if tic == STARE_TIC and wanted.length_squared() > 0.0001:
		base = wanted.normalized()
	look = base.rotated(float(p["head_turn"]) * HEAD_TURN_MAX)


func _setup_dims() -> void:
	var shape: Dictionary = CharacterStyle.TIER_SHAPES[tier]
	var build_v: Vector2 = CharacterStyle.BUILDS[int(appearance.get("build", 3))]
	var volume: float = float(appearance.get("volume", 1.0))
	width_scale = build_v.x * volume
	height_scale = build_v.y * sqrt(volume)
	shoulder_half = float(shape["shoulder"]) * width_scale * (1.0 - SIDE_NARROW_SHOULDER * side * side)
	hip_half = float(shape["hip"]) * width_scale * (1.0 - SIDE_NARROW_HIP * side * side)
	torso_h = float(shape["torso"]) * height_scale
	leg_h = float(shape["leg"]) * height_scale
	hunch = float(shape["hunch"]) + float(p["hunch"])
	loose = float(shape["loose"])
	pad = float(shape["pad"])
	uniform = str(appearance.get("uniform", ""))
	if not uniform.is_empty():
		loose = minf(loose, 0.05)
		pad = 0.0
	var head_index: int = int(appearance.get("head", 0))
	var hs: Vector3 = CharacterStyle.HEAD_SHAPES[head_index % CharacterStyle.HEAD_SHAPES.size()]
	age = head_index / CharacterStyle.HEAD_SHAPES.size()
	head_radii = Vector2(hs.x, hs.y) * float(shape["head"]) * sqrt(sqrt(volume))
	head_exp = hs.z


func _setup_vertical() -> void:
	var crouch: float = float(p["crouch"])
	var sit: float = float(p["sit"])
	var leg: float = leg_h * (1.0 - 0.5 * crouch) * (1.0 - 0.45 * sit)
	var torso: float = torso_h * float(p["squash"]) * (1.0 - 0.1 * crouch)
	var lean: float = float(p["lean"])
	hip_c = Vector2(float(p["shake"]), -leg + float(p["bob"]))
	shoulder_c = hip_c + Vector2(0.0, -torso) + fwd * (lean + hunch * 0.6)
	var tilt: float = float(p["head_tilt"])
	var neck: Vector2 = Vector2(0.0, -(head_radii.y * 0.92 + NECK))
	head_c = shoulder_c + neck + fwd * (hunch * 0.9 + lean * 0.3 + tilt * 2.0)
	head_c.y += hunch * 0.65 + tilt * 2.0


func _setup_legs() -> void:
	var crouch: float = float(p["crouch"])
	var sit: float = float(p["sit"])
	var spread: float = hip_half * 0.45 * (1.0 + 0.4 * crouch)
	hip_l = hip_c - lat * spread
	hip_r = hip_c + lat * spread
	var step: Vector2 = fwd * float(p["step"])
	var seat: Vector2 = fwd * 9.0 * sit
	foot_l = -lat_g * spread * 1.1 + step + seat + Vector2(0.0, -float(p["lift_l"]))
	foot_r = lat_g * spread * 1.1 - step + seat + Vector2(0.0, -float(p["lift_r"]))
	var bend: Vector2 = fwd * 5.0 * maxf(crouch, sit) + Vector2(0.0, -3.0 * crouch)
	knee_l = hip_l.lerp(foot_l, 0.5) + bend - lat * 2.0 * crouch
	knee_r = hip_r.lerp(foot_r, 0.5) + bend + lat * 2.0 * crouch


## Qué lleva en las manos: objeto del escalón (§14.5), accesorio de mano o accesorio único.
func _setup_items() -> void:
	unique = str(appearance.get("unique", ""))
	unique_hold = CharacterProps.unique_hold(unique)
	accessory = str(appearance.get("accessory", ""))
	var carries: Array = CharacterStyle.TIER_CARRY[tier]
	carry = str(carries[int(appearance.get("carry_pick", 0)) % carries.size()])
	held = ""
	if tier < CharacterStyle.HANDS_FREE_TIER and CharacterStyle.HANDHELD.has(accessory):
		held = accessory
	if RIGHT_HOLDS.has(unique_hold):
		held = unique
	if held == "cart" or BOTH_HOLDS.has(unique_hold):
		carry = ""
	elif unique_hold == HUG_HOLD:
		carry = "planner"
	elif not held.is_empty() and carry == "box":
		carry = "papers"
	if bool(p["uses_hands"]):
		carry = ""
		held = ""


func _setup_arms() -> void:
	var off: float = shoulder_half * 0.86
	sh_r = shoulder_c + lat * off + Vector2(0.0, 3.0)
	sh_l = shoulder_c - lat * off + Vector2(0.0, 3.0)
	hand_r = _hand(sh_r, lat, p["hand_r"])
	hand_l = _hand(sh_l, -lat, p["hand_l"])
	_apply_item_grips()
	elbow_r = _elbow(sh_r, hand_r, lat)
	elbow_l = _elbow(sh_l, hand_l, -lat)


## v = Vector3(delante, fuera, arriba); `out_dir` = lateral proyectado hacia fuera de ese brazo.
func _hand(shoulder: Vector2, out_dir: Vector2, v: Vector3) -> Vector2:
	var base: Vector2 = shoulder + Vector2(0.0, torso_h * HAND_DROP) + out_dir * 1.5
	return base + fwd * v.x + out_dir * v.y + Vector2(0.0, -v.z)


func _elbow(shoulder: Vector2, hand: Vector2, out_dir: Vector2) -> Vector2:
	var arm: float = torso_h * ARM_LENGTH
	var d: float = shoulder.distance_to(hand)
	var bend: float = sqrt(maxf(0.0, arm * arm * 0.25 - d * d * 0.25))
	var outward: Vector2 = out_dir.normalized() if out_dir.length_squared() > 0.0001 else Vector2.RIGHT
	return shoulder.lerp(hand, 0.5) + outward * bend * 0.8 + Vector2(0.0, bend * 0.3)


## Coloca las manos sobre el objeto transportado (caja con ambas, carpeta abrazada, carrito...).
func _apply_item_grips() -> void:
	var chest: Vector2 = shoulder_c.lerp(hip_c, 0.55)
	match carry:
		"box":
			var c: Vector2 = chest + fwd * 9.0
			hand_l = c - lat * 9.0
			hand_r = c + lat * 9.0
		"folder", "planner":
			hand_l = shoulder_c.lerp(hip_c, 0.45) + fwd * 5.0 - lat * 2.0
		"papers":
			hand_l = hand_l.lerp(chest - lat * 4.0 + fwd * 6.0, 0.7)
	if held == "cart" or unique_hold == "cart":
		var push: Vector2 = shoulder_c.lerp(hip_c, 0.75) + fwd * 13.0
		hand_l = push - lat * 6.0
		hand_r = push + lat * 6.0
	elif unique_hold == "both" or unique_hold == "both_up":
		var up: float = 9.0 if unique_hold == "both_up" else 4.0
		hand_l = chest + fwd * 6.0 - lat * 5.0 + Vector2(0.0, -up)
		hand_r = chest + fwd * 6.0 + lat * 5.0 + Vector2(0.0, -up)
	elif not held.is_empty():
		hand_r = hand_r.lerp(chest + lat * 6.0 + fwd * 5.0, 0.6)


func _setup_colors() -> void:
	var skin_i: int = int(appearance.get("skin", 0))
	var hair_i: int = int(appearance.get("hair_color", 0))
	var pal: Dictionary = CharacterStyle.PALETTES[int(appearance.get("palette", 0))]
	var pick: int = int(appearance.get("carry_pick", 0))
	colors = {
		"skin": CharacterStyle.SKIN_TONES[skin_i], "hair": CharacterStyle.HAIR_COLORS[hair_i],
		"shirt": pal["shirt"], "tie": pal["tie"], "coat": pal["coat"], "trim": Color(),
		"hands": Color(), "cap": Color(), "shoe": CharacterStyle.SHOE_DARK,
	}
	outfit = CharacterStyle.TIER_OUTFITS[tier] if uniform.is_empty() else uniform
	if not uniform.is_empty():
		_uniform_colors()
		return
	_outfit_colors(pal, pick)


func _outfit_colors(pal: Dictionary, pick: int) -> void:
	short_sleeves = outfit == "polo"
	match outfit:
		"hoodie":
			colors["top"] = pal["casual"]
			colors["bottom"] = CharacterStyle.JEANS[pick % CharacterStyle.JEANS.size()]
			colors["shoe"] = CharacterStyle.SNEAKER
		"polo":
			colors["top"] = pal["casual"]
			colors["bottom"] = CharacterStyle.KHAKI[pick % CharacterStyle.KHAKI.size()]
			colors["shoe"] = CharacterStyle.SHOE_BROWN
		"shirt_tie":
			colors["top"] = pal["shirt"]
			colors["bottom"] = pal["trousers"]
		"blazer":
			colors["top"] = pal["blazer"]
			colors["bottom"] = pal["trousers"]
		_:
			colors["top"] = pal["suit"]
			colors["bottom"] = (pal["suit"] as Color).darkened(0.12)
	if outfit == "lux_suit" or outfit == "lux_coat":
		colors["shirt"] = CharacterStyle.WHITE_SHIRT
		colors["trim"] = CharacterStyle.GOLD
	colors["sleeve"] = colors["top"]


func _uniform_colors() -> void:
	var u: Dictionary = CharacterStyle.UNIFORMS.get(uniform, CharacterStyle.UNIFORMS["security"])
	colors["top"] = u["top"]
	colors["sleeve"] = u["top"]
	colors["bottom"] = u["bottom"]
	colors["trim"] = u["trim"]
	colors["cap"] = u["cap"]
	colors["hands"] = u["hands"]
	short_sleeves = uniform == "security"
