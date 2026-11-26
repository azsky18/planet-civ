extends Node3D
## 행성 지도 프로토타입: 장면 구성, 카메라 조작, UI

const LEVELS := [5, 6, 7]
const LEVEL_LABELS := ["작게 (10,242칸)", "보통 (40,962칸)", "크게 (163,842칸, 느림)"]
const MODE_LABELS := ["지형", "고도", "기온", "강수량", "판 구조", "기압과 바람", "식생"]
## 화면에 표시되는 빌드 이름. PC에서 어떤 버전이 실행 중인지 확인하는 용도.
const BUILD := "v7.1 시점 돌리기 (Q/E, 휠 버튼 드래그)"
const COMPASS := ["북", "북동", "동", "남동", "남", "남서", "서", "북서"]

var hs := HexSphere.new()
var gen := WorldGen.new()
var view := PlanetView.new()

var pivot := Node3D.new()
var cam := Camera3D.new()
var sun := DirectionalLight3D.new()
var yaw: float = 0.4
var pitch: float = -0.35
var dist: float = 3.2
var dist_target: float = 3.2
## 바라보는 지점을 중심으로 카메라가 도는 방위각 (0 = 북쪽이 위)
var heading: float = 0.0
var _orbiting: bool = false
var dragging := false
var hover: int = -1
var selected: int = -1
var current_level: int = -1
var busy := false

# UI
var font_body: Font
var font_title: Font
var seed_edit := LineEdit.new()
var size_opt := OptionButton.new()
var land_slider := HSlider.new()
var plates_slider := HSlider.new()
var temp_slider := HSlider.new()
var moist_slider := HSlider.new()
var river_slider := HSlider.new()
var exag_slider := HSlider.new()
var mode_opt := OptionButton.new()
var river_chk := CheckBox.new()
var wind_chk := CheckBox.new()
var atmo_chk := CheckBox.new()
var grid_chk := CheckBox.new()
var art_chk := CheckBox.new()
var status_lbl := Label.new()
var info_lbl := RichTextLabel.new()
var legend_box := VBoxContainer.new()
var stats_lbl := Label.new()


func _ready() -> void:
	font_body = load("res://fonts/NanumGothic-Regular.ttf")
	font_title = load("res://fonts/NanumMyeongjo-ExtraBold.ttf")
	_setup_scene()
	_setup_ui()
	await get_tree().process_frame
	_regenerate()
	var shot: String = ""
	for a in OS.get_cmdline_user_args():
		while busy:
			await get_tree().process_frame
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a.begins_with("--dist="):
			dist = float(a.substr(7))
			dist_target = dist
		elif a.begins_with("--heading="):
			heading = deg_to_rad(float(a.substr(10)))
		elif a.begins_with("--seed="):
			seed_edit.text = a.substr(7)
			_regenerate()
		elif a.begins_with("--exag="):
			exag_slider.value = float(a.substr(7))
			view.exaggeration = exag_slider.value
			view.rebuild()
		elif a.begins_with("--size="):
			size_opt.select(int(a.substr(7)))
			_regenerate()
		elif a.begins_with("--pick="):
			_update_camera()
			await get_tree().process_frame
			var xy: PackedStringArray = a.substr(7).split(",")
			_pick(Vector2(float(xy[0]), float(xy[1])))
			selected = hover
			_update_info()
		elif a == "--demo":
			_demo_town()
		elif a.begins_with("--key="):
			_layer_action(OS.find_keycode_from_string(a.substr(6)))
		elif a.begins_with("--mode="):
			mode_opt.select(int(a.substr(7)))
			_on_mode(int(a.substr(7)))
	_update_camera()
	if shot != "":
		while busy:
			await get_tree().process_frame
		for _f in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _setup_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("070b12")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a94a8")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun.light_energy = 1.25
	sun.light_color = Color("fff1d8")
	sun.rotation = Vector3(deg_to_rad(-25), deg_to_rad(-40), 0)
	add_child(sun)

	add_child(pivot)
	pivot.add_child(cam)
	cam.fov = 40.0
	cam.near = 0.01
	cam.far = 200.0
	_update_camera()

	view.hs = hs
	view.gen = gen
	add_child(view)
	_add_stars()


func _add_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	for _s in 1500:
		var v := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * 60.0
		pos.append(v)
		var b: float = rng.randf_range(0.25, 0.9)
		cols.append(Color(b, b * 0.97, b * 0.9))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.use_point_size = true
	mat.point_size = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)


# ---------------------------------------------------------------- UI

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.09, 0.06, 0.9)
	sb.border_color = Color("b48d43")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	return sb


func _setup_ui() -> void:
	var theme := Theme.new()
	theme.default_font = font_body
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", Color("efe3c4"))
	theme.set_color("font_color", "CheckBox", Color("efe3c4"))
	theme.set_color("default_color", "RichTextLabel", Color("efe3c4"))
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("5a3f22")
	btn.border_color = Color("c9a24a")
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(3)
	btn.set_content_margin_all(6)
	var btn_h := btn.duplicate() as StyleBoxFlat
	btn_h.bg_color = Color("74532d")
	for t in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", t, btn)
		theme.set_stylebox("hover", t, btn_h)
		theme.set_stylebox("pressed", t, btn_h)
		theme.set_color("font_color", t, Color("f5e9c8"))
		theme.set_color("font_hover_color", t, Color("ffffff"))
	var le := StyleBoxFlat.new()
	le.bg_color = Color("1c140d")
	le.border_color = Color("8a6a35")
	le.set_border_width_all(1)
	le.set_content_margin_all(6)
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_color("font_color", "LineEdit", Color("f5e9c8"))

	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	layer.add_child(root)

	# 왼쪽: 생성 설정
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _panel_style())
	left.position = Vector2(14, 14)
	left.custom_minimum_size = Vector2(290, 0)
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)

	var title := Label.new()
	title.text = "행성 지도 시제품"
	title.add_theme_font_override("font", font_title)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e8c872"))
	lv.add_child(title)
	var sub := Label.new()
	sub.text = "판 구조, 대기 순환, 물의 흐름으로 만든 세계\n빌드: " + BUILD
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color("b9a67c"))
	lv.add_child(sub)
	lv.add_child(HSeparator.new())

	var seed_row := HBoxContainer.new()
	seed_edit.text = "1"
	seed_edit.custom_minimum_size = Vector2(120, 0)
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.text_submitted.connect(func(_t): _regenerate())
	var dice := Button.new()
	dice.text = "무작위"
	dice.pressed.connect(func():
		seed_edit.text = str(randi() % 1000000)
		_regenerate())
	seed_row.add_child(_lbl("시드", 44))
	seed_row.add_child(seed_edit)
	seed_row.add_child(dice)
	lv.add_child(seed_row)

	for k in LEVEL_LABELS.size():
		size_opt.add_item(LEVEL_LABELS[k], k)
	size_opt.select(1)
	lv.add_child(_row("크기", size_opt))

	_setup_slider(lv, land_slider, "육지 비율", 0.15, 0.6, 0.01, 0.32, func(v): return "%d%%" % int(v * 100))
	_setup_slider(lv, plates_slider, "판 개수", 6, 30, 1, 16, func(v): return str(int(v)))
	_setup_slider(lv, temp_slider, "평균 기온", -10, 10, 0.5, 0, func(v): return "%+.1f°C" % v)
	_setup_slider(lv, moist_slider, "강수량", 0.5, 1.8, 0.05, 1.0, func(v): return "×%.2f" % v)
	_setup_slider(lv, river_slider, "강의 양", 0.3, 2.5, 0.1, 1.0, func(v): return "×%.1f" % v)

	var gen_btn := Button.new()
	gen_btn.text = "세계 생성"
	gen_btn.pressed.connect(_regenerate)
	lv.add_child(gen_btn)
	status_lbl.add_theme_font_size_override("font_size", 12)
	status_lbl.add_theme_color_override("font_color", Color("b9a67c"))
	lv.add_child(status_lbl)

	lv.add_child(HSeparator.new())
	for k in MODE_LABELS.size():
		mode_opt.add_item(MODE_LABELS[k], k)
	mode_opt.item_selected.connect(_on_mode)
	lv.add_child(_row("보기", mode_opt))
	_setup_slider(lv, exag_slider, "고도 과장", 0.0, 4.0, 0.1, 1.0, func(v): return "×%.1f" % v)
	exag_slider.drag_ended.connect(func(_c):
		view.exaggeration = exag_slider.value
		if current_level >= 0:
			view.rebuild()
			if hover >= 0:
				view.set_hover(hover))
	river_chk.text = "강 표시"
	river_chk.button_pressed = true
	river_chk.toggled.connect(func(on): view.river_mi.visible = on)
	wind_chk.text = "바람 화살표"
	wind_chk.toggled.connect(func(on): view.wind_mi.visible = on or view.mode == PlanetView.Mode.WIND)
	atmo_chk.text = "대기"
	atmo_chk.button_pressed = true
	atmo_chk.toggled.connect(func(on): view.atmo_mi.visible = on)
	grid_chk.text = "격자"
	grid_chk.button_pressed = true
	grid_chk.toggled.connect(func(on): view.grid_mi.visible = on)
	var chk_row := HBoxContainer.new()
	chk_row.add_child(river_chk)
	chk_row.add_child(grid_chk)
	chk_row.add_child(atmo_chk)
	lv.add_child(chk_row)
	art_chk.text = "타일 그림"
	art_chk.button_pressed = true
	art_chk.toggled.connect(func(on):
		view.art_enabled = on
		if current_level >= 0:
			view.recolor())
	var chk_row2 := HBoxContainer.new()
	chk_row2.add_child(wind_chk)
	chk_row2.add_child(art_chk)
	lv.add_child(chk_row2)

	lv.add_child(HSeparator.new())
	lv.add_child(legend_box)
	stats_lbl.add_theme_font_size_override("font_size", 12)
	stats_lbl.add_theme_color_override("font_color", Color("b9a67c"))
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_lbl.custom_minimum_size = Vector2(260, 0)
	lv.add_child(stats_lbl)

	# 오른쪽 위: 타일 정보
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", _panel_style())
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-14 - 300, 14)
	right.custom_minimum_size = Vector2(300, 0)
	root.add_child(right)
	info_lbl.bbcode_enabled = true
	info_lbl.fit_content = true
	info_lbl.scroll_active = false
	info_lbl.custom_minimum_size = Vector2(276, 0)
	info_lbl.add_theme_font_override("bold_font", load("res://fonts/NanumGothic-Bold.ttf"))
	right.add_child(info_lbl)

	# 아래: 조작법
	var help := Label.new()
	help.text = "드래그: 회전   휠: 확대/축소 (가까이 가면 비스듬한 시점)   클릭: 타일 고정   방향키: 이동   Q/E 또는 휠 버튼 드래그: 시점 돌리기   R: 북쪽 정렬\n고정한 타일에 시험: 1 벌목  2 배수  3 경작지  4 도로  5 정착지 구역  T 10턴 진행"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color("9f906c"))
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(16, -46)
	root.add_child(help)
	_update_info()


func _lbl(t: String, w: float = 0.0) -> Label:
	var l := Label.new()
	l.text = t
	if w > 0.0:
		l.custom_minimum_size = Vector2(w, 0)
	return l


func _row(label: String, ctrl: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_child(_lbl(label, 70))
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ctrl)
	return r


func _setup_slider(parent: Control, s: HSlider, label: String, mn: float, mx: float, st: float, v: float, fmt: Callable) -> void:
	var r := HBoxContainer.new()
	r.add_child(_lbl(label, 70))
	s.min_value = mn
	s.max_value = mx
	s.step = st
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(s)
	var val := _lbl(fmt.call(v), 62)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x): val.text = fmt.call(x))
	r.add_child(val)
	parent.add_child(r)


func _on_mode(idx: int) -> void:
	view.mode = idx
	view.wind_mi.visible = wind_chk.button_pressed or idx == PlanetView.Mode.WIND
	if current_level >= 0:
		view.recolor()
	_update_legend()


func _update_legend() -> void:
	for c in legend_box.get_children():
		c.queue_free()
	var items: Array = []
	match view.mode:
		PlanetView.Mode.BIOME:
			var counts: PackedInt32Array = gen.stats.get("counts", PackedInt32Array())
			for b in WorldGen.BIOME_NAMES.size():
				if counts.size() > b and counts[b] == 0:
					continue
				items.append([WorldGen.BIOME_COLORS[b], WorldGen.BIOME_NAMES[b]])
			items.append([WorldGen.BIOME_COLORS[WorldGen.B.GRASSLAND].lerp(WorldGen.ROCK_COLOR, 0.5), "산 (기복)"])
			items.append([WorldGen.SNOWCAP_COLOR, "눈 덮인 산"])
		PlanetView.Mode.ELEVATION:
			for h in [-4000, 0, 500, 1500, 3000, 5000]:
				items.append([PlanetView.elevation_color(h), "%s m" % _num(h)])
		PlanetView.Mode.TEMPERATURE:
			for t in [-25, -10, 0, 10, 20, 30]:
				items.append([PlanetView.temp_color(t), "%d °C" % t])
		PlanetView.Mode.PRECIP:
			for p in [100, 300, 700, 1400, 2400, 3500]:
				items.append([PlanetView.precip_color(p), "%s mm/년" % _num(p)])
		PlanetView.Mode.PLATES:
			items = [[Color("d1392b"), "수렴 경계 (산맥, 해구)"], [Color("37c6d8"), "발산 경계 (열곡, 해령)"],
				[Color("777777"), "어두운 판 = 해양 지각 성향"]]
		PlanetView.Mode.WIND:
			items = [[Color("3c5a8a"), "저기압대 (적도, 위도 60°)"], [Color("c2a25c"), "고기압대 (위도 30°, 극)"],
				[Color("ffd36b"), "화살표 = 지표 바람 (코리올리로 꺾임)"]]
		PlanetView.Mode.VEG:
			for v in range(1, TileLayers.VEG_NAMES.size()):
				items.append([TileLayers.VEG_COLORS[v], TileLayers.VEG_NAMES[v]])
			items.append([Color("d9a13b"), "시설물"])
			items.append([TileLayers.VEG_COLORS[TileLayers.Veg.GRASS].lerp(Color("c46a3a"), 0.6), "도로"])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	legend_box.add_child(grid)
	for it in items:
		var h := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = it[0]
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		var l := _lbl(it[1])
		l.add_theme_font_size_override("font_size", 12)
		h.add_child(l)
		grid.add_child(h)
	if view.mode == PlanetView.Mode.PLATES or view.mode == PlanetView.Mode.WIND:
		grid.columns = 1


func _num(v: float) -> String:
	var s := str(int(absf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


# ---------------------------------------------------------------- 생성

func _regenerate() -> void:
	if busy:
		return
	busy = true
	status_lbl.text = "세계를 만드는 중..."
	await get_tree().process_frame
	await get_tree().process_frame
	var t0: int = Time.get_ticks_msec()
	var lvl: int = LEVELS[size_opt.selected]
	if lvl != current_level:
		hs = HexSphere.new()
		hs.build(lvl)
		view.hs = hs
	var t1: int = Time.get_ticks_msec()
	gen = WorldGen.new()
	var s: String = seed_edit.text.strip_edges()
	gen.seed_value = int(s) if s.is_valid_int() else hash(s)
	gen.land_ratio = land_slider.value
	gen.plate_count = int(plates_slider.value)
	gen.temp_offset = temp_slider.value
	gen.moisture_mult = moist_slider.value
	gen.river_amount = river_slider.value
	gen.generate(hs)
	var t2: int = Time.get_ticks_msec()
	view.gen = gen
	view.exaggeration = exag_slider.value
	current_level = lvl
	view.rebuild()
	var t3: int = Time.get_ticks_msec()
	hover = -1
	selected = -1
	_turns = 0
	status_lbl.text = "완성: 격자 %.1f초, 생성 %.1f초, 그리기 %.1f초" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0]
	print(status_lbl.text)
	var st: Dictionary = gen.stats
	stats_lbl.text = "타일 %s칸 중 육지 %d%%, 강 %s칸, 호수 %s칸, 습지 %s칸, 판 %d개" % [
		_num(hs.count), int(100.0 * st["land"] / hs.count), _num(st["rivers"]), _num(st["lakes"]), _num(st["marsh"]), gen.plate_count]
	_update_legend()
	_update_info()
	busy = false


# ---------------------------------------------------------------- 카메라와 입력

## 멀리서는 행성 전체를 정면으로 보고, 가까이 갈수록 카메라가 지평선 쪽으로 기울어
## 문명 시리즈처럼 비스듬히 내려다보는 시점이 된다.
func _update_camera() -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	var h: float = dist - 1.0
	var tilt: float = deg_to_rad(58.0) * (1.0 - smoothstep(0.06, 0.8, h))
	var out: Vector3 = pivot.basis.z.normalized()
	var north: Vector3 = pivot.basis.y.normalized()
	var east: Vector3 = pivot.basis.x.normalized()
	# 방위각만큼 돌린 '화면 위쪽' 방향. 카메라는 그 반대편에서 바라본다.
	var upv: Vector3 = (north * cos(heading) + east * sin(heading)).normalized()
	var target: Vector3 = out
	var cam_pos: Vector3 = target + out * (h * cos(tilt)) - upv * (h * sin(tilt))
	var up: Vector3 = (upv * cos(tilt) + out * sin(tilt)).normalized()
	cam.look_at_from_position(cam_pos, target, up)
	sun.rotation = Vector3(deg_to_rad(-20) + pitch * 0.5, yaw - deg_to_rad(35), 0)


func _process(delta: float) -> void:
	var rot := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down"))
	if rot != Vector2.ZERO:
		_pan(Vector2(-rot.x, rot.y) * delta * 1.2 * (dist - 1.0) / 2.0)
	var spin: float = 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		spin -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		spin += 1.0
	if spin != 0.0:
		heading = wrapf(heading + spin * delta * 1.6, -PI, PI)
	if absf(dist - dist_target) > 1e-4 or rot != Vector2.ZERO or spin != 0.0:
		dist = lerpf(dist, dist_target, minf(1.0, delta * 10.0))
		_update_camera()


## 화면 기준 이동량을 (방위각을 반영해) 경도/위도 회전으로 바꾼다.
func _pan(d: Vector2) -> void:
	var c: float = cos(heading)
	var sn: float = sin(heading)
	yaw += -d.x * c + d.y * sn
	pitch = clampf(pitch - (d.x * sn + d.y * c), -1.5, 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				dragging = true
				_drag_moved = 0.0
			else:
				dragging = false
				if mb.button_index == MOUSE_BUTTON_LEFT and _drag_moved < 4.0:
					selected = -1 if selected == hover else hover
					_update_info()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist_target = clampf(dist_target - (dist_target - 1.0) * 0.15, 1.025, 8.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist_target = clampf(dist_target + (dist_target - 1.0) * 0.15, 1.025, 8.0)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			heading = wrapf(heading + mm.relative.x * 0.006, -PI, PI)
			_update_camera()
		elif dragging:
			_drag_moved += mm.relative.length()
			var k: float = 0.005 * (dist - 1.0) / 2.0
			_pan(mm.relative * k)
			_update_camera()
		else:
			_pick(mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).keycode
		if kc == KEY_R:
			pitch = -0.35
			heading = 0.0
			_update_camera()
		elif kc in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_T]:
			_layer_action(kc)


## 타일 레이어 규칙을 손으로 시험해 보는 단축키. 고정한 타일(클릭)에 적용한다.
func _layer_action(kc: int) -> void:
	if current_level < 0 or busy:
		return
	var i: int = selected
	var msg: String = ""
	if kc == KEY_T:
		var used := PackedByteArray()
		used.resize(gen.n)
		for _t in 10:
			TileLayers.advance_turn(gen, used)
		for k in gen.n:
			gen.refresh_biome(k)
		_turns += 10
		msg = "10턴 진행 (모든 시설을 쓰지 않은 것으로 처리). 지금까지 %d턴" % _turns
	elif i < 0:
		msg = "먼저 타일을 클릭해서 고정하세요"
	else:
		match kc:
			KEY_1:
				msg = "벌목했습니다" if TileLayers.clear_forest(gen, i) > 0 else "숲이 아니라 벌목할 수 없습니다"
			KEY_2:
				msg = "배수했습니다 (습지 -> 초지)" if TileLayers.drain(gen, i) else "습지가 아니라 배수할 수 없습니다"
			KEY_3, KEY_5:
				var s: int = TileLayers.Struct.FARM if kc == KEY_3 else TileLayers.Struct.DISTRICT
				var why: String = TileLayers.build_block_reason(gen, i, s)
				if why == "":
					TileLayers.build(gen, i, s)
					msg = "%s을(를) 지었습니다" % TileLayers.STRUCT_NAMES[s]
				else:
					msg = "%s 불가: %s" % [TileLayers.STRUCT_NAMES[s], why]
			KEY_4:
				var why_r: String = TileLayers.road_block_reason(gen, i)
				if why_r == "":
					TileLayers.build_road(gen, i)
					msg = "도로를 냈습니다"
				else:
					msg = "도로 불가: " + why_r
		gen.refresh_biome(i)
	status_lbl.text = msg
	view.recolor()
	_update_info()


var _turns: int = 0


## 스크린샷 점검용 (--demo): 고정한 타일에 정착지 구역을 두고, 둘레에 도로와 경작지를 깐다.
func _demo_town() -> void:
	var i: int = selected
	if i < 0:
		# 온대 평지에서 둘레가 모두 땅인 칸을 고르고 카메라를 그쪽으로 돌린다
		for k in gen.n:
			if gen.base[k] != TileLayers.Base.LAND or gen.relief[k] != 0 or gen.temp_band[k] != TileLayers.TempBand.TEMPERATE:
				continue
			var ok := true
			for q in range(hs.nb_offsets[k], hs.nb_offsets[k + 1]):
				var j: int = hs.nb_list[q]
				if gen.base[j] != TileLayers.Base.LAND or gen.veg[j] == TileLayers.Veg.WETLAND:
					ok = false
			if ok and gen.veg[k] == TileLayers.Veg.FOREST:
				i = k
				break
		if i < 0:
			return
		selected = i
		var d: Vector3 = hs.centers[i]
		pitch = -asin(d.y)
		yaw = atan2(d.x, d.z)
	TileLayers.clear_forest(gen, i)
	TileLayers.drain(gen, i)
	TileLayers.build(gen, i, TileLayers.Struct.DISTRICT)
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	for k in deg:
		var j: int = hs.nb_list[off + k]
		if k % 3 == 0:
			# 도로를 바깥으로 두 칸 잇는다
			TileLayers.build_road(gen, j)
			var o2: int = hs.nb_offsets[j]
			for q in hs.degree(j):
				var j2: int = hs.nb_list[o2 + q]
				if j2 != i and hs.nb_list.slice(off, off + deg).find(j2) < 0:
					TileLayers.build_road(gen, j2)
					break
		elif k % 3 == 1:
			TileLayers.build(gen, j, TileLayers.Struct.FARM)
	for k in gen.n:
		gen.refresh_biome(k)
	view.recolor()


var _drag_moved: float = 0.0


func _pick(mp: Vector2) -> void:
	if current_level < 0:
		return
	var o: Vector3 = cam.project_ray_origin(mp)
	var d: Vector3 = cam.project_ray_normal(mp)
	# 반지름 1.0 구와 교차
	var b: float = o.dot(d)
	var c: float = o.dot(o) - 1.0
	var disc: float = b * b - c
	var t: int = -1
	if disc >= 0.0:
		var s: float = -b - sqrt(disc)
		var p: Vector3 = (o + d * s).normalized()
		t = hs.find_tile(p, maxi(hover, 0))
	if t != hover:
		hover = t
		view.set_hover(selected if selected >= 0 else hover)
		if selected < 0:
			_update_info()


func _update_info() -> void:
	var i: int = selected if selected >= 0 else hover
	if current_level < 0 or i < 0:
		info_lbl.text = "[color=#e8c872][font_size=18]타일 정보[/font_size][/color]\n행성 위에 마우스를 올리면 그 칸의 지형, 기후, 물, 타일 레이어 정보를 보여 줍니다."
		return
	view.set_hover(i)
	var lat: float = rad_to_deg(gen.lat_of(i))
	var lon: float = rad_to_deg(gen.lon_of(i))
	var name_: String = WorldGen.BIOME_NAMES[gen.biome[i]]
	var hm: float = gen.height_m(i)
	var w: Vector3 = gen.wind[i]
	var en: Array = WorldGen.east_north(gen.hs.centers[i])
	var we: float = w.dot(en[0])
	var wn: float = w.dot(en[1])
	var wind_txt := "고요"
	if w.length() > 0.05:
		# 바람 이름은 불어오는 방향
		var bearing: float = fposmod(rad_to_deg(atan2(-we, -wn)), 360.0)
		wind_txt = "%s풍, 세기 %d%%" % [COMPASS[int(round(bearing / 45.0)) % 8], int(w.length() * 100)]
	var water: String = ""
	if gen.is_lake[i] == 1:
		water = "호수"
	elif gen.is_river[i] == 1:
		var sides: int = 0
		for k in hs.degree(i):
			if gen.river_mask[i] & (1 << k):
				sides += 1
		water = "강변 (변 %d개에 강)" % sides
	elif gen.elevation[i] >= 0.0:
		water = "없음"
	var lines: Array = []
	lines.append("[color=#e8c872][font_size=18]%s[/font_size][/color]%s" % [name_, "  [color=#9f906c](고정됨)[/color]" if selected >= 0 else ""])
	lines.append("[color=#9f906c]위도 %.1f°%s, 경도 %.1f°%s, %s각형 칸[/color]" % [absf(lat), "N" if lat >= 0 else "S", absf(lon), "E" if lon >= 0 else "W", "육" if hs.degree(i) == 6 else "오"])
	lines.append("")
	if gen.elevation[i] >= 0.0 and gen.is_lake[i] == 0:
		lines.append("[b]고도[/b]  %s m, %s" % [_num(hm), WorldGen.RELIEF_NAMES[gen.relief[i]]])
	else:
		lines.append("[b]수심[/b]  %s m" % _num(absf(hm)))
	lines.append("[b]연평균 기온[/b]  %.1f °C" % gen.temperature[i])
	lines.append("[b]연 강수량[/b]  %s mm" % _num(gen.precip[i]))
	lines.append("[b]지표 바람[/b]  %s" % wind_txt)
	if water != "":
		lines.append("[b]물[/b]  %s" % water)
	lines.append("")
	lines.append("[color=#e8c872]타일 레이어[/color]")
	lines.append("[b]1층 지형·기후[/b]  %s" % TileLayers.terrain_text(gen, i))
	if gen.base[i] == TileLayers.Base.LAND or gen.veg[i] != TileLayers.Veg.NONE:
		var vtxt: String = TileLayers.VEG_NAMES[gen.veg[i]]
		if gen.potential_veg[i] != gen.veg[i]:
			vtxt += " [color=#9f906c](자연 상태: %s)[/color]" % TileLayers.VEG_NAMES[gen.potential_veg[i]]
		lines.append("[b]2층 식생[/b]  %s" % vtxt)
	if gen.base[i] == TileLayers.Base.LAND:
		lines.append("[b]3층 시설물[/b]  %s" % TileLayers.structure_text(gen, i))
		var y: Vector3i = TileLayers.yields(gen, i)
		lines.append("[b]산출[/b]  식량 %d · 생산 %d · 교역 %d" % [y.x, y.y, y.z])
	lines.append("")
	var pid: int = gen.plate[i]
	var btxt := ""
	if gen.boundary[i] > 0.05:
		btxt = ", 수렴 경계"
	elif gen.boundary[i] < -0.05:
		btxt = ", 발산 경계"
	lines.append("[b]판[/b]  %d번 (%s 지각%s)" % [pid + 1, "해양" if gen.plate_oceanic[pid] == 1 else "대륙", btxt])
	info_lbl.text = "\n".join(lines)
