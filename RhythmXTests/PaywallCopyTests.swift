import StoreKit
import XCTest
@testable import RhythmX

/// Paywall wording and the yearly saving. The strings are the ones App Review and the user see, so they are pinned.
final class PaywallCopyTests: XCTestCase {

    // MARK: Trial wording comes from the introductory offer, never from a constant

    func testTrialLengthFromIntroductoryOfferPeriod() {
        XCTAssertEqual(PaywallCopy.trialLength(value: 3, unit: .day, paymentMode: .freeTrial, eligible: true), "3 days")
        XCTAssertEqual(PaywallCopy.trialLength(value: 1, unit: .day, paymentMode: .freeTrial, eligible: true), "1 day")
        XCTAssertEqual(PaywallCopy.trialLength(value: 1, unit: .week, paymentMode: .freeTrial, eligible: true), "1 week")
        XCTAssertEqual(PaywallCopy.trialLength(value: 2, unit: .week, paymentMode: .freeTrial, eligible: true), "2 weeks")
        XCTAssertEqual(PaywallCopy.trialLength(value: 1, unit: .month, paymentMode: .freeTrial, eligible: true), "1 month")
        XCTAssertEqual(PaywallCopy.trialLength(value: 1, unit: .year, paymentMode: .freeTrial, eligible: true), "1 year")
    }

    func testNoTrialWordingWithoutAFreeTrialTheUserCanGet() {
        // Not eligible (already used the trial on this Apple Account).
        XCTAssertNil(PaywallCopy.trialLength(value: 3, unit: .day, paymentMode: .freeTrial, eligible: false))
        // An introductory price is not a free trial; the paywall must not promise "free".
        XCTAssertNil(PaywallCopy.trialLength(value: 3, unit: .day, paymentMode: .payAsYouGo, eligible: true))
        XCTAssertNil(PaywallCopy.trialLength(value: 3, unit: .day, paymentMode: .payUpFront, eligible: true))
        XCTAssertNil(PaywallCopy.trialLength(value: 0, unit: .day, paymentMode: .freeTrial, eligible: true))
    }

    func testTrialButtonAndHintUseTheOfferLength() {
        XCTAssertEqual(PaywallCopy.trialButton(trial: "3 days"), "Start 3-day free trial")
        XCTAssertEqual(PaywallCopy.trialButton(trial: "1 week"), "Start 1-week free trial")
        XCTAssertEqual(PaywallCopy.trialHint(trial: "3 days"),
                       "Starts the free trial. Billing begins after 3 days unless you cancel.")
    }

    func testFeatureListExact() {
        XCTAssertEqual(PaywallCopy.features, [
            "Unlimited calendar and report PDFs",
            "Blue Moon, Harvest Moon, Eclipse themes",
            "Week Strip and Quick Log widgets",
            "Sync to Apple Calendar"
        ])
    }

    func testYearlyLineUsesPrice() {
        XCTAssertEqual(PaywallCopy.yearlyLine(price: "$9.99", trial: "3 days"), "3 days free, then $9.99 per year")
        XCTAssertEqual(PaywallCopy.yearlyLine(price: "9,99 €", trial: "3 days"), "3 days free, then 9,99 € per year")
    }

    func testSavingPercentComputedFromPrices() {
        XCTAssertEqual(PaywallCopy.savingPercent(monthly: Decimal(string: "1.99")!, yearly: Decimal(string: "9.99")!), 58)
        XCTAssertEqual(PaywallCopy.savingLabel(percent: 58), "Save 58%")
        // No saving, or a yearly price that is not cheaper, shows no badge.
        XCTAssertNil(PaywallCopy.savingPercent(monthly: Decimal(string: "1.00")!, yearly: Decimal(string: "12.00")!))
        XCTAssertNil(PaywallCopy.savingPercent(monthly: Decimal(string: "1.00")!, yearly: Decimal(string: "15.00")!))
        XCTAssertNil(PaywallCopy.savingPercent(monthly: 0, yearly: Decimal(string: "9.99")!))
    }

    func testDisclosureMentionsTrialPriceAndRenewal() {
        XCTAssertEqual(PaywallCopy.renewalDisclosure(price: "$9.99", trial: "3 days"),
                       "Free for 3 days, then $9.99 per year. Renews automatically until you cancel in Settings.")
        let localized = PaywallCopy.renewalDisclosure(price: "9,99 €", trial: "3 days")
        XCTAssertTrue(localized.contains("3 days"), "trial length")
        XCTAssertTrue(localized.contains("9,99 €"), "price from the loaded product")
        XCTAssertTrue(localized.contains("Renews automatically"), "auto-renew statement")
        XCTAssertTrue(localized.contains("cancel"), "how to stop it")
        XCTAssertFalse(localized.contains("$9.99"), "no hardcoded price once the product is loaded")
    }

    /// While the products have not loaded there is no price and no offer to quote, so the fallback states the
    /// renewal rule only. It never carries a price or a trial length that StoreKit has not confirmed.
    func testFallbackDisclosureHasNoPriceAndNoTrialPromise() {
        let fallback = PaywallCopy.renewalDisclosureUnavailable
        XCTAssertEqual(fallback, "The price and any free trial are shown here once prices load. A subscription renews automatically until you cancel in Settings.")
        XCTAssertFalse(fallback.contains("$"))
        XCTAssertFalse(fallback.contains("9.99"))
        XCTAssertFalse(fallback.contains("3 days"))
        XCTAssertTrue(fallback.contains("renews automatically"))
    }

    func testFixedLines() {
        XCTAssertEqual(PaywallCopy.trialButton(trial: "3 days"), "Start 3-day free trial")
        XCTAssertEqual(PaywallCopy.restoreButton, "Restore Purchases")
        XCTAssertEqual(PaywallCopy.dataPromise, "Your data always stays yours, even if you cancel.")
        XCTAssertEqual(PaywallCopy.monthlyLine(price: "$1.99"), "$1.99 per month")
        XCTAssertEqual(PaywallCopy.monthlyButton(price: "$1.99"), "Subscribe for $1.99 per month")
        XCTAssertEqual(PaywallCopy.yearlyLineWithoutTrial(price: "$9.99"), "$9.99 per year")
        XCTAssertEqual(PaywallCopy.yearlyButtonWithoutTrial(price: "$9.99"), "Subscribe for $9.99 per year")
        XCTAssertEqual(PaywallCopy.dayPassLine(price: "$0.99"),
                       "$0.99 unlocks both PDFs until the end of today. No subscription.")
        XCTAssertEqual(PaywallCopy.dayPassButton(price: "$0.99"), "Buy Day Pass for $0.99")
    }

    func testNoEmDashesInCopy() {
        let all = PaywallCopy.features + [
            PaywallCopy.renewalDisclosure(price: "$9.99", trial: "3 days"), PaywallCopy.renewalDisclosureUnavailable,
            PaywallCopy.dataPromise, PaywallCopy.trialButton(trial: "3 days"), PaywallCopy.trialHint(trial: "3 days"),
            PaywallCopy.restoreButton, PaywallCopy.yearlyLine(price: "$9.99", trial: "3 days"), PaywallCopy.monthlyLine(price: "$1.99"),
            PaywallCopy.dayPassLine(price: "$0.99"), PaywallCopy.pendingMessage, PaywallCopy.pricesUnavailable
        ]
        for line in all {
            XCTAssertFalse(line.contains("\u{2014}"), "em dash in: \(line)")
        }
    }
}
