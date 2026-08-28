from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "exports" / "pdf" / "Babel-第一轮设计评审.pdf"
PNG = ROOT / "exports" / "png"
ICONS = ROOT / "assets" / "app-icons"
CACHE = ROOT / "tmp" / "pdf-cache"

PAGE = landscape(A4)
W, H = PAGE

BG = HexColor("#F2EFE8")
INK = HexColor("#232322")
SECONDARY = HexColor("#6E6B66")
LINE = HexColor("#D7D2C9")
ACCENT = HexColor("#C13D32")
DARK = HexColor("#171716")
PAPER = HexColor("#FAF7F0")

pdfmetrics.registerFont(
    TTFont(
        "BabelSongti",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
        subfontIndex=0,
    )
)
CN = "BabelSongti"
LATIN = "Helvetica"
LATIN_BOLD = "Helvetica-Bold"


def background(c, dark=False):
    c.setFillColor(DARK if dark else BG)
    c.rect(0, 0, W, H, stroke=0, fill=1)


def cached_image(path, target_width):
    CACHE.mkdir(parents=True, exist_ok=True)
    out = CACHE / f"{path.parent.name}-{path.stem}-{target_width}.jpg"
    if not out.exists() or out.stat().st_mtime < path.stat().st_mtime:
        image = Image.open(path).convert("RGB")
        target_height = round(image.height * target_width / image.width)
        image = image.resize((target_width, target_height), Image.Resampling.LANCZOS)
        image.save(out, "JPEG", quality=88, optimize=True, progressive=True)
    return out


def page_number(c, n, dark=False):
    c.setFillColor(HexColor("#77736D") if dark else SECONDARY)
    c.setFont(LATIN, 7)
    c.drawRightString(W - 28, 18, f"BABEL / DESIGN 01    {n:02d}")


def title(c, kicker, heading, body=None, x=38, y=None, dark=False):
    if y is None:
        y = H - 44
    c.setFillColor(HexColor("#ED7468") if dark else ACCENT)
    c.setFont(LATIN_BOLD, 8)
    c.drawString(x, y, kicker.upper())
    c.setFillColor(HexColor("#EFEDE7") if dark else INK)
    c.setFont(CN, 23)
    c.drawString(x, y - 29, heading)
    if body:
        c.setFillColor(HexColor("#AAA69F") if dark else SECONDARY)
        c.setFont(CN, 9)
        c.drawString(x, y - 47, body)


def phone(c, image_path, x, y, height=400):
    width = height * 402 / 874
    c.setFillColor(HexColor("#090909"))
    c.roundRect(x - 4, y - 4, width + 8, height + 8, 17, stroke=0, fill=1)
    c.drawImage(
        str(cached_image(image_path, 402)),
        x,
        y,
        width=width,
        height=height,
        preserveAspectRatio=True,
        anchor="c",
        mask="auto",
    )
    return width


def label(c, x, y, text, dark=False):
    c.setFillColor(HexColor("#AAA69F") if dark else SECONDARY)
    c.setFont(CN, 7)
    c.drawCentredString(x, y, text)


def bullet_block(c, x, y, heading, bullets, width=210, dark=False):
    c.setFillColor(HexColor("#EFEDE7") if dark else INK)
    c.setFont(CN, 13)
    c.drawString(x, y, heading)
    cy = y - 23
    for item in bullets:
        c.setStrokeColor(HexColor("#ED7468") if dark else ACCENT)
        c.circle(x + 3, cy + 3, 2.4, stroke=1, fill=0)
        c.setFillColor(HexColor("#AAA69F") if dark else SECONDARY)
        c.setFont(CN, 8)
        lines = wrap_text(item, 20)
        for line in lines:
            c.drawString(x + 13, cy, line)
            cy -= 12
        cy -= 7
    return cy


def wrap_text(text, size):
    return [text[i : i + size] for i in range(0, len(text), size)]


def footer_rule(c, dark=False):
    c.setStrokeColor(HexColor("#3B3A37") if dark else LINE)
    c.line(38, 32, W - 38, 32)


def direction_page(c, n, code, name, summary, bullets, files, dark=False):
    background(c, dark)
    title(c, f"DIRECTION {code}", name, summary, dark=dark)
    x0 = 38
    y0 = 61
    h = 397
    gap = 19
    for index, (file_name, caption) in enumerate(files):
        x = x0 + index * (h * 402 / 874 + gap)
        pw = phone(c, PNG / file_name, x, y0, h)
        label(c, x + pw / 2, y0 - 14, caption, dark)
    notes_x = x0 + len(files) * (h * 402 / 874 + gap) + 3
    bullet_block(c, notes_x, H - 128, "这个方向解决什么", bullets, dark=dark)
    footer_rule(c, dark)
    page_number(c, n, dark)
    c.showPage()


def draw_cover(c):
    background(c, True)
    c.setStrokeColor(HexColor("#3B3A37"))
    c.line(48, 84, 48, H - 58)
    c.setStrokeColor(HexColor("#ED7468"))
    c.line(48, H - 190, 48, H - 58)
    c.drawImage(
        str(cached_image(ICONS / "direction-c" / "Babel-C-Dark.png", 320)),
        W - 216,
        H - 242,
        width=154,
        height=154,
        preserveAspectRatio=True,
        mask="auto",
    )
    c.setFillColor(HexColor("#ED7468"))
    c.setFont(LATIN_BOLD, 9)
    c.drawString(76, H - 83, "BABEL / PRODUCT DESIGN / ROUND 01")
    c.setFillColor(HexColor("#EFEDE7"))
    c.setFont(CN, 38)
    c.drawString(76, H - 145, "为跨语言阅读重新排版")
    c.setFont(CN, 18)
    c.drawString(76, H - 181, "三个完整方向 · 浅色与深色 · 设置 · 长图 · App 图标")
    c.setFillColor(HexColor("#AAA69F"))
    c.setFont(CN, 12)
    c.drawString(76, H - 246, "Babel 是一个让任何人用自己的阅读语言，阅读世界内容的阅读器。")
    c.setFont(CN, 9)
    c.drawString(76, H - 285, "依据 DESIGN-BRIEF、设计问卷与现有 App 截图制作")
    c.drawString(76, H - 303, "主画布 402 × 874pt / @3x 导出 / 2026-07-31")
    c.setFillColor(HexColor("#ED7468"))
    c.setFont(CN, 10)
    c.drawString(76, 104, "推荐：以 C「译者的校样桌」为主方向，吸收 A 的克制与 B 的入口图像原则。")
    page_number(c, 1, True)
    c.showPage()


def comparison_page(c):
    background(c)
    title(c, "COMPARISON", "三个方向，用同一内容比较", "主页、翻译状态、设置与导出均使用相同内容模型")
    y = 77
    h = 390
    files = [
        ("A-home-starred-light@3x.png", "A · 安静的编辑排版"),
        ("B-home-starred-light@3x.png", "B · 图像只留在门口"),
        ("C-home-starred-light@3x.png", "C · 译者的校样桌"),
    ]
    xs = [90, 330, 570]
    for x, (file_name, caption) in zip(xs, files):
        pw = phone(c, PNG / file_name, x, y, h)
        label(c, x + pw / 2, y - 14, caption)
    footer_rule(c)
    page_number(c, 2)
    c.showPage()


def translation_page(c):
    background(c, True)
    title(c, "CORE FLOW", "翻译是阅读状态，不是永久标签", "原文 → 翻译中 → 已翻译 → 下滑停靠", dark=True)
    y = 72
    h = 392
    files = [
        ("C-article-original-light@3x.png", "原文"),
        ("C-article-translating-light@3x.png", "翻译中"),
        ("C-article-translated-dark@3x.png", "已翻译 / 深色"),
        ("C-article-docked-dark@3x.png", "停靠"),
    ]
    x = 32
    for file_name, caption in files:
        pw = phone(c, PNG / file_name, x, y, h)
        label(c, x + pw / 2, y - 14, caption, True)
        x += pw + 20
    footer_rule(c, True)
    page_number(c, 6, True)
    c.showPage()


def settings_page(c):
    background(c)
    title(c, "SETTINGS + EXPORT", "设置收紧结构，长图变成出版物", "全局阅读语言、订阅源覆盖项与可传播的长图模板")
    y = 72
    h = 392
    files = [
        ("C-settings-light@3x.png", "设置主页"),
        ("C-language-light@3x.png", "翻译与语言"),
        ("C-feed-dark@3x.png", "单订阅源 / 深色"),
        ("C-longimage-light@3x.png", "长图导出"),
    ]
    x = 32
    for file_name, caption in files:
        pw = phone(c, PNG / file_name, x, y, h)
        label(c, x + pw / 2, y - 14, caption)
        x += pw + 20
    footer_rule(c)
    page_number(c, 7)
    c.showPage()


def icon_page(c):
    background(c, True)
    title(c, "APP ICON", "三套构形，完整 Light / Dark / Mono", "第一轮概念稿均保留 SVG 与 1024px PNG", dark=True)
    names = [
        ("direction-a", "Babel-A", "A · 编辑字标"),
        ("direction-b", "Babel-B", "B · 门洞与远方"),
        ("direction-c", "Babel-C", "C · 校样裁切标"),
    ]
    modes = ["Light", "Dark", "Mono"]
    start_x = 74
    start_y = 320
    size = 112
    for col, (folder, prefix, caption) in enumerate(names):
        x = start_x + col * 250
        c.setFillColor(HexColor("#EFEDE7"))
        c.setFont(CN, 12)
        c.drawString(x, H - 125, caption)
        for row, mode in enumerate(modes):
            y = start_y - row * 126
            c.drawImage(
                str(cached_image(ICONS / folder / f"{prefix}-{mode}.png", 320)),
                x,
                y,
                width=size,
                height=size,
                preserveAspectRatio=True,
                mask="auto",
            )
            c.setFillColor(HexColor("#AAA69F"))
            c.setFont(LATIN, 7)
            c.drawString(x + size + 12, y + size / 2, mode.upper())
    c.setFillColor(HexColor("#ED7468"))
    c.setFont(CN, 9)
    c.drawString(74, 70, "优先继续迭代 C：小尺寸可辨认，跨语言编辑工具的身份最明确。")
    footer_rule(c, True)
    page_number(c, 8, True)
    c.showPage()


def matrix_page(c):
    background(c)
    title(c, "DECISION", "方向判断与第二轮组合", "评分 5 为最好；这是设计判断，不是用户研究结论")
    columns = ["维度", "A", "B", "C"]
    rows = [
        ("内容可读性", 5, 4, 5),
        ("产品差异化", 3, 4, 5),
        ("全球化适配", 4, 3, 5),
        ("延续现有品牌", 2, 5, 3),
        ("深色模式表现", 5, 4, 5),
        ("开发可控性", 5, 4, 4),
        ("长图传播识别", 3, 4, 5),
        ("总分", 27, 28, 32),
    ]
    x0, y0 = 48, H - 130
    widths = [165, 68, 68, 68]
    row_h = 32
    c.setFillColor(HexColor("#E8E2D8"))
    c.rect(x0, y0, sum(widths), row_h, stroke=0, fill=1)
    x = x0
    for item, width in zip(columns, widths):
        c.setFillColor(INK)
        c.setFont(CN if item == "维度" else LATIN_BOLD, 9)
        c.drawCentredString(x + width / 2, y0 + 11, item)
        x += width
    for r, row in enumerate(rows):
        y = y0 - (r + 1) * row_h
        c.setStrokeColor(LINE)
        c.line(x0, y, x0 + sum(widths), y)
        x = x0
        for item, width in zip(row, widths):
            if isinstance(item, int):
                c.setFont(LATIN_BOLD, 10)
                c.setFillColor(ACCENT if item in (5, 32) else INK)
            else:
                c.setFont(CN, 9)
                c.setFillColor(INK)
            c.drawCentredString(x + width / 2, y + 11, str(item))
            x += width
    bullet_block(
        c,
        490,
        H - 130,
        "建议进入第二轮的组合",
        [
            "以 C 的跨语言校样结构为骨架。",
            "吸收 A 的排版纪律，减少正文区的标记密度。",
            "只在主页保留一处 B 式入口图像。",
            "单源列表默认不重复来源名。",
            "目标语言文章保留翻译键，但弱化到约 38%。",
        ],
        width=260,
    )
    c.setFillColor(PAPER)
    c.roundRect(490, 76, 290, 118, 12, stroke=0, fill=1)
    c.setFillColor(ACCENT)
    c.setFont(LATIN_BOLD, 8)
    c.drawString(508, 170, "NEXT ROUND")
    c.setFillColor(INK)
    c.setFont(CN, 11)
    c.drawString(508, 147, "收敛 C 的标记密度，完成实机可点击原型")
    c.setFillColor(SECONDARY)
    c.setFont(CN, 8)
    c.drawString(508, 126, "重点验证：标题交接、控制板层级、目标语言按钮、")
    c.drawString(508, 112, "单源列表密度，以及长图在真实文章中的长度边界。")
    footer_rule(c)
    page_number(c, 9)
    c.showPage()


def build():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUT), pagesize=PAGE)
    c.setTitle("Babel 第一轮设计评审")
    c.setAuthor("OpenAI Codex")
    draw_cover(c)
    comparison_page(c)
    direction_page(
        c,
        3,
        "A",
        "安静的编辑排版",
        "排版秩序、纸张层次、克制陶土色",
        [
            "成熟、安静，正文可读性最好。",
            "不依赖插画，深浅色转换稳定。",
            "风险是与其他优质阅读器的差异不够强。",
        ],
        [
            ("A-list-rest-light@3x.png", "文章列表"),
            ("A-article-translated-dark@3x.png", "文章 / 深色"),
            ("A-settings-light@3x.png", "设置"),
        ],
    )
    direction_page(
        c,
        4,
        "B",
        "图像只留在门口",
        "延续浮世绘情绪，但图像在内容开始前退场",
        [
            "对现有用户最熟悉，入口最亲和。",
            "列表和正文不再被大图抢走注意力。",
            "风险是地域气质仍可能限制全球化理解。",
        ],
        [
            ("B-home-all-light@3x.png", "入口图像"),
            ("B-list-docked-dark@3x.png", "列表停靠 / 深色"),
            ("B-article-original-light@3x.png", "文章原文"),
        ],
    )
    direction_page(
        c,
        5,
        "C",
        "译者的校样桌",
        "裁切标、批注与双语结构形成产品自己的语言",
        [
            "跨语言阅读不再只是一个翻译按钮。",
            "不依赖特定文化图像，全球化适配最好。",
            "推荐方向；第二轮需继续控制标记密度。",
        ],
        [
            ("C-home-starred-light@3x.png", "主页"),
            ("C-list-rest-light@3x.png", "文章列表"),
            ("C-article-translated-dark@3x.png", "文章 / 深色"),
        ],
    )
    translation_page(c)
    settings_page(c)
    icon_page(c)
    matrix_page(c)
    c.save()
    print(OUT)


if __name__ == "__main__":
    build()
