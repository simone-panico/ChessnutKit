public struct LEDMask: Equatable, Sendable, ExpressibleByArrayLiteral {
    private var bits: UInt64

    public static let none = LEDMask()

    public init() { bits = 0 }

    public init(_ squares: some Sequence<Square>) {
        bits = squares.reduce(into: UInt64(0)) { $0 |= 1 << UInt64($1.rawValue) }
    }

    public init(arrayLiteral elements: Square...) { self.init(elements) }

    public static func squares(_ squares: Square...) -> LEDMask { LEDMask(squares) }

    public subscript(square: Square) -> Bool {
        get { bits & (1 << UInt64(square.rawValue)) != 0 }
        set {
            let bit = UInt64(1) << UInt64(square.rawValue)
            if newValue { bits |= bit } else { bits &= ~bit }
        }
    }

    public var litSquares: [Square] { Square.allCases.filter { self[$0] } }

    public var isEmpty: Bool { bits == 0 }

    public var rows: [UInt8] {
        (0 ..< 8).map { rank in
            var byte: UInt8 = 0
            for file in 0 ..< 8 where bits & (1 << UInt64(rank * 8 + file)) != 0 {
                byte |= 1 << UInt8(7 - file)
            }
            return byte
        }
    }
}
