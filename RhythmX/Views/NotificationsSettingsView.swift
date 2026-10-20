//  NotificationsSettingsView.swift
//  The one Notifications section of Settings: Period, Fertile window and Check-ins (with tag reminders).
//  No notification controls live anywhere else.

import SwiftUI

struct NotificationsSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var fertileStore: FertileStore

    @State private var reminders: [LoggingReminder] = ReminderStore.load()
    @State private var permissionDenied = false
    @State private var editing: ReminderDraft?

    private struct ReminderDraft: Identifiable {
        let reminder: LoggingReminder
        let isNew: Bool
        var id: UUID { reminder.id }
    }

    var body: some View {
        Form {
            periodSection
            fertileSection
            checkInsSection
            if permissionDenied {
                Section {
                    Label("Notifications are disabled. Enable them in iOS Settings.", systemImage: "exclamationmark.triangle")
                        .font(DS.Font.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedPage()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { draft in
            ReminderEditorView(reminder: draft.reminder, isNew: draft.isNew) { saved in
                upsert(saved)
            } onDelete: {
                remove(id: draft.reminder.id)
            }
        }
    }

    // MARK: - Period

    private var periodSection: some View {
        Section {
            Toggle("Period reminders", isOn: $appSettings.notificationsEnabled)
                .tint(DS.Color.accent)
                .onChange(of: appSettings.notificationsEnabled) { _, enabled in
                    if enabled {
                        ensurePermission(onDenied: { appSettings.notificationsEnabled = false })
                    } else {
                        NotificationScheduler.cancelAllCycleReminders()
                    }
                }
            if appSettings.notificationsEnabled {
                Toggle("Day before", isOn: $appSettings.notifyDayBefore)
                    .tint(DS.Color.accent)
                    .onChange(of: appSettings.notifyDayBefore) { _, _ in reschedulePeriod() }
                Toggle("Day of", isOn: $appSettings.notifyDayOf)
                    .tint(DS.Color.accent)
                    .onChange(of: appSettings.notifyDayOf) { _, _ in reschedulePeriod() }
            }
        } header: {
            Text("Period")
        } footer: {
            Text("A reminder at 8:00 around the day your next period is expected.")
        }
    }

    // MARK: - Fertile window

    private var fertileSection: some View {
        Section {
            Toggle("Fertile window starts", isOn: $appSettings.fertileStartOn)
                .tint(DS.Color.accent)
                .onChange(of: appSettings.fertileStartOn) { _, on in changed(turnedOn: on) { appSettings.fertileStartOn = false } }
            Toggle("Day of likely ovulation", isOn: $appSettings.fertileOvulationOn)
                .tint(DS.Color.accent)
                .onChange(of: appSettings.fertileOvulationOn) { _, on in changed(turnedOn: on) { appSettings.fertileOvulationOn = false } }
        } header: {
            Text("Fertile window")
        } footer: {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Predictions are estimates and are not birth control.")
                if appSettings.trackingMode == .menopause {
                    Text("These reminders are not scheduled in Menopause mode.")
                }
            }
        }
    }

    // MARK: - Check-ins

    private var daily: Binding<CheckInSetting> {
        Binding(get: { appSettings.dailyCheckIn ?? .defaultDaily }, set: { appSettings.dailyCheckIn = $0 })
    }

    private var weekly: Binding<CheckInSetting> {
        Binding(get: { appSettings.weeklyCheckIn ?? .defaultWeekly }, set: { appSettings.weeklyCheckIn = $0 })
    }

    private var weeklyDay: Binding<Int> {
        Binding(get: { weekly.wrappedValue.singleWeekday }, set: { weekly.wrappedValue.weekdays = [$0] })
    }

    private var checkInsSection: some View {
        Section {
            Toggle("Daily check-in", isOn: daily.isOn).tint(DS.Color.accent)
            if daily.wrappedValue.isOn {
                DatePicker("Time", selection: time(daily), displayedComponents: .hourAndMinute)
                WeekdayPicker(selection: daily.weekdays)
                Text(daily.wrappedValue.weekdays.isEmpty ? "Every day." : "Only on the selected days.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            }

            Toggle("Weekly check-in", isOn: weekly.isOn).tint(DS.Color.accent)
            if weekly.wrappedValue.isOn {
                Picker("Day", selection: weeklyDay) {
                    ForEach(WeekdayPicker.orderedWeekdays, id: \.self) { day in
                        Text(WeekdayPicker.name(day)).tag(day)
                    }
                }
                DatePicker("Time", selection: time(weekly), displayedComponents: .hourAndMinute)
            }

            ForEach(reminders) { reminder in
                reminderRow(reminder)
            }
            .onDelete { offsets in
                let ids = offsets.map { reminders[$0].id }
                ids.forEach(remove(id:))
            }

            Button {
                let mode = appSettings.trackingMode
                editing = ReminderDraft(
                    reminder: LoggingReminder(title: "", hour: 20, minute: 0, weekdays: [],
                                              category: mode.mainCategory, mode: mode, isOn: true),
                    isNew: true
                )
            } label: {
                Label("Add a tag reminder", systemImage: "plus.circle")
            }
        } header: {
            Text("Check-ins")
        } footer: {
            Text("The daily check-in opens the tag form. The weekly check-in opens your patterns. Tag reminders belong to a mode; only the current mode's reminders fire, the others wait until you switch back.")
        }
        .onChange(of: appSettings.dailyCheckInData) { _, _ in
            changed(turnedOn: appSettings.dailyCheckIn?.isOn == true) { daily.wrappedValue.isOn = false }
        }
        .onChange(of: appSettings.weeklyCheckInData) { _, _ in
            changed(turnedOn: appSettings.weeklyCheckIn?.isOn == true) { weekly.wrappedValue.isOn = false }
        }
    }

    private func reminderRow(_ reminder: LoggingReminder) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                editing = ReminderDraft(reminder: reminder, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.displayTitle)
                        .font(DS.Font.label).foregroundColor(DS.Color.primaryText)
                    Text(Self.summary(reminder, currentMode: appSettings.trackingMode))
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits this reminder")

            Toggle("", isOn: Binding(
                get: { reminder.isOn },
                set: { on in
                    var updated = reminder
                    updated.isOn = on
                    upsert(updated)
                }
            ))
            .labelsHidden()
            .tint(DS.Color.accent)
            .accessibilityLabel("\(reminder.displayTitle) reminder")
        }
    }

    static func summary(_ reminder: LoggingReminder, currentMode: TrackingMode) -> String {
        var parts = [WeekdayPicker.timeText(hour: reminder.hour, minute: reminder.minute),
                     WeekdayPicker.daysText(reminder.weekdays),
                     reminder.category.rawValue]
        if reminder.mode != currentMode { parts.append("\(reminder.mode.title) mode") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private func upsert(_ reminder: LoggingReminder) {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index] = reminder
        } else {
            reminders.append(reminder)
        }
        ReminderStore.save(reminders)
        changed(turnedOn: reminder.isOn) {
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                reminders[index].isOn = false
                ReminderStore.save(reminders)
            }
        }
    }

    private func remove(id: UUID) {
        reminders.removeAll { $0.id == id }
        ReminderStore.save(reminders)
        rescheduleAll()
    }

    /// Something was switched on or off: ask for permission when turning on, then reschedule.
    private func changed(turnedOn: Bool, onDenied: @escaping () -> Void) {
        if turnedOn {
            ensurePermission(onDenied: onDenied)
        } else {
            rescheduleAll()
        }
    }

    private func ensurePermission(onDenied: @escaping () -> Void) {
        NotificationScheduler.requestPermissionIfNeeded { granted in
            permissionDenied = !granted
            if granted {
                reschedulePeriod()
                rescheduleAll()
            } else {
                onDenied()
            }
        }
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
        NotificationScheduler.rescheduleAll(events: myEvents.events, overrides: fertileStore.overrides,
                                            settings: appSettings, reminders: reminders)
    }

    private func time(_ setting: Binding<CheckInSetting>) -> Binding<Date> {
        Binding(
            get: { WeekdayPicker.date(hour: setting.wrappedValue.hour, minute: setting.wrappedValue.minute) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updated = setting.wrappedValue
                updated.hour = c.hour ?? 0
                updated.minute = c.minute ?? 0
                setting.wrappedValue = updated
            }
        )
    }
}

// MARK: - Reminder editor

private struct ReminderEditorView: View {
    @State var reminder: LoggingReminder
    let isNew: Bool
    let onSave: (LoggingReminder) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var time: Binding<Date> {
        Binding(
            get: { WeekdayPicker.date(hour: reminder.hour, minute: reminder.minute) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminder.hour = c.hour ?? 0
                reminder.minute = c.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $reminder.title)
                    Picker("Category", selection: $reminder.category) {
                        ForEach(TagCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Mode", selection: $reminder.mode) {
                        ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("Tapping the reminder opens the tag form on this category.")
                }
                Section {
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    WeekdayPicker(selection: $reminder.weekdays)
                    Text(reminder.weekdays.isEmpty ? "Every day." : "Only on the selected days.")
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    Toggle("On", isOn: $reminder.isOn).tint(DS.Color.accent)
                }
                if !isNew {
                    Section {
                        Button("Delete reminder", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .themedPage()
            .navigationTitle(isNew ? "New tag reminder" : "Edit tag reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = reminder
                        if saved.title.trimmingCharacters(in: .whitespaces).isEmpty {
                            saved.title = "Log \(saved.category.rawValue.lowercased())"
                        }
                        onSave(saved)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Weekday picker

/// Seven toggles, Sunday = 1 through Saturday = 7, ordered by the calendar's first weekday.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    static func name(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday - 1]
    }

    static func shortName(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
    }

    static func timeText(hour: Int, minute: Int) -> String {
        date(hour: hour, minute: minute).formatted(date: .omitted, time: .shortened)
    }

    static func daysText(_ weekdays: Set<Int>) -> String {
        if weekdays.isEmpty || weekdays.count == 7 { return "every day" }
        return orderedWeekdays.filter { weekdays.contains($0) }.map(shortName).joined(separator: " ")
    }

    var body: some View {
        FlowLayout(spacing: DS.Spacing.xs) {
            ForEach(Self.orderedWeekdays, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Self.shortName(day))
                        .font(DS.Font.caption.weight(isOn ? .semibold : .regular))
                        .foregroundColor(isOn ? DS.Color.onAccent : DS.Color.primaryText)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, DS.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(isOn ? DS.Color.accent : Color(UIColor.tertiarySystemFill))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.name(day))
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Days")
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
        .environmentObject(EventStore(preview: true))
        .environmentObject(AppSettings())
        .environmentObject(ArchivedDataStore())
        .environmentObject(FertileStore())
}
