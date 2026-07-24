//
//  TranslationController.swift
//  NetNewsWire — AI 翻译 fork
//
//  Phase 2:翻译按钮 + 点击后的整套流程编排。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

// ⚠️ 为什么整个文件包在 #if os(iOS) 里:
// Shared/ 目录会同时被 macOS 版和 iOS 版编译。本文件用到 UIKit,
// 而 macOS 上没有 UIKit —— 不加这个开关,macOS 版会编译失败。
// (CLAUDE.md 第 1 节:本次只做 iOS,但不能因此弄坏 macOS 的编译。)
#if os(iOS)

import UIKit
import os

// MARK: - 翻译按钮

/// 按钮当前该显示成什么样。
enum TranslationButtonState {
	/// 正在显示原文,点一下会翻译(联网请求)。
	case original
	/// 正在显示原文,本地已有**完整**译文缓存 —— 点一下瞬间显示,零请求。实心角标点。
	case cachedAvailable
	/// 正在显示原文,本地有**未完成**的译文缓存(上次翻到一半被打断) ——
	/// 点一下接着上次继续翻,已翻过的组不再花钱。空心角标点。
	case partialCacheAvailable
	/// 正在翻译中,转圈,不可点(再点一下 = 取消)。
	case working
	/// 正在显示译文,点一下切回原文。
	case translated
	/// 上次翻译失败了(或部分段落失败)。
	case failed
}

/// 工具栏上那个翻译按钮。
///
/// 做法完全照抄项目里现成的"阅读视图"按钮(`iOS/Article/ArticleExtractorButton.swift`),
/// 因为它已经解决了"按钮里怎么放一个转圈动画"这个问题。
final class TranslationButton: UIButton {

	private let activityIndicator: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .medium)
		indicator.hidesWhenStopped = true
		indicator.translatesAutoresizingMaskIntoConstraints = false
		return indicator
	}()

	var displayState: TranslationButtonState = .original {
		didSet {
			guard displayState != oldValue else { return }
			applyDisplayState()
		}
	}

	/// 图标右上角的小圆点:实心 = 有完整缓存;空心 = 有未完成的缓存。
	private let badgeView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.layer.cornerRadius = 4.5
		view.isHidden = true
		view.isUserInteractionEnabled = false
		return view
	}()

	override init(frame: CGRect) {
		super.init(frame: frame)
		setUpSubviews()
		applyDisplayState()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setUpSubviews()
		applyDisplayState()
	}

	private func setUpSubviews() {
		addSubview(activityIndicator)
		addSubview(badgeView)

		// ⚠️ 这两条尺寸约束是必须的,不是装饰(见 NOTES-lessons L19)。
		// 作为 UIBarButtonItem 的 customView 时,按钮宽度靠"图标撑出的固有尺寸"决定。
		// 而转圈状态会 setImage(nil) —— 图标一没,固有尺寸变 0,
		// iOS 26 的工具栏会把它算成 0 宽并永久塌掉,按钮就此消失。
		translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: 44),
			heightAnchor.constraint(equalToConstant: 44)
		])

		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
			// 角标点悬在气泡图标的右上方
			badgeView.widthAnchor.constraint(equalToConstant: 9),
			badgeView.heightAnchor.constraint(equalToConstant: 9),
			badgeView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 11),
			badgeView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -11)
		])
	}

	private func applyDisplayState() {
		// 角标点只属于两种"有缓存"状态,进入其他任何状态都先藏起来
		badgeView.isHidden = true
		switch displayState {
		case .original:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "character.bubble"), for: .normal)
		case .cachedAvailable:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "character.bubble"), for: .normal)
			// 实心点:有完整缓存,点击秒开
			badgeView.backgroundColor = tintColor
			badgeView.layer.borderWidth = 0
			badgeView.isHidden = false
		case .partialCacheAvailable:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "character.bubble"), for: .normal)
			// 空心点:有未完成的缓存,点击接着上次继续翻
			badgeView.backgroundColor = .clear
			badgeView.layer.borderWidth = 1.5
			badgeView.layer.borderColor = tintColor.cgColor
			badgeView.isHidden = false
		case .working:
			setImage(nil, for: .normal)
			activityIndicator.startAnimating()
			isUserInteractionEnabled = false
		case .translated:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "character.bubble.fill"), for: .normal)
		case .failed:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "exclamationmark.bubble"), for: .normal)
		}
	}

	// 同 TranslationService.swift 里的说明:故意不用 NSLocalizedString,
	// 避免 Xcode 自动往上游共用的 Shared/Localizable.xcstrings 里塞内容。
	override var accessibilityLabel: String? {
		get {
			switch displayState {
			case .original:
				return "翻译成中文"
			case .cachedAvailable:
				return "已有译文缓存,点击立即显示"
			case .partialCacheAvailable:
				return "有未完成的译文,点击接着翻译"
			case .working:
				return "正在翻译"
			case .translated:
				return "显示原文"
			case .failed:
				return "翻译失败,点击重试"
			}
		}
		set { super.accessibilityLabel = newValue }
	}
}

// MARK: - 网页脚本

/// 负责把 `translation.js` 的内容读出来。
///
/// 这个 js 文件放在 `Shared/Translation/` 下,编译时会被自动拷进 app 包
/// (已实测验证,见 NOTES-architecture.md)。
enum TranslationScript {

	static let source: String = {
		guard let url = Bundle.main.url(forResource: "translation", withExtension: "js"),
			  let text = try? String(contentsOf: url, encoding: .utf8) else {
			assertionFailure("translation.js 没有被打进 app 包,翻译功能无法工作")
			return ""
		}
		return text
	}()
}

// MARK: - 流程编排

/// 把"点按钮"到"屏幕上文字变了"这条链路串起来。
///
/// 它不认识具体的界面,只通过一个闭包去拿"当前这篇文章的网页"。
/// 这样将来换界面、加 macOS 版,这个类都不用改。
@MainActor final class TranslationController {

	private let currentWebViewController: @MainActor () -> WebViewController?

	/// 同时最多发几个请求。太多会被服务商限流。
	private static let maxConcurrentRequests = 4

	/// 单组最多重试几次。偶发的限流/超时靠它兜住。
	private static let maxRetries = 1

	// MARK: - 对冲参数(治尾延迟,item①)
	//
	// 同一个请求偶尔会慢好几倍(见 NOTES-todo.md T5:同尺寸两组 22s vs 81.6s ——
	// 因为 OpenRouter 把它路由到了慢服务商)。对冲的办法:先发一份,
	// 若在阈值时间内没成功,就并发再发一份,谁先成功用谁、另一份取消。
	// translate() 用的是支持取消的 URLSession.shared.data(for:),
	// 所以输的那份能真被掐掉,不会白烧 token。

	// 这几个常量要在 nonisolated 的对冲函数里读,所以标成 nonisolated
	// (本类是 @MainActor,静态属性默认带 actor 隔离,不标就够不着)。

	/// 估算「健康耗时」用的保守速率(字符/秒)。实测健康的组约 200 字符/秒。
	private nonisolated static let hedgeCharsPerSecond = 200.0

	/// 超过「健康耗时」这么多倍才对冲 —— 只有真正偏慢的请求会被对冲,
	/// 健康的请求不会平白多花一份钱。
	private nonisolated static let hedgeSlowFactor = 2.0

	/// 正文组对冲阈值的下限(秒)。小组也别太早对冲。
	private nonisolated static let minBodyHedgeDelay: TimeInterval = 6

	/// 先导块在关键路径上(它不回来,后面所有组都不开始),
	/// 给它一个更短的固定阈值,让「开头出现中文」尽快发生。
	private nonisolated static let leadHedgeDelay: TimeInterval = 4

	/// 先导块的赛跑份数(2026-07-24 用户拍板):**开局就并发 4 份、谁先成功用谁**,
	/// 不再"等 4 秒才补一份"。
	/// 为什么值得:所有正文组都在等先导块的译文当示范(方案 C),它慢一秒整篇静止一秒;
	/// 而服务商延迟方差极大(T5 实测同尺寸 22s vs 81.6s),取 4 份里最快的能把尾延迟砍掉大半。
	/// 成本:先导块只有 ~500 字符,多花 3 份小请求 ≈ 零。
	private nonisolated static let leadRaceCopies = 4

	/// 按一组的大小估它的对冲阈值。
	private nonisolated static func bodyHedgeDelay(forChars count: Int) -> TimeInterval {
		max(minBodyHedgeDelay, Double(count) / hedgeCharsPerSecond * hedgeSlowFactor)
	}

	// MARK: - 分组参数
	//
	// 为什么按组翻而不是一段一次:一段一次的话,系统提示词和上下文示范
	// 要随每个请求重复一遍,十几段下来的固定开销比正文本身还大;
	// 而且各段互相看不见,术语容易前后不一致。

	/// 先导块的目标字符数。约合英文 150 词,够读四十多秒 ——
	/// 它单独先翻,让用户几秒内就有东西可读,不用干等全文。
	///
	/// 500 → 750(2026-07-24 用户拍板):流式上线后,先导块变大不再增加"干等"
	/// (第一个字出现的时间只取决于首字延迟,和块大小无关),
	/// 而阅读跑道和方案 C 的示范都变厚。代价是正文各组晚起跑约 2~5 秒,可接受。
	/// ⚠️ 改这个数会挪动所有组的边界 —— **必须同时把 TranslationCache.promptGeneration +1**,
	/// 否则旧的"未完成缓存"按旧边界存的组套到新边界上会丢内容。
	private static let leadChunkCharacters = 750

	/// 第 1 组的目标字符数,之后逐组翻倍(2000、4000……)。
	/// 为什么第 1 组要小:读者读完先导块马上就要读它,它必须最快回来。
	/// 之前所有组一样大(可达数千字符),第 1 组和最后一组一样慢,
	/// 读者读完先导块要干等一大块 —— 这就是"第一块显著更耗时"问题的由来。
	private static let firstGroupCharacters = 1000

	/// 单组字符上限。超长文章会自动多分几组,
	/// 避免一次要模型吐太多内容而被截断(截断会直接丢掉半篇文章)。
	private static let maxGroupCharacters = 4000

	/// 正在进行的翻译任务。换文章时要取消它,
	/// 否则还在飞的译文会替换到**下一篇文章**的页面上。
	private var runningTask: Task<Void, Never>?

	/// 本次翻译运行中已完成的组(组号→译文)与标题。
	/// 中途被打断时,靠它们把进度存成"未完成缓存",下次接着翻。
	private var runGroupTranslations: [Int: String] = [:]
	private var runTitleTranslation: String?

	/// 运行序号。防一个竞态:快速切文章时,上一次运行的"保存进度"
	/// 可能在新一次运行开始后才执行 —— 那时累积器里已经是新文章的内容了,
	/// 存下去会把 B 文章的译文安到 A 文章的缓存里。序号对不上就放弃保存。
	private var runID = 0

	// nonisolated:对冲函数(nonisolated)里也要写日志。
	private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Translation")

	/// 每次翻译时现取,这样在设置里换了模型能立刻生效。
	private func makeService() throws -> TranslationService {
		if let problem = TranslationConfigStore.configurationProblem {
			throw TranslationError.notConfigured(problem)
		}
		guard let config = TranslationConfigStore.config else {
			throw TranslationError.notConfigured("配置文件读取失败。")
		}
		return OpenAICompatibleTranslator(config: config, model: TranslationConfigStore.selectedModel)
	}

	let button: TranslationButton = {
		let button = TranslationButton(type: .system)
		button.frame = CGRect(x: 0, y: 0, width: 44.0, height: 44.0)
		return button
	}()

	private(set) var state: TranslationButtonState = .original {
		didSet { button.displayState = state }
	}

	/// 最近一次失败的原因,用人话写的。翻译失败时弹给用户看。
	private(set) var lastErrorMessage: String?

	/// 用户发起的翻译**失败或未配置**时,把人话说明弹给用户看。由界面层设置。
	/// (自动恢复等后台流程不会用它 —— 那些是静默的。)
	var presentError: (@MainActor (String) -> Void)?

	/// - Parameter currentWebViewController: 怎么拿到"当前正在看的那篇文章的网页"。
	init(currentWebViewController: @escaping @MainActor () -> WebViewController?) {
		self.currentWebViewController = currentWebViewController
	}

	/// 包成工具栏上能放的那种按钮。
	func makeBarButtonItem() -> UIBarButtonItem {
		UIBarButtonItem(customView: button)
	}

	/// 点了按钮。
	func toggle() {

		// 正在翻译时再点一下 = 取消,并回到原文。
		// (以前这里是直接 return,转圈期间点了没反应,用户没法中途停下。)
		if state == .working {
			runningTask?.cancel()
			runningTask = nil
			runningTask = Task {
				if let webViewController = currentWebViewController() {
					_ = try? await webViewController.nnwTranslationRestore()
				}
				state = .original
				recordTranslatedState(false)	// [状态记忆] item③:取消=回到原文
				refreshCacheHint()
			}
			return
		}

		// [翻译] 还没配好翻译服务:直接给一句能照做的提示,不走 spinner→感叹号那一下。
		// (以前这里会静默变成感叹号,用户不知道为什么。)
		if let problem = configurationPromptIfNeeded() {
			presentError?(problem)
			return
		}

		runningTask?.cancel()
		runningTask = Task { await performToggle() }
	}

	/// 翻译服务没配好时,返回一句给用户看的提示;配好了返回 nil。
	/// 没填 API Key 时用固定的引导语(要同时提到填 Key 和选模型);
	/// 其它配置问题(如服务地址非法)沿用 TranslationConfigStore 给的说明。
	private func configurationPromptIfNeeded() -> String? {
		if !TranslationConfigStore.hasAPIKey {
			return "请前往设置中填写 API 并选择翻译模型。\n(设置 → 文章 → 翻译 API Key、翻译模型)"
		}
		return TranslationConfigStore.configurationProblem
	}

	/// [翻译] item②:强制重新翻译整篇(长按翻译键 → 确认后调用)。
	/// 跳过缓存、从原文重新分组翻译,成功后覆盖旧缓存。
	func forceRetranslate() {
		runningTask?.cancel()
		runningTask = Task { await performToggle(force: true) }
	}

	/// [翻译] item②:当前文章本地有没有**完整**译文缓存。
	/// 长按翻译键前用它判断要不要弹「重新翻译全文」。纯本地检查,不发请求。
	/// 语义与按钮上的实心角标一致(只看有没有完整缓存条目,不校验指纹)。
	func hasFullCache() async -> Bool {
		guard let article = currentWebViewController()?.article else {
			return false
		}
		let key = TranslationCache.articleKey(articleID: article.accountID + "|" + article.articleID,
											  model: TranslationConfigStore.selectedModel)
		guard let entry = await TranslationCache.lookup(key: key) else {
			return false
		}
		return entry.bodyHTML != nil
	}

	/// [状态记忆] item③:记住这篇「是否显示译文」。换文章时不要调这个。
	private func recordTranslatedState(_ translated: Bool) {
		guard let article = currentWebViewController()?.article else { return }
		ArticleReadingStateStore.setTranslated(translated, for: article.accountID + "|" + article.articleID)
	}

	/// [状态记忆] item③:页面渲染完成后调用(由 WebViewController.didFinish
	/// → ArticleViewController 转来)。若这篇被记为「上次翻译过」且本地有匹配的
	/// **完整**缓存,就自动秒显译文(零请求、免费)。
	///
	/// 用户的选择:没有可用缓存时**不**自动联网重翻,保持原文、等用户点 ——
	/// 免得打开较老文章时悄悄花钱。
	func autoApplyTranslationFromCacheIfNeeded() {

		// 正在翻译时别插手
		guard state != .working else { return }
		guard let webViewController = currentWebViewController(),
			  let article = webViewController.article else { return }

		let articleID = article.accountID + "|" + article.articleID
		guard ArticleReadingStateStore.state(for: articleID).translated else { return }

		let model = TranslationConfigStore.selectedModel
		let key = TranslationCache.articleKey(articleID: articleID, model: model)

		runningTask?.cancel()
		runningTask = Task { [weak self] in
			guard let self else { return }

			// 复核内容指纹:只有缓存里的原文和现在页面的原文对得上才拿来用
			//(页面此刻显示的是原文,fingerprint 取的正是原文的纯文字)。
			guard let fingerprint = try? await webViewController.nnwTranslationBodyFingerprint() else { return }
			let bodyHash = TranslationCache.contentHash(fingerprint)

			guard let cached = await TranslationCache.lookup(key: key),
				  cached.bodyHash == bodyHash,
				  let fullBody = cached.bodyHTML else {
				// 没有可用的完整缓存 → 按用户选择不自动联网重翻;
				// 顺手把按钮刷成「有缓存可点」的提示(若有未完成缓存)。
				self.refreshCacheHint()
				return
			}

			// 异步回来后复核:用户可能已经切走文章、或自己点了翻译
			guard self.state != .working,
				  let current = self.currentWebViewController(),
				  current === webViewController,
				  current.article?.articleID == article.articleID else {
				return
			}

			if let cachedTitle = cached.titleHTML {
				_ = try? await webViewController.nnwTranslationApplyTitle(cachedTitle)
			}
			if (try? await webViewController.nnwTranslationApply(fullBody)) == true {
				self.state = .translated
				self.lastErrorMessage = nil
				Self.logger.debug("[翻译] 自动恢复:命中完整缓存,零请求")
			}
		}
	}

	/// 换到另一篇文章时调用,把按钮图标重置成"未翻译"。
	///
	/// 为什么可以直接重置、而不用去问网页:
	/// 换文章一定会导致网页重新加载(要么是新建的 WebViewController,
	/// 要么是同一个控制器调 setArticle 重新渲染),新页面里必然没有译文。
	/// 直接重置是同步的,不会出现"页面已经换了、图标过一会儿才跟上"的闪烁。
	func resetForNewArticle() {
		// 必须取消:否则上一篇文章还在飞的译文,会替换到这一篇的页面上。
		runningTask?.cancel()
		runningTask = nil
		state = .original
		refreshCacheHint()
	}

	/// 查一下当前文章有没有译文缓存,有就把按钮换成"灰底"外观提示用户。
	/// 纯本地检查,不发请求。
	private func refreshCacheHint() {
		guard let article = currentWebViewController()?.article else {
			return
		}
		let articleID = article.accountID + "|" + article.articleID
		let key = TranslationCache.articleKey(articleID: articleID,
											  model: TranslationConfigStore.selectedModel)
		Task { [weak self] in
			guard let self else { return }
			guard let entry = await TranslationCache.lookup(key: key) else { return }
			// 异步回来后要复核:用户可能已经切走文章、或已经点了翻译
			guard self.state == .original,
				  let current = self.currentWebViewController()?.article,
				  current.accountID + "|" + current.articleID == articleID else {
				return
			}
			// 实心点=完整缓存,空心点=未完成缓存(可断点续翻)
			self.state = entry.bodyHTML != nil ? .cachedAvailable : .partialCacheAvailable
		}
	}

	private func performToggle(force: Bool = false) async {

		guard let webViewController = currentWebViewController() else {
			return
		}

		// 关键:不相信 Swift 这边记的状态,每次都先问网页当前真实显示的是什么。
		//
		// 为什么要这样:页面可能在我们不知情的情况下被重新渲染(比如切换阅读视图、
		// 改字号、换主题),那时译文已经没了,但 Swift 这边还以为在显示译文。
		// 图标可以短暂不准,但"点下去的行为"必须永远正确。
		let isShowingTranslation = (try? await webViewController.nnwTranslationIsShowingTranslation()) ?? false

		// 已经在看译文时:
		//   - 正常点击 → 切回原文(瞬间,原文存在网页里);
		//   - 强制重翻(item②)→ 先还原到原文,好让下面的 splitBody 读到原文,
		//     然后**不 return**,继续往下走一遍全新翻译。
		if isShowingTranslation {
			if force {
				_ = try? await webViewController.nnwTranslationRestore()
			} else {
				let didRestore = (try? await webViewController.nnwTranslationRestore()) ?? false
				state = didRestore ? .original : .failed
				if didRestore {
					recordTranslatedState(false)	// [状态记忆] item③:用户切回原文
					refreshCacheHint()	// 刚翻完的文章大概率有缓存了,按钮转为灰底提示
				}
				return
			}
		}

		// [翻译] item④:点翻译即滚到文章顶部,方便从头读译文。
		// 上面「切回原文」的分支已经 return,所以这里只在「要显示译文」时执行;
		// 之后无论是走缓存秒开、断点续翻,还是全新翻译,都从顶部开始。
		_ = try? await webViewController.nnwTranslationScrollToTop()

		state = .working

		// 重置本次运行的进度累积器,并领一个运行序号(防串号,见 runID 注释)
		runGroupTranslations = [:]
		runTitleTranslation = nil
		runID += 1
		let thisRun = runID
		var cacheKey: String?
		var currentBodyHash: String?

		do {
			let service = try makeService()
			let model = TranslationConfigStore.selectedModel

			// 标题的翻译任务句柄。声明在这里、配合 defer,确保中途取消或出错时
			// 这个游离的小任务一定会被叫停 —— 不会在翻页之后把标题译文安到下一篇文章头上。
			var titleTask: Task<String?, Never>? = nil
			defer { titleTask?.cancel() }

			// 0. 先查本地缓存。两种命中:
			//    完整缓存 → 整篇秒开,零请求;
			//    未完成缓存(上次翻到一半被打断) → 记下来,已翻过的组直接复用,只翻剩下的。
			var partialEntry: CachedTranslation?
			if let article = webViewController.article {
				let key = TranslationCache.articleKey(articleID: article.accountID + "|" + article.articleID,
													  model: model)
				cacheKey = key
				// 指纹用**纯文字**而不是 HTML:页面脚本会异步改 HTML(图片装饰等),
				// HTML 每次不完全一样,拿它当指纹缓存会"时中时不中"(见 L18)。
				if let fingerprint = try await webViewController.nnwTranslationBodyFingerprint() {
					let bodyHash = TranslationCache.contentHash(fingerprint)
					currentBodyHash = bodyHash
					// [翻译] item②:强制重翻时跳过缓存(照样保留 cacheKey/bodyHash 供翻完后覆盖写)。
					if !force, let cached = await TranslationCache.lookup(key: key) {
						if cached.bodyHash != bodyHash {
							Self.logger.debug("[翻译] 有缓存条目但内容指纹不匹配,按未缓存处理并重新翻译")
						} else if let fullBody = cached.bodyHTML {
							// 完整缓存:整篇秒开
							if let cachedTitle = cached.titleHTML {
								_ = try? await webViewController.nnwTranslationApplyTitle(cachedTitle)
							}
							_ = try await webViewController.nnwTranslationApply(fullBody)
							state = .translated
							lastErrorMessage = nil
							recordTranslatedState(true)	// [状态记忆] item③
							Self.logger.debug("[翻译] 命中完整缓存,零请求")
							return
						} else {
							partialEntry = cached
							Self.logger.debug("[翻译] 命中未完成缓存(已有 \(cached.groups?.count ?? 0) 组),接着上次继续")
						}
					}
				}
			}

			// 1. 让网页把正文切成若干组(第 1 组最小、越往后越大,理由见参数注释)
			guard let chunksJSON = try await webViewController.nnwTranslationSplitBody(
				leadChars: Self.leadChunkCharacters,
				firstGroupChars: Self.firstGroupCharacters,
				maxGroupChars: Self.maxGroupCharacters) else {
				throw TranslationError.bodyNotFound
			}
			let chunks = try JSONDecoder().decode([TranslationChunk].self,
												  from: Data(chunksJSON.utf8))
			guard !chunks.isEmpty else {
				throw TranslationError.emptyContent
			}

			// 排查性能问题的关键日志:一眼看清每组多大
			let sizeSummary = chunks.map { "组\($0.group)=\($0.html.count)字符" }.joined(separator: " ")
			Self.logger.debug("[翻译] 切分完成:\(sizeSummary, privacy: .public)")

			var context = TranslationContext.initial(
				articleTitle: webViewController.article?.title,
				articleURL: webViewController.article?.preferredLink
			)

			// 2. 标题和先导块**同时**发出。
			//    标题最短、回得最快,最先变成中文 —— 让人立刻感觉到"开始了"。
			//    (之前标题排在所有正文组后面,并发槽一旦占满就轮不到它,
			//     表现为"标题很靠后才被翻译"。)
			if let cachedTitle = partialEntry?.titleHTML {
				// 标题上次已经翻过了,直接用,零请求
				_ = try? await webViewController.nnwTranslationApplyTitle(cachedTitle)
				runTitleTranslation = cachedTitle
			} else if let titleHTML = try await webViewController.nnwTranslationReadTitle(),
			   !titleHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				let titleContext = context
				titleTask = Task { [weak webViewController] in
					// 失败自动重试一次,和正文组同等待遇
					var translated = try? await service.translate(htmlChunk: titleHTML, context: titleContext)
					if translated == nil, !Task.isCancelled {
						try? await Task.sleep(for: .milliseconds(600))
						translated = try? await service.translate(htmlChunk: titleHTML, context: titleContext)
					}
					guard !Task.isCancelled, let translated, let webViewController else {
						return nil
					}
					_ = try? await webViewController.nnwTranslationApplyTitle(translated)
					return translated
				}
			}

			// 3. 先导块。上次翻过就直接复用缓存;否则单独先翻。
			//    它最先出现在屏幕上,你可以马上开始读;
			//    同时它的译文会作为"示范"传给后面所有组,压住术语漂移(方案 C)。
			let first = chunks[0]
			let firstTranslation: String
			if let cachedLead = partialEntry?.groups?[String(first.group)],
			   (try? await webViewController.nnwTranslationApplyGroup(group: first.group,
																	  translatedHTML: cachedLead)) == true {
				firstTranslation = cachedLead
				Self.logger.debug("[翻译] 先导块复用缓存,零请求")
			} else {
				let leadStartedAt = Date()
				// [翻译] 先导块在关键路径上(所有正文组都在等它的译文当示范,方案 C),
				// 用 4 路赛跑把它的延迟压到"4 份里最快的那份"(见 leadRaceCopies 的说明)。
				// 服务支持流式(2026-07-24)→ 4 条流赛跑,冠军的译文**一边生成一边上屏**;
				// 不支持(Mock)→ 非流式赛跑,行为和以前一样。
				var raced: String?
				if let streamingService = service as? StreamingTranslationService,
				   (try? await webViewController.nnwTranslationStreamLeadBegin()) == true {
					var lastPush = Date.distantPast
					raced = await racedStreamingTranslate(htmlChunk: first.html,
														  context: context,
														  service: streamingService,
														  copies: Self.leadRaceCopies) { [weak webViewController] accumulated in
						// 节流:每 0.12 秒最多上屏一次。冠军流是顺序 await 的,这里没有并发竞争
						await MainActor.run {
							guard Date().timeIntervalSince(lastPush) >= 0.12 else { return }
							lastPush = Date()
							guard let webViewController else { return }
							Task { _ = try? await webViewController.nnwTranslationStreamLeadUpdate(accumulated) }
						}
					}
					// 成功失败都要收尾:拆临时容器、原文复位(成功路径下一步 applyGroup 正式替换)
					_ = try? await webViewController.nnwTranslationStreamLeadEnd()
				} else {
					raced = await racedTranslate(htmlChunk: first.html,
												 context: context,
												 service: service,
												 copies: Self.leadRaceCopies)
				}
				if let raced {
					firstTranslation = raced
				} else {
					// 全失败:再直接发一次,好拿到能说人话的错误抛给用户。
					try Task.checkCancellation()
					firstTranslation = try await service.translate(htmlChunk: first.html, context: context)
				}
				Self.logger.debug("[翻译] 先导块完成,耗时 \(String(format: "%.1f", Date().timeIntervalSince(leadStartedAt)), privacy: .public)s")
				try Task.checkCancellation()
				_ = try await webViewController.nnwTranslationApplyGroup(group: first.group,
																		 translatedHTML: firstTranslation)
			}
			runGroupTranslations[first.group] = firstTranslation

			// 注意:这里**不**把按钮切成"已完成"。
			// 全文没翻完就显示完成,会让人以为翻译停了 —— 转圈要一直转到真的全部结束。
			context = context.withSample(original: first.html, translation: firstTranslation)

			// 4. 其余组:上次翻过的直接复用缓存(零请求),剩下的并行翻。
			//    组是按"由小到大"切的,天然靠前的先回来 —— 正合顺序阅读的节奏。
			var work: [TranslationWorkItem] = []
			for chunk in chunks.dropFirst() {
				if let cachedGroup = partialEntry?.groups?[String(chunk.group)],
				   (try? await webViewController.nnwTranslationApplyGroup(group: chunk.group,
																		  translatedHTML: cachedGroup)) == true {
					runGroupTranslations[chunk.group] = cachedGroup
				} else {
					work.append(TranslationWorkItem(target: .chunk(chunk.group), html: chunk.html))
				}
			}
			if partialEntry != nil {
				Self.logger.debug("[翻译] 复用缓存 \(self.runGroupTranslations.count) 组,还需翻 \(work.count) 组")
			}

			var failureCount = 0
			if !work.isEmpty {
				failureCount = await translateInParallel(work,
														 service: service,
														 context: context,
														 webViewController: webViewController)
			}

			try Task.checkCancellation()

			// 5. 事后自检:哪些组还是英文、或者混进了英文原文?
			//    这一步是**纯本地判断,不发请求、不花钱** —— 数一下中英文字符比例,
			//    再拿原文中段当探针查一下有没有被回显。查出来的重翻一次。
			let recheckFailures = await recheckAndRetranslate(service: service,
															 context: context,
															 webViewController: webViewController)

			// 6. 等标题翻完(它是最早发出的,通常此刻早已完成)
			var translatedTitle: String? = runTitleTranslation
			if let titleTask {
				translatedTitle = await titleTask.value
				runTitleTranslation = translatedTitle
			}

			try Task.checkCancellation()

			// 7. 真的全部结束了,现在才点亮按钮
			let totalFailures = failureCount + recheckFailures

			if totalFailures > 0 {
				state = .failed
				lastErrorMessage = "有 \(totalFailures) 组内容没能翻译成功,保持了原文。点一下回到原文,再点一次可以接着翻(已翻好的组会复用,不重复花钱)。"
				Self.logger.error("[翻译] 完成,但有 \(totalFailures) 组失败")
				recordTranslatedState(false)	// [状态记忆] item③:没整篇成功就不记成"已翻译",避免自动恢复到残缺态
				// 翻好的部分存成"未完成缓存",下次接着翻
				savePartialProgress(cacheKey: cacheKey, bodyHash: currentBodyHash, run: thisRun)
			} else {
				state = .translated
				lastErrorMessage = nil
				recordTranslatedState(true)	// [状态记忆] item③:整篇成功,记住"已翻译"

				// 8. 全部成功 → 存完整缓存,下次这篇秒开、零花费
				if let cacheKey, let currentBodyHash,
				   let translatedBody = try? await webViewController.nnwTranslationReadBody() {
					TranslationCache.store(key: cacheKey,
										   CachedTranslation(bodyHash: currentBodyHash,
															 titleHTML: translatedTitle,
															 bodyHTML: translatedBody,
															 groups: nil))
				}
			}

		} catch is CancellationError {
			// 用户翻页/中途取消。已翻好的组存成"未完成缓存",
			// 下次打开这篇文章可以接着翻,已花的钱不浪费。
			Self.logger.debug("[翻译] 已取消,保存未完成进度")
			savePartialProgress(cacheKey: cacheKey, bodyHash: currentBodyHash, run: thisRun)
		} catch {
			Self.logger.error("[翻译] 失败:\(error.localizedDescription, privacy: .public)")
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			state = .failed
			// [翻译] 把失败原因弹给用户,别只留一个静默的感叹号。
			// 未配置(如强制重翻时 key 被清了)用引导语,其它用错误说明。
			// performToggle 只由用户点击/长按触发,所以这里弹窗一定是用户发起的。
			presentError?(configurationPromptIfNeeded() ?? lastErrorMessage ?? "翻译失败,请稍后重试。")
		}
	}

	/// 把已完成的组存成"未完成缓存"。下次打开这篇文章接着翻,不重复花钱。
	private func savePartialProgress(cacheKey: String?, bodyHash: String?, run: Int) {
		// 序号对不上 = 已经有新的翻译运行开始了,累积器里是别的文章的内容,
		// 存下去会张冠李戴 —— 放弃保存(只损失一点省钱机会,不会出错)。
		guard run == runID else {
			Self.logger.debug("[翻译] 进度已被新运行取代,放弃保存")
			return
		}
		guard let cacheKey, let bodyHash, !runGroupTranslations.isEmpty else {
			return
		}
		let groups = Dictionary(uniqueKeysWithValues: runGroupTranslations.map { (String($0.key), $0.value) })
		TranslationCache.store(key: cacheKey,
							   CachedTranslation(bodyHash: bodyHash,
												 titleHTML: runTitleTranslation,
												 bodyHTML: nil,
												 groups: groups))
		Self.logger.debug("[翻译] 已保存未完成进度:\(self.runGroupTranslations.count) 组")
	}

	/// 全部翻完后再检查一遍,把没翻好的组重翻。返回重翻后仍然失败的组数。
	///
	/// 检查两种毛病(都由 JS 在本地判断,不发请求):
	///   ① 这一组还是英文 —— 请求失败过,或者模型把原文原样还回来了
	///   ② 这一组混进了英文原文 —— 模型做了中英对照
	///
	/// 只查一轮。查两轮的收益很小,却可能在模型持续不听话时反复烧钱。
	private func recheckAndRetranslate(service: TranslationService,
									   context: TranslationContext,
									   webViewController: WebViewController) async -> Int {

		guard let json = try? await webViewController.nnwTranslationFindGroupsNeedingRetranslation(),
			  let bad = try? JSONDecoder().decode([TranslationChunk].self, from: Data(json.utf8)),
			  !bad.isEmpty else {
			return 0
		}

		Self.logger.debug("[翻译] 自检发现 \(bad.count) 组需要重翻")

		let work = bad.map { TranslationWorkItem(target: .chunk($0.group), html: $0.html) }

		return await translateInParallel(work,
										 service: service,
										 context: context,
										 webViewController: webViewController)
	}

	/// 对冲翻译(治尾延迟,item①):先发一份;`delay` 秒内没成功,就并发再发一份,
	/// 取第一个成功的,另一份取消。两份都失败返回 nil(交给上层的重试逻辑处理)。
	///
	/// 注意「先失败」和「先慢」是两回事:
	///   - 第一份很快就**失败**(网络错/限流)→ 立刻返回 nil,不等对冲,
	///     让外层该重试重试、该报错报错(拿到能说人话的原因)。
	///   - 第一份迟迟**不回**(尾延迟)→ 到点补发一份,谁先成功用谁。
	///
	/// 流式赛跑的「冠军门」:4 条流里**谁先吐出第一个字,谁就是冠军**,
	/// 只有冠军的增量上屏,其余三条在下一次回调时得知落选、立刻自我了断(停止花钱)。
	private actor StreamWinnerGate {
		private var winner: Int?
		/// 第 `id` 条流来认领。第一个来的成为冠军;之后只有冠军自己再来才返回 true。
		func claim(_ id: Int) -> Bool {
			if winner == nil { winner = id }
			return winner == id
		}
	}

	/// 流式赛跑翻译(先导块专用,2026-07-24):并发 `copies` 条**流式**请求,
	/// 第一条产出增量的流成为冠军,它的增量通过 `onWinnerDelta` 渐进上屏;
	/// 其余的流自我了断。冠军跑完返回完整译文;全失败返回 nil(上层回落到非流式)。
	///
	/// 顺序安全:冠军是**单独一条**顺序读取的流,每个增量都 await 完 onWinnerDelta
	/// 才读下一行 —— 上屏天然按序,不需要额外去重/排序。
	nonisolated private func racedStreamingTranslate(htmlChunk: String,
													 context: TranslationContext,
													 service: StreamingTranslationService,
													 copies: Int,
													 onWinnerDelta: @Sendable @escaping (String) async -> Void) async -> String? {

		let gate = StreamWinnerGate()

		return await withTaskGroup(of: String?.self) { group in
			for id in 0..<max(copies, 1) {
				group.addTask {
					try? await service.translateStreaming(htmlChunk: htmlChunk, context: context) { accumulated in
						guard await gate.claim(id) else { return false }	// 落选 → 让这条流自我了断
						await onWinnerDelta(accumulated)
						return true
					}
				}
			}
			var remaining = max(copies, 1)
			while let result = await group.next() {
				if let result {
					group.cancelAll()
					return result
				}
				remaining -= 1
				if remaining == 0 { return nil }
			}
			return nil
		}
	}

	/// 赛跑翻译(非流式版,MockTranslationService 这类不支持流式的服务用):
	/// 开局就并发 `copies` 份同样的请求,**谁先成功用谁**,其余立刻取消;
	/// 全失败返回 nil(交给上层拿可读错误)。
	///
	/// 和下面 hedgedTranslate 的区别:对冲是"慢了才补一份"(省钱,给普通组用),
	/// 赛跑是"一开始就全发"(费一点小钱,换关键路径的最低延迟,只给先导块用)。
	nonisolated private func racedTranslate(htmlChunk: String,
											context: TranslationContext,
											service: TranslationService,
											copies: Int) async -> String? {

		await withTaskGroup(of: String?.self) { group in
			for _ in 0..<max(copies, 1) {
				group.addTask {
					try? await service.translate(htmlChunk: htmlChunk, context: context)
				}
			}
			var remaining = max(copies, 1)
			while let result = await group.next() {
				if let result {
					group.cancelAll()	// 有一份成功,其余的钱不用再花
					return result
				}
				remaining -= 1
				if remaining == 0 { return nil }
			}
			return nil
		}
	}

	/// nonisolated:只用到入参、不碰实例状态,这样它能在并发任务里直接跑,不必回主线程。
	nonisolated private func hedgedTranslate(htmlChunk: String,
											 context: TranslationContext,
											 service: TranslationService,
											 delay: TimeInterval) async -> String? {

		await withTaskGroup(of: TranslationHedgeSignal.self) { group in

			// 第一份:立刻发。
			group.addTask {
				if let text = try? await service.translate(htmlChunk: htmlChunk, context: context) {
					return .translated(text)
				}
				return .failed
			}
			// 计时哨兵:到 delay 就发一个信号,说明第一份「慢了」。
			group.addTask {
				try? await Task.sleep(for: .seconds(delay))
				return .timerFired
			}

			// 当前在飞的「翻译」份数(哨兵不算)。降到 0 = 所有翻译都失败了。
			var inFlightTranslations = 1

			while let signal = await group.next() {
				switch signal {
				case .translated(let text):
					group.cancelAll()	// 有一份成功,掐掉另一份(和还在睡的哨兵)
					return text
				case .timerFired:
					// 第一份还没成功,补发一份对冲。
					Self.logger.debug("[翻译] 对冲触发:一份请求超过 \(String(format: "%.0f", delay), privacy: .public)s 未成功,补发一份")
					group.addTask {
						if let text = try? await service.translate(htmlChunk: htmlChunk, context: context) {
							return .translated(text)
						}
						return .failed
					}
					inFlightTranslations += 1
				case .failed:
					inFlightTranslations -= 1
					if inFlightTranslations == 0 {
						group.cancelAll()	// 翻译都失败了,别让哨兵吊着
						return nil
					}
					// 还有另一份在飞,继续等
				}
			}
			return nil
		}
	}

	/// 并行翻译,返回最终仍然失败的段数。
	///
	/// 用滑动窗口控制并发:同时最多 `maxConcurrentRequests` 个请求在飞,
	/// 有一个回来就补一个,而不是一口气把几十个请求全丢出去(那样会被服务商限流)。
	///
	/// 失败的段会**自动重试一次**。之前没有重试,导致偶发的限流/超时
	/// 直接表现为"某几段没翻",而且不告诉用户。
	private func translateInParallel(_ items: [TranslationWorkItem],
									 service: TranslationService,
									 context: TranslationContext,
									 webViewController: WebViewController) async -> Int {

		var failureCount = 0
		var pending = items
		var nextIndex = 0

		await withTaskGroup(of: (TranslationWorkItem, String?, TimeInterval).self) { group in

			func addNext() {
				guard nextIndex < pending.count else { return }
				let item = pending[nextIndex]
				nextIndex += 1
				// [翻译] item①:按这一组的大小估对冲阈值(主线程算好再带进任务)。
				let hedgeDelay = Self.bodyHedgeDelay(forChars: item.html.count)
				group.addTask {
					// 重试前先等一下。被限流时立刻重试多半还是被拒。
					if item.attempt > 0 {
						try? await Task.sleep(for: .milliseconds(600))
					}
					let startedAt = Date()
					// 用对冲翻译:偏慢的组会并发补发一份,压住尾延迟(见 hedgedTranslate)。
					let translated = await self.hedgedTranslate(htmlChunk: item.html,
																context: context,
																service: service,
																delay: hedgeDelay)
					return (item, translated, Date().timeIntervalSince(startedAt))
				}
			}

			for _ in 0..<min(Self.maxConcurrentRequests, pending.count) {
				addNext()
			}

			while let (item, translated, elapsed) = await group.next() {

				if Task.isCancelled {
					group.cancelAll()
					break
				}

				// ⚠️ 替换失败要和请求失败同等对待。
				// 以前这里写的是 `_ = try? ...`,替换失败被静默吞掉 ——
				// 那一组会一直显示原文,拖到最后的自检阶段才被救回来,
				// 表象就是"某一组总是最后才翻好"。
				var applied = false
				if let translated {
					switch item.target {
					case .chunk(let group):
						applied = (try? await webViewController.nnwTranslationApplyGroup(group: group,
																						 translatedHTML: translated)) ?? false
						if applied {
							runGroupTranslations[group] = translated	// 进度累积,供断点续翻
						}
					case .title:
						applied = (try? await webViewController.nnwTranslationApplyTitle(translated)) ?? false
						if applied {
							runTitleTranslation = translated
						}
					}
				}

				let outcome = translated == nil ? "请求失败" : (applied ? "完成" : "替换失败")
				Self.logger.debug("[翻译] \(item.debugLabel, privacy: .public) 第\(item.attempt + 1)次:\(outcome, privacy: .public),耗时 \(String(format: "%.1f", elapsed), privacy: .public)s,原文 \(item.html.count) 字符")

				if !applied {
					if item.attempt < Self.maxRetries {
						// 排到队尾再试一次
						pending.append(item.retrying())
					} else {
						// 重试后仍然失败,这一组保持原文。不影响其他组。
						failureCount += 1
					}
				}

				addNext()
			}
		}

		return failureCount
	}
}

/// JS 切好的一组。对应 translation.js 里 splitBody() 返回的结构。
private struct TranslationChunk: Decodable, Sendable {
	let group: Int
	let html: String
}

/// 对冲翻译内部的信号(item①)。故意不携带 Error —— 只带 Sendable 的值,
/// 好让它能安全地在并发任务组之间传递。
private enum TranslationHedgeSignal: Sendable {
	/// 某一份成功了,带回译文。
	case translated(String)
	/// 某一份失败了(网络错/限流/超时)。
	case failed
	/// 计时哨兵到点:说明第一份「慢了」,该补发对冲了。
	case timerFired
}

/// 一件待翻译的活:正文的某一块,或者标题。
private struct TranslationWorkItem: Sendable {

	enum Target: Sendable {
		case chunk(Int)
		case title
	}

	let target: Target
	let html: String
	var attempt: Int = 0

	var debugLabel: String {
		switch target {
		case .chunk(let group):
			return "组\(group)"
		case .title:
			return "标题"
		}
	}

	func retrying() -> TranslationWorkItem {
		TranslationWorkItem(target: target, html: html, attempt: attempt + 1)
	}
}

#endif
