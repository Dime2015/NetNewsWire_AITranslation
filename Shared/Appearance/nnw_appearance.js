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
	// 这里写我们自己的样式。
	//
	// 已经做的改动(2026-07-21):
	//   · 图注(figcaption)靠右、变淡、字号跟随动态字体
	//   · 顶部作者名变小变淡,订阅源名保持原样 —— 拉开两者的层级
	//   · 横图顶到屏幕边缘 / 竖图留白居中 —— 这条在下面的「图片排版」一节,
	//     因为 CSS 判断不了横竖,需要一小段只读的 JS 配合
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
		/* 我们自己的「次要文字」颜色(图注、作者名都用它)。
		   为什么不直接用上游的 --article-date-color:那个变量定义在默认主题的
		   stylesheet.css 里,换成别的主题就可能不存在,颜色会静默失效。
		   自己定义一份,8 套主题下表现一致。 */
		:root {
			--nnw-secondary-text: rgba(0, 0, 0, 0.45);
		}
		@media (prefers-color-scheme: dark) {
			:root {
				--nnw-secondary-text: rgba(255, 255, 255, 0.45);
			}
		}

		/* [外观] 正文页背景**故意留空(透明)** —— 纸色由 UIKit 画在 WebView 底下。
		   (2026-07-23 改。原来这里写死了 #F3F0EB / #1E1E1E 两个色值。)

		   ⚠️ 这不是"顺手简化",是顶栏能安全做透明的**前提**,别改回来:

		   顶栏一旦透明,露出的就是它背后的 WebView。而网页的深浅色走的是网页自己的
		   「prefers-color-scheme」,不保证和 app 同步 —— 曾经浅色模式下顶栏透出网页的
		   深色底,整条顶栏变成一片黑(见 NOTES-lessons L60,用户截图为证)。

		   现在把纸色的**所有权收归 UIKit**(WebViewController 的 view 背景,
		   用 AppAppearance.paperBackground 这个动态色,系统级自适应、不经过任何回调),
		   网页只负责画文字和图片。于是顶栏透出来的永远是正确的纸色,
		   最坏情况也只是正文文字颜色慢半拍,**顶栏再也不可能变黑**。

		   配套改动在「WebViewController.nnwUseUIKitPaperBackground()」,两处必须同时在:
		   只改这里 → 正文变成 WebView 默认白底;只改那里 → 网页底盖住 UIKit 底,白改。
		   改暖纸色现在**只需改 AppAppearance.Palette 一处**(这里不再有色值)。 */
		html, body {
			background-color: transparent;
		}

		/* 藏掉 Substack 塞在每张图下面的两个按钮。
		   它们是 Substack 自己的「Restack(转发)」和「放大看图」,
		   随 RSS 内容一起发过来,但 Substack 的 JS 不在我们这儿,所以**点了没有任何反应**。
		   其中「Restack」的图标用了 var(--color-fg-primary) —— 这个 CSS 变量只存在于
		   Substack 网站,在我们这里没有,所以描边没颜色,渲染成一个灰色空壳。 */
		.image-link-expand {
			display: none !important;
		}

		/* ---- 抹掉「装着图片的段落」上的左右内边距 -----------------------
		   有些源(例如 3 Quarks Daily 用的 WordPress 首字下沉样式)会给段落写死
		   style="padding-left: 40px"。后果有两个:
		     ① 这段正文比标题、日期往右缩 40px,看着像排歪了
		     ② 里面的图片要顶到屏幕边,得先跨过这 40px —— 顶不到,差一截
		   所以把它抹平。

		   ⚠️ 只对**直接装着图片**的段落生效(p:has(> img))。
		      有些源用「带左内边距的段落」来表示引文,那种段落里没有图片,
		      不受影响,缩进照旧。

		   ⚠️ 这里必须用 !important:源站是写在元素的 style 属性里的,
		      行内样式的优先级高于任何样式表规则,不加 !important 盖不住。 */
		p:has(> img) {
			padding-left: 0 !important;
			padding-right: 0 !important;
		}

		/* ---- 图注:靠右、比正文淡 -------------------------------------
		   只对用 <figure><figcaption> 的源生效(实测约三分之一的图有图注,
		   其余的图本来就没有图注,不受影响)。
		   上游把图注字号写死成 14px,这里改成相对值,让它跟随系统动态字体。 */
		figcaption {
			text-align: right;
			color: var(--nnw-secondary-text);
			font-size: 0.82em;
		}

		/* 图注里常有版权链接(例如 "CC BY")。上游的 .articleBody a:link 会把它
		   染成蓝色,比图注本身还抢眼,所以在这里一起压暗;
		   下划线保留,它仍然看得出是可以点的。 */
		.articleBody figcaption a:link,
		.articleBody figcaption a:visited {
			color: var(--nnw-secondary-text);
		}

		/* ================================================================
		   正文排版:行高、段距、小标题、引用块、代码、列表、分隔线、表格
		   ================================================================
		   这一段全部是**按元素类型**定义的,不针对任何具体订阅源。
		   所以新接一个源不用改代码 —— 这是能不能收敛的关键。 */

		/* ---- 行高与段间距 ---------------------------------------------
		   上游写的是 line-height: 1.6em(**带单位**)。带单位的行高会把
		   算好的像素值原样传给子元素,于是小标题、代码块虽然字号不同,
		   却共用同一个行高,显得挤。改成不带单位,子元素各自按自己的字号重算。 */
		.articleBody {
			line-height: 1.65;
		}

		/* 段间距:只给下边距,不给上边距。
		   这样「小标题 → 正文」的距离由标题自己控制,不会两份边距叠在一起。 */
		.articleBody p {
			margin-top: 0;
			margin-bottom: 1.15em;
		}

		/* ---- 小标题:建立层级 -----------------------------------------
		   上游**没有给正文里的小标题设过字号**,用的是浏览器默认值 ——
		   默认 h1 是 2em,比文章大标题(1.5rem)还大,层级是反的。
		   实测有 28 篇文章的正文里真的用了 h1(例如 Experimental History)。

		   同时选 .articleBody 和 #bodyContainer 两个写法是为了换主题时更稳
		   (个别主题会改容器的 id,见 L12)。文章大标题在这个容器**外面**,
		   所以不会被这里波及。 */
		.articleBody h1, #bodyContainer h1 { font-size: 1.32em; }
		.articleBody h2, #bodyContainer h2 { font-size: 1.20em; }
		.articleBody h3, #bodyContainer h3 { font-size: 1.08em; }
		.articleBody :is(h4, h5, h6) { font-size: 1em; }

		/* 上疏下密 —— 标题离**上面**的段落远、离**下面**自己管的内容近,
		   这样一眼就能看出标题属于下文,而不是浮在两段中间。 */
		.articleBody :is(h1, h2, h3, h4, h5, h6) {
			line-height: 1.3;
			font-weight: 700;
			margin-top: 1.8em;
			margin-bottom: 0.5em;
		}

		/* ⚠️ 空标题必须藏掉。
		   Michael Tsai 的博客(引用类源里篇数最多的一个)会输出 <h4></h4>,
		   里面一个字都没有。上面刚给标题加了 1.8em 的上边距,
		   不藏的话这些空标题会凭空撑出一大片空白。 */
		.articleBody :is(h1, h2, h3, h4, h5, h6):empty {
			display: none;
		}

		/* ---- 引用块 ---------------------------------------------------
		   引用块占了 24% 的文章,而且 Michael Tsai(98/100 篇)、
		   Daring Fireball(39/48 篇)这类源里,**引用就是正文本身**。
		   所以这里只调竖线粗细和间距,**不把引用文字调淡** ——
		   调淡等于把这些源的主体内容变得难读。 */
		.articleBody blockquote {
			border-inline-start-width: 2px;
			padding-inline-start: 16px;
			margin-top: 1.2em;
			margin-bottom: 1.2em;
		}

		/* 引用块里首尾段落的边距去掉,竖线才不会上下多出一截 */
		.articleBody blockquote > p:first-child { margin-top: 0; }
		.articleBody blockquote > p:last-child { margin-bottom: 0; }

		/* ---- 代码块 ---------------------------------------------------
		   上游在 iOS 上只给了 5px 内边距,贴着边框很局促。
		   代码块占 7% 的文章,其中纽约联储那个源每篇末尾都附一段
		   BibTeX 引用格式,长期会一直看到。 */
		.articleBody pre {
			padding: 12px 14px;
			border-radius: 6px;
			font-size: 0.86em;
			line-height: 1.5;
			margin-top: 1.2em;
			margin-bottom: 1.2em;
		}

		/* 行内代码:上游只给了 1px 2px,和周围文字几乎粘在一起 */
		.articleBody code {
			padding: 2px 5px;
			border-radius: 4px;
			font-size: 0.88em;
		}

		/* <pre><code> 是嵌套的,两层都带底色和内边距 —— 里面那层要清掉,
		   否则色块套色块,而且字号会被缩两次。 */
		.articleBody pre code {
			padding: 0;
			background: none;
			font-size: 1em;
		}

		/* ---- 列表 -----------------------------------------------------
		   占 22% 的文章。浏览器默认缩进 40px,在手机上太深,
		   会把本来就窄的正文再挤掉一截。 */
		.articleBody :is(ul, ol) {
			padding-inline-start: 1.5em;
		}
		.articleBody li {
			margin-bottom: 0.4em;
		}

		/* ---- 分隔线 ---------------------------------------------------
		   占 17% 的文章。上游写的是 border: 1.5px solid —— 四条边都有边框,
		   渲染出来是一个约 3px 厚的空心长条,很笨重。改成一条细线。 */
		.articleBody hr {
			border: 0;
			border-top: 1px solid var(--nnw-secondary-text);
			opacity: 0.35;
			margin: 2.2em 0;
		}

		/* ---- 表格 -----------------------------------------------------
		   占 4.7% 的文章。上游已经把表格包进了可横向滚动的容器,
		   这里只是把字号收一点,让更多列能一屏放下。 */
		.articleBody .nnw-overflow table {
			font-size: 0.9em;
		}
		.articleBody .nnw-overflow :is(td, th) {
			padding: 7px 10px;
		}
		.articleBody .nnw-overflow th {
			font-weight: 700;
		}

		/* ---- 「排版用的假表格」:让并排的格子上下堆叠 -------------------
		   Reddit 的正文是一个一行两格的表格:
		       [缩略图] [正文 + submitted by + 链接]
		   在手机宽度下并排,文字被挤成细长一条,图也被压得很小。

		   ⚠️ 注意这不是样式没生效 —— 图和文字并排是因为它们**本来就是
		      两个并排的单元格**,不是同一段里的行内元素。所以「图片独占一行」
		      那条规则对它无效,必须针对表格结构本身来改。

		   选择器故意**不认 Reddit 这个来源**,认的是结构特征:
		   「只有一行」+「某个格子里装着一张被链接包着的图」= 排版用的假表格。
		   真正的数据表格(多行、或带表头)完全不受影响。 */
		.articleBody table:has(tr:only-child):has(td > a > img) :is(td, th) {
			display: block;
			width: auto;
			padding-left: 0;
			padding-right: 0;
		}

		/* 表格里的图片一律老实待在格子里,**不参与「顶到屏幕边缘」**。
		   原因:上游会把表格包进 overflow-x: auto 的容器,
		   图片用负边距顶出去会拖出一条横向滚动条。
		   这条的优先级(0,1,2)高于按图片地址生成的规则(0,1,1),所以能盖住它。 */
		.articleBody table img {
			width: auto;
			max-width: 100%;
			margin-left: auto;
			margin-right: auto;
		}

		/* ---- YouTube 播放器 -------------------------------------------
		   由 nnw_youtube.js 插在正文容器**前面**。

		   左右顶到屏幕边缘,和横图同一个做法。除了好看,这也是**唯一能诚实
		   提升画质的杠杆** —— YouTube 按播放器尺寸和带宽自动选画质,
		   播放器越大默认画质越高。(锁定「最高画质」做不到,画质参数早已废弃。) */
		   ⚠️ 比例**自己用 aspect-ratio 写全,不借用上游的 .iframeWrap**。
		   上游那个类是老式的 padding-top: 56.25% 撑高度,要求 iframe 绝对定位
		   盖在 padding 上;一旦没盖住,那块 padding 就变成标题和播放器之间的
		   一大片空白(2026-07-21 用户实测遇到)。aspect-ratio 直接把盒子做成
		   16:9,没有"空 padding"这个东西,也就不会有那种空白。 */
		#nnwYouTubePlayer {
			display: block;
			position: relative;
			margin: 0 -20px 20px;
			width: calc(100% + 40px);
			max-width: none;
			aspect-ratio: 16 / 9;
			/* 上游给所有 div 设了 height: auto !important,配合 aspect-ratio
			   正好 —— 高度由宽度和比例算出来。 */
			padding: 0;
			background: #000;
		}

		#nnwYouTubePlayer iframe {
			position: absolute;
			top: 0;
			left: 0;
			width: 100% !important;
			height: 100% !important;
			max-width: none;
			margin: 0;
			border: 0;
		}

		/* YouTube 视频简介。white-space: pre-wrap 是关键 ——
		   简介是**纯文本**,靠它把原文的换行和空行还原出来,
		   不需要把 \\n 转成 <br>(那样就得处理 HTML 转义,反而容易出错)。 */
		#nnwYouTubeDescription {
			white-space: pre-wrap;
			margin-top: 4px;
		}

		/* ---- 播客语音条 -----------------------------------------------
		   由 nnw_podcast.js 插在正文容器**前面**(不是里面 —— 插里面会被
		   翻译功能当成正文的一段)。这里只管长相。 */
		#nnwPodcastPlayer {
			margin: 18px 0 24px;
			padding: 14px;
			border-radius: 12px;
			background: var(--code-background-color, rgba(127, 127, 127, 0.12));
			text-align: center;		/* 里面每一行都居中(2026-07-23 用户要求) */
		}

		/* 语音条**独占一行、拉满宽度**。
		   ⚠️ 这三行缺一不可:audio 默认是 inline 元素,不设 block 的话
		   后面的「在播客中打开」会贴着它排在同一行,文字还会拦腰折断(用户截图为证)。 */
		#nnwPodcastPlayer audio {
			display: block;
			width: 100%;
			margin: 0 auto;
		}

		#nnwPodcastPlayer .nnwPodcastMeta {
			margin-top: 8px;
			font-size: 0.82em;
			color: var(--nnw-secondary-text);
		}

		/* 「在『播客』中打开这一期」也**自成一行** ——
		   原来是 inline-block,会去挤语音条那一行。 */
		#nnwPodcastPlayer .nnwPodcastAppleLink {
			display: block;
			margin-top: 10px;
			font-size: 0.9em;
		}

		/* ---- 顶部:拉开「订阅源名」和「作者名」的层级 -------------------
		   模板里作者名是裸文本,跟在 <br> 后面,**没有自己的容器**,没法单独选中。
		   所以做法是:把顶部整块调小调淡,再把订阅源名单独放大回原来的大小。
		   净效果 = 只有作者名变小变淡。 */
		.headerContainer .header {
			font-size: 0.8em;
			color: var(--nnw-secondary-text);
		}

		/* 订阅源名放大回去(0.8 × 1.25 = 1.0,即原始大小);颜色不动,仍是上游的蓝色 */
		.headerContainer .feedlink {
			font-size: 1.25em;
		}

		/* 有些源会把作者名做成链接,那样它会是蓝色的 —— 比订阅源名还显眼,
		   正好和我们想要的层级相反。这里把作者链接也压成灰色。
		   :not(.feedlink) 保证订阅源名那个链接不受影响。 */
		.headerContainer .header a:not(.feedlink):link,
		.headerContainer .header a:not(.feedlink):visited {
			color: var(--nnw-secondary-text);
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
		installImageLayout();
	}

	// ==================================================================
	// 图片排版:横图顶到屏幕边缘,竖图留白居中
	// ==================================================================
	//
	// **为什么这里非得有 JS**:CSS 没有任何办法判断一张图是横的还是竖的
	// (没有「按宽高比选择元素」的选择器)。这是 CSS 语言本身的限制。
	//
	// ⚠️ 关键设计:**一个字都不写进文章的 DOM。**
	//    不加节点、不删节点、不改 class、不改属性 —— 只是「看一眼尺寸」,
	//    然后把结论写成 CSS 规则(`img[src="…"] { … }`)追加到 <head> 里
	//    我们自己的 <style> 上。
	//
	//    这样做有三个好处:
	//    ① `#bodyContainer` / `.articleTitle` 完全没被碰过 → 翻译功能零风险(见 L12)
	//    ② 翻译时整段 innerHTML 被替换、图片元素被重建,但**图片地址不变**,
	//       所以这些规则照样生效,不需要重新扫一遍
	//    ③ 这段 JS 万一没跑起来,页面就是上游原本的样子,不会坏

	const IMAGE_RULES_ID = "nnwAppearanceImageRules";

	// 比这更窄的图当成「正文里的行内小图标」(徽章、表情、logo),完全不管,
	// 免得把一行里的小图标顶成独占一行。
	const MIN_WIDTH_TO_TOUCH = 100;

	// 允许顶边的门槛:原图宽度至少要有屏幕宽度的这个比例。
	//
	// 为什么用比例而不是固定像素:判断标准是**会不会被放大到糊**。
	// 屏幕宽 393 时门槛约 334 —— 一张 360px 宽的图放大 1.09 倍,肉眼看不出;
	// 而 Substack 那种真实只有 168px 的图要放大 2.3 倍,必糊,所以不让它顶边。
	const FULL_BLEED_MIN_RATIO = 0.85;

	// 竖图:最宽占正文宽度的 85%,最高不超过屏幕高的 62%,水平居中。
	// 两个上限一起作用,保证竖图两边有留白,也不会一张图霸占整个屏幕。
	const TALL_MAX_WIDTH = "85%";
	const TALL_MAX_HEIGHT = "62vh";

	// 已经处理过的图片地址,避免同一张图重复写规则
	const styledSources = new Set();

	let cachedSidePadding = null;

	/// 正文左右的留白是多少像素 —— 横图要向外扩出这么多才能正好顶到屏幕边。
	/// 不写死 20:每套主题的 stylesheet.css 都可能给 body 设不同的 padding,
	/// 直接问浏览器要实际值,换主题也不会错位。
	function bodySidePadding() {
		if (cachedSidePadding === null) {
			const measured = parseFloat(getComputedStyle(document.body).paddingLeft);
			cachedSidePadding = (isFinite(measured) && measured > 0) ? measured : 20;
		}
		return cachedSidePadding;
	}

	/// 把一段字符串安全地放进 CSS 的引号里(图片地址里可能有引号或反斜杠)
	function cssString(value) {
		return '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
	}

	function appendImageRule(rule) {
		let sheet = document.getElementById(IMAGE_RULES_ID);
		if (!sheet) {
			const head = document.head || document.documentElement;
			if (!head) {
				return;
			}
			sheet = document.createElement("style");
			sheet.id = IMAGE_RULES_ID;
			head.appendChild(sheet);
		}
		sheet.textContent += rule + "\n";
	}

	/// 看一张图的尺寸,给它写一条规则。
	/// 尺寸来源有两个:
	///   ① 图片已经下载完 → naturalWidth/naturalHeight(最准)
	///   ② 还没下完 → 退回读 HTML 里的 width/height 属性(实测 78% 的图都有,
	///      好处是**不用等图下载完**就能定好版,不会出现「先满屏再跳一下」)
	/// 两个都拿不到就先放着,等 load 事件回来再看。
	function styleImage(img) {
		const src = img.getAttribute("src");
		if (!src || styledSources.has(src)) {
			return;
		}
		// 顶部那个订阅源头像不参与(它本来就是 48×48,下面的宽度门槛也会挡住,双保险)
		if (img.id === "nnwImageIcon") {
			return;
		}

		const width = img.naturalWidth || parseInt(img.getAttribute("width"), 10);
		const height = img.naturalHeight || parseInt(img.getAttribute("height"), 10);
		if (!width || !height) {
			return; // 还不知道尺寸,等 load 事件
		}

		styledSources.add(src);

		if (width < MIN_WIDTH_TO_TOUCH) {
			return; // 行内小图标,保持上游原样
		}

		const selector = "img[src=" + cssString(src) + "]";

		if (height > width) {
			// 竖图:限宽 + 限高,左右自动居中,两边自然留出空白
			appendImageRule(selector + " { display: block; width: auto; max-width: " + TALL_MAX_WIDTH + "; max-height: " + TALL_MAX_HEIGHT + "; margin-left: auto; margin-right: auto; }");
			return;
		}

		// 到这里都是横图(含正方形)。够宽的才顶边,不够宽的只居中,绝不放大。
		if (width >= window.innerWidth * FULL_BLEED_MIN_RATIO) {
			// 向左右各外扩一个 body padding,正好顶到屏幕两边。
			// max-width: none 是必须的 —— 上游给 img 设了 max-width: 100%,
			// 不解开的话下面这个 width 会被它压回去,一点效果都没有。
			const pad = bodySidePadding();
			appendImageRule(selector + " { display: block; max-width: none; width: calc(100% + " + (pad * 2) + "px); margin-left: -" + pad + "px; margin-right: -" + pad + "px; }");
		} else {
			// 原图太小,放大就糊了 —— 保持原始大小,独占一行、居中
			appendImageRule(selector + " { display: block; margin-left: auto; margin-right: auto; }");
		}
	}

	function installImageLayout() {
		if (window.__nnwImageLayoutInstalled) {
			return;
		}
		window.__nnwImageLayoutInstalled = true;

		// 图片下载完之后再看一次(补上那些 HTML 里没写 width/height 的)。
		// load 事件不冒泡,所以必须用捕获阶段在 document 上监听。
		// 翻译功能替换正文后新生成的 <img> 也会走到这里。
		document.addEventListener("load", function (event) {
			const target = event.target;
			if (target && target.tagName === "IMG") {
				styleImage(target);
			}
		}, true);

		document.querySelectorAll("img").forEach(styleImage);
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
