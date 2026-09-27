# hiding_spot.gd — Escondite de una sala: interactivo de tipo "hiding_spot" (bajo mesa, taquilla, cubo…).
# PROPIETARIO DE: nada más que su propia configuración (el contenido escondido es de PlayerState).
# ESCUCHA: nada.
class_name HidingSpot
extends Interactable

## Entrada de datos (§27): {id, type, pos, capacity, can_hide_body}. interact_type = "hiding_spot";
## spot_type = type de datos (under_desk, vent, toilet_stall, crate, supply_closet, curtain,
## archive_shelves, locker, car_trunk, dumpster). También en el grupo "hiding_spots".
## PlayerState.stash_item(item_id, spot_id, room_id) usa interact_id como spot_id.

const HIDING_GROUP := "hiding_spots"
const HIDING_TYPE := "hiding_spot"
const PROMPT_HIDE := "UI_INTERACT_HIDING_SPOT"

var spot_type: String = ""
var capacity: int = 0
var can_hide_body: bool = false


func setup_spot(entry: Dictionary, p_room_id: String, p_cell_px: float, center_px: Vector2) -> void:
	spot_type = str(entry.get("type", ""))
	capacity = int(entry.get("capacity", 0))
	can_hide_body = bool(entry.get("can_hide_body", false))
	setup(str(entry["id"]), HIDING_TYPE, p_room_id, entry.duplicate(true), p_cell_px, center_px)
	add_to_group(HIDING_GROUP)


func get_prompt_key() -> String:
	return PROMPT_HIDE
