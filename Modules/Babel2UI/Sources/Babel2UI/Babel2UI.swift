import Foundation

@_exported import Babel2Core

#if canImport(UIKit)
import UIKit
#endif

/// Placeholder for the future UIKit layer. Phase 0 intentionally has no screen
/// or navigation implementation here.
public enum Babel2UI {
	public static var isUIKitAvailable: Bool {
#if canImport(UIKit)
		true
#else
		false
#endif
	}
}
