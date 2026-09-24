import CoreGraphics
import Babel2Core

/// 阅读页「滑动收缩」的纯计算规则（不依赖界面，方便自动化测试）。
///
/// 所有量都用「已滚动距离」表示：0 = 刚进文章时的位置，往下读越多数值越大。
/// 公式来自 MOTION-CONTRACT.md 第 9 节：
/// - 收缩进度 pCollapse = clamp((已滚动 − 收缩起点) / 收缩距离, 0, 1)
/// - 阅读进度 pReading  = clamp((已滚动 − 收缩起点) / (最大可滚动 − 收缩起点), 0, 1)
/// - 只有「最大可滚动 > 收缩起点」的文章才会收缩；短文永远保持展开（Figma 04D1）
struct Babel2ReaderChromeProgress: Equatable {
	/// 收缩距离：合同标注为 to-tune（旧实现测得 70pt，不是已批准常数），真机手感不对就调这里。
	static let defaultCollapseDistance: CGFloat = 70

	/// 大标题的上沿开始钻进顶栏时的已滚动距离。
	let collapseStart: CGFloat
	let collapseDistance: CGFloat
	/// 这篇文章最多能滚动多远（随图片加载、正文变长而变化）。
	let maxScroll: CGFloat

	init(collapseStart: CGFloat, collapseDistance: CGFloat = Self.defaultCollapseDistance, maxScroll: CGFloat) {
		self.collapseStart = max(collapseStart, 0)
		self.collapseDistance = collapseDistance
		self.maxScroll = max(maxScroll, 0)
	}

	/// 这篇文章够不够长、能不能进入收缩。
	var isEligible: Bool { maxScroll > collapseStart }

	func pCollapse(scrolled: CGFloat) -> CGFloat {
		guard isEligible, collapseDistance > 0 else { return 0 }
		return Self.clamp((scrolled - collapseStart) / collapseDistance)
	}

	func pReading(scrolled: CGFloat) -> CGFloat {
		guard isEligible else { return 0 }
		return Self.clamp((scrolled - collapseStart) / (maxScroll - collapseStart))
	}

	/// 对应运动合同里的状态名，用于性能打点。
	static func state(pCollapse: CGFloat) -> MotionReaderChromeState {
		if pCollapse <= 0 { return .expanded }
		if pCollapse >= 1 { return .compactPinned }
		return .collapsing
	}

	private static func clamp(_ value: CGFloat) -> CGFloat {
		guard value.isFinite else { return 0 }
		return min(max(value, 0), 1)
	}
}
