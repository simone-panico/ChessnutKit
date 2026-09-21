# ChessnutKit

A Swift package for talking to Chessnut electronic chessboards over Bluetooth LE. It connects to the board, streams the piece positions as they change, and lets you control LEDs, sound and queries such as battery and firmware version.

## Requirements

- Swift 6.4 toolchain (Xcode 26 or newer)
- iOS 26 or macOS 26

## Installation

Add the package to your `Package.swift` or through Xcode's package dependencies, then import it:

```swift
import ChessnutKit
```


## Quick start

```swift
import ChessnutKit

let board = ChessBoard(transport: BLETransport())
try await board.connect()

let battery = try await board.battery()
let firmware = try await board.version(.mcu)

try await board.beep()
try await board.setLEDs([.e2, .e4])

for await position in board.positions {
    print(position.fen)
}
```

`board.positions` is an `AsyncStream<Position>`. Each `Position` gives you the piece on every `Square`, a FEN string via `position.fen`, and `position.changes(from:)` to see which squares were lifted or placed since the last one.

## Modules

- **ChessnutKit**: `ChessBoard`, `BLETransport` and `BoardError`. This is the layer you use in an app.
- **ChessnutProtocol**: the wire format and model types (`Frame`, `Command`, `Position`, `Square`, `Piece`, `LEDMask`). 

## Custom transports

`ChessBoard` talks to the board through the `BoardTransport` protocol. Implement it to run the board over another channel or to replay recorded frames in tests:

```swift
protocol BoardTransport: Sendable {
    var frames: AsyncStream<Frame> { get }
    func connect() async throws
    func disconnect() async
    func send(_ frame: Frame) async throws
}
```

## Bluetooth permission

Apps using `BLETransport` need `NSBluetoothAlwaysUsageDescription` in their `Info.plist`. Command line tools on macOS are prompted for Bluetooth access on first run.

## AI coding assistants

The package ships a skill for Claude Code and other agents that read `SKILL.md` files. It lives in `skills/chessnutkit` and covers the connection lifecycle, turning positions into moves, LEDs, SwiftUI integration and testing with a fake transport. Copy the folder from a checkout of this repository into your app's `.claude/skills/` directory to activate it:

```bash
cp -R ChessnutKit/skills/chessnutkit .claude/skills/chessnutkit
```
