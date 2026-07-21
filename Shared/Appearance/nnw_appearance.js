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
	// ------------------------------------------------------------------
	const STYLE = `
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
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", inject);
	} else {
		inject();
	}
})();
