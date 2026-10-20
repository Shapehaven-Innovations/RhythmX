//  ExportView.swift
//
//  The export screen for the two PDFs. The on-screen preview is free; exporting needs Plus (no grace period)
//  or a Day Pass that is still running. The locked state opens the paywall with the Day Pass card. Name and
//  date of birth for the Doctor Report live in view state only and are never written anywhere.

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Gate

enum ExportGate: Equatable {
    case locked
    /// `until` is the Day Pass end; nil for Plus.
    case unlocked(until: Date?)

    /// Plus without grace wins; then a running Day Pass; otherwise locked. The widgets' 3-day grace never
    /// applies to exports.
    static func state(_ entitlement: Entitlement, now: Date) -> ExportGate {
        if entitlement.isPlus(now: now, grace: 0) { return .unlocked(until: nil) }
        if entitlement.hasDayPass(now: now), let expiry = entitlement.dayPassExpiry { return .unlocked(until: expiry) }
        return .locked
    }

    var isUnlocked: Bool {
        if case .unlocked = self { return true }
        return false
    }
}

// MARK: - Copy

enum ExportCopy {
    static let title = "Export"
    static func dayPassTitle(price: String) -> String { "Day Pass · \(price)" }
    static let dayPassTitleWithoutPrice = "Day Pass"
    static let dayPassBody = "Unlocks the calendar and the report, any month, until midnight tonight. Plus members export free."
    static let dayPassButton = "Get Day Pass"
    static let dayPassHint = "Opens the purchase options, including RhythmX Plus."
    static let unlockedWithPlus = "Unlocked with RhythmX Plus"
    static let exportCalendar = "Export Calendar PDF"
    static let exportReport = "Export Doctor Report PDF"
    static let previewNote = "Preview is free. Export needs a Day Pass or Plus."
    static let privacyNote = "Name and date of birth are printed on the report only. They are not saved."
    static let menopauseNote = "Menopause mode: the report shows months since your last period and weekly symptom counts."

    /// "Unlocked until 11:59 pm": the last minute of the pass, in the user's time format.
    static func unlockedUntil(_ expiry: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let lastMinute = calendar.date(byAdding: .minute, value: -1, to: expiry) ?? expiry
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = lastMinute.formatted(style)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .lowercased()
        return "Unlocked until \(time)"
    }
}

// MARK: - Share item

/// A rendered PDF handed to `ShareLink`. Data only: nothing is written to disk by the app.
struct PDFExportFile: Transferable {
    /// Called when the share sheet asks for the file, so it always reflects the current fields.
    let makeData: @MainActor () -> Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { file in await MainActor.run { file.makeData() } }
            .suggestedFileName { $0.fileName }
    }
}

// MARK: - View

struct ExportView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case calendar = "Calendar"
        case report = "Doctor Report"
        var id: String { rawValue }
    }

    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var archivedDataStore: ArchivedDataStore
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var fertileStore: FertileStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var kind: Kind
    @State private var month = CalendarMonthModel(containing: Date())
    @State private var paper = PaperSize.default
    @State private var lightTints = false
    @State private var name = ""
    @State private var includeBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var showPaywall = false
    @State private var now = Date()
    @State private var renderedFields: FieldKey?
    @State private var previewSummary = ""
    @State private var calendarPDF = Data()
    @State private var reportPDF = Data()
    @State private var preview: UIImage?

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(kind: Kind = .calendar) {
        _kind = State(initialValue: kind)
    }

    private var gate: ExportGate { ExportGate.state(purchaseStore.entitlement, now: now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Picker("Document", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Document to export")

                    previewCard
                    if kind == .calendar { calendarOptions } else { reportOptions }
                    gateCard
                }
                .padding(DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xl)
            }
            .themedPage()
            .navigationTitle(ExportCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(showsDayPass: true).environmentObject(purchaseStore)
            }
            .task(id: renderKey) { render() }
            .task(id: fieldKey) {
                // Typing in the report fields re-renders after a pause, not on every keystroke.
                guard fieldKey != renderedFields else { return }
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                render()
            }
            .onAppear { now = purchaseStore.currentDate() }
            .onReceive(clock) { _ in now = purchaseStore.currentDate() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = purchaseStore.currentDate() } }
            .onChange(of: purchaseStore.entitlement) { _, _ in
                if reduceMotion { now = purchaseStore.currentDate() } else { withAnimation(.easeInOut(duration: 0.2)) { now = purchaseStore.currentDate() } }
            }
        }
    }

    // MARK: Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Group {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .blur(radius: gate.isUnlocked ? 0 : 9, opaque: true)
                        .overlay(alignment: .topTrailing) {
                            if !gate.isUnlocked {
                                Image(systemName: "lock.fill")
                                    .font(DS.Font.caption.weight(.semibold))
                                    .foregroundColor(DS.Color.onAccent)
                                    .padding(DS.Spacing.sm)
                                    .background(DS.Color.accent, in: Circle())
                                    .padding(DS.Spacing.sm)
                                    .accessibilityHidden(true)
                            }
                        }
                } else {
                    Rectangle().fill(DS.Color.cardBackground)
                        .aspectRatio(paper.size.width / paper.size.height, contentMode: .fit)
                        .overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip).strokeBorder(DS.Color.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(previewLabel)
            .accessibilityValue(gate.isUnlocked ? previewSummary : "")

            Text(ExportCopy.previewNote)
                .font(DS.Font.micro)
                .foregroundColor(DS.Color.secondaryText)
        }
    }

    private var previewLabel: String {
        let document = kind == .calendar ? "the \(month.title) calendar" : "the Doctor Report"
        return "Preview of \(document) on \(paper.title) paper" + (gate.isUnlocked ? "" : ". Export is locked")
    }

    // MARK: Options

    private var calendarOptions: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.sm))
                : AnyLayout(HStackLayout())) {
                Text(month.title)
                    .font(DS.Font.sectionHeader)
                    .foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Button { month = month.adding(months: -1) } label: {
                        Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Previous month")
                    Button { month = month.adding(months: 1) } label: {
                        Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Next month")
                }
            }
            Toggle("Lighter tints to save ink", isOn: $lightTints)
                .font(DS.Font.label)
                .foregroundColor(DS.Color.primaryText)
            paperPicker
        }
        .cardStyle()
    }

    private var reportOptions: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("For the report")
                .font(DS.Font.sectionHeader)
                .foregroundColor(DS.Color.primaryText)
                .accessibilityAddTraits(.isHeader)
            TextField("Name (optional)", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .font(DS.Font.label)
                .padding(DS.Spacing.sm)
                .background(DS.Color.pageBackground)
                .cornerRadius(DS.Radius.chip)
                .accessibilityLabel("Name, optional")
            Toggle("Include date of birth", isOn: $includeBirthDate)
                .font(DS.Font.label)
                .foregroundColor(DS.Color.primaryText)
            if includeBirthDate {
                DatePicker("Date of birth", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .font(DS.Font.label)
                    .foregroundColor(DS.Color.primaryText)
            }
            Text(ExportCopy.privacyNote)
                .font(DS.Font.micro)
                .foregroundColor(DS.Color.secondaryText)
            if appSettings.trackingMode == .menopause {
                Text(ExportCopy.menopauseNote)
                    .font(DS.Font.micro)
                    .foregroundColor(DS.Color.secondaryText)
            }
            paperPicker
        }
        .cardStyle()
    }

    private var paperPicker: some View {
        Picker("Paper size", selection: $paper) {
            ForEach(PaperSize.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Paper size")
    }

    // MARK: Gate

    @ViewBuilder
    private var gateCard: some View {
        switch gate {
        case .locked:
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(purchaseStore.dayPass.map { ExportCopy.dayPassTitle(price: $0.displayPrice) } ?? ExportCopy.dayPassTitleWithoutPrice)
                    .font(DS.Font.sectionHeader)
                    .foregroundColor(DS.Color.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(ExportCopy.dayPassBody)
                    .font(DS.Font.label)
                    .foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: ExportCopy.dayPassButton) { showPaywall = true }
                    .accessibilityHint(ExportCopy.dayPassHint)
                Text(ExportCopy.dayPassHint)
                    .font(DS.Font.micro)
                    .foregroundColor(DS.Color.secondaryText)
            }
            .cardStyle()
        case .unlocked(let until):
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(DS.Color.accent).accessibilityHidden(true)
                    Text(until.map { ExportCopy.unlockedUntil($0) } ?? ExportCopy.unlockedWithPlus)
                        .font(DS.Font.label.weight(.semibold))
                        .foregroundColor(DS.Color.primaryText)
                }
                .accessibilityElement(children: .combine)
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm))
                    : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))) {
                    exportButton(ExportCopy.exportCalendar, isReady: !calendarPDF.isEmpty, fileName: "Calendar \(month.title).pdf") { calendarPDF }
                    exportButton(ExportCopy.exportReport, isReady: !reportPDF.isEmpty, fileName: "\(reportTitle).pdf") { makeReportPDF() }
                }
            }
            .cardStyle()
        }
    }

    private func exportButton(_ title: String, isReady: Bool, fileName: String, makeData: @escaping @MainActor () -> Data) -> some View {
        ShareLink(item: PDFExportFile(makeData: makeData, fileName: fileName), preview: SharePreview(fileName)) {
            Text(title)
                .font(DS.Font.label.weight(.semibold))
                .foregroundColor(DS.Color.onAccent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .padding(.horizontal, DS.Spacing.sm)
                .background(DS.Color.accent)
                .cornerRadius(DS.Radius.button)
        }
        .disabled(!isReady)
        .accessibilityLabel(title)
        .accessibilityHint("Opens the share sheet to save or send the PDF")
    }

    // MARK: Rendering

    private var reportTitle: String { appSettings.trackingMode == .menopause ? "Menopause Report" : "Cycle Report" }

    private struct RenderKey: Hashable {
        let kind: Kind
        let month: Date
        let paper: PaperSize
        let lightTints: Bool
        let mode: TrackingMode
        let colors: String
        let eventCount: Int
        let blockCount: Int
        let day: Date
    }

    private struct FieldKey: Hashable {
        let name: String
        let birthDate: Date?
    }

    private var fieldKey: FieldKey { FieldKey(name: name, birthDate: includeBirthDate ? birthDate : nil) }

    private var renderKey: RenderKey {
        RenderKey(kind: kind, month: month.monthStart, paper: paper, lightTints: lightTints, mode: appSettings.trackingMode,
                  colors: appSettings.colorSignature, eventCount: eventStore.events.count,
                  blockCount: archivedDataStore.archivedBlocks.count, day: now.startOfDay)
    }

    /// Renders both PDFs (the unlocked card offers both) and the preview of the selected one.
    private func render() {
        let colors = Event.EventType.allCases.map { appSettings.phaseColor(for: $0) }
        calendarPDF = CalendarPDFRenderer(events: eventStore.cycleEvents, archivedBlocks: archivedDataStore.cycleBlocks,
                                          colors: colors, fertileOverrides: fertileStore.overrides)
            .render(month: month.monthStart, paper: paper, lightTints: lightTints, today: now)

        reportPDF = makeReportPDF()
        renderedFields = fieldKey

        let data = kind == .calendar ? calendarPDF : reportPDF
        if let page = PDFDocument(data: data)?.page(at: 0) {
            previewSummary = String((page.string ?? "").prefix(200))
            let width: CGFloat = 1200
            preview = page.thumbnail(of: CGSize(width: width, height: width * paper.size.height / paper.size.width), for: .mediaBox)
        }
    }

    /// The Doctor Report with the name and date of birth as they are right now.
    private func makeReportPDF() -> Data {
        // Cycle and Planning read cycle data only. The Menopause variant needs the menopause entries as well;
        // the builder keeps them out of every cycle statistic.
        let mode = appSettings.trackingMode
        let events = mode == .menopause ? eventStore.events : eventStore.cycleEvents
        let blocks = mode == .menopause ? archivedDataStore.archivedBlocks : archivedDataStore.cycleBlocks
        let report = DoctorReportBuilder.make(events: events, archivedBlocks: blocks, mode: mode, today: now)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return DoctorReportPDFRenderer(today: now)
            .render(report, paper: paper, name: trimmed.isEmpty ? nil : trimmed, birthDate: includeBirthDate ? birthDate : nil)
    }
}

#Preview {
    ExportView(kind: .calendar)
        .environmentObject(EventStore(preview: true))
        .environmentObject(ArchivedDataStore())
        .environmentObject(AppSettings())
        .environmentObject(FertileStore())
        .environmentObject(PurchaseStore(listensForUpdates: false))
}
