import CoreGraphics

/// 阅读页「顶栏按钮 + 底栏随上下滑显隐」的纯计算规则（不依赖界面，方便自动化测试）。
///
/// 规则来自 MOTION-CONTRACT.md 第 10 节与 Figma INTERACTION-CONTRACT「Direction response after pinning」：
/// - 只有紧凑标题栏已经固定（pCollapse = 1）之后才会隐藏；没固定、或回到顶部时强制显示
/// - 朝同一方向累计滑过 12pt 才开始切换；小于 12pt 的来回抖动一律忽略（防闪烁）
/// - 开始切换后，隐藏程度 barP 跟着手指走：barP += 下滑距离 / hideDistance（0 = 显示，1 = 隐藏）
/// - 到底时的橡皮筋回弹不算数
/// - 松手后若停在半路，由界面用 180ms 匀速走完到最近的一端（见 settleTarget）
struct Babel2ReaderBarVisibility: Equatable {
	/// 方向判定门槛：Figma 合同 reference 值。
	static let directionThreshold: CGFloat = 12
	/// 从完全显示到完全隐藏需要的滑动距离：合同标注 to-tune，真机手感不对就调这里。
	static let hideDistance: CGFloat = 60
	/// 松手补完动画时长：Figma reference。
	static let settleDuration: Double = 0.18

	private(set) var barP: CGFloat = 0
	/// 当前方向上累计的滑动距离（下滑为正、上滑为负）。
	private var accumulator: CGFloat = 0
	/// 是否已越过 12pt 门槛、正在跟手。
	private(set) var isTracking = false

	/// 每次滚动位置变化时调用。
	/// - delta: 本次滚动的变化量（下滑为正）
	/// - isPinned: 紧凑标题栏是否已固定
	/// - isBottomOverscroll: 是否处于到底后的橡皮筋回弹区
	mutating func update(delta: CGFloat, isPinned: Bool, isBottomOverscroll: Bool) {
		guard isPinned else {
			// 没固定（包括回到顶部）→ 强制显示
			forceShown()
			return
		}
		guard !isBottomOverscroll, delta != 0, delta.isFinite else { return }

		if accumulator != 0, (delta > 0) != (accumulator > 0) {
			// 方向反转：从零重新累计，直到再次越过门槛才动
			accumulator = 0
			isTracking = false
		}
		accumulator += delta

		if isTracking {
			apply(delta)
		} else if abs(accumulator) >= Self.directionThreshold {
			isTracking = true
			// 只把越过门槛的那一部分算进去，避免一越过就跳一下
			let excess = accumulator > 0 ? accumulator - Self.directionThreshold : accumulator + Self.directionThreshold
			apply(excess)
		}
	}

	/// 松手（或惯性滚动停下）后应该补完到哪一端。
	var settleTarget: CGFloat { barP >= 0.5 ? 1 : 0 }

	/// 界面补完动画结束 / 被打断时，把实际停下的位置写回来。
	mutating func settle(at value: CGFloat) {
		barP = min(max(value, 0), 1)
		accumulator = 0
		isTracking = false
	}

	mutating func forceShown() {
		settle(at: 0)
	}

	private mutating func apply(_ delta: CGFloat) {
		barP = min(max(barP + delta / Self.hideDistance, 0), 1)
	}
}
