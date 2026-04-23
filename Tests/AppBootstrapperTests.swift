import XCTest
@testable import Pikko

@MainActor
final class AppBootstrapperTests: XCTestCase {
    func testBootstrapMovesAppToReadyPhase() async {
        let container = AppDIContainer()
        let appState = container.makeAppState()
        let bootstrapper = container.makeAppBootstrapper(appState: appState)

        await bootstrapper.bootstrapIfNeeded()

        XCTAssertEqual(appState.launchPhase, .ready)
        XCTAssertFalse(appState.sessionStore.isAuthenticated)
        XCTAssertEqual(appState.cartStore.summary, .empty)
    }
}
