# ChessnutKit public API

Everything public in both modules. `import ChessnutKit` re-exports `ChessnutProtocol`.

## Module ChessnutKit

### `actor ChessBoard`

```swift
init(transport: any BoardTransport, requestTimeout: Duration = .seconds(2))

nonisolated let positions: AsyncStream<Position>   // bufferingNewest(1), single consumer, ends when the link ends

func connect(mode: Mode? = .realTime) async throws  // no-op if already connected
func disconnect() async

func setMode(_ mode: Mode) async throws
func beep(hz: UInt16 = 1000, milliseconds: UInt16 = 200) async throws
func setLEDs(_ mask: LEDMask) async throws

func battery() async throws -> Int                  // percent, waits for the reply
func version(_ chip: Chip) async throws -> String
func storedGameCount() async throws -> Int

var lastPosition: Position? { get }                 // actor isolated, needs await
var lastBattery: Int? { get }
```

Commands throw `BoardError.notConnected` before `connect()`. Queries are serialized and throw
`.timedOut` after `requestTimeout`, `.malformedReply(Frame)` on an unparseable answer, and
`.disconnected` if the link drops while waiting.

### `final class BLETransport: BoardTransport`

```swift
init(
    scanTimeout: Duration = .seconds(10),
    onDiscovery: (@Sendable (CBUUID, CBUUID, CBCharacteristicProperties) -> Void)? = nil
)
let frames: AsyncStream<Frame>
func connect() async throws                        // cancelling the task stops the scan and throws CancellationError
func disconnect() async
func send(_ frame: Frame) async throws
```

Single use: after `disconnect()` or a dropped connection, `connect()` throws `.disconnected`.
Scans for peripherals whose name contains any entry of `ChessnutBLE.deviceNames`.

### `enum ChessnutBLE`

```swift
static let stateCharacteristic: CBUUID   // notifies board positions
static let replyCharacteristic: CBUUID   // notifies query replies
static let writeCharacteristic: CBUUID   // accepts commands
static let deviceNames: [String]         // ["Chessnut"]
```

### `protocol BoardTransport: Sendable`

```swift
var frames: AsyncStream<Frame> { get }
func connect() async throws
func disconnect() async
func send(_ frame: Frame) async throws

// extension
func send(_ command: Command) async throws
```

### `enum BoardError: Error, Equatable, CustomStringConvertible, LocalizedError`

```swift
case bluetoothUnavailable   // Bluetooth off, unauthorized or unsupported
case boardNotFound          // scan timed out or characteristics missing
case notConnected           // operation needs a connection
case timedOut               // query got no reply in time
case malformedReply(Frame)  // reply had an unexpected shape
case disconnected           // link dropped, or transport already used
```

## Module ChessnutProtocol

### `struct Position: Equatable, Sendable`

```swift
static let boardByteCount = 32
static let standard: Position

let pieces: [Piece?]                              // 64 entries, index = Square.rawValue
init(pieces: [Piece?])                            // precondition: 64 entries
init?(payload: some Collection<UInt8>)            // 32+ nibble encoded bytes

subscript(square: Square) -> Piece? { get }
var occupiedSquares: [Square]
var fen: String                                   // piece placement field only
func changes(from previous: Position) -> Changes

struct Changes: Equatable, Sendable {
    let lifted: [Square]   // had a piece before and differs now (removed or replaced)
    let placed: [Square]   // has a piece now and differs from before (added or replaced)
    var isEmpty: Bool
}
```

### `enum Square: Int, CaseIterable, Sendable, CustomStringConvertible`

```swift
case a8 = 0, b8, ..., h8, a7, ..., h1 = 63       // rank 8 first, same order as FEN
init(file: File, rank: Rank)
var file: File
var rank: Rank
var hardwareIndex: Int                            // nibble index in the wire payload
var description: String                           // "e4"
```

### `enum File: Int, CaseIterable` and `enum Rank: Int, CaseIterable`

```swift
File: case a = 0, b, c, d, e, f, g, h            // description "a" ... "h"
Rank: case one = 1, two, ..., eight              // description "1" ... "8"
```

### `enum Piece: UInt8, CaseIterable, Sendable, CustomStringConvertible`

```swift
case blackQueen = 1, blackKing, blackBishop, blackPawn, blackKnight
case whiteRook = 6, whitePawn, blackRook, whiteBishop, whiteKnight, whiteQueen, whiteKing

var color: PieceColor        // .white or .black
var kind: PieceKind          // .pawn .knight .bishop .rook .queen .king
var fenCharacter: Character  // "P" ... "k"
var description: String      // same as fenCharacter
```

`enum PieceColor { case white, black }`, `enum PieceKind { case pawn, knight, bishop, rook, queen, king }`.

### `struct LEDMask: Equatable, Sendable, ExpressibleByArrayLiteral`

```swift
static let none: LEDMask
init()
init(_ squares: some Sequence<Square>)
init(arrayLiteral elements: Square...)
static func squares(_ squares: Square...) -> LEDMask

subscript(square: Square) -> Bool { get set }
var litSquares: [Square]
var isEmpty: Bool
var rows: [UInt8]            // 8 wire bytes, rank 8 first
```

### `enum Command: Equatable, Sendable`

```swift
case setMode(Mode)
case beep(hz: UInt16 = 1000, milliseconds: UInt16 = 200)
case setLEDs(LEDMask)
case queryVersion(Chip)
case queryBattery
case queryFileCount
case beginFileTransfer
case requestFileData
case deleteTransferredFile

var frame: Frame
var bytes: [UInt8]
```

`enum Mode: UInt8 { case realTime = 0x00, upload = 0x01 }`
`enum Chip: UInt8 { case ble = 0x00, mcu = 0x01 }`

### `enum Event: Equatable, Sendable`

```swift
case position(Position)
case battery(Int)
case fileTransferBegan
case fileTransferEnded
case response(Frame)

init(_ frame: Frame)
```

### `struct Frame: Equatable, Sendable`

```swift
let opcode: UInt8
let payload: [UInt8]
init(opcode: UInt8, payload: [UInt8] = [])          // payload must be <= 255 bytes
init?(decoding bytes: some Collection<UInt8>)       // [opcode, length, payload...]
var bytes: [UInt8]
var countValue: Int?                                // first payload byte
var textValue: String?                              // payload after the first byte as UTF-8
```

### `enum Opcode` (static `UInt8` constants)

| Name | Value | Direction |
| --- | --- | --- |
| `boardState` | `0x01` | board to app, position report |
| `setLEDs` | `0x0a` | app to board |
| `beep` | `0x0b` | app to board |
| `setMode` | `0x21` | app to board |
| `queryVersion` | `0x27` | app to board |
| `queryBattery` | `0x29` | app to board |
| `batteryReport` | `0x2a` | board to app |
| `queryFileCount` | `0x31` | app to board |
| `beginFileTransfer` | `0x33` | app to board |
| `requestFileData` | `0x34` | app to board |
| `fileMarker` | `0x37` | board to app, `0xbe` begin / `0xed` end |
| `deleteFile` | `0x39` | app to board |
