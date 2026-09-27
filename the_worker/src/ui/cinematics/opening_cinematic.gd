# opening_cinematic.gd — Secuencia de apertura (§13.9): graduación, traslado a la torre y torniquetes; título y lema.
# PROPIETARIO DE: la línea de tiempo de la apertura, la elección (falsa) de oferta y el salto.
# ESCUCHA: nada.
class_name OpeningCinematic
extends Control

## ~90 s sin diálogo hablado: solo texto (rótulos) y sonido (subtítulos si el ajuste está activo).
## play() arranca; skip() la salta (también Esc y el botón «atrás» de Android); seek(t) salta a un
## instante (capturas, pruebas). Sonidos: AudioDirector (SfxBank) y OpeningSounds (autobús).
## La única elección (la oferta de Stellar Sell) espera al jugador hasta `espera_eleccion_segundos`
## y después se elige sola. Al terminar emite finished(skipped). Duraciones: balance menus.apertura.

signal finished(skipped: bool)
signal movement_started(index: int)
signal offer_chosen()

const MOVEMENTS := 4
## Instantes (fracción del primer movimiento) de los hitos de la graduación (guion, no tunables).
const CHOICE_AT := 0.5
## Rótulos: [movimiento, inicio (fracción), fin (fracción), clave, es_sonido].
const CAPTIONS: Array[Array] = [
	[0, 0.05, 0.2, "OPENING_M1_CAPTION_1", false],
	[0, 0.2, 0.3, "OPENING_SFX_CHEER", true],
	[0, 0.31, 0.49, "OPENING_M1_CAPTION_2", false],
	[0, 0.62, 0.78, "OPENING_M1_CAPTION_3", false],
	[0, 0.78, 0.95, "OPENING_M1_CAPTION_4", false],
	[1, 0.04, 0.3, "OPENING_M2_CAPTION_1", false],
	[1, 0.05, 0.36, "OPENING_SFX_BUS", true],
	[1, 0.36, 0.44, "OPENING_SFX_BRAKES", true],
	[1, 0.5, 0.68, "OPENING_M2_CAPTION_2", false],
	[1, 0.72, 0.83, "OPENING_M2_CAPTION_3", false],
	[1, 0.84, 0.96, "OPENING_M2_CAPTION_4", false],
	[2, 0.06, 0.4, "OPENING_M3_CAPTION_1", false],
	[2, 0.42, 0.56, "OPENING_SFX_BEEP", true],
	[2, 0.58, 0.85, "OPENING_M3_CAPTION_2", false],
	[2, 0.7, 0.84, "OPENING_SFX_CHIME", true],
]

## Efectos: [movimiento, instante (fracción), id]. Ids de SfxBank → AudioDirector (si existe);
## los de OpeningSounds (autobús) suenan en esta escena. Cada subtítulo de sonido tiene su efecto.
const SOUND_CUES: Array[Array] = [
	[0, 0.2, "chatter"], [1, 0.05, OpeningSounds.ENGINE], [1, 0.36, OpeningSounds.BRAKES],
	[2, 0.44, "card_beep"], [2, 0.7, "elevator_chime"],
]

## Posición global (segundos) de la línea de tiempo; se anima con Tweens.
var timeline: float = 0.0:
	set(value):
		timeline = value
		_on_timeline()

## Multiplicador de velocidad de reproducción (1 = tiempo real). Pruebas y depuración.
var playback_speed: float = 1.0
var _durations: Array[float] = []
var _last_timeline: float = 0.0
var _tween: Tween
var _playing: bool = false
var _waiting_choice: bool = false
var _chosen_at: float = -1.0
var _done: bool = false
var _movement: int = -1
var _back: OpeningStage
var _front: OpeningStage
var _tower: TowerArt
var _caption: Label
var _subtitle: Label
var _hint: Label
var _skip_button: Button
var _sounds: OpeningSounds


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MenuKit.build_theme()
	_durations = _read_durations()
	_build_layers()
	_build_texts()
	_sounds = OpeningSounds.new()
	_sounds.name = "Sounds"
	add_child(_sounds)
	resized.connect(_on_timeline)
	_on_timeline()


func _process(delta: float) -> void:
	_back.idle_time += delta
	_front.idle_time += delta


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and _waiting_choice:
		var card: int = _back.card_at(click.position)
		if card == OpeningStage.STELLAR_CARD:
			choose_offer()
		elif card >= 0:
			_back.shake_card(card)
			MenuKit.audio_call(self, "play_sfx", ["ui_error"])
		accept_event()


## Botón «atrás» de Android: salta la apertura.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _playing:
		skip()


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		skip()
	elif _waiting_choice and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		choose_offer()


# ─── API ───────────────────────────────────────────────────────

func play() -> void:
	_playing = true
	_done = false
	_run_to(choice_time(), _begin_choice)


func skip() -> void:
	_finish(true)


func is_playing() -> bool:
	return _playing


func is_waiting_choice() -> bool:
	return _waiting_choice


func total_duration() -> float:
	var total: float = 0.0
	for d: float in _durations:
		total += d
	return total


## Instante global en que se despliega la elección de oferta.
func choice_time() -> float:
	return _durations[0] * CHOICE_AT


## Inicio (segundos) de un movimiento 0..3 (el 3 es el título).
func movement_start(index: int) -> float:
	var t: float = 0.0
	for i: int in clampi(index, 0, MOVEMENTS):
		t += _durations[i]
	return t


## Salta a un instante sin reproducir (capturas y pruebas). Pasado el hito, la oferta cuenta como elegida.
func seek(seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	_waiting_choice = false
	_hint.visible = false
	_chosen_at = choice_time() if seconds > choice_time() else -1.0
	_last_timeline = clampf(seconds, 0.0, total_duration())
	timeline = _last_timeline


func is_hint_visible() -> bool:
	return _hint.visible


## El jugador (o el temporizador) elige Stellar Sell: la única oferta disponible.
func choose_offer() -> void:
	if not _waiting_choice:
		return
	_waiting_choice = false
	_chosen_at = timeline
	_hint.visible = false
	MenuKit.audio_call(self, "play_sfx", ["ui_confirm"])
	offer_chosen.emit()
	_run_to(total_duration(), func() -> void: _finish(false))


# ─── Línea de tiempo ───────────────────────────────────────────

func _read_durations() -> Array[float]:
	var keys: Array[String] = ["m1_segundos", "m2_segundos", "m3_segundos", "titulo_segundos"]
	var out: Array[float] = []
	for key: String in keys:
		out.append(maxf(MenuKit.bal_float("menus.apertura." + key), 0.1))
	return out


func _run_to(target: float, then: Callable) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_speed_scale(playback_speed)
	_tween.tween_property(self, "timeline", target, maxf(target - timeline, 0.01))
	_tween.tween_callback(then)


func _begin_choice() -> void:
	present_offers()


## Despliega las ofertas y espera la elección (se elige sola pasado `espera_eleccion_segundos`).
func present_offers() -> void:
	if _tween != null:
		_tween.kill()
	_waiting_choice = true
	_hint.visible = true
	_on_timeline()
	var wait: float = MenuKit.bal_float("menus.apertura.espera_eleccion_segundos")
	_tween = create_tween().set_speed_scale(playback_speed)
	_tween.tween_interval(maxf(wait, 0.01))
	_tween.tween_callback(choose_offer)


## Centro (coordenadas locales) de una oferta en pantalla; STELLAR_CARD es la de Stellar Sell.
func offer_center(index: int) -> Vector2:
	return _back.card_center(index)


func _finish(skipped: bool) -> void:
	if _done:
		return
	_done = true
	_playing = false
	_waiting_choice = false
	_hint.visible = false
	_sounds.stop_all()
	if _tween != null:
		_tween.kill()
	finished.emit(skipped)


## Movimiento actual y tiempo local (0..1) para una posición global.
func locate(t: float) -> Vector2:
	var start: float = 0.0
	for i: int in MOVEMENTS:
		if t < start + _durations[i] or i == MOVEMENTS - 1:
			return Vector2(i, clampf((t - start) / _durations[i], 0.0, 1.0))
		start += _durations[i]
	return Vector2(MOVEMENTS - 1, 1.0)


func _on_timeline() -> void:
	if _back == null:
		return
	var where: Vector2 = locate(timeline)
	var index: int = int(where.x)
	if index != _movement:
		_movement = index
		movement_started.emit(index)
	var chosen_local: float = -1.0
	if _chosen_at >= 0.0:
		chosen_local = (timeline - _chosen_at) / maxf(_durations[0] * (1.0 - CHOICE_AT), 0.01)
	for stage: OpeningStage in [_back, _front]:
		stage.set_moment(index, where.y, chosen_local, _waiting_choice)
	_place_tower(index, where.y)
	_update_texts(index, where.y)
	_hint.visible = _waiting_choice
	_fire_cues(timeline)


func _fire_cues(t: float) -> void:
	for cue: Array in SOUND_CUES:
		var index: int = int(cue[0])
		var at: float = movement_start(index) + _durations[index] * float(cue[1])
		if _last_timeline < at and t >= at:
			_play_cue(str(cue[2]))
	_last_timeline = t


func _play_cue(id: String) -> void:
	if id == OpeningSounds.ENGINE or id == OpeningSounds.BRAKES:
		_sounds.play(id)
	else:
		MenuKit.audio_call(self, "play_sfx", [id])


# ─── Capas y textos ────────────────────────────────────────────

func _build_layers() -> void:
	_back = OpeningStage.new()
	_back.name = "Back"
	_back.layer = OpeningStage.LAYER_BACK
	add_child(_back)
	_tower = TowerArt.new()
	_tower.name = "Tower"
	_tower.show_factory = false
	_tower.show_ground = false
	_tower.show_people = true
	_tower.reserve_label_space = true
	_tower.elevator_visible = false
	add_child(_tower)
	_front = OpeningStage.new()
	_front.name = "Front"
	_front.layer = OpeningStage.LAYER_FRONT
	add_child(_front)
	for stage: OpeningStage in [_back, _front]:
		stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _place_tower(index: int, local_t: float) -> void:
	var shot: Dictionary = _front.tower_shot(index, local_t)
	_tower.visible = bool(shot.get("visible", false))
	if not _tower.visible:
		return
	var r: Rect2 = shot["rect"]
	_tower.position = r.position
	_tower.size = r.size
	_tower.tint = shot.get("tint", Color(0, 0, 0, 0))
	_tower.show_labels = bool(shot.get("labels", false))
	_tower.show_band_names = bool(shot.get("labels", false))
	_tower.highlight_floor = int(shot.get("highlight", TowerArt.NO_FLOOR))


func _build_texts() -> void:
	_caption = _text_label("Caption", "display", MenuKit.fs(MenuKit.FONT_HEADING))
	_caption.anchor_top = 1.0 - OpeningStage.LETTERBOX
	_caption.anchor_bottom = 1.0
	_subtitle = _text_label("Subtitle", "italic", MenuKit.fs(MenuKit.FONT_BODY))
	_subtitle.anchor_top = 1.0 - OpeningStage.LETTERBOX * 1.7
	_subtitle.anchor_bottom = 1.0 - OpeningStage.LETTERBOX
	_hint = _text_label("Hint", "bold", MenuKit.fs(MenuKit.FONT_BODY))
	_hint.text = tr("OPENING_CHOICE_HINT")
	_hint.anchor_top = OpeningStage.LETTERBOX
	_hint.anchor_bottom = OpeningStage.LETTERBOX * 2.0
	_hint.visible = false
	_skip_button = MenuKit.button(tr("OPENING_SKIP"))
	_skip_button.name = "Skip"
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	_skip_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.modulate.a = 0.85
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)


func _text_label(node_name: String, font_kind: String, font_size: int) -> Label:
	var l: Label = MenuKit.label("", "", true)
	l.name = node_name
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.anchor_left = 0.08
	l.anchor_right = 0.92
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuKit.poster_text(l, font_kind, font_size, MenuKit.color("paper"), MenuKit.color("ink"))
	add_child(l)
	return l


func _update_texts(index: int, local_t: float) -> void:
	var caption_text: String = ""
	var caption_alpha: float = 0.0
	var sound_text: String = ""
	var sound_alpha: float = 0.0
	var subtitles_on: bool = SettingsMenu.get_bool("subtitles")
	for entry: Array in CAPTIONS:
		if int(entry[0]) != index or local_t < float(entry[1]) or local_t > float(entry[2]):
			continue
		var a: float = _fade(local_t, float(entry[1]), float(entry[2]))
		if bool(entry[4]):
			sound_text = tr(str(entry[3]))
			sound_alpha = a if subtitles_on else 0.0
		elif _caption_allowed(str(entry[3])):
			caption_text = _caption_text(str(entry[3]))
			caption_alpha = a
	_caption.text = caption_text
	_caption.modulate.a = caption_alpha
	_subtitle.text = sound_text
	_subtitle.modulate.a = sound_alpha


## Rótulo traducido; {name} = nombre elegido en el alta (variante _ANON si aún no hay nombre).
func _caption_text(key: String) -> String:
	var player_name: String = str(GameLaunch.peek().get("player_name", ""))
	if player_name.is_empty() and TranslationServer.translate(key).contains("{name}"):
		return tr(key + "_ANON")
	return MenuKit.trf(key, {"name": player_name})


## Los rótulos posteriores a la elección solo aparecen si ya se eligió la oferta.
func _caption_allowed(key: String) -> bool:
	if key == "OPENING_M1_CAPTION_3" or key == "OPENING_M1_CAPTION_4":
		return _chosen_at >= 0.0
	return true


func _fade(t: float, start: float, end: float) -> float:
	var edge: float = minf((end - start) * 0.2, 0.03)
	return clampf(minf((t - start) / edge, (end - t) / edge), 0.0, 1.0)
