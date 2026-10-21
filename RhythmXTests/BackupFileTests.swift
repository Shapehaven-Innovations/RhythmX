import XCTest
@testable import RhythmX

final class BackupFileTests: XCTestCase {
    private let fastIterations = 1_000

    // MARK: - Fixtures

    private func samplePayload() -> BackupPayload {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let events = [
            Event(id: "e1", eventType: .menstrual, date: base, note: "Start", tags: "#cramps"),
            Event(id: "e2", eventType: .ovulation, date: base.addingTimeInterval(14 * day), note: "", tags: "", mode: .planning)
        ]
        let block = ArchivedDataBlock(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            date: base.addingTimeInterval(30 * day),
            groupedEvents: [ArchivedDataBlock.PhaseEvents(eventType: .menstrual, events: [events[0]])],
            mode: .cycle
        )
        let settings = BackupSettings(
            phaseColors: ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"],
            notificationsEnabled: true,
            notifyDayBefore: true,
            notifyDayOf: false,
            fertileStartOn: true,
            fertileOvulationOn: false,
            trackingMode: "cycle",
            defaultModeOnLaunch: "last",
            themeID: "default",
            weeklyCheckIn: nil
        )
        return BackupPayload(events: events, archivedBlocks: [block], settings: settings)
    }

    private func canonicalJSON(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(payload)
    }

    private func envelope(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func bodyBlob(_ data: Data) throws -> Data {
        let body = try XCTUnwrap(envelope(data)["body"] as? String)
        return try XCTUnwrap(Data(base64Encoded: body))
    }

    private func assertThrows(_ expected: BackupFileError, file: StaticString = #filePath, line: UInt = #line, _ block: () throws -> Void) {
        do {
            try block()
            XCTFail("Expected \(expected) but nothing was thrown", file: file, line: line)
        } catch let error as BackupFileError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected) but got \(error)", file: file, line: line)
        }
    }

    // MARK: - Round trips

    func testPlainRoundTrip() throws {
        let payload = samplePayload()
        let data = try BackupFile.make(payload, appVersion: "2.0.0", passphrase: nil)
        let restored = try BackupFile.open(data, passphrase: nil)
        XCTAssertEqual(try canonicalJSON(restored), try canonicalJSON(payload))
        XCTAssertEqual(restored.settings, payload.settings)
    }

    func testEncryptedRoundTrip() throws {
        let payload = samplePayload()
        let data = try BackupFile.make(payload, appVersion: "2.0.0", passphrase: "moon river", iterations: fastIterations)
        let restored = try BackupFile.open(data, passphrase: "moon river")
        XCTAssertEqual(try canonicalJSON(restored), try canonicalJSON(payload))
    }

    func testEncryptedBodyDoesNotContainPlaintext() throws {
        let data = try BackupFile.make(samplePayload(), appVersion: "2.0.0", passphrase: "pw", iterations: fastIterations)
        let blob = try bodyBlob(data)
        XCTAssertNil(blob.range(of: Data("#cramps".utf8)))
        XCTAssertNil(data.range(of: Data("#cramps".utf8)))
    }

    // MARK: - Passphrase handling

    func testWrongPassphraseThrowsWrongPassphrase() throws {
        let data = try BackupFile.make(samplePayload(), appVersion: "2.0.0", passphrase: "right", iterations: fastIterations)
        assertThrows(.wrongPassphrase) { _ = try BackupFile.open(data, passphrase: "wrong") }
    }

    func testEncryptedFileNeedsPassphrase() throws {
        let data = try BackupFile.make(samplePayload(), appVersion: "2.0.0", passphrase: "right", iterations: fastIterations)
        assertThrows(.wrongPassphrase) { _ = try BackupFile.open(data, passphrase: nil) }
    }

    func testInspectNeedsNoPassphrase() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let data = try BackupFile.make(samplePayload(), appVersion: "2.0.0", passphrase: "secret", iterations: fastIterations, now: now)
        let header = try BackupFile.inspect(data)
        XCTAssertEqual(header, BackupHeader(formatVersion: BackupFile.currentFormat, appVersion: "2.0.0", createdAt: now, isEncrypted: true))

        let plain = try BackupFile.make(samplePayload(), appVersion: "2.0.0", passphrase: nil, now: now)
        XCTAssertFalse(try BackupFile.inspect(plain).isEncrypted)
    }

    // MARK: - Format version

    func testNewerFormatIsRefusedBeforeDecoding() throws {
        // A future file whose body this version could not possibly decode.
        let future: [String: Any] = [
            "formatVersion": 99,
            "appVersion": "9.0.0",
            "createdAt": "2030-01-01T00:00:00Z",
            "encrypted": false,
            "body": Data("{\"somethingNew\":true}".utf8).base64EncodedString()
        ]
        let data = try JSONSerialization.data(withJSONObject: future)
        assertThrows(.newerFormat(99)) { _ = try BackupFile.inspect(data) }
        assertThrows(.newerFormat(99)) { _ = try BackupFile.open(data, passphrase: nil) }

        // Even with only the version key present, the version is what is reported.
        let bare = try JSONSerialization.data(withJSONObject: ["formatVersion": 99])
        assertThrows(.newerFormat(99)) { _ = try BackupFile.inspect(bare) }
        assertThrows(.newerFormat(99)) { _ = try BackupFile.open(bare, passphrase: "x") }
    }

    func testFileExtension() {
        XCTAssertEqual(BackupFile.fileExtension, "rhythmx")
        XCTAssertEqual(BackupFile.currentFormat, 1)
    }

    // MARK: - Damaged input

    func testTruncatedFileThrowsCorrupted() throws {
        let data = try BackupFile.make(samplePayload(), appVersion: "2.0.0", passphrase: nil)
        let truncated = data.prefix(data.count / 2)
        assertThrows(.corrupted) { _ = try BackupFile.inspect(Data(truncated)) }
        assertThrows(.corrupted) { _ = try BackupFile.open(Data(truncated), passphrase: nil) }
    }

    func testTruncatedEncryptedBodyThrowsCorrupted() throws {
        let data = try BackupFile.make(samplePayload(), appVersion: "2.0.0", passphrase: "pw", iterations: fastIterations)
        var env = try envelope(data)
        let blob = try bodyBlob(data)
        env["body"] = Data(blob.prefix(25)).base64EncodedString()
        let damaged = try JSONSerialization.data(withJSONObject: env)
        assertThrows(.corrupted) { _ = try BackupFile.open(damaged, passphrase: "pw") }
    }

    func testUnparseablePlainBodyThrowsCorrupted() throws {
        let data = try BackupFile.make(samplePayload(), appVersion: "2.0.0", passphrase: nil)
        var env = try envelope(data)
        env["body"] = Data("not a payload".utf8).base64EncodedString()
        let damaged = try JSONSerialization.data(withJSONObject: env)
        assertThrows(.corrupted) { _ = try BackupFile.open(damaged, passphrase: nil) }
    }

    func testRandomBytesThrowNotABackup() throws {
        var random = Data(count: 512)
        for i in random.indices { random[i] = UInt8.random(in: 0...255) }
        random[0] = 0x00 // never a JSON object start
        assertThrows(.notABackup) { _ = try BackupFile.inspect(random) }
        assertThrows(.notABackup) { _ = try BackupFile.open(random, passphrase: nil) }

        let otherJSON = try JSONSerialization.data(withJSONObject: ["hello": "world"])
        assertThrows(.notABackup) { _ = try BackupFile.inspect(otherJSON) }
        assertThrows(.notABackup) { _ = try BackupFile.open(otherJSON, passphrase: nil) }

        let missingKeys = try JSONSerialization.data(withJSONObject: ["formatVersion": 1, "appVersion": "2.0.0"])
        assertThrows(.notABackup) { _ = try BackupFile.inspect(missingKeys) }

        assertThrows(.notABackup) { _ = try BackupFile.inspect(Data()) }
    }

    // MARK: - Crypto

    func testSealUsesFreshSaltAndNonce() throws {
        let plain = Data("same data".utf8)
        let a = try BackupCrypto.seal(plain, passphrase: "pw", iterations: fastIterations)
        let b = try BackupCrypto.seal(plain, passphrase: "pw", iterations: fastIterations)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.prefix(16), b.prefix(16), "salt must be fresh")
        // AES.GCM combined layout: 12-byte nonce follows salt (16) and iteration count (4).
        XCTAssertNotEqual(a.subdata(in: 20..<32), b.subdata(in: 20..<32), "nonce must be fresh")
        XCTAssertEqual(try BackupCrypto.open(a, passphrase: "pw"), plain)
        XCTAssertEqual(try BackupCrypto.open(b, passphrase: "pw"), plain)
    }

    func testDefaultIterationCountIsAtLeast600k() throws {
        let blob = try BackupCrypto.seal(Data("x".utf8), passphrase: "pw")
        let count = blob.subdata(in: 16..<20).reduce(0) { ($0 << 8) | Int($1) }
        XCTAssertGreaterThanOrEqual(count, 600_000)
    }

    func testStoredIterationCountIsBigEndian() throws {
        let blob = try BackupCrypto.seal(Data("x".utf8), passphrase: "pw", iterations: 0x1234)
        XCTAssertEqual(Array(blob.subdata(in: 16..<20)), [0x00, 0x00, 0x12, 0x34])
        XCTAssertEqual(try BackupCrypto.open(blob, passphrase: "pw"), Data("x".utf8))
    }

    func testAbsurdIterationCountIsRejected() throws {
        var blob = try BackupCrypto.seal(Data("x".utf8), passphrase: "pw", iterations: fastIterations)
        blob.replaceSubrange(16..<20, with: [0xFF, 0xFF, 0xFF, 0xFF])
        assertThrows(.corrupted) { _ = try BackupCrypto.open(blob, passphrase: "pw") }
        blob.replaceSubrange(16..<20, with: [0, 0, 0, 0])
        assertThrows(.corrupted) { _ = try BackupCrypto.open(blob, passphrase: "pw") }
    }

    func testIterationCapIsTwoMillion() throws {
        XCTAssertEqual(BackupCrypto.maxIterations, 2_000_000)
        var blob = try BackupCrypto.seal(Data("x".utf8), passphrase: "pw", iterations: fastIterations)
        // 2_000_001 big-endian: refused before any key derivation runs.
        blob.replaceSubrange(16..<20, with: [0x00, 0x1E, 0x84, 0x81])
        assertThrows(.corrupted) { _ = try BackupCrypto.open(blob, passphrase: "pw") }
    }

    func testShortBlobIsCorrupted() {
        assertThrows(.corrupted) { _ = try BackupCrypto.open(Data(count: 10), passphrase: "pw") }
    }

    // MARK: - Settings written by earlier builds

    /// Files written before 2.0 shipped carried `reminders: [String]` and `dailyCheckIn/weeklyCheckIn: String?`.
    /// They must still open; the placeholder values read as absent and the other fields as before.
    func testFormatOneBackupWithPlaceholderShapesStillOpens() throws {
        let settingsJSON: [String: Any] = [
            "phaseColors": ["#111111", "#222222", "#333333", "#444444"],
            "notificationsEnabled": true,
            "notifyDayBefore": false,
            "notifyDayOf": true,
            "fertileStartOn": false,
            "fertileOvulationOn": true,
            "trackingMode": "cycle",
            "defaultModeOnLaunch": "menopause",
            "themeID": "default",
            "reminders": ["old placeholder", "another"],
            "dailyCheckIn": "20:00",
            "weeklyCheckIn": "18:00",
            "dailyInsightsOn": "yes"
        ]
        let payloadJSON: [String: Any] = ["events": [], "archivedBlocks": [], "settings": settingsJSON]
        let body = try JSONSerialization.data(withJSONObject: payloadJSON)
        let envelope: [String: Any] = [
            "formatVersion": 1,
            "appVersion": "2.0.0",
            "createdAt": "2026-10-19T10:00:00Z",
            "encrypted": false,
            "body": body.base64EncodedString()
        ]
        let restored = try BackupFile.open(try JSONSerialization.data(withJSONObject: envelope), passphrase: nil)

        XCTAssertNil(restored.settings.weeklyCheckIn)
        XCTAssertNil(restored.settings.dailyInsightsOn, "a value of the wrong shape reads as absent")
        XCTAssertTrue(restored.settings.notificationsEnabled)
        XCTAssertTrue(restored.settings.notifyDayOf)
        XCTAssertTrue(restored.settings.fertileOvulationOn)
        XCTAssertEqual(restored.settings.defaultModeOnLaunch, "menopause")
        XCTAssertEqual(restored.settings.phaseColors.count, 4)
    }
}
