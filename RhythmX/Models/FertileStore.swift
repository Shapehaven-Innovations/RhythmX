//  FertileStore.swift

import Foundation

/// Holds the user's manual fertile-window changes; the auto window comes from the logged events.
@MainActor
final class FertileStore: ObservableObject {
    @Published private(set) var overrides: FertileOverrides
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        self.overrides = FertileWindow.loadOverrides(from: defaults)
    }

    func days(events: [Event]) -> Set<String> {
        FertileWindow.days(events: events, overrides: overrides)
    }

    func isFertile(_ date: Date, events: [Event]) -> Bool {
        days(events: events).contains(FertileWindow.dayKey(date))
    }

    func toggle(_ date: Date, events: [Event]) {
        overrides = FertileWindow.toggled(overrides, date: date, autoDays: FertileWindow.autoDays(events: events))
        FertileWindow.saveOverrides(overrides, to: defaults)
    }
}
