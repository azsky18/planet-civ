"""임시 그림 만들기.  python3 art/tools/gen_placeholders.py

손으로 그린 그림(art/tiles/decal, sprite 의 기본 그림)은 건드리지 않고, 아래처럼 수가 많은
그림만 만든다. 나중에 진짜 그림이 생기면 같은 이름의 파일을 덮어쓰면 된다.

  ground/<바닥>.svg, <바닥>.2.svg ...      이음매 없이 반복되는 바닥 무늬와 변주
  ground/<물>.svg, ground/shore_<물가>.svg  물 무늬와 물가 땅 무늬 (같이 반복)
  decal/river.svg                           강물 띠
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


# ---------------------------------------------------------------- 물과 물가 무늬 (바닥처럼 이음매 없이 반복)
# 꼭짓점 합성에서 물 칸은 물 무늬, 땅과 물이 만나는 곳의 땅 쪽은 물가 무늬로 칠한다.

WATERS = {
    "deep": ("#1d4468", ["#173a5c", "#24507a", "#1a3f62"],
             lambda r: ripples(r, 50, "#5f8cb0", op=0.45, w0=8, w1=18, sw=1.4) + ripples(r, 30, "#0e2840", op=0.4, w0=10, w1=20, sw=1.6)),
    "shallow": ("#3f8c9a", ["#4a9aa6", "#388090", "#58a8ae"],
                lambda r: ripples(r, 50, "#a8dcd8", op=0.4, w0=6, w1=14, sw=1.3) + blobs(r, 14, ["#6ab8b4"], 10, 24, 0.3)),
    "lake": ("#3f7f9a", ["#46889e", "#38728c"], lambda r: ripples(r, 30, "#b4dce6", op=0.35, w0=6, w1=12, sw=1.2)),
    "ice": ("#e6eef2", ["#f4f8fa", "#d4e2ea", "#c8d8e4"],
            lambda r: cracks(r, 40, "#9ab4c6") + blobs(r, 10, ["#b8d0e0"], 10, 24, 0.4)),
}
WATER_NOTE = {"deep": "깊은 바다", "shallow": "얕은 바다", "lake": "호수", "ice": "해빙"}
SHORES = {
    "sand": ("#e2cf96", ["#ecdcaa", "#d6c088", "#f0e2b8"], lambda r: specks(r, 80, ["#b89c62", "#fff4d8"], 1.4)),
    "grass": ("#a8b070", ["#b8b680", "#98a462", "#c4bc8c"], lambda r: specks(r, 120, ["#8a8474", "#d8d0b8"], 2.0) + blades(r, 80, ["#6f9a3a", "#8ab443"], 6)),
    "mud": ("#6e6248", ["#5a5038", "#7a6c4c", "#4e5a48", "#86785a"], lambda r: ripples(r, 20, "#9aa89c", op=0.4) + blades(r, 60, ["#6a7a3a", "#5a6a2a"], 9)),
    "rock": ("#6e675c", ["#5e584e", "#847c70", "#4e4840"], lambda r: specks(r, 160, ["#3e382f", "#a49c8e"], 3.0) + cracks(r, 40, "#2e2a24")),
    "ice": ("#f2f6f8", ["#e4eef4", "#ffffff", "#d0dee8"], lambda r: cracks(r, 30, "#a8c0d0")),
    "gravel": ("#9a968c", ["#8a8478", "#aaa69c"], lambda r: specks(r, 400, ["#7a766c", "#a8a498", "#c4c0b4", "#6a665e"], 3.0)),
}
SHORE_NOTE = {"sand": "모래 해변", "grass": "풀밭 물가 (자갈 섞인)", "mud": "갯벌·진흙", "rock": "바위 해안", "ice": "얼음 해안", "gravel": "자갈 해안"}


def tex_svg(spec, seed):
    base, cols, extra = spec
    r = random.Random(seed)
    return f'<rect width="{S}" height="{S}" fill="{base}"/>\n' + blobs(r, 40, cols, 12, 36, 0.5) + extra(r)


for k, name in enumerate(WATERS):
    for v in (1, 2):
        out("ground", name if v == 1 else f"{name}.{v}", f"물: {WATER_NOTE[name]}, 변주 {v}", tex_svg(WATERS[name], 500 + 10 * k + v))
for k, name in enumerate(SHORES):
    for v in (1, 2):
        out("ground", f"shore_{name}" + ("" if v == 1 else f".{v}"), f"물가 땅: {SHORE_NOTE[name]}, 변주 {v}", tex_svg(SHORES[name], 600 + 10 * k + v))


out("decal", "river", "강물: 가로로 늘여 쓰는 띠. 가운데가 물, 위아래 끝은 투명",
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
