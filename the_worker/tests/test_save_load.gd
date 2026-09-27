# test_save_load.gd — Escenario headless: guardar y cargar reproduce el estado exacto de todos los sistemas (§21), escritura atómica y permadeath.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends "res://tests/test_base.gd"


func case_path() -> String:
	return "res://tests/cases/save_load_case.gd"
