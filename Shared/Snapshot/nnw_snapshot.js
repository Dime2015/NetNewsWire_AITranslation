//
//  nnw_snapshot.js
//  NetNewsWire — AI 翻译 fork
//
//  [长图] 生成文章长图前的网页侧准备工作(T22,2026-07-24)。本 fork 新增,上游没有。
//
//  ## 它解决两个问题
//
//  1. **标题不在网页里**:阅读栏把网页的标题/表头/日期用 CSS 藏了、改由 UIKit 画 ——
//     直接截网页,长图会没有标题。→ 截图期间给 <html> 加 `nnw-snapshotting` 标记类,
//     用更高优先级的规则把它们放出来;截完摘掉标记,页面回到原样。
//     (标题元素里装的是**当前显示的内容** —— 翻译过就是译文,天然所见即所得。)
//  2. **懒加载的图片**:没滚到过的图片可能还没加载,截出来是空白。
//     → prepare() 强制全部图片立刻加载;Swift 侧轮询 pendingImageCount() 等它们到齐。
//
//  和 translation.js 一样按需注入、幂等,不在 articleScripts 常驻清单里。
//

(function () {
	"use strict";

	if (window.nnwSnapshot) {
		return true;
	}

	// 截图模式的样式:把被阅读栏藏掉的表头/标题/日期放出来。
	// 选择器比隐藏规则(.nnw-reading-bar .articleTitle)多一个类,优先级必胜,不用 !important。
	var style = document.createElement("style");
	style.id = "nnwSnapshotStyle";
	style.textContent =
		".nnw-reading-bar.nnw-snapshotting .articleTitle," +
		".nnw-reading-bar.nnw-snapshotting .headerContainer," +
		".nnw-reading-bar.nnw-snapshotting .articleDateline," +
		".nnw-reading-bar.nnw-snapshotting .articleDatelineTitle { display: block; }";
	(document.head || document.documentElement).appendChild(style);

	window.nnwSnapshot = {

		/// 进入截图模式:露出标题区 + 强制加载全部图片。
		prepare: function () {
			document.documentElement.classList.add("nnw-snapshotting");

			var imgs = document.querySelectorAll("img");
			for (var i = 0; i < imgs.length; i++) {
				var img = imgs[i];
				// 浏览器的原生懒加载:改成"立刻加载"
				if (img.loading === "lazy") {
					img.loading = "eager";
				}
				// 常见的 JS 懒加载约定:真地址存在 data-src 里
				if (!img.getAttribute("src") && img.getAttribute("data-src")) {
					img.setAttribute("src", img.getAttribute("data-src"));
				}
			}
			return true;
		},

		/// 还有几张图没加载完(0 = 可以截了)。Swift 侧带超时轮询,不会被一张死图吊死。
		pendingImageCount: function () {
			var imgs = document.querySelectorAll("img");
			var pending = 0;
			for (var i = 0; i < imgs.length; i++) {
				// complete 对加载失败的图也是 true,所以坏图不会卡住计数
				if (imgs[i].getAttribute("src") && !imgs[i].complete) {
					pending++;
				}
			}
			return pending;
		},

		/// 退出截图模式:标题区回到被藏状态,页面和截图前一模一样。**幂等**。
		finish: function () {
			document.documentElement.classList.remove("nnw-snapshotting");
			return true;
		}
	};

	return true;
})();
