public enum Square: Int, CaseIterable, Sendable, CustomStringConvertible {
    case a8 = 0, b8, c8, d8, e8, f8, g8, h8
    case a7, b7, c7, d7, e7, f7, g7, h7
    case a6, b6, c6, d6, e6, f6, g6, h6
    case a5, b5, c5, d5, e5, f5, g5, h5
    case a4, b4, c4, d4, e4, f4, g4, h4
    case a3, b3, c3, d3, e3, f3, g3, h3
    case a2, b2, c2, d2, e2, f2, g2, h2
    case a1, b1, c1, d1, e1, f1, g1, h1

    public init(file: File, rank: Rank) {
        self.init(rawValue: (8 - rank.rawValue) * 8 + file.rawValue)!
    }

    public var file: File { File(rawValue: rawValue % 8)! }
    public var rank: Rank { Rank(rawValue: 8 - rawValue / 8)! }

    public var hardwareIndex: Int { (rawValue / 8) * 8 + (7 - rawValue % 8) }

    public var description: String { "\(file)\(rank)" }
}

public enum File: Int, CaseIterable, Sendable, CustomStringConvertible {
    case a = 0, b, c, d, e, f, g, h

    public var description: String { String(UnicodeScalar(UInt8(97 + rawValue))) }
}

public enum Rank: Int, CaseIterable, Sendable, CustomStringConvertible {
    case one = 1, two, three, four, five, six, seven, eight

    public var description: String { String(rawValue) }
}
