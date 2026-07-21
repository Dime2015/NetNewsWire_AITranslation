#!/usr/bin/env python3
"""
把某种语言的翻译注入 Xcode 字符串目录(.xcstrings)。

设计目标 —— 为什么不用普通的 json.dump:
Xcode 写 .xcstrings 用的是一种特殊格式(键与冒号之间有空格、空对象里带空行、
文件末尾没有换行)。普通 JSON 序列化会把整个文件重排,
`git diff` 变成"整份文件都改了" —— 那会让 `git pull upstream` 的冲突无法阅读。

本脚本复刻了 Xcode 的格式,已验证对本项目 4 个 .xcstrings 文件都能
**字节级还原**。所以注入翻译后,git diff 只会显示新增的行。

用法:
    python3 i18n/inject.py zh-Hans          # 注入
    python3 i18n/inject.py zh-Hans --check  # 只体检,不写文件

翻译表放在 i18n/<语言代码>.json,格式:{"English key": "译文", ...}

加一门新语言(例如日语)要做的全部事情:
    1. python3 i18n/inject.py ja --check    # 会列出所有待翻的 key
    2. 照着列表写 i18n/ja.json
    3. python3 i18n/inject.py ja
    4. 翻译 iOS/Base.lproj/Main.storyboard → 新建 iOS/ja.lproj/Main.strings
    5. 编译一次(Xcode 会自动把 ja 加进工程的 knownRegions)
详见 NOTES-i18n.md。
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# 需要注入的字符串目录。新增目录时加在这里。
CATALOGS = [
    "Shared/Localizable.xcstrings",
    "Shared/DefaultAccountNames.xcstrings",
    "Widget/Resources/Localizable.xcstrings",
    "Modules/ActivityLog/Sources/ActivityLog/Resources/Localizable.xcstrings",
]


def render(obj, indent=0):
    """复刻 Xcode 的 .xcstrings 写法。"""
    pad = " " * indent
    pad2 = " " * (indent + 2)
    if isinstance(obj, dict):
        if not obj:
            return "{\n\n" + pad + "}"
        parts = [f"{pad2}{json.dumps(k, ensure_ascii=False)} : {render(v, indent + 2)}"
                 for k, v in obj.items()]
        return "{\n" + ",\n".join(parts) + "\n" + pad + "}"
    if isinstance(obj, list):
        if not obj:
            return "[\n\n" + pad + "]"
        parts = [f"{pad2}{render(v, indent + 2)}" for v in obj]
        return "[\n" + ",\n".join(parts) + "\n" + pad + "]"
    return json.dumps(obj, ensure_ascii=False)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    language = sys.argv[1]
    check_only = "--check" in sys.argv

    table_path = REPO / "i18n" / f"{language}.json"
    table = {}
    if table_path.exists():
        table = json.loads(table_path.read_text(encoding="utf-8"))
        # 允许在翻译表里写以 _ 开头的说明字段,注入时忽略
        table = {k: v for k, v in table.items() if not k.startswith("_")}

    all_keys = set()
    untranslated = []
    injected_total = 0

    for rel in CATALOGS:
        path = REPO / rel
        if not path.exists():
            print(f"⚠️  找不到 {rel},跳过")
            continue

        original = path.read_text(encoding="utf-8")
        data = json.loads(original)

        # 先自检:本脚本能否字节级还原这个文件?不能就绝不写入,避免制造 diff 噪音。
        if render(data) != original:
            print(f"❌ {rel}:格式还原校验失败,已跳过(不写入,以免污染 diff)")
            continue

        injected = 0
        for key, entry in data.get("strings", {}).items():
            if not key.strip():
                continue
            all_keys.add(key)
            translation = table.get(key)
            if translation is None:
                untranslated.append((rel, key))
                continue
            localizations = entry.setdefault("localizations", {})
            localizations[language] = {
                "stringUnit": {"state": "translated", "value": translation}
            }
            injected += 1

        injected_total += injected
        if not check_only and injected:
            path.write_text(render(data), encoding="utf-8")
        status = "(仅体检)" if check_only else "已写入"
        print(f"{'✅' if injected else '  '} {rel}: {injected} 条 {status}")

    # 体检报告
    unknown = [k for k in table if k not in all_keys]

    print(f"\n合计注入 {injected_total} 条")
    if unknown:
        print(f"\n⚠️  翻译表里有 {len(unknown)} 条在字符串目录里找不到(多半是引号或空格抄错了):")
        for k in unknown[:20]:
            print(f"    {k!r}")
        if len(unknown) > 20:
            print(f"    …还有 {len(unknown) - 20} 条")
    if untranslated:
        print(f"\n📝 还有 {len(untranslated)} 条没翻译:")
        for rel, k in untranslated[:40]:
            print(f"    [{Path(rel).parent.name}] {k!r}")
        if len(untranslated) > 40:
            print(f"    …还有 {len(untranslated) - 40} 条")

    return 0


if __name__ == "__main__":
    sys.exit(main())
