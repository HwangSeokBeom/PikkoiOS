import XCTest
@testable import Pikko

final class AppConfigurationTests: XCTestCase {
    func testNormalizedBaseURLAcceptsPickupHostWithTrailingSlash() {
        let baseURL = AppConfiguration.normalizedBaseURL(from: "http://pickup.sesac.kr:42678/")

        XCTAssertEqual(baseURL?.absoluteString, "http://pickup.sesac.kr:42678/")
        XCTAssertNil(AppConfiguration.baseURLValidationError(for: "http://pickup.sesac.kr:42678/"))
    }

    func testNormalizedBaseURLAcceptsPickupHostWithoutTrailingSlash() {
        let baseURL = AppConfiguration.normalizedBaseURL(from: "http://pickup.sesac.kr:42678")

        XCTAssertEqual(baseURL?.absoluteString, "http://pickup.sesac.kr:42678")
        XCTAssertNil(AppConfiguration.baseURLValidationError(for: "http://pickup.sesac.kr:42678"))
    }

    func testBaseURLValidationRejectsMissingValue() {
        XCTAssertEqual(AppConfiguration.baseURLValidationError(for: nil), .missingBaseURL)
        XCTAssertNil(AppConfiguration.normalizedBaseURL(from: nil))
    }

    func testBaseURLValidationRejectsRelativeV1Value() {
        XCTAssertEqual(AppConfiguration.baseURLValidationError(for: "v1"), .invalidBaseURL)
        XCTAssertNil(AppConfiguration.normalizedBaseURL(from: "v1"))
    }

    func testBaseURLValidationRejectsPathOnlyV1Value() {
        XCTAssertEqual(AppConfiguration.baseURLValidationError(for: "/v1"), .invalidBaseURL)
        XCTAssertNil(AppConfiguration.normalizedBaseURL(from: "/v1"))
    }

    func testBaseURLValidationRejectsV1Host() {
        XCTAssertEqual(AppConfiguration.baseURLValidationError(for: "http://v1"), .invalidBaseURL)
        XCTAssertNil(AppConfiguration.normalizedBaseURL(from: "http://v1"))
    }

    func testBaseURLValidationRejectsUnresolvedBuildSettingReference() {
        XCTAssertEqual(AppConfiguration.baseURLValidationError(for: "$(PIKKO_BASE_URL)"), .invalidBaseURL)
        XCTAssertNil(AppConfiguration.normalizedBaseURL(from: "$(PIKKO_BASE_URL)"))
    }

    func testBaseURLValidationRejectsAngleBracketPlaceholder() {
        XCTAssertEqual(AppConfiguration.baseURLValidationError(for: "<base_url>"), .invalidBaseURL)
        XCTAssertNil(AppConfiguration.normalizedBaseURL(from: "<base_url>"))
    }

    func testNormalizedBaseURLAcceptsQuotedURLValue() {
        let baseURL = AppConfiguration.normalizedBaseURL(from: "\"http://pickup.sesac.kr:42678/\"")

        XCTAssertEqual(baseURL?.absoluteString, "http://pickup.sesac.kr:42678/")
        XCTAssertNil(AppConfiguration.baseURLValidationError(for: "\"http://pickup.sesac.kr:42678/\""))
    }

    func testAppConfigurationReadsCamelCaseInfoPlistKeys() throws {
        let bundle = try makeBundle(
            infoDictionary: [
                "PIKKOBaseURL": "http://pickup.sesac.kr:42678/",
                "PIKKOSeSACKey": "test-sesac-key",
                "KakaoNativeAppKey": "kakao-key",
                "GoogleIOSClientID": "google-client-id",
                "GoogleReversedClientID": "google-reversed-id"
            ]
        )

        let configuration = AppConfiguration(environment: .development, bundle: bundle)

        XCTAssertEqual(configuration.baseURL?.absoluteString, "http://pickup.sesac.kr:42678/")
        XCTAssertEqual(configuration.baseURLError, nil)
        XCTAssertEqual(configuration.seSACKeyError, nil)
        XCTAssertEqual(configuration.kakaoNativeAppKey, "kakao-key")
        XCTAssertEqual(configuration.googleIOSClientID, "google-client-id")
        XCTAssertEqual(configuration.googleReversedClientID, "google-reversed-id")
    }

    func testAppConfigurationMarksInfoPlistSubstitutionFailureAsInvalid() throws {
        let bundle = try makeBundle(
            infoDictionary: [
                "PIKKOBaseURL": "$(PIKKO_BASE_URL)",
                "PIKKOSeSACKey": "test-sesac-key"
            ]
        )

        let configuration = AppConfiguration(environment: .development, bundle: bundle)

        XCTAssertNil(configuration.baseURL)
        XCTAssertEqual(configuration.baseURLError, .invalidBaseURL)
    }

    func testProductionConfigurationBlocksTestPaymentPG() {
        let configuration = AppConfiguration(
            environment: .production,
            baseURL: URL(string: "http://pickup.sesac.kr:42678/"),
            seSACKey: "test-sesac-key",
            portOneUserCode: "imp_test",
            portOnePg: "html5_inicis",
            portOnePgID: "INIpayTest",
            portOnePayMethod: "card",
            portOneAppScheme: "pikko",
            paymentTestMode: false
        )

        XCTAssertTrue(configuration.blocksProductionPayment)
        XCTAssertTrue(configuration.shouldShowPaymentWarning)
    }

    func testProductionConfigurationBlocksPaymentTestModeEvenWithLivePGID() {
        let configuration = AppConfiguration(
            environment: .production,
            baseURL: URL(string: "http://pickup.sesac.kr:42678/"),
            seSACKey: "test-sesac-key",
            portOneUserCode: "imp_live",
            portOnePg: "html5_inicis",
            portOnePgID: "production-pg",
            portOnePayMethod: "card",
            portOneAppScheme: "pikko",
            paymentTestMode: true
        )

        XCTAssertTrue(configuration.blocksProductionPayment)
        XCTAssertTrue(configuration.shouldShowPaymentWarning)
    }
}

private extension AppConfigurationTests {
    func makeBundle(infoDictionary: [String: Any]) throws -> Bundle {
        let fileManager = FileManager.default
        let bundleURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")

        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let plistURL = bundleURL.appendingPathComponent("Info.plist")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: infoDictionary,
            format: .xml,
            options: 0
        )
        try plistData.write(to: plistURL)

        guard let bundle = Bundle(url: bundleURL) else {
            XCTFail("Failed to create test bundle at \(bundleURL.path)")
            throw NSError(domain: "AppConfigurationTests", code: 1, userInfo: nil)
        }

        return bundle
    }
}
