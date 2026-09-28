# _default.gd — Módulo de reserva del InteractionRouter: tipos sin módulo propio.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends RefCounted

## No reclama tipos (handled_types vacío): el router lo usa para todo interact_type que ningún
## módulo atiende. "npc" (hasta que social.gd lo reclame) abre la ficha rápida del personaje
## (NPCLayer.open_card, §13.7 «toque sobre un personaje»). El resto: aviso educado
## INTERACT_NOTHING_USEFUL y un pequeño sonido, para que ninguna pulsación quede sin respuesta.

const NPC_TYPE := "npc"
const NOTHING_KEY := "INTERACT_NOTHING_USEFUL"
const SFX_NOTHING := "ui_click"


static func handled_types() -> Array[String]:
	return []


static func interact(interactable: Interactable, _player: Node, ctx: Dictionary) -> void:
	if interactable.interact_type == NPC_TYPE and _open_card(interactable):
		return
	var ui: UIRoot = ctx.get("ui_root") as UIRoot
	if ui != null:
		ui.toast(NOTHING_KEY)
	var audio: AudioDirector = AudioDirector.find(interactable.get_tree()) if interactable.is_inside_tree() else null
	if audio != null:
		audio.play_sfx(SFX_NOTHING)


static func _open_card(interactable: Interactable) -> bool:
	var layer: NPCLayer = NPCLayer.find(interactable.get_tree()) if interactable.is_inside_tree() else null
	var npc_id: String = str(interactable.data.get("npc_id", ""))
	if layer == null or npc_id.is_empty():
		return false
	return layer.open_card(npc_id) != null
