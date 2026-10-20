import SwiftUI

@main
struct SmoothWheelApp: App {
    // Plain `let`, not @State: the App is created once, and SwiftUI's macro plugins
    // (which @State needs) only ship with full Xcode, not the Command Line Tools.
    private let controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(controller: controller, settings: controller.settings, loginItem: controller.loginItem)
        } label: {
            Image(systemName: controller.settings.enabled ? "computermouse.fill" : "computermouse")
        }
        .menuBarExtraStyle(.window)

        Window("SmoothWheel", id: "settings") {
            SettingsView(settings: controller.settings, permissions: controller.permissions)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// The small panel under the menu bar icon: the everyday controls, one click away.
private struct MenuPanel: View {
    let controller: AppController
    @Bindable var settings: Settings
    let loginItem: LoginItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !controller.permissions.trusted {
                Button("Grant Accessibility Access…") { controller.permissions.openSettings() }
            }

            Toggle("Smooth scrolling", isOn: $settings.enabled)
                .toggleStyle(.switch)
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Glide after you stop")
                    Spacer()
                    Text(Settings.stopGlideLabel(settings.stopGlideMs))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.stopGlideMs, in: Settings.stopGlideRange, step: 30) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("Short").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Full").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.enabled)

            Divider()

            if let app = controller.frontApp {
                Toggle("Off in \(app.name)", isOn: Binding(
                    get: { settings.isExcluded(app.bundleID) },
                    set: { settings.setExcluded(app.bundleID, $0) }
                ))
            }
            Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))

            Divider()

            HStack {
                Button("More Settings…") {
                    openWindow(id: "settings")
                    // A menu bar app isn't active by default, so bring the window forward explicitly.
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 290)
    }
}
