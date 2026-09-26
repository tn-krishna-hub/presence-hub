import Foundation
import CoreBluetooth

/// Passive BLE listener. Never pairs; just watches for a peripheral advertising
/// the configured service UUID and streams the RSSI of every advertisement seen.
public final class BLEPresenceScanner: NSObject, CBCentralManagerDelegate {
    public typealias SampleHandler = (_ rssi: Int, _ date: Date) -> Void

    /// Emitted on the CoreBluetooth queue.
    public var onSample: SampleHandler
    public var onStateChange: ((CBManagerState) -> Void)?

    private var manager: CBCentralManager!
    private let serviceUUID: UUID

    public init(serviceUUID: UUID, onSample: @escaping SampleHandler) {
        self.serviceUUID = serviceUUID
        self.onSample = onSample
        super.init()
        manager = CBCentralManager(
            delegate: self,
            queue: DispatchQueue(
                label: "presence.blescanner",
                qos: .utility
            )
        )
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Scan with NO service filter: on macOS, custom 128-bit service UUIDs
            // from Android beacons often arrive in the *overflow* advertisement
            // field, which the CoreBluetooth `withServices:` filter ignores.
            // We match the UUID in software instead (see `matches`).
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        default:
            central.stopScan()
        }
        onStateChange?(central.state)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard matches(advertisementData) else { return }
        onSample(RSSI.intValue, Date())
    }

    /// True when the advertisement carries our identity UUID in either the
    /// standard *or* the overflow service-UUID advertisement field.
    private func matches(_ advertisementData: [String: Any]) -> Bool {
        let wanted = serviceUUID.uuidString.uppercased()
        let keys: [String] = [
            CBAdvertisementDataServiceUUIDsKey,
            CBAdvertisementDataOverflowServiceUUIDsKey
        ]
        for key in keys {
            guard let uuids = advertisementData[key] as? [CBUUID] else { continue }
            if uuids.contains(where: { $0.uuidString.uppercased() == wanted }) { return true }
        }
        return false
    }

    public func stop() {
        manager?.stopScan()
    }
}