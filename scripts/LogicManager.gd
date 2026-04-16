extends Node

const PAGE_MAIN := "MAIN"
const PAGE_MAIL_HOME := "MAIL_HOME"
const PAGE_MAIL_UNREAD_LIST := "MAIL_UNREAD_LIST"
const PAGE_MAIL_READ_DAY_LIST := "MAIL_READ_DAY_LIST"
const PAGE_MAIL_DAY_MESSAGE_LIST := "MAIL_DAY_MESSAGE_LIST"

const MAIL_HOME_TARGET := "__MAIL_HOME__"

@export_file("*.json") var story_file_path: String = "res://data/Story.json"
@export_file("*.json") var mail_file_path: String = "res://data/MailData.json"

var initialized: bool = false

var story_title: String = "Email From Sister"
var start_node_id: String = ""
var story_nodes: Dictionary = {}
var current_scene_id: String = ""
var current_scene_data: Dictionary = {}

var ui_page: String = PAGE_MAIN
var day_label: String = "第 4 天"
var weather_label: String = "晴朗"
var transient_hint: String = ""

var mail_entries: Array[Dictionary] = []
var read_mail_ids: Dictionary = {}
var selected_unread_index: int = 0
var selected_day_index: int = 0
var selected_day_value: int = -1
var selected_message_index: int = 0
var show_selected_mail_body: bool = false


func _ready() -> void:
	initialize_game()


func initialize_game() -> void:
	if initialized:
		return

	_load_story_data()
	_load_mail_data()
	_open_start_scene()
	initialized = true


func _load_story_data() -> void:
	story_nodes.clear()

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
		start_node_id = str(metadata.get("startNodeId", start_node_id)).strip_edges()

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
	read_mail_ids.clear()

	if mail_file_path == "":
		return

	var mailbox_data = _load_json_file(mail_file_path)
	if mailbox_data.is_empty():
		return

	day_label = str(mailbox_data.get("defaultDayLabel", day_label)).strip_edges()
	weather_label = str(mailbox_data.get("defaultWeatherLabel", weather_label)).strip_edges()

	var raw_messages = mailbox_data.get("messages", [])
	if not (raw_messages is Array):
		return

	for message_value in raw_messages:
		if not (message_value is Dictionary):
			continue

		var message_dict: Dictionary = message_value
		var normalized_message: Dictionary = {
			"id": str(message_dict.get("id", "")).strip_edges(),
			"sender": str(message_dict.get("sender", "妹妹")).strip_edges(),
			"day": int(message_dict.get("day", 0)),
			"time": str(message_dict.get("time", "00:00")).strip_edges(),
			"label": str(message_dict.get("label", "")).strip_edges(),
			"title": str(message_dict.get("title", "")).strip_edges(),
			"body": str(message_dict.get("body", "")).strip_edges(),
			"is_read_default": bool(message_dict.get("is_read_default", false))
		}

		if str(normalized_message["id"]) == "":
			continue

		mail_entries.append(normalized_message)
		if bool(normalized_message["is_read_default"]):
			read_mail_ids[normalized_message["id"]] = true


func _open_start_scene() -> void:
	if start_node_id == "" or not story_nodes.has(start_node_id):
		_create_default_story()

	_set_main_scene(start_node_id)


func _set_main_scene(scene_id: String) -> void:
	if not story_nodes.has(scene_id):
		transient_hint = "目标场景不存在。"
		return

	current_scene_id = scene_id
	current_scene_data = story_nodes[scene_id]
	ui_page = PAGE_MAIN
	transient_hint = ""
	show_selected_mail_body = false


func get_current_ui_page() -> String:
	return ui_page


func get_day_label() -> String:
	return day_label


func get_weather_label() -> String:
	return weather_label


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


func get_page_option_lines() -> Array[String]:
	match ui_page:
		PAGE_MAIN:
			return _build_main_option_lines()
		PAGE_MAIL_HOME:
			return [
				"> 1. 查看未读邮件",
				"> 2. 查看已读邮件",
				"> 3. 退出邮件"
			]
		PAGE_MAIL_UNREAD_LIST:
			return [
				"> 1. 查看已读邮件",
				"> 2. 退出邮件"
			]
		PAGE_MAIL_READ_DAY_LIST, PAGE_MAIL_DAY_MESSAGE_LIST:
			return [
				"> 1. 查看未读邮件",
				"> 2. 退出邮件"
			]
		_:
			return []


func supports_cursor_navigation() -> bool:
	return ui_page in [
		PAGE_MAIL_UNREAD_LIST,
		PAGE_MAIL_READ_DAY_LIST,
		PAGE_MAIL_DAY_MESSAGE_LIST
	]


func move_cursor(delta: int) -> void:
	if delta == 0:
		return

	match ui_page:
		PAGE_MAIL_UNREAD_LIST:
			_move_unread_selection(delta)
		PAGE_MAIL_READ_DAY_LIST:
			_move_day_selection(delta)
		PAGE_MAIL_DAY_MESSAGE_LIST:
			_move_day_message_selection(delta)


func process_command(command: String) -> void:
	initialize_game()

	var trimmed = command.strip_edges()
	if trimmed == "":
		return

	if _process_global_command(trimmed):
		return

	match ui_page:
		PAGE_MAIN:
			_process_main_command(trimmed)
		PAGE_MAIL_HOME:
			_process_mail_home_command(trimmed)
		PAGE_MAIL_UNREAD_LIST:
			_process_mail_unread_command(trimmed)
		PAGE_MAIL_READ_DAY_LIST:
			_process_mail_read_day_command(trimmed)
		PAGE_MAIL_DAY_MESSAGE_LIST:
			_process_mail_day_message_command(trimmed)


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
			transient_hint = "当前页面：%s｜未读邮件：%d｜已读日期：%d" % [
				ui_page,
				_get_unread_mails().size(),
				_get_read_day_values().size()
			]
			return true
		"quit", "exit", "退出游戏":
			get_tree().quit()
			return true
		_:
			return false


func _build_help_text() -> String:
	match ui_page:
		PAGE_MAIN:
			return "输入数字选择当前剧情选项，也可以直接输入选项文字。"
		PAGE_MAIL_HOME:
			return "邮件首页支持输入数字，或输入“未读”“已读”“退出”。"
		PAGE_MAIL_UNREAD_LIST:
			return "未读页支持方向键上下切换高亮，也支持输入“上一个”“下一个”；输入“查看”打开当前邮件。"
		PAGE_MAIL_READ_DAY_LIST:
			return "已读页支持方向键上下切换日期，也支持输入“上一个”“下一个”；输入“查看”进入当天邮件。"
		PAGE_MAIL_DAY_MESSAGE_LIST:
			return "当天邮件页支持方向键上下切换高亮，也支持输入“上一个”“下一个”；输入“查看”展开或收起正文，输入“返回”回到已读列表。"
		_:
			return "可输入数字或关键字操作当前页面。"


func _process_main_command(command: String) -> void:
	var choices = _get_main_choices()
	var normalized_command = _normalize_input(command)

	for choice in choices:
		if bool(choice.get("synthetic", false)) and normalized_command == _normalize_input(str(choice.get("text", ""))):
			_execute_main_choice(choice)
			return

	if command.is_valid_int():
		var option_index = command.to_int() - 1
		if option_index >= 0 and option_index < choices.size():
			_execute_main_choice(choices[option_index])
			return

	for choice in choices:
		if _command_matches_choice(command, str(choice.get("text", ""))):
			_execute_main_choice(choice)
			return

	transient_hint = "没有匹配到当前场景的操作。输入“帮助”可查看提示。"


func _process_mail_home_command(command: String) -> void:
	var normalized = _normalize_input(command)

	if command.is_valid_int():
		match command.to_int():
			1:
				_open_mail_unread_list()
				return
			2:
				_open_mail_read_day_list()
				return
			3:
				_close_mail()
				return

	if normalized.contains("未读"):
		_open_mail_unread_list()
		return
	if normalized.contains("已读"):
		_open_mail_read_day_list()
		return
	if normalized.contains("退出") or normalized.contains("返回"):
		_close_mail()
		return

	transient_hint = "邮件首页只支持“未读 / 已读 / 退出”三类操作。"


func _process_mail_unread_command(command: String) -> void:
	var normalized = _normalize_input(command)

	if command.is_valid_int():
		match command.to_int():
			1:
				_open_mail_read_day_list()
				return
			2:
				_close_mail()
				return

	if normalized.contains("已读"):
		_open_mail_read_day_list()
		return
	if normalized.contains("退出") or normalized.contains("返回首页"):
		_close_mail()
		return
	if _is_previous_command(normalized):
		_move_unread_selection(-1)
		return
	if _is_next_command(normalized):
		_move_unread_selection(1)
		return
	if _is_confirm_command(normalized):
		_open_selected_unread_mail()
		return

	transient_hint = "可输入“上一个 / 下一个 / 查看”，或使用底部数字操作。"


func _process_mail_read_day_command(command: String) -> void:
	var normalized = _normalize_input(command)

	if command.is_valid_int():
		match command.to_int():
			1:
				_open_mail_unread_list()
				return
			2:
				_close_mail()
				return

	if normalized.contains("未读"):
		_open_mail_unread_list()
		return
	if normalized.contains("退出"):
		_close_mail()
		return
	if _is_previous_command(normalized):
		_move_day_selection(-1)
		return
	if _is_next_command(normalized):
		_move_day_selection(1)
		return
	if _is_confirm_command(normalized):
		_open_selected_read_day()
		return

	transient_hint = "可输入“上一个 / 下一个 / 查看”，或使用底部数字操作。"


func _process_mail_day_message_command(command: String) -> void:
	var normalized = _normalize_input(command)

	if command.is_valid_int():
		match command.to_int():
			1:
				_open_mail_unread_list()
				return
			2:
				_close_mail()
				return

	if normalized.contains("未读"):
		_open_mail_unread_list()
		return
	if normalized.contains("退出"):
		_close_mail()
		return
	if normalized.contains("返回"):
		_open_mail_read_day_list()
		return
	if _is_previous_command(normalized):
		_move_day_message_selection(-1)
		return
	if _is_next_command(normalized):
		_move_day_message_selection(1)
		return
	if _is_confirm_command(normalized):
		show_selected_mail_body = not show_selected_mail_body
		transient_hint = ""
		return

	transient_hint = "可输入“上一个 / 下一个 / 查看 / 返回”，或使用底部数字操作。"


func _build_main_page_body() -> String:
	var parts: Array[String] = []
	var body = str(current_scene_data.get("body", current_scene_data.get("description", ""))).strip_edges()

	if body == "":
		var title = str(current_scene_data.get("title", "")).strip_edges()
		if title != "":
			body = "【%s】" % title

	if body != "":
		parts.append(body)

	if transient_hint != "":
		parts.append(transient_hint)

	return "\n\n".join(parts)


func _build_mail_home_body() -> String:
	var parts: Array[String] = [
		"[邮件]",
		"收件箱已同步。",
		"当前共有 %d 封未读邮件。" % _get_unread_mails().size(),
		"已归档 %d 天的邮件记录。" % _get_read_day_values().size()
	]

	if transient_hint != "":
		parts.append(transient_hint)

	return "\n\n".join(parts)


func _build_unread_mail_body() -> String:
	var lines: Array[String] = ["【未读邮件】", ""]
	var unread_mails = _get_unread_mails()

	if unread_mails.is_empty():
		lines.append("（当前没有未读邮件）")
	else:
		var clamped_index = clamp(selected_unread_index, 0, unread_mails.size() - 1)
		for i in range(unread_mails.size()):
			lines.append(_format_mail_overview_line(unread_mails[i], i == clamped_index, true))

	if transient_hint != "":
		lines.append("")
		lines.append(transient_hint)

	return "\n".join(lines)


func _build_read_day_body() -> String:
	var lines: Array[String] = ["【已读邮件】", ""]
	var read_days = _get_read_day_values()

	if read_days.is_empty():
		lines.append("（当前还没有已读邮件）")
	else:
		var clamped_index = clamp(selected_day_index, 0, read_days.size() - 1)
		for i in range(read_days.size()):
			var current_day = read_days[i]
			var suffix = " <--" if i == clamped_index else ""
			lines.append("[第 %d 天的邮件]%s" % [current_day, suffix])

	if transient_hint != "":
		lines.append("")
		lines.append(transient_hint)

	return "\n".join(lines)


func _build_day_message_body() -> String:
	var lines: Array[String] = ["【第 %d 天的邮件】" % selected_day_value, ""]
	var day_messages = _get_read_mails_for_day(selected_day_value)

	if day_messages.is_empty():
		lines.append("（这一天还没有可展示的邮件）")
	else:
		var clamped_index = clamp(selected_message_index, 0, day_messages.size() - 1)
		for i in range(day_messages.size()):
			lines.append(_format_mail_overview_line(day_messages[i], i == clamped_index, false))

		if show_selected_mail_body:
			var current_message: Dictionary = day_messages[clamped_index]
			lines.append("")
			lines.append("【邮件正文】")
			lines.append(str(current_message.get("body", "")).strip_edges())

	if transient_hint != "":
		lines.append("")
		lines.append(transient_hint)

	return "\n".join(lines)


func _build_main_option_lines() -> Array[String]:
	var lines: Array[String] = []
	var choices = _get_main_choices()

	for i in range(choices.size()):
		lines.append("> %d. %s" % [i + 1, str(choices[i].get("text", ""))])

	return lines


func _get_main_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var raw_choices = current_scene_data.get("choices", [])

	if raw_choices is Array:
		for choice_value in raw_choices:
			if not (choice_value is Dictionary):
				continue

			var choice_dict: Dictionary = choice_value
			var choice_text = str(choice_dict.get("text", "")).strip_edges()
			if choice_text == "":
				continue

			choices.append({
				"text": choice_text,
				"target": _extract_choice_target(choice_dict),
				"synthetic": false,
				"error": _get_choice_route_error(choice_dict)
			})
	elif raw_choices is Dictionary:
		for option_text in raw_choices.keys():
			choices.append({
				"text": str(option_text),
				"target": str(raw_choices[option_text]),
				"synthetic": false,
				"error": ""
			})
	else:
		var raw_options = current_scene_data.get("options", {})
		if raw_options is Dictionary:
			for option_text in raw_options.keys():
				choices.append({
					"text": str(option_text),
					"target": str(raw_options[option_text]),
					"synthetic": false,
					"error": ""
				})

	choices.append({
		"text": "查看邮件",
		"target": MAIL_HOME_TARGET,
		"synthetic": true,
		"error": ""
	})

	return choices


func _execute_main_choice(choice: Dictionary) -> void:
	var target_id = str(choice.get("target", "")).strip_edges()
	var route_error = str(choice.get("error", "")).strip_edges()

	if bool(choice.get("synthetic", false)) or target_id == MAIL_HOME_TARGET:
		_open_mail_home()
		return

	if route_error != "":
		transient_hint = route_error
		return

	if target_id == "":
		transient_hint = "这个选项暂时没有可用的跳转目标。"
		return

	if not story_nodes.has(target_id):
		transient_hint = "目标场景不存在。"
		return

	_set_main_scene(target_id)


func _extract_choice_target(choice_dict: Dictionary) -> String:
	var route_value = choice_dict.get("route", {})
	if route_value is Dictionary:
		var route_dict: Dictionary = route_value
		var route_mode = str(route_dict.get("mode", "direct")).strip_edges().to_lower()
		if route_mode == "" or route_mode == "direct":
			var nested_target = str(route_dict.get("targetNodeId", route_dict.get("target", ""))).strip_edges()
			if nested_target != "":
				return nested_target

	return str(choice_dict.get("targetNodeId", choice_dict.get("target", ""))).strip_edges()


func _get_choice_route_error(choice_dict: Dictionary) -> String:
	var route_value = choice_dict.get("route", {})
	if not (route_value is Dictionary):
		return ""

	var route_dict: Dictionary = route_value
	var route_mode = str(route_dict.get("mode", "direct")).strip_edges().to_lower()
	if route_mode == "" or route_mode == "direct":
		return ""

	return "当前版本暂时不支持这种跳转方式：%s" % route_mode


func _open_mail_home() -> void:
	ui_page = PAGE_MAIL_HOME
	transient_hint = ""
	show_selected_mail_body = false


func _open_mail_unread_list() -> void:
	ui_page = PAGE_MAIL_UNREAD_LIST
	var unread_mails = _get_unread_mails()
	selected_unread_index = max(unread_mails.size() - 1, 0)
	transient_hint = ""
	show_selected_mail_body = false


func _open_mail_read_day_list() -> void:
	ui_page = PAGE_MAIL_READ_DAY_LIST
	var read_days = _get_read_day_values()
	if read_days.is_empty():
		selected_day_index = 0
		selected_day_value = -1
	else:
		selected_day_index = max(read_days.size() - 1, 0)
		selected_day_value = read_days[selected_day_index]

	transient_hint = ""
	show_selected_mail_body = false


func _open_mail_day_messages(day_value: int, preferred_mail_id: String = "", preview_body: bool = false) -> void:
	ui_page = PAGE_MAIL_DAY_MESSAGE_LIST
	selected_day_value = day_value
	selected_day_index = _get_read_day_values().find(day_value)
	selected_message_index = 0

	var day_messages = _get_read_mails_for_day(day_value)
	if preferred_mail_id != "":
		for i in range(day_messages.size()):
			if str(day_messages[i].get("id", "")) == preferred_mail_id:
				selected_message_index = i
				break

	show_selected_mail_body = preview_body and not day_messages.is_empty()
	transient_hint = ""


func _close_mail() -> void:
	ui_page = PAGE_MAIN
	transient_hint = ""
	show_selected_mail_body = false


func _open_selected_unread_mail() -> void:
	var unread_mails = _get_unread_mails()
	if unread_mails.is_empty():
		transient_hint = "当前没有未读邮件。"
		return

	var clamped_index = clamp(selected_unread_index, 0, unread_mails.size() - 1)
	var message: Dictionary = unread_mails[clamped_index]
	read_mail_ids[message["id"]] = true
	_open_mail_day_messages(int(message.get("day", 0)), str(message.get("id", "")), true)


func _open_selected_read_day() -> void:
	var read_days = _get_read_day_values()
	if read_days.is_empty():
		transient_hint = "当前还没有已读邮件。"
		return

	var clamped_index = clamp(selected_day_index, 0, read_days.size() - 1)
	_open_mail_day_messages(read_days[clamped_index], "", false)


func _move_unread_selection(delta: int) -> void:
	var unread_mails = _get_unread_mails()
	if unread_mails.is_empty():
		transient_hint = "当前没有未读邮件。"
		return

	selected_unread_index = _wrap_index(selected_unread_index + delta, unread_mails.size())
	transient_hint = ""


func _move_day_selection(delta: int) -> void:
	var read_days = _get_read_day_values()
	if read_days.is_empty():
		transient_hint = "当前还没有已读邮件。"
		return

	selected_day_index = _wrap_index(selected_day_index + delta, read_days.size())
	selected_day_value = read_days[selected_day_index]
	transient_hint = ""


func _move_day_message_selection(delta: int) -> void:
	var day_messages = _get_read_mails_for_day(selected_day_value)
	if day_messages.is_empty():
		transient_hint = "这一天没有可切换的邮件。"
		return

	selected_message_index = _wrap_index(selected_message_index + delta, day_messages.size())
	transient_hint = ""


func _get_unread_mails() -> Array[Dictionary]:
	var unread_mails: Array[Dictionary] = []
	for message in mail_entries:
		if not read_mail_ids.has(message["id"]):
			unread_mails.append(message)
	return unread_mails


func _get_read_day_values() -> Array[int]:
	var day_values: Array[int] = []
	for message in mail_entries:
		if not read_mail_ids.has(message["id"]):
			continue

		var current_day = int(message.get("day", 0))
		if current_day not in day_values:
			day_values.append(current_day)

	return day_values


func _get_read_mails_for_day(day_value: int) -> Array[Dictionary]:
	var day_messages: Array[Dictionary] = []
	for message in mail_entries:
		if not read_mail_ids.has(message["id"]):
			continue
		if int(message.get("day", 0)) == day_value:
			day_messages.append(message)

	return day_messages


func _format_mail_overview_line(message: Dictionary, selected: bool, include_day: bool) -> String:
	var line = "[%s] [ %s ]" % [
		str(message.get("label", "")),
		str(message.get("sender", "妹妹"))
	]

	if include_day:
		line += " [第 %d 天]" % int(message.get("day", 0))

	line += " [ %s ]" % str(message.get("time", "00:00"))

	if selected:
		line += " <--"

	return line


func _is_previous_command(normalized: String) -> bool:
	return normalized.contains("上一个") or normalized.contains("上一封") or normalized.contains("上一页")


func _is_next_command(normalized: String) -> bool:
	return normalized.contains("下一个") or normalized.contains("下一封") or normalized.contains("下一页")


func _is_confirm_command(normalized: String) -> bool:
	return normalized.contains("查看") or normalized.contains("打开") or normalized.contains("确认")


func _command_matches_choice(command: String, choice_text: String) -> bool:
	var normalized_command = _normalize_input(command)
	var normalized_choice = _normalize_input(choice_text)
	return normalized_command == normalized_choice or normalized_command.contains(normalized_choice) or normalized_choice.contains(normalized_command)


func _normalize_input(text: String) -> String:
	return text.strip_edges().to_lower()


func _wrap_index(index: int, size: int) -> int:
	if size <= 0:
		return 0

	return ((index % size) + size) % size


func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		push_error("JSON parse error: %s (%s)" % [path, json.get_error_message()])
		return {}

	var data = json.get_data()
	if data is Dictionary:
		return data

	return {}
