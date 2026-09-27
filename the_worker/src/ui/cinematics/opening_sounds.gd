# opening_sounds.gd — Sonidos propios de la apertura (§13.9: «solo texto y sonido»): motor del autobús y frenos.
# PROPIETARIO DE: los AudioStreamWAV de la apertura (sintetizados con SynthDSP en un hilo) y su reproductor.
# ESCUCHA: nada.
class_name OpeningSounds
extends Node

## SfxBank no tiene autobús: estos dos se sintetizan aquí con las primitivas compartidas (SynthDSP)
## y suenan por el bus SFX. Los demás efectos de la apertura (murmullo, lector de tarjeta, campanilla)
## los reproduce AudioDirector. play(id) / stop_all(). El render va en WorkerThreadPool (sin tirones).

const ENGINE := "bus_engine"
const BRAKES := "bus_brakes"
const SFX_BUS := "SFX"
const FALLBACK_RATE := 22050
const ENGINE_SECONDS := 1.6
const BRAKES_SECONDS := 1.4
const FADE_SECONDS := 0.6
const PEAK := 0.8
const SILENT_DB := -60.0

var _streams: Dictionary = {}
var _players: Dictionary = {}
var _task: int = -1
var _rate: int = FALLBACK_RATE
var _mutex: Mutex = Mutex.new()


func _ready() -> void:
	var rate: int = MenuKit.bal_int("audio.frecuencia_muestreo")
	_rate = rate if rate > 0 else FALLBACK_RATE
	for id: String in [ENGINE, BRAKES]:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = id
		player.bus = SFX_BUS if AudioServer.get_bus_index(SFX_BUS) >= 0 else &"Master"
		add_child(player)
		_players[id] = player
	SynthDSP.warm_up()
	_task = WorkerThreadPool.add_task(_render_all)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _render_all() -> void:
	var engine: AudioStreamWAV = SynthDSP.to_stream(render_engine(_rate), _rate, true)
	var brakes: AudioStreamWAV = SynthDSP.to_stream(render_brakes(_rate), _rate, false)
	_mutex.lock()
	_streams[ENGINE] = engine
	_streams[BRAKES] = brakes
	_mutex.unlock()


## Reproduce un sonido de la apertura (silencio si aún no está listo). Los frenos apagan el motor.
func play(id: String) -> void:
	_mutex.lock()
	var stream: AudioStreamWAV = _streams.get(id)
	_mutex.unlock()
	var player: AudioStreamPlayer = _players.get(id)
	if stream == null or player == null:
		return
	if id == BRAKES:
		fade_out(ENGINE)
	player.stream = stream
	player.volume_db = 0.0
	player.play()


func fade_out(id: String) -> void:
	var player: AudioStreamPlayer = _players.get(id)
	if player == null or not player.playing:
		return
	var tween: Tween = create_tween()
	tween.tween_property(player, "volume_db", SILENT_DB, FADE_SECONDS)
	tween.tween_callback(player.stop)


func stop_all() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()


func is_ready() -> bool:
	_mutex.lock()
	var ready: bool = _streams.size() == 2
	_mutex.unlock()
	return ready


## Motor diésel al ralentí: dos sierras graves, ruido sordo y un trémolo de cilindros (en bucle).
static func render_engine(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(ENGINE_SECONDS, rate)
	SynthDSP.tone_into(buf, rate, 0.0, ENGINE_SECONDS, 46.0, 46.0, 0.5, SynthDSP.Wave.SAW, 0.0, 0.0)
	SynthDSP.tone_into(buf, rate, 0.0, ENGINE_SECONDS, 69.0, 69.0, 0.25, SynthDSP.Wave.SQUARE, 0.0, 0.0)
	SynthDSP.noise_into(buf, rate, 0.0, ENGINE_SECONDS, 0.35, 0.0, 0.0, 40.0, 260.0, 20)
	SynthDSP.amp_mod(buf, rate, 12.5, 0.35, false)
	SynthDSP.lowpass(buf, rate, 700.0, 2)
	SynthDSP.normalize(buf, PEAK)
	return buf


## Frenos neumáticos: chirrido que baja y el soplido del aire al final.
static func render_brakes(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(BRAKES_SECONDS, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.7, 1850.0, 1500.0, 0.18, SynthDSP.Wave.TRIANGLE, 0.05, 0.4)
	SynthDSP.tone_into(buf, rate, 0.05, 0.6, 2710.0, 2300.0, 0.08, SynthDSP.Wave.SINE, 0.05, 0.3)
	SynthDSP.noise_into(buf, rate, 0.75, 0.6, 0.6, 0.01, 0.25, 1800.0, 6000.0, 71)
	SynthDSP.tone_into(buf, rate, 0.7, 0.2, 90.0, 55.0, 0.4, SynthDSP.Wave.SINE, 0.005, 0.08)
	SynthDSP.normalize(buf, PEAK)
	return buf
