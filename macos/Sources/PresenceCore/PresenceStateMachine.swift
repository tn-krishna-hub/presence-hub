import Foundation

public enum PresenceState: String, Codable, Equatable, Sendable {
    case home
    case away
}

public enum PresenceTransition: Equatable, Sendable {
    case none
    case home
    case away
}

public struct PresenceConfig: Equatable, Sendable {
    /// RSSI (dBm) at or above which the beacon is considered "in range".
    public var signalThreshold: Int
    /// Consecutive out-of-range samples required to flip home → away. Guards against single-sample BT blips.
    public var awayConfirmations: Int
    /// Consecutive in-range samples required to flip away → home.
    public var homeConfirmations: Int
    /// If no sample arrives within this window, treat the beacon as gone.
    public var staleTimeout: TimeInterval

    public init(
        signalThreshold: Int = -80,
        awayConfirmations: Int = 3,
        homeConfirmations: Int = 3,
        staleTimeout: TimeInterval = 15
    ) {
        self.signalThreshold = signalThreshold
        self.awayConfirmations = awayConfirmations
        self.homeConfirmations = homeConfirmations
        self.staleTimeout = staleTimeout
    }
}

/// Pure, synchronous presence decision engine.
///
/// Feed it RSSI samples over time; it only emits a transition when a change is
/// actually *confirmed* (consecutive samples or a stale-data timeout), so a
/// momentary BLE hiccup can never lock your screen mid-typing.
public struct PresenceStateMachine: Sendable {
    public private(set) var state: PresenceState = .home

    /// How many consecutive out-of-range samples have built up so far. Exposed for
    /// diagnostics (signal log / live UI) to show "how close" a lock actually is.
    public private(set) var awayStreak: Int = 0
    private var homeStreak = 0
    private var lastSampleAt: Date?

    public init() {}

    public mutating func update(rssi: Int, at date: Date, config: PresenceConfig) -> PresenceTransition {
        defer { lastSampleAt = date }

        // Stale data (beacon stopped advertising) → treat as gone.
        if let last = lastSampleAt, date.timeIntervalSince(last) > config.staleTimeout {
            awayStreak = 0
            homeStreak = 0
            guard state != .away else { return .none }
            state = .away
            return .away
        }

        if rssi >= config.signalThreshold {
            awayStreak = 0
            homeStreak += 1
            guard state == .away, homeStreak >= config.homeConfirmations else { return .none }
            state = .home
            homeStreak = 0
            return .home
        } else {
            homeStreak = 0
            awayStreak += 1
            guard state == .home, awayStreak >= config.awayConfirmations else { return .none }
            state = .away
            awayStreak = 0
            return .away
        }
    }

    /// The effective state at a point in time, including staleness.
    public func resolvedState(at date: Date, config: PresenceConfig) -> PresenceState {
        if let last = lastSampleAt, date.timeIntervalSince(last) > config.staleTimeout {
            return .away
        }
        return state
    }

    /// Forces the machine to the effective (stale-aware) state.
    /// Only ever forces **away** — staleness means the beacon is gone, so it can
    /// confirm a departure that plain samples never will. Returning **home** still
    /// requires the normal in-range confirmations, never a forced flip.
    public mutating func resolve(at date: Date, config: PresenceConfig) -> PresenceTransition {
        guard state != .away,
              resolvedState(at: date, config: config) == .away
        else { return .none }

        state = .away
        awayStreak = 0
        homeStreak = 0
        return .away
    }
}