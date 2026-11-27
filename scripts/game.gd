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
var _camp_labels := {}           # 칸 -> Label3D (야영지 이름)
var _font_bold: Font
var _tag_nodes := {}             # 칸 -> Label3D (야영지·부족민 이름표)
var _mats := {}
var _labels: Array = []          # 깊이 검사를 끈 글자와 체력 막대 (뒤쪽 숨김 대상)
var _token_mesh: Mesh
var _animal_mesh: Mesh
var _res_mesh: Mesh
var _camp_sig: String = "[]"

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
	_font_bold = load("res://fonts/NanumGothic-Bold.ttf")
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
		"hurt":
			# 체력 막대 점검용
			if sel_unit != null:
				sel_unit.hp = maxi(sel_unit.hp - 1, 1)
				_after_action()
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


## 지도 위 글자: 문명 시리즈처럼 작고 차분하게. 얇은 어두운 외곽선만 두른다.
func _label(text: String, col: Color, size: int, range_end: float, font: Font = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font if font != null else font_body
	l.font_size = size
	l.outline_size = 8
	l.outline_modulate = Color(0.07, 0.06, 0.04, 0.95)
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.double_sided = true
	l.visibility_range_end = range_end
	# 강, 격자, 물, 다른 그림에 가려 글자가 끊기지 않게 깊이 검사를 끄고 맨 나중에 그린다.
	# 대신 행성 뒤쪽에 있는 글자는 _process 에서 숨긴다.
	l.no_depth_test = true
	l.render_priority = 20
	l.outline_render_priority = 19
	l.set_meta("on", true)
	_labels.append(l)
	return l


func _unit_color(u: GameRules.Unit) -> Color:
	match u.side():
		GameRules.Side.PLAYER:
			return Color("3d7be0")
		GameRules.Side.PREY:
			return Color("8fbf4a")
	return Color("d2452f")


var _hp_tex := {}
var _res_tex := {}

## 채집 식량 그림 (64px SVG). 밝은 원판 위에 그려 어느 바닥에서도 잘 보이게 한다.
const RES_SVG := {
	1: "<g stroke='#6b4a12' stroke-width='2'><path d='M32 58 L32 18' fill='none'/><g fill='#f0c23e'><ellipse cx='32' cy='14' rx='4' ry='7'/><ellipse cx='25' cy='22' rx='4' ry='7' transform='rotate(-30 25 22)'/><ellipse cx='39' cy='22' rx='4' ry='7' transform='rotate(30 39 22)'/><ellipse cx='25' cy='33' rx='4' ry='7' transform='rotate(-30 25 33)'/><ellipse cx='39' cy='33' rx='4' ry='7' transform='rotate(30 39 33)'/><ellipse cx='26' cy='44' rx='4' ry='6' transform='rotate(-30 26 44)'/><ellipse cx='38' cy='44' rx='4' ry='6' transform='rotate(30 38 44)'/></g></g>",
	2: "<g stroke='#2f5a1c' stroke-width='2' fill='none'><path d='M30 58 C30 40 30 26 40 14'/><path d='M30 58 C26 44 20 36 14 30'/><path d='M30 58 C34 46 42 40 50 38'/></g><g fill='#f7f3e0' stroke='#7a6a3a' stroke-width='1.5'><ellipse cx='42' cy='14' rx='3' ry='5'/><ellipse cx='38' cy='21' rx='3' ry='5'/><ellipse cx='45' cy='22' rx='3' ry='5'/><ellipse cx='14' cy='27' rx='3' ry='5'/><ellipse cx='19' cy='32' rx='3' ry='5'/><ellipse cx='50' cy='34' rx='3' ry='5'/><ellipse cx='45' cy='39' rx='3' ry='5'/></g>",
	3: "<path d='M32 10 C40 6 48 10 50 16 C42 18 36 16 32 10 Z' fill='#4f9a3a' stroke='#245018' stroke-width='2'/><path d='M32 10 L32 20' stroke='#5a3a1a' stroke-width='2'/><g fill='#b0305e' stroke='#5a1030' stroke-width='2'><circle cx='26' cy='28' r='8'/><circle cx='40' cy='28' r='8'/><circle cx='33' cy='40' r='8'/><circle cx='21' cy='42' r='7'/><circle cx='45' cy='42' r='7'/><circle cx='33' cy='53' r='6'/></g><g fill='#f2b6cf'><circle cx='23' cy='25' r='2'/><circle cx='37' cy='25' r='2'/><circle cx='30' cy='37' r='2'/></g>",
	4: "<path d='M8 32 C18 16 40 16 50 32 C40 48 18 48 8 32 Z' fill='#4aa3e0' stroke='#1c4f78' stroke-width='2.5'/><path d='M48 32 L60 20 L60 44 Z' fill='#4aa3e0' stroke='#1c4f78' stroke-width='2.5'/><circle cx='18' cy='29' r='3' fill='#10263a'/><path d='M26 24 C30 30 30 34 26 40' fill='none' stroke='#1c4f78' stroke-width='2'/>",
	5: "<path d='M32 54 L10 30 C12 14 52 14 54 30 Z' fill='#f2a693' stroke='#8a3f2f' stroke-width='2.5'/><g stroke='#8a3f2f' stroke-width='2' fill='none'><path d='M32 54 L20 22'/><path d='M32 54 L32 18'/><path d='M32 54 L44 22'/><path d='M32 54 L13 28'/><path d='M32 54 L51 28'/></g><path d='M24 54 L40 54 L36 60 L28 60 Z' fill='#e48a76' stroke='#8a3f2f' stroke-width='2'/>",
}


func _res_icon(r: int) -> Texture2D:
	if _res_tex.has(r):
		return _res_tex[r]
	var svg: String = "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'>" \
		+ "<circle cx='32' cy='34' r='29' fill='#fff8e6' fill-opacity='0.82' stroke='#3a2a14' stroke-width='2.5'/>" \
		+ RES_SVG[r] + "</svg>"
	var img := Image.new()
	img.load_svg_from_string(svg, 2.0)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_res_tex[r] = t
	return t

## 체력 막대 그림: 칸 하나가 체력 1. 남은 체력은 초록, 잃은 체력은 빨강, 위에서부터 잃는다.
func _hp_texture(hp: int, full: int) -> ImageTexture:
	var key: String = "%d/%d" % [hp, full]
	if _hp_tex.has(key):
		return _hp_tex[key]
	var seg_h: int = 7
	var w: int = 7
	var h: int = full * seg_h + 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.04, 0.03, 0.9))
	for k in full:
		# k = 0 이 맨 아래 칸
		var col: Color = Color("3fcf4a") if k < hp else Color("d63a2c")
		var y1: int = h - 1 - k * seg_h
		for y in range(y1 - seg_h + 1, y1):
			for x in range(1, w - 1):
				img.set_pixel(x, y, col)
	var t := ImageTexture.create_from_image(img)
	_hp_tex[key] = t
	return t


## 문명3 처럼 공격/방어/이동력
static func stat_text(u: GameRules.Unit) -> String:
	return "%d/%d/%d" % [u.info()["a"], u.info()["d"], u.info()["mp"]]


func _unit_text(u: GameRules.Unit) -> String:
	var t: String = "%s %s" % [u.name(), stat_text(u)]
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
				var col: Color = Color("d9d0b8") if u.side() == GameRules.Side.PREY else Color("e3a493")
				var lbl := _label("", col, 16, 0.32)
				lbl.offset = Vector2(0, 16)   # 체력 막대 위로
				lbl.position = Vector3(0, hs.spacing * 0.4, 0)
				lbl.name = "label"
				node.add_child(lbl)
			var bar := Sprite3D.new()
			bar.name = "hp"
			bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			bar.fixed_size = true
			bar.pixel_size = 0.0017
			bar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			bar.no_depth_test = true
			bar.render_priority = 21
			bar.shaded = false
			bar.position = Vector3(0, hs.spacing * 0.2, 0)
			# 문명3 처럼 유닛 왼쪽에 세로 체력 막대 (화면 기준으로 왼쪽에 붙도록 픽셀 오프셋)
			bar.offset = Vector2(-11, 2) if u.side() == GameRules.Side.PLAYER else Vector2(-17, 2)
			bar.visibility_range_end = 0.6 if u.side() == GameRules.Side.PLAYER else 0.32
			bar.set_meta("on", true)
			node.add_child(bar)
			_labels.append(bar)
			marks.add_child(node)
			_unit_nodes[u.id] = node
		(node.get_node("hp") as Sprite3D).texture = _hp_texture(u.hp, int(u.info()["hp"]))
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
	# 채집 식량: 칸 가운데에 그림으로만 보여 준다 (남은 양은 칸을 클릭하면 오른쪽 정보 창에)
	for i in gen.n:
		var r: int = rules.res_kind[i]
		if r == GameRules.Res.NONE:
			continue
		var amt: int = rules.res_amt[i]
		var entry: Array = _res_nodes.get(i, [])
		if entry.is_empty():
			var icon := Sprite3D.new()
			icon.texture = _res_icon(r)
			icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			icon.pixel_size = hs.spacing * 0.34 / 128.0
			icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			icon.shaded = false
			icon.visibility_range_end = 0.9
			var tf: Transform3D = _frame(_ground(i))
			icon.position = tf.origin + tf.basis.y * hs.spacing * 0.18
			marks.add_child(icon)
			entry = [icon, -1]
			_res_nodes[i] = entry
		if entry[1] != amt or full:
			entry[1] = amt
			# 다 쓴 자원은 흐리게
			(entry[0] as Sprite3D).modulate = Color(1, 1, 1, 1) if amt > 0 else Color(0.6, 0.6, 0.6, 0.45)
			(entry[0] as Sprite3D).alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD if amt > 0 else SpriteBase3D.ALPHA_CUT_DISABLED
	# 야영지와 부족민이 있는 칸: 이름표 하나에 모아 쓴다 (겹치지 않게)
	var tags := {}
	for c in rules.camps:
		var cl: Label3D = _camp_labels.get(c.tile)
		if cl == null:
			cl = _label("", Color("f3e4b6"), 19, 1.0, _font_bold)
			cl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			cl.transform = _frame(_ground(c.tile))
			cl.position += cl.transform.basis.y * hs.spacing * 0.05
			marks.add_child(cl)
			_camp_labels[c.tile] = cl
		cl.text = "%s  인구 %d/%d · 식량 %d/%d" % [c.name, c.pop, GameRules.CAMP_MAX_POP, c.food, GameRules.growth_need(c.pop)]
	for t in _camp_labels.keys():
		if rules.camp_at(t) == null:
			_camp_labels[t].queue_free()
			_camp_labels.erase(t)
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
			var line: String = ("부족민 " if ps.size() == 1 else "부족민 ×%d " % ps.size()) + stat_text(ps[0])
			if carry > 0:
				line += " · 식량 %d" % carry
			tags[t].append(line)
		var r2: int = rules.res_kind[t]
	for t in _tag_nodes.keys():
		if not tags.has(t):
			_tag_nodes[t].queue_free()
			_tag_nodes.erase(t)
	for t in tags:
		var lbl: Label3D = _tag_nodes.get(t)
		if lbl == null:
			lbl = _label("", Color("e6e8ea"), 16, 1.0)
			# 칸 가운데에서 화면 아래쪽으로 늘어지게 (문명 시리즈의 도시 이름처럼 칸 아래에)
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			lbl.transform = _frame(_ground(t))
			lbl.position += lbl.transform.basis.y * hs.spacing * 0.05
			marks.add_child(lbl)
			_tag_nodes[t] = lbl
		lbl.text = "\n".join(tags[t])
		# 야영지 이름 아래 줄에 오도록 (화면 픽셀 기준으로 내림)
		lbl.offset = Vector2(0, -22) if rules.camp_at(t) != null else Vector2.ZERO
	var sig: String = str(rules.camp_tiles.keys())
	if sig != _camp_sig:
		_camp_sig = sig
		view.recolor()
	_draw_selection()


func _process(delta: float) -> void:
	super._process(delta)
	_cull_labels()


## 행성 뒤쪽(지평선 너머)에 있는 글자와 꺼 둔 글자를 숨긴다.
func _cull_labels() -> void:
	var cp: Vector3 = cam.global_position
	var k: int = 0
	while k < _labels.size():
		var obj = _labels[k]
		if not is_instance_valid(obj) or (obj as Node3D).is_queued_for_deletion() or not (obj as Node3D).is_inside_tree():
			_labels.remove_at(k)
			continue
		var l: Node3D = obj
		var p: Vector3 = l.global_position
		l.visible = bool(l.get_meta("on", true)) and (cp - p).dot(p.normalized()) > 0.0
		k += 1


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
		sel_title.text = "%s %s  (남은 이동력 %d/%d)" % [u.name(), stat_text(u), u.mp, u.info()["mp"]]
		var t: Array = []
		t.append("공/방/이동 %s · 체력 %d/%d · 들고 있는 식량 %d/%d" % [stat_text(u), u.hp, u.info()["hp"], u.carry, GameRules.CARRY_MAX])
		var gt: int = rules.gather_target(u)
		if gt >= 0:
			t.append("채집 가능: %s (식량 %d, 한 번에 모두 거둠)" % [GameRules.RES_NAMES[rules.res_kind[gt]], rules.res_amt[gt]])
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
		var rel_txt: String = "부족민 내보내기 (U)" if c.pop > 1 else "모두 떠나기 (U, 야영지 사라짐)"
		sel_buttons.add_child(_button(rel_txt, _act_release, why_r == "", why_r))
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
		# 빈 칸을 누르면 그 칸 정보를 오른쪽 창에 고정한다 (한 번 더 누르면 풀림)
		selected = -1 if selected == t else t
		_draw_selection()
		_refresh_hud()
		return
	selected = -1
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
	var i: int = selected if selected >= 0 else hover
	if i < 0:
		return
	var lines: Array = []
	var a: GameRules.Unit = rules.animal_at(i)
	if a != null:
		var kind: String = "먹잇감" if a.side() == GameRules.Side.PREY else "포식자, 곁에 오면 덮침"
		lines.append("[color=#e8c872][font_size=17]%s[/font_size][/color]  [color=#9f906c](%s)[/color]" % [a.name(), kind])
		lines.append("공/방/이동 %s · 체력 %d/%d · 고기 %d" % [stat_text(a), a.hp, a.info()["hp"], a.info()["food"]])
		lines.append("[color=#9f906c]이 칸의 방어 보정 ×%.2f[/color]" % rules.terrain_defense(i))
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
		if rules.res_amt[i] > 0:
			lines.append("[b]채집 식량[/b]  %s, 거두면 식량 %d" % [GameRules.RES_NAMES[r], rules.res_amt[i]])
		else:
			lines.append("[b]채집 식량[/b]  %s, 다 거둠 (%d턴 뒤 다시 자람)" % [GameRules.RES_NAMES[r], rules.res_wait[i]])
	if lines.is_empty():
		return
	info_lbl.text = "\n".join(lines) + "\n\n" + info_lbl.text
