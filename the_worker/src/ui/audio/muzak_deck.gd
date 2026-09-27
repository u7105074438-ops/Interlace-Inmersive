# muzak_deck.gd — La "pletina" del edificio: reproduce las pistas del hilo musical como una cinta que se degrada.
# PROPIETARIO DE: el estado de reproducción (posición, variante de la melodía, silencios, oscilaciones, telemetría).
# ESCUCHA: nada.
class_name MuzakDeck
extends RefCounted

## Lee las pistas de MuzakSynth.render_piece() a velocidad variable (tempo × irregularidad × wow &
## flutter: la velocidad de cinta cambia tempo Y tono a la vez), elige por nota la variante limpia /
## desafinada / atonal, introduce silencios anómalos y cortes, siseo y pérdida de agudos (§14.9).
## Coste: unas pocas operaciones por muestra; lo llama AudioDirector solo con los frames que el
## generador admite (sin bucles de espera). También sirve para el render sin conexión (WAV, tests).

const BLOCK := 64
const FADE_S := 0.006
const JITTER_SMOOTH_S := 0.35
const SILENT_GAIN := 0.001
const HISS_SMOOTH := 0.5
const EVENT_DROPOUT := "dropout"
const EVENT_CUT := "cut"
const EVENT_INTERRUPT := "interrupt"
const EVENT_LOOP := "loop"

## Si es true, cada bloque anota {rate, gain, variant} en `telemetry` (escenario QA, análisis).
var record_telemetry: bool = false
var telemetry: Dictionary = {}

var _rate: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _smooth_s: float = 0.0
var _swap_fade_s: float = 0.0
var _acc: PackedFloat32Array = PackedFloat32Array()
var _mel: Array[PackedFloat32Array] = []
var _switches: PackedInt32Array = PackedInt32Array()
var _length: int = 0
var _pending: Dictionary = {}
var _pending_keep_pos: bool = true
var _pos: float = 0.0
var _prev_pos: float = 0.0
var _switch_idx: int = 0
var _variant: int = 0
var _target: Dictionary = {}
var _cur: Dictionary = {"tempo": 1.0, "jitter": 0.0, "wow": 0.0, "flutter": 0.0, "hiss": 0.0,
		"lowpass_hz": 0.0}
var _jit: float = 0.0
var _jit_target: float = 0.0
var _jit_timer: float = 0.0
var _wow_ph: float = 0.0
var _flut_ph: float = 0.0
var _step: float = 1.0
var _silence_left: int = 0
var _silence_kills_hiss: bool = false
var _g: float = 1.0
var _hg: float = 1.0
var _swap_g: float = 1.0
var _lp_y: float = 0.0
var _hiss_y: float = 0.0
var _noise_i: int = 0
var _events: Array[String] = []


## rate = frecuencia de salida (igual a la de las pistas); smooth_s = inercia de los parámetros;
## swap_fade_s = fundido al cambiar de arreglo (0 = inmediato).
func setup(rate: int, seed: int, smooth_s: float, swap_fade_s: float) -> void:
	_rate = rate
	_rng.seed = seed
	_smooth_s = smooth_s
	_swap_fade_s = swap_fade_s
	_reset_telemetry()


func has_stems() -> bool:
	return _length > 0


func get_length_s() -> float:
	return float(_length) / float(maxi(1, _rate))


func get_position_s() -> float:
	return _pos / float(maxi(1, _rate))


func current_variant() -> int:
	return _variant


func is_silenced() -> bool:
	return _silence_left > 0


## Cambia de pistas con un fundido breve; `keep_position` conserva el punto del bucle (el hilo
## musical del edificio es continuo: al cambiar de planta sigue por el mismo compás).
func load_stems(stems: Dictionary, keep_position: bool) -> void:
	if _length <= 0 or _swap_fade_s <= 0.0:
		_apply_stems(stems, keep_position)
		return
	_pending = stems
	_pending_keep_pos = keep_position


func load_stems_now(stems: Dictionary) -> void:
	_pending = {}
	_apply_stems(stems, false)


## Parámetros de MuzakSynth.degradation(); `immediate` salta la inercia (render sin conexión).
func set_degradation(params: Dictionary, immediate: bool) -> void:
	var first: bool = _target.is_empty()
	_target = params.duplicate()
	if immediate or first or _smooth_s <= 0.0:
		for key: String in _cur.keys():
			_cur[key] = float(_target.get(key, _cur[key]))


## Silencio total durante `seconds` (flagrancia: el edificio contiene la respiración, §14.10).
func interrupt(seconds: float) -> void:
	_silence_left = maxi(_silence_left, int(seconds * _rate))
	_silence_kills_hiss = true
	_events.append(EVENT_INTERRUPT)


## Avanza la cinta sin sonar (plantas sin hilo musical): al volver sigue por donde iría.
func skip(seconds: float) -> void:
	if _length <= 0:
		return
	_pos = fmod(_pos + seconds * float(_rate) * float(_cur["tempo"]), float(_length))


## Eventos desde la última llamada: "dropout", "cut", "interrupt", "loop".
func consume_events() -> Array[String]:
	var out: Array[String] = _events.duplicate()
	_events.clear()
	return out


## Genera `frames` muestras estéreo (mono duplicado: altavoces de techo).
func process(frames: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(maxi(0, frames))
	if _length <= 0:
		if not _pending.is_empty():
			_apply_stems(_pending, _pending_keep_pos)
			_pending = {}
		return out
	var done: int = 0
	while done < frames:
		var n: int = mini(BLOCK, frames - done)
		_update_block(n)
		_render_block(out, done, n)
		done += n
	return out


func _apply_stems(stems: Dictionary, keep_position: bool) -> void:
	_acc = stems.get("acc", PackedFloat32Array())
	_mel.assign(stems.get("mel", []))
	_switches = stems.get("switches", PackedInt32Array())
	var new_len: int = int(stems.get("length", 0))
	if _mel.is_empty() or _acc.size() < new_len or new_len <= 0:
		_length = 0
		return
	_pos = fmod(_pos, float(new_len)) if keep_position else 0.0
	_length = new_len
	_prev_pos = _pos
	_switch_idx = 0
	_variant = MuzakSynth.VARIANT_CLEAN


func _update_block(n: int) -> void:
	var dt: float = float(n) / float(_rate)
	_smooth_params(dt)
	_update_jitter(dt)
	_wow_ph = fmod(_wow_ph + dt * float(_target.get("wow_hz", 0.0)), 1.0)
	_flut_ph = fmod(_flut_ph + dt * float(_target.get("flutter_hz", 0.0)), 1.0)
	var wobble: float = float(_cur["wow"]) * sin(TAU * _wow_ph) \
			+ float(_cur["flutter"]) * sin(TAU * _flut_ph)
	_step = maxf(0.0, float(_cur["tempo"]) * (1.0 + _jit) * (1.0 + wobble))
	_check_switches()
	_schedule_silences(dt)
	if not _pending.is_empty() and _swap_g < SILENT_GAIN:
		_apply_stems(_pending, _pending_keep_pos)
		_pending = {}
	if record_telemetry:
		(telemetry["rate"] as PackedFloat32Array).append(_step)
		(telemetry["gain"] as PackedFloat32Array).append(_g * _swap_g)
		(telemetry["variant"] as PackedByteArray).append(_variant)


func _render_block(out: PackedVector2Array, from: int, n: int) -> void:
	var acc: PackedFloat32Array = _acc
	var mel: PackedFloat32Array = _mel[mini(_variant, _mel.size() - 1)]
	var noise: PackedFloat32Array = SynthDSP.noise_table()
	var fade_k: float = _fade_coef(FADE_S)
	var swap_k: float = _fade_coef(_swap_fade_s)
	var g_t: float = 0.0 if _silence_left > 0 else 1.0
	var hg_t: float = 0.0 if _silence_left > 0 and _silence_kills_hiss else 1.0
	var sg_t: float = 0.0 if not _pending.is_empty() else 1.0
	var lp_a: float = SynthDSP.one_pole_coef(_rate, maxf(1.0, float(_cur["lowpass_hz"])))
	var hiss: float = float(_cur["hiss"])
	var lf: float = float(_length)
	var pos: float = _pos
	for i: int in n:
		var ip: int = int(pos)
		var ip2: int = ip + 1 if ip + 1 < _length else 0
		var fr: float = pos - float(ip)
		var s: float = acc[ip] + (acc[ip2] - acc[ip]) * fr + mel[ip] + (mel[ip2] - mel[ip]) * fr
		_g += (g_t - _g) * fade_k
		_hg += (hg_t - _hg) * fade_k
		_swap_g += (sg_t - _swap_g) * swap_k
		_hiss_y += HISS_SMOOTH * (noise[_noise_i & SynthDSP.NOISE_MASK] - _hiss_y)
		_noise_i += 1
		_lp_y += lp_a * (s * _g * _swap_g + _hiss_y * hiss * _hg - _lp_y)
		out[from + i] = Vector2(_lp_y, _lp_y)
		pos += _step
		if pos >= lf:
			pos -= lf
	_pos = pos
	_silence_left = maxi(0, _silence_left - n)


func _fade_coef(seconds: float) -> float:
	if seconds <= 0.0:
		return 1.0
	return 1.0 - exp(-1.0 / (seconds * float(_rate)))


func _smooth_params(dt: float) -> void:
	var k: float = 1.0 if _smooth_s <= 0.0 else 1.0 - exp(-dt / _smooth_s)
	for key: String in _cur.keys():
		if _target.has(key):
			_cur[key] = float(_cur[key]) + (float(_target[key]) - float(_cur[key])) * k


func _update_jitter(dt: float) -> void:
	var amount: float = float(_cur["jitter"])
	_jit_timer -= dt
	if _jit_timer <= 0.0:
		var change: Vector2 = _target.get("jitter_change_s", Vector2.ONE)
		_jit_timer = _rng.randf_range(change.x, maxf(change.x, change.y))
		_jit_target = _rng.randf_range(-amount, amount)
	_jit += (_jit_target - _jit) * (1.0 - exp(-dt / JITTER_SMOOTH_S))


func _check_switches() -> void:
	if _pos < _prev_pos:
		_switch_idx = 0
		_events.append(EVENT_LOOP)
	_prev_pos = _pos
	while _switch_idx < _switches.size() and _pos >= float(_switches[_switch_idx]):
		_switch_idx += 1
		_variant = _roll_variant()


func _roll_variant() -> int:
	if _mel.size() < MuzakSynth.VARIANT_COUNT:
		return MuzakSynth.VARIANT_CLEAN
	var r: float = _rng.randf()
	var atonal: float = float(_target.get("atonal", 0.0))
	if r < atonal:
		return MuzakSynth.VARIANT_ATONAL
	if r < atonal + float(_target.get("sour", 0.0)):
		return MuzakSynth.VARIANT_SOUR
	return MuzakSynth.VARIANT_CLEAN


func _schedule_silences(dt: float) -> void:
	if _silence_left > 0:
		return
	if _rng.randf() < float(_target.get("cuts_per_s", 0.0)) * dt:
		var cut: Vector2 = _target.get("cut_s", Vector2.ZERO)
		_silence_left = int(_rng.randf_range(cut.x, maxf(cut.x, cut.y)) * _rate)
		_silence_kills_hiss = true
		_events.append(EVENT_CUT)
	elif _rng.randf() < float(_target.get("dropouts_per_s", 0.0)) * dt:
		var drop: Vector2 = _target.get("dropout_s", Vector2.ZERO)
		_silence_left = int(_rng.randf_range(drop.x, maxf(drop.x, drop.y)) * _rate)
		_silence_kills_hiss = false
		_events.append(EVENT_DROPOUT)


func _reset_telemetry() -> void:
	telemetry = {"rate": PackedFloat32Array(), "gain": PackedFloat32Array(),
			"variant": PackedByteArray(), "block": BLOCK, "sample_rate": _rate}
