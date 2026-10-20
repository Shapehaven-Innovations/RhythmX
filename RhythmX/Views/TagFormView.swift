//
//  TagFormView.swift
//  Rhythm
//
//  Created by user on 9/27/24.
//

import SwiftUI

// `TagCategory` lives in Models/TagCategory.swift (shared with the widget extension).

struct TagFormView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var healthSync: HealthSync
    @Environment(\.dismiss) var dismiss

    @State private var category: TagCategory = .dietary
    @State private var customType: String = ""
    @State private var tagDate = Date()

    @State private var smartTags: [String] = []
    /// Categories outside the current mode's list are hidden behind a "More" chip until asked for.
    @State private var showMoreCategories = false
    @State private var didPickInitialCategory = false

    /// A category to open on (a notification tap); nil picks the mode's first category.
    private let initialCategory: TagCategory?

    init(initialDate: Date = Date(), initialCategory: TagCategory? = nil) {
        _tagDate = State(initialValue: initialDate)
        self.initialCategory = initialCategory
    }
    
    // Suggestion dictionary for quick symptom selection
    private let phaseSymptomSuggestions: [Event.EventType: [String]] = [
        .menstrual:  ["Cramps", "Bloating", "Fatigue", "Headache", "Irritable"],
        .follicular: ["Increased Energy", "Clearer Thinking", "Higher Libido"],
        .ovulation:  ["Mittelschmerz", "Bloating", "Mild Cramping"],
        .luteal:     ["Mood Swings", "Breast Tenderness", "Food Cravings", "PMS"]
    ]

    // === NEW: Alert to stop duplicate tags on the same day ===
    @State private var showDuplicateTagAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Category")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(modeCategories, id: \.self) { cat in
                                ChipButton(title: cat.rawValue, isSelected: category == cat) { category = cat }
                            }
                            if !otherCategories.isEmpty {
                                if showMoreCategories || otherCategories.contains(category) {
                                    ForEach(otherCategories, id: \.self) { cat in
                                        ChipButton(title: cat.rawValue, isSelected: category == cat) { category = cat }
                                    }
                                } else {
                                    ChipButton(title: "More") { showMoreCategories = true }
                                        .accessibilityLabel("More categories")
                                }
                            }
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.md, bottom: 0, trailing: DS.Spacing.md))
                }

                TextField("Specific Type (e.g. 🍫)", text: $customType)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .keyboardType(.default)
                
                DatePicker("Date", selection: $tagDate, displayedComponents: .date)

                // A Health reading is offered, never filled in by itself: the tag is saved only when she taps Save.
                if category == .basalTemp, let reading = healthSync.temperature(on: tagDate) {
                    Section(header: Text("From Apple Health")) {
                        let text = Self.temperatureText(reading)
                        Text("Apple Health has a basal temperature of \(text) for this day.")
                            .font(DS.Font.caption)
                            .foregroundColor(DS.Color.secondaryText)
                        Button(customType == text ? "Using the Health value" : "Use \(text)") { customType = text }
                            .disabled(customType == text)
                            .accessibilityHint("Fills the temperature field with the Health reading")
                    }
                }

                if let phaseType = currentPhaseType {
                    Section(header: Text("Suggested Tags for \(phaseType.rawValue.capitalized) Phase")) {
                        if let suggestions = phaseSymptomSuggestions[phaseType], !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: DS.Spacing.sm) {
                                    ForEach(suggestions, id: \.self) { suggestion in
                                        ChipButton(
                                            title: suggestion,
                                            isSelected: customType == suggestion && category == suggestionCategory(suggestion)
                                        ) {
                                            category = suggestionCategory(suggestion)
                                            customType = suggestion
                                        }
                                    }
                                }
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.md, bottom: 0, trailing: DS.Spacing.md))
                        } else {
                            Text("No suggestions available for this phase.")
                                .font(DS.Font.caption)
                                .foregroundColor(DS.Color.secondaryText)
                        }
                    }
                }

                if let phaseType = currentPhaseType,
                   (phaseType == .follicular || phaseType == .ovulation),
                   category != .cervicalMucus {
                    Section(header: Text("Track Cervical Mucus")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Spacing.sm) {
                                ForEach(TagLibrary.tags[.cervicalMucus] ?? [], id: \.self) { tag in
                                    ChipButton(
                                        title: tag,
                                        isSelected: customType == tag && category == .cervicalMucus
                                    ) {
                                        category = .cervicalMucus
                                        customType = tag
                                    }
                                }
                            }
                            .padding(.vertical, DS.Spacing.xs)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.md, bottom: 0, trailing: DS.Spacing.md))
                    }
                }

                if !smartTags.isEmpty {
                    Section(header: Text("Smart Tags (from Archive)")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Spacing.sm) {
                                ForEach(smartTags, id: \.self) { tagString in
                                    let displayName = tagString.split(separator: ":", maxSplits: 1).last
                                        .map { String($0).trimmingCharacters(in: .whitespaces) } ?? tagString
                                    ChipButton(title: displayName) {
                                        applySmartTag(tagString)
                                    }
                                }
                            }
                            .padding(.vertical, DS.Spacing.xs)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.md, bottom: 0, trailing: DS.Spacing.md))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Color.pageBackground)
            .navigationTitle("Add a Tag")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // === Check for duplicates first ===
                    Button("Save") {
                        if isDuplicateTag() {
                            showDuplicateTagAlert = true
                        } else {
                            saveTag()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            // Show an alert if the user attempts a duplicate
            .alert("Duplicate Tag", isPresented: $showDuplicateTagAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This tag already exists for the selected day.")
            }
            .onAppear {
                if !didPickInitialCategory {
                    didPickInitialCategory = true
                    category = initialCategory ?? modeCategories.first ?? .dietary
                }
                buildSmartTags()
                // Archive-based pre-selection is a cycle habit; other modes start on their own category,
                // and a requested category is kept.
                if appSettings.trackingMode == .cycle && initialCategory == nil { smartPrePopulate() }
            }
            // If iOS 17 or later:
            .onChange(of: tagDate) { oldValue, newValue in
                buildSmartTags()
            }
            .onChange(of: category) { oldValue, newValue in
                buildSmartTags()
            }
        }
    }

    /// "97.8": one decimal, a plain dot, so it round-trips through `PlanningInsights.temperature(from:)`.
    static func temperatureText(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// The current mode's categories, shown first.
    private var modeCategories: [TagCategory] {
        TagLibrary.categories(for: appSettings.trackingMode)
    }

    /// Every other category, kept reachable under "More".
    private var otherCategories: [TagCategory] {
        TagCategory.allCases.filter { !modeCategories.contains($0) }
    }

    /// Suggestions default to Symptom unless they are a known mood tag (e.g. "Mood Swings").
    private func suggestionCategory(_ suggestion: String) -> TagCategory {
        (TagLibrary.tags[.mood] ?? []).contains(suggestion) ? .mood : .symptom
    }

    /// Phase of the cycle event on the chosen day. Menopause carrier events have no phase.
    private var currentPhaseType: Event.EventType? {
        myEvents.cycleEvents.first {
            $0.date.startOfDay == tagDate.startOfDay
        }?.eventType
    }

    // === Check if the tag already exists on this day across all events. Repeatable tags never are. ===
    private func isDuplicateTag() -> Bool {
        myEvents.isDuplicateTag(buildTagString(), on: tagDate)
    }

    private func buildTagString() -> String {
        let trimmed = customType.trimmingCharacters(in: .whitespacesAndNewlines)
        let capitalized = trimmed.isEmpty ? "unspecified" : (trimmed.prefix(1).uppercased() + trimmed.dropFirst())
        return "\(category.rawValue):\(capitalized)"
    }

    /// Appends the tag to every event on the chosen day. In Menopause mode a day with no event gets
    /// a carrier event first, so the tag has somewhere to live.
    private func saveTag() {
        myEvents.logTag(buildTagString(), on: tagDate, mode: appSettings.trackingMode)
    }

    // === Called when user taps a "smart tag" button ===
    private func applySmartTag(_ tagString: String) {
        let parts = tagString.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            let prefix = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let matchedCategory = TagCategory.allCases.first(where: { $0.rawValue.lowercased() == prefix.lowercased() }) {
                category = matchedCategory
            } else {
                category = .other
            }
            customType = suffix
        } else {
            category = .other
            customType = tagString
        }
    }
}

// MARK: - SMART TAGS
extension TagFormView {
    private func buildSmartTags() {
        // With no cycle phase on the day (Menopause, or a day outside the cycle) the archive has
        // nothing to rank, so the list is just the library tags for the chosen category.
        let phaseType = currentPhaseType
        var frequency: [String: Int] = [:]

        for block in archivedDataStore.cycleBlocks where phaseType != nil {
            for archivedPhase in block.groupedEvents where archivedPhase.eventType == phaseType {
                for archivedEvent in archivedPhase.events {
                    let rawTags = archivedEvent.tags
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    for t in rawTags where !t.isEmpty {
                        frequency[t, default: 0] += 1
                    }
                }
            }
        }

        var ranked = frequency.sorted { $0.value > $1.value }.map { $0.key }

        // Append library tags for current category not already in smart list
        let libTags = TagLibrary.tags[category] ?? []
        let existing = Set(ranked)
        let additional = libTags
            .filter { !existing.contains("\(category.rawValue):\($0)") && !existing.contains($0) }
            .map { "\(category.rawValue):\($0)" }
        ranked = Array((ranked + additional).prefix(8))

        smartTags = ranked
    }

    private func smartPrePopulate() {
        guard let phaseType = currentPhaseType else { return }
        var categoryFreq: [TagCategory: Int] = [:]
        for block in archivedDataStore.cycleBlocks {
            for archivedPhase in block.groupedEvents where archivedPhase.eventType == phaseType {
                for archivedEvent in archivedPhase.events {
                    let rawTags = archivedEvent.tags
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    for tag in rawTags where !tag.isEmpty {
                        let parts = tag.split(separator: ":", maxSplits: 1)
                        guard parts.count == 2 else { continue }
                        let prefix = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if let cat = TagCategory.allCases.first(where: {
                            $0.rawValue.lowercased() == prefix.lowercased()
                        }) {
                            categoryFreq[cat, default: 0] += 1
                        }
                    }
                }
            }
        }
        if let topCategory = categoryFreq.max(by: { $0.value < $1.value })?.key {
            category = topCategory
        }
    }
}

