extends Node

# ==================== 音频管理器 ====================
# 负责: 背景底噪、音效、环境音

@onready var ambient_player: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var heartbeat_player: AudioStreamPlayer = AudioStreamPlayer.new()

var base_volume: float = -20.0  # 基础音量 (dB)
var heartbeat_intensity: float = 0.0  # 0-1

func _ready():
	add_child(ambient_player)
	add_child(sfx_player)
	add_child(heartbeat_player)
	
	# 启动背景底噪
	_play_ambient_noise()
	
	print("音频管理器初始化完成")

func _play_ambient_noise():
	# 使用程序生成的噪声作为背景音
	# 由于我们没有实际音频文件，使用一个低音量占位
	ambient_player.volume_db = base_volume

# ==================== 音效控制 ====================

func play_sound_effect(sound_type: String):
	match sound_type:
		"static":
			# 电视静电噪音
			sfx_player.volume_db = base_volume - 5
			# 模拟静态噪音
			_play_static_noise()
		"door_creak":
			# 门吱呀声
			sfx_player.volume_db = base_volume + 5
			_play_tone(200, 0.5, 0.3)
		"footstep":
			# 脚步声
			sfx_player.volume_db = base_volume
			_play_tone(100, 0.1, 0.1)
		"whisper":
			# 低语声
			sfx_player.volume_db = base_volume - 10
			_play_tone(400, 1.0, 0.5)
		"glitch":
			# 故障音效
			sfx_player.volume_db = base_volume - 5
			_play_glitch_sound()

func _play_static_noise():
	# 生成静电噪音（使用简单噪声模拟）
	pass  # 占位，实际项目中使用音频文件

func _play_tone(frequency: float, duration: float, volume_factor: float):
	# 生成简单音调
	pass  # 占位

func _play_glitch_sound():
	# 生成故障音效
	pass  # 占位

# ==================== 心跳声 ====================

func update_heartbeat(intensity: float):
	heartbeat_intensity = clamp(intensity, 0.0, 1.0)
	
	if heartbeat_intensity > 0.3:
		if not heartbeat_player.playing:
			heartbeat_player.play()
		heartbeat_player.volume_db = base_volume - 20 + (heartbeat_intensity * 20)
	else:
		heartbeat_player.stop()

# ==================== 音量控制 ====================

func set_ambient_volume(volume_db: float):
	ambient_player.volume_db = volume_db

func set_master_volume(volume_db: float):
	AudioServer.set_bus_volume_db(0, volume_db)

func fade_out_ambient(duration: float = 2.0):
	# 渐出背景音
	var tween = create_tween()
	tween.tween_property(ambient_player, "volume_db", -80.0, duration)

func fade_in_ambient(duration: float = 2.0):
	# 渐入背景音
	ambient_player.volume_db = -80.0
	var tween = create_tween()
	tween.tween_property(ambient_player, "volume_db", base_volume, duration)
