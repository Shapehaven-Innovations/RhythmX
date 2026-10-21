//
//  TagFormView.swift
//  Rhythm
//
//  Created by user on 9/27/24.
//
//  The Add Tags sheet. A glass close button, the title with the day, cycle day and phase (tap it to log
//  another day), a confirm button, then one search over every category, the "For your <phase> phase" row
//  (Smart Tags from past cycles plus the phase picks), Recent, the category strip and the category's body:
//  Symptom rows with a three-step moon strength (crescent light, half medium, full heavy), the Mood glyph
//  grid, the Planning ovulation test strip with its info circle and two toggles, the Basal Temp entry with
//  the Apple Health suggestion, the Menopause counters and strength rows, and chips for the rest.
//  Picked tags collect in the glass tray above "Add N Tags". Logging still goes through EventStore.logTag,
//  one "Category:Value" string at a time, so stored formats and the duplicate rules are unchanged.
//  The pure logic lives in Services/TagFormLogic.swift.

import SwiftUI

// `TagCategory` lives in Models/TagCategory.swift (shared with the widget extension).

struct TagFormView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var healthSync: HealthSync
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var category: TagCategory = .dietary
    /// The typed temperature on the Basal Temp page.
    @State private var customText: String = ""
    @State private var tagDate = Date()
    @State private var selection = TagSelection()
    @State private var query = ""
    @State private var customCategory: TagCategory = .symptom
    @State private var customLevel: TagIntensity?

    /// Smart Tags (archive history for the day's phase, then the category's library), as the form always built them.
    @State private var smartTags: [String] = []
    @State private var didPickInitialCategory = false

    @State private var showDuplicateTagAlert = false
    @State private var duplicateLabels: [String] = []
    @State private var showDatePicker = false
    @State private var showOvulationInfo = false
    @FocusState private var searchFocused: Bool

    /// A category to open on (a notification tap); nil picks the mode's first category.
    private let initialCategory: TagCategory?
    /// Picks to start with (Screenshots and "More tags" from the quick log card).
    private let initialSelection: TagSelection
    private let initialQuery: String

    init(initialDate: Date = Date(), initialCategory: TagCategory? = nil,
         initialSelection: TagSelection = TagSelection(), initialQuery: String = "") {
        _tagDate = State(initialValue: initialDate)
        self.initialCategory = initialCategory
        self.initialSelection = initialSelection
        self.initialQuery = initialQuery
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, DS.Spacing.md)
            searchField
                .padding(.horizontal, DS.Spacing.md)
                .padding(.top, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !dayCanHoldTags { noCycleDayNote }
                        if isSearching {
                            searchResults
                        } else {
                            suggestedRow
                            recentRow
                            categoryStrip(proxy: proxy)
                            categoryBody
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, DS.Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(category, anchor: .center) }
            }
        }
        .safeAreaInset(edge: .bottom) { tray }
        .themedPage()
        .presentationDragIndicator(.visible)
        .alert("Duplicate Tag", isPresented: $showDuplicateTagAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(duplicateLabels.count == 1
                 ? "\(duplicateLabels[0]) already exists for the selected day. Remove it from your picks to save."
                 : "These tags already exist for the selected day: \(duplicateLabels.joined(separator: ", ")). Remove them from your picks to save.")
        }
        .sensoryFeedback(.selection, trigger: selection.totalCount)
        .onAppear {
            if !didPickInitialCategory {
                didPickInitialCategory = true
                category = initialCategory ?? modeCategories.first ?? .dietary
                // Archive-based pre-selection is a cycle habit; other modes start on their own category,
                // and a requested category is kept.
                if appSettings.trackingMode == .cycle && initialCategory == nil,
                   let top = TagFormLogic.topCategory(phase: currentPhaseType, blocks: archivedDataStore.cycleBlocks) {
                    category = top
                }
                selection = initialSelection
                query = initialQuery
                customCategory = TagFormLogic.customCategories(for: mode).first ?? .symptom
            }
            buildSmartTags()
        }
        .onChange(of: tagDate) { _, _ in buildSmartTags() }
        .onChange(of: category) { _, _ in buildSmartTags() }
        // No emoji in typed tags: they are dropped as they are typed.
        .onChange(of: customText) { _, new in
            let clean = TagFormLogic.removingEmoji(new)
            if clean != new { customText = clean }
        }
        .onChange(of: query) { _, new in
            let clean = TagFormLogic.removingEmoji(new)
            if clean != new { query = clean }
        }
    }

    /// "97.8": one decimal, a plain dot, so it round-trips through `PlanningInsights.temperature(from:)`.
    static func temperatureText(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: - State helpers

    private var mode: TrackingMode { appSettings.trackingMode }

    /// The current mode's categories, in the strip. Every category is in the grid menu.
    private var modeCategories: [TagCategory] { TagLibrary.categories(for: mode) }

    /// Every other category, reachable from the grid button.
    private var otherCategories: [TagCategory] { TagCategory.allCases.filter { !modeCategories.contains($0) } }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Phase of the cycle event on the chosen day. Menopause carrier events have no phase.
    private var currentPhaseType: Event.EventType? {
        myEvents.cycleEvents.first { $0.date.startOfDay == tagDate.startOfDay }?.eventType
    }

    /// Cycle and Planning tags need a cycle day to hold them (`EventStore.eventForLogging`); Menopause makes one.
    private var dayCanHoldTags: Bool { TagFormLogic.canHoldTags(on: tagDate, mode: mode, events: myEvents.events) }

    private var dayEvents: [Event] { myEvents.events.filter { $0.date.startOfDay == tagDate.startOfDay } }

    /// Tags already stored on the chosen day.
    private var loggedOnDay: [String] { dayEvents.flatMap { TagParser.split($0.tags) } }

    /// A normal tag already on the day cannot be logged again (`EventStore.isDuplicateTag`).
    private func isAlreadyLogged(_ pick: TagPick) -> Bool {
        !pick.isRepeatable && loggedOnDay.contains(pick.raw)
    }

    private func storedLevel(_ raw: String) -> TagIntensity? {
        dayEvents.lazy.compactMap { $0.intensity(for: raw) }.first
    }

    /// A typed temperature not added to the tray yet; saving includes it, as the form always did.
    private var pendingCustom: TagPick? {
        guard category == .basalTemp else { return nil }
        return TagFormLogic.customPick(category: .basalTemp, text: customText)
    }

    private var pickCount: Int {
        selection.totalCount + (pendingCustom.map { selection.contains($0) ? 0 : 1 } ?? 0)
    }

    private var canSave: Bool { dayCanHoldTags && pickCount > 0 }

    private func animate(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { change() } }
    }

    /// A normal tag toggles; a repeatable one adds another each tap (the tray takes them away again).
    private func tap(_ pick: TagPick) {
        animate {
            if TagFormLogic.isOvulationTest(pick) {
                TagFormLogic.chooseOvulationTest(pick, in: &selection)
            } else if pick.isRepeatable {
                selection.increment(pick)
            } else {
                selection.toggle(pick)
            }
        }
    }

    private func setLevel(_ pick: TagPick, _ level: TagIntensity?) {
        selection.set(pick, level: level)
    }

    // MARK: - Header

    private var dateText: String { tagDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }

    private var subtitle: String {
        TagFormLogic.headerSubtitle(dateText: dateText, cycleDay: TagFormLogic.cycleDay(on: tagDate, events: myEvents.events),
                                    phase: currentPhaseType, mode: mode)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close")

            VStack(spacing: 2) {
                Text("Add Tags")
                    .font(.headline)
                    .foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Button { showDatePicker = true } label: {
                    Text(subtitle)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                    .font(.subheadline)
                    .foregroundColor(DS.Color.secondaryText)
                    .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Day to tag: \(subtitle)")
                .accessibilityHint("Pick another day")
                .popover(isPresented: $showDatePicker) {
                    DatePicker("Day to tag", selection: $tagDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(DS.Color.accent)
                        .padding()
                        .frame(minWidth: 320)
                        .presentationCompactAdaptation(dynamicTypeSize.isAccessibilitySize ? .sheet : .popover)
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: save) {
                Image(systemName: "checkmark").font(.body.weight(.bold)).frame(width: 30, height: 30)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(DS.Color.accent)
            .disabled(!canSave)
            .accessibilityLabel(TagFormLogic.addButtonTitle(count: pickCount))
        }
    }

    private var noCycleDayNote: some View {
        Label("This day is outside your cycle, so tags cannot be saved here. Tap the date to pick another day.",
              systemImage: "calendar.badge.exclamationmark")
            .font(.footnote)
            .foregroundColor(DS.Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundColor(DS.Color.secondaryText).accessibilityHidden(true)
            TextField("Search tags or add your own", text: $query)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($searchFocused)
                .foregroundColor(DS.Color.primaryText)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(DS.Color.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Capsule().fill(DS.Color.primaryText.opacity(0.07)))
    }

    @ViewBuilder
    private var searchResults: some View {
        let outcome = TagFormLogic.searchOutcome(query, mode: mode)
        if let value = outcome.customValue {
            sectionCaption("No tag matches yet")
            customTagCard(value: value)
        }
        ForEach(outcome.groups, id: \.category) { group in
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                sectionCaption(group.category.rawValue)
                VStack(spacing: 0) {
                    let rows = group.values.map { TagPick(category: group.category, value: $0) }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, pick in
                        if index > 0 { Divider().padding(.leading, 58) }
                        searchRow(pick)
                    }
                }
                .padding(.vertical, 4)
                .background(CardSurface())
                .padding(.horizontal, 12)
            }
        }
    }

    private func searchRow(_ pick: TagPick) -> some View {
        HStack(spacing: 12) {
            RowIconSquare(symbol: TagGlyph.symbol(for: pick), color: DS.Color.accent.opacity(0.75))
            Text(pick.value).font(.body).foregroundColor(DS.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            if TagFormLogic.supportsIntensity(pick) {
                MoonIntensityControl(label: pick.value, level: selection.intensity(of: pick)) { setLevel(pick, $0) }
            } else if pick.isRepeatable {
                CountStepper(label: pick.value, count: selection.count(of: pick),
                             onMinus: { animate { selection.decrement(pick) } },
                             onPlus: { animate { selection.increment(pick) } })
            } else {
                let logged = isAlreadyLogged(pick)
                Button { tap(pick) } label: {
                    Image(systemName: logged ? "checkmark.circle" : (selection.contains(pick) ? "checkmark.circle.fill" : "plus.circle"))
                        .font(.title2)
                        .foregroundColor(logged ? DS.Color.secondaryText : DS.Color.accent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(logged)
                .accessibilityLabel(pick.value)
                .accessibilityValue(logged ? "Already logged for this day" : (selection.contains(pick) ? "Picked" : ""))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
    }

    private func customTagCard(value: String) -> some View {
        let pick = TagPick(category: customCategory, value: value)
        let rated = TagFormLogic.supportsIntensity(pick)
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                animate {
                    if rated, let customLevel { selection.set(pick, level: customLevel) } else { selection.add(pick) }
                    category = customCategory
                }
                query = ""
                customLevel = nil
                searchFocused = false
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(DS.Color.onAccent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(DS.Color.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TagFormLogic.customTagTitle(value))
                            .font(.headline).foregroundColor(DS.Color.primaryText)
                        Text("Saved as your own tag. Use it again from Recent.")
                            .font(.subheadline).foregroundColor(DS.Color.secondaryText)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds your own tag to the picks")

            Text("Put it under").font(.subheadline.weight(.semibold)).foregroundColor(DS.Color.secondaryText)
            FlowLayout(spacing: DS.Spacing.sm) {
                ForEach(TagFormLogic.customCategories(for: mode), id: \.self) { cat in
                    SheetChip(label: cat.rawValue, symbol: cat.symbolName, isSelected: customCategory == cat, height: 34) {
                        animate { customCategory = cat }
                    }
                }
            }
            if rated {
                HStack {
                    Text("How strong").font(.body).foregroundColor(DS.Color.primaryText)
                    Spacer()
                    MoonIntensityControl(label: "How strong", level: customLevel) { customLevel = $0 }
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(CardSurface())
        .padding(.horizontal, 12)
    }

    // MARK: - Suggested and Recent

    /// The archive part of the Smart Tags: what she logged in this phase of past cycles.
    private var historyPicks: [TagPick] {
        let history = Set(TagFormLogic.historyTags(phase: currentPhaseType, blocks: archivedDataStore.cycleBlocks))
        return smartTags.filter { history.contains($0) }.map(TagFormLogic.pick(fromRaw:))
    }

    @ViewBuilder
    private var suggestedRow: some View {
        if let row = TagFormLogic.suggestedRow(phase: currentPhaseType, mode: mode, history: historyPicks) {
            chipRow(title: row.title, symbol: "sparkles", picks: row.picks)
        }
    }

    @ViewBuilder
    private var recentRow: some View {
        let recent = TagFormLogic.recentTags(events: myEvents.events, mode: mode, now: Date())
        if !recent.isEmpty {
            chipRow(title: "Recent", symbol: "clock", picks: recent)
        }
    }

    private func chipRow(title: String, symbol: String, picks: [TagPick]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundColor(DS.Color.accent)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(DS.Color.secondaryText)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, DS.Spacing.md)
            ScrollView(.horizontal) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(picks) { pick in chip(pick) }
                }
            }
            .contentMargins(.horizontal, DS.Spacing.md, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    private func chip(_ pick: TagPick, showCategory: Bool = false) -> some View {
        SheetChip(label: pick.value,
                  symbol: showCategory ? pick.category.symbolName : nil,
                  isSelected: selection.contains(pick),
                  isLogged: isAlreadyLogged(pick),
                  count: selection.count(of: pick)) { tap(pick) }
            .accessibilityLabel("\(pick.value), \(pick.category.rawValue)")
            .accessibilityHint(pick.isRepeatable ? "Adds one more. Can be logged more than once a day." : "")
    }

    private func sectionCaption(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(DS.Color.secondaryText)
            .padding(.horizontal, DS.Spacing.md)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Category strip

    /// The mode's categories (and the open one when it is from another mode); the grid button lists every category.
    private var stripCategories: [TagCategory] {
        modeCategories.contains(category) ? modeCategories : modeCategories + [category]
    }

    private func categoryStrip(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(stripCategories, id: \.self) { categoryChip($0) }
                }
            }
            .contentMargins(.leading, DS.Spacing.md, for: .scrollContent)
            .contentMargins(.trailing, DS.Spacing.sm, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onChange(of: category) { _, new in
                if reduceMotion { proxy.scrollTo(new, anchor: .center) } else { withAnimation { proxy.scrollTo(new, anchor: .center) } }
            }
            allCategoriesMenu
                .padding(.trailing, DS.Spacing.md)
        }
    }

    private func categoryChip(_ cat: TagCategory) -> some View {
        let isSelected = category == cat
        let picked = selection.items.filter { $0.pick.category == cat }.reduce(0) { $0 + $1.count }
        return Button { animate { category = cat } } label: {
            HStack(spacing: 7) {
                Image(systemName: cat.symbolName).imageScale(.small)
                Text(cat.rawValue)
                if picked > 0 && !isSelected {
                    Text("\(picked)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(DS.Color.onAccent)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(DS.Color.accent))
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(isSelected ? DS.Color.onAccent : DS.Color.primaryText)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Capsule().fill(isSelected ? DS.Color.accent : DS.Color.cardBackground))
            .overlay(Capsule().strokeBorder(DS.Color.primaryText.opacity(isSelected ? 0 : 0.1), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .id(cat)
        .accessibilityLabel(cat.rawValue)
        .accessibilityValue(picked > 0 ? "\(picked) picked" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Shows the \(cat.rawValue) tags")
    }

    /// Every category in one list, grouped by mode, so none is ever out of reach.
    private var allCategoriesMenu: some View {
        Menu {
            Section("\(mode.title) mode") {
                ForEach(modeCategories, id: \.self) { cat in
                    Button { category = cat } label: { Label(cat.rawValue, systemImage: cat.symbolName) }
                }
            }
            Section("More categories") {
                ForEach(otherCategories, id: \.self) { cat in
                    Button { category = cat } label: { Label(cat.rawValue, systemImage: cat.symbolName) }
                }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Color.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(DS.Color.cardBackground))
                .overlay(Circle().strokeBorder(DS.Color.primaryText.opacity(0.1), lineWidth: 1))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("All categories")
        .accessibilityHint("Lists every category")
    }

    // MARK: - Category bodies

    @ViewBuilder
    private var categoryBody: some View {
        let rows = TagFormLogic.rows(for: category, selection: selection)
        switch TagFormLogic.bodyKind(for: category) {
        case .intensityRows: intensityCard(title: category.rawValue, rows: rows)
        case .moodGrid:      moodGrid(rows)
        case .planning:      planningBody(rows)
        case .basalTemp:     basalBody(rows)
        case .menopause:     menopauseBody(rows)
        case .chips:         chipsBody(rows)
        }
    }

    /// A card of rows, each a label and the three-step moon control, with Light, Medium, Heavy over the column.
    private func intensityCard(title: String, rows: [TagRow]) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        return VStack(spacing: 0) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !stacked { IntensityColumnLabels() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            ForEach(Array(rows.filter { $0.kind == .intensity }.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, 16) }
                intensityRow(row.pick, stacked: stacked)
            }
        }
        .padding(.bottom, 6)
        .background(CardSurface())
        .padding(.horizontal, 12)
    }

    private func intensityRow(_ pick: TagPick, stacked: Bool) -> some View {
        let logged = storedLevel(pick.raw).map { "Logged as \($0.title)" } ?? (loggedOnDay.contains(pick.raw) ? "Logged" : nil)
        let label = VStack(alignment: .leading, spacing: 1) {
            Text(pick.value).font(.body).foregroundColor(DS.Color.primaryText)
            if let logged { Text(logged).font(.caption).foregroundColor(DS.Color.secondaryText) }
        }
        let control = MoonIntensityControl(label: pick.value, level: selection.intensity(of: pick)) { setLevel(pick, $0) }
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) { label; control }
            } else {
                HStack { label; Spacer(minLength: 8); control }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 50)
    }

    private func moodGrid(_ rows: [TagRow]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How do you feel?").font(.title3.weight(.semibold)).foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text("Pick any that fit. Tap again to clear.").font(.subheadline).foregroundColor(DS.Color.secondaryText)
            }
            .padding(.horizontal, DS.Spacing.md)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(rows) { row in
                    RoundGlyphButton(label: row.pick.value, symbol: TagGlyph.symbol(for: row.pick),
                                     isSelected: selection.contains(row.pick), isLogged: isAlreadyLogged(row.pick)) {
                        tap(row.pick)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    private func planningBody(_ rows: [TagRow]) -> some View {
        let tests = rows.filter { $0.kind == .ovulationTest }
        let toggles = rows.filter { $0.kind == .toggle }
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Ovulation test").font(.headline).foregroundColor(DS.Color.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    ovulationInfoButton
                    Spacer()
                    Text("Pick one").font(.subheadline).foregroundColor(DS.Color.secondaryText)
                }
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    ForEach(Array(tests.enumerated()), id: \.element.id) { index, row in
                        ovulationStripButton(row.pick, result: index)
                    }
                }
                Text("Test line compared with the control line.")
                    .font(.caption).foregroundColor(DS.Color.secondaryText)
            }
            .padding(DS.Spacing.md)
            .background(CardSurface())
            .padding(.horizontal, 12)

            VStack(spacing: 0) {
                ForEach(Array(toggles.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 58) }
                    toggleRow(row.pick, color: index == 0 ? Event.EventType.menstrual.defaultPhaseColor
                                                          : Event.EventType.follicular.defaultPhaseColor)
                }
            }
            .padding(.vertical, 4)
            .background(CardSurface())
            .padding(.horizontal, 12)
        }
    }

    private var ovulationInfoButton: some View {
        Button { showOvulationInfo = true } label: {
            Image(systemName: "info.circle").font(.title3).foregroundColor(DS.Color.accent)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About ovulation tests")
        .popover(isPresented: $showOvulationInfo) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ovulation tests").font(.headline)
                Text(ModeGuideContent.ovulationTestExplanation).font(.body)
                Text(PlanningInsightsView.disclaimer).font(.footnote).foregroundColor(DS.Color.secondaryText)
            }
            .foregroundColor(DS.Color.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .frame(idealWidth: 320)
            .presentationCompactAdaptation(dynamicTypeSize.isAccessibilitySize ? .sheet : .popover)
        }
    }

    private func ovulationStripButton(_ pick: TagPick, result: Int) -> some View {
        let isOn = selection.contains(pick)
        let logged = isAlreadyLogged(pick)
        let name = TagFormLogic.ovulationTestShortName(pick.value)
        return Button { tap(pick) } label: {
            VStack(spacing: 7) {
                OvulationStripGlyph(result: result)
                Text(name)
                    .font(.footnote.weight(isOn ? .bold : .medium))
                    .foregroundColor(DS.Color.primaryText)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.top, 10).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isOn ? DS.Color.accent.opacity(0.12) : DS.Color.primaryText.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(DS.Color.accent, lineWidth: isOn ? 1.5 : 0)
            )
            .opacity(logged ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(logged)
        .accessibilityLabel("Ovulation test \(name)")
        .accessibilityValue(logged ? "Already logged for this day" : (isOn ? "Picked" : ""))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggleRow(_ pick: TagPick, color: Color) -> some View {
        let logged = isAlreadyLogged(pick)
        return Toggle(isOn: Binding(
            get: { logged || selection.contains(pick) },
            set: { _ in tap(pick) }
        )) {
            HStack(spacing: 12) {
                RowIconSquare(symbol: TagGlyph.symbol(for: pick), color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.value).font(.body).foregroundColor(DS.Color.primaryText)
                    if logged { Text("Logged").font(.caption).foregroundColor(DS.Color.secondaryText) }
                }
            }
        }
        .tint(DS.Color.accent)
        .disabled(logged)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func basalBody(_ rows: [TagRow]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 10) {
                TextField("97.7", text: $customText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundColor(DS.Color.primaryText)
                    .accessibilityLabel("Temperature")
                    .accessibilityHint("Saved under Basal Temp")
                Button {
                    guard let pick = pendingCustom else { return }
                    animate { selection.add(pick) }
                    customText = ""
                } label: {
                    Label("Add to picks", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(DS.Color.accent)
                .disabled(pendingCustom == nil || selection.contains(pendingCustom!))
            }
            .frame(maxWidth: .infinity)

            healthSuggestion

            Text("Take it right after waking, before you get up. A rise of about 0.3 \u{00B0}F that holds for three days often follows ovulation.")
                .font(.subheadline)
                .foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.md)

            FlowLayout(spacing: DS.Spacing.sm) {
                ForEach(rows.filter { Double($0.pick.value) == nil }) { row in chip(row.pick) }
            }
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    /// A Health reading is offered, never filled in by itself: the tag is saved only when she adds it.
    @ViewBuilder
    private var healthSuggestion: some View {
        if let reading = healthSync.temperature(on: tagDate) {
            let text = Self.temperatureText(reading)
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 1, green: 0.22, blue: 0.37)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("From Apple Health").font(.subheadline).foregroundColor(DS.Color.secondaryText)
                    Text("\(text) for this day").font(.headline).foregroundColor(DS.Color.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(customText == text ? "In use" : "Use") { customText = text }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(DS.Color.accent)
                    .disabled(customText == text)
                    .accessibilityHint("Fills the temperature with the Health reading")
            }
            .padding(DS.Spacing.md)
            .background(CardSurface())
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
        }
    }

    private func menopauseBody(_ rows: [TagRow]) -> some View {
        let counters = rows.filter { $0.kind == .counter }
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Count each one").font(.subheadline.weight(.semibold)).foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                ForEach(Array(counters.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 58) }
                    counterRow(row.pick, color: index == 0 ? DS.Color.accent : Event.EventType.luteal.defaultPhaseColor)
                }
            }
            .padding(.bottom, 6)
            .background(CardSurface())
            .padding(.horizontal, 12)

            intensityCard(title: "How strong", rows: rows)
        }
    }

    private func counterRow(_ pick: TagPick, color: Color) -> some View {
        let logged = loggedOnDay.filter { $0 == pick.raw }.count
        let stacked = dynamicTypeSize.isAccessibilitySize
        let label = HStack(spacing: 12) {
            RowIconSquare(symbol: TagGlyph.symbol(for: pick), color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(pick.value).font(.body).foregroundColor(DS.Color.primaryText)
                Text(TagFormLogic.loggedCountText(logged)).font(.caption).foregroundColor(DS.Color.secondaryText)
            }
        }
        let stepper = CountStepper(label: pick.value, count: selection.count(of: pick),
                                   onMinus: { animate { selection.decrement(pick) } },
                                   onPlus: { animate { selection.increment(pick) } })
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) { label; stepper }
            } else {
                HStack { label; Spacer(minLength: 8); stepper }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func chipsBody(_ rows: [TagRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.rawValue).font(.subheadline.weight(.semibold)).foregroundColor(DS.Color.primaryText)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: DS.Spacing.sm) {
                ForEach(rows) { row in chip(row.pick) }
            }
            Text("Not here? Type it in the search to add your own.")
                .font(.footnote).foregroundColor(DS.Color.secondaryText)
        }
        .padding(DS.Spacing.md)
        .background(CardSurface())
        .padding(.horizontal, 12)
    }

    // MARK: - Tray and Add

    private var tray: some View {
        let items = TagFormLogic.trayItems(selection, mode: mode)
        return VStack(alignment: .leading, spacing: 10) {
            if !items.isEmpty {
                if dynamicTypeSize.isAccessibilitySize {
                    FlowLayout(spacing: 6) { ForEach(items) { trayChip($0) } }
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) { ForEach(items) { trayChip($0) } }
                            .padding(.vertical, 1)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            Button(action: save) {
                Text(TagFormLogic.addButtonTitle(count: pickCount))
                    .font(.headline)
                    .foregroundColor(DS.Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Capsule().fill(DS.Color.accent.opacity(canSave ? 1 : 0.4)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityHint(canSave ? "Saves the picked tags to this day" : "Pick a tag first")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(DS.Color.cardBackground.opacity(0.88))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: CardSurface.shadow, radius: 14, x: 0, y: -2)
        )
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.xs)
    }

    private func trayChip(_ item: TagSelection.Item) -> some View {
        TrayChip(item: item) { animate { selection.remove(item.pick) } }
            .transition(.scale.combined(with: .opacity))
    }

    /// Logs every picked tag (and a typed temperature not added yet) to the day, one `logTag` call per count,
    /// with its strength. A normal tag already on the day stops the save with the duplicate alert, as before,
    /// unless it carries a new strength (the stored strength then changes).
    private func save() {
        var picks = selection
        if let custom = pendingCustom { picks.add(custom) }
        guard dayCanHoldTags, !picks.isEmpty else { return }
        let blocked = TagFormLogic.blockedDuplicates(picks.items,
                                                     isDuplicate: { myEvents.isDuplicateTag($0, on: tagDate) },
                                                     storedLevel: storedLevel)
        if !blocked.isEmpty {
            duplicateLabels = blocked.map(\.pick.value)
            showDuplicateTagAlert = true
            return
        }
        for tag in picks.tagsToLog {
            myEvents.logTag(tag.raw, on: tagDate, mode: mode, intensity: tag.intensity)
        }
        dismiss()
    }
}

// MARK: - SMART TAGS
extension TagFormView {
    /// Archive tags from the same phase of past cycle blocks, then the category's library tags.
    /// With no cycle phase on the day the list is just the library tags for the chosen category.
    private func buildSmartTags() {
        smartTags = TagFormLogic.smartTags(phase: currentPhaseType, blocks: archivedDataStore.cycleBlocks, category: category)
    }
}
