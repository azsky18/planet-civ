class_name TileArt
extends RefCounted
## 타일 위 그림. 세 가지로 나뉜다.
##
##   바닥 (GROUND): 1층 지형·기후로 정하는 바닥 무늬. 이음매 없이 반복되는 그림이며,
##       식생을 모두 걷어 내도 남는다. 가까이 가면 지형 색 대신 이 무늬가 보인다.
##   납작한 그림 (DECAL): 칸 위에 깔리는 그림. 밭, 광장, 웅덩이, 도로, 해안, 강둑 등.
##   세운 그림 (SPRITE): 나무, 집, 천막처럼 바닥에 세워 그리는 그림. 카메라를 향해 서고
##       발밑에 그림자가 깔린다.
##
## 그림을 바꾸려면 아래 목록의 경로만 바꾸거나 같은 이름의 파일을 덮어쓰면 된다.
## SVG 와 PNG 를 모두 쓸 수 있다. 목록에서 지운 항목은 그리지 않는다.
## 그림 규칙은 art/tiles/README.md 에 있다.

const GROUND := {
	"grass": "res://art/tiles/ground/grass.svg",    # 습윤
	"plains": "res://art/tiles/ground/plains.svg",  # 반건조
	"desert": "res://art/tiles/ground/desert.svg",  # 건조
	"tundra": "res://art/tiles/ground/tundra.svg",  # 한대
	"snow": "res://art/tiles/ground/snow.svg",      # 빙설
	"rock": "res://art/tiles/ground/rock.svg",      # 산지
}

const DECAL := {
	# 2층 식생
	"grass": "res://art/tiles/grass.svg",
	"grass_dry": "res://art/tiles/grass_dry.svg",
	"tundra": "res://art/tiles/tundra.svg",
	"forest": "res://art/tiles/forest.svg",
	"forest_boreal": "res://art/tiles/forest_boreal.svg",
	"jungle": "res://art/tiles/jungle.svg",
	"wetland": "res://art/tiles/wetland.svg",
	"desert": "res://art/tiles/desert.svg",
	# 3층 시설물 (바닥 부분)
	"farm": "res://art/tiles/farm.svg",
	"district": "res://art/tiles/district.svg",
	"shrine": "res://art/tiles/shrine.svg",
	"mine": "res://art/tiles/mine.svg",
	"lumber": "res://art/tiles/lumber.svg",
	"irrigation": "res://art/tiles/irrigation.svg",
	"camp": "res://art/tiles/camp.svg",
	"fishery": "res://art/tiles/fishery.svg",
	"ruin": "res://art/tiles/ruin.svg",
	# 도로
	"road": "res://art/tiles/road.svg",              # 한 갈래 (가운데 -> +x 변)
	"road_alone": "res://art/tiles/road_alone.svg",  # 이웃 도로가 없는 외딴 도로
	# 물가
	"shore": "res://art/tiles/shore.svg",            # 위 절반 물, 아래 절반 땅
	"river_bank": "res://art/tiles/river_bank.svg",  # 강줄기 아래 깔리는 흙둑
	# 세운 그림 발밑 그림자
	"shadow": "res://art/tiles/sprites/shadow.svg",
}

const SPRITE := {
	"tree_broad": "res://art/tiles/sprites/tree_broad.svg",
	"tree_conifer": "res://art/tiles/sprites/tree_conifer.svg",
	"tree_conifer_snow": "res://art/tiles/sprites/tree_conifer_snow.svg",
	"tree_jungle": "res://art/tiles/sprites/tree_jungle.svg",
	"palm": "res://art/tiles/sprites/palm.svg",
	"reeds": "res://art/tiles/sprites/reeds.svg",
	"bush": "res://art/tiles/sprites/bush.svg",
	"rock": "res://art/tiles/sprites/rock.svg",
	"house": "res://art/tiles/sprites/house.svg",
	"tower": "res://art/tiles/sprites/tower.svg",
	"temple": "res://art/tiles/sprites/temple.svg",
	"tent": "res://art/tiles/sprites/tent.svg",
	"fire": "res://art/tiles/sprites/fire.svg",
	"mine": "res://art/tiles/sprites/mine.svg",
	"hut": "res://art/tiles/sprites/hut.svg",
	"logs": "res://art/tiles/sprites/logs.svg",
	"haystack": "res://art/tiles/sprites/haystack.svg",
	"boat": "res://art/tiles/sprites/boat.svg",
	"ruin_wall": "res://art/tiles/sprites/ruin_wall.svg",
	"ruin_column": "res://art/tiles/sprites/ruin_column.svg",
}

## 시설 종류 -> 그림 이름 (TileLayers.Struct 순서)
const STRUCT_ART := ["", "farm", "district", "shrine", "mine", "lumber", "irrigation", "camp", "fishery"]

## 시설마다 세울 그림: [그림, x, y, 크기]. 좌표는 칸 중심 0, 꼭짓점까지 1, y 는 북쪽.
## 크기는 그림 정사각형의 너비 (같은 단위).
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

var ground_tex: Texture2DArray
var ground_keys: Array = []
var decals := Atlas.new(256, 8)
var sprites := Atlas.new(128, 8)


## 등록된 그림을 모두 읽는다.
func load_all() -> void:
	decals.build(DECAL)
	sprites.build(SPRITE)
	var imgs: Array[Image] = []
	for key in GROUND:
		var img: Image = Atlas.load_image(GROUND[key], 256)
		if img == null:
			push_warning("바닥 그림을 읽지 못함: %s" % GROUND[key])
			img = Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.5, 0.5))
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		imgs.append(img)
		ground_keys.append(key)
	ground_tex = Texture2DArray.new()
	ground_tex.create_from_images(imgs)


## 여러 그림을 한 장에 모은 아틀라스
class Atlas:
	var cell: int
	var cols: int
	var pad: int
	var texture: ImageTexture
	var keys: Array = []
	var _index := {}
	var _rows: int = 1

	func _init(cell_px: int, columns: int) -> void:
		cell = cell_px
		cols = columns
		pad = cell_px / 16

	func build(list: Dictionary) -> void:
		var images: Array = []
		for key in list:
			var img: Image = load_image(list[key], cell)
			if img == null:
				push_warning("타일 그림을 읽지 못함: %s (%s)" % [key, list[key]])
				continue
			img.fix_alpha_edges()   # 투명한 가장자리가 검게 번지지 않도록
			_index[key] = keys.size()
			keys.append(key)
			images.append(img)
		_rows = maxi(1, ceili(float(images.size()) / cols))
		var step: int = cell + pad * 2
		var big := Image.create_empty(step * cols, step * _rows, false, Image.FORMAT_RGBA8)
		big.fill(Color(0, 0, 0, 0))
		for k in images.size():
			big.blit_rect(images[k], Rect2i(0, 0, cell, cell), Vector2i((k % cols) * step + pad, (k / cols) * step + pad))
		big.generate_mipmaps()
		texture = ImageTexture.create_from_image(big)

	func has(key: String) -> bool:
		return _index.has(key)

	## 그림 key 위의 점 (x, y) (가운데 0, 가장자리 ±1, y 는 위쪽) 의 아틀라스 좌표
	func uv(key: String, x: float, y: float) -> Vector2:
		var k: int = _index[key]
		var step: float = cell + pad * 2
		var px: float = (k % cols) * step + pad + (0.5 + x * 0.5) * cell
		var py: float = (k / cols) * step + pad + (0.5 - y * 0.5) * cell
		return Vector2(px / (step * cols), py / (step * _rows))

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

## 바닥 그림 번호 (ground_keys 의 순서). 물이면 -1.
func ground_index(gen: WorldGen, i: int) -> int:
	if gen.base[i] != TileLayers.Base.LAND:
		return -1
	var key: String
	if gen.veg[i] == TileLayers.Veg.ICE:
		key = "snow"
	elif gen.relief[i] == 2:
		key = "snow" if gen.temperature[i] < -4.0 else "rock"
	elif gen.temp_band[i] == TileLayers.TempBand.POLAR:
		key = "tundra"
	else:
		match gen.moist[i]:
			TileLayers.Moist.HUMID:
				key = "grass"
			TileLayers.Moist.SEMI:
				key = "plains"
			_:
				key = "desert"
	return ground_keys.find(key)


## 2층 식생의 납작한 그림. 없으면 "".
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


## 3층 시설의 납작한 그림. 없으면 "".
static func struct_key(gen: WorldGen, i: int) -> String:
	var s: int = gen.structure[i]
	if s == TileLayers.Struct.NONE:
		return ""
	if gen.structure_state[i] == TileLayers.State.RUIN:
		return "ruin"
	return STRUCT_ART[s]


## 칸 i 에 세울 그림 목록: [그림, x, y, 크기, 색]
static func sprites_for(gen: WorldGen, i: int) -> Array:
	var out: Array = []
	var sk: String = struct_key(gen, i)
	var tint: Color = IDLE_TINT if gen.structure_state[i] == TileLayers.State.IDLE else Color.WHITE
	var replaces: bool = sk != "" and sk != "ruin" and TileLayers.STRUCT_COVER[gen.structure[i]] == TileLayers.Cover.REPLACE
	# 식생: 시설이 놓인 자리는 비워 둔다
	var vk: String = "" if replaces else veg_key(gen, i)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(i * 7919 + gen.seed_value)
	var keep_out: float = 0.0 if sk == "" else 0.45
	match vk:
		"forest", "forest_boreal", "jungle":
			var n: int = 11
			for p in _scatter(rng, n, 0.78, keep_out):
				var kind: String
				if vk == "jungle":
					kind = "palm" if rng.randf() < 0.3 else "tree_jungle"
				elif vk == "forest_boreal":
					kind = "tree_conifer_snow" if gen.temp_band[i] == TileLayers.TempBand.POLAR or rng.randf() < 0.4 else "tree_conifer"
				else:
					kind = "tree_conifer" if rng.randf() < 0.4 else "tree_broad"
				out.append([kind, p.x, p.y, rng.randf_range(0.36, 0.46), Color.WHITE])
		"wetland":
			for p in _scatter(rng, 6, 0.75, keep_out):
				out.append(["reeds", p.x, p.y, rng.randf_range(0.2, 0.26), Color.WHITE])
		"grass_dry":
			for p in _scatter(rng, 3, 0.7, keep_out):
				out.append(["bush", p.x, p.y, rng.randf_range(0.14, 0.18), Color.WHITE])
		"tundra":
			for p in _scatter(rng, 3, 0.7, keep_out):
				out.append(["rock" if rng.randf() < 0.6 else "bush", p.x, p.y, rng.randf_range(0.14, 0.2), Color.WHITE])
	if STRUCT_SPRITES.has(sk):
		for e in STRUCT_SPRITES[sk]:
			out.append([e[0], e[1], e[2], e[3], tint])
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
