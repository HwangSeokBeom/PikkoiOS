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
            portOneUserCode: "imp12345678",
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
            portOneUserCode: "imp87654321",
            portOnePg: "html5_inicis",
            portOnePgID: "production-pg",
            portOnePayMethod: "card",
            portOneAppScheme: "pikko",
            paymentTestMode: true
        )

        XCTAssertTrue(configuration.blocksProductionPayment)
        XCTAssertTrue(configuration.shouldShowPaymentWarning)
    }

    func testPortOneUserCodeDiagnosticMarksKnownPlaceholdersInvalid() {
        let placeholderValues = [
            "",
            "placeholder",
            "YOUR_PORTONE_USER_CODE",
            "PORTONE_USER_CODE",
            "$(PORTONE_USER_CODE)",
            "imp00000000",
            "replace_me",
            "missing_or_placeholder",
            "REPLACE_WITH_PORTONE_USER_CODE"
        ]

        for placeholderValue in placeholderValues {
            let configuration = AppConfiguration(
                environment: .development,
                baseURL: URL(string: "http://pickup.sesac.kr:42678/"),
                seSACKey: "test-sesac-key",
                portOneUserCode: placeholderValue,
                portOnePg: "html5_inicis",
                portOnePgID: "INIpayTest",
                portOnePayMethod: "card",
                portOneAppScheme: "pikko",
                paymentTestMode: true
            )

            XCTAssertNil(configuration.portOneUserCode, placeholderValue)
            XCTAssertNotEqual(configuration.portOneUserCodeDiagnostic.state, "valid", placeholderValue)
        }
    }

    func testPortOneUserCodeDiagnosticMarksRealisticUserCodeValid() {
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "http://pickup.sesac.kr:42678/"),
            seSACKey: "test-sesac-key",
            portOneUserCode: "imp12345678",
            portOnePg: "html5_inicis",
            portOnePgID: "INIpayTest",
            portOnePayMethod: "card",
            portOneAppScheme: "pikko",
            paymentTestMode: true
        )

        XCTAssertEqual(configuration.portOneUserCode, "imp12345678")
        XCTAssertEqual(configuration.portOneUserCodeDiagnostic.state, "valid")
        XCTAssertEqual(configuration.portOneUserCodeDiagnostic.source, "AppConfiguration.explicit.PORTONE_USER_CODE")
    }

    func testPortOnePgIDIsOptionalWhenEmpty() {
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "http://pickup.sesac.kr:42678/"),
            seSACKey: "test-sesac-key",
            portOneUserCode: "imp12345678",
            portOnePg: "html5_inicis",
            portOnePgID: "",
            portOnePayMethod: "card",
            portOneAppScheme: "pikko",
            paymentTestMode: true
        )

        XCTAssertNil(configuration.portOnePgID)
        XCTAssertEqual(configuration.portOnePgIDDiagnostic.state, "emptyOptional")
    }

    func testPortOnePgIDPlaceholderDoesNotBlockAsRequiredValue() {
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "http://pickup.sesac.kr:42678/"),
            seSACKey: "test-sesac-key",
            portOneUserCode: "imp12345678",
            portOnePg: "html5_inicis",
            portOnePgID: "REPLACE_WITH_PORTONE_PG_ID",
            portOnePayMethod: "card",
            portOneAppScheme: "pikko",
            paymentTestMode: true
        )

        XCTAssertNil(configuration.portOnePgID)
        XCTAssertEqual(configuration.portOnePgIDDiagnostic.state, "placeholderOptional")
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
