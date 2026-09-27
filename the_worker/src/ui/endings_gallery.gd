# endings_gallery.gd — Galería de finales del menú principal (§12.9, PASO 46): nueve finales, siluetas si bloqueados.
# PROPIETARIO DE: nada (lee los finales de data/endings.json y los desbloqueos de SaveSystem).
# ESCUCHA: nada.
class_name EndingsGallery
extends Control

## Desbloqueos: SaveSystem.get_unlocked_endings() (profile.json). Un id "<ending>@<empire|husk>"
## marca además la variante de ruina vista (opcional). setup(ids) fuerza la lista (tests, capturas).

signal closed()

const ENDINGS_FILE := "res://data/endings.json"
const COLUMNS := 3
const NARROW_COLUMNS := 2
const NARROW_ASPECT := 1.45
const RUIN_TIERS: Array[String] = ["empire", "husk"]
const CATEGORY_KEYS: Dictionary = {
	"full_victory": "UI_GALLERY_CAT_FULL", "partial_victory": "UI_GALLERY_CAT_PARTIAL", "defeat": "UI_GALLERY_CAT_DEFEAT",
}

var _unlocked: Array[String] = []
var _override: bool = false
var _states: Dictionary = {}
var _built_locale: String = ""


## Fuerza la lista de desbloqueos (si no se llama, se lee del perfil).
func setup(unlocked_ids: Array[String]) -> void:
	_unlocked = unlocked_ids.duplicate()
	_override = true
	if is_node_ready():
		_rebuild()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if not _override:
		_unlocked = read_unlocked()
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _built_locale != TranslationServer.get_locale():
		_rebuild.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


# ─── Datos ─────────────────────────────────────────────────────

## Finales desbloqueados del perfil (guardado: SaveSystem puede ser un stub).
static func read_unlocked() -> Array[String]:
	if SaveSystem.has_method("get_unlocked_endings"):
		return SaveSystem.get_unlocked_endings()
	return []


## Los finales en orden de galería (victorias plenas, parciales, derrotas).
static func load_endings() -> Array[Dictionary]:
	var data: Dictionary = MenuKit.read_json(ENDINGS_FILE)
	if Database.has_method("get_endings_data"):
		var from_db: Variant = Database.call("get_endings_data")
		if from_db is Dictionary and not (from_db as Dictionary).is_empty():
			data = from_db
	var out: Array[Dictionary] = []
	for category: String in CATEGORY_KEYS:
		for raw: Variant in data.get("endings", []):
			if raw is Dictionary and str((raw as Dictionary).get("category", "")) == category:
				out.append(raw)
	return out


static func find_ending(ending_id: String) -> Dictionary:
	for ending: Dictionary in load_endings():
		if str(ending.get("id", "")) == ending_id:
			return ending
	return {}


## Eje visual de un final: blood/gold/silk/sweat, "hybrid" o "defeat".
static func ending_axis(ending: Dictionary, fallback_axis: String = "hybrid") -> String:
	var conditions: Dictionary = ending.get("conditions", {})
	if str(ending.get("category", "")) == "defeat":
		return "defeat"
	if conditions.has("dominant_axis"):
		return str(conditions["dominant_axis"])
	if bool(conditions.get("hybrid", false)):
		return "hybrid"
	return fallback_axis


## Estado de una tarjeta tras construir: "unlocked" | "locked" | "" (no existe).
func get_card_state(ending_id: String) -> String:
	return str(_states.get(ending_id, ""))


func unlocked_count() -> int:
	var count: int = 0
	for id: String in _states:
		if _states[id] == "unlocked":
			count += 1
	return count


func card_count() -> int:
	return _states.size()


# ─── Construcción ──────────────────────────────────────────────

func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_build()


func _build() -> void:
	_built_locale = TranslationServer.get_locale()
	theme = MenuKit.build_theme()
	_states.clear()
	var endings: Array[Dictionary] = load_endings()
	var frame: Dictionary = MenuKit.memo_frame(tr("UI_GALLERY_TITLE"), tr("UI_GALLERY_KICKER"))
	add_child(frame["root"])
	(frame["back"] as Button).pressed.connect(func() -> void: closed.emit())
	(frame["back"] as Button).grab_focus.call_deferred()
	var body: VBoxContainer = frame["body"]
	var unlocked_total: int = 0
	for ending: Dictionary in endings:
		if _unlocked.has(str(ending.get("id", ""))):
			unlocked_total += 1
	var counter: Label = MenuKit.label(MenuKit.trf("UI_GALLERY_COUNTER", {"n": unlocked_total, "total": endings.size()}))
	counter.add_theme_font_override("font", MenuKit.font("bold"))
	body.add_child(counter)
	var grid: GridContainer = GridContainer.new()
	grid.name = "Grid"
	var viewport_size: Vector2 = get_viewport_rect().size
	grid.columns = NARROW_COLUMNS if viewport_size.x / maxf(1.0, viewport_size.y) < NARROW_ASPECT else COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	for ending: Dictionary in endings:
		grid.add_child(_make_card(ending))


func _make_card(ending: Dictionary) -> Control:
	var id: String = str(ending.get("id", ""))
	var unlocked: bool = _unlocked.has(id)
	_states[id] = "unlocked" if unlocked else "locked"
	var card: PanelContainer = PanelContainer.new()
	card.name = "Card_" + id
	card.theme_type_variation = "TWCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not unlocked:
		card.add_theme_stylebox_override("panel", MenuKit.box(MenuKit.color("paper_dim"), MenuKit.color("ink"), MenuKit.OUTLINE, MenuKit.SHADOW))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var emblem: Emblem = Emblem.new()
	emblem.ending_id = id
	emblem.locked = not unlocked
	emblem.accent = MenuKit.axis_color(ending_axis(ending))
	emblem.custom_minimum_size = Vector2.ONE * MenuKit.fs(120)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(emblem)
	row.add_child(_card_texts(ending, unlocked))
	return card


func _card_texts(ending: Dictionary, unlocked: bool) -> VBoxContainer:
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	var category: String = str(ending.get("category", ""))
	var tag: Label = MenuKit.label(tr(str(CATEGORY_KEYS.get(category, ""))).to_upper(), "TWSmall")
	tag.add_theme_font_override("font", MenuKit.font("bold"))
	tag.add_theme_color_override("font_color", MenuKit.axis_color(ending_axis(ending)).darkened(0.25))
	texts.add_child(tag)
	var title_text: String = tr(str(ending.get("name_key", ""))) if unlocked else tr("UI_GALLERY_LOCKED_NAME")
	var title: Label = MenuKit.label(title_text.to_upper(), "TWHeading", true)
	title.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_HEADING - 8))
	texts.add_child(title)
	var desc_key: String = str(ending.get("description_key", "")) if unlocked else "UI_GALLERY_LOCKED_HINT_" + category.to_upper()
	texts.add_child(MenuKit.label(tr(desc_key), "TWSmall", true))
	if bool(ending.get("has_ruin_variants", false)):
		texts.add_child(_ruin_pips(str(ending.get("id", "")), unlocked))
	return texts


func _ruin_pips(id: String, unlocked: bool) -> HBoxContainer:
	var pips: HBoxContainer = HBoxContainer.new()
	pips.add_theme_constant_override("separation", 8)
	for tier: String in RUIN_TIERS:
		var seen: bool = unlocked and _unlocked.has(id + "@" + tier)
		var pip: Label = MenuKit.label(tr("RUIN_TIER_" + tier.to_upper()).to_upper() if unlocked else "· · ·", "TWSmall")
		pip.add_theme_font_override("font", MenuKit.font("bold"))
		var fill: Color = MenuKit.color("ink") if seen else Color(0, 0, 0, 0)
		pip.add_theme_stylebox_override("normal", MenuKit.box(fill, MenuKit.color("ink"), 2, 0))
		pip.add_theme_color_override("font_color", MenuKit.color("paper") if seen else MenuKit.color("steel"))
		pips.add_child(pip)
	return pips


## Emblema vectorial de un final (silueta oscura si está bloqueado).
class Emblem extends Control:
	var ending_id: String = ""
	var locked: bool = true
	var accent: Color = Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var c: Vector2 = size * 0.5
		var ink: Color = MenuKit.color("ink")
		var disc: Color = MenuKit.color("steel") if locked else accent
		draw_circle(c + Vector2(4, 4), s * 0.47, ink)
		draw_circle(c, s * 0.47, disc)
		draw_arc(c, s * 0.47, 0.0, TAU, 40, ink, maxf(2.0, s * 0.035), true)
		var fill: Color = MenuKit.color("slate").darkened(0.4) if locked else MenuKit.color("paper")
		EmblemPainter.paint(self, ending_id, c, s * 0.3, fill, ink)
		if locked:
			var f: Font = MenuKit.font("display")
			var fsize: int = roundi(s * 0.42)
			var tw: float = f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			var pos: Vector2 = c + Vector2(-tw * 0.5, fsize * 0.36)
			draw_string_outline(f, pos, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, maxi(4, fsize / 6), ink)
			draw_string(f, pos, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, MenuKit.color("paper_dim"))
