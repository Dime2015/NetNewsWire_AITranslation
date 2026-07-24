//
//  translation.js
//  NetNewsWire — AI 翻译 fork
//
//  这个文件跑在文章页面的网页里(不是 Swift)。
//  它负责三件事:把正文切成若干组、把译文替换回去、事后检查哪些组没翻好。
//
//  为什么这些活在网页里做,而不是在 Swift 里做:
//  1. 浏览器自带 HTML 解析器,切分和替换不会破坏结构(CLAUDE.md 第 5 节的地基条款)
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
		"#bodyContainer",		// 默认主题
		"#body-container",		// Biblioteca 主题
		".articleBody",			// 按 class 找
		".article-body",
		"article"				// 最后的兜底
	];

	// 标题容器的候选名单,同样要兼容不同主题。
	var TITLE_SELECTORS = [
		".articleTitle",
		".article-title",
		"article h1",
		"h1"
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

	function findTitleElement() {
		for (var i = 0; i < TITLE_SELECTORS.length; i++) {
			var element = document.querySelector(TITLE_SELECTORS[i]);
			if (element) {
				return element;
			}
		}
		return null;
	}

	function normalizeSpace(text) {
		return (text || "").replace(/\s+/g, " ").trim();
	}

	/// 判断一段文字"看起来还是英文"(= 没被翻译)。
	///
	/// 判据:中文字符极少 + 英文字母很多。
	/// 太短的不判断 —— 短句子可能本来就是人名、代码、数字,误判代价高。
	function looksUntranslated(text) {

		var t = normalizeSpace(text);
		if (t.length < 40) {
			return false;
		}

		var latin = 0;
		var cjk = 0;

		for (var i = 0; i < t.length; i++) {
			var code = t.charCodeAt(i);
			if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
				latin++;
			} else if (code >= 0x4e00 && code <= 0x9fff) {
				cjk++;
			}
		}

		return cjk < t.length * 0.05 && latin > t.length * 0.4;
	}

	/// 判断译文里"混进了英文原文"(模型做了中英对照)。
	///
	/// 做法:从原文中段取一段 60 字符当探针,看它是否原样出现在当前内容里。
	/// 用中段而不是开头,是因为开头常有专有名词,正常译文里也可能保留。
	function containsOriginalEcho(currentText, originalText) {

		var original = normalizeSpace(originalText);
		if (original.length < 120) {
			return false;
		}

		var start = Math.floor(original.length / 2) - 30;
		var probe = original.substr(start, 60);
		if (probe.length < 60) {
			return false;
		}

		return normalizeSpace(currentText).indexOf(probe) >= 0;
	}

	window.nnwTranslation = {

		// 正文原文备份,用于切回原文。
		originalHTML: null,

		// 标题的原文备份。标题在正文容器**外面**,所以要单独存。
		originalTitleHTML: null,

		// 每一组的原文 HTML 与纯文字。事后检查、重翻时要用。
		groupOriginalHTML: {},
		groupOriginalText: {},

		// 当前显示的是译文还是原文。
		isShowingTranslation: false,

		/// 读取文章标题的 HTML。标题在正文容器外面,splitBody 切不到。
		readTitle: function () {
			var element = findTitleElement();
			if (!element) {
				return null;
			}
			if (this.originalTitleHTML === null) {
				this.originalTitleHTML = element.innerHTML;
			}
			return element.innerHTML;
		},

		/// 把标题换成译文。
		applyTitle: function (translatedHTML) {
			var element = findTitleElement();
			if (!element) {
				return false;
			}
			if (this.originalTitleHTML === null) {
				this.originalTitleHTML = element.innerHTML;
			}
			element.innerHTML = translatedHTML;
			return true;
		},

		/// 标题**当前显示**的纯文字(译文或原文,取决于现在是哪个)。
		/// 给 iOS 的「阅读栏」用:那条栏把网页标题藏掉、由 UIKit 重画,
		/// 翻译后要把译文文字喂给它,否则用户看到的标题永远是原文(2026-07-24)。
		/// 只回纯文字不回 HTML —— UIKit 标签只要文字,Swift 也不该去解析 HTML(地基)。
		titleText: function () {
			var element = findTitleElement();
			return element ? normalizeSpace(element.textContent) : null;
		},

		/// 读取当前正文的完整 HTML。
		/// 翻译前调用 → 拿到原文(用于算缓存键);
		/// 翻译完调用 → 拿到译文(用于存缓存)。
		readBody: function () {
			var element = findBodyElement();
			if (!element) {
				return null;
			}
			if (this.originalHTML === null) {
				this.originalHTML = element.innerHTML;
			}
			return element.innerHTML;
		},

		/// 正文的"指纹":规范化空白后的纯文字。
		///
		/// 为什么不用 innerHTML 当指纹:页面加载后,NetNewsWire 自带的脚本
		/// 会异步地改 HTML(图片查看器装饰、图片懒加载等),点按钮早晚不同,
		/// HTML 就不同 —— 拿它当指纹,缓存会"时中时不中"。
		/// 纯文字不受这些影响,才是稳定的。
		bodyFingerprint: function () {
			var element = findBodyElement();
			if (!element) {
				return null;
			}
			return normalizeSpace(element.textContent);
		},

		/// 把整个正文一次性换成给定内容(缓存命中时用,零请求秒开)。
		apply: function (translatedHTML) {
			var element = findBodyElement();
			if (!element) {
				return false;
			}
			if (this.originalHTML === null) {
				this.originalHTML = element.innerHTML;
			}
			element.innerHTML = translatedHTML;
			this.isShowingTranslation = true;
			return true;
		},

		/// 把正文切成若干组,交给 Swift 拿去翻译。
		///
		/// 切法:
		///   - 第 0 组是"先导块",累计到 leadChars 个字符就收手 ——
		///     它单独先翻,让你几秒内就有东西可读
		///   - 其余内容**渐进式**分组:第 1 组最小(firstGroupChars),
		///     之后逐组翻倍,到 maxGroupChars 封顶。
		///     读者是从前往后读的:读完先导块马上就需要第 1 组,
		///     所以第 1 组必须小、必须快;越靠后的内容读到越晚,
		///     组可以越大,靠"大块"省请求数和重复的提示词开销。
		///
		/// 为什么按组而不是按段:一段一次请求的话,系统提示词要重复十几遍,
		/// 开销比正文本身还大;而且每段互相看不见,术语容易前后不一致。
		///
		/// 返回 JSON 字符串:[{"group":0,"html":"..."}, ...]
		/// 找不到正文容器时返回 null。
		splitBody: function (leadChars, firstGroupChars, maxGroupChars) {

			var element = findBodyElement();
			if (!element) {
				return null;
			}

			if (this.originalHTML === null) {
				this.originalHTML = element.innerHTML;
			}

			this.groupOriginalHTML = {};
			this.groupOriginalText = {};

			// 先挑出需要翻译的单元(没有文字的纯图片、分隔线跳过 —— 省钱也省时间)。
			//
			// 特殊处理:超大的单个元素(典型:引用型博客里一整段几千字符的 <blockquote>)
			// 按顶层切分切不动,谁分到它谁就巨慢。
			// 所以对"文字超过 maxGroupChars 一半、且内容主要在子元素里"的大元素,
			// 下钻一层,把它的子元素当作切分单元。
			var translatable = [];
			(function collect(container) {
				var children = container.children;
				for (var i = 0; i < children.length; i++) {
					var child = children[i];
					var text = normalizeSpace(child.textContent);
					if (text.length === 0) {
						continue;
					}
					// ⚠️ 下钻条件是 >= 1 个子元素,不是 >= 2(2026-07-24 修):
					// 阅读模式(Readability)的输出外面包着**单子元素的壳**
					// (<div id="readability-page-1"><div>正文…</div></div>)。
					// 原来写 >= 2,这层壳钻不进去 → **整篇文章成了一个组** →
					// 流式藏"第 0 组"时全篇消失(用户报的),翻译也没有分组并行可言。
					// >= 1 时递归会一层层剥壳,直到见到真正的段落们。
					if (text.length > maxGroupChars / 2 && child.children.length >= 1) {
						var childrenTextLength = 0;
						for (var j = 0; j < child.children.length; j++) {
							childrenTextLength += normalizeSpace(child.children[j].textContent).length;
						}
						// 子元素承载了 ≥90% 的文字才下钻,否则会丢掉直挂在大元素里的裸文本
						if (childrenTextLength >= text.length * 0.9) {
							collect(child);
							continue;
						}
					}
					translatable.push({ node: child, length: text.length, parent: container });
				}
			})(element);

			if (translatable.length === 0) {
				return JSON.stringify([]);
			}

			// 第 0 组:先导块。至少含一个单元,累计到 leadChars 为止。
			// 同一组的单元必须共享同一个父节点(替换时按共同父节点插回),父节点一变就收手。
			var assignments = [];
			var cursor = 0;
			var leadLength = 0;
			while (cursor < translatable.length) {
				if (cursor > 0 && translatable[cursor].parent !== translatable[0].parent) {
					break;
				}
				assignments.push(0);
				leadLength += translatable[cursor].length;
				cursor++;
				if (leadLength >= leadChars) {
					break;
				}
			}

			// 其余内容:渐进式分组 —— 第 1 组最小,之后逐组翻倍,到上限封顶。
			// 父节点变化时强制开新组(同一组必须共享父节点,替换才安全)。
			var currentGroup = 1;
			var currentSize = 0;
			var targetSize = Math.max(firstGroupChars, 1);
			for (var k = cursor; k < translatable.length; k++) {
				var parentChanged = k > cursor && translatable[k].parent !== translatable[k - 1].parent;
				// 当前组已经装够了(或父节点变了)就开新组,但不能把组开成空的
				if (currentSize > 0 && (parentChanged || currentSize + translatable[k].length > targetSize)) {
					currentGroup++;
					currentSize = 0;
					targetSize = Math.min(targetSize * 2, maxGroupChars);
				}
				assignments.push(currentGroup);
				currentSize += translatable[k].length;
			}

			// 打记号 + 收集每组的 HTML
			var grouped = {};
			for (var m = 0; m < translatable.length; m++) {
				var group = assignments[m];
				var node = translatable[m].node;
				node.setAttribute("data-nnw-group", String(group));
				if (!grouped[group]) {
					grouped[group] = { html: "", text: "" };
				}
				// 注意:这里用 outerHTML(含外层标签)。
				// 一组里有多个元素,必须把标签一起给模型,否则它不知道段落边界。
				grouped[group].html += node.outerHTML;
				grouped[group].text += " " + normalizeSpace(node.textContent);
			}

			var result = [];
			var keys = Object.keys(grouped).sort(function (a, b) { return a - b; });
			for (var n = 0; n < keys.length; n++) {
				var g = keys[n];
				this.groupOriginalHTML[g] = grouped[g].html;
				this.groupOriginalText[g] = normalizeSpace(grouped[g].text);
				result.push({ group: parseInt(g, 10), html: grouped[g].html });
			}

			return JSON.stringify(result);
		},

		// ============================================================
		// 先导块的流式显示(2026-07-24)
		// ============================================================
		//
		// 译文一边生成一边显示:藏掉第 0 组的原文节点,插一个临时容器,
		// 增量译文渐进写进去;流结束后拆掉临时容器,由 applyGroup(0, 完整HTML) 正式替换。
		// 全程不碰第 0 组以外的任何节点;失败/取消时 streamLeadEnd 会把原文原样放回来。

		/// 流式显示的临时容器(null = 当前没有流在显示)
		streamLeadContainer: null,

		/// 开始流式显示:藏掉第 0 组、插入临时容器。找不到第 0 组返回 false(调用方就不流式了)。
		streamLeadBegin: function () {
			var element = findBodyElement();
			if (!element) {
				return false;
			}
			var leadNodes = element.querySelectorAll('[data-nnw-group="0"]');
			if (leadNodes.length === 0) {
				return false;
			}
			// 兜底(2026-07-24):第 0 组大得离谱(> 5000 字符,正常约 750)就不流式 ——
			// 藏掉它等于把大半篇文章变没。切分器修好后不该再发生,但这类"整篇被当成一组"
			// 的伤害太大(用户报过全篇消失),值得留一道闸。返回 false 后调用方
			// 会走非流式赛跑:原文一直显示,译文好了整块替换,只是没有逐字效果。
			var leadTextLength = 0;
			for (var g = 0; g < leadNodes.length; g++) {
				leadTextLength += normalizeSpace(leadNodes[g].textContent).length;
			}
			if (leadTextLength > 5000) {
				return false;
			}
			this.streamLeadEnd();	// 上一条流的残留(理论上没有,双保险)
			var temp = document.createElement("div");
			temp.id = "nnwTranslationStreamLead";
			leadNodes[0].parentNode.insertBefore(temp, leadNodes[0]);
			for (var i = 0; i < leadNodes.length; i++) {
				leadNodes[i].style.display = "none";
			}
			this.streamLeadContainer = temp;
			return true;
		},

		/// 更新流式显示(传**累计**的完整文本,幂等,漏一帧不缺字)。
		streamLeadUpdate: function (accumulatedHTML) {
			if (!this.streamLeadContainer) {
				return false;
			}
			// 把结尾**没写完的标签**先掐掉再显示(比如流刚好断在 "<str" 中间),
			// 否则那半截标签会以文字形式闪现一帧。
			// ⚠️ 这不是在解析文章 HTML(地基禁止的那种):对象是模型正在生成的**译文流**,
			// 只影响临时容器的显示,流结束后整个容器就拆了,一个字都不会留在文章里。
			var display = accumulatedHTML.replace(/<[^>]*$/, "");
			this.streamLeadContainer.innerHTML = display;
			return true;
		},

		/// 结束流式显示:拆临时容器、把第 0 组的原文放回来。
		/// 成功路径:紧接着 applyGroup(0, 完整译文) 正式替换;
		/// 失败/取消路径:原文就地恢复,页面回到没流式过的样子。
		streamLeadEnd: function () {
			if (this.streamLeadContainer) {
				if (this.streamLeadContainer.parentNode) {
					this.streamLeadContainer.parentNode.removeChild(this.streamLeadContainer);
				}
				this.streamLeadContainer = null;
			}
			var element = findBodyElement();
			if (!element) {
				return false;
			}
			var leadNodes = element.querySelectorAll('[data-nnw-group="0"]');
			for (var i = 0; i < leadNodes.length; i++) {
				leadNodes[i].style.display = "";
			}
			return true;
		},

		/// 某一组的译文回来了,替换掉这一组。
		///
		/// 每组回来就立刻替换,所以译文是"逐块浮现"的,不用等全文翻完。
		applyGroup: function (group, translatedHTML) {

			var element = findBodyElement();
			if (!element) {
				return false;
			}

			var oldNodes = element.querySelectorAll('[data-nnw-group="' + group + '"]');
			if (oldNodes.length === 0) {
				return false;
			}

			// 先在临时容器里解析译文,并给新元素补上同样的记号 ——
			// 否则替换之后就找不到这一组了,事后检查和重翻都没法做。
			var temp = document.createElement("div");
			temp.innerHTML = translatedHTML;
			if (temp.children.length === 0) {
				// 模型偶尔会把标签吞掉、只回裸文本。
				// 有文字就用原来第一个节点的标签包回去;连文字都没有才算失败。
				if ((temp.textContent || "").trim().length === 0) {
					return false;
				}
				var wrapper = document.createElement(oldNodes[0].tagName);
				wrapper.innerHTML = translatedHTML;
				temp.innerHTML = "";
				temp.appendChild(wrapper);
			}
			for (var i = 0; i < temp.children.length; i++) {
				temp.children[i].setAttribute("data-nnw-group", String(group));
			}

			var anchor = oldNodes[0];
			var parent = anchor.parentNode;
			while (temp.firstChild) {
				parent.insertBefore(temp.firstChild, anchor);
			}
			for (var j = 0; j < oldNodes.length; j++) {
				oldNodes[j].parentNode.removeChild(oldNodes[j]);
			}

			this.isShowingTranslation = true;
			return true;
		},

		/// 事后检查:哪些组没翻好,需要重翻?
		///
		/// 两种情况会被挑出来:
		///   ① 这一组还是英文 —— 请求失败过,或者模型原样返回了原文
		///   ② 这一组里混进了英文原文 —— 模型做了中英对照
		///
		/// 这两种检查都是纯本地判断,不花一分钱、不发一个请求。
		///
		/// 返回 JSON 字符串:[{"group":3,"html":"<原文>"}, ...]
		findGroupsNeedingRetranslation: function () {

			var element = findBodyElement();
			if (!element) {
				return JSON.stringify([]);
			}

			var result = [];
			var keys = Object.keys(this.groupOriginalHTML);

			for (var i = 0; i < keys.length; i++) {

				var group = keys[i];
				var nodes = element.querySelectorAll('[data-nnw-group="' + group + '"]');
				if (nodes.length === 0) {
					continue;
				}

				var currentText = "";
				for (var j = 0; j < nodes.length; j++) {
					currentText += " " + normalizeSpace(nodes[j].textContent);
				}
				currentText = normalizeSpace(currentText);

				var originalText = this.groupOriginalText[group] || "";

				if (looksUntranslated(currentText) || containsOriginalEcho(currentText, originalText)) {
					result.push({ group: parseInt(group, 10), html: this.groupOriginalHTML[group] });
				}
			}

			return JSON.stringify(result);
		},

		/// 滚到文章顶部。点翻译后调用,方便从头开始读译文。
		/// 只移动滚动位置,不碰任何内容。
		scrollToTop: function () {
			window.scrollTo(0, 0);
			return true;
		},

		/// 换回原文。因为原文一直存在内存里,所以是瞬间完成的。
		restore: function () {

			var element = findBodyElement();
			if (!element || this.originalHTML === null) {
				return false;
			}
			element.innerHTML = this.originalHTML;

			// 标题也要一起换回来
			var titleElement = findTitleElement();
			if (titleElement && this.originalTitleHTML !== null) {
				titleElement.innerHTML = this.originalTitleHTML;
			}

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
