extends Node2D

const GAME_SCENE_PATH := "res://scenes/Main.tscn"

const MENU_STATE_ROOT := "root"
const MENU_STATE_LOAD_SELECT := "load_select"

const OPTION_NEW_GAME := "new_game"
const OPTION_LOAD_GAME := "load_game"
const OPTION_QUIT_GAME := "quit_game"
const OPTION_BACK := "back"
const MAX_VISIBLE_OPTIONS := 7

@onready var title_label: Label = $CanvasLayer/MainLayout/Header/TitleLabel
@onready var section_label: Label = $CanvasLayer/MainLayout/Header/SectionLabel
@onready var content_text: RichTextLabel = $CanvasLayer/MainLayout/ContentText
@onready var options_text: RichTextLabel = $CanvasLayer/MainLayout/OptionsText
@onready var prefix_label: Label = $CanvasLayer/MainLayout/InputArea/Prefix

var menu_state: String = MENU_STATE_ROOT
var selected_index: int = 0


func _ready() -> void:
	_setup_ui_style()
	_render_menu()


func _setup_ui_style() -> void:
	$CanvasLayer/Background.color = Color.BLACK

	var ui_font = SystemFont.new()
	ui_font.font_names = ["JetBrains Mono", "Consolas", "SimSun", "Microsoft YaHei UI"]

	for label in [title_label, section_label, prefix_label]:
		label.add_theme_font_override("font", ui_font)
		label.add_theme_font_size_override("font_size", 20)
		label.modulate = Color.WHITE

	prefix_label.text = ""

	for separator in [$CanvasLayer/MainLayout/DividerTop, $CanvasLayer/MainLayout/DividerMiddle]:
		separator.modulate = Color(1, 1, 1, 0.88)

	for rich_text in [content_text, options_text]:
		rich_text.bbcode_enabled = false
		rich_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rich_text.scroll_active = false
		rich_text.scroll_following = false
		rich_text.add_theme_font_override("normal_font", ui_font)
		rich_text.modulate = Color.WHITE

	content_text.add_theme_font_size_override("normal_font_size", 23)
	content_text.add_theme_constant_override("line_separation", 8)
	options_text.fit_content = true
	options_text.add_theme_font_size_override("normal_font_size", 21)
	options_text.add_theme_constant_override("line_separation", 6)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	if not event.pressed or event.echo:
		return

	if event.is_action_pressed("ui_cancel"):
		if menu_state != MENU_STATE_ROOT:
			menu_state = MENU_STATE_ROOT
			selected_index = 0
			_render_menu()
			_mark_input_handled()
		return

	if event.is_action_pressed("ui_up"):
		selected_index = _wrap_index(selected_index - 1, _get_current_options().size())
		_render_menu()
		_mark_input_handled()
		return

	if event.is_action_pressed("ui_down"):
		selected_index = _wrap_index(selected_index + 1, _get_current_options().size())
		_render_menu()
		_mark_input_handled()
		return

	if event.is_action_pressed("ui_accept"):
		_mark_input_handled()
		var options = _get_current_options()
		if options.is_empty():
			return
		_activate_option(options[selected_index])


func _activate_option(option: Dictionary) -> void:
	if bool(option.get("disabled", false)):
		return

	match menu_state:
		MENU_STATE_ROOT:
			match str(option.get("id", "")):
				OPTION_NEW_GAME:
					SaveManager.discard_pending_snapshot()
					get_tree().change_scene_to_file(GAME_SCENE_PATH)
				OPTION_LOAD_GAME:
					menu_state = MENU_STATE_LOAD_SELECT
					selected_index = 0
					_render_menu()
				OPTION_QUIT_GAME:
					get_tree().quit()
		MENU_STATE_LOAD_SELECT:
			match str(option.get("id", "")):
				OPTION_BACK:
					menu_state = MENU_STATE_ROOT
					selected_index = 0
					_render_menu()
				"load_slot":
					var slot_index = int(option.get("slot_index", -1))
					if SaveManager.stage_loaded_snapshot_from_slot(slot_index):
						get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _render_menu() -> void:
	SaveManager.clear_invalid_cache_if_needed()
	var options = _get_current_options()
	selected_index = _wrap_index(selected_index, options.size())

	title_label.text = "[ Email From Sister ]"
	section_label.text = "[ 主菜单 ]"
	content_text.text = _get_current_body_text()
	options_text.text = "\n".join(_build_option_lines(options))


func _get_current_body_text() -> String:
	match menu_state:
		MENU_STATE_LOAD_SELECT:
			return "[读取存档]\n\n选择一个存档栏位。"
		_:
			return ""


func _build_option_lines(options: Array[Dictionary]) -> Array[String]:
	var lines: Array[String] = []
	var visible_range = _get_visible_option_range(options.size(), selected_index)
	for index in range(int(visible_range.get("start", 0)), int(visible_range.get("end", 0))):
		var option = options[index]
		var line = "- %s" % str(option.get("label", "")).strip_edges()
		if bool(option.get("disabled", false)):
			line += "（不可用）"
		if index == selected_index:
			line += " <--"
		lines.append(line)
	return lines


func _get_current_options() -> Array[Dictionary]:
	match menu_state:
		MENU_STATE_LOAD_SELECT:
			return _get_load_slot_options()
		_:
			return _get_root_options()


func _get_root_options() -> Array[Dictionary]:
	return [
		{"id": OPTION_NEW_GAME, "label": "新游戏", "disabled": false},
		{"id": OPTION_LOAD_GAME, "label": "读取存档", "disabled": not SaveManager.has_any_valid_save()},
		{"id": OPTION_QUIT_GAME, "label": "退出游戏", "disabled": false}
	]


func _get_load_slot_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for slot in SaveManager.get_save_slots():
		options.append({
			"id": "load_slot",
			"slot_index": int(slot.get("slot_index", -1)),
			"label": _format_slot_label(slot),
			"disabled": not bool(slot.get("occupied", false))
		})

	options.append({"id": OPTION_BACK, "label": "返回", "disabled": false})
	return options


func _format_slot_label(slot: Dictionary) -> String:
	return "[栏位 %d] %s" % [
		int(slot.get("slot_number", int(slot.get("slot_index", 0)) + 1)),
		str(slot.get("save_time_label", SaveManager.EMPTY_SAVE_LABEL))
	]


func _mark_input_handled() -> void:
	var viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _wrap_index(index: int, size: int) -> int:
	if size <= 0:
		return 0

	var wrapped = index % size
	if wrapped < 0:
		wrapped += size
	return wrapped


func _get_visible_option_range(total_count: int, selected_index_value: int) -> Dictionary:
	if total_count <= 0:
		return {"start": 0, "end": 0}
	if total_count <= MAX_VISIBLE_OPTIONS:
		return {"start": 0, "end": total_count}

	var clamped_selected = clampi(selected_index_value, 0, total_count - 1)
	var start_index = clamped_selected - int(MAX_VISIBLE_OPTIONS / 2)
	start_index = clampi(start_index, 0, total_count - MAX_VISIBLE_OPTIONS)
	return {"start": start_index, "end": start_index + MAX_VISIBLE_OPTIONS}
