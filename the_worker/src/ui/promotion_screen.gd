# promotion_screen.gd — Transición de ascenso/degradación (§14.1): el ascensor recorre el corte de la torre.
# PROPIETARIO DE: nada (pantalla superpuesta; se cierra sola al pulsar «volver al trabajo»).
# ESCUCHA: nada.
class_name PromotionScreen
extends Control

## API: PromotionScreen.present(host, old_occupation_id, new_occupation_id, reason) → PromotionScreen.
## Si host tiene open_modal (UIRoot) se abre como modal que pausa el reloj; si no, como hijo de host.
## Emite finished() al cerrarse. Duración del ascensor: balance menus.promocion.
## Título: ASCENDIDO (rango mayor), DEGRADADO (menor) o TRASLADADO (mismo rango). Un puesto de la
## nave (planta de fábrica) viaja hasta la PB por el hueco y resalta la nave anexa al llegar.

signal finished()

const QUIPS_UP: Array[String] = ["PROMO_QUIP_UP_1", "PROMO_QUIP_UP_2", "PROMO_QUIP_UP_3"]
const QUIPS_DOWN: Array[String] = ["PROMO_QUIP_DOWN_1", "PROMO_QUIP_DOWN_2"]
const QUIPS_SAME: Array[String] = ["PROMO_QUIP_SAME_1", "PROMO_QUIP_SAME_2"]
const LOWEST_SHAFT_FLOOR := -3
const OCCUPATIONS_FILE := "res://data/occupations.json"
## Hueco horizontal de la torre (fracción de pantalla) a la izquierda de la tarjeta.
const TOWER_ANCHOR_RIGHT := 0.47

var old_occupation: String = ""
var new_occupation: String = ""
var reason: String = ""
var _host: Node
var _tower: TowerArt
var _display: Label
var _continue: Button
var _from_floor: int = 0
var _to_floor: int = 0
var _tween: Tween


static func present(host: Node, old_occupation_id: String, new_occupation_id: String, change_reason: String = "") -> PromotionScreen:
	var screen: PromotionScreen = PromotionScreen.new()
	screen.old_occupation = old_occupation_id
	screen.new_occupation = new_occupation_id
	screen.reason = change_reason
	screen._host = host
	if host.has_method("open_modal"):
		host.call("open_modal", screen, true)
	else:
		host.add_child(screen)
	return screen


## Planta del despacho de una ocupación (sala de office_room); si no se sabe, estimada por rango.
static func occupation_floor(occupation_id: String) -> int:
	var record: Dictionary = occupation_record(occupation_id)
	var room_id: String = str(record.get("office_room", ""))
	var room: RoomData = Database.get_room(room_id) if not room_id.is_empty() else null
	if room != null and (room.floor == TowerArt.factory_floor() or (room.floor >= TowerArt.LOWEST and room.floor <= TowerArt.ROOF)):
		return room.floor
	return roundi(float(record.get("rank", 0)) / OccupationData.MAX_RANK * TowerArt.TOP_FLOOR)


static func occupation_rank(occupation_id: String) -> int:
	return int(occupation_record(occupation_id).get("rank", 0))


static func occupation_name(occupation_id: String) -> String:
	var key: String = str(occupation_record(occupation_id).get("name_key", ""))
	return TranslationServer.translate(key) if not key.is_empty() else occupation_id


## {name_key, rank, office_room} de una ocupación: Database si ya cargó; si no, occupations.json.
static func occupation_record(occupation_id: String) -> Dictionary:
	var occ: OccupationData = Database.get_occupation(occupation_id)
	if occ != null:
		return {"name_key": occ.name_key, "rank": occ.rank, "office_room": occ.office_room, "tier": occ.tier}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(OCCUPATIONS_FILE)) if FileAccess.file_exists(OCCUPATIONS_FILE) else null
	var entries: Array = raw if raw is Array else ((raw as Dictionary).get("occupations", []) if raw is Dictionary else [])
	for entry: Variant in entries:
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == occupation_id:
			return entry
	return {}


## true si el cambio es un ascenso (rango nuevo > anterior).
func is_promotion() -> bool:
	return occupation_rank(new_occupation) > occupation_rank(old_occupation)


## true si es un traslado al mismo rango (ni ascenso ni degradación).
func is_transfer() -> bool:
	return occupation_rank(new_occupation) == occupation_rank(old_occupation)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MenuKit.build_theme()
	_from_floor = occupation_floor(old_occupation)
	_to_floor = occupation_floor(new_occupation)
	_build()
	_ride.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		advance()


## Botón «atrás» de Android: igual que Esc.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		advance()


## Primer toque: termina el trayecto; segundo: cierra.
func advance() -> void:
	if _tween != null and _tween.is_running():
		skip_to_end()
	else:
		close()


func _build() -> void:
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(MenuKit.color("night"), 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_tower = TowerArt.new()
	_tower.name = "Tower"
	_tower.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tower.anchor_right = TOWER_ANCHOR_RIGHT
	_tower.anchor_x = 0.5
	_tower.offset_left = 24
	_tower.offset_top = 20
	_tower.show_labels = true
	_tower.show_band_names = true
	_tower.elevator_floor = _shaft_floor(_from_floor)
	_tower.highlight_floor = _from_floor
	add_child(_tower)
	add_child(_build_card())


## Parada del ascensor para una planta: la nave (anexa a la PB) se alcanza desde la planta baja.
func _shaft_floor(f: int) -> int:
	if f == TowerArt.factory_floor():
		return 0
	return clampi(f, LOWEST_SHAFT_FLOOR, TowerArt.TOP_FLOOR)


func _build_card() -> Control:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.anchor_left = 0.48
	for pair: Array in [["left", 0], ["right", 90], ["top", 120], ["bottom", 120]]:
		margin.add_theme_constant_override("margin_" + str(pair[0]), int(pair[1]))
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var kicker: Label = MenuKit.label(tr("PROMO_KICKER").to_upper(), "TWSmall")
	kicker.add_theme_font_override("font", MenuKit.font("bold"))
	column.add_child(kicker)
	var head: Label = MenuKit.label(tr(_title_key()).to_upper(), "TWHeading", true)
	head.name = "Title"
	head.add_theme_color_override("font_color", MenuKit.heading_color(_title_color()))
	column.add_child(head)
	column.add_child(MenuKit.rule(MenuKit.color("ink"), MenuKit.OUTLINE))
	var from_label: Label = MenuKit.label(occupation_name(old_occupation), "TWSmall", true)
	from_label.add_theme_color_override("font_color", MenuKit.color("steel"))
	column.add_child(from_label)
	var to_label: Label = MenuKit.label(occupation_name(new_occupation), "", true)
	to_label.name = "NewOccupation"
	to_label.add_theme_font_override("font", MenuKit.font("display"))
	to_label.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_HEADING + 8))
	column.add_child(to_label)
	column.add_child(MenuKit.label(MenuKit.trf("PROMO_RANK_FMT", {"from": occupation_rank(old_occupation), "to": occupation_rank(new_occupation)}), "", true))
	column.add_child(_build_display())
	var quips: Array[String] = QUIPS_SAME if is_transfer() else (QUIPS_UP if is_promotion() else QUIPS_DOWN)
	var quip: Label = MenuKit.label(tr(quips[absi(hash(new_occupation)) % quips.size()]), "TWSmall", true)
	column.add_child(quip)
	_continue = MenuKit.button(tr("PROMO_CONTINUE"))
	_continue.name = "Continue"
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_END
	_continue.pressed.connect(close)
	column.add_child(_continue)
	return margin


func _title_key() -> String:
	if is_transfer():
		return "PROMO_TITLE_SAME"
	return "PROMO_TITLE_UP" if is_promotion() else "PROMO_TITLE_DOWN"


func _title_color() -> Color:
	if is_transfer():
		return MenuKit.color("steel")
	return MenuKit.axis_color("sweat" if is_promotion() else "blood").darkened(0.2)


## Indicador de planta estilo ascensor (dígitos ámbar sobre fondo oscuro).
func _build_display() -> Control:
	var box: PanelContainer = PanelContainer.new()
	box.add_theme_stylebox_override("panel", MenuKit.box(MenuKit.color("night"), MenuKit.color("ink"), MenuKit.OUTLINE, 0))
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	box.add_child(column)
	var caption: Label = MenuKit.label(tr("OPENING_FLOOR_LABEL"), "TWSmall")
	caption.add_theme_font_override("font", MenuKit.font("bold"))
	caption.add_theme_color_override("font_color", MenuKit.color("paper_dim"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	_display = MenuKit.label("")
	_display.name = "FloorDisplay"
	_display.add_theme_font_override("font", MenuKit.font("display"))
	_display.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_DISPLAY))
	_display.add_theme_color_override("font_color", MenuKit.color("amber"))
	_display.custom_minimum_size.x = MenuKit.fs(180)
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_display)
	_set_display(_from_floor)
	return box


func _set_display(f: int) -> void:
	_display.text = TowerArt.floor_label(f) if f != TowerArt.factory_floor() else tr("PROMO_FACTORY_SHORT")


func _ride() -> void:
	var span: float = absf(float(_shaft_floor(_to_floor) - _shaft_floor(_from_floor)))
	var duration: float = clampf(span * MenuKit.bal_float("menus.promocion.segundos_por_planta"),
			MenuKit.bal_float("menus.promocion.duracion_min_segundos"), MenuKit.bal_float("menus.promocion.duracion_max_segundos"))
	_tween = create_tween()
	_tween.tween_method(_set_elevator, float(_shaft_floor(_from_floor)), float(_shaft_floor(_to_floor)), duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(skip_to_end)


func _set_elevator(value: float) -> void:
	_tower.elevator_floor = value
	_tower.highlight_floor = roundi(value)
	_set_display(roundi(value))


func destination_floor() -> int:
	return _to_floor


## Planta donde para el ascensor al final del trayecto (la PB para la nave).
func destination_stop() -> int:
	return _shaft_floor(_to_floor)


## Salta al final del trayecto (planta de destino resaltada).
func skip_to_end() -> void:
	if _tween != null:
		_tween.kill()
	_tower.elevator_floor = _shaft_floor(_to_floor)
	_tower.highlight_floor = _to_floor
	_set_display(_to_floor)
	_continue.grab_focus()


func close() -> void:
	finished.emit()
	if _host != null and is_instance_valid(_host) and _host.has_method("close_modal"):
		_host.call("close_modal")
	else:
		queue_free()
