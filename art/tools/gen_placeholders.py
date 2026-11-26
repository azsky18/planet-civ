"""임시 그림 만들기.  python3 art/tools/gen_placeholders.py

손으로 그린 그림(art/tiles/decal, sprite 의 기본 그림)은 건드리지 않고, 아래처럼 수가 많은
그림만 만든다. 나중에 진짜 그림이 생기면 같은 이름의 파일을 덮어쓰면 된다.

  ground/<바닥>.svg, <바닥>.2.svg ...      이음매 없이 반복되는 바닥 무늬와 변주
  edge/<이 칸>__<이웃 칸>.svg               이웃 바닥이 이 칸으로 번져 드는 경계 그림
  shore/<땅 물가>__<물>.svg                 땅과 물이 닿는 띠 (위 절반 물, 아래 절반 땅)
  water/<물>.svg ...                        물 위에 얹는 물결 그림, 강물
  decal/<이름>.N.svg, sprite/<이름>.N.svg   기본 그림의 변주
"""
import math
import zlib
import os
import random
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tiles")
S = 256


def out(folder, name, note, body, size=S):
    os.makedirs(os.path.join(ROOT, folder), exist_ok=True)
    with open(os.path.join(ROOT, folder, name + ".svg"), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}">\n'
                f'<!-- {note} (art/tools/gen_placeholders.py 로 생성한 임시 그림) -->\n{body}\n</svg>\n')


def wrap(draw, x, y, r):
    s = ""
    for dx in (-S, 0, S):
        for dy in (-S, 0, S):
            if -r <= x + dx <= S + r and -r <= y + dy <= S + r:
                s += draw(x + dx, y + dy)
    return s


def blobs(rnd, n, cols, rmin, rmax, op, tile=True, box=(0, 0, S, S)):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(box[0], box[2]), rnd.uniform(box[1], box[3])
        rx, ry = rnd.uniform(rmin, rmax), rnd.uniform(rmin, rmax) * 0.7
        c, a = rnd.choice(cols), rnd.uniform(0, 180)
        d = lambda X, Y: f'<ellipse cx="{X:.1f}" cy="{Y:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{c}" opacity="{op}" transform="rotate({a:.0f} {X:.1f} {Y:.1f})"/>'
        s += wrap(d, x, y, rmax) if tile else d(x, y)
    return s


def blades(rnd, n, cols, ln, tile=True, box=(0, 0, S, S), op=1.0):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(box[0], box[2]), rnd.uniform(box[1], box[3])
        c, dx, l = rnd.choice(cols), rnd.uniform(-3, 3), rnd.uniform(ln * 0.6, ln)
        d = lambda X, Y: f'<path d="M{X:.1f},{Y:.1f} q{dx/2:.1f},{-l/2:.1f} {dx:.1f},{-l:.1f}" stroke="{c}" stroke-width="1.3" fill="none" stroke-linecap="round" opacity="{op}"/>'
        s += wrap(d, x, y, ln) if tile else d(x, y)
    return s


def specks(rnd, n, cols, rmax, tile=True, box=(0, 0, S, S), op=1.0):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(box[0], box[2]), rnd.uniform(box[1], box[3])
        c, r = rnd.choice(cols), rnd.uniform(0.6, rmax)
        d = lambda X, Y: f'<circle cx="{X:.1f}" cy="{Y:.1f}" r="{r:.1f}" fill="{c}" opacity="{op}"/>'
        s += wrap(d, x, y, rmax) if tile else d(x, y)
    return s


def ripples(rnd, n, col, tile=True, box=(0, 0, S, S), op=0.55, w0=14, w1=30, sw=1.4):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(box[0], box[2]), rnd.uniform(box[1], box[3])
        w = rnd.uniform(w0, w1)
        d = lambda X, Y: f'<path d="M{X-w:.1f},{Y:.1f} q{w/2:.1f},-4 {w:.1f},0 t{w:.1f},0" stroke="{col}" stroke-width="{sw}" fill="none" opacity="{op}" stroke-linecap="round"/>'
        s += wrap(d, x, y, 2 * w) if tile else d(x, y)
    return s


def cracks(rnd, n, col):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        a, b, c, d = rnd.uniform(-12, 12), rnd.uniform(4, 12), rnd.uniform(-8, 8), rnd.uniform(4, 10)
        s += wrap(lambda X, Y: f'<path d="M{X:.1f},{Y:.1f} l{a:.1f},{b:.1f} l{c:.1f},{d:.1f}" stroke="{col}" stroke-width="1.2" fill="none" opacity="0.6"/>', x, y, 30)
    return s


# ---------------------------------------------------------------- 바닥

GROUND = {
    # 이름: (바탕색, 얼룩색, 무늬 함수)
    "grass": ("#7da24a", ["#6d9440", "#8cb052", "#76a046", "#94b65a"],
              lambda r: specks(r, 90, ["#5f8a36", "#a6c466"], 1.6) + blades(r, 220, ["#5b8530", "#6f9a3a", "#9cc05c"], 6)),
    "plains": ("#a9a258", ["#9a9450", "#b8ae62", "#a0a858", "#c2b46a"],
               lambda r: specks(r, 120, ["#8a7c44", "#c8bc78", "#7a8a40"], 1.6) + blades(r, 160, ["#8a8a40", "#b0a250", "#c8b664"], 5)),
    "desert": ("#d9c28a", ["#cfb67c", "#e4cf9a", "#d2b878", "#e8d6a6"],
               lambda r: ripples(r, 40, "#b89c62") + specks(r, 70, ["#a88a58", "#efe0b8"], 1.4)),
    "tundra": ("#949a78", ["#86906a", "#a2a684", "#7a8a62", "#aaa890", "#8e7e68"],
               lambda r: specks(r, 110, ["#6a6a5a", "#b8b8a8", "#7a5a4a"], 1.8)),
    "snow": ("#eef1f3", ["#dfe6ee", "#f8fafc", "#d6dee8"], lambda r: ripples(r, 24, "#c4d0de")),
    "rock": ("#8c8272", ["#7a7062", "#a09684", "#6a6256", "#b0a690"],
             lambda r: specks(r, 140, ["#5a5248", "#c4bcae"], 2.0) + cracks(r, 30, "#4e463c")),
}
NOTE = {"grass": "초원 (습윤)", "plains": "평원 (반건조)", "desert": "사막 (건조)", "tundra": "툰드라 (한대)",
        "snow": "눈과 얼음", "rock": "산지 바위"}


def ground_svg(name, seed):
    base, cols, extra = GROUND[name]
    r = random.Random(seed)
    return f'<rect width="{S}" height="{S}" fill="{base}"/>\n' + blobs(r, 40, cols, 12, 36, 0.5) + extra(r)


for gi, name in enumerate(GROUND):
    for v in (1, 2, 3):
        out("ground", name if v == 1 else f"{name}.{v}", f"바닥: {NOTE[name]}, 변주 {v}", ground_svg(name, 100 * gi + v))


# ---------------------------------------------------------------- 경계 (이웃 바닥이 이 칸으로 번져 듦)
# 위쪽 가장자리(y=0)가 이웃과 맞닿은 변이고, 아래로 갈수록 이웃 무늬가 옅어진다.

def edge_svg(nb, seed, water=False):
    r = random.Random(seed)
    if water:
        col = {"deep": "#14324e", "shallow": "#6fb6b8"}[nb]
        body = f'<defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{col}" stop-opacity="0.75"/><stop offset="1" stop-color="{col}" stop-opacity="0"/></linearGradient></defs>\n'
        body += f'<rect width="{S}" height="150" fill="url(#f)"/>'
        return body
    base, cols, _ = GROUND[nb]
    # 물결 모양 아래 끝
    pts = []
    for k in range(0, 9):
        pts.append((k * 32, r.uniform(70, 120)))
    path = f"M0,0 L{S},0 L{S},{pts[-1][1]:.0f} " + " ".join(f"Q{x + 16:.0f},{y + r.uniform(-25, 25):.0f} {x:.0f},{y:.0f}" for x, y in reversed(pts[:-1])) + " Z"
    body = f'<defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{base}" stop-opacity="0.95"/><stop offset="0.35" stop-color="{base}" stop-opacity="0.6"/><stop offset="0.55" stop-color="{base}" stop-opacity="0"/></linearGradient></defs>\n'
    body += f'<path d="{path}" fill="url(#f)"/>\n'
    body += blobs(r, 18, cols, 8, 22, 0.45, tile=False, box=(0, 0, S, 70))
    body += blobs(r, 14, cols, 5, 14, 0.3, tile=False, box=(0, 60, S, 130))
    return body


LAND = list(GROUND)
for a in LAND:
    for b in LAND:
        if a != b:
            out("edge", f"{a}__{b}", f"경계: {NOTE[a]} 칸에 {NOTE[b]} 바닥이 번져 듦", edge_svg(b, zlib.crc32((a + b).encode()) & 0xffff))
out("edge", "shallow__deep", "경계: 얕은 바다 칸에 깊은 바다가 번져 듦", edge_svg("deep", 1, water=True))
out("edge", "deep__shallow", "경계: 깊은 바다 칸에 얕은 바다가 번져 듦", edge_svg("shallow", 2, water=True))


# ---------------------------------------------------------------- 물가 (땅 종류 x 물 종류)
# 위 절반(y<128)이 물, 아래 절반이 땅, y=128 이 물가선. 가로로 늘여 쓴다.

def shore_svg(land, water, seed):
    r = random.Random(seed)
    calm = water == "lake"
    sh = "#7cc4c4" if not calm else "#7ab8c8"
    body = (f'<defs><linearGradient id="w" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{sh}" stop-opacity="0"/>'
            f'<stop offset="0.3" stop-color="{sh}" stop-opacity="0.35"/><stop offset="0.5" stop-color="{sh}" stop-opacity="0.7"/></linearGradient>\n')
    spec = {
        "sand": ("#e6d39a", 0.62, "모래"),
        "grass": ("#7da24a", 0.85, "풀밭"),
        "mud": ("#6e6248", 0.85, "갯벌"),
        "rock": ("#6e675c", 0.95, "바위 절벽"),
        "ice": ("#f2f6f8", 0.95, "얼음"),
        "gravel": ("#9a968c", 0.8, "자갈"),
    }[land]
    col, op, _ = spec
    body += (f'<linearGradient id="l" x1="0" y1="0" x2="0" y2="1"><stop offset="0.5" stop-color="{col}" stop-opacity="{op}"/>'
             f'<stop offset="0.75" stop-color="{col}" stop-opacity="{op * 0.5:.2f}"/><stop offset="1" stop-color="{col}" stop-opacity="0"/></linearGradient></defs>\n')
    body += f'<rect width="{S}" height="128" fill="url(#w)"/>\n<rect y="128" width="{S}" height="128" fill="url(#l)"/>\n'
    # 땅 쪽 무늬
    if land == "sand":
        body += f'<rect y="124" width="{S}" height="26" fill="#ecdcaa"/>'
        body += specks(r, 18, ["#b89c62", "#d8c48a"], 1.6, tile=False, box=(0, 132, S, 170), op=0.7)
    elif land == "grass":
        body += f'<rect y="124" width="{S}" height="9" fill="#c8b98a" opacity="0.9"/>'
        body += specks(r, 26, ["#9a9484", "#c0b8a4"], 2.2, tile=False, box=(0, 126, S, 134))
        body += blades(r, 70, ["#5b8530", "#6f9a3a", "#8ab443"], 8, tile=False, box=(0, 140, S, 200), op=0.9)
    elif land == "mud":
        body += blobs(r, 22, ["#5a5038", "#7a6c4c", "#4e5a48"], 8, 20, 0.6, tile=False, box=(0, 120, S, 170))
        body += blades(r, 40, ["#6a7a3a", "#5a6a2a"], 14, tile=False, box=(0, 130, S, 180))
        body += ripples(r, 6, "#a8c0b8", tile=False, box=(10, 100, S - 10, 124), op=0.5)
    elif land == "rock":
        for k in range(10):
            x = k * 28 + r.uniform(-6, 6)
            h = r.uniform(18, 34)
            body += f'<path d="M{x - 18:.0f},{128 + h * 0.4:.0f} L{x - 10:.0f},{128 - h * 0.25:.0f} L{x + 4:.0f},{128 - h * 0.35:.0f} L{x + 18:.0f},{128 + h * 0.3:.0f} Z" fill="{r.choice(["#7a7266", "#8a8276", "#665e54"])}" stroke="#3e382f" stroke-width="1"/>'
        body += specks(r, 20, ["#5a5248", "#a09888"], 2.4, tile=False, box=(0, 140, S, 175))
    elif land == "ice":
        body += f'<path d="M0,124 ' + " ".join(f"L{k * 16:.0f},{124 + r.uniform(-6, 4):.0f}" for k in range(17)) + f' L{S},160 L0,160 Z" fill="#f8fbfc" stroke="#b8cad6" stroke-width="1.2"/>'
        body += "".join(f'<path d="M{r.uniform(0, S):.0f},{r.uniform(132, 156):.0f} l{r.uniform(-14, 14):.0f},{r.uniform(4, 10):.0f}" stroke="#b8cad6" stroke-width="1"/>' for _ in range(8))
        body += blobs(r, 6, ["#f2f6f8", "#e4eef4"], 5, 12, 0.9, tile=False, box=(0, 96, S, 118))
    elif land == "gravel":
        body += specks(r, 140, ["#7a766c", "#a8a498", "#8a8478", "#c4c0b4"], 3.2, tile=False, box=(0, 124, S, 156))
    # 물 쪽: 물거품 또는 잔물결
    if calm:
        body += ripples(r, 8, "#e8f4f2", tile=False, box=(10, 96, S - 10, 122), op=0.5, w0=10, w1=18, sw=1.6)
    elif land != "ice":
        foam = "#f6f4ea"
        body += f'<path d="M0,124 Q16,{116 + r.uniform(-3, 3):.0f} 32,124 T64,124 T96,124 T128,124 T160,124 T192,124 T224,124 T256,124 L256,{130 if land != "rock" else 128} L0,{130 if land != "rock" else 128} Z" fill="{foam}" opacity="{0.9 if land != "mud" else 0.4}"/>'
        body += f'<path d="M0,104 Q21,98 42,104 T85,104 T128,104 T171,104 T213,104 T256,104" fill="none" stroke="#e8f4f2" stroke-width="3" opacity="0.5"/>'
        if land == "rock":
            body += blobs(r, 10, ["#ffffff"], 3, 8, 0.8, tile=False, box=(0, 112, S, 126))
    return body


SHORE_NOTE = {"sand": "모래 해변", "grass": "풀밭 물가", "mud": "갯벌·진흙", "rock": "바위 절벽", "ice": "얼음 가장자리", "gravel": "자갈 물가"}
for land in SHORE_NOTE:
    for water in ("ocean", "lake"):
        n = 2 if land in ("sand", "grass", "rock") and water == "ocean" else 1
        for v in range(1, n + 1):
            out("shore", f"{land}__{water}" + ("" if v == 1 else f".{v}"),
                f"물가: {SHORE_NOTE[land]} / {'바다' if water == 'ocean' else '호수'}, 변주 {v}. 위 절반 물, 아래 절반 땅",
                shore_svg(land, water, zlib.crc32((land + water).encode()) % 1000 + v))
out("shore", "any__any", "물가: 맞는 그림이 없을 때 쓰는 기본값", shore_svg("sand", "ocean", 5))


# ---------------------------------------------------------------- 물 위에 얹는 그림 (칸마다, 가운데 기준 원 안쪽)

def water_svg(kind, seed):
    r = random.Random(seed)
    box = (40, 40, 216, 216)
    if kind == "deep":
        return (ripples(r, 7, "#9cc0d8", tile=False, box=box, op=0.22, w0=10, w1=20, sw=1.4)
                + ripples(r, 5, "#0a1e30", tile=False, box=box, op=0.2, w0=12, w1=22, sw=1.8))
    if kind == "shallow":
        return (blobs(r, 5, ["#9ad8d0", "#c8e8d8"], 14, 30, 0.12, tile=False, box=box)
                + ripples(r, 7, "#e8f8f4", tile=False, box=box, op=0.3, w0=8, w1=16, sw=1.3))
    if kind == "lake":
        return "".join(f'<ellipse cx="{x:.0f}" cy="{y:.0f}" rx="{w:.0f}" ry="{w * 0.35:.0f}" fill="none" stroke="#e0f0f4" stroke-width="1.3" opacity="0.45"/>'
                       for x, y, w in [(r.uniform(60, 196), r.uniform(60, 196), r.uniform(6, 16)) for _ in range(7)])
    if kind == "ice":
        s = ""
        for _ in range(7):
            x, y, w = r.uniform(56, 200), r.uniform(56, 200), r.uniform(14, 30)
            pts = " ".join(f"{x + w * math.cos(a) * r.uniform(0.7, 1.0):.0f},{y + w * 0.7 * math.sin(a) * r.uniform(0.7, 1.0):.0f}" for a in [k * math.pi / 3 for k in range(6)])
            s += f'<polygon points="{pts}" fill="#f4f8fa" stroke="#b8cad6" stroke-width="1.2" opacity="0.95"/>'
        return s
    return ""


WATER_NOTE = {"deep": "깊은 바다 물결", "shallow": "얕은 바다 물빛", "lake": "호수 잔물결", "ice": "해빙 조각"}
for kind in WATER_NOTE:
    for v in (1, 2, 3):
        out("water", kind if v == 1 else f"{kind}.{v}", f"물: {WATER_NOTE[kind]}, 변주 {v}", water_svg(kind, 300 + 10 * v + len(kind)))

out("water", "river", "강물: 가로로 늘여 쓰는 띠. 가운데가 물, 위아래 끝은 투명",
    '<defs><linearGradient id="r" x1="0" y1="0" x2="0" y2="1"><stop offset="0.12" stop-color="#2a64a8" stop-opacity="0"/>'
    '<stop offset="0.22" stop-color="#2f6cae" stop-opacity="1"/><stop offset="0.5" stop-color="#3a7cbc" stop-opacity="1"/>'
    '<stop offset="0.78" stop-color="#2f6cae" stop-opacity="1"/><stop offset="0.88" stop-color="#2a64a8" stop-opacity="0"/></linearGradient></defs>\n'
    '<rect width="256" height="256" fill="url(#r)"/>\n'
    + "".join(f'<path d="M{x:.0f},{y:.0f} q12,-4 24,0" stroke="#9cd0ee" stroke-width="3" fill="none" opacity="0.6" stroke-linecap="round"/>'
              for x, y in [(12, 100), (70, 150), (130, 112), (190, 146), (220, 104), (40, 132), (160, 128)]))


# ---------------------------------------------------------------- 납작한 그림 변주 (흩뿌린 풀, 물웅덩이)

def tufts(seed, cols, flowers, n=16, rocks=False):
    r = random.Random(seed)
    s = ""
    for _ in range(n):
        a, d = r.uniform(0, 2 * math.pi), 100 * math.sqrt(r.uniform(0.02, 1))
        x, y = 128 + d * math.cos(a), 128 + d * math.sin(a)
        s += f'<g transform="translate({x:.0f},{y:.0f})"><ellipse cx="2" cy="1" rx="8" ry="2.5" fill="#2a3a10" opacity="0.2"/>'
        for k in range(4):
            dx, l = r.uniform(-9, 9), r.uniform(8, 15)
            s += f'<path d="M{k * 0.6:.1f},0 q{dx / 2:.1f},{-l / 2:.1f} {dx:.1f},{-l:.1f}" stroke="{r.choice(cols)}" stroke-width="2" fill="none" stroke-linecap="round"/>'
        s += "</g>"
    for _ in range(flowers):
        a, d = r.uniform(0, 2 * math.pi), 95 * math.sqrt(r.random())
        s += f'<circle cx="{128 + d * math.cos(a):.0f}" cy="{128 + d * math.sin(a):.0f}" r="2.2" fill="{r.choice(["#f0e28a", "#f4f0e4", "#e8a8c8"])}"/>'
    if rocks:
        for _ in range(5):
            a, d = r.uniform(0, 2 * math.pi), 90 * math.sqrt(r.random())
            s += f'<ellipse cx="{128 + d * math.cos(a):.0f}" cy="{128 + d * math.sin(a):.0f}" rx="{r.uniform(4, 8):.0f}" ry="3" fill="#8a8a84" stroke="#4a4a44" stroke-width="0.8"/>'
    return s


def pools(seed):
    r = random.Random(seed)
    s = '<defs><linearGradient id="p" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6a8e8a"/><stop offset="1" stop-color="#3e625e"/></linearGradient></defs>'
    for _ in range(4):
        a, d = r.uniform(0, 2 * math.pi), 70 * math.sqrt(r.random())
        x, y, w = 128 + d * math.cos(a), 128 + d * math.sin(a), r.uniform(14, 34)
        s += f'<ellipse cx="{x:.0f}" cy="{y:.0f}" rx="{w:.0f}" ry="{w * 0.5:.0f}" fill="url(#p)" stroke="#2e4a3e" stroke-width="1.5"/>'
        s += f'<path d="M{x - w * 0.5:.0f},{y - w * 0.15:.0f} l{w * 0.6:.0f},-1" stroke="#a9c6c0" stroke-width="1.5" opacity="0.8"/>'
    return s


for v in (2, 3):
    out("decal", f"grass.{v}", f"초지 (습윤), 변주 {v}", tufts(700 + v, ["#6f9a34", "#8ab443", "#5e8a2c", "#a4c858"], 6))
    out("decal", f"grass_dry.{v}", f"초지 (건조), 변주 {v}", tufts(710 + v, ["#a89a4a", "#c8b45c", "#9a8a40"], 0, n=12))
    out("decal", f"tundra.{v}", f"툰드라, 변주 {v}", tufts(720 + v, ["#7a8a52", "#98a060", "#8a6a4a"], 0, n=8, rocks=True))
    out("decal", f"wetland.{v}", f"습지 웅덩이, 변주 {v}", pools(730 + v))


# ---------------------------------------------------------------- 세운 그림 변주 (색만 바꿈)

def recolor(src, dst, note, swaps):
    s = open(os.path.join(ROOT, "sprite", src + ".svg")).read()
    for a, b in swaps:
        s = s.replace(a, b)
    s = re.sub(r"<!-- (.*?) -->", f"<!-- \\1, {note} (gen_placeholders.py 로 색만 바꾼 변주) -->", s, count=1)
    open(os.path.join(ROOT, "sprite", dst + ".svg"), "w").write(s)


recolor("tree_broad", "tree_broad.2", "밝은 잎", [("#557f2f", "#6f9a36"), ("#a8c86a", "#c4dc80")])
recolor("tree_broad", "tree_broad.3", "짙은 잎", [("#557f2f", "#3f6a2a"), ("#a8c86a", "#86ac58")])
recolor("tree_conifer", "tree_conifer.2", "푸른 잎", [("#2f5a2a", "#2a5a46")])
recolor("tree_jungle", "tree_jungle.2", "밝은 잎", [("#2c5a22", "#3a6e26")])
recolor("house", "house.2", "청회색 지붕", [("#b0482c", "#5a6a7a"), ("#7e2e1c", "#3e4a58")])
recolor("house", "house.3", "초가 지붕", [("#b0482c", "#b8964a"), ("#7e2e1c", "#8a6a2e")])
recolor("tent", "tent.2", "푸른 띠", [("#b04a2c", "#3a6aa0"), ("#8a3a24", "#2a4a70")])
print("ok")
