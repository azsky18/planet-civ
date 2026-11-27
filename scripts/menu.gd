extends Control
## 임시 시작 화면: 게임 시작 / 맵 테스트 / 종료

const BUILD_SCRIPT := preload("res://scripts/main.gd")


func _ready() -> void:
	# 스크린샷 점검용: --game 이면 게임, 다른 -- 인자가 있으면 예전처럼 맵 테스트로 바로 간다
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--game"):
		_go.call_deferred("res://game.tscn")
		return
	if args.size() > 0 and not args.has("--menu"):
		_go.call_deferred("res://map_test.tscn")
		return
	_build()
	var shot: String = ""
	for a in args:
		if a.begins_with("--shot="):
			shot = a.substr(7)
	if shot != "":
		for _f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _go(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _build() -> void:
	var font_body: Font = load("res://fonts/NanumGothic-Regular.ttf")
	var font_title: Font = load("res://fonts/NanumMyeongjo-ExtraBold.ttf")
	var bg := ColorRect.new()
	bg.color = Color("0b0f17")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := ColorRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 p = UV - vec2(0.5, 0.62);
	p.x *= 1.78;
	float d = length(p);
	float planet = smoothstep(0.30, 0.295, d);
	float rim = smoothstep(0.36, 0.30, d) * (1.0 - planet);
	vec3 col = mix(vec3(0.05, 0.08, 0.13), vec3(0.13, 0.22, 0.33), planet * (0.6 + 0.4 * (0.5 - p.y)));
	col += vec3(0.25, 0.45, 0.7) * rim * 0.35;
	COLOR = vec4(col, 1.0);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	glow.material = sm
	add_child(glow)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(360, 0)
	box.position = Vector2(-180, -210)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := Label.new()
	title.text = "행성 문명"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font_title)
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color("c9a75a"))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "수렵채집 시대 시제품"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", font_body)
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color("9a917e"))
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	box.add_child(gap)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.075, 0.085, 0.10, 0.82)
	btn.border_color = Color(0.79, 0.65, 0.35, 0.45)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(2)
	btn.set_content_margin_all(11)
	var btn_h := btn.duplicate() as StyleBoxFlat
	btn_h.bg_color = Color(0.13, 0.145, 0.165, 0.92)
	btn_h.border_color = Color("c9a75a")
	var items := [["게임 시작", "res://game.tscn"], ["맵 테스트", "res://map_test.tscn"], ["종료", ""]]
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.add_theme_font_override("font", font_body)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_stylebox_override("normal", btn)
		b.add_theme_stylebox_override("hover", btn_h)
		b.add_theme_stylebox_override("pressed", btn_h)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color("e4dccb"))
		b.add_theme_color_override("font_hover_color", Color("fff6e0"))
		b.focus_mode = Control.FOCUS_NONE
		var path: String = it[1]
		if path == "":
			b.pressed.connect(func(): get_tree().quit())
		else:
			b.pressed.connect(func(): _go(path))
		box.add_child(b)

	var build := Label.new()
	build.text = "빌드: " + BUILD_SCRIPT.BUILD
	build.add_theme_font_override("font", font_body)
	build.add_theme_font_size_override("font_size", 12)
	build.add_theme_color_override("font_color", Color("6f6a60"))
	build.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	build.position = Vector2(16, -30)
	add_child(build)
