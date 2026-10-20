//  SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var purchaseStore: PurchaseStore
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var fertileStore: FertileStore
    @EnvironmentObject var healthSync: HealthSync
    @EnvironmentObject var calendarSync: CalendarSync
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showManageSubscriptions = false
    @State private var healthDenied = false
    @State private var calendarDenied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    privacyCard
                    plusCard
                    appearanceCard
                    phaseColorsCard
                    notificationsCard
                    healthCard
                    calendarCard
                    yourDataCard
                    linksCard
                }
                .padding(DS.Spacing.md)
            }
            .themedPage()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: appSettings.colorSignature) { _, _ in AppGroup.reloadWidgets() }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
    }

    // MARK: - Plus
    /// Under the privacy card. Opens the single paywall (the root sheet driven by
    /// `PurchaseStore.isPaywallPresented`, shared with the widget's paywall link); once Plus is active it shows
    /// the state and the system subscription management sheet. The Terms and Privacy links are always visible here.
    private var plusCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(PaywallCopy.title).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                Spacer()
                if purchaseStore.isPlus {
                    Text("Active").font(DS.Font.caption.weight(.semibold)).foregroundColor(DS.Color.accent)
                }
            }
            Text(purchaseStore.isPlus
                 ? PaywallCopy.alreadyPlus
                 : "Unlimited PDFs, three extra themes, two extra widgets and Apple Calendar sync.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if purchaseStore.isPlus {
                Button("Manage subscription") { showManageSubscriptions = true }
                    .font(DS.Font.label.weight(.semibold)).foregroundColor(DS.Color.accent)
                    .padding(.vertical, DS.Spacing.xs)
                    .accessibilityHint("Opens the App Store subscription settings")
            } else {
                Button("See Plus") { purchaseStore.isPaywallPresented = true }
                    .font(DS.Font.label.weight(.semibold)).foregroundColor(DS.Color.accent)
                    .padding(.vertical, DS.Spacing.xs)
                    .accessibilityHint("Shows the plans, prices and the free trial")
            }
            Text(PaywallCopy.dataPromise)
                .font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            LegalLinksRow(font: DS.Font.caption, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The Plus card carries the theme: card colour under a wash of the accent, with an accent edge.
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(LinearGradient(colors: [DS.Color.accent.opacity(0.18), DS.Color.accent.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(DS.Color.accent.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Appearance
    /// Theme picker. Blush is free; the three moon themes need Plus. A locked theme opens the paywall and
    /// changes nothing; a Plus theme chosen earlier stays stored and is shown again when Plus is active.
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Appearance").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: DS.Spacing.md) {
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        themeSwatch(.blush)
                        themeSwatch(.blueMoon)
                    }
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        themeSwatch(.harvestMoon)
                        themeSwatch(.eclipse)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    ForEach(AppTheme.all) { themeSwatch($0) }
                }
            }
            if let stored = AppTheme.named(appSettings.themeID), stored.isPlus, !purchaseStore.isPlus {
                Text("\(stored.name) is shown again as soon as RhythmX Plus is active. Blush is used until then.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Phase colors stay the same in every theme.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func themeSwatch(_ theme: AppTheme) -> some View {
        let locked = theme.isPlus && !purchaseStore.isPlus
        let selected = appSettings.themeID == theme.id
        let page = DS.Color.adaptive(light: theme.light.page, dark: theme.dark.page)
        let card = DS.Color.adaptive(light: theme.light.card, dark: theme.dark.card)
        let accent = DS.Color.adaptive(light: theme.light.accent, dark: theme.dark.accent)
        let moon = DS.Color.adaptive(light: theme.light.moon, dark: theme.dark.moon)
        return Button {
            if locked {
                purchaseStore.isPaywallPresented = true
            } else if reduceMotion {
                appSettings.themeID = theme.id
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { appSettings.themeID = theme.id }
            }
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: DS.Radius.chip + 2, style: .continuous)
                        .fill(page)
                        .overlay(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(card)
                                .frame(height: 22)
                                .padding(6)
                                .overlay(alignment: .leading) {
                                    HStack(spacing: 4) {
                                        Circle().fill(accent).frame(width: 10, height: 10)
                                        Circle().fill(moon).frame(width: 10, height: 10)
                                    }
                                    .padding(.leading, 12)
                                }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip + 2, style: .continuous)
                                .stroke(selected ? DS.Color.accent : DS.Color.separator, lineWidth: selected ? 2 : 1)
                        )
                        .frame(height: 56)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(accent)
                            .padding(5)
                    } else if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(accent)
                            .padding(4)
                    }
                }
                Text(theme.name)
                    .font(DS.Font.micro.weight(selected ? .semibold : .regular))
                    .foregroundColor(DS.Color.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                if theme.isPlus {
                    Text("Plus")
                        .font(DS.Font.micro.weight(.semibold))
                        .foregroundColor(DS.Color.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DS.Color.accent.opacity(0.14)))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.isPlus ? "\(theme.name), Plus theme" : theme.name)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityHint(locked ? "Opens RhythmX Plus" : "Applies this theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Privacy
    private var privacyCard: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            MoonPhaseView(phase: .full, color: DS.Color.brandMoon, isActive: false, size: 32)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Private by design")
                    .font(DS.Font.sectionHeader)
                Text("Everything stays on this device. No account. No ads. No tracking.")
                    .font(DS.Font.caption)
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(Color.white)
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Color.brand))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Phase Colors
    private var phaseColorsCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Phase colors").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: DS.Spacing.md) {
                    HStack(alignment: .top) {
                        phaseColorMoon(.menstrual,  "Menstrual",  $appSettings.phaseColor1)
                        phaseColorMoon(.follicular, "Follicular", $appSettings.phaseColor2)
                    }
                    HStack(alignment: .top) {
                        phaseColorMoon(.ovulation,  "Ovulation",  $appSettings.phaseColor3)
                        phaseColorMoon(.luteal,     "Luteal",     $appSettings.phaseColor4)
                    }
                }
            } else {
                HStack(alignment: .top) {
                    phaseColorMoon(.menstrual,  "Menstrual",  $appSettings.phaseColor1)
                    phaseColorMoon(.follicular, "Follicular", $appSettings.phaseColor2)
                    phaseColorMoon(.ovulation,  "Ovulation",  $appSettings.phaseColor3)
                    phaseColorMoon(.luteal,     "Luteal",     $appSettings.phaseColor4)
                }
            }
            Button("Reset to Defaults") { appSettings.resetToDefaults() }
                .font(DS.Font.caption)
                .foregroundColor(DS.Color.accent)
        }
        .cardStyle()
    }

    private func phaseColorMoon(_ phase: Event.EventType, _ label: String, _ hex: Binding<String>) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            ZStack {
                MoonPhaseView(phase: phase.moonPhase, color: appSettings.phaseColor(for: phase), size: 36)
                    .accessibilityHidden(true)
                ColorPicker("\(label) color", selection: Binding(
                    get: { Color(hex: hex.wrappedValue) ?? phase.defaultPhaseColor },
                    set: { hex.wrappedValue = $0.hexString }
                ), supportsOpacity: false)
                .labelsHidden()
                .opacity(0.02)
                .frame(width: 44, height: 44)
                .accessibilityLabel("\(label) color")
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            Text(label).font(DS.Font.micro).foregroundColor(DS.Color.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Notifications
    /// The only place with notification controls: Period, Fertile window and Check-ins live in
    /// NotificationsSettingsView.
    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifications").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                .padding(.bottom, DS.Spacing.xs)
            NavigationLink { NotificationsSettingsView() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Period, fertile window and check-ins")
                            .font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                        Text(notificationsSummary)
                            .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(DS.Font.caption).foregroundColor(DS.Color.tertiaryText)
                }
                .padding(.vertical, DS.Spacing.sm)
            }
        }
        .cardStyle()
    }

    private var notificationsSummary: String {
        let fertile = appSettings.fertileStartOn || appSettings.fertileOvulationOn
        let checkIns = appSettings.dailyCheckIn?.isOn == true || appSettings.weeklyCheckIn?.isOn == true
        func state(_ on: Bool) -> String { on ? "on" : "off" }
        return "Period \(state(appSettings.notificationsEnabled)). Fertile window \(state(fertile)). Check-ins \(state(checkIns))."
    }

    // MARK: - Apple Health
    /// Three independent switches, all off until she turns one on. Each asks Health for its own permission at
    /// that moment and nothing else; a prompt that cannot be shown turns the switch back off.
    private var healthCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Apple Health").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            if healthSync.isAvailable {
                healthToggle("Write period days", isOn: $appSettings.healthWritePeriod, write: true)
                healthToggle("Read temperature", isOn: $appSettings.healthReadTemperature, readTemperature: true)
                healthToggle("Read sleep", isOn: $appSettings.healthReadSleep, readSleep: true)
                Text("Period days are written to Health as menstrual flow, once per day. If you remove a period day here, the entry RhythmX wrote is removed from Health too. Turning off Write period days stops new writes and keeps what is already in Health. Temperature and sleep from Health show in Insights and are offered in the tag form; they are not added to your events. Nothing leaves this device.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if healthDenied {
                    Label("Health did not allow this. You can change it in the Health app under Sharing.", systemImage: "exclamationmark.triangle")
                        .font(DS.Font.caption).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error = healthSync.lastError {
                    Text(error).font(DS.Font.caption).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Apple Health is not available on this device.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            }
        }
        .cardStyle()
    }

    private func healthToggle(_ title: String, isOn: Binding<Bool>,
                              write: Bool = false, readTemperature: Bool = false, readSleep: Bool = false) -> some View {
        Toggle(title, isOn: isOn)
            .font(DS.Font.label).foregroundColor(DS.Color.primaryText)
            .tint(DS.Color.accent)
            .onChange(of: isOn.wrappedValue) { _, on in
                Task { @MainActor in
                    if on {
                        let granted = await healthSync.requestAuthorization(write: write, readTemperature: readTemperature, readSleep: readSleep)
                        healthDenied = !granted
                        if !granted { isOn.wrappedValue = false; return }
                    }
                    await healthSync.refresh(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks, settings: appSettings)
                }
            }
    }

    // MARK: - Apple Calendar (Plus)
    /// One way, into a calendar named "RhythmX". Without Plus the switch opens the paywall and stays off. Turning
    /// it on asks for calendar access first (full access; see CalendarSync.swift for why) and syncs; turning it
    /// off removes every event the app created. When Plus is no longer active the app removes its events and
    /// turns the switch off (`CalendarSync.reconcile`); the card then says sync is a Plus feature.
    private var calendarCard: some View {
        let active = appSettings.calendarSyncOn && purchaseStore.isPlus
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Apple Calendar").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                Spacer()
                if !purchaseStore.isPlus {
                    Text("Plus")
                        .font(DS.Font.micro.weight(.semibold)).foregroundColor(DS.Color.accent)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(DS.Color.accent.opacity(0.14)))
                }
            }
            Toggle("Sync to Apple Calendar", isOn: Binding(get: { active }, set: { calendarSyncSwitched($0) }))
                .font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                .tint(DS.Color.accent)
                .accessibilityHint(purchaseStore.isPlus ? "Adds your cycle to a calendar named RhythmX" : "Opens RhythmX Plus")
            if !purchaseStore.isPlus {
                Text("Calendar sync is a Plus feature.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if active {
                calendarOptionToggle("Period days", $appSettings.calendarSyncPeriodDays)
                calendarOptionToggle("Predicted period", $appSettings.calendarSyncPredictedPeriod)
                calendarOptionToggle("Fertile window", $appSettings.calendarSyncFertileWindow)
                calendarOptionToggle("Phase starts", $appSettings.calendarSyncPhaseStarts)
                calendarOptionToggle("Discreet titles", $appSettings.calendarSyncDiscreet)
                if appSettings.calendarSyncDiscreet {
                    calendarSymbolField("Period", default: DiscreetSymbols.defaultPeriod, $appSettings.calendarSyncSymbolPeriod)
                    calendarSymbolField("Fertile window", default: DiscreetSymbols.defaultFertileWindow, $appSettings.calendarSyncSymbolFertile)
                    calendarSymbolField("Phase start", default: DiscreetSymbols.defaultPhaseStart, $appSettings.calendarSyncSymbolPhase)
                }
                Text(appSettings.calendarSyncDiscreet
                     ? "Discreet titles show only your symbols, for a calendar you share with someone else. Use 1 or 2 letters or digits, or one emoji. Leave a symbol blank to use the default."
                     : "Discreet titles use short symbols, for a calendar you share with someone else.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("One way, into a calendar named RhythmX that iCloud carries to your other devices. Turning this off removes every event RhythmX added. RhythmX asks for full calendar access because Apple Calendar only lets an app create its own calendar and update or remove its events at that level; RhythmX reads and writes only the RhythmX calendar. Nothing leaves this device.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if calendarDenied {
                Label("Calendar access was not allowed. You can change it in iOS Settings under Privacy, Calendars.", systemImage: "exclamationmark.triangle")
                    .font(DS.Font.caption).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = calendarSync.lastError {
                Text(error).font(DS.Font.caption).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func calendarOptionToggle(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(DS.Font.label).foregroundColor(DS.Color.primaryText)
            .tint(DS.Color.accent)
            .onChange(of: isOn.wrappedValue) { _, _ in Task { await resyncCalendar() } }
    }

    /// One discreet symbol. What is typed is cleaned as it is typed (at most 2 letters or digits, or one emoji);
    /// blank shows and uses the default. A change resyncs, which replaces the events that carry the old symbol.
    private func calendarSymbolField(_ title: String, default fallback: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
            Spacer()
            TextField(fallback, text: text)
                .font(DS.Font.label)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(minWidth: 44, maxWidth: 64)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).stroke(DS.Color.secondaryText.opacity(0.4)))
                .accessibilityLabel("\(title) symbol")
                .accessibilityHint("Up to 2 letters or digits, or one emoji. Blank uses \(fallback).")
        }
        .onChange(of: text.wrappedValue) { _, typed in
            let cleaned = DiscreetSymbols.clean(typed)
            if cleaned != typed {
                text.wrappedValue = cleaned
                return   // the cleaned value comes back through this handler and resyncs then
            }
            Task { await resyncCalendar() }
        }
    }

    private func calendarSyncSwitched(_ on: Bool) {
        if on {
            guard purchaseStore.isPlus else {
                purchaseStore.isPaywallPresented = true
                return
            }
            Task { @MainActor in
                let granted = await calendarSync.requestAccess()
                calendarDenied = !granted
                guard granted else { return }
                appSettings.calendarSyncOn = true
                await resyncCalendar()
            }
        } else {
            appSettings.calendarSyncOn = false
            Task { await calendarSync.turnOff(settings: appSettings) }
        }
    }

    private func resyncCalendar() async {
        await calendarSync.reconcile(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                                     overrides: fertileStore.overrides, settings: appSettings,
                                     isPlus: purchaseStore.isPlus,
                                     verified: purchaseStore.entitlementVerifiedThisSession,
                                     withinGrace: purchaseStore.isWithinPlusGrace)
    }

    // MARK: - Your data
    private var yourDataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your data").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                .padding(.bottom, DS.Spacing.xs)
            NavigationLink { BackupView() } label: { linkRow("Backup and restore") }
        }
        .cardStyle()
    }

    // MARK: - Links
    private var linksCard: some View {
        VStack(spacing: 0) {
            NavigationLink { ShareRhythmView() } label: { linkRow("Share RhythmX") }
            Divider()
            NavigationLink { GettingStartedView() } label: { linkRow("How RhythmX works") }
            Divider()
            HStack {
                Text("Version").font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            }
            .padding(.vertical, DS.Spacing.sm)
        }
        .cardStyle()
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title).font(DS.Font.label).foregroundColor(DS.Color.primaryText)
            Spacer()
            Image(systemName: "chevron.right").font(DS.Font.caption).foregroundColor(DS.Color.tertiaryText)
        }
        .padding(.vertical, DS.Spacing.sm)
    }
}

#Preview {
    SettingsView()
        .environmentObject(EventStore(preview: true))
        .environmentObject(AppSettings())
        .environmentObject(ArchivedDataStore())
        .environmentObject(FertileStore())
        .environmentObject(PurchaseStore(listensForUpdates: false))
        .environmentObject(HealthSync())
        .environmentObject(CalendarSync())
}
