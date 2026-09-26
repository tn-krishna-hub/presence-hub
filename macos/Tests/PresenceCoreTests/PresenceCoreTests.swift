import Foundation
@testable import PresenceCore
import XCTest

final class PresenceStateMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let config = PresenceConfig(
        signalThreshold: -80,
        awayConfirmations: 5,
        homeConfirmations: 3,
        staleTimeout: 15
    )

    // MARK: - Away confirmation

    func testStaysHomeWhileInRange() {
        var sm = PresenceStateMachine()
        for i in 0..<10 {
            let t = sm.update(rssi: -45, at: t0.addingTimeInterval(Double(i)), config: config)
            XCTAssertEqual(t, .none)
        }
        XCTAssertEqual(sm.state, .home)
    }

    func testConfirmsAwayOnlyAfterEnoughOutOfRangeSamples() {
        var sm = PresenceStateMachine()
        for i in 0..<4 {
            let t = sm.update(rssi: -90, at: t0.addingTimeInterval(Double(i)), config: config)
            XCTAssertEqual(t, .none, "should not flip before \(config.awayConfirmations) confirmations")
        }
        XCTAssertEqual(sm.state, .home)
        let transition = sm.update(rssi: -90, at: t0.addingTimeInterval(4), config: config)
        XCTAssertEqual(transition, .away)
        XCTAssertEqual(sm.state, .away)
    }

    func testSingleBlipDoesNotLock() {
        var sm = PresenceStateMachine()
        sm.update(rssi: -40, at: t0, config: config)
        // One momentary fade...
        sm.update(rssi: -95, at: t0.addingTimeInterval(1), config: config)
        // ...then back. Streak resets; no lock ever happened.
        let t = sm.update(rssi: -40, at: t0.addingTimeInterval(2), config: config)
        XCTAssertEqual(t, .none)
        XCTAssertEqual(sm.state, .home)
    }

    func testAwayStreakExposedForDiagnostics() {
        var sm = PresenceStateMachine()
        _ = sm.update(rssi: -40, at: t0, config: config)
        XCTAssertEqual(sm.awayStreak, 0)
        _ = sm.update(rssi: -95, at: t0.addingTimeInterval(1), config: config)
        XCTAssertEqual(sm.awayStreak, 1, "streak should count consecutive out-of-range samples")
        _ = sm.update(rssi: -95, at: t0.addingTimeInterval(2), config: config)
        XCTAssertEqual(sm.awayStreak, 2)
        _ = sm.update(rssi: -40, at: t0.addingTimeInterval(3), config: config)
        XCTAssertEqual(sm.awayStreak, 0, "an in-range sample resets the streak")
    }

    func testNoFurtherTransitionsWhileAlreadyAway() {
        var sm = PresenceStateMachine()
        for i in 0..<5 {
            sm.update(rssi: -95, at: t0.addingTimeInterval(Double(i)), config: config)
        }
        XCTAssertEqual(sm.state, .away)
        let t = sm.update(rssi: -95, at: t0.addingTimeInterval(5), config: config)
        XCTAssertEqual(t, .none, "no repeated away transitions")
    }

    // MARK: - Return home

    func testReturnHomeRequiresHomeConfirmations() {
        var sm = PresenceStateMachine()
        for i in 0..<5 { sm.update(rssi: -95, at: t0.addingTimeInterval(Double(i)), config: config) }
        XCTAssertEqual(sm.state, .away)

        for i in 0..<(config.homeConfirmations - 1) {
            let t = sm.update(rssi: -45, at: t0.addingTimeInterval(10 + Double(i)), config: config)
            XCTAssertEqual(t, .none)
        }
        XCTAssertEqual(sm.state, .away)
        let t = sm.update(rssi: -45, at: t0.addingTimeInterval(12), config: config)
        XCTAssertEqual(t, .home)
        XCTAssertEqual(sm.state, .home)
    }

    // MARK: - Stale timeout

    func testStaleGapForcesAway() {
        var sm = PresenceStateMachine()
        sm.update(rssi: -45, at: t0, config: config)
        let t = sm.update(rssi: -45, at: t0.addingTimeInterval(60), config: config)
        XCTAssertEqual(t, .away, "gaping hole in samples means the beacon is gone")
        XCTAssertEqual(sm.state, .away)
    }

    func testResolvedStateTreatsStaleAsAway() {
        var sm = PresenceStateMachine()
        sm.update(rssi: -45, at: t0, config: config)
        XCTAssertEqual(sm.resolvedState(at: t0.addingTimeInterval(60), config: config), .away)
        XCTAssertEqual(sm.resolvedState(at: t0.addingTimeInterval(5), config: config), .home)
    }

    func testSampleWithinStaleWindowKeepsHome() {
        var sm = PresenceStateMachine()
        sm.update(rssi: -45, at: t0, config: config)
        let t = sm.update(rssi: -45, at: t0.addingTimeInterval(5), config: config)
        XCTAssertEqual(t, .none)
        XCTAssertEqual(sm.state, .home)
    }

    // MARK: - Stale resolve (no new samples arrive at all)

    func testResolveForcesAwayWhenNoSamplesArrive() {
        var sm = PresenceStateMachine()
        sm.update(rssi: -45, at: t0, config: config)
        // No further feeds; the clock alone declares us gone.
        let t = sm.resolve(at: t0.addingTimeInterval(60), config: config)
        XCTAssertEqual(t, .away)
        XCTAssertEqual(sm.state, .away)
    }

    func testResolveDoesNotFlipHomePrematurely() {
        var sm = PresenceStateMachine()
        sm.update(rssi: -45, at: t0, config: config)
        // Inside the stale window → no forced transition.
        let t = sm.resolve(at: t0.addingTimeInterval(5), config: config)
        XCTAssertEqual(t, .none)
        XCTAssertEqual(sm.state, .home)
    }

    func testResolveIsIdempotentOnceAlreadyAway() {
        var sm = PresenceStateMachine()
        sm.update(rssi: -45, at: t0, config: config)
        XCTAssertEqual(sm.resolve(at: t0.addingTimeInterval(60), config: config), .away)
        XCTAssertEqual(sm.resolve(at: t0.addingTimeInterval(90), config: config), .none)
        XCTAssertEqual(sm.state, .away)
    }
}

final class TimelineStoreTests: XCTestCase {
    func testAppendThenLoadRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeline-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = TimelineStore(fileURL: url)
        store.append(TimelineEvent(timestamp: Date(timeIntervalSince1970: 1000), state: .home, rssi: -50))
        store.append(TimelineEvent(timestamp: Date(timeIntervalSince1970: 2000), state: .away, rssi: -95))

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].state, .home)
        XCTAssertEqual(loaded[0].rssi, -50)
        XCTAssertEqual(loaded[1].state, .away)
    }
}