import ChessnutProtocol
import CoreBluetooth
import Foundation

nonisolated public enum ChessnutBLE {
    /// Notifies with board positions.
    nonisolated(unsafe) public static let stateCharacteristic = CBUUID(string: "1B7E8262-2877-41C3-B46E-CF057C562023")

    /// Notifies with replies to commands: version, battery, file count.
    nonisolated(unsafe) public static let replyCharacteristic = CBUUID(string: "1B7E8273-2877-41C3-B46E-CF057C562023")

    /// Accepts commands.
    nonisolated(unsafe) public static let writeCharacteristic = CBUUID(string: "1B7E8272-2877-41C3-B46E-CF057C562023")

    nonisolated(unsafe) static let notifyCharacteristics: Set<CBUUID> = [stateCharacteristic, replyCharacteristic]

    /// Advertised names seen on these boards.
    public static let deviceNames = ["Chessnut"]
}

nonisolated public final class BLETransport: NSObject, BoardTransport, @unchecked Sendable {
    public let frames: AsyncStream<Frame>

    private let framesContinuation: AsyncStream<Frame>.Continuation
    private let queue = DispatchQueue(label: "com.chessnut.ble")
    private let scanTimeout: Duration
    private let onDiscovery: (@Sendable (CBUUID, CBUUID, CBCharacteristicProperties) -> Void)?

    private var central: CBCentralManager!

    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var discoveredNotify: Set<CBUUID> = []
    private var subscribed: Set<CBUUID> = []
    private var connectContinuation: CheckedContinuation<Void, any Error>?
    private var scanDeadline: DispatchWorkItem?
    private var pendingServices = 0
    private var isSpent = false

    private var isReady: Bool {
        writeCharacteristic != nil && subscribed == ChessnutBLE.notifyCharacteristics
    }

    public init(
        scanTimeout: Duration = .seconds(10),
        onDiscovery: (@Sendable (CBUUID, CBUUID, CBCharacteristicProperties) -> Void)? = nil
    ) {
        self.scanTimeout = scanTimeout
        self.onDiscovery = onDiscovery
        let (stream, continuation) = AsyncStream<Frame>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.frames = stream
        self.framesContinuation = continuation
        super.init()
        self.central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: BoardTransport

    public func connect() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                queue.async {
                    if self.isSpent {
                        continuation.resume(throwing: BoardError.disconnected)
                        return
                    }
                    if self.isReady {
                        continuation.resume()
                        return
                    }
                    guard self.connectContinuation == nil else {
                        continuation.resume(throwing: BoardError.notConnected)
                        return
                    }
                    self.connectContinuation = continuation
                    self.startIfReady()
                }
            }
        } onCancel: {
            queue.async { self.teardown(failingWith: CancellationError()) }
        }
    }

    public func disconnect() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.teardown(failingWith: BoardError.disconnected)
                continuation.resume()
            }
        }
    }

    public func send(_ frame: Frame) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                guard
                    let peripheral = self.peripheral,
                    let characteristic = self.writeCharacteristic,
                    peripheral.state == .connected
                else {
                    continuation.resume(throwing: BoardError.notConnected)
                    return
                }
                peripheral.writeValue(
                    Data(frame.bytes),
                    for: characteristic,
                    type: .withResponse
                )
                continuation.resume()
            }
        }
    }

    // MARK: Connection flow

    private func startIfReady() {
        switch central.state {
        case .poweredOn:
            beginScan()
        case .poweredOff, .unauthorized, .unsupported:
            finishConnect(throwing: BoardError.bluetoothUnavailable)
        case .unknown, .resetting:
            break  // centralManagerDidUpdateState will call back
        @unknown default:
            finishConnect(throwing: BoardError.bluetoothUnavailable)
        }
    }

    private func beginScan() {
        central.scanForPeripherals(withServices: nil)

        let deadline = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.central.stopScan()
            self.finishConnect(throwing: BoardError.boardNotFound)
        }
        scanDeadline = deadline
        queue.asyncAfter(deadline: .now() + seconds(scanTimeout), execute: deadline)
    }

    private func matchesBoard(name: String?) -> Bool {
        guard let name else { return false }
        return ChessnutBLE.deviceNames.contains {
            name.range(of: $0, options: .caseInsensitive) != nil
        }
    }

    private func finishConnect(throwing error: (any Error)? = nil) {
        scanDeadline?.cancel()
        scanDeadline = nil
        guard let continuation = connectContinuation else { return }
        connectContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func completeIfUsable() {
        if isReady {
            finishConnect()
            return
        }
        if pendingServices == 0,
           writeCharacteristic == nil || discoveredNotify != ChessnutBLE.notifyCharacteristics {
            finishConnect(throwing: BoardError.boardNotFound)
        }
    }

    private func teardown(failingWith error: any Error) {
        isSpent = true
        scanDeadline?.cancel()
        scanDeadline = nil
        if central.isScanning { central.stopScan() }
        if let peripheral, peripheral.state != .disconnected {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        writeCharacteristic = nil
        discoveredNotify = []
        subscribed = []
        finishConnect(throwing: error)
        framesContinuation.finish()
    }

    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}

// MARK: - CBCentralManagerDelegate
nonisolated extension BLETransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard connectContinuation != nil else { return }
        startIfReady()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard matchesBoard(name: peripheral.name) || matchesBoard(name: advertised) else {
            return
        }
        central.stopScan()
        scanDeadline?.cancel()
        scanDeadline = nil

        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices(nil)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        teardown(failingWith: error ?? BoardError.boardNotFound)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        teardown(failingWith: error ?? BoardError.disconnected)
    }
}

// MARK: - CBPeripheralDelegate

nonisolated extension BLETransport: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: (any Error)?
    ) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            finishConnect(throwing: error ?? BoardError.boardNotFound)
            return
        }
        pendingServices = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        pendingServices = max(0, pendingServices - 1)

        for characteristic in service.characteristics ?? [] {
            onDiscovery?(service.uuid, characteristic.uuid, characteristic.properties)

            if characteristic.uuid == ChessnutBLE.writeCharacteristic {
                writeCharacteristic = characteristic
            } else if ChessnutBLE.notifyCharacteristics.contains(characteristic.uuid) {
                discoveredNotify.insert(characteristic.uuid)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        completeIfUsable()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard ChessnutBLE.notifyCharacteristics.contains(characteristic.uuid) else { return }
        if let error {
            finishConnect(throwing: error)
            return
        }
        if characteristic.isNotifying {
            subscribed.insert(characteristic.uuid)
        } else {
            subscribed.remove(characteristic.uuid)
        }
        completeIfUsable()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard
            let data = characteristic.value,
            let frame = Frame(decoding: data)
        else { return }
        framesContinuation.yield(frame)
    }
}
