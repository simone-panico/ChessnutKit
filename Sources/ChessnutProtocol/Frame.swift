// Copied from EasyLinkSDK.cpp
public enum Opcode {
    public static let boardState: UInt8        = 0x01
    public static let setLEDs: UInt8           = 0x0a
    public static let beep: UInt8              = 0x0b
    public static let setMode: UInt8           = 0x21
    public static let queryVersion: UInt8      = 0x27
    public static let queryBattery: UInt8      = 0x29
    public static let batteryReport: UInt8     = 0x2a
    public static let queryFileCount: UInt8    = 0x31
    public static let beginFileTransfer: UInt8 = 0x33
    public static let requestFileData: UInt8   = 0x34
    public static let fileMarker: UInt8        = 0x37
    public static let deleteFile: UInt8        = 0x39
}

public struct Frame: Equatable, Sendable {
    public let opcode: UInt8
    public let payload: [UInt8]

    public init(opcode: UInt8, payload: [UInt8] = []) {
        precondition(payload.count <= Int(UInt8.max), "payload length must fit in one byte")
        self.opcode = opcode
        self.payload = payload
    }

    /// Reads a frame from raw bytes, trusting the declared length rather than the
    /// buffer size. USB reports 32 payload bytes for a position and BLE reports 36,
    /// so both decode without a transport-specific branch.
    public init?(decoding bytes: some Collection<UInt8>) {
        let bytes = Array(bytes)
        guard bytes.count >= 2 else { return nil }
        let length = Int(bytes[1])
        guard bytes.count >= length + 2 else { return nil }
        self.opcode = bytes[0]
        self.payload = Array(bytes[2 ..< length + 2])
    }

    public var bytes: [UInt8] { [opcode, UInt8(payload.count)] + payload }
}

extension Frame {
    public var countValue: Int? { payload.first.map(Int.init) }

    public var textValue: String? {
        guard payload.count > 1 else { return nil }
        return String(decoding: payload.dropFirst(), as: UTF8.self)
    }
}
