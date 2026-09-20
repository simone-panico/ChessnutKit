import ChessnutProtocol

nonisolated public protocol BoardTransport: Sendable {
    var frames: AsyncStream<Frame> { get }
    func connect() async throws
    func disconnect() async
    func send(_ frame: Frame) async throws
}

extension BoardTransport {
    public func send(_ command: Command) async throws {
        try await send(command.frame)
    }
}
