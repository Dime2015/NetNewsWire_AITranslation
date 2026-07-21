// nnw_youtube.js
//
// [YouTube] 本 fork 新增,上游没有这个文件。
//
// 作用:订阅 YouTube 频道后,文章正文是**空的**(YouTube 官方 RSS 里没有
//      <content>,实测确认)。这个脚本在正文位置放一个官方 embed 播放器,
//      点一下就能在 app 内看。
//
// ## 为什么这个文件不需要 Swift 配合
//
// 播客那边要 Swift 帮忙,是因为音频地址不在页面里(得重新拉 feed)。
// YouTube 不一样:**视频 ID 就在页面自己的链接里** ——
// 模板把文章链接放进了标题和日期的 href(`[[preferred_link]]`),
// 而 YouTube 文章的链接就是 `https://www.youtube.com/watch?v=<视频ID>`。
// 所以直接从页面读就行,Swift 一行都不用改。
//
// ## 插在哪里
//
// 和播客语音条一样,插在 `#bodyContainer` 的**前面**(兄弟节点,不是子节点)。
// 插里面会被 translation.js 当成正文的一段拿去翻译(见 NOTES-lessons L12)。
//
// ## 关于「最高分辨率」
//
// **锁定最高画质做不到。** YouTube 的画质参数(vq= 之类)多年前就废弃了,
// 播放器按带宽自适应。唯一能诚实使用的杠杆是**把播放器放大** ——
// 播放器尺寸是 YouTube 选择默认画质的输入之一,所以这里让它左右顶到屏幕边缘。

(function () {
	"use strict";

	const PLAYER_ID = "nnwYouTubePlayer";
	const DESCRIPTION_ID = "nnwYouTubeDescription";

	/// 排查「错误代码 152」时用过的临时探针,**已完成使命,置 null 关闭**。
	///
	/// 当时的做法:把同一个视频插进一篇非 YouTube 的文章里,除了「文章的身份」
	/// 其它条件完全一样。结果那边能播 → 证明问题出在身份上,而不是视频、
	/// 拦截规则或 UA。修法见 WebViewController 里的 nnwAdjustedBaseURL。
	///
	/// 留着这行(和下面那段说明)是因为这类问题以后还可能出现,
	/// 到时把视频 ID 填回来就能重跑这个对照实验。
	const PROBE_VIDEO_ID = null;

	/// 找正文容器。用候选链而不是只认一个 id ——
	/// 8 套主题里有的把容器叫 body-container(L12 踩过)。
	function findBodyContainer() {
		return document.getElementById("bodyContainer")
			|| document.getElementById("body-container")
			|| document.querySelector(".articleBody")
			|| document.querySelector(".body-container");
	}

	/// 从页面里找出这篇文章的原始链接。
	/// 标题、日期、外链行都指向同一个地址,任取一个能拿到的。
	function findArticleLink() {
		const selectors = [
			".articleTitle a",
			".articleDateline a",
			".articleDatelineTitle a",
			".externalLink a"
		];
		for (const selector of selectors) {
			const element = document.querySelector(selector);
			if (element && element.href) {
				return element.href;
			}
		}
		return null;
	}

	/// 从各种 YouTube 网址里抠出视频 ID。
	/// 认这几种:
	///   youtube.com/watch?v=<id>     最常见,RSS 给的就是这种
	///   youtu.be/<id>                分享短链
	///   youtube.com/shorts/<id>      短视频
	///   youtube.com/embed/<id>       已经是 embed 的
	function videoIDFromURL(urlString) {

		let url;
		try {
			url = new URL(urlString);
		} catch (e) {
			return null;
		}

		const host = url.hostname.replace(/^www\./, "").toLowerCase();
		const isYouTube = host === "youtube.com"
			|| host === "m.youtube.com"
			|| host === "youtube-nocookie.com"
			|| host === "youtu.be";
		if (!isYouTube) {
			return null;
		}

		let candidate = null;

		if (host === "youtu.be") {
			candidate = url.pathname.split("/")[1];
		} else if (url.pathname === "/watch") {
			candidate = url.searchParams.get("v");
		} else {
			const match = url.pathname.match(/^\/(?:shorts|embed|v)\/([^/?#]+)/);
			if (match) {
				candidate = match[1];
			}
		}

		// YouTube 的视频 ID 是 11 位的字母数字加 - 和 _。
		// 卡死格式是为了不把别的路径段(比如 /watch 后面的杂七杂八)当成 ID。
		if (candidate && /^[A-Za-z0-9_-]{11}$/.test(candidate)) {
			return candidate;
		}
		return null;
	}

	function installPlayer() {

		if (document.getElementById(PLAYER_ID)) {
			return; // 已经装过
		}

		const link = findArticleLink();
		if (!link) {
			return;
		}
		const videoID = videoIDFromURL(link);

		const container = findBodyContainer();
		if (!container || !container.parentNode) {
			return;
		}

		if (videoID) {
			insertPlayer(container, videoID);
			return;
		}

		// ================================================================
		// ⚠️ 临时探针 —— 定位完就删,不要留在正式版里
		// ================================================================
		// 排查「错误代码 152:此视频不能观看」。
		//
		// 已排除:作者禁止嵌入(oEmbed 测 8 个视频全部允许)、UA、Referer、
		//         拦截规则(42 条里没有 googlevideo/ytimg/youtube)。
		//
		// 剩两个假设:
		//   A. 拦截规则第 2 条挡了 doubleclick.net(播放器初始化会请求它)
		//   B. 页面身份被伪装成 youtube.com —— 上游用
		//      loadHTMLString(html, baseURL:) 渲染文章,而 YouTube 文章的
		//      baseURL 恰好就是 https://www.youtube.com/watch?v=...
		//
		// 这个探针**把同一个视频**放进一篇非 YouTube 的文章里。
		// 除了「所在文章的身份」,其它条件完全一样,所以:
		//   能播  → 是 B(身份伪装)
		//   不能播 → 是 A 或别的
		// 两个假设给出不同预测,这才算一个有效的对照(见 NOTES-lessons L27)。
		if (PROBE_VIDEO_ID) {
			insertPlayer(container, PROBE_VIDEO_ID);
		}
	}

	function insertPlayer(container, videoID) {

		const wrapper = document.createElement("div");
		wrapper.id = PLAYER_ID;
		// 2026-07-21:这里原本借用上游的 .iframeWrap 类(它用老式的
		// padding-top: 56.25% 撑出 16:9)。**已去掉**,原因:
		// 那套办法要求 iframe 绝对定位盖在 padding 上,一旦没盖住,
		// 那块 padding 就变成标题和播放器之间的一大片空白(用户实测遇到)。
		// 现在改成在 nnw_appearance.js 里用 aspect-ratio 自己写全,
		// 不依赖上游的类,也少一层耦合。

		const iframe = document.createElement("iframe");
		// 2026-07-21 从 youtube-nocookie.com 换回主域名。
		// 原因:出现「此视频不能观看 错误代码 152」。已经排除了「作者禁止嵌入」
		// (oEmbed 测 8 个视频全部允许)和 UA、Referer、拦截规则三项,
		// 而 nocookie 域在 WKWebView 里比主域名更容易出问题,所以先换回来。
		// playsinline=1:iOS 上必须有,否则会尝试跳原生全屏播放。
		// rel=0:播完不推荐别人家的视频。
		iframe.src = "https://www.youtube.com/embed/" + videoID + "?playsinline=1&rel=0";
		iframe.setAttribute("frameborder", "0");
		iframe.setAttribute("allowfullscreen", "");
		iframe.setAttribute("allow",
			"accelerometer; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen");
		// 不加 autoplay:app 本身也设了「媒体必须用户点了才播」,
		// 这和用户要的「点击播放」正好一致。
		iframe.setAttribute("title", "YouTube 视频播放器");

		wrapper.appendChild(iframe);
		container.parentNode.insertBefore(wrapper, container);
	}

	/// Swift 把视频简介取回来之后调这个,把简介填进正文。
	///
	/// 简介为什么要 Swift 帮忙:YouTube 的 RSS 里**有**简介
	/// (`<media:group><media:description>`),但上游的 Atom 解析器明确忽略所有
	/// 带前缀的元素,所以它压根没被解析过,页面里也就没有。
	///
	/// ⚠️ **用 textContent 填,不用 innerHTML。**
	/// 简介是**纯文本**,里面常有 < > & 和各种符号。当成 HTML 塞进去的话,
	/// 轻则显示错乱,重则被当成标签执行 —— 而且这些文字来自我们无法控制的第三方。
	/// 用 textContent 由浏览器负责转义,既安全又不会丢字符。
	/// 换行靠 CSS 的 white-space: pre-wrap 还原,不用把 \n 转成 <br>。
	window.nnwYouTube = {

		setDescription: function (text) {

			if (!text || document.getElementById(DESCRIPTION_ID)) {
				return false;
			}
			const container = findBodyContainer();
			if (!container) {
				return false;
			}

			const box = document.createElement("div");
			box.id = DESCRIPTION_ID;
			box.textContent = text;

			// 简介属于正文内容,所以放**在正文容器里面** ——
			// 这样翻译功能会把它一起翻译掉,正是我们想要的。
			// (播放器则相反,必须放在外面,它不能被翻译。)
			container.appendChild(box);
			return true;
		}
	};

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", installPlayer);
	} else {
		installPlayer();
	}
})();
