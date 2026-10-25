extends Control
## Стартовое меню: Seed процедурной генерации, размер мира 1×1 / 10×10 / 50×50 км.

var _seed_edit: LineEdit
var _size_buttons: Array[Button] = []
var _selected_size_km: float = 1.0

func _ready() -> void:
	# Фон: сгенерированная иллюстрация ночной долины и НЗТБНЗ
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex: Texture2D = GameMaterials.tex("menu_bg")
	if tex != null:
		bg.texture = tex
	else:
		bg.modulate = Color(0.04, 0.0, 0.06)
	add_child(bg)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.0, 0.03, 0.42)
	add_child(shade)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(-330, -300)
	center.custom_minimum_size = Vector2(660, 600)
	center.add_theme_constant_override("separation", 14)
	add_child(center)
	var title := _label("ТЕМНЫЙ БОГ", 54, Color(1.0, 0.82, 0.82))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)
	var title2 := _label("НАДУВНЫХ ЗАМКОВ", 54, Color(1.0, 0.45, 0.5))
	title2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title2)
	var sub := _label("3D-хоррор · физическая песочница · открытый процедурный мир\nНочь, 22:00. В долине стоит Надувной Замок Темного Бога… и он живой.", 19, Color(0.9, 0.85, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(sub)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.0, 0.03, 0.82)
	sb.border_color = Color(0.85, 0.3, 0.35, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("Seed мира (процедурная генерация):", 20, Color(1, 0.9, 0.85)))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	box.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(randi() % 900000 + 1000)
	_seed_edit.custom_minimum_size = Vector2(280, 52)
	_seed_edit.add_theme_font_size_override("font_size", 22)
	seed_row.add_child(_seed_edit)
	var btn_random := _button("🎲 Случайный")
	btn_random.pressed.connect(func() -> void:
		_seed_edit.text = str(randi() % 9000000 + 1000))
	seed_row.add_child(btn_random)
	box.add_child(_label("Размер мира:", 20, Color(1, 0.9, 0.85)))
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	box.add_child(size_row)
	var sizes: Array = [[1.0, "1×1 км"], [10.0, "10×10 км"], [50.0, "50×50 км"]]
	for entry: Array in sizes:
		var b := _button(entry[1])
		b.toggle_mode = true
		var km: float = entry[0]
		b.pressed.connect(func() -> void: _select_size(km))
		size_row.add_child(b)
		_size_buttons.append(b)
	_size_buttons[0].button_pressed = true
	var btn_start := _button("▶  Начать игру", 28)
	btn_start.custom_minimum_size = Vector2(0, 76)
	btn_start.pressed.connect(_start_game)
	box.add_child(btn_start)
	var help := _label("Сенсорное управление: слева джойстик (дальше — бег), справа свайп — камера,\nкнопки действий справа. На ПК: WASD + мышь, Space — прыжок, Tab — отладка.", 16, Color(0.8, 0.8, 0.88))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(help)
	var ver := _label("Godot Engine 4.7.2 · Jolt Physics · Aerodynamic Physics · Mobile renderer", 15, Color(0.65, 0.6, 0.7))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(ver)
	AudioManager.play_music("music_menu", -10.0)

func _label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func _button(text: String, font_size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.01, 0.04, 0.9)
	normal.border_color = Color(0.85, 0.32, 0.38, 0.95)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", normal)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.62, 0.1, 0.15, 0.95)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(1, 0.94, 0.94))
	b.custom_minimum_size = Vector2(150, 54)
	return b

func _select_size(km: float) -> void:
	_selected_size_km = km
	var sizes: Array[float] = [1.0, 10.0, 50.0]
	for i: int in _size_buttons.size():
		_size_buttons[i].button_pressed = sizes[i] == km

func _start_game() -> void:
	var seed_value: int = 1337
	if _seed_edit.text.is_valid_int():
		seed_value = _seed_edit.text.to_int()
	else:
		seed_value = _seed_edit.text.hash()
	GameState.world_seed = seed_value
	GameState.world_size_km = _selected_size_km
	GameState.game_minutes = 22.0 * 60.0
	GameState.day_count = 1
	AudioManager.stop_music()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
