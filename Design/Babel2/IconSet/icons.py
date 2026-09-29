# Babel 2.0 统一图标集 · 定稿方向「Swiss Precision」（尺规几何）
#
# 2026-09-27 过程：第一稿（圆头线条）被评「过于卡通、拟物、复杂」；四个方向比较后用户认为「瑞士几何」最接近想要的感觉；
# 另画的四种构造方法（细线直角 / 实心剪影 / 印刷网点 / 衬线笔画，见 directions.py）被否。
# 在瑞士几何上只改了 3 处：更换图标（加一个日点，才读得出「图片」）、Reddit（正圆气泡 + 小尾巴，原来像水滴）、
# 刷新 / 恢复默认（箭头臂 4 → 3.25，与其它箭头轻重一致）。
# 试过又退回的：今天改日出（空心半圆像灯罩、实心半日像礼帽）、取消星标去掉斜杠（像一对括号）。
#
# 构造语法（整套只遵守这一份）：
# - 画布 24×24，线宽 2（2026-09-27 用户在手机上比较后从 1.75 加到 2.0），圆头、圆角连接；颜色一律 currentColor（App 里按模板图上色）
# - 只用五种基本形（坐标都是笔画中心线）：
#     大圆 C  半径 8（Ø16；含笔画约 Ø17.75）          圆心 (12,12)
#     小圆 c  半径 6.5（Ø13）
#     方框 S  14×14（5–19）          竖框 P 11×17      横框 L 16×12 / 16×14
#     圆角 R = 2.5（全套唯一的框圆角）
#     直线：只走 0° / 45° / 90°（五角星、字母 A、「文」的斜笔除外）
# - 小实心点 d：半径 1.4；折角箭头：两臂 90°，dx = dy = 4；chevron：两臂 90°，dx = dy = 6
# - 抽象靠减法：一个图标只说一件事；能开口就不封闭；框里不放装饰
# - 镂空（取消星标的斜杠缺口、已订阅的反白勾）直接用几何算出来，不靠 <mask>，放大缩小都锐利
#
# 每个图标：名字、中文语义、用在哪里（审阅页用）、SVG 内容（不含外层 <svg>）。
import math

STROKE = 2.0
H = STROKE / 2

ICONS = []


def icon(name, meaning, where, body, group):
    ICONS.append({"name": name, "meaning": meaning, "where": where, "body": body.strip(), "group": group})


# ---------- 作图工具（尺规：点、圆弧、直线） ----------

def _f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def _pt(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def arc(cx, cy, r, a0, a1):
    """从角度 a0 顺时针画到 a1（屏幕坐标：0° 朝右，90° 朝下）。"""
    x0, y0 = _pt(cx, cy, r, a0)
    x1, y1 = _pt(cx, cy, r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{_f(x0)} {_f(y0)}A{_f(r)} {_f(r)} 0 {large} 1 {_f(x1)} {_f(y1)}"


def arc_ccw(cx, cy, r, a0, a1):
    """从角度 a0 逆时针画到 a1。"""
    x0, y0 = _pt(cx, cy, r, a0)
    x1, y1 = _pt(cx, cy, r, a1)
    large = 1 if (a0 - a1) % 360 > 180 else 0
    return f"M{_f(x0)} {_f(y0)}A{_f(r)} {_f(r)} 0 {large} 0 {_f(x1)} {_f(y1)}"


def dot(x, y, r=1.4):
    return f'<circle cx="{_f(x)}" cy="{_f(y)}" r="{_f(r)}" fill="currentColor" stroke="none"/>'


def star_pts(cx=12, cy=12.6, R=8.5):
    # 正五角星：内外半径比 0.382——每条边都落在同一条直线上（尺规作图的五角星）
    r = R * 0.381966
    return [_pt(cx, cy, R if i % 2 == 0 else r, -90 + i * 36) for i in range(10)]


def poly(pts):
    return " ".join(f"{_f(x)},{_f(y)}" for x, y in pts)


def check_pts(cx, cy, a, b):
    """勾：短臂 a、长臂 b（都走 45°），外接框居中于 (cx, cy)。"""
    vx = cx - (b - a) / 2
    vy = cy + b / 2
    return [(vx - a, vy - a), (vx, vy), (vx + b, vy - b)]


def pl(pts):
    return "M" + "L".join(f"{_f(x)} {_f(y)}" for x, y in pts)


def stroke_outline(pts, h=H):
    """一条折线按「圆头 + 圆角」描边后的外轮廓（闭合路径），用来做 evenodd 镂空。"""
    def side(p):
        segs = []
        for (x0, y0), (x1, y1) in zip(p, p[1:]):
            L = math.hypot(x1 - x0, y1 - y0)
            ux, uy = (x1 - x0) / L, (y1 - y0) / L
            segs.append(((x0, y0), (x1, y1), (ux, uy), (-uy, ux)))
        out = []
        (p0, _, _, n0) = segs[0]
        out.append(("M", (p0[0] + h * n0[0], p0[1] + h * n0[1])))
        for i, (a, b, u, n) in enumerate(segs):
            end = (b[0] + h * n[0], b[1] + h * n[1])
            if i + 1 < len(segs):
                (_, _, u2, n2) = segs[i + 1]
                c = u[0] * u2[1] - u[1] * u2[0]
                start2 = (b[0] + h * n2[0], b[1] + h * n2[1])
                if c > 0:   # 内侧：两条偏移线求交
                    # 解 end + t*u = start2 - s*u2
                    det = u[0] * (-u2[1]) - u[1] * (-u2[0])
                    rx, ry = start2[0] - end[0], start2[1] - end[1]
                    t = (rx * (-u2[1]) - ry * (-u2[0])) / det
                    out.append(("L", (end[0] + t * u[0], end[1] + t * u[1])))
                else:       # 外侧：圆角
                    out.append(("L", end))
                    out.append(("A0", start2))
            else:
                out.append(("L", end))
        (_, b, u, n) = segs[-1]
        out.append(("A0", (b[0] - h * n[0], b[1] - h * n[1])))  # 圆头
        return out

    fwd = side(pts)
    back = side(list(reversed(pts)))[1:]
    d = ""
    for cmd, (x, y) in fwd + back:
        if cmd == "M":
            d += f"M{_f(x)} {_f(y)}"
        elif cmd == "L":
            d += f"L{_f(x)} {_f(y)}"
        else:
            d += f"A{_f(h)} {_f(h)} 0 0 0 {_f(x)} {_f(y)}"
    return d + "Z"   # 反向那一侧自带起点圆头，回到起点闭合


def circle_path(cx, cy, r):
    return f"M{_f(cx - r)} {_f(cy)}A{_f(r)} {_f(r)} 0 1 0 {_f(cx + r)} {_f(cy)}A{_f(r)} {_f(r)} 0 1 0 {_f(cx - r)} {_f(cy)}Z"


def letter_A(x0, y0, w, h, bar=0.64):
    """字母 A：顶点在上，横杠在 bar 高度，横杠两端离开斜边一点（留缝）。"""
    ax = x0 + w / 2
    yb = y0 + h * bar
    k = bar
    xl, xr = ax - (w / 2) * k, ax + (w / 2) * k
    return f"M{_f(x0)} {_f(y0 + h)}L{_f(ax)} {_f(y0)}L{_f(x0 + w)} {_f(y0 + h)}M{_f(xl + 0.5)} {_f(yb)}H{_f(xr - 0.5)}"


def glyph_wen(x0, y0, w, h, s=0.08, bar=0.32):
    """「文」：丶（短斜笔，和横分开）+ 一（横）+ 乂（两笔从横的两端出发、在中间交叉）。
    丶 不用圆点：圆点 + 横 + 叉 会被看成火柴人。"""
    cx = x0 + w / 2
    yb = y0 + h * bar
    d = (f"M{_f(cx - 0.8)} {_f(y0)}L{_f(cx + 0.6)} {_f(yb - 1.9)}"
         f"M{_f(x0)} {_f(yb)}H{_f(x0 + w)}"
         f"M{_f(x0 + w * (1 - s))} {_f(yb)}L{_f(x0 + 0.3)} {_f(y0 + h)}"
         f"M{_f(x0 + w * s)} {_f(yb)}L{_f(x0 + w - 0.3)} {_f(y0 + h)}")
    return f'<path d="{d}"/>'


def clip_half(pts, a, b, g, side):
    """实心多边形在直线 ab 的一侧、离线 g 以外的部分（半平面裁剪），用来把实心星沿斜杠剪开。"""
    (ax, ay), (bx, by) = a, b
    L = math.hypot(bx - ax, by - ay)
    nx, ny = -(by - ay) / L, (bx - ax) / L
    keep = lambda p: side * ((p[0] - ax) * nx + (p[1] - ay) * ny) - g
    out = []
    for i in range(len(pts)):
        p, q = pts[i], pts[(i + 1) % len(pts)]
        dp, dq = keep(p), keep(q)
        if dp >= 0:
            out.append(p)
        if (dp >= 0) != (dq >= 0):
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def corners(x0, y0, x1, y1, arm=2.5, r=2.5):
    """取景框四角：框只留四个圆角和一小段臂，中间全部开口。"""
    d = (f"M{_f(x0)} {_f(y0 + r + arm)}V{_f(y0 + r)}A{_f(r)} {_f(r)} 0 0 1 {_f(x0 + r)} {_f(y0)}H{_f(x0 + r + arm)}"
         f"M{_f(x1 - r - arm)} {_f(y0)}H{_f(x1 - r)}A{_f(r)} {_f(r)} 0 0 1 {_f(x1)} {_f(y0 + r)}V{_f(y0 + r + arm)}"
         f"M{_f(x1)} {_f(y1 - r - arm)}V{_f(y1 - r)}A{_f(r)} {_f(r)} 0 0 1 {_f(x1 - r)} {_f(y1)}H{_f(x1 - r - arm)}"
         f"M{_f(x0 + r + arm)} {_f(y1)}H{_f(x0 + r)}A{_f(r)} {_f(r)} 0 0 1 {_f(x0)} {_f(y1 - r)}V{_f(y1 - r - arm)}")
    return f'<path d="{d}"/>'


# ---------- 共享构件 ----------

STAR = star_pts()
CHECK = check_pts(12, 12, 4, 9)            # 独立的勾：13 × 9
CHECK_IN = check_pts(12, 12, 2.4, 5.4)     # 圆里的勾：同一造型缩到 0.6

# 刷新 / 同步 / 恢复默认：同一段圆弧（半径 7，缺口 45°）；恢复默认 = 刷新的镜像
# 同步（只有圆弧）圆心 (12,12) 原地转；刷新 / 恢复默认多一个往上探的箭头，整体下移 0.5 让视觉重心回到中间
RR = 7
SYNC_ARC = arc(12, 12, RR, 0, 315)
REFRESH_ARC = arc(12, 12.5, RR, 0, 315)
_ex, _ey = _pt(12, 12.5, RR, 315)
REFRESH_HEAD = f"M{_f(_ex - 3.25)} {_f(_ey)}H{_f(_ex)}V{_f(_ey - 3.25)}"
UNDO_ARC = arc_ccw(12, 12.5, RR, 180, 225)
_ux, _uy = _pt(12, 12.5, RR, 225)
UNDO_HEAD = f"M{_f(_ux + 3.25)} {_f(_uy)}H{_f(_ux)}V{_f(_uy - 3.25)}"

# 取消星标：「已加星标」的实心星被一道 45° 斜杠划掉（试过去掉斜杠只留劈开的两块：20px 下像一对括号，认不出是星，已退回）。
# 空心细线星一剪就碎成很多小段（五角星的顶点正好落在 45° 线附近），实心星剪开只剩两块干净的面。
# 斜杠穿过星的中心 (12, 12.6)；两块各离斜杠中线 2.75（减去两边的半笔宽，视觉缝 = 1）
_SA, _SB = (4.5, 5.1), (19.5, 20.1)
STAR_OFF = "".join(f'<polygon points="{poly(p)}" fill="currentColor"/>'
                   for p in (clip_half(STAR, _SA, _SB, 2.75, 1), clip_half(STAR, _SA, _SB, 2.75, -1)) if len(p) > 2)
STAR_OFF += f'<path d="M{_f(_SA[0])} {_f(_SA[1])}L{_f(_SB[0])} {_f(_SB[1])}"/>'

# ---------- 导航与通用 ----------
G = "导航与通用"
icon("back", "返回", "文章列表左上、设置页返回、浏览器后退", '<path d="M15 6 9 12l6 6"/>', G)
icon("forward", "前进 / 进入下一级", "浏览器前进、设置行右侧、首页文件夹展开", '<path d="M9 6l6 6-6 6"/>', G)
icon("chevron-down", "向下 / 下一篇 / 下拉", "阅读页底栏「下一篇」、设置里的下拉选项", '<path d="M6 9l6 6 6-6"/>', G)
icon("close", "关闭 / 取消", "阅读页、图片查看器、浏览器、设置编辑页左上", '<path d="M7 7l10 10M17 7 7 17"/>', G)
icon("more", "更多", "阅读页、文章列表、浏览器右上「•••」", dot(6, 12) + dot(12, 12) + dot(18, 12), G)
icon("check", "勾选 / 保存", "菜单里开关打勾、设置单选、设置编辑页右上「保存」", f'<path d="{pl(CHECK)}"/>', G)
icon("search", "搜索", "文章列表放大镜、添加订阅搜索框", '<circle cx="10.5" cy="10.5" r="6"/><path d="M14.75 14.75 19 19"/>', G)
icon("add", "添加", "首页右上「+」、菜单「添加订阅」", '<path d="M12 6v12M6 12h12"/>', G)
icon("settings", "设置", "首页左上（原齿轮）",
     '<path d="M5 8.5h1.75M11.25 8.5H19M5 15.5h7.75M17.25 15.5H19"/><circle cx="9" cy="8.5" r="2.25"/><circle cx="15" cy="15.5" r="2.25"/>', G)
icon("share", "分享", "阅读页右上、浏览器底栏",
     '<path d="M6.5 11.5V17a2.5 2.5 0 0 0 2.5 2.5h6a2.5 2.5 0 0 0 2.5-2.5v-5.5"/><path d="M12 4.5V14M8 8.5l4-4 4 4"/>', G)
icon("refresh", "刷新", "浏览器刷新、刷新模型列表", f'<path d="{REFRESH_ARC}"/><path d="{REFRESH_HEAD}"/>', G)
icon("sync", "同步中（转动）", "首页标题旁、文章列表顶部刷新按钮", f'<path d="{SYNC_ARC}"/>', G)
icon("arrow-up", "回到顶部", "「↑ N 篇新文章」小胶囊", '<path d="M12 18.5V5.5M8 9.5l4-4 4 4"/>', G)
icon("open-link", "打开链接", "图片查看器右下「打开链接」", '<path d="M7 17 17 7M11.5 7H17v5.5"/>', G)
icon("browser", "在浏览器打开 / 网站", "「打开网站」「打开原文」、浏览器「在 Safari 打开」",
     '<circle cx="12" cy="12" r="8"/><path d="M14.5 9.5 12.75 12.75 9.5 14.5 11.25 11.25z" fill="currentColor"/>', G)

# ---------- 阅读与文章状态 ----------
G = "阅读与文章状态"
icon("read-off", "未读（点一下标为已读）", "阅读页底栏第 1 格", '<circle cx="12" cy="12" r="6.5"/>', G)
icon("read-on", "已读", "阅读页底栏第 1 格（已读时）", '<circle cx="12" cy="12" r="6.5" fill="currentColor"/>', G)
icon("star", "加星标", "阅读页底栏、菜单「加星标」、首页 / 列表底栏星标档、「全部星标」", f'<polygon points="{poly(STAR)}"/>', G)
icon("star-on", "已加星标", "阅读页底栏（已加星标时）、底栏选中的星标档", f'<polygon points="{poly(STAR)}" fill="currentColor"/>', G)
icon("star-off", "取消星标", "菜单「取消星标」", STAR_OFF, G)
icon("reader-mode", "阅读模式", "阅读页底栏第 4 格、「此源总是阅读模式」、设置「阅读页」（四道横线、最后一道短——ADR-049 用户定过的形状，保留）",
     '<path d="M5.5 6h13M5.5 10h13M5.5 14h13M5.5 18h7.5"/>', G)
icon("translate", "翻译", "阅读页底栏最右、列表底栏标题翻译、浏览器「翻译此页」、设置「翻译」",
     # 文 在左上、A 在右边略低；两字之间视觉缝 ≥ 1（算过线段最短距离）；
     # A 的右脚停在 (19.75, 16)，右下角约 6×6 留给 App 的缓存圆点。
     # （试过 A 左下、文 右上：文 太小，在 18–20pt 下会被看成「A×」——编辑器里「清除格式」的样子）
     glyph_wen(3.5, 3.5, 8, 10) + f'<path d="{letter_A(13.25, 6.5, 6.5, 9.5)}"/>', G)
icon("long-image", "生成长图", "阅读页「•••」→ 生成长图",
     corners(6.5, 3.5, 17.5, 20.5), G)
icon("read-all", "全部标为已读", "文章列表底栏左 1", f'<circle cx="12" cy="12" r="8"/><path d="{pl(CHECK_IN)}"/>', G)
icon("unread-dot", "未读档", "首页 / 列表底栏的「● UNREAD」", dot(12, 12, 3), G)
icon("list", "全部 / 列表", "底栏「全部」档、菜单「打开这个源」、设置「文章列表」",
     '<path d="M9.5 7H19M9.5 12H19M9.5 17H19"/>' + dot(5.5, 7) + dot(5.5, 12) + dot(5.5, 17), G)

# ---------- 首页入口 ----------
G = "首页入口"
_RAYS = "".join(f"M{_f(_pt(12, 12, 7, a)[0])} {_f(_pt(12, 12, 7, a)[1])}L{_f(_pt(12, 12, 8.25, a)[0])} {_f(_pt(12, 12, 8.25, a)[1])}"
                for a in range(0, 360, 45))
icon("today", "今日未读 / 今天", "首页顶部入口", f'<circle cx="12" cy="12" r="3.5"/><path d="{_RAYS}"/>', G)
icon("inbox", "全部未读 / 全部文章", "首页顶部入口",
     '<rect x="4" y="5" width="16" height="14" rx="2.5"/><path d="M4 13h4.5l2 2h3l2-2H20"/>', G)
icon("globe", "外文源 / 网站", "首页顶部入口、「这是外文源」、添加订阅里的网站",
     '<circle cx="12" cy="12" r="8"/><ellipse cx="12" cy="12" rx="3.5" ry="8"/><path d="M4 12h16"/>', G)

# ---------- 整理与管理 ----------
G = "整理与管理"
FOLDER = "M6.5 5H10l2.5 2.5h5A2.5 2.5 0 0 1 20 10v6.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 16.5v-9A2.5 2.5 0 0 1 6.5 5z"
icon("folder", "文件夹", "（备用）文件夹", f'<path d="{FOLDER}"/>', G)
icon("folder-add", "新建文件夹", "「+」→ 新建文件夹", f'<path d="{FOLDER}"/><path d="M12 10.75v5.5M9.25 13.5h5.5"/>', G)
icon("edit", "编辑 / 重命名", "长按「编辑」、重命名文件夹、列表「更多」→ 编辑",
     '<path d="M15 5l4 4-10 10H5v-4z"/><path d="M12.5 7.5l4 4"/>', G)
icon("trash", "删除 / 取消订阅", "删除文件夹、取消订阅（红色）",
     '<path d="M4.5 7h15M10 4h4"/><path d="M7 7v10a2.5 2.5 0 0 0 2.5 2.5h5A2.5 2.5 0 0 0 17 17V7"/>', G)
icon("image", "更换图标", "长按 / 「更多」→ 更换图标",
     '<rect x="5" y="5" width="14" height="14" rx="2.5"/><path d="M5 16l4.5-4.5L17 19"/>' + dot(15, 9), G)
icon("undo", "恢复默认", "「恢复默认图标」", f'<path d="{UNDO_ARC}"/><path d="{UNDO_HEAD}"/>', G)
icon("copy", "拷贝", "「拷贝订阅地址」",
     '<rect x="8.5" y="8.5" width="11" height="11" rx="2.5"/><path d="M4.5 15.5V7A2.5 2.5 0 0 1 7 4.5h8.5"/>', G)
icon("bell", "新文章通知", "「新文章通知」、设置「通知」",
     '<path d="M6.5 15.5v-5a5.5 5.5 0 0 1 11 0v5M4.5 15.5h15M10.5 19h3"/>', G)
icon("shield", "去广告", "浏览器「•••」→ 去广告",
     '<path d="M8 4.5h8a2.5 2.5 0 0 1 2.5 2.5v4A9.48 9.48 0 0 1 12 20a9.48 9.48 0 0 1-6.5-9V7A2.5 2.5 0 0 1 8 4.5z"/>', G)

# ---------- 设置 ----------
G = "设置分类"
icon("account", "账户", "设置「账户」、新建文件夹时选账户", '<circle cx="12" cy="7.5" r="3"/><path d="M5.5 20a6.5 6.5 0 0 1 13 0"/>', G)
icon("feed", "订阅源", "设置「订阅源」（原电波图标）",
     dot(7, 17, 1.5) + f'<path d="{arc(7, 17, 5.5, 270, 360)}"/><path d="{arc(7, 17, 11, 270, 360)}"/>', G)
icon("appearance", "外观", "设置「外观」", '<circle cx="12" cy="12" r="8"/><path d="M12 4a8 8 0 0 1 0 16z" fill="currentColor" stroke="none"/>', G)
icon("help", "支持 / 帮助", "设置「支持」",
     f'<circle cx="12" cy="12" r="8"/><path d="{arc(12, 9.75, 2.5, 180, 90)}V13.5"/>' + dot(12, 16.25), G)

# ---------- 添加订阅 ----------
G = "添加订阅"
icon("podcast", "播客", "添加订阅搜索结果",
     dot(12, 12.75, 1.75) + f'<path d="{arc(12, 12.75, 4.5, 135, 45)}"/><path d="{arc(12, 12.75, 8, 135, 45)}"/>', G)
icon("video", "YouTube 频道", "添加订阅搜索结果",
     '<rect x="4" y="6" width="16" height="12" rx="2.5"/><path d="M10.75 9.75v4.5L14.5 12z" fill="currentColor"/>', G)
_B150, _B120 = _pt(12, 11.5, 7.5, 150), _pt(12, 11.5, 7.5, 120)
icon("chat", "Reddit 社区", "添加订阅搜索结果",
     f'<path d="M{_f(_B150[0])} {_f(_B150[1])}A7.5 7.5 0 1 1 {_f(_B120[0])} {_f(_B120[1])}L4.75 19.25z"/>', G)
icon("subscribe", "订阅", "添加订阅每行右侧（没订阅时）", '<circle cx="12" cy="12" r="8"/><path d="M12 8.5v7M8.5 12h7"/>', G)
icon("subscribed", "已订阅", "添加订阅每行右侧（已订阅时）",
     f'<path d="{circle_path(12, 12, 8 + H)}{stroke_outline(CHECK_IN)}" fill="currentColor" fill-rule="evenodd" stroke="none"/>', G)
