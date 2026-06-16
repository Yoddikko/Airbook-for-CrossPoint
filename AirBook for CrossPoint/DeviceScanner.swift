import CoreBluetooth
import Foundation

/// Lightweight passive BLE scanner used by the home screen to detect
/// whether a CrossPoint device is advertising nearby.
/// BLE is activated only while scanning (8 s max) to preserve battery.
@MainActor
@Observable
final class DeviceScanner: NSObject {
    var isNearby: Bool = false
    var isScanning: Bool = false

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var stopTimer: Timer?

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        // ShowPowerAlertKey:false → no system popup if BT is off; status just stays unknown
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func stopScan() {
        stopTimer?.invalidate(); stopTimer = nil
        central?.stopScan()
        central?.delegate = nil
        central = nil
        isScanning = false
    }

    private func performScan(_ central: CBCentralManager) {
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        // Auto-stop after 8 seconds regardless of result
        stopTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
    }
}

extension DeviceScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            performScan(central)
        } else {
            stopScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if peripheral.name == "CrossPoint AirBook" {
            isNearby = true
            stopScan()
        }
    }
}
