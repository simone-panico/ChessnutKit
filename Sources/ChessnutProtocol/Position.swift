public struct Position: Equatable, Sendable {
    public static let boardByteCount = 32

    public let pieces: [Piece?]

    public init(pieces: [Piece?]) {
        precondition(pieces.count == 64, "a position has 64 squares")
        self.pieces = pieces
    }

    public init?(payload: some Collection<UInt8>) {
        let bytes = Array(payload)
        guard bytes.count >= Self.boardByteCount else { return nil }
        var pieces = [Piece?](repeating: nil, count: 64)
        for square in Square.allCases {
            let index = square.hardwareIndex
            let byte = bytes[index / 2]
            let nibble = index.isMultiple(of: 2) ? byte & 0x0f : byte >> 4
            pieces[square.rawValue] = Piece(rawValue: nibble)
        }
        self.pieces = pieces
    }

    public subscript(square: Square) -> Piece? { pieces[square.rawValue] }

    public var occupiedSquares: [Square] {
        Square.allCases.filter { pieces[$0.rawValue] != nil }
    }

    public var fen: String {
        var result = ""
        for rank in 0 ..< 8 {
            var empty = 0
            for file in 0 ..< 8 {
                if let piece = pieces[rank * 8 + file] {
                    if empty > 0 {
                        result += String(empty)
                        empty = 0
                    }
                    result.append(piece.fenCharacter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { result += String(empty) }
            if rank < 7 { result.append("/") }
        }
        return result
    }

    public struct Changes: Equatable, Sendable {
        public let lifted: [Square]
        public let placed: [Square]

        public var isEmpty: Bool { lifted.isEmpty && placed.isEmpty }
    }

    public func changes(from previous: Position) -> Changes {
        var lifted: [Square] = []
        var placed: [Square] = []
        for square in Square.allCases {
            let before = previous[square]
            let after = self[square]
            guard before != after else { continue }
            if before != nil { lifted.append(square) }
            if after != nil { placed.append(square) }
        }
        return Changes(lifted: lifted, placed: placed)
    }
}

extension Position {
    public static let standard = Position(pieces: [
        .blackRook, .blackKnight, .blackBishop, .blackQueen,
        .blackKing, .blackBishop, .blackKnight, .blackRook,
        .blackPawn, .blackPawn, .blackPawn, .blackPawn,
        .blackPawn, .blackPawn, .blackPawn, .blackPawn,
    ] + [Piece?](repeating: nil, count: 32) + [
        .whitePawn, .whitePawn, .whitePawn, .whitePawn,
        .whitePawn, .whitePawn, .whitePawn, .whitePawn,
        .whiteRook, .whiteKnight, .whiteBishop, .whiteQueen,
        .whiteKing, .whiteBishop, .whiteKnight, .whiteRook,
    ])
}
