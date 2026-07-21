# NOTES-i18n.md — 多语言(本地化)工程手册

> 本文件回答一个问题:**再加一门语言(比如日语),要动哪些地方、怎么最省事。**
> 简体中文已按这套流程落地(2026-07-21),可作为范例。

最后更新:2026-07-21

---

## 一、加一门新语言的完整清单

以日语(`ja`)为例。**全部步骤加起来,除了翻译本身,只有 4 条命令。**

```bash
# 1. 看看要翻什么(不写任何文件,只列清单)
python3 i18n/inject.py ja --check

# 2. 照着清单写 i18n/ja.json,格式:{"English key": "訳文", ...}
#    (可以直接复制 i18n/zh-Hans.json 改)

# 3. 注入到 4 个字符串目录
python3 i18n/inject.py ja

# 4. 翻译 Storyboard:先导出可翻条目,再照着写 iOS/ja.lproj/Main.strings
xcrun ibtool --export-strings-file /tmp/Main.strings iOS/Base.lproj/Main.storyboard

# 5. 编译一次。Xcode 会自动把 ja 加进工程的 knownRegions
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
```

**语言选择器不用改。** `Shared/Translation/AppLanguageController.swift` 的可选项直接来自
`Bundle.main.localizations` —— app 包里有什么语言就列什么,日语会自动出现。

---

## 二、这套东西由什么组成

| 位置 | 作用 | 属于谁 |
|---|---|---|
| `i18n/inject.py` | 把翻译注入 .xcstrings,**保留 Xcode 的原始格式** | 本 fork 新增 |
| `i18n/zh-Hans.json` | 简体中文翻译表(436 条) | 本 fork 新增 |
| `iOS/zh-Hans.lproj/Main.strings` | Main.storyboard 的中文 | 本 fork 新增 |
| `Shared/Translation/AppLanguageController.swift` | 语言的读写,可选项自动发现 | 本 fork 新增 |
| `Shared/Translation/AppLanguagePickerViewController.swift` | 设置 → 外观 → 界面语言 | 本 fork 新增 |
| 4 个 `.xcstrings` | 上游文件,**被注入了 zh-Hans 段** | 上游 |
| `iOS/Settings/SettingsViewController.swift` | 加了「界面语言」一行 | 上游 |

被注入的 4 个字符串目录:

```
Shared/Localizable.xcstrings                                    384 条
Shared/DefaultAccountNames.xcstrings                              1 条
Widget/Resources/Localizable.xcstrings                           11 条
Modules/ActivityLog/Sources/ActivityLog/Resources/Localizable.xcstrings  40 条
```

---

## 三、为什么必须改上游文件(试过绕开,失败了)

最初的设想是"完全不碰上游文件,另起一份自己的中文表"。**实测被 Xcode 拒绝:**

```
error: Localizable.xcstrings cannot co-exist with other .strings
       or .stringsdict tables with the same name.
```

字符串目录(.xcstrings)和同名 .strings 不能并存,所以翻译**只能写进上游那个目录里**。

### 把伤害降到最小的做法

`i18n/inject.py` **复刻了 Xcode 写 .xcstrings 的格式**(键与冒号间有空格、空对象带空行、
文件末尾无换行),并且在写入前会自检"能否字节级还原原文件",不能就拒绝写入。

因此注入后 `git diff` **只显示新增的行**,不会把整个文件重排。
已验证:注入 436 条后,逐 key 对比确认**除新增 zh-Hans 外,原有内容一个字节都没变**。

### 冲突了怎么办(写给未来的自己)

`git pull upstream` 时若这几个 .xcstrings 冲突:

> **规则极简单:`zh-Hans`/`ja` 等我们加的语言段,永远保留我们的;
> `en` 段和 `comment` 永远用上游的。**

而且本地化文件的冲突**不可能弄坏 app 逻辑** —— 最坏结果是某几句显示英文。
这是所有冲突类型里最安全的一种。

上游若新增了字符串,`python3 i18n/inject.py zh-Hans --check` 会把没翻的列出来。

---

## 四、Storyboard 分两类,命运不同

| 类型 | 判断方法 | 能否翻译 |
|---|---|---|
| **已本地化** | 文件在 `Base.lproj/` 里 | ✅ 纯新增 `<语言>.lproj/xxx.strings`,零上游改动 |
| **未本地化** | 文件不在任何 `.lproj` 里 | ❌ 必须先把文件移进 `Base.lproj/` |

本项目现状:

```
iOS/Base.lproj/Main.storyboard              ← 上游就已本地化,已翻译
iOS/Settings/Base.lproj/Settings.storyboard ← 本 fork 移入 Base.lproj,已翻译
iOS/Account/Base.lproj/Account.storyboard   ← 本 fork 移入 Base.lproj,已翻译
iOS/Add/Base.lproj/Add.storyboard           ← 本 fork 移入 Base.lproj,已翻译
iOS/Inspector/Base.lproj/Inspector.storyboard ← 本 fork 移入 Base.lproj,已翻译
```

**把未本地化的 storyboard 变成可翻译的**(本 fork 已对上面 4 个做过):

```bash
mkdir -p iOS/Settings/Base.lproj
git mv iOS/Settings/Settings.storyboard iOS/Settings/Base.lproj/Settings.storyboard
```

用 `git mv` 而不是普通移动 —— git 会把它记成**重命名**而非删除+新增,
将来上游改这个文件时 git 能自动跟踪过去,冲突面小得多。
移完编译一次,确认它出现在 app 包的 `Base.lproj/` 里而不是包根目录。

**验证某个 storyboard 属于哪类**:编译后看它落在 app 包的哪里 ——
在 `Base.lproj/` 里就是已本地化,在包根目录就是未本地化。

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData/NetNewsWire-*/Build/Products/Debug-iphonesimulator \
  -maxdepth 1 -name "NetNewsWire.app" -type d | head -1)
ls "$APP"/*.storyboardc          # 未本地化的
ls "$APP"/Base.lproj/*.storyboardc  # 已本地化的
```

---

## 五、语言切换是怎么工作的

- **默认跟随系统**:不写任何设置时,iOS 按设备语言自动选。
- **手动指定**:设置 → 外观 → 界面语言。写入系统的 `AppleLanguages` 键覆盖。
- **需要重启 app 生效** —— 界面文字在启动时加载,这是 iOS 的固有行为,不是 bug。
  选择器里已经写明了这一点。
- **未翻译的条目自动回退到英文**,不会显示成空白或 key 名。

我们另外记了一个 `nnwSelectedInterfaceLanguage` 键。
**为什么不直接读 `AppleLanguages`**:系统会把它改写成完整的回退链(如 `["zh-Hans","en"]`),
读回来分不清"用户主动选了中文"还是"系统本来就是中文",没法正确显示"跟随系统"那一项的勾。

---

## 六、翻译时的约定

术语表写在 `i18n/zh-Hans.json` 顶部的 `_术语` 字段里,加新语言时请照建对应的表。

简体中文的核心约定:

| 英文 | 中文 |
|---|---|
| Feed | **保持英文不译**(智能 Feed、添加 Feed) |
| Smart Feed | 智能 Feed |
| Article | 文章 |
| Starred | 已加星标 |
| Read / Unread | 已读 / 未读 |
| Account | 账户 |
| Reader View | 阅读视图 |
| Timeline | 文章列表 |

专有名词(NetNewsWire、Feedly、iCloud、OPML、NewsBlur…)一律保持英文。

### 两个容易踩的坑

**1. 调换了占位符顺序,必须用位置参数。**
例如 `Install theme "%@" by %@?` 译成中文后两个参数顺序反了,
就必须写成 `安装由 %2$@ 制作的主题"%1$@"?` —— 否则参数会错位。

**2. 键必须与目录里的原文完全一致**,包括弯引号(`"` `"` `'`)、
不间断空格(`\xa0`)、多余的空格。抄错了 `inject.py` 会报
"翻译表里有 N 条在字符串目录里找不到",**照着报告改就行,不会静默失败**。

---

## 七、还没做的部分

| 内容 | 为什么没做 |
|---|---|
| macOS 专属界面 | macOS 不在项目范围内(CLAUDE.md 第 1 节) |

iOS 侧的界面文案已全部汉化(436 条字符串 + 5 个 storyboard)。
