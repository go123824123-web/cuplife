//
//  ServoBLEManager.swift
//  wave
//
//  Ported from macOS ServoController project.
//

import Foundation
import CoreBluetooth
import Combine

private let kServiceUUID = CBUUID(string: "59462F12-9543-9999-12C8-58B459A2712D")
private let kCharUUID    = CBUUID(string: "33333333-2222-2222-1111-111100000000")

// MARK: - Persisted device record

struct SavedBLEDevice: Codable, Identifiable, Equatable {
    let id: String       // peripheral UUID string
    let name: String
    let lastConnected: Date

    static func == (lhs: SavedBLEDevice, rhs: SavedBLEDevice) -> Bool {
        lhs.id == rhs.id
    }
}

struct BLEDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

// MARK: - Direction

enum ServoDirection: String {
    case left  = "向左转"
    case right = "向右转"
    case still = "静止"

    var arrow: String {
        switch self {
        case .left:  return "←"
        case .right: return "→"
        case .still: return "•"
        }
    }
}

// MARK: - UserDefaults keys

private let kSavedDevicesKey = "wave.ble.savedDevices"
private let kLastDeviceIDKey = "wave.ble.lastDeviceID"

// MARK: - Shared BLE Manager

final class ServoBLEManager: NSObject, ObservableObject {

    static let shared = ServoBLEManager()

    @Published var isScanning = false
    @Published var isConnected = false
    @Published var statusText = "未连接"
    @Published var discoveredDevices: [BLEDevice] = []

    // Servo state
    @Published var currentAngle: Int = 90
    @Published var direction: ServoDirection = .still
    @Published var speed: Double = 0

    // Connection history
    @Published var savedDevices: [SavedBLEDevice] = []

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var lastCommandTime: Date = .now
    private var lastAngle: Int = 90
    private var shouldAutoConnect = true
    private var autoConnectAttempted = false

    override init() {
        super.init()
        loadSavedDevices()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Persistence

    private func loadSavedDevices() {
        guard let data = UserDefaults.standard.data(forKey: kSavedDevicesKey),
              let devices = try? JSONDecoder().decode([SavedBLEDevice].self, from: data) else {
            return
        }
        savedDevices = devices
    }

    private func persistDevices() {
        if let data = try? JSONEncoder().encode(savedDevices) {
            UserDefaults.standard.set(data, forKey: kSavedDevicesKey)
        }
    }

    private func saveDevice(peripheral: CBPeripheral) {
        let record = SavedBLEDevice(
            id: peripheral.identifier.uuidString,
            name: peripheral.name ?? "未知设备",
            lastConnected: Date()
        )

        // Update existing or insert at top
        if let idx = savedDevices.firstIndex(where: { $0.id == record.id }) {
            savedDevices[idx] = record
        } else {
            savedDevices.insert(record, at: 0)
        }

        // Keep max 10 records
        if savedDevices.count > 10 {
            savedDevices = Array(savedDevices.prefix(10))
        }

        UserDefaults.standard.set(record.id, forKey: kLastDeviceIDKey)
        persistDevices()
    }

    func removeSavedDevice(_ device: SavedBLEDevice) {
        savedDevices.removeAll { $0.id == device.id }
        persistDevices()
        if UserDefaults.standard.string(forKey: kLastDeviceIDKey) == device.id {
            UserDefaults.standard.removeObject(forKey: kLastDeviceIDKey)
        }
    }

    // MARK: - Auto-connect

    private func attemptAutoConnect() {
        guard !autoConnectAttempted, !isConnected else { return }
        autoConnectAttempted = true

        guard let lastID = UserDefaults.standard.string(forKey: kLastDeviceIDKey),
              let uuid = UUID(uuidString: lastID) else { return }

        let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = known.first {
            statusText = "正在自动连接..."
            centralManager.connect(peripheral, options: nil)
        }
    }

    // MARK: - Scan

    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusText = "蓝牙不可用"
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        statusText = "扫描中..."
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        if !isConnected {
            statusText = discoveredDevices.isEmpty ? "未发现设备" : "请选择设备"
        }
    }

    func connect(to device: BLEDevice) {
        stopScan()
        statusText = "正在连接 \(device.name)..."
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
    }

    func reconnectSaved(_ saved: SavedBLEDevice) {
        guard let uuid = UUID(uuidString: saved.id) else { return }
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = peripherals.first {
            statusText = "正在连接 \(saved.name)..."
            centralManager.connect(peripheral, options: nil)
        } else {
            startScan()
        }
    }

    // MARK: - Send command

    func sendServoCommand(angle: Int) {
        guard let char = writeCharacteristic, let p = connectedPeripheral else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastCommandTime)
        let delta = angle - lastAngle

        if delta != 0 {
            direction = delta > 0 ? .right : .left
            speed = elapsed > 0 ? abs(Double(delta)) / elapsed : 0
        } else {
            direction = .still
            speed = 0
        }

        lastAngle = angle
        lastCommandTime = now
        currentAngle = angle

        let cmd = "servo:\(angle)"
        if let data = cmd.data(using: .utf8) {
            p.writeValue(data, for: char, type: .withResponse)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if self.lastCommandTime == now {
                self.direction = .still
                self.speed = 0
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ServoBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            switch central.state {
            case .poweredOn:
                self.statusText = "就绪，可以扫描"
                self.attemptAutoConnect()
            case .poweredOff:
                self.statusText = "蓝牙已关闭"
            case .unauthorized:
                self.statusText = "蓝牙权限被拒绝"
            default:
                self.statusText = "蓝牙不可用"
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let deviceName = name, !deviceName.isEmpty else { return }
        if discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) { return }

        let device = BLEDevice(id: peripheral.identifier, name: deviceName,
                               rssi: RSSI.intValue, peripheral: peripheral)
        DispatchQueue.main.async {
            self.discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([kServiceUUID])
        DispatchQueue.main.async {
            self.isConnected = true
            self.statusText = "已连接 \(peripheral.name ?? "设备")"
            self.saveDevice(peripheral: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.statusText = "连接失败"
            self.isConnected = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.connectedPeripheral = nil
            self.writeCharacteristic = nil
            self.isConnected = false
            self.statusText = "已断开"
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ServoBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == kServiceUUID {
            peripheral.discoverCharacteristics([kCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == kCharUUID {
            writeCharacteristic = char
            DispatchQueue.main.async {
                self.statusText = "就绪 - \(peripheral.name ?? "设备")"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Write error: \(error.localizedDescription)")
        }
    }
}
