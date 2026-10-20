import Foundation
import ServiceManagement

/// User preferences, persisted in UserDefaults (domain com.steve.smoothwheel).
@MainActor
@Observable
final class Settings {
    // Defaults: 100 px steps, 400 ms animations, up to 3× acceleration.
    static let stepRange = 20.0...300.0
    static let animationRange = 100.0...1000.0
    static let accelerationRange = 1.0...7.0
    /// The top of the range means "Full": no braking, every notch plays out.
    static let stopGlideRange = 60.0...480.0

    var enabled: Bool { didSet { store(enabled, "enabled") } }
    /// How long scrolling takes to come to rest after the wheel stops turning.
    var stopGlideMs: Double { didSet { store(stopGlideMs, "stopGlideMs") } }
    /// Pixels one wheel notch scrolls (before acceleration).
    var stepSize: Double { didSet { store(stepSize, "stepSize") } }
    /// How long each notch's animation lasts.
    var animationMs: Double { didSet { store(animationMs, "animationMs") } }
    /// Largest boost for fast spins; 1 turns acceleration off.
    var accelerationMax: Double { didSet { store(accelerationMax, "accelerationMax") } }
    var shiftHorizontal: Bool { didSet { store(shiftHorizontal, "shiftHorizontal") } }
    var excludedBundleIDs: [String] { didSet { store(excludedBundleIDs, "excludedBundleIDs") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            "enabled": true,
            "stopGlideMs": 150.0,
            "stepSize": 100.0,
            "animationMs": 400.0,
            "accelerationMax": 3.0,
            "shiftHorizontal": true,
            "excludedBundleIDs": [String](),
        ])
        enabled = defaults.bool(forKey: "enabled")
        stopGlideMs = defaults.double(forKey: "stopGlideMs")
        stepSize = defaults.double(forKey: "stepSize")
        animationMs = defaults.double(forKey: "animationMs")
        accelerationMax = defaults.double(forKey: "accelerationMax")
        shiftHorizontal = defaults.bool(forKey: "shiftHorizontal")
        excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
    }

    /// Seconds for the smoother, or nil for a full glide.
    var stopTime: Double? {
        stopGlideMs >= Self.stopGlideRange.upperBound ? nil : stopGlideMs / 1000
    }

    static func stopGlideLabel(_ ms: Double) -> String {
        ms >= stopGlideRange.upperBound ? "Full" : "\(Int(ms)) ms"
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        bundleID.map(excludedBundleIDs.contains) ?? false
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        excludedBundleIDs.removeAll { $0 == bundleID }
        if excluded { excludedBundleIDs.append(bundleID) }
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

/// Launch at login via the modern login-item API.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var lastError: String?

    init() { refresh() }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        if needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    private func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
}
