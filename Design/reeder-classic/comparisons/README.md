# Reeder / Babel 叠图比较

- 参考图：`../references/video-selected/dark-home.png`
- 模拟器截图：`/tmp/babel-home-plain.png`
- `home-dark-overlay.png`：参考图与 Babel 截图 50% 混合
- `home-dark-diff.png`：差异增强图

两张图均保持 1206×2622 画布，仅用于开发校准，不代表相似度结论。后续每个页面按同一设备、同一显示缩放和同一状态生成对应叠图。

## 生成方式

使用模拟器截图替换第二个参数即可：

```bash
python3 Design/reeder-classic/comparisons/make_overlay.py \
  Design/reeder-classic/references/video-selected/dark-reader-second.png \
  /tmp/babel-reader-dark-current.png \
  Design/reeder-classic/comparisons/reader-dark-current-overlay.png
```

脚本会自动把模拟器截图缩放到参考图画布，并同时生成 `*-diff.png` 差异增强图。参考图和模拟器截图必须对应同一页面状态；文章文本不同的画面只能用于检查控件几何位置，不能据此判断内容区域的像素一致性。
