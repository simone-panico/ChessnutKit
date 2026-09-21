---
name: chessnutkit
description: "Build Swift apps on ChessnutKit, the Swift package for Chessnut electronic chessboards over Bluetooth LE: connect, stream piece positions, turn positions into moves, light LEDs, beep, read battery and firmware, test with a fake transport, decode protocol frames. Use this whenever a project imports ChessnutKit or ChessnutProtocol, or the user mentions a Chessnut board (Air, Pro, Evo), an electronic or smart chessboard, an e-board, reading piece positions from a physical board, or highlighting squares with LEDs in a Swift, SwiftUI, iOS or macOS project, even if they do not name the SDK. Read it before writing or reviewing any code that touches ChessBoard, BLETransport, BoardTransport, Position, Square, LEDMask or Frame."
---

# ChessnutKit

ChessnutKit is a Swift 6 package (tools 6.4, iOS 26 / macOS 26) with two modules:

- `ChessnutKit`: `ChessBoard` (an actor, the API you call), `BLETransport` (CoreBluetooth),
  `BoardTransport` (protocol for other channels and test fakes) and `BoardError`. It re-exports
  `ChessnutProtocol`, so a single `import ChessnutKit` is enough.
- `ChessnutProtocol`: wire format and model types with no Bluetooth dependency: `Frame`,
  `Opcode`, `Command`, `Event`, `Position`, `Square`, `Piece`, `LEDMask`, `Mode`, `Chip`.

The API is small. Every public symbol with its exact signature is listed in
[references/api.md](references/api.md). Read that file instead of guessing a method name;
if something is not listed there, the SDK does not have it.

## Add the dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/simone-panico/ChessnutKit.git", branch: "main"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "ChessnutKit", package: "ChessnutKit"),
    ]),
]
```

Bluetooth needs permission or the connection fails silently at the OS level:

- iOS and macOS apps: add `NSBluetoothAlwaysUsageDescription` to `Info.plist`.
- Sandboxed macOS apps: also enable the `com.apple.security.device.bluetooth` entitlement.
- macOS command line tools are prompted for Bluetooth access on first run.

Build with the Xcode 26 toolchain. If `swift --version` reports anything older than 6.4,
run `xcrun swift build` so SwiftPM picks up Xcode's compiler.

## The connection lifecycle

```swift
import ChessnutKit

let board = ChessBoard(transport: BLETransport())
try await board.connect()

let reader = Task {
    var previous: Position?
    for await position in board.positions {
        if let previous {
            let changes = position.changes(from: previous)
            print("lifted \(changes.lifted) placed \(changes.placed)")
        }
        previous = position
        print(position.fen)
    }
}

let battery = try await board.battery()
let firmware = try await board.version(.mcu)
try await board.beep()
try await board.setLEDs([.e2, .e4])
try await board.setLEDs(.none)

reader.cancel()
await board.disconnect()
```

`connect()` scans for a peripheral whose name contains "Chessnut" (10 s by default), connects,
subscribes to the state and reply characteristics and then puts the board into `.realTime`
mode so it streams positions. Pass `connect(mode: nil)` to skip the mode command, or
`.upload` to make the board record games to its own storage instead of streaming.

Rules that follow from how the SDK is built:

- **Consume `positions` from exactly one task.** It is an `AsyncStream`, so two `for await`
  loops would each receive only some of the elements. Fan out yourself if several views need it.
- **Only the newest position is buffered.** A slow consumer skips intermediate positions,
  which is what you want for a live board. Do not rely on seeing every intermediate state.
- **A `BLETransport` is single use.** After `disconnect()` or a dropped link it refuses to
  connect again. To reconnect, create a new `BLETransport` and a new `ChessBoard`, then
  restart your positions reader on the new board.
- **`positions` does not end on disconnect.** It finishes only when the `ChessBoard` is
  deallocated. You learn that the link dropped when a command or query throws
  `BoardError.disconnected` or `.notConnected`. Call `battery()` periodically if you need a
  heartbeat.
- **Queries run one at a time** with a 2 s timeout (`requestTimeout` in the initializer).
  `battery()`, `version(_:)` and `storedGameCount()` throw `.timedOut` if the board stays
  silent. `beep`, `setLEDs` and `setMode` are fire and forget and never wait for a reply.
- **`lastPosition` and `lastBattery` are actor properties.** Read them with `await`.

Errors to expect: `connect()` throws `bluetoothUnavailable` when Bluetooth is off or denied,
`boardNotFound` after the scan timeout or when the expected characteristics are missing, and
can surface raw CoreBluetooth errors. `BoardError` is `CustomStringConvertible`, so
`"\(error)"` gives a user readable message.

## Turning positions into moves

The board reports which piece sits on each square, never a move. Captures, castling,
en passant and promotions pass through intermediate states (a piece in the air, a target
square momentarily empty), so reconstructing moves from `changes(from:)` alone gets those
cases wrong. Instead, keep the game in your chess model and match each reported position
against the piece placement that every legal move would produce:

```swift
func move(reaching position: Position, in game: Game) -> Move? {
    game.legalMoves.first { move in
        game.playing(move).piecePlacement == position.fen
    }
}
```

`Game`, `Move`, `legalMoves`, `playing` and `piecePlacement` are your own chess model. If no
legal move matches, the position is transient; wait for the next one. This handles promotion
for free because the piece on the promotion square identifies the chosen piece. Use
`changes(from:)` for UI feedback such as highlighting the lifted square.

`position.fen` is only the piece placement field of a FEN, not all six fields. Compare it
against your model's placement string, or append the remaining fields from your game state
(`"\(position.fen) w KQkq - 0 1"`) when a library insists on a full FEN. `Position.standard`
is the starting position, useful to detect that the player has reset the pieces.

Square indexing: `Square.a8.rawValue == 0` through `Square.h1.rawValue == 63`, rank 8 first,
the same order as FEN. Prefer `position[.e4]` over indexing `pieces` directly. A `Piece`
exposes `color`, `kind` and `fenCharacter`.

## LEDs

`setLEDs` replaces the whole mask on every call, it is not additive. Build the full set of
squares you want lit and send it; send `.none` to switch everything off.

```swift
try await board.setLEDs([.e2, .e4])             // array literal
try await board.setLEDs(LEDMask(changes.lifted)) // any sequence of Square

var mask = LEDMask()
mask[.g1] = true
mask[.f3] = true
try await board.setLEDs(mask)
```

## SwiftUI integration

Own the board in a `@MainActor` observable object so the position reaches views without
manual hopping. One task reads positions for the object's lifetime.

```swift
import ChessnutKit
import Observation

@MainActor
@Observable
final class BoardSession {
    private(set) var position: Position?
    private(set) var battery: Int?
    private(set) var errorMessage: String?

    private var board: ChessBoard?
    private var reader: Task<Void, Never>?

    func start() async {
        await stop()
        let board = ChessBoard(transport: BLETransport())
        self.board = board
        do {
            try await board.connect()
            battery = try await board.battery()
        } catch {
            errorMessage = "\(error)"
            return
        }
        reader = Task {
            for await position in board.positions {
                self.position = position
            }
        }
    }

    func stop() async {
        reader?.cancel()
        reader = nil
        await board?.disconnect()
        board = nil
    }

    func highlight(_ squares: LEDMask) async {
        do {
            try await board?.setLEDs(squares)
        } catch {
            errorMessage = "\(error)"
        }
    }
}
```

Calling `start()` again after an error or disconnect is the reconnect path, because it
creates a fresh transport and board.

## Testing without a board

`ChessBoard` only needs a `BoardTransport`, so tests inject a fake that records sent frames
and feeds frames back. Reply asynchronously, not inline in `send`, because `ChessBoard`
registers its expectation after `send` returns; an inline reply can be dropped and the query
would time out.

```swift
import ChessnutKit

actor FakeTransport: BoardTransport {
    nonisolated let frames: AsyncStream<Frame>
    private nonisolated let continuation: AsyncStream<Frame>.Continuation
    private(set) var sent: [Frame] = []
    var replies: [UInt8: Frame] = [:]

    init() {
        let (stream, continuation) = AsyncStream<Frame>.makeStream()
        frames = stream
        self.continuation = continuation
    }

    func connect() async throws {}
    func disconnect() async { continuation.finish() }

    func send(_ frame: Frame) async throws {
        sent.append(frame)
        if let reply = replies[frame.opcode] {
            Task {
                try? await Task.sleep(for: .milliseconds(10))
                continuation.yield(reply)
            }
        }
    }

    func reply(to opcode: UInt8, with frame: Frame) {
        replies[opcode] = frame
    }

    nonisolated func receive(_ frame: Frame) { continuation.yield(frame) }

    nonisolated func receive(_ position: Position) {
        receive(Frame(opcode: Opcode.boardState, payload: position.payload))
    }
}

extension Position {
    var payload: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Position.boardByteCount)
        for square in Square.allCases {
            guard let piece = self[square] else { continue }
            let index = square.hardwareIndex
            bytes[index / 2] |= index.isMultiple(of: 2) ? piece.rawValue : piece.rawValue << 4
        }
        return bytes
    }
}
```

The SDK decodes positions but has no encoder, hence the `payload` extension: even hardware
indices occupy the low nibble, odd ones the high nibble, and `Piece.rawValue` is the nibble.

```swift
import ChessnutKit
import Testing

@Test func streamsPositions() async throws {
    let transport = FakeTransport()
    let board = ChessBoard(transport: transport)
    try await board.connect(mode: nil)

    transport.receive(Position.standard)

    var iterator = board.positions.makeAsyncIterator()
    #expect(await iterator.next() == .standard)
}

@Test func beepSendsTheBeepFrame() async throws {
    let transport = FakeTransport()
    let board = ChessBoard(transport: transport)
    try await board.connect(mode: nil)

    try await board.beep(hz: 880, milliseconds: 100)

    let sent = await transport.sent
    #expect(sent == [Command.beep(hz: 880, milliseconds: 100).frame])
}

@Test func batteryReadsTheReply() async throws {
    let transport = FakeTransport()
    await transport.reply(to: Opcode.queryBattery, with: Frame(opcode: Opcode.batteryReport, payload: [87]))
    let board = ChessBoard(transport: transport)
    try await board.connect(mode: nil)

    #expect(try await board.battery() == 87)
}
```

Use `connect(mode: nil)` in tests unless you want to assert the mode frame too. Compare sent
frames with `Command.someCommand.frame` rather than hand written bytes.

## Dropping to the protocol layer

Use `ChessnutProtocol` directly when you write your own transport (USB, a replay file, a
remote relay) or need a command `ChessBoard` does not wrap:

- `Frame(decoding: bytes)` parses raw bytes and trusts the declared length, so 32 byte USB
  and 36 byte BLE position reports both decode. `frame.bytes` serializes.
- `Event(frame)` classifies an incoming frame into `.position`, `.battery`, `.response`,
  `.fileTransferBegan` or `.fileTransferEnded`.
- `Command` covers everything the board understands, including `.beginFileTransfer`,
  `.requestFileData` and `.deleteTransferredFile`, which `ChessBoard` does not expose.
  Downloading games recorded in `.upload` mode therefore means driving the transport yourself
  with `transport.send(command)`; `ChessBoard` ignores file transfer events.
- `ChessnutBLE` holds the characteristic UUIDs. Pass `onDiscovery` to `BLETransport` to log
  every service and characteristic the board advertises when debugging a new board model.
