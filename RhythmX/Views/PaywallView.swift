//  PaywallView.swift
//
//  The one place Plus is sold. Yearly is pre-selected with its saving over monthly computed from the two
//  loaded prices. The price, the trial length and the auto-renew statement are shown before purchase,
//  with the Terms and Privacy links and Restore Purchases next to the button. The Day Pass card is
//  shown where PDF export opened the paywall.
//
//  Nothing about price or trial is hard-coded: the trial wording comes from the yearly product's
//  introductory offer (period and payment mode) and the account's eligibility for it. No offer, a paid
//  introductory price, or an account that already used the trial means no trial wording at all.

import StoreKit
import SwiftUI

// MARK: - Copy

enum PaywallCopy {
    static let title = "RhythmX Plus"
    static let features = [
        "Unlimited calendar and report PDFs",
        "Blue Moon, Harvest Moon, Eclipse themes",
        "Week Strip and Quick Log widgets",
        "Sync to Apple Calendar"
    ]

    // MARK: Trial length from the introductory offer

    /// "3 days", "1 week", "1 month": the free trial the user can actually get, or nil when there is none to
    /// promise (no free-trial payment mode, a zero period, or an account that is not eligible).
    static func trialLength(value: Int,
                            unit: Product.SubscriptionPeriod.Unit,
                            paymentMode: Product.SubscriptionOffer.PaymentMode,
                            eligible: Bool) -> String? {
        guard eligible, paymentMode == .freeTrial, value > 0 else { return nil }
        let name: String
        switch unit {
        case .day: name = "day"
        case .week: name = "week"
        case .month: name = "month"
        case .year: name = "year"
        @unknown default: return nil
        }
        return "\(value) \(name)\(value == 1 ? "" : "s")"
    }

    static func trialLength(offer: Product.SubscriptionOffer?, eligible: Bool) -> String? {
        guard let offer else { return nil }
        return trialLength(value: offer.period.value, unit: offer.period.unit, paymentMode: offer.paymentMode, eligible: eligible)
    }

    // MARK: Lines

    /// `trial` is a `trialLength` result, e.g. "3 days".
    static func yearlyLine(price: String, trial: String) -> String { "\(trial) free, then \(price) per year" }
    static func yearlyLineWithoutTrial(price: String) -> String { "\(price) per year" }
    static func monthlyLine(price: String) -> String { "\(price) per month" }

    /// "Start 3-day free trial" from "3 days".
    static func trialButton(trial: String) -> String {
        let parts = trial.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "Start free trial" }
        let unit = parts[1].hasSuffix("s") ? String(parts[1].dropLast()) : parts[1]
        return "Start \(parts[0])-\(unit) free trial"
    }
    static func trialHint(trial: String) -> String {
        "Starts the free trial. Billing begins after \(trial) unless you cancel."
    }
    static func yearlyButtonWithoutTrial(price: String) -> String { "Subscribe for \(price) per year" }
    static func monthlyButton(price: String) -> String { "Subscribe for \(price) per month" }
    static let restoreButton = "Restore Purchases"

    /// Shown under the purchase button. Price and trial come from the loaded product.
    static func renewalDisclosure(price: String, trial: String) -> String {
        "Free for \(trial), then \(price) per year. Renews automatically until you cancel in Settings."
    }
    /// Fallback while the products have not loaded: no price and no trial length that StoreKit has not confirmed.
    static let renewalDisclosureUnavailable =
        "The price and any free trial are shown here once prices load. A subscription renews automatically until you cancel in Settings."
    static func renewalDisclosureWithoutTrial(price: String) -> String {
        "\(price) per year. Renews automatically until you cancel in Settings."
    }
    static func monthlyDisclosure(price: String) -> String {
        "\(price) per month. Renews automatically until you cancel in Settings."
    }

    static let dataPromise = "Your data always stays yours, even if you cancel."

    static let dayPassTitle = "Just need a PDF today?"
    static func dayPassLine(price: String) -> String {
        "\(price) unlocks both PDFs until the end of today. No subscription."
    }
    static func dayPassButton(price: String) -> String { "Buy Day Pass for \(price)" }

    static let pendingMessage = "Waiting for approval. Plus turns on as soon as the purchase is approved."
    static let pricesUnavailable = "Prices could not be loaded. Check your connection and try again."
    static let restoredNothing = "No purchase to restore on this Apple Account."
    static let alreadyPlus = "RhythmX Plus is active on this device."

    /// Whole-percent saving of the yearly plan over twelve months of the monthly plan, or `nil` when there is
    /// no saving to show. 1.99 and 9.99 give 58.
    static func savingPercent(monthly: Decimal, yearly: Decimal) -> Int? {
        guard monthly > 0, yearly > 0 else { return nil }
        let annual = monthly * 12
        guard yearly < annual else { return nil }
        let ratio = NSDecimalNumber(decimal: (annual - yearly) / annual).doubleValue
        let percent = Int((ratio * 100).rounded())
        return percent > 0 ? percent : nil
    }

    static func savingLabel(percent: Int) -> String { "Save \(percent)%" }
}

// MARK: - View

struct PaywallView: View {
    enum Plan { case yearly, monthly }

    /// Show the Day Pass card. On when PDF export opened the paywall.
    var showsDayPass = false

    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var plan: Plan = .yearly
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?
    /// The free trial the user can get, e.g. "3 days", from the yearly product's introductory offer and the
    /// account's eligibility (once per Apple Account). Nil until the products load, and nil when there is none.
    @State private var trial: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if purchaseStore.isPlus { activeCard }
                    featureCard
                    if !purchaseStore.isPlus { purchaseCard }
                    if showsDayPass && !purchaseStore.isPlus { dayPassCard }
                    footer
                }
                .padding(DS.Spacing.md)
            }
            .themedPage()
            .navigationTitle(PaywallCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close")
                }
            }
            .task { await loadIfNeeded() }
            .alert("Purchase failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Cards

    private var activeCard: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill").foregroundColor(DS.Color.accent).accessibilityHidden(true)
            Text(PaywallCopy.alreadyPlus).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("What Plus adds").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            ForEach(PaywallCopy.features, id: \.self) { feature in
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                    Image(systemName: "checkmark").font(DS.Font.caption.weight(.semibold))
                        .foregroundColor(DS.Color.accent).accessibilityHidden(true)
                    Text(feature).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                }
            }
            Text("Tracking, insights, backup, Apple Health and all three modes stay free.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .padding(.top, DS.Spacing.xs)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var purchaseCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if let yearly = purchaseStore.yearly, let monthly = purchaseStore.monthly {
                planOption(.yearly, title: "Yearly", line: yearlyLine(yearly), badge: savingBadge(monthly: monthly, yearly: yearly))
                planOption(.monthly, title: "Monthly", line: PaywallCopy.monthlyLine(price: monthly.displayPrice), badge: nil)

                PrimaryButton(title: buttonTitle(yearly: yearly, monthly: monthly), action: purchasePlus, isDisabled: isWorking)
                    .accessibilityHint(plan == .yearly && trial != nil
                                       ? PaywallCopy.trialHint(trial: trial ?? "")
                                       : "Starts the subscription.")

                Text(disclosure(yearly: yearly, monthly: monthly))
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(PaywallCopy.pricesUnavailable).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    SecondaryButton(title: "Try again") { Task { await purchaseStore.loadProducts(); await refreshTrial() } }
                }
                Text(PaywallCopy.renewalDisclosureUnavailable)
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isWorking {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                    Text("Contacting the App Store").font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                }
            }
            if let message {
                Text(message).font(DS.Font.caption).foregroundColor(DS.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Restore and the two legal links sit with the button, never behind a disclosure.
            restoreAndLinks
        }
        .cardStyle()
    }

    private var restoreAndLinks: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Button(PaywallCopy.restoreButton, action: restore)
                .font(DS.Font.label.weight(.semibold))
                .foregroundColor(DS.Color.accent)
                .disabled(isWorking)
                .accessibilityHint("Brings back a Plus subscription bought with this Apple Account")
            LegalLinksRow(font: DS.Font.caption, alignment: .leading)
        }
    }

    private var dayPassCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(PaywallCopy.dayPassTitle).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            if let dayPass = purchaseStore.dayPass {
                Text(PaywallCopy.dayPassLine(price: dayPass.displayPrice))
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if purchaseStore.hasDayPass {
                    Text("Your Day Pass is active until the end of today.")
                        .font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                } else {
                    SecondaryButton(title: PaywallCopy.dayPassButton(price: dayPass.displayPrice), action: purchaseDayPass)
                        .disabled(isWorking)
                        .accessibilityHint("One-time purchase. Ends at midnight tonight.")
                }
            } else {
                Text(PaywallCopy.pricesUnavailable).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            }
        }
        .cardStyle()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(PaywallCopy.dataPromise)
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if purchaseStore.isPlus {
                Button(PaywallCopy.restoreButton, action: restore)
                    .font(DS.Font.caption).foregroundColor(DS.Color.accent)
                    .disabled(isWorking)
                LegalLinksRow(font: DS.Font.caption, alignment: .leading)
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    // MARK: Plan option

    private func planOption(_ option: Plan, title: String, line: String, badge: String?) -> some View {
        let selected = plan == option
        return Button {
            if reduceMotion { plan = option } else { withAnimation(.easeInOut(duration: 0.15)) { plan = option } }
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundColor(selected ? DS.Color.accent : DS.Color.tertiaryText)
                    .accessibilityHidden(true)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(title).font(DS.Font.label.weight(.semibold)).foregroundColor(DS.Color.primaryText)
                        if let badge { badgeView(badge) }
                        Text(line).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.Spacing.sm) {
                            Text(title).font(DS.Font.label.weight(.semibold)).foregroundColor(DS.Color.primaryText)
                            if let badge { badgeView(badge) }
                        }
                        Text(line).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .strokeBorder(selected ? DS.Color.accent : DS.Color.separator, lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(line)." + (badge.map { " \($0)." } ?? ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selected ? "Selected" : "Selects this plan")
    }

    private func badgeView(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.micro.weight(.semibold))
            .foregroundColor(DS.Color.onAccent)
            .padding(.horizontal, DS.Spacing.sm).padding(.vertical, 2)
            .background(Capsule().fill(DS.Color.accent))
    }

    // MARK: Copy helpers

    private func yearlyLine(_ yearly: Product) -> String {
        if let trial { return PaywallCopy.yearlyLine(price: yearly.displayPrice, trial: trial) }
        return PaywallCopy.yearlyLineWithoutTrial(price: yearly.displayPrice)
    }

    private func savingBadge(monthly: Product, yearly: Product) -> String? {
        PaywallCopy.savingPercent(monthly: monthly.price, yearly: yearly.price).map(PaywallCopy.savingLabel)
    }

    private func buttonTitle(yearly: Product, monthly: Product) -> String {
        switch plan {
        case .yearly:
            if let trial { return PaywallCopy.trialButton(trial: trial) }
            return PaywallCopy.yearlyButtonWithoutTrial(price: yearly.displayPrice)
        case .monthly:
            return PaywallCopy.monthlyButton(price: monthly.displayPrice)
        }
    }

    private func disclosure(yearly: Product, monthly: Product) -> String {
        switch plan {
        case .yearly:
            if let trial { return PaywallCopy.renewalDisclosure(price: yearly.displayPrice, trial: trial) }
            return PaywallCopy.renewalDisclosureWithoutTrial(price: yearly.displayPrice)
        case .monthly:
            return PaywallCopy.monthlyDisclosure(price: monthly.displayPrice)
        }
    }

    // MARK: Actions

    private func loadIfNeeded() async {
        if purchaseStore.products.isEmpty { await purchaseStore.loadProducts() }
        await refreshTrial()
    }

    /// The trial wording follows the offer StoreKit reports and the account's eligibility for it.
    private func refreshTrial() async {
        guard let subscription = purchaseStore.yearly?.subscription else {
            trial = nil
            return
        }
        let eligible = await subscription.isEligibleForIntroOffer
        trial = PaywallCopy.trialLength(offer: subscription.introductoryOffer, eligible: eligible)
    }

    private func purchasePlus() {
        run {
            let outcome = try await purchaseStore.purchasePlus(yearly: plan == .yearly)
            handle(outcome)
        }
    }

    private func purchaseDayPass() {
        run {
            let outcome = try await purchaseStore.purchaseDayPass()
            handle(outcome)
        }
    }

    private func restore() {
        run {
            await purchaseStore.restore()
            if purchaseStore.isPlus {
                message = "Plus restored."
                dismiss()
            } else {
                message = PaywallCopy.restoredNothing
            }
        }
    }

    private func handle(_ outcome: PurchaseStore.PurchaseOutcome) {
        switch outcome {
        case .purchased: dismiss()
        case .pending: message = PaywallCopy.pendingMessage
        case .cancelled: break
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            do { try await work() } catch { errorMessage = error.localizedDescription }
        }
    }
}

#Preview {
    PaywallView(showsDayPass: true)
        .environmentObject(PurchaseStore(listensForUpdates: false))
}
