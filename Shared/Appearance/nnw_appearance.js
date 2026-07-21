// nnw_appearance.js
//
// [界面] 本 fork 新增,上游没有这个文件。
//
// 作用:给文章正文页追加一层「我们自己的样式」。
//
// 为什么这么做:
// 正文页其实是一个网页,长相由 CSS 决定。上游的 CSS 在
// `Shared/Article Rendering/stylesheet.css`(以及 8 套主题各自的 stylesheet.css)里。
// 直接改那些文件最省事,但它们是上游高频改动的文件,以后 `git pull upstream` 会天天冲突。
//
// 所以改成:上游的 CSS 一个字不动,我们在页面加载完成后**再追加一份自己的样式**。
// 后加的样式在优先级相同时会盖过先加的,于是就能覆盖任何我们想改的地方,
// 而上游文件的改动量只有一行(在 WebViewConfiguration.swift 的脚本清单里加一个名字)。
//
// 好处还有一个:这层样式对 8 套主题都生效,不需要给每套主题各改一遍。
//
// **想调整正文页的长相,只改下面 STYLE 里的 CSS,不要去动 stylesheet.css。**

(function () {
	"use strict";

	// 已经插过就不再插(页面脚本可能被重复注入)。
	const ELEMENT_ID = "nnwAppearanceOverrides";

	// ------------------------------------------------------------------
	// 这里写我们自己的样式。目前是空的 —— 界面应与上游完全一致。
	//
	// 可以用的选择器(来自 Shared/Article Rendering/template.html,
	// 各套主题的 template.html 结构基本一致):
	//
	//   .headerContainer      顶部那条:订阅源名 + 作者 + 右侧头像
	//   .feedlink             顶部的订阅源名(蓝色链接)
	//   .avatar img           右侧头像
	//   .articleTitle         文章大标题       ⚠️ 翻译功能依赖这个类名
	//   .articleTitle a       标题文字本身 —— **标题颜色要改这里,不是 .articleTitle h1**
	//                         (上游把颜色写在 `.articleTitle a:link` 上,写在 h1 上会被它盖掉)
	//   .articleDateline      标题下方的日期
	//   .externalLink         日期下方的外链行
	//   #bodyContainer        正文容器         ⚠️ 翻译功能依赖这个 id
	//   #bodyContainer p      正文段落
	//   #bodyContainer a      正文里的链接
	//   #bodyContainer img    正文里的图片
	//   blockquote / pre / code / h1..h6 / ul / ol / table
	//
	// ⚠️ 只改样式(颜色、字号、间距),**不要用 JS 改动页面结构** ——
	//    删掉或改名 `#bodyContainer`、`.articleTitle` 会让翻译功能失灵(见 NOTES-lessons L12)。
	//    (下面的点击拦截只调用 preventDefault,**不动 DOM**,所以不违反这条。)
	// ------------------------------------------------------------------
	const STYLE = `
		/* 藏掉 Substack 塞在每张图下面的两个按钮。
		   它们是 Substack 自己的「Restack(转发)」和「放大看图」,
		   随 RSS 内容一起发过来,但 Substack 的 JS 不在我们这儿,所以**点了没有任何反应**。
		   其中「Restack」的图标用了 var(--color-fg-primary) —— 这个 CSS 变量只存在于
		   Substack 网站,在我们这里没有,所以描边没颜色,渲染成一个灰色空壳。 */
		.image-link-expand {
			display: none !important;
		}
	`;

	function inject() {
		if (document.getElementById(ELEMENT_ID)) {
			return;
		}
		const head = document.head || document.documentElement;
		if (!head) {
			return;
		}
		const style = document.createElement("style");
		style.id = ELEMENT_ID;
		style.textContent = STYLE;
		// 必须插进 <head>:上游的 main.js 会把 <body> 里的 <style> 全部删掉。
		// 追加到最后,才能在优先级相同时盖过上游的样式。
		head.appendChild(style);
		installImageTapFix();
	}

	/// 让「点图片」打开 app 自带的全屏查看器,而不是跳去浏览器。
	///
	/// 背景:很多源(尤其 Substack)把图片包在 `<a href="图片地址">` 里。
	/// 上游的 main_ios.js 本来就监听了图片点击、会打开原生全屏查看器,
	/// 但那个 `<a>` 会同时触发链接跳转,**结果是浏览器赢了**,查看器永远轮不到。
	///
	/// 做法:捕获阶段拦一道,发现点的是图片就 preventDefault() 掐掉跳转。
	/// **不改 DOM**,只是取消默认行为 —— main_ios.js 的 window.onclick 照常收到事件,
	/// 全屏查看器正常打开。
	///
	/// 顺带把交互分工理顺了:**点 = 看图,长按 = 系统自带菜单**
	/// (长按会弹 WebKit 自己的菜单:打开链接 / 拷贝链接 / 共享 / 保存到"照片" / 显示文本。
	///  2026-07-21 用户验收后确认这套够用,所以本 fork **不再自己做长按菜单**。
	///  注意:这个菜单是因为图片被 <a> 包着才有的 —— 我们只取消了跳转,没有拆掉那个链接,
	///  所以系统菜单照常工作。)
	function installImageTapFix() {
		if (window.__nnwImageTapFixInstalled) {
			return;
		}
		window.__nnwImageTapFixInstalled = true;

		document.addEventListener("click", function (event) {
			const target = event.target;
			if (!target || target.tagName !== "IMG") {
				return;
			}
			// nnw-nozoom 是上游用来标记「这张图不要放大」的,尊重它
			if (target.classList.contains("nnw-nozoom")) {
				return;
			}
			// 只在图片确实被链接包着时才拦,其它情况一律不碰
			if (!target.closest("a")) {
				return;
			}
			event.preventDefault();
		}, true); // 捕获阶段:要赶在浏览器处理链接跳转之前
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", inject);
	} else {
		inject();
	}
})();
