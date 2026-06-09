import CoreBluetooth
import Foundation

// CrossPoint AirBook BLE service/characteristic UUIDs
private let kServiceUUID = CBUUID(string: "8b45f100-9128-4d4f-9a4f-7a0dc1b26b01")
private let kControlUUID = CBUUID(string: "8b45f101-9128-4d4f-9a4f-7a0dc1b26b01")
private let kDataUUID    = CBUUID(string: "8b45f102-9128-4d4f-9a4f-7a0dc1b26b01")
private let kStatusUUID  = CBUUID(string: "8b45f103-9128-4d4f-9a4f-7a0dc1b26b01")

enum TransferState: Equatable {
    case idle
    case bluetoothUnavailable
    case scanning
    case connecting
    case preparing
    case transferring
    case done
    case cancelled
    case error(String)

    var isActive: Bool {
        switch self {
        case .scanning, .connecting, .preparing, .transferring: return true
        default: return false
        }
    }

    var statusMessage: String {
        switch self {
        case .idle:                 return "Ready to send"
        case .bluetoothUnavailable: return "Bluetooth not available"
        case .scanning:             return "Searching for CrossPoint…"
        case .connecting:           return "Connecting to device…"
        case .preparing:            return "Setting up transfer…"
        case .transferring:         return "Sending book…"
        case .done:                 return "Book delivered!"
        case .cancelled:            return "Transfer cancelled"
        case .error(let msg):       return msg
        }
    }
}

@MainActor
@Observable
final class BluetoothManager: NSObject {
    var transferState: TransferState = .idle
    var progress: Double = 0
    var bytesTransferred: Int = 0
    var totalBytes: Int = 0

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var controlChar: CBCharacteristic?
    @ObservationIgnored private var dataChar: CBCharacteristic?
    @ObservationIgnored private var statusChar: CBCharacteristic?
    @ObservationIgnored private var fileData: Data?
    @ObservationIgnored private var filename: String?
    @ObservationIgnored private var sendOffset: Int = 0
    @ObservationIgnored private var chunkSize: Int = 512
    @ObservationIgnored private var scanTimer: Timer?

    // MARK: - Public API

    func sendBook(name: String, data: Data) {
        guard !transferState.isActive else { return }
        fileData = data
        filename = name
        sendOffset = 0
        bytesTransferred = 0
        totalBytes = data.count
        progress = 0
        transferState = .scanning
        // Creating CBCentralManager here activates BLE — not before.
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
        armScanTimeout()
    }

    func cancel() {
        scanTimer?.invalidate()
        scanTimer = nil
        if let p = peripheral, let c = controlChar {
            p.writeValue("CANCEL".data(using: .utf8)!, for: c, type: .withResponse)
        }
        transferState = .cancelled
        shutdownBluetooth()
    }

    func reset() {
        guard !transferState.isActive else { return }
        transferState = .idle
        progress = 0
        bytesTransferred = 0
        totalBytes = 0
    }

    // MARK: - Private

    private func armScanTimeout() {
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self, case .scanning = self.transferState else { return }
            self.transferState = .error("CrossPoint not found.\nMake sure the device is on the AirBook screen.")
            self.shutdownBluetooth()
        }
    }

    private func shutdownBluetooth() {
        scanTimer?.invalidate()
        scanTimer = nil
        central?.stopScan()
        if let p = peripheral {
            central?.cancelPeripheralConnection(p)
        }
        // Nil-out delegate before releasing to prevent stale callbacks
        central?.delegate = nil
        central = nil
        peripheral = nil
        controlChar = nil
        dataChar = nil
        statusChar = nil
        fileData = nil
        filename = nil
        sendOffset = 0
    }

    // Pumps as many without-response chunks as the BLE stack will accept.
    // Called on READY, on peripheralIsReady, and after PROGRESS notifications.
    // NOTE: no END command is sent — the firmware auto-completes and sends DONE
    // as soon as bytesReceived == bytesExpected. Sending END after auto-complete
    // causes the firmware to call failUploadLocked("Transfer incomplete").
    private func pumpChunks() {
        guard let data = fileData, let p = peripheral, let dc = dataChar else { return }
        while sendOffset < data.count && p.canSendWriteWithoutResponse {
            let end = min(sendOffset + chunkSize, data.count)
            p.writeValue(data.subdata(in: sendOffset..<end), for: dc, type: .withoutResponse)
            sendOffset = end
            bytesTransferred = sendOffset
            progress = Double(sendOffset) / Double(data.count)
        }
    }

    private func handleDeviceStatus(_ raw: String) {
        // Once we reach a terminal state, ignore any late-arriving BLE notifications
        // (e.g. an ERROR from a duplicate END that raced with the firmware's DONE).
        switch transferState {
        case .done, .error, .cancelled: return
        default: break
        }

        let msg = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.hasPrefix("PROGRESS:") {
            let parts = msg.dropFirst("PROGRESS:".count).split(separator: ":")
            if parts.count == 2, let done = Int(parts[0]), let total = Int(parts[1]), total > 0 {
                bytesTransferred = done
                totalBytes = total
                progress = Double(done) / Double(total)
            }
            pumpChunks()
        } else if msg == "READY" {
            transferState = .transferring
            pumpChunks()
        } else if msg == "DONE" {
            progress = 1.0
            bytesTransferred = totalBytes
            transferState = .done
            shutdownBluetooth()
        } else if msg.hasPrefix("ERROR:") {
            transferState = .error(String(msg.dropFirst("ERROR:".count)))
            shutdownBluetooth()
        } else if msg == "CANCELLED" {
            if case .cancelled = transferState { } else { transferState = .cancelled }
            shutdownBluetooth()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Scan without service-UUID filter: NimBLE on ESP32 places the 128-bit
            // service UUID in scan-response data (primary adv packet is too small),
            // so filtering by UUID here misses the device. Filter by name instead.
            central.scanForPeripherals(withServices: nil, options: nil)
        case .poweredOff:
            transferState = .error("Please enable Bluetooth to send books.")
            shutdownBluetooth()
        case .unauthorized:
            transferState = .error("Bluetooth access denied. Enable it in Settings > Privacy.")
            shutdownBluetooth()
        case .unsupported:
            transferState = .bluetoothUnavailable
            shutdownBluetooth()
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripheral.name == "CrossPoint AirBook" else { return }
        scanTimer?.invalidate()
        scanTimer = nil
        central.stopScan()
        self.peripheral = peripheral
        transferState = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        transferState = .preparing
        peripheral.delegate = self
        peripheral.discoverServices([kServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        transferState = .error(error?.localizedDescription ?? "Failed to connect to CrossPoint.")
        shutdownBluetooth()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard transferState.isActive else { return }
        transferState = .error("Device disconnected unexpectedly.")
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == kServiceUUID }) else {
            transferState = .error("CrossPoint service not found.")
            shutdownBluetooth()
            return
        }
        peripheral.discoverCharacteristics([kControlUUID, kDataUUID, kStatusUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            transferState = .error("Failed to discover characteristics.")
            shutdownBluetooth()
            return
        }
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case kControlUUID: controlChar = char
            case kDataUUID:    dataChar    = char
            case kStatusUUID:  statusChar  = char
            default: break
            }
        }
        guard controlChar != nil, dataChar != nil, let sc = statusChar else {
            transferState = .error("Missing required BLE characteristics.")
            shutdownBluetooth()
            return
        }
        chunkSize = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
        peripheral.setNotifyValue(true, for: sc)

        guard let name = filename, let data = fileData else { return }
        let cmd = "START:\(name):\(data.count)"
        peripheral.writeValue(cmd.data(using: .utf8)!, for: controlChar!, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == kStatusUUID,
              let data = characteristic.value,
              let msg = String(data: data, encoding: .utf8) else { return }
        handleDeviceStatus(msg)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            transferState = .error("Write error: \(error.localizedDescription)")
            shutdownBluetooth()
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard case .transferring = transferState else { return }
        pumpChunks()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {}
}
