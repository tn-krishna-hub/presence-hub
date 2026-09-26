import Foundation

/// Append-only CSV of every fed signal sample, so a failed walk-away experiment
/// can be diagnosed with actual numbers (how low RSSI got, how close the away
/// streak came) instead of guessing. Roughly one line per 0.5 s while hearing
/// the beacon.
public final class SignalLogger: @unchecked Sendable {

    public let fileURL: URL
    private let handle: FileHandle?

    public init?(directory: URL) {
        let url = directory.appendingPathComponent("signal.log")
        fileURL = url

        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let exists = manager.fileExists(atPath: url.path)
        guard let handle = FileHandle(forWritingAtPath: url.path) ?? FileHandle(forWritingAtPath: {
            manager.createFile(atPath: url.path, contents: nil)
            return url.path
        }())
        else { return nil }
        self.handle = handle
        if !exists {
            write("timestamp,smoothed,state,threshold,awayStreak\n")
        }
    }

    public func append(date: Date, smoothed: Int?, threshold: Int, state: PresenceState, awayStreak: Int) {
        let iso = ISO8601DateFormatter().string(from: date)
        let rssi = smoothed.map(String.init) ?? "-"
        write("\(iso),\(rssi),\(state.rawValue),\(threshold),\(awayStreak)\n")
    }

    private func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        try? handle?.seekToEnd()
        try? handle?.write(contentsOf: data)
    }
}