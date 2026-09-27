# ambience.gd — Ambientes de sala en bucle generados por código, con fundido cruzado entre salas.
# PROPIETARIO DE: los dos reproductores de ambiente; la caché de bucles renderizados y el render en curso (del proceso).
# ESCUCHA: nada (AudioDirector le indica la sala/planta actual).
class_name Ambience
extends Node

## Ids = `ambient_sound` de data/rooms y data/art_bands.json. El ruido ambiente desciende al subir
## de banda (§14.3); la fábrica no tiene hilo musical: su ambiente ES el ritmo de la maquinaria
## (§14.9), a `audio.ambiente.fabrica_bpm`. El exterior nocturno: tráfico lejano y silencio.
## Los bucles se renderizan en WorkerThreadPool (uno a la vez) y se guardan para todo el proceso;
## nadie espera nunca a un render sin terminar (salir del árbol no bloquea el hilo principal).

const IDS: Array[String] = [
	"office_hum", "quiet_office", "executive_quiet", "silence", "lobby_murmur", "call_center_noise",
	"street_ambient", "distant_traffic", "machinery_hum", "ventilation_drone", "assembly_line",
	"elevator_muzak", "stairwell_echo",
]
const LOOP_S := 8.0
const CROSSFADE_TAIL_S := 0.5
const PEAK := 0.5
const METHOD_PREFIX := "_amb_"
const W_SINE := SynthDSP.Wave.SINE
const W_SAW := SynthDSP.Wave.SAW
const W_SQUARE := SynthDSP.Wave.SQUARE
const W_TRI := SynthDSP.Wave.TRIANGLE
const FACTORY_BARS := 2
const BEATS_PER_BAR := 4
const SILENT_DB := -80.0

static var _loops: Dictionary = {}
static var _job: Dictionary = {}

var _rate: int = 0
var _factory_bpm: float = 0.0
var _fade_s: float = 0.0
var _base_db: float = 0.0
var _min_level: float = 0.0
var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _current_id: String = ""
var _playing_id: String = ""
var _current_level: float = 0.0
var _tween: Tween = null


func setup(rate: int, bus: String) -> void:
	_rate = rate
	_factory_bpm = AudioTuning.num("audio.ambiente.fabrica_bpm")
	_fade_s = AudioTuning.num("audio.ambiente.fundido_s")
	_base_db = AudioTuning.num("audio.ambiente.nivel_db")
	_min_level = AudioTuning.num("audio.ambiente.nivel_min")
	for i: int in 2:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "AmbiencePlayer%d" % i
		p.bus = bus
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)


func current_id() -> String:
	return _current_id


## True mientras se renderiza algún bucle de ambiente (de cualquier Ambience del proceso).
func is_busy() -> bool:
	return not _job.is_empty()


## Id que suena de verdad ("" mientras se renderiza el primero).
func playing_id() -> String:
	return _playing_id


## Cambia el ambiente (id de ambient_sound) con su nivel 0-1 (ambient_noise_level de la sala).
func set_ambience(sound_id: String, level: float) -> void:
	var id: String = sound_id if IDS.has(sound_id) else "silence"
	_current_level = level
	_current_id = id
	if id == _playing_id:
		_fade_active_to(_level_db(level))
		return
	poll_jobs()
	if _loops.has(id):
		_crossfade_to(id)
	elif _job.is_empty():
		_start_job(id, _rate, _factory_bpm)


## Recoge un render terminado (nunca espera a uno en curso).
static func poll_jobs() -> void:
	if _job.is_empty() or not WorkerThreadPool.is_task_completed(int(_job["id"])):
		return
	WorkerThreadPool.wait_for_task_completion(int(_job["id"]))
	var stream: Variant = (_job["holder"] as Array)[0]
	if stream is AudioStreamWAV:
		_loops[str(_job["sound"])] = stream
	_job = {}


static func _start_job(sound_id: String, rate: int, bpm: float) -> void:
	var holder: Array = [null]
	var task: Callable = func() -> void:
		holder[0] = SynthDSP.to_stream(Ambience.render(sound_id, rate, bpm), rate, true)
	_job = {"id": WorkerThreadPool.add_task(task, false, "ambience_render"), "sound": sound_id,
			"holder": holder}


## Render puro de un bucle de ambiente (mono, sin costura). Vacío si el id no existe.
static func render(sound_id: String, rate: int, factory_bpm: float) -> PackedFloat32Array:
	SynthDSP.warm_up()
	var host: Ambience = Ambience.new()
	var method: String = METHOD_PREFIX + sound_id
	var out: PackedFloat32Array = PackedFloat32Array()
	if host.has_method(method):
		var loop_s: float = LOOP_S
		if sound_id == "assembly_line" and factory_bpm > 0.0:
			loop_s = float(FACTORY_BARS * BEATS_PER_BAR) * 60.0 / factory_bpm
		var buf: PackedFloat32Array = host.call(method, rate, loop_s + CROSSFADE_TAIL_S)
		out = SynthDSP.loopify(buf, int(loop_s * rate))
		SynthDSP.normalize(out, PEAK)
	host.free()
	return out


func _process(_delta: float) -> void:
	if _current_id.is_empty() or _current_id == _playing_id:
		return
	poll_jobs()
	if _loops.has(_current_id):
		_crossfade_to(_current_id)
	elif _job.is_empty():
		_start_job(_current_id, _rate, _factory_bpm)


func _exit_tree() -> void:
	_silence()


## Silencia el ambiente mientras su director está inactivo; vuelve a sonar con resume().
func suspend() -> void:
	_silence()
	set_process(false)


func resume() -> void:
	set_process(true)


func _silence() -> void:
	_kill_tween()
	for p: AudioStreamPlayer in _players:
		p.stop()
	_playing_id = ""


func _crossfade_to(id: String) -> void:
	var incoming: AudioStreamPlayer = _players[1 - _active]
	var outgoing: AudioStreamPlayer = _players[_active]
	_playing_id = id
	incoming.stream = _loops[id]
	incoming.volume_db = SILENT_DB
	incoming.play()
	_active = 1 - _active
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(incoming, "volume_db", _level_db(_current_level), _fade_s)
	_tween.tween_property(outgoing, "volume_db", SILENT_DB, _fade_s)
	_tween.chain().tween_callback(outgoing.stop)


func _fade_active_to(db: float) -> void:
	if _players.is_empty():
		return
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_players[_active], "volume_db", db, _fade_s)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _level_db(level: float) -> float:
	if _current_id == "silence" and level <= 0.0:
		return SILENT_DB
	return linear_to_db(maxf(level, _min_level)) + _base_db


# ─── Recetas de ambiente (diseño sonoro; `dur` incluye la cola de fundido) ─

func _amb_office_hum(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 100.0, 100.0, 0.05, W_SINE, 0.0, 0.0)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 50.0, 50.0, 0.04, W_SINE, 0.0, 0.0)
	var buzz: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.tone_into(buzz, rate, 0.0, dur, 120.0, 120.0, 0.05, W_SAW, 0.0, 0.0)
	SynthDSP.amp_mod(buzz, rate, 0.37, 0.8, true)
	SynthDSP.lowpass(buzz, rate, 900.0, 1)
	SynthDSP.mix_into(buf, buzz, 0, 1.0, false)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.5, 0.0, 0.0, 40.0, 350.0, 211)
	_typing_into(buf, rate, dur, 0.09, 223)
	SynthDSP.tone_into(buf, rate, 5.0, 0.8, 440.0, 440.0, 0.015, W_SINE, 0.01, 0.0)
	SynthDSP.tone_into(buf, rate, 5.0, 0.8, 480.0, 480.0, 0.015, W_SINE, 0.01, 0.0)
	return buf


func _amb_quiet_office(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.4, 0.0, 0.0, 40.0, 300.0, 227)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 100.0, 100.0, 0.02, W_SINE, 0.0, 0.0)
	_typing_into(buf, rate, dur, 0.05, 229)
	return buf


## Despachos: silencio caro. Solo aire y un reloj de pared.
func _amb_executive_quiet(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.25, 0.0, 0.0, 30.0, 180.0, 233)
	for k: int in int(dur):
		var f: float = 3000.0 if k % 2 == 0 else 2200.0
		SynthDSP.noise_into(buf, rate, float(k), 0.01, 0.35, 0.0, 0.003, f, 0.0, 239 + k)
		SynthDSP.tone_into(buf, rate, float(k), 0.02, f * 0.5, f * 0.5, 0.08, W_SINE, 0.0, 0.004)
	return buf


func _amb_silence(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.15, 0.0, 0.0, 30.0, 150.0, 241)
	return buf


func _amb_lobby_murmur(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	_crowd_into(buf, rate, dur, 6, 251)
	SynthDSP.lowpass(buf, rate, 1400.0, 1)
	var steps: PackedFloat32Array = SfxBank.render("npc_step", rate)
	for t: float in [0.7, 1.25, 1.8, 4.9, 5.45]:
		SynthDSP.mix_into(buf, steps, int(t * rate), 0.15, false)
	SynthDSP.echo(buf, rate, 0.19, 0.4, 0.5)
	return buf


func _amb_call_center_noise(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	_crowd_into(buf, rate, dur, 10, 257)
	SynthDSP.lowpass(buf, rate, 2600.0, 1)
	for t: float in [3.0, 3.4]:
		SynthDSP.tone_into(buf, rate, t, 0.35, 440.0, 440.0, 0.03, W_SINE, 0.005, 0.0)
		SynthDSP.tone_into(buf, rate, t, 0.35, 480.0, 480.0, 0.03, W_SINE, 0.005, 0.0)
	SynthDSP.tone_into(buf, rate, 6.2, 0.08, 1400.0, 1400.0, 0.02, W_SINE, 0.002, 0.0)
	return buf


func _amb_street_ambient(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	var rumble: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(rumble, rate, 0.0, dur, 1.0, 0.0, 0.0, 20.0, 180.0, 263)
	SynthDSP.amp_mod(rumble, rate, 0.125, 0.5, false)
	SynthDSP.mix_into(buf, rumble, 0, 0.5, false)
	SynthDSP.noise_into(buf, rate, 2.5, 4.0, 0.45, 2.0, 0.8, 150.0, 1400.0, 269)
	var wind: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(wind, rate, 0.0, dur, 0.05, 0.0, 0.0, 1500.0, 4000.0, 271)
	SynthDSP.amp_mod(wind, rate, 0.25, 0.7, false)
	SynthDSP.mix_into(buf, wind, 0, 1.0, false)
	SynthDSP.tone_into(buf, rate, 6.0, 1.0, 700.0, 900.0, 0.012, W_SINE, 0.3, 0.0)
	SynthDSP.tone_into(buf, rate, 7.0, 1.0, 900.0, 700.0, 0.012, W_SINE, 0.0, 0.6)
	return buf


func _amb_distant_traffic(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.5, 0.0, 0.0, 20.0, 150.0, 277)
	SynthDSP.noise_into(buf, rate, 3.0, 4.0, 0.25, 2.0, 0.8, 100.0, 600.0, 281)
	return buf


func _amb_machinery_hum(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 50.0, 50.0, 0.2, W_SINE, 0.0, 0.0)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 100.0, 100.0, 0.1, W_SAW, 0.0, 0.0)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 150.0, 150.0, 0.05, W_SINE, 0.0, 0.0)
	var rattle: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(rattle, rate, 0.0, dur, 0.12, 0.0, 0.0, 300.0, 2000.0, 283)
	SynthDSP.amp_mod(rattle, rate, 13.0, 0.7, true)
	SynthDSP.mix_into(buf, rattle, 0, 1.0, false)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.4, 0.0, 0.0, 20.0, 120.0, 293)
	SynthDSP.lowpass(buf, rate, 2500.0, 1)
	return buf


func _amb_ventilation_drone(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.5, 0.0, 0.0, 120.0, 500.0, 307)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 120.0, 120.0, 0.05, W_TRI, 0.0, 0.0)
	SynthDSP.amp_mod(buf, rate, 0.25, 0.2, false)
	return buf


## La nave fabril: la maquinaria como única música (prensa, neumática, cinta, motor).
func _amb_assembly_line(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	var beats: int = FACTORY_BARS * BEATS_PER_BAR
	var beat_s: float = (dur - CROSSFADE_TAIL_S) / float(beats)
	for b: int in beats:
		var t: float = float(b) * beat_s
		if b % 2 == 0:
			SynthDSP.tone_into(buf, rate, t, 0.3, 90.0, 38.0, 0.9, W_SINE, 0.001, 0.09)
			SynthDSP.bell_into(buf, rate, t, 0.6, 180.0, 0.25, 2.37, 3.0, 0.2)
		else:
			SynthDSP.noise_into(buf, rate, t + beat_s * 0.5, 0.3, 0.3, 0.01, 0.12, 1500.0, 0.0, 311 + b)
		for s: int in 4:
			var accent: float = 0.2 if s == 0 else 0.09
			SynthDSP.tone_into(buf, rate, t + s * beat_s * 0.25, 0.015, 900.0, 700.0, accent, W_SQUARE, 0.0, 0.004)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 60.0, 60.0, 0.12, W_SAW, 0.0, 0.0)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.2, 0.0, 0.0, 30.0, 400.0, 313)
	SynthDSP.lowpass(buf, rate, 5000.0, 1)
	return buf


func _amb_elevator_muzak(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.tone_into(buf, rate, 0.0, dur, 90.0, 90.0, 0.03, W_SINE, 0.0, 0.0)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.2, 0.0, 0.0, 30.0, 250.0, 317)
	return buf


func _amb_stairwell_echo(rate: int, dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.noise_into(buf, rate, 0.0, dur, 0.15, 0.0, 0.0, 30.0, 200.0, 331)
	SynthDSP.tone_into(buf, rate, 2.0, 0.2, 85.0, 50.0, 0.4, W_SINE, 0.001, 0.05)
	SynthDSP.noise_into(buf, rate, 2.0, 0.08, 0.3, 0.001, 0.02, 200.0, 900.0, 337)
	var steps: PackedFloat32Array = SfxBank.render("npc_step", rate)
	for t: float in [5.0, 5.5, 6.0]:
		SynthDSP.mix_into(buf, steps, int(t * rate), 0.12, false)
	SynthDSP.echo(buf, rate, 0.23, 0.55, 0.6)
	return buf


## Tecleo: ráfagas de clics cortos repartidas por el bucle.
func _typing_into(buf: PackedFloat32Array, rate: int, dur: float, amp: float, noise_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = noise_seed
	var t: float = rng.randf_range(0.2, 1.0)
	while t < dur - 1.0:
		for k: int in rng.randi_range(5, 12):
			SynthDSP.noise_into(buf, rate, t, 0.012, amp, 0.0, 0.003, 2500.0, 0.0, noise_seed + k)
			t += rng.randf_range(0.07, 0.16)
		t += rng.randf_range(0.8, 2.2)


## Murmullo de gente: `voices` voces solapadas con tonos distintos.
func _crowd_into(buf: PackedFloat32Array, rate: int, dur: float, voices: int, noise_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = noise_seed
	for v: int in voices:
		var pitch: float = rng.randf_range(105.0, 230.0)
		var start: float = rng.randf_range(0.0, 1.5)
		SynthDSP.babble_into(buf, rate, start, dur - start - 0.3, pitch, 0.18, noise_seed + v * 13)
