//
//  LongImagePreviewViewController.swift
//  NetNewsWire — AI 翻译 fork
//
//  [长图] 生成后的预览页(2026-07-24 用户要求:先看一眼,再决定存相册还是分享)。
//  本 fork 新增,上游没有。
//
//  ## ⚠️ 预览用副本,保存/分享用原图
//
//  长图可能高达 2.5 万像素,而系统图层的纹理上限约 1.6 万像素 ——
//  把原图直接塞进 UIImageView,超限的部分会**渲染空白**(不报错,就是白的)。
//  所以预览显示的是降采样副本(上限 1.4 万像素,肉眼几乎无感),
//  「保存到相册」和「分享」用的始终是**原图**,清晰度一点不损失。
//

#if os(iOS)

import UIKit

@MainActor final class LongImagePreviewViewController: UIViewController, UIScrollViewDelegate {

	/// 原图(保存/分享用)
	private let originalImage: UIImage
	/// 预览副本(显示用,超高时降采样)
	private let displayImage: UIImage

	private let scrollView = UIScrollView()
	private let imageView = UIImageView()
	private var saveButton: UIBarButtonItem!

	init(image: UIImage) {
		self.originalImage = image
		self.displayImage = Self.displayCopy(of: image)
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	/// 超过纹理安全线就做一份降采样副本,否则原图直接当预览。
	private static func displayCopy(of image: UIImage) -> UIImage {
		let maxDisplayHeight: CGFloat = 14000
		guard image.size.height * image.scale > maxDisplayHeight else { return image }
		let ratio = maxDisplayHeight / (image.size.height * image.scale)
		let target = CGSize(width: image.size.width * image.scale * ratio,
							height: maxDisplayHeight)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = true
		return UIGraphicsImageRenderer(size: target, format: format).image { _ in
			image.draw(in: CGRect(origin: .zero, size: target))
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "长图预览"
		view.backgroundColor = AppAppearance.paperBackground
		navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close,
														   target: self, action: #selector(closeTapped))

		scrollView.delegate = self
		scrollView.maximumZoomScale = 3
		scrollView.minimumZoomScale = 1
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(scrollView)

		imageView.image = displayImage
		imageView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.addSubview(imageView)

		// 宽度贴合屏幕,高度按比例 —— 长图就该竖着滚
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: view.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

			imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
			imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
			imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
			imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor,
											 multiplier: displayImage.size.height / max(displayImage.size.width, 1))
		])

		// .done 样式 = 加粗强调(.prominent 要 iOS 26 起,工程最低支持 17,不用)
		saveButton = UIBarButtonItem(title: "保存到相册", style: .done,
									 target: self, action: #selector(saveTapped))
		let shareButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"),
										  style: .plain, target: self, action: #selector(shareTapped))
		shareButton.accessibilityLabel = "分享"
		toolbarItems = [
			shareButton,
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
			saveButton
		]
		navigationController?.setToolbarHidden(false, animated: false)
	}

	// MARK: - 动作

	@objc private func closeTapped() {
		dismiss(animated: true)
	}

	@objc private func shareTapped() {
		let share = UIActivityViewController(activityItems: [originalImage], applicationActivities: nil)
		share.popoverPresentationController?.barButtonItem = toolbarItems?.first
		present(share, animated: true)
	}

	@objc private func saveTapped() {
		saveButton.isEnabled = false
		// 存的是**原图**。回调选择器的签名是系统规定的,一个字都不能差,否则运行时崩
		UIImageWriteToSavedPhotosAlbum(originalImage, self,
									   #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
	}

	@objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
		if let error {
			saveButton.isEnabled = true
			// 最常见的失败是没给相册权限 —— 把路径说清楚,别只说"失败"
			let alert = UIAlertController(
				title: "保存失败",
				message: "\(error.localizedDescription)\n\n如果是权限问题:设置 → 应用 → \(NNWBrand.displayName) → 照片,允许「添加照片」。",
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "好", style: .default))
			present(alert, animated: true)
			return
		}
		// 成功:按钮变成"已保存",不弹窗打断 —— 用户可能接着还要分享
		saveButton.title = "已保存 ✓"
	}

	// MARK: - 缩放

	func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}

#endif
