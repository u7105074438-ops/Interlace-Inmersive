# game_session_fake_module.gd — Módulo de interacción falso para test_game_session (contrato del InteractionRouter, BUILD_NOTES §15).
# PROPIETARIO DE: el registro estático de llamadas recibidas.
# ESCUCHA: nada.
extends RefCounted

const FAKE_TYPE := "qa_fake_type"
const FAKE_PROMPT := "UI_INTERACT_GENERIC"

static var calls: Array[Dictionary] = []


static func handled_types() -> Array[String]:
	return [FAKE_TYPE]


static func interact(interactable: Interactable, player: Node, ctx: Dictionary) -> void:
	calls.append({"id": interactable.interact_id, "player": player, "ctx": ctx})


static func is_available(interactable: Interactable, _player: Node) -> bool:
	return not bool(interactable.data.get("blocked", false))


static func prompt_key(_interactable: Interactable) -> String:
	return FAKE_PROMPT
