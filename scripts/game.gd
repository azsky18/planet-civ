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
var log_lbl := Label.new()
var sel_title := Label.new()
var sel_body := RichTextLabel.new()
var sel_buttons := HBoxContainer.new()
var msg_lbl := Label.new()
var over_lbl := Label.new()
var help_panel: PanelContainer
var info_panel: PanelContainer
var log_panel := PanelContainer.new()
var hp_row := HBoxContainer.new()
var end_btn: Button
var banner_layer := Control.new()
var _banners := {}               # 칸 -> 야영지 배너 (2D)
var shot_wait: float = 0.0
var fight_shots: String = ""   # 점검용: 합마다 화면을 이 경로(%d 포함)로 저장
var _fight_shot_n: int = 0


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
		elif a.begins_with("--fightshots="):
			fight_shots = a.substr(13)
		elif a.begins_with("--wait="):
			shot_wait = float(a.substr(7))
		elif a.begins_with("--play="):
			script_steps = Array(a.substr(7).split(","))
	await get_tree().process_frame
	await _new_game(seed_v)
	for s in script_steps:
		_scripted(s)
	_update_camera()
	if shot != "":
		if shot_wait > 0.0:
			await get_tree().create_timer(shot_wait).timeout
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
		"fight":
			# 전투 연출 점검용: 곁에 들소를 두고 공격한다
			if sel_unit != null:
				for j in rules.neighbors(sel_unit.tile):
					if rules.is_land(j) and rules.unit_at(j) == null and rules.camp_at(j) == null:
						rules.spawn("bison", j)
						_sync_marks()
						_order(j)
						break
		"inspect":
			# 칸 정보 점검용: 가까운 동물 칸을 고정해서 보여 준다
			if sel_unit != null:
				var near3: Dictionary = rules.within(sel_unit.tile, 4)
				for j in near3:
					if rules.animal_at(j) != null:
						selected = j
						_update_info()
						break
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

## 채집 식량 그림: art/tiles/resource/ 의 이름.svg (같은 이름의 PNG 가 있으면 그것). 256px, 바닥 점 (128,244).
## 그림을 바꾸려면 파일만 바꾸면 된다. 만드는 스크립트는 art/tools/gen_resources.py.
const RES_ART := ["", "wheat", "rice", "berry", "fish", "shell"]


func _res_icon(r: int) -> Texture2D:
	if _res_tex.has(r):
		return _res_tex[r]
	var path: String = ""
	for e in TileArt.scan("resource"):
		if e[0] == RES_ART[r]:
			path = e[1]
	var img: Image = TileArt.Atlas.load_image(path, 256) if path != "" else null
	if img == null:
		img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(GameRules.RES_COLORS[r])
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
		var col: Color = Color("3fcf4a") if k < hp else Color("e8382a")
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
func _sync_marks(full: bool = false, keep: Dictionary = {}) -> void:
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
			node.set_meta("kind", u.kind)
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
		if not alive.has(id) and not keep.has(id):
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
			# 칸 너비의 절반쯤 되는 크기로, 그림의 바닥 점이 칸 가운데 땅에 닿게 세운다
			icon.pixel_size = hs.spacing * 0.62 / 256.0
			icon.offset = Vector2(0, 128 - 12)
			icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			icon.shaded = false
			icon.visibility_range_end = 0.9
			var tf: Transform3D = _frame(_ground(i))
			icon.position = tf.origin + tf.basis.y * hs.spacing * 0.01
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
	_sync_banners()
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
		lbl.offset = Vector2(0, -48) if rules.camp_at(t) != null else Vector2.ZERO
	var sig: String = str(rules.camp_tiles.keys())
	if sig != _camp_sig:
		_camp_sig = sig
		view.recolor()
	_draw_selection()


func _process(delta: float) -> void:
	super._process(delta)
	_cull_labels()
	if rules != null:
		_place_banners()
		# 문명3 처럼 움직일 부족민이 없으면 턴 종료 단추가 은은하게 깜빡인다
		if end_btn != null:
			var idle: bool = _movable_count() == 0 and not busy
			var k: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0) if idle else 1.0
			end_btn.modulate = Color(1, 1, 1).lerp(Color(1.25, 1.12, 0.8), (1.0 - k) if idle else 0.0)


func _movable_count() -> int:
	var n: int = 0
	for u in rules.player_units():
		if u.mp > 0 and u.path.is_empty():
			n += 1
	return n


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
	var theme := make_ui_theme()

	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	layer.add_child(root)

	# 야영지 배너 (문명3 도시 배너처럼 지도 위에 2D 로 띄운다). 다른 판보다 먼저 넣어 아래에 깔리게.
	banner_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner_layer)

	# 위: 한 줄 상단 막대
	var top := PanelContainer.new()
	var tsb := _panel_style(0.92)
	tsb.set_border_width_all(0)
	tsb.border_width_bottom = 1
	tsb.set_corner_radius_all(0)
	tsb.content_margin_top = 6
	tsb.content_margin_bottom = 6
	tsb.shadow_size = 0
	top.add_theme_stylebox_override("panel", tsb)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(top)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 18)
	top.add_child(tr)
	turn_lbl.add_theme_font_override("font", font_title)
	turn_lbl.add_theme_font_size_override("font_size", 18)
	turn_lbl.add_theme_color_override("font_color", UI_GOLD)
	tr.add_child(turn_lbl)
	tr.add_child(VSeparator.new())
	pop_lbl.add_theme_font_size_override("font_size", 13)
	pop_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(pop_lbl)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(fill)
	var sub := Label.new()
	sub.text = "빌드 " + BUILD.split(" ")[0]
	sub.tooltip_text = BUILD
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(UI_MUTED.r, UI_MUTED.g, UI_MUTED.b, 0.7))
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_PASS
	tr.add_child(sub)
	tr.add_child(_button("조작법 (F1)", _toggle_help))
	tr.add_child(_button("처음 화면 (Esc)", _to_menu))

	# 왼쪽 위: 사건 기록
	var left := log_panel
	var lsb := _panel_style(0.55)
	lsb.border_color = Color(UI_LINE.r, UI_LINE.g, UI_LINE.b, 0.15)
	lsb.shadow_size = 0
	left.add_theme_stylebox_override("panel", lsb)
	left.position = Vector2(12, 52)
	left.custom_minimum_size = Vector2(300, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left.add_child(lv)
	log_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_lbl.custom_minimum_size = Vector2(272, 0)
	log_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_lbl.add_theme_font_size_override("font_size", 12)
	log_lbl.add_theme_color_override("font_color", Color("c8c0ad"))
	lv.add_child(log_lbl)

	# 오른쪽 위: 칸 정보 (문명3 처럼 꼭 필요한 몇 줄만). 보여 줄 것이 없으면 숨긴다.
	info_panel = PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _panel_style(0.9))
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_left = -12 - 250
	info_panel.offset_right = -12
	info_panel.offset_top = 52
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(info_panel)
	info_lbl.bbcode_enabled = true
	info_lbl.fit_content = true
	info_lbl.scroll_active = false
	info_lbl.custom_minimum_size = Vector2(222, 0)
	info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_lbl.add_theme_font_override("bold_font", _font_bold)
	info_lbl.add_theme_font_size_override("normal_font_size", 13)
	info_lbl.add_theme_font_size_override("bold_font_size", 13)
	info_panel.add_child(info_lbl)

	# 오른쪽 아래: 문명3 의 정보 상자. 위에 명령 단추 줄, 안에 고른 유닛·야영지, 맨 아래 턴 종료.
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.offset_right = -12
	br.offset_bottom = -12
	br.offset_left = -12 - 340
	br.offset_top = -12
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.add_theme_constant_override("separation", 6)
	root.add_child(br)
	sel_buttons.add_theme_constant_override("separation", 4)
	sel_buttons.alignment = BoxContainer.ALIGNMENT_END
	br.add_child(sel_buttons)
	var box := PanelContainer.new()
	var bsb := _panel_style(0.95)
	bsb.border_width_top = 2
	box.add_theme_stylebox_override("panel", bsb)
	box.custom_minimum_size = Vector2(340, 0)
	br.add_child(box)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	box.add_child(bv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	bv.add_child(head)
	sel_title.add_theme_font_override("font", font_title)
	sel_title.add_theme_font_size_override("font_size", 18)
	sel_title.add_theme_color_override("font_color", UI_GOLD)
	sel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sel_title)
	hp_row.add_theme_constant_override("separation", 2)
	hp_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hp_row)
	bv.add_child(HSeparator.new())
	sel_body.bbcode_enabled = true
	sel_body.fit_content = true
	sel_body.scroll_active = false
	sel_body.custom_minimum_size = Vector2(312, 0)
	sel_body.add_theme_font_override("bold_font", _font_bold)
	sel_body.add_theme_font_size_override("normal_font_size", 13)
	sel_body.add_theme_font_size_override("bold_font_size", 13)
	bv.add_child(sel_body)
	msg_lbl.add_theme_font_size_override("font_size", 12)
	msg_lbl.add_theme_color_override("font_color", Color("d9b46a"))
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.custom_minimum_size = Vector2(312, 0)
	bv.add_child(msg_lbl)
	bv.add_child(HSeparator.new())
	var tail := HBoxContainer.new()
	tail.add_theme_constant_override("separation", 6)
	bv.add_child(tail)
	var nb := _button("다음 (N)", _select_next)
	nb.custom_minimum_size = Vector2(96, 40)
	tail.add_child(nb)
	end_btn = _button("턴 종료  ⏎", _end_turn, true, "Enter")
	end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_btn.custom_minimum_size = Vector2(0, 40)
	end_btn.add_theme_font_override("font", font_title)
	end_btn.add_theme_font_size_override("font_size", 18)
	end_btn.add_theme_color_override("font_color", Color("f1e2bd"))
	end_btn.add_theme_stylebox_override("normal", _flat(Color("2a2418"), UI_GOLD, 2))
	end_btn.add_theme_stylebox_override("hover", _flat(Color("3a3120"), Color("e6c47a"), 2))
	end_btn.add_theme_stylebox_override("pressed", _flat(Color("1c1810"), UI_GOLD, 2))
	tail.add_child(end_btn)

	# 조작법: F1 로 여닫는 판
	help_panel = PanelContainer.new()
	help_panel.add_theme_stylebox_override("panel", _panel_style(0.95))
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	help_panel.visible = false
	root.add_child(help_panel)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	help_panel.add_child(hv)
	var ht := Label.new()
	ht.text = "조작법"
	ht.add_theme_font_override("font", font_title)
	ht.add_theme_font_size_override("font_size", 20)
	ht.add_theme_color_override("font_color", UI_GOLD)
	hv.add_child(ht)
	hv.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 5)
	hv.add_child(grid)
	for pair in [["왼쪽 클릭", "부족민·야영지·칸 고르기 (야영지 배너를 눌러도 됨)"], ["오른쪽 클릭", "이동, 곁의 동물 공격"],
			["B", "야영지 세우기"], ["G", "채집"], ["J", "야영지에 합류"], ["U", "부족민 내보내기"],
			["N / Tab", "다음 부족민"], ["Space", "이번 턴 쉬기 (체력 1칸 회복)"], ["Enter", "턴 종료"],
			["드래그 / 휠", "회전 / 확대·축소"], ["Q / E", "시점 돌리기"], ["C", "고른 곳으로 시점 이동"],
			["F1", "이 창 여닫기"], ["Esc", "처음 화면"]]:
		var k := Label.new()
		k.text = pair[0]
		k.add_theme_color_override("font_color", UI_GOLD)
		grid.add_child(k)
		var v := Label.new()
		v.text = pair[1]
		grid.add_child(v)

	over_lbl.add_theme_font_override("font", font_title)
	over_lbl.add_theme_font_size_override("font_size", 40)
	over_lbl.add_theme_color_override("font_color", UI_GOLD)
	over_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	over_lbl.add_theme_constant_override("outline_size", 6)
	over_lbl.set_anchors_preset(Control.PRESET_CENTER)
	over_lbl.position = Vector2(-200, -60)
	over_lbl.visible = false
	root.add_child(over_lbl)
	_update_info()


## 글이 바뀐 판을 내용에 맞게 다시 잰다 (RichTextLabel 높이는 한 프레임 늦게 정해짐)
func _fit_panels() -> void:
	await get_tree().process_frame
	# 자동 줄바꿈 글의 최소 높이가 실제보다 작게 잡히는 일이 있어 줄 수로 직접 잡아 준다
	log_lbl.custom_minimum_size.y = log_lbl.get_line_count() * (log_lbl.get_line_height() + 3) + 6
	log_panel.reset_size()
	if info_panel != null:
		info_panel.reset_size()


func _toggle_help() -> void:
	help_panel.visible = not help_panel.visible


## 체력 칸을 UI 로: 남은 칸 초록, 깎인 칸 빨강 (지도 위 막대와 같은 색)
func _set_hp_row(hp: int, full: int) -> void:
	for c in hp_row.get_children():
		c.queue_free()
	for k in full:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(12, 9)
		r.color = Color("3fcf4a") if k < hp else Color("e8382a")
		hp_row.add_child(r)


# ---------------------------------------------------------------- 야영지 배너

## 문명3 도시 배너: [인구] 이름 [성장까지 턴], 아래에 식량 창고 막대
func _make_banner(c: GameRules.Camp) -> Control:
	var b := PanelContainer.new()
	var sb := _flat(Color(0.07, 0.08, 0.10, 0.9), Color(0.79, 0.65, 0.35, 0.8), 1)
	sb.content_margin_left = 0
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	b.add_theme_stylebox_override("panel", sb)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not busy:
			var cc: GameRules.Camp = rules.camp_at(b.get_meta("tile"))
			if cc != null:
				_select_camp(cc))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var pop := Label.new()
	pop.name = "pop"
	pop.custom_minimum_size = Vector2(24, 24)
	pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pop.add_theme_font_override("font", _font_bold)
	pop.add_theme_font_size_override("font_size", 15)
	pop.add_theme_color_override("font_color", Color("ffffff"))
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color("2f5fb8")
	psb.set_corner_radius_all(1)
	pop.add_theme_stylebox_override("normal", psb)
	h.add_child(pop)
	var name_l := Label.new()
	name_l.name = "name"
	name_l.add_theme_font_override("font", _font_bold)
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", Color("f3ead2"))
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_l)
	var grow := Label.new()
	grow.name = "grow"
	grow.add_theme_font_size_override("font_size", 11)
	grow.add_theme_color_override("font_color", Color("9fd38a"))
	grow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(grow)
	var bar := ProgressBar.new()
	bar.name = "food"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.18, 0.12, 0.9)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color("6fbf4a")
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	b.set_meta("tile", c.tile)
	banner_layer.add_child(b)
	return b


func _sync_banners() -> void:
	for c in rules.camps:
		var b: Control = _banners.get(c.tile)
		if b == null:
			b = _make_banner(c)
			_banners[c.tile] = b
		var need: int = GameRules.growth_need(c.pop)
		var net: int = rules.camp_net(c)
		(b.find_child("pop", true, false) as Label).text = str(c.pop)
		(b.find_child("name", true, false) as Label).text = c.name
		var g: String
		if c.pop >= GameRules.CAMP_MAX_POP:
			g = "가득"
		elif net <= 0:
			g = "정체"
		else:
			g = "%d턴" % int(ceil(float(maxi(need - c.food, 0)) / float(net)))
		(b.find_child("grow", true, false) as Label).text = g
		var bar := b.find_child("food", true, false) as ProgressBar
		bar.max_value = need
		bar.value = c.food
		b.reset_size()
	for t in _banners.keys():
		if rules.camp_at(t) == null:
			_banners[t].queue_free()
			_banners.erase(t)


## 배너를 야영지 칸 바로 아래 화면 위치에 둔다. 행성 뒤쪽이거나 너무 멀면 숨긴다.
func _place_banners() -> void:
	var cp: Vector3 = cam.global_position
	for t in _banners:
		var b: Control = _banners[t]
		var p: Vector3 = _ground(t)
		var front: bool = (cp - p).dot(p.normalized()) > 0.0 and dist < 2.2
		b.visible = front and not cam.is_position_behind(p)
		if b.visible:
			var sp: Vector2 = cam.unproject_position(p)
			b.position = (sp + Vector2(-b.size.x * 0.5, 14)).round()


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
	for e in rules.events.slice(-6):
		lines.append(e)
	log_lbl.text = "\n".join(lines)
	_fit_panels.call_deferred()
	over_lbl.visible = rules.game_over
	over_lbl.text = "부족이 모두 사라졌습니다"
	_refresh_selection()
	_update_info()


func _refresh_selection() -> void:
	for c in sel_buttons.get_children():
		c.queue_free()
	if sel_unit != null and not rules.units.has(sel_unit):
		sel_unit = null
	_set_hp_row(0, 0)
	if sel_unit != null:
		var u: GameRules.Unit = sel_unit
		sel_title.text = u.name()
		_set_hp_row(u.hp, int(u.info()["hp"]))
		var t: Array = []
		t.append("[b]공격[/b] %d   [b]방어[/b] %d   [b]이동[/b] %d/%d   [b]체력[/b] %d/%d" % [u.info()["a"], u.info()["d"], u.mp, u.info()["mp"], u.hp, u.info()["hp"]])
		t.append("[color=#9a917e]식량[/color] %d/%d   [color=#9a917e]땅[/color] %s" % [u.carry, GameRules.CARRY_MAX, _terrain_name(u.tile)])
		var gt: int = rules.gather_target(u)
		if gt >= 0:
			t.append("[color=#9fd38a]채집 가능: %s, 식량 %d[/color]" % [GameRules.RES_NAMES[rules.res_kind[gt]], rules.res_amt[gt]])
		if not u.path.is_empty():
			t.append("[color=#9a917e]목적지까지 %d칸[/color]" % u.path.size())
		sel_body.text = "\n".join(t)
		var why_c: String = rules.camp_block_reason(u)
		sel_buttons.add_child(_button("야영지 B", _act_camp, why_c == "", why_c if why_c != "" else "야영지 세우기"))
		var why_g: String = rules.gather_block_reason(u)
		sel_buttons.add_child(_button("채집 G", _act_gather, why_g == "", why_g if why_g != "" else "채집"))
		if rules.camp_at(u.tile) != null:
			var why_j: String = rules.join_block_reason(u)
			sel_buttons.add_child(_button("합류 J", _act_join, why_j == "", why_j if why_j != "" else "야영지에 합류"))
		sel_buttons.add_child(_button("쉬기 Space", _act_rest, u.mp > 0, "이번 턴 쉬기 (다음 턴 체력 1칸 회복)"))
	elif sel_camp != null:
		var c: GameRules.Camp = sel_camp
		sel_title.text = c.name
		var net: int = rules.camp_net(c)
		var need: int = GameRules.growth_need(c.pop)
		var t2: Array = []
		t2.append("[b]인구[/b] %d/%d   [b]식량[/b] %d/%d   [b]턴당[/b] %+d" % [c.pop, GameRules.CAMP_MAX_POP, c.food, need, net])
		t2.append("[color=#9a917e]일하는 칸 %d곳, 모닥불 +%d, 먹는 양 -%d[/color]" % [rules.camp_worked(c).size(), GameRules.CAMP_BONUS, GameRules.FOOD_PER_POP * c.pop])
		if c.pop >= GameRules.CAMP_MAX_POP:
			t2.append("[color=#d9a066]인구가 가득 찼습니다. 부족민을 내보내세요.[/color]")
		elif net > 0:
			t2.append("[color=#9fd38a]%d턴 뒤 인구 +1[/color]" % int(ceil(float(maxi(need - c.food, 0)) / float(net))))
		sel_body.text = "\n".join(t2)
		var why_r: String = rules.release_block_reason(c)
		var rel_txt: String = "내보내기 U" if c.pop > 1 else "모두 떠나기 U"
		sel_buttons.add_child(_button(rel_txt, _act_release, why_r == "", why_r if why_r != "" else ("부족민 1명 내보내기" if c.pop > 1 else "마지막 사람이 떠나면 야영지가 사라집니다")))
	else:
		sel_title.text = "수렵채집 부족"
		if _movable_count() == 0:
			sel_body.text = "[color=#d9b46a]모든 부족민이 움직였습니다. 턴을 마치세요 (Enter).[/color]"
		else:
			sel_body.text = "[color=#9a917e]움직일 부족민 %d명. N 으로 다음 부족민을 고르세요.[/color]" % _movable_count()


## 칸 이름: 생물군 + 기복 + 물 (문명3 의 "초원 (강)" 처럼 짧게)
func _terrain_name(i: int) -> String:
	if not rules.is_land(i):
		return "호수" if gen.is_lake[i] == 1 else "바다"
	var parts: Array = [WorldGen.BIOME_NAMES[gen.biome[i]]]
	if gen.relief[i] > 0:
		parts.append(WorldGen.RELIEF_NAMES[gen.relief[i]])
	if gen.is_river[i] == 1:
		parts.append("강")
	return " · ".join(parts)


# ---------------------------------------------------------------- 행동

func _say(m: String) -> void:
	msg_lbl.text = m


func _after_action() -> void:
	if busy:
		return   # 전투를 보여 주는 중이면 끝날 때 한꺼번에 갱신된다
	if not rules.fights.is_empty():
		await _play_fights()
	_sync_marks()
	_refresh_hud()


## 전투를 한 합씩 보여 준다: 공격하는 쪽이 달려들고, 맞은 쪽 체력 막대가 한 칸씩 빨갛게 바뀐다.
func _play_fights() -> void:
	var keep := {}
	for f in rules.fights:
		keep[f["att"]] = true
		keep[f["def"]] = true
	_sync_marks(false, keep)
	busy = true
	for f in rules.fights:
		var an: Node3D = _unit_nodes.get(f["att"])
		var dn: Node3D = _unit_nodes.get(f["def"])
		if an == null or dn == null or not is_instance_valid(an) or not is_instance_valid(dn):
			continue
		var af: int = int(GameRules.KINDS[_kind_of(f["att"], an)]["hp"])
		var df: int = int(GameRules.KINDS[_kind_of(f["def"], dn)]["hp"])
		var ah: int = f["att_hp"]
		var dh: int = f["def_hp"]
		var abar := an.get_node("hp") as Sprite3D
		var dbar := dn.get_node("hp") as Sprite3D
		abar.texture = _hp_texture(ah, af)
		dbar.texture = _hp_texture(dh, df)
		# 공격자는 방어자 쪽 칸 경계까지 나와서 싸운다
		var home: Vector3 = an.position
		var front: Vector3 = home.lerp(dn.position, 0.45)
		var t0 := create_tween()
		t0.tween_property(an, "position", front, 0.18)
		await t0.finished
		for hit in f["rounds"]:
			var victim: Node3D = dn if hit else an
			if hit:
				dh -= 1
				dbar.texture = _hp_texture(dh, df)
			else:
				ah -= 1
				abar.texture = _hp_texture(ah, af)
			var base: Vector3 = victim.position
			var side: Vector3 = victim.transform.basis.x * hs.spacing * 0.05
			var tw := create_tween()
			tw.tween_property(victim, "position", base + side, 0.05)
			tw.tween_property(victim, "position", base - side, 0.08)
			tw.tween_property(victim, "position", base, 0.05)
			await tw.finished
			if fight_shots != "":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(fight_shots % _fight_shot_n)
				_fight_shot_n += 1
			await get_tree().create_timer(0.32).timeout
		var loser: Node3D = dn if dh <= 0 else an
		var tl := create_tween()
		tl.tween_property(loser, "scale", Vector3.ONE * 0.05, 0.3)
		await tl.finished
		loser.visible = false
		if loser != an:
			var tb := create_tween()
			tb.tween_property(an, "position", home, 0.15)
			await tb.finished
	rules.fights.clear()
	busy = false


func _kind_of(id: int, node: Node3D) -> String:
	for u in rules.units:
		if u.id == id:
			return u.kind
	return node.get_meta("kind", "tribe")


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
	if sel_unit == null or goal < 0 or busy:
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
	if not rules.fights.is_empty():
		await _play_fights()
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
			KEY_F1:
				_toggle_help()
			KEY_ESCAPE:
				if help_panel.visible:
					help_panel.visible = false
				else:
					_to_menu()
			KEY_R:
				super._unhandled_input(event)


func _pick(mp: Vector2) -> void:
	var before: int = hover
	super._pick(mp)
	if hover != before:
		_update_info()


func _update_info() -> void:
	if rules == null or info_panel == null:
		return
	var i: int = selected if selected >= 0 else hover
	if i < 0:
		info_panel.visible = false
		return
	view.set_hover(i)
	info_panel.visible = true
	var lines: Array = []
	lines.append("[font_size=16][color=#c9a75a]%s[/color][/font_size]%s" % [_terrain_name(i), "  [color=#9a917e]고정[/color]" if selected >= 0 else ""])
	if rules.is_land(i):
		var y: Vector3i = TileLayers.yields(gen, i)
		var dfn: int = int(round((rules.terrain_defense(i) - 1.0) * 100.0))
		var row: String = "[color=#9a917e]식량[/color] %d" % y.x
		if dfn > 0:
			row += "    [color=#9a917e]방어[/color] +%d%%" % dfn
		lines.append(row)
	var r: int = rules.res_kind[i]
	if r != GameRules.Res.NONE:
		if rules.res_amt[i] > 0:
			lines.append("[color=#9fd38a]%s[/color]  채집하면 식량 %d" % [GameRules.RES_NAMES[r], rules.res_amt[i]])
		else:
			lines.append("[color=#9a917e]%s  다 거둠, %d턴 뒤 다시 자람[/color]" % [GameRules.RES_NAMES[r], rules.res_wait[i]])
	var c: GameRules.Camp = rules.camp_at(i)
	if c != null:
		lines.append("[b]%s[/b]  인구 %d" % [c.name, c.pop])
	var ps: Array = rules.players_at(i)
	if not ps.is_empty():
		lines.append("부족민 %d명" % ps.size())
	var a: GameRules.Unit = rules.animal_at(i)
	if a != null:
		var col: String = "#d9d0b8" if a.side() == GameRules.Side.PREY else "#e3a493"
		lines.append("[b][color=%s]%s[/color][/b] %s   체력 %d/%d" % [col, a.name(), stat_text(a), a.hp, a.info()["hp"]])
		if sel_unit != null and rules.units.has(sel_unit):
			var odds: int = int(round(rules.attack_odds(sel_unit, a) * 100.0))
			var oc: String = "#9fd38a" if odds >= 60 else ("#d9b46a" if odds >= 40 else "#e07a5f")
			lines.append("공격 승률 [b][color=%s]%d%%[/color][/b]%s" % [oc, odds, "" if rules.is_adjacent(sel_unit.tile, i) else "  [color=#9a917e](곁으로 가야 함)[/color]"])
	info_lbl.text = "\n".join(lines)
	_fit_panels.call_deferred()

