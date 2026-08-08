//
//  NNWAccentTint.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。用户 2026-08-08 第 9 件:**开关和系统控件也要跟着主题色走**。
//
//  ## 病根有两个,而且不是同一个(T40 早就写下的判据)
//
//  **(a) 用了 `Assets.Colors.*` 这类静态色板。**
//  `primaryAccentColor` 是 xcassets 里烘死的陶土红,编译进 app 之后改不了 ——
//  引用它的地方永远是陶土红,和调色板选的颜色对不上。
//  设置页那一排开关的 `onTintColor` 更狠:是**写死在 storyboard 里**指向那个色板的
//  (Settings.storyboard 7 处 + Inspector.storyboard 5 处,已一并删掉,让它们回落到下面的
//  `UISwitch.appearance()`)。
//
//  **(b) 上色写在只跑一次的地方。**
//  `SceneDelegate` 开机时设一次 `window.tintColor` 就再也不管了 ——
//  用户在设置里换个颜色,窗口还是开机那个。所以本文件除了"设",还必须"换色时重设"。
//
//  ## 为什么"设 appearance"和"扫一遍已有的开关"两件都要做
//
//  `UISwitch.appearance()` 只在视图**进入窗口那一刻**生效 —— 它管的是**以后**新建的开关。
//  而换色时屏幕上已经摆着的那些开关早就进过窗口了,不会再被它碰一次,
//  所以要亲自扫一遍现有的窗口给它们重设。**两件事各管一半,少一件就有一半不跟。**
//  (同一个道理在 L119 里以另一种形式记过:烘焙过的东西不会自己跟随,得有人叫它重来。)
//

#if os(iOS)

import UIKit

@MainActor enum NNWAccentTint {

	/// 开机时叫一次(SceneDelegate 里)。**幂等**:每个窗口叫一次都行。
	static func install(in window: UIWindow) {
		applyAppearanceProxies()
		window.tintColor = NNWAccentPalette.live
		observeAccentChangesOnce()
	}

	/// 给"以后新建的"控件定调 —— 只对进入窗口时还没被显式上色的控件生效。
	private static func applyAppearanceProxies() {
		// 开关打开时的底色。⚠️ 用 `live`:它是一个动态 UIColor,解析时才去读当前选的颜色,
		// 所以连"深色模式下亮一档"都一起跟上了。
		UISwitch.appearance().onTintColor = NNWAccentPalette.live
	}

	private static var isObserving = false

	private static func observeAccentChangesOnce() {
		guard !isObserving else { return }
		isObserving = true
		NotificationCenter.default.addObserver(forName: NNWAccentPalette.didChangeNotification,
											   object: nil, queue: .main) { _ in
			MainActor.assumeIsolated { refreshAllWindows() }
		}
	}

	/// 换色之后:窗口重新上色 + 把屏幕上现有的开关逐个重设。
	static func refreshAllWindows() {
		applyAppearanceProxies()
		for scene in UIApplication.shared.connectedScenes {
			guard let windowScene = scene as? UIWindowScene else { continue }
			for window in windowScene.windows {
				// ⚠️ 每次读 `live` 都会造一个**新的** UIColor 实例 —— 正因为对象换了,
				// UIKit 才认为"颜色变了"并把 tintColorDidChange 传下去。
				// 传同一个对象进来它会当成没变,整条链就不动(这类"设了没反应"最难查)。
				window.tintColor = NNWAccentPalette.live
				refreshSwitches(in: window)
			}
		}
	}

	/// 递归把这棵视图树里的开关重设一遍。
	private static func refreshSwitches(in view: UIView) {
		if let toggle = view as? UISwitch {
			toggle.onTintColor = NNWAccentPalette.live
		}
		for subview in view.subviews {
			refreshSwitches(in: subview)
		}
	}
}

#endif
