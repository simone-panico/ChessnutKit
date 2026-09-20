public enum PieceColor: Sendable, Equatable {
    case white, black
}

public enum PieceKind: Sendable, Equatable {
    case pawn, knight, bishop, rook, queen, king
}

public enum Piece: UInt8, CaseIterable, Sendable, CustomStringConvertible {
    // Copied from EasyLinkSDK.cpp
    case blackQueen  = 1
    case blackKing   = 2
    case blackBishop = 3
    case blackPawn   = 4
    case blackKnight = 5
    case whiteRook   = 6
    case whitePawn   = 7
    case blackRook   = 8
    case whiteBishop = 9
    case whiteKnight = 10
    case whiteQueen  = 11
    case whiteKing   = 12

    public var color: PieceColor {
        switch self {
        case .blackQueen, .blackKing, .blackBishop, .blackPawn, .blackKnight, .blackRook: .black
        case .whiteRook, .whitePawn, .whiteBishop, .whiteKnight, .whiteQueen, .whiteKing: .white
        }
    }

    public var kind: PieceKind {
        switch self {
        case .blackPawn, .whitePawn: .pawn
        case .blackKnight, .whiteKnight: .knight
        case .blackBishop, .whiteBishop: .bishop
        case .blackRook, .whiteRook: .rook
        case .blackQueen, .whiteQueen: .queen
        case .blackKing, .whiteKing: .king
        }
    }

    // Copied from EasyLinkSDK.cpp
    public var fenCharacter: Character {
        switch self {
        case .blackQueen: "q"
        case .blackKing: "k"
        case .blackBishop: "b"
        case .blackPawn: "p"
        case .blackKnight: "n"
        case .whiteRook: "R"
        case .whitePawn: "P"
        case .blackRook: "r"
        case .whiteBishop: "B"
        case .whiteKnight: "N"
        case .whiteQueen: "Q"
        case .whiteKing: "K"
        }
    }

    public var description: String { String(fenCharacter) }
}
