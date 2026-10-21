import XCTest
@testable import RhythmX

/// The two links App Review expects next to any auto-renewing subscription purchase button.
/// App Store Connect must carry the same two URLs.
final class LegalLinksTests: XCTestCase {

    func testTermsIsAppleStandardEULA() {
        XCTAssertEqual(LegalLinks.termsOfUse.absoluteString,
                       "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        XCTAssertEqual(LegalLinks.termsLabel, "Terms of Use (EULA)")
    }

    func testPrivacyPolicyURL() {
        XCTAssertEqual(LegalLinks.privacyPolicy.absoluteString, "https://shapehaveninnovations.com/privacy.html")
        XCTAssertEqual(LegalLinks.privacyLabel, "Privacy Policy")
    }

    func testBothLinksAreHTTPS() {
        for url in [LegalLinks.termsOfUse, LegalLinks.privacyPolicy] {
            XCTAssertEqual(url.scheme, "https", url.absoluteString)
            XCTAssertNotNil(url.host, url.absoluteString)
        }
    }
}
