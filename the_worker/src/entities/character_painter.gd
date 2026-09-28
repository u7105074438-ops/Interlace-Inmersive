# character_painter.gd — Personajes vectoriales planos con contorno en cenital 3/4 (§14.2, §14.4–§14.7).
# PROPIETARIO DE: la caché LRU de poses (mallas CharacterCanvas), la de fotos y fondos de foto, y la de combinaciones reservadas (derivadas de datos).
# ESCUCHA: nada.
class_name CharacterPainter
extends RefCounted

## Contrato (BUILD_NOTES §14): appearance_from_seed() + draw() + draw_portrait(). Lo comparten el
## jugador, los NPC, PERSONNEL y los menús.
## Apariencia (Dictionary): seed, tier, is_named, presentation ("f"/"m"), build 0–5, head 0–19,
##   hair 0–24, skin 0–7, hair_color 0–7, palette 0–11, outfit (vestuario del escalón), accessory
##   (uno de 15), unique (accesorio del nominado), carry_pick, uniform ("" | security | cleaning |
##   maintenance | factory), volume (1.0; Harlan Voss mayor).
## Pose (Dictionary): anim (CharacterAnim.CATALOGUE), frame, facing (Vector2), look (Vector2
##   opcional: hacia dónde mira la cabeza), tic (visual_tic del arquetipo), tic_frame, seated
##   (bool: cualquier gesto no locomotor —móvil a escondidas, bostezo, charla...— hecho sentado),
##   origin (Vector2, píxeles del canvas), scale (float). El origen es el centro de los pies; en
##   las poses sentadas, el punto del suelo bajo el asiento (ver seat_origin()).
## Rendimiento: cada combinación apariencia + escalón + pose clave se graba una vez
## (CharacterCanvas; dirección y mirada cuantizadas a 8 rumbos) y se tesela en una malla (rellenos
## + contornos suavizados con colores por vértice): cada redibujado es UNA llamada de dibujo
## (draw_mesh), nítida a cualquier zoom. El teselado gasta como mucho
## arte_personajes.teselado_ms_por_fotograma por fotograma: una pose aún sin malla se dibuja con
## su lista de órdenes (mismo aspecto, una llamada por trazo) y su lienzo se redibuja al fotograma
## siguiente, sin tirones al llenarse la planta. Caché LRU acotada por número de poses
## (arte_personajes.cache_poses) y por memoria (arte_personajes.cache_mallas_kb); al pasarse
## descarta las poses menos usadas hasta quedar en el 90 %. Un lienzo retiene (metadato) las mallas
## que dibujó hasta su siguiente redibujo: descartar una pose que sigue en pantalla nunca deja
## órdenes apuntando a una malla liberada. set_reference_mode(true) (solo QA) no tesela nunca: el
## dibujo anterior, una orden de CanvasItem por trazo, para comparar llamadas, tiempos y píxeles.

const FPS_PATH := "animacion.fps_base"
const VOLUME_PATH := "arte_personajes.escala_volumen_perfil"
const CACHE_PATH := "arte_personajes.cache_poses"
const CACHE_BYTES_PATH := "arte_personajes.cache_mallas_kb"
const PORTRAIT_CACHE_PATH := "arte_personajes.cache_retratos"
const TESSELLATION_PATH := "arte_personajes.teselado_ms_por_fotograma"
## Topes provisionales de las cachés si balance.json aún no está cargado (no se memorizan).
const CACHE_FALLBACK := 256
const CACHE_KB_FALLBACK := 8192
const PORTRAIT_FALLBACK := 64
const TESSELLATION_MS_FALLBACK := 4.0
## Presupuesto de teselado: sin leer de balance.json / sin límite.
const BUDGET_UNREAD := -2
const BUDGET_UNLIMITED := -1
const USEC_PER_MS := 1000.0
## Fracción de la caché que se conserva tras un vaciado parcial (vaciados pequeños: sin tirones).
const CACHE_KEEP := 0.9
## Clave reservada de cada cubo de apariencia: la clave con la que está en _poses (para borrarlo).
const BUCKET_APP := &"app"
## Topes del memo de claves: claves brutas memorizadas (clave bruta → id canónico) y firmas de
## esqueleto (firma → id, ~0,6 KB cada una). Al llegar a uno se vacía solo ese memo: los ids nunca
## se reutilizan (contador), así la caché de poses sigue siendo válida y nunca se vacía entera en
## pleno juego (una pose con un id que ya no se vuelve a calcular la acaba descartando el LRU).
const CANON_LIMIT := 16384
const CANON_SIG_LIMIT := 4096
## Metadato del lienzo con las grabaciones de su última pasada de dibujo: [fotograma, grabaciones...].
const HELD_META := &"_character_recordings"
const HAIR_AGE_GREY_CHANCE: Array[float] = [0.0, 0.08, 0.4, 0.9]
const DIRECTION_STEPS := 8
const NO_LOOK := -1
const KEY_FRAMES := 16
## Dirección de arte de los 23 nominados (combinaciones reservadas, §14.4) por accesorio único.
const NAMED_LOOKS: Dictionary = {
	"oversized_mug": {"presentation": "f", "build": 1, "head": 5, "hair": 22, "hair_color": 3,
		"skin": 1, "palette": 5, "accessory": ""},
	"employee_of_month_pin": {"presentation": "m", "build": 2, "head": 3, "hair": 4, "hair_color": 2,
		"skin": 0, "palette": 8, "accessory": "glasses"},
	"noise_cancelling_headphones": {"presentation": "m", "build": 3, "head": 0, "hair": 7,
		"hair_color": 1, "skin": 4, "palette": 1, "accessory": ""},
	"colour_coded_planner": {"presentation": "f", "build": 2, "head": 1, "hair": 12, "hair_color": 0,
		"skin": 2, "palette": 3, "accessory": ""},
	"thirty_year_pin": {"presentation": "m", "build": 1, "head": 17, "hair": 20, "hair_color": 6,
		"skin": 1, "palette": 2, "accessory": ""},
	"visitor_lanyard": {"presentation": "f", "build": 0, "head": 1, "hair": 14, "hair_color": 5,
		"skin": 0, "palette": 6, "accessory": ""},
	"stopwatch": {"presentation": "m", "build": 4, "head": 13, "hair": 18, "hair_color": 1,
		"skin": 2, "palette": 9, "accessory": ""},
	"glasses_chain": {"presentation": "f", "build": 2, "head": 12, "hair": 15, "hair_color": 6,
		"skin": 3, "palette": 4, "accessory": ""},
	"paperback_novel": {"presentation": "m", "build": 1, "head": 9, "hair": 3, "hair_color": 1,
		"skin": 5, "palette": 0, "accessory": ""},
	"heavy_flashlight": {"presentation": "f", "build": 4, "head": 8, "hair": 15, "hair_color": 4,
		"skin": 0, "palette": 1, "accessory": ""},
	"cleaning_cart": {"presentation": "f", "build": 1, "head": 16, "hair": 10, "hair_color": 7,
		"skin": 3, "palette": 2, "accessory": ""},
	"tool_belt": {"presentation": "m", "build": 1, "head": 11, "hair": 24, "hair_color": 2,
		"skin": 2, "palette": 3, "accessory": ""},
	"hard_hat": {"presentation": "m", "build": 5, "head": 7, "hair": 19, "hair_color": 5,
		"skin": 1, "palette": 4, "accessory": ""},
	"designer_sunglasses": {"presentation": "f", "build": 4, "head": 6, "hair": 13, "hair_color": 0,
		"skin": 1, "palette": 5, "accessory": ""},
	"pocket_ledger": {"presentation": "m", "build": 0, "head": 5, "hair": 9, "hair_color": 0,
		"skin": 2, "palette": 11, "accessory": ""},
	"red_pen": {"presentation": "f", "build": 2, "head": 14, "hair": 16, "hair_color": 6,
		"skin": 2, "palette": 8, "accessory": "glasses"},
	"clutched_laptop": {"presentation": "m", "build": 0, "head": 8, "hair": 18, "hair_color": 2,
		"skin": 1, "palette": 10, "accessory": "glasses"},
	"twin_phones": {"presentation": "f", "build": 2, "head": 2, "hair": 12, "hair_color": 4,
		"skin": 4, "palette": 7, "accessory": ""},
	"gold_watch": {"presentation": "m", "build": 5, "head": 10, "hair": 8, "hair_color": 1,
		"skin": 6, "palette": 2, "accessory": ""},
	"statement_necklace": {"presentation": "f", "build": 3, "head": 11, "hair": 17, "hair_color": 4,
		"skin": 0, "palette": 9, "accessory": ""},
	"signet_ring": {"presentation": "m", "build": 4, "head": 18, "hair": 18, "hair_color": 6,
		"skin": 0, "palette": 7, "accessory": ""},
	"gold_lapel_pin": {"presentation": "m", "build": 5, "head": 19, "hair": 23, "hair_color": 6,
		"skin": 5, "palette": 0, "accessory": "", "volume_profile": "ceo"},
	"steno_pad": {"presentation": "f", "build": 2, "head": 15, "hair": 15, "hair_color": 1,
		"skin": 6, "palette": 4, "accessory": "glasses"},
}
const ARCHETYPE_AGES: Dictionary = {"old_hand": 3, "rookie": 0, "burnout": 2}
## Vestuario de oficio por departamento (solo escalones ≤ 4: los directores van de traje).
const DEPARTMENT_UNIFORMS: Dictionary = {
	"security": "security", "cleaning": "cleaning", "maintenance": "maintenance",
	"factory": "factory",
}
const UNIFORM_TIER_MAX := 4
const UNIFORM_IDS: Array[String] = ["security", "cleaning", "maintenance", "factory"]
const SIT_ANIMS: Array[String] = ["sit", "sit_type", "type_intense"]

static var _named_combos: Dictionary = {}
static var _named_combos_ready: bool = false
static var _poses: Dictionary = {}
static var _pose_count: int = 0
static var _pose_bytes: int = 0
## Poses en caché aún sin malla (se dibujan con su lista de órdenes hasta teselarlas).
static var _pending: int = 0
## Diagnóstico de la caché de poses: aciertos, fallos (grabaciones) y poses descartadas.
static var _hits: int = 0
static var _misses: int = 0
static var _evicted: int = 0
## Orden LRU de las poses en caché (grabación → [cubo, clave]; la primera es la usada hace más tiempo).
static var _lru: Dictionary = {}
## Clave bruta de pose (anim, fotograma, rumbos, escalón, tic, fotograma de tic, sentado) → id
## canónico: poses brutas distintas que dan el MISMO esqueleto comparten grabación.
static var _canon_of_raw: Dictionary = {}
static var _canon_ids: Dictionary = {}
static var _next_canon_id: int = 0
static var _canon_raw_max: int = CANON_LIMIT
static var _canon_sig_max: int = CANON_SIG_LIMIT
## Veces que se ha llegado a un tope del memo de claves (diagnóstico).
static var _canon_resets: int = 0
static var _tick: int = 0
static var _portraits: Dictionary = {}
static var _portrait_backgrounds: Dictionary = {}
static var _cache_max: int = 0
static var _bytes_max: int = 0
static var _portrait_max: int = 0
static var _fps_base: float = -1.0
static var _reference_mode: bool = false
static var _budget_usec: int = BUDGET_UNREAD
static var _budget_frame: int = -1
static var _budget_spent: int = 0
## Lienzos que dibujaron alguna pose aún sin malla: id de instancia → WeakRef (se redibujan al
## fotograma siguiente).
static var _redraw_next: Dictionary = {}
static var _redraw_hooked: bool = false


# ─── Apariencia ────────────────────────────────────────────────

## Capas de §14.4 deterministas por semilla. `accessory` = accesorio único del nominado ("" si no).
static func appearance_from_seed(seed: int, tier: int, is_named: bool, accessory: String) -> Dictionary:
	return _build_appearance(seed, tier, is_named, accessory, "", "")


## Genéricos: presentación ("" = por semilla) y edad por arquetipo ANTES de evitar las
## combinaciones de los nominados; nominados: su dirección de arte completa (NAMED_LOOKS).
static func _build_appearance(seed: int, tier: int, is_named: bool, accessory: String,
		presentation: String, archetype: String) -> Dictionary:
	var app: Dictionary = _roll_layers(seed, clampi(tier, 1, CharacterStyle.OUTFIT_COUNT), is_named,
			presentation)
	app["unique"] = accessory if is_named else ""
	if is_named:
		_apply_named_look(app, accessory)
	else:
		_apply_archetype_age(app, archetype)
		_avoid_reserved(app)
	return app


static func _roll_layers(seed: int, tier: int, is_named: bool, presentation: String) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	var heads: int = CharacterStyle.HEAD_COUNT - (0 if is_named else CharacterStyle.RESERVED_HEADS)
	var app: Dictionary = {
		"seed": seed, "tier": tier, "is_named": is_named,
		"build": rng.randi_range(0, CharacterStyle.BUILD_COUNT - 1),
		"head": rng.randi_range(0, heads - 1),
		"hair": rng.randi_range(0, CharacterStyle.HAIR_COUNT - 1),
		"skin": rng.randi_range(0, CharacterStyle.SKIN_COUNT - 1),
		"palette": rng.randi_range(0, CharacterStyle.PALETTE_COUNT - 1),
		"accessory": CharacterStyle.ACCESSORIES[rng.randi_range(0, CharacterStyle.ACCESSORY_COUNT - 1)],
		"carry_pick": rng.randi_range(0, CharacterStyle.PALETTE_COUNT - 1),
		"outfit": CharacterStyle.TIER_OUTFITS[tier], "uniform": "", "volume": 1.0,
	}
	var rolled_f: bool = rng.randf() < 0.5
	app["presentation"] = presentation if not presentation.is_empty() else \
			(CharacterStyle.PRESENTATION_F if rolled_f else CharacterStyle.PRESENTATION_M)
	var pool: Array[int] = hair_pool(str(app["presentation"]))
	app["hair"] = pool[int(app["hair"]) % pool.size()]
	app["hair_color"] = _roll_hair_color(rng, int(app["head"]))
	_ensure_contrast(app)
	return app


## El pelo no puede confundirse con la prenda de arriba (de espaldas serían una sola mancha):
## si se parecen demasiado, pasa a la siguiente paleta de vestuario.
static func _ensure_contrast(app: Dictionary) -> void:
	var hair: Color = CharacterStyle.HAIR_COLORS[int(app["hair_color"])]
	for i: int in CharacterStyle.PALETTE_COUNT:
		var top: Color = CharacterStyle.top_color(int(app["tier"]), int(app["palette"]))
		if Vector3(hair.r - top.r, hair.g - top.g, hair.b - top.b).length() >= CharacterStyle.MIN_HAIR_CONTRAST:
			return
		app["palette"] = (int(app["palette"]) + 1) % CharacterStyle.PALETTE_COUNT


## Peinados genéricos permitidos para una presentación (sin los reservados de los nominados).
static func hair_pool(presentation: String) -> Array[int]:
	return CharacterStyle.HAIRS_F if presentation == CharacterStyle.PRESENTATION_F else CharacterStyle.HAIRS_M


## Presentación a partir del nombre de pila ("Brenda Croft" → "f"); "" si no hay nombre.
static func presentation_for_name(full_name: String) -> String:
	var first: String = full_name.strip_edges().get_slice(" ", 0)
	if first.is_empty():
		return ""
	return CharacterStyle.PRESENTATION_F if CharacterStyle.FEMININE_FIRST_NAMES.has(first) \
			else CharacterStyle.PRESENTATION_M


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


## Un genérico nunca repite la combinación cabeza+peinado+piel de un nominado: cambia de
## peinado dentro de su repertorio (misma presentación) hasta salir de las reservadas.
static func _avoid_reserved(app: Dictionary) -> void:
	var combos: Dictionary = _reserved_combos()
	var pool: Array[int] = hair_pool(str(app.get("presentation", CharacterStyle.PRESENTATION_M)))
	var at: int = maxi(pool.find(int(app["hair"])), 0)
	var guard: int = pool.size()
	while combos.has(_combo_key(app)) and guard > 0:
		at = (at + 1) % pool.size()
		app["hair"] = pool[at]
		guard -= 1


static func _combo_key(app: Dictionary) -> String:
	return "%d:%d:%d" % [int(app["head"]), int(app["hair"]), int(app["skin"])]


## Combinaciones cabeza:peinado:piel de los nominados (id de nominado por combinación).
static func reserved_combos() -> Dictionary:
	return _reserved_combos().duplicate()


static func _reserved_combos() -> Dictionary:
	if _named_combos_ready:
		return _named_combos
	var named: Array[NPCData] = Database.get_all_named_npcs()
	for npc: NPCData in named:
		var app: Dictionary = _roll_layers(npc.portrait_seed, 1, true, "")
		_apply_named_look(app, npc.unique_accessory)
		_named_combos[_combo_key(app)] = npc.id
	_named_combos_ready = not named.is_empty()
	return _named_combos


## Apariencia completa de un nominado (dirección de arte propia, vestuario de oficio).
static func appearance_for_named(npc: NPCData, tier: int) -> Dictionary:
	var app: Dictionary = appearance_from_seed(npc.portrait_seed, tier, true, npc.unique_accessory)
	var occupation: OccupationData = Database.get_occupation(npc.occupation)
	if occupation != null:
		app["uniform"] = uniform_for_occupation(occupation.id, tier)
	return app


## Apariencia de un personaje en ejecución (NPCDirector): portrait_seed, escalón, ocupación, nombre
## de pila (presentación) y arquetipo (edad).
static func appearance_for_npc(npc: NPCRuntime) -> Dictionary:
	if npc.is_named:
		var data: NPCData = Database.get_named_npc(npc.id)
		if data != null:
			return appearance_for_named(data, npc.tier)
	var app: Dictionary = _build_appearance(npc.portrait_seed, npc.tier, npc.is_named,
			npc.unique_accessory, presentation_for_name(npc.name), npc.archetype)
	app["uniform"] = uniform_for_occupation(npc.occupation_id, npc.tier)
	return app


## Edad por arquetipo (cabeza = forma + 5 × edad), sin caer en las cabezas reservadas.
static func _apply_archetype_age(app: Dictionary, archetype: String) -> void:
	if not ARCHETYPE_AGES.has(archetype):
		return
	var shapes: int = CharacterStyle.HEAD_SHAPES.size()
	var aged: int = int(app["head"]) % shapes + shapes * int(ARCHETYPE_AGES[archetype])
	app["head"] = mini(aged, CharacterStyle.HEAD_COUNT - CharacterStyle.RESERVED_HEADS - 1)


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
	if _fps_base < 0.0:
		if not Database.has_balance(FPS_PATH):
			return 0.0
		_fps_base = Database.get_balance_float(FPS_PATH)
	return _fps_base * float(CharacterAnim.info(anim)["fps"])


static func anim_frames(anim: String) -> int:
	return CharacterAnim.frame_count(anim)


static func make_pose(anim: String, frame: int, facing: Vector2, extra: Dictionary = {}) -> Dictionary:
	var pose: Dictionary = {"anim": anim, "frame": frame, "facing": facing}
	pose.merge(extra, true)
	return pose


## Origen de la pose sentada para que la cadera caiga sobre el centro del asiento de la silla.
static func seat_origin(chair_center: Vector2, appearance: Dictionary, tier: int) -> Vector2:
	var t: int = clampi(tier, 1, CharacterStyle.OUTFIT_COUNT)
	var build: Vector2 = CharacterStyle.BUILDS[int(appearance.get("build", 3))]
	var leg: float = float(CharacterStyle.TIER_SHAPES[t]["leg"]) * build.y * sqrt(float(appearance.get("volume", 1.0)))
	return chair_center + Vector2(0.0, leg * (1.0 - CharacterRig.SIT_LEG_DROP) * 0.8)


# ─── Dibujo ────────────────────────────────────────────────────

## Dibuja el personaje en `canvas` (dentro de su _draw): una llamada de dibujo (su malla). El
## transform del canvas queda en identidad.
static func draw(canvas: CanvasItem, appearance: Dictionary, tier: int, pose: Dictionary) -> void:
	var rec: CharacterCanvas = pose_recording(appearance, tier, pose)
	var s: float = float(pose.get("scale", 1.0))
	canvas.draw_set_transform(pose.get("origin", Vector2.ZERO), rec.roll, Vector2(s, s))
	rec.replay(canvas)
	canvas.draw_set_transform(Vector2.ZERO)
	_after_replay(canvas, rec)


## Foto de PERSONNEL: busto frontal dentro de `rect` (fondo de la banda + busto: dos mallas).
static func draw_portrait(canvas: CanvasItem, appearance: Dictionary, rect: Rect2) -> void:
	var tier: int = clampi(int(appearance.get("tier", 1)), 1, CharacterStyle.OUTFIT_COUNT)
	if _reference_mode:
		CharacterPortrait.draw_background(canvas, rect, tier)
	else:
		var bg: CharacterCanvas = _portrait_background(tier)
		canvas.draw_set_transform_matrix(Transform2D(0.0, rect.size, 0.0, rect.position))
		bg.replay(canvas)
		_after_replay(canvas, bg)
	var rec: CharacterCanvas = portrait_recording(appearance)
	canvas.draw_set_transform_matrix(CharacterPortrait.design_transform(rect))
	rec.replay(canvas)
	canvas.draw_set_transform(Vector2.ZERO)
	_after_replay(canvas, rec)


## Busto grabado (en caché LRU, arte_personajes.cache_retratos) de una apariencia.
static func portrait_recording(appearance: Dictionary) -> CharacterCanvas:
	var rec: CharacterCanvas = _portraits.get([appearance])
	if rec == null:
		rec = CharacterCanvas.new()
		CharacterPortrait.record(rec, appearance)
		rec.finish()
		if _portraits.size() >= _portrait_limit():
			_evict_oldest_portrait()
		_portraits[[appearance.duplicate(true)]] = rec
	_tick += 1
	rec.last_used = _tick
	_try_build(rec, false)
	return rec


static func _evict_oldest_portrait() -> void:
	var oldest: Array = []
	var oldest_tick: int = _tick + 1
	for key: Array in _portraits:
		var used: int = (_portraits[key] as CharacterCanvas).last_used
		if used < oldest_tick:
			oldest_tick = used
			oldest = key
	_portraits.erase(oldest)


## Fondo de la foto de un escalón en el cuadrado unidad (se escala al rectángulo al dibujar).
static func _portrait_background(tier: int) -> CharacterCanvas:
	var rec: CharacterCanvas = _portrait_backgrounds.get(tier)
	if rec == null:
		rec = CharacterCanvas.new()
		CharacterPortrait.record_background(rec, tier)
		rec.finish()
		_try_build(rec, true)
		_portrait_backgrounds[tier] = rec
	return rec


## Las órdenes del lienzo apuntan a la malla hasta su próximo redibujo: el lienzo guarda las
## grabaciones de su pasada de dibujo actual para que la caché pueda descartarlas sin liberar
## una malla que aún se dibuja. Una pasada nueva (otro fotograma) sustituye la lista.
static func _hold(canvas: CanvasItem, rec: CharacterCanvas) -> void:
	if rec.get_mesh() == null:
		return
	var frame: int = Engine.get_process_frames()
	var held: Array = canvas.get_meta(HELD_META, []) as Array
	if held.is_empty() or int(held[0]) != frame:
		held = [frame]
		canvas.set_meta(HELD_META, held)
	held.append(rec)


## Tras reproducir una grabación: retener su malla o, si aún no la tiene, pedir que el lienzo se
## redibuje al fotograma siguiente (entonces se teselará con el presupuesto de ese fotograma).
static func _after_replay(canvas: CanvasItem, rec: CharacterCanvas) -> void:
	if rec.is_built():
		_hold(canvas, rec)
	elif not _reference_mode:
		_redraw_later(canvas)


static func _redraw_later(canvas: CanvasItem) -> void:
	_redraw_next[canvas.get_instance_id()] = weakref(canvas)
	if _redraw_hooked:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_redraw_hooked = true
	tree.process_frame.connect(func() -> void: CharacterPainter._redraw_waiting(), CONNECT_ONE_SHOT)


static func _redraw_waiting() -> void:
	_redraw_hooked = false
	var waiting: Dictionary = _redraw_next
	_redraw_next = {}
	for id: int in waiting:
		var canvas: CanvasItem = (waiting[id] as WeakRef).get_ref() as CanvasItem
		if canvas != null and canvas.is_inside_tree():
			canvas.queue_redraw()


## Tesela `rec` si queda presupuesto en este fotograma (siempre si `force`; al menos una pose por
## fotograma, así siempre avanza). Nunca en el modo de referencia. Actualiza la memoria de la
## caché (lista de órdenes → malla).
static func _try_build(rec: CharacterCanvas, force: bool) -> void:
	if rec.is_built() or _reference_mode:
		return
	var frame: int = Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_spent = 0
	var budget: int = _tessellation_budget()
	if not force and budget != BUDGET_UNLIMITED and _budget_spent > 0 and _budget_spent >= budget:
		return
	var start: int = Time.get_ticks_usec()
	var before: int = rec.byte_size()
	rec.build_mesh()
	_budget_spent += Time.get_ticks_usec() - start
	if _lru.has(rec):
		_pose_bytes += rec.byte_size() - before
		_pending -= 1


static func _tessellation_budget() -> int:
	if _budget_usec == BUDGET_UNREAD:
		var ms: float = Database.get_balance_float(TESSELLATION_PATH) if Database.has_balance(TESSELLATION_PATH) \
				else TESSELLATION_MS_FALLBACK
		_budget_usec = roundi(ms * USEC_PER_MS)
	return _budget_usec


## Tests/QA: tope de teselado por fotograma en ms (< 0 = sin límite; 0 = el de balance.json).
static func set_tessellation_budget_ms(ms: float) -> void:
	if ms < 0.0:
		_budget_usec = BUDGET_UNLIMITED
	elif ms == 0.0:
		_budget_usec = BUDGET_UNREAD
	else:
		_budget_usec = roundi(ms * USEC_PER_MS)


## QA: true = camino de referencia (una orden de CanvasItem por trazo, como antes de las mallas);
## false = una malla por pose (juego). Cambiar de camino vacía las cachés.
static func set_reference_mode(enabled: bool) -> void:
	if enabled == _reference_mode:
		return
	_reference_mode = enabled
	clear_cache()


static func is_reference_mode() -> bool:
	return _reference_mode


## Grabación (en caché) de una pose: la graba la primera vez que se pide y la tesela en cuanto hay
## presupuesto (replay() dibuja la malla o, mientras tanto, la lista de órdenes). Caché en dos
## niveles: apariencia → {clave entera de la pose → CharacterCanvas} (+ BUCKET_APP). La pose se
## reduce a lo que cambia el dibujo: fotograma en su ciclo, rumbos cuantizados a 8 direcciones y
## fotograma de tic solo si la animación lo usa.
static func pose_recording(appearance: Dictionary, tier: int, pose: Dictionary) -> CharacterCanvas:
	var anim: String = str(pose.get("anim", CharacterAnim.DEFAULT_ANIM))
	if not CharacterAnim.has_anim(anim):
		anim = CharacterAnim.DEFAULT_ANIM
	var frame: int = posmod(int(pose.get("frame", 0)), CharacterAnim.frame_count(anim))
	var tic: String = str(pose.get("tic", ""))
	if not CharacterAnim.TIC_ANIMS.has(anim):
		tic = ""
	var tic_f: int = posmod(int(pose.get("tic_frame", frame)), CharacterAnim.TIC_CYCLE) if not tic.is_empty() else 0
	var facing_i: int = maxi(_direction_index(pose.get("facing", Vector2.DOWN)), 0)
	var look_i: int = _direction_index(pose.get("look", Vector2.ZERO))
	var seated: bool = bool(pose.get("seated", false))
	var raw: int = _pose_key(CharacterAnim.anim_index(anim), frame, facing_i, look_i, tier,
			CharacterAnim.TICS.find(tic) + 1, tic_f) * 2 + (1 if seated else 0)
	var key: int = int(_canon_of_raw.get(raw, -1))
	if key < 0:
		key = _canonical_key(raw, appearance, tier, _clean_pose(anim, frame, facing_i, look_i, tic, tic_f, seated))
	var bucket: Dictionary = _poses.get([appearance], {})
	var rec: CharacterCanvas = bucket.get(key)
	if rec != null:
		var ref: Array = _lru[rec]
		_lru.erase(rec)
		_lru[rec] = ref
		_hits += 1
		_try_build(rec, false)
		return rec
	_misses += 1
	rec = CharacterCanvas.new()
	_record(rec, appearance, tier, _clean_pose(anim, frame, facing_i, look_i, tic, tic_f, seated))
	rec.finish()
	_insert(appearance, bucket, key, rec)
	return rec


## Pose reducida a lo que cambia el dibujo (rumbos cuantizados), la que se graba.
static func _clean_pose(anim: String, frame: int, facing_i: int, look_i: int, tic: String, tic_f: int,
		seated: bool) -> Dictionary:
	var clean: Dictionary = {"anim": anim, "frame": frame, "facing": _direction_of(facing_i), "tic": tic,
			"tic_frame": tic_f, "seated": seated}
	if look_i != NO_LOOK:
		clean["look"] = _direction_of(look_i)
	return clean


## Mete una grabación nueva en la caché (la más recién usada), la tesela si hay presupuesto y
## vacía lo que sobre.
static func _insert(appearance: Dictionary, bucket: Dictionary, key: int, rec: CharacterCanvas) -> void:
	if bucket.is_empty():
		var app_key: Array = [appearance.duplicate(true)]
		bucket[BUCKET_APP] = app_key
		_poses[app_key] = bucket
	bucket[key] = rec
	_lru[rec] = [bucket, key]
	_pose_count += 1
	_pose_bytes += rec.byte_size()
	_pending += 1
	_try_build(rec, false)
	_evict_if_full()


## Id canónico de una pose: lo que de verdad lee el dibujo, sacado del propio esqueleto
## (CharacterRig): escalón, rumbo, mirada resuelta (tic, pose.look y head_turn), tic "sin girar la
## cabeza" (cascos) y todos los parámetros resueltos de la pose (fotograma clave + tic + sentado).
## No depende de la apariencia. Los fotogramas clave que se mantienen varios fotogramas y los
## fotogramas de tic que no cambian nada comparten grabación: el dibujo es el mismo por
## construcción. Se memoriza por clave bruta.
static func _canonical_key(raw: int, appearance: Dictionary, tier: int, clean: Dictionary) -> int:
	if _canon_of_raw.size() >= _canon_raw_max:
		_canon_resets += 1
		_canon_of_raw.clear()
	if _canon_ids.size() >= _canon_sig_max:
		_canon_resets += 1
		_canon_ids.clear()
	var sig: Array = _rig_signature(CharacterRig.build(appearance, tier, clean))
	var id: int = int(_canon_ids.get(sig, -1))
	if id < 0:
		id = _next_canon_id
		_next_canon_id += 1
		_canon_ids[sig] = id
	_canon_of_raw[raw] = id
	return id


## Firma compacta y exacta del esqueleto: números en float64 (escalón, rumbo, mirada, cascos y los
## parámetros de la pose en su orden fijo, CharacterAnim.DEFAULTS) + textos (expresión, efectos,
## objetos); una clave ajena a DEFAULTS entra con su nombre.
static func _rig_signature(rig: CharacterRig) -> Array:
	var nums: PackedFloat64Array = PackedFloat64Array([rig.tier, rig.facing.x, rig.facing.y, rig.look.x, rig.look.y,
			1.0 if rig.tic == CharacterRig.OBLIVIOUS_TIC else 0.0, rig.p.size()])
	var words: String = ""
	for k: Variant in rig.p:
		var v: Variant = rig.p[k]
		if not CharacterAnim.DEFAULTS.has(k):
			words += str(k) + "="
		match typeof(v):
			TYPE_FLOAT, TYPE_INT, TYPE_BOOL:
				nums.append(float(v))
			TYPE_VECTOR3:
				var v3: Vector3 = v
				nums.append_array(PackedFloat64Array([v3.x, v3.y, v3.z]))
			_:
				words += str(v) + "|"
	return [nums, words]


static func _pose_key(anim_i: int, frame: int, facing_i: int, look_i: int, tier: int, tic_i: int,
		tic_f: int) -> int:
	var key: int = anim_i * KEY_FRAMES + frame
	key = key * DIRECTION_STEPS + facing_i
	key = key * (DIRECTION_STEPS + 1) + look_i + 1
	key = key * (CharacterStyle.OUTFIT_COUNT + 1) + clampi(tier, 0, CharacterStyle.OUTFIT_COUNT)
	key = key * (CharacterAnim.TICS.size() + 1) + tic_i
	return key * CharacterAnim.TIC_CYCLE + tic_f


static func _direction_index(v: Vector2) -> int:
	if v.length_squared() < 0.0001:
		return NO_LOOK
	return posmod(roundi(v.angle() / (TAU / float(DIRECTION_STEPS))), DIRECTION_STEPS)


static func _direction_of(index: int) -> Vector2:
	return Vector2.from_angle(float(index) * TAU / float(DIRECTION_STEPS))


## Caché acotada (arte_personajes.cache_poses poses y cache_mallas_kb de mallas): al pasarse de
## cualquiera de los dos topes descarta las poses usadas hace más tiempo (LRU: las primeras de
## _lru) hasta quedar en el 90 % de ambos (CACHE_KEEP). Coste proporcional a las poses descartadas.
static func _evict_if_full() -> void:
	var limit: float = float(_cache_limit())
	var budget: float = float(_byte_limit())
	if float(_pose_count) <= limit and float(_pose_bytes) <= budget:
		return
	var victims: Array[CharacterCanvas] = []
	var count: int = _pose_count
	var bytes: int = _pose_bytes
	for rec: CharacterCanvas in _lru:
		if float(count) <= limit * CACHE_KEEP and float(bytes) <= budget * CACHE_KEEP:
			break
		victims.append(rec)
		count -= 1
		bytes -= rec.byte_size()
	for rec: CharacterCanvas in victims:
		_forget(rec)


static func _forget(rec: CharacterCanvas) -> void:
	var ref: Array = _lru[rec]
	_lru.erase(rec)
	var bucket: Dictionary = ref[0]
	bucket.erase(ref[1])
	if bucket.size() == 1:
		_poses.erase(bucket[BUCKET_APP])
	_pose_count -= 1
	_pose_bytes -= rec.byte_size()
	_evicted += 1
	if not rec.is_built():
		_pending -= 1


static func _cache_limit() -> int:
	if _cache_max <= 0:
		if not Database.has_balance(CACHE_PATH):
			return CACHE_FALLBACK
		_cache_max = maxi(Database.get_balance_int(CACHE_PATH), 1)
	return _cache_max


static func _byte_limit() -> int:
	if _bytes_max <= 0:
		if not Database.has_balance(CACHE_BYTES_PATH):
			return CACHE_KB_FALLBACK * 1024
		_bytes_max = maxi(Database.get_balance_int(CACHE_BYTES_PATH), 1) * 1024
	return _bytes_max


static func _portrait_limit() -> int:
	if _portrait_max <= 0:
		if not Database.has_balance(PORTRAIT_CACHE_PATH):
			return PORTRAIT_FALLBACK
		_portrait_max = maxi(Database.get_balance_int(PORTRAIT_CACHE_PATH), 1)
	return _portrait_max


## Tests/QA: fija los topes de la caché de poses (0 = los de balance.json) y la vacía.
static func set_cache_limits(max_poses: int, max_kb: int) -> void:
	_cache_max = maxi(max_poses, 0)
	_bytes_max = maxi(max_kb, 0) * 1024
	clear_cache()


## Tests: topes del memo de claves (claves brutas, firmas; 0 = CANON_LIMIT / CANON_SIG_LIMIT).
static func set_key_memo_limits(max_raw: int, max_sigs: int) -> void:
	_canon_raw_max = max_raw if max_raw > 0 else CANON_LIMIT
	_canon_sig_max = max_sigs if max_sigs > 0 else CANON_SIG_LIMIT


## Número de poses grabadas en caché (diagnóstico y tests).
static func cached_pose_count() -> int:
	return _pose_count


## Memoria (bytes) de las mallas de las poses en caché (diagnóstico y tests).
static func cached_mesh_bytes() -> int:
	return _pose_bytes


static func cached_portrait_count() -> int:
	return _portraits.size()


## Poses en caché que aún se dibujan con su lista de órdenes (esperan presupuesto de teselado).
static func pending_pose_count() -> int:
	return _pending


## Diagnóstico (QA): {hits, misses, evicted, poses, bytes, pending} desde el último reset_cache_stats(),
## más el memo de claves: canon_raw (claves brutas), canon_sigs (firmas) y resets (topes alcanzados).
static func cache_stats() -> Dictionary:
	return {"hits": _hits, "misses": _misses, "evicted": _evicted, "poses": _pose_count, "bytes": _pose_bytes,
		"pending": _pending, "canon_raw": _canon_of_raw.size(), "canon_sigs": _canon_ids.size(),
		"resets": _canon_resets}


static func reset_cache_stats() -> void:
	_hits = 0
	_misses = 0
	_evicted = 0


static func clear_cache() -> void:
	_poses.clear()
	_lru.clear()
	_pending = 0
	_portraits.clear()
	_portrait_backgrounds.clear()
	_pose_count = 0
	_pose_bytes = 0


## Graba y tesela de antemano (sin presupuesto) los fotogramas de una animación (p. ej. al cargar
## una planta, con la pausa de carga), para que el primer ciclo no grabe en pleno juego.
static func prewarm(appearance: Dictionary, tier: int, anim: String, facing: Vector2, extra: Dictionary = {}) -> void:
	for frame: int in CharacterAnim.frame_count(anim):
		_try_build(pose_recording(appearance, tier, make_pose(anim, frame, facing, extra)), true)


## Graba el personaje completo en su espacio local (origen = pies, sin escala).
static func _record(canvas: CharacterCanvas, appearance: Dictionary, tier: int, pose: Dictionary) -> void:
	var rig: CharacterRig = CharacterRig.build(appearance, tier, pose)
	canvas.roll = float(rig.p["roll"])
	_draw_shadow(canvas, rig)
	CharacterProps.draw_fx_behind(canvas, rig)
	CharacterProps.draw_scene_prop(canvas, rig, false)
	CharacterProps.draw_hand_items(canvas, rig, true)
	CharacterProps.draw_hugged(canvas, rig, true)
	if rig.front >= -0.3:
		CharacterHead.draw_back_hair(canvas, rig)
	_draw_arms(canvas, rig, true)
	_draw_legs(canvas, rig)
	CharacterOutfit.draw_torso(canvas, rig)
	CharacterProps.draw_torso_wear(canvas, rig)
	CharacterOutfit.draw_coat(canvas, rig)
	CharacterProps.draw_scene_prop(canvas, rig, true)
	CharacterProps.draw_hugged(canvas, rig, false)
	_draw_arms(canvas, rig, false)
	CharacterProps.draw_hand_items(canvas, rig, false)
	CharacterProps.draw_wrist_wear(canvas, rig)
	if rig.front < -0.3:
		CharacterHead.draw_back_hair(canvas, rig)
	CharacterHead.draw(canvas, rig)
	CharacterProps.draw_fx(canvas, rig)


static func _draw_shadow(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	var crouch: float = float(rig.p["crouch"])
	var r: Vector2 = Vector2(rig.shoulder_half * 1.05 + 3.0, 5.5) * Vector2(1.0 + 0.4 * crouch, 1.0 + 0.3 * crouch)
	canvas.draw_colored_polygon(CharacterStyle.ellipse(Vector2(0, 1), r, 18), CharacterStyle.SHADOW)


static func _draw_legs(canvas: CharacterCanvas, rig: CharacterRig) -> void:
	if rig.legs_hidden:
		return
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
static func _draw_arms(canvas: CharacterCanvas, rig: CharacterRig, far: bool) -> void:
	for right: bool in [false, true]:
		if rig.arm_is_far(right) != far:
			continue
		var sh: Vector2 = rig.sh_r if right else rig.sh_l
		var el: Vector2 = rig.elbow_r if right else rig.elbow_l
		var hand: Vector2 = rig.hand_r if right else rig.hand_l
		_draw_arm(canvas, rig, sh, el, hand)


static func _draw_arm(canvas: CharacterCanvas, rig: CharacterRig, sh: Vector2, el: Vector2, hand: Vector2) -> void:
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
