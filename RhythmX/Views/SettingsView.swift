//  SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    privacyCard
                    phaseColorsCard
                    notificationsCard
                    linksCard
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.Color.pageBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Privacy
    private var privacyCard: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            MoonPhaseView(phase: .full, color: Color(red: 240/255, green: 179/255, blue: 196/255), isActive: false, size: 32)
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
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color(red: 94/255, green: 38/255, blue: 79/255)))
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
                .foregroundColor(.accentColor)
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
    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Reminders").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            Toggle("Cycle reminders", isOn: $appSettings.notificationsEnabled)
                .tint(DS.Color.accent)
                .onChange(of: appSettings.notificationsEnabled) { _, enabled in
                    handleNotificationToggle(enabled: enabled)
                }
            if appSettings.notificationsEnabled {
                Toggle("Day before", isOn: $appSettings.notifyDayBefore)
                    .tint(DS.Color.accent)
                    .font(DS.Font.label)
                    .onChange(of: appSettings.notifyDayBefore) { _, _ in reschedule() }
                Toggle("Day of", isOn: $appSettings.notifyDayOf)
                    .tint(DS.Color.accent)
                    .font(DS.Font.label)
                    .onChange(of: appSettings.notifyDayOf) { _, _ in reschedule() }
                if notificationsDenied {
                    Label("Notifications are disabled. Enable them in iOS Settings.", systemImage: "exclamationmark.triangle")
                        .font(DS.Font.caption)
                        .foregroundColor(.orange)
                }
            }
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

    // MARK: - Notification helpers
    private func handleNotificationToggle(enabled: Bool) {
        if enabled {
            NotificationScheduler.requestPermissionIfNeeded { granted in
                if granted {
                    notificationsDenied = false
                    reschedule()
                } else {
                    notificationsDenied = true
                    appSettings.notificationsEnabled = false
                }
            }
        } else {
            NotificationScheduler.cancelAllCycleReminders()
        }
    }

    private func reschedule() {
        guard appSettings.notificationsEnabled,
              let predicted = CyclePredictionService.predictedStartDate(from: archivedDataStore.archivedBlocks)
        else { return }
        NotificationScheduler.scheduleCycleReminders(
            for: predicted,
            dayBefore: appSettings.notifyDayBefore,
            dayOf: appSettings.notifyDayOf
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .environmentObject(ArchivedDataStore())
}
