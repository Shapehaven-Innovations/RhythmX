import SwiftUI
import WidgetKit

@main
struct RhythmXWidgetBundle: WidgetBundle {
    var body: some Widget { PhaseWidget() }
}

struct PhaseWidget: Widget {
    let kind = "PhaseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PhaseTimelineProvider()) { entry in
            PhaseWidgetView(entry: entry)
                .containerBackground(DS.Color.pageBackground, for: .widget)
        }
        .configurationDisplayName("Cycle Phase")
        .description("Your current phase, cycle day, and next period.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
