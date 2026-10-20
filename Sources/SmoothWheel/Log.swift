import Foundation
import QuartzCore

/// `SMOOTHWHEEL_LOG=1` writes wheel input and every animation frame to stderr, for tuning.
/// Launch with: open --env SMOOTHWHEEL_LOG=1 --stderr /tmp/smoothwheel.log ~/Applications/SmoothWheel.app
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["SMOOTHWHEEL_LOG"] != nil

    static func write(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = String(format: "%.4f ", CACurrentMediaTime()) + message() + "\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
