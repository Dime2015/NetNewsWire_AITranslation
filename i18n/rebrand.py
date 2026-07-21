#!/usr/bin/env python3
"""改 app 的显示名。

用法:
    python3 i18n/rebrand.py Babel        # 改成 Babel
    python3 i18n/rebrand.py --check      # 只看现在叫什么、还有哪里没改干净

做了什么
--------
1. 改 `xcconfig/NetNewsWire_iOSapp_target.xcconfig` 里的 `APP_DISPLAY_NAME`
   —— 这是主屏和界面上那个名字的**单一真源**
2. 把**我们自己维护的中文文案**里写死的旧名字换成新名字:
     · i18n/zh-Hans.json                     (注入 .xcstrings 的译文源头)
     · iOS/**/zh-Hans.lproj/*.strings        (storyboard 的中文译文)
3. 提醒你重新跑注入脚本和编译

刻意不做的事(重要)
------------------
· **不改 bundle id**。一改,iOS 会把它当成另一个 app 重新安装,
  订阅源、翻译 API Key、已读状态、缓存**全部清零**。
  而且这和显示名毫无关系 —— 主屏显示的是 CFBundleDisplayName。
· **不改 target / scheme / .xcodeproj / 模块名 / 类名**。
  那是 370 个 Swift 文件 + 143 处 pbxproj 的改动,会让所有构建命令失效,
  也会让 `git pull upstream` 从此变成灾难。用户永远看不到这些名字。
· **不改英文原文**(.xcstrings 的英文一侧)。那是上游的文件,
  我们只往里注入中文译文。英文界面显示的仍然是上游的原名 ——
  如果哪天要连英文一起改,那是另一个决定,需要单独评估。
· **不改 User-Agent**(Info.plist 里的 `UserAgent`)。
  那是给服务器看的兼容性标识,不是给人看的名字。实测 Reddit 等站点
  认这个值;换成没人认识的名字有被拒的风险(教训见 NOTES-lessons L33)。
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 单一真源:app 显示名就写在这个文件的这个键上
BRAND_XCCONFIG = os.path.join(REPO, "xcconfig", "NetNewsWire_iOSapp_target.xcconfig")
BRAND_KEY = "APP_DISPLAY_NAME"

# 我们自己维护、且可能写死了品牌名的文案文件
OWN_TEXT_FILES = [
    os.path.join(REPO, "i18n", "zh-Hans.json"),
]


def find_own_strings_files():
    """找出本 fork 自己新增的 <语言>.lproj/*.strings(上游那些不动)。"""
    found = []
    for root, dirs, files in os.walk(os.path.join(REPO, "iOS")):
        if not root.endswith(".lproj") or root.endswith("Base.lproj"):
            continue
        for name in files:
            if name.endswith(".strings"):
                found.append(os.path.join(root, name))
    return sorted(found)


def current_brand():
    """读出当前的显示名。读不到就退回 NetNewsWire(上游原名)。"""
    if not os.path.exists(BRAND_XCCONFIG):
        return "NetNewsWire"
    with open(BRAND_XCCONFIG, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*%s\s*=\s*(.+?)\s*$" % BRAND_KEY, line)
            if m:
                return m.group(1)
    return "NetNewsWire"


def set_brand(new_name):
    with open(BRAND_XCCONFIG, encoding="utf-8") as f:
        text = f.read()
    if re.search(r"^\s*%s\s*=" % BRAND_KEY, text, re.M):
        text = re.sub(r"^(\s*%s\s*=\s*).+$" % BRAND_KEY,
                      lambda m: m.group(1) + new_name, text, flags=re.M)
    else:
        text += "\n%s = %s\n" % (BRAND_KEY, new_name)
    with open(BRAND_XCCONFIG, "w", encoding="utf-8") as f:
        f.write(text)


def replace_in_translation_json(path, old, new):
    """替换翻译表里的品牌名 —— **只动译文,绝不动键**。

    ⚠️ 这条区分是这个脚本里最要紧的一处。

    `i18n/zh-Hans.json` 的**键是英文原文**,必须和上游 `.xcstrings` 里的英文
    一字不差,`inject.py` 才能对上号。第一版脚本图省事做了全文替换,
    结果把键里的 "NetNewsWire" 也换成了新名字 ——
    那 6 条翻译会**静默地注入不进去**,界面上悄悄变回英文,
    而且没有任何报错(正是 NOTES-lessons L20 记过的那类坑)。

    `_术语` 那条是写给译者看的术语表,不是界面文案,也跳过。
    """
    import json
    with open(path, encoding="utf-8") as f:
        text = f.read()
    data = json.loads(text)

    count = 0
    for key, value in data.items():
        if key.startswith("_"):        # 以下划线开头的是给译者的说明,不是界面文案
            continue
        if isinstance(value, str) and old in value:
            count += value.count(old)
            data[key] = value.replace(old, new)
        elif isinstance(value, dict):  # 设备变体(见 L21)
            for variant_key, variant_value in value.items():
                if isinstance(variant_value, str) and old in variant_value:
                    count += variant_value.count(old)
                    value[variant_key] = variant_value.replace(old, new)

    if count:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
    return count


def replace_in_files(paths, old, new):
    changed = []
    for path in paths:
        if not os.path.exists(path):
            continue

        # 翻译表要按 JSON 结构处理,不能全文替换 —— 原因见上面那个函数
        if path.endswith(".json"):
            count = replace_in_translation_json(path, old, new)
            if count:
                changed.append((os.path.relpath(path, REPO), count))
            continue

        # .strings 的键是 storyboard 的对象 id(形如 "76A-Ng-kfs.text"),
        # 不含品牌名,所以全文替换是安全的
        with open(path, encoding="utf-8") as f:
            text = f.read()
        count = text.count(old)
        if count == 0:
            continue
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.replace(old, new))
        changed.append((os.path.relpath(path, REPO), count))
    return changed


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    brand = current_brand()
    targets = OWN_TEXT_FILES + find_own_strings_files()

    if sys.argv[1] == "--check":
        print("当前显示名:%s" % brand)
        print("\n我们自己的文案文件里还剩多少处旧名字「NetNewsWire」:")
        total = 0
        for path in targets:
            if not os.path.exists(path):
                continue
            with open(path, encoding="utf-8") as f:
                n = f.read().count("NetNewsWire")
            if n:
                total += n
                print("  %-52s %d 处" % (os.path.relpath(path, REPO), n))
        if total == 0:
            print("  (没有了)")
        print("\n注:英文原文、类名、bundle id 里的 NetNewsWire 是**故意保留**的,"
              "\n    原因见本文件开头的说明。")
        return

    new_name = sys.argv[1].strip()
    if not new_name:
        print("新名字不能为空")
        sys.exit(1)
    # ⚠️ 即使 xcconfig 里已经是新名字,也**不能提前返回**。
    # 真实情况会出现「名字改了但文案还没改」的中间状态(改到一半被打断、
    # 或者先手动改了 xcconfig)。这个脚本必须能反复跑、每次都把状态推到完整,
    # 而不是看一眼第一处就宣布无事可做。
    if new_name == brand:
        print("显示名已经是「%s」,继续检查界面文案是否也改干净了。\n" % brand)
    else:
        print("显示名:%s → %s\n" % (brand, new_name))

    set_brand(new_name)
    print("✅ 单一真源:%s 的 %s = %s"
          % (os.path.relpath(BRAND_XCCONFIG, REPO), BRAND_KEY, new_name))

    # 旧名字可能是上游原名,也可能是上一次改成的名字,两个都要换
    changed = []
    for old in {brand, "NetNewsWire"}:
        if old == new_name:
            continue
        changed += replace_in_files(targets, old, new_name)

    if changed:
        print("\n✅ 界面文案已替换:")
        for path, count in changed:
            print("   %-52s %d 处" % (path, count))
    else:
        print("\n(界面文案里没有需要替换的地方)")

    print("""
接下来还要跑两条命令才会生效:

    python3 i18n/inject.py zh-Hans      # 把改好的译文注入 .xcstrings
    然后重新编译安装

改完请在模拟器上确认:主屏图标下面的名字、以及 设置 → 关于。""")


if __name__ == "__main__":
    main()
