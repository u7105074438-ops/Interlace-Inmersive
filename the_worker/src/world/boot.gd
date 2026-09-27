# boot.gd — Escena de arranque provisional: registra las acciones de entrada y muestra el título.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends Control

## Provisional (PASO 1). game_root.gd la sustituirá como punto de entrada de la partida.

const TITLE_FONT_SIZE := 96
const TAGLINE_FONT_SIZE := 28


func _ready() -> void:
	InputSetup.register_actions()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_title()


func _build_title() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	center.add_child(column)
	column.add_child(_make_label("Title", "UI_TITLE", TITLE_FONT_SIZE))
	column.add_child(_make_label("Tagline", "UI_TAGLINE", TAGLINE_FONT_SIZE))


func _make_label(node_name: String, key: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = tr(key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label
