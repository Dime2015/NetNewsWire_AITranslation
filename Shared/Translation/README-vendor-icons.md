# 厂商 logo 的来源与校验(vendored 第三方素材)

> 按 CLAUDE.md「第三方 vendored 文件的规矩」记录:**单独目录 + README-vendor 记录来源与校验和**。
> 素材本身在 `iOS/Resources/Assets.xcassets/vendor-*.imageset/`。

最后更新:2026-08-08

## 这是什么

模型选择页(设置 → 翻译模型)厂商分组前面那颗图标。用户 2026-08-08 要求「把厂商 logo 加在前面」。

## ⚠️ 为什么只有 25 家(全部 52 家里)

拿 logo 试过三条路,结论记在 `OpenRouterVendorStyle.swift` 的文件头和 NOTES-todo T51:

| 路子 | 结果 |
|---|---|
| `/api/v1/models` 里找图片地址 | ❌ 没有这种字段 |
| 猜 OpenRouter `/images/icons/` 的文件名 | 58 家只中 12(那目录放的是**推理提供商**,`amazon → Bedrock.svg`) |
| 拿它 101 个提供商名去对 | 只中 13 |
| 去它前端 53 个 JS chunk 里挖 | **一个图标路径都没有** —— 图标是**内联在代码里的组件** |
| 补 Simple Icons(CC0) | 补到 25 家 |

**剩下 27 家继续用自绘字母徽标**(主题色圆角方块 + 首字母),
用户看过对照表后选的**方案 A**:接受真 logo 和字母徽标混排。

## 规矩(和 Readability.js 那份一样)

- **不许手改这些 SVG**。要调外观改 `OpenRouterVendorStyle.swift`
- 升级 = **整个文件替换**,然后更新下面这张表的字节数与 SHA-256
- **商标归各品牌所有**。这里是"标识出处"的用法(nominative use),
  Simple Icons 本身是 CC0

## 渲染方式

- `original` = 保留品牌色(彩色图标,浅色深色都读得出来)
- `template` = 单色图标,**染成主题色**。⚠️ 它们的原色是**纯黑**,深色模式下会直接消失(L112);
  染主题色一举两得 —— 深浅色都读得出来,而且和这个 app「单一强调色」的调子一路

## 清单

| 厂商 slug | 资源名 | 来源 | 渲染 | 大小 | SHA-256(前 16) |
|---|---|---|---|---|---|
| `amazon` | `vendor-amazon` | OpenRouter | original | 1133B | `06eedc9924b9d544` |
| `anthropic` | `vendor-anthropic` | OpenRouter | original | 584B | `a7dc6e7705f702a1` |
| `baidu` | `vendor-baidu` | SimpleIcons:baidu | original | 1406B | `c06b13de3ac002d1` |
| `bytedance` | `vendor-bytedance` | SimpleIcons:bytedance | original | 346B | `09e1b96b8565257e` |
| `bytedance-seed` | `vendor-bytedance-seed` | SimpleIcons:bytedance | original | 346B | `09e1b96b8565257e` |
| `deepseek` | `vendor-deepseek` | SimpleIcons:deepseek | original | 2101B | `b0b2c0dfb3acb314` |
| `google` | `vendor-google` | OpenRouter | original | 623B | `968da8483e45257b` |
| `ibm-granite` | `vendor-ibm-granite` | OpenRouter | template | 972B | `537710ece9271647` |
| `inception` | `vendor-inception` | OpenRouter | template | 2926B | `4dc46d424fdd128a` |
| `kwaipilot` | `vendor-kwaipilot` | SimpleIcons:kuaishou | original | 1180B | `ed951f8f64841ba3` |
| `meituan` | `vendor-meituan` | SimpleIcons:meituan | original | 1215B | `c030f195b10a5930` |
| `meta` | `vendor-meta` | SimpleIcons:meta | original | 1339B | `18e15e0cd6ef858a` |
| `meta-llama` | `vendor-meta-llama` | SimpleIcons:meta | original | 1339B | `18e15e0cd6ef858a` |
| `microsoft` | `vendor-microsoft` | OpenRouter | original | 309B | `b865b2a564235a3f` |
| `minimax` | `vendor-minimax` | SimpleIcons:minimax | original | 736B | `e514235f472e335f` |
| `mistralai` | `vendor-mistralai` | SimpleIcons:mistralai | original | 305B | `5d6abe5c18446f79` |
| `moonshotai` | `vendor-moonshotai` | SimpleIcons:moonshotai | template | 667B | `652aefb614833aee` |
| `nex-agi` | `vendor-nex-agi` | OpenRouter | template | 1217B | `61138e5b098100d9` |
| `nvidia` | `vendor-nvidia` | SimpleIcons:nvidia | original | 896B | `db04aa87719392f2` |
| `openai` | `vendor-openai` | OpenRouter | template | 1709B | `6ab2f60b45feb247` |
| `openrouter` | `vendor-openrouter` | SimpleIcons:openrouter | original | 699B | `c34ab396f6c4940a` |
| `perplexity` | `vendor-perplexity` | OpenRouter | original | 555B | `9875991687969836` |
| `qwen` | `vendor-qwen` | SimpleIcons:alibabacloud | original | 562B | `cb21fc53f968aa32` |
| `x-ai` | `vendor-x-ai` | SimpleIcons:x | template | 314B | `07099f0e2eea46fe` |
| `xiaomi` | `vendor-xiaomi` | SimpleIcons:xiaomi | original | 918B | `20fb26a3565ed908` |

合计 23.8 KB。
⚠️ 它们是**矢量**的,任何尺寸都清晰 —— 不需要也不该再存一份"高清大图"。
