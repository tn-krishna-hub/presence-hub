import AppKit
import ApplicationServices
import Combine
import CoreBluetooth
import Foundation
import UserNotifications
import PresenceCore

/// Main-thread coordinator: owns the scanner, the state machine, the lock trigger
/// and the timeline. All UI observes this single object.
@MainActor
final class PresenceModel: ObservableObject {
    @Published private(set) var state: PresenceState = .home
    @Published private(set) var lastRssi: Int?
    @Published private(set) var btState: CBManagerState = .unknown
    @Published private(set) var scannerActive = false
    @Published var timeline: [TimelineEvent] = []

    @Published var identityUUIDString: String {
        didSet {
            UserDefaults.standard.set(identityUUIDString, forKey: Keys.identity)
            restartScanner()
        }
    }
    @Published var autoLockEnabled: Bool {
        didSet { UserDefaults.standard.set(autoLockEnabled, forKey: Keys.autoLock) }
    }
    @Published var notifyOnReturn: Bool {
        didSet { UserDefaults.standard.set(notifyOnReturn, forKey: Keys.notify) }
    }
    @Published var signalThreshold: Int {
        didSet { UserDefaults.standard.set(signalThreshold, forKey: Keys.threshold) }
    }
    @Published var awayConfirmations: Int {
        didSet { UserDefaults.standard.set(awayConfirmations, forKey: Keys.away) }
    }
    @Published var homeConfirmations: Int {
        didSet { UserDefaults.standard.set(homeConfirmations, forKey: Keys.home) }
    }
    @Published var staleTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(staleTimeout, forKey: Keys.stale) }
    }
    @Published var accessibilityTrusted: Bool = AXIsProcessTrusted()

    /// Calibration flow state.
    @Published private(set) var calHere: Int?
    @Published private(set) var calFar: Int?
    @Published private(set) var calMessage: String = "Stand where you use the laptop, then tap “Sample here”."

    /// Average of recent (feed-throttled) RSSI samples — calmer than a single reading.
    var averageRssi: Int? {
        if !rssiWindow.isEmpty {
            return rssiWindow.reduce(0, +) / rssiWindow.count
        }
        return lastRssi
    }

    /// Current signal minus the lock threshold. Positive = safely in range;
    /// ≤ 0 means the phone would already be counted as away while you sit here.
    var headroom: Int? {
        averageRssi.map { $0 - signalThreshold }
    }

    private enum Keys {
        static let identity = "identity.uuid"
        static let autoLock = "behavior.autolock"
        static let notify = "behavior.notify"
        static let threshold = "tuning.threshold"
        static let away = "tuning.away"
        static let home = "tuning.home"
        static let stale = "tuning.stale"
        static let notifiedRequested = "notifications.requested"
    }

    private var config: PresenceConfig {
        PresenceConfig(
            signalThreshold: signalThreshold,
            awayConfirmations: awayConfirmations,
            homeConfirmations: homeConfirmations,
            staleTimeout: staleTimeout
        )
    }

    private let defaults = UserDefaults.standard
    private let timelineStore = TimelineStore()
    private let signalLog: SignalLogger?
    private var stateMachine = PresenceStateMachine()
    private var scanner: BLEPresenceScanner?
    private var rssiWindow: [Int] = []
    private var lastFeedAt: Date?
    private var staleTimer: Timer?

    var timelineFileURL: URL { timelineStore.fileURL }
    var signalLogFileURL: URL? { signalLog?.fileURL }

    init() {
        identityUUIDString = defaults.string(forKey: Keys.identity) ?? ""
        autoLockEnabled = defaults.object(forKey: Keys.autoLock) as? Bool ?? true
        notifyOnReturn = defaults.object(forKey: Keys.notify) as? Bool ?? true
        signalThreshold = defaults.object(forKey: Keys.threshold) as? Int ?? -80
        awayConfirmations = defaults.object(forKey: Keys.away) as? Int ?? 3
        homeConfirmations = defaults.object(forKey: Keys.home) as? Int ?? 3
        staleTimeout = defaults.object(forKey: Keys.stale) as? TimeInterval ?? 15
        timeline = timelineStore.load()
        signalLog = SignalLogger(directory: timelineStore.fileURL.deletingLastPathComponent())
        requestNotificationPermission()
        startScanner()
        startStaleCheckTimer()
        logLockDiag("launch ax=\(AXIsProcessTrusted())")
    }

    private func logLockDiag(_ message: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/presence_lock.log")
        let line = (Date().ISO8601Format() + " " + message + "\n").data(using: .utf8) ?? Data()
        if let handle = FileHandle(forWritingAtPath: url.path) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            _ = FileManager.default.createFile(atPath: url.path, contents: line)
        }
    }

    private func startStaleCheckTimer() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStale() }
        }
        RunLoop.main.add(timer, forMode: .common)
        staleTimer = timer
    }

    private var identityUUID: UUID? { UUID(uuidString: identityUUIDString) }

    private func startScanner() {
        scanner?.stop()
        scanner = nil
        stateMachine = PresenceStateMachine()
        lastFeedAt = nil

        guard let uuid = identityUUID else {
            scannerActive = false
            state = .home
            return
        }

        let scanner = BLEPresenceScanner(serviceUUID: uuid) { [weak self] rssi, date in
            Task { @MainActor in self?.feed(rssi: rssi, at: date) }
        }
        scanner.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.btState = state
                self?.lastRssi = nil
                if state != .poweredOn {
                    self?.stateMachine = PresenceStateMachine()
                    self?.state = .home
                    self?.scannerActive = false
                }
            }
        }
        self.scanner = scanner
        scannerActive = true
    }

    private func restartScanner() { startScanner() }

    private func feed(rssi: Int, at date: Date) {
        lastRssi = rssi
        if let last = lastFeedAt, date.timeIntervalSince(last) < 0.5 { return }
        lastFeedAt = date

        rssiWindow.append(rssi)
        if rssiWindow.count > 5 { rssiWindow.removeFirst() }
        let smoothed = rssiWindow.reduce(0, +) / rssiWindow.count

        signalLog?.append(
            date: date,
            smoothed: smoothed,
            threshold: signalThreshold,
            state: stateMachine.state,
            awayStreak: stateMachine.awayStreak
        )

        let transition = stateMachine.update(rssi: smoothed, at: date, config: config)
        state = stateMachine.state
        apply(transition, at: date, rssi: smoothed)
    }

    /// Staleness can only be judged by the clock, not by new samples — if the beacon
    /// simply stops advertising (killed app, phone BT off, walked totally out of range),
    /// no `feed` ever arrives, so a periodic nudge lets `resolve` confirm we're away.
    private func checkStale() {
        let transition = stateMachine.resolve(at: Date(), config: config)
        state = stateMachine.state
        apply(transition, at: Date(), rssi: lastRssi)
    }

    private func apply(_ transition: PresenceTransition, at date: Date, rssi: Int?) {
        switch transition {
        case .away:
            record(TimelineEvent(timestamp: date, state: .away, rssi: rssi))
            if autoLockEnabled {
                LockController.lockScreen()
            }
        case .home:
            record(TimelineEvent(timestamp: date, state: .home, rssi: rssi))
            if notifyOnReturn {
                sendReturnNotification(at: date)
            }
        case .none:
            break
        }
    }

    private func record(_ event: TimelineEvent) {
        timelineStore.append(event)
        timeline = timelineStore.load()
    }

    func lockNow() {
        LockController.lockScreen()
    }

    func refreshAccessibilityStatus() {
        if !accessibilityTrusted {
            let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            accessibilityTrusted = AXIsProcessTrustedWithOptions(prompt)
        } else {
            accessibilityTrusted = AXIsProcessTrusted()
        }
        logLockDiag("refresh ax=\(accessibilityTrusted)")
    }

    // MARK: - One-tap calibration

    func sampleHere() {
        guard let rssi = averageRssi else {
            calMessage = "Not hearing your phone yet — make sure the beacon is on."
            return
        }
        calHere = rssi
        calFar = nil
        calMessage = "Here: \(rssi) dBm. Now walk to your “far away” spot and tap “Sample far” (wait ~5 s first)."
    }

    func sampleFar() {
        guard let here = calHere else {
            calMessage = "Sample “here” first."
            return
        }
        if state == .away {
            calMessage = "The phone is fully out of range here — the timeout already locks it. No threshold change needed."
            return
        }
        guard let far = averageRssi else {
            calMessage = "No signal samples right now — wait until you see a dBm value, or walk a little."
            return
        }
        calFar = far
        let midpoint = (here + far) / 2
        let clamped = max(-110, min(-50, midpoint))
        signalThreshold = clamped
        calMessage = "Threshold set to \(clamped) dBm (here \(here), far \(far)). Try walking away again."
    }

    /// Short-range mode: anchor the lock line ~10 dB under wherever you are right
    /// now (e.g. sat at the desk). Leaving that spot by more than 10 dB = away.
    func setBoundaryHere() {
        guard let rssi = averageRssi else {
            calMessage = "Not hearing your phone yet — make sure the beacon is on."
            return
        }
        let target = max(-110, min(-50, rssi - 10))
        calMessage = "Boundary set at \(target) dBm (current \(rssi), 10 dB headroom). Leave your desk spot by >10 dB and it locks."
        calHere = rssi
        signalThreshold = target
    }

    func quit() {
        scanner?.stop()
        staleTimer?.invalidate()
        NSApp.terminate(nil)
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        guard defaults.bool(forKey: Keys.notifiedRequested) == false else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.defaults.set(true, forKey: Keys.notifiedRequested) }
        }
    }

    private func sendReturnNotification(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Phone is back"
        content.body = "Your phone is in range again."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}