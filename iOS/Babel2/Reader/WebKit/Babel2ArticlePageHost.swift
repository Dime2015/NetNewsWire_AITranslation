import UIKit
import WebKit
import Articles

/// 让 Babel 2.0 阅读页成为翻译引擎（Shared/Translation/TranslationController）的「文章页宿主」。
///
/// 翻译引擎只认 `NNWArticlePageHost` 这个接口：给它文章对象（缓存键、标题、原文链接）
/// 和网页控件（它往里注入 translation.js、逐组替换译文）。引擎本身一行不改。
/// 放在这个目录是因为接口里有网页控件类型，而 Babel2 只允许这里出现网页控件（边界测试）。
extension Babel2ArticleViewController: NNWArticlePageHost {
	var nnwHostArticle: Article? { translationHostArticle as? Article }
	var nnwHostWebView: WKWebView? { readerContentView.pageWebView }

	/// 标题译文就位（text）或切回原文（nil）：同步到原生大标题和紧凑栏标题。
	func nnwTranslationTitleDidChange(_ text: String?) {
		applyDisplayedTitle(text)
	}
}
