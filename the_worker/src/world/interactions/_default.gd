# _default.gd — Módulo de reserva del InteractionRouter: tipos sin módulo propio (y los apaños del bucle básico hasta que su módulo exista).
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends RefCounted

## No reclama tipos (handled_types vacío): el router lo usa para todo interact_type que ningún
## módulo atiende. Nunca promete lo que no hace: la indicación de un tipo sin módulo es la neutra
## UI_INTERACT_EXAMINE («Mirar») y la respuesta, el aviso educado INTERACT_NOTHING_USEFUL con un
## clic, para que ninguna pulsación quede sin respuesta.
## APAÑOS del bucle básico (se retiran solos en cuanto un módulo reclama el tipo; ese módulo debe
## conservar estos comportamientos):
##  · "npc" → ficha rápida del personaje (NPCLayer.open_card; «¿Quién es?») hasta social.gd.
##  · "bed" de hogar.sala_domicilio (acción sleep_save) → WorldBridges.request_sleep(): dormir,
##    resumen, jornada nueva y GUARDADO (§12.7) con confirmación. Otra cama → aviso neutro.
##  · "desk" del despacho propio → el ordenador (UIRoot.open_computer; WorldBridges sienta al
##    jugador). Una mesa ajena → «No es tu mesa».
##  · "turnstile" → pasar la tarjeta (DoorAccess.swipe: abre el torno si la acreditación llega; el
##    paso queda registrado al cruzarlo) o el pitido rojo de tarjeta denegada.

const NPC_TYPE := "npc"
const BED_TYPE := "bed"
const DESK_TYPE := "desk"
const TURNSTILE_TYPE := "turnstile"
const K_ACTION := "action"
const SLEEP_ACTION := "sleep_save"
const B_HOME := "hogar.sala_domicilio"
const EXAMINE_KEY := "UI_INTERACT_EXAMINE"
const NOTHING_KEY := "INTERACT_NOTHING_USEFUL"
const SFX_NOTHING := "ui_click"
const SFX_DENIED := "card_denied"


static func handled_types() -> Array[String]:
	return []


static func interact(interactable: Interactable, _player: Node, ctx: Dictionary) -> void:
	var ui: UIRoot = ctx.get("ui_root") as UIRoot
	match interactable.interact_type:
		NPC_TYPE:
			if _open_card(interactable):
				return
		BED_TYPE:
			if is_own_bed(interactable):
				await _sleep(interactable)
				return
		DESK_TYPE:
			if is_own_desk(interactable) and ui != null:
				ui.open_computer()
				return
			if ui != null:
				ui.toast("INTERACT_NOT_YOUR_DESK")
				return
		TURNSTILE_TYPE:
			_swipe(interactable, ui)
			return
	_nothing(interactable, ui)


## Indicación: la honesta de cada apaño; la neutra «Mirar» para todo tipo sin módulo.
static func prompt_key(interactable: Interactable) -> String:
	match interactable.interact_type:
		NPC_TYPE:
			return "UI_INTERACT_NPC_CARD"
		BED_TYPE:
			return "UI_INTERACT_SLEEP" if is_own_bed(interactable) else EXAMINE_KEY
		DESK_TYPE:
			return "UI_INTERACT_OWN_DESK" if is_own_desk(interactable) else EXAMINE_KEY
		TURNSTILE_TYPE:
			return ""
	return EXAMINE_KEY


static func is_own_bed(interactable: Interactable) -> bool:
	return str(interactable.data.get(K_ACTION, "")) == SLEEP_ACTION \
			or DatabaseSystem.get_room_base_id(interactable.room_id) == str(Database.get_balance(B_HOME))


static func is_own_desk(interactable: Interactable) -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	return occupation != null and DatabaseSystem.get_room_base_id(interactable.room_id) == occupation.office_room


static func _sleep(interactable: Interactable) -> void:
	var bridges: WorldBridges = WorldBridges.find(interactable.get_tree()) if interactable.is_inside_tree() else null
	if bridges != null:
		await bridges.request_sleep()


static func _swipe(interactable: Interactable, ui: UIRoot) -> void:
	var tree: SceneTree = interactable.get_tree() if interactable.is_inside_tree() else null
	var access: DoorAccess = DoorAccess.find(tree)
	var streamer: FloorStreamer = FloorStreamer.find_in(tree) if tree != null else null
	var gate: Door = streamer.get_door_by_id(interactable.interact_id) if streamer != null else null
	if access == null or gate == null:
		_nothing(interactable, ui)
		return
	if access.swipe(gate):
		if ui != null:
			ui.toast("INTERACT_TURNSTILE_OPEN", [], ToastStack.KIND_GOOD)
		return
	var audio: AudioDirector = AudioDirector.find(tree)
	if audio != null:
		audio.play_sfx(SFX_DENIED, gate.global_position)
	if ui != null:
		ui.toast("WORLD_TURNSTILE_DENIED", [gate.clearance], ToastStack.KIND_WARN)


static func _nothing(interactable: Interactable, ui: UIRoot) -> void:
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
