class_name TileArt
extends RefCounted
## 타일 위 그림 (식생, 시설물, 도로).
##
## 그림을 바꾸려면 ART 의 경로만 바꾸거나 같은 이름의 파일을 덮어쓰면 된다.
## SVG 와 PNG 를 모두 쓸 수 있다. 파일이 없는 항목은 그림 없이 색만 칠한다.
##
## 그림 규칙 (art/tiles/README.md 에 더 자세히):
##   - 정사각형. 가운데가 칸 중심, 위쪽이 북쪽이다.
##   - 정사각형의 너비는 육각 칸의 꼭짓점-꼭짓점 거리와 같다. 그래서 칸 안에 들어오는 부분은
##     가운데에서 반지름 0.43 (256px 기준 약 110px) 안쪽 원이다.
##   - 도로 한 갈래(road)는 가운데에서 오른쪽(+x) 변까지 그린다. 이웃 칸으로 이어진 방향마다
##     돌려서 한 장씩 겹쳐 그린다.

const ART := {
	# 2층 식생
	"grass": "res://art/tiles/grass.svg",                # 초지 (습윤)
	"grass_dry": "res://art/tiles/grass_dry.svg",        # 초지 (건조·반건조, 평원)
	"tundra": "res://art/tiles/tundra.svg",              # 초지 (한대, 툰드라)
	"forest": "res://art/tiles/forest.svg",              # 숲 (열대·온대)
	"forest_boreal": "res://art/tiles/forest_boreal.svg",  # 숲 (냉대·한대)
	"jungle": "res://art/tiles/jungle.svg",              # 밀림
	"wetland": "res://art/tiles/wetland.svg",            # 습지
	"desert": "res://art/tiles/desert.svg",              # 맨땅 (건조)
	# 3층 시설물
	"farm": "res://art/tiles/farm.svg",
	"district": "res://art/tiles/district.svg",
	"shrine": "res://art/tiles/shrine.svg",
	"mine": "res://art/tiles/mine.svg",
	"lumber": "res://art/tiles/lumber.svg",
	"irrigation": "res://art/tiles/irrigation.svg",
	"camp": "res://art/tiles/camp.svg",
	"fishery": "res://art/tiles/fishery.svg",
	"ruin": "res://art/tiles/ruin.svg",                  # 폐허 (모든 시설 공용)
	# 도로
	"road": "res://art/tiles/road.svg",                  # 한 갈래 (가운데 -> +x 변)
	"road_alone": "res://art/tiles/road_alone.svg",      # 이웃 도로가 없는 외딴 도로
}

## 시설 종류 -> 그림 이름 (TileLayers.Struct 순서)
const STRUCT_ART := ["", "farm", "district", "shrine", "mine", "lumber", "irrigation", "camp", "fishery"]

## 방치된 시설은 조금 어둡고 바랜 색으로
const IDLE_TINT := Color(0.72, 0.68, 0.62)

const CELL := 256      # 그림 한 장을 굽는 크기
const PAD := 16        # 밉맵에서 이웃 그림이 번지지 않게 둘레에 두는 여백
const COLS := 8

var atlas: ImageTexture
var keys: Array = []
var _index := {}


## 등록된 그림을 모두 읽어 아틀라스 한 장으로 굽는다.
func load_all() -> void:
	var images: Array = []
	for key in ART:
		var img: Image = _load_image(ART[key])
		if img == null:
			push_warning("타일 그림을 읽지 못함: %s (%s)" % [key, ART[key]])
			continue
		if img.get_width() != CELL or img.get_height() != CELL:
			img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		_index[key] = keys.size()
		keys.append(key)
		images.append(img)
	var rows: int = maxi(1, ceili(float(images.size()) / COLS))
	var step: int = CELL + PAD * 2
	var big := Image.create_empty(step * COLS, step * rows, false, Image.FORMAT_RGBA8)
	big.fill(Color(0, 0, 0, 0))
	for k in images.size():
		var img: Image = images[k]
		big.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i((k % COLS) * step + PAD, (k / COLS) * step + PAD))
	big.generate_mipmaps()
	atlas = ImageTexture.create_from_image(big)


func has(key: String) -> bool:
	return _index.has(key)


## 그림 key 의 UV. 칸 안의 점 (x, y) (중심 0, 반지름 1 = 꼭짓점 거리, y 는 북쪽) 을 아틀라스 좌표로.
func uv(key: String, x: float, y: float) -> Vector2:
	var k: int = _index[key]
	var step: float = CELL + PAD * 2
	var w: float = step * COLS
	var h: float = step * maxi(1, ceili(float(keys.size()) / COLS))
	var px: float = (k % COLS) * step + PAD + (0.5 + x * 0.5) * CELL
	var py: float = (k / COLS) * step + PAD + (0.5 - y * 0.5) * CELL
	return Vector2(px / w, py / h)


static func _load_image(path: String) -> Image:
	# 편집기에서 실행할 때는 SVG 원본을 바로 굽는다 (가져오기 설정과 상관없이 선명하게)
	if path.get_extension().to_lower() == "svg" and FileAccess.file_exists(path):
		var img := Image.new()
		var text: String = FileAccess.get_file_as_string(path)
		if img.load_svg_from_string(text, float(CELL) / _svg_width(text)) == OK:
			return img
	# 내보낸 게임이나 PNG 는 가져온 텍스처를 쓴다
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex != null:
			var im: Image = tex.get_image()
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			return im
	if FileAccess.file_exists(path):
		var im2 := Image.load_from_file(path)
		if im2 != null:
			im2.convert(Image.FORMAT_RGBA8)
		return im2
	return null


static func _svg_width(text: String) -> float:
	var re := RegEx.create_from_string("viewBox=\"[-\\d.]+[ ,]+[-\\d.]+[ ,]+([\\d.]+)")
	var m := re.search(text)
	return float(m.get_string(1)) if m else float(CELL)


# ---------------------------------------------------------------- 칸마다 고르는 규칙

## 2층 식생 그림. 없으면 "".
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


## 3층 시설 그림. 없으면 "".
static func struct_key(gen: WorldGen, i: int) -> String:
	var s: int = gen.structure[i]
	if s == TileLayers.Struct.NONE:
		return ""
	if gen.structure_state[i] == TileLayers.State.RUIN:
		return "ruin"
	return STRUCT_ART[s]


## 도로가 이어지는 칸: 도로가 있거나 사용 중인 정착지 구역
static func road_link(gen: WorldGen, i: int) -> bool:
	if gen.road[i] == 1:
		return true
	return gen.structure[i] == TileLayers.Struct.DISTRICT and gen.structure_state[i] != TileLayers.State.RUIN
