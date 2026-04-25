extends Node

const PAGE_MAIN := "MAIN"
const PAGE_MAIL_HOME := "MAIL_HOME"
const PAGE_MAIL_UNREAD_LIST := "MAIL_UNREAD_LIST"
const PAGE_MAIL_READ_DAY_LIST := "MAIL_READ_DAY_LIST"
const PAGE_MAIL_DAY_MESSAGE_LIST := "MAIL_DAY_MESSAGE_LIST"

const MAIN_MENU_SCENE_PATH := "res://scenes/MainMenu.tscn"
const MAIL_HOME_TARGET := "__MAIL_HOME__"
const READ_ALL_EMAILS_GLOBAL_NAME := "ReadAllEmails"
const SAN_GLOBAL_NAME := "SAN"
const DAY_TAG_PREFIX := "第"
const DAY_TAG_SUFFIX := "天"

@export_file("*.json") var story_file_path: String = "res://data/Story.json"
@export_file("*.json") var mail_file_path: String = "res://data/MailData.json"
@export_dir var mail_directory_path: String = "res://data/Emails"

var initialized: bool = false

var story_title: String = "Email From Sister"
var start_node_id: String = ""
var story_nodes: Dictionary = {}
var story_global_definitions: Array[Dictionary] = []
var story_globals: Dictionary = {}
var global_values: Dictionary = {}
var read_all_emails_global_id: String = ""
var san_global_id: String = ""
var current_scene_id: String = ""
var current_scene_data: Dictionary = {}

var ui_page: String = PAGE_MAIN
var default_day_label: String = "第 4 天"
var day_label: String = default_day_label
var current_day_number: int = 4
var weather_label: String = "晴朗"
var transient_hint: String = ""
var warning_messages: Array[String] = []

var mail_entries: Array[Dictionary] = []
var introduced_mail_ids: Dictionary = {}
var read_mail_ids: Dictionary = {}
var removed_mail_ids: Dictionary = {}
var mail_body_overrides: Dictionary = {}
var selected_unread_index: int = 0
var selected_day_index: int = 0
var selected_day_value: int = -1
var selected_message_index: int = 0
var show_selected_mail_body: bool = false
var mail_day_origin_page: String = PAGE_MAIL_READ_DAY_LIST
var selected_main_choice_index: int = 0
var selected_mail_home_index: int = 0
var selected_mail_body_action_index: int = 0


func _ready() -> void:
	initialize_game()


func initialize_game() -> void:
	if initialized:
		return

	_load_story_data()
	_load_mail_data()
	_initialize_story_globals()
	_open_start_scene()
	initialized = true


func _load_story_data() -> void:
	story_nodes.clear()
	story_global_definitions.clear()

	if story_file_path == "":
		_create_default_story()
		return

	var story_data = _load_json_file(story_file_path)
	if story_data.is_empty():
		_create_default_story()
		return

	var metadata = story_data.get("metadata", {})
	if metadata is Dictionary:
		story_title = str(metadata.get("title", story_title)).strip_edges()
		start_node_id = str(metadata.get("startNodeId", "")).strip_edges()

	var raw_globals = story_data.get("globals", [])
	if raw_globals is Array:
		for global_value in raw_globals:
			if global_value is Dictionary:
				story_global_definitions.append(global_value)

	var raw_nodes = story_data.get("nodes", [])
	if raw_nodes is Array:
		for node_value in raw_nodes:
			if not (node_value is Dictionary):
				continue

			var node_dict: Dictionary = node_value
			var node_id = str(node_dict.get("id", "")).strip_edges()
			if node_id == "":
				continue

			story_nodes[node_id] = node_dict
	elif raw_nodes is Dictionary:
		story_nodes = raw_nodes.duplicate(true)
		if start_node_id == "":
			start_node_id = str(story_data.get("start_node", "")).strip_edges()
		story_title = str(story_data.get("title", story_title)).strip_edges()

	if start_node_id == "" and not story_nodes.is_empty():
		start_node_id = str(story_nodes.keys()[0]).strip_edges()

	if story_nodes.is_empty():
		_create_default_story()


func _create_default_story() -> void:
	start_node_id = "fallback_intro"
	story_title = "Email From Sister"
	story_global_definitions.clear()
	story_nodes = {
		"fallback_intro": {
			"id": "fallback_intro",
			"title": "开始",
			"body": "故事文件加载失败。",
			"choices": []
		}
	}


func _load_mail_data() -> void:
	mail_entries.clear()
	introduced_mail_ids.clear()
	read_mail_ids.clear()
	removed_mail_ids.clear()
	mail_body_overrides.clear()
	default_day_label = "第 4 天"
	day_label = default_day_label
	current_day_number = 4
	weather_label = "晴朗"

	if mail_file_path != "":
		var mailbox_data = _load_json_file(mail_file_path)
		if not mailbox_data.is_empty():
			default_day_label = str(mailbox_data.get("defaultDayLabel", default_day_label)).strip_edges()
			weather_label = str(mailbox_data.get("defaultWeatherLabel", weather_label)).strip_edges()

	day_label = default_day_label
	var parsed_default_day = _parse_day_tag(default_day_label)
	if parsed_default_day >= 0:
		current_day_number = parsed_default_day

	_load_mail_entries_from_directory()


func _load_mail_entries_from_directory() -> void:
	if mail_directory_path == "":
		return

	var directory = DirAccess.open(mail_directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	while true:
		var file_name = directory.get_next()
		if file_name == "":
			break
		if directory.current_is_dir() or not file_name.to_lower().ends_with(".txt"):
			continue

		var entry = _build_mail_entry_from_file(file_name)
		if not entry.is_empty():
			mail_entries.append(entry)
	directory.list_dir_end()

	mail_entries.sort_custom(_sort_mail_entry_ascending)


func _build_mail_entry_from_file(file_name: String) -> Dictionary:
	var base_name = file_name.get_basename()
	var segments = base_name.split("-")
	if segments.size() != 3:
		return {}

	var day_segment = _unwrap_bracket_segment(segments[0])
	var label_segment = _unwrap_bracket_segment(segments[1])
	var sender_segment = _unwrap_bracket_segment(segments[2])
	var day_number = _parse_day_tag(day_segment)
	if day_number < 0:
		return {}

	var mail_number = _parse_mail_number(label_segment)
	var file_path = mail_directory_path.path_join(file_name)
	var body_text = _load_text_file(file_path).strip_edges()
	if body_text == "":
		return {}

	return {
		"id": file_name,
		"sender": sender_segment if sender_segment != "" else "妹妹",
		"day": day_number,
		"time": "",
		"label": label_segment,
		"title": "",
		"body": body_text,
		"mail_number": mail_number
	}


func _unwrap_bracket_segment(value: String) -> String:
	var trimmed = value.strip_edges()
	if trimmed.begins_with("[") and trimmed.ends_with("]") and trimmed.length() >= 2:
		return trimmed.substr(1, trimmed.length() - 2).strip_edges()
	return trimmed


func _parse_mail_number(label_text: String) -> int:
	var trimmed = label_text.strip_edges()
	if not trimmed.begins_with("第") or not trimmed.ends_with("封"):
		return -1

	var middle = trimmed.substr(1, trimmed.length() - 2).strip_edges()
	if not middle.is_valid_int():
		return -1

	return int(middle)


func _sort_mail_entry_ascending(a: Dictionary, b: Dictionary) -> bool:
	var day_a = int(a.get("day", 0))
	var day_b = int(b.get("day", 0))
	if day_a != day_b:
		return day_a < day_b

	var number_a = int(a.get("mail_number", 0))
	var number_b = int(b.get("mail_number", 0))
	if number_a != number_b:
		return number_a < number_b

	return str(a.get("id", "")) < str(b.get("id", ""))


func _initialize_story_globals() -> void:
	story_globals.clear()
	global_values.clear()
	read_all_emails_global_id = ""
	san_global_id = ""

	for global_definition in story_global_definitions:
		var global_id = str(global_definition.get("id", "")).strip_edges()
		if global_id == "":
			continue

		var value_type = str(global_definition.get("valueType", "")).strip_edges().to_lower()
		var default_value = _coerce_global_value_by_type(value_type, global_definition.get("defaultValue"))
		var global_meta := {
			"id": global_id,
			"name": str(global_definition.get("name", "")).strip_edges(),
			"value_type": value_type,
			"default_value": default_value
		}

		story_globals[global_id] = global_meta
		global_values[global_id] = default_value

		if str(global_meta.get("name", "")) == READ_ALL_EMAILS_GLOBAL_NAME:
			read_all_emails_global_id = global_id
		if str(global_meta.get("name", "")) == SAN_GLOBAL_NAME:
			san_global_id = global_id


func _open_start_scene() -> void:
	if start_node_id == "" or not story_nodes.has(start_node_id):
		_create_default_story()

	_set_main_scene(start_node_id)


func _set_main_scene(scene_id: String) -> bool:
	if not story_nodes.has(scene_id):
		transient_hint = "目标场景不存在：%s" % scene_id
		return false

	current_scene_id = scene_id
	current_scene_data = story_nodes[scene_id]
	ui_page = PAGE_MAIN
	show_selected_mail_body = false
	warning_messages.clear()
	transient_hint = ""
	_update_day_label_from_scene(current_scene_data)
	_trigger_file_triggers_for_scene(current_scene_data)
	if _scene_has_tag(current_scene_data, "End"):
		call_deferred("_return_to_main_menu")
	return true


func _update_day_label_from_scene(scene_data: Dictionary) -> void:
	var tags_value = scene_data.get("tags", [])
	if not (tags_value is Array):
		return

	for tag_value in tags_value:
		var tag_text = str(tag_value).strip_edges()
		var parsed_day = _parse_day_tag(tag_text)
		if parsed_day >= 0:
			day_label = "第 %d 天" % parsed_day
			current_day_number = parsed_day
			return


func _scene_has_tag(scene_data: Dictionary, target_tag: String) -> bool:
	var tags_value = scene_data.get("tags", [])
	if not (tags_value is Array):
		return false

	for tag_value in tags_value:
		if str(tag_value).strip_edges() == target_tag:
			return true

	return false


func _return_to_main_menu() -> void:
	var tree = get_tree()
	if tree == null:
		return

	tree.change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _parse_day_tag(tag_text: String) -> int:
	if not tag_text.begins_with(DAY_TAG_PREFIX) or not tag_text.ends_with(DAY_TAG_SUFFIX):
		return -1

	if tag_text.length() < DAY_TAG_PREFIX.length() + DAY_TAG_SUFFIX.length() + 1:
		return -1

	var middle = tag_text.substr(
		DAY_TAG_PREFIX.length(),
		tag_text.length() - DAY_TAG_PREFIX.length() - DAY_TAG_SUFFIX.length()
	).strip_edges()
	if not middle.is_valid_int():
		return -1

	return int(middle)


func get_current_ui_page() -> String:
	return ui_page


func get_day_label() -> String:
	return day_label


func get_weather_label() -> String:
	return weather_label


func get_san_debug_label() -> String:
	if san_global_id == "" or not global_values.has(san_global_id):
		return "N/A"

	return str(global_values[san_global_id])


func build_save_snapshot() -> Dictionary:
	initialize_game()

	return {
		"save_version": 1,
		"current_scene_id": current_scene_id,
		"global_values": global_values.duplicate(true),
		"introduced_mail_ids": introduced_mail_ids.duplicate(true),
		"read_mail_ids": read_mail_ids.duplicate(true),
		"removed_mail_ids": removed_mail_ids.duplicate(true),
		"mail_body_overrides": mail_body_overrides.duplicate(true),
		"ui_page": ui_page,
		"selected_unread_index": selected_unread_index,
		"selected_day_index": selected_day_index,
		"selected_day_value": selected_day_value,
		"selected_message_index": selected_message_index,
		"show_selected_mail_body": show_selected_mail_body,
		"mail_day_origin_page": mail_day_origin_page,
		"selected_main_choice_index": selected_main_choice_index,
		"selected_mail_home_index": selected_mail_home_index,
		"selected_mail_body_action_index": selected_mail_body_action_index,
		"day_label": day_label,
		"current_day_number": current_day_number,
		"weather_label": weather_label
	}


func apply_save_snapshot(snapshot: Dictionary) -> bool:
	initialize_game()
	if snapshot.is_empty():
		return false

	var scene_id = str(snapshot.get("current_scene_id", "")).strip_edges()
	if scene_id == "" or not story_nodes.has(scene_id):
		return false

	_initialize_story_globals()
	_apply_saved_global_values(snapshot.get("global_values", {}))

	introduced_mail_ids = _restore_saved_mail_flags(snapshot.get("introduced_mail_ids", {}))
	read_mail_ids = _restore_saved_mail_flags(snapshot.get("read_mail_ids", {}))
	removed_mail_ids = _restore_saved_mail_flags(snapshot.get("removed_mail_ids", {}))
	mail_body_overrides = _restore_saved_mail_body_overrides(snapshot.get("mail_body_overrides", {}))
	for read_mail_id in read_mail_ids.keys():
		introduced_mail_ids[read_mail_id] = true
	for removed_mail_id in removed_mail_ids.keys():
		introduced_mail_ids.erase(removed_mail_id)
		read_mail_ids.erase(removed_mail_id)
	_apply_saved_mail_body_overrides()

	current_scene_id = scene_id
	current_scene_data = story_nodes[scene_id]
	ui_page = _restore_saved_page(str(snapshot.get("ui_page", PAGE_MAIN)).strip_edges())
	selected_unread_index = int(snapshot.get("selected_unread_index", 0))
	selected_day_index = int(snapshot.get("selected_day_index", 0))
	selected_day_value = int(snapshot.get("selected_day_value", -1))
	selected_message_index = int(snapshot.get("selected_message_index", 0))
	show_selected_mail_body = bool(snapshot.get("show_selected_mail_body", false))
	mail_day_origin_page = _restore_mail_origin_page(str(snapshot.get("mail_day_origin_page", PAGE_MAIL_READ_DAY_LIST)).strip_edges())
	selected_main_choice_index = int(snapshot.get("selected_main_choice_index", 0))
	selected_mail_home_index = int(snapshot.get("selected_mail_home_index", 0))
	selected_mail_body_action_index = int(snapshot.get("selected_mail_body_action_index", 0))

	var restored_day_label = str(snapshot.get("day_label", default_day_label)).strip_edges()
	day_label = restored_day_label if restored_day_label != "" else default_day_label
	current_day_number = int(snapshot.get("current_day_number", current_day_number))

	var restored_weather = str(snapshot.get("weather_label", weather_label)).strip_edges()
	if restored_weather != "":
		weather_label = restored_weather

	transient_hint = ""
	warning_messages.clear()
	_sync_read_all_emails_global_from_mailbox()
	_clamp_restored_ui_state()
	return true


func get_page_body_text() -> String:
	match ui_page:
		PAGE_MAIN:
			return _build_main_page_body()
		PAGE_MAIL_HOME:
			return _build_mail_home_body()
		PAGE_MAIL_UNREAD_LIST:
			return _build_unread_mail_body()
		PAGE_MAIL_READ_DAY_LIST:
			return _build_read_day_body()
		PAGE_MAIL_DAY_MESSAGE_LIST:
			return _build_day_message_body()
		_:
			return ""


func get_page_options_text() -> String:
	return "\n".join(get_page_option_lines())


func get_page_option_entries() -> Array[Dictionary]:
	match ui_page:
		PAGE_MAIN:
			return _get_main_option_entries()
		PAGE_MAIL_HOME:
			return _get_mail_home_option_entries()
		PAGE_MAIL_UNREAD_LIST:
			return _get_unread_option_entries()
		PAGE_MAIL_READ_DAY_LIST:
			return _get_read_day_option_entries()
		PAGE_MAIL_DAY_MESSAGE_LIST:
			return _get_day_message_option_entries()
		_:
			return []


func get_page_option_lines() -> Array[String]:
	return _build_option_lines_from_entries(get_page_option_entries())


func supports_cursor_navigation() -> bool:
	return not get_page_option_lines().is_empty()


func move_cursor(direction: int) -> void:
	if direction == 0:
		return

	match ui_page:
		PAGE_MAIN:
			selected_main_choice_index = _wrap_index(selected_main_choice_index + direction, _get_main_choices().size())
		PAGE_MAIL_HOME:
			selected_mail_home_index = _wrap_index(selected_mail_home_index + direction, _get_mail_home_options().size())
		PAGE_MAIL_UNREAD_LIST:
			selected_unread_index = _wrap_index(selected_unread_index + direction, _get_unread_option_count())
		PAGE_MAIL_READ_DAY_LIST:
			var read_days = _get_read_days()
			selected_day_index = _wrap_index(selected_day_index + direction, _get_read_day_option_count())
			if not read_days.is_empty() and selected_day_index < read_days.size():
				selected_day_value = read_days[selected_day_index]
		PAGE_MAIL_DAY_MESSAGE_LIST:
			if show_selected_mail_body:
				selected_mail_body_action_index = _wrap_index(
					selected_mail_body_action_index + direction,
					_get_mail_body_action_options().size()
				)
			else:
				selected_message_index = _wrap_index(selected_message_index + direction, _get_day_message_option_count())


func confirm_current_selection() -> void:
	match ui_page:
		PAGE_MAIN:
			var main_choices = _get_main_choices()
			if main_choices.is_empty():
				return
			selected_main_choice_index = _wrap_index(selected_main_choice_index, main_choices.size())
			_execute_main_choice(main_choices[selected_main_choice_index])
		PAGE_MAIL_HOME:
			var mail_home_options = _get_mail_home_options()
			if mail_home_options.is_empty():
				return
			selected_mail_home_index = _wrap_index(selected_mail_home_index, mail_home_options.size())
			match str(mail_home_options[selected_mail_home_index].get("id", "")):
				"unread":
					_open_unread_mail_list()
				"read":
					_open_read_day_list()
				"exit":
					ui_page = PAGE_MAIN
					show_selected_mail_body = false
		PAGE_MAIL_UNREAD_LIST:
			var unread_mails = _get_unread_mails()
			selected_unread_index = _wrap_index(selected_unread_index, _get_unread_option_count())
			if unread_mails.is_empty() or selected_unread_index >= unread_mails.size():
				_open_mail_home()
				return
			_open_unread_mail(selected_unread_index)
		PAGE_MAIL_READ_DAY_LIST:
			var read_days = _get_read_days()
			selected_day_index = _wrap_index(selected_day_index, _get_read_day_option_count())
			if read_days.is_empty() or selected_day_index >= read_days.size():
				_open_mail_home()
				return
			selected_day_value = read_days[selected_day_index]
			_open_selected_day_messages(PAGE_MAIL_READ_DAY_LIST)
		PAGE_MAIL_DAY_MESSAGE_LIST:
			if show_selected_mail_body:
				var body_actions = _get_mail_body_action_options()
				if body_actions.is_empty():
					return
				selected_mail_body_action_index = _wrap_index(selected_mail_body_action_index, body_actions.size())
				match str(body_actions[selected_mail_body_action_index].get("id", "")):
					"unread":
						_open_unread_mail_list()
					"read":
						_open_read_day_list()
					"exit":
						ui_page = PAGE_MAIN
						show_selected_mail_body = false
				return

			var day_messages = _get_day_messages(selected_day_value)
			selected_message_index = _wrap_index(selected_message_index, _get_day_message_option_count())
			if day_messages.is_empty() or selected_message_index >= day_messages.size():
				_return_to_day_origin()
				return
			show_selected_mail_body = true


func process_command(raw_command: String) -> void:
	var command = raw_command.strip_edges()
	if command == "":
		return

	transient_hint = ""

	if _process_global_command(command):
		return

	match ui_page:
		PAGE_MAIN:
			_process_main_command(command)
		PAGE_MAIL_HOME:
			_process_mail_home_command(command)
		PAGE_MAIL_UNREAD_LIST:
			_process_mail_unread_command(command)
		PAGE_MAIL_READ_DAY_LIST:
			_process_mail_read_day_command(command)
		PAGE_MAIL_DAY_MESSAGE_LIST:
			_process_mail_day_message_command(command)


func _process_global_command(command: String) -> bool:
	var normalized = _normalize_input(command)
	match normalized:
		"help", "帮助":
			transient_hint = _build_help_text()
			return true
		"clear", "清屏":
			transient_hint = ""
			return true
		"stats", "状态":
			transient_hint = _build_stats_text()
			return true
		"quit", "退出游戏":
			get_tree().quit()
			return true
		_:
			return false


func _build_help_text() -> String:
	var lines: Array[String] = [
		"全局指令：help/帮助、clear/清屏、stats/状态、quit/退出游戏"
	]

	match ui_page:
		PAGE_MAIN:
			lines.append("主界面：输入数字或选项文本推进剧情。")
		PAGE_MAIL_HOME:
			lines.append("邮件首页：输入 1 查看未读，输入 2 查看已读，输入 3 返回主界面。")
		PAGE_MAIL_UNREAD_LIST, PAGE_MAIL_READ_DAY_LIST, PAGE_MAIL_DAY_MESSAGE_LIST:
			lines.append("邮件列表：使用方向键或“上一个 / 下一个”切换高亮，输入“查看”打开当前项，输入“返回”回到上一层。")

	return "\n".join(lines)


func _build_stats_text() -> String:
	var lines: Array[String] = [
		"当前页面：%s" % ui_page,
		"当前天数：%s" % day_label,
		"天气：%s" % weather_label,
		"未读邮件：%d" % _get_unread_mails().size()
	]

	if not global_values.is_empty():
		var global_lines: Array[String] = []
		for global_id in global_values.keys():
			var meta: Dictionary = story_globals.get(global_id, {})
			var display_name = str(meta.get("name", global_id)).strip_edges()
			global_lines.append("%s = %s" % [display_name, str(global_values[global_id])])
		global_lines.sort()
		lines.append("全局变量：\n%s" % "\n".join(global_lines))

	return "\n".join(lines)


func _process_main_command(command: String) -> void:
	var choices = _get_main_choices()
	if choices.is_empty():
		return

	if command.is_valid_int():
		var selected_index = int(command) - 1
		if selected_index >= 0 and selected_index < choices.size():
			_execute_main_choice(choices[selected_index])
			return

	for choice in choices:
		if _command_matches_choice(command, choice):
			_execute_main_choice(choice)
			return


func _process_mail_home_command(command: String) -> void:
	var normalized = _normalize_input(command)
	match normalized:
		"1", "未读", "查看未读", "查看未读邮件":
			_open_unread_mail_list()
		"2", "已读", "查看已读", "查看已读邮件":
			_open_read_day_list()
		"3", "返回", "退出", "回去", "主界面":
			ui_page = PAGE_MAIN
			show_selected_mail_body = false
		_:
			return


func _process_mail_unread_command(command: String) -> void:
	var unread_mails = _get_unread_mails()
	if unread_mails.is_empty():
		if _normalize_input(command) == "1" or _is_previous_command(command):
			_open_mail_home()
		return

	if _normalize_input(command) == "上一个":
		move_cursor(-1)
		return

	if _is_next_command(command):
		move_cursor(1)
		return

	if _is_previous_command(command) or _normalize_input(command) == "2":
		_open_mail_home()
		return

	if _normalize_input(command) == "1" or _is_confirm_command(command):
		_open_unread_mail(selected_unread_index)
		return


func _process_mail_read_day_command(command: String) -> void:
	var read_days = _get_read_days()
	if read_days.is_empty():
		if _normalize_input(command) == "1" or _is_previous_command(command):
			_open_mail_home()
		return

	if _normalize_input(command) == "上一个":
		move_cursor(-1)
		return

	if _is_next_command(command):
		move_cursor(1)
		return

	if _is_previous_command(command) or _normalize_input(command) == "2":
		_open_mail_home()
		return

	if _normalize_input(command) == "1" or _is_confirm_command(command):
		_open_selected_day_messages(PAGE_MAIL_READ_DAY_LIST)
		return


func _process_mail_day_message_command(command: String) -> void:
	var day_messages = _get_day_messages(selected_day_value)
	if day_messages.is_empty():
		if _normalize_input(command) == "1" or _is_previous_command(command):
			_return_to_day_origin()
		return

	if _normalize_input(command) == "上一个":
		move_cursor(-1)
		return

	if show_selected_mail_body:
		var normalized = _normalize_input(command)
		match normalized:
			"1", "未读", "查看未读", "查看未读邮件":
				_open_unread_mail_list()
			"2", "已读", "查看已读", "查看已读邮件":
				_open_read_day_list()
			"3", "退出", "退出邮件系统", "返回", "主界面":
				ui_page = PAGE_MAIN
				show_selected_mail_body = false
			_:
				return
		return

	if _is_next_command(command):
		move_cursor(1)
		return

	if _is_previous_command(command) or _normalize_input(command) == "2":
		if show_selected_mail_body:
			show_selected_mail_body = false
			return
		_return_to_day_origin()
		return

	if _normalize_input(command) == "1" or _is_confirm_command(command):
		show_selected_mail_body = not show_selected_mail_body
		return


func _build_main_page_body() -> String:
	var sections: Array[String] = []
	var scene_body = str(current_scene_data.get("body", "")).strip_edges()

	if scene_body != "":
		sections.append(scene_body)

	_append_feedback_sections(sections)
	return "\n\n".join(sections)


func _build_mail_home_body() -> String:
	var sections: Array[String] = [
		"[邮件]",
		"未读邮件：%d 封\n已读日期归档：%d 天" % [_get_unread_mails().size(), _get_read_days().size()]
	]
	_append_feedback_sections(sections)
	return "\n\n".join(sections)


func _build_unread_mail_body() -> String:
	var sections: Array[String] = ["[未读邮件]"]
	if _get_unread_mails().is_empty():
		sections.append("当前没有未读邮件。")
	_append_feedback_sections(sections)
	return "\n\n".join(sections)


func _build_read_day_body() -> String:
	var sections: Array[String] = ["[已读邮件]"]
	if _get_read_days().is_empty():
		sections.append("当前没有已读邮件归档。")
	_append_feedback_sections(sections)
	return "\n\n".join(sections)


func _build_day_message_body() -> String:
	var sections: Array[String] = []
	var day_messages = _get_day_messages(selected_day_value)
	if selected_day_value > 0:
		sections.append("[第 %d 天的邮件]" % selected_day_value)
	else:
		sections.append("[邮件列表]")

	if day_messages.is_empty():
		sections.append("当前日期没有已读邮件。")
		_append_feedback_sections(sections)
		return "\n\n".join(sections)

	if show_selected_mail_body:
		selected_message_index = _wrap_index(selected_message_index, day_messages.size())
		var selected_entry = day_messages[selected_message_index]
		sections.append(str(selected_entry.get("body", "")).strip_edges())
	_append_feedback_sections(sections)
	return "\n\n".join(sections)


func _append_feedback_sections(sections: Array[String]) -> void:
	if not warning_messages.is_empty():
		sections.append("[系统警告]\n%s" % "\n".join(warning_messages))

	if transient_hint != "":
		sections.append("[提示]\n%s" % transient_hint)


func _build_main_option_lines() -> Array[String]:
	return _build_option_lines_from_entries(_get_main_option_entries())


func _build_mail_home_option_lines() -> Array[String]:
	return _build_option_lines_from_entries(_get_mail_home_option_entries())


func _build_unread_option_lines() -> Array[String]:
	return _build_option_lines_from_entries(_get_unread_option_entries())


func _build_read_day_option_lines() -> Array[String]:
	return _build_option_lines_from_entries(_get_read_day_option_entries())


func _build_day_message_option_lines() -> Array[String]:
	return _build_option_lines_from_entries(_get_day_message_option_entries())


func _build_option_lines_from_entries(entries: Array[Dictionary]) -> Array[String]:
	var lines: Array[String] = []
	for entry in entries:
		lines.append(_format_option_line(
			str(entry.get("label", "")).strip_edges(),
			bool(entry.get("selected", false))
		))
	return lines


func _get_main_option_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var choices = _get_main_choices()
	selected_main_choice_index = _wrap_index(selected_main_choice_index, choices.size())
	var has_unread_mail = not _get_unread_mails().is_empty()
	for index in choices.size():
		var choice = choices[index]
		var is_mail_entry = bool(choice.get("synthetic", false)) or str(choice.get("target", "")) == MAIL_HOME_TARGET
		entries.append({
			"label": str(choice.get("text", "")).strip_edges(),
			"selected": index == selected_main_choice_index,
			"attention": is_mail_entry and has_unread_mail,
			"kind": "mail_entry" if is_mail_entry else "story_choice"
		})
	return entries


func _get_mail_home_option_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var options = _get_mail_home_options()
	selected_mail_home_index = _wrap_index(selected_mail_home_index, options.size())
	for index in options.size():
		entries.append({
			"label": str(options[index].get("label", "")).strip_edges(),
			"selected": index == selected_mail_home_index,
			"attention": false,
			"kind": "mail_home_option"
		})
	return entries


func _get_unread_option_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var unread_mails = _get_unread_mails()
	selected_unread_index = _wrap_index(selected_unread_index, _get_unread_option_count())
	for index in unread_mails.size():
		entries.append({
			"label": _format_mail_entry_text(unread_mails[index]),
			"selected": index == selected_unread_index,
			"attention": false,
			"kind": "mail_message"
		})
	entries.append({
		"label": "返回邮件首页",
		"selected": selected_unread_index == unread_mails.size(),
		"attention": false,
		"kind": "back"
	})
	return entries


func _get_read_day_option_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var read_days = _get_read_days()
	selected_day_index = _wrap_index(selected_day_index, _get_read_day_option_count())
	for index in read_days.size():
		entries.append({
			"label": _format_read_day_entry_text(read_days[index]),
			"selected": index == selected_day_index,
			"attention": false,
			"kind": "mail_day"
		})
	entries.append({
		"label": "返回邮件首页",
		"selected": selected_day_index == read_days.size(),
		"attention": false,
		"kind": "back"
	})
	return entries


func _get_day_message_option_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if show_selected_mail_body:
		var actions = _get_mail_body_action_options()
		selected_mail_body_action_index = _wrap_index(selected_mail_body_action_index, actions.size())
		for index in actions.size():
			entries.append({
				"label": str(actions[index].get("label", "")).strip_edges(),
				"selected": index == selected_mail_body_action_index,
				"attention": false,
				"kind": "mail_body_action"
			})
		return entries

	var day_messages = _get_day_messages(selected_day_value)
	selected_message_index = _wrap_index(selected_message_index, _get_day_message_option_count())
	for index in day_messages.size():
		entries.append({
			"label": _format_mail_entry_text(day_messages[index]),
			"selected": index == selected_message_index,
			"attention": false,
			"kind": "mail_message"
		})
	entries.append({
		"label": "返回上一层",
		"selected": selected_message_index == day_messages.size(),
		"attention": false,
		"kind": "back"
	})
	return entries


func _format_option_line(label_text: String, is_selected: bool) -> String:
	var line = "- %s" % label_text.strip_edges()
	if is_selected:
		line += " <--"
	return line


func _get_mail_home_options() -> Array[Dictionary]:
	return [
		{"id": "unread", "label": "查看未读邮件"},
		{"id": "read", "label": "查看已读邮件"},
		{"id": "exit", "label": "退出邮件系统"}
	]


func _get_mail_body_action_options() -> Array[Dictionary]:
	return [
		{"id": "unread", "label": "查看未读邮件"},
		{"id": "read", "label": "查看已读邮件"},
		{"id": "exit", "label": "退出邮件系统"}
	]


func _get_unread_option_count() -> int:
	return _get_unread_mails().size() + 1


func _get_read_day_option_count() -> int:
	return _get_read_days().size() + 1


func _get_day_message_option_count() -> int:
	return _get_day_messages(selected_day_value).size() + 1


func _format_mail_entry_text(entry: Dictionary) -> String:
	var day_value = int(entry.get("day", 0))
	var time_text = str(entry.get("time", "")).strip_edges()
	var sender_text = str(entry.get("sender", "妹妹")).strip_edges()
	var title_text = str(entry.get("title", "")).strip_edges()
	var label_text = str(entry.get("label", "")).strip_edges()
	var parts: Array[String] = ["第 %d 天" % day_value]
	if time_text != "":
		parts.append(time_text)
	if label_text != "":
		parts.append("[%s]" % label_text)
	if sender_text != "":
		parts.append(sender_text)
	if title_text != "":
		parts.append(title_text)
	return " ".join(parts).strip_edges()


func _format_read_day_entry_text(day_value: int) -> String:
	return "第 %d 天（%d 封）" % [day_value, _get_day_messages(day_value).size()]


func _get_main_choices() -> Array[Dictionary]:
	var visible_story_choices = _get_visible_story_choices()
	if visible_story_choices.is_empty() and not _get_unread_mails().is_empty():
		return [_create_mail_choice()]
	return visible_story_choices


func _get_visible_story_choices() -> Array[Dictionary]:
	var visible_choices: Array[Dictionary] = []
	var raw_choices = current_scene_data.get("choices", [])
	if not (raw_choices is Array):
		return visible_choices

	for choice_value in raw_choices:
		if not (choice_value is Dictionary):
			continue

		var choice_dict: Dictionary = choice_value
		var visibility_result = _evaluate_visibility_condition(choice_dict.get("visibilityCondition"))
		if not bool(visibility_result.get("ok", true)):
			_append_warning(str(visibility_result.get("error", "选项可见性条件无效。")).strip_edges())
			continue

		if not bool(visibility_result.get("visible", true)):
			continue

		visible_choices.append(_build_visible_story_choice(choice_dict))

	return visible_choices


func _build_visible_story_choice(choice_dict: Dictionary) -> Dictionary:
	return {
		"id": str(choice_dict.get("id", "")).strip_edges(),
		"text": str(choice_dict.get("text", "")).strip_edges(),
		"synthetic": false,
		"choice": choice_dict
	}


func _create_mail_choice() -> Dictionary:
	return {
		"id": "synthetic_mail_home",
		"text": "查看邮件",
		"synthetic": true,
		"target": MAIL_HOME_TARGET
	}


func _execute_main_choice(main_choice: Dictionary) -> void:
	if bool(main_choice.get("synthetic", false)) or str(main_choice.get("target", "")) == MAIL_HOME_TARGET:
		_open_mail_home()
		return

	var source_choice: Dictionary = main_choice.get("choice", {})
	if source_choice.is_empty():
		transient_hint = "选项数据无效，无法继续。"
		return

	_apply_choice_effects(source_choice.get("effects"))

	var route_result = _resolve_choice_target(source_choice)
	if not bool(route_result.get("ok", false)):
		transient_hint = str(route_result.get("error", "该选项没有可用的目标节点。")).strip_edges()
		return

	var target_scene_id = str(route_result.get("target", "")).strip_edges()
	if target_scene_id == "":
		transient_hint = "该选项没有可用的目标节点。"
		return

	if target_scene_id == MAIL_HOME_TARGET:
		_open_mail_home()
		return

	_set_main_scene(target_scene_id)


func _evaluate_visibility_condition(condition_value) -> Dictionary:
	if condition_value == null:
		return {"ok": true, "visible": true}

	var condition_result = _evaluate_condition(condition_value)
	if not bool(condition_result.get("ok", false)):
		return {
			"ok": false,
			"visible": false,
			"error": str(condition_result.get("error", "选项可见性条件无效。")).strip_edges()
		}

	return {"ok": true, "visible": bool(condition_result.get("result", false))}


func _evaluate_condition(condition_value) -> Dictionary:
	if condition_value == null:
		return {"ok": true, "result": true}

	if not (condition_value is Dictionary):
		return {"ok": false, "result": false, "error": "条件格式无效。"}

	var condition_dict: Dictionary = condition_value
	var global_id = str(condition_dict.get("globalId", "")).strip_edges()
	if global_id == "":
		return {"ok": false, "result": false, "error": "条件缺少 globalId。"}

	if not story_globals.has(global_id):
		return {"ok": false, "result": false, "error": "条件引用了不存在的全局变量：%s" % global_id}

	var operator_name = str(condition_dict.get("operator", "eq")).strip_edges().to_lower()
	var expected_value = _coerce_global_value(global_id, condition_dict.get("value"))
	var current_value = global_values.get(global_id)
	var value_type = str(story_globals[global_id].get("value_type", "")).strip_edges()

	match operator_name:
		"eq":
			if value_type == "number":
				return {"ok": true, "result": is_equal_approx(_to_number(current_value), _to_number(expected_value))}
			return {"ok": true, "result": current_value == expected_value}
		"gt":
			return {"ok": true, "result": _to_number(current_value) > _to_number(expected_value)}
		"gte":
			return {"ok": true, "result": _to_number(current_value) >= _to_number(expected_value)}
		"lte":
			return {"ok": true, "result": _to_number(current_value) <= _to_number(expected_value)}
		_:
			return {"ok": false, "result": false, "error": "未支持的条件运算符：%s" % operator_name}


func _apply_choice_effects(effects_value) -> void:
	if effects_value == null:
		return

	if not (effects_value is Array):
		_push_transient_hint("选项效果格式无效，已跳过。")
		return

	for effect_value in effects_value:
		if not (effect_value is Dictionary):
			_push_transient_hint("发现无效的效果配置，已跳过。")
			continue

		var effect_dict: Dictionary = effect_value
		var global_id = str(effect_dict.get("globalId", "")).strip_edges()
		if global_id == "":
			_push_transient_hint("发现缺少 globalId 的效果配置，已跳过。")
			continue

		if not story_globals.has(global_id):
			_push_transient_hint("效果引用了不存在的全局变量：%s" % global_id)
			continue

		var operator_name = str(effect_dict.get("operator", "set")).strip_edges().to_lower()
		match operator_name:
			"set", "lte":
				global_values[global_id] = _coerce_global_value(global_id, effect_dict.get("value"))
			"change":
				if not _is_number_global(global_id):
					_push_transient_hint("change 效果只能用于数值变量：%s" % global_id)
					continue

				var current_value = _to_number(global_values.get(global_id, 0))
				var change_value = _to_number(effect_dict.get("value", 0))
				global_values[global_id] = _coerce_global_value(global_id, current_value + change_value)
			_:
				_push_transient_hint("未支持的效果运算符：%s" % operator_name)


func _resolve_choice_target(choice_dict: Dictionary) -> Dictionary:
	var route_value = choice_dict.get("route")
	if route_value is Dictionary:
		var route_dict: Dictionary = route_value
		var route_mode = str(route_dict.get("mode", "direct")).strip_edges().to_lower()
		match route_mode:
			"direct":
				var direct_target = str(route_dict.get("targetNodeId", "")).strip_edges()
				if direct_target == "":
					direct_target = str(choice_dict.get("targetNodeId", choice_dict.get("target", ""))).strip_edges()
				if direct_target == "":
					return {"ok": false, "error": "direct 路由缺少 targetNodeId。"}
				if not story_nodes.has(direct_target):
					return {"ok": false, "error": "目标节点不存在：%s" % direct_target}
				return {"ok": true, "target": direct_target}
			"conditional":
				return _resolve_conditional_route(route_dict)
			_:
				return {"ok": false, "error": "未支持的路由模式：%s" % route_mode}

	var legacy_target = str(choice_dict.get("targetNodeId", choice_dict.get("target", ""))).strip_edges()
	if legacy_target == "":
		return {"ok": false, "error": "该选项没有可用的目标节点。"}
	if not story_nodes.has(legacy_target):
		return {"ok": false, "error": "目标节点不存在：%s" % legacy_target}
	return {"ok": true, "target": legacy_target}


func _resolve_conditional_route(route_dict: Dictionary) -> Dictionary:
	var raw_branches = route_dict.get("branches", [])
	if raw_branches is Array:
		for branch_value in raw_branches:
			if not (branch_value is Dictionary):
				continue

			var branch_dict: Dictionary = branch_value
			var condition_result = _evaluate_condition(branch_dict.get("condition"))
			if not bool(condition_result.get("ok", false)):
				return {
					"ok": false,
					"error": str(condition_result.get("error", "条件分支判断失败。")).strip_edges()
				}

			if not bool(condition_result.get("result", false)):
				continue

			var branch_target = str(branch_dict.get("targetNodeId", "")).strip_edges()
			if branch_target == "":
				return {"ok": false, "error": "conditional 路由分支缺少 targetNodeId。"}
			if not story_nodes.has(branch_target):
				return {"ok": false, "error": "条件分支目标节点不存在：%s" % branch_target}
			return {"ok": true, "target": branch_target}

	var fallback_target = str(route_dict.get("fallbackTargetNodeId", "")).strip_edges()
	if fallback_target == "":
		return {"ok": false, "error": "conditional 路由没有命中分支且缺少 fallbackTargetNodeId。"}
	if not story_nodes.has(fallback_target):
		return {"ok": false, "error": "fallback 目标节点不存在：%s" % fallback_target}
	return {"ok": true, "target": fallback_target}


func _coerce_global_value(global_id: String, raw_value):
	if not story_globals.has(global_id):
		return raw_value

	var value_type = str(story_globals[global_id].get("value_type", "")).strip_edges()
	return _coerce_global_value_by_type(value_type, raw_value)


func _is_number_global(global_id: String) -> bool:
	if not story_globals.has(global_id):
		return false

	return str(story_globals[global_id].get("value_type", "")).strip_edges() == "number"


func _coerce_global_value_by_type(value_type: String, raw_value):
	match value_type:
		"boolean":
			return _to_bool(raw_value)
		"number":
			if raw_value is int:
				return raw_value
			if raw_value is float:
				return raw_value
			var raw_text = str(raw_value).strip_edges()
			if raw_text.is_valid_int():
				return int(raw_text)
			if raw_text.is_valid_float():
				return float(raw_text)
			return 0
		_:
			return raw_value


func _open_mail_home() -> void:
	ui_page = PAGE_MAIL_HOME
	show_selected_mail_body = false
	selected_mail_home_index = _wrap_index(selected_mail_home_index, _get_mail_home_options().size())
	transient_hint = ""


func _open_unread_mail_list() -> void:
	ui_page = PAGE_MAIL_UNREAD_LIST
	show_selected_mail_body = false
	selected_unread_index = _wrap_index(selected_unread_index, _get_unread_option_count())


func _open_read_day_list() -> void:
	ui_page = PAGE_MAIL_READ_DAY_LIST
	show_selected_mail_body = false
	var read_days = _get_read_days()
	selected_day_index = _wrap_index(selected_day_index, _get_read_day_option_count())
	if not read_days.is_empty() and selected_day_index < read_days.size():
		selected_day_value = read_days[selected_day_index]
	else:
		selected_day_value = -1


func _open_selected_day_messages(origin_page: String) -> void:
	var read_days = _get_read_days()
	if read_days.is_empty():
		_open_read_day_list()
		return

	selected_day_index = _wrap_index(selected_day_index, read_days.size())
	selected_day_value = read_days[selected_day_index]
	selected_message_index = _wrap_index(selected_message_index, _get_day_message_option_count())
	show_selected_mail_body = false
	selected_mail_body_action_index = 0
	ui_page = PAGE_MAIL_DAY_MESSAGE_LIST
	mail_day_origin_page = origin_page


func _open_unread_mail(index: int) -> void:
	var unread_mails = _get_unread_mails()
	if unread_mails.is_empty():
		_open_unread_mail_list()
		return

	selected_unread_index = _wrap_index(index, unread_mails.size())
	var entry = unread_mails[selected_unread_index]
	read_mail_ids[str(entry.get("id", ""))] = true
	_sync_read_all_emails_global_from_mailbox()

	selected_day_value = int(entry.get("day", 0))
	mail_day_origin_page = PAGE_MAIL_UNREAD_LIST
	ui_page = PAGE_MAIL_DAY_MESSAGE_LIST
	show_selected_mail_body = true
	selected_mail_body_action_index = 0

	var day_messages = _get_day_messages(selected_day_value)
	selected_message_index = _find_message_index(day_messages, str(entry.get("id", "")))
	selected_unread_index = _wrap_index(selected_unread_index, _get_unread_option_count())


func _return_to_day_origin() -> void:
	show_selected_mail_body = false
	if mail_day_origin_page == PAGE_MAIL_UNREAD_LIST:
		_open_unread_mail_list()
		return
	_open_read_day_list()


func _trigger_file_triggers_for_scene(scene_data: Dictionary) -> void:
	var file_triggers = scene_data.get("fileTriggers", scene_data.get("fileTrigers", []))
	if file_triggers == null:
		_sync_read_all_emails_global_from_mailbox()
		return

	if not (file_triggers is Array):
		_append_warning("当前节点的 fileTriggers 格式无效。")
		_sync_read_all_emails_global_from_mailbox()
		return

	var seen_ids: Dictionary = {}
	for trigger_value in file_triggers:
		var trigger_text = str(trigger_value).strip_edges()
		if trigger_text == "":
			continue

		var trigger_action = _parse_file_trigger_action(trigger_text)
		var file_id = str(trigger_action.get("file_id", "")).strip_edges()
		if file_id == "":
			continue

		var dedupe_key = "%s:%s" % [str(trigger_action.get("action", "introduce")), file_id]
		if seen_ids.has(dedupe_key):
			continue
		seen_ids[dedupe_key] = true

		if not _has_mail_entry(file_id):
			_append_warning("fileTriggers 引用了不存在的邮件文件：%s" % trigger_text)
			continue

		match str(trigger_action.get("action", "introduce")):
			"remove":
				removed_mail_ids[file_id] = true
				introduced_mail_ids.erase(file_id)
				read_mail_ids.erase(file_id)
				mail_body_overrides.erase(file_id)
				_restore_mail_entry_body(file_id)
			"corrupt":
				_set_mail_body_override(file_id, "系统错误，无法读取邮件内容\n系统错误，无法读取邮件内容\n系统错误，无法读取邮件内容")
			_:
				if removed_mail_ids.has(file_id):
					continue
				if introduced_mail_ids.has(file_id):
					continue
				introduced_mail_ids[file_id] = true
				_update_day_label_from_special_mail(file_id)

	_sync_read_all_emails_global_from_mailbox()


func _has_mail_entry(file_id: String) -> bool:
	for entry in mail_entries:
		if str(entry.get("id", "")).strip_edges() == file_id:
			return true
	return false


func _update_day_label_from_special_mail(file_id: String) -> void:
	for entry in mail_entries:
		if str(entry.get("id", "")).strip_edges() != file_id:
			continue

		if str(entry.get("label", "")).strip_edges() != "第x封":
			return

		var mail_day = int(entry.get("day", -1))
		if mail_day < 0:
			return

		day_label = "第 %d 天" % mail_day
		current_day_number = mail_day
		return


func _parse_file_trigger_action(trigger_text: String) -> Dictionary:
	var normalized = trigger_text.strip_edges()
	if normalized == "":
		return {"action": "introduce", "file_id": ""}

	if normalized.begins_with("-"):
		return {"action": "remove", "file_id": normalized.substr(1).strip_edges()}
	if normalized.begins_with("~"):
		return {"action": "corrupt", "file_id": normalized.substr(1).strip_edges()}

	return {"action": "introduce", "file_id": normalized}


func _set_mail_body_override(file_id: String, body_text: String) -> void:
	var normalized_id = file_id.strip_edges()
	if normalized_id == "":
		return

	mail_body_overrides[normalized_id] = body_text
	for index in mail_entries.size():
		if str(mail_entries[index].get("id", "")).strip_edges() != normalized_id:
			continue
		mail_entries[index]["body"] = body_text
		return


func _restore_mail_entry_body(file_id: String) -> void:
	var normalized_id = file_id.strip_edges()
	if normalized_id == "":
		return

	for index in mail_entries.size():
		if str(mail_entries[index].get("id", "")).strip_edges() != normalized_id:
			continue
		var rebuilt_entry = _build_mail_entry_from_file(normalized_id)
		if rebuilt_entry.is_empty():
			return
		mail_entries[index]["body"] = str(rebuilt_entry.get("body", "")).strip_edges()
		return


func _restore_saved_mail_body_overrides(saved_overrides) -> Dictionary:
	var restored: Dictionary = {}
	if not (saved_overrides is Dictionary):
		return restored

	for mail_id in saved_overrides.keys():
		var normalized_mail_id = str(mail_id).strip_edges()
		if normalized_mail_id == "" or not _has_mail_entry(normalized_mail_id):
			continue
		restored[normalized_mail_id] = str(saved_overrides[mail_id])

	return restored


func _apply_saved_mail_body_overrides() -> void:
	for mail_id in mail_body_overrides.keys():
		_set_mail_body_override(str(mail_id).strip_edges(), str(mail_body_overrides[mail_id]))


func _sync_read_all_emails_global_from_mailbox() -> void:
	if read_all_emails_global_id == "":
		return

	global_values[read_all_emails_global_id] = _get_unread_mails().is_empty()


func _get_unread_mails() -> Array[Dictionary]:
	var unread_mails: Array[Dictionary] = []
	for entry in mail_entries:
		var entry_id = str(entry.get("id", "")).strip_edges()
		if entry_id == "" or not introduced_mail_ids.has(entry_id) or read_mail_ids.has(entry_id):
			continue
		unread_mails.append(entry)
	return unread_mails


func _get_read_days() -> Array[int]:
	var day_set: Dictionary = {}
	for entry in mail_entries:
		var entry_id = str(entry.get("id", "")).strip_edges()
		if entry_id == "" or not introduced_mail_ids.has(entry_id) or not read_mail_ids.has(entry_id):
			continue
		day_set[int(entry.get("day", 0))] = true

	var read_days: Array[int] = []
	for day_value in day_set.keys():
		read_days.append(int(day_value))
	read_days.sort()
	return read_days


func _get_day_messages(day_value: int) -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	if day_value < 0:
		return messages

	for entry in mail_entries:
		var entry_id = str(entry.get("id", "")).strip_edges()
		if entry_id == "" or not introduced_mail_ids.has(entry_id) or not read_mail_ids.has(entry_id):
			continue
		if int(entry.get("day", -1)) != day_value:
			continue
		messages.append(entry)

	return messages


func _find_message_index(messages: Array[Dictionary], message_id: String) -> int:
	for index in messages.size():
		if str(messages[index].get("id", "")).strip_edges() == message_id:
			return index
	return 0


func _format_mail_entry_line(entry: Dictionary, is_selected: bool) -> String:
	var marker = "<--" if is_selected else ""
	var day_value = int(entry.get("day", 0))
	var time_text = str(entry.get("time", "00:00")).strip_edges()
	var sender_text = str(entry.get("sender", "妹妹")).strip_edges()
	var title_text = str(entry.get("title", "")).strip_edges()
	var label_text = str(entry.get("label", "")).strip_edges()

	var prefix = "第 %d 天" % day_value
	if time_text != "":
		prefix += " %s" % time_text
	if label_text != "":
		prefix += " [%s]" % label_text

	var suffix_parts: Array[String] = []
	if sender_text != "":
		suffix_parts.append(sender_text)
	if title_text != "":
		suffix_parts.append(title_text)

	var suffix = " - ".join(suffix_parts)
	var line = prefix
	if suffix != "":
		line += " %s" % suffix
	if marker != "":
		line += " %s" % marker
	return line.strip_edges()


func _is_previous_command(command: String) -> bool:
	return _normalize_input(command) in ["返回", "上一级", "后退", "back"]


func _is_next_command(command: String) -> bool:
	return _normalize_input(command) in ["下一个", "下移", "next"]


func _is_confirm_command(command: String) -> bool:
	return _normalize_input(command) in ["查看", "打开", "确认", "进入", "open", "enter"]


func _command_matches_choice(command: String, choice: Dictionary) -> bool:
	return _normalize_input(command) == _normalize_input(str(choice.get("text", "")).strip_edges())


func _normalize_input(value: String) -> String:
	return value.strip_edges().to_lower()


func _wrap_index(index: int, size: int) -> int:
	if size <= 0:
		return 0

	var wrapped = index % size
	if wrapped < 0:
		wrapped += size
	return wrapped


func _apply_saved_global_values(saved_values) -> void:
	if not (saved_values is Dictionary):
		return

	for global_id in saved_values.keys():
		if not story_globals.has(global_id):
			continue
		global_values[global_id] = _coerce_global_value(global_id, saved_values[global_id])


func _restore_saved_mail_flags(saved_flags) -> Dictionary:
	var restored: Dictionary = {}
	if not (saved_flags is Dictionary):
		return restored

	for mail_id in saved_flags.keys():
		var normalized_mail_id = str(mail_id).strip_edges()
		if normalized_mail_id == "" or not _has_mail_entry(normalized_mail_id):
			continue
		restored[normalized_mail_id] = true

	return restored


func _restore_saved_page(page_name: String) -> String:
	match page_name:
		PAGE_MAIN, PAGE_MAIL_HOME, PAGE_MAIL_UNREAD_LIST, PAGE_MAIL_READ_DAY_LIST, PAGE_MAIL_DAY_MESSAGE_LIST:
			return page_name
		_:
			return PAGE_MAIN


func _restore_mail_origin_page(page_name: String) -> String:
	match page_name:
		PAGE_MAIL_UNREAD_LIST, PAGE_MAIL_READ_DAY_LIST:
			return page_name
		_:
			return PAGE_MAIL_READ_DAY_LIST


func _clamp_restored_ui_state() -> void:
	selected_main_choice_index = _wrap_index(selected_main_choice_index, _get_main_choices().size())
	selected_mail_home_index = _wrap_index(selected_mail_home_index, _get_mail_home_options().size())
	selected_unread_index = _wrap_index(selected_unread_index, _get_unread_option_count())

	var read_days = _get_read_days()
	selected_day_index = _wrap_index(selected_day_index, _get_read_day_option_count())
	if read_days.is_empty():
		selected_day_value = -1
	else:
		if selected_day_index < read_days.size():
			selected_day_value = read_days[selected_day_index]
		elif not read_days.has(selected_day_value):
			selected_day_value = read_days[selected_day_index]

	var day_messages = _get_day_messages(selected_day_value)
	selected_message_index = _wrap_index(selected_message_index, _get_day_message_option_count())
	selected_mail_body_action_index = _wrap_index(selected_mail_body_action_index, _get_mail_body_action_options().size())
	if day_messages.is_empty():
		show_selected_mail_body = false

	match ui_page:
		PAGE_MAIL_DAY_MESSAGE_LIST:
			if day_messages.is_empty():
				show_selected_mail_body = false
		PAGE_MAIL_READ_DAY_LIST:
			if read_days.is_empty():
				selected_day_value = -1
		PAGE_MAIL_UNREAD_LIST:
			selected_unread_index = _wrap_index(selected_unread_index, _get_unread_option_count())


func _append_warning(message: String) -> void:
	var trimmed = message.strip_edges()
	if trimmed == "":
		return

	if warning_messages.has(trimmed):
		return

	warning_messages.append(trimmed)


func _push_transient_hint(message: String) -> void:
	var trimmed = message.strip_edges()
	if trimmed == "":
		return

	if transient_hint == "":
		transient_hint = trimmed
		return

	if transient_hint.contains(trimmed):
		return

	transient_hint += "\n" + trimmed


func _to_bool(value) -> bool:
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is float:
		return not is_zero_approx(value)

	var text = str(value).strip_edges().to_lower()
	return text in ["true", "1", "yes", "on", "是", "真"]


func _to_number(value) -> float:
	if value is int:
		return float(value)
	if value is float:
		return value

	var text = str(value).strip_edges()
	if text.is_valid_int():
		return float(int(text))
	if text.is_valid_float():
		return float(text)
	return 0.0


func _load_json_file(file_path: String) -> Dictionary:
	if file_path == "" or not FileAccess.file_exists(file_path):
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}

	var raw_text = file.get_as_text()
	file.close()
	if raw_text.strip_edges() == "":
		return {}

	var json = JSON.new()
	var parse_result = json.parse(raw_text)
	if parse_result != OK:
		return {}

	if json.data is Dictionary:
		return json.data

	return {}


func _load_text_file(file_path: String) -> String:
	if file_path == "" or not FileAccess.file_exists(file_path):
		return ""

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""

	var raw_text = file.get_as_text()
	file.close()
	return raw_text
