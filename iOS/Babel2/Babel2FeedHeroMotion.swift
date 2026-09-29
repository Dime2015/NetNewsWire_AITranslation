import CoreGraphics

/// 文章列表页顶部大图收缩的纯计算（MOTION-CONTRACT §11，ADR-027 第 3 步）。不依赖界面，可直接测试。
///
/// 几何：展开 = 安全区 + 169pt，收缩后的窄栏 = 安全区 + 99pt，两者相差 70pt（collapseDistance）。
/// 列表顶部固定留出窄栏高度，最上面再垫 70pt 空白；往上滑 d（0–70）时大图整体上移 d，
/// 所以大图下沿始终贴着列表内容上沿，任何进度下都没有缝。
enum Babel2FeedHeroMotion {
	/// Figma 03A 展开 169pt − 03C 窄栏 99pt。
	static let collapseDistance: CGFloat = 70
	/// Figma 03C「Feed Hero / Compact Sticky」安全区以下 99pt。
	static let compactHeight: CGFloat = 99

	/// pHero = clamp((offsetY − restOffset) / collapseDistance, 0, 1)。
	/// restOffset 是列表停在最顶时的 contentOffset.y（= −adjustedContentInset.top）。
	/// 往下拉过头（回弹）时为 0：大图保持原样。
	static func progress(offsetY: CGFloat, restOffset: CGFloat) -> CGFloat {
		min(max((offsetY - restOffset) / collapseDistance, 0), 1)
	}

	/// 松手后预计停在半路（0 < 进度 < 1）时，改停到最近的一端：不到一半弹回展开，过半收到窄栏。
	/// 预计停在两端以外（完全展开以上、完全收缩以下）时不干预。
	static func settledTargetOffset(proposed: CGFloat, restOffset: CGFloat) -> CGFloat {
		let travel = proposed - restOffset
		guard travel > 0, travel < collapseDistance else { return proposed }
		return restOffset + (travel < collapseDistance / 2 ? 0 : collapseDistance)
	}

	/// 大图里的图与大标题：随进度淡出（标题比图稍快，窄栏标题出现前就让位）。
	static func heroContentAlpha(_ progress: CGFloat) -> CGFloat {
		1 - progress
	}

	static func heroTitleAlpha(_ progress: CGFloat) -> CGFloat {
		max(0, 1 - progress * 1.6)
	}

	/// 窄栏：纸色底随进度变不透明（进度 1 时完全不透明）；小图标与名字在后半程淡入。
	static func compactBackgroundAlpha(_ progress: CGFloat) -> CGFloat {
		progress
	}

	static func compactContentAlpha(_ progress: CGFloat) -> CGFloat {
		min(max((progress - 0.4) / 0.6, 0), 1)
	}

	// MARK: 天幕（ADR-068，没有大图时）

	/// 纹路不随滑动离开，收起后也不变淡，像一直挂在头顶（原 55% → 85% → 100%，2026-09-29 用户真机：收起后太淡）。
	static func skyPatternAlpha(_ progress: CGFloat) -> CGFloat {
		1
	}

	/// 列表顶部的消融带（从安全区顶端量起）：标题下沿（约 82pt）以上完全看不见，往下约 110pt 里逐渐显出。
	/// 窄栏下沿在 99pt，文章在它下面约 90pt 就开始化开（原 66 / 96 / 134，只有约 40pt，2026-09-29 用户真机：化开得不明显）。
	static let skyDissolveStops: [(offset: CGFloat, alpha: CGFloat)] = [(82, 0), (120, 0.2), (160, 0.55), (192, 1)]

	/// 日期段标题滑向窄栏下沿时淡掉（吸顶那一刻为 0），日期改由顶栏右侧显示；distance = 离吸顶位置还有多远。
	static func skyDayHeaderAlpha(distanceToPin distance: CGFloat) -> CGFloat {
		min(max(distance / 40, 0), 1)
	}
}
