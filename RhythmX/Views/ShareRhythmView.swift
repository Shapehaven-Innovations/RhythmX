//  ShareRhythmView.swift
//  Share RhythmX: pick the day's insight cards (ShareCardModel), see them in the current theme, and send them
//  as 1080 by 1350 images through the iOS share sheet (ShareLink with in-memory PNG data, no files). The full
//  size images are rendered only when Share or the partner view asks for them (`ShareCardItem`), and cached;
//  the thumbnails are plain SwiftUI. The calendar file (.ics) stays as the secondary choice, with cycle data
//  only. Nothing is uploaded.

import SwiftUI

struct ShareRhythmView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var fertileStore: FertileStore
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Screenshots pass a fixed clock and insights; the app uses today and the template's tiles.
    var now: Date? = nil
    var fixedInsights: DailyInsights? = nil
    /// Screenshots open the partner view directly.
    var showsPartnerViewInitially = false

    @State private var cards: [ShareCard] = []
    @State private var selection: Set<ShareCard.Kind> = []
    @State private var selectionTouched = false
    @State private var images: [ShareCardItem] = []
    @State private var showPartnerView = false
    @State private var shareError: String?

    private var palette: Palette {
        colorScheme == .dark ? DS.Theme.current.dark : DS.Theme.current.light
    }

    private var selectedCards: [ShareCard] { cards.filter { selection.contains($0.kind) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                    Text("Cards are made on this iPhone")
                        .font(.subheadline)
                        .foregroundColor(DS.Color.secondaryText)
                    Spacer(minLength: 0)
                    InfoButton(topic: InfoCopy.share)
                }
                .padding(.horizontal, DS.Spacing.md)

                if cards.isEmpty {
                    emptyCard.padding(.horizontal, DS.Spacing.md)
                } else {
                    previews
                    includeList.padding(.horizontal, DS.Spacing.md)
                    Text("Only these cards leave your iPhone. Tags and notes are never included.")
                        .font(.footnote)
                        .foregroundColor(DS.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.Spacing.lg)
                    nameField.padding(.horizontal, DS.Spacing.md)
                    Button { showPartnerView = true } label: {
                        Label("See what they receive", systemImage: "eye")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Color.accent)
                            .frame(minHeight: 44)
                    }
                    .disabled(images.isEmpty)
                    .padding(.horizontal, DS.Spacing.md)
                }
            }
            .padding(.vertical, DS.Spacing.sm)
        }
        .scrollIndicators(.hidden)
        .themedPage()
        .navigationTitle("Share RhythmX")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions }
        .task(id: cardsKey) { reloadCards() }
        .task(id: renderKey) { prepareItems() }
        .sheet(isPresented: $showPartnerView) { PartnerView(images: images) }
        .onAppear { if showsPartnerViewInitially { showPartnerView = true } }
        .alert("Unable to Share", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
    }

    // MARK: - Sections

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Nothing to share yet").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            Text("Start a cycle in Cycles first. Your cards appear here.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var previews: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(cards) { card in
                    let on = selection.contains(card.kind)
                    Button { toggle(card.kind) } label: {
                        ShareCardThumbnail(card: card, palette: palette, width: dynamicTypeSize.isAccessibilitySize ? 220 : 150)
                            .opacity(on ? 1 : 0.45)
                            .overlay(alignment: .topLeading) {
                                checkBadge(on).padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(card.accessibilityDescription)
                    .accessibilityValue(on ? "Included" : "Not included")
                    .accessibilityHint("Includes or leaves out this card")
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, DS.Spacing.sm)
        }
        .contentMargins(.horizontal, DS.Spacing.md, for: .scrollContent)
        .scrollClipDisabled()
    }

    private func checkBadge(_ on: Bool) -> some View {
        ZStack {
            Circle().fill(on ? DS.Color.onAccent : Color.black.opacity(0.18))
            if on {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundColor(DS.Color.accent)
            }
        }
        .frame(width: 24, height: 24)
        .overlay(Circle().strokeBorder(Color.white.opacity(on ? 0 : 0.8), lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    private var includeList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("INCLUDE")
                .font(.footnote.weight(.semibold))
                .tracking(1)
                .foregroundColor(DS.Color.secondaryText)
                .padding(.horizontal, DS.Spacing.sm)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Divider().padding(.leading, 58) }
                    includeRow(card)
                }
            }
            .padding(.vertical, 4)
            .background(CardSurface())
        }
    }

    private func includeRow(_ card: ShareCard) -> some View {
        let on = selection.contains(card.kind)
        return Button { toggle(card.kind) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(on ? DS.Color.accent : Color.clear)
                    Circle().strokeBorder(on ? Color.clear : DS.Color.separator, lineWidth: 1.8)
                    if on {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundColor(DS.Color.onAccent)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.pickerTitle).font(.body).foregroundColor(DS.Color.primaryText)
                    Text(card.pickerSummary).font(.subheadline).foregroundColor(DS.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.pickerTitle). \(card.pickerSummary)")
        .accessibilityValue(on ? "Included" : "Not included")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Name on the cards").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            TextField("Optional", text: $appSettings.sharerName)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .accessibilityLabel("Name on the cards, optional")
        }
        .cardStyle()
    }

    private var actions: some View {
        VStack(spacing: 6) {
            ShareLink(items: images, subject: Text("From RhythmX")) { item in
                SharePreview(item.title, image: Image("ExportLogo"))
            } label: {
                Label(ShareCardModel.shareButtonTitle(count: images.count), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundColor(DS.Color.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(images.isEmpty ? DS.Color.accent.opacity(0.4) : DS.Color.accent))
            }
            .disabled(images.isEmpty)
            .accessibilityHint("Opens the share sheet with the selected cards as images")

            Button(action: shareCalendar) {
                Label("Add to calendar (.ics)", systemImage: "calendar")
                    .font(.headline)
                    .foregroundColor(phaseRanges.isEmpty ? DS.Color.accent.opacity(0.4) : DS.Color.accent)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(phaseRanges.isEmpty)
            .accessibilityHint("Shares your phase days as a calendar file")
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.xs)
        .background(.regularMaterial)
    }

    // MARK: - Data

    private var today: Date { now ?? Date() }

    /// Changes when anything on a card could change.
    private var cardsKey: String {
        var hasher = Hasher()
        for event in myEvents.events { hasher.combine(event.id); hasher.combine(event.tags); hasher.combine(event.date) }
        hasher.combine(archivedDataStore.archivedBlocks.count)
        hasher.combine(appSettings.sharerName)
        hasher.combine(appSettings.trackingModeRaw)
        return "\(Calendar.current.startOfDay(for: today).timeIntervalSince1970)|\(hasher.finalize())"
    }

    private var renderKey: String {
        "\(cards.map(\.accessibilityDescription))|\(selection.map(\.rawValue).sorted())|\(DS.Theme.current.id)|\(colorScheme == .dark)|\(appSettings.sharerName)"
    }

    private func reloadCards() {
        let mode = appSettings.trackingMode
        let facts = InsightFacts.make(events: myEvents.events, archivedBlocks: archivedDataStore.archivedBlocks,
                                      mode: mode, today: today, fertileOverrides: fertileStore.overrides)
        let snapshot = PhaseWidgetSnapshot.make(events: myEvents.events, archived: archivedDataStore.archivedBlocks,
                                                today: today, fertileOverrides: fertileStore.overrides)
        let input = ShareCardInput(mode: mode, insights: fixedInsights ?? TemplateInsightWriter().insights(for: facts),
                                   facts: facts, fertileToday: snapshot.isFertileToday,
                                   fertileStartsIn: snapshot.fertileStartsIn, sharerName: appSettings.sharerName)
        cards = ShareCardModel.cards(for: input)
        let available = Set(cards.map(\.kind))
        selection = selectionTouched ? selection.intersection(available) : ShareCardModel.defaultSelection(cards)
    }

    /// The share list for the selected cards. Nothing is rendered here; each image is made (once, then cached)
    /// when the share sheet or the partner view asks for it.
    private func prepareItems() {
        let palette = palette
        let isDark = colorScheme == .dark
        let themeID = DS.Theme.current.id
        images = selectedCards.map { card in
            ShareCardItem(card: card, palette: palette, isDark: isDark, themeID: themeID,
                          name: appSettings.sharerName, cache: .shared)
        }
    }

    private func toggle(_ kind: ShareCard.Kind) {
        selectionTouched = true
        if selection.contains(kind) { selection.remove(kind) } else { selection.insert(kind) }
    }

    // MARK: - Calendar file (unchanged)

    private struct PhaseRange: Identifiable {
        let id: Event.EventType
        let start: Date
        let end: Date
    }

    private var phaseRanges: [PhaseRange] {
        Event.EventType.allCases.compactMap { phase in
            let dates = myEvents.cycleEvents.filter { $0.eventType == phase }.map { $0.date }
            guard let start = dates.min(), let end = dates.max() else { return nil }
            return PhaseRange(id: phase, start: start, end: end)
        }
    }

    private func shareCalendar() {
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
              let root = windowScene.windows.first?.rootViewController else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(activityVC, animated: true)
    }
}

// MARK: - Partner view

/// What the person they share with receives: the same images, as they arrive. Rendered when this opens.
struct PartnerView: View {
    let images: [ShareCardItem]
    @Environment(\.dismiss) private var dismiss
    @State private var rendered: [(id: String, label: String, image: UIImage)] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    Text("Each card arrives as one image, 1080 by 1350, in your theme. Nothing else is sent.")
                        .font(.subheadline)
                        .foregroundColor(DS.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(rendered, id: \.id) { image in
                        HStack {
                            Image(uiImage: image.image)
                                .resizable()
                                .aspectRatio(4 / 5, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .accessibilityLabel(image.label)
                            Spacer(minLength: 56)
                        }
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.Color.pageBackground.ignoresSafeArea())
            .onAppear {
                rendered = images.compactMap { item in
                    item.renderNow().flatMap(UIImage.init(data:)).map { (item.id, item.card.accessibilityDescription, $0) }
                }
            }
            .navigationTitle("What they receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .tint(DS.Color.accent)
                        .accessibilityLabel("Done")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ShareRhythmView()
            .environmentObject(EventStore(preview: true))
            .environmentObject(ArchivedDataStore())
            .environmentObject(FertileStore())
            .environmentObject(AppSettings())
    }
}
