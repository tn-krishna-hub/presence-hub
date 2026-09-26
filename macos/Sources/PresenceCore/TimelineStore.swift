import Foundation

public struct TimelineEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let state: PresenceState
    public let rssi: Int?

    public init(timestamp: Date, state: PresenceState, rssi: Int?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.state = state
        self.rssi = rssi
    }
}

/// Append-only local event log (NDJSON). No cloud, no telemetry — the file is yours.
public final class TimelineStore {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Presence", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("timeline.jsonl")
    }

    public func append(_ event: TimelineEvent) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard
            let data = try? encoder.encode(event),
            var line = String(data: data, encoding: .utf8)
        else { return }

        line += "\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: fileURL)
        }
    }

    public func load() -> [TimelineEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var events: [TimelineEvent] = []
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            if let event = try? decoder.decode(TimelineEvent.self, from: Data(line.utf8)) {
                events.append(event)
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }
}