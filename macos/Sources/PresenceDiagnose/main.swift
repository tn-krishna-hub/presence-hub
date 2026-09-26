import CoreBluetooth
import Foundation

/// Diagnostic tool: dumps every BLE peripheral visible to CoreBluetooth on this
/// Mac, with its RSSI and advertised service UUIDs. Polls `CBManagerState` every
/// second (delegate callbacks can go silent on some macOS setups), runs 30 s, exits.
final class Scanner: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager!
    private var seen = 0
    private let logURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("presence_diagnose.log")
    private var startedScan = false

    override init() {
        super.init()
        report("BOOT: writing to \(logURL.path)")
        manager = CBCentralManager(delegate: self, queue: nil)

        let poll = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let state = self.manager.state.rawValue
            self.report("STATE-poll: \(state)")
            if state == CBManagerState.poweredOn.rawValue && !self.startedScan {
                self.startedScan = true
                self.report("SCAN: starting 30 s window")
                self.manager.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    self.report("DONE: saw \(self.seen) distinct peripherals")
                    exit(0)
                }
            }
        }
        RunLoop.main.add(poll, forMode: .common)

        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            self.report("TIMEOUT: still saw \(self.seen) distinct peripherals; state=\(self.manager.state.rawValue)")
            exit(0)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        report("STATE-delegate: \(central.state.rawValue)")
    }

    private func report(_ line: String) {
        print(line)
        let data = line + "\n"
        if let handle = FileHandle(forWritingAtPath: logURL.path) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data.data(using: .utf8) ?? Data())
        } else {
            _ = FileManager.default.createFile(atPath: logURL.path, contents: data.data(using: .utf8) ?? Data())
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        seen += 1
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "(anonymous)"
        let mac = peripheral.identifier.uuidString
        let standard = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString }.joined(separator: ",") ?? "-"
        let overflow = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString }.joined(separator: ",") ?? "-"
        let rawServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let rawOverflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]
        let marker = (standard.uppercased().contains("069293BA")
                      || overflow.uppercased().contains("069293BA")
                      || rawServices?.contains(where: { $0.uuidString.uppercased() == "069293BA-AA49-4906-B09F-11CE3B7719AA" }) == true
                      || rawOverflow?.contains(where: { $0.uuidString.uppercased() == "069293BA-AA49-4906-B09F-11CE3B7719AA" }) == true)
            ? " >>> PHONE" : ""
        print("RSSI \(RSSI.intValue) dbm | \(name) | \(mac) | std:\(standard) | ovf:\(overflow)\(marker)")
    }
}

Scanner()
RunLoop.main.run()