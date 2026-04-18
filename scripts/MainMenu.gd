extends Node2D

const GAME_SCENE_PATH := "res://scenes/Main.tscn"
const OPTION_NEW_GAME := "new_game"
const OPTION_LOAD_GAME := "load_game"
const OPTION_QUIT_GAME := "quit_game"

@onready var title_label: Label = $CanvasLayer/MainLayout/Header/TitleLabel
@onready var section_label: Label = $CanvasLayer/MainLayout/Header/SectionLabel
@onready var content_text: RichTextLabel = $CanvasLayer/MainLayout/ContentText
@onready var options_text: RichTextLabel = $CanvasLayer/MainLayout/OptionsText
@onready var prefix_label: Label = $CanvasLayer/MainLayout/InputArea/Prefix

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
		label.add_theme_font_size_override("font_size", 18)
		label.modulate = Color.WHITE

	prefix_label.text = ""

	for separator in [$CanvasLayer/MainLayout/DividerTop, $CanvasLayer/MainLayout/DividerMiddle]:
		separator.modulate = Color(1, 1, 1, 0.75)

	for rich_text in [content_text, options_text]:
		rich_text.bbcode_enabled = false
		rich_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rich_text.scroll_active = false
		rich_text.scroll_following = false
		rich_text.add_theme_font_override("normal_font", ui_font)
		rich_text.modulate = Color.WHITE

	content_text.add_theme_font_size_override("normal_font_size", 20)
	content_text.add_theme_constant_override("line_separation", 10)
	options_text.fit_content = true
	options_text.add_theme_font_size_override("normal_font_size", 18)
	options_text.add_theme_constant_override("line_separation", 8)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	if not event.pressed or event.echo:
		return

	if event.is_action_pressed("ui_up"):
		selected_index = _wrap_index(selected_index - 1, _get_menu_options().size())
		_render_menu()
		_mark_input_handled()
		return

	if event.is_action_pressed("ui_down"):
		selected_index = _wrap_index(selected_index + 1, _get_menu_options().size())
		_render_menu()
		_mark_input_handled()
		return

	if event.is_action_pressed("ui_accept"):
		_mark_input_handled()
		_activate_option(_get_menu_options()[selected_index])
		return


func _activate_option(option: Dictionary) -> void:
	if bool(option.get("disabled", false)):
		return

	match str(option.get("id", "")):
		OPTION_NEW_GAME:
			SaveManager.discard_pending_snapshot()
			get_tree().change_scene_to_file(GAME_SCENE_PATH)
		OPTION_LOAD_GAME:
			if SaveManager.stage_loaded_snapshot():
				get_tree().change_scene_to_file(GAME_SCENE_PATH)
			else:
				_render_menu()
		OPTION_QUIT_GAME:
			get_tree().quit()


func _render_menu() -> void:
	SaveManager.clear_invalid_cache_if_needed()
	selected_index = _wrap_index(selected_index, _get_menu_options().size())

	title_label.text = "[ Email From Sister ]"
	section_label.text = "[ 主菜单 ]"
	content_text.text = ""
	options_text.text = "\n".join(_build_option_lines())


func _build_option_lines() -> Array[String]:
	var lines: Array[String] = []
	var options = _get_menu_options()
	for index in options.size():
		var option = options[index]
		var line = "- %s" % str(option.get("label", ""))
		if bool(option.get("disabled", false)):
			line += "（不可用）"
		if index == selected_index:
			line += " <--"
		lines.append(line)
	return lines


func _get_menu_options() -> Array[Dictionary]:
	return [
		{"id": OPTION_NEW_GAME, "label": "新游戏", "disabled": false},
		{"id": OPTION_LOAD_GAME, "label": "读取存档", "disabled": not SaveManager.has_valid_save()},
		{"id": OPTION_QUIT_GAME, "label": "退出游戏", "disabled": false}
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
