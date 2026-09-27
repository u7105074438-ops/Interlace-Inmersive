# epilogue_screen.gd — Epílogo / fin de partida (§12.9, §12.7): nombre del final, texto a máquina y torre teñida.
# PROPIETARIO DE: nada (muestra el final; desbloquea en el perfil y borra la partida por permadeath, ambos guardados).
# ESCUCHA: nada.
class_name EpilogueScreen
extends Control

## API: EpilogueScreen.show_epilogue(get_tree(), ending_id, context) sustituye la escena actual.
## context (todas opcionales): name, days, victims, scapegoats, bribes_total, company_value, share_price,
##   investigator, case_id, evidence_count, successor (ya formateadas), ruin_tier ("empire"|"husk"),
##   dominant_axis, cause (id de endings.json → causes).
## Texto: Tracking.get_epilogue(ending_id[, context]) si existe; si no, tr(epilogue_key) + variante de
## ruina, con .format(context); los marcadores ausentes se rellenan con UI_EPILOGUE_REDACTED.
## Al cerrar emite closed(start_over) y, si se abrió con show_epilogue, vuelve al menú
## (start_over = true abre directamente el alta de un nuevo empleado: la graduación, §12.7).
## Mientras se escribe, los botones están desactivados (un clic o una tecla solo completa el texto);
## aparecen tras `menus.epilogo.retardo_botones_segundos` con el foco en «Menú principal».
## Registro (record = true): idempotente con el oyente game_over de SaveSystem (desbloquea el final y
## su variante de ruina, guarda el perfil y borra la partida); game_root debería emitir game_over antes.

signal closed(start_over: bool)

const DEFEAT := "defeat"
const FILE_ENDING := "the_file"
const GAP_ENDING := "the_gap"
const EXILE_ENDING := "the_owner_in_exile"
## Sala del archivo muerto (data/rooms): donde acaba el expediente de «the_file».
const ARCHIVE_ROOM := "dead_archive"
const START_OCCUPATION_KEY := "jugador.ocupacion_inicial"
## Sello de goma por final (o por categoría): [clave, eje de color].
const STAMPS: Dictionary = {
	"the_file": ["UI_STAMP_CASE_CLOSED", "blood"], "the_gap": ["UI_STAMP_POSITION_FILLED", "blood"],
	"the_owner_in_exile": ["UI_STAMP_ACCESS_DENIED", "blood"], "the_figurehead": ["UI_STAMP_BOARD_APPROVED", "gold"],
	"full_victory": ["UI_STAMP_NOTARISED", "sweat"],
}
const STAMP_DELAY := 0.6
const STAMP_TIME := 0.18

var ending_id: String = ""
var context: Dictionary = {}
var return_on_close: bool = false
var record_on_ready: bool = false
var _ending: Dictionary = {}
var _text_label: Label
var _scroll: ScrollContainer
var _buttons: HBoxContainer
var _tween: Tween
var _typing: bool = false
var _buttons_ready: bool = false
var _area: MenuScroll


## Sustituye la escena actual por el epílogo.
static func show_epilogue(tree: SceneTree, id: String, ctx: Dictionary) -> EpilogueScreen:
	var screen: EpilogueScreen = create(id, ctx, true)
	screen.return_on_close = true
	tree.change_scene_to_node(screen)
	return screen


## Crea la pantalla sin cambiar de escena. record = desbloquear en el perfil y borrar la partida
## (permadeath); false para vistas previas, pruebas y capturas.
static func create(id: String, ctx: Dictionary, record: bool = false) -> EpilogueScreen:
	var screen: EpilogueScreen = EpilogueScreen.new()
	screen.ending_id = id
	screen.context = ctx.duplicate()
	screen.record_on_ready = record
	return screen


## Texto completo del epílogo para un final y un contexto.
static func compose_text(id: String, ctx: Dictionary) -> String:
	var from_tracking: String = _tracking_epilogue(id, ctx)
	if not from_tracking.is_empty():
		return from_tracking
	var ending: Dictionary = EndingsGallery.find_ending(id)
	if ending.is_empty():
		return TranslationServer.translate("UI_EPILOGUE_MISSING")
	var values: Dictionary = placeholder_values(ending, ctx)
	var text: String = TranslationServer.translate(str(ending.get("epilogue_key", ""))).format(values)
	if bool(ending.get("has_ruin_variants", false)):
		var variants: Dictionary = ending.get("epilogue_variants", {})
		var tier: String = resolve_ruin_tier(ctx)
		if variants.has(tier):
			text += "\n\n" + TranslationServer.translate(str(variants[tier])).format(values)
	return text


static func _tracking_epilogue(id: String, ctx: Dictionary) -> String:
	if not Tracking.has_method("get_epilogue"):
		return ""
	var arity: int = 1
	for info: Dictionary in Tracking.get_method_list():
		if str(info.get("name", "")) == "get_epilogue":
			arity = (info.get("args", []) as Array).size()
	var result: Variant = Tracking.call("get_epilogue", id, ctx) if arity >= 2 else Tracking.call("get_epilogue", id)
	return str(result) if result is String else ""


## "empire" | "husk": del contexto, si no de Tracking, si no "empire".
static func resolve_ruin_tier(ctx: Dictionary) -> String:
	var tier: String = str(ctx.get("ruin_tier", ""))
	if tier.is_empty() and Tracking.has_method("get_ruin_tier"):
		tier = Tracking.get_ruin_tier()
	return tier if EndingsGallery.RUIN_TIERS.has(tier) else EndingsGallery.RUIN_TIERS[0]


## Valores de los marcadores del final; los que faltan se tachan (UI_EPILOGUE_REDACTED).
static func placeholder_values(ending: Dictionary, ctx: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var redacted: String = TranslationServer.translate("UI_EPILOGUE_REDACTED")
	for key: Variant in ending.get("placeholders", []):
		var value: Variant = ctx.get(str(key), null)
		values[str(key)] = str(value) if value != null and str(value) != "" else redacted
	if not ctx.has("name"):
		var player_name: String = _player_name()
		if not player_name.is_empty():
			values["name"] = player_name
	return values


static func _player_name() -> String:
	if PlayerState.has_method("get_player_name"):
		var value: Variant = PlayerState.call("get_player_name")
		if value is String:
			return value
	return ""


## Planta resaltada en las derrotas: el archivo muerto (the_file) o la mesa del primer día (the_gap).
static func defeat_floor(id: String) -> int:
	if id == FILE_ENDING:
		var room: RoomData = Database.get_room(ARCHIVE_ROOM)
		return room.floor if room != null else TowerArt.NO_FLOOR
	if id == GAP_ENDING:
		return PromotionScreen.occupation_floor(str(MenuKit.bal(START_OCCUPATION_KEY)))
	return TowerArt.NO_FLOOR


# ─── Pantalla ──────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme = MenuKit.build_theme()
	_ending = EndingsGallery.find_ending(ending_id)
	if record_on_ready:
		_record_ending()
	_build()
	MenuKit.audio_call(self, "play_epilogue", [axis()], true)
	get_tree().quit_on_go_back = false
	_start_typing.call_deferred()


## Mientras se escribe, cualquier clic, toque o tecla de aceptar/cancelar solo completa el texto:
## se atiende en _input (antes que los botones) y se consume.
func _input(event: InputEvent) -> void:
	if not _typing:
		return
	var accept: bool = event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")
	var click: InputEventMouseButton = event as InputEventMouseButton
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept = true
	if touch != null and touch.pressed:
		accept = true
	if accept:
		get_viewport().set_input_as_handled()
		finish_typing()


## Botón «atrás» de Android: completa el texto o vuelve al menú.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or not is_inside_tree():
		return
	if _typing:
		finish_typing()
	elif _buttons_ready:
		_close(false)


## Guarda el final (y su variante de ruina) en la galería y aplica el permadeath. Idempotente con
## el oyente game_over de SaveSystem: el orden entre ambos no cambia el resultado.
func _record_ending() -> void:
	if SaveSystem.has_method("unlock_ending") and not ending_id.is_empty():
		SaveSystem.unlock_ending(ending_id)
		if bool(_ending.get("has_ruin_variants", false)):
			var variant: String = ending_id + "@" + resolve_ruin_tier(context)
			if not SaveSystem.has_method("is_valid_ending_id") or SaveSystem.is_valid_ending_id(variant):
				SaveSystem.unlock_ending(variant)
		SaveSystem.save_profile()
	if SaveSystem.has_method("run_exists") and SaveSystem.run_exists():
		SaveSystem.delete_run()


func axis() -> String:
	var fallback: String = str(context.get("dominant_axis", ""))
	if fallback.is_empty() and Tracking.has_method("get_dominant_axis"):
		fallback = Tracking.get_dominant_axis()
	return EndingsGallery.ending_axis(_ending, fallback if not fallback.is_empty() else "hybrid")


func _build() -> void:
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	backdrop.show_billboard = false
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var tower: TowerArt = _make_tower()
	add_child(tower)
	var sync: Callable = func() -> void: backdrop.ground_y = tower.position.y + tower.ground_y()
	tower.resized.connect(sync)
	sync.call_deferred()
	add_child(_build_panel())
	_add_stamp()


## Sello sobre el tercio alto de la torre (lado izquierdo): nunca tapa el texto, los botones ni las
## plantas resaltadas (la cima en las victorias, el archivo o la mesa del primer día en las derrotas).
func _add_stamp() -> void:
	var entry: Array = STAMPS.get(ending_id, STAMPS.get(str(_ending.get("category", "")), []))
	if entry.is_empty():
		return
	var stamp: Stamp = Stamp.new()
	stamp.name = "Stamp"
	stamp.text = tr(str(entry[0]))
	stamp.ink = MenuKit.axis_color(str(entry[1]))
	stamp.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stamp.anchor_left = 0.03
	stamp.anchor_top = 0.3
	stamp.anchor_right = 0.37
	stamp.anchor_bottom = 0.44
	add_child(stamp)
	stamp.scale = Vector2.ONE * 1.8
	stamp.modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(stamp, "scale", Vector2.ONE, STAMP_TIME).set_delay(STAMP_DELAY)
	tween.tween_property(stamp, "modulate:a", 1.0, STAMP_TIME).set_delay(STAMP_DELAY)


func _make_tower() -> TowerArt:
	var tower: TowerArt = TowerArt.new()
	tower.name = "Tower"
	tower.show_ground = false
	tower.set_anchors_preset(Control.PRESET_FULL_RECT)
	tower.anchor_right = 0.4
	tower.offset_top = 24
	var tint: Color = MenuKit.axis_color(axis())
	tint.a = MenuKit.bal_float("menus.epilogo.intensidad_tinte")
	tower.tint = tint
	var category: String = str(_ending.get("category", ""))
	if category != DEFEAT and ending_id != EXILE_ENDING:
		tower.figure_visible = true
		tower.figure_floor = TowerArt.TOP_FLOOR
		tower.figure_x = 0.5
		tower.highlight_floor = TowerArt.TOP_FLOOR
	elif ending_id == EXILE_ENDING:
		tower.figure_visible = true
		tower.figure_floor = 0
		tower.figure_x = 0.0
	else:
		tower.highlight_floor = defeat_floor(ending_id)
	return tower


func _build_panel() -> Control:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.anchor_left = 0.4
	for pair: Array in [["left", 12], ["right", 80], ["top", 50], ["bottom", 50]]:
		margin.add_theme_constant_override("margin_" + str(pair[0]), int(pair[1]))
	var panel: PanelContainer = PanelContainer.new()
	margin.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_build_header())
	column.add_child(MenuKit.rule(MenuKit.color("ink"), MenuKit.OUTLINE))
	_area = MenuScroll.new()
	_area.name = "ScrollArea"
	_area.fade_color = MenuKit.color("paper")
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = _area.scroll
	column.add_child(_area)
	_text_label = MenuKit.label(compose_text(ending_id, context), "", true)
	_text_label.name = "EpilogueText"
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	if ending_id == FILE_ENDING:
		_text_label.add_theme_font_override("font", MenuKit.font("mono"))
	_area.set_content(_text_label)
	_buttons = _build_buttons()
	column.add_child(_buttons)
	return margin


func _build_header() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var emblem: EndingsGallery.Emblem = EndingsGallery.Emblem.new()
	emblem.ending_id = ending_id
	emblem.locked = false
	emblem.accent = MenuKit.axis_color(axis())
	emblem.custom_minimum_size = Vector2.ONE * MenuKit.fs(132)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(emblem)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	row.add_child(titles)
	var kicker: Label = MenuKit.label(_kicker_text().to_upper(), "TWSmall", true)
	kicker.add_theme_font_override("font", MenuKit.font("bold"))
	kicker.add_theme_color_override("font_color", MenuKit.heading_color(MenuKit.axis_color(axis()).darkened(0.3)))
	titles.add_child(kicker)
	var name_label: Label = MenuKit.label(tr(str(_ending.get("name_key", "UI_EPILOGUE_MISSING"))).to_upper(), "TWHeading", true)
	name_label.name = "EndingName"
	name_label.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_DISPLAY + 12))
	titles.add_child(name_label)
	var sub: String = _subline_text()
	if not sub.is_empty():
		var sub_label: Label = MenuKit.label(sub, "TWSmall", true)
		sub_label.add_theme_font_override("font", MenuKit.font("bold"))
		titles.add_child(sub_label)
	return row


func _kicker_text() -> String:
	var category: String = str(_ending.get("category", ""))
	var key: String = str(EndingsGallery.CATEGORY_KEYS.get(category, "UI_GALLERY_CAT_DEFEAT"))
	var head: String = tr("UI_EPILOGUE_GAME_OVER") if category == DEFEAT else tr("UI_EPILOGUE_KICKER")
	return "%s · %s" % [head, tr(key)]


## Variante de ruina (victorias) o causa (derrotas y parciales).
func _subline_text() -> String:
	var parts: Array[String] = []
	if bool(_ending.get("has_ruin_variants", false)):
		var tier: String = resolve_ruin_tier(context)
		parts.append(MenuKit.trf("UI_EPILOGUE_RUIN_FMT", {"tier": tr("RUIN_TIER_" + tier.to_upper())}))
	var cause: String = str(context.get("cause", ""))
	if not cause.is_empty():
		parts.append(MenuKit.trf("UI_EPILOGUE_CAUSE_FMT", {"cause": tr("CAUSE_" + cause.to_upper())}))
	return "  ·  ".join(parts)


func _build_buttons() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var menu: Button = MenuKit.button(tr("UI_EPILOGUE_TO_MENU"))
	menu.name = "ToMenu"
	menu.pressed.connect(_close.bind(false))
	row.add_child(menu)
	var again: Button = MenuKit.button(tr("UI_EPILOGUE_START_OVER"))
	again.name = "StartOver"
	again.pressed.connect(_close.bind(true))
	row.add_child(again)
	row.modulate.a = 0.0
	_set_buttons_enabled(row, false)
	return row


## Botones inertes (sin ratón, sin foco, desactivados) mientras el texto se escribe.
static func _set_buttons_enabled(row: HBoxContainer, enabled: bool) -> void:
	for child: Node in row.get_children():
		var b: Button = child as Button
		b.disabled = not enabled
		b.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		b.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


func buttons_ready() -> bool:
	return _buttons_ready


func _start_typing() -> void:
	var total: int = _text_label.get_total_character_count()
	var speed: float = maxf(MenuKit.bal_float("menus.epilogo.caracteres_por_segundo"), 1.0)
	_text_label.visible_characters = 0
	_typing = true
	_area.hint_enabled = false
	_tween = create_tween()
	_tween.tween_method(_set_typed, 0, total, total / speed)
	_tween.tween_callback(finish_typing)


func _set_typed(count: int) -> void:
	_text_label.visible_characters = count
	var ratio: float = float(count) / maxf(1.0, float(_text_label.get_total_character_count()))
	var overflow: float = _text_label.size.y - _scroll.size.y
	if overflow > 0.0:
		_scroll.scroll_vertical = roundi(clampf(ratio * _text_label.size.y - _scroll.size.y * 0.75, 0.0, overflow))


## Muestra el texto completo; los botones se activan tras una breve pausa (evita que el mismo
## toque que completa el texto pulse «Nuevo empleado» o «Menú principal»).
func finish_typing() -> void:
	if _tween != null:
		_tween.kill()
	_typing = false
	_text_label.visible_characters = -1
	_area.hint_enabled = true
	if _buttons_ready:
		return
	var delay: float = maxf(MenuKit.bal_float("menus.epilogo.retardo_botones_segundos"), 0.01)
	_tween = create_tween()
	_tween.tween_interval(delay)
	_tween.tween_callback(reveal_buttons)


## Activa y muestra los botones con el foco en «Menú principal».
func reveal_buttons() -> void:
	if _buttons_ready:
		return
	_buttons_ready = true
	_set_buttons_enabled(_buttons, true)
	var tween: Tween = create_tween()
	tween.tween_property(_buttons, "modulate:a", 1.0, STAMP_TIME)
	MenuKit.focus_later(_buttons.get_node("ToMenu") as Button)


func is_typing() -> bool:
	return _typing


func _close(start_over: bool) -> void:
	if not _buttons_ready:
		return
	closed.emit(start_over)
	if return_on_close and is_inside_tree():
		GameLaunch.return_to_menu(get_tree(), GameLaunch.ENTRY_NEW_GAME if start_over else GameLaunch.ENTRY_TITLE)


## Sello de goma dibujado (texto inclinado dentro de un rectángulo doble).
class Stamp extends Control:
	const TILT := -0.16
	var text: String = ""
	var ink: Color = Color.RED

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(func() -> void: pivot_offset = size * 0.5)
		pivot_offset = size * 0.5

	func _draw() -> void:
		var f: Font = MenuKit.font("display")
		var fsize: int = roundi(size.y * 0.42)
		var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if tw > size.x * 0.86 and tw > 0.0:
			fsize = floori(fsize * size.x * 0.86 / tw)
			tw = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_set_transform(size * 0.5, TILT, Vector2.ONE)
		var box: Rect2 = Rect2(-tw * 0.5 - 22, -fsize * 0.8, tw + 44, fsize * 1.5)
		draw_rect(box, Color(ink, 0.9), false, 7.0)
		draw_rect(box.grow(-10), Color(ink, 0.9), false, 3.0)
		draw_string(f, Vector2(-tw * 0.5, fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(ink, 0.92))
