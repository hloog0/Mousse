import Foundation
import QuartzCore

/// `MOUSSE_LOG=1` writes wheel input and every animation frame to stderr, for tuning.
/// Launch with: open --env MOUSSE_LOG=1 --stderr /tmp/mousse.log /Applications/Mousse.app
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["MOUSSE_LOG"] != nil

    static func write(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = String(format: "%.4f ", CACurrentMediaTime()) + message() + "\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
