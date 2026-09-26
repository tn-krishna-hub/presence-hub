import Foundation
import CoreBluetooth
import PresenceCore

// PresenceCLI <identity-uuid> [--dump] [--threshold N] [--away-count N]
//               [--home-count N] [--stale N]
//
// Development spike: prints raw RSSI and live state transitions so you can tune
// thresholds against real-world signal strength before wiring up the menu-bar app.

var args = Array(CommandLine.arguments.dropFirst())
var config = PresenceConfig()
var dumpOnly = false
var identity: UUID?

func usage() -> Never {
    print("Usage: PresenceCLI <identity-uuid> [--dump] [--threshold N] [--away-count N] [--home-count N] [--stale N]")
    exit(64)
}

while let arg = args.first {
    args.removeFirst()
    switch arg {
    case "--dump":
        dumpOnly = true
    case "--threshold", "--away-count", "--home-count", "--stale":
        guard let raw = args.first, let value = Int(raw) else { usage() }
        args.removeFirst()
        switch arg {
        case "--threshold": config.signalThreshold = value
        case "--away-count": config.awayConfirmations = value
        case "--home-count": config.homeConfirmations = value
        case "--stale": config.staleTimeout = TimeInterval(value)
        default: break
        }
    default:
        if identity == nil, let uuid = UUID(uuidString: arg) {
            identity = uuid
        } else {
            usage()
        }
    }
}

guard let identity else { usage() }

print("Presence Core  •  watching \(identity.uuidString)")
print("threshold=\(config.signalThreshold)dBm away=\(config.awayConfirmations)x home=\(config.homeConfirmations)x stale=\(Int(config.staleTimeout))s")

var stateMachine = PresenceStateMachine()
let smoothingWindow = 5
var rssiWindow: [Int] = []

func smoothed(_ rssi: Int) -> Int {
    rssiWindow.append(rssi)
    if rssiWindow.count > smoothingWindow { rssiWindow.removeFirst() }
    let avg = rssiWindow.reduce(0, +) / rssiWindow.count
    return avg
}

func handleSample(_ rssi: Int, at date: Date) {
    guard !dumpOnly else {
        print("rssi=\(rssi)")
        return
    }
    let value = smoothed(rssi)
    let transition = stateMachine.update(rssi: value, at: date, config: config)
    let marker = stateMachine.state == .home ? "HOME" : "AWAY"
    switch transition {
    case .home:
        print("\(timestamp(date))  <<< arrived   (rssi \(value)dBm)  [\(marker)]")
    case .away:
        print("\(timestamp(date))  >>> left      (rssi \(value)dBm)  [\(marker)]")
    case .none:
        print("\(timestamp(date))  sample \(value)dBm  [\(marker)]")
    }
}

func timestamp(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withTime]
    return f.string(from: date)
}

let scanner = BLEPresenceScanner(serviceUUID: identity) { rssi, date in
    handleSample(rssi, at: date)
}
scanner.onStateChange = { state in
    print("bluetooth: \(state.rawValue)")
}

dispatchMain()