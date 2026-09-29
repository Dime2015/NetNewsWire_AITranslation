# 图标方向比较板（2026-09-27 第二轮）：四种构造方法完全不同的视觉语言，各画同样 12 个代表性图标，
# 放进真实大小的阅读页底栏与菜单里比较。用户选定方向后再画全套 47 个。
#
# 上一轮四个方向差别很小的原因：四个方向被给了同一套硬规定（圆头圆角线条、线宽 2、同一批参考）。
# 这一轮每个方向的「外层属性」（线宽、端点、转角）和「基本造型方式」（线 / 实心块 / 网点 / 粗细对比笔画）都不一样。
#
# 用法：python3 directions.py  → 生成 directions.html（同目录）
import html
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

KEYS = [
    ("settings", "设置"), ("share", "分享"), ("translate", "翻译"), ("star", "加星标"), ("star-on", "已加星标"),
    ("reader-mode", "阅读模式"), ("long-image", "生成长图"), ("today", "今天"), ("trash", "删除"),
    ("read-off", "未读"), ("read-on", "已读"), ("chevron-down", "下一篇"),
]


def star_points(cx=12, cy=12.8, R=9, r=3.8, rot=-90):
    pts = []
    for i in range(10):
        rad = R if i % 2 == 0 else r
        a = math.radians(rot + i * 36)
        pts.append(f"{cx + rad * math.cos(a):.2f},{cy + rad * math.sin(a):.2f}")
    return " ".join(pts)


# ------------------------------------------------------------------ A 细线直角
A_ATTRS = 'fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="butt" stroke-linejoin="miter" stroke-miterlimit="10"'
A = {
    "settings": '<path d="M3.5 8h17M3.5 16h17"/><rect x="6.5" y="6" width="4" height="4" fill="currentColor" stroke="none"/>'
                '<rect x="13.5" y="14" width="4" height="4" fill="currentColor" stroke="none"/>',
    "share": '<path d="M7.5 10.5h-3v10h15v-10h-3"/><path d="M12 15V3.5M8 7.5l4-4 4 4"/>',
    "translate": '<path d="M3 17.5 7.25 6 11.5 17.5M4.6 13.2h5.3"/><path d="M13.5 7.5h7M17 5v2.5M14 10.5l6 7M20 10.5l-6 7"/>',
    "star": f'<polygon points="{star_points()}"/>',
    "star-on": f'<polygon points="{star_points()}" fill="currentColor"/>',
    "reader-mode": '<path d="M3.5 6h17M3.5 10h17M3.5 14h17M3.5 18h9"/>',
    "long-image": '<rect x="7" y="2.75" width="10" height="18.5"/><path d="M7 9h10M7 15h10"/>',
    "today": '<path d="M3.5 16h17"/><path d="M7.5 16a4.5 4.5 0 0 1 9 0"/><path d="M12 5.5v3M5.8 8.3l2 2M18.2 8.3l-2 2"/>',
    "trash": '<path d="M3.5 7h17M9.5 7V3.75h5V7M6.5 7v13.25h11V7"/>',
    "read-off": '<circle cx="12" cy="12" r="6.5"/>',
    "read-on": '<circle cx="12" cy="12" r="6.5" fill="currentColor"/>',
    "chevron-down": '<path d="M5 8.5 12 15.5 19 8.5"/>',
}

# ------------------------------------------------------------------ B 实心剪影（镂空一律用 mask）
B_ATTRS = 'fill="currentColor" stroke="none"'
B = {
    "settings": '<mask id="b-set"><rect width="24" height="24" fill="white"/><circle cx="12" cy="12" r="3.2" fill="black"/>'
                '<rect x="11" y="2" width="2" height="4.5" fill="black"/></mask><circle cx="12" cy="12" r="9" mask="url(#b-set)"/>',
    "share": '<mask id="b-share"><rect width="24" height="24" fill="white"/><rect x="9.5" y="10" width="5" height="4.5" fill="black"/></mask>'
             '<rect x="3.5" y="11" width="17" height="10" rx="2" mask="url(#b-share)"/>'
             '<polygon points="12,2.5 17,8 13.3,8 13.3,15 10.7,15 10.7,8 7,8"/>',
    "translate": '<mask id="b-tr-back"><rect width="24" height="24" fill="white"/><rect x="2" y="6.5" width="14.5" height="14.5" rx="3" fill="black"/></mask>'
                 '<rect x="9" y="3" width="11.5" height="11.5" rx="2" mask="url(#b-tr-back)"/>'
                 '<mask id="b-tr-a"><rect width="24" height="24" fill="white"/><path d="M6.6 16.5 9.25 10 11.9 16.5M7.7 14.2h3.1" fill="none" stroke="black" stroke-width="1.8" stroke-linecap="square"/></mask>'
                 '<rect x="3.5" y="8" width="11.5" height="11.5" rx="2" mask="url(#b-tr-a)"/>',
    "star": f'<mask id="b-star"><rect width="24" height="24" fill="white"/><polygon points="{star_points(R=5.2, r=2.2)}" fill="black"/></mask>'
            f'<polygon points="{star_points()}" mask="url(#b-star)"/>',
    "star-on": f'<polygon points="{star_points()}"/>',
    "reader-mode": '<rect x="3.5" y="4.75" width="17" height="2.5"/><rect x="3.5" y="8.75" width="17" height="2.5"/>'
                   '<rect x="3.5" y="12.75" width="17" height="2.5"/><rect x="3.5" y="16.75" width="9" height="2.5"/>',
    "long-image": '<mask id="b-long"><rect width="24" height="24" fill="white"/><rect x="6" y="8.5" width="12" height="1.4" fill="black"/>'
                  '<rect x="6" y="14.1" width="12" height="1.4" fill="black"/></mask><rect x="7" y="2.5" width="10" height="19" rx="1" mask="url(#b-long)"/>',
    "today": '<path d="M6.5 15.5a5.5 5.5 0 0 1 11 0z"/><rect x="3" y="17" width="18" height="2.4"/>',
    "trash": '<rect x="4" y="5.2" width="16" height="2.4"/><rect x="9.5" y="2.8" width="5" height="2"/>'
             '<polygon points="6.3,9 17.7,9 16.7,21.2 7.3,21.2"/>',
    "read-off": '<mask id="b-ring"><rect width="24" height="24" fill="white"/><circle cx="12" cy="12" r="4" fill="black"/></mask>'
                '<circle cx="12" cy="12" r="6.8" mask="url(#b-ring)"/>',
    "read-on": '<circle cx="12" cy="12" r="6.8"/>',
    "chevron-down": '<path d="M4.5 8 12 15.5 19.5 8" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="butt" stroke-linejoin="miter"/>',
}


# ------------------------------------------------------------------ C 印刷网点（7×7 点阵，点距 3；状态靠网点大小：小点 = 浅网，大点 = 深网）
def dots(rows, r=1.2, big=None, big_r=1.75):
    out = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "#":
                rr = big_r if big and (x, y) in big else r
                out.append(f'<circle cx="{3 + x * 3}" cy="{3 + y * 3}" r="{rr}"/>')
    return "".join(out)


STAR_BITMAP = ["...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", ".#...#."]
DISC = ["..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###.."]
RING = ["..###..", ".#...#.", "#.....#", "#.....#", "#.....#", ".#...#.", "..###.."]
C_ATTRS = 'fill="currentColor" stroke="none"'
C = {
    "settings": dots([".......", "#######", ".......", ".......", ".......", "#######", "......."], big={(2, 1), (4, 5)}, big_r=2.1),
    "share": dots(["...#...", "..###..", ".#.#.#.", "...#...", "#..#..#", "#.....#", "#######"]),
    "translate": dots([".....#.", "....###", ".#..#.#", "#.#..#.", "###.#.#", "#.#....", "#.#...."]),
    "star": dots(STAR_BITMAP, r=0.8),
    "star-on": dots(STAR_BITMAP, r=1.45),
    "reader-mode": dots(["#######", ".......", "#######", ".......", "#######", ".......", "####..."]),
    "long-image": dots([".#####.", ".#...#.", ".#...#.", ".#####.", ".#...#.", ".#...#.", ".#####."]),
    "today": dots([".......", "...#...", ".......", "..###..", ".#####.", "#######", "......."]),
    "trash": dots(["..###..", "#######", ".#...#.", ".#...#.", ".#...#.", ".#...#.", ".#####."]),
    "read-off": dots(RING, r=1.2),
    "read-on": dots(DISC, r=1.35),
    "chevron-down": dots([".......", "#.....#", ".#...#.", "..#.#..", "...#...", ".......", "......."]),
}


# ------------------------------------------------------------------ D 衬线笔画（粗细对比：竖 / 撇捺粗 3，横 / 发丝线细 1.1；平头；一个实心「句点」作记号）
D_ATTRS = 'fill="none" stroke="currentColor" stroke-width="1.1" stroke-linecap="butt" stroke-linejoin="miter" stroke-miterlimit="10"'


def thick(x1, y1, x2, y2, w=3.0):
    """一道粗笔画（平头平行四边形）。"""
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    nx, ny = -dy / length * w / 2, dx / length * w / 2
    pts = [(x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)]
    return '<polygon points="' + " ".join(f"{x:.2f},{y:.2f}" for x, y in pts) + '" fill="currentColor" stroke="none"/>'


D = {
    "settings": '<path d="M3.5 8h17M3.5 16h17"/><rect x="7.5" y="4.5" width="3" height="7" fill="currentColor" stroke="none"/>'
                '<rect x="13.5" y="12.5" width="3" height="7" fill="currentColor" stroke="none"/>',
    "share": '<path d="M7.5 11H5.5v9h13v-9h-2"/>' + thick(12, 16, 12, 7.5) + '<polygon points="12,2.5 16,8 8,8" fill="currentColor" stroke="none"/>',
    "translate": '<path d="M3 17.3 6.9 5.5M2 17.3h3M8.9 17.3h4.3M5.1 13h5.2"/>' + thick(6.9, 5.2, 11.2, 17.3, 2.6)
                 + '<path d="M13.2 7.6h7.4M14.6 16 19.6 8.6"/>' + thick(14.3, 9.2, 20.2, 16, 2.4)
                 + '<rect x="16.3" y="3.8" width="1.6" height="2.6" fill="currentColor" stroke="none"/>',
    "star": f'<polygon points="{star_points()}"/>',
    "star-on": f'<polygon points="{star_points()}" fill="currentColor" stroke="none"/>',
    "reader-mode": '<rect x="3.5" y="4.6" width="17" height="2.8" fill="currentColor" stroke="none"/><path d="M3.5 10.5h17M3.5 14.5h17M3.5 18.5h9"/>',
    "long-image": '<rect x="6.75" y="2.75" width="10.5" height="18.5"/><rect x="6.75" y="2.75" width="10.5" height="3.2" fill="currentColor" stroke="none"/>'
                  '<path d="M9 9.5h6M9 12.5h6M9 15.5h3.5"/>',
    "today": '<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="2.4" fill="currentColor" stroke="none"/>',
    "trash": '<rect x="3.5" y="5" width="17" height="2.8" fill="currentColor" stroke="none"/><path d="M9.5 5V3h5v2M6.5 7.8l1 13.2h9l1-13.2"/>'
             '<path d="M10.3 10.5v7.5M13.7 10.5v7.5"/>',
    "read-off": '<circle cx="12" cy="12" r="6.5"/>',
    "read-on": '<circle cx="12" cy="12" r="6.5" fill="currentColor" stroke="none"/>',
    "chevron-down": '<path d="M5 8.5 12 16"/>' + thick(12, 16, 19.2, 8.2, 2.8),
}

DIRECTIONS = [
    ("A", "细线直角", A_ATTRS, A,
     "像建筑图纸和瑞士平面设计：1.5 的细线、平头方端、锐利直角，没有圆角；状态用「实心小方块 / 实心面」表达。冷静、精确、理性。"),
    ("B", "实心剪影", B_ATTRS, B,
     "像奥运会和日本公共标识：全部是实心几何块，意思靠挖出来的负空间表达（设置 = 带孔的旋钮，长图 = 被切成三段的竖条）。醒目、有分量，小尺寸下最清楚。"),
    ("C", "印刷网点", C_ATTRS, C,
     "取自报纸印刷的网点：每个图标由 7×7 的圆点拼成。状态靠「网点密度」——没选中是浅网（小点），选中是深网（大点）。最有辨识度，带一点科技感。"),
    ("D", "衬线笔画", D_ATTRS, D,
     "像铅字：粗细对比强烈——竖画、撇捺粗，横画是发丝线，平头方端，呼应 App 图标里粗衬线的「B.」。阅读模式是「一道粗标题线 + 三道细正文线」，今天是天文学的太阳记号 ☉。"),
]


def svg(attrs, body, size):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 24 24" {attrs}>{body}</svg>'


def section(code, name, attrs, icons, note):
    big = "".join(f'<figure>{svg(attrs, icons[k], 44)}<figcaption>{label}</figcaption></figure>' for k, label in KEYS)
    real = "".join(svg(attrs, icons[k], 20) for k, _ in KEYS)
    bar = "".join(svg(attrs, icons[k], 21) for k in ["read-off", "star", "chevron-down", "reader-mode", "translate"])
    menu_rows = [("settings", "设置"), ("share", "分享"), ("star", "加星标"), ("long-image", "生成长图"), ("trash", "取消订阅该源")]
    menu = "".join(f'<div class="row{" danger" if k == "trash" else ""}">{svg(attrs, icons[k], 18)}<span>{t}</span></div>' for k, t in menu_rows)
    states = "".join(f'<div class="st">{svg(attrs, icons[a], 26)}<span class="arrow">→</span>{svg(attrs, icons[b], 26)}<span class="lbl">{t}</span></div>'
                     for a, b, t in [("read-off", "read-on", "未读 → 已读"), ("star", "star-on", "加星标 → 已加星标")])
    return f'''<section>
<h2><span class="code">{code}</span>{html.escape(name)}</h2>
<p class="note">{html.escape(note)}</p>
<div class="big">{big}</div>
<div class="panels">
  <div class="panel"><div class="lab">实际大小（20pt）</div><div class="real">{real}</div></div>
  <div class="panel"><div class="lab">阅读页底栏（21pt）</div><div class="bar">{bar}</div></div>
  <div class="panel"><div class="lab">菜单（18pt）</div>{menu}</div>
  <div class="panel"><div class="lab">状态对比</div>{states}</div>
</div>
</section>'''


def page():
    body = "\n".join(section(*d) for d in DIRECTIONS)
    return f'''<!doctype html>
<html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>图标方向比较</title>
<style>
:root {{ --bg:#F5F2F1; --card:#FFFFFF; --ink:#3A3A3A; --muted:#787878; --faint:#A3A0A1; --line:#E0DDDD; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#1C1C1C; --card:#262626; --ink:#D8D8D8; --muted:#8E8E8E; --faint:#6C6C6C; --line:#3A3A3A; }} }}
:root[data-theme="dark"] {{ --bg:#1C1C1C; --card:#262626; --ink:#D8D8D8; --muted:#8E8E8E; --faint:#6C6C6C; --line:#3A3A3A; }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.6 -apple-system,"PingFang SC",system-ui,sans-serif; }}
main {{ max-width:1000px; margin:0 auto; padding:28px 16px 80px; }}
header {{ display:flex; justify-content:space-between; align-items:baseline; gap:12px; flex-wrap:wrap; }}
h1 {{ font-size:24px; margin:0; font-weight:650; }}
.lead {{ color:var(--muted); margin:10px 0 0; }}
.toggle {{ display:inline-flex; border:1px solid var(--line); border-radius:999px; overflow:hidden; }}
.toggle button {{ border:0; background:transparent; color:var(--muted); padding:6px 14px; font:inherit; font-size:13px; cursor:pointer; }}
.toggle button[aria-pressed="true"] {{ background:var(--ink); color:var(--bg); }}
section {{ margin-top:36px; padding-top:24px; border-top:1px solid var(--line); }}
h2 {{ font-size:20px; margin:0; display:flex; align-items:center; gap:12px; }}
.code {{ display:inline-grid; place-items:center; width:30px; height:30px; border-radius:50%; background:var(--ink); color:var(--bg); font-size:15px; }}
.note {{ color:var(--muted); margin:8px 0 16px; max-width:720px; }}
.big {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(min(84px,100%),1fr)); gap:8px; }}
figure {{ margin:0; background:var(--card); border:1px solid var(--line); border-radius:12px; padding:14px 6px 8px; text-align:center; color:var(--ink); }}
figcaption {{ font-size:12px; color:var(--muted); margin-top:6px; }}
.panels {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(min(220px,100%),1fr)); gap:8px; margin-top:8px; }}
.panel {{ background:var(--card); border:1px solid var(--line); border-radius:12px; padding:12px 14px; color:var(--muted); }}
.lab {{ font-size:12px; color:var(--faint); margin-bottom:8px; }}
.real {{ display:flex; flex-wrap:wrap; gap:10px; }}
.bar {{ display:flex; justify-content:space-between; align-items:center; padding:4px 0; }}
.row {{ display:flex; align-items:center; gap:10px; padding:4px 0; color:var(--ink); }}
.row svg {{ color:var(--muted); }}
.row.danger, .row.danger svg {{ color:#E75C57; }}
.st {{ display:flex; align-items:center; gap:8px; padding:4px 0; color:var(--ink); }}
.arrow {{ color:var(--faint); }}
.lbl {{ color:var(--muted); font-size:13px; margin-left:6px; }}
</style></head>
<body><main>
<header><h1>图标方向比较 · 四种构造方法</h1>
<div class="toggle" role="group" aria-label="外观"><button data-mode="auto" aria-pressed="true">跟随系统</button><button data-mode="light" aria-pressed="false">浅色</button><button data-mode="dark" aria-pressed="false">深色</button></div></header>
<p class="lead">每个方向画同样 12 个代表性图标，并放进实际大小的底栏和菜单里。选定一个方向（或说「A 的某某 + C 的某某」）后，再把全部 47 个按它画完。</p>
{body}
</main>
<script>
(function(){{var r=document.documentElement,b=document.querySelectorAll('.toggle button');
function a(m){{if(m==='auto')r.removeAttribute('data-theme');else r.setAttribute('data-theme',m);b.forEach(function(x){{x.setAttribute('aria-pressed',String(x.dataset.mode===m));}});try{{localStorage.setItem('babel-dir-mode',m);}}catch(e){{}}}}
b.forEach(function(x){{x.addEventListener('click',function(){{a(x.dataset.mode);}});}});
var s=null;try{{s=localStorage.getItem('babel-dir-mode');}}catch(e){{}}if(s)a(s);}})();
</script>
</body></html>'''


if __name__ == "__main__":
    for code, _, _, icons, _ in DIRECTIONS:
        missing = [k for k, _ in KEYS if k not in icons]
        assert not missing, (code, missing)
    with open(os.path.join(HERE, "directions.html"), "w") as f:
        f.write(page())
    print("ok")
