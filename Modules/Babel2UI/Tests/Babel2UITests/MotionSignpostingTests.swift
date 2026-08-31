import Foundation
import Testing
@testable import Babel2Core

@Suite struct MotionSignpostingTests {
	@Test func eventCarriesAllContractFields() {
		let route = MotionRouteIdentity(id: "reader", generation: 4)
		let oldToken = MotionInteractionToken(interaction: .navigationPop, route: route, sequence: 1)
		let newToken = MotionInteractionToken(interaction: .readerToBrowser, route: route, sequence: 2)
		let event = MotionSignpostEvent(
			baseName: .interrupt,
			interaction: .readerToBrowser,
			route: route,
			recognizer: "right-edge",
			token: newToken,
			oldToken: oldToken,
			newToken: newToken,
			progress: .half,
			sampledProgress: .quarter,
			projectedProgress: .threeQuarters,
			duration: 0.18,
			outcome: .finished
		)
		#expect(event.route == route)
		#expect(event.recognizer == "right-edge")
		#expect(event.oldToken == oldToken)
		#expect(event.newToken == newToken)
		#expect(event.sampledProgress == .quarter)
		#expect(event.projectedProgress == .threeQuarters)
		#expect(event.duration == 0.18)
		#expect(event.outcome == .finished)
		#expect(event.intent == .readerToBrowser)
		#expect(event.diagnosticPayload.contains("route=reader"))
		#expect(event.diagnosticPayload.contains("routeGeneration=4"))
		#expect(event.diagnosticPayload.contains("recognizer=right-edge"))
		#expect(event.diagnosticPayload.contains("sampledProgress=0.25"))
		#expect(event.diagnosticPayload.contains("projectedProgress=0.75"))
		#expect(event.diagnosticPayload.contains("oldToken=\(MotionInteractionID.navigationPop.rawValue):reader:4:1"))
		#expect(event.diagnosticPayload.contains("newToken=\(MotionInteractionID.readerToBrowser.rawValue):reader:4:2"))
	}

	@Test func allContractSignpostNamesAreStable() {
		#expect(MotionSignpostName.allCases.count == 10)
		#expect(MotionSignpostName.begin.rawValue == "Babel2.Motion.Begin")
		#expect(MotionSignpostName.interrupt.rawValue == "Babel2.Motion.Interrupt")
		#expect(MotionSignpostName.libraryFilter.rawValue == "Babel2.Library.Filter")
		#expect(MotionSignpostName.webPrepared.rawValue == "Babel2.Web.Prepared")
		#expect(MotionSignpostName.loadingOwner.rawValue == "Babel2.Loading.Owner")
	}

	@Test func typedPayloadPreservesSurfaceSemantics() {
		let route = MotionRouteIdentity(id: "reader", generation: 2)
		let token = MotionInteractionToken(interaction: .readerToBrowser, route: route, sequence: 4)
		let chrome = MotionSignpostEvent(
			payload: .readerChrome(.init(state: .collapsing, pCollapse: .quarter, barP: .half))
		)
		let pager = MotionSignpostEvent(
			payload: .readerPager(.init(previousID: "a", currentID: "b", nextID: "c", progress: .threeQuarters))
		)
		let hero = MotionSignpostEvent(
			payload: .feedHero(.init(pHero: .half, imageReady: true))
		)
		let filter = MotionSignpostEvent(
			payload: .libraryFilter(.init(fromFilter: .unread, toFilter: .starred, pFilter: .quarter, token: token))
		)
		let web = MotionSignpostEvent(
			payload: .webPrepared(.init(routeToken: token, preparation: .warm))
		)
		let loading = MotionSignpostEvent(
			payload: .loading(.init(surface: .translation, owner: .translationSkeleton, state: .active))
		)
		#expect(chrome.name == .readerChrome)
		#expect(pager.name == .readerPager)
		#expect(hero.name == .feedHero)
		#expect(filter.name == .libraryFilter)
		#expect(web.name == .webPrepared)
		#expect(loading.name == .loadingOwner)
		#expect(chrome.typedPayload == .readerChrome(.init(state: .collapsing, pCollapse: .quarter, barP: .half)))
		#expect(pager.typedPayload == .readerPager(.init(previousID: "a", currentID: "b", nextID: "c", progress: .threeQuarters)))
		#expect(hero.typedPayload == .feedHero(.init(pHero: .half, imageReady: true)))
		#expect(filter.typedPayload == .libraryFilter(.init(fromFilter: .unread, toFilter: .starred, pFilter: .quarter, token: token)))
		#expect(web.typedPayload == .webPrepared(.init(routeToken: token, preparation: .warm)))
		#expect(loading.diagnosticPayload.contains("typedPayload=loading(surface:translation,owner:translationSkeleton,state:active)"))
		#expect(filter.diagnosticPayload.contains("typedPayload=libraryFilter(fromFilter:unread,toFilter:starred,pFilter:0.25,token:reader.browser:reader:2:4)"))
	}

	@Test func mismatchedNameAndPayloadAreRejected() {
		#expect(MotionSignpostEvent(
			name: .readerChrome,
			typedPayload: .loading(.init(surface: .article, owner: .articleSkeleton, state: .started))
		) == nil)
		let valid = MotionSignpostEvent(
			name: .readerChrome,
			typedPayload: .readerChrome(.init(state: .expanded, pCollapse: .zero, barP: .zero))
		)
		#expect(valid?.name == .readerChrome)
		#expect(valid?.typedPayload == .readerChrome(.init(state: .expanded, pCollapse: .zero, barP: .zero)))
	}

	@Test func typedNamesRequirePayloadAndBaseEventsRemainConstructible() {
		let typedNames: [MotionSignpostName] = [
			.readerChrome, .readerPager, .feedHero, .libraryFilter, .webPrepared, .loadingOwner
		]
		for name in typedNames {
			#expect(MotionSignpostEvent(name: name) == nil)
		}
		for name in [MotionSignpostName.begin, .track, .settle, .interrupt] {
			#expect(MotionSignpostEvent(name: name) != nil)
		}
	}
}
