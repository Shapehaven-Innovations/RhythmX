import WidgetKit

struct PhaseEntry: TimelineEntry {
    let date: Date
    let snapshot: PhaseWidgetSnapshot
}

struct PhaseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhaseEntry {
        PhaseEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhaseEntry) -> Void) {
        let snap = context.isPreview ? PhaseWidgetSnapshot.sample : PhaseWidgetSnapshot.load()
        completion(PhaseEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhaseEntry>) -> Void) {
        let now = Date()
        let entries = PhaseWidgetSnapshot.timeline(from: now, days: 7).map { PhaseEntry(date: $0.date, snapshot: $0.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.startOfDay.diff(numDays: 7))))
    }
}
