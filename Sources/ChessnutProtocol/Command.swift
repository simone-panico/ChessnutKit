// Copied from EasyLinkSDK.cpp
public enum Command: Equatable, Sendable {
    case setMode(Mode)
    case beep(hz: UInt16 = 1000, milliseconds: UInt16 = 200)
    case setLEDs(LEDMask)
    case queryVersion(Chip)
    case queryBattery
    case queryFileCount
    case beginFileTransfer
    case requestFileData
    case deleteTransferredFile

    public var frame: Frame {
        switch self {
        case .setMode(let mode):
            Frame(opcode: Opcode.setMode, payload: [mode.rawValue])
        case .beep(let hz, let milliseconds):
            Frame(opcode: Opcode.beep, payload: [
                UInt8(hz >> 8), UInt8(hz & 0xff),
                UInt8(milliseconds >> 8), UInt8(milliseconds & 0xff),
            ])
        case .setLEDs(let mask):
            Frame(opcode: Opcode.setLEDs, payload: mask.rows)
        case .queryVersion(let chip):
            Frame(opcode: Opcode.queryVersion, payload: [chip.rawValue])
        case .queryBattery:
            Frame(opcode: Opcode.queryBattery, payload: [0x00])
        case .queryFileCount:
            Frame(opcode: Opcode.queryFileCount, payload: [0x00])
        case .beginFileTransfer:
            Frame(opcode: Opcode.beginFileTransfer, payload: [0x00])
        case .requestFileData:
            Frame(opcode: Opcode.requestFileData, payload: [0x01])
        case .deleteTransferredFile:
            Frame(opcode: Opcode.deleteFile, payload: [0x00])
        }
    }

    public var bytes: [UInt8] { frame.bytes }
}

public enum Mode: UInt8, Sendable {
    /// The board streams its layout as pieces move.
    case realTime = 0x00
    /// The board records games to internal storage instead of streaming.
    case upload = 0x01
}

public enum Chip: UInt8, Sendable {
    case ble = 0x00
    case mcu = 0x01
}
