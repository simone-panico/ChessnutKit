public enum Event: Equatable, Sendable {
    case position(Position)
    case battery(Int)
    case fileTransferBegan
    case fileTransferEnded
    case response(Frame)

    public init(_ frame: Frame) {
        switch (frame.opcode, frame.payload.first) {
        case (Opcode.boardState, _):
            if let position = Position(payload: frame.payload) {
                self = .position(position)
            } else {
                self = .response(frame)
            }
        case (Opcode.batteryReport, let level?) where level != 0:
            self = .battery(Int(level))
        case (Opcode.fileMarker, 0xbe):
            self = .fileTransferBegan
        case (Opcode.fileMarker, 0xed):
            self = .fileTransferEnded
        default:
            self = .response(frame)
        }
    }
}
