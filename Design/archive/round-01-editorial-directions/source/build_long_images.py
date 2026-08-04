from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "exports" / "long-image"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1206, 3000
SONGTI = "/System/Library/Fonts/Supplemental/Songti.ttc"
HEITI = "/System/Library/Fonts/STHeiti Light.ttc"


def font(path, size, index=0):
    return ImageFont.truetype(path, size=size, index=index)


DISPLAY = font(SONGTI, 86)
SUBTITLE = font(HEITI, 36)
BODY = font(SONGTI, 44)
BODY_BOLD = font(SONGTI, 44)
META = font(HEITI, 25)
SMALL = font(HEITI, 22)
MARK = font(SONGTI, 52)

COPY = [
    "在过去三十年里，全球供应链被设计成一台追求效率的机器。库存被压缩，路线被优化，每一个多余环节都被视为成本。",
    "如今，企业没有放弃效率，但它们开始为不确定性付费。更近的供应商、更大的库存与第二套方案，正从浪费变成保险。",
    "这并不是去全球化，而是一种更复杂的全球化。网络没有消失，只是学会了保留余地。",
    "对读者而言，这场变化也意味着一个更难回答的问题：当世界不再追求单一效率，我们应当如何理解成本、速度与安全之间的关系？",
    "答案不会来自某一个国家或某一家公司。它来自无数细小的重新配置：一条更短的路线、一家备用供应商、一份被重新计算的库存，以及对失败可能性的坦然承认。",
]


def wrap(draw, text, fnt, max_width):
    lines = []
    current = ""
    for char in text:
        candidate = current + char
        if draw.textlength(candidate, font=fnt) <= max_width:
            current = candidate
        else:
            lines.append(current)
            current = char
    if current:
        lines.append(current)
    return lines


def draw_lines(draw, lines, xy, fnt, fill, spacing):
    x, y = xy
    for line in lines:
        draw.text((x, y), line, font=fnt, fill=fill)
        y += spacing
    return y


def build(direction, dark):
    if dark:
        bg, paper, ink = "#121211", "#1D1D1C", "#EFEDE7"
        secondary, line, accent = "#AAA69F", "#3B3A37", "#ED7468"
    else:
        bg, paper, ink = "#D9D2C7", "#FAF7F0", "#232322"
        secondary, line, accent = "#6E6B66", "#D7D2C9", "#C13D32"

    if direction == "a":
        accent = "#DF805C" if dark else "#B95736"
    if direction == "b":
        accent = "#E0785E" if dark else "#BA4D35"

    image = Image.new("RGB", (W, H), bg)
    draw = ImageDraw.Draw(image)
    margin = 48
    draw.rounded_rectangle((margin, 34, W - margin, H - 34), radius=22, fill=paper)
    left, right = 126, W - 126

    if direction == "b":
        top = 34
        banner_h = 320
        draw.rounded_rectangle((margin, top, W - margin, top + banner_h), radius=22, fill=accent)
        draw.rectangle((margin, top + 190, W - margin, top + banner_h), fill="#214D44" if not dark else "#733126")
        draw.ellipse((W - 330, 84, W - 170, 244), fill="#EACB98")
        draw.arc((left + 70, 86, left + 390, 420), 180, 360, fill=paper, width=28)

    header_y = 92
    header_fill = paper if direction == "b" else ink
    draw.text((left, header_y), "BABEL", font=META, fill=header_fill)
    lang_text = "READING COPY · 简体中文"
    lang_w = draw.textlength(lang_text, font=SMALL)
    draw.text((right - lang_w, header_y + 2), lang_text, font=SMALL, fill=header_fill)

    if direction == "c":
        mark = 36
        draw.line((left - 36, 82, left - 36 + mark, 82), fill=accent, width=5)
        draw.line((left - 36, 82, left - 36, 82 + mark), fill=accent, width=5)
        draw.line((right + 36, 82, right + 36 - mark, 82), fill=accent, width=5)
        draw.line((right + 36, 82, right + 36, 82 + mark), fill=accent, width=5)

    y = 402 if direction == "b" else 246
    kicker = "FINANCIAL TIMES · ENGLISH → 简体中文"
    draw.text((left, y), kicker, font=SMALL, fill=accent)
    y += 61
    title = "全球供应链正在学习如何与不确定性共处"
    title_lines = wrap(draw, title, DISPLAY, right - left)
    y = draw_lines(draw, title_lines, (left, y), DISPLAY, ink, 104)
    y += 20
    deck = "效率不再是唯一目标。企业正在重新权衡成本、速度、冗余与地缘政治风险。"
    y = draw_lines(draw, wrap(draw, deck, SUBTITLE, right - left), (left, y), SUBTITLE, secondary, 54)
    y += 42
    draw.text((left, y), "Financial Times", font=META, fill=ink)
    meta = "2026 年 7 月 31 日   ·   8 分钟"
    meta_w = draw.textlength(meta, font=META)
    draw.text((right - meta_w, y), meta, font=META, fill=secondary)
    y += 63
    draw.line((left, y, right, y), fill=line, width=3)
    y += 78

    for index, paragraph in enumerate(COPY):
        if direction == "c" and index in (0, 3):
            draw.text((left - 66, y - 4), "校" if index == 0 else "注", font=MARK, fill=accent)
            draw.line((left - 20, y + 20, left - 2, y + 20), fill=accent, width=4)
        paragraph_lines = wrap(draw, paragraph, BODY, right - left)
        y = draw_lines(draw, paragraph_lines, (left, y), BODY, ink, 72)
        y += 50
        if index == 1:
            y += 10
            draw.rectangle((left, y, right, y + 244), fill=accent)
            quote = "“最便宜的路径，不一定是最能抵达终点的路径。”"
            quote_fill = "#FFF8EE" if not dark else "#171716"
            quote_lines = wrap(draw, quote, DISPLAY, right - left - 100)
            quote_y = y + 40
            draw_lines(draw, quote_lines, (left + 50, quote_y), DISPLAY, quote_fill, 102)
            y += 294

    footer_y = H - 246
    draw.line((left, footer_y, right, footer_y), fill=line, width=3)
    draw.rounded_rectangle((left, footer_y + 42, left + 70, footer_y + 112), radius=16, outline=accent, width=4)
    draw.text((left + 21, footer_y + 47), "B", font=MARK, fill=accent)
    draw.text((left + 93, footer_y + 52), "分享自 Babel", font=META, fill=ink)
    source = "原文：ft.com · 译文为阅读辅助"
    source_w = draw.textlength(source, font=SMALL)
    draw.text((right - source_w, footer_y + 55), source, font=SMALL, fill=secondary)

    if direction == "c":
        draw.line((left - 36, H - 82, left - 36 + 36, H - 82), fill=accent, width=5)
        draw.line((left - 36, H - 82, left - 36, H - 118), fill=accent, width=5)
        draw.line((right + 36, H - 82, right, H - 82), fill=accent, width=5)
        draw.line((right + 36, H - 82, right + 36, H - 118), fill=accent, width=5)

    mode = "dark" if dark else "light"
    image.save(OUT / f"Babel-{direction.upper()}-long-image-{mode}@3x.png", optimize=True)


for direction in ("a", "b", "c"):
    for dark in (False, True):
        build(direction, dark)

print(f"Generated 6 long-image samples in {OUT}")
