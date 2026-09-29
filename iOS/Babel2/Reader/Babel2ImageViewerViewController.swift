import ImageIO
import UIKit

/// 阅读页点图片后的查看器（2026-09-27 用户反馈第 3 条，ADR-040）。
///
/// 卡片式：图片从正文里原来的位置放大到屏幕中央；背景跟随 app 的浅色 / 深色
/// （纸色，几乎不透明），不像跳到了另一个页面。
/// 直角、无描边；横图（宽大于高）贴满屏幕两边，竖图 / 方图四周留白居中（2026-09-27 用户验收时要求，ADR-051）。
/// - 双指缩放；双击放大 / 还原；放大后可以拖着看
/// - 点一下、或往下拖（跟手，松手缩回原处）关闭；左上角也有 ✕
/// - 长按图片：存到相册 / 分享（系统分享面板）
/// - 图片外面链到的是另一个网页（不是图片文件本身）时，底部给「打开链接」
///
/// 不用系统转场：以不带动画的方式弹出，进出动画由本页自己做（也方便自动化测试直接驱动）。
/// 大图下载完之前，先用正文里那张图的截图顶上，放大动画一开始就有画面。
@MainActor
final class Babel2ImageViewerViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
	struct Source {
		/// 先顶上的画面（正文里那张图的截图）；nil = 等下载
		let placeholder: UIImage?
		let imageURL: URL?
		/// 图片外面包着的链接；本身就是图片文件的不算
		let linkURL: URL?
		/// 图在屏幕上的原位置（窗口坐标）；nil = 不做从原位放大的动画，只淡入淡出
		let originFrame: CGRect?
		let altText: String
	}

	static let margin: CGFloat = 16
	/// 竖图 / 方图的小图最多放大到原尺寸的 3 倍（再大就糊了）；横图不受这个限制，一律贴满两边
	static let maxUpscale: CGFloat = 3
	/// 往下拖多远（或多快）松手算关闭
	static let dismissDistance: CGFloat = 110
	static let dismissVelocity: CGFloat = 900

	private let source: Source
	private let loadImage: (@MainActor (URL) async -> UIImage?)?
	/// 点了「打开链接」：先关掉查看器，再交给阅读页打开。
	var onOpenLink: ((URL) -> Void)?
	/// 关闭动画结束、页面已收起。
	var onDismiss: (() -> Void)?

	private let backdrop = UIView()
	private let scrollView = UIScrollView()
	let imageView = UIImageView()
	private let closeButton = UIButton(type: .system)
	private let closeDisc = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
	private let failureLabel = UILabel()
	private var linkButton: UIButton?
	private var loadTask: Task<Void, Never>?
	/// 长按分享的手感（ADR-060）
	private var longPressFeedback: Babel2LongPressFeedback?
	private var didAnimateIn = false
	private(set) var isDismissing = false
	private var lastLayoutSize: CGSize = .zero

	init(source: Source, loadImage: (@MainActor (URL) async -> UIImage?)?) {
		self.source = source
		self.loadImage = loadImage
		super.init(nibName: nil, bundle: nil)
		modalPresentationStyle = .overFullScreen
	}

	required init?(coder: NSCoder) { nil }

	deinit { loadTask?.cancel() }

	/// 图片外面的链接值不值得给「打开链接」：链到的就是图片文件本身的不给。
	static func meaningfulLink(_ link: URL?, imageURL: URL?) -> URL? {
		guard let link, ["http", "https"].contains(link.scheme?.lowercased() ?? "") else { return nil }
		if let imageURL, link.absoluteString == imageURL.absoluteString { return nil }
		let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "svg", "tif", "tiff"]
		return imageExtensions.contains(link.pathExtension.lowercased()) ? nil : link
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .clear
		view.accessibilityViewIsModal = true

		backdrop.backgroundColor = BabelPalette.background.withAlphaComponent(0.97)
		backdrop.frame = view.bounds
		backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		backdrop.alpha = 0
		view.addSubview(backdrop)

		scrollView.frame = view.bounds
		scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		scrollView.delegate = self
		scrollView.minimumZoomScale = 1
		scrollView.maximumZoomScale = 4
		scrollView.showsVerticalScrollIndicator = false
		scrollView.showsHorizontalScrollIndicator = false
		scrollView.contentInsetAdjustmentBehavior = .never
		scrollView.decelerationRate = .fast
		scrollView.backgroundColor = .clear
		view.addSubview(scrollView)

		imageView.image = source.placeholder
		imageView.contentMode = .scaleAspectFill
		imageView.clipsToBounds = true
		// 直角、无描边（ADR-051）：贴满两边的横图两侧不会多出一道线
		imageView.backgroundColor = BabelPalette.raisedBackground
		imageView.isUserInteractionEnabled = true
		imageView.isAccessibilityElement = true
		imageView.accessibilityTraits = .image
		imageView.accessibilityLabel = source.altText.isEmpty ? nil : source.altText
		imageView.accessibilityIdentifier = "babel2.image-viewer.image"
		scrollView.addSubview(imageView)

		failureLabel.text = Babel2Localization.text(.unableToLoadImage)
		failureLabel.font = .systemFont(ofSize: 15, weight: .regular)
		failureLabel.textColor = BabelPalette.mutedInk
		failureLabel.textAlignment = .center
		failureLabel.isHidden = true
		failureLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(failureLabel)

		configureCloseButton()
		configureLinkButton()
		configureGestures()
		NSLayoutConstraint.activate([
			failureLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			failureLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])
		startLoadingFullImage()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		// 只在尺寸变化（第一次布局、旋转）且没有放大、没有在拖时重排卡片
		guard view.bounds.size != lastLayoutSize, !isDismissing else { return }
		lastLayoutSize = view.bounds.size
		scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
		layoutCard()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		animateInIfNeeded()
	}

	override func accessibilityPerformEscape() -> Bool {
		dismissViewer()
		return true
	}

	// MARK: - 布局

	/// 图在屏幕上的位置，竖直方向都在安全区里（上下留 16pt）居中：
	/// - 横图（宽大于高）：贴满屏幕两边（不管原图多小都放大到整宽；横着拿手机、整宽放不下高度时才按高度缩）
	/// - 竖图 / 方图：左右也留 16pt，按比例放进去；小图最多放大 3 倍
	static func fittedFrame(imageSize: CGSize, in bounds: CGRect, safeArea: UIEdgeInsets) -> CGRect {
		let available = bounds.inset(by: UIEdgeInsets(
			top: safeArea.top + margin, left: safeArea.left + margin,
			bottom: safeArea.bottom + margin, right: safeArea.right + margin))
		guard imageSize.width > 0, imageSize.height > 0, available.width > 0, available.height > 0 else {
			return CGRect(x: bounds.midX - 60, y: bounds.midY - 60, width: 120, height: 120)
		}
		let scale: CGFloat
		let centerX: CGFloat
		if imageSize.width > imageSize.height {
			scale = min(bounds.width / imageSize.width, available.height / imageSize.height)
			centerX = bounds.midX
		} else {
			scale = min(available.width / imageSize.width, available.height / imageSize.height, maxUpscale)
			centerX = available.midX
		}
		let size = CGSize(width: (imageSize.width * scale).rounded(), height: (imageSize.height * scale).rounded())
		return CGRect(x: (centerX - size.width / 2).rounded(), y: (available.midY - size.height / 2).rounded(), width: size.width, height: size.height)
	}

	/// 当前图片（没有图时用原位置的比例）应该放成多大、放在哪。
	private var cardFrame: CGRect {
		let size = imageView.image?.size ?? source.originFrame?.size ?? CGSize(width: 4, height: 3)
		return Self.fittedFrame(imageSize: size, in: view.bounds, safeArea: view.safeAreaInsets)
	}

	/// 缩放用的标准结构：图片在滚动区内容的原点，内容大小 = 图片大小，用内边距把它放到卡片位置并保持居中。
	private func layoutCard() {
		let frame = cardFrame
		imageView.transform = .identity
		imageView.frame = CGRect(origin: .zero, size: frame.size)
		scrollView.contentSize = frame.size
		centerImage()
	}

	private func centerImage() {
		let size = imageView.frame.size
		let horizontal = max((scrollView.bounds.width - size.width) / 2, 0)
		let vertical = max((scrollView.bounds.height - size.height) / 2, 0)
		scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
	}

	// MARK: - 按钮

	/// 左上角 ✕：36pt 毛玻璃圆底（与文章列表大图上的按钮同款），位置与阅读页顶栏的 ✕ 一致。
	private func configureCloseButton() {
		closeDisc.layer.cornerRadius = 18
		closeDisc.clipsToBounds = true
		closeDisc.isUserInteractionEnabled = false
		closeDisc.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(closeDisc)
		closeButton.setImage(Babel2Icon.close.image(size: Babel2Icon.Size.top), for: .normal)
		closeButton.tintColor = BabelPalette.ink
		closeButton.accessibilityLabel = Babel2Localization.text(.close)
		closeButton.accessibilityIdentifier = "babel2.image-viewer.close"
		closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
		closeButton.translatesAutoresizingMaskIntoConstraints = false
		closeButton.alpha = 0
		closeDisc.alpha = 0
		Babel2Motion.addPressFeedback(to: closeButton)
		view.addSubview(closeButton)
		NSLayoutConstraint.activate([
			closeButton.centerXAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
			closeButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 22),
			closeButton.widthAnchor.constraint(equalToConstant: 44),
			closeButton.heightAnchor.constraint(equalToConstant: 44),
			closeDisc.centerXAnchor.constraint(equalTo: closeButton.centerXAnchor),
			closeDisc.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
			closeDisc.widthAnchor.constraint(equalToConstant: 36),
			closeDisc.heightAnchor.constraint(equalToConstant: 36)
		])
	}

	/// 底部「打开链接」胶囊（反色：墨色底、纸色字，与「已存储到相册」提示同一套配色）。
	private func configureLinkButton() {
		guard Self.meaningfulLink(source.linkURL, imageURL: source.imageURL) != nil else { return }
		var configuration = UIButton.Configuration.filled()
		configuration.title = Babel2Localization.text(.openLink)
		configuration.image = Babel2Icon.openLink.image(size: 16)
		configuration.imagePlacement = .trailing
		configuration.imagePadding = 6
		configuration.baseBackgroundColor = BabelPalette.ink
		configuration.baseForegroundColor = BabelPalette.background
		configuration.cornerStyle = .capsule
		configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16)
		configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
			var attributes = attributes
			attributes.font = .systemFont(ofSize: 14, weight: .semibold)
			return attributes
		}
		let button = UIButton(configuration: configuration)
		button.accessibilityIdentifier = "babel2.image-viewer.open-link"
		button.addTarget(self, action: #selector(openLinkTapped), for: .touchUpInside)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.alpha = 0
		Babel2Motion.addPressFeedback(to: button)
		view.addSubview(button)
		NSLayoutConstraint.activate([
			button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
		])
		linkButton = button
	}

	/// 仅供自动化测试。
	var hasOpenLinkButton: Bool { linkButton != nil }

	@objc private func closeTapped() { dismissViewer() }

	@objc private func openLinkTapped() {
		guard let link = Self.meaningfulLink(source.linkURL, imageURL: source.imageURL) else { return }
		dismissViewer { [weak self] in self?.onOpenLink?(link) }
	}

	// MARK: - 手势

	private func configureGestures() {
		let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
		doubleTap.numberOfTapsRequired = 2
		scrollView.addGestureRecognizer(doubleTap)
		let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
		singleTap.require(toFail: doubleTap)
		scrollView.addGestureRecognizer(singleTap)
		let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
		pan.delegate = self
		scrollView.addGestureRecognizer(pan)
		// 长按图片：按住图片慢慢缩小，按满震一下弹回，再出分享面板（ADR-060）。
		// 缩放的是外面那层滚动区——图片本身的形变由双指缩放占用，动它会把放大状态弄乱
		longPressFeedback = Babel2LongPressFeedback(on: imageView, target: { [weak self] _ in
			self?.imageView.image == nil ? nil : self?.scrollView
		}, onCommit: { [weak self] _ in
			self?.presentShareSheet() ?? false
		})
	}

	/// 双击：没放大时以手指位置为中心放大到 2.5 倍；已放大时还原。
	@objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
		toggleZoom(at: gesture.location(in: imageView))
	}

	func toggleZoom(at point: CGPoint) {
		if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
			scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
			return
		}
		let scale: CGFloat = 2.5
		let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
		scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
	}

	/// 仅供自动化测试。
	var zoomScale: CGFloat { scrollView.zoomScale }
	var maximumZoomScale: CGFloat { scrollView.maximumZoomScale }

	@objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
		dismissViewer()
	}

	/// 往下拖关闭只在没放大时生效；竖直方向为主才开始（横着拖交给滚动 / 忽略）。
	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
		guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01, !isDismissing else { return false }
		let velocity = pan.velocity(in: view)
		return abs(velocity.y) > abs(velocity.x) * 1.2
	}

	@objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
		let translation = gesture.translation(in: view)
		switch gesture.state {
		case .changed:
			let progress = min(abs(translation.y) / 300, 1)
			imageView.transform = CGAffineTransform(translationX: translation.x * 0.3, y: translation.y)
				.scaledBy(x: 1 - progress * 0.12, y: 1 - progress * 0.12)
			backdrop.alpha = 1 - progress * 0.85
			setChromeAlpha(1 - progress * 2)
		case .ended, .cancelled:
			let velocity = gesture.velocity(in: view).y
			if gesture.state == .ended, Self.shouldDismiss(dragDistance: translation.y, velocity: velocity) {
				dismissViewer()
			} else {
				Babel2Motion.animate(Babel2Motion.standard) {
					self.imageView.transform = .identity
					self.backdrop.alpha = 1
					self.setChromeAlpha(1)
				}
			}
		default:
			break
		}
	}

	/// 松手时关不关：拖得够远，或者甩得够快（往上往下都算）。纯函数，方便测试。
	static func shouldDismiss(dragDistance: CGFloat, velocity: CGFloat) -> Bool {
		abs(dragDistance) > dismissDistance || abs(velocity) > dismissVelocity
	}

	/// 长按图片：系统分享面板（里面有「存储图像」）。返回是否弹出了。
	@discardableResult
	private func presentShareSheet() -> Bool {
		guard let image = imageView.image, presentedViewController == nil else { return false }
		if let shareForTesting {
			shareForTesting(image)
			return true
		}
		let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
		activity.popoverPresentationController?.sourceView = imageView
		activity.popoverPresentationController?.sourceRect = imageView.bounds
		present(activity, animated: true)
		return true
	}

	/// 仅供自动化测试。
	var longPressFeedbackForTesting: Babel2LongPressFeedback? { longPressFeedback }
	/// 仅供自动化测试：设了就不弹真的分享面板（它会在模拟器后台加载一批分享扩展，拖慢之后的测试），改为交给这里。
	var shareForTesting: ((UIImage) -> Void)?

	// MARK: - UIScrollViewDelegate

	func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		centerImage()
		// 放大时收起按钮，免得挡图；还原时放回来
		let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
		Babel2Motion.animate(Babel2Motion.quick) { self.setChromeAlpha(zoomed ? 0 : 1) }
	}

	// MARK: - 大图

	private func startLoadingFullImage() {
		guard let url = source.imageURL, let loadImage else {
			failureLabel.isHidden = source.placeholder != nil
			return
		}
		loadTask = Task { @MainActor [weak self] in
			let image = await loadImage(url)
			guard !Task.isCancelled, let self else { return }
			guard let image else {
				self.failureLabel.isHidden = self.source.placeholder != nil
				return
			}
			let atRest = self.scrollView.zoomScale <= self.scrollView.minimumZoomScale + 0.01
			Babel2Motion.crossfade(self.imageView) { self.imageView.image = image }
			// 比例变了（截图和原图不完全一致）且没在缩放、没在拖：按新比例重排卡片
			if atRest, !self.isDismissing, self.imageView.transform == .identity { self.layoutCard() }
		}
	}

	/// 解码下载回来的图片；GIF 动图保留动画（UIImage(data:) 只取第一帧）。
	nonisolated static func decodeImage(_ data: Data) -> UIImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
		let count = CGImageSourceGetCount(source)
		guard count > 1 else { return UIImage(data: data) }
		var frames = [UIImage]()
		var duration: TimeInterval = 0
		for index in 0..<min(count, 300) {
			guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
			frames.append(UIImage(cgImage: frame))
			let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
			let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
			let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
			duration += delay < 0.02 ? 0.1 : delay
		}
		return frames.isEmpty ? UIImage(data: data) : UIImage.animatedImage(with: frames, duration: duration)
	}

	/// data: 开头的图（正文里内嵌的小图）直接解出来，不走网络。
	nonisolated static func inlineImageData(_ url: URL) -> Data? {
		guard url.scheme?.lowercased() == "data" else { return nil }
		let string = url.absoluteString
		guard let comma = string.firstIndex(of: ",") else { return nil }
		let header = string[..<comma]
		let payload = String(string[string.index(after: comma)...])
		if header.contains(";base64") { return Data(base64Encoded: payload.removingPercentEncoding ?? payload) }
		return payload.removingPercentEncoding.map { Data($0.utf8) }
	}

	// MARK: - 进出动画

	/// 原位置（窗口坐标）换算到本页；不在屏幕上的不算。
	private var originFrameInView: CGRect? {
		guard let origin = source.originFrame, let window = view.window else { return nil }
		let frame = view.convert(origin, from: window)
		return frame.intersects(view.bounds) ? frame : nil
	}

	private func setChromeAlpha(_ alpha: CGFloat) {
		let value = max(0, min(1, alpha))
		closeButton.alpha = value
		closeDisc.alpha = value
		linkButton?.alpha = value
	}

	/// 从正文里的位置放大到卡片（0.32 秒 ease-out）；减弱动态效果时只淡入。
	private func animateInIfNeeded() {
		guard !didAnimateIn else { return }
		didAnimateIn = true
		view.layoutIfNeeded()
		let target = imageView.frame
		if let origin = originFrameInView, !Babel2Motion.reduceMotion {
			let startInScroll = scrollView.convert(origin, from: view)
			imageView.frame = startInScroll
			Babel2Motion.animate(Babel2Motion.page, {
				self.imageView.frame = target
				self.backdrop.alpha = 1
				self.setChromeAlpha(1)
			})
		} else {
			imageView.alpha = 0
			Babel2Motion.animate(Babel2Motion.standard, {
				self.imageView.alpha = 1
				self.backdrop.alpha = 1
				self.setChromeAlpha(1)
			})
		}
	}

	/// 关闭：图片缩回正文里原来的位置（还在屏幕上的话），背景淡出；然后收起本页。
	func dismissViewer(completion: (() -> Void)? = nil) {
		guard !isDismissing else { return }
		isDismissing = true
		loadTask?.cancel()
		let finish: (Bool) -> Void = { [weak self] _ in
			guard let self else { return }
			self.dismiss(animated: false) {
				self.onDismiss?()
				completion?()
			}
		}
		guard view.window != nil else {
			finish(true)
			return
		}
		let origin = originFrameInView
		// 从当前画面（可能正被拖着、可能放大着）接着动
		let current = imageView.convert(imageView.bounds, to: view)
		imageView.transform = .identity
		scrollView.zoomScale = scrollView.minimumZoomScale
		imageView.removeFromSuperview()
		imageView.frame = current
		view.insertSubview(imageView, aboveSubview: scrollView)
		Babel2Motion.animate(Babel2Motion.standard, {
			if let origin, !Babel2Motion.reduceMotion {
				self.imageView.frame = origin
			} else {
				self.imageView.alpha = 0
			}
			self.backdrop.alpha = 0
			self.setChromeAlpha(0)
		}, completion: finish)
	}
}
