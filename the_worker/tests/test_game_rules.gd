# test_game_rules.gd — Lanzador de las reglas de la sesión de juego (puertas y registros al cruzar, cierre de las 19:00, dormir, trayecto, observadores, continuar en frío, guardado ilegible).
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends "res://tests/test_base.gd"


func case_path() -> String:
	return "res://tests/cases/game_rules_case.gd"
