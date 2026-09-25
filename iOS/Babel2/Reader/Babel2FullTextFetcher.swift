import UIKit

/// 阅读模式的「全文获取」：包装既有的 ReaderViewExtractor（Shared/ReaderView，一行不改）。
///
/// 提取器在手机本地打开原网页、注入 Mozilla Readability.js 抽出正文，不经过任何服务器、
/// 不需要 key；超时 20 秒。这里只把它的「委托回调」包成可以直接 await 的一次性调用，
/// 并支持取消（页面关闭、用户关掉阅读模式时）。
@MainActor
final class Babel2FullTextFetcher: ArticleExtractorDelegate {
	struct Failure: LocalizedError {
		let underlying: Error?
		var errorDescription: String? { underlying?.localizedDescription ?? "extraction failed" }
	}

	private var extractor: ReaderViewExtractor?
	private var continuation: CheckedContinuation<String, Error>?

	/// 取回全文 HTML。hostView：隐藏网页控件要挂进视图层级才会稳定加载。
	static func fetch(url: URL, hostView: UIView) async throws -> String {
		let fetcher = Babel2FullTextFetcher()
		return try await withTaskCancellationHandler {
			try await fetcher.start(url: url, hostView: hostView)
		} onCancel: {
			Task { @MainActor in fetcher.cancel() }
		}
	}

	private func start(url: URL, hostView: UIView) async throws -> String {
		try await withCheckedThrowingContinuation { continuation in
			guard let extractor = ReaderViewExtractor(url.absoluteString, delegate: self, hostView: hostView) else {
				continuation.resume(throwing: Failure(underlying: nil))
				return
			}
			self.continuation = continuation
			self.extractor = extractor
			extractor.process()
		}
	}

	private func cancel() {
		extractor?.cancel()
		finish(.failure(CancellationError()))
	}

	private func finish(_ result: Result<String, Error>) {
		extractor = nil
		guard let continuation else { return }
		self.continuation = nil
		continuation.resume(with: result)
	}

	// MARK: - ArticleExtractorDelegate

	func articleExtractionDidFail(with error: Error) {
		finish(.failure(Failure(underlying: error)))
	}

	func articleExtractionDidComplete(extractedArticle: ExtractedArticle) {
		guard let content = extractedArticle.content, !content.isEmpty else {
			finish(.failure(Failure(underlying: nil)))
			return
		}
		finish(.success(content))
	}
}
