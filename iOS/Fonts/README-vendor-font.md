# 第三方字体:思源宋体(Noto Serif CJK SC)

本目录放的是**原样搬进来的第三方文件**,规矩见 `CLAUDE.md` 第 2 节
「第三方 vendored 文件的规矩」。**不要手改这个字体文件**,要换就整个替换并更新本文件。

> ⚠️ **文件名为什么不是 `README-vendor.md`**:`Shared/ReaderView/` 下已经有一个同名文件,
> 而 Xcode 的「文件系统同步文件夹」会把这类文件**原样拷进 app 包的根目录** ——
> 两个同名文件就会撞车,报 `Multiple commands produce .../README-vendor.md`,编译直接失败。
> 所以本文件叫 `README-vendor-font.md`。**以后再加 vendored 目录,记得起不重名的文件名。**

---

## 文件

| | |
|---|---|
| 文件名 | `NotoSerifCJKsc-Bold-subset.otf` |
| 大小 | 2.1 MB(子集化后;原文件 24 MB) |
| SHA-256(子集后) | `03c5ad6242438473aae4c9c903a27471947e4107daa4496fc350a9b1e1a590e6` |
| PostScript 名 | `NotoSerifCJKsc-Bold` ← **代码里按这个名字取字体** |
| 字族 / 字重 | Noto Serif CJK SC / Bold |

## 来源

| | |
|---|---|
| 项目 | [notofonts/noto-cjk](https://github.com/notofonts/noto-cjk) |
| 下载地址 | `https://raw.githubusercontent.com/notofonts/noto-cjk/main/Serif/OTF/SimplifiedChinese/NotoSerifCJKsc-Bold.otf` |
| 下载日期 | 2026-07-23 |
| 原文件 SHA-256 | `8af07d4b6c2e82bcc72a30e066eaf295f11b9424f4aad2eaa9fe0e9c3b38fc73` |
| 授权 | **SIL Open Font License 1.1** —— 允许自由使用、修改(含子集化)、随软件再分发 |
| 版权 | © 2017-2024 Adobe (http://www.adobe.com/) |

⚠️ **OFL 的两条硬要求,别违反**:
1. 字体文件本身**不得单独出售**(随 app 分发没问题)
2. 修改后的版本**不得使用 "Noto" 保留名称**发布 ——
   我们只是**子集化**(删掉用不到的字形),没有改字形、也没有重命名字族,
   属于 OFL 明确允许的"修改后随软件分发";文件名加了 `-subset` 以示区别。
   字体内部的版权与授权声明**原样保留**(子集化时用 `--name-IDs='*'` 保住了 name 表)。

## 为什么要打包一个字体(而不是用系统自带的)

头图标题有意用**衬线体**(报头 / 杂志刊名的气质,和下面文章标题的黑体拉开层次)。
西文用苹果自带的 New York,而**中文没有任何系统衬线可用** ——
2026-07-23 在 app 里实测过一次完整字体名单:

> iOS 26.5 上认识简体字的字体,**只有苹方(PingFang)的四个地区版 × 六个字重,
> 全是黑体,一个衬线都没有。**

试过、都不行的路(**别再重试**,详见 `NOTES-lessons.md` L70):
- 宋体 `STSongti-SC-Bold` —— 那是 **macOS 才有的**,iOS 上 `UIFont(name:)` 返回 nil
- 日文明朝体 `HiraMinProN-W6` —— iOS 确实带,但**缺简体专用字**
  (实测「读」「标」「观」「严」「肃」「长」都没有),用了会一个标题里半衬线半黑体
- `withDesign(.serif)` —— 只影响西文,对汉字无效

## 子集化是怎么做的(要换字重 / 换字体,照这个重跑)

只保留 **GB2312 全集(一级 3755 + 二级 3008 = 6763 字)** + ASCII + 常用中文标点,
24 MB → 2.1 MB。

```bash
python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install fonttools brotli

# 生成字符表(GB2312 全集 + 符号)
/tmp/fontenv/bin/python - <<'PY'
chars = set()
for b1 in range(0xB0, 0xF8):
    for b2 in range(0xA1, 0xFF):
        try: chars.add(bytes([b1, b2]).decode('gb2312'))
        except Exception: pass
chars |= set(chr(c) for c in range(0x20, 0x7F))
chars |= set("　、。〈〉《》「」『』【】〔〕・…—～‘’“”（）·￥°℃±×÷")
chars |= set("０１２３４５６７８９")
open('/tmp/subset-chars.txt', 'w', encoding='utf-8').write(''.join(sorted(chars)))
PY

/tmp/fontenv/bin/pyftsubset <原始字体>.otf \
  --text-file=/tmp/subset-chars.txt \
  --output-file=NotoSerifCJKsc-Bold-subset.otf \
  --layout-features='' --no-hinting --desubroutinize \
  --name-IDs='*' --drop-tables+=DSIG
```

⚠️ `--name-IDs='*'` **不能省** —— 它保住字体内部的 name 表(含版权与授权声明),
OFL 要求保留;顺带也保住了 PostScript 名,否则代码里按名字取字体会失败。

## 字体是怎么装进 app 的

**没有改 `Info.plist`**(那是上游文件,加 `UIAppFonts` 会留下一处 merge 冲突点)。
改为**运行时注册**:`CTFontManagerRegisterFontsForURL`,实现在
`iOS/MainTimeline/TimelineStyle.swift` 的 `nnwRegisterBundledSerifIfNeeded()`。

⚠️ **缺字保护**:订阅源名是任意的,万一某个字不在这 6763 字里,
`headerTitleFont(for:)` 会**整条退回黑体**,绝不出现"一个标题里半衬线半黑体"。
