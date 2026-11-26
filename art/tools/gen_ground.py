"""바닥 그림(이음매 없이 반복되는 256x256 SVG)을 만든다.  python3 art/tools/gen_ground.py
가장자리에 걸친 무늬는 반대편에도 그려서 타일처럼 이어 붙여도 이음매가 보이지 않는다."""
import random, math, os

OUT = os.path.join(os.path.dirname(__file__), "..", "tiles", "ground")
S = 256


def wrap(draw, x, y, r):
    out = []
    for dx in (-S, 0, S):
        for dy in (-S, 0, S):
            if -r <= x + dx <= S + r and -r <= y + dy <= S + r:
                out.append(draw(x + dx, y + dy))
    return "".join(out)


def blobs(rnd, n, cols, rmin, rmax, op):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        rx, ry = rnd.uniform(rmin, rmax), rnd.uniform(rmin, rmax) * 0.7
        c = rnd.choice(cols)
        a = rnd.uniform(0, 180)
        s += wrap(lambda X, Y: f'<ellipse cx="{X:.1f}" cy="{Y:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{c}" opacity="{op}" transform="rotate({a:.0f} {X:.1f} {Y:.1f})"/>', x, y, rmax)
    return s


def blades(rnd, n, cols, ln):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        c = rnd.choice(cols)
        dx, l = rnd.uniform(-3, 3), rnd.uniform(ln * 0.6, ln)
        s += wrap(lambda X, Y: f'<path d="M{X:.1f},{Y:.1f} q{dx/2:.1f},{-l/2:.1f} {dx:.1f},{-l:.1f}" stroke="{c}" stroke-width="1.3" fill="none" stroke-linecap="round"/>', x, y, ln)
    return s


def specks(rnd, n, cols, rmax):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        c, r = rnd.choice(cols), rnd.uniform(0.6, rmax)
        s += wrap(lambda X, Y: f'<circle cx="{X:.1f}" cy="{Y:.1f}" r="{r:.1f}" fill="{c}"/>', x, y, rmax)
    return s


def ripples(rnd, n, col):
    s = ""
    for _ in range(n):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        w = rnd.uniform(14, 30)
        s += wrap(lambda X, Y: f'<path d="M{X-w:.1f},{Y:.1f} q{w/2:.1f},-4 {w:.1f},0 t{w:.1f},0" stroke="{col}" stroke-width="1.4" fill="none" opacity="0.55"/>', x, y, 2 * w)
    return s


def svg(name, note, base, body):
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">\n'
                f'<!-- {note} (art/tools/gen_ground.py 로 생성) -->\n<rect width="{S}" height="{S}" fill="{base}"/>\n{body}\n</svg>\n')


os.makedirs(OUT, exist_ok=True)
r = random.Random(7)
svg("grass", "바닥: 초원 (습윤)", "#7da24a",
    blobs(r, 40, ["#6d9440", "#8cb052", "#76a046", "#94b65a"], 14, 34, 0.5) + specks(r, 90, ["#5f8a36", "#a6c466"], 1.6)
    + blades(r, 220, ["#5b8530", "#6f9a3a", "#9cc05c"], 6))
r = random.Random(8)
svg("plains", "바닥: 평원 (반건조)", "#a9a258",
    blobs(r, 40, ["#9a9450", "#b8ae62", "#a0a858", "#c2b46a"], 14, 34, 0.5) + specks(r, 120, ["#8a7c44", "#c8bc78", "#7a8a40"], 1.6)
    + blades(r, 160, ["#8a8a40", "#b0a250", "#c8b664"], 5))
r = random.Random(9)
svg("desert", "바닥: 사막 (건조)", "#d9c28a",
    blobs(r, 36, ["#cfb67c", "#e4cf9a", "#d2b878", "#e8d6a6"], 18, 40, 0.55) + ripples(r, 40, "#b89c62")
    + specks(r, 70, ["#a88a58", "#efe0b8"], 1.4))
r = random.Random(10)
svg("tundra", "바닥: 툰드라 (한대)", "#949a78",
    blobs(r, 50, ["#86906a", "#a2a684", "#7a8a62", "#aaa890", "#8e7e68"], 10, 26, 0.55) + specks(r, 110, ["#6a6a5a", "#b8b8a8", "#7a5a4a"], 1.8))
r = random.Random(11)
svg("snow", "바닥: 눈과 얼음", "#eef1f3",
    blobs(r, 40, ["#dfe6ee", "#f8fafc", "#d6dee8"], 16, 40, 0.6) + ripples(r, 24, "#c4d0de"))
r = random.Random(12)
svg("rock", "바닥: 산지 바위", "#8c8272",
    blobs(r, 50, ["#7a7062", "#a09684", "#6a6256", "#b0a690"], 10, 28, 0.6) + specks(r, 140, ["#5a5248", "#c4bcae"], 2.0)
    + "".join(wrap(lambda X, Y: f'<path d="M{X:.1f},{Y:.1f} l{r.uniform(-12,12):.1f},{r.uniform(4,12):.1f} l{r.uniform(-8,8):.1f},{r.uniform(4,10):.1f}" stroke="#4e463c" stroke-width="1.2" fill="none" opacity="0.6"/>', r.uniform(0, S), r.uniform(0, S), 30) for _ in range(30)))
print("ok")
