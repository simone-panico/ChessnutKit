import ChessnutProtocol

public enum BoardError: Error, Equatable {
    /// Bluetooth is off, unauthorised, or unsupported on this device.
    case bluetoothUnavailable

    /// Scanning finished without finding a board.
    case boardNotFound

    /// The operation needs a connection that is not established.
    case notConnected

    /// The board did not answer within the allotted time.
    case timedOut

    /// The board answered, but not in a shape this SDK understands.
    case malformedReply(Frame)

    /// The connection dropped while the operation was in flight.
    case disconnected
}

extension BoardError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .bluetoothUnavailable: "Bluetooth is not available"
        case .boardNotFound: "No chessboard found"
        case .notConnected: "Not connected to a chessboard"
        case .timedOut: "The chessboard did not reply in time"
        case .malformedReply(let frame): "Unexpected reply: opcode 0x\(String(frame.opcode, radix: 16))"
        case .disconnected: "The chessboard disconnected"
        }
    }
}
