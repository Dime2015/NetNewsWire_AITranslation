//
//  NNWFloatingModeBar.swift
//  NetNewsWire — AI 翻译 fork
//
//  [阅读档][外观] 本 fork 新增(2026-08-05)。把**订阅源列表页(首页)**的三档控件
//  从系统工具栏里搬出来,改成浮在页面之上的一块视图。
//
//  ## 为什么要搬(两个理由,第二个才是真正的目的)
//
//  1. **用户报的缺陷**:iOS 27 真机上「内圈比外圈小很多」。
//     病根是**两把尺子**——27 上外圈由系统的液态玻璃画(它自带内边距、比控件本身高一圈),
//     而内圈还是按**我们自己的**高度往里收 3.5pt 算的。
//     ⚠️ 本来可以去"凑"一个补偿值,但那要按系统版本猜内边距,是负债(L114)。
//     搬出来之后内外都归我们画,两个系统版本渲染一致,这个差**自然消失**,不是凑没的。
//
//  2. **T43 的前置条件**(真正的目的):陀螺仪驱动的边缘反光要求
//     **那圈亮边归我们画**。留在栏里时它归系统,碰不到 —— 搬出来才谈得上做。
//
//  ## 做法照抄文章页 dock(`iOS/Article/NNWFloatingDock.swift`),包括那三条纪律
//
//  - **工具栏这个壳子留着不动**:齿轮和加号仍住在里面,它撑起来的底部安全区、
//    列表的内边距一概不变 —— 我们只是把**中间那一项**挪到它上面去画。
//  - **`toolbarItems` 的结构反而变干净了**:原来我们往里插了 [控件][空白] 两项,
//    现在不插了 → 数组回到故事板原样的 3 项。`expectedItemCount == 3` 那条守卫
//    (CLAUDE.md 点名过)从"被我们撑破"回到"原样满足",风险是**减少**的,不是增加。
//  - **`addNewItemButton` 是 IBOutlet、上游还往它身上挂 menu** —— 全程没碰。
//
//  ## ⚠️ 浮层挂在 **split view controller 的 view** 上(第一、二版都栽在"挂哪"上)
//
//  这一条是三轮探针换来的,别再回头走:
//
//  1. **挂在本页的 view 里**(第一版):画得出来,但 `hitTest` **一次都没被调用**。
//  2. **挂在导航控制器的 view 里、置顶**(第二版):z-order 日志确认我们排在
//     最前(比装工具栏的 `FloatingBarContainerView` 还靠前),点了**仍然零次 `hitTest`**。
//
//  两条合起来只有一个解释:`UILayoutContainerView`(导航控制器的 view,私有类)
//  在 iOS 26 上**自己重写了命中测试** —— 底部栏那片区域的触摸直接路由给栏容器,
//  根本不按 z-order 遍历子视图。在它肚子里怎么置顶都没用。
//  (这也顺带解释了第一版:命中测试在下行到页面层级**之前**就被它截走了。)
//
//  所以挂到**它的上一层**:`self.splitViewController?.view`(公开 API)。
//  上游 iPhone 上就是 split view 收拢成单列的结构(探针链里那两个
//  `_UISplitViewControllerAdaptiveColumn*` 就是它),这一层没有那套定制路由。
//  模态弹层(设置、发现页)走的是**窗口级**的转场容器,天然仍在我们之上,互不影响。
//
//  代价:**它跨页面、跨导航栈共用**,离开首页必须收起来。
//  收起的钩子在 `MainFeedCollectionViewController.viewWillDisappear` ——
//  和文章页 dock 还原工具栏外观(`nnwUseFloatingToolbar(false)`)是同一个位置、同一个理由。
//  ⚠️ iPad 没适配(split 真分栏时控件会按整窗居中,不是按列居中)—— 用户只用 iPhone,记档即可。
//
//  ## ⚠️ 位置:**别拿工具栏当尺子**
//
//  最直觉的写法是量工具栏、或者把约束钉在它身上。两条都不行:
//  · 钉约束 —— 跨过"页面 / 导航控制器"这条边界,转场时会失去公共祖先;
//  · 量它 —— iOS 26 上它的 frame 是整屏、`safeAreaInsets.bottom` 是 0,**量不出东西来**
//    (第一版据此算出的位置偏高了 54pt)。
//
//  可靠的尺子是**窗口自己的安全区**,详见 `layoutSubviews` 里的说明。
//

#if os(iOS)

import UIKit
import ObjectiveC

/// [阅读档] 铺满整页的透明宿主,里面只装那条三档控件。
///
/// ⚠️ **必须重写 `hitTest`**:它铺满整页,不放行的话整个列表都点不动、滑不动了。
/// 只有落在控件自己身上的触摸才收下,其余一律放过去。
@MainActor final class NNWFloatingModeBarHost: UIView {

	let bar: NNWReadingModeBar

	/// 工具栏允许 bar item 的圆盘**探入 Home 条那一段**多少 —— 实测值,iOS 26 与 27 相同。
	///
	/// 本浮层要和左右两颗圆钮(齿轮/加号,它们是真的 bar item)对齐,就得跟着探这么多。
	/// ⚠️ **这是一个实测常量,不是推导值** —— 我没找到 UIToolbar 凭什么这么摆。
	/// 判据:改它之前先重新量一遍三个控件的外接框(办法见 `layoutSubviews` 里的表),
	/// **别凭观感调**。
	private static let nnwBarItemOvershoot: CGFloat = 2

	init(bar: NNWReadingModeBar) {
		self.bar = bar
		super.init(frame: .zero)
		backgroundColor = .clear
		addSubview(bar)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("不从故事板加载") }

	override func layoutSubviews() {
		super.layoutSubviews()

		// ⚠️ **每次排版都确认自己还在最前**(2026-08-05 第二版栽在这:点不动)。
		// 装的时候置过顶,但**导航控制器在转场之后会把工具栏重新提上来** ——
		// 一旦被压回工具栏底下,底部那条的触摸就又被它先拿走了(实测 `hitTest` 一次都不被调用)。
		// 这里是幂等的:已经在最前就什么都不做,所以不会和布局打架。
		if let superview, superview.subviews.last !== self {
			superview.bringSubviewToFront(self)
		}

		let size = bar.intrinsicContentSize

		// 控件要落在**和齿轮 / 加号一模一样的高度**上 —— 搬家前后位置不能变。
		//
		// ⚠️ **别拿工具栏当尺子**(2026-08-05 第一版就栽在这,偏高了 54pt):
		// 实测 iOS 26 上 `navigationController.toolbar.frame` 是 **{0,0,402,874} 整屏**、
		// 它自己的 `safeAreaInsets.bottom` 是 **0** —— 那不是一条"栏"的几何,量不出东西来。
		//
		// 可靠的尺子是**窗口自己的安全区**(= Home 条那 34pt,不含任何栏)。
		// 三档控件和那两颗圆钮**共用同一个直径**(`NNWSoftMaterial.controlDiameter`,
		// 用户 2026-08-05 要求的唯一真源,见 L111),所以高度天然一致。
		//
		// ⚠️ **那个 +overshoot 不是凑数,是量出来的**(2026-08-05 晚,用户看出"三个控件没对齐"):
		// 装上 iOS 27 模拟器后把三个控件的外接框都量了一遍(阈值扫亮边,不靠任何假设的圆心):
		//
		// | | 上缘 | 下缘 | 高 | 中心 |
		// |---|---|---|---|---|
		// | 齿轮 / 加号(bar item) | 802.00 | **841.67** | 39.67 | **821.83** |
		// | 三档(本浮层,改前) | 800.00 | 839.67 | 39.67 | 819.83 |
		//
		// **iOS 26 和 27 上这两组数字完全相同**,所以这不是版本差异,是"工具栏怎么摆 bar item"。
		// 关键发现:bar item 的圆盘下缘 **841.67 > 安全区上沿 840** ——
		// **工具栏允许圆盘略微探入 Home 条那一段**(超出 1.67pt)。
		// 而本浮层老老实实贴着安全区上沿放,于是恒定高 2pt。
		let homeIndicatorInset = window?.safeAreaInsets.bottom ?? 0
		let centerY = bounds.height - homeIndicatorInset + Self.nnwBarItemOvershoot - size.height / 2

		bar.frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(),
						   y: (centerY - size.height / 2).rounded(),
						   width: size.width, height: size.height)

	}

	/// ⚠️ **必须重写**:宿主铺满整屏,不放行的话整页都点不动、滑不动。
	/// 只收下落在控件自己身上的触摸,其余一律放过去(交给底下的工具栏和列表)。
	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		guard !isHidden, alpha > 0.01, bar.frame.contains(point) else { return nil }
		return super.hitTest(point, with: event)
	}
}

extension UIViewController {

	private static var nnwFloatingModeBarHostKey: UInt8 = 0

	/// 本页那块浮层(装过一次之后从关联对象里取;扩展不能加存储属性)。
	var nnwFloatingModeBarHost: NNWFloatingModeBarHost? {
		get { objc_getAssociatedObject(self, &Self.nnwFloatingModeBarHostKey) as? NNWFloatingModeBarHost }
		set { objc_setAssociatedObject(self, &Self.nnwFloatingModeBarHostKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
	}

	/// [阅读档] 把三档控件装成浮层。**幂等** —— `viewWillAppear` 会调很多次。
	///
	/// - Parameter onSelect: 换档回调(和原来走工具栏那条路完全一样)
	func nnwInstallFloatingModeBar(onSelect: @escaping (NNWReadingMode) -> Void) {

		// ⚠️ 挂在 **split view controller 的 view** 上 —— 导航控制器的 view 有定制命中测试,
		// 挂进去拿不到触摸(两版探针的结论,见文件头)。iPhone 上 splitViewController 一定存在;
		// 万一不存在,宁可不装(装一个点不动的控件比不装更糟)。
		guard let container = splitViewController?.view else { return }

		if let host = nnwFloatingModeBarHost, host.superview === container {
			container.bringSubviewToFront(host)		// 每次回到本页都置顶(工具栏可能被重新添加过)
			return
		}

		let bar = nnwReadingModeBar ?? {
			// ⚠️ `drawsOwnTrack: true` —— 搬出栏之后外圈没人替我们画了,见 NNWReadingModeBar 里的说明
			let created = NNWReadingModeBar(drawsOwnTrack: true)
			nnwReadingModeBar = created
			return created
		}()
		bar.onSelect = onSelect

		nnwFloatingModeBarHost?.removeFromSuperview()		// 换过导航控制器时别留下旧的

		let host = NNWFloatingModeBarHost(bar: bar)
		host.translatesAutoresizingMaskIntoConstraints = false
		nnwFloatingModeBarHost = host
		container.addSubview(host)
		NSLayoutConstraint.activate([
			host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			host.topAnchor.constraint(equalTo: container.topAnchor),
			host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
		])

		// ⚠️ 置顶要等这一轮布局跑完再做(文章页 dock 第一版就栽在这:装它的代码比
		// 承载内容的视图早,于是内容那层直接盖在它上面)。
		DispatchQueue.main.async { [weak host, weak container] in
			guard let host, let container, host.superview === container else { return }
			container.bringSubviewToFront(host)
		}
	}

	/// [编辑] 进出原地编辑模式时开关浮层。
	///
	/// 编辑模式下工具栏整条换成 [新建文件夹][移动到…][删除],三档控件不该继续浮在上面
	/// (原来它住在工具栏里,被整条替换时自然就没了;搬出来之后得有人显式收起)。
	func nnwSetFloatingModeBarHidden(_ hidden: Bool) {
		nnwFloatingModeBarHost?.isHidden = hidden
	}
}

#endif
