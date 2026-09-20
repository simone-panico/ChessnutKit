import ChessnutProtocol

public actor ChessBoard {
    public nonisolated let positions: AsyncStream<Position>
    private nonisolated let positionsContinuation: AsyncStream<Position>.Continuation

    private let transport: any BoardTransport
    private let requestTimeout: Duration

    private var isConnected = false
    private var pump: Task<Void, Never>?

    private var latestPosition: Position?
    private var latestBattery: Int?

    private enum Expectation: Equatable {
        case battery
        case response
    }

    private struct Pending {
        let expectation: Expectation
        let continuation: CheckedContinuation<Event, any Error>
    }

    private var pending: Pending?
    private var isRequesting = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(
        transport: any BoardTransport,
        requestTimeout: Duration = .seconds(2)
    ) {
        self.transport = transport
        self.requestTimeout = requestTimeout
        let (stream, continuation) = AsyncStream<Position>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.positions = stream
        self.positionsContinuation = continuation
    }

    deinit {
        pump?.cancel()
        positionsContinuation.finish()
    }

    public func connect(mode: Mode? = .realTime) async throws {
        guard !isConnected else { return }

        try await transport.connect()
        isConnected = true
        startPump()

        if let mode {
            try await transport.send(.setMode(mode))
        }
    }

    public func disconnect() async {
        pump?.cancel()
        pump = nil
        isConnected = false
        failPending(with: BoardError.disconnected)
        await transport.disconnect()
    }

    // MARK: Commands

    public func setMode(_ mode: Mode) async throws {
        try await sendCommand(.setMode(mode))
    }

    public func beep(hz: UInt16 = 1000, milliseconds: UInt16 = 200) async throws {
        try await sendCommand(.beep(hz: hz, milliseconds: milliseconds))
    }

    public func setLEDs(_ mask: LEDMask) async throws {
        try await sendCommand(.setLEDs(mask))
    }

    // MARK: Queries

    public func battery() async throws -> Int {
        let event = try await request(.queryBattery, expecting: .battery)
        guard case .battery(let level) = event else {
            throw BoardError.timedOut
        }
        return level
    }

    public func version(_ chip: Chip) async throws -> String {
        let event = try await request(.queryVersion(chip), expecting: .response)
        guard case .response(let frame) = event, let text = frame.textValue else {
            throw BoardError.malformedReply(Frame(opcode: Opcode.queryVersion))
        }
        return text
    }

    public func storedGameCount() async throws -> Int {
        let event = try await request(.queryFileCount, expecting: .response)
        guard case .response(let frame) = event, let count = frame.countValue else {
            throw BoardError.malformedReply(Frame(opcode: Opcode.queryFileCount))
        }
        return count
    }

    public var lastPosition: Position? { latestPosition }
    public var lastBattery: Int? { latestBattery }

    // MARK: Sending

    private func sendCommand(_ command: Command) async throws {
        guard isConnected else { throw BoardError.notConnected }
        try await transport.send(command)
    }

    private func request(
        _ command: Command,
        expecting expectation: Expectation
    ) async throws -> Event {
        guard isConnected else { throw BoardError.notConnected }

        await acquire()
        defer { release() }

        try await transport.send(command)

        let timeout = Task { [requestTimeout] in
            try? await Task.sleep(for: requestTimeout)
            guard !Task.isCancelled else { return }
            await self.failPending(with: BoardError.timedOut)
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending = Pending(expectation: expectation, continuation: continuation)
        }
    }

    // MARK: Receiving

    private func startPump() {
        let frames = transport.frames
        pump = Task { [weak self] in
            for await frame in frames {
                await self?.handle(frame)
            }
            await self?.transportDidFinish()
        }
    }

    private func handle(_ frame: Frame) {
        switch Event(frame) {
        case .position(let position):
            latestPosition = position
            positionsContinuation.yield(position)

        case .battery(let level):
            latestBattery = level
            deliver(.battery(level), matching: .battery)

        case .response(let frame):
            deliver(.response(frame), matching: .response)

        case .fileTransferBegan, .fileTransferEnded:
            break
        }
    }

    private func transportDidFinish() {
        isConnected = false
        failPending(with: BoardError.disconnected)
    }

    private func deliver(_ event: Event, matching expectation: Expectation) {
        guard let pending, pending.expectation == expectation else { return }
        self.pending = nil
        pending.continuation.resume(returning: event)
    }

    private func failPending(with error: any Error) {
        guard let pending else { return }
        self.pending = nil
        pending.continuation.resume(throwing: error)
    }

    // MARK: One request at a time

    private func acquire() async {
        guard isRequesting else {
            isRequesting = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            isRequesting = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
