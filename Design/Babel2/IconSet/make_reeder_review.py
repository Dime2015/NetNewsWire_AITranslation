# 生成第八轮对比页 review-reeder.html：Reeder 原图参考 / 第七轮「瑞士几何」（App 里现在的）/ 第八轮「Reeder 式」候选。
# 用法：python3 make_reeder_review.py
import base64
import html
import importlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
swiss = importlib.import_module("icons")
reeder = importlib.import_module("icons_reeder")
SETS = [("swiss", "第七轮 · 瑞士几何（App 里现在的）", swiss), ("reeder", "第八轮 · Reeder 式（候选）", reeder)]


def svg(mod, name, size, extra=""):
    item = next(i for i in mod.ICONS if i["name"] == name)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" '
            f'stroke="currentColor" stroke-width="{mod.STROKE}" stroke-linecap="round" stroke-linejoin="round">'
            f'{item["body"]}{extra}</svg>')


def reference_images():
    """从 Reeder 截图裁出底栏 / 顶栏 / 设置分类，缩小后内嵌（只在本地看，不发布）。"""
    from PIL import Image
    src = os.path.join(ROOT, "Reeder screenshots")
    crops = [("1.PNG", (0, 2440, 1206, 2560), "文章列表底栏"), ("3.PNG", (0, 2440, 1206, 2560), "阅读页底栏"),
             ("3.PNG", (0, 170, 1206, 290), "阅读页顶栏"), ("4.PNG", (0, 170, 1206, 290), "首页顶栏"),
             ("2.PNG", (0, 170, 1206, 290), "文件夹页顶栏")]
    out = []
    for f, box, label in crops:
        im = Image.open(os.path.join(src, f)).convert("RGB").crop(box)
        im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=88)
        out.append((label, "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()))
    im = Image.open(os.path.join(src, "5.PNG")).convert("RGB").crop((40, 520, 700, 1880))
    im = im.resize((im.width // 3, im.height // 3), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=88)
    settings = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    return out, settings


# 翻译按钮在 App 里右下角会画一个缓存圆点（实心 = 整篇译文已缓存），场景里一起画出来看位置
CACHE_DOT = '<circle cx="20" cy="19.5" r="2.25" fill="currentColor" stroke="none"/>'


def scenes(mod):
    def g(n, s, extra=""):
        return svg(mod, n, s, extra)
    reader_bar = "".join([g("read-off", 21), g("star", 21), g("chevron-down", 21), g("reader-mode", 21), g("translate", 21, CACHE_DOT)])
    reader_bar_on = "".join([g("read-on", 21), g("star-on", 21), g("chevron-down", 21), g("reader-mode", 21), g("translate", 21)])
    list_bar = (g("read-all", 21) + g("star", 21) + '<span class="pill"><i></i>UNREAD</span>' + g("list", 21) + g("search", 21))
    browser_bar = "".join(g(n, 21) for n in ["back", "forward", "refresh", "share", "browser"])
    top = f'<div class="bar top">{g("close", 22)}{g("more", 22)}{g("share", 22)}</div>'
    home_top = f'<div class="bar top">{g("settings", 22)}<span class="chip">{g("sync", 16)}</span>{g("add", 22)}</div>'
    menu_items = [("edit", "编辑订阅源", ""), ("image", "更换图标", ""), ("undo", "恢复默认图标", ""), ("star-off", "取消星标", ""),
                  ("list", "打开这个源", ""), ("copy", "拷贝订阅地址", ""), ("bell", "新文章通知", ""), ("long-image", "生成长图", ""),
                  ("shield", "去广告", ""), ("trash", "取消订阅该源", " danger")]
    menu = "".join(f'<div class="row{c}">{g(n, 20)}<span>{t}</span></div>' for n, t, c in menu_items)
    settings_items = [("account", "账户"), ("feed", "订阅源"), ("list", "文章列表"), ("reader-mode", "阅读页"),
                      ("translate", "翻译"), ("appearance", "外观"), ("bell", "通知"), ("help", "支持")]
    settings = "".join(f'<div class="row">{g(n, 20)}<span>{t}</span>{g("forward", 14)}</div>' for n, t in settings_items)
    home = "".join(f'<div class="row">{g(n, 18)}<span>{t}</span></div>' for n, t in [("today", "今日未读"), ("inbox", "全部未读"), ("globe", "外文源")])
    add_rows = "".join(f'<div class="row">{g(n, 20)}<span>{t}</span>{g(s, 22)}</div>' for n, t, s in
                       [("podcast", "The Daily", "subscribe"), ("video", "Veritasium", "subscribed"), ("chat", "r/apple", "subscribe"), ("globe", "daringfireball.net", "subscribed")])
    return f"""
<div class="scene"><div class="label">阅读页顶栏 · 底栏（未读 / 已读已星标）</div>{top}
<div class="bar">{reader_bar}</div><div class="bar">{reader_bar_on}</div>
<div class="label">文章列表底栏</div><div class="bar">{list_bar}</div>
<div class="label">内置浏览器底栏</div><div class="bar">{browser_bar}</div></div>
<div class="scene"><div class="label">首页顶栏 · 入口</div>{home_top}{home}
<div class="label">添加订阅（类别 · 订阅 / 已订阅）</div>{add_rows}</div>
<div class="scene"><div class="label">长按 / 「•••」菜单</div>{menu}</div>
<div class="scene"><div class="label">设置分类</div>{settings}</div>"""


def main():
    refs, settings_ref = reference_images()
    ref_html = "".join(f'<figure><img src="{u}" alt=""><figcaption>{l}</figcaption></figure>' for l, u in refs)
    cols = "".join(f'<section class="set" data-set="{k}"><h3>{html.escape(t)}</h3><div class="scenes">{scenes(m)}</div></section>'
                   for k, t, m in SETS)
    groups = []
    for item in reeder.ICONS:
        if not groups or groups[-1][0] != item["group"]:
            groups.append((item["group"], []))
        groups[-1][1].append(item)
    grid = []
    for group, items in groups:
        grid.append(f'<h2>{html.escape(group)}</h2><div class="grid">')
        for it in items:
            n = it["name"]
            grid.append(f'''<div class="card"><div class="pair">
<div class="slot"><span class="tag">现在</span>{svg(swiss, n, 40)}<span class="small">{svg(swiss, n, 20)}</span></div>
<div class="slot new"><span class="tag">Reeder 式</span>{svg(reeder, n, 40)}<span class="small">{svg(reeder, n, 20)}</span></div></div>
<div class="meaning">{html.escape(it["meaning"])}</div><div class="where">{html.escape(it["where"])}</div></div>''')
        grid.append("</div>")
    rules = []
    for line in open(os.path.join(HERE, "icons_reeder.py")):
        if not line.startswith("#"):
            break
        t = line.lstrip("#").strip()
        if t.startswith("- "):
            rules.append(f"<li>{html.escape(t[2:])}</li>")
    page = open(os.path.join(HERE, "review-reeder-template.html")).read()
    page = (page.replace("{{REFS}}", ref_html).replace("{{SETTINGS_REF}}", settings_ref).replace("{{SETS}}", cols)
            .replace("{{GRID}}", "\n".join(grid)).replace("{{RULES}}", "".join(rules)).replace("{{COUNT}}", str(len(reeder.ICONS))))
    with open(os.path.join(HERE, "review-reeder.html"), "w") as f:
        f.write(page)
    print(os.path.join(HERE, "review-reeder.html"))


if __name__ == "__main__":
    main()
