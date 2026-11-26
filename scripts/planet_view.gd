class_name PlanetView
extends Node3D
## 행성 메시.
## 각 타일의 꼭짓점은 그 점을 공유하는 세 타일 고도의 평균에 놓인다. 그래서 타일 사이에
## 단차가 생기지 않고, 고도 차이는 타일이 기울어진 모습으로 나타난다. 산은 따로 모양을
## 만들지 않고 높은 고도가 모여서 자연스럽게 산맥으로 보인다.
## 바다는 해저 지형 위에 반투명 수면 구를 덮고, 호수는 평평한 수면을 따로 그린다.

enum Mode { BIOME, ELEVATION, TEMPERATURE, PRECIP, PLATES, WIND, VEG }

const LAND_SCALE := 0.07     # 고도 1.0 (약 7,500m) 일 때 반지름 증가량
const SEA_SCALE := 0.025     # 수심 쪽은 덜 과장
const LAND_BASE := 0.0025    # 해안선이 수면 위로 올라오도록 하는 최소 높이
const SEA_BASE := 0.004

var hs: HexSphere
var gen: WorldGen
var exaggeration: float = 1.0
var mode: int = Mode.BIOME

var tile_radius := PackedFloat32Array()     # 타일 가운데 반지름
var corner_radius := PackedFloat32Array()   # 꼭짓점(면) 반지름
var _arrays: Array = []
var _vert_tile := PackedInt32Array()
var _vert_shade := PackedFloat32Array()

var terrain_mi := MeshInstance3D.new()
var water_mi := MeshInstance3D.new()
var lake_mi := MeshInstance3D.new()
var river_mi := MeshInstance3D.new()
var grid_mi := MeshInstance3D.new()
var wind_mi := MeshInstance3D.new()
var hover_mi := MeshInstance3D.new()
var atmo_mi := MeshInstance3D.new()
var terrain_mesh := ArrayMesh.new()

## 타일 위 그림 (식생, 도로, 시설물). 그림 목록과 고르는 규칙은 TileArt 에 있다.
static var tile_art: TileArt
var art_enabled := true
## 꼭짓점 조합 바닥 (땅, 물, 물가를 한 장으로). 가까이서만 보인다.
var surface_mi := MeshInstance3D.new()
var _surface_mat := ShaderMaterial.new()
var _surface_sig := PackedInt32Array()   # 마지막으로 만든 바닥의 칸별 무늬 (바뀐 게 없으면 다시 만들지 않는다)
var art_veg_mi := MeshInstance3D.new()
var art_road_mi := MeshInstance3D.new()
var art_struct_mi := MeshInstance3D.new()
var art_shadow_mi := MeshInstance3D.new()
var art_sprite_mi := MeshInstance3D.new()
var river_bank_mi := MeshInstance3D.new()

## 꼭짓점 조합 바닥. 세 칸이 만나는 꼭짓점마다 삼각형 하나(그 세 칸의 가운데를 잇는)를 이루고,
## 세 칸의 무늬를 무게(COLOR.rgb, 칸 가운데에서 1)로 섞는다. 무게에 노이즈를 더해 경계를 구불구불하게 하고,
## 땅과 물이 만나는 곳에는 땅 쪽에 물가 무늬, 물 쪽에 물거품을 넣는다.
## CUSTOM0 = 세 칸의 무늬 층 (a, b, c), 조합 완성 그림이 있으면 w = 1. CUSTOM1 = 세 칸의 물가 무늬 층.
## UV = 조합 완성 그림 위의 좌표. 무늬는 위치로 세 방향에서 찍어 섞는다(삼면 투영).
const SURFACE_SHADER := """
shader_type spatial;
uniform sampler2DArray tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D combo : source_color, filter_linear_mipmap;
uniform float tex_scale = 25.0;
uniform float near_d = 0.6;
uniform float far_d = 0.9;
uniform float water_start = 100.0;
varying vec3 opos;
varying vec3 onrm;
varying vec3 bw;
varying vec4 lay;
varying vec4 shl;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	bw = COLOR.rgb;
	lay = CUSTOM0;
	shl = CUSTOM1;
}

vec3 tri3(float layer, vec3 p, vec3 tw) {
	return texture(tex, vec3(p.yz, layer)).rgb * tw.x
		+ texture(tex, vec3(p.xz, layer)).rgb * tw.y
		+ texture(tex, vec3(p.xy, layer)).rgb * tw.z;
}

float nz(vec3 p, vec3 tw) {
	return texture(noise, p.yz).r * tw.x + texture(noise, p.xz).r * tw.y + texture(noise, p.xy).r * tw.z;
}

void fragment() {
	float k = 1.0 - smoothstep(near_d, far_d, length(VERTEX));
	// 멀어지면 점점이 사라지며 칸 색으로 넘어간다
	float h = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (h >= k) {
		discard;
	}
	vec3 tw = pow(abs(normalize(onrm)), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	vec3 p = opos * tex_scale;
	// 경계 흔들기 노이즈는 칸의 순서(x,y,z)가 아니라 그 칸의 바닥 그림 번호로 고른다.
	// 이웃 삼각형에서는 같은 칸이 다른 자리에 오기 때문에, 자리로 고르면 삼각형 경계에서 물가선이 어긋난다.
	vec3 nv = vec3(nz(p * 0.35 + lay.x * vec3(0.37, 0.13, 0.51), tw),
		nz(p * 0.35 + lay.y * vec3(0.37, 0.13, 0.51), tw),
		nz(p * 0.35 + lay.z * vec3(0.37, 0.13, 0.51), tw));
	// 이 삼각형에 없는 칸(무게 0, 즉 이웃 삼각형과 맞닿은 변)은 흔들지 않아 양쪽이 똑같이 이어진다.
	vec3 w = clamp(bw + (nv - 0.5) * 0.55 * clamp(bw * 4.0, 0.0, 1.0), 0.0, 1.0);
	w = pow(w, vec3(5.0));
	w /= (w.x + w.y + w.z + 1e-6);
	vec3 isw = vec3(step(water_start - 0.5, lay.x), step(water_start - 0.5, lay.y), step(water_start - 0.5, lay.z));
	vec3 ca = tri3(lay.x, p, tw);
	vec3 cb = tri3(lay.y, p, tw);
	vec3 cc = tri3(lay.z, p, tw);
	vec3 col = ca * w.x + cb * w.y + cc * w.z;
	float wet = 0.0;
	// 땅과 물이 섞이면: 경계를 또렷하게, 땅 쪽에 물가 무늬, 물 쪽에 물거품
	float anyw = isw.x + isw.y + isw.z;
	if (anyw > 0.5 && anyw < 2.5) {
		vec3 lw3 = w * (1.0 - isw);
		vec3 ww3 = w * isw;
		float lw = lw3.x + lw3.y + lw3.z;
		float ww = ww3.x + ww3.y + ww3.z;
		vec3 land = (ca * lw3.x + cb * lw3.y + cc * lw3.z) / max(lw, 1e-4);
		vec3 water = (ca * ww3.x + cb * ww3.y + cc * ww3.z) / max(ww, 1e-4);
		vec3 sh = vec3(0.0);
		float shw = 0.0;
		if (shl.x >= 0.0) { sh += tri3(shl.x, p, tw) * lw3.x; shw += lw3.x; }
		if (shl.y >= 0.0) { sh += tri3(shl.y, p, tw) * lw3.y; shw += lw3.y; }
		if (shl.z >= 0.0) { sh += tri3(shl.z, p, tw) * lw3.z; shw += lw3.z; }
		if (shw > 1e-4) {
			sh /= shw;
			float s = 1.0 - smoothstep(0.55, 0.8, lw + (nz(p * 1.3, tw) - 0.5) * 0.2);
			land = mix(land, sh, s);
		}
		float m = smoothstep(0.47, 0.53, lw);
		float foam = smoothstep(0.3, 0.44, lw) * (1.0 - smoothstep(0.44, 0.5, lw));
		foam *= smoothstep(0.35, 0.6, nz(p * 3.0, tw));
		water = mix(water, vec3(0.93, 0.95, 0.93), foam * 0.85);
		col = mix(water, land, m);
		wet = 1.0 - m;
	} else if (anyw > 2.5) {
		wet = 1.0;
	}
	if (lay.w > 0.5) {
		vec4 o = texture(combo, UV);
		col = mix(col, o.rgb, o.a);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.35, wet);
	SPECULAR = mix(0.1, 0.5, wet);
}
"""

## 세운 그림: 네 꼭짓점이 모두 바닥 점에 모여 있고, UV2 만큼 카메라 쪽으로 펼친다.
## 세로축은 카메라 위쪽과 지면의 위쪽을 섞어서, 내려다볼 때도 납작해지지 않게 한다.
const SPRITE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float near_d = 0.6;
uniform float far_d = 0.9;
void vertex() {
	vec3 anchor = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 up = normalize(anchor);
	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 vaxis = normalize(cam_up + up * 0.9);
	vec3 haxis = normalize(cross(vaxis, cross(cam_right, vaxis)) + cam_right * 0.001);
	float d = length(anchor - CAMERA_POSITION_WORLD);
	float k = 1.0 - smoothstep(near_d, far_d, d);
	vec3 wp = anchor + (haxis * UV2.x + vaxis * UV2.y) * k + up * 0.0008;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(normalize(up * 0.5 + normalize(INV_VIEW_MATRIX[2].xyz) * 0.5), 0.0)).xyz;
}
void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	EMISSION = t.rgb * COLOR.rgb * 0.18;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
"""
var _sprite_mat := ShaderMaterial.new()
## 그림이 보이기 시작하는 화면 위 칸 크기 (px, 화면 높이 900 기준). 이보다 작으면 흐려지다 사라진다.
const ART_MIN_PX := 26.0
const ART_FULL_PX := 40.0


func _ready() -> void:
	if tile_art == null:
		tile_art = TileArt.new()
		tile_art.load_all()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic_specular = 0.1
	terrain_mi.material_override = mat
	var surf_sh := Shader.new()
	surf_sh.code = SURFACE_SHADER
	_surface_mat.shader = surf_sh
	_surface_mat.set_shader_parameter("tex", tile_art.ground_tex)
	_surface_mat.set_shader_parameter("water_start", float(tile_art.water_start))
	_surface_mat.set_shader_parameter("noise", _make_noise())
	if tile_art.combos.count > 0:
		_surface_mat.set_shader_parameter("combo", tile_art.combos.texture)
	surface_mi.material_override = _surface_mat
	surface_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface_mi)
	terrain_mi.mesh = terrain_mesh
	add_child(terrain_mi)

	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.08, 0.2, 0.36, 0.84)
	wmat.roughness = 0.55
	wmat.metallic_specular = 0.25
	wmat.render_priority = -1   # 해안 물거품이 수면 위에 그려지도록 수면을 먼저 그린다
	var ws := SphereMesh.new()
	ws.radius = 1.0
	ws.height = 2.0
	ws.radial_segments = 256
	ws.rings = 128
	water_mi.mesh = ws
	water_mi.material_override = wmat
	add_child(water_mi)

	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color("4f93b3")
	lmat.roughness = 0.3
	lmat.metallic_specular = 0.6
	lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lake_mi.material_override = lmat
	add_child(lake_mi)

	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.vertex_color_use_as_albedo = true
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color("3f7f9a")
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _river_tex():
		# 강물 그림(decal/river)이 있으면 그 그림으로 칠한다
		rmat.albedo_color = Color.WHITE
		rmat.albedo_texture = tile_art.decals.texture
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		rmat.render_priority = 3
	river_mi.material_override = rmat
	add_child(river_mi)

	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.1, 0.07, 0.03, 0.45)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmat.render_priority = 5
	grid_mi.material_override = gmat
	add_child(grid_mi)

	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.vertex_color_use_as_albedo = true
	wind_mi.material_override = amat
	wind_mi.visible = false
	add_child(wind_mi)

	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.albedo_color = Color("f2d27a")
	hmat.no_depth_test = true
	hover_mi.material_override = hmat
	add_child(hover_mi)

	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = vec3(0.42, 0.62, 0.95) * f * 0.9;
}
"""
	var am := ShaderMaterial.new()
	am.shader = sh
	var sph := SphereMesh.new()
	sph.radius = 1.07
	sph.height = 2.14
	sph.radial_segments = 96
	sph.rings = 48
	atmo_mi.mesh = sph
	atmo_mi.material_override = am
	add_child(atmo_mi)

	var prio := 0
	# 그리는 순서: (꼭짓점 조합 바닥) -> 강둑 -> 강물 -> 식생 -> 도로 -> 시설 -> 그림자
	for mi in [river_bank_mi, art_veg_mi, art_road_mi, art_struct_mi, art_shadow_mi]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = tile_art.decals.texture
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
		m.metallic_specular = 0.05
		m.render_priority = prio
		prio += 1
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var ssh := Shader.new()
	ssh.code = SPRITE_SHADER
	_sprite_mat.shader = ssh
	_sprite_mat.set_shader_parameter("atlas", tile_art.sprites.texture)
	art_sprite_mi.material_override = _sprite_mat
	art_sprite_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 세운 그림은 카메라 쪽으로 기울어 실제 위치를 벗어나므로 화면 밖으로 잘리지 않게 넉넉히
	art_sprite_mi.extra_cull_margin = 0.5
	add_child(art_sprite_mi)


func _land_r(e: float) -> float:
	return 1.0 + LAND_BASE + e * LAND_SCALE * exaggeration


func radius_for(i: int) -> float:
	if gen.is_lake[i] == 1:
		return _land_r(gen.filled[i]) - 0.0015   # 호수 바닥은 수면보다 약간 아래
	var e: float = gen.elevation[i]
	if e >= 0.0:
		return _land_r(e)
	return 1.0 - SEA_BASE + e * SEA_SCALE * maxf(exaggeration, 0.3)


func lake_level(i: int) -> float:
	return _land_r(gen.filled[i]) + 0.0004


func rebuild() -> void:
	tile_radius.resize(hs.count)
	for i in hs.count:
		tile_radius[i] = radius_for(i)
	var fc: int = hs.face_centers.size()
	corner_radius.resize(fc)
	for f in fc:
		var ta: int = hs.face_tiles[f * 3]
		var tb: int = hs.face_tiles[f * 3 + 1]
		var tc: int = hs.face_tiles[f * 3 + 2]
		var sea: int = int(gen.elevation[ta] < 0.0) + int(gen.elevation[tb] < 0.0) + int(gen.elevation[tc] < 0.0)
		if sea > 0 and sea < 3:
			# 땅과 바다가 만나는 꼭짓점은 정확히 수면 높이에 둔다 -> 해안선이 칸 경계를 따라간다
			corner_radius[f] = 1.0
		else:
			corner_radius[f] = (tile_radius[ta] + tile_radius[tb] + tile_radius[tc]) / 3.0
	_build_terrain()
	_build_lakes()
	_build_rivers()
	_build_grid()
	_build_wind()
	set_hover(-1)


func corner_pos(k: int) -> Vector3:
	var f: int = hs.corner_face[k]
	return hs.face_centers[f] * corner_radius[f]


func _build_terrain() -> void:
	var fc: int = hs.face_centers.size()
	# 공유 정점 기준으로 부드러운 법선 계산
	var n_center := PackedVector3Array()
	n_center.resize(hs.count)
	var n_face := PackedVector3Array()
	n_face.resize(fc)
	for i in hs.count:
		var c: Vector3 = hs.centers[i]
		var pc: Vector3 = c * tile_radius[i]
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		for k in deg:
			var ka: int = off + k
			var kb: int = off + (k + 1) % deg
			var pa: Vector3 = corner_pos(ka)
			var pb: Vector3 = corner_pos(kb)
			var tn: Vector3 = (pa - pc).cross(pb - pc)
			if tn.dot(c) < 0.0:
				tn = -tn
			n_center[i] += tn
			n_face[hs.corner_face[ka]] += tn
			n_face[hs.corner_face[kb]] += tn

	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	_vert_tile = PackedInt32Array()
	_vert_shade = PackedFloat32Array()
	for i in hs.count:
		var c: Vector3 = hs.centers[i]
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		var base: int = pos.size()
		pos.append(c * tile_radius[i])
		nrm.append(n_center[i].normalized())
		_vert_tile.append(i)
		_vert_shade.append(1.0)
		for k in deg:
			pos.append(corner_pos(off + k))
			nrm.append(n_face[hs.corner_face[off + k]].normalized())
			_vert_tile.append(i)
			_vert_shade.append(1.0)
		for k in deg:
			idx.append(base)
			idx.append(base + 1 + (k + 1) % deg)
			idx.append(base + 1 + k)
	_arrays = []
	_arrays.resize(Mesh.ARRAY_MAX)
	_arrays[Mesh.ARRAY_VERTEX] = pos
	_arrays[Mesh.ARRAY_NORMAL] = nrm
	_arrays[Mesh.ARRAY_INDEX] = idx
	recolor()


func recolor() -> void:
	var tile_col := PackedColorArray()
	tile_col.resize(hs.count)
	for i in hs.count:
		tile_col[i] = tile_color(i)
	var cols := PackedColorArray()
	cols.resize(_vert_tile.size())
	for v in _vert_tile.size():
		var col: Color = tile_col[_vert_tile[v]]
		var s: float = _vert_shade[v]
		cols[v] = Color(col.r * s, col.g * s, col.b * s)
	_arrays[Mesh.ARRAY_COLOR] = cols
	terrain_mesh.clear_surfaces()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	# 수면은 지형/고도 보기에서만 덮는다
	water_mi.visible = mode == Mode.BIOME or mode == Mode.ELEVATION or mode == Mode.VEG
	lake_mi.visible = water_mi.visible
	_build_art()


func _hash01(i: int) -> float:
	var h: int = (i * 73856093) ^ (gen.seed_value * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xffff) / 65535.0


func tile_color(i: int) -> Color:
	match mode:
		Mode.BIOME:
			var b: int = gen.biome[i]
			var col: Color = WorldGen.BIOME_COLORS[b]
			var e: float = gen.elevation[i]
			if e < 0.0 and gen.is_lake[i] == 0:
				# 해저: 얕으면 모래빛, 깊을수록 어둡게 (수면을 통해 비쳐 보인다)
				if b == WorldGen.B.SEA_ICE:
					return col
				return Color("6fa0a0").lerp(Color("0e1d2e"), clampf(-e * 1.6, 0.0, 1.0))
			if gen.relief[i] == 2:
				col = col.lerp(WorldGen.ROCK_COLOR, 0.5)
				var tt: float = gen.temperature[i]
				if tt < -4.0:
					col = col.lerp(WorldGen.SNOWCAP_COLOR, clampf((-4.0 - tt) / 6.0, 0.35, 0.9))
			elif gen.relief[i] == 1:
				col = col.lerp(WorldGen.ROCK_COLOR, 0.12)
			var j: float = (_hash01(i) - 0.5) * 0.04
			return Color(col.r + j, col.g + j, col.b + j)
		Mode.ELEVATION:
			return elevation_color(gen.height_m(i))
		Mode.TEMPERATURE:
			return temp_color(gen.temperature[i])
		Mode.PRECIP:
			if gen.elevation[i] < 0.0:
				return Color("27374a").lerp(Color("3d5f80"), clampf(gen.precip[i] / 2500.0, 0.0, 1.0))
			return precip_color(gen.precip[i])
		Mode.PLATES:
			var pc: Color = gen.plate_color[gen.plate[i]]
			if gen.plate_oceanic[gen.plate[i]] == 1:
				pc = pc.darkened(0.35)
			var bd: float = gen.boundary[i]
			if bd > 0.05:
				pc = pc.lerp(Color("d1392b"), clampf(bd * 1.5, 0.3, 0.9))
			elif bd < -0.05:
				pc = pc.lerp(Color("37c6d8"), clampf(-bd * 1.5, 0.3, 0.9))
			return pc
		Mode.VEG:
			# 2층 식생만 칠하고, 시설물이 있으면 표시한다
			if gen.base[i] != TileLayers.Base.LAND and gen.veg[i] != TileLayers.Veg.ICE:
				return Color("6fa0a0").lerp(Color("0e1d2e"), clampf(-gen.elevation[i] * 1.6, 0.0, 1.0))
			var vc: Color = TileLayers.VEG_COLORS[gen.veg[i]]
			if gen.structure[i] != TileLayers.Struct.NONE:
				vc = Color("d9a13b") if gen.structure_state[i] == TileLayers.State.ACTIVE else Color("8a6d4a")
			elif gen.road[i] == 1:
				vc = vc.lerp(Color("c46a3a"), 0.6)
			return vc
		Mode.WIND:
			var pv: float = clampf(gen.pressure[i] * 0.5 + 0.5, 0.0, 1.0)
			var c2: Color = Color("3c5a8a").lerp(Color("c2a25c"), pv)
			if gen.elevation[i] >= 0.0:
				c2 = c2.lightened(0.15)
			return c2
	return Color.MAGENTA


static func elevation_color(h: float) -> Color:
	if h < 0.0:
		return Color("8fc3d6").lerp(Color("102a47"), clampf(-h / 6000.0, 0.0, 1.0))
	var stops := [[0.0, Color("4f7d3d")], [400.0, Color("8aa457")], [1000.0, Color("d6c97c")],
		[2000.0, Color("b0804a")], [3500.0, Color("7d5a43")], [5500.0, Color("f2f0ea")]]
	return _ramp(stops, h)


static func temp_color(t: float) -> Color:
	var stops := [[-30.0, Color("3b3f9e")], [-10.0, Color("6fa6d6")], [0.0, Color("e8f0f2")],
		[12.0, Color("e9d27a")], [22.0, Color("e2873c")], [32.0, Color("a8281f")]]
	return _ramp(stops, t)


static func precip_color(p: float) -> Color:
	var stops := [[0.0, Color("c9a566")], [300.0, Color("d9cc8a")], [700.0, Color("9bbd63")],
		[1400.0, Color("3f8f4d")], [2400.0, Color("2a6f8f")], [3500.0, Color("2a3f8f")]]
	return _ramp(stops, p)


static func _ramp(stops: Array, v: float) -> Color:
	if v <= stops[0][0]:
		return stops[0][1]
	for s in range(1, stops.size()):
		if v <= stops[s][0]:
			var a: float = stops[s - 1][0]
			var b: float = stops[s][0]
			return (stops[s - 1][1] as Color).lerp(stops[s][1], (v - a) / (b - a))
	return stops[stops.size() - 1][1]


func _build_lakes() -> void:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in hs.count:
		if gen.is_lake[i] == 0:
			continue
		var c: Vector3 = hs.centers[i]
		var r: float = lake_level(i)
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		var base: int = pos.size()
		pos.append(c * r)
		nrm.append(c)
		for k in deg:
			# 이웃 호수 쪽으로는 살짝 넓혀 틈을 없앤다
			pos.append((c + (hs.corner_list[off + k] - c) * 1.04).normalized() * r)
			nrm.append(c)
		for k in deg:
			idx.append_array([base, base + 1 + (k + 1) % deg, base + 1 + k])
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	lake_mi.mesh = m


## 타일 i 에서 이웃 j 쪽 변의 가운데 점 (지형 표면 위)
func _edge_mid(i: int, j: int) -> Vector3:
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	for k in deg:
		if hs.nb_list[off + k] == j:
			return (corner_pos(off + k) + corner_pos(off + (k + 1) % deg)) * 0.5
	return (hs.centers[i] * tile_radius[i] + hs.centers[j] * tile_radius[j]) * 0.5


## 방향 dir 이 가리키는 지형 표면 위의 점 (타일 부채꼴 삼각형 평면과의 교점)
func surface_point(dir: Vector3, hint: int) -> Vector3:
	var t: int = hs.find_tile(dir, hint)
	var c: Vector3 = hs.centers[t]
	var pc: Vector3 = c * tile_radius[t]
	var off: int = hs.nb_offsets[t]
	var deg: int = hs.degree(t)
	for k in deg:
		var a: Vector3 = corner_pos(off + k)
		var b: Vector3 = corner_pos(off + (k + 1) % deg)
		var s1: float = dir.dot(c.cross(a))
		var s2: float = dir.dot(a.cross(b))
		var s3: float = dir.dot(b.cross(c))
		if (s1 >= 0.0 and s2 >= 0.0 and s3 >= 0.0) or (s1 <= 0.0 and s2 <= 0.0 and s3 <= 0.0):
			var nn: Vector3 = (a - pc).cross(b - pc)
			var den: float = nn.dot(dir)
			if absf(den) > 1e-9:
				return dir * (nn.dot(pc) / den)
	return dir * tile_radius[t]


func _face_pos(f: int) -> Vector3:
	return hs.face_centers[f] * corner_radius[f]


static func _bez3(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return a * (u * u) + c * (2.0 * u * t) + b * (t * t)


## 경계 강: 칸의 변(꼭짓점에서 꼭짓점)을 따라 흐르되, 그리는 선은 부드럽게 굽이친다.
func _build_rivers() -> void:
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	var F: int = hs.face_centers.size()
	var max_flow: float = 1.0
	var main_up := PackedInt32Array()
	main_up.resize(F)
	main_up.fill(-1)
	for f in F:
		if gen.c_river[f] == 0:
			continue
		max_flow = maxf(max_flow, gen.c_flow[f])
		var d: int = gen.c_down[f]
		if d >= 0 and (main_up[d] < 0 or gen.c_flow[f] > gen.c_flow[main_up[d]]):
			main_up[d] = f
	var lift: float = 0.0016 * maxf(exaggeration, 0.5)
	var bank := _ArtBuf.new()
	var ruv := PackedVector2Array()
	var rcol := PackedColorArray()
	var tex: bool = _river_tex()
	# 강물 그림은 위아래 끝이 투명하므로 그만큼 넓혀 그린다
	var wk: float = 1.3 if tex else 1.0
	for f in F:
		if gen.c_river[f] == 0:
			continue
		var d: int = gen.c_down[f]
		if d < 0:
			continue
		# 칸의 변을 따라 흐르되, 위아래 물줄기와 부드럽게 이어지는 곡선에 불규칙한 굽이를 더한다.
		# 굽이는 양 끝(꼭짓점)에서 0 이고 기울기도 0 이라 이웃 구간과 어긋나지 않는다.
		var pts: Array = _river_curve(f, d, main_up, lift)
		var pf: Vector3 = pts[0]
		var w0: float = hs.spacing * (0.07 + 0.2 * sqrt(gen.c_flow[f] / max_flow))
		var w1: float = w0
		if gen.c_river[d] == 1:
			w1 = hs.spacing * (0.07 + 0.2 * sqrt(gen.c_flow[d] / max_flow))
		# 갈래가 만나는 꼭짓점은 둥근 이음매(원판)로 메운다
		_disc(pos, idx, pf, pf.normalized(), w0 * 0.5)
		_river_pad(ruv, rcol, pos.size(), f, tex)
		_river_piece(pos, idx, ruv, rcol, pts, w0 * wk, w1 * wk, 1.0, 1.0, f, tex)
		_bank_strip(bank, pts, w0 * 2.8, w1 * 2.8, -lift * 0.3)
		if gen.c_river[d] == 0:
			_river_mouth(pos, idx, ruv, rcol, bank, pts, f, d, w1, wk, lift, gen.c_flow[f] / max_flow, tex)
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_INDEX] = idx
		arr[Mesh.ARRAY_COLOR] = rcol
		if tex:
			arr[Mesh.ARRAY_TEX_UV] = ruv
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	river_mi.mesh = m
	river_bank_mi.mesh = bank.mesh()


## 강 조각 하나: 곡선을 따라 띠를 깔고, 그림 좌표와 투명도(a0 -> a1)를 붙인다.
func _river_piece(pos: PackedVector3Array, idx: PackedInt32Array, ruv: PackedVector2Array, rcol: PackedColorArray,
		pts: Array, w0: float, w1: float, a0: float, a1: float, seed: int, tex: bool) -> void:
	_strip(pos, idx, pts, w0, w1)
	var m: int = pts.size()
	for k in m:
		var t: float = float(k) / (m - 1)
		var a: float = lerpf(a0, a1, smoothstep(0.5, 1.0, t))
		rcol.append_array([Color(1, 1, 1, a), Color(1, 1, 1, a)])
		if tex:
			var x: float = lerpf(-0.98, 0.98, t)
			ruv.append(tile_art.decals.uv("decal/river", x, -0.98, seed))
			ruv.append(tile_art.decals.uv("decal/river", x, 0.98, seed))


## 원판처럼 그림 좌표 없이 더한 꼭짓점을 강 한가운데 색으로 채운다.
func _river_pad(ruv: PackedVector2Array, rcol: PackedColorArray, n: int, seed: int, tex: bool) -> void:
	while rcol.size() < n:
		rcol.append(Color.WHITE)
		if tex:
			ruv.append(tile_art.decals.uv("decal/river", 0.0, 0.0, seed))


## 하구: 강이 끝나는 꼭짓점(d)은 물 칸과 닿아 있고, 바닥 합성에서 물이 이 꼭짓점까지 파고들어 온다 (_build_surface).
## 강은 거기서 물 쪽으로 조금 더 들어가 물빛으로 스며든다.
## 큰 강은 삼각주: 마지막 구간 중간에서 갈라져, 강 좌우의 땅 칸 위를 지나 양옆 해안선(물 칸과 땅 칸 사이 변의 가운데)으로
## 흘러든다. 갈래 밑에는 모래·갯벌 띠를 넓게 깔아, 바다 위가 아니라 땅 쪽에 삼각주가 생긴다.
func _river_mouth(pos: PackedVector3Array, idx: PackedInt32Array, ruv: PackedVector2Array, rcol: PackedColorArray,
		bank: _ArtBuf, pts: Array, f: int, d: int, w: float, wk: float, lift: float, flow: float, tex: bool) -> void:
	var pd: Vector3 = pts[pts.size() - 1]
	var up: Vector3 = pd.normalized()
	var r: float = pd.length()
	var target := Vector3.ZERO
	var nw: int = 0
	for q in 3:
		var t: int = hs.face_tiles[d * 3 + q]
		if _is_water_tile(t):
			target += hs.centers[t]
			nw += 1
	if nw == 0:
		return
	target = (target / nw).normalized() * r
	var into: Vector3 = target - pd
	into -= up * into.dot(up)
	var reach: float = into.length()
	if reach < 1e-6:
		return
	var dw: Vector3 = into / reach
	# 본류: 꼭짓점에서 물 쪽으로 조금 더, 넓어지며 스며든다
	_river_tail(pos, idx, ruv, rcol, pd, dw, reach * 0.45, w, wk, r, d, tex)
	# 삼각주는 강 좌우가 모두 땅이고 물 칸이 앞에 하나만 있을 때 (강이 해안을 따라 흐르는 경우는 빼고)
	if flow <= 0.3 or nw != 1:
		return
	# 삼각주 갈래: 마지막 구간 중간에서 갈라져 양옆 해안선으로
	var fork: Vector3 = pts[int(pts.size() * 0.4)]
	var wb: float = w * 0.6
	var bi: int = 0
	for e in 3:
		var g: int = hs.face_nb[d * 3 + e]
		if g < 0 or g == f:
			continue
		# d-g 변이 물 칸과 땅 칸 사이(해안선)인지
		var shared: Array = []
		for q in 3:
			var t: int = hs.face_tiles[d * 3 + q]
			for q2 in 3:
				if hs.face_tiles[g * 3 + q2] == t:
					shared.append(t)
		if shared.size() != 2 or _is_water_tile(shared[0]) == _is_water_tile(shared[1]):
			continue
		var end: Vector3 = ((pd + _face_pos(g)) * 0.5).normalized() * r
		var ctrl: Vector3 = (fork + pd) * 0.5
		var bp: Array = []
		var n: int = 8
		var side: Vector3 = (end - fork).cross(up).normalized()
		for k in n + 1:
			var t: float = float(k) / n
			var c: Vector3 = _bez3(fork, ctrl, end, t)
			c += side * sin(PI * t) * sin(PI * t * 2.0 + float(bi)) * reach * 0.05
			bp.append(c.normalized() * r)
		_disc(pos, idx, fork, fork.normalized(), wb * 0.5)
		_river_pad(ruv, rcol, pos.size(), d, tex)
		_river_piece(pos, idx, ruv, rcol, bp, wb * wk, wb * wk * 1.2, 1.0, 1.0, d + 7 + bi, tex)
		# 삼각주 땅: 갈래 밑을 넓은 모래·갯벌 띠로
		_bank_strip(bank, bp, wb * 4.5, wb * 3.5, -lift * 0.3, 0.25)
		var out: Vector3 = end - bp[n - 1]
		out -= up * out.dot(up)
		_river_tail(pos, idx, ruv, rcol, end, (out.normalized() + dw).normalized(), reach * 0.35, wb, wk, r, d + 11 + bi, tex)
		bi += 1
	if bi > 0:
		# 갈래 사이 본류 둘레도 넓게
		_bank_strip(bank, pts.slice(int(pts.size() * 0.4)), w * 3.5, w * 4.5, -lift * 0.3, 0.25)


## 강 끝에서 물 쪽으로 넓어지며 사라지는 짧은 꼬리
func _river_tail(pos: PackedVector3Array, idx: PackedInt32Array, ruv: PackedVector2Array, rcol: PackedColorArray,
		p: Vector3, dir: Vector3, len: float, w: float, wk: float, r: float, seed: int, tex: bool) -> void:
	var tp: Array = []
	for k in 5:
		tp.append((p + dir * len * float(k) / 4.0).normalized() * r)
	_disc(pos, idx, p, p.normalized(), w * 0.5)
	_river_pad(ruv, rcol, pos.size(), seed, tex)
	_river_piece(pos, idx, ruv, rcol, tp, w * wk, w * wk * 1.8, 1.0, 0.0, seed, tex)


func _is_water_tile(t: int) -> bool:
	return gen.elevation[t] < 0.0 or gen.is_lake[t] == 1


const RIVER_STEPS := 10

## f 꼭짓점에서 d 꼭짓점까지의 강 곡선. 위쪽 본류와 아래쪽 물줄기를 함께 보고
## Catmull-Rom 으로 이어 꺾임을 없애고, 구간마다 정해진 굽이를 옆으로 더한다.
func _river_curve(f: int, d: int, main_up: PackedInt32Array, lift: float) -> Array:
	var pf: Vector3 = _face_pos(f)
	var pd: Vector3 = _face_pos(d)
	var rf: float = maxf(pf.length(), 1.0) + lift
	var rd: float = maxf(pd.length(), 1.0) + lift
	var u: int = main_up[f]
	var p0: Vector3 = _face_pos(u) if u >= 0 else pf * 2.0 - pd
	var dd: int = gen.c_down[d] if gen.c_river[d] == 1 else -1
	var p3: Vector3 = _face_pos(dd) if dd >= 0 else pd * 2.0 - pf
	var up: Vector3 = (pf + pd).normalized()
	var side: Vector3 = (pd - pf).cross(up)
	if side.length_squared() > 1e-14:
		side = side.normalized()
	var h: int = hash(Vector2i(f, d))
	var s1: float = float(h & 1023) / 511.5 - 1.0
	var s2: float = float((h >> 10) & 1023) / 511.5 - 1.0
	var amp: float = hs.spacing * 0.16
	var pts: Array = []
	for k in RIVER_STEPS + 1:
		var t: float = float(k) / RIVER_STEPS
		var c: Vector3 = _catmull(p0, pf, pd, p3, t)
		var env: float = sin(PI * t)
		env *= env
		c += side * amp * env * (s1 * 0.8 + s2 * 0.9 * cos(PI * t))
		pts.append(c.normalized() * lerpf(rf, rd, t))
	return pts


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	# 구간 길이가 크게 다를 때 튀지 않도록 바깥 점을 이 구간 길이로 맞춘다
	var l: float = p1.distance_to(p2)
	var a: Vector3 = p1 + (p0 - p1).normalized() * l if (p0 - p1).length_squared() > 1e-14 else p1 * 2.0 - p2
	var b: Vector3 = p2 + (p3 - p2).normalized() * l if (p3 - p2).length_squared() > 1e-14 else p2 * 2.0 - p1
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-a + p2) * t + (2.0 * a - 5.0 * p1 + 4.0 * p2 - b) * t2 + (-a + 3.0 * p1 - 3.0 * p2 + b) * t3)


func _river_tex() -> bool:
	return tile_art != null and tile_art.decals.has("decal/river")


func _strip(pos: PackedVector3Array, idx: PackedInt32Array, pts: Array, w0: float, w1: float) -> void:
	var m: int = pts.size()
	var base: int = pos.size()
	for k in m:
		var p: Vector3 = pts[k]
		var a: Vector3 = pts[maxi(k - 1, 0)]
		var b: Vector3 = pts[mini(k + 1, m - 1)]
		var side: Vector3 = (b - a).cross(p.normalized())
		if side.length_squared() < 1e-14:
			side = Vector3.UP.cross(p).normalized()
		side = side.normalized() * lerpf(w0, w1, float(k) / (m - 1)) * 0.5
		pos.append(p - side)
		pos.append(p + side)
	for k in m - 1:
		var v: int = base + k * 2
		idx.append_array([v, v + 1, v + 3, v, v + 3, v + 2])


func _ribbon(pos: PackedVector3Array, idx: PackedInt32Array, a: Vector3, b: Vector3, w: float) -> void:
	var dir: Vector3 = b - a
	if dir.length_squared() < 1e-12:
		return
	var up: Vector3 = ((a + b) * 0.5).normalized()
	var side: Vector3 = dir.cross(up)
	if side.length_squared() < 1e-12:
		return
	side = side.normalized() * w * 0.5
	var s: int = pos.size()
	pos.append_array([a - side, a + side, b + side, b - side])
	idx.append_array([s, s + 1, s + 2, s, s + 2, s + 3])


func _disc(pos: PackedVector3Array, idx: PackedInt32Array, c: Vector3, nrm: Vector3, r: float) -> void:
	var t: Vector3 = nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
	var b: Vector3 = nrm.cross(t)
	var s: int = pos.size()
	pos.append(c)
	for k in 16:
		var a: float = TAU * k / 16.0
		pos.append(c + (t * cos(a) + b * sin(a)) * r)
	for k in 16:
		idx.append_array([s, s + 1 + k, s + 1 + (k + 1) % 16])


## 타일 경계선. 육지 위에만 그린다. 1 픽셀 선은 바닥 그림에 묻혀 안 보이므로 얇은 띠로 그린다.
func _build_grid() -> void:
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	var lift: float = 0.0012
	var w: float = hs.spacing * 0.03
	for i in hs.count:
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		var land_i: bool = gen.elevation[i] >= 0.0 and gen.is_lake[i] == 0
		for k in deg:
			var j: int = hs.nb_list[off + k]
			if j < i:
				continue
			var land_j: bool = gen.elevation[j] >= 0.0 and gen.is_lake[j] == 0
			if not (land_i or land_j):
				continue
			var a: Vector3 = corner_pos(off + k)
			var b: Vector3 = corner_pos(off + (k + 1) % deg)
			_ribbon(pos, idx, a + a.normalized() * lift, b + b.normalized() * lift, w)
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	grid_mi.mesh = m


func _build_wind() -> void:
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	var step: int = maxi(1, int(pow(4.0, hs.level - 3)))
	var len: float = hs.spacing * 0.9 * maxf(1.0, sqrt(float(step)))
	for i in range(0, hs.count, step):
		var w: Vector3 = gen.wind[i]
		var spd: float = w.length()
		if spd < 0.05:
			continue
		var c: Vector3 = hs.centers[i] * (maxf(tile_radius[i], 1.0) + 0.006)
		var dirv: Vector3 = w.normalized()
		var tip: Vector3 = c + dirv * len * (0.4 + 0.6 * spd)
		var side: Vector3 = dirv.cross(hs.centers[i]).normalized() * len * 0.18
		var back: Vector3 = tip - dirv * len * 0.3
		var col := Color(1, 1, 1).lerp(Color("ffd36b"), spd)
		pos.append_array([c, tip, tip, back + side, tip, back - side])
		for _q in 6:
			cols.append(col)
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_COLOR] = cols
		m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	wind_mi.mesh = m


func set_hover(i: int) -> void:
	if i < 0:
		hover_mi.mesh = null
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	for k in deg + 1:
		var p: Vector3 = corner_pos(off + k % deg)
		p = p.normalized() * maxf(p.length(), 1.0)
		im.surface_add_vertex(p + p.normalized() * 0.0015)
	im.surface_end()
	hover_mi.mesh = im


# ---------------------------------------------------------------- 타일 위 그림

func _build_art() -> void:
	var show: bool = art_enabled and (mode == Mode.BIOME or mode == Mode.VEG)
	# 칸이 화면에서 작아지면 흐려지다 사라지게 (먼 거리에서 투명, 가까우면 불투명)
	var px_per_unit: float = 900.0 / (2.0 * tan(deg_to_rad(20.0)))
	var far_d: float = hs.spacing * px_per_unit / ART_MIN_PX
	var near_d: float = hs.spacing * px_per_unit / ART_FULL_PX
	surface_mi.visible = show
	for mi in [art_veg_mi, art_road_mi, art_struct_mi, art_shadow_mi, art_sprite_mi, river_bank_mi]:
		mi.visible = show
		if mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = mi.material_override
			m.distance_fade_min_distance = far_d
			m.distance_fade_max_distance = near_d
	_sprite_mat.set_shader_parameter("near_d", near_d)
	_sprite_mat.set_shader_parameter("far_d", far_d)
	_surface_mat.set_shader_parameter("near_d", near_d)
	_surface_mat.set_shader_parameter("far_d", far_d)
	# 바닥 무늬 한 장이 칸 두 개쯤을 덮도록
	_surface_mat.set_shader_parameter("tex_scale", 1.0 / (hs.spacing * 2.0))
	if not show:
		return
	_build_surface()
	var veg := _ArtBuf.new()
	var road := _ArtBuf.new()
	var st := _ArtBuf.new()
	var shadow := _ArtBuf.new()
	var spr := _ArtBuf.new()
	var D: TileArt.Atlas = tile_art.decals
	for i in hs.count:
		var seed: int = TileArt.tile_seed(gen, i, 2)
		var vk: String = TileArt.veg_key(gen, i)
		if vk != "" and D.has("decal/" + vk):
			_art_fan(veg, i, "decal/" + vk, 0.0, 0.0006, Color.WHITE, seed)
		_art_roads(road, i)
		var sk: String = TileArt.struct_key(gen, i)
		if sk != "" and D.has("decal/" + sk):
			var tint: Color = TileArt.IDLE_TINT if gen.structure_state[i] == TileLayers.State.IDLE else Color.WHITE
			_art_fan(st, i, "decal/" + sk, 0.0, 0.0012, tint, seed)
		for e in TileArt.sprites_for(gen, i):
			_art_sprite(spr, shadow, i, e[0], e[1], e[2], e[3], e[4], e[5])
	art_veg_mi.mesh = veg.mesh()
	art_road_mi.mesh = road.mesh()
	art_struct_mi.mesh = st.mesh()
	art_shadow_mi.mesh = shadow.mesh()
	art_sprite_mi.mesh = spr.mesh(true)


func _make_noise() -> ImageTexture:
	var fn := FastNoiseLite.new()
	fn.seed = 7
	fn.frequency = 0.02
	fn.fractal_octaves = 3
	var img: Image = fn.get_seamless_image(256, 256)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## 물 칸이 하나라도 닿은 점은 수면 높이로 올린다
func _water_level_at(tiles: Array) -> float:
	var wl: float = -1.0
	for t in tiles:
		if gen.base[t] != TileLayers.Base.LAND:
			wl = maxf(wl, lake_level(t) if gen.is_lake[t] == 1 else 1.0)
	return wl


func _lifted(p: Vector3, tiles: Array) -> Vector3:
	var r: float = p.length()
	var wl: float = _water_level_at(tiles)
	if wl > 0.0:
		r = maxf(r, wl)
	return p / p.length() * (r + 0.0003)


## 꼭짓점 조합 바닥: 꼭짓점(면) f 마다 세 칸 a, b, c 의 가운데와 변 가운데로 이루어진 육각형(삼각형 6개)을
## 만든다. 각 조각은 그 칸의 부채꼴 지형 위에 정확히 놓인다.
func _build_surface() -> void:
	var sig := PackedInt32Array()
	sig.resize(hs.count * 2)
	for i in hs.count:
		sig[i * 2] = tile_art.class_layer(gen, i)
		sig[i * 2 + 1] = tile_art.shore_layer(gen, i)
	if sig == _surface_sig and surface_mi.mesh != null:
		return
	_surface_sig = sig
	var F: int = hs.face_centers.size()
	var nv: int = F * 7
	var pos := PackedVector3Array()
	pos.resize(nv)
	var nrm := PackedVector3Array()
	nrm.resize(nv)
	var col := PackedColorArray()
	col.resize(nv)
	var uv := PackedVector2Array()
	uv.resize(nv)
	var c0 := PackedFloat32Array()
	c0.resize(nv * 4)
	var c1 := PackedFloat32Array()
	c1.resize(nv * 4)
	var idx := PackedInt32Array()
	idx.resize(F * 18)
	var C: TileArt.Atlas = tile_art.combos
	var has_combo: bool = C.count > 0
	# 조합 완성 그림 위 삼각형 꼭짓점 (위, 왼쪽 아래, 오른쪽 아래)
	var img_v: Array = [Vector2(0.0, 0.86), Vector2(-0.86, -0.63), Vector2(0.86, -0.63)]
	# 강이 물로 드는 꼭짓점
	var mouth := PackedByteArray()
	mouth.resize(F)
	for g in F:
		var dd: int = gen.c_down[g]
		if gen.c_river[g] == 1 and dd >= 0 and gen.c_river[dd] == 0:
			mouth[dd] = 1
	for f in F:
		var t: Array = [hs.face_tiles[f * 3], hs.face_tiles[f * 3 + 1], hs.face_tiles[f * 3 + 2]]
		var ctr: Array = [hs.centers[t[0]], hs.centers[t[1]], hs.centers[t[2]]]
		# 바깥에서 보아 반시계 방향으로
		if (ctr[1] - ctr[0]).cross(ctr[2] - ctr[0]).dot(hs.face_centers[f]) < 0.0:
			t = [t[0], t[2], t[1]]
			ctr = [ctr[0], ctr[2], ctr[1]]
		var pf: Vector3 = _lifted(_face_pos(f), t)
		var cp: Array = []
		for q in 3:
			var ti: int = t[q]
			cp.append(_lifted(hs.centers[ti] * tile_radius[ti], [ti]))
		var mp: Array = []
		for q in 3:
			var ta: int = t[q]
			var tb: int = t[(q + 1) % 3]
			# 칸 ta 와 tb 사이 변의 반대쪽 끝 꼭짓점
			var g: int = -1
			for e in 3:
				var h: int = hs.face_nb[f * 3 + e]
				if h < 0:
					continue
				var ht: PackedInt32Array = hs.face_tiles.slice(h * 3, h * 3 + 3)
				if ht.has(ta) and ht.has(tb):
					g = h
					break
			var other: Vector3 = _face_pos(g) if g >= 0 else _face_pos(f)
			mp.append(_lifted((_face_pos(f) + other) * 0.5, [ta, tb]))
		var la: Array = [sig[t[0] * 2], sig[t[1] * 2], sig[t[2] * 2]]
		var sa: Array = [sig[t[0] * 2 + 1], sig[t[1] * 2 + 1], sig[t[2] * 2 + 1]]
		var ckey: String = ""
		var crot: int = 0
		if has_combo:
			var cn: Array = TileArt.combo_name(TileArt.surface_class(gen, t[0]), TileArt.surface_class(gen, t[1]), TileArt.surface_class(gen, t[2]))
			if C.has(cn[0]):
				ckey = cn[0]
				crot = cn[1]
		var base: int = f * 7
		# 0: 꼭짓점, 1..3: 칸 가운데, 4..6: 변 가운데 (q 와 q+1 사이)
		var pts: Array = [pf, cp[0], cp[1], cp[2], mp[0], mp[1], mp[2]]
		var ws: Array = [Vector3(1, 1, 1) / 3.0, Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
			Vector3(0.5, 0.5, 0), Vector3(0, 0.5, 0.5), Vector3(0.5, 0, 0.5)]
		if mouth[f] == 1:
			# 강 하구 꼭짓점: 물이 꼭짓점까지 파고들어(만) 강 끝과 바로 이어지게 한다.
			# 꼭짓점(0번)의 무게만 물 칸 쪽으로 몰고, 이웃 삼각형과 맞닿은 변 가운데 점은 그대로 둔다.
			var wc := Vector3.ZERO
			for q in 3:
				wc[q] = 1.0 if _is_water_tile(t[q]) else 0.25
			ws[0] = wc / (wc.x + wc.y + wc.z)
		elif gen.c_river[f] == 1:
			# 강이 지나는 꼭짓점은 땅으로 남겨, 물가 합성이 강을 물에 잠기게 하지 않는다
			var wl := Vector3.ZERO
			for q in 3:
				wl[q] = 0.25 if _is_water_tile(t[q]) else 1.0
			ws[0] = wl / (wl.x + wl.y + wl.z)
		for v in 7:
			var p: Vector3 = pts[v]
			var w: Vector3 = ws[v]
			pos[base + v] = p
			nrm[base + v] = p.normalized()
			col[base + v] = Color(w.x, w.y, w.z)
			var o: int = (base + v) * 4
			c0[o] = la[0]
			c0[o + 1] = la[1]
			c0[o + 2] = la[2]
			c0[o + 3] = 1.0 if ckey != "" else 0.0
			c1[o] = sa[0]
			c1[o + 1] = sa[1]
			c1[o + 2] = sa[2]
			if ckey != "":
				# 슬롯 q 가 그림의 (q - 돌린 수) 번째 꼭짓점
				var ip := Vector2.ZERO
				for q in 3:
					ip += img_v[posmod(q - crot, 3)] * w[q]
				uv[base + v] = C.uv(ckey, ip.x, ip.y, f)
		# 앞면이 바깥을 향하도록 (Godot 는 시계 방향이 앞면)
		var tris: Array = [0, 4, 1, 0, 2, 4, 0, 5, 2, 0, 3, 5, 0, 6, 3, 0, 1, 6]
		for q in 18:
			idx[f * 18 + q] = base + tris[q]
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	var fl: int = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fl)
	surface_mi.mesh = m


## 칸 i 의 점 (x, y) (칸 좌표, 꼭짓점까지 1) 아래 지형 표면 위치
func _art_ground(i: int, x: float, y: float) -> Vector3:
	var c: Vector3 = hs.centers[i]
	var fr: Array = _tile_frame(i)
	var dir: Vector3 = (c + (fr[0] * x + fr[1] * y) * _tile_rad(i)).normalized()
	var p: Vector3 = surface_point(dir, i)
	if gen.base[i] != TileLayers.Base.LAND:
		p = dir * (lake_level(i) if gen.is_lake[i] == 1 else maxf(p.length(), 1.0))
	return p


func _tile_rad(i: int) -> float:
	var c: Vector3 = hs.centers[i]
	var rad := 0.0
	for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
		rad = maxf(rad, (hs.corner_list[k] - c).length())
	return rad


## 세운 그림 하나: 바닥 점에 네 꼭짓점을 모아 두고, 셰이더가 카메라를 향해 펼친다.
## 발밑에는 납작한 그림자를 깐다.
func _art_sprite(buf: _ArtBuf, shadow: _ArtBuf, i: int, key: String, x: float, y: float, size: float, tint: Color, seed: int) -> void:
	if not tile_art.sprites.has(key):
		return
	var p: Vector3 = _art_ground(i, x, y)
	var w: float = size * _tile_rad(i)
	var S: TileArt.Atlas = tile_art.sprites
	var base: int = buf.pos.size()
	var up: Vector3 = p.normalized()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		buf.pos.append(p)
		buf.nrm.append(up)
		buf.col.append(tint)
		buf.uv.append(S.uv(key, corner.x, corner.y, seed))
		# 바닥 점 기준 펼칠 거리 (가로는 가운데 기준, 세로는 아래 끝 기준)
		buf.uv2.append(Vector2(corner.x * 0.5 * w, (corner.y * 0.5 + 0.5) * w))
	buf.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if tile_art.decals.has("decal/shadow"):
		var fr: Array = _tile_frame(i)
		var e: Vector3 = fr[0] * w * 0.42
		var n: Vector3 = fr[1] * w * 0.26
		var c: Vector3 = p + up * 0.0013 + fr[0] * w * 0.08 - fr[1] * w * 0.04
		var sb: int = shadow.pos.size()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			shadow.pos.append(c + e * corner.x + n * corner.y)
			shadow.nrm.append(up)
			shadow.col.append(Color.WHITE)
			shadow.uv.append(tile_art.decals.uv("decal/shadow", corner.x, corner.y))
		shadow.tri(sb, sb + 2, sb + 1)
		shadow.tri(sb, sb + 3, sb + 2)


## 강줄기 아래 흙둑 띠. 강 곡선을 그대로 따라간다.
func _bank_strip(buf: _ArtBuf, pts: Array, w0: float, w1: float, lift: float, fade: float = 0.0) -> void:
	if not tile_art.decals.has("decal/river_bank"):
		return
	var m: int = pts.size()
	var ext: Vector3 = (pts[1] - pts[0]).normalized() * w0 * 0.25
	var ext2: Vector3 = (pts[m - 1] - pts[m - 2]).normalized() * w1 * 0.25
	var seed: int = int(pts[0].x * 1e5)
	var base: int = buf.pos.size()
	for k in m:
		var p: Vector3 = pts[k]
		if k == 0:
			p -= ext
		elif k == m - 1:
			p += ext2
		var a: Vector3 = pts[maxi(k - 1, 0)]
		var b: Vector3 = pts[mini(k + 1, m - 1)]
		var up: Vector3 = p.normalized()
		var side: Vector3 = (b - a).cross(up)
		if side.length_squared() < 1e-14:
			return
		side = side.normalized() * lerpf(w0, w1, float(k) / (m - 1)) * 0.5
		p += up * lift
		var x: float = lerpf(-0.98, 0.98, float(k) / (m - 1))
		buf.pos.append_array([p - side, p + side])
		buf.nrm.append_array([up, up])
		# fade > 0 이면 끝쪽 그만큼을 점점 투명하게 (물속으로 스며드는 삼각주, 하구 둑)
		var fa: float = 1.0
		if fade > 0.0:
			fa = 1.0 - smoothstep(1.0 - fade, 1.0, float(k) / (m - 1))
		buf.col.append_array([Color(1, 1, 1, fa), Color(1, 1, 1, fa)])
		buf.uv.append(tile_art.decals.uv("decal/river_bank", x, -0.98, seed))
		buf.uv.append(tile_art.decals.uv("decal/river_bank", x, 0.98, seed))
	for k in m - 1:
		var v: int = base + k * 2
		buf.tri(v, v + 1, v + 3)
		buf.tri(v, v + 3, v + 2)


func _art_roads(buf: _ArtBuf, i: int) -> void:
	var is_road: bool = gen.road[i] == 1
	var is_district: bool = TileArt.road_link(gen, i) and not is_road
	if not (is_road or is_district) or not tile_art.decals.has("decal/road"):
		return
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	var any := false
	for k in deg:
		var j: int = hs.nb_list[off + k]
		# 도로 칸은 이어진 모든 방향으로, 정착지 구역은 도로 칸 쪽으로만 갈래를 낸다
		var linked: bool = TileArt.road_link(gen, j) if is_road else gen.road[j] == 1
		if not linked:
			continue
		any = true
		var mid: Vector3 = (hs.corner_list[off + k] + hs.corner_list[off + (k + 1) % deg]).normalized()
		var fr: Array = _tile_frame(i)
		var d: Vector3 = mid - hs.centers[i]
		_art_fan(buf, i, "decal/road", atan2(d.dot(fr[1]), d.dot(fr[0])), 0.0009, Color.WHITE)
	if is_road and not any and tile_art.decals.has("decal/road_alone"):
		_art_fan(buf, i, "decal/road_alone", 0.0, 0.0009, Color.WHITE)


## 칸 중심의 접평면 좌표축 [동, 북]
func _tile_frame(i: int) -> Array:
	var c: Vector3 = hs.centers[i]
	var north: Vector3 = Vector3.UP - c * c.y
	if north.length_squared() < 1e-8:
		north = Vector3.BACK - c * c.z
	north = north.normalized()
	return [north.cross(c).normalized(), north]


## 칸 i 를 덮는 부채꼴에 그림 key 를 붙인다. angle 만큼 그림을 돌린다 (그림의 +x 가 그 방향).
func _art_fan(buf: _ArtBuf, i: int, key: String, angle: float, lift: float, tint: Color, seed: int = 0) -> void:
	var c: Vector3 = hs.centers[i]
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	var fr: Array = _tile_frame(i)
	var east: Vector3 = fr[0]
	var north: Vector3 = fr[1]
	var rad := 0.0
	for k in deg:
		rad = maxf(rad, (hs.corner_list[off + k] - c).length())
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var on_water: bool = gen.base[i] != TileLayers.Base.LAND
	var wr: float = lake_level(i) if gen.is_lake[i] == 1 else maxf(tile_radius[i], 1.0)
	var base: int = buf.pos.size()
	for k in deg + 1:
		var p: Vector3
		var dir: Vector3
		if k == 0:
			dir = c
			p = c * (wr if on_water else tile_radius[i])
		else:
			dir = hs.corner_list[off + k - 1]
			p = dir * wr if on_water else corner_pos(off + k - 1)
		p += p.normalized() * lift
		var d: Vector3 = dir - c
		var x: float = d.dot(east) / rad
		var y: float = d.dot(north) / rad
		buf.pos.append(p)
		buf.nrm.append(p.normalized())
		buf.col.append(tint)
		buf.uv.append(tile_art.decals.uv(key, x * ca + y * sa, -x * sa + y * ca, seed))
	for k in deg:
		buf.idx.append_array([base, base + 1 + (k + 1) % deg, base + 1 + k])


class _ArtBuf:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	## 바깥(행성 밖)을 향하도록 감는 방향을 맞춰 삼각형을 넣는다
	func tri(a: int, b: int, c: int) -> void:
		var n: Vector3 = (pos[b] - pos[a]).cross(pos[c] - pos[a])
		if n.dot(pos[a]) < 0.0:
			idx.append_array([a, b, c])
		else:
			idx.append_array([a, c, b])

	func mesh(with_uv2: bool = false) -> ArrayMesh:
		var m := ArrayMesh.new()
		if pos.is_empty():
			return m
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_TEX_UV] = uv
		if with_uv2:
			arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
