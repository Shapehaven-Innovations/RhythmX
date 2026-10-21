//  InfoButton.swift
//  The info circle used across the app: a card shows a one-line summary and the longer explanation
//  (`InfoCopy`) opens from here, as a popover, or as a medium sheet at accessibility text sizes. Disclaimers,
//  the paywall's terms and denied or error states are never moved behind it.

import SwiftUI

struct InfoButton: View {
    let topic: InfoTopic
    /// Draws the 44 point target over its neighbours so a header row keeps its height.
    var compact: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShown = false

    var body: some View {
        Button {
            isShown = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundColor(DS.Color.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(compact ? -10 : 0)
        .accessibilityLabel(topic.accessibilityLabel)
        .accessibilityHint("Shows more about this")
        .sensoryFeedback(.selection, trigger: isShown) { _, shown in shown }
        .popover(isPresented: Binding(get: { isShown && !dynamicTypeSize.isAccessibilitySize },
                                      set: { isShown = $0 })) {
            InfoPopoverContent(topic: topic)
                .frame(idealWidth: 320)
                .presentationCompactAdaptation(.popover)
        }
        .sheet(isPresented: Binding(get: { isShown && dynamicTypeSize.isAccessibilitySize },
                                    set: { isShown = $0 })) {
            InfoSheet(topic: topic) { isShown = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// The popover: the title in bold, then the paragraphs.
struct InfoPopoverContent: View {
    let topic: InfoTopic

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(topic.title).font(.headline).foregroundColor(DS.Color.primaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(topic.paragraphs, id: \.self) { paragraph in
                Text(paragraph).font(.subheadline).foregroundColor(DS.Color.primaryText)
            }
            if let footnote = topic.footnote {
                Text(footnote).font(.footnote).foregroundColor(DS.Color.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(DS.Spacing.md)
    }
}

/// The same text as a sheet, for accessibility text sizes.
struct InfoSheet: View {
    let topic: InfoTopic
    let done: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    ForEach(topic.paragraphs, id: \.self) { paragraph in
                        Text(paragraph).font(.body).foregroundColor(DS.Color.primaryText)
                    }
                    if let footnote = topic.footnote {
                        Text(footnote).font(.body).foregroundColor(DS.Color.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DS.Spacing.md)
            }
            .background(DS.Color.pageBackground.ignoresSafeArea())
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: done) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .tint(DS.Color.accent)
                        .accessibilityLabel("Done")
                }
            }
        }
    }
}
