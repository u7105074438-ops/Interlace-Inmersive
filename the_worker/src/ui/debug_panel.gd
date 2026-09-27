# debug_panel.gd — Panel de depuración F1 (§14/PASO 14, 17, 27, 32) con trucos de QA (BUILD_NOTES §9).
# PROPIETARIO DE: el personaje seleccionado para inspección y el interruptor de conos de visión.
# ESCUCHA: nada (consulta getters en cada refresco mientras está visible).
class_name DebugPanel
extends PanelContainer

## Muestra en tiempo real: sospecha y su desglose (BeliefNet), reputación, creencias vivas sobre el
## jugador y las tres que más aportan a la sospecha (desglose de BeliefNet: certeza × credibilidad
## × peso) con su portador, franja, personaje seleccionado (seis rasgos y registro de relaciones),
## alerta sobre el máximo de balance y registros (Security), fundamentales y pérdidas por robo
## acumuladas (Company.get_total_theft_losses), FPS. Selección: clic sobre un personaje (grupo
## "npcs") o teclas [ y ].
## Trucos: rango ±, dinero, +1 h / franja / día, planta ± (FloorStreamer), creencia/registro,
## conos de visión (llama set_debug_cones(bool) en nodos de "npcs"/"perception" que lo tengan).

const PLAYER_ID := "player"
const TOP_BELIEFS := 3
const WIDTH_EMS := 30.0
const TRAIT_BAR_CELLS := 10
const CLOCK_ADVANCE_METHODS: Array[String] = ["debug_advance_minutes", "advance_minutes", "advance_game_minutes"]
const MINUTES_PER_HOUR := 60
const DEBUG_BELIEF_FACT := "debug_observed"
const DEBUG_RECORD_TYPE := "camera_footage"
const RECORD_WEIGHT_PATH := "investigaciones.pesos_evidencia.grabacion_camara"
const BELIEF_CERTAINTY_PATH := "creencias.certeza_directa_completa"
const ALERT_MAX_PATH := "seguridad.nivel_alerta_max"
const TRAIT_KEY := "DEBUG_TRAIT_%s"
const THEFT_GETTER := "get_total_theft_losses"

## Conos de visión visibles (las piezas de percepción pueden consultarlo al dibujar).
static var cones_visible: bool = false

var _selected_npc: String = ""
var _refresh_left: float = 0.0
var _text: RichTextLabel
var _fps_label: Label
var _cheat_buttons: Array[Button] = []


func _init() -> void:
	name = "DebugPanel"
	theme_type_variation = UITheme.V_MODAL
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	column.add_child(_build_header())
	column.add_child(_build_cheats())
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_text)


func _ready() -> void:
	set_process(visible)
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_top = 16
	offset_bottom = -16
	offset_right = -16
	_apply_width()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_inside_tree():
		_apply_width()
		var small: int = roundi(get_theme_constant("base", UITheme.HUD_TYPE) * UITheme.RATIO_CAPTION)
		for button: Button in _cheat_buttons:
			button.add_theme_font_size_override("font_size", small)
		_text.add_theme_font_override("normal_font", UITheme.font(UITheme.FONT_MONO))


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		refresh()


func get_selected_npc() -> String:
	return _selected_npc


func select_npc(npc_id: String) -> void:
	_selected_npc = npc_id
	if visible:
		refresh()


## Texto plano del panel (pruebas).
func get_text() -> String:
	return _text.get_parsed_text()


func refresh() -> void:
	_fps_label.text = UITheme.trf("DEBUG_FPS", [roundi(Engine.get_frames_per_second())])
	var parts: Array[String] = [
		_section_meters(), _section_breakdown(), _section_beliefs(), _section_npc(),
		_section_security(), _section_company(),
	]
	_text.text = "\n".join(parts)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = UITheme.tune("interfaz.debug_refresco_segundos")
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.physical_keycode == KEY_BRACKETRIGHT or key.physical_keycode == KEY_BRACKETLEFT:
			cycle_npc(1 if key.physical_keycode == KEY_BRACKETRIGHT else -1)
			get_viewport().set_input_as_handled()
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var npc_id: String = _npc_at_screen(click.position)
		if not npc_id.is_empty():
			select_npc(npc_id)
			get_viewport().set_input_as_handled()


func cycle_npc(step: int) -> void:
	var ids: Array[String] = _npc_ids()
	if ids.is_empty():
		return
	var index: int = ids.find(_selected_npc)
	select_npc(ids[posmod(index + step, ids.size())])


# ─── Construcción ──────────────────────────────────────────────────

func _apply_width() -> void:
	var w: float = get_theme_constant("base", UITheme.HUD_TYPE) * WIDTH_EMS * UITheme.RATIO_MONO
	offset_left = -w - 16


func _build_header() -> HBoxContainer:
	var header: HBoxContainer = HBoxContainer.new()
	header.add_child(UITheme.IconView.new("bug", "warn"))
	var title: Label = Label.new()
	title.theme_type_variation = UITheme.V_HEADING
	title.text = UITheme.trf("DEBUG_TITLE")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_fps_label = Label.new()
	_fps_label.theme_type_variation = UITheme.V_MONO
	header.add_child(_fps_label)
	return header


func _build_cheats() -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	var cheats: Array[Array] = [
		["DEBUG_RANK_DOWN", cheat_rank.bind(-1)], ["DEBUG_RANK_UP", cheat_rank.bind(1)],
		["DEBUG_ADD_MONEY", cheat_money], ["DEBUG_CONES", cheat_toggle_cones],
		["DEBUG_HOUR", cheat_advance_hour], ["DEBUG_BAND", cheat_next_band],
		["DEBUG_DAY", cheat_next_day], ["DEBUG_NPC_NEXT", cycle_npc.bind(1)],
		["DEBUG_FLOOR_DOWN", cheat_floor.bind(-1)], ["DEBUG_FLOOR_UP", cheat_floor.bind(1)],
		["DEBUG_ADD_BELIEF", cheat_add_belief], ["DEBUG_ADD_RECORD", cheat_add_record],
	]
	for entry: Array in cheats:
		var button: Button = Button.new()
		button.text = str(entry[0])
		button.theme_type_variation = UITheme.V_FLAT
		button.pressed.connect(entry[1] as Callable)
		button.focus_mode = Control.FOCUS_NONE
		grid.add_child(button)
		_cheat_buttons.append(button)
	return grid


# ─── Trucos de QA ──────────────────────────────────────────────────

func cheat_rank(step: int) -> void:
	var target: int = clampi(PlayerState.get_rank() + step, OccupationData.MIN_RANK, OccupationData.MAX_RANK)
	var options: Array[OccupationData] = Database.get_occupations_by_rank(target)
	if not options.is_empty():
		PlayerState.set_occupation(options[0].id, "debug")
	refresh()


func cheat_money() -> void:
	PlayerState.add_money(UITheme.tune_int("interfaz.debug_dinero_truco"), "debug")
	refresh()


func cheat_advance_hour() -> void:
	for method: String in CLOCK_ADVANCE_METHODS:
		if GameClock.has_method(method):
			GameClock.call(method, MINUTES_PER_HOUR)
			refresh()
			return
	cheat_next_band()


func cheat_next_band() -> void:
	var bands: Array[String] = Validate.TIME_BANDS
	var index: int = bands.find(GameClock.get_current_band())
	GameClock.advance_to_band(bands[posmod(index + 1, bands.size())])
	refresh()


func cheat_next_day() -> void:
	GameClock.advance_to_next_day()
	refresh()


func cheat_toggle_cones() -> void:
	cones_visible = not cones_visible
	for group: String in ["npcs", "perception"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node.has_method("set_debug_cones"):
				node.call("set_debug_cones", cones_visible)


func cheat_floor(step: int) -> void:
	var streamer: Node = _find_streamer()
	if streamer == null:
		return
	var floors: Array = Database.call("get_floor_ids") if Database.has_method("get_floor_ids") else []
	var current: int = int(streamer.call("get_current_floor"))
	var index: int = floors.find(current)
	if floors.is_empty():
		return
	var target: int = int(floors[posmod(index + step, floors.size())])
	streamer.call("load_floor", target)
	_move_player_to_floor(streamer, target)
	refresh()


func cheat_add_belief() -> void:
	var holder: String = _selected_npc if not _selected_npc.is_empty() else _first_npc()
	if holder.is_empty():
		return
	BeliefNet.create_belief(holder, PLAYER_ID, DEBUG_BELIEF_FACT, UITheme.tune(BELIEF_CERTAINTY_PATH),
			Belief.SOURCE_DIRECT, _player_room())
	BeliefNet.calculate_player_suspicion()
	refresh()


func cheat_add_record() -> void:
	BeliefNet.create_record(DEBUG_RECORD_TYPE, PLAYER_ID, UITheme.tune(RECORD_WEIGHT_PATH), _player_room())
	BeliefNet.calculate_player_suspicion()
	refresh()


# ─── Secciones ─────────────────────────────────────────────────────

func _section_meters() -> String:
	var lines: Array[String] = [_head("DEBUG_SEC_PLAYER")]
	var occ: OccupationData = PlayerState.get_occupation()
	lines.append(_kv("DEBUG_SUSPICION", "%.1f  (BeliefNet %.1f)" % [PlayerState.get_suspicion(),
			BeliefNet.calculate_player_suspicion()]))
	lines.append(_kv("DEBUG_REPUTATION", "%.1f" % PlayerState.get_reputation()))
	lines.append(_kv("DEBUG_MONEY", UITheme.format_money(PlayerState.get_money())))
	lines.append(_kv("DEBUG_RANK", UITheme.trf("DEBUG_RANK_FMT", [PlayerState.get_rank(),
			occ.id if occ != null else "-", PlayerState.get_clearance()])))
	lines.append(_kv("DEBUG_WHERE", "%s · %s" % [_player_room(), str(_player_floor())]))
	lines.append(_kv("DEBUG_TIME", "%s · %s · D%d" % [GameClock.get_time_string(), GameClock.get_current_band(),
			GameClock.get_day()]))
	lines.append(_kv("DEBUG_INVENTORY", "%d (%d)" % [PlayerState.get_inventory().size(), PlayerState.get_hot_item_count()]))
	return "\n".join(lines)


func _section_breakdown() -> String:
	var lines: Array[String] = [_head("DEBUG_SEC_BREAKDOWN")]
	var rows: Array[Dictionary] = BeliefNet.get_suspicion_breakdown()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _weight(a) > _weight(b))
	for row: Dictionary in rows:
		lines.append("  [color=#%s]%6.2f[/color] %s" % [_hex("loss"), _weight(row), _row_text(row)])
	if rows.is_empty():
		lines.append("  " + UITheme.trf("DEBUG_NONE"))
	return "\n".join(lines)


func _section_beliefs() -> String:
	var live: int = 0
	for b: Belief in BeliefNet.get_beliefs_about(PLAYER_ID):
		if not b.is_record:
			live += 1
	var records: Array[Belief] = BeliefNet.get_records_about(PLAYER_ID)
	var lines: Array[String] = [_head("DEBUG_SEC_BELIEFS")]
	lines.append(_kv("DEBUG_LIVE_BELIEFS", "%d · %s %d" % [live, UITheme.trf("DEBUG_RECORDS"), records.size()]))
	var ranked: Array[Dictionary] = top_beliefs(BeliefNet.get_suspicion_breakdown(), TOP_BELIEFS)
	for i: int in ranked.size():
		var row: Dictionary = ranked[i]
		lines.append("  " + UITheme.trf("DEBUG_TOP_BELIEF_FMT", [i + 1, str(row.get("fact", "")),
				_npc_name(str(row.get("holder", ""))), _weight(row), float(row.get("certainty", 0.0))]))
	return "\n".join(lines)


## Las `count` creencias vivas (no registros) que más aportan a la sospecha, de mayor a menor.
static func top_beliefs(breakdown: Array[Dictionary], count: int) -> Array[Dictionary]:
	var live: Array[Dictionary] = []
	for row: Dictionary in breakdown:
		if not bool(row.get("is_record", false)):
			live.append(row)
	live.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _weight(a) > _weight(b))
	return live.slice(0, count)


func _section_npc() -> String:
	var lines: Array[String] = [_head("DEBUG_SEC_NPC")]
	var npc: NPCRuntime = NPCDirector.get_npc(_selected_npc) if not _selected_npc.is_empty() else null
	if npc == null:
		lines.append("  " + UITheme.trf("DEBUG_SELECT_HINT"))
		return "\n".join(lines)
	lines.append("  [b]%s[/b] (%s) · %s · %s" % [npc.name, npc.id, npc.archetype, npc.occupation_id])
	lines.append("  " + UITheme.trf("DEBUG_NPC_STATE_FMT", [npc.current_room, npc.state, npc.lod, npc.mood]))
	for trait_name: String in Validate.TRAIT_NAMES:
		var v: int = NPCDirector.get_trait(npc.id, trait_name)
		lines.append("  %-12s %s %3d" % [UITheme.trf(TRAIT_KEY % trait_name.to_upper()), _bar(v), v])
	var ledger: Dictionary = NPCDirector.get_ledger(npc.id)
	lines.append("  %s %d · %s %d · %s %d · %s %d · %s %d" % [
			UITheme.trf("DEBUG_AFFECTION"), int(ledger.get("affection", 0)), UITheme.trf("DEBUG_FEAR"),
			int(ledger.get("fear", 0)), UITheme.trf("DEBUG_DEBT"), int(ledger.get("debt", 0)),
			UITheme.trf("DEBUG_GRIEVANCES"), (ledger.get("grievances", []) as Array).size(),
			UITheme.trf("DEBUG_FAVOURS"), (ledger.get("favours", []) as Array).size()])
	return "\n".join(lines)


func _section_security() -> String:
	var lines: Array[String] = [_head("DEBUG_SEC_SECURITY")]
	lines.append(_kv("DEBUG_ALERT", "%d/%d · %s %s" % [Security.get_alert_level(), UITheme.tune_int(ALERT_MAX_PATH),
			UITheme.trf("DEBUG_CAN_SEARCH"), UITheme.trf("DEBUG_YES" if Security.can_search_player() else "DEBUG_NO")]))
	for inv: Investigation in Security.get_active_investigations():
		var flag: String = " [color=#%s]%s[/color]" % [_hex("danger"), UITheme.trf("DEBUG_SHORTLIST")] \
				if Security.is_player_in_shortlist(inv.id) else ""
		lines.append("  " + UITheme.trf("DEBUG_CASE_FMT", [inv.id, inv.incident_type, inv.phase,
				Security.get_case_weight_against(PLAYER_ID, inv.id)]) + flag)
	lines.append(_kv("DEBUG_COLD_CASES", str(Security.get_cold_cases().size())))
	for record: Belief in BeliefNet.get_records_about(PLAYER_ID):
		lines.append("  " + UITheme.trf("DEBUG_RECORD_FMT", [record.record_type, record.weight, record.location]))
	return "\n".join(lines)


func _section_company() -> String:
	var lines: Array[String] = [_head("DEBUG_SEC_COMPANY")]
	var fundamentals: Dictionary = Company.get_fundamentals()
	for key: Variant in fundamentals:
		lines.append("  %-20s %s" % [str(key), _num(fundamentals[key])])
	if Company.has_method(THEFT_GETTER):
		var theft: float = float(Company.call(THEFT_GETTER))
		lines.append(_kv("DEBUG_THEFT_LOSSES", "[color=#%s]%s[/color]" % [_hex("loss"), UITheme.format_money(roundi(theft))]))
	lines.append(_kv("DEBUG_DISCONTENT", str(Company.get_discontent())))
	lines.append(_kv("DEBUG_PRICE", "%.2f" % Market.get_price()))
	return "\n".join(lines)


# ─── Utilidades ────────────────────────────────────────────────────

func _head(key: String) -> String:
	return "[color=#%s][b]%s[/b][/color]" % [_hex("hazard"), UITheme.trf(key).to_upper()]


func _kv(key: String, value: String) -> String:
	return "  [color=#%s]%s[/color] %s" % [_hex("muted"), UITheme.trf(key), value]


static func _hex(color_name: String) -> String:
	return UITheme.color(color_name).to_html(false)


static func _weight(row: Dictionary) -> float:
	for key: String in ["contribution", "weight", "value", "certainty"]:
		if row.has(key) and (row[key] is float or row[key] is int):
			return float(row[key])
	return 0.0


## Fila del desglose: hecho ← portador · certeza · credibilidad · peso (y marca de registro).
func _row_text(row: Dictionary) -> String:
	var text: String = UITheme.trf("DEBUG_BREAKDOWN_FMT", [str(row.get("fact", "")),
			_npc_name(str(row.get("holder", ""))), float(row.get("certainty", 0.0)),
			float(row.get("credibility", 0.0)), float(row.get("weight", 0.0))])
	if bool(row.get("is_record", false)):
		text += " · " + UITheme.trf("DEBUG_RECORD_TAG")
	return text


static func _num(value: Variant) -> String:
	return "%.2f" % float(value) if value is float else str(value)


static func _bar(value: int) -> String:
	var filled: int = clampi(roundi(value / 100.0 * TRAIT_BAR_CELLS), 0, TRAIT_BAR_CELLS)
	return "[color=#%s]%s[/color][color=#%s]%s[/color]" % [_hex("rep"), "█".repeat(filled), _hex("line"),
			"█".repeat(TRAIT_BAR_CELLS - filled)]


func _npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.name if npc != null else npc_id


func _npc_ids() -> Array[String]:
	var ids: Array[String] = []
	for node: Node in get_tree().get_nodes_in_group("npcs"):
		var id_value: Variant = node.get("npc_id")
		if id_value != null and not str(id_value).is_empty():
			ids.append(str(id_value))
	if ids.is_empty():
		for npc: NPCRuntime in NPCDirector.get_all_npcs():
			ids.append(npc.id)
	return ids


func _first_npc() -> String:
	var ids: Array[String] = _npc_ids()
	return ids[0] if not ids.is_empty() else ""


func _npc_at_screen(screen_pos: Vector2) -> String:
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var radius: float = UITheme.tune("interfaz.debug_radio_seleccion_npc") * UITheme.tune("mundo.px_por_unidad")
	var best: String = ""
	for node: Node in get_tree().get_nodes_in_group("npcs"):
		var n2d: Node2D = node as Node2D
		if n2d == null or n2d.get("npc_id") == null:
			continue
		var d: float = n2d.global_position.distance_to(world_pos)
		if d < radius:
			radius = d
			best = str(n2d.get("npc_id"))
	return best


func _find_streamer() -> Node:
	var grouped: Node = get_tree().get_first_node_in_group("floor_streamer")
	if grouped != null:
		return grouped
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	for node: Node in scene.find_children("*", "Node2D", true, false):
		if node.has_method("load_floor") and node.has_method("get_current_floor"):
			return node
	return null


func _move_player_to_floor(streamer: Node, floor_number: int) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var rooms: Array[RoomData] = Database.get_rooms_by_floor(floor_number)
	if player == null or rooms.is_empty() or not streamer.has_method("get_spawn_point"):
		return
	player.global_position = streamer.call("get_spawn_point", rooms[0].id)


func _player_room() -> String:
	return str(PlayerState.call("get_room")) if PlayerState.has_method("get_room") else ""


func _player_floor() -> int:
	return int(PlayerState.call("get_floor")) if PlayerState.has_method("get_floor") else 0
