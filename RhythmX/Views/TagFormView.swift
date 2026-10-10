//
//  TagFormView.swift
//  Rhythm
//
//  Created by user on 9/27/24.
//

import SwiftUI

enum TagCategory: String, CaseIterable {
    case dietary        = "Dietary"
    case exercise       = "Exercise"
    case medication     = "Medication"
    case mood           = "Mood"
    case symptom        = "Symptom"
    case cervicalMucus  = "Cervical Mucus"
    case other          = "Other"
}

struct TagFormView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @Environment(\.dismiss) var dismiss

    @State private var category: TagCategory = .dietary
    @State private var customType: String = ""
    @State private var tagDate = Date()

    @State private var smartTags: [String] = []

    init(initialDate: Date = Date()) {
        _tagDate = State(initialValue: initialDate)
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
                            ForEach(TagCategory.allCases, id: \.self) { cat in
                                ChipButton(title: cat.rawValue, isSelected: category == cat) { category = cat }
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
                buildSmartTags()
                smartPrePopulate()
            }
            // If iOS 17 or later:
            .onChange(of: tagDate) { oldValue, newValue in
                buildSmartTags()
            }
        }
    }

    /// Suggestions default to Symptom unless they are a known mood tag (e.g. "Mood Swings").
    private func suggestionCategory(_ suggestion: String) -> TagCategory {
        (TagLibrary.tags[.mood] ?? []).contains(suggestion) ? .mood : .symptom
    }

    private var currentPhaseType: Event.EventType? {
        myEvents.events.first {
            $0.date.startOfDay == tagDate.startOfDay
        }?.eventType
    }
    
    // === NEW: Check if the tag already exists on this day across all events ===
    private func isDuplicateTag() -> Bool {
        let finalTag = buildTagString()
        let targetStartOfDay = tagDate.startOfDay

        // Gather all tags on this day from *all* events
        var dayWideTagSet = Set<String>()
        for event in myEvents.events where event.date.startOfDay == targetStartOfDay {
            let tagsArray = event.tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            for t in tagsArray {
                dayWideTagSet.insert(t)
            }
        }
        // Return true if we already have this exact tag
        return dayWideTagSet.contains(finalTag)
    }

    private func buildTagString() -> String {
        let trimmed = customType.trimmingCharacters(in: .whitespacesAndNewlines)
        let capitalized = trimmed.isEmpty ? "unspecified" : (trimmed.prefix(1).uppercased() + trimmed.dropFirst())
        return "\(category.rawValue):\(capitalized)"
    }

    private func saveTag() {
        let finalTag = buildTagString()
        let targetStartOfDay = tagDate.startOfDay

        // Append this new tag to *every* event on the chosen day
        for event in myEvents.events where event.date.startOfDay == targetStartOfDay {
            var updated = event
            if updated.tags.isEmpty {
                updated.tags = finalTag
            } else {
                updated.tags += ", \(finalTag)"
            }
            myEvents.update(updated)
        }
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
        guard let phaseType = currentPhaseType else {
            smartTags = []
            return
        }

        var frequency: [String: Int] = [:]

        for block in archivedDataStore.archivedBlocks {
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
        for block in archivedDataStore.archivedBlocks {
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

