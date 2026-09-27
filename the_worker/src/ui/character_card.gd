# character_card.gd — Ficha rápida de un personaje al tocarlo o pulsarlo (§13.7, escalada por acreditación §13.4): identidad y lo que el nivel de expediente del jugador deja ver, sin abrir PERSONNEL.
# PROPIETARIO DE: la ficha abierta (su contenido se construye al abrirla; no guarda estado de partida).
# ESCUCHA: nada.
class_name CharacterCard
extends PanelContainer

## open_for(tree, npc_id) la crea sobre UIRoot (capa de interfaz; si no hay, sobre la raíz) junto
## al personaje en pantalla. Contenido con PersonnelApp.build_file(npc_id, effective_level):
##   N1 foto, nombre, puesto, planta y ala (+ «te conoce») · N2 carácter (tipo + frases) y dónde
##   está ahora · N3 seis rasgos en barras (aproximadas; exactas con N5) · N4 debilidad · N5 precio
##   de soborno estimado. Lo bloqueado se anuncia con el nivel que lo abre. Botón de objetivo
##   (PersonnelApp.set_marked). Se cierra con la X, Esc, un clic fuera (NPCLayer) o si el
##   personaje sale de la planta. No pausa el reloj ni bloquea al jugador.

signal closed()

const PORTRAIT_EMS := 4.4
const BAR_WIDTH_FACTOR := 0.42
const SCREEN_MARGIN := 16.0
const ANCHOR_GAP := 28.0
const ANCHOR_LIFT := 1.1
const TRAIT_COLUMNS := 2
const MAX_PHRASES := 2
const LOCKED_SECTIONS: Array[String] = [PersonnelApp.S_CHARACTER, PersonnelApp.S_TRAITS,
	PersonnelApp.S_WEAKNESS, PersonnelApp.S_BRIBE]
const SECTION_TITLES: Dictionary = {
	PersonnelApp.S_CHARACTER: "PERS_SEC_CHARACTER", PersonnelApp.S_TRAITS: "PERS_SEC_TRAITS",
	PersonnelApp.S_WEAKNESS: "PERS_SEC_WEAKNESS", PersonnelApp.S_BRIBE: "PERS_SEC_BRIBE_PRICE",
}


## Retrato de PERSONNEL (CharacterPainter.draw_portrait).
class Portrait extends Control:
	var appearance: Dictionary = {}

	func _draw() -> void:
		if not appearance.is_empty():
			CharacterPainter.draw_portrait(self, appearance, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.color("line"), false, 2.0)


var npc_id: String = ""
var _anchor_world: Vector2 = Vector2.INF
var _mark_button: Button = null
var _body: VBoxContainer = null


## Abre la ficha de `npc_id` junto a su personaje (si está en la planta). null si no existe.
static func open_for(tree: SceneTree, npc_id: String) -> CharacterCard:
	if tree == null or NPCDirector.get_npc(npc_id) == null:
		return null
	var card: CharacterCard = CharacterCard.new()
	card.setup(npc_id)
	var layer: NPCLayer = NPCLayer.find(tree)
	var node: NPCNode = layer.get_node_for(npc_id) if layer != null else null
	if node != null:
		card._anchor_world = node.get_visual_position()
	var ui: UIRoot = UIRoot.find(tree)
	if ui != null:
		ui.add_child(card)
	else:
		var canvas: CanvasLayer = CanvasLayer.new()
		canvas.layer = UIRoot.LAYER
		tree.root.add_child(canvas)
		canvas.add_child(card)
	return card


func setup(p_npc_id: String) -> void:
	npc_id = p_npc_id
	name = "CharacterCard"
	theme = UITheme.build(UITheme.current_text_size, UITheme.current_high_contrast)
	theme_type_variation = UITheme.V_PANEL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var base: float = float(UITheme.base_font_size(UITheme.current_text_size))
	custom_minimum_size = Vector2(base * UITheme.tune("interfaz.ficha_personaje_ancho_em"), 0.0)
	_body = VBoxContainer.new()
	add_child(_body)
	_build(PersonnelApp.build_file(npc_id, PersonnelApp.effective_level(npc_id)))


func _ready() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, UITheme.tune("interfaz.animacion_panel_segundos"))
	_place.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


func _process(_delta: float) -> void:
	var layer: NPCLayer = NPCLayer.find(get_tree())
	if _anchor_world.is_finite() and (layer == null or layer.get_node_for(npc_id) == null):
		close()


# ─── Contenido ────────────────────────────────────────────────

func _build(file: Dictionary) -> void:
	if file.is_empty():
		return
	var sections: Dictionary = file["sections"]
	_body.add_child(_header(sections[PersonnelApp.S_IDENTITY], int(file["level"])))
	if sections.has(PersonnelApp.S_CHARACTER):
		_body.add_child(_character_block(sections[PersonnelApp.S_CHARACTER]))
	if sections.has(PersonnelApp.S_TRAITS):
		_body.add_child(_traits_block(sections[PersonnelApp.S_TRAITS]))
	if sections.has(PersonnelApp.S_WEAKNESS):
		_body.add_child(_text_block(PersonnelApp.S_WEAKNESS, [str(sections[PersonnelApp.S_WEAKNESS])]))
	if sections.has(PersonnelApp.S_BRIBE):
		_body.add_child(_text_block(PersonnelApp.S_BRIBE, _bribe_lines(sections[PersonnelApp.S_BRIBE])))
	var locked: Label = _locked_hint(file.get("locked", []))
	if locked != null:
		_body.add_child(locked)
	_body.add_child(_footer(int(file["level"])))


func _header(identity: Dictionary, level: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var portrait: Portrait = Portrait.new()
	portrait.appearance = identity.get("photo", {})
	var side: float = float(UITheme.base_font_size(UITheme.current_text_size)) * PORTRAIT_EMS
	portrait.custom_minimum_size = Vector2(side, side)
	row.add_child(portrait)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(str(identity.get("name", "")), UITheme.V_HEADING))
	info.add_child(_label(str(identity.get("post", "")), UITheme.V_STRONG))
	info.add_child(_label("%s · %s" % [identity.get("floor", ""), identity.get("wing", "")], UITheme.V_SMALL))
	if NPCDirector.knows_player(npc_id):
		info.add_child(_chip(tr("CARD_KNOWS_YOU"), "rep"))
	row.add_child(info)
	var close_button: Button = Button.new()
	close_button.theme_type_variation = UITheme.V_FLAT
	close_button.tooltip_text = tr("CARD_CLOSE")
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.add_child(_icon("cross", "muted"))
	close_button.custom_minimum_size = Vector2.ONE * float(UITheme.base_font_size(UITheme.current_text_size)) * 1.6
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return row


func _character_block(character: Dictionary) -> VBoxContainer:
	var lines: Array[String] = []
	var phrases: Array = character.get("lines", [])
	for i: int in mini(phrases.size(), MAX_PHRASES):
		lines.append(str(phrases[i]))
	var block: VBoxContainer = _text_block(PersonnelApp.S_CHARACTER, lines)
	var title: Label = _label(str(character.get("archetype_name", "")), UITheme.V_STRONG)
	block.add_child(title)
	block.move_child(title, 1)
	var now: String = _now_text()
	if not now.is_empty():
		block.add_child(_label(now, UITheme.V_SMALL))
	return block


## Dónde está ahora y qué hace (N2: rutina aproximada).
func _now_text() -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return ""
	var place: String = PersonnelApp.room_name(NPCDirector.get_current_location(npc_id))
	if NPCDirector.is_slacking(npc_id):
		place += " · " + tr("CARD_SLACKING")
	return UITheme.trf("CARD_NOW_FMT", [place])


func _traits_block(traits: Array) -> VBoxContainer:
	var block: VBoxContainer = _text_block(PersonnelApp.S_TRAITS, [])
	var grid: GridContainer = GridContainer.new()
	grid.columns = TRAIT_COLUMNS * 2
	for entry: Variant in traits:
		var t: Dictionary = entry
		var name_label: Label = _label(str(t["name"]), UITheme.V_SMALL)
		grid.add_child(name_label)
		var bar: UITheme.MeterBar = UITheme.MeterBar.new("accent", "slot", false)
		bar.width_factor = BAR_WIDTH_FACTOR
		bar.set_value(float(t["value"]))
		bar.tooltip_text = str(t["word"])
		grid.add_child(bar)
	block.add_child(grid)
	return block


func _bribe_lines(bribe: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if bool(bribe.get("unbribable", false)):
		out.append(tr("PERS_BRIBE_UNBRIBABLE"))
		return out
	for price: Variant in bribe.get("prices", []):
		out.append(UITheme.trf("CARD_BRIBE_FMT", [price["name"], UITheme.format_money(int(price["price"]))]))
	return out


func _text_block(section: String, lines: Array[String]) -> VBoxContainer:
	var block: VBoxContainer = VBoxContainer.new()
	block.add_child(HSeparator.new())
	block.add_child(_label(tr(str(SECTION_TITLES.get(section, ""))).to_upper(), UITheme.V_CAPTION))
	for line: String in lines:
		var label: Label = _label(line, UITheme.V_SMALL)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_child(label)
	return block


## «Con N3: perfil de personalidad…» para la primera sección de la ficha rápida aún cerrada.
func _locked_hint(locked: Array) -> Label:
	for entry: Variant in locked:
		var section: String = str((entry as Dictionary).get("id", ""))
		if LOCKED_SECTIONS.has(section):
			var label: Label = _label(UITheme.trf("CARD_LOCKED_FMT", [int(entry["level"]),
					tr(str(SECTION_TITLES[section]))]), UITheme.V_SMALL)
			label.add_theme_color_override("font_color", UITheme.color("faint"))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			return label
	return null


func _footer(level: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_chip(UITheme.trf("PERS_LEVEL_CHIP", [level]), "muted"))
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_mark_button = Button.new()
	_mark_button.pressed.connect(_toggle_mark)
	_refresh_mark()
	row.add_child(_mark_button)
	return row


func _toggle_mark() -> void:
	PersonnelApp.set_marked(npc_id, not PersonnelApp.is_marked(npc_id))
	_refresh_mark()


func _refresh_mark() -> void:
	var marked: bool = PersonnelApp.is_marked(npc_id)
	_mark_button.text = tr("PERS_ACT_UNMARK" if marked else "PERS_ACT_MARK")
	_mark_button.theme_type_variation = UITheme.V_FLAT if marked else UITheme.V_PRIMARY


func is_target_marked() -> bool:
	return PersonnelApp.is_marked(npc_id)


func _label(text: String, variation: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _chip(text: String, color_name: String) -> PanelContainer:
	var chip: PanelContainer = PanelContainer.new()
	chip.theme_type_variation = UITheme.V_PILL
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var label: Label = _label(text, UITheme.V_CAPTION)
	label.add_theme_color_override("font_color", UITheme.color(color_name))
	chip.add_child(label)
	return chip


func _icon(icon: String, color_name: String) -> UITheme.IconView:
	var view: UITheme.IconView = UITheme.IconView.new(icon, color_name)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


# ─── Posición ─────────────────────────────────────────────────

## Junto al personaje (a su derecha si cabe, si no a su izquierda), dentro de la pantalla; sin
## personaje, en el centro derecho.
func _place() -> void:
	reset_size()
	var view: Rect2 = get_viewport().get_visible_rect()
	var target: Vector2 = Vector2(view.end.x - size.x - SCREEN_MARGIN, (view.size.y - size.y) * 0.5)
	if _anchor_world.is_finite():
		var cell: float = Database.get_balance_float("mundo.px_por_unidad")
		var screen: Vector2 = get_viewport().get_canvas_transform() * (_anchor_world - Vector2(0.0, cell * ANCHOR_LIFT))
		target = Vector2(screen.x + ANCHOR_GAP, screen.y - size.y * 0.5)
		if target.x + size.x > view.end.x - SCREEN_MARGIN:
			target.x = screen.x - ANCHOR_GAP - size.x
	target.x = clampf(target.x, view.position.x + SCREEN_MARGIN, view.end.x - size.x - SCREEN_MARGIN)
	target.y = clampf(target.y, view.position.y + SCREEN_MARGIN, view.end.y - size.y - SCREEN_MARGIN)
	position = target
