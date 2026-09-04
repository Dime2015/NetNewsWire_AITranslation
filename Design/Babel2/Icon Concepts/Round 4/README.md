# Babel 2.0 App Icon Concepts · Round 4

Round 4 是当前唯一候选方向。Round 1、Round 2、Round 3 均保留在原目录中，但不作为本轮最终展示；本轮彻底放弃平面字标、玻璃字母、杂志海颜色浮现等构图。

## 参考图角色

本轮每次生成都使用以下两张参考图，均为 visual-language reference，不是 edit target：

- Image 1：`/var/folders/bk/v080cwfd4sg7s5lx5xy70s540000gn/T/codex-clipboard-de0d0bcd-a90b-4515-81ca-4ca3a91824a4.jpg`。用于参考双色套印、米白纸张、实验排版、纸张颗粒和鱼/植物/器物等图像语言。
- Image 2：`/var/folders/bk/v080cwfd4sg7s5lx5xy70s540000gn/T/codex-clipboard-7a58723e-f047-4612-be4f-efca1f52d2ed.jpg`。用于参考低饱和纸面、双色印刷、网点/套印、版式密度和多样封面视觉。

先前的玻璃字母 PNG 参考在 Round 4 中没有使用。最终图像是根据两张杂志参考从零重建的虚构杂志堆，不直接复制网页截图的网格、编号、标题或具体封面。

## 共通合同

- 正俯拍或近乎正俯拍；真实木桌可见并提供负空间，构图在 iOS mask 后安全。
- 数本不同尺寸、角度、厚度和页边的真实杂志自然排列、重叠，整体形成清晰的大写 `B`。
- `B` 完全由杂志本体的外轮廓、页块、厚度和阴影组成；没有印刷字母 B、独立 B 对象、玻璃、发光或额外材质。
- 封面重建两张参考中的米白纸、低饱和双色套印、网点颗粒、鱼/植物/器物/抽象剪影和实验排版；不得出现真实品牌或可读长文。
- 不烘焙圆角遮罩，不做设备 mockup，不使用生成水印；输出完整不透明 1024 × 1024 方图。

## A · 暖浅橡木 / 较松散自然排列

文件：`babel2-icon-round4-a-light-oak.png`

浅橡木桌面，杂志数量相对较少、排列较松，但 B 轮廓最直接；保留自然角度、堆叠和页边，不做机械网格。

最终 prompt 摘要：

```text
Use case: logo-brand; Asset type: iOS app icon concept, full square 1024×1024 artwork. Use the two supplied magazine images only as visual-language references for pale cream paper, restrained two-color screenprint, halftone grain, experimental layouts, fish/plants/pottery/tools/architecture and abstract shapes; rebuild from scratch with no copied cover, title, number, logo or readable wording. On a real warm light-oak tabletop, arrange several different magazines with slight natural rotations, realistic thickness, visible page edges and believable overlaps so their combined physical silhouettes clearly spell a large uppercase B. The B is made entirely from magazines: no printed B, standalone emblem, glass, glow or extra material. A is the clearest version but remains relaxed and human, not a perfect grid. Near-straight top-down view, full opaque square, wood visible around the magazine-built B, generous safe margin, soft diffuse daylight and subtle contact shadows. Covers use low-saturation cream, pale pink, mist blue, faded sage, butter yellow and light gray with restrained cobalt, coral, terracotta and olive two-color inks. No readable long text, real brands, device mockup, phone frame, baked rounded corners, 3D render, neon or image-generation watermark. B must read at 128px and remain recognizable at 64px.
```

核验：首轮同主题请求被安全过滤器拦截，未生成文件；随后将封面人物联想改为鱼、植物、器物和抽象图形后成功生成。最终版本原图中杂志可辨、B 清晰；128px 与 64px 缩略图均保持 B 轮廓。

## B · 深胡桃木 / 厚叠阴影

文件：`babel2-icon-round4-b-dark-walnut.png`

深胡桃木桌面，杂志层叠更厚，页边和接触阴影更明显；通过两组圆弧和中央连接自然形成 B，整体比 A 更有重量。

最终 prompt 摘要：

```text
Use case: logo-brand; Asset type: iOS app icon concept, full square 1024×1024 artwork. Rebuild fictional magazine covers from the two supplied references using pale cream paper, restrained two-color screenprint, offset registration, halftone grain and varied fish/plant/object/abstract imagery; copy no specific cover, title, number, logo or readable wording. On a deep dark-walnut wooden tabletop, arrange several distinct magazines with varied sizes, slight rotations, natural overlaps and visibly thicker page blocks so the physical magazine silhouettes form a clear uppercase B. Version B uses thicker stacks and stronger soft contact shadows than A, but remains human and irregular, never a mechanical grid or color mosaic. The B is entirely the magazines: no printed B, standalone emblem, glass, glow or extra material. Near-straight top-down, full opaque square, generous wood border, soft directional daylight, realistic paper and wood. Low-saturation cream, dusty pink, mist blue, faded sage, butter yellow and gray covers with restrained cobalt, coral, terracotta and olive inks. No readable text, real brands, device mockup, baked rounded corners, 3D, neon or image-generation watermark. B must read at 128px and remain recognizable at 64px.
```

核验：原图显示深胡桃木、较厚杂志堆叠、可见页边和明显但柔和的阴影；没有独立 B 或玻璃材质。128px 与 64px 缩略图均可识别 B，同时仍像杂志排列。

## C · 中性白蜡木 / 编辑化排列

文件：`babel2-icon-round4-c-white-ash.png`

中性白蜡木桌面，构图最编辑化，杂志角度和间距经过平衡但仍有轻微随机性；靠纸张边缘、双色封面和物理轮廓共同形成 B。

最终 prompt 摘要：

```text
Use case: logo-brand; Asset type: iOS app icon concept, full square 1024×1024 artwork. Use the two supplied magazine images only for visual language: pale cream paper, restrained two-color screenprint, offset registration, halftone grain, experimental editorial layouts and varied fish/plant/object/abstract silhouettes. Rebuild all covers from scratch. On a real neutral white-ash wooden tabletop, arrange several distinct magazines with slight random angles, realistic thickness, visible page edges and natural overlaps so the overall physical group clearly forms a large uppercase B. C is the most editorial and art-directed: balanced but human, with small offsets and uneven stacks; the B is entirely made from magazine bodies, silhouettes, page blocks and shadows, never printed or added as an object. Near-straight top-down, full opaque square, pale ash wood visible around the B, generous safe margin, soft even daylight and gentle contact shadows. Low-saturation cream, warm white, dusty pink, mist blue, faded sage, butter yellow and gray papers with restrained cobalt, coral, terracotta and olive two-color inks. No readable text, real brands, glass, plastic, glow, device mockup, perfect grid, baked rounded corners, 3D, neon or image-generation watermark. B must read at 128px and remain recognizable at 64px.
```

核验：原图中性白蜡木和纸张边缘清楚，杂志仍是主体；B 由自然排列形成，没有印刷字母或额外材质。128px 与 64px 缩略图均能识别 B。

## 工具、输出与边界

- 使用内置 `image_gen`，三版分别独立调用；每次都传入上述两张 JPG 参考图。
- 生成器原始输出随后以无裁切方式缩放为最终 `1024 × 1024` PNG；三个文件均为不透明 RGB。
- 已逐张查看原图，并分别生成 128px、64px 缩略图检查：B 的识别、小尺寸下仍为杂志而非平面字模、木桌负空间、无设备框和无生成水印。
- Round 4 未接入 Asset Catalog，未修改 AppIcon，未删除 Round 1–3，也未提交 Git。
