# game_clock.gd — Reloj de juego: hora, jornada, semana, mes, trimestre y franja horaria.
# PROPIETARIO DE: hora, jornada, semana, mes, trimestre, franja activa, semilla de partida, pausa y velocidad.
# ESCUCHA: run_started, run_loaded.
class_name GameClockSystem
extends Node

## Manual §5.6, §15.1, §15.6, §19.2 (PASO 5); BUILD_NOTES §2, §6, §11, §13.
## Emite: time_band_changed, day_advanced, week_closed, month_closed, quarter_closed y las EXT
## hour_passed(hour, day) y time_skipped(from_hour, to_hour).
## DECISIONES (contrato para el resto de sistemas):
##  · Tiempo real → juego por franja: balance tiempo.minutos_reales_por_hora_por_franja (minutos
##    reales por hora de juego ≡ segundos reales por minuto de juego) da la FORMA del día; se escala
##    para que de hora_inicio_jornada (8:00) a hora_dormir_referencia (23:00) sume
##    tiempo.minutos_reales_por_jornada (11, PASO 5). Con los datos actuales la escala es 1: oficina
##    8-19 = 9 min reales; tarde-noche 19-23 = 2 min. Velocidad efectiva = set_speed_multiplier ×
##    set_accessibility_speed, nunca inferior a tiempo.multiplicador_velocidad_minimo (el reloj se
##    ralentiza, no se detiene). La accesibilidad se limita a menus.velocidad_reloj.min/max (el
##    mismo rango que ofrece el menú de ajustes).
##  · La jornada de juego va de 06:00 a 06:00. Tras la medianoche get_hour() vale 0..5 pero get_day()
##    sigue siendo la jornada anterior. El día avanza al dormir (advance_to_next_day) o a las
##    tiempo.hora_cambio_jornada (06:00) si el jugador pasa la noche en vela. "night" = 19:00-08:00.
##  · Cada hora de juego alcanzada emite, en orden: [cierres + day_advanced si es la hora de cambio]
##    → time_band_changed (si cambia la franja) → hour_passed(hora, jornada).
##  · Cierre de la jornada N: week_closed / month_closed / quarter_closed (si N es múltiplo de
##    jornadas_por_semana / _mes / _trimestre) y después day_advanced(N + 1). Durante los cierres
##    get_day() aún vale N y el reloj marca ya las 06:00 del cierre (get_day_minutes() = 1800,
##    get_total_minutes() = N × 1440, el mismo valor que tras day_advanced: el tiempo es monótono).
##  · Los saltos (advance_to_band, advance_to_next_day) recorren cada hora igual que el tiempo normal
##    (ningún oyente horario se pierde) y al final emiten time_skipped(from_hour, to_hour).
##  · reset_for_new_run() y load_state() dejan el reloj EN PAUSA; se reanuda solo al oír run_started
##    o run_loaded (la partida está viva: game_root los emite con el mundo ya construido). Así los
##    tests, que no emiten esas señales, no dependen del reloj real.
##  · advance_minutes(m) avanza m minutos de juego con la lógica de _process e ignora la pausa (tests,
##    coste temporal de deberes §10.6, depuración). advance_real_seconds(s) es lo que hace _process.

const BANDS: Array[String] = [
	"arrival", "work_morning", "lunch", "work_afternoon", "exit", "night",
]
const BAND_NAME_KEY_FORMAT := "TIME_BAND_%s"
const TIME_FORMAT := "%02d:%02d"
const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := MINUTES_PER_HOUR * HOURS_PER_DAY
const FIRST_DAY := 1
const NEUTRAL_SPEED := 1.0
## Tolerancia numérica para alinear el reloj con las marcas horarias exactas.
const EPSILON := 0.0001

const P_RATE_FORMAT := "tiempo.minutos_reales_por_hora_por_franja.%s"
const P_BAND_START_FORMAT := "tiempo.franjas_hora_inicio.%s"
const P_DAY_START := "tiempo.hora_inicio_jornada"
const P_DAY_END := "tiempo.hora_fin_jornada"
const P_ROLLOVER := "tiempo.hora_cambio_jornada"
const P_DAYS_WEEK := "tiempo.jornadas_por_semana"
const P_DAYS_MONTH := "tiempo.jornadas_por_mes"
const P_DAYS_QUARTER := "tiempo.jornadas_por_trimestre"
const P_MIN_SPEED := "tiempo.multiplicador_velocidad_minimo"
const P_REAL_MINUTES_PER_DAY := "tiempo.minutos_reales_por_jornada"
const P_SLEEP_HOUR := "tiempo.hora_dormir_referencia"
const P_ACCESS_MIN := "menus.velocidad_reloj.min"
const P_ACCESS_MAX := "menus.velocidad_reloj.max"

const S_DAY := "day"
const S_MINUTES := "minutes"
const S_SEED := "run_seed"

## Semilla de la partida (BUILD_NOTES §6): cada sistema siembra su RandomNumberGenerator con
## GameClock.get_run_seed(). reset_for_new_run() NO la cambia.
var _run_seed: int = 0
## 0 = no hay partida en curso.
var _day: int = 0
## Minutos desde la medianoche del día natural en que empezó la jornada; rango
## [hora_cambio × 60, hora_cambio × 60 + 1440): tras la medianoche supera 1440.
var _minutes: float = 0.0
var _band: String = ""
var _paused: bool = true
var _speed: float = NEUTRAL_SPEED
## Ajuste de accesibilidad (§13.10): pertenece al perfil, no a la partida; sobrevive a los resets.
var _access_speed: float = NEUTRAL_SPEED
var _observer_check: Callable = Callable()

# Configuración leída de balance.json (caché; se refresca en reset_for_new_run / load_state).
var _config_loaded: bool = false
var _rates: Dictionary = {}
## Factor que hace sumar minutos_reales_por_jornada a las tasas de 8:00 a hora_dormir_referencia.
var _rate_scale: float = NEUTRAL_SPEED
var _band_start: Dictionary = {}
var _day_start_min: float = 0.0
var _day_end_min: float = 0.0
var _rollover_min: float = 0.0
var _days_week: int = 0
var _days_month: int = 0
var _days_quarter: int = 0
var _min_speed: float = 0.0
var _access_min: float = NEUTRAL_SPEED
var _access_max: float = NEUTRAL_SPEED


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_loaded.connect(_on_run_loaded)


func _process(delta: float) -> void:
	if _paused or _day <= 0:
		return
	advance_real_seconds(delta)


func reset_for_new_run() -> void:
	_load_config()
	_day = FIRST_DAY
	_minutes = _day_start_min
	_band = _band_at(_minutes)
	_paused = true
	_speed = NEUTRAL_SPEED


# EXTRA (BUILD_NOTES §6): semilla de partida.
func get_run_seed() -> int:
	return _run_seed


@warning_ignore("shadowed_global_identifier")
func set_run_seed(seed: int) -> void:
	_run_seed = seed


## EXTRA (BUILD_NOTES §13): el mundo registra una función sin argumentos que devuelve true cuando
## hay observadores cerca o la ubicación no es segura (§15.6). Sin función registrada, no hay veto.
func set_observer_check(callable: Callable) -> void:
	_observer_check = callable


# ─── Consulta de estado ────────────────────────────────────────

func get_hour() -> int:
	return int(floorf(_minutes / MINUTES_PER_HOUR)) % HOURS_PER_DAY


func get_minute() -> int:
	return int(floorf(_minutes)) % MINUTES_PER_HOUR


func get_day() -> int:
	return _day


func get_week() -> int:
	return _period_of(_day, _days_week)


func get_month() -> int:
	return _period_of(_day, _days_month)


func get_quarter() -> int:
	return _period_of(_day, _days_quarter)


## "arrival" | "work_morning" | "lunch" | "work_afternoon" | "exit" | "night"
func get_current_band() -> String:
	return _band


## "13:42"
func get_time_string() -> String:
	return TIME_FORMAT % [get_hour(), get_minute()]


## De hora_inicio_jornada (8:00) a hora_fin_jornada (19:00) de la jornada en curso.
func is_working_hours() -> bool:
	return _minutes >= _day_start_min and _minutes < _day_end_min


## EXTRA: minutos desde la medianoche del día natural en que empezó la jornada (puede superar 1440
## después de medianoche). Útil para comparar con plazos: deadline_hour × 60.
func get_day_minutes() -> float:
	return _minutes


## EXTRA: marca temporal monótona en minutos de juego desde el inicio de la partida (jornada 1,
## hora de cambio). Sirve para ordenar eventos entre jornadas.
func get_total_minutes() -> float:
	if _day <= 0:
		return 0.0
	return float(_day - FIRST_DAY) * MINUTES_PER_DAY + (_minutes - _rollover_min)


## EXTRA: orden canónico de las franjas.
func get_band_order() -> Array[String]:
	return BANDS.duplicate()


## EXTRA: hora de inicio de una franja (balance tiempo.franjas_hora_inicio); -1 si no existe.
func get_band_start_hour(band: String) -> int:
	_ensure_config()
	return int(_band_start.get(band, -1))


## EXTRA: clave de strings.csv con el nombre visible de la franja ("TIME_BAND_LUNCH").
func get_band_name_key(band: String) -> String:
	return BAND_NAME_KEY_FORMAT % band.to_upper()


func is_paused() -> bool:
	return _paused


func get_speed_multiplier() -> float:
	return _speed


func get_accessibility_speed() -> float:
	return _access_speed


## EXTRA: minutos reales que dura una hora de juego en `band` a velocidad 1 (tasa de balance ×
## escala de minutos_reales_por_jornada). 0.0 si la franja no existe.
func get_real_minutes_per_game_hour(band: String) -> float:
	_ensure_config()
	return float(_rates.get(band, 0.0)) * _rate_scale


## Velocidad real aplicada: multiplicador × accesibilidad, con suelo en el mínimo de balance.
func get_effective_speed() -> float:
	_ensure_config()
	return maxf(_speed * _access_speed, _min_speed)


# ─── Control ───────────────────────────────────────────────────

func pause() -> void:
	_paused = true


func resume() -> void:
	_paused = false


## 0.4 dentro del ordenador (balance tiempo.velocidad_en_ordenador). Nunca detiene el reloj:
## valores por debajo de tiempo.multiplicador_velocidad_minimo se elevan a ese mínimo.
func set_speed_multiplier(mult: float) -> void:
	_ensure_config()
	_speed = maxf(mult, _min_speed)


## EXTRA (§13.10): ritmo del reloj elegido en accesibilidad, independiente de la dificultad.
## Se multiplica con set_speed_multiplier. Limitado a [menus.velocidad_reloj.min, .max].
func set_accessibility_speed(mult: float) -> void:
	_ensure_config()
	_access_speed = clampf(mult, _access_min, _access_max)


## Falla (false) si hay observadores (función de set_observer_check), si la franja no existe o si ya
## es la franja actual. Avanza hasta el inicio de la próxima aparición de `band`, procesando cada
## hora.
func advance_to_band(band: String) -> bool:
	if _day <= 0 or not BANDS.has(band) or band == _band:
		return false
	if _observers_present():
		return false
	_ensure_config()
	var target: float = float(int(_band_start.get(band, 0)) * MINUTES_PER_HOUR)
	_skip(_minutes_until_clock(target))
	return true


## Al dormir: salta a la próxima hora_inicio_jornada (8:00). Si el día aún no ha cambiado (dormir
## antes de las 06:00) emite day_advanced (y los cierres que toquen) por el camino; si ya cambió
## (en vela hasta las 06:00-07:59) solo avanza hasta las 8:00 de la misma jornada.
func advance_to_next_day() -> void:
	if _day <= 0:
		return
	_ensure_config()
	_skip(_minutes_until_clock(_day_start_min))


## EXTRA: avanza `minutes` minutos de juego exactamente como lo haría _process (señales incluidas).
## Ignora la pausa. Valores <= 0 no hacen nada.
func advance_minutes(minutes: float) -> void:
	if _day <= 0 or minutes <= 0.0:
		return
	_ensure_config()
	_advance_game_minutes(minutes)


## EXTRA: avanza `seconds` segundos reales con las tasas por franja y la velocidad efectiva
## (lo que hace _process cada fotograma). Ignora la pausa.
func advance_real_seconds(seconds: float) -> void:
	if _day <= 0:
		return
	_ensure_config()
	var remaining: float = seconds
	while remaining > 0.0:
		var sec_per_min: float = _real_seconds_per_game_minute()
		if sec_per_min <= 0.0:
			return
		var to_hour: float = _minutes_to_next_hour()
		var needed: float = to_hour * sec_per_min
		if remaining + EPSILON < needed:
			_advance_game_minutes(remaining / sec_per_min)
			return
		_advance_game_minutes(to_hour)
		remaining -= needed


## EXTRA (depuración / tests / carga): fija la hora sin emitir señales. Una hora anterior a la hora
## de cambio de jornada se interpreta como la madrugada de esa jornada.
func set_time(day: int, hour: int, minute: int) -> void:
	_ensure_config()
	_day = maxi(day, FIRST_DAY)
	var clock: float = float(hour * MINUTES_PER_HOUR + minute)
	if clock < _rollover_min:
		clock += MINUTES_PER_DAY
	_minutes = clock
	_band = _band_at(_minutes)


# ─── Utilidad ──────────────────────────────────────────────────

## Horas hasta hora_fin_jornada (19:00) de la jornada en curso; 0.0 si ya pasó.
func hours_until_closing() -> float:
	return maxf((_day_end_min - _minutes) / MINUTES_PER_HOUR, 0.0)


func days_since(day: int) -> int:
	return _day - day


# EXTRA: persistencia (SaveSystem.load_run() llama a load_state de cada sistema).
## La velocidad, la pausa y la función de observadores son estado transitorio: no se guardan.
func save_state() -> Dictionary:
	return {S_DAY: _day, S_MINUTES: _minutes, S_SEED: _run_seed}


func load_state(data: Dictionary) -> void:
	_load_config()
	_day = maxi(int(data.get(S_DAY, FIRST_DAY)), FIRST_DAY)
	_minutes = float(data.get(S_MINUTES, _day_start_min))
	_run_seed = int(data.get(S_SEED, _run_seed))
	_band = _band_at(_minutes)
	_paused = true
	_speed = NEUTRAL_SPEED


# ─── Interno: avance del tiempo ────────────────────────────────

func _advance_game_minutes(minutes: float) -> void:
	var remaining: float = minutes
	while remaining > 0.0:
		var to_boundary: float = _minutes_to_next_hour()
		if remaining + EPSILON < to_boundary:
			_minutes += remaining
			return
		_minutes = _next_hour_mark()
		remaining = maxf(remaining - to_boundary, 0.0)
		_on_hour_reached()


func _on_hour_reached() -> void:
	if _minutes + EPSILON >= _rollover_min + MINUTES_PER_DAY:
		_close_day()
	_update_band()
	EventBus.hour_passed.emit(get_hour(), _day)


## Los cierres se emiten con el reloj aún en la jornada N a las 06:00 (minutos = cambio + 1440):
## get_total_minutes() ya vale lo mismo que tras day_advanced (monótono).
func _close_day() -> void:
	var closing: int = _day
	if _is_period_end(closing, _days_week):
		EventBus.week_closed.emit(_period_of(closing, _days_week))
	if _is_period_end(closing, _days_month):
		EventBus.month_closed.emit(_period_of(closing, _days_month))
	if _is_period_end(closing, _days_quarter):
		EventBus.quarter_closed.emit(_period_of(closing, _days_quarter))
	_minutes -= MINUTES_PER_DAY
	_day = closing + 1
	EventBus.day_advanced.emit(_day)


func _update_band() -> void:
	var new_band: String = _band_at(_minutes)
	if new_band == _band:
		return
	var old_band: String = _band
	_band = new_band
	EventBus.time_band_changed.emit(old_band, new_band)


func _skip(minutes: float) -> void:
	var from_hour: int = get_hour()
	_advance_game_minutes(minutes)
	EventBus.time_skipped.emit(from_hour, get_hour())


func _observers_present() -> bool:
	if not _observer_check.is_valid():
		return false
	return bool(_observer_check.call())


func _real_seconds_per_game_minute() -> float:
	var speed: float = get_effective_speed()
	if speed <= 0.0:
		return 0.0
	return float(_rates.get(_band, 0.0)) * _rate_scale / speed


func _next_hour_mark() -> float:
	return (floorf(_minutes / MINUTES_PER_HOUR) + 1.0) * MINUTES_PER_HOUR


func _minutes_to_next_hour() -> float:
	return _next_hour_mark() - _minutes


## Minutos hasta la próxima vez que el reloj marque `clock_minutes` (minutos desde medianoche).
## Si ya lo marca, un día completo.
func _minutes_until_clock(clock_minutes: float) -> float:
	var delta: float = fposmod(clock_minutes - _minutes, float(MINUTES_PER_DAY))
	return delta if delta > EPSILON else float(MINUTES_PER_DAY)


func _band_at(minutes: float) -> String:
	return _band_for_hour(fposmod(minutes, float(MINUTES_PER_DAY)) / MINUTES_PER_HOUR, _band_start)


## Franja de una hora del día (0-24) según los inicios `band_starts`; fuera de las cinco primeras,
## "night".
static func _band_for_hour(hour: float, band_starts: Dictionary) -> String:
	for i: int in BANDS.size() - 1:
		var start: float = float(band_starts.get(BANDS[i], 0))
		var end: float = float(band_starts.get(BANDS[i + 1], 0))
		if hour >= start and hour < end:
			return BANDS[i]
	return BANDS[BANDS.size() - 1]


## EXTRA (pura): escala que hace que las horas [from_hour, to_hour) sumen `target_real_minutes`
## con las tasas por franja `rates` y los inicios `band_starts` (misma forma que balance). 1.0 si
## el tramo no suma nada.
static func compute_rate_scale(rates: Dictionary, band_starts: Dictionary, from_hour: int,
		to_hour: int, target_real_minutes: float) -> float:
	var total: float = 0.0
	for hour: int in range(from_hour, to_hour):
		total += float(rates.get(_band_for_hour(float(hour), band_starts), 0.0))
	return target_real_minutes / total if total > 0.0 else NEUTRAL_SPEED


static func _period_of(day: int, days_per_period: int) -> int:
	if day <= 0 or days_per_period <= 0:
		return 0
	return floori(float(day - FIRST_DAY) / float(days_per_period)) + 1


static func _is_period_end(day: int, days_per_period: int) -> bool:
	return days_per_period > 0 and day % days_per_period == 0


# ─── Interno: configuración ────────────────────────────────────

func _ensure_config() -> void:
	if not _config_loaded:
		_load_config()


func _load_config() -> void:
	_config_loaded = true
	for band: String in BANDS:
		_rates[band] = Database.get_balance_float(P_RATE_FORMAT % band)
		_band_start[band] = Database.get_balance_int(P_BAND_START_FORMAT % band)
	_day_start_min = float(Database.get_balance_int(P_DAY_START) * MINUTES_PER_HOUR)
	_day_end_min = float(Database.get_balance_int(P_DAY_END) * MINUTES_PER_HOUR)
	_rollover_min = float(Database.get_balance_int(P_ROLLOVER) * MINUTES_PER_HOUR)
	_days_week = Database.get_balance_int(P_DAYS_WEEK)
	_days_month = Database.get_balance_int(P_DAYS_MONTH)
	_days_quarter = Database.get_balance_int(P_DAYS_QUARTER)
	_min_speed = Database.get_balance_float(P_MIN_SPEED)
	_access_min = Database.get_balance_float(P_ACCESS_MIN)
	_access_max = Database.get_balance_float(P_ACCESS_MAX)
	_rate_scale = compute_rate_scale(_rates, _band_start, int(_day_start_min / MINUTES_PER_HOUR),
			Database.get_balance_int(P_SLEEP_HOUR),
			Database.get_balance_float(P_REAL_MINUTES_PER_DAY))


# ─── Oyentes ───────────────────────────────────────────────────

## La partida está viva (game_root la emite con el mundo listo): el reloj echa a andar.
func _on_run_started(_seed_value: int) -> void:
	if _day > 0:
		resume()


func _on_run_loaded(_day_number: int) -> void:
	if _day > 0:
		resume()
