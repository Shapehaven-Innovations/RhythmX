//  NotificationsSettingsView.swift
//  The one Notifications page of Settings: Period, Fertile window, Daily insights and Weekly review.
//  No notification controls live anywhere else. On top, a preview of what will actually arrive on the Lock
//  Screen (the scheduler's own text, neutral when Lock Screen privacy is on); then the Lock Screen privacy row,
//  which covers every notification, and one card per group with an icon, a one-line summary
//  (`NotificationsPage`), an info circle (`InfoCopy`) and its controls.

import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var fertileStore: FertileStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Screenshots pass a fixed clock and a permission state; the app reads the real ones.
    var now: Date? = nil
    var forcedPermissionDenied: Bool? = nil

    @State private var permissionDenied = false

    private var today: Date { now ?? Date() }
    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if permissionDenied { deniedBanner }
                previewCard
                Group {
                    privacyGroup
                    periodGroup
                    fertileGroup
                    dailyInsightsGroup
                    weeklyGroup
                }
                .disabled(permissionDenied)
                .opacity(permissionDenied ? 0.6 : 1)
                Text(NotificationsPage.footer)
                    .font(.footnote)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Spacing.md)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
        .scrollIndicators(.hidden)
        .themedPage()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .task { await refreshPermissionState() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPermissionState() } }
        }
        // Period
        .onChange(of: appSettings.notificationsEnabled) { _, enabled in
            if enabled {
                ensurePermission(onDenied: { appSettings.notificationsEnabled = false })
            } else {
                NotificationScheduler.cancelAllCycleReminders()
            }
        }
        .onChange(of: appSettings.notifyDayBefore) { _, _ in reschedulePeriod() }
        .onChange(of: appSettings.notifyDayOf) { _, _ in reschedulePeriod() }
        // Fertile window
        .onChange(of: appSettings.fertileStartOn) { _, on in changed(turnedOn: on) { appSettings.fertileStartOn = false } }
        .onChange(of: appSettings.fertileOvulationOn) { _, on in changed(turnedOn: on) { appSettings.fertileOvulationOn = false } }
        // Daily insights
        .onChange(of: appSettings.dailyInsightsOn) { _, on in
            changed(turnedOn: on, writesInsights: true) { appSettings.dailyInsightsOn = false }
        }
        .onChange(of: appSettings.dailyInsightsHour) { _, _ in rescheduleInsights() }
        .onChange(of: appSettings.dailyInsightsMinute) { _, _ in rescheduleInsights() }
        // Lock Screen privacy covers every notification, so everything is rescheduled with the new text.
        .onChange(of: appSettings.dailyInsightsDiscreet) { _, _ in
            reschedulePeriod()
            rescheduleAll()
            rescheduleInsights()
        }
        // Weekly review
        .onChange(of: appSettings.weeklyCheckInData) { _, _ in
            changed(turnedOn: appSettings.weeklyCheckIn?.isOn == true) { weekly.wrappedValue.isOn = false }
        }
        // A light tick for every switch.
        .sensoryFeedback(.selection, trigger: appSettings.notificationsEnabled)
        .sensoryFeedback(.selection, trigger: appSettings.notifyDayBefore)
        .sensoryFeedback(.selection, trigger: appSettings.notifyDayOf)
        .sensoryFeedback(.selection, trigger: appSettings.fertileStartOn)
        .sensoryFeedback(.selection, trigger: appSettings.fertileOvulationOn)
        .sensoryFeedback(.selection, trigger: appSettings.dailyInsightsOn)
        .sensoryFeedback(.selection, trigger: appSettings.dailyInsightsDiscreet)
        .sensoryFeedback(.selection, trigger: appSettings.weeklyCheckIn?.isOn == true)
    }

    // MARK: - Denied

    private var deniedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.body.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(DS.Color.phase1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Notifications are off").font(.headline).foregroundColor(DS.Color.primaryText)
                Text("Allow them for RhythmX in iPhone Settings to get these.")
                    .font(.subheadline).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Color.onAccent)
                        .padding(.horizontal, DS.Spacing.md)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(DS.Color.accent))
                }
                .padding(.top, DS.Spacing.xs)
                .accessibilityHint("Opens the RhythmX notification settings in iOS Settings")
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                CardSurface()
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Color.phase1.opacity(0.10))
            }
        )
    }

    // MARK: - Preview

    private var todaysInsights: DailyInsights {
        let facts = InsightFacts.make(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                                      mode: appSettings.trackingMode, today: today,
                                      fertileOverrides: fertileStore.overrides)
        return TemplateInsightWriter().insights(for: facts)
    }

    private var previewCard: some View {
        let insight = NotificationsPage.insightPreview(todaysInsights, discreet: appSettings.dailyInsightsDiscreet)
        let insightFire = appSettings.dailyInsights.nextFireDate(after: today)
        let period = appSettings.notificationsEnabled
            ? NotificationsPage.periodPreview(predicted: CyclePredictionService.predictedStartDate(from: archivedDataStore.cycleBlocks),
                                              dayBefore: appSettings.notifyDayBefore, dayOf: appSettings.notifyDayOf,
                                              now: today, discreet: appSettings.dailyInsightsDiscreet)
            : nil
        return VStack(spacing: 10) {
            Text("Next on your Lock Screen")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
                .accessibilityAddTraits(.isHeader)
            notificationBubble(title: insight.title, body: insight.body,
                               when: insightFire.map { NotificationsPage.whenLabel($0, now: today) } ?? "",
                               dimmed: !appSettings.dailyInsightsOn)
            if !appSettings.dailyInsightsOn {
                Text("Daily insights is off. This is what it would send.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
            if let period {
                notificationBubble(title: period.title, body: period.body,
                                   when: NotificationsPage.whenLabel(period.fire, now: today), dimmed: false)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: CardSurface.shadow, radius: 14, x: 0, y: 8)
    }

    /// The night sky of a Lock Screen, the same in every theme so white text always reads.
    private var previewBackground: some View {
        ZStack {
            Color(red: 27 / 255, green: 19 / 255, blue: 40 / 255)
            RadialGradient(colors: [DS.Color.phase4.opacity(0.8), .clear], center: UnitPoint(x: 0.25, y: 0.2),
                           startRadius: 0, endRadius: 220)
            RadialGradient(colors: [Color(red: 94 / 255, green: 38 / 255, blue: 79 / 255).opacity(0.8), .clear],
                           center: UnitPoint(x: 0.85, y: 0.95), startRadius: 0, endRadius: 220)
        }
        .environment(\.colorScheme, .dark)
    }

    private func notificationBubble(title: String, body: String, when: String, dimmed: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image("ExportLogo")
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(when).opacity(0.7)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).fontWeight(.semibold)
                        Text(when).opacity(0.7)
                    }
                }
                Text(body).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        )
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(title), \(when). \(body)")
    }

    // MARK: - Group parts

    private func iconTile(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
            .accessibilityHidden(true)
    }

    /// Icon, title and summary, the info circle and (when the group has one) the switch.
    private func header(symbol: String, color: Color, title: String, summary: String, topic: InfoTopic,
                        isOn: Binding<Bool>?) -> some View {
        let text = VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body).foregroundColor(DS.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary).font(.subheadline).foregroundColor(DS.Color.secondaryText)
                .lineLimit(isAX ? nil : 2)
                .fixedSize(horizontal: false, vertical: isAX)
        }
        .accessibilityElement(children: .combine)

        let toggle = isOn.map { binding in
            Toggle(title, isOn: binding)
                .labelsHidden()
                .tint(DS.Color.accent)
                .accessibilityLabel(title)
                .accessibilityHint(summary)
        }

        return Group {
            if isAX {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: 12) { iconTile(symbol, color: color); Spacer(minLength: 0) }
                    text
                    HStack {
                        InfoButton(topic: topic, compact: false)
                        Spacer()
                        toggle
                    }
                }
            } else {
                HStack(spacing: 12) {
                    iconTile(symbol, color: color)
                    text
                    Spacer(minLength: 4)
                    InfoButton(topic: topic, compact: false)
                    toggle
                }
            }
        }
        .frame(minHeight: 60)
    }

    private func subToggle(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.body).foregroundColor(DS.Color.primaryText)
        }
        .tint(DS.Color.accent)
        .frame(minHeight: 44)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardSurface())
    }

    private var indent: CGFloat { isAX ? 0 : 44 }

    // MARK: - Period

    private var periodGroup: some View {
        group {
            header(symbol: "drop.fill", color: DS.Color.phase1, title: "Period coming up",
                   summary: NotificationsPage.periodSummary(on: appSettings.notificationsEnabled,
                                                            dayBefore: appSettings.notifyDayBefore,
                                                            dayOf: appSettings.notifyDayOf),
                   topic: InfoCopy.periodReminders, isOn: $appSettings.notificationsEnabled)
            if appSettings.notificationsEnabled {
                Divider()
                subToggle("Day before", $appSettings.notifyDayBefore).padding(.leading, indent)
                Divider().padding(.leading, indent)
                subToggle("Day of", $appSettings.notifyDayOf).padding(.leading, indent)
            }
        }
    }

    // MARK: - Fertile window

    private var fertileGroup: some View {
        group {
            header(symbol: "sparkles", color: DS.Color.phase3, title: "Fertile window",
                   summary: NotificationsPage.fertileSummary(startOn: appSettings.fertileStartOn,
                                                             ovulationOn: appSettings.fertileOvulationOn,
                                                             mode: appSettings.trackingMode),
                   topic: InfoCopy.fertileReminders, isOn: nil)
            Divider()
            subToggle("Fertile window starts", $appSettings.fertileStartOn).padding(.leading, indent)
            Divider().padding(.leading, indent)
            subToggle("Day of likely ovulation", $appSettings.fertileOvulationOn).padding(.leading, indent)
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanningInsightsView.disclaimer)
                if appSettings.trackingMode == .menopause {
                    Text("These reminders are not scheduled in Menopause mode.")
                }
            }
            .font(.footnote)
            .foregroundColor(DS.Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, indent)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Daily insights

    private var insightTime: Binding<Date> {
        Binding(
            get: { Weekdays.date(hour: appSettings.dailyInsightsHour, minute: appSettings.dailyInsightsMinute) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                appSettings.dailyInsightsHour = c.hour ?? DailyInsightsSetting.defaultHour
                appSettings.dailyInsightsMinute = c.minute ?? DailyInsightsSetting.defaultMinute
            }
        )
    }

    private var dailyInsightsGroup: some View {
        group {
            header(symbol: "moon.fill", color: DS.Color.phase4, title: "Daily insights",
                   summary: NotificationsPage.dailyInsightsSummary(on: appSettings.dailyInsightsOn,
                                                                   hour: appSettings.dailyInsightsHour,
                                                                   minute: appSettings.dailyInsightsMinute),
                   topic: InfoCopy.dailyInsights, isOn: $appSettings.dailyInsightsOn)
            if appSettings.dailyInsightsOn {
                Divider()
                DatePicker(selection: insightTime, displayedComponents: .hourAndMinute) {
                    Text("Time").font(.body).foregroundColor(DS.Color.primaryText)
                }
                .tint(DS.Color.accent)
                .frame(minHeight: 44)
                .padding(.leading, indent)
            }
        }
    }

    // MARK: - Lock Screen privacy

    /// One switch for every RhythmX notification (stored under its first key, `dailyInsightsDiscreet`).
    private var privacyGroup: some View {
        group {
            header(symbol: "lock.fill", color: Color(UIColor.systemGray), title: InfoCopy.discreetLockScreen.title,
                   summary: NotificationsPage.discreetSummary(on: appSettings.dailyInsightsDiscreet),
                   topic: InfoCopy.discreetLockScreen, isOn: $appSettings.dailyInsightsDiscreet)
        }
    }

    // MARK: - Weekly review

    private var weekly: Binding<CheckInSetting> {
        Binding(get: { appSettings.weeklyCheckIn ?? .defaultWeekly }, set: { appSettings.weeklyCheckIn = $0 })
    }

    private var weeklyDay: Binding<Int> {
        Binding(get: { weekly.wrappedValue.singleWeekday }, set: { weekly.wrappedValue.weekdays = [$0] })
    }

    private var weeklyTime: Binding<Date> {
        Binding(
            get: { Weekdays.date(hour: weekly.wrappedValue.hour, minute: weekly.wrappedValue.minute) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updated = weekly.wrappedValue
                updated.hour = c.hour ?? 0
                updated.minute = c.minute ?? 0
                weekly.wrappedValue = updated
            }
        )
    }

    private var weeklyGroup: some View {
        group {
            header(symbol: "calendar", color: DS.Color.phase2, title: "Weekly review",
                   summary: NotificationsPage.weeklySummary(appSettings.weeklyCheckIn),
                   topic: InfoCopy.weeklyReview, isOn: weekly.isOn)
            if weekly.wrappedValue.isOn {
                Divider()
                LabeledContent {
                    Picker("Day", selection: weeklyDay) {
                        ForEach(Weekdays.ordered, id: \.self) { day in
                            Text(Weekdays.name(day)).tag(day)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(DS.Color.accent)
                } label: {
                    Text("Day").font(.body).foregroundColor(DS.Color.primaryText)
                }
                .frame(minHeight: 44)
                .padding(.leading, indent)
                Divider().padding(.leading, indent)
                DatePicker(selection: weeklyTime, displayedComponents: .hourAndMinute) {
                    Text("Time").font(.body).foregroundColor(DS.Color.primaryText)
                }
                .tint(DS.Color.accent)
                .frame(minHeight: 44)
                .padding(.leading, indent)
            }
        }
    }

    // MARK: - Actions

    /// Something was switched on or off: ask for permission when turning on, then reschedule.
    private func changed(turnedOn: Bool, writesInsights: Bool = false, onDenied: @escaping () -> Void) {
        if turnedOn {
            ensurePermission(writesInsights: writesInsights, onDenied: onDenied)
        } else {
            rescheduleAll()
        }
    }

    private func ensurePermission(writesInsights: Bool = false, onDenied: @escaping () -> Void) {
        NotificationScheduler.requestPermissionIfNeeded { granted in
            permissionDenied = !granted
            if granted {
                reschedulePeriod()
                rescheduleAll()
                if writesInsights { rescheduleInsights() }
            } else {
                onDenied()
            }
        }
    }

    private func refreshPermissionState() async {
        if let forcedPermissionDenied {
            permissionDenied = forcedPermissionDenied
            return
        }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        permissionDenied = status == .denied
    }

    private func reschedulePeriod() {
        guard appSettings.notificationsEnabled else {
            NotificationScheduler.cancelAllCycleReminders()
            return
        }
        guard let predicted = CyclePredictionService.predictedStartDate(from: archivedDataStore.cycleBlocks) else { return }
        NotificationScheduler.scheduleCycleReminders(
            for: predicted,
            dayBefore: appSettings.notifyDayBefore,
            dayOf: appSettings.notifyDayOf
        )
    }

    private func rescheduleAll() {
        NotificationScheduler.rescheduleAll(events: myEvents.events, overrides: fertileStore.overrides, settings: appSettings)
    }

    /// The time or the Lock Screen text changed: the next seven notes are rescheduled and the next one written.
    private func rescheduleInsights() {
        DailyInsightsCoordinator.shared.update(write: true)
    }
}

// MARK: - Weekdays

/// Weekday names and times for the pickers. Sunday = 1 through Saturday = 7, ordered by the calendar's first weekday.
enum Weekdays {
    static var ordered: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    static func name(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday - 1]
    }

    static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
        .environmentObject(EventStore(preview: true))
        .environmentObject(AppSettings())
        .environmentObject(ArchivedDataStore())
        .environmentObject(FertileStore())
}
