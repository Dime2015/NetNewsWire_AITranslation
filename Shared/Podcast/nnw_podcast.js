// nnw_podcast.js
//
// [播客] 本 fork 新增,上游没有这个文件。
//
// 作用:在播客单集的正文上方插一个语音条,可以直接试听;
//      再给一个「在『播客』中打开」的链接。
//
// ⚠️ **插在哪里是这个文件最要紧的一件事。**
//
// 播放器插在 `#bodyContainer` 的**前面**(是它的兄弟节点,不是子节点)。
// 原因:翻译功能会把 `#bodyContainer` 的**子元素**切成若干组、逐组替换
// (translation.js 的 splitBody)。播放器要是插在里面,就会被当成正文的一段
// 拿去翻译 —— 轻则白花钱,重则整个播放器被译文覆盖掉。
//
// 插在外面之后:`#bodyContainer` 和 `.articleTitle` 都没被碰过,
// 翻译功能完全不受影响(见 NOTES-lessons L12)。

(function () {
	"use strict";

	const PLAYER_ID = "nnwPodcastPlayer";

	/// 找正文容器。用候选链而不是只认一个 id ——
	/// 8 套主题里有的把容器叫 body-container(L12 踩过)。
	function findBodyContainer() {
		return document.getElementById("bodyContainer")
			|| document.getElementById("body-container")
			|| document.querySelector(".articleBody")
			|| document.querySelector(".body-container");
	}

	/// 把秒数变成 1:02:03 这样
	function formatDuration(seconds) {
		if (!seconds || seconds <= 0) {
			return "";
		}
		const total = Math.round(seconds);
		const h = Math.floor(total / 3600);
		const m = Math.floor((total % 3600) / 60);
		const s = total % 60;
		const pad = (n) => String(n).padStart(2, "0");
		return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
	}

	window.nnwPodcast = {

		/// 装一个播放器。重复调用只会装一次。
		/// audioURL 必填;durationSeconds 可以是 0(feed 里没写时长);
		/// 返回 true 表示装上了。
		installPlayer: function (audioURL, durationSeconds) {

			if (!audioURL) {
				return false;
			}
			if (document.getElementById(PLAYER_ID)) {
				return true; // 已经装过
			}

			const container = findBodyContainer();
			if (!container || !container.parentNode) {
				return false;
			}

			const wrapper = document.createElement("div");
			wrapper.id = PLAYER_ID;

			const audio = document.createElement("audio");
			audio.controls = true;
			// preload="none":**不要**一打开文章就开始下载音频。
			// 播客动辄几十上百 MB,用户多半只是路过看看简介。
			audio.preload = "none";
			audio.src = audioURL;
			wrapper.appendChild(audio);

			const duration = formatDuration(durationSeconds);
			if (duration) {
				const meta = document.createElement("div");
				meta.className = "nnwPodcastMeta";
				meta.textContent = "时长 " + duration;
				wrapper.appendChild(meta);
			}

			// **插在正文容器前面**,不是里面 —— 原因见文件顶部
			container.parentNode.insertBefore(wrapper, container);
			return true;
		},

		/// 补一个「在『播客』中打开」的链接。
		/// 单独一个方法,因为这个链接要联网去苹果目录查,比音频慢 ——
		/// 先让语音条出来能听,链接查到了再补上。
		addAppleLink: function (linkURL, isExactEpisode) {

			if (!linkURL) {
				return false;
			}
			const wrapper = document.getElementById(PLAYER_ID);
			if (!wrapper || wrapper.querySelector(".nnwPodcastAppleLink")) {
				return false;
			}

			const link = document.createElement("a");
			link.className = "nnwPodcastAppleLink";
			link.href = linkURL;
			link.textContent = isExactEpisode
				? "在「播客」中打开这一期"
				: "在「播客」中打开这个节目";
			wrapper.appendChild(link);
			return true;
		},

		/// 换文章时清掉旧的播放器。
		/// WebViewController 是复用的,不清会把上一篇的音频留在这一篇上。
		removePlayer: function () {
			const wrapper = document.getElementById(PLAYER_ID);
			if (wrapper && wrapper.parentNode) {
				const audio = wrapper.querySelector("audio");
				if (audio) {
					audio.pause();
				}
				wrapper.parentNode.removeChild(wrapper);
			}
			return true;
		}
	};
})();
