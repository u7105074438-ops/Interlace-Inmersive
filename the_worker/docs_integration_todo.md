# Integration TODO (from the API gap pass over the simulation layer)

Open requests from the systems/UI phases that belong to **World** (`src/world/*`, `src/entities/*`,
`scenes/*`), **UI** (`src/ui/*`) or helpers that do not exist yet. Everything that concerned
`src/autoload`, `src/simulation`, `data/` or `tests/` was implemented in this pass (see BUILD_NOTES
§2 and §13 for the new contracts). One bullet per item: file → exact change.

## UI (`src/ui/*`)

Note: while this pass ran, the UI builders had already started adopting the new PlayerState API in
`notebook_app.gd` (get_notepad/set_notepad, get_notebook_entries), `personnel_app.gd`
(mark_target/unmark_target, get_notes_about) and `contacts_tab.gd` (get_contacts). At integration,
tick the bullets below that their final versions already satisfy.

- `src/ui/stellar_os/notebook_app.gd` → the free notepad is now `PlayerState.get_notepad()` /
  `PlayerState.set_notepad(text)`. Change `NOTES_GETTER`/`NOTES_SETTER` from `"get_notes"`/
  `"set_notes"` to `"get_notepad"`/`"set_notepad"`. (`PlayerState.get_notes()` now returns the
  note LIST `Array[Dictionary]` {id, day, hour, minute, text, npc_id}; `set_notes` does not exist,
  so today `notes_supported()` is false and the pad only lives while the window is open.)
  `get_notebook_entries()` and `get_marked_targets()` now exist on PlayerState: the log and target
  tabs already pick them up through the `has_method` probes; the PERSONNEL fallback can go.
- `src/ui/stellar_os/personnel_app.gd` → drop the static stores (`_targets`, `_notes`, `_studies`,
  `_full_files`, `_sync_store`). `set_marked(id, on)` → call only `PlayerState.mark_target(id)` /
  `unmark_target(id)`: they emit `notebook_entry_added("targets", "PERS_NOTE_TARGET_MARKED"|
  "_CLEARED", [name])` and NPCDirector keeps/releases LOD 0 ("marked_target") by itself — remove the
  direct `NPCDirector.force_full_lod/release_full_lod` calls and the own notebook emission.
  `add_note(npc_id, text)` → `PlayerState.add_note(text, npc_id)` (it logs `PERS_NOTE_ENTRY`
  [name, text]); `get_notes(npc_id)` → `PlayerState.get_notes_about(npc_id)` (entries have
  `day`/`hour`/`minute`, no `time` string: format with `UITheme.format_hour(hour, minute)`).
  `open_full_file(id, "hr_intrusion")` → `PlayerState.grant_full_file(id, reason)` (also gives the
  phone number). Studies → `PlayerState.record_study(id, action, result)` / `get_studies(id)`.
- `src/ui/mobile/contacts_tab.gd` → `PlayerState.get_contacts()` now exists and returns
  `{npc_id, source, day}` with `source ∈ proximity | favour | hr | purchase | messaged`.
  Map sources for display with `PlayerStateSystem.contact_source_key(source)` (keys
  `CONTACT_SOURCE_*`, EN+ES) or extend `SOURCE_KEYS`/`SOURCE_ORDER` with `proximity`
  (= colleague) and `purchase` (= bought); today `_from_player_state` would show those two with no
  label. The derived heuristics (affection ≥ `movil.afecto_minimo_contacto`, same office) are
  superseded: proximity is automatic after `movil.horas_proximidad_contacto` working hours in the
  same room; favours/messages/blackmail/HR are automatic. The "buy a number" flow must call
  `PlayerState.add_contact(npc_id, "purchase")`. Use `PlayerState.has_contact(id)` in `is_contact`.
- `src/ui/ui_root.gd` (`open_modal(..., pauses_clock=true)` / `close_modal`) → replace
  `GameClock.pause()`/`resume()` + `_clock_was_paused` bookkeeping by the ownership-counted pause:
  `GameClock.pause_by("ui_modal:%d" % modal.get_instance_id())` on open and
  `GameClock.resume_by(same_owner)` on close (the settings/pause menu can use `"pause_menu"`).
  `pause()/resume()` keep their old meaning for the run lifecycle.
- `src/ui/ui_root.gd` (or `hud.gd`) → connect `EventBus.occupation_changed` to
  `PromotionScreen.present(ui_root, old_id, new_id, reason)` (nothing calls it in game yet).
- `src/ui/debug_panel.gd:23` → `DEBUG_RECORD_TYPE := "camera_footage"` is the *investigation
  evidence* id; BeliefNet records use `BeliefNetSystem.RECORD_FOOTAGE` (`"footage"`). With
  "camera_footage" BeliefNet treats the record as an unknown, weightless fact.
- `src/ui/audio/audio_director.gd` → wait for / cancel the MuzakLibrary and ambience render jobs on
  exit (crash 134 / headless hang at process exit); optionally add `bus_engine`, `bus_brakes` to
  SfxBank.
- `src/ui/hud.gd` → connect `AudioDirector.mask_changed` to the acoustic-mask indicator; optional:
  shaft+head arrow in the subtitle feed instead of the chevron.
- `src/ui/settings_menu.gd` → after changing `text_size`, `high_contrast` or `subtitles`, call
  `UIRoot.apply_settings()` (or open it through `UIRoot.open_modal` so `setting_changed` is wired).
- Inventory/stash UI (whoever shows hidden items: `src/ui/inventory_ui.gd` or the hiding-spot
  dialog) → retrieve through `InventoryRules.retrieve_from_stash(spot_id, item_id)` (charges the
  retrieval minutes) and check `PlayerState.is_carrying(id)` (not `has_item`, which is also true for
  issued tools) before `remove_item`/`stash_item`/`dispose_item`.
- Idea watching (notebook "watch" tag / Aurora prep) → when the player starts following an idea
  owner, `NPCDirector.force_full_lod(owner, "watched_idea")`; `release_full_lod(owner,
  "watched_idea")` when they stop (or simply `PlayerState.mark_target(owner)`).

## World (`src/world/*`, `src/entities/*`, `scenes/*`)

- `src/world/game_root.gd` (not written yet) → lifecycle of BUILD_NOTES §2: `Database.load_all_or_halt()`
  at boot (show `Database.get_load_report()` and stop if false; also `src/world/boot.gd`),
  `GameClock.set_run_seed(seed)` before the resets, `generate_population`, `build_initial_graph`,
  the other resets, then emit `EventBus.run_started(seed)` once the world is built (GameClock
  resumes itself; `run_loaded` does it after `SaveSystem.load_run()` for Continue).
  `GameLaunch.consume()`: "new" → new run, `PlayerState.set_player_name(name)`,
  `Database.set_difficulty_preset(difficulty)` (now saved in run.json), `portrait_seed`, tutorial
  skip; "load" → `SaveSystem.load_run()`; "" → default QA run.
- `src/world/game_root.gd` → add `CaughtHandler.new()`, `DutySystem.new()`, `UIRoot.new()`,
  `AudioDirector.new()` as children. CaughtHandler/DutySystem save themselves (group
  `SaveSystemNode.SCENE_GROUP`); if they are created after `load_run()` they claim their state in
  `_ready` — nothing else to wire. Call `SaveSystem.save_run()` only at the END of the sleep
  sequence (it returns false after a game over). On `aurora_meeting_started` call
  `IdeaPresentation.summon_attendees()`. On `game_over` show
  `EpilogueScreen.show_epilogue(get_tree(), ending_id, context)`. Handle
  `NOTIFICATION_WM_GO_BACK_REQUEST`. Instance `scenes/world/player.tscn` under
  `streamer.get_actor_layer()`, `streamer.set_player(player)`, then after each `load_floor` call
  the camera's `set_bounds(streamer.get_floor_rect_px())` and `snap_to_target()`.
- Day cycle / sleep handler (World) → on `day_advanced`: `PlayerState.spend_money(
  PlayerState.get_daily_expenses(), "daily_expenses")`; if it fails, run the starvation check
  (§4.4, cause `starvation`); pay `PlayerState.add_money(PlayerState.get_daily_wage(), "wage")`;
  collect dividends with `MarketTrading.collect_broker_cash()`. Bed: emit
  `day_summary_ready({day, income_lines, expense_lines, reputation, reputation_delta, suspicion,
  suspicion_delta, missed_duties, completed_duties})` BEFORE `GameClock.advance_to_next_day()`.
- `src/simulation/perception.gd` (World-phase node) → use `NPCDirector.get_effective_perception()`
  as is (it already includes the suspicion term and Security's guard bonus); the
  `player_caught_redhanded.witnesses` count = OTHER NPCs with line of sight (not the catcher), then
  `CaughtHandler.set_witness_ids(catcher_id, witness_ids)` right after emitting; read the player's movement mode,
  crouch, stillness, sprint, current act and hiding state; apply acoustic masks listener-side;
  `set_debug_cones(bool)` (or read `DebugPanel.cones_visible`); detection indicator colours from
  `UITheme.palette(UITheme.current_high_contrast)`.
- `src/entities/npc.gd` (not written yet) → read `NPCDirector.get_current_location/get_lod/
  get_lod_update_interval`, report the real room with `set_current_location` /
  `release_current_location`; expose `npc_id` and `occupation_id`; walk with
  `FloorStreamer.get_seats_in_room` + `find_path_to_point`; `CharacterPainter.appearance_for_npc`,
  `tic_for_archetype`, `pose.look` toward anomalies, `anim_fps`/`next_frame`; show
  `IdeaPool.get_signalling_npcs()`; `play_sfx("chair_creak")` on stand-up,
  `play_sfx("elevator_chime", pos)` on elevator arrival; touch "quick card"
  (`UIRoot.open_modal(card, false)`).
- `src/world/interaction_router.gd` (crime emitters) → theft crimes carry `details.value` (€);
  non-lethal violence `details.violent: true`; framing `details.target`; company goods other than
  `theft_product` add `details.company_loss`; factory theft → `Company.add_theft_loss(value)` AND
  `crime_committed("theft_product", room, {value, loss_booked: true})`; server room →
  `crime_committed("records_deleted", "server_room", {record_ids | reader_id | camera_id})`;
  noises `noise_emitted` with sources `drawer`, `lock_forced` (every ~1.4 s while forcing),
  `break_object`, `freight_elevator`; refused card → `play_sfx("card_denied", pos)`. Provide
  `static func interact(target, player)` (or a node in group `interaction_router`) using
  `player.begin_act/end_act/play_anim` and `act_finished`. Travel: read `Interactable.data.transit`,
  `streamer.load_floor(target)` outside physics callbacks, place the player at
  `get_arrival_point(source_room, kind)`. Item drops: a node in group `item_drop_handlers` with
  `drop_player_item(item_id) -> bool`. Stash: `PlayerState.stash_item(item, spot, room)`.
- Card readers / cameras (World) → emit `card_reader_logged` ONLY for the player's swipes (reader
  doors via `FloorStreamer.door_crossed` / `get_door_between`); fixed cameras already emit
  `camera_recorded_player` (do not emit it again); power cut →
  `call_group("security_cameras", "set_active", false)`; `UIRoot.set_camera_watch(id, inside)` on
  entering/leaving a camera field; `Security.set_last_to_leave(npc_id)` when an NPC leaves the
  building last; room ids with `@floor` suffixes for transversal spaces.
- Body search (guard NPC / CaughtHandler caller in the world) → when
  `Security.can_search_player()`, call `InventoryRules.perform_body_search(
  Security.get_effective_suspicion())` (Security never confiscates by itself).
- `src/entities/player.gd` → `UIRoot.show_interactable(nearest_or_null)` when the focus changes;
  treat the runtime `sprint` action (VirtualControls) as sprint; do not bind map/phone/computer/
  inventory/F1 there.
- `src/world/floor_streamer.gd` / `room_builder.gd` → add the streamer to group `floor_streamer`
  (F1 teleport); `get_seats_in_room` should return the chair centre in pixels; cubicle y-sort
  (seated actors vanish under the cubicle prop: split the prop or raise seated z).
- `src/world/floor_layout.gd` → floor 21 (roof) has no corridor; ignore cross-floor `connects_to`
  (`ceo_office` ↔ `rooftop_terrace`) when placing rooms side by side (verify in test_floor_layout).
- `BUILD_NOTES.md §3` (World builder) → document the per-floor circulation (ground-floor
  turnstiles hall, S1 service landing, street, tunnel, hub floors).
- `src/entities/character_style.gd` → `FEMININE_FIRST_NAMES` mirrors the name bank of
  `npcs_generation.json`; if the data owner adds a presentation field to `name_bank`, read it.

## Helpers that do not exist yet (Endgame / later phases, `src/simulation/*`)

- Strike module → `Company.modify_discontent`, `apply_labour_event(id)`, `is_strike_active()`;
  emit `strike_resolved(resolution)` for betrayal/leadership outcomes.
- FactoryTheft → `Company.add_theft_loss(value)` + `crime_committed("theft_product", room,
  {value, loss_booked: true})`.
- Payroll manipulation discovered (§11.7 item 19) → whoever discovers it calls
  `Company.apply_labour_event("payroll_manipulation_discovered")`.
- Endgame → victory: emit `ownership_notarised`, then `game_over("ownership_notarised",
  Tracking.evaluate_ending(), Tracking.get_snapshot())`; every other terminal cause uses the ids of
  `endings.json causes` with `Tracking.evaluate_ending_for_cause(cause)` /
  `get_snapshot_for_cause(cause)`; mission state can live in `PlayerState.get_flag/set_flag`.
- Disguise → if uniforms grant room access, expose `grants_access(uniform_id, room) -> bool` so the
  map/HUD red halo can respect it.
- Bribes: a "cession and silence" favour for the idea purchase route (`bribes.json`) that calls
  `IdeaPool.acquire(idea, "purchase")` when accepted — needs a design ruling (price, which NPCs).

## Localisation (tools/check_locale.py)

- `src/ui/scene_stage.gd:39` → `"SCENE_UNKNOWN_COLLEAGUE"` is not in strings.csv (add EN+ES with
  tools/loc_add.py; re-run `tools/check_locale.py`).
- `src/util/autopilot_scenarios/audio.gd:230,273` → `"MSG_TEST"` is not in strings.csv (QA
  scenario; use an existing phone message key or add one with tools/loc_add.py).
- `NPC_STATE_WORKING … NPC_STATE_FLEEING` (9 keys) and `DEPT_BASE_FLOORS`, `ROLE_CHIEF_ACCOUNTANT`
  are unused by code today; kept in case the UI shows utility actions as states (loc_add cannot
  delete rows; remove them in a cleanup pass if nobody adopts them).
