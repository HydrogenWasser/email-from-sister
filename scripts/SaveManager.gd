extends Node

const SAVE_SLOT_COUNT := 8
const SAVE_VERSION := 1
const EMPTY_SAVE_LABEL := "空栏位"

var _pending_snapshot: Dictionary = {}


func get_save_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot_index in SAVE_SLOT_COUNT:
		var snapshot = load_snapshot_from_slot(slot_index)
		var occupied = not snapshot.is_empty()
		slots.append({
			"slot_index": slot_index,
			"slot_number": slot_index + 1,
			"occupied": occupied,
			"save_time_unix": int(snapshot.get("save_time_unix", 0)) if occupied else 0,
			"save_time_label": str(snapshot.get("save_time_label", EMPTY_SAVE_LABEL)) if occupied else EMPTY_SAVE_LABEL,
			"disabled": not occupied
		})
	return slots


func has_any_valid_save() -> bool:
	for slot in get_save_slots():
		if bool(slot.get("occupied", false)):
			return true
	return false


func has_valid_save() -> bool:
	return has_any_valid_save()


func has_valid_save_in_slot(slot_index: int) -> bool:
	return not load_snapshot_from_slot(slot_index).is_empty()


func save_snapshot_to_slot(slot_index: int, snapshot: Dictionary) -> bool:
	if not _is_valid_slot_index(slot_index):
		return false

	if not _is_valid_snapshot(snapshot):
		return false

	var save_data = snapshot.duplicate(true)
	save_data["save_version"] = SAVE_VERSION
	save_data["save_time_unix"] = int(Time.get_unix_time_from_system())
	save_data["save_time_label"] = _build_save_time_label()

	var file = FileAccess.open(_get_slot_save_path(slot_index), FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	return true


func load_snapshot_from_slot(slot_index: int) -> Dictionary:
	if not _is_valid_slot_index(slot_index):
		return {}

	var save_path = _get_slot_save_path(slot_index)
	if not FileAccess.file_exists(save_path):
		return {}

	var file = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}

	var raw_text = file.get_as_text()
	file.close()
	if raw_text.strip_edges() == "":
		return {}

	var json = JSON.new()
	if json.parse(raw_text) != OK:
		return {}
	if not (json.data is Dictionary):
		return {}

	var snapshot: Dictionary = json.data
	if not _is_valid_snapshot(snapshot):
		return {}

	return snapshot


func save_snapshot(snapshot: Dictionary) -> bool:
	return save_snapshot_to_slot(0, snapshot)


func load_snapshot() -> Dictionary:
	return load_snapshot_from_slot(0)


func stage_loaded_snapshot_from_slot(slot_index: int) -> bool:
	var snapshot = load_snapshot_from_slot(slot_index)
	if snapshot.is_empty():
		_pending_snapshot.clear()
		return false

	_pending_snapshot = snapshot.duplicate(true)
	return true


func stage_loaded_snapshot() -> bool:
	return stage_loaded_snapshot_from_slot(0)


func consume_pending_snapshot() -> Dictionary:
	var snapshot = _pending_snapshot.duplicate(true)
	_pending_snapshot.clear()
	return snapshot


func discard_pending_snapshot() -> void:
	_pending_snapshot.clear()


func clear_invalid_cache_if_needed() -> void:
	if not _pending_snapshot.is_empty() and not _is_valid_snapshot(_pending_snapshot):
		_pending_snapshot.clear()


func _get_slot_save_path(slot_index: int) -> String:
	return "user://save_slot_%d.json" % [slot_index + 1]


func _is_valid_slot_index(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SAVE_SLOT_COUNT


func _build_save_time_label() -> String:
	var datetime = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(datetime.get("year", 0)),
		int(datetime.get("month", 0)),
		int(datetime.get("day", 0)),
		int(datetime.get("hour", 0)),
		int(datetime.get("minute", 0)),
		int(datetime.get("second", 0))
	]


func _is_valid_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return false

	var save_version_value = snapshot.get("save_version", SAVE_VERSION)
	if not _is_number_variant(save_version_value):
		return false

	var save_version = int(save_version_value)
	if save_version != SAVE_VERSION:
		return false

	if str(snapshot.get("current_scene_id", "")).strip_edges() == "":
		return false

	return (
		snapshot.get("global_values") is Dictionary
		and snapshot.get("introduced_mail_ids") is Dictionary
		and snapshot.get("read_mail_ids") is Dictionary
		and snapshot.get("removed_mail_ids") is Dictionary
		and snapshot.get("mail_body_overrides") is Dictionary
		and snapshot.get("ui_page") is String
		and _is_number_variant(snapshot.get("selected_unread_index", 0))
		and _is_number_variant(snapshot.get("selected_day_index", 0))
		and _is_number_variant(snapshot.get("selected_day_value", 0))
		and _is_number_variant(snapshot.get("selected_message_index", 0))
		and snapshot.get("show_selected_mail_body", false) is bool
		and snapshot.get("mail_day_origin_page", "") is String
		and _is_number_variant(snapshot.get("selected_main_choice_index", 0))
		and _is_number_variant(snapshot.get("selected_mail_home_index", 0))
		and _is_number_variant(snapshot.get("selected_mail_body_action_index", 0))
		and snapshot.get("day_label", "") is String
		and _is_number_variant(snapshot.get("current_day_number", 0))
		and snapshot.get("weather_label", "") is String
	)


func _is_number_variant(value) -> bool:
	return value is int or value is float
