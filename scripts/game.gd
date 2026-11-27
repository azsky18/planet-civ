extends "res://scripts/main.gd"
## 게임: 채집 → 인구 상승 → 사냥 → 인구 상승 순환을 직접 해 보는 화면.
## 행성, 카메라, 타일 정보는 맵 테스트(main.gd)의 것을 그대로 쓰고, 그 위에 유닛과 야영지를 얹는다.

## class_name 대신 preload: 에디터가 전역 클래스 목록을 아직 갱신하지 않은 PC 에서도 바로 실행되도록
const GameRules := preload("res://scripts/game_rules.gd")

var rules: GameRules
var marks := Node3D.new()
var sel_mi := MeshInstance3D.new()
var path_mi := MeshInstance3D.new()
var sel_unit: GameRules.Unit = null
var sel_camp: GameRules.Camp = null

var _unit_nodes := {}            # unit id -> Node3D
var _res_nodes := {}             # tile -> [Node3D, Label3D, 마지막 양]
var _tag_nodes := {}             # 칸 -> Label3D (야영지·부족민 이름표)
var _mats := {}
var _token_mesh: Mesh
var _animal_mesh: Mesh
var _res_mesh: Mesh
var _camp_count_drawn: int = 0

# HUD
var turn_lbl := Label.new()
var pop_lbl := Label.new()
var log_lbl := RichTextLabel.new()
var sel_title := Label.new()
var sel_body := RichTextLabel.new()
var sel_buttons := HBoxContainer.new()
var msg_lbl := Label.new()
var over_lbl := Label.new()


func _ready() -> void:
	font_body = load("res://fonts/NanumGothic-Regular.ttf")
	font_title = load("res://fonts/NanumMyeongjo-ExtraBold.ttf")
	_setup_scene()
	add_child(marks)
	_setup_rings()
	_setup_ui()
	var seed_v: int = randi() % 1000000
	var shot: String = ""
	var script_steps: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		elif a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--dist="):
			dist = float(a.substr(7))
			dist_target = dist
		elif a.begins_with("--play="):
			script_steps = Array(a.substr(7).split(","))
	await get_tree().process_frame
	await _new_game(seed_v)
	for s in script_steps:
		_scripted(s)
	_update_camera()
	if shot != "":
		for _f in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


## 스크린샷 점검용 동작 (--play=camp,next,gather,end,hunt ...)
func _scripted(s: String) -> void:
	match s:
		"camp":
			_act_camp()
		"end":
			_end_turn()
		"next":
			_select_next()
		"gather":
			_act_gather()
		"release":
			if not rules.camps.is_empty():
				_select_camp(rules.camps[0])
				_act_release()
		"food":
			# 가장 가까운 땅 위 식량 칸으로 보낸다
			if sel_unit != null:
				var near: Dictionary = rules.within(sel_unit.tile, 3)
				var best: int = -1
				for j in near:
					if rules.is_land(j) and rules.res_kind[j] != GameRules.Res.NONE and near[j] > 0:
						if best < 0 or near[j] < near[best]:
							best = j
				if best >= 0:
					_order(best)
		"hunt":
			if sel_unit != null:
				var near2: Dictionary = rules.within(sel_unit.tile, 5)
				for j in near2:
					var a: GameRules.Unit = rules.animal_at(j)
					if a != null and a.side() == GameRules.Side.PREY:
						_order(j)
						break


func _new_game(seed_v: int) -> void:
	busy = true
	msg_lbl.text = "세계를 만드는 중..."
	await get_tree().process_frame
	hs = HexSphere.new()
	hs.build(6)
	view.hs = hs
	gen = WorldGen.new()
	gen.seed_value = seed_v
	gen.generate(hs)
	view.gen = gen
	current_level = 6
	rules = GameRules.new()
	rules.setup(gen, seed_v)
	view.rebuild()
	view.recolor()
	_make_meshes()
	_sync_marks(true)
	_look_at_tile(rules.start_tile)
	dist = 1.16
	dist_target = 1.16

	_update_camera()
	busy = false
	msg_lbl.text = "시드 %d" % seed_v
	_select_next()
	_refresh_hud()


# ---------------------------------------------------------------- 화면 구성

func _setup_rings() -> void:
	for mi in [sel_mi, path_mi]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("ffe27a") if mi == sel_mi else Color(1, 1, 1, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
		mi.material_override = m
		add_child(mi)


func _make_meshes() -> void:
	var s: float = hs.spacing
	var body := CylinderMesh.new()
	body.top_radius = s * 0.07
	body.bottom_radius = s * 0.16
	body.height = s * 0.34
	body.radial_segments = 12
	_token_mesh = body
	_animal_mesh = _quadruped(s)
	var disc := CylinderMesh.new()
	disc.top_radius = s * 0.1
	disc.bottom_radius = s * 0.12
	disc.height = s * 0.04
	disc.radial_segments = 6
	_res_mesh = disc


## 몸통, 머리, 다리 네 개로 된 단순한 네발짐승 모양
func _quadruped(s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [
		[Vector3(0, s * 0.02, 0), Vector3(s * 0.36, s * 0.15, s * 0.16)],
		[Vector3(s * 0.22, s * 0.08, 0), Vector3(s * 0.13, s * 0.12, s * 0.12)],
		[Vector3(s * 0.13, -s * 0.09, s * 0.05), Vector3(s * 0.05, s * 0.12, s * 0.05)],
		[Vector3(s * 0.13, -s * 0.09, -s * 0.05), Vector3(s * 0.05, s * 0.12, s * 0.05)],
		[Vector3(-s * 0.13, -s * 0.09, s * 0.05), Vector3(s * 0.05, s * 0.12, s * 0.05)],
		[Vector3(-s * 0.13, -s * 0.09, -s * 0.05), Vector3(s * 0.05, s * 0.12, s * 0.05)],
	]
	for p in parts:
		var b := BoxMesh.new()
		b.size = p[1]
		st.append_from(b, 0, Transform3D(Basis(), p[0]))
	return st.commit()


func _mat(c: Color) -> StandardMaterial3D:
	var key: String = c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.7
		_mats[key] = m
	return _mats[key]


func _ground(tile: int) -> Vector3:
	var c: Vector3 = hs.centers[tile]
	var p: Vector3 = view.surface_point(c, tile)
	var r: float = maxf(p.length(), 1.0)
	if gen.is_lake[tile] == 1:
		r = maxf(r, view.lake_level(tile))
	return c * r


func _frame(pos: Vector3) -> Transform3D:
	var up: Vector3 = pos.normalized()
	var ref: Vector3 = Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT
	var x: Vector3 = ref.cross(up).normalized()
	var z: Vector3 = x.cross(up).normalized()
	return Transform3D(Basis(x, up, z), pos)


func _label(text: String, col: Color, size: int, range_end: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font_body
	l.font_size = size
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.double_sided = true
	l.visibility_range_end = range_end
	return l


func _unit_color(u: GameRules.Unit) -> Color:
	match u.side():
		GameRules.Side.PLAYER:
			return Color("3d7be0")
		GameRules.Side.PREY:
			return Color("8fbf4a")
	return Color("d2452f")


func _unit_text(u: GameRules.Unit) -> String:
	var t: String = u.name()
	if u.hp < int(u.info()["hp"]):
		t += " ♥%d" % u.hp
	if u.carry > 0:
		t += " 식량 %d" % u.carry
	return t


## 규칙 상태에 맞춰 표식을 만들거나 옮기거나 지운다.
func _sync_marks(full: bool = false) -> void:
	var alive := {}
	var stack := {}
	for u in rules.units:
		alive[u.id] = true
		var node: Node3D = _unit_nodes.get(u.id)
		if node == null:
			node = Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = _token_mesh if u.side() == GameRules.Side.PLAYER else _animal_mesh
			mi.material_override = _mat(_unit_color(u))
			mi.position = Vector3(0, hs.spacing * 0.12, 0)
			mi.visibility_range_end = 1.2
			mi.name = "body"
			node.add_child(mi)
			if u.side() == GameRules.Side.PLAYER:
				var head := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = hs.spacing * 0.08
				sp.height = hs.spacing * 0.16
				head.mesh = sp
				head.material_override = _mat(Color("f0d6a8"))
				head.position = Vector3(0, hs.spacing * 0.33, 0)
				head.visibility_range_end = 1.2
				node.add_child(head)
			if u.side() != GameRules.Side.PLAYER:
				var col: Color = Color("d8f0b0") if u.side() == GameRules.Side.PREY else Color("ffb3a6")
				var lbl := _label("", col, 24, 0.32)
				lbl.position = Vector3(0, hs.spacing * 0.4, 0)
				lbl.name = "label"
				node.add_child(lbl)
			marks.add_child(node)
			_unit_nodes[u.id] = node
		var k: int = stack.get(u.tile, 0)
		stack[u.tile] = k + 1
		var tf: Transform3D = _frame(_ground(u.tile))
		if k > 0:
			var ang: float = k * 2.1
			tf.origin += (tf.basis.x * cos(ang) + tf.basis.z * sin(ang)) * hs.spacing * 0.3
		node.transform = tf
		if u.side() != GameRules.Side.PLAYER:
			(node.get_node("label") as Label3D).text = _unit_text(u)
	for id in _unit_nodes.keys():
		if not alive.has(id):
			_unit_nodes[id].queue_free()
			_unit_nodes.erase(id)
	# 채집 식량
	for i in gen.n:
		var r: int = rules.res_kind[i]
		if r == GameRules.Res.NONE:
			continue
		var amt: int = rules.res_amt[i]
		var entry: Array = _res_nodes.get(i, [])
		if entry.is_empty():
			var node := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = _res_mesh
			mi.material_override = _mat(GameRules.RES_COLORS[r])
			mi.visibility_range_end = 0.9
			node.add_child(mi)
			var lbl := _label("", GameRules.RES_COLORS[r].lightened(0.3), 22, 0.3)
			lbl.position = Vector3(0, hs.spacing * 0.12, 0)
			node.add_child(lbl)
			var tf: Transform3D = _frame(_ground(i))
			tf.origin += (tf.basis.x * 0.3 - tf.basis.z * 0.3) * hs.spacing
			node.transform = tf
			marks.add_child(node)
			entry = [node, lbl, mi, -1]
			_res_nodes[i] = entry
		if entry[3] != amt or full:
			entry[3] = amt
			(entry[1] as Label3D).text = "%s %d" % [GameRules.RES_SHORT[r], amt] if amt > 0 else "%s (고갈)" % GameRules.RES_SHORT[r]
			(entry[2] as MeshInstance3D).transparency = 0.0 if amt > 0 else 0.6
	# 야영지와 부족민이 있는 칸: 이름표 하나에 모아 쓴다 (겹치지 않게)
	var tags := {}
	for c in rules.camps:
		var dots: String = "●".repeat(c.pop) + "○".repeat(GameRules.CAMP_MAX_POP - c.pop)
		tags[c.tile] = ["%s %s  식량 %d/%d" % [c.name, dots, c.food, GameRules.growth_need(c.pop)]]
	for u in rules.player_units():
		if not tags.has(u.tile):
			tags[u.tile] = []
	for t in tags:
		var ps: Array = rules.players_at(t)
		if not ps.is_empty():
			var carry: int = 0
			var hurt: int = 0
			for u in ps:
				carry += u.carry
				hurt += int(u.info()["hp"]) - u.hp
			var line: String = "부족민" if ps.size() == 1 else "부족민 ×%d" % ps.size()
			if hurt > 0:
				line += " 부상"
			if carry > 0:
				line += " · 식량 %d" % carry
			tags[t].append(line)
		var r2: int = rules.res_kind[t]
		if r2 != GameRules.Res.NONE:
			tags[t].append("%s %d" % [GameRules.RES_SHORT[r2], rules.res_amt[t]])
			(_res_nodes[t][1] as Label3D).visible = false
	for t in _tag_nodes.keys():
		if not tags.has(t):
			_tag_nodes[t].queue_free()
			_tag_nodes.erase(t)
			if _res_nodes.has(t):
				(_res_nodes[t][1] as Label3D).visible = true
	for t in tags:
		var lbl: Label3D = _tag_nodes.get(t)
		if lbl == null:
			lbl = _label("", Color("ffe9a8"), 24, 1.0)
			# 칸 가운데에서 화면 아래쪽으로 늘어지게 (문명 시리즈의 도시 이름처럼 칸 아래에)
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			lbl.transform = _frame(_ground(t))
			lbl.position += lbl.transform.basis.y * hs.spacing * 0.05
			# 땅에 파묻히지 않게 깊이 검사를 끄고, 행성 뒤쪽은 _process 에서 숨긴다
			lbl.no_depth_test = true
			lbl.render_priority = 2
			lbl.outline_render_priority = 1
			marks.add_child(lbl)
			_tag_nodes[t] = lbl
		lbl.text = "\n".join(tags[t])
		lbl.modulate = Color("ffe9a8") if rules.camp_at(t) != null else Color("cfe0ff")
	if rules.camps.size() != _camp_count_drawn:
		_camp_count_drawn = rules.camps.size()
		view.recolor()
	_draw_selection()


func _process(delta: float) -> void:
	super._process(delta)
	var cp: Vector3 = cam.global_position
	for t in _tag_nodes:
		var l: Label3D = _tag_nodes[t]
		var p: Vector3 = l.position
		l.visible = (cp - p).dot(p.normalized()) > 0.0


func _ring(i: int, im: ImmediateMesh, lift: float) -> void:
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for k in deg + 1:
		var p: Vector3 = view.corner_pos(off + k % deg)
		p = p.normalized() * maxf(p.length(), 1.0)
		var cc: Vector3 = _ground(i)
		p = p.lerp(cc, 0.12)
		im.surface_add_vertex(p + p.normalized() * lift)
	im.surface_end()


func _draw_selection() -> void:
	var t: int = -1
	if sel_unit != null and rules.units.has(sel_unit):
		t = sel_unit.tile
	elif sel_camp != null:
		t = sel_camp.tile
	if t < 0:
		sel_mi.mesh = null
		path_mi.mesh = null
		return
	var im := ImmediateMesh.new()
	_ring(t, im, 0.002)
	_ring(t, im, 0.0026)
	sel_mi.mesh = im
	if sel_unit != null and not sel_unit.path.is_empty():
		var pm := ImmediateMesh.new()
		pm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		pm.surface_add_vertex(_ground(sel_unit.tile) * 1.002)
		for j in sel_unit.path:
			pm.surface_add_vertex(_ground(j) * 1.002)
		pm.surface_end()
		path_mi.mesh = pm
	else:
		path_mi.mesh = null


# ---------------------------------------------------------------- HUD

func _setup_ui() -> void:
	var theme := Theme.new()
	theme.default_font = font_body
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", Color("efe3c4"))
	theme.set_color("default_color", "RichTextLabel", Color("efe3c4"))
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("5a3f22")
	btn.border_color = Color("c9a24a")
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(3)
	btn.set_content_margin_all(6)
	var btn_h := btn.duplicate() as StyleBoxFlat
	btn_h.bg_color = Color("74532d")
	var btn_d := btn.duplicate() as StyleBoxFlat
	btn_d.bg_color = Color("3a2c1e")
	btn_d.border_color = Color("6a5530")
	theme.set_stylebox("normal", "Button", btn)
	theme.set_stylebox("hover", "Button", btn_h)
	theme.set_stylebox("pressed", "Button", btn_h)
	theme.set_stylebox("disabled", "Button", btn_d)
	theme.set_color("font_color", "Button", Color("f5e9c8"))
	theme.set_color("font_hover_color", "Button", Color("ffffff"))
	theme.set_color("font_disabled_color", "Button", Color("8a7a5c"))

	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	layer.add_child(root)

	# 왼쪽 위: 턴과 부족 현황, 사건 기록
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _panel_style())
	left.position = Vector2(14, 14)
	left.custom_minimum_size = Vector2(330, 0)
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	turn_lbl.add_theme_font_override("font", font_title)
	turn_lbl.add_theme_font_size_override("font_size", 22)
	turn_lbl.add_theme_color_override("font_color", Color("e8c872"))
	lv.add_child(turn_lbl)
	pop_lbl.add_theme_font_size_override("font_size", 13)
	lv.add_child(pop_lbl)
	var row := HBoxContainer.new()
	row.add_child(_button("턴 종료 (Enter)", _end_turn))
	row.add_child(_button("다음 부족민 (N)", _select_next))
	row.add_child(_button("처음 화면 (Esc)", _to_menu))
	lv.add_child(row)
	lv.add_child(HSeparator.new())
	log_lbl.bbcode_enabled = true
	log_lbl.fit_content = true
	log_lbl.scroll_active = false
	log_lbl.custom_minimum_size = Vector2(306, 0)
	log_lbl.add_theme_font_size_override("normal_font_size", 12)
	lv.add_child(log_lbl)
	var sub := Label.new()
	sub.text = "빌드: " + BUILD
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color("9f906c"))
	lv.add_child(sub)

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

	# 아래 가운데: 고른 부족민 / 야영지
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _panel_style())
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.custom_minimum_size = Vector2(560, 0)
	bottom.offset_left = -280
	bottom.offset_right = 280
	bottom.offset_top = -60
	bottom.offset_bottom = -60
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bottom.add_child(bv)
	sel_title.add_theme_font_override("font", font_title)
	sel_title.add_theme_font_size_override("font_size", 18)
	sel_title.add_theme_color_override("font_color", Color("e8c872"))
	bv.add_child(sel_title)
	sel_body.bbcode_enabled = true
	sel_body.fit_content = true
	sel_body.scroll_active = false
	sel_body.custom_minimum_size = Vector2(536, 0)
	bv.add_child(sel_body)
	bv.add_child(sel_buttons)
	msg_lbl.add_theme_font_size_override("font_size", 12)
	msg_lbl.add_theme_color_override("font_color", Color("ffd27a"))
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.custom_minimum_size = Vector2(536, 0)
	bv.add_child(msg_lbl)

	var help := Label.new()
	help.text = "왼쪽 클릭: 고르기   오른쪽 클릭: 이동 / 곁의 동물 공격   B 야영지 세우기  G 채집  J 합류  U 부족민 내보내기  N 다음  Space 쉬기  Enter 턴 종료\n드래그: 회전   휠: 확대/축소   Q/E: 시점 돌리기   C: 고른 곳으로   Esc: 메뉴"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color("cdbf9c"))
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.08, 0.06, 0.04, 0.78)
	hsb.set_content_margin_all(6)
	help.add_theme_stylebox_override("normal", hsb)
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -46
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(help)

	over_lbl.add_theme_font_override("font", font_title)
	over_lbl.add_theme_font_size_override("font_size", 40)
	over_lbl.add_theme_color_override("font_color", Color("e8c872"))
	over_lbl.set_anchors_preset(Control.PRESET_CENTER)
	over_lbl.position = Vector2(-200, -60)
	over_lbl.visible = false
	root.add_child(over_lbl)
	_update_info()


func _button(text: String, cb: Callable, enabled: bool = true, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _refresh_hud() -> void:
	if rules == null:
		return
	turn_lbl.text = "수렵채집 시대 · %d턴" % rules.turn
	var units: int = rules.player_units().size()
	var camp_pop: int = 0
	for c in rules.camps:
		camp_pop += c.pop
	pop_lbl.text = "부족 인구 %d명 = 야영지 %d곳 %d명 + 부족민 %d명" % [rules.population(), rules.camps.size(), camp_pop, units]
	var lines: Array = []
	for e in rules.events.slice(-9):
		lines.append(e)
	log_lbl.text = "[color=#c9b98f]" + "\n".join(lines) + "[/color]"
	over_lbl.visible = rules.game_over
	over_lbl.text = "부족이 모두 사라졌습니다"
	_refresh_selection()
	_update_info()


func _refresh_selection() -> void:
	for c in sel_buttons.get_children():
		c.queue_free()
	if sel_unit != null and not rules.units.has(sel_unit):
		sel_unit = null
	if sel_unit != null:
		var u: GameRules.Unit = sel_unit
		sel_title.text = "%s  (이동력 %d/%d)" % [u.name(), u.mp, u.info()["mp"]]
		var t: Array = []
		t.append("체력 %d/%d · 공격 %d · 방어 %d · 들고 있는 식량 %d/%d" % [u.hp, u.info()["hp"], u.info()["a"], u.info()["d"], u.carry, GameRules.CARRY_MAX])
		var gt: int = rules.gather_target(u)
		if gt >= 0:
			t.append("채집 가능: %s (남은 양 %d)" % [GameRules.RES_NAMES[rules.res_kind[gt]], rules.res_amt[gt]])
		if not u.path.is_empty():
			t.append("목적지까지 %d칸 남음 (턴마다 이어서 이동)" % u.path.size())
		sel_body.text = "\n".join(t)
		var why_c: String = rules.camp_block_reason(u)
		sel_buttons.add_child(_button("야영지 세우기 (B)", _act_camp, why_c == "", why_c))
		var why_g: String = rules.gather_block_reason(u)
		sel_buttons.add_child(_button("채집 (G)", _act_gather, why_g == "", why_g))
		if rules.camp_at(u.tile) != null:
			var why_j: String = rules.join_block_reason(u)
			sel_buttons.add_child(_button("야영지에 합류 (J)", _act_join, why_j == "", why_j))
		sel_buttons.add_child(_button("쉬기 (Space)", _act_rest, u.mp > 0))
	elif sel_camp != null:
		var c: GameRules.Camp = sel_camp
		sel_title.text = "%s  (인구 %d/%d)" % [c.name, c.pop, GameRules.CAMP_MAX_POP]
		var net: int = rules.camp_net(c)
		var t2: Array = []
		t2.append("식량 창고 %d/%d · 턴당 %+d (일하는 칸 %d곳, 모닥불 +%d, 먹는 양 -%d)" % [c.food, GameRules.growth_need(c.pop), net, rules.camp_worked(c).size(), GameRules.CAMP_BONUS, GameRules.FOOD_PER_POP * c.pop])
		if c.pop >= GameRules.CAMP_MAX_POP:
			t2.append("[color=#ffb37a]인구가 가득 찼습니다. 부족민을 내보내 사냥과 채집을 보내세요.[/color]")
		else:
			t2.append("부족민이 식량을 들고 들어오면 창고에 쌓이고, 창고가 차면 턴이 끝날 때 인구가 1 늡니다.")
		sel_body.text = "\n".join(t2)
		var why_r: String = rules.release_block_reason(c)
		sel_buttons.add_child(_button("부족민 내보내기 (U)", _act_release, why_r == "", why_r))
	else:
		sel_title.text = "고른 것 없음"
		sel_body.text = "부족민이나 야영지를 왼쪽 클릭으로 고르세요. N 을 누르면 아직 움직일 수 있는 부족민으로 갑니다."


# ---------------------------------------------------------------- 행동

func _say(m: String) -> void:
	msg_lbl.text = m


func _after_action() -> void:
	_sync_marks()
	_refresh_hud()


func _act_camp() -> void:
	if sel_unit == null:
		return
	var why: String = rules.camp_block_reason(sel_unit)
	if why != "":
		_say("야영지를 세울 수 없음: " + why)
		return
	var c: GameRules.Camp = rules.found_camp(sel_unit)
	sel_unit = null
	_select_camp(c)
	_say("%s 세웠습니다." % GameRules.josa(c.name, "을"))
	_after_action()


func _act_gather() -> void:
	if sel_unit == null:
		return
	var why: String = rules.gather_block_reason(sel_unit)
	if why != "":
		_say("채집할 수 없음: " + why)
		return
	var got: int = rules.gather(sel_unit)
	_say("식량 %d 채집했습니다." % got)
	_after_action()


func _act_join() -> void:
	if sel_unit == null:
		return
	var why: String = rules.join_block_reason(sel_unit)
	if why != "":
		_say("합류할 수 없음: " + why)
		return
	var c: GameRules.Camp = rules.camp_at(sel_unit.tile)
	rules.join_camp(sel_unit)
	sel_unit = null
	_select_camp(c)
	_after_action()


func _act_release() -> void:
	var c: GameRules.Camp = sel_camp
	if c == null and sel_unit != null:
		c = rules.camp_at(sel_unit.tile)
	if c == null:
		return
	var why: String = rules.release_block_reason(c)
	if why != "":
		_say("내보낼 수 없음: " + why)
		return
	var u: GameRules.Unit = rules.release_unit(c)
	sel_camp = null
	sel_unit = u
	_after_action()


func _act_rest() -> void:
	if sel_unit == null:
		return
	sel_unit.mp = 0
	sel_unit.path.clear()
	_select_next()


func _order(goal: int) -> void:
	if sel_unit == null or goal < 0:
		return
	var m: String = rules.order_move(sel_unit, goal)
	if m != "":
		_say(m)
	_after_action()


func _end_turn() -> void:
	if rules == null or busy or rules.game_over:
		return
	rules.end_turn()
	_say("")
	sel_camp = null
	sel_unit = null
	_sync_marks()
	_select_next()
	_refresh_hud()


func _select_camp(c: GameRules.Camp) -> void:
	sel_camp = c
	sel_unit = null
	_draw_selection()
	_refresh_hud()


## 아직 이동력이 남은 부족민을 차례로 고르고 카메라를 그쪽으로 돌린다.
func _select_next() -> void:
	if rules == null:
		return
	var list: Array = rules.player_units()
	if list.is_empty():
		sel_unit = null
		if not rules.camps.is_empty() and sel_camp == null:
			sel_camp = rules.camps[0]
		_draw_selection()
		_refresh_hud()
		return
	var start: int = list.find(sel_unit) + 1
	for k in list.size():
		var u: GameRules.Unit = list[(start + k) % list.size()]
		if u.mp > 0 and u.path.is_empty():
			sel_unit = u
			sel_camp = null
			_look_at_tile(u.tile)
			_draw_selection()
			_refresh_hud()
			return
	_say("모든 부족민이 이번 턴 행동을 마쳤습니다. Enter 로 턴을 마치세요.")
	_draw_selection()
	_refresh_hud()


func _look_at_tile(i: int) -> void:
	var d: Vector3 = hs.centers[i]
	pitch = -asin(d.y)
	yaw = atan2(d.x, d.z)
	# 비스듬한 시점에서도 칸이 화면 가운데쯤 오도록 살짝 남쪽으로
	_update_camera()


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func _on_left_click(t: int) -> void:
	if t < 0:
		return
	var ps: Array = rules.players_at(t)
	if not ps.is_empty():
		var idx: int = ps.find(sel_unit)
		sel_unit = ps[(idx + 1) % ps.size()]
		sel_camp = null
	elif rules.camp_at(t) != null:
		_select_camp(rules.camp_at(t))
		return
	else:
		sel_unit = null
		sel_camp = null
	_draw_selection()
	_refresh_hud()


# ---------------------------------------------------------------- 입력

func _unhandled_input(event: InputEvent) -> void:
	if busy or rules == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				dragging = true
				_drag_moved = 0.0
			else:
				dragging = false
				if _drag_moved < 4.0:
					if mb.button_index == MOUSE_BUTTON_LEFT:
						_on_left_click(hover)
					else:
						_order(hover)
			return
		super._unhandled_input(event)
	elif event is InputEventMouseMotion:
		super._unhandled_input(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_end_turn()
			KEY_N, KEY_TAB:
				_select_next()
			KEY_B:
				_act_camp()
			KEY_G:
				_act_gather()
			KEY_J:
				_act_join()
			KEY_U:
				_act_release()
			KEY_SPACE:
				_act_rest()
			KEY_C:
				if sel_unit != null:
					_look_at_tile(sel_unit.tile)
				elif sel_camp != null:
					_look_at_tile(sel_camp.tile)
			KEY_ESCAPE:
				_to_menu()
			KEY_R:
				super._unhandled_input(event)


func _pick(mp: Vector2) -> void:
	var before: int = hover
	super._pick(mp)
	if hover != before:
		_update_info()


func _update_info() -> void:
	super._update_info()
	if rules == null:
		return
	var i: int = hover
	if i < 0:
		return
	var lines: Array = []
	var a: GameRules.Unit = rules.animal_at(i)
	if a != null:
		var kind: String = "먹잇감" if a.side() == GameRules.Side.PREY else "포식자, 곁에 오면 덮침"
		lines.append("[color=#e8c872][font_size=17]%s[/font_size][/color]  [color=#9f906c](%s)[/color]" % [a.name(), kind])
		lines.append("체력 %d/%d · 공격 %d · 방어 %d (지형 보정 ×%.2f) · 고기 %d" % [a.hp, a.info()["hp"], a.info()["a"], a.info()["d"], rules.terrain_defense(i), a.info()["food"]])
		if sel_unit != null and rules.units.has(sel_unit):
			var odds: float = rules.attack_odds(sel_unit, a)
			var near: String = "" if rules.is_adjacent(sel_unit.tile, i) else " (곁으로 가야 공격 가능)"
			lines.append("[b]공격 승률[/b] %d%%%s" % [int(round(odds * 100.0)), near])
	var c: GameRules.Camp = rules.camp_at(i)
	if c != null:
		lines.append("[color=#e8c872][font_size=17]%s[/font_size][/color]  인구 %d/%d, 식량 %d/%d" % [c.name, c.pop, GameRules.CAMP_MAX_POP, c.food, GameRules.growth_need(c.pop)])
	var ps: Array = rules.players_at(i)
	if not ps.is_empty():
		lines.append("부족민 %d명" % ps.size())
	var r: int = rules.res_kind[i]
	if r != GameRules.Res.NONE:
		lines.append("[b]채집 식량[/b]  %s %d/%d" % [GameRules.RES_NAMES[r], rules.res_amt[i], GameRules.RES_MAX[r]])
	if lines.is_empty():
		return
	info_lbl.text = "\n".join(lines) + "\n\n" + info_lbl.text
