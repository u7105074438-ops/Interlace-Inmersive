# sfx_bank.gd — Catálogo y síntesis de efectos de sonido (§14.10): delatores, avisos y señales especiales.
# PROPIETARIO DE: la caché de AudioStreamWAV renderizados (una por id, compartida por el proceso) y su pre-render.
# ESCUCHA: nada.
class_name SfxBank
extends RefCounted

## Cada id tiene receta (_sfx_<id>), subtítulo (§13.10), importancia, ganancia y radio de referencia
## de balance (ruido.*) con el que se escala el volumen de los sonidos del jugador.
## Importancia del subtítulo (contrato de SubtitleFeed): 0 ambiente (gris) · 1 informativo ·
## 2 peligro (ámbar, negrita).

const IMPORTANCE_AMBIENT := 0
const IMPORTANCE_INFO := 1
const IMPORTANCE_DANGER := 2
const PEAK := 0.9
const C_SUB := 0
const C_IMPORTANCE := 1
const C_GAIN := 2
const C_RADIUS := 3
const C_LOOP := 4
const ALARM_PREFIX := "alarm_"
const METHOD_PREFIX := "_sfx_"

## id: [clave de subtítulo, importancia, ganancia, ruta del radio de referencia, bucle].
const CATALOGUE: Dictionary = {
	"step_sneak": ["", 0, 0.25, "ruido.radio_sigiloso", false],
	"step_walk": ["SUB_OWN_STEPS_WALK", 0, 0.45, "ruido.radio_normal", false],
	"step_sprint": ["SUB_OWN_STEPS_SPRINT", 1, 0.7, "ruido.radio_esprint", false],
	"drawer_open": ["SUB_DRAWER", 1, 0.7, "ruido.radio_cajon", false],
	"lock_forcing": ["SUB_LOCK_FORCING", 1, 0.6, "ruido.radio_forzar_cerradura", false],
	"break_object": ["SUB_BREAK", 2, 0.95, "ruido.radio_romper_objeto", false],
	"card_beep": ["SUB_CARD_BEEP", 1, 0.5, "ruido.radio_lector_tarjeta", false],
	"card_denied": ["SUB_CARD_DENIED", 1, 0.5, "ruido.radio_lector_tarjeta", false],
	"freight_elevator": ["SUB_FREIGHT", 1, 0.7, "ruido.radio_montacargas", false],
	"npc_step": ["", 0, 0.45, "", false],
	"chatter": ["SUB_CHATTER", 1, 0.55, "", false],
	"chair_creak": ["SUB_CHAIR_CREAK", 1, 0.55, "", false],
	"guard_radio": ["SUB_GUARD_RADIO", 2, 0.55, "", false],
	"pa_chime": ["SUB_PA_SECURITY", 1, 0.5, "", false],
	"elevator_chime": ["SUB_ELEVATOR_CHIME", 1, 0.55, "", false],
	"caught_thud": ["SUB_CAUGHT", 2, 1.0, "", false],
	"phone_vibrate": ["SUB_PHONE_BUZZ", 1, 0.6, "", false],
	"alarm_the_guts": ["SUB_ALARM_THE_GUTS", 2, 0.7, "", true],
	"alarm_the_pit": ["SUB_ALARM_THE_PIT", 2, 0.7, "", true],
	"alarm_the_specialists": ["SUB_ALARM_THE_SPECIALISTS", 2, 0.7, "", true],
	"alarm_the_power": ["SUB_ALARM_THE_POWER", 2, 0.6, "", true],
	"alarm_the_throne": ["SUB_ALARM_THE_THRONE", 2, 0.6, "", true],
	"alarm_factory": ["SUB_ALARM_FACTORY", 2, 0.75, "", true],
	"alarm_exterior": ["SUB_ALARM_EXTERIOR", 2, 0.7, "", true],
	"ui_click": ["", 0, 0.35, "", false],
	"ui_confirm": ["", 0, 0.4, "", false],
	"ui_error": ["", 0, 0.4, "", false],
	"ui_notify": ["", 0, 0.4, "", false],
	"cash": ["", 0, 0.5, "", false],
}

## Caché del proceso: la comparten todos los AudioDirector (menú → partida no vuelve a renderizar).
static var _cache: Dictionary = {}
static var _mutex: Mutex = Mutex.new()
static var _prewarm_task: int = -1
static var _prewarm_done: bool = false


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in CATALOGUE.keys():
		out.append(id)
	return out


static func has_sfx(id: String) -> bool:
	return CATALOGUE.has(id)


static func subtitle_key(id: String) -> String:
	return str((CATALOGUE.get(id, [""]) as Array)[C_SUB])


static func importance(id: String) -> int:
	return int((CATALOGUE.get(id, ["", IMPORTANCE_AMBIENT]) as Array)[C_IMPORTANCE])


## Ruta de balance del radio "nominal" del sonido ("" si no depende del radio).
static func reference_radius_path(id: String) -> String:
	return str((CATALOGUE.get(id, ["", 0, 0.0, ""]) as Array)[C_RADIUS])


static func is_looping(id: String) -> bool:
	return has_sfx(id) and bool((CATALOGUE[id] as Array)[C_LOOP])


## Id de alarma para una banda de arte (la alarma varía por planta, §14.10).
static func alarm_for_band(band_id: String) -> String:
	var id: String = ALARM_PREFIX + band_id
	return id if has_sfx(id) else ALARM_PREFIX + "the_pit"


## Render puro de un efecto (mono, normalizado a PEAK × ganancia). Vacío si el id no existe.
static func render(id: String, rate: int) -> PackedFloat32Array:
	SynthDSP.warm_up()
	var recipes: SfxBank = SfxBank.new()
	var method: String = METHOD_PREFIX + id
	if not has_sfx(id) or not recipes.has_method(method):
		return PackedFloat32Array()
	var buf: PackedFloat32Array = recipes.call(method, rate)
	SynthDSP.normalize(buf, PEAK * float((CATALOGUE[id] as Array)[C_GAIN]))
	return buf


## Stream listo para reproducir (se renderiza y se guarda la primera vez). Seguro en hilos.
static func get_stream(id: String, rate: int) -> AudioStreamWAV:
	_mutex.lock()
	var cached: AudioStreamWAV = _cache.get(id)
	_mutex.unlock()
	if cached != null or not has_sfx(id):
		return cached
	var stream: AudioStreamWAV = SynthDSP.to_stream(render(id, rate), rate, is_looping(id))
	_mutex.lock()
	_cache[id] = stream
	_mutex.unlock()
	return stream


static func is_cached(id: String) -> bool:
	_mutex.lock()
	var found: bool = _cache.has(id)
	_mutex.unlock()
	return found


## Renderiza todo el catálogo (en el hilo que llame).
static func prewarm(rate: int) -> void:
	for id: String in ids():
		get_stream(id, rate)


## Pre-render en WorkerThreadPool, una sola vez por proceso. Nadie espera a que termine: lo recoge
## poll_prewarm() (y un efecto pedido antes se renderiza en el acto).
static func prewarm_async(rate: int) -> void:
	if _prewarm_task >= 0 or _prewarm_done:
		return
	SynthDSP.warm_up()
	_prewarm_task = WorkerThreadPool.add_task(func() -> void: SfxBank.prewarm(rate), false, "sfx_prewarm")


static func poll_prewarm() -> void:
	if _prewarm_task >= 0 and WorkerThreadPool.is_task_completed(_prewarm_task):
		WorkerThreadPool.wait_for_task_completion(_prewarm_task)
		_prewarm_task = -1
		_prewarm_done = true


static func is_prewarmed() -> bool:
	return _prewarm_done


# ─── Recetas: sonidos del jugador (lo delatan) ───────────────────
# Diseño sonoro: frecuencias, tiempos y niveles son "colores" del sonido, no ajustes de juego.

const W_SINE := SynthDSP.Wave.SINE
const W_SQUARE := SynthDSP.Wave.SQUARE
const W_SAW := SynthDSP.Wave.SAW
const W_TRI := SynthDSP.Wave.TRIANGLE


func _sfx_step_sneak(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.2, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.05, 110.0, 70.0, 0.12, W_SINE, 0.004, 0.02)
	SynthDSP.noise_into(buf, rate, 0.01, 0.16, 0.45, 0.03, 0.05, 500.0, 2200.0, 3)
	return buf


func _sfx_step_walk(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.2, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.07, 150.0, 65.0, 0.5, W_SINE, 0.001, 0.025)
	SynthDSP.noise_into(buf, rate, 0.0, 0.05, 0.9, 0.001, 0.012, 900.0, 4000.0, 5)
	SynthDSP.noise_into(buf, rate, 0.035, 0.13, 0.35, 0.01, 0.04, 500.0, 2600.0, 7)
	return buf


func _sfx_step_sprint(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.22, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.08, 180.0, 60.0, 0.9, W_SINE, 0.001, 0.03)
	SynthDSP.noise_into(buf, rate, 0.0, 0.06, 0.7, 0.001, 0.01, 900.0, 5500.0, 9)
	SynthDSP.noise_into(buf, rate, 0.02, 0.1, 0.35, 0.002, 0.03, 1500.0, 6000.0, 13)
	SynthDSP.tone_into(buf, rate, 0.012, 0.03, 420.0, 300.0, 0.25, W_TRI, 0.001, 0.01)
	return buf


func _sfx_drawer_open(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.7, rate)
	var slide: PackedFloat32Array = SynthDSP.silence(0.4, rate)
	SynthDSP.noise_into(slide, rate, 0.0, 0.4, 0.8, 0.05, 0.0, 500.0, 2400.0, 17)
	SynthDSP.amp_mod(slide, rate, 28.0, 0.65, false)
	SynthDSP.tone_into(slide, rate, 0.0, 0.38, 310.0, 360.0, 0.12, W_SAW, 0.05, 0.0)
	SynthDSP.mix_into(buf, slide, 0, 0.6, false)
	SynthDSP.tone_into(buf, rate, 0.38, 0.12, 95.0, 55.0, 0.8, W_SINE, 0.001, 0.035)
	SynthDSP.bell_into(buf, rate, 0.38, 0.3, 880.0, 0.25, 2.76, 1.6, 0.06)
	SynthDSP.noise_into(buf, rate, 0.38, 0.04, 0.5, 0.001, 0.008, 1500.0, 0.0, 19)
	return buf


## Forzar cerradura: raspados metálicos y chasquidos durante casi dos segundos (prolongado).
func _sfx_lock_forcing(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.6, rate)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 29
	var t: float = 0.0
	while t < 1.3:
		var dur: float = rng.randf_range(0.06, 0.18)
		SynthDSP.noise_into(buf, rate, t, dur, 0.45, 0.01, 0.06, 2200.0, 6500.0, rng.randi())
		SynthDSP.tone_into(buf, rate, t + dur, 0.02, 3100.0, 2800.0, 0.3, W_SQUARE, 0.0, 0.004)
		SynthDSP.tone_into(buf, rate, t, dur, 5200.0, 4700.0, 0.05, W_SINE, 0.005, 0.05)
		t += dur + rng.randf_range(0.03, 0.12)
	SynthDSP.bell_into(buf, rate, 1.4, 0.18, 1400.0, 0.5, 1.41, 2.0, 0.03)
	SynthDSP.noise_into(buf, rate, 1.4, 0.05, 0.6, 0.001, 0.01, 1000.0, 0.0, 31)
	return buf


func _sfx_break_object(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.3, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.25, 95.0, 38.0, 0.9, W_SINE, 0.001, 0.08)
	SynthDSP.noise_into(buf, rate, 0.0, 0.7, 0.9, 0.001, 0.12, 250.0, 7000.0, 37)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 41
	for i: int in 16:
		var t: float = 0.02 + rng.randf() * 0.55
		SynthDSP.bell_into(buf, rate, t, 0.3, rng.randf_range(2400.0, 6800.0), 0.18, 1.37, 0.9,
				rng.randf_range(0.03, 0.08))
	for i: int in 5:
		SynthDSP.noise_into(buf, rate, 0.5 + i * 0.13, 0.05, 0.25, 0.001, 0.015, 1800.0, 0.0, 43 + i)
	return buf


func _sfx_card_beep(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.3, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.09, 1760.0, 1760.0, 0.4, W_SQUARE, 0.002, 0.0)
	SynthDSP.tone_into(buf, rate, 0.11, 0.14, 2349.0, 2349.0, 0.4, W_SQUARE, 0.002, 0.0)
	SynthDSP.lowpass(buf, rate, 5000.0, 1)
	return buf


func _sfx_card_denied(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.45, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.4, 196.0, 185.0, 0.45, W_SQUARE, 0.002, 0.0)
	SynthDSP.amp_mod(buf, rate, 22.0, 0.5, false)
	SynthDSP.lowpass(buf, rate, 2400.0, 1)
	return buf


func _sfx_freight_elevator(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.8, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 1.7, 52.0, 58.0, 0.4, W_SAW, 0.25, 0.0)
	SynthDSP.tone_into(buf, rate, 0.0, 1.7, 81.0, 86.0, 0.2, W_SAW, 0.3, 0.0)
	SynthDSP.noise_into(buf, rate, 0.0, 1.7, 0.5, 0.2, 0.0, 30.0, 320.0, 47)
	SynthDSP.tone_into(buf, rate, 0.55, 0.45, 1180.0, 1360.0, 0.07, W_SINE, 0.1, 0.0)
	SynthDSP.lowpass(buf, rate, 1800.0, 1)
	SynthDSP.tone_into(buf, rate, 1.6, 0.15, 90.0, 50.0, 0.7, W_SINE, 0.001, 0.05)
	return buf


# ─── Recetas: sonidos de los personajes (avisan al jugador) ──────

func _sfx_npc_step(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.2, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.06, 170.0, 80.0, 0.4, W_SINE, 0.001, 0.02)
	SynthDSP.tone_into(buf, rate, 0.0, 0.02, 2300.0, 1900.0, 0.45, W_TRI, 0.0, 0.004)
	SynthDSP.noise_into(buf, rate, 0.0, 0.04, 0.8, 0.001, 0.01, 1200.0, 4500.0, 53)
	SynthDSP.noise_into(buf, rate, 0.04, 0.1, 0.12, 0.01, 0.03, 500.0, 2000.0, 59)
	return buf


## Conversación a través del tabique: dos voces por turnos, muy filtradas.
func _sfx_chatter(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.8, rate)
	SynthDSP.babble_into(buf, rate, 0.0, 0.8, 118.0, 0.5, 61)
	SynthDSP.babble_into(buf, rate, 0.85, 0.9, 205.0, 0.45, 67)
	SynthDSP.lowpass(buf, rate, 850.0, 2)
	return buf


## Silla que cruje: fricción adherencia-deslizamiento excitando dos resonancias + golpe de patas.
func _sfx_chair_creak(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.7, rate)
	var src: PackedFloat32Array = SynthDSP.silence(0.5, rate)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 71
	var t: float = 0.02
	while t < 0.45:
		src[int(t * rate)] = rng.randf_range(0.6, 1.0)
		t += lerpf(0.004, 0.011, t / 0.45) * rng.randf_range(0.8, 1.25)
	var low: PackedFloat32Array = src.duplicate()
	SynthDSP.bandpass(low, rate, 760.0, 0.06)
	SynthDSP.bandpass(src, rate, 1680.0, 0.08)
	SynthDSP.mix_into(buf, low, 0, 1.0, false)
	SynthDSP.mix_into(buf, src, 0, 0.6, false)
	SynthDSP.tone_into(buf, rate, 0.5, 0.12, 110.0, 60.0, 0.5, W_SINE, 0.001, 0.03)
	SynthDSP.noise_into(buf, rate, 0.5, 0.05, 0.3, 0.001, 0.012, 600.0, 3000.0, 73)
	return buf


## Radio del vigilante: chasquido de silencio, voz distorsionada de banda estrecha, pitido final.
func _sfx_guard_radio(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.35, rate)
	var voice: PackedFloat32Array = SynthDSP.silence(1.35, rate)
	SynthDSP.babble_into(voice, rate, 0.1, 0.9, 125.0, 0.8, 79)
	SynthDSP.noise_into(voice, rate, 0.08, 0.95, 0.06, 0.0, 0.0, 0.0, 0.0, 83)
	SynthDSP.bandpass(voice, rate, 1300.0, 0.9)
	SynthDSP.soft_clip(voice, 4.0)
	SynthDSP.mix_into(buf, voice, 0, 0.8, false)
	SynthDSP.noise_into(buf, rate, 0.0, 0.08, 0.6, 0.001, 0.03, 1200.0, 0.0, 89)
	SynthDSP.noise_into(buf, rate, 1.05, 0.14, 0.5, 0.001, 0.05, 1500.0, 0.0, 97)
	SynthDSP.tone_into(buf, rate, 1.22, 0.07, 1000.0, 1000.0, 0.25, W_SINE, 0.002, 0.0)
	return buf


func _sfx_elevator_chime(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.8, rate)
	for note: Array in [[0.0, 659.25], [0.42, 523.25]]:
		SynthDSP.bell_into(buf, rate, note[0], 1.3, note[1], 0.5, 1.0, 0.5, 0.55)
		SynthDSP.bell_into(buf, rate, note[0], 0.6, note[1] * 2.0, 0.12, 3.5, 0.8, 0.2)
	return buf


## Megafonía del edificio: el "ding-dong-dong" que precede a un aviso de seguridad (sin vigilante cerca).
func _sfx_pa_chime(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(2.0, rate)
	for note: Array in [[0.0, 783.99], [0.38, 659.25], [0.76, 523.25]]:
		SynthDSP.bell_into(buf, rate, note[0], 1.1, note[1], 0.45, 1.0, 0.6, 0.5)
		SynthDSP.bell_into(buf, rate, note[0], 0.5, note[1] * 3.0, 0.08, 1.0, 0.9, 0.15)
	SynthDSP.noise_into(buf, rate, 0.0, 2.0, 0.04, 0.02, 0.1, 300.0, 3000.0, 113)
	SynthDSP.bandpass(buf, rate, 1200.0, 0.7)
	return buf


# ─── Recetas: señales especiales ─────────────────────────────────

## Flagrancia: golpe seco grave (el hilo musical se corta aparte durante un segundo).
func _sfx_caught_thud(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.1, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.9, 78.0, 32.0, 0.8, W_SINE, 0.001, 0.25)
	SynthDSP.tone_into(buf, rate, 0.0, 0.6, 46.0, 40.0, 0.3, W_TRI, 0.001, 0.3)
	SynthDSP.noise_into(buf, rate, 0.0, 0.03, 0.6, 0.001, 0.008, 800.0, 5000.0, 101)
	SynthDSP.noise_into(buf, rate, 0.0, 0.25, 0.7, 0.001, 0.05, 200.0, 2000.0, 103)
	for f: float in [110.0, 116.54, 164.81, 233.08]:
		SynthDSP.bell_into(buf, rate, 0.0, 1.0, f, 0.3, 1.0, 4.0, 0.35)
	return buf


## Vibración del móvil sobre la mesa: dos zumbidos con traqueteo.
func _sfx_phone_vibrate(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.0, rate)
	for start: float in [0.0, 0.5]:
		SynthDSP.tone_into(buf, rate, start, 0.35, 150.0, 146.0, 0.6, W_SAW, 0.01, 0.0)
		SynthDSP.noise_into(buf, rate, start, 0.35, 0.12, 0.01, 0.0, 2000.0, 0.0, 103)
	SynthDSP.amp_mod(buf, rate, 31.0, 0.45, false)
	SynthDSP.lowpass(buf, rate, 1300.0, 1)
	return buf


# ─── Recetas: alarmas por banda (bucle; §14.10 "la alarma varía por planta") ─

func _sfx_alarm_the_guts(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.6, rate)
	for start: float in [0.0, 0.8]:
		SynthDSP.tone_into(buf, rate, start, 0.55, 220.0, 214.0, 0.35, W_SAW, 0.01, 0.0)
		SynthDSP.tone_into(buf, rate, start, 0.55, 277.0, 270.0, 0.3, W_SAW, 0.01, 0.0)
	SynthDSP.soft_clip(buf, 3.0)
	SynthDSP.lowpass(buf, rate, 2800.0, 1)
	return buf


func _sfx_alarm_the_pit(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.6, rate)
	for k: int in 32:
		SynthDSP.bell_into(buf, rate, k * 0.05, 0.3, 950.0, 0.22, 2.76, 1.2, 0.08)
	return buf


func _sfx_alarm_the_specialists(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.6, rate)
	for start: float in [0.0, 0.8]:
		SynthDSP.tone_into(buf, rate, start, 0.7, 500.0, 1250.0, 0.5, W_SINE, 0.01, 0.0)
		SynthDSP.tone_into(buf, rate, start, 0.7, 1000.0, 2500.0, 0.08, W_SQUARE, 0.01, 0.0)
	return buf


func _sfx_alarm_the_power(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(2.0, rate)
	for note: Array in [[0.0, 523.25], [0.35, 659.25], [0.7, 783.99]]:
		SynthDSP.bell_into(buf, rate, note[0], 1.2, note[1], 0.3, 1.0, 0.4, 0.6)
	return buf


## Planta noble: un arpa, con urgencia (sátira).
func _sfx_alarm_the_throne(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.6, rate)
	var scale: Array[int] = [72, 74, 76, 79, 81, 84, 86, 88]
	for k: int in 16:
		var idx: int = k if k < 8 else 15 - k
		SynthDSP.pluck_into(buf, rate, k * 0.045, 0.9, SynthDSP.midi_hz(scale[idx]), 0.5, 0.995, k)
	return buf


func _sfx_alarm_factory(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.2, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.6, 600.0, 900.0, 0.35, W_SQUARE, 0.01, 0.0)
	SynthDSP.tone_into(buf, rate, 0.6, 0.6, 900.0, 600.0, 0.35, W_SQUARE, 0.0, 0.0)
	SynthDSP.lowpass(buf, rate, 3000.0, 1)
	return buf


func _sfx_alarm_exterior(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(1.6, rate)
	for k: int in 8:
		SynthDSP.tone_into(buf, rate, k * 0.2, 0.2, 900.0, 1700.0, 0.35, W_SAW, 0.005, 0.0)
	SynthDSP.lowpass(buf, rate, 4000.0, 1)
	return buf


# ─── Recetas: interfaz ───────────────────────────────────────────

func _sfx_ui_click(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.05, rate)
	SynthDSP.noise_into(buf, rate, 0.0, 0.006, 0.5, 0.0, 0.002, 2000.0, 0.0, 107)
	SynthDSP.tone_into(buf, rate, 0.0, 0.03, 2000.0, 1800.0, 0.3, W_SINE, 0.0, 0.006)
	return buf


func _sfx_ui_confirm(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.25, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.08, 880.0, 880.0, 0.35, W_SINE, 0.002, 0.05)
	SynthDSP.tone_into(buf, rate, 0.07, 0.15, 1320.0, 1320.0, 0.35, W_SINE, 0.002, 0.06)
	return buf


func _sfx_ui_error(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.25, rate)
	SynthDSP.tone_into(buf, rate, 0.0, 0.2, 220.0, 175.0, 0.35, W_SQUARE, 0.002, 0.0)
	SynthDSP.lowpass(buf, rate, 2000.0, 1)
	return buf


func _sfx_ui_notify(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.6, rate)
	SynthDSP.bell_into(buf, rate, 0.0, 0.5, 1046.5, 0.35, 1.0, 0.5, 0.25)
	SynthDSP.bell_into(buf, rate, 0.1, 0.5, 1568.0, 0.3, 1.0, 0.5, 0.25)
	return buf


## "Ka-ching": cajón de caja registradora + campanilla (sobornos, compras).
func _sfx_cash(rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.7, rate)
	SynthDSP.noise_into(buf, rate, 0.0, 0.04, 0.5, 0.001, 0.01, 1500.0, 0.0, 109)
	SynthDSP.bell_into(buf, rate, 0.05, 0.6, 2093.0, 0.3, 2.4, 1.5, 0.25)
	SynthDSP.bell_into(buf, rate, 0.12, 0.55, 2637.0, 0.3, 2.4, 1.5, 0.25)
	return buf
