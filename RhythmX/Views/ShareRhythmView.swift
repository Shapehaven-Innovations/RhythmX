//  ShareRhythmView.swift

import SwiftUI

struct ShareRhythmView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var appSettings: AppSettings

    @State private var shareError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Your name").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                    TextField("Your name", text: $appSettings.sharerName)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Phases to share").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                    if phaseRanges.isEmpty {
                        Text("No active cycle to share. Start a cycle in Cycles first.")
                            .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    } else {
                        ForEach(phaseRanges) { range in
                            PhaseCardHeader(phase: range.phase, startDate: range.start, endDate: range.end)
                        }
                    }
                }
                .cardStyle()
            }
            .padding(DS.Spacing.md)
        }
        .themedPage()
        .navigationTitle("Share RhythmX")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Share RhythmX", action: share, isDisabled: phaseRanges.isEmpty)
                .padding(DS.Spacing.md)
                .background(.regularMaterial)
        }
        .alert("Unable to Share", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
    }

    // MARK: - Computed

    private struct PhaseRange: Identifiable {
        let id: Event.EventType
        let phase: Event.EventType
        let start: Date
        let end: Date
    }

    private var phaseRanges: [PhaseRange] {
        Event.EventType.allCases.compactMap { phase in
            let dates = myEvents.cycleEvents
                .filter { $0.eventType == phase }
                .map { $0.date }
            guard let start = dates.min(), let end = dates.max() else { return nil }
            return PhaseRange(id: phase, phase: phase, start: start, end: end)
        }
    }

    // MARK: - Actions

    private func share() {
        let data = ICSExporter.export(events: myEvents.cycleEvents, sharerName: appSettings.sharerName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RhythmX-\(UUID().uuidString).ics")
        do {
            try data.write(to: url)
            presentShareSheet(url: url)
        } catch {
            shareError = error.localizedDescription
        }
    }

    private func presentShareSheet(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(activityVC, animated: true)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ShareRhythmView()
            .environmentObject(EventStore(preview: true))
            .environmentObject(AppSettings())
    }
}
