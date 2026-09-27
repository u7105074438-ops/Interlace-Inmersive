# character_painter.gd — Personajes vectoriales planos con contorno en cenital 3/4 (§14.2, §14.4–§14.7).
# PROPIETARIO DE: nada (API estática pura; la caché de combinaciones reservadas es derivada de datos).
# ESCUCHA: nada.
class_name CharacterPainter
extends RefCounted

## Contrato (BUILD_NOTES §14): appearance_from_seed() + draw() + draw_portrait(). Lo comparten el
## jugador, los NPC, PERSONNEL y los menús.
## Apariencia (Dictionary): seed, tier, is_named, build 0–5, head 0–19, hair 0–24, skin 0–7,
##   hair_color 0–7, palette 0–11, outfit (vestuario del escalón), accessory (uno de 15), unique
##   (accesorio del nominado), carry_pick, uniform ("" | security | cleaning | maintenance |
##   factory), volume (1.0; Harlan Voss mayor).
## Pose (Dictionary): anim (CharacterAnim.CATALOGUE), frame, facing (Vector2), look (Vector2
##   opcional: hacia dónde mira la cabeza), tic (visual_tic del arquetipo), tic_frame, origin
##   (Vector2, píxeles del canvas), scale (float). El origen es el centro de los pies.

const FPS_PATH := "animacion.fps_base"
const VOLUME_PATH := "arte_personajes.escala_volumen_perfil"
const HAIR_AGE_GREY_CHANCE: Array[float] = [0.0, 0.08, 0.4, 0.9]
## Dirección de arte de los nominados (combinaciones reservadas, §14.4) por accesorio único.
const NAMED_LOOKS: Dictionary = {
	"gold_lapel_pin": {"build": 5, "head": 19, "hair": 23, "hair_color": 7, "palette": 5,
		"volume_profile": "ceo"},
	"signet_ring": {"build": 4, "head": 18, "hair": 8, "hair_color": 6, "palette": 7},
	"thirty_year_pin": {"head": 17, "hair": 20, "hair_color": 6},
	"visitor_lanyard": {"head": 1, "hair": 14},
	"cleaning_cart": {"head": 16, "hair": 15, "hair_color": 6, "build": 1},
	"designer_sunglasses": {"hair": 22, "head": 6},
	"statement_necklace": {"hair": 22, "head": 13, "hair_color": 4},
	"gold_watch": {"hair": 8, "head": 12, "build": 5},
	"noise_cancelling_headphones": {"hair": 10, "head": 0},
	"tool_belt": {"hair": 24, "head": 12, "build": 1},
	"hard_hat": {"build": 5, "head": 7},
	"clutched_laptop": {"hair": 18, "head": 8, "build": 0},
	"red_pen": {"hair": 12, "head": 11, "hair_color": 1},
}
const ARCHETYPE_AGES: Dictionary = {"old_hand": 3, "rookie": 0, "burnout": 2}
## Vestuario de oficio por departamento (solo escalones ≤ 4: los directores van de traje).
const DEPARTMENT_UNIFORMS: Dictionary = {
	"security": "security", "cleaning": "cleaning", "maintenance": "maintenance",
	"factory": "factory",
}
const UNIFORM_TIER_MAX := 4
const UNIFORM_IDS: Array[String] = ["security", "cleaning", "maintenance", "factory"]

static var _named_combos: Dictionary = {}
static var _named_combos_ready: bool = false


# ─── Apariencia ────────────────────────────────────────────────

## Capas de §14.4 deterministas por semilla. `accessory` = accesorio único del nominado ("" si no).
static func appearance_from_seed(seed: int, tier: int, is_named: bool, accessory: String) -> Dictionary:
	var app: Dictionary = _roll_layers(seed, clampi(tier, 1, CharacterStyle.OUTFIT_COUNT), is_named)
	app["unique"] = accessory if is_named else ""
	if is_named:
		_apply_named_look(app, accessory)
	else:
		_avoid_reserved(app)
	return app


static func _roll_layers(seed: int, tier: int, is_named: bool) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	var heads: int = CharacterStyle.HEAD_COUNT - (0 if is_named else CharacterStyle.RESERVED_HEADS)
	var hairs: int = CharacterStyle.HAIR_COUNT - (0 if is_named else CharacterStyle.RESERVED_HAIRS)
	var app: Dictionary = {
		"seed": seed, "tier": tier, "is_named": is_named,
		"build": rng.randi_range(0, CharacterStyle.BUILD_COUNT - 1),
		"head": rng.randi_range(0, heads - 1),
		"hair": rng.randi_range(0, hairs - 1),
		"skin": rng.randi_range(0, CharacterStyle.SKIN_COUNT - 1),
		"palette": rng.randi_range(0, CharacterStyle.PALETTE_COUNT - 1),
		"accessory": CharacterStyle.ACCESSORIES[rng.randi_range(0, CharacterStyle.ACCESSORY_COUNT - 1)],
		"carry_pick": rng.randi_range(0, CharacterStyle.PALETTE_COUNT - 1),
		"outfit": CharacterStyle.TIER_OUTFITS[tier], "uniform": "", "volume": 1.0,
	}
	app["hair_color"] = _roll_hair_color(rng, int(app["head"]))
	return app


static func _roll_hair_color(rng: RandomNumberGenerator, head: int) -> int:
	var age: int = head / CharacterStyle.HEAD_SHAPES.size()
	var natural: int = rng.randi_range(0, CharacterStyle.HAIR_GREY - 1)
	if rng.randf() < HAIR_AGE_GREY_CHANCE[clampi(age, 0, CharacterStyle.HEAD_AGES - 1)]:
		return CharacterStyle.HAIR_WHITE if age >= CharacterStyle.HEAD_AGES - 1 and rng.randf() < 0.5 \
				else CharacterStyle.HAIR_GREY
	return natural


static func _apply_named_look(app: Dictionary, accessory: String) -> void:
	var look: Dictionary = NAMED_LOOKS.get(accessory, {})
	for key: String in look:
		if key != "volume_profile":
			app[key] = look[key]
	var profile: String = str(look.get("volume_profile", ""))
	if profile.is_empty():
		return
	var path: String = VOLUME_PATH + "." + profile
	if Database.has_balance(path):
		app["volume"] = Database.get_balance_float(path)


## Un genérico nunca repite la combinación cabeza+peinado+piel de un nominado.
static func _avoid_reserved(app: Dictionary) -> void:
	var combos: Dictionary = _reserved_combos()
	var generic_hairs: int = CharacterStyle.HAIR_COUNT - CharacterStyle.RESERVED_HAIRS
	var guard: int = generic_hairs
	while combos.has(_combo_key(app)) and guard > 0:
		app["hair"] = (int(app["hair"]) + 1) % generic_hairs
		guard -= 1


static func _combo_key(app: Dictionary) -> String:
	return "%d:%d:%d" % [int(app["head"]), int(app["hair"]), int(app["skin"])]


static func _reserved_combos() -> Dictionary:
	if _named_combos_ready:
		return _named_combos
	if not Database.is_loaded():
		return {}
	for npc: NPCData in Database.get_all_named_npcs():
		var app: Dictionary = _roll_layers(npc.portrait_seed, 1, true)
		_apply_named_look(app, npc.unique_accessory)
		_named_combos[_combo_key(app)] = npc.id
	_named_combos_ready = true
	return _named_combos


## Apariencia completa de un nominado (edad sesgada por arquetipo, vestuario de oficio).
static func appearance_for_named(npc: NPCData, tier: int) -> Dictionary:
	var app: Dictionary = appearance_from_seed(npc.portrait_seed, tier, true, npc.unique_accessory)
	_apply_archetype_age(app, npc.archetype)
	var occupation: OccupationData = Database.get_occupation(npc.occupation)
	if occupation != null:
		app["uniform"] = uniform_for_occupation(occupation.id, tier)
	return app


## Apariencia de un personaje en ejecución (NPCDirector): usa portrait_seed, tier y ocupación.
static func appearance_for_npc(npc: NPCRuntime) -> Dictionary:
	if npc.is_named:
		var data: NPCData = Database.get_named_npc(npc.id)
		if data != null:
			return appearance_for_named(data, npc.tier)
	var app: Dictionary = appearance_from_seed(npc.portrait_seed, npc.tier, npc.is_named,
			npc.unique_accessory)
	_apply_archetype_age(app, npc.archetype)
	app["uniform"] = uniform_for_occupation(npc.occupation_id, npc.tier)
	return app


static func _apply_archetype_age(app: Dictionary, archetype: String) -> void:
	if not ARCHETYPE_AGES.has(archetype):
		return
	var shapes: int = CharacterStyle.HEAD_SHAPES.size()
	var head: int = int(app["head"])
	if head >= CharacterStyle.HEAD_COUNT - CharacterStyle.RESERVED_HEADS:
		return
	app["head"] = head % shapes + shapes * int(ARCHETYPE_AGES[archetype])


## Vestuario de oficio de una ocupación ("" = ropa de oficina del escalón).
static func uniform_for_occupation(occupation_id: String, tier: int) -> String:
	if occupation_id.is_empty() or tier > UNIFORM_TIER_MAX:
		return ""
	var occupation: OccupationData = Database.get_occupation(occupation_id)
	if occupation == null:
		return ""
	var department: String = str(occupation.extra.get("department", ""))
	return str(DEPARTMENT_UNIFORMS.get(department, ""))


## Traduce el id de disfraz de PlayerState ("uniform_cleaning", "cleaning_uniform"...) a capa.
static func uniform_for_disguise(uniform_id: String) -> String:
	for id: String in UNIFORM_IDS:
		if uniform_id.contains(id):
			return id
	return ""


## visual_tic del arquetipo (archetypes.json) para `pose.tic`.
static func tic_for_archetype(archetype_id: String) -> String:
	var data: ArchetypeData = Database.get_archetype(archetype_id)
	return data.visual_tic if data != null else ""


# ─── Animación ─────────────────────────────────────────────────

## Fotogramas por segundo de una animación (animacion.fps_base × multiplicador del catálogo).
static func anim_fps(anim: String) -> float:
	var base: float = Database.get_balance_float(FPS_PATH) if Database.has_balance(FPS_PATH) else 0.0
	return base * float(CharacterAnim.info(anim)["fps"])


static func anim_frames(anim: String) -> int:
	return CharacterAnim.frame_count(anim)


static func make_pose(anim: String, frame: int, facing: Vector2, extra: Dictionary = {}) -> Dictionary:
	var pose: Dictionary = {"anim": anim, "frame": frame, "facing": facing}
	pose.merge(extra, true)
	return pose


# ─── Dibujo ────────────────────────────────────────────────────

## Dibuja el personaje en `canvas` (dentro de su _draw). El transform del canvas queda en identidad.
static func draw(canvas: CanvasItem, appearance: Dictionary, tier: int, pose: Dictionary) -> void:
	var rig: CharacterRig = CharacterRig.build(appearance, tier, pose)
	var s: float = float(pose.get("scale", 1.0))
	canvas.draw_set_transform(pose.get("origin", Vector2.ZERO), float(rig.p["roll"]), Vector2(s, s))
	_draw_shadow(canvas, rig)
	CharacterProps.draw_hand_items(canvas, rig, true)
	if rig.front >= -0.3:
		CharacterHead.draw_back_hair(canvas, rig)
	_draw_arms(canvas, rig, true)
	_draw_legs(canvas, rig)
	CharacterOutfit.draw_torso(canvas, rig)
	CharacterProps.draw_torso_wear(canvas, rig)
	_draw_arms(canvas, rig, false)
	CharacterOutfit.draw_coat(canvas, rig)
	CharacterProps.draw_hand_items(canvas, rig, false)
	CharacterProps.draw_wrist_wear(canvas, rig)
	if rig.front < -0.3:
		CharacterHead.draw_back_hair(canvas, rig)
	CharacterHead.draw(canvas, rig)
	CharacterProps.draw_fx(canvas, rig)
	canvas.draw_set_transform(Vector2.ZERO)


## Foto de PERSONNEL: busto frontal dentro de `rect`.
static func draw_portrait(canvas: CanvasItem, appearance: Dictionary, rect: Rect2) -> void:
	CharacterPortrait.draw(canvas, appearance, rect)


static func _draw_shadow(canvas: CanvasItem, rig: CharacterRig) -> void:
	var r: Vector2 = Vector2(rig.shoulder_half * 1.05 + 3.0, 5.5) * (1.0 + 0.25 * float(rig.p["crouch"]))
	canvas.draw_colored_polygon(CharacterStyle.ellipse(Vector2(0, 1), r, 18), CharacterStyle.SHADOW)


static func _draw_legs(canvas: CanvasItem, rig: CharacterRig) -> void:
	var width: float = CharacterRig.LEG_WIDTH * sqrt(rig.width_scale) * (1.0 + rig.loose)
	var legs: Array[Array] = [[rig.hip_l, rig.knee_l, rig.foot_l], [rig.hip_r, rig.knee_r, rig.foot_r]]
	if rig.foot_l.y > rig.foot_r.y:
		legs.reverse()
	for leg: Array in legs:
		var foot: Vector2 = leg[2]
		CharacterStyle.limb(canvas, PackedVector2Array([leg[0], leg[1], foot + Vector2(0, -2)]),
				width, rig.colors["bottom"])
		var shoe_c: Vector2 = foot + rig.fwd * 2.0 + Vector2(0, -0.5)
		var shoe_r: Vector2 = Vector2(3.6 + 1.6 * rig.side, 2.6)
		CharacterStyle.fill(canvas, CharacterStyle.ellipse(shoe_c, shoe_r, 12), rig.colors["shoe"])


## Brazos del lado lejano (far = true, antes del torso) o cercano (después).
static func _draw_arms(canvas: CanvasItem, rig: CharacterRig, far: bool) -> void:
	for right: bool in [false, true]:
		if rig.arm_is_far(right) != far:
			continue
		var sh: Vector2 = rig.sh_r if right else rig.sh_l
		var el: Vector2 = rig.elbow_r if right else rig.elbow_l
		var hand: Vector2 = rig.hand_r if right else rig.hand_l
		_draw_arm(canvas, rig, sh, el, hand)


static func _draw_arm(canvas: CanvasItem, rig: CharacterRig, sh: Vector2, el: Vector2, hand: Vector2) -> void:
	var width: float = CharacterRig.ARM_WIDTH * sqrt(rig.width_scale) * (1.0 + rig.loose * 0.8)
	var sleeve: Color = rig.colors["sleeve"]
	var skin: Color = rig.colors["skin"]
	if rig.short_sleeves:
		CharacterStyle.limb(canvas, PackedVector2Array([el, hand]), width * 0.78, skin)
		CharacterStyle.limb(canvas, PackedVector2Array([sh, el]), width, sleeve)
	else:
		CharacterStyle.limb(canvas, PackedVector2Array([sh, el, hand]), width, sleeve)
	var glove: Color = rig.colors["hands"]
	CharacterStyle.circle(canvas, hand, CharacterRig.HAND_RADIUS, glove if glove.a > 0.0 else skin)
