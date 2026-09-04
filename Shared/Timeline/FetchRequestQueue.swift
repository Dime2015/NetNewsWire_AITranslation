//
//  FetchRequestQueue.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 6/20/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Foundation

struct FetchRequestQueueCancellationAudit: Equatable {
	let requestsFound: Int
	let cancellationRequested: Bool
	let currentOperationCancellationRequested: Bool
	let currentOperationTaskCompleted: Bool
	let queueDrained: Bool
}

@MainActor final class FetchRequestQueue {
	private var pendingRequests = [FetchRequestOperation]()
	private var currentRequest: FetchRequestOperation?

	var isAnyCurrentRequest: Bool {
		if let currentRequest = currentRequest {
			return !currentRequest.isCanceled
		}
		return false
	}

	var pendingRequestCount: Int {
		pendingRequests.count + (currentRequest == nil ? 0 : 1)
	}

	@discardableResult
	func cancelAllRequests() -> FetchRequestQueueCancellationAudit {
		precondition(Thread.isMainThread)
		let pending = pendingRequests
		let current = currentRequest
		let requestsFound = pending.count + (current == nil ? 0 : 1)

		// Cancel the pending operations as well as the current operation. Pending
		// operations have no task yet; the operation-level method still records
		// the request consistently and prevents a later accidental run.
		pending.forEach { $0.cancel() }
		current?.cancel()
		pendingRequests.removeAll()

		// `FetchRequestOperation.cancel()` synchronously invokes the queue's
		// completion barrier when a task has started. Keep this defensive detach
		// for an operation canceled between queue assignment and task creation;
		// the completion callback is idempotent and cannot reattach it later.
		if let current, currentRequest === current {
			currentRequest = nil
		}

		return FetchRequestQueueCancellationAudit(
			requestsFound: requestsFound,
			cancellationRequested: requestsFound > 0,
			currentOperationCancellationRequested: current?.taskCancellationRequested ?? true,
			currentOperationTaskCompleted: current?.taskDidComplete ?? true,
			queueDrained: currentRequest == nil && pendingRequests.isEmpty
		)
	}

	func add(_ fetchRequestOperation: FetchRequestOperation) {
		precondition(Thread.isMainThread)
		pendingRequests.append(fetchRequestOperation)
		runNextRequestIfNeeded()
	}
}

private extension FetchRequestQueue {

	func runNextRequestIfNeeded() {
		precondition(Thread.isMainThread)
		removeCanceledAndFinishedRequests()
		guard currentRequest == nil, let requestToRun = pendingRequests.first else {
			return
		}

		currentRequest = requestToRun
		pendingRequests.removeFirst()
		currentRequest!.run { (fetchRequestOperation) in
			precondition(fetchRequestOperation === self.currentRequest)
			self.currentRequest = nil
			self.runNextRequestIfNeeded()
		}
	}

	func removeCanceledAndFinishedRequests() {
		pendingRequests = pendingRequests.filter { !$0.isCanceled && !$0.isFinished }
	}
}
