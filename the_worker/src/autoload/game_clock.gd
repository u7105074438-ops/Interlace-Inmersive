# game_clock.gd — Reloj de juego: hora, jornada, semana, mes, trimestre y franja horaria.
# PROPIETARIO DE: hora, jornada, semana, mes, trimestre, franja horaria activa y semilla de partida.
# ESCUCHA: nada.
# STUB — implemented in PASO 5. Firmas exactas de §19.2; cuerpos con valores neutros.
class_name GameClockSystem
extends Node

## Semilla de la partida (BUILD_NOTES §6): cada sistema siembra su RandomNumberGenerator con
## GameClock.get_run_seed(). reset_for_new_run() NO debe cambiarla.
var _run_seed: int = 0


func reset_for_new_run() -> void:
	pass


# EXTRA (BUILD_NOTES §6): semilla de partida.
func get_run_seed() -> int:
	return _run_seed


@warning_ignore("shadowed_global_identifier")
func set_run_seed(seed: int) -> void:
	_run_seed = seed


# Consulta de estado
func get_hour() -> int:
	return 0


func get_minute() -> int:
	return 0


func get_day() -> int:
	return 0


func get_week() -> int:
	return 0


func get_month() -> int:
	return 0


func get_quarter() -> int:
	return 0


## "arrival" | "work_morning" | "lunch" | "work_afternoon" | "exit" | "night"
func get_current_band() -> String:
	return ""


## "13:42"
func get_time_string() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


func is_working_hours() -> bool:
	return false


# Control
func pause() -> void:
	pass


func resume() -> void:
	pass


## 0.4 dentro del ordenador.
func set_speed_multiplier(mult: float) -> void:
	pass


## Falla si hay observadores.
func advance_to_band(band: String) -> bool:
	return false


## Al dormir.
func advance_to_next_day() -> void:
	pass


# Utilidad
func hours_until_closing() -> float:
	return 0.0


func days_since(day: int) -> int:
	return 0


# EXTRA: persistencia (SaveSystem.load_run() llama a load_state de cada sistema).
func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
