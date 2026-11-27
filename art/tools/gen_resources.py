#!/usr/bin/env python3
"""채집 식량 자원 그림 (art/tiles/resource/*.svg) 을 만든다.

256x256, 세워 그리는 그림. 바닥에 닿는 점이 (128,244).
화풍은 sprite/ 의 나무·집 그림과 같게: 진한 갈색 외곽선, 평평한 색, 밝은 쪽 하이라이트.
진짜 그림으로 바꿀 때는 같은 이름의 PNG 를 넣으면 된다 (PNG 가 SVG 보다 먼저 쓰인다).
"""
import math
import os
import random

OUT = os.path.join(os.path.dirname(__file__), "..", "tiles", "resource")
INK = "#4a3218"


def svg(name, note, body):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">\n')
        f.write(f"<!-- {note} (art/tools/gen_resources.py 로 생성한 임시 그림). 바닥 점 (128,244) -->\n")
        f.write(body)
        f.write("\n</svg>\n")


def shadow(cx=128, cy=240, rx=70, ry=12):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#1e1408" opacity="0.28"/>\n'


def f2(v):
    return f"{v:.1f}"


# ---------------------------------------------------------------- 야생 밀: 고개 숙인 금빛 이삭 한 무더기
def wheat():
    r = random.Random(11)
    s = shadow(rx=64)
    stalks = []
    for k in range(9):
        a = -0.55 + 1.1 * k / 8 + r.uniform(-0.06, 0.06)
        h = r.uniform(150, 190) * (1.0 - 0.25 * abs(a))
        bx = 128 + r.uniform(-14, 14)
        tx = bx + math.sin(a) * h
        ty = 240 - math.cos(a) * h
        stalks.append((abs(a), bx, tx, ty, a))
    stalks.sort(reverse=True)  # 바깥쪽부터 그려 가운데가 앞에 오게
    # 바닥 풀
    for k in range(10):
        x = 128 + r.uniform(-60, 60)
        h = r.uniform(18, 34)
        lean = r.uniform(-10, 10)
        s += f'<path d="M{f2(x-3)},242 Q{f2(x+lean*0.5)},{f2(242-h*0.6)} {f2(x+lean)},{f2(242-h)} Q{f2(x+2)},{f2(242-h*0.5)} {f2(x+4)},242 Z" fill="#7d9a3a" stroke="{INK}" stroke-width="1.5"/>\n'
    for _, bx, tx, ty, a in stalks:
        # 줄기 (끝이 살짝 휜다)
        cx = (bx + tx) / 2 + math.sin(a) * 10
        cy = (240 + ty) / 2
        s += f'<path d="M{f2(bx)},240 Q{f2(cx)},{f2(cy)} {f2(tx)},{f2(ty)}" fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>\n'
        s += f'<path d="M{f2(bx)},240 Q{f2(cx)},{f2(cy)} {f2(tx)},{f2(ty)}" fill="none" stroke="#c89a3a" stroke-width="2.6" stroke-linecap="round"/>\n'
        # 잎 하나
        lx = bx + (tx - bx) * 0.35
        ly = 240 + (ty - 240) * 0.35
        side = 1 if a < 0 else -1
        s += f'<path d="M{f2(lx)},{f2(ly)} q{side*10},-4 {side*30},-30 q{-side*4},20 {-side*30},30 Z" fill="#c4a84a" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round"/>\n'
        # 이삭: 줄기 끝에서 아래로 살짝 숙인 낟알 줄
        ang = a + (0.35 if a >= 0 else -0.35)
        dx, dy = math.sin(ang), -math.cos(ang)
        px, py = -dy, dx
        n = 6
        for g in range(n):
            t = g / (n - 1)
            gx = tx + dx * (6 + t * 34)
            gy = ty + dy * (6 + t * 34)
            sz = 7.5 - t * 3
            for sd in (-1, 1):
                ex = gx + px * sd * 4.5
                ey = gy + py * sd * 4.5
                rot = math.degrees(math.atan2(dy, dx)) + 90 + sd * 22
                s += f'<ellipse cx="{f2(ex)}" cy="{f2(ey)}" rx="{f2(sz*0.55)}" ry="{f2(sz)}" transform="rotate({f2(rot)} {f2(ex)} {f2(ey)})" fill="#f0c447" stroke="{INK}" stroke-width="1.6"/>\n'
                # 까끄라기
                s += f'<path d="M{f2(ex)},{f2(ey)} l{f2(dx*14+px*sd*8)},{f2(dy*14+py*sd*8)}" stroke="#9a7426" stroke-width="1.1"/>\n'
        # 하이라이트
        s += f'<circle cx="{f2(tx+dx*12-px*3)}" cy="{f2(ty+dy*12-py*3)}" r="2.2" fill="#fff3b8"/>\n'
    return s


# ---------------------------------------------------------------- 야생 쌀: 얕은 물웅덩이 위로 늘어진 벼 이삭
def rice():
    r = random.Random(23)
    s = '<ellipse cx="128" cy="232" rx="104" ry="22" fill="#4f9aa6" stroke="' + INK + '" stroke-width="2.5"/>\n'
    s += '<ellipse cx="120" cy="228" rx="80" ry="13" fill="#6fb8bc"/>\n'
    s += '<path d="M60,236 q18,-6 36,0 M150,238 q16,-5 32,0 M98,224 q12,-4 24,0" stroke="#d4f0ee" stroke-width="2.2" fill="none" stroke-linecap="round"/>\n'
    blades = []
    for k in range(11):
        a = -0.7 + 1.4 * k / 10 + r.uniform(-0.05, 0.05)
        h = r.uniform(120, 175) * (1 - 0.3 * abs(a))
        bx = 128 + r.uniform(-18, 18)
        blades.append((abs(a), a, h, bx))
    blades.sort(reverse=True)
    for _, a, h, bx in blades:
        tx = bx + math.sin(a) * h
        ty = 230 - math.cos(a) * h
        cx = bx + math.sin(a) * h * 0.4
        cy = 230 - h * 0.55
        w = 8.0
        s += (f'<path d="M{f2(bx-w)},230 Q{f2(cx-w*0.5)},{f2(cy)} {f2(tx)},{f2(ty)} '
              f'Q{f2(cx+w*0.5)},{f2(cy)} {f2(bx+w)},230 Z" fill="#5f9a34" stroke="{INK}" stroke-width="1.6"/>\n')
        s += f'<path d="M{f2(bx)},228 Q{f2(cx)},{f2(cy+6)} {f2(tx)},{f2(ty+4)}" stroke="#9ccc5a" stroke-width="1.4" fill="none"/>\n'
    # 늘어진 이삭 다섯 줄기
    for k, (bx, top, hang) in enumerate([(104, 70, -1), (128, 52, 1), (150, 66, 1), (90, 96, -1), (168, 92, 1)]):
        tip_x = bx + hang * 44
        tip_y = top + 60
        s += f'<path d="M{bx},228 Q{bx+hang*4},{top+30} {bx+hang*10},{top} Q{bx+hang*36},{top-6} {tip_x},{tip_y}" stroke="{INK}" stroke-width="4" fill="none" stroke-linecap="round"/>\n'
        s += f'<path d="M{bx},228 Q{bx+hang*4},{top+30} {bx+hang*10},{top} Q{bx+hang*36},{top-6} {tip_x},{tip_y}" stroke="#a8b048" stroke-width="2" fill="none" stroke-linecap="round"/>\n'
        # 낟알: 곡선을 따라 매달린다
        for g in range(9):
            t = g / 8
            u = 1 - t
            x = u * u * (bx + hang * 10) + 2 * u * t * (bx + hang * 36) + t * t * tip_x
            y = u * u * top + 2 * u * t * (top - 6) + t * t * tip_y
            for sd in (-1, 1):
                gx = x + sd * 5
                gy = y + 5
                s += f'<ellipse cx="{f2(gx)}" cy="{f2(gy)}" rx="3.4" ry="5.6" transform="rotate({f2(sd*25 + hang*20)} {f2(gx)} {f2(gy)})" fill="#efe2a0" stroke="{INK}" stroke-width="1.3"/>\n'
    return s


# ---------------------------------------------------------------- 나무 열매: 열매가 송이송이 달린 덤불
def berry():
    r = random.Random(37)
    s = shadow(rx=80, ry=14)
    leaves = [(128, 150, 62), (82, 178, 48), (174, 178, 48), (104, 118, 44), (154, 120, 44), (128, 196, 52), (62, 206, 34), (194, 206, 34)]
    for x, y, rad in leaves:
        s += f'<circle cx="{x}" cy="{y}" r="{rad}" fill="#2f6a2c" stroke="{INK}" stroke-width="3"/>\n'
    for x, y, rad in leaves:
        s += f'<circle cx="{x}" cy="{y}" r="{rad-3}" fill="#3f8236"/>\n'
    for x, y, rad in leaves:
        s += f'<path d="M{x-rad*0.6},{y-rad*0.2} A{rad*0.7},{rad*0.7} 0 0 1 {x+rad*0.2},{y-rad*0.65}" stroke="#6eae4c" stroke-width="5" fill="none" stroke-linecap="round"/>\n'
    # 잎맥이 보이는 낱잎
    for _ in range(14):
        x = r.uniform(50, 206)
        y = r.uniform(100, 225)
        if (x - 128) ** 2 / 85 ** 2 + (y - 170) ** 2 / 80 ** 2 > 1:
            continue
        a = r.uniform(0, 360)
        s += f'<g transform="translate({f2(x)},{f2(y)}) rotate({f2(a)})"><path d="M0,0 q8,-10 0,-22 q-8,12 0,22 Z" fill="#4f9440" stroke="{INK}" stroke-width="1.3"/><path d="M0,-2 L0,-18" stroke="#2a5a24" stroke-width="1"/></g>\n'
    # 열매 송이
    for cx, cy in [(96, 140), (150, 112), (176, 176), (112, 196), (140, 160), (72, 188)]:
        pts = [(0, 0), (-9, 7), (9, 7), (0, 14), (-7, -8), (8, -7)]
        for dx, dy in pts:
            x, y = cx + dx, cy + dy
            s += f'<circle cx="{x}" cy="{y}" r="7.5" fill="#b4245a" stroke="#4a0c24" stroke-width="2"/>\n'
            s += f'<circle cx="{x-2.5}" cy="{y-2.5}" r="2.3" fill="#f6a8c6"/>\n'
    return s


# ---------------------------------------------------------------- 물고기: 물결 위로 뛰어오르는 물고기
def fish():
    s = ""
    # 물결 고리 (물 칸 위에 놓이므로 물 자체는 그리지 않는다)
    s += '<ellipse cx="128" cy="232" rx="96" ry="16" fill="none" stroke="#e8f8fa" stroke-width="4" opacity="0.9"/>\n'
    s += '<ellipse cx="128" cy="232" rx="62" ry="10" fill="none" stroke="#e8f8fa" stroke-width="3.5" opacity="0.8"/>\n'
    s += '<ellipse cx="128" cy="232" rx="30" ry="5" fill="#cdeef2" opacity="0.8"/>\n'
    # 물보라
    for x, y, rr in [(88, 214, 6), (100, 196, 4.5), (170, 214, 6), (158, 198, 4.5), (124, 206, 5), (186, 196, 3.5), (70, 198, 3.5)]:
        s += f'<circle cx="{x}" cy="{y}" r="{rr}" fill="#eaf8fb" stroke="#4f8ea0" stroke-width="1.5"/>\n'
    # 몸통: 위로 휘어 뛰어오르는 모습
    body = "M66,150 C80,92 150,62 196,92 C206,100 204,116 192,120 C150,104 100,124 78,164 Z"
    s += f'<path d="{body}" fill="#5e9ec4" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>\n'
    # 배 (밝은 색)
    s += '<path d="M80,158 C104,124 150,108 190,118 C150,114 108,132 84,164 Z" fill="#e6f0e8"/>\n'
    # 등 무늬
    s += '<path d="M90,128 C110,98 150,84 184,92" stroke="#2f6a92" stroke-width="7" fill="none" stroke-linecap="round" opacity="0.8"/>\n'
    for x, y in [(110, 112), (128, 102), (146, 96), (164, 94), (120, 124), (140, 112)]:
        s += f'<circle cx="{x}" cy="{y}" r="2.6" fill="#1f4a6a"/>\n'
    # 꼬리
    s += f'<path d="M72,156 L36,178 L50,150 L34,124 Z" fill="#4a88b0" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>\n'
    s += '<path d="M66,152 L44,166 M64,146 L42,134" stroke="#2f6a92" stroke-width="2"/>\n'
    # 지느러미
    s += f'<path d="M132,82 C138,62 160,60 170,74 C158,74 146,78 140,90 Z" fill="#4a88b0" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>\n'
    s += f'<path d="M150,118 C150,132 142,140 130,140 C136,130 138,124 138,116 Z" fill="#4a88b0" stroke="{INK}" stroke-width="2.5" stroke-linejoin="round"/>\n'
    # 아가미, 눈, 입
    s += f'<path d="M176,94 C170,102 170,110 176,116" stroke="{INK}" stroke-width="2.5" fill="none"/>\n'
    s += f'<circle cx="186" cy="100" r="6" fill="#ffffff" stroke="{INK}" stroke-width="2"/><circle cx="187.5" cy="100" r="3" fill="#10202c"/>\n'
    s += f'<path d="M198,108 L204,110" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>\n'
    # 반짝임
    s += '<path d="M120,96 C134,86 152,82 166,84" stroke="#bfe4f6" stroke-width="3" fill="none" stroke-linecap="round"/>\n'
    # 떨어지는 물방울
    for x, y in [(60, 176), (50, 192), (42, 166)]:
        s += f'<path d="M{x},{y-6} q5,7 0,10 q-5,-3 0,-10 Z" fill="#d8f2f8" stroke="#4f8ea0" stroke-width="1.3"/>\n'
    return s


# ---------------------------------------------------------------- 조개: 모래톱 위의 가리비와 대합, 진주
def shell():
    s = '<ellipse cx="128" cy="226" rx="104" ry="26" fill="#e6d29a" stroke="' + INK + '" stroke-width="2.5"/>\n'
    s += '<ellipse cx="120" cy="220" rx="78" ry="14" fill="#f2e4b6"/>\n'
    for x, y in [(56, 228), (70, 236), (196, 230), (182, 238), (150, 240), (100, 240)]:
        s += f'<circle cx="{x}" cy="{y}" r="2" fill="#b89c62"/>\n'

    def scallop(cx, cy, sc, col, dark, rot=0):
        o = f'<g transform="translate({cx},{cy}) rotate({rot}) scale({sc})">'
        o += f'<path d="M-14,0 L-20,8 L-8,8 Z M14,0 L20,8 L8,8 Z" fill="{col}" stroke="{INK}" stroke-width="2.5" stroke-linejoin="round"/>'
        o += f'<path d="M0,6 L-34,-30 C-30,-62 30,-62 34,-30 Z" fill="{col}" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
        for k in range(7):
            a = math.radians(-60 + 120 * k / 6)
            ex = math.sin(a) * 40
            ey = -math.cos(a) * 46 + 6
            o += f'<path d="M0,4 L{f2(ex*0.82)},{f2(ey*0.82)}" stroke="{dark}" stroke-width="3" stroke-linecap="round"/>'
        o += '<path d="M-20,-40 C-10,-50 10,-50 20,-40" stroke="#fff6ee" stroke-width="3" fill="none" stroke-linecap="round" opacity="0.8"/>'
        return o + "</g>\n"

    def clam(cx, cy, sc, rot=0):
        o = f'<g transform="translate({cx},{cy}) rotate({rot}) scale({sc})">'
        # 아래 껍데기와 안쪽
        o += f'<path d="M-30,0 C-30,22 30,22 30,0 Z" fill="#c9b8d8" stroke="{INK}" stroke-width="3"/>'
        o += '<path d="M-24,2 C-22,16 22,16 24,2 Z" fill="#f4ecf6"/>'
        # 진주
        o += f'<circle cx="0" cy="6" r="8" fill="#fbf8f2" stroke="{INK}" stroke-width="2"/><circle cx="-2.5" cy="3.5" r="2.5" fill="#ffffff"/>'
        # 열린 위 껍데기
        o += f'<path d="M-30,0 C-34,-30 -10,-50 8,-48 C28,-46 36,-24 30,0 C20,-14 -20,-14 -30,0 Z" fill="#a98cc4" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
        for k in range(4):
            o += f'<path d="M{-22+k*4},{-6-k*9} C{-12+k*2},{-14-k*9} {14-k*2},{-14-k*9} {24-k*4},{-6-k*9}" stroke="#7a5c98" stroke-width="2" fill="none"/>'
        return o + "</g>\n"

    s += scallop(84, 214, 1.05, "#f4a78e", "#c45f48", -14)
    s += clam(166, 206, 1.15, 8)
    s += scallop(126, 236, 0.62, "#f6d0a4", "#c88a48", 6)
    # 작은 소라
    s += f'<g transform="translate(200,232) rotate(-20)"><path d="M-16,0 C-16,-14 4,-20 14,-8 C20,0 10,6 0,6 C-8,6 -16,4 -16,0 Z" fill="#f0d8b8" stroke="{INK}" stroke-width="2.5"/><path d="M-10,-2 C-6,-10 6,-12 10,-6" stroke="#b08458" stroke-width="2" fill="none"/></g>\n'
    return s


svg("wheat", "야생 밀", wheat())
svg("rice", "야생 쌀", rice())
svg("berry", "나무 열매 덤불", berry())
svg("fish", "물고기 (물 칸 위에 세워 그림)", fish())
svg("shell", "조개 (모래톱 위)", shell())
print("ok")
