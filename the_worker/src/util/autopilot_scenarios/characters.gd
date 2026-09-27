# characters.gd (escenario) — Hojas de QA de CharacterPainter: escalones, arquetipos, nominados, fotos, animaciones.
# PROPIETARIO DE: nada (monta nodos temporales para capturas).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_characters characters
## Capturas: characters_tiers, characters_archetypes, characters_named, characters_portraits,
## characters_anims, characters_anims_zoom, characters_modes (modos de desplazamiento a zoom de
## juego), characters_directions, characters_uniforms, characters_ingame (zoom de juego por
## defecto), characters_zoom, characters_phone (pantalla 20:9 con el zoom móvil).

const VIEW := Vector2(1920, 1080)
const TITLE_SIZE := 34
const LABEL_SIZE := 17
const SMALL_SIZE := 13
const SEED_BASE := 4100
const TIER_BANDS: Array[String] = ["", "the_pit", "the_pit", "the_pit", "the_specialists",
	"the_specialists", "the_power", "the_power", "the_throne"]
const DIRECTIONS: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(1, -1),
	Vector2(0, -1), Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1)]
const ANIM_ORDER: Array[String] = ["idle", "walk", "sprint", "sneak", "crouch", "crouch_idle",
	"sit", "sit_type", "drawer", "steal", "hide", "drag", "phone", "bribe", "caught", "clock_in",
	"check_watch", "yawn", "chat", "type_intense", "phone_sneak", "startle", "suspicion", "point",
	"walk_report"]


## Lienzo que dibuja figuras, fotos y paneles de fondo en su _draw().
class Sheet extends Node2D:
	var panels: Array[Dictionary] = []
	var figures: Array[Dictionary] = []
	var portraits: Array[Dictionary] = []

	func _draw() -> void:
		for p: Dictionary in panels:
			draw_rect(p["rect"], p["color"])
		var ordered: Array[Dictionary] = figures.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["pose"]["origin"] as Vector2).y < (b["pose"]["origin"] as Vector2).y)
		for f: Dictionary in ordered:
			CharacterPainter.draw(self, f["app"], f["tier"], f["pose"])
		for p: Dictionary in portraits:
			CharacterPainter.draw_portrait(self, p["app"], p["rect"])
			draw_rect(p["rect"], Color("#1d1a22"), false, 2.0)


var _sheet: Sheet = null
var _labels: Control = null


func run(pilot: Autopilot) -> void:
	Database.load_all()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_sheet = Sheet.new()
	layer.add_child(_sheet)
	_labels = Control.new()
	_labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_labels)
	for sheet_name: String in ["tiers", "archetypes", "named", "portraits", "anims", "anims_zoom",
			"modes", "directions", "uniforms", "ingame", "zoom"]:
		_clear()
		call("_build_" + sheet_name)
		_sheet.queue_redraw()
		await pilot.frames(3)
		await pilot.shot("characters_" + sheet_name)
	await _phone_shot(pilot)


## Móvil 20:9: se maqueta contra el rectángulo visible real (stretch "expand") y al zoom móvil.
func _phone_shot(pilot: Autopilot) -> void:
	get_window().size = Vector2i(960, 432)
	await pilot.frames(4)
	_clear()
	var view: Vector2 = get_viewport().get_visible_rect().size
	_title("QA_CHAR_PHONE_TITLE")
	_populate_floor(view, _zoom_for(PlayerCamera.MOBILE_LEVEL_PATH), 18)
	_sheet.queue_redraw()
	await pilot.frames(4)
	await pilot.shot("characters_phone")


func _clear() -> void:
	_sheet.panels.clear()
	_sheet.figures.clear()
	_sheet.portraits.clear()
	for child: Node in _labels.get_children():
		child.queue_free()


func _bg(band: String, key: String) -> Color:
	return CharacterStyle.band_color(band, key, Color("#8a8f7d"))


func _panel(rect: Rect2, color: Color) -> void:
	_sheet.panels.append({"rect": rect, "color": color})


func _figure(app: Dictionary, tier: int, anim: String, frame: int, facing: Vector2, origin: Vector2,
		scale: float, extra: Dictionary = {}) -> void:
	var pose: Dictionary = CharacterPainter.make_pose(anim, frame, facing, extra)
	pose["origin"] = origin
	pose["scale"] = scale
	_sheet.figures.append({"app": app, "tier": tier, "pose": pose})


func _label(text: String, pos: Vector2, size: int, color: Color = Color.WHITE, width: float = 0.0) -> void:
	var l: Label = Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("#1d1a22"))
	l.add_theme_constant_override("outline_size", 5)
	if width > 0.0:
		l.size = Vector2(width, size * 2)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_labels.add_child(l)


func _title(key: String) -> void:
	_label(tr(key), Vector2(40, 24), TITLE_SIZE)


# ─── Hojas ─────────────────────────────────────────────────────

func _build_tiers() -> void:
	_title("QA_CHAR_TIERS_TITLE")
	var col_w: float = VIEW.x / 8.0
	for tier: int in range(1, 9):
		var x: float = col_w * float(tier - 1)
		_panel(Rect2(Vector2(x, 90), Vector2(col_w, VIEW.y - 90)), _bg(TIER_BANDS[tier], "floor"))
		_panel(Rect2(Vector2(x, 90), Vector2(col_w, 50)), _bg(TIER_BANDS[tier], "wall"))
		_label(tr("QA_CHAR_TIER") % tier, Vector2(x, 100), LABEL_SIZE + 4, Color.WHITE, col_w)
		for i: int in 2:
			var app: Dictionary = CharacterPainter.appearance_from_seed(SEED_BASE + tier * 17 + i * 5, tier, false, "")
			var cx: float = x + col_w * (0.3 + 0.4 * float(i))
			_figure(app, tier, "idle", 0, Vector2.DOWN, Vector2(cx, 470), 2.6)
			var facing: Vector2 = Vector2(1, 0) if i == 0 else Vector2(-1, 1).normalized()
			_figure(app, tier, "walk", 2 + i * 4, facing, Vector2(cx, 820), 2.6)


func _build_archetypes() -> void:
	_title("QA_CHAR_ARCHETYPES_TITLE")
	_panel(Rect2(Vector2(0, 90), VIEW - Vector2(0, 90)), _bg("the_specialists", "floor"))
	var archetypes: Array[ArchetypeData] = Database.get_all_archetypes()
	for i: int in archetypes.size():
		var a: ArchetypeData = archetypes[i]
		var col: int = i % 6
		var row: int = i / 6
		var origin: Vector2 = Vector2(160 + col * 320, 440 + row * 460)
		var tier: int = 1 + (i * 3) % 6
		var app: Dictionary = CharacterPainter.appearance_from_seed(SEED_BASE + 300 + i * 11, tier, false, "")
		var anim: String = "walk" if a.visual_tic == "rushes_to_superiors_offices" else "idle"
		_figure(app, tier, anim, 3, Vector2(0.4, 1).normalized(), origin, 2.8,
				{"tic": a.visual_tic, "tic_frame": 1 + i, "look": Vector2(1, 0.3)})
		_label(tr(a.name_key), origin + Vector2(-150, 40), LABEL_SIZE + 2, Color.WHITE, 300)
		_label(tr("ARCH_TIC_" + a.visual_tic.to_upper()), origin + Vector2(-150, 70), SMALL_SIZE, Color("#dfe6ee"), 300)


func _build_named() -> void:
	_title("QA_CHAR_NAMED_TITLE")
	_panel(Rect2(Vector2(0, 90), VIEW - Vector2(0, 90)), _bg("the_pit", "floor"))
	var named: Array[NPCData] = Database.get_all_named_npcs()
	for i: int in named.size():
		var npc: NPCData = named[i]
		var tier: int = _named_tier(npc)
		var app: Dictionary = CharacterPainter.appearance_for_named(npc, tier)
		var origin: Vector2 = Vector2(120 + (i % 8) * 240, 330 + (i / 8) * 330)
		_figure(app, tier, "idle", 0, Vector2(0.3, 1).normalized(), origin, 2.3,
				{"tic": CharacterPainter.tic_for_archetype(npc.archetype)})
		_label(npc.name, origin + Vector2(-120, 30), LABEL_SIZE, Color.WHITE, 240)
		_label(tr("ACCESSORY_" + npc.unique_accessory.to_upper()), origin + Vector2(-120, 56), SMALL_SIZE,
				Color("#e8ecd8"), 240)


func _named_tier(npc: NPCData) -> int:
	var occupation: OccupationData = Database.get_occupation(npc.occupation)
	if occupation != null:
		return occupation.tier
	return int(npc.extra.get("tier", 1))


func _build_portraits() -> void:
	_title("QA_CHAR_PORTRAITS_TITLE")
	_panel(Rect2(Vector2.ZERO, VIEW), Color("#2a2c33"))
	var named: Array[NPCData] = Database.get_all_named_npcs()
	var size: Vector2 = Vector2(150, 170)
	for i: int in 30:
		var pos: Vector2 = Vector2(55 + (i % 10) * 184, 100 + (i / 10) * 322)
		var app: Dictionary
		var caption: String
		if i < named.size():
			app = CharacterPainter.appearance_for_named(named[i], _named_tier(named[i]))
			caption = named[i].name
		else:
			var tier: int = 1 + (i - named.size())
			app = CharacterPainter.appearance_from_seed(SEED_BASE + 900 + i * 7, tier, false, "")
			caption = tr("QA_CHAR_TIER") % tier
		_sheet.portraits.append({"app": app, "rect": Rect2(pos, size)})
		_label(caption, pos + Vector2(-17, size.y + 6), SMALL_SIZE + 2, Color.WHITE, size.x + 34)


func _build_anims() -> void:
	_title("QA_CHAR_ANIMS_TITLE")
	_panel(Rect2(Vector2(0, 80), VIEW - Vector2(0, 80)), _bg("the_pit", "floor"))
	var app: Dictionary = CharacterPainter.appearance_from_seed(SEED_BASE + 7, 1, false, "")
	var cell: Vector2 = Vector2(VIEW.x / 5.0, (VIEW.y - 80) / 5.0)
	for i: int in ANIM_ORDER.size():
		var anim: String = ANIM_ORDER[i]
		var base: Vector2 = Vector2(cell.x * float(i % 5), 80 + cell.y * float(i / 5))
		var frames: int = CharacterPainter.anim_frames(anim)
		for k: int in 4:
			var frame: int = int(float(k) * float(frames) / 4.0)
			var origin: Vector2 = base + Vector2(cell.x * (0.14 + 0.24 * float(k)), cell.y * 0.72)
			_figure(app, 1 + (i % 3) * 2, anim, frame, Vector2(1, 0.6).normalized(), origin, 1.35)
		_label(tr("ANIM_" + anim.to_upper()), base + Vector2(6, cell.y - 30), SMALL_SIZE + 1, Color.WHITE, cell.x - 12)


func _build_anims_zoom() -> void:
	_title("QA_CHAR_ANIMS_TITLE")
	_panel(Rect2(Vector2(0, 80), VIEW - Vector2(0, 80)), _bg("the_specialists", "floor"))
	var picks: Array[String] = ["point", "bribe", "yawn", "drawer", "steal", "caught", "drag", "sneak"]
	for i: int in picks.size():
		var anim: String = picks[i]
		var app: Dictionary = CharacterPainter.appearance_from_seed(SEED_BASE + 20 + i, 3, false, "")
		var base: Vector2 = Vector2(960.0 * float(i % 2), 80 + 250.0 * float(i / 2))
		var frames: int = CharacterPainter.anim_frames(anim)
		for k: int in 4:
			var frame: int = int(float(k) * float(frames) / 4.0) + 1
			var facing: Vector2 = Vector2(1, 0.35).normalized() if i % 2 == 0 else Vector2(0.2, 1).normalized()
			_figure(app, 3, anim, frame, facing, base + Vector2(120 + 220 * k, 215), 2.4)
		_label(tr("ANIM_" + anim.to_upper()), base + Vector2(10, 10), LABEL_SIZE, Color.WHITE)


func _build_directions() -> void:
	_title("QA_CHAR_DIRECTIONS_TITLE")
	_panel(Rect2(Vector2(0, 90), VIEW - Vector2(0, 90)), _bg("the_power", "carpet"))
	var tiers: Array[int] = [1, 3, 5, 8]
	for row: int in tiers.size():
		var tier: int = tiers[row]
		var app: Dictionary = CharacterPainter.appearance_from_seed(SEED_BASE + 50 + row * 13, tier, false, "")
		for d: int in DIRECTIONS.size():
			var origin: Vector2 = Vector2(150 + d * 230, 300 + row * 235)
			_figure(app, tier, "walk", (d * 3) % 8, DIRECTIONS[d].normalized(), origin, 2.2)


func _build_uniforms() -> void:
	_title("QA_CHAR_UNIFORMS_TITLE")
	_panel(Rect2(Vector2(0, 90), VIEW - Vector2(0, 90)), _bg("the_guts", "floor"))
	var uniforms: Array[String] = ["", "security", "cleaning", "maintenance", "factory"]
	for i: int in uniforms.size():
		for j: int in 3:
			var app: Dictionary = CharacterPainter.appearance_from_seed(SEED_BASE + 600 + i * 9 + j, 2, false, "")
			app["uniform"] = uniforms[i]
			var facing: Vector2 = [Vector2.DOWN, Vector2(1, 0.5).normalized(), Vector2.UP][j]
			_figure(app, 2, "walk" if j == 1 else "idle", 2, facing, Vector2(120 + i * 370 + j * 100, 560), 2.6)
		var key: String = "QA_UNIFORM_" + (uniforms[i].to_upper() if not uniforms[i].is_empty() else "NONE")
		_label(tr(key), Vector2(70 + i * 370, 660), LABEL_SIZE, Color.WHITE, 300)


func _build_ingame() -> void:
	_title("QA_CHAR_INGAME_TITLE")
	_populate_floor(VIEW, _zoom_for(PlayerCamera.DEFAULT_LEVEL_PATH), 40)


## Zoom de cámara de un nivel (camara.zoom_niveles[nivel]).
func _zoom_for(level_path: String) -> float:
	var levels: Array = []
	if Database.get_balance("camara.zoom_niveles") is Array:
		levels = Database.get_balance("camara.zoom_niveles")
	var level: int = Database.get_balance_int(level_path)
	return float(levels[level]) if level >= 0 and level < levels.size() else 1.0


## Moqueta con rejilla de celdas y `count` figuras a la escala de la cámara de juego.
func _populate_floor(view: Vector2, zoom: float, count: int) -> void:
	var cell: float = float(Database.get_balance_int("mundo.px_por_unidad")) * zoom
	_panel(Rect2(Vector2(0, 90), view - Vector2(0, 90)), _bg("the_pit", "carpet"))
	for gx: int in int(view.x / cell) + 1:
		_panel(Rect2(Vector2(gx * cell, 90), Vector2(1, view.y)), Color(0, 0, 0, 0.08))
	var anims: Array[String] = ["walk", "idle", "sit_type", "chat", "phone_sneak", "check_watch", "sneak",
		"crouch", "sprint"]
	var cols: int = maxi(int(view.x / (cell * 2.2)), 1)
	for i: int in count:
		var tier: int = 1 + (i * 5) % 8
		var app: Dictionary = CharacterPainter.appearance_from_seed(SEED_BASE + 1200 + i * 3, tier, false, "")
		var origin: Vector2 = Vector2(cell * (1.1 + float(i % cols) * 2.2) + float(i / cols % 2) * cell * 0.6,
				170.0 + cell * 1.4 + float(i / cols) * cell * 2.4)
		if origin.y > view.y - 10.0:
			break
		var facing: Vector2 = DIRECTIONS[(i * 3) % 8].normalized()
		_figure(app, tier, anims[i % anims.size()], i % 8, facing, origin, zoom)


## Modos del jugador a zoom de juego (silueta antes que detalle): de frente, de perfil y de espaldas.
func _build_modes() -> void:
	_title("QA_CHAR_MODES_TITLE")
	var zoom: float = _zoom_for(PlayerCamera.DEFAULT_LEVEL_PATH)
	_panel(Rect2(Vector2(0, 90), VIEW - Vector2(0, 90)), _bg("the_pit", "carpet"))
	var me: Dictionary = CharacterPainter.appearance_from_seed(
			Database.get_balance_int("jugador.semilla_apariencia"), 1, false, "")
	var modes: Array[String] = ["idle", "walk", "sneak", "sprint", "crouch", "crouch_idle", "sit_type", "drawer"]
	var facings: Array[Vector2] = [Vector2.DOWN, Vector2.RIGHT, Vector2.UP]
	var col_w: float = VIEW.x / float(modes.size())
	for i: int in modes.size():
		for row: int in facings.size():
			var origin: Vector2 = Vector2(col_w * (float(i) + 0.5), 330.0 + float(row) * 260.0)
			var frame: int = 6 if modes[i] == "drawer" else 1
			_figure(me, 1, modes[i], frame, facings[row], origin, zoom)
		_label(tr("ANIM_" + modes[i].to_upper()), Vector2(col_w * float(i), 110), LABEL_SIZE, Color.WHITE, col_w)


func _build_zoom() -> void:
	_title("QA_CHAR_NAMED_TITLE")
	_panel(Rect2(Vector2(0, 90), VIEW - Vector2(0, 90)), _bg("the_throne", "floor"))
	var ids: Array[String] = ["npc_harlan_voss", "npc_debbie_foyle", "npc_ludmila_petrova",
		"npc_connie_marks", "npc_diana_sedgwick"]
	for i: int in ids.size():
		var npc: NPCData = Database.get_named_npc(ids[i])
		var tier: int = _named_tier(npc)
		var app: Dictionary = CharacterPainter.appearance_for_named(npc, tier)
		var facing: Vector2 = Vector2(0.35, 1).normalized() if i % 2 == 0 else Vector2(-1, 0.4).normalized()
		_figure(app, tier, "idle", 0, facing, Vector2(170 + i * 320, 820), 4.4)
		_label(npc.name, Vector2(10 + i * 320, 860), LABEL_SIZE + 4, Color.WHITE, 320)
	var me: Dictionary = CharacterPainter.appearance_from_seed(
			Database.get_balance_int("jugador.semilla_apariencia"), 1, false, "")
	_figure(me, 1, "walk", 2, Vector2(0.5, 1).normalized(), Vector2(1770, 820), 4.4)
	_label(tr("QA_PLAYER_TITLE"), Vector2(1610, 860), LABEL_SIZE + 4, Color.WHITE, 320)
