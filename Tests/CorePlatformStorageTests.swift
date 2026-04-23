import CoreLocation
import XCTest
@testable import Pikko

@MainActor
final class CorePlatformStorageTests: XCTestCase {
    func testAuthorizedFileURLResolverNormalizesRelativeDataPathToAbsoluteV1DataURL() throws {
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
            seSACKey: "test"
        )
        let resolver = AuthorizedFileURLResolver(configuration: configuration)

        let resolvedURL = try resolver.resolveURL(from: "/data/profiles/1746246312955.jpg")

        XCTAssertEqual(
            resolvedURL.absoluteString,
            "http://pickup.sesac.kr:42678/v1/data/profiles/1746246312955.jpg"
        )
    }

    func testRecentSearchStoreStoresDeduplicatedMostRecentTerms() async {
        let store = UserDefaultsStore(userDefaults: makeUserDefaults(suiteName: #function))
        let recentSearchStore = RecentSearchStore(store: store)

        await recentSearchStore.record("Latte", for: "store")
        await recentSearchStore.record("Bagel", for: "store")
        await recentSearchStore.record("latte", for: "store")

        let entries = await recentSearchStore.entries(for: "store")

        XCTAssertEqual(entries, ["latte", "Bagel"])
    }

    func testCartStoreRequiresReplacementWhenDifferentStoreAlreadyBound() {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())

        cartStore.apply(summary: CartSummary(itemCount: 2, subtotalText: "₩12,000"), for: "store-a")

        let decision = cartStore.decisionForUsingCart(with: "store-b")

        XCTAssertEqual(
            decision,
            .replaceRequired(currentStoreID: "store-a", requestedStoreID: "store-b")
        )
    }

    func testSessionStorePersistsDeviceToken() {
        let suiteName = #function
        let userDefaults = makeUserDefaults(suiteName: suiteName)
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let sessionStore = SessionStore(
            tokenStore: InMemoryTokenStore(),
            userDefaultsStore: store
        )

        sessionStore.updateDeviceToken("device-token-123")

        XCTAssertEqual(sessionStore.deviceToken, "device-token-123")
        XCTAssertEqual(store.string(forKey: "session.deviceToken"), "device-token-123")
    }

    private func makeUserDefaults(suiteName: String) -> UserDefaults {
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}

private actor InMemoryTokenStore: TokenStore {
    private var tokens: StoredTokens?

    func loadTokens() async throws -> StoredTokens? {
        tokens
    }

    func saveTokens(_ tokens: StoredTokens) async throws {
        self.tokens = tokens
    }

    func clearTokens() async throws {
        tokens = nil
    }
}
