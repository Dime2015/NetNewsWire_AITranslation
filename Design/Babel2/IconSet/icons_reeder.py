# Babel 2.0 图标集 · 候选方向「Reeder 式」（2026-09-27 第八轮，用户：「参考 Reeder 截图里的各种 icon，设计一套类似风格的」）
#
# 与 icons.py（第七轮「瑞士几何」，已接进 App、待验收）是同一套 47 个语义、同名同用处，可以整套互换：
# 2026-09-27 用户看完对比页选定这一套（「选这套」），make.py 已改为从本文件导出；icons.py 留作第七轮记录。
#
# 从 Reeder 截图（Reeder screenshots/）归纳出的构造语法：
# - 画布 24×24，线宽 2，圆头圆角；颜色一律 currentColor（App 里按模板图上色）
# - 实心与空心成对表示状态：空心 = 没做 / 可以做，实心 = 已做（已读、星标、已订阅、全部已读）
# - 「外框 + 实心件」：开关胶囊里一颗实心圆钮（设置）、半实心圆（外观）、框里一块实心（长图、今天）
# - 圆弧箭头一律用实心三角箭头（刷新 / 同步 / 恢复默认），直箭头用线箭头
# - 横线左对齐、由长到短（文章列表 3 道递减；阅读模式 4 道、最后一道短）
# - chevron 两臂张角约 100°（比瑞士几何的 90° 更宽、更柔），前进 / 后退 / 向下同一副
# - 框的圆角统一 3（比瑞士几何的 2.5 更圆润）；主体收在约 15–16 的范围里，四周留白
# - 镂空（反白的勾、剪开的星）直接用几何算进路径（evenodd），不用 mask
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import icons as base  # noqa: E402  只借作图工具，不用它的图标

STROKE = 2.0
H = STROKE / 2
R = 3            # 全套框圆角

_f, _pt, arc, arc_ccw, poly, pl = base._f, base._pt, base.arc, base.arc_ccw, base.poly, base.pl

ICONS = []


def icon(name, meaning, where, body, group):
    ICONS.append({"name": name, "meaning": meaning, "where": where, "body": body.strip(), "group": group})


def dot(x, y, r=1.5):
    return f'<circle cx="{_f(x)}" cy="{_f(y)}" r="{_f(r)}" fill="currentColor" stroke="none"/>'


def rrect(x, y, w, h, r=R, extra=""):
    return f'<rect x="{_f(x)}" y="{_f(y)}" width="{_f(w)}" height="{_f(h)}" rx="{_f(r)}"{extra}/>'


def rrect_path(x, y, w, h, r):
    """圆角矩形的闭合路径（顺时针），用来和别的形 evenodd 镂空。"""
    return (f"M{_f(x + r)} {_f(y)}H{_f(x + w - r)}A{_f(r)} {_f(r)} 0 0 1 {_f(x + w)} {_f(y + r)}"
            f"V{_f(y + h - r)}A{_f(r)} {_f(r)} 0 0 1 {_f(x + w - r)} {_f(y + h)}"
            f"H{_f(x + r)}A{_f(r)} {_f(r)} 0 0 1 {_f(x)} {_f(y + h - r)}V{_f(y + r)}A{_f(r)} {_f(r)} 0 0 1 {_f(x + r)} {_f(y)}Z")


def head(cx, cy, r, deg, cw=True, width=5.2, length=3.8):
    """圆弧末端的实心三角箭头：底边沿半径方向跨在弧上，尖朝弧的前进方向。
    带同色细描边（stroke-linejoin 圆角）让三个角微微圆起来，和线条的圆头一致。"""
    px, py = _pt(cx, cy, r, deg)
    a = math.radians(deg)
    rx, ry = math.cos(a), math.sin(a)                     # 半径方向
    tx, ty = (-ry, rx) if cw else (ry, -rx)               # 前进方向
    b1 = (px + rx * width / 2, py + ry * width / 2)
    b2 = (px - rx * width / 2, py - ry * width / 2)
    tip = (px + tx * length, py + ty * length)
    return f'<polygon points="{poly([b1, tip, b2])}" fill="currentColor" stroke-width="1"/>'


# ---------- 共享构件 ----------

STAR = base.star_pts(12, 12.7, 8.25)
CHECK = [(5.5, 12.5), (9.75, 16.75), (18.5, 7.25)]           # 独立的勾：短臂 45°，长臂更陡（Reeder / 系统的勾）
CHECK_IN = [(8.25, 12.25), (10.9, 14.9), (15.9, 9.4)]         # 圆里的勾：同一造型缩小


def solid_circle_with(cx, cy, r, knock_pts):
    """实心圆 + 反白折线（勾），evenodd 一次算出来。"""
    return (f'<path d="{base.circle_path(cx, cy, r)}{base.stroke_outline(knock_pts)}" '
            f'fill="currentColor" fill-rule="evenodd" stroke="none"/>')


# 刷新 / 同步 / 恢复默认：同一段圆弧（半径 7，顶部留 70° 缺口）+ 实心三角箭头
RR = 7
REFRESH = f'<path d="{arc(12, 12.5, RR, 305, 235 + 360)}"/>' + head(12, 12.5, RR, 235)
SYNC = f'<path d="{arc(12, 12, RR, 305, 235 + 360)}"/>' + head(12, 12, RR, 235)
UNDO = f'<path d="{arc_ccw(12, 12.5, RR, 235, 305 - 360)}"/>' + head(12, 12.5, RR, 305, cw=False)

# chevron：两臂 dx 5.5 / dy 6.75（张角约 101°）
CX, CY = 5.5, 6.75

# 取消星标：实心星被一道斜杠剪开（与第七轮同一构造，Reeder 的星更饱满）
_SA, _SB = (4.5, 5.2), (19.5, 20.2)
STAR_OFF = "".join(f'<polygon points="{poly(p)}" fill="currentColor"/>'
                   for p in (base.clip_half(STAR, _SA, _SB, 2.75, 1), base.clip_half(STAR, _SA, _SB, 2.75, -1)) if len(p) > 2)
STAR_OFF += f'<path d="M{_f(_SA[0])} {_f(_SA[1])}L{_f(_SB[0])} {_f(_SB[1])}"/>'

# ---------- 导航与通用 ----------
G = "导航与通用"
icon("back", "返回", "文章列表左上、设置页返回、浏览器后退",
     f'<path d="M{_f(9.25 + CX)} {_f(12 - CY)}L9.25 12L{_f(9.25 + CX)} {_f(12 + CY)}"/>', G)
icon("forward", "前进 / 进入下一级", "浏览器前进、设置行右侧、首页文件夹展开",
     f'<path d="M{_f(14.75 - CX)} {_f(12 - CY)}L14.75 12L{_f(14.75 - CX)} {_f(12 + CY)}"/>', G)
icon("chevron-down", "向下 / 下一篇 / 下拉", "阅读页底栏「下一篇」、设置里的下拉选项",
     f'<path d="M{_f(12 - CY)} {_f(14.75 - CX)}L12 14.75L{_f(12 + CY)} {_f(14.75 - CX)}"/>', G)
icon("close", "关闭 / 取消", "阅读页、图片查看器、浏览器、设置编辑页左上", '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>', G)
icon("more", "更多", "阅读页、文章列表、浏览器右上「•••」", dot(5.75, 12, 1.75) + dot(12, 12, 1.75) + dot(18.25, 12, 1.75), G)
icon("check", "勾选 / 保存", "菜单里开关打勾、设置单选、设置编辑页右上「保存」", f'<path d="{pl(CHECK)}"/>', G)
icon("search", "搜索", "文章列表放大镜、添加订阅搜索框", '<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l4.25 4.25"/>', G)
icon("add", "添加", "首页右上「+」、菜单「添加订阅」", '<path d="M12 5.5v13M5.5 12h13"/>', G)
# 设置：Reeder 首页左上那颗「开关」——空心胶囊 + 实心圆钮
icon("settings", "设置", "首页左上（原齿轮）",
     rrect(3.5, 7, 17, 10, 5) + dot(15.25, 12, 2.75), G)
icon("share", "分享", "阅读页右上、浏览器底栏",
     '<path d="M9 9.5H8a2 2 0 0 0-2 2V18a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-6.5a2 2 0 0 0-2-2h-1"/>'
     '<path d="M12 3.75v10.5M8.75 7 12 3.75 15.25 7"/>', G)
icon("refresh", "刷新", "浏览器刷新、刷新模型列表", REFRESH, G)
icon("sync", "同步中（转动）", "首页标题旁、文章列表顶部刷新按钮", SYNC, G)
icon("arrow-up", "回到顶部", "「↑ N 篇新文章」小胶囊", '<path d="M12 19V5.5M7 10.5l5-5 5 5"/>', G)
icon("open-link", "打开链接", "图片查看器右下「打开链接」", '<path d="M7 17 17 7M9.5 7H17v7.5"/>', G)
icon("browser", "在浏览器打开 / 网站", "「打开网站」「打开原文」、浏览器「在 Safari 打开」",
     '<circle cx="12" cy="12" r="8"/><path d="M15 9 13 13 9 15 11 11z" fill="currentColor" stroke-width="1"/>', G)

# ---------- 阅读与文章状态 ----------
G = "阅读与文章状态"
icon("read-off", "未读（点一下标为已读）", "阅读页底栏第 1 格", '<circle cx="12" cy="12" r="6"/>', G)
icon("read-on", "已读", "阅读页底栏第 1 格（已读时）", '<circle cx="12" cy="12" r="6" fill="currentColor"/>', G)
icon("star", "加星标", "阅读页底栏、菜单「加星标」、首页 / 列表底栏星标档、「全部星标」", f'<polygon points="{poly(STAR)}"/>', G)
icon("star-on", "已加星标", "阅读页底栏（已加星标时）、底栏选中的星标档", f'<polygon points="{poly(STAR)}" fill="currentColor"/>', G)
icon("star-off", "取消星标", "菜单「取消星标」", STAR_OFF, G)
# 阅读模式：与第七轮同一组坐标、一点不改——阅读页底栏那颗是代码画的（为了「进行中」四道线依次明灭），
# 坐标写死在 Babel2StatusIcons.swift 的 Babel2ReaderModeIconButton.lineSpecs，两边必须一致
icon("reader-mode", "阅读模式", "阅读页底栏第 4 格、「此源总是阅读模式」、设置「阅读页」（四道横线、最后一道短——ADR-049 定过的形状）",
     '<path d="M5.5 6h13M5.5 10h13M5.5 14h13M5.5 18h7.5"/>', G)
# 翻译：学 Reeder 底栏的「BR」——一粗一细两个字。「文」常规线宽，「A」细（1.5），右下角约 6×6 留给缓存圆点
# （试过「文」加粗到 2.4：笔画挤在一起，20px 下像一个「✗」，退回）
icon("translate", "翻译", "阅读页底栏最右、列表底栏标题翻译、浏览器「翻译此页」、设置「翻译」",
     f'{base.glyph_wen(3.25, 3.5, 8.5, 10.5)}'
     f'<path stroke-width="1.5" d="{base.letter_A(13.25, 6.5, 6.5, 9.5)}"/>', G)
# 长图：底边敞开的竖框（「还没完，往下接着长」）+ 顶上一块实心（题图）+ 两道递减横线（正文）
# （试过封口的竖框：20px 下像一部手机，退回）
icon("long-image", "生成长图", "阅读页「•••」→ 生成长图",
     '<path d="M6.5 20.5V6a3 3 0 0 1 3-3h5a3 3 0 0 1 3 3v14.5"/>'
     + rrect(9.5, 6, 5, 4, 1, ' fill="currentColor" stroke="none"')
     + '<path d="M10 14.5h4M10 18.5h2"/>', G)
# 全部标为已读：Reeder 列表底栏左 1 原样——实心圆 + 反白勾
icon("read-all", "全部标为已读", "文章列表底栏左 1", solid_circle_with(12, 12, 8 + H, CHECK_IN), G)
icon("unread-dot", "未读档", "首页 / 列表底栏的「● UNREAD」", dot(12, 12, 3), G)
# 列表：Reeder 底栏「全部」——三道左对齐、由长到短
icon("list", "全部 / 列表", "底栏「全部」档、菜单「打开这个源」、设置「文章列表」",
     '<path d="M5.5 7h13M5.5 12h9M5.5 17h5"/>', G)

# ---------- 首页入口 ----------
G = "首页入口"
# 今天：日历页——框 + 页眉线 + 当天一块实心
icon("today", "今日未读 / 今天", "首页顶部入口",
     rrect(4.5, 4.5, 15, 15) + '<path d="M4.5 9.5h15"/>' + rrect(8.5, 12.5, 4, 3.5, 1, ' fill="currentColor" stroke="none"'), G)
icon("inbox", "全部未读 / 全部文章", "首页顶部入口",
     rrect(4.5, 4.5, 15, 15) + '<path d="M4.5 13.5h4l1.5 2h4l1.5-2h4"/>', G)
icon("globe", "外文源 / 网站", "首页顶部入口、「这是外文源」、添加订阅里的网站",
     '<circle cx="12" cy="12" r="8"/><ellipse cx="12" cy="12" rx="3.5" ry="8"/><path d="M4 12h16"/>', G)

# ---------- 整理与管理 ----------
G = "整理与管理"
FOLDER = "M7 5H10l2 2.5h5A3 3 0 0 1 20 10.5v6A3 3 0 0 1 17 19.5H7A3 3 0 0 1 4 16.5V8A3 3 0 0 1 7 5z"
icon("folder", "文件夹", "（备用）文件夹", f'<path d="{FOLDER}"/>', G)
icon("folder-add", "新建文件夹", "「+」→ 新建文件夹", f'<path d="{FOLDER}"/><path d="M12 10.75v5.5M9.25 13.5h5.5"/>', G)
# 编辑：一支笔的剖面——笔身空心，笔尖实心
icon("edit", "编辑 / 重命名", "长按「编辑」、重命名文件夹、列表「更多」→ 编辑",
     '<path d="M14.5 5.5l4 4-9 9-4-4z"/><path d="M5.5 14.5 4.5 19.5 9.5 18.5z" fill="currentColor"/>', G)
icon("trash", "删除 / 取消订阅", "删除文件夹、取消订阅（红色）",
     '<path d="M4.5 7h15M10 4h4"/><path d="M6.75 7l.75 10.5A2.5 2.5 0 0 0 10 20h4a2.5 2.5 0 0 0 2.5-2.5L17.25 7"/>', G)
# 更换图标：一枚「App 图标」——圆角更大的方块，右下一颗实心点（呼应 Babel 图标「B.」的那个点）
# （试过 Reeder「关于」式的实心方块挖圆：像录音 / 停止按钮，退回）
icon("image", "更换图标", "长按 / 「更多」→ 更换图标",
     rrect(4.5, 4.5, 15, 15, 4.5) + dot(15, 15, 1.75), G)
icon("undo", "恢复默认", "「恢复默认图标」", UNDO, G)
icon("copy", "拷贝", "「拷贝订阅地址」",
     rrect(8.5, 8.5, 11, 11) + '<path d="M4.5 15.5V7.5a3 3 0 0 1 3-3h8"/>', G)
icon("bell", "新文章通知", "「新文章通知」、设置「通知」",
     '<path d="M6.5 16v-5a5.5 5.5 0 0 1 11 0v5M4.5 16h15"/>' + dot(12, 19.25, 1.5), G)
icon("shield", "去广告", "浏览器「•••」→ 去广告",
     '<path d="M12 4 18.5 6.5V11c0 4.25-2.75 7.25-6.5 9-3.75-1.75-6.5-4.75-6.5-9V6.5z"/>'
     '<path d="M12 4 18.5 6.5V11c0 4.25-2.75 7.25-6.5 9z" fill="currentColor" stroke="none"/>', G)

# ---------- 设置 ----------
G = "设置分类"
# 账户：Reeder「添加账户」的实心人形
icon("account", "账户", "设置「账户」、新建文件夹时选账户",
     '<circle cx="12" cy="8" r="3.25" fill="currentColor"/><path d="M5 19.5a7 5.5 0 0 1 14 0z" fill="currentColor"/>', G)
icon("feed", "订阅源", "设置「订阅源」（原电波图标）",
     dot(7, 17, 1.75) + f'<path d="{arc(7, 17, 5.5, 270, 360)}"/><path d="{arc(7, 17, 11, 270, 360)}"/>', G)
# 外观：Reeder 原样——空心圆 + 右半实心
icon("appearance", "外观", "设置「外观」", '<circle cx="12" cy="12" r="8"/><path d="M12 4a8 8 0 0 1 0 16z" fill="currentColor" stroke="none"/>', G)
# 支持：Reeder 原样——不套圈的粗问号
icon("help", "支持 / 帮助", "设置「支持」",
     f'<path stroke-width="2.4" d="{arc(12, 8.5, 3.75, 180, 90)}V14.25"/>' + dot(12, 18.75, 1.6), G)

# ---------- 添加订阅 ----------
G = "添加订阅"
icon("podcast", "播客", "添加订阅搜索结果",
     dot(12, 12.75, 2) + f'<path d="{arc(12, 12.75, 4.75, 135, 45)}"/><path d="{arc(12, 12.75, 8, 135, 45)}"/>', G)
icon("video", "YouTube 频道", "添加订阅搜索结果",
     rrect(4, 6, 16, 12) + '<path d="M10.5 9.5v5L14.75 12z" fill="currentColor" stroke-width="1"/>', G)
_B150, _B120 = _pt(12, 11.5, 7.5, 150), _pt(12, 11.5, 7.5, 120)
icon("chat", "Reddit 社区", "添加订阅搜索结果",
     f'<path d="M{_f(_B150[0])} {_f(_B150[1])}A7.5 7.5 0 1 1 {_f(_B120[0])} {_f(_B120[1])}L4.75 19.25z"/>', G)
icon("subscribe", "订阅", "添加订阅每行右侧（没订阅时）", '<circle cx="12" cy="12" r="8"/><path d="M12 8.25v7.5M8.25 12h7.5"/>', G)
icon("subscribed", "已订阅", "添加订阅每行右侧（已订阅时）", solid_circle_with(12, 12, 8 + H, CHECK_IN), G)
