import AppKit
import ApplicationServices

/// Accessibility permission, which an event tap that modifies events requires.
@MainActor
@Observable
final class Permissions {
    private(set) var trusted = AXIsProcessTrusted()
    @ObservationIgnored private var timer: Timer?

    /// Shows the system prompt (once per app identity) that offers to open Settings.
    func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// There's no notification for being granted access, so check every couple of seconds.
    func whenTrusted(_ action: @escaping () -> Void) {
        if trusted { return action() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                timer.invalidate()
                self.trusted = true
                action()
            }
        }
    }
}
