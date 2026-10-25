extends Node
## AudioManager (autoload) — все звуки в Ogg Vorbis (assets/audio).
## Шины Master/Music/SFX/Ambient, пул SFX-плееров, позиционные звуки,
## атмосферные петли (ночь/день/ветер по силе), музыка состояний.

const AUDIO_DIR: String = "res://assets/audio/"

var streams: Dictionary = {}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0

var music_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var wind_player: AudioStreamPlayer

func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Ambient")
	for i: int in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Ambient"
	add_child(ambient_player)
	wind_player = AudioStreamPlayer.new()
	wind_player.bus = "Ambient"
	add_child(wind_player)
	_preload()

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func _preload() -> void:
	var names: Array[String] = [
		"wind_calm", "wind_breeze", "wind_storm", "night_ambience", "day_ambience",
		"water_shore", "suction_roar", "cyclone_roar", "wing_flap_loop",
		"music_menu", "music_dark_ambient", "music_nyashing", "music_fly",
		"boing_1", "boing_2", "boing_3", "pvc_squeak_1", "pvc_squeak_2",
		"pvc_squeak_3", "pvc_squeak_4", "step_soft_1", "step_soft_2",
		"splash", "rope_creak", "gate_hiss", "thunder_1", "thunder_2",
		"chime_magic", "heartbeat", "snore_soft",
	]
	var loops: Array[String] = ["wind_calm", "wind_breeze", "wind_storm", "night_ambience",
		"day_ambience", "water_shore", "suction_roar", "cyclone_roar", "wing_flap_loop",
		"music_menu", "music_dark_ambient", "music_nyashing", "music_fly"]
	for n: String in names:
		var path: String = AUDIO_DIR + n + ".ogg"
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path) as AudioStream
			if s is AudioStreamOggVorbis and loops.has(n):
				(s as AudioStreamOggVorbis).loop = true
			streams[n] = s

func get_stream(stream_name: String) -> AudioStream:
	return streams.get(stream_name, null) as AudioStream

## Короткий звук без позиции (UI, контакты игрока).
func play_sfx(stream_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s: AudioStream = get_stream(stream_name)
	if s == null:
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()

## Короткий 3D-звук в точке мира. Родитель — текущая сцена.
func play_sfx_3d(stream_name: String, at_position: Vector3, volume_db: float = 0.0, max_distance: float = 120.0) -> void:
	var s: AudioStream = get_stream(stream_name)
	if s == null:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.global_position = at_position
	tree.current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func play_music(stream_name: String, volume_db: float = -8.0) -> void:
	var s: AudioStream = get_stream(stream_name)
	if s == null:
		return
	if music_player.stream == s and music_player.playing:
		return
	music_player.stream = s
	music_player.volume_db = volume_db
	music_player.play()

func stop_music() -> void:
	music_player.stop()

## Атмосфера: ночь/день + ветер по текущей скорости (вызывается из Main).
func update_ambience(is_night: bool, wind_kmh: float) -> void:
	var amb_name: String = "night_ambience" if is_night else "day_ambience"
	var amb: AudioStream = get_stream(amb_name)
	if amb != null and ambient_player.stream != amb:
		ambient_player.stream = amb
		ambient_player.volume_db = -16.0
		ambient_player.play()
	var wind_name: String = "wind_calm"
	var vol: float = -26.0
	if wind_kmh >= 70.0:
		wind_name = "wind_storm"
		vol = -6.0
	elif wind_kmh >= 35.0:
		wind_name = "wind_breeze"
		vol = -10.0
	elif wind_kmh >= 15.0:
		wind_name = "wind_breeze"
		vol = -16.0
	var w: AudioStream = get_stream(wind_name)
	if w != null and wind_player.stream != w:
		wind_player.stream = w
		wind_player.play()
	wind_player.volume_db = vol
	wind_player.pitch_scale = clampf(0.8 + wind_kmh / 120.0 * 0.5, 0.8, 1.35)
