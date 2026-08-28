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

	/// 把纯文本转义成可以安全塞进 innerHTML 的字符串(占位色条要用原文,里面可能有 < & ")
	function escapeHTMLText(text) {
		return String(text)
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;");
	}

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

	/// 把"直接挂在容器上的裸文本"包进 `<span>`,让它们成为可翻译的单元。
	///
	/// 分段规则:以 `<br>` 和**块级元素**为界,把它们之间连续的节点(裸文本 + 行内元素)
	/// 收成一段。只有**真的含裸文本**的那些段才包 —— 纯元素的段本来就收得到,
	/// 不包就不会平白多一层 span。
	///
	/// ⚠️ **为什么用行内的 `<span>` 而不是 `<p>`**:`<p>` 是块级的,会改变页面排版
	/// (MacRumors 那种 `<br>` 分行的文章会凭空多出段间距)。`<span>` 是行内元素,
	/// 包上去**视觉上一个像素都不变**。
	///
	/// ⚠️ **幂等**:包完之后,裸文本已经在 span 里,容器的直接子节点里不再有裸文本 ——
	/// 所以再跑一遍什么都不会发生,不会套娃(重新翻译时会再调一次 splitBody)。
	///
	/// ⚠️ **在 `originalHTML` 存档之后才调**(splitBody 开头就存了),
	/// 所以"还原原文"仍然是把存档的 innerHTML 塞回去,这些 span 一起消失。
	function wrapLooseText(container) {

		// 块级元素:它们自己就是完整的单元,不该和旁边的裸文本捆在一起
		var BLOCK = {
			P: 1, DIV: 1, BLOCKQUOTE: 1, PRE: 1, HR: 1, TABLE: 1, FIGURE: 1, FIGCAPTION: 1,
			UL: 1, OL: 1, LI: 1, DL: 1, DT: 1, DD: 1, SECTION: 1, ARTICLE: 1, ASIDE: 1,
			HEADER: 1, FOOTER: 1, NAV: 1, MAIN: 1, FORM: 1, IFRAME: 1, VIDEO: 1, AUDIO: 1,
			H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1
		};

		var nodes = Array.prototype.slice.call(container.childNodes);
		var run = [];
		var runHasBareText = false;

		function flush() {
			if (run.length > 0 && runHasBareText) {
				var span = container.ownerDocument.createElement("span");
				span.setAttribute("data-nnw-run", "1");
				container.insertBefore(span, run[0]);		// 先占位,再把这一段搬进去
				for (var s = 0; s < run.length; s++) {
					span.appendChild(run[s]);
				}
			}
			run = [];
			runHasBareText = false;
		}

		for (var i = 0; i < nodes.length; i++) {
			var node = nodes[i];

			// <br> 和块级元素都是"分界":把前面攒的收掉,它们自己不进任何一段
			if (node.nodeType === 1 && (node.tagName === "BR" || BLOCK[node.tagName])) {
				flush();
				continue;
			}

			if (node.nodeType === 3) {			// 文本节点
				if (normalizeSpace(node.textContent).length > 0) {
					runHasBareText = true;
				} else if (run.length === 0) {
					continue;					// 段首的纯空白不收,免得 span 从空格开始
				}
			}

			run.push(node);
		}
		flush();
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
			// 会"占位置"的元素:它们没有文字,不会被当成翻译单元,
			// 但**在页面上确实站在一个具体位置上**——翻译分组不能把它们两边的文字
			// 揉进同一组(见下面 `boundaryBefore` 的注释,这是 MacRumors 图文错位那个 bug 的病根)。
			var POSITION_SENSITIVE = {
				IMG: 1, PICTURE: 1, VIDEO: 1, IFRAME: 1, SVG: 1, HR: 1, TABLE: 1
			};
			var MEDIA_SELECTOR = "img, picture, video, iframe, svg, table, hr";

			/// 这个元素**在页面上占着一个位置**吗?
			///
			/// 🔴 2026-08-12(用户报デイリーポータルＺ「阅读模式+翻译后图片堆到最后」):
			/// 原来只认**标签名**(IMG/VIDEO/TABLE…)。可阅读模式(Readability)输出的图是
			/// **`<p><img></p>`** —— 标签是 P、文字为空,于是被当成"没内容"直接跳过,
			/// 又因为 `POSITION_SENSITIVE["P"]` 是 undefined 而**没被标成占位置的**。
			/// 结果它前后两段文字被并进同一组,`applyGroup` 把合并后的译文插在
			/// 第一个节点的位置、再把这一组的旧节点全删掉 ——
			/// **图片原地不动,文字全跑到它前面去**,图片就一张张堆到了文章最后。
			/// 这正是 2026-08-11 修 MacRumors 时写下的那个机制,只是当时的判据漏了这一类。
			///
			/// 现在按**结构**判断:自己是媒体,或者里面裹着媒体,都算占位置。
			function occupiesPosition(el) {
				if (POSITION_SENSITIVE[el.tagName]) {
					return true;
				}
				return !!(el.querySelector && el.querySelector(MEDIA_SELECTOR));
			}

			var translatable = [];
			(function collect(container) {
				// ⚠️ **先把"裸文本"包起来,再遍历元素子节点**(2026-08-08 修,用户报的真 bug)。
				//
				// 下面这个循环遍历的是 `container.children` —— **只有元素子节点**。
				// 于是**直接挂在容器上的文本节点从头到尾没被看见**,一个字都不会被翻译。
				//
				// 有些源的正文就是这么写的(实测 MacRumors 的 RSS 原文):
				//     Apple captured 65% of the global premium smartphone market...
				//     <br/><img .../><br/>
				//     That's according to <a href="...">Handset Model Sales Tracker</a>, which...
				// 全篇没有一个 <p>。结果是:<br>/<img> 没文字被跳过,
				// **只有 <a> 因为"有文字"被收走翻译了** —— 用户看到的正是
				// "整篇英文,只有超链接变成了中文"。
				//
				// 修法见 wrapLooseText:把裸文本连成的一段(以 <br> 和块级元素为界)
				// 包进一个 <span>,它就成了正常的翻译单元。
				// 顺带一个真正的改善:句子里的链接从此**跟着句子一起翻**,
				// 不再被单独拆出来译成"Bloomberg 报道 短信摘录Axios报道"那种碎片。
				wrapLooseText(container);

				// 上一个被跳过的兄弟节点是不是"占位置"的(图片等)——
				// 记下来,下一段可译文字要知道自己前面是不是隔着一张图。
				var sawPositionSensitiveSibling = false;

				var children = container.children;
				for (var i = 0; i < children.length; i++) {
					var child = children[i];
					var text = normalizeSpace(child.textContent);
					if (text.length === 0) {
						if (occupiesPosition(child)) {
							sawPositionSensitiveSibling = true;
						}
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
							sawPositionSensitiveSibling = false;
							continue;
						}
					}
					// [翻译] 2026-08-11:`boundaryBefore` —— 这一段前面紧挨着一张图(或其他
					// 占位置的元素)。见下面分组那一步,它会强制在这里断开一个新组。
					// ⚠️ **有文字、但里面裹着图**的单元(典型:带 figcaption 的 `<figure>`)
					// 要**单独成组**。它会被整块交给模型再整块换回来 ——
					// 一旦和邻近段落合并,模型很可能在重写时把 `<img>` 丢掉或挪位置。
					// 单独成组多花一次请求,但图不会没。
					translatable.push({
						node: child, length: text.length, parent: container,
						boundaryBefore: sawPositionSensitiveSibling,
						mediaInside: !!(child.querySelector && child.querySelector(MEDIA_SELECTOR))
					});
					sawPositionSensitiveSibling = false;
				}
			})(element);

			if (translatable.length === 0) {
				return JSON.stringify([]);
			}

			// 第 0 组:先导块。至少含一个单元,累计到 leadChars 为止。
			// 同一组的单元必须共享同一个父节点(替换时按共同父节点插回),父节点一变就收手。
			// ⚠️ 隔着一张图也要收手,理由见下面那段大注释。
			var assignments = [];
			var cursor = 0;
			var leadLength = 0;
			while (cursor < translatable.length) {
				if (cursor > 0 && translatable[cursor].parent !== translatable[0].parent) {
					break;
				}
				if (cursor > 0 && translatable[cursor].boundaryBefore) {
					break;
				}
				// 裹着图的单元要独占一组:它自己之前收手,它之后也收手(见 collect 里的说明)
				if (cursor > 0 && (translatable[cursor].mediaInside || translatable[cursor - 1].mediaInside)) {
					break;
				}
				assignments.push(0);
				leadLength += translatable[cursor].length;
				cursor++;
				if (leadLength >= leadChars || cursor >= 6) {
					break;
				}
			}

			// 其余内容:渐进式分组 —— 第 1 组最小,之后逐组翻倍,到上限封顶。
			// 父节点变化时强制开新组(同一组必须共享父节点,替换才安全)。
			//
			// ⚠️ **隔着一张图也强制开新组**(2026-08-11 修,MacRumors 图文顺序错乱的病根)。
			//
			// `applyGroup` 换某一组译文时,是"在这一组第一个节点的位置插入译文、
			// 再把这一组**所有**旧节点删掉"——如果同一组里的两段文字中间隔着一张图,
			// 图片会原地不动,但两段文字被合并成一整块**插在图片前面**,
			// 原来在图片后面那段文字的旧节点却被删掉了。
			// 结果:文字全跑到图片前面,图片堆在后面 —— 组的成员在文档里必须是连续的,
			// 中间不能站着一个"没被搬走、但会被绕过去"的元素。
			//
			// 这不是 MacRumors 专属的坑:任何图片直接插在两段可译文字之间(不是包在
			// 段落自己里面)的文章都可能中招,只是 MacRumors 那种整篇没有 <p>、
			// 靠 <br> 断句的写法,可译单元又多又碎,最容易撞上这种合并。
			// ⚠️ 2026-08-12:除了按**字符数**封顶,还要按**元素个数**封顶。
			// 起因(用户报 restofworld 那篇"段落不全"):后面的组是逐组翻倍的,
			// 实测能长到 4222 字符 / **11 个块级元素**。让模型一次原样吐回 11 个块,
			// 它经常会合并或漏掉几段 —— 而 applyGroup 是"把这一组旧节点全删掉、
			// 换成模型返回的东西",模型少还几段,那几段就**永久消失**了。
			// 元素少一点,模型守约的概率高很多;代价只是多发几次请求(它们是并发的)。
			var maxElementsPerGroup = 6;
			var currentGroup = 1;
			var currentSize = 0;
			var currentCount = 0;
			var targetSize = Math.max(firstGroupChars, 1);
			for (var k = cursor; k < translatable.length; k++) {
				var parentChanged = k > cursor && translatable[k].parent !== translatable[k - 1].parent;
				var imageBetween = translatable[k].boundaryBefore;
				// 自己裹着图,或前一个裹着图 —— 两种都要断开,让裹图的那个独占一组
				var mediaIsolate = translatable[k].mediaInside ||
					(k > cursor && translatable[k - 1].mediaInside);
				// 当前组已经装够了(或父节点变了、或隔着一张图、或要隔离裹图单元)就开新组,
				// 但不能把组开成空的
				if (currentSize > 0 && (parentChanged || imageBetween || mediaIsolate ||
										currentCount >= maxElementsPerGroup ||
										currentSize + translatable[k].length > targetSize)) {
					currentGroup++;
					currentSize = 0;
					currentCount = 0;
					targetSize = Math.min(targetSize * 2, maxGroupChars);
				}
				assignments.push(currentGroup);
				currentSize += translatable[k].length;
				currentCount++;
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

			// ⚠️ 2026-08-12:这里**曾经**试过"不藏第 0 组、让色条被译文一段段吃掉",
			// 想做出"色条慢慢变成译文"。真机上很难看:剩下的那一节色条挨着流式文字,
			// 随着一节节被藏起来,看上去像**一根小条在追着文字跑**(用户原话)。
			// 用户要的"像原来一样流式输出"指的就是**这个原样**:藏掉第 0 组,
			// 文字在原位逐字浮现。别再往这儿加退让逻辑了。
			for (var i = 0; i < leadNodes.length; i++) {
				leadNodes[i].style.display = "none";
			}

			// 🔴 2026-08-12「吃豆人」(用户要求:同一行里文字一点点把色条吃掉,一行行往下走)。
			//
			// 做法:容器里永远是 [已翻好的译文][剩余部分的占位色条]。
			// 占位用的是**原文的剩余部分**(文字透明,只借它的字形占位),
			// 所以它会自然接在译文后面、自然换行、宽度也真实。
			// 译文每长一点,占位就从头砍掉相应长度 —— 色条被从左往右、一行行吃掉。
			this.streamLeadOriginalText = "";
			for (var t = 0; t < leadNodes.length; t++) {
				this.streamLeadOriginalText += (t > 0 ? " " : "") + normalizeSpace(leadNodes[t].textContent);
			}
			this.streamLeadConsumed = 0;
			temp.innerHTML = '<p><span class="nnw-tr-skel">' +
				escapeHTMLText(this.streamLeadOriginalText) + '</span></p>';

			this.streamLeadContainer = temp;
			return true;
		},

		/// 流式期间的原文(拿来当占位色条)与已被"吃掉"的字数(只增不减,免得色条来回伸缩)
		streamLeadOriginalText: "",
		streamLeadConsumed: 0,

		/// 译文字数 → 原文字数的换算比。中文译文一般比日文/英文原文短,
		/// 所以"吃掉"的原文字数 = 已出译文字数 ÷ 这个比值。
		/// ⚠️ 它**只影响色条退得快慢**,不影响任何文字内容 —— 估偏了最多是吃早吃晚一点。
		streamLeadShrinkRatio: 0.7,

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

			// 吃豆人:把"还没翻到的那段原文"当占位色条,**接在最后一个块的末尾** ——
			// 接在末尾(而不是另起一块)才会跟译文同一行续上,看起来才是"被吃掉"。
			var original = this.streamLeadOriginalText;
			if (original.length > 0) {
				var doneChars = normalizeSpace(this.streamLeadContainer.textContent).length;
				var eat = Math.round(doneChars / this.streamLeadShrinkRatio);
				// 只增不减:流里偶尔回退一两个字符时,色条不该反弹回来
				if (eat > this.streamLeadConsumed) { this.streamLeadConsumed = eat; }
				if (this.streamLeadConsumed > original.length) { this.streamLeadConsumed = original.length; }

				var remaining = original.slice(this.streamLeadConsumed);
				if (remaining.length > 0) {
					var placeholder = '<span class="nnw-tr-skel">' + escapeHTMLText(remaining) + '</span>';
					var last = this.streamLeadContainer.lastElementChild;
					if (last) {
						last.insertAdjacentHTML("beforeend", placeholder);
					} else {
						this.streamLeadContainer.insertAdjacentHTML("beforeend", "<p>" + placeholder + "</p>");
					}
				}
			}
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
			this.streamLeadOriginalText = "";
			this.streamLeadConsumed = 0;
			var leadNodes = element.querySelectorAll('[data-nnw-group="0"]');
			for (var i = 0; i < leadNodes.length; i++) {
				leadNodes[i].style.display = "";
			}
			return true;
		},

		/// 某一组的译文回来了,替换掉这一组。
		///
		/// 每组回来就立刻替换,所以译文是"逐块浮现"的,不用等全文翻完。
		// ============================================================
		// 骨架占位动画(2026-08-12,用户要求)
		// ============================================================
		//
		// 效果:点翻译后,还没翻到的段落**原地变成淡色条**(文字透明但仍占着位置,
		// 所以一个像素的重排都不会发生);某一组译文回来时,新文字从左往右"填"进来。
		//
		// ⚠️ 最大的风险是「骨架清不掉 = 整篇正文变成隐形」。所以设计上有三道保险:
		//   ① 组被 applyGroup 替换时,骨架跟着旧节点一起消失(不需要谁记得清);
		//   ② restore() 直接把 originalHTML 写回去,骨架自然没了;
		//   ③ **看门狗**:超过 skeletonWatchdogMs 没有任何一组落地就自动全清 ——
		//      即使 Swift 那边漏了某条退出路径,正文最多隐形这么久,不会永久消失。

		/// 看门狗时长:每次有组落地都会重新计时。断流/卡住时正文自动现身。
		skeletonWatchdogMs: 45000,
		skeletonWatchdogTimer: null,

		/// 样式只注入一次(幂等)。放在 JS 里而不是 app 的 CSS 包里 ——
		// 这套样式只服务翻译,和阅读主题解耦,改起来不用碰主题文件。
		ensureSkeletonStyle: function () {
			if (document.getElementById("nnwTranslationSkeletonStyle")) {
				return;
			}
			var style = document.createElement("style");
			style.id = "nnwTranslationSkeletonStyle";
			style.textContent = [
				// 色条:文字透明 + 一条顺着文字行走的浅灰渐变。
				// `box-decoration-break: clone` 是关键 —— 它让**每一行**各自成为一根
				// 带圆角的条,而不是整段糊成一个大矩形。
				// 灰度用中性色(127),浅色纸底和深色底下都不突兀。
				// 文字透明。⚠️ 光设 color 不够:主题给链接单独上了颜色/下划线,
				// 那条蓝线会孤零零地留在色条上(用户 2026-08-12 反馈)。
				// 所以把**一切会自己画线上色的东西**在骨架期间全部关掉。
				".nnw-tr-skel, .nnw-tr-skel * {",
				"  color: transparent !important;",
				"  -webkit-text-fill-color: transparent !important;",
				"  text-decoration: none !important;",
				"  -webkit-text-decoration: none !important;",
				"  text-shadow: none !important;",
				"  border-bottom: 0 !important;",
				"  box-shadow: none !important;",
				"}",
				// 子元素自己的背景也要清掉,不然链接的底色会盖在色条上
				".nnw-tr-skel * { background: none !important; }",
				".nnw-tr-skel {",
				// ⚠️ 2026-08-12 加浓过一次:原来是 0.11–0.24,再被呼吸的 opacity 一压,
				// 暖纸底上基本看不见了(用户报"没有骨架色条了")。
				"  background-image: linear-gradient(90deg,",
				"    rgba(127,127,127,0.16) 0%, rgba(127,127,127,0.34) 45%,",
				"    rgba(127,127,127,0.16) 90%);",
				"  background-size: 220% 100%;",
				"  border-radius: 5px;",
				"  -webkit-box-decoration-break: clone;",
				"  box-decoration-break: clone;",
				// 两条动画叠加:流光横扫 + 呼吸。周期故意不同(1.6s / 2.6s)——
				// 同步了两者会一起到峰值,看着很机械。
				// ⚠️ 呼吸**只在 0.86–1 之间浮动**,不能压太狠:色条本来就淡,
				// 呼吸的谷底要是把它压没了,用户看到的就是"根本没有色条"(2026-08-12 踩过)。
				"  animation: nnwSkelShimmer 1.6s linear infinite, nnwSkelBreathe 2.6s ease-in-out infinite;",
				"}",
				"@keyframes nnwSkelShimmer {",
				"  from { background-position: 140% 0; }",
				"  to   { background-position: -60% 0; }",
				"}",
				"@keyframes nnwSkelBreathe {",
				"  0%, 100% { opacity: 0.86; }",
				"  50%      { opacity: 1; }",
				"}",
				// 译文落地:轻轻浮现。
				//
				// ⚠️ 2026-08-12 改掉了初版的 `clip-path` 从左往右擦入(用户报"整页像被刷子扫过")。
				// 单段落时那个擦入确实像"文字填进色条",但**分组是逐组翻倍的,最后一组最大** ——
				// 它一落地就是几乎整页的元素**同时**做同一个方向的擦入,叠起来就成了一把刷子扫全页。
				// 方向性动画只要作用面积一大就会变成"页面级转场",这是它的固有毛病,不是参数问题。
				// 换成没有方向的淡入 + 2px 上浮:面积再大也只是"内容落定",不会扫。
				// "色条慢慢变成译文"那个感觉由**第 0 组的色条退让**承担(见 streamLeadUpdate),
				// 那里是逐段退的,天然不会整页一起动。
				".nnw-tr-fill { animation: nnwFillIn 0.28s ease-out both; }",
				"@keyframes nnwFillIn {",
				"  from { opacity: 0; transform: translateY(2px); }",
				"  to   { opacity: 1; transform: translateY(0); }",
				"}",
				// 用户关了动态效果:去掉流光和擦入,只保留静态色条与淡入
				"@media (prefers-reduced-motion: reduce) {",
				"  .nnw-tr-skel { animation: none; }",
				"  .nnw-tr-fill { animation: nnwFillInPlain 0.2s linear both; }",
				"  @keyframes nnwFillInPlain { from { opacity: 0; } to { opacity: 1; } }",
				"}"
			].join("\n");
			(document.head || document.documentElement).appendChild(style);
		},

		/// 把**还没翻的组**变成色条。在 splitBody 之后、开始翻之前调一次。
		///
		/// 做法:把每个待翻节点的内容包进一个 `<span class="nnw-tr-skel">`。
		/// 用 **inline** 的 span 是有讲究的:块级元素的背景是一个大矩形,
		/// 只有行内元素的背景才会**逐行**绘制 —— 那才是"色条跟着句子走"的样子。
		/// 文字只是变透明,占位一模一样,所以译文替换时不会有任何跳动。
		markPending: function () {
			var element = findBodyElement();
			if (!element) {
				return false;
			}
			this.ensureSkeletonStyle();
			var nodes = element.querySelectorAll("[data-nnw-group]");
			for (var i = 0; i < nodes.length; i++) {
				var node = nodes[i];
				if (node.querySelector(".nnw-tr-skel")) {
					continue;	// 已经包过了(重入保护)
				}
				var skin = document.createElement("span");
				skin.className = "nnw-tr-skel";
				while (node.firstChild) {
					skin.appendChild(node.firstChild);
				}
				node.appendChild(skin);
			}
			this.armSkeletonWatchdog();
			return true;
		},

		/// 拆掉所有色条,把文字原样放回去(**不动内容**,只是脱掉那层皮)。
		clearPending: function () {
			if (this.skeletonWatchdogTimer) {
				clearTimeout(this.skeletonWatchdogTimer);
				this.skeletonWatchdogTimer = null;
			}
			var skins = document.querySelectorAll(".nnw-tr-skel");
			for (var i = 0; i < skins.length; i++) {
				var skin = skins[i];
				var parent = skin.parentNode;
				if (!parent) {
					continue;
				}
				while (skin.firstChild) {
					parent.insertBefore(skin.firstChild, skin);
				}
				parent.removeChild(skin);
			}
			return true;
		},

		/// 看门狗:每有一组落地就重新计时;久久没动静就自己把正文放出来。
		armSkeletonWatchdog: function () {
			var self = this;
			if (this.skeletonWatchdogTimer) {
				clearTimeout(this.skeletonWatchdogTimer);
			}
			this.skeletonWatchdogTimer = setTimeout(function () {
				self.skeletonWatchdogTimer = null;
				self.clearPending();
			}, this.skeletonWatchdogMs);
		},

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
				// [外观] 2026-08-12:译文从左往右"填"进色条留下的位置(见 markPending)
				temp.children[i].classList.add("nnw-tr-fill");
			}

			// 🔴 2026-08-12:**模型少还了块级元素就拒收这一组**(用户报"翻译后段落不全")。
			//
			// 这里的替换是"在第一个旧节点的位置插入译文,再把这一组旧节点**全部删掉**"。
			// 所以模型只要少还几个 `<p>`,那几段原文就**永久消失**了 —— 而且悄无声息:
			// 页面看着是通顺的中文,只是少了两段,用户很难发现,发现了也无从追。
			//
			// 判据用**元素个数**而不是文字长度:英译中本来就会短三四成,长度判不出问题;
			// 而"翻译"不应该改变块级元素的个数,少了就是把段落合并/吞掉了。
			// 拒收之后这一组保持原文,上层会当成一次失败去重试(自检那一步也会再捞一遍),
			// **宁可这一组没翻,也不能让它把原文吃掉**。
			if (temp.children.length < oldNodes.length) {
				return false;
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
			// 有组落地 = 流程还活着,看门狗重新计时(见 armSkeletonWatchdog)
			if (this.skeletonWatchdogTimer) {
				this.armSkeletonWatchdog();
			}
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
		// 🪦 scrollToTop 已删(2026-08-12):点翻译不再动页面,理由见
		// TranslationController 里 item④ 那块墓碑注释。

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
