import Foundation

enum ReceiverConfig {
    static var port: UInt16 {
        if let raw = ProcessInfo.processInfo.environment["GITTRACKER_PORT"],
           let value = UInt16(raw) {
            return value
        }
        return 8787
    }

    static var databasePath: String {
        if let raw = ProcessInfo.processInfo.environment["GITTRACKER_DB"], !raw.isEmpty {
            return raw
        }
        let base = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GitTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("runs.sqlite").path
    }

    static var secret: String? {
        if let raw = ProcessInfo.processInfo.environment["GITTRACKER_WEBHOOK_SECRET"], !raw.isEmpty {
            return raw
        }
        let path = secretFilePath
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let trimmed = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var secretFilePath: String {
        if let raw = ProcessInfo.processInfo.environment["GITTRACKER_SECRET_FILE"], !raw.isEmpty {
            return raw
        }
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gittracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("webhook-secret").path
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var isoNow: String {
        formatter.string(from: Date())
    }

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("[\(stamp)] \(message)")
        fflush(stdout)
    }
}
