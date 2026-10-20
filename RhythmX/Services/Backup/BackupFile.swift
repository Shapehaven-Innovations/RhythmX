//
//  BackupFile.swift
//
//  The `.rhythmx` backup file: a versioned JSON envelope
//  `{ formatVersion, appVersion, createdAt, encrypted, body }` where `body` is the
//  base64 of the JSON-encoded `BackupPayload`, sealed with `BackupCrypto` when a passphrase is set.
//  Purchases are never part of a backup.
//

import Foundation

struct BackupPayload: Codable {
    var events: [Event]
    var archivedBlocks: [ArchivedDataBlock]
    var settings: BackupSettings
}

struct BackupSettings: Codable, Equatable {
    var phaseColors: [String]
    var notificationsEnabled: Bool
    var notifyDayBefore: Bool
    var notifyDayOf: Bool
    var fertileStartOn: Bool
    var fertileOvulationOn: Bool
    var trackingMode: String
    var defaultModeOnLaunch: String
    var themeID: String
    /// Nil when the file carried no readable reminder list; a restore then leaves the stored list alone.
    var reminders: [LoggingReminder]?
    var dailyCheckIn: CheckInSetting?
    var weeklyCheckIn: CheckInSetting?
}

extension BackupSettings {
    /// Format 1 files written before 2.0 shipped carried `reminders` as `[String]` and the check-ins as
    /// `String?`. Those three are read leniently: anything that is not the current shape reads as absent
    /// (nil), so such a file still opens and a restore does not clear what the device has. Every other
    /// field decodes as synthesized; encoding is synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phaseColors = try c.decode([String].self, forKey: .phaseColors)
        notificationsEnabled = try c.decode(Bool.self, forKey: .notificationsEnabled)
        notifyDayBefore = try c.decode(Bool.self, forKey: .notifyDayBefore)
        notifyDayOf = try c.decode(Bool.self, forKey: .notifyDayOf)
        fertileStartOn = try c.decode(Bool.self, forKey: .fertileStartOn)
        fertileOvulationOn = try c.decode(Bool.self, forKey: .fertileOvulationOn)
        trackingMode = try c.decode(String.self, forKey: .trackingMode)
        defaultModeOnLaunch = try c.decode(String.self, forKey: .defaultModeOnLaunch)
        themeID = try c.decode(String.self, forKey: .themeID)
        reminders = (try? c.decodeIfPresent([LoggingReminder].self, forKey: .reminders)) ?? nil
        dailyCheckIn = (try? c.decodeIfPresent(CheckInSetting.self, forKey: .dailyCheckIn)) ?? nil
        weeklyCheckIn = (try? c.decodeIfPresent(CheckInSetting.self, forKey: .weeklyCheckIn)) ?? nil
    }
}

struct BackupHeader: Equatable {
    let formatVersion: Int
    let appVersion: String
    let createdAt: Date
    let isEncrypted: Bool
}

enum BackupFileError: Error, Equatable {
    case notABackup
    case newerFormat(Int)
    case wrongPassphrase
    case corrupted
}

enum BackupFile {
    static let currentFormat = 1
    static let fileExtension = "rhythmx"

    private struct Envelope: Codable {
        let formatVersion: Int
        let appVersion: String
        let createdAt: Date
        let encrypted: Bool
        let body: Data
    }

    /// Builds a backup file. A nil or empty passphrase writes an unencrypted file.
    static func make(
        _ payload: BackupPayload,
        appVersion: String,
        passphrase: String?,
        iterations: Int = BackupCrypto.defaultIterations,
        now: Date = Date()
    ) throws -> Data {
        let payloadData = try JSONEncoder().encode(payload)
        let encrypted: Bool
        let body: Data
        if let passphrase, !passphrase.isEmpty {
            body = try BackupCrypto.seal(payloadData, passphrase: passphrase, iterations: iterations)
            encrypted = true
        } else {
            body = payloadData
            encrypted = false
        }
        let envelope = Envelope(
            formatVersion: currentFormat,
            appVersion: appVersion,
            createdAt: now,
            encrypted: encrypted,
            body: body
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    /// Reads the header without a passphrase and without decoding the payload.
    static func inspect(_ data: Data) throws -> BackupHeader {
        let envelope = try readEnvelope(data)
        return BackupHeader(
            formatVersion: envelope.formatVersion,
            appVersion: envelope.appVersion,
            createdAt: envelope.createdAt,
            isEncrypted: envelope.encrypted
        )
    }

    static func open(_ data: Data, passphrase: String?) throws -> BackupPayload {
        let envelope = try readEnvelope(data)
        let payloadData: Data
        if envelope.encrypted {
            guard let passphrase, !passphrase.isEmpty else { throw BackupFileError.wrongPassphrase }
            payloadData = try BackupCrypto.open(envelope.body, passphrase: passphrase)
        } else {
            payloadData = envelope.body
        }
        do {
            return try JSONDecoder().decode(BackupPayload.self, from: payloadData)
        } catch {
            throw BackupFileError.corrupted
        }
    }

    // MARK: - Envelope

    /// Checks the format version before anything else is decoded, so a newer file is refused untouched.
    private static func readEnvelope(_ data: Data) throws -> Envelope {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw looksLikeBackup(data) ? BackupFileError.corrupted : BackupFileError.notABackup
        }
        guard let dictionary = object as? [String: Any],
              let version = dictionary["formatVersion"] as? Int else {
            throw BackupFileError.notABackup
        }
        if version > currentFormat { throw BackupFileError.newerFormat(version) }
        guard version >= 1 else { throw BackupFileError.notABackup }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Envelope.self, from: data)
        } catch DecodingError.dataCorrupted {
            // Keys present but a value is malformed, e.g. a body that is not valid base64.
            throw BackupFileError.corrupted
        } catch {
            throw BackupFileError.notABackup
        }
    }

    /// True when unparseable bytes still start like one of our envelopes (a truncated or damaged file).
    private static func looksLikeBackup(_ data: Data) -> Bool {
        guard let first = data.first(where: { !$0.isASCIIWhitespace }), first == UInt8(ascii: "{") else {
            return false
        }
        // Keys are written sorted, so "appVersion" leads the file and survives truncation.
        return ["\"appVersion\"", "\"formatVersion\""].contains { key in
            data.range(of: Data(key.utf8)) != nil
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}
