extends Node

const SAVE_PATH := "user://save_slot_1.json"
const SAVE_VERSION := 1

var _pending_snapshot: Dictionary = {}


func has_valid_save() -> bool:
	return not load_snapshot().is_empty()


func save_snapshot(snapshot: Dictionary) -> bool:
	if not _is_valid_snapshot(snapshot):
		return false

	var save_data = snapshot.duplicate(true)
	save_data["save_version"] = SAVE_VERSION

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	return true


func load_snapshot() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
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


func stage_loaded_snapshot() -> bool:
	var snapshot = load_snapshot()
	if snapshot.is_empty():
		_pending_snapshot.clear()
		return false

	_pending_snapshot = snapshot.duplicate(true)
	return true


func consume_pending_snapshot() -> Dictionary:
	var snapshot = _pending_snapshot.duplicate(true)
	_pending_snapshot.clear()
	return snapshot


func discard_pending_snapshot() -> void:
	_pending_snapshot.clear()


func clear_invalid_cache_if_needed() -> void:
	if not has_valid_save():
		_pending_snapshot.clear()


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
		and snapshot.get("ui_page") is String
		and _is_number_variant(snapshot.get("selected_unread_index", 0))
		and _is_number_variant(snapshot.get("selected_day_index", 0))
		and _is_number_variant(snapshot.get("selected_day_value", 0))
		and _is_number_variant(snapshot.get("selected_message_index", 0))
		and snapshot.get("show_selected_mail_body", false) is bool
		and snapshot.get("mail_day_origin_page", "") is String
		and snapshot.get("day_label", "") is String
		and _is_number_variant(snapshot.get("current_day_number", 0))
		and snapshot.get("weather_label", "") is String
	)


func _is_number_variant(value) -> bool:
	return value is int or value is float
