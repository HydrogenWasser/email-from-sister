extends Node2D

const PAUSE_OPTION_SAVE := "save"
const PAUSE_OPTION_LOAD := "load"
const PAUSE_OPTION_QUIT := "quit"

@export_range(1.0, 120.0, 1.0, "or_greater", "suffix:cps") var typewriter_characters_per_second: float = 35.0

@onready var day_label: Label = $CanvasLayer/MainLayout/Header/DayLabel
@onready var weather_label: Label = $CanvasLayer/MainLayout/Header/WeatherLabel
@onready var content_text: RichTextLabel = $CanvasLayer/MainLayout/ContentText
@onready var options_text: RichTextLabel = $CanvasLayer/MainLayout/OptionsText
@onready var prefix_label: Label = $CanvasLayer/MainLayout/InputArea/Prefix
@onready var crt_overlay: ColorRect = $CanvasLayer/CRT_Overlay

@onready var pause_overlay: Control = $CanvasLayer/PauseOverlay
@onready var pause_title: Label = $CanvasLayer/PauseOverlay/MenuFrame/MenuLayout/PauseTitle
@onready var pause_body_text: RichTextLabel = $CanvasLayer/PauseOverlay/MenuFrame/MenuLayout/PauseBodyText
@onready var pause_options_text: RichTextLabel = $CanvasLayer/PauseOverlay/MenuFrame/MenuLayout/PauseOptionsText

@onready var logic_manager = $LogicManager
@onready var audio_manager = $AudioManager

var terror_value: int = 0
var current_body_text: String = ""
var current_static_text: String = ""
var current_animated_text: String = ""
var is_typewriter_playing: bool = false
var typewriter_tween: Tween
var sanity_state: String = "理智"

var pause_menu_open: bool = false
var pause_selected_index: int = 0
var option_attention_phase: float = 0.0
var attention_overlay_active: bool = false
var crt_material: ShaderMaterial
var base_noise_intensity: float = 0.05
var base_flicker_intensity: float = 0.02


func _ready() -> void:
	_setup_ui_style()
	set_process(true)
	call_deferred("_initialize_ui")


func _setup_ui_style() -> void:
	$CanvasLayer/Background.color = Color.BLACK
	$CanvasLayer/PauseOverlay/Dimmer.color = Color(0, 0, 0, 0.86)
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	if crt_overlay.material is ShaderMaterial:
		crt_material = crt_overlay.material as ShaderMaterial
		base_noise_intensity = float(crt_material.get_shader_parameter("noise_intensity"))
		base_flicker_intensity = float(crt_material.get_shader_parameter("flicker_intensity"))

	var ui_font = SystemFont.new()
	ui_font.font_names = ["JetBrains Mono", "Consolas", "SimSun", "Microsoft YaHei UI"]

	for label in [day_label, weather_label, prefix_label, pause_title]:
		label.add_theme_font_override("font", ui_font)
		label.add_theme_font_size_override("font_size", 18)
		label.modulate = Color.WHITE

	prefix_label.text = ""

	for separator in [
		$CanvasLayer/MainLayout/DividerTop,
		$CanvasLayer/MainLayout/DividerMiddle,
		$CanvasLayer/PauseOverlay/MenuFrame/MenuLayout/PauseDividerTop,
		$CanvasLayer/PauseOverlay/MenuFrame/MenuLayout/PauseDividerBottom
	]:
		separator.modulate = Color(1, 1, 1, 0.75)

	_style_rich_text(content_text, ui_font, 20, 10)
	_style_rich_text(options_text, ui_font, 18, 8)
	_style_rich_text(pause_body_text, ui_font, 20, 10)
	_style_rich_text(pause_options_text, ui_font, 18, 8)


func _style_rich_text(label: RichTextLabel, ui_font: Font, font_size: int, line_separation: int) -> void:
	label.bbcode_enabled = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.scroll_active = false
	label.scroll_following = false
	label.add_theme_font_override("normal_font", ui_font)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_constant_override("line_separation", line_separation)
	label.modulate = Color.WHITE


func _initialize_ui() -> void:
	logic_manager.initialize_game()

	var pending_snapshot = SaveManager.consume_pending_snapshot()
	if not pending_snapshot.is_empty():
		logic_manager.apply_save_snapshot(pending_snapshot)

	_render_current_page()
	_close_pause_menu()


func _render_current_page() -> void:
	_render_page_chrome()
	_render_body_text(logic_manager.get_page_body_text())
	_render_pause_menu()


func _render_page_chrome() -> void:
	day_label.text = "[ %s ]" % logic_manager.get_day_label()
	weather_label.text = "[ 天气：%s ]" % logic_manager.get_weather_label()
	_render_option_text()
	_render_pause_menu()


func _process(delta: float) -> void:
	if pause_menu_open:
		_update_attention_overlay_effect(false)
		return

	var option_entries = logic_manager.get_page_option_entries()
	if not _has_attention_option(option_entries):
		_update_attention_overlay_effect(false)
		if not is_zero_approx(option_attention_phase):
			option_attention_phase = 0.0
			_render_option_text(option_entries)
		return

	option_attention_phase = fposmod(option_attention_phase + delta * 2.0, TAU)
	_update_attention_overlay_effect(true)
	_render_option_text(option_entries)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	if not event.pressed or event.echo:
		return

	if event.is_action_pressed("ui_cancel"):
		_mark_input_handled()
		_toggle_pause_menu()
		return

	if pause_menu_open:
		if event.is_action_pressed("ui_up"):
			pause_selected_index = _wrap_index(pause_selected_index - 1, _get_pause_options().size())
			_render_pause_menu()
			_mark_input_handled()
			return

		if event.is_action_pressed("ui_down"):
			pause_selected_index = _wrap_index(pause_selected_index + 1, _get_pause_options().size())
			_render_pause_menu()
			_mark_input_handled()
			return

		if event.is_action_pressed("ui_accept"):
			_mark_input_handled()
			_activate_pause_option(_get_pause_options()[pause_selected_index])
			return

		return

	if event.is_action_pressed("ui_accept") and is_typewriter_playing:
		_complete_typewriter_text()
		_mark_input_handled()
		return

	if event.is_action_pressed("ui_up") and logic_manager.supports_cursor_navigation():
		logic_manager.move_cursor(-1)
		_render_page_chrome()
		_mark_input_handled()
		return

	if event.is_action_pressed("ui_down") and logic_manager.supports_cursor_navigation():
		logic_manager.move_cursor(1)
		_render_page_chrome()
		_mark_input_handled()
		return

	if event.is_action_pressed("ui_accept") and logic_manager.supports_cursor_navigation():
		logic_manager.confirm_current_selection()
		_render_current_page()
		_mark_input_handled()
		return


func _get_pause_options() -> Array[Dictionary]:
	return [
		{"id": PAUSE_OPTION_SAVE, "label": "保存游戏", "disabled": false},
		{"id": PAUSE_OPTION_LOAD, "label": "读取存档", "disabled": not SaveManager.has_valid_save()},
		{"id": PAUSE_OPTION_QUIT, "label": "退出游戏", "disabled": false}
	]


func _activate_pause_option(option: Dictionary) -> void:
	if bool(option.get("disabled", false)):
		return

	match str(option.get("id", "")):
		PAUSE_OPTION_SAVE:
			if SaveManager.save_snapshot(logic_manager.build_save_snapshot()):
				_close_pause_menu()
				_render_page_chrome()
		PAUSE_OPTION_LOAD:
			var snapshot = SaveManager.load_snapshot()
			if snapshot.is_empty():
				return
			if logic_manager.apply_save_snapshot(snapshot):
				_close_pause_menu()
				_render_current_page()
		PAUSE_OPTION_QUIT:
			get_tree().quit()


func _toggle_pause_menu() -> void:
	if pause_menu_open:
		_close_pause_menu()
		_render_page_chrome()
		return

	if is_typewriter_playing:
		_complete_typewriter_text()

	pause_menu_open = true
	pause_selected_index = 0
	_render_pause_menu()


func _close_pause_menu() -> void:
	pause_menu_open = false
	pause_selected_index = 0
	pause_overlay.visible = false


func _render_pause_menu() -> void:
	pause_overlay.visible = pause_menu_open
	if not pause_menu_open:
		return

	pause_title.text = "[ 暂停 ]"
	pause_body_text.text = "游戏已暂停。\n\n当前进度可以保存，或从已有存档恢复。"

	var lines: Array[String] = []
	var options = _get_pause_options()
	for index in options.size():
		var option = options[index]
		var line = "- %s" % str(option.get("label", ""))
		if bool(option.get("disabled", false)):
			line += "（不可用）"
		if index == pause_selected_index:
			line += " <--"
		lines.append(line)

	pause_options_text.text = "\n".join(lines)


func _render_option_text(option_entries: Array[Dictionary] = []) -> void:
	if option_entries.is_empty():
		option_entries = logic_manager.get_page_option_entries()

	options_text.clear()
	for index in option_entries.size():
		var entry = option_entries[index]
		var line = _build_option_display_line(entry)
		if bool(entry.get("attention", false)):
			options_text.push_color(_get_attention_color())
			options_text.add_text(line)
			options_text.pop()
		else:
			options_text.add_text(line)

		if index < option_entries.size() - 1:
			options_text.newline()


func _build_option_display_line(entry: Dictionary) -> String:
	var line = "- %s" % str(entry.get("label", "")).strip_edges()
	if bool(entry.get("selected", false)):
		line += " <--"
	return line


func _has_attention_option(option_entries: Array[Dictionary]) -> bool:
	if str(logic_manager.get_current_ui_page()) != "MAIN":
		return false

	for entry in option_entries:
		if bool(entry.get("attention", false)):
			return true

	return false


func _get_attention_color() -> Color:
	var pulse = 0.68 + ((sin(option_attention_phase) + 1.0) * 0.16)
	return Color(pulse, pulse, pulse, 1.0)


func _update_attention_overlay_effect(is_active: bool) -> void:
	if crt_material == null:
		return

	if not is_active:
		if attention_overlay_active:
			crt_material.set_shader_parameter("noise_intensity", base_noise_intensity)
			crt_material.set_shader_parameter("flicker_intensity", base_flicker_intensity)
			attention_overlay_active = false
		return

	attention_overlay_active = true
	var pulse = (sin(option_attention_phase) + 1.0) * 0.5
	var boosted_noise = min(base_noise_intensity + 0.03 + pulse * 0.03, 1.0)
	var boosted_flicker = min(base_flicker_intensity + 0.01 + pulse * 0.015, 1.0)
	crt_material.set_shader_parameter("noise_intensity", boosted_noise)
	crt_material.set_shader_parameter("flicker_intensity", boosted_flicker)


func _render_body_text(full_text: String) -> void:
	_stop_typewriter_animation(false)
	current_body_text = full_text
	var reveal_start = _get_reveal_start_index(current_body_text)
	current_static_text = current_body_text.substr(0, reveal_start)
	current_animated_text = current_body_text.substr(reveal_start)

	if current_animated_text.length() <= 0 or typewriter_characters_per_second <= 0.0:
		content_text.text = current_body_text
		_align_content_to_bottom()
		is_typewriter_playing = false
		return

	content_text.text = current_static_text
	_align_content_to_bottom()
	is_typewriter_playing = true

	var duration = max(float(current_animated_text.length()) / typewriter_characters_per_second, 0.01)
	typewriter_tween = create_tween()
	typewriter_tween.tween_method(_set_typewriter_progress, 0.0, float(current_animated_text.length()), duration)
	typewriter_tween.finished.connect(_on_typewriter_finished)


func _get_reveal_start_index(full_text: String) -> int:
	var current_page = str(logic_manager.get_current_ui_page())
	match current_page:
		"MAIN", "MAIL_HOME":
			return 0
		"MAIL_DAY_MESSAGE_LIST":
			var split_index = full_text.find("\n\n")
			if split_index == -1:
				return full_text.length()
			return split_index + 2
		_:
			return full_text.length()


func _set_typewriter_progress(value: float) -> void:
	var visible_count = clampi(int(round(value)), 0, current_animated_text.length())
	content_text.text = current_static_text + current_animated_text.substr(0, visible_count)
	_align_content_to_bottom()


func _complete_typewriter_text() -> void:
	_stop_typewriter_animation(true)


func _stop_typewriter_animation(show_full_text: bool) -> void:
	if typewriter_tween != null:
		typewriter_tween.kill()
		typewriter_tween = null

	if show_full_text:
		content_text.text = current_body_text
		_align_content_to_bottom()

	is_typewriter_playing = false


func _on_typewriter_finished() -> void:
	typewriter_tween = null
	content_text.text = current_body_text
	_align_content_to_bottom()
	is_typewriter_playing = false


func _align_content_to_bottom() -> void:
	if not is_instance_valid(content_text):
		return

	var target_line = maxi(content_text.get_line_count() - 1, 0)
	content_text.scroll_to_line(target_line)


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


func add_terror(value: int) -> void:
	var previous_terror = terror_value
	terror_value = clamp(terror_value + value, 0, 100)

	if terror_value >= 95:
		sanity_state = "崩溃"
	elif terror_value >= 80:
		sanity_state = "恐惧"
	elif terror_value >= 50:
		sanity_state = "不安"
	else:
		sanity_state = "理智"

	audio_manager.update_heartbeat(terror_value / 100.0)

	if terror_value != previous_terror:
		_trigger_crt_shake(abs(value))


func _trigger_crt_shake(amount: int = 10) -> void:
	var material = crt_overlay.material
	if material == null or not (material is ShaderMaterial):
		return

	var intensity = clamp(0.005 + float(amount) / 1000.0, 0.005, 0.03)
	material.set_shader_parameter("shake_intensity", intensity)

	var tween = create_tween()
	tween.tween_method(
		func(v: float) -> void:
			material.set_shader_parameter("shake_intensity", v),
		intensity,
		0.0,
		0.35
	)
