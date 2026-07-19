//
//  translation.js
//  NetNewsWire — AI 翻译 fork
//
//  这个文件跑在文章页面的网页里(不是 Swift)。
//  它只干三件事:找到正文、把正文换成译文、把正文换回原文。
//
//  为什么放在网页里做,而不是在 Swift 里做:
//  1. 浏览器自带 HTML 解析器,替换内容不会破坏结构(CLAUDE.md 第 5 节的要求)
//  2. 原地替换 → 页面不闪、滚动位置不丢
//  3. 原文存在网页里,切回原文是瞬间的,不用重新翻译
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

(function () {

	// 已经装过就不重复装(Swift 侧每次都会注入一遍,靠这行保证幂等)
	if (window.nnwTranslation) {
		return;
	}

	// 正文容器的候选名单,按顺序找,找到第一个就用。
	//
	// 为什么要一串而不是一个:文章主题可以整套替换 template.html,
	// 不同主题给正文容器起的名字不一样。实测:
	//   - 默认主题和其他 6 个内置主题 → id="bodyContainer"
	//   - Biblioteca 主题            → id="body-container"   ← 不一样!
	// 用户还能自己装第三方主题,名字完全不可控,所以最后用 <article> 兜底。
	var BODY_SELECTORS = [
		"#bodyContainer",     // 默认主题
		"#body-container",    // Biblioteca 主题
		".articleBody",       // 按 class 找
		".article-body",
		"article"             // 最后的兜底
	];

	function findBodyElement() {
		for (var i = 0; i < BODY_SELECTORS.length; i++) {
			var element = document.querySelector(BODY_SELECTORS[i]);
			if (element) {
				return element;
			}
		}
		return null;
	}

	window.nnwTranslation = {

		// 原文备份。第一次翻译时存下来,用于切回原文。
		originalHTML: null,

		// 当前显示的是译文还是原文。
		isShowingTranslation: false,

		/// 读取当前正文的 HTML,交给 Swift 拿去翻译。
		/// 找不到正文容器时返回 null。
		readBody: function () {
			var element = findBodyElement();
			if (!element) {
				return null;
			}
			return element.innerHTML;
		},

		/// 把正文换成译文。
		/// 返回 true 表示换成功了。
		apply: function (translatedHTML) {
			var element = findBodyElement();
			if (!element) {
				return false;
			}
			// 只在第一次备份,避免"译文覆盖了原文备份"
			if (this.originalHTML === null) {
				this.originalHTML = element.innerHTML;
			}
			element.innerHTML = translatedHTML;
			this.isShowingTranslation = true;
			return true;
		},

		/// 换回原文。因为原文一直存在内存里,所以是瞬间完成的。
		restore: function () {
			var element = findBodyElement();
			if (!element || this.originalHTML === null) {
				return false;
			}
			element.innerHTML = this.originalHTML;
			this.isShowingTranslation = false;
			return true;
		},

		/// 告诉 Swift 当前状态,让按钮图标能显示正确。
		state: function () {
			return {
				bodyFound: findBodyElement() !== null,
				isShowingTranslation: this.isShowingTranslation
			};
		}
	};
})();

// 注意:这一行必须留着。
// Swift 的 evaluateJavaScript 在脚本没有返回值时行为不稳定,
// 所以让整段脚本以一个明确的值结尾。
true;
