# 生成统一图标集：svg/ 下每个图标一个文件；review.html 审阅页（现在 vs 新，浅色 / 深色，实际大小 + 放大）。
# 用法：python3 make.py [--sheet 渲染器路径 输出png]   （--sheet 只用于自查：把「现在 | 新」拼成一张图）
import base64
import html
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from icons_reeder import ICONS, STROKE  # noqa: E402  第八轮起用 Reeder 式（第七轮设计源 icons.py 留作记录）

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

# 每个新图标对应 App 里现在用的图标（审阅页左边那一格）："sym:系统符号名" 或 "asset:资源名"
CURRENT = {
    "back": "sym:chevron.left", "forward": "sym:chevron.right", "chevron-down": "asset:Babel2ReaderNext",
    "close": "asset:Babel2ReaderClose", "more": "asset:Babel2ReaderMore", "check": "asset:Babel2SettingsCheck",
    "search": "sym:magnifyingglass", "add": "asset:BabelHomeAdd", "settings": "sym:gearshape",
    "share": "sym:square.and.arrow.up", "refresh": "sym:arrow.clockwise", "sync": "sym:arrow.clockwise",
    "arrow-up": "sym:arrow.up", "open-link": "sym:arrow.up.right", "browser": "sym:safari",
    "read-off": "asset:Babel2ReaderReadState", "read-on": "asset:Babel2ReaderReadStateFilled",
    "star": "asset:Babel2ReaderStar", "star-on": "asset:Babel2ReaderStarFilled", "star-off": "sym:star.slash",
    "reader-mode": "asset:BabelReaderReadingMode", "translate": "sym:translate", "long-image": "asset:BabelReaderShareLongImage",
    "read-all": "asset:Babel2FeedReadAll", "unread-dot": "sym:circle.fill", "list": "asset:BabelHomeAll",
    "today": "sym:sun.max", "inbox": "sym:tray.full", "globe": "sym:globe",
    "folder": "sym:folder", "folder-add": "sym:folder.badge.plus", "edit": "sym:pencil", "trash": "sym:trash",
    "image": "sym:photo", "undo": "sym:arrow.uturn.backward", "copy": "sym:doc.on.doc", "bell": "sym:bell",
    "shield": "sym:shield",
    "account": "sym:person.crop.circle", "feed": "sym:dot.radiowaves.up.forward", "appearance": "sym:circle.lefthalf.filled",
    "help": "sym:questionmark.circle",
    "podcast": "sym:mic", "video": "sym:play.rectangle", "chat": "sym:bubble.left.and.bubble.right",
    "subscribe": "sym:plus.circle", "subscribed": "sym:checkmark.circle.fill",
}


def svg_text(body, color="currentColor", size=24):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" '
            f'stroke="{color}" stroke-width="{STROKE}" stroke-linecap="round" stroke-linejoin="round">{body}</svg>')


def asset_svg(name):
    for base in ("iOS/Babel2/Assets.xcassets", "iOS/Resources/Assets.xcassets"):
        path = os.path.join(ROOT, base, name + ".imageset", name + ".svg")
        if os.path.exists(path):
            return open(path).read()
    raise FileNotFoundError(name)


def write_svgs():
    out = os.path.join(HERE, "svg")
    os.makedirs(out, exist_ok=True)
    for item in ICONS:
        with open(os.path.join(out, item["name"] + ".svg"), "w") as f:
            f.write(svg_text(item["body"]) + "\n")


def render(renderer, kind, source, out_png, px):
    """kind = svg 文件 / sym 系统符号。返回是否成功。"""
    if kind == "svg":
        cmd = [renderer, "svg", source, out_png, str(px)]
    else:
        cmd = [renderer, "sym", source, out_png, str(px / 4 * 0.72), "regular"]
    return subprocess.run(cmd, capture_output=True).returncode == 0


def current_png(renderer, name, tmp, px):
    spec = CURRENT.get(name)
    if not spec:
        return None
    kind, value = spec.split(":", 1)
    out = os.path.join(tmp, f"cur-{name}.png")
    if kind == "asset":
        src = os.path.join(tmp, f"cur-{name}.svg")
        with open(src, "w") as f:
            f.write(asset_svg(value).replace("#787878", "#3a3a3a"))
        ok = render(renderer, "svg", src, out, px)
    else:
        ok = render(renderer, "sym", value, out, px)
    return out if ok else None


def new_png(renderer, item, tmp, px, color="#3a3a3a"):
    src = os.path.join(tmp, f"new-{item['name']}.svg")
    with open(src, "w") as f:
        f.write(svg_text(item["body"], color=color).replace('fill="currentColor"', f'fill="{color}"'))
    out = os.path.join(tmp, f"new-{item['name']}.png")
    return out if render(renderer, "svg", src, out, px) else None


def contact_sheet(renderer, out_path):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 20)
    cell_w, cell_h, px, cols = 300, 110, 72, 4
    rows = (len(ICONS) + cols - 1) // cols
    sheet = Image.new("RGB", (cell_w * cols, cell_h * rows), "white")
    draw = ImageDraw.Draw(sheet)
    with tempfile.TemporaryDirectory() as tmp:
        for i, item in enumerate(ICONS):
            x, y = (i % cols) * cell_w, (i // cols) * cell_h
            cur = current_png(renderer, item["name"], tmp, px)
            new = new_png(renderer, item, tmp, px)
            if cur:
                img = Image.open(cur).convert("RGBA")
                img.thumbnail((px, px))
                sheet.paste(img, (x + 20 + (px - img.width) // 2, y + 8 + (px - img.height) // 2), img)
            if new:
                img = Image.open(new).convert("RGBA")
                sheet.paste(img, (x + 120, y + 8), img)
            draw.line([(x + 106, y + 12), (x + 106, y + 76)], fill="#dddddd")
            draw.text((x + 20, y + 82), item["meaning"][:13], fill="#444444", font=font)
    sheet.save(out_path)


def data_uri_png(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def rules_html():
    """从 icons.py 开头的注释里取「规则」要点（以「# -」开头的行）。"""
    lines = []
    for line in open(os.path.join(HERE, "icons_reeder.py")):
        if not line.startswith("#"):
            break
        text = line.lstrip("#").strip()
        if text.startswith("- "):
            lines.append(f"<li>{html.escape(text[2:])}</li>")
    return f'<ul class="rules">{"".join(lines)}</ul>' if lines else ""


def scenes_html():
    by = {i["name"]: i for i in ICONS}

    def g(name, size):
        return svg_text(by[name]["body"], size=size) if name in by else ""

    bar = "".join(g(n, 21) for n in ["read-off", "star", "chevron-down", "reader-mode", "translate"])
    menu_items = [("edit", "编辑订阅源", ""), ("image", "更换图标", ""), ("undo", "恢复默认图标", ""), ("star", "加星标", ""),
                  ("list", "打开这个源", ""), ("copy", "拷贝订阅地址", ""), ("bell", "新文章通知", ""), ("trash", "取消订阅该源", " danger")]
    menu = "".join(f'<div class="menu-row{cls}">{g(n, 18)}<span>{t}</span></div>' for n, t, cls in menu_items)
    settings_items = [("account", "账户"), ("feed", "订阅源"), ("list", "文章列表"), ("reader-mode", "阅读页"),
                      ("translate", "翻译"), ("appearance", "外观"), ("bell", "通知"), ("help", "支持")]
    settings = "".join(f'<div class="set-row">{g(n, 20)}<span>{t}</span></div>' for n, t in settings_items)
    home_items = [("today", "今日未读"), ("inbox", "全部未读"), ("globe", "外文源")]
    home = (f'<div class="bar">{g("settings", 22)}{g("add", 22)}</div>'
            + "".join(f'<div class="set-row">{g(n, 16)}<span>{t}</span></div>' for n, t in home_items))
    browser = "".join(g(n, 21) for n in ["back", "forward", "refresh", "share", "browser"])
    list_bar = "".join(g(n, 21) for n in ["read-all", "star", "unread-dot", "list", "translate"])
    return f"""<div class="scenes">
<div class="scene"><div class="label">阅读页底栏（21pt）</div><div class="bar">{bar}</div>
<div class="label" style="margin-top:14px">文章列表底栏</div><div class="bar">{list_bar}</div>
<div class="label" style="margin-top:14px">内置浏览器底栏</div><div class="bar">{browser}</div></div>
<div class="scene"><div class="label">长按 / 「•••」菜单（18pt）</div>{menu}</div>
<div class="scene"><div class="label">设置分类（20pt）</div>{settings}</div>
<div class="scene"><div class="label">首页（顶栏 22pt · 入口 16pt）</div>{home}</div>
</div>"""


def review_html(renderer, notes=""):
    groups = []
    for item in ICONS:
        if not groups or groups[-1][0] != item["group"]:
            groups.append((item["group"], []))
        groups[-1][1].append(item)
    with tempfile.TemporaryDirectory() as tmp:
        currents = {item["name"]: current_png(renderer, item["name"], tmp, 96) for item in ICONS}
        uris = {name: data_uri_png(path) for name, path in currents.items() if path}
    rows = []
    for group, items in groups:
        rows.append(f'<h2>{html.escape(group)}</h2><div class="grid">')
        for item in items:
            new = svg_text(item["body"], size=40)
            small = svg_text(item["body"], size=20)
            cur = uris.get(item["name"])
            cur_html = f'<img class="cur" src="{cur}" alt="">' if cur else '<span class="none">—</span>'
            rows.append(f'''<div class="card"><div class="pair"><div class="slot"><span class="tag">现在</span>{cur_html}</div>
<div class="slot new"><span class="tag">新</span>{new}<span class="small">{small}</span></div></div>
<div class="meaning">{html.escape(item["meaning"])}</div><div class="where">{html.escape(item["where"])}</div>
<div class="name">{item["name"]}</div></div>''')
        rows.append('</div>')
    template = open(os.path.join(HERE, "review-template.html")).read()
    page = (template.replace("{{ROWS}}", "\n".join(rows)).replace("{{COUNT}}", str(len(ICONS)))
            .replace("{{RULES}}", rules_html()).replace("{{SCENES}}", scenes_html()).replace("{{NOTES}}", notes))
    with open(os.path.join(HERE, "review.html"), "w") as f:
        f.write(page)


def export_assets():
    """导出成 App 的图片资源：iOS/Babel2/Assets.xcassets/Babel2Icons/Babel2Icon-<名字>.imageset。
    资源里的颜色写死黑色（App 按模板图上色，只看形状）；线条属性写在外层 <g> 上，不依赖 currentColor。"""
    import json
    folder = os.path.join(ROOT, "iOS", "Babel2", "Assets.xcassets", "Babel2Icons")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    for item in ICONS:
        name = "Babel2Icon-" + item["name"]
        imageset = os.path.join(folder, name + ".imageset")
        os.makedirs(imageset, exist_ok=True)
        body = item["body"].replace("currentColor", "#000000")
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
               f'<g fill="none" stroke="#000000" stroke-width="{STROKE}" stroke-linecap="round" stroke-linejoin="round">'
               f'{body}</g></svg>\n')
        with open(os.path.join(imageset, item["name"] + ".svg"), "w") as f:
            f.write(svg)
        contents = {
            "images": [{"filename": item["name"] + ".svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
        }
        with open(os.path.join(imageset, "Contents.json"), "w") as f:
            json.dump(contents, f, indent=2)
            f.write("\n")
    return folder


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--export":
        print(export_assets())
    write_svgs()
    renderer = sys.argv[2] if len(sys.argv) > 2 else None
    if len(sys.argv) > 1 and sys.argv[1] == "--sheet":
        contact_sheet(renderer, sys.argv[3])
    elif len(sys.argv) > 1 and sys.argv[1] == "--review":
        review_html(renderer)
    print(f"{len(ICONS)} icons")
