# test_character_perf.gd — Escenario headless: una malla por pose de personaje (1 llamada de dibujo), teselado fiel al motor y con presupuesto por fotograma, caché LRU acotada y retención de mallas en pantalla.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends "res://tests/test_base.gd"


func case_path() -> String:
	return "res://tests/cases/character_perf_case.gd"
