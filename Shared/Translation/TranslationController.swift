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
	/// 正在显示原文,点一下会翻译。
	case original
	/// 正在翻译中,转圈,不可点。
	case working
	/// 正在显示译文,点一下切回原文。
	case translated
	/// 上次翻译失败了。
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

	override init(frame: CGRect) {
		super.init(frame: frame)
		setUpActivityIndicator()
		applyDisplayState()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setUpActivityIndicator()
		applyDisplayState()
	}

	private func setUpActivityIndicator() {
		addSubview(activityIndicator)
		NSLayoutConstraint.activate([
			activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}

	private func applyDisplayState() {
		switch displayState {
		case .original:
			activityIndicator.stopAnimating()
			isUserInteractionEnabled = true
			setImage(UIImage(systemName: "character.bubble"), for: .normal)
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

	private let service: TranslationService
	private let currentWebViewController: @MainActor () -> WebViewController?

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Translation")

	let button: TranslationButton = {
		let button = TranslationButton(type: .system)
		button.frame = CGRect(x: 0, y: 0, width: 44.0, height: 44.0)
		return button
	}()

	private(set) var state: TranslationButtonState = .original {
		didSet { button.displayState = state }
	}

	/// - Parameters:
	///   - service: 翻译服务。默认是 Phase 1 的假实现;Phase 3 换成真后端时只改这一个默认值。
	///   - currentWebViewController: 怎么拿到"当前正在看的那篇文章的网页"。
	init(service: TranslationService = MockTranslationService(),
		 currentWebViewController: @escaping @MainActor () -> WebViewController?) {
		self.service = service
		self.currentWebViewController = currentWebViewController
	}

	/// 包成工具栏上能放的那种按钮。
	func makeBarButtonItem() -> UIBarButtonItem {
		UIBarButtonItem(customView: button)
	}

	/// 点了按钮。
	func toggle() {
		guard state != .working else { return }
		Task { await performToggle() }
	}

	/// 换到另一篇文章时调用,把按钮图标重置成"未翻译"。
	///
	/// 为什么可以直接重置、而不用去问网页:
	/// 换文章一定会导致网页重新加载(要么是新建的 WebViewController,
	/// 要么是同一个控制器调 setArticle 重新渲染),新页面里必然没有译文。
	/// 直接重置是同步的,不会出现"页面已经换了、图标过一会儿才跟上"的闪烁。
	func resetForNewArticle() {
		state = .original
	}

	private func performToggle() async {

		guard let webViewController = currentWebViewController() else {
			return
		}

		// 关键:不相信 Swift 这边记的状态,每次都先问网页当前真实显示的是什么。
		//
		// 为什么要这样:页面可能在我们不知情的情况下被重新渲染(比如切换阅读视图、
		// 改字号、换主题),那时译文已经没了,但 Swift 这边还以为在显示译文。
		// 图标可以短暂不准,但"点下去的行为"必须永远正确。
		let isShowingTranslation = (try? await webViewController.nnwTranslationIsShowingTranslation()) ?? false

		// 已经在看译文 → 切回原文。原文存在网页里,所以是瞬间的。
		if isShowingTranslation {
			let didRestore = (try? await webViewController.nnwTranslationRestore()) ?? false
			state = didRestore ? .original : .failed
			return
		}

		state = .working

		do {
			guard let originalHTML = try await webViewController.nnwTranslationReadBody() else {
				Self.logger.error("[翻译] 在页面里找不到正文容器,可能是当前主题不受支持")
				state = .failed
				return
			}

			let articleURL = webViewController.article?.preferredLink
			let translatedHTML = try await service.translate(html: originalHTML, articleURL: articleURL)

			let didApply = try await webViewController.nnwTranslationApply(translatedHTML)
			state = didApply ? .translated : .failed

		} catch {
			Self.logger.error("[翻译] 失败:\(error.localizedDescription, privacy: .public)")
			state = .failed
		}
	}
}

#endif
