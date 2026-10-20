//  BackupView.swift
//
//  Backup screen (Settings > Your data) and the restore flow. The restore flow is also presented
//  as a sheet when a `.rhythmx` file is opened from Files, AirDrop or Mail (see `AppEntry.onOpenURL`).

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist under UTExportedTypeDeclarations.
    static let rhythmxBackup = UTType(exportedAs: "beta.Rhythm.backup", conformingTo: .data)
}

// MARK: - View model

@MainActor
final class BackupViewModel: ObservableObject {
    /// In `UserDefaults.standard`. Shown as "Last backup" only; it no longer affects any saved copy.
    static let lastBackupDateKey = "lastBackupDate"
    /// Where `createBackup` writes the file handed to the share sheet.
    nonisolated static let defaultExportDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RhythmXBackupExport", isDirectory: true)

    enum RestoreError: Error, Equatable {
        /// The copy of the current data that Replace writes first could not be saved, so nothing was replaced.
        case safetyCopyFailed
        /// The file's bytes could not be read at all (missing, not downloaded yet, access denied). Says nothing
        /// about the file's contents, so it is not reported as damaged.
        case unreadableFile
    }

    @Published var lastBackupDate: Date?
    @Published var selectedMode: RestoreMode = .merge
    @Published private(set) var header: BackupHeader?
    @Published private(set) var preview: BackupPreview?
    @Published private(set) var fileName: String?
    /// True while a backup is built or a file is unlocked (key derivation runs off the main actor).
    @Published private(set) var isWorking = false

    /// A safety copy on this phone with what it holds. `preview` is nil when the file cannot be read.
    struct SavedCopyRow: Identifiable, Equatable {
        let copy: SafetyCopy
        let preview: BackupPreview?
        var id: URL { copy.id }
    }

    @Published private(set) var savedCopies: [SavedCopyRow] = []
    @Published var savedCopiesError: String?

    /// The file `loadFile` read. Pruning after a Replace never removes it.
    private var sourceURL: URL?
    private var fileData: Data?
    private var payload: BackupPayload?

    private let events: EventStore
    private let archived: ArchivedDataStore
    private let settings: AppSettings
    private let defaults: UserDefaults
    private let exportDirectory: URL
    private let safetyDirectory: URL?
    private let appVersion: String
    private let iterations: Int
    private let now: () -> Date

    init(
        events: EventStore,
        archived: ArchivedDataStore,
        settings: AppSettings,
        defaults: UserDefaults = .standard,
        exportDirectory: URL = BackupViewModel.defaultExportDirectory,
        safetyDirectory: URL? = SafetyCopies.defaultDirectory,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        iterations: Int = BackupCrypto.defaultIterations,
        now: @escaping () -> Date = Date.init
    ) {
        self.events = events
        self.archived = archived
        self.settings = settings
        self.defaults = defaults
        self.exportDirectory = exportDirectory
        self.safetyDirectory = safetyDirectory
        self.appVersion = appVersion
        self.iterations = iterations
        self.now = now
        self.lastBackupDate = defaults.object(forKey: Self.lastBackupDateKey) as? Date
    }

    // MARK: Backup

    /// Writes `RhythmX-yyyy-MM-dd.rhythmx` to a temporary directory for the share sheet.
    /// A nil or empty passphrase writes an unencrypted file. Earlier exports are removed first.
    /// The payload is read from the stores here; encoding and encryption run off the main actor.
    func createBackup(passphrase: String?) async throws -> URL {
        isWorking = true
        defer { isWorking = false }

        let date = now()
        let payload = BackupService.makePayload(events: events, archived: archived, settings: settings)
        let appVersion = appVersion
        let iterations = iterations
        let data = try await Task.detached(priority: .userInitiated) {
            try BackupFile.make(payload, appVersion: appVersion, passphrase: passphrase,
                                iterations: iterations, now: date)
        }.value

        clearExports()
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let url = exportDirectory.appendingPathComponent(Self.fileName(for: date), isDirectory: false)
        try data.write(to: url, options: [.atomic, .completeFileProtection])

        lastBackupDate = date
        defaults.set(date, forKey: Self.lastBackupDateKey)
        return url
    }

    /// Removes exported files from the temporary directory so no copy lingers after sharing.
    func clearExports() {
        Self.clearExports(at: exportDirectory)
    }

    /// Also called at launch and when the app goes to the background (`AppEntry`).
    nonisolated static func clearExports(at directory: URL = defaultExportDirectory) {
        try? FileManager.default.removeItem(at: directory)
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return "RhythmX-\(formatter.string(from: date)).\(BackupFile.fileExtension)"
    }

    // MARK: Restore

    /// Reads the file (with security-scoped access when the URL needs it) and its header.
    /// Nothing is decoded beyond the header and no store is touched. A copy iOS placed in the
    /// app's Documents/Inbox (Open In, AirDrop, Mail) is deleted once read, so it does not linger.
    func loadFile(_ url: URL) throws -> BackupHeader {
        header = nil
        preview = nil
        payload = nil
        fileData = nil
        sourceURL = nil
        selectedMode = .merge
        fileName = url.lastPathComponent

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RestoreError.unreadableFile
        }
        if Self.isInboxCopy(url) {
            try? FileManager.default.removeItem(at: url)
        }
        let header = try BackupFile.inspect(data)
        fileData = data
        sourceURL = url
        self.header = header
        return header
    }

    static func isInboxCopy(_ url: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.path.contains("/Documents/Inbox/")
    }

    /// Decrypts (when needed) and decodes the loaded file off the main actor, then builds the preview.
    /// No store is touched, whatever the outcome.
    func unlock(passphrase: String?) async throws -> BackupPreview {
        guard let fileData else { throw BackupFileError.notABackup }
        isWorking = true
        defer { isWorking = false }

        let payload = try await Task.detached(priority: .userInitiated) {
            try BackupFile.open(fileData, passphrase: passphrase)
        }.value
        let preview = BackupService.preview(payload)
        self.payload = payload
        self.preview = preview
        return preview
    }

    /// Restores the unlocked file. Replace must be passed explicitly; the UI confirms it first.
    /// The file is already in memory (`unlock`). Before Replace, the current data is saved as an unencrypted
    /// pre-restore safety copy and the copies are pruned, never removing the file being restored; if that
    /// copy cannot be saved, Replace does not run and `RestoreError.safetyCopyFailed` is thrown.
    @discardableResult
    func restore(_ mode: RestoreMode) throws -> RestoreResult {
        guard let payload else { return RestoreResult(eventsAdded: 0, blocksAdded: 0) }
        if mode == .replace {
            try writePreRestoreCopy()
        }
        // Store saves reload widgets (AppGroup.reloadWidgets) on their own.
        let result = BackupService.restore(payload, mode: mode, events: events, archived: archived, settings: settings)
        events.reloadCalendarIcons()
        rescheduleNotifications()
        return result
    }

    private func writePreRestoreCopy() throws {
        let date = now()
        let current = BackupService.makePayload(events: events, archived: archived, settings: settings)
        do {
            // Unencrypted, so no key derivation runs on the main actor here.
            let data = try BackupFile.make(current, appVersion: appVersion, passphrase: nil, now: date)
            try SafetyCopies.write(data, kind: .preRestore, date: date, now: date, directory: safetyDirectory,
                                   protecting: Set([sourceURL].compactMap { $0 }))
        } catch {
            throw RestoreError.safetyCopyFailed
        }
    }

    // MARK: Saved copies

    /// Lists the safety copies and reads what each holds. Files are decoded off the main actor.
    func refreshSavedCopies() async {
        let copies = SafetyCopies.list(directory: safetyDirectory)
        let payloads: [BackupPayload?] = await Task.detached(priority: .userInitiated) {
            copies.map { copy in
                guard let data = try? Data(contentsOf: copy.url),
                      let header = try? BackupFile.inspect(data), !header.isEncrypted else { return nil }
                return try? BackupFile.open(data, passphrase: nil)
            }
        }.value
        savedCopies = zip(copies, payloads).map { copy, payload in
            SavedCopyRow(copy: copy, preview: payload.map(BackupService.preview))
        }
    }

    /// Deletes one copy. A failure is shown in `savedCopiesError`; the list is refreshed either way.
    func deleteSavedCopy(_ copy: SafetyCopy) async {
        do {
            try SafetyCopies.delete(copy.url, directory: safetyDirectory)
            savedCopiesError = nil
        } catch {
            savedCopiesError = "This copy could not be deleted. Try again."
        }
        await refreshSavedCopies()
    }

    static func label(for kind: SafetyCopy.Kind) -> String {
        switch kind {
        case .preUpdate: return "Before the update"
        case .preRestore: return "Before a restore"
        }
    }

    /// Same scheduling path SettingsView uses for cycle reminders.
    private func rescheduleNotifications() {
        guard settings.notificationsEnabled else {
            NotificationScheduler.cancelAllCycleReminders()
            return
        }
        guard let predicted = CyclePredictionService.predictedStartDate(from: archived.cycleBlocks) else { return }
        NotificationScheduler.scheduleCycleReminders(
            for: predicted,
            dayBefore: settings.notifyDayBefore,
            dayOf: settings.notifyDayOf
        )
    }

    // MARK: Messages

    static func message(for error: Error) -> String {
        switch error as? RestoreError {
        case .safetyCopyFailed:
            return "A safety copy of your current data could not be saved, so nothing was replaced. Your data has not changed."
        case .unreadableFile:
            return "This file could not be opened. Make sure it has finished downloading and try again."
        case .none:
            break
        }
        switch error as? BackupFileError {
        case .notABackup: return "That file isn't a RhythmX backup."
        case .newerFormat: return "This backup was made by a newer version of RhythmX. Update the app to open it."
        case .wrongPassphrase: return "Wrong passphrase."
        case .corrupted, .none: return "This file looks damaged and was not restored."
        }
    }
}

// MARK: - Backup screen

struct BackupView: View {
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        BackupScreen(events: myEvents, archived: archivedDataStore, settings: appSettings)
    }
}

private struct BackupScreen: View {
    @StateObject private var model: BackupViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var usePassphrase = false
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var incoming: IncomingBackup?
    @State private var pendingDelete: SafetyCopy?

    init(events: EventStore, archived: ArchivedDataStore, settings: AppSettings) {
        _model = StateObject(wrappedValue: BackupViewModel(events: events, archived: archived, settings: settings))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                backupCard
                restoreCard
                savedCopiesCard
                statusCard
            }
            .padding(DS.Spacing.md)
        }
        .themedPage()
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.rhythmxBackup]) { result in
            if case .success(let url) = result { incoming = IncomingBackup(url: url) }
        }
        .sheet(item: $incoming, onDismiss: refreshSavedCopies) { item in
            RestoreView(model: model, url: item.url)
        }
        .task { await model.refreshSavedCopies() }
        .alert("Delete this copy?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { copy in
            Button("Delete", role: .destructive) {
                Task { await model.deleteSavedCopy(copy) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { copy in
            Text("This removes the copy saved \(BackupViewModel.label(for: copy.kind).lowercased()) from this phone. Your current data is not affected.")
        }
        .onDisappear { model.clearExports() }
        .onChange(of: usePassphrase) { _, _ in exportURL = nil }
        .onChange(of: passphrase) { _, _ in exportURL = nil }
        .onChange(of: confirmation) { _, _ in exportURL = nil }
        // AppEntry removes exported files when the app goes to the background; drop the stale link too.
        .onChange(of: scenePhase) { _, phase in if phase == .background { exportURL = nil } }
    }

    // MARK: Back up now

    private var passphraseReady: Bool {
        !usePassphrase || (!passphrase.isEmpty && passphrase == confirmation)
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Back up now").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            Text("Creates one RhythmX file with your cycles, entries, tags and settings. Save it to Files or iCloud Drive.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Protect with a passphrase", isOn: Binding(
                get: { usePassphrase },
                set: { value in
                    if reduceMotion { usePassphrase = value } else { withAnimation { usePassphrase = value } }
                }
            ))
            .tint(DS.Color.accent)
            .font(DS.Font.label)
            .disabled(model.isWorking)

            if usePassphrase {
                SecureField("Passphrase", text: $passphrase)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isWorking)
                SecureField("Confirm passphrase", text: $confirmation)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isWorking)
                if !confirmation.isEmpty && passphrase != confirmation {
                    Text("The passphrases don't match.")
                        .font(DS.Font.caption).foregroundColor(.red)
                }
                Label("If you forget it, nobody can recover the file, including us.", systemImage: "exclamationmark.triangle")
                    .font(DS.Font.caption).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage).font(DS.Font.caption).foregroundColor(.red)
            }

            if let exportURL {
                Text("Your backup is ready: \(exportURL.lastPathComponent)")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                ShareLink(item: exportURL) {
                    Text("Save or share the file")
                        .font(DS.Font.label.weight(.semibold))
                        .foregroundColor(DS.Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(DS.Color.accent)
                        .cornerRadius(DS.Radius.button)
                }
                .accessibilityHint("Opens the share sheet to save the backup file")
            } else if model.isWorking {
                ProgressView("Creating your backup…")
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                PrimaryButton(title: "Create backup", action: createBackup, isDisabled: !passphraseReady)
                    .accessibilityHint(usePassphrase ? "Creates a file protected by your passphrase" : "Creates a file without a passphrase")
            }
        }
        .cardStyle()
    }

    private func createBackup() {
        guard !model.isWorking else { return }
        errorMessage = nil
        let chosen = usePassphrase ? passphrase : nil
        Task {
            do {
                exportURL = try await model.createBackup(passphrase: chosen)
            } catch {
                errorMessage = "The backup could not be created. Try again."
            }
        }
    }

    // MARK: Restore

    private var restoreCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Restore").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            Text("Open a RhythmX file from Files, AirDrop or Mail.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            SecondaryButton(title: "Choose a file") { showImporter = true }
        }
        .cardStyle()
    }

    // MARK: Saved copies

    private func refreshSavedCopies() {
        Task { await model.refreshSavedCopies() }
    }

    private var savedCopiesCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Saved copies").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
                .accessibilityAddTraits(.isHeader)
            if model.savedCopies.isEmpty {
                Text("No saved copies. A copy is saved automatically before a Replace restore.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Kept on this phone only. Copies from before a restore are kept for 30 days, up to three at a time. The copy from before the update stays until you delete it.")
                    .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(model.savedCopies.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    savedCopyRow(row)
                }
            }
            if let error = model.savedCopiesError {
                Text(error).font(DS.Font.caption).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func savedCopyRow(_ row: BackupViewModel.SavedCopyRow) -> some View {
        let label = BackupViewModel.label(for: row.copy.kind)
        let date = row.copy.date.formatted(date: .abbreviated, time: .shortened)
        let spoken = "\(label), \(date)"
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(label).font(DS.Font.label.weight(.semibold)).foregroundColor(DS.Color.primaryText)
                Text(date).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                Text(contentsText(row.preview)).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.xs))
                : AnyLayout(HStackLayout(spacing: DS.Spacing.md))) {
                Button("Restore") { incoming = IncomingBackup(url: row.copy.url) }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Restore the copy \(spoken)")
                ShareLink(item: row.copy.url) { Text("Save") }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Save the copy \(spoken)")
                    .accessibilityHint("Opens the share sheet to save the file")
                Button("Delete", role: .destructive) { pendingDelete = row.copy }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Delete the copy \(spoken)")
            }
            .font(DS.Font.label)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func contentsText(_ preview: BackupPreview?) -> String {
        guard let preview else { return "This copy can't be read." }
        let cycles = "\(preview.cycleCount) \(preview.cycleCount == 1 ? "cycle" : "cycles")"
        let entries = "\(preview.eventCount) \(preview.eventCount == 1 ? "entry" : "entries")"
        return "\(cycles), \(entries)"
    }

    // MARK: Status

    private var statusCard: some View {
        Text(statusText)
            .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .cardStyle()
    }

    private var statusText: String {
        model.lastBackupDate.map { "Last backup: \($0.formatted(date: .abbreviated, time: .omitted))." }
            ?? "Last backup: never."
    }
}

// MARK: - Restore flow

struct IncomingBackup: Identifiable {
    let id = UUID()
    let url: URL
}

/// Restore flow for a file opened from outside the app. Owns its own view model.
struct RestoreSheet: View {
    let url: URL
    @EnvironmentObject var myEvents: EventStore
    @EnvironmentObject var archivedDataStore: ArchivedDataStore
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        RestoreSheetContent(url: url, events: myEvents, archived: archivedDataStore, settings: appSettings)
    }
}

private struct RestoreSheetContent: View {
    let url: URL
    @StateObject private var model: BackupViewModel

    init(url: URL, events: EventStore, archived: ArchivedDataStore, settings: AppSettings) {
        self.url = url
        _model = StateObject(wrappedValue: BackupViewModel(events: events, archived: archived, settings: settings))
    }

    var body: some View {
        RestoreView(model: model, url: url)
    }
}

struct RestoreView: View {
    @ObservedObject var model: BackupViewModel
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Set after a restore that brought events in, so onboarding cannot overwrite them.
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false

    private enum Stage: Equatable {
        case loading
        case failed(String)
        case locked
        case ready
        case done(String)
    }

    @State private var stage: Stage = .loading
    @State private var passphrase = ""
    @State private var unlockError: String?
    @State private var confirmReplace = false
    @State private var restoreError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text(model.fileName ?? url.lastPathComponent)
                        .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                        .accessibilityLabel("File: \(model.fileName ?? url.lastPathComponent)")
                    content
                }
                .padding(DS.Spacing.md)
            }
            .themedPage()
            .navigationTitle("Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .done = stage {
                        EmptyView()
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .alert("Replace everything on this phone?", isPresented: $confirmReplace) {
                Button("Replace", role: .destructive) { performRestore(.replace) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your cycles, entries and settings on this phone will be replaced with the ones in this file. A copy of your current data is kept on this phone for 30 days, so you can undo this from Backup.")
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .failed(let message):
            messageCard(title: "Can't open this file", message: message)
            PrimaryButton(title: "Close") { dismiss() }
        case .locked:
            lockedCard
        case .ready:
            insideCard
            modeCard
            if let restoreError {
                Text(restoreError).font(DS.Font.caption).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: "Restore") {
                if model.selectedMode == .replace { confirmReplace = true } else { performRestore(.merge) }
            }
            Text("Replace asks you to confirm first.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        case .done(let message):
            messageCard(title: "Restore finished", message: message)
            PrimaryButton(title: "Done") { dismiss() }
        }
    }

    private func messageCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title).font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            Text(message).font(DS.Font.label).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: Locked

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("This file has a passphrase").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            Text("Enter the passphrase used when the backup was made.")
                .font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Passphrase", text: $passphrase)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(unlock)
                .disabled(model.isWorking)
            if let unlockError {
                Text(unlockError).font(DS.Font.caption).foregroundColor(.red)
            }
            if model.isWorking {
                ProgressView("Checking the passphrase…")
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                PrimaryButton(title: "Unlock", action: unlock, isDisabled: passphrase.isEmpty)
            }
        }
        .cardStyle()
    }

    // MARK: Ready

    private var insideCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("What's inside").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            if let preview = model.preview {
                infoRow("Cycles", "\(preview.cycleCount)")
                infoRow("Entries", "\(preview.eventCount)")
                infoRow("Dates", dateRange(preview))
            }
            if let header = model.header {
                infoRow("Saved with", "RhythmX \(header.appVersion)")
                infoRow("Saved on", header.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .cardStyle()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.xs))
            : AnyLayout(HStackLayout())) {
            Text(label).font(DS.Font.label).foregroundColor(DS.Color.secondaryText)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: DS.Spacing.sm) }
            Text(value).font(DS.Font.label.weight(.semibold)).foregroundColor(DS.Color.primaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func dateRange(_ preview: BackupPreview) -> String {
        guard let earliest = preview.earliest, let latest = preview.latest else { return "None" }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).year()
        let first = earliest.formatted(style)
        let last = latest.formatted(style)
        return first == last ? first : "\(first) to \(last)"
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("How to restore").font(DS.Font.sectionHeader).foregroundColor(DS.Color.primaryText)
            modeRow(.merge, title: "Merge", detail: "Keep what's here, add what's missing")
            modeRow(.replace, title: "Replace", detail: "Swap everything on this phone for the file")
        }
        .cardStyle()
    }

    private func modeRow(_ mode: RestoreMode, title: String, detail: String) -> some View {
        let selected = model.selectedMode == mode
        return Button { model.selectedMode = mode } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? DS.Color.accent : DS.Color.tertiaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(title).font(DS.Font.label.weight(.semibold)).foregroundColor(DS.Color.primaryText)
                    Text(detail).font(DS.Font.caption).foregroundColor(DS.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(selected ? DS.Color.accent : DS.Color.separator, lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Actions

    private func load() async {
        guard stage == .loading else { return }
        do {
            let header = try model.loadFile(url)
            if header.isEncrypted {
                stage = .locked
            } else {
                _ = try await model.unlock(passphrase: nil)
                stage = .ready
            }
        } catch {
            stage = .failed(BackupViewModel.message(for: error))
        }
    }

    private func unlock() {
        guard !passphrase.isEmpty, !model.isWorking else { return }
        let entered = passphrase
        unlockError = nil
        Task {
            do {
                _ = try await model.unlock(passphrase: entered)
                passphrase = ""
                stage = .ready
            } catch BackupFileError.wrongPassphrase {
                unlockError = BackupViewModel.message(for: BackupFileError.wrongPassphrase)
            } catch {
                stage = .failed(BackupViewModel.message(for: error))
            }
        }
    }

    private func performRestore(_ mode: RestoreMode) {
        let result: RestoreResult
        do {
            result = try model.restore(mode)
        } catch {
            restoreError = BackupViewModel.message(for: error)
            return
        }
        restoreError = nil
        if result.eventsAdded > 0 { didFinishOnboarding = true }
        switch mode {
        case .merge:
            if result.eventsAdded == 0 && result.blocksAdded == 0 && result.eventsUpdated == 0 {
                stage = .done("Everything in this file was already on this phone. Nothing was added.")
            } else {
                var text = "Added \(countText(result.eventsAdded, "entry", "entries")) and \(countText(result.blocksAdded, "cycle", "cycles"))."
                if result.eventsUpdated > 0 {
                    text += " Tags from the file were added to \(countText(result.eventsUpdated, "entry", "entries")) already on this phone."
                }
                stage = .done(text)
            }
        case .replace:
            stage = .done("Your data now matches the file: \(countText(result.eventsAdded, "entry", "entries")) and \(countText(result.blocksAdded, "cycle", "cycles")). Changed your mind? Open Backup to go back to the copy saved before this restore.")
        }
    }

    private func countText(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

#Preview {
    NavigationStack {
        BackupView()
    }
    .environmentObject(EventStore(preview: true))
    .environmentObject(ArchivedDataStore())
    .environmentObject(AppSettings())
}
