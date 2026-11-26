class_name TileArt
extends RefCounted
## 타일 위 그림. 문명3 처럼 상황마다 다른 2D 그림을 골라 쓰는 틀이다.
##
## 그림은 art/tiles/ 아래 폴더에 파일을 넣기만 하면 읽는다 (목록을 코드에 적지 않는다).
## 파일 이름 규칙 (자세한 내용은 art/tiles/README.md):
##
##   이름.svg, 이름.2.svg, 이름.3.svg ...   같은 그림의 변주. 칸마다 정해진 하나를 고른다.
##   A_B_C.svg (combo/)                     세 칸이 만나는 꼭짓점의 조합 완성 그림
##
## 바닥은 칸마다 따로 칠하지 않고, 세 칸이 만나는 꼭짓점마다 그 세 칸의 조합으로 한 장의 그림을
## 만든다 (문명3 가 네 칸 꼭짓점마다 조합 그림을 쓰는 방식의 육각형판). 그래서 칸 경계에 직선 이음매가
## 생기지 않고, 땅·물·물가·물거품이 한 그림 안에서 섞인다. combo/ 에 그 조합의 완성 그림이 있으면
## 그 그림을 쓰고, 없으면 바닥 무늬로 자동 합성한다.
##
## 폴더:
##   ground/  바닥 무늬 (이음매 없이 반복): 땅(grass ...), 물(deep, shallow, lake, ice), 물가 땅(shore_sand ...)
##   combo/   꼭짓점 조합 완성 그림 (선택). 없으면 자동 합성.
##   decal/   칸 위에 깔리는 그림 (식생 바닥, 밭, 광장, 도로, 그림자, 강둑, 강물)
##   sprite/  세워 그리는 그림 (나무, 집, 천막 ...)
## SVG 와 PNG 를 모두 쓸 수 있다. 같은 이름의 PNG 가 있으면 SVG 대신 쓴다.

const ART_DIR := "res://art/tiles/"

## 시설 종류 -> 그림 이름 (TileLayers.Struct 순서)
const STRUCT_ART := ["", "farm", "district", "shrine", "mine", "lumber", "irrigation", "camp", "fishery"]

## 시설마다 세울 그림: [그림, x, y, 크기]. 좌표는 칸 중심 0, 꼭짓점까지 1, y 는 북쪽.
## 크기는 그림 정사각형의 너비 (같은 단위). 그림 이름에 변주가 있으면 하나씩 골라 쓴다.
const STRUCT_SPRITES := {
	"farm": [["haystack", 0.38, -0.05, 0.22], ["haystack", 0.5, 0.06, 0.18]],
	"district": [["house", -0.4, 0.38, 0.4], ["house", 0.36, 0.42, 0.4], ["tower", 0.0, 0.18, 0.62],
		["house", -0.56, -0.02, 0.4], ["house", 0.56, 0.0, 0.4], ["house", -0.18, -0.2, 0.4],
		["house", 0.24, -0.26, 0.4], ["house", -0.36, -0.5, 0.4], ["house", 0.34, -0.56, 0.4]],
	"shrine": [["temple", 0.0, -0.1, 0.9]],
	"mine": [["mine", 0.0, 0.0, 0.85], ["rock", -0.5, -0.3, 0.2]],
	"lumber": [["hut", -0.18, 0.06, 0.42], ["logs", 0.34, -0.22, 0.38]],
	"camp": [["tent", -0.3, 0.26, 0.42], ["tent", 0.34, 0.2, 0.42], ["fire", 0.0, -0.08, 0.18],
		["tent", -0.36, -0.36, 0.42], ["tent", 0.24, -0.46, 0.42]],
	"fishery": [["boat", 0.0, -0.48, 0.5]],
	"ruin": [["ruin_wall", -0.36, 0.2, 0.45], ["ruin_wall", 0.34, 0.36, 0.38], ["ruin_column", -0.05, -0.08, 0.3],
		["ruin_column", 0.22, -0.22, 0.22]],
}

## 방치된 시설은 조금 어둡고 바랜 색으로
const IDLE_TINT := Color(0.72, 0.68, 0.62)

## 물 무늬 (이 순서대로 ground_tex 의 맨 뒤에 놓인다. 셰이더가 water_start 이후를 물로 본다)
const WATER_CLASSES := ["deep", "shallow", "lake"]

var ground_tex: Texture2DArray
var water_start: int = 0          # ground_tex 에서 물 무늬가 시작하는 층
var _ground_layers := {}          # 바닥 이름 -> [층 번호...]
## decal 폴더. 이름은 "decal/이름"
var decals := Atlas.new(256, 10)
var sprites := Atlas.new(128, 8)
## combo 폴더: 꼭짓점 조합 완성 그림. 이름은 "A_B_C"
var combos := Atlas.new(256, 8)


## art/tiles/ 의 그림을 모두 읽는다.
func load_all() -> void:
	var flat := {}
	for e in scan("decal"):
		flat["decal/" + e[0]] = e[1]
	decals.build(flat)
	var cmb := {}
	for e in scan("combo"):
		cmb[e[0]] = e[1]
	combos.build(cmb)
	var spr := {}
	for e in scan("sprite"):
		spr[e[0]] = e[1]
	sprites.build(spr)
	var imgs: Array[Image] = []
	# 물 무늬를 맨 뒤로
	var entries: Array = scan("ground")
	var land_e: Array = []
	var water_e: Array = []
	for e in entries:
		(water_e if WATER_CLASSES.has(Atlas.base_name(e[0])) else land_e).append(e)
	water_start = -1
	for e in land_e + water_e:
		if water_start < 0 and water_e.has(e):
			water_start = imgs.size()
		var img: Image = Atlas.load_image(e[1], 256)
		if img == null:
			continue
		img.generate_mipmaps()
		var key: String = Atlas.base_name(e[0])
		if not _ground_layers.has(key):
			_ground_layers[key] = []
		_ground_layers[key].append(imgs.size())
		imgs.append(img)
	if water_start < 0:
		water_start = imgs.size()
	if imgs.is_empty():
		var blank := Image.create_empty(4, 4, true, Image.FORMAT_RGBA8)
		blank.fill(Color(0.5, 0.5, 0.5))
		imgs.append(blank)
	ground_tex = Texture2DArray.new()
	ground_tex.create_from_images(imgs)


## 폴더 안의 그림 파일: [[파일 이름(확장자 뺀 것), 경로], ...] 이름순.
## 내보낸 게임에서는 원본 대신 .import 파일만 보이므로 그 이름도 받아들인다.
static func scan(folder: String) -> Array:
	var dir_path: String = ART_DIR + folder + "/"
	var found := {}
	for f in DirAccess.get_files_at(dir_path):
		var name: String = f.trim_suffix(".import").trim_suffix(".remap")
		var ext: String = name.get_extension().to_lower()
		if ext != "svg" and ext != "png":
			continue
		var stem: String = name.get_basename()
		# 같은 이름이면 PNG 를 먼저 쓴다 (나중에 그린 진짜 그림)
		if found.has(stem) and ext == "svg":
			continue
		found[stem] = dir_path + name
	var keys: Array = found.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append([k, found[k]])
	return out


## 여러 그림을 한 장에 모은 아틀라스. 변주(이름.2, 이름.3)는 같은 이름 아래 묶인다.
class Atlas:
	var cell: int
	var cols: int
	var pad: int
	var texture: ImageTexture
	var count: int = 0
	var _variants := {}    # 이름 -> [칸 번호...]
	var _rows: int = 1

	func _init(cell_px: int, columns: int) -> void:
		cell = cell_px
		cols = columns
		pad = cell_px / 16

	## list: 파일 이름(변주 번호 포함) -> 경로
	func build(list: Dictionary) -> void:
		var images: Array = []
		for name in list:
			var img: Image = load_image(list[name], cell)
			if img == null:
				push_warning("타일 그림을 읽지 못함: %s" % list[name])
				continue
			img.fix_alpha_edges()   # 투명한 가장자리가 검게 번지지 않도록
			var key: String = base_name(name)
			if not _variants.has(key):
				_variants[key] = []
			_variants[key].append(images.size())
			images.append(img)
		count = images.size()
		_rows = maxi(1, ceili(float(count) / cols))
		var step: int = cell + pad * 2
		var big := Image.create_empty(step * cols, step * _rows, false, Image.FORMAT_RGBA8)
		big.fill(Color(0, 0, 0, 0))
		for k in count:
			big.blit_rect(images[k], Rect2i(0, 0, cell, cell), Vector2i((k % cols) * step + pad, (k / cols) * step + pad))
		big.generate_mipmaps()
		texture = ImageTexture.create_from_image(big)

	func has(key: String) -> bool:
		return _variants.has(key)

	## 후보 이름 중 그림이 있는 첫 번째. 없으면 "".
	func resolve(candidates: Array) -> String:
		for c in candidates:
			if _variants.has(c):
				return c
		return ""

	func variant_count(key: String) -> int:
		return _variants[key].size() if _variants.has(key) else 0

	## 그림 key 의 변주 중 seed 로 하나를 골라, 그 위의 점 (x, y) (가운데 0, 가장자리 ±1, y 는 위쪽) 의 아틀라스 좌표
	func uv(key: String, x: float, y: float, seed: int = 0) -> Vector2:
		var v: Array = _variants[key]
		var k: int = v[posmod(seed, v.size())]
		var step: float = cell + pad * 2
		var px: float = (k % cols) * step + pad + (0.5 + x * 0.5) * cell
		var py: float = (k / cols) * step + pad + (0.5 - y * 0.5) * cell
		return Vector2(px / (step * cols), py / (step * _rows))

	## "forest.2" -> "forest"
	static func base_name(name: String) -> String:
		var dot: int = name.rfind(".")
		if dot > 0 and name.substr(dot + 1).is_valid_int():
			return name.substr(0, dot)
		return name

	static func load_image(path: String, size: int) -> Image:
		var img: Image = _read(path, size)
		if img == null:
			return null
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != size or img.get_height() != size:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		return img

	static func _read(path: String, size: int) -> Image:
		# 편집기에서 실행할 때는 SVG 원본을 바로 굽는다 (가져오기 설정과 상관없이 선명하게)
		if path.get_extension().to_lower() == "svg" and FileAccess.file_exists(path):
			var img := Image.new()
			var text: String = FileAccess.get_file_as_string(path)
			if img.load_svg_from_string(text, float(size) / _svg_width(text)) == OK:
				return img
		# 내보낸 게임이나 PNG 는 가져온 텍스처를 쓴다
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				var im: Image = tex.get_image()
				if im.is_compressed():
					im.decompress()
				return im
		if FileAccess.file_exists(path):
			return Image.load_from_file(path)
		return null

	static func _svg_width(text: String) -> float:
		var re := RegEx.create_from_string("viewBox=\"[-\\d.]+[ ,]+[-\\d.]+[ ,]+([\\d.]+)")
		var m := re.search(text)
		return float(m.get_string(1)) if m else 256.0


# ---------------------------------------------------------------- 칸마다 고르는 규칙

## 칸마다 고정된 난수 (변주 고르기용). salt 로 같은 칸에서도 다른 값을 낸다.
static func tile_seed(gen: WorldGen, i: int, salt: int = 0) -> int:
	return hash(Vector3i(i, gen.seed_value, salt)) & 0x7fffffff


## 칸의 겉모습 종류. 땅은 바닥 이름(grass, plains, desert, tundra, snow, rock),
## 물은 deep, shallow, lake, ice. 경계 그림(edge/이칸__이웃)을 고를 때 쓴다.
static func surface_class(gen: WorldGen, i: int) -> String:
	match gen.base[i]:
		TileLayers.Base.LAKE:
			return "ice" if gen.veg[i] == TileLayers.Veg.ICE else "lake"
		TileLayers.Base.SHALLOW:
			return "ice" if gen.veg[i] == TileLayers.Veg.ICE else "shallow"
		TileLayers.Base.DEEP:
			return "ice" if gen.veg[i] == TileLayers.Veg.ICE else "deep"
	if gen.veg[i] == TileLayers.Veg.ICE:
		return "snow"
	if gen.relief[i] == 2:
		return "snow" if gen.temperature[i] < -4.0 else "rock"
	if gen.temp_band[i] == TileLayers.TempBand.POLAR:
		return "tundra"
	match gen.moist[i]:
		TileLayers.Moist.HUMID:
			return "grass"
		TileLayers.Moist.SEMI:
			return "plains"
	return "desert"


static func is_land(gen: WorldGen, i: int) -> bool:
	return gen.base[i] == TileLayers.Base.LAND


## 칸의 바닥 무늬 층 번호 (땅이면 바닥, 물이면 물 무늬). 변주가 여럿이면 칸마다 하나를 고른다. 없으면 -1.
func class_layer(gen: WorldGen, i: int) -> int:
	return _pick_layer(surface_class(gen, i), tile_seed(gen, i))


## 땅 칸이 물과 만날 때 쓰는 물가 무늬 층 번호. 물 칸이면 -1.
func shore_layer(gen: WorldGen, i: int) -> int:
	if not is_land(gen, i):
		return -1
	return _pick_layer("shore_" + shore_class(gen, i), tile_seed(gen, i, 3))


func _pick_layer(key: String, seed: int) -> int:
	var layers: Array = _ground_layers.get(key, [])
	if layers.is_empty():
		return -1
	return layers[seed % layers.size()]


## 이 칸의 땅이 물과 닿는 모양: sand, grass, mud, rock, ice, gravel
static func shore_class(gen: WorldGen, i: int) -> String:
	if gen.veg[i] == TileLayers.Veg.WETLAND:
		return "mud"
	match surface_class(gen, i):
		"snow":
			return "ice"
		"rock":
			return "rock"
		"tundra":
			return "gravel"
		"desert", "plains":
			return "sand"
	# 열대 바다는 모래 해변, 나머지 습윤한 땅은 풀밭 물가
	if gen.temp_band[i] == TileLayers.TempBand.TROPICAL:
		return "sand"
	return "grass"


## 꼭짓점 조합 이름: 세 칸의 겉모습을 바깥에서 보아 반시계 방향으로 이은 것을, 사전순으로 가장 앞서게
## 돌린 것. 돌린 칸 수도 함께 돌려준다 ([이름, 돌린 수]). 그림 삼각형은 위 -> 왼쪽 아래 -> 오른쪽 아래 순서.
static func combo_name(a: String, b: String, c: String) -> Array:
	var rots: Array = [[a, b, c], [b, c, a], [c, a, b]]
	var best: int = 0
	for r in 3:
		if "_".join(rots[r]) < "_".join(rots[best]):
			best = r
	return ["_".join(rots[best]), best]


## 2층 식생의 납작한 그림 이름 (decal/ 아래). 없으면 "".
static func veg_key(gen: WorldGen, i: int) -> String:
	if gen.base[i] != TileLayers.Base.LAND:
		return ""
	# 대체형 시설(경작지, 구역)이 서 있으면 식생 그림은 그리지 않는다
	var s: int = gen.structure[i]
	if s != TileLayers.Struct.NONE and TileLayers.STRUCT_COVER[s] == TileLayers.Cover.REPLACE \
			and gen.structure_state[i] != TileLayers.State.RUIN:
		return ""
	match gen.veg[i]:
		TileLayers.Veg.GRASS:
			if gen.temp_band[i] == TileLayers.TempBand.POLAR:
				return "tundra"
			return "grass" if gen.moist[i] == TileLayers.Moist.HUMID else "grass_dry"
		TileLayers.Veg.FOREST:
			if TileLayers.is_jungle(gen, i):
				return "jungle"
			if gen.temp_band[i] >= TileLayers.TempBand.BOREAL:
				return "forest_boreal"
			return "forest"
		TileLayers.Veg.WETLAND:
			return "wetland"
		TileLayers.Veg.BARE:
			return "desert" if gen.moist[i] == TileLayers.Moist.ARID else ""
	return ""


## 3층 시설의 납작한 그림 이름 (decal/ 아래). 없으면 "".
static func struct_key(gen: WorldGen, i: int) -> String:
	var s: int = gen.structure[i]
	if s == TileLayers.Struct.NONE:
		return ""
	if gen.structure_state[i] == TileLayers.State.RUIN:
		return "ruin"
	return STRUCT_ART[s]


## 칸 i 에 세울 그림 목록: [그림, x, y, 크기, 색, 변주 seed]
static func sprites_for(gen: WorldGen, i: int) -> Array:
	var out: Array = []
	var sk: String = struct_key(gen, i)
	var tint: Color = IDLE_TINT if gen.structure_state[i] == TileLayers.State.IDLE else Color.WHITE
	var replaces: bool = sk != "" and sk != "ruin" and TileLayers.STRUCT_COVER[gen.structure[i]] == TileLayers.Cover.REPLACE
	# 식생: 시설이 놓인 자리는 비워 둔다
	var vk: String = "" if replaces else veg_key(gen, i)
	var rng := RandomNumberGenerator.new()
	rng.seed = tile_seed(gen, i, 1)
	var keep_out: float = 0.0 if sk == "" else 0.45
	match vk:
		"forest", "forest_boreal", "jungle":
			for p in _scatter(rng, 11, 0.78, keep_out):
				var kind: String
				if vk == "jungle":
					kind = "palm" if rng.randf() < 0.3 else "tree_jungle"
				elif vk == "forest_boreal":
					kind = "tree_conifer_snow" if gen.temp_band[i] == TileLayers.TempBand.POLAR or rng.randf() < 0.4 else "tree_conifer"
				else:
					kind = "tree_conifer" if rng.randf() < 0.4 else "tree_broad"
				out.append([kind, p.x, p.y, rng.randf_range(0.36, 0.46), Color.WHITE, rng.randi()])
		"wetland":
			for p in _scatter(rng, 6, 0.75, keep_out):
				out.append(["reeds", p.x, p.y, rng.randf_range(0.2, 0.26), Color.WHITE, rng.randi()])
		"grass_dry":
			for p in _scatter(rng, 3, 0.7, keep_out):
				out.append(["bush", p.x, p.y, rng.randf_range(0.14, 0.18), Color.WHITE, rng.randi()])
		"tundra":
			for p in _scatter(rng, 3, 0.7, keep_out):
				out.append(["rock" if rng.randf() < 0.6 else "bush", p.x, p.y, rng.randf_range(0.14, 0.2), Color.WHITE, rng.randi()])
	if STRUCT_SPRITES.has(sk):
		for e in STRUCT_SPRITES[sk]:
			out.append([e[0], e[1], e[2], e[3], tint, rng.randi()])
	return out


## 원 안에 서로 너무 붙지 않게 흩뿌린 점들. keep_out 반지름 안쪽은 비운다.
static func _scatter(rng: RandomNumberGenerator, n: int, radius: float, keep_out: float) -> Array:
	var pts: Array = []
	var tries: int = 0
	while pts.size() < n and tries < n * 30:
		tries += 1
		var p := Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))
		var r: float = p.length()
		if r > radius or r < keep_out:
			continue
		var ok := true
		for q in pts:
			if p.distance_to(q) < 0.3:
				ok = false
				break
		if ok:
			pts.append(p)
	return pts


## 도로가 이어지는 칸: 도로가 있거나 폐허가 아닌 정착지 구역
static func road_link(gen: WorldGen, i: int) -> bool:
	if gen.road[i] == 1:
		return true
	return gen.structure[i] == TileLayers.Struct.DISTRICT and gen.structure_state[i] != TileLayers.State.RUIN
