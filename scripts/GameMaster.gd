extends Node2D

@export_range(1.0, 120.0, 1.0, "or_greater", "suffix:cps") var typewriter_characters_per_second: float = 35.0

@onready var day_label: Label = $CanvasLayer/MainLayout/Header/DayLabel
@onready var weather_label: Label = $CanvasLayer/MainLayout/Header/WeatherLabel
@onready var content_text: RichTextLabel = $CanvasLayer/MainLayout/ContentText
@onready var options_text: RichTextLabel = $CanvasLayer/MainLayout/OptionsText
@onready var command_input: LineEdit = $CanvasLayer/MainLayout/InputArea/CommandInput
@onready var prefix_label: Label = $CanvasLayer/MainLayout/InputArea/Prefix
@onready var crt_overlay: ColorRect = $CanvasLayer/CRT_Overlay

@onready var logic_manager = $LogicManager
@onready var audio_manager = $AudioManager

var terror_value: int = 0
var current_body_text: String = ""
var is_typewriter_playing: bool = false
var typewriter_tween: Tween
var sanity_state: String = "理智"


func _ready() -> void:
	_setup_ui_style()
	call_deferred("_initialize_ui")


func _setup_ui_style() -> void:
	$CanvasLayer/Background.color = Color.BLACK

	var ui_font = SystemFont.new()
	ui_font.font_names = ["JetBrains Mono", "Consolas", "SimSun", "Microsoft YaHei UI"]

	for label in [day_label, weather_label, prefix_label]:
		label.add_theme_font_override("font", ui_font)
		label.add_theme_font_size_override("font_size", 18)
		label.modulate = Color.WHITE

	for separator in [$CanvasLayer/MainLayout/DividerTop, $CanvasLayer/MainLayout/DividerMiddle]:
		separator.modulate = Color(1, 1, 1, 0.75)

	content_text.bbcode_enabled = false
	content_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_text.scroll_active = true
	content_text.scroll_following = false
	content_text.add_theme_font_override("normal_font", ui_font)
	content_text.add_theme_font_size_override("normal_font_size", 20)
	content_text.add_theme_constant_override("line_separation", 10)
	content_text.modulate = Color.WHITE

	options_text.bbcode_enabled = false
	options_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_text.fit_content = true
	options_text.scroll_active = false
	options_text.add_theme_font_override("normal_font", ui_font)
	options_text.add_theme_font_size_override("normal_font_size", 18)
	options_text.add_theme_constant_override("line_separation", 8)
	options_text.modulate = Color.WHITE

	command_input.add_theme_font_override("font", ui_font)
	command_input.add_theme_font_size_override("font_size", 18)
	command_input.flat = true
	command_input.focus_mode = Control.FOCUS_ALL
	command_input.keep_editing_on_text_submit = true
	command_input.caret_force_displayed = true
	command_input.modulate = Color.WHITE
	command_input.placeholder_text = "输入数字或关键词"


func _initialize_ui() -> void:
	logic_manager.initialize_game()
	_render_current_page()
	_ensure_command_input_focus()


func _render_current_page() -> void:
	day_label.text = "[ %s ]" % logic_manager.get_day_label()
	weather_label.text = "[ 天气：%s ]" % logic_manager.get_weather_label()
	_render_body_text(logic_manager.get_page_body_text())
	options_text.text = logic_manager.get_page_options_text()
	content_text.scroll_to_line(0)
	_ensure_command_input_focus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	if not event.pressed or event.echo:
		return

	if is_typewriter_playing and event.is_action_pressed("ui_accept"):
		if command_input.text.strip_edges() != "":
			return
		_complete_typewriter_text()
		_ensure_command_input_focus()
		get_viewport().set_input_as_handled()
		return

	if not logic_manager.supports_cursor_navigation():
		return

	if event.is_action_pressed("ui_up"):
		logic_manager.move_cursor(-1)
		_render_current_page()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_down"):
		logic_manager.move_cursor(1)
		_render_current_page()
		get_viewport().set_input_as_handled()
		return


func _on_command_input_text_submitted(new_text: String) -> void:
	var trimmed = new_text.strip_edges()
	if is_typewriter_playing:
		_complete_typewriter_text()
		if trimmed == "":
			_ensure_command_input_focus()
			return
		_submit_command(trimmed)
		return

	if trimmed == "":
		return

	_submit_command(trimmed)


func _render_body_text(full_text: String) -> void:
	_stop_typewriter_animation(false)
	current_body_text = full_text
	content_text.text = current_body_text
	content_text.scroll_to_line(0)

	var total_characters = content_text.get_total_character_count()
	if total_characters <= 0 or typewriter_characters_per_second <= 0.0:
		content_text.visible_characters = -1
		is_typewriter_playing = false
		return

	var reveal_start = _get_reveal_start_index(current_body_text)
	if reveal_start >= total_characters:
		content_text.visible_characters = -1
		is_typewriter_playing = false
		return

	content_text.visible_characters = reveal_start
	is_typewriter_playing = true

	var duration = max(float(total_characters - reveal_start) / typewriter_characters_per_second, 0.01)
	typewriter_tween = create_tween()
	typewriter_tween.tween_method(_set_visible_characters, float(reveal_start), float(total_characters), duration)
	typewriter_tween.finished.connect(_on_typewriter_finished)


func _get_reveal_start_index(full_text: String) -> int:
	var current_page = str(logic_manager.get_current_ui_page())
	match current_page:
		"MAIN", "MAIL_HOME":
			return 0
		"MAIL_DAY_MESSAGE_LIST":
			var marker = "【邮件正文】\n"
			var marker_index = full_text.find(marker)
			if marker_index == -1:
				return content_text.get_total_character_count()
			return marker_index + marker.length()
		_:
			return content_text.get_total_character_count()


func _set_visible_characters(value: float) -> void:
	content_text.visible_characters = mini(int(round(value)), content_text.get_total_character_count())


func _complete_typewriter_text() -> void:
	_stop_typewriter_animation(true)


func _stop_typewriter_animation(show_full_text: bool) -> void:
	if typewriter_tween != null:
		typewriter_tween.kill()
		typewriter_tween = null

	if show_full_text:
		content_text.visible_characters = -1

	is_typewriter_playing = false


func _on_typewriter_finished() -> void:
	typewriter_tween = null
	content_text.visible_characters = -1
	is_typewriter_playing = false
	_ensure_command_input_focus()


func _submit_command(command: String) -> void:
	logic_manager.process_command(command)
	command_input.clear()
	_render_current_page()
	_ensure_command_input_focus()


func _ensure_command_input_focus() -> void:
	call_deferred("_apply_command_input_focus")


func _apply_command_input_focus() -> void:
	if not is_instance_valid(command_input):
		return

	command_input.grab_focus()
	command_input.caret_column = command_input.text.length()
	command_input.deselect()


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
