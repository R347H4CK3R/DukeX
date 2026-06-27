import CoreBluetooth
import Foundation

final class ControllerBatteryMonitor: NSObject, ObservableObject {
    @Published private(set) var batteryPercent: Int?

    private let batteryService = CBUUID(string: "180F")
    private let batteryLevelCharacteristic = CBUUID(string: "2A19")

    private var centralManager: CBCentralManager?
    private var controllerNameHints: [String] = []
    private var candidatePeripherals: [UUID: CBPeripheral] = [:]
    private var selectedPeripheral: CBPeripheral?
    private var scanReviewWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func refresh(controllerNameHints: [String]) {
        self.controllerNameHints = controllerNameHints.map(Self.normalizedName)
            .filter { !$0.isEmpty }
        scanForControllerBatteryIfReady(reason: "refresh")
    }

    func clear() {
        batteryPercent = nil
        selectedPeripheral = nil
        candidatePeripherals.removeAll()
        centralManager?.stopScan()
        scanReviewWorkItem?.cancel()
        scanReviewWorkItem = nil
        log("clear")
    }

    private func scanForControllerBatteryIfReady(reason: String) {
        guard let centralManager else {
            return
        }

        guard centralManager.state == .poweredOn else {
            batteryPercent = nil
            log("scan skipped reason=\(reason) state=\(centralManager.state.rawValue)")
            return
        }

        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [batteryService])
        log("scan start reason=\(reason) connectedBatteryPeripherals=\(connectedPeripherals.count) hints=\(controllerNameHints.joined(separator: ","))")
        for peripheral in connectedPeripherals {
            handleCandidate(peripheral, source: "connected")
        }

        centralManager.scanForPeripherals(
            withServices: [batteryService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scheduleScanReview()
    }

    private func handleCandidate(_ peripheral: CBPeripheral, source: String) {
        candidatePeripherals[peripheral.identifier] = peripheral
        log("candidate source=\(source) name=\(peripheral.name ?? "unknown") id=\(peripheral.identifier.uuidString)")

        guard selectedPeripheral == nil else {
            return
        }

        if matchesControllerHint(peripheral) {
            connect(peripheral, reason: "name-match")
        }
    }

    private func scheduleScanReview() {
        scanReviewWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reviewBatteryCandidates()
        }
        scanReviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: workItem)
    }

    private func reviewBatteryCandidates() {
        centralManager?.stopScan()
        scanReviewWorkItem = nil

        guard selectedPeripheral == nil else {
            return
        }

        let candidates = Array(candidatePeripherals.values)
        if let matchedPeripheral = candidates.first(where: matchesControllerHint) {
            connect(matchedPeripheral, reason: "delayed-name-match")
        } else if candidates.count == 1, let onlyPeripheral = candidates.first {
            connect(onlyPeripheral, reason: "single-battery-peripheral")
        } else {
            batteryPercent = nil
            log("no battery peripheral selected candidates=\(candidates.count)")
        }
    }

    private func connect(_ peripheral: CBPeripheral, reason: String) {
        guard selectedPeripheral?.identifier != peripheral.identifier else {
            return
        }

        selectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager?.stopScan()
        log("connect reason=\(reason) name=\(peripheral.name ?? "unknown") id=\(peripheral.identifier.uuidString)")
        centralManager?.connect(peripheral)
    }

    private func matchesControllerHint(_ peripheral: CBPeripheral) -> Bool {
        guard let peripheralName = peripheral.name.map(Self.normalizedName),
              !peripheralName.isEmpty,
              !controllerNameHints.isEmpty else {
            return false
        }

        return controllerNameHints.contains { hint in
            peripheralName.contains(hint) || hint.contains(peripheralName)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func log(_ message: String) {
        NSLog("xemu_ios: controller_battery: %@", message)
    }
}

extension ControllerBatteryMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("state=\(central.state.rawValue)")
        scanForControllerBatteryIfReady(reason: "state")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        handleCandidate(peripheral, source: "scan")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("connected name=\(peripheral.name ?? "unknown")")
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("connect failed name=\(peripheral.name ?? "unknown") error=\(error?.localizedDescription ?? "none")")
        if selectedPeripheral?.identifier == peripheral.identifier {
            selectedPeripheral = nil
            batteryPercent = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("disconnected name=\(peripheral.name ?? "unknown") error=\(error?.localizedDescription ?? "none")")
        if selectedPeripheral?.identifier == peripheral.identifier {
            selectedPeripheral = nil
            batteryPercent = nil
            scanForControllerBatteryIfReady(reason: "disconnect")
        }
    }
}

extension ControllerBatteryMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log("discover services failed error=\(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            return
        }

        for service in services where service.uuid == batteryService {
            peripheral.discoverCharacteristics([batteryLevelCharacteristic], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            log("discover characteristics failed error=\(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            return
        }

        for characteristic in characteristics where characteristic.uuid == batteryLevelCharacteristic {
            peripheral.readValue(for: characteristic)
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("read failed error=\(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == batteryLevelCharacteristic,
              let data = characteristic.value,
              let rawLevel = data.first else {
            return
        }

        let percent = min(max(Int(rawLevel), 0), 100)
        batteryPercent = percent
        log("battery name=\(peripheral.name ?? "unknown") percent=\(percent)%")
    }
}
