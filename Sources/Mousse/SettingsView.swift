import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: Settings
    let permissions: Permissions

    var body: some View {
        Form {
            if !permissions.trusted {
                Section {
                    Label("Mousse needs Accessibility access to take over the mouse wheel.",
                          systemImage: "exclamationmark.triangle.fill")
                    Button("Open Privacy & Security…") { permissions.openSettings() }
                }
            }

            Section("Feel") {
                Toggle("Smooth scrolling", isOn: $settings.enabled)
                LabeledContent("Glide after you stop") {
                    valueSlider($settings.stopGlideMs, in: Settings.stopGlideRange, step: 30, label: Settings.stopGlideLabel)
                }
                LabeledContent("Step size") {
                    valueSlider($settings.stepSize, in: Settings.stepRange, step: 10) { "\(Int($0)) px" }
                }
                LabeledContent("Animation time") {
                    valueSlider($settings.animationMs, in: Settings.animationRange, step: 20) { "\(Int($0)) ms" }
                }
                LabeledContent("Acceleration") {
                    valueSlider($settings.accelerationMax, in: Settings.accelerationRange, step: 0.5) {
                        $0 == 1 ? "off" : String(format: "%g×", $0)
                    }
                }
                Toggle("Shift + wheel scrolls sideways", isOn: $settings.shiftHorizontal)
            }

            Section("Try it here") {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(1...150, id: \.self) { row in
                            Text("Row \(row)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(row.isMultiple(of: 2) ? Color.secondary.opacity(0.08) : .clear)
                        }
                    }
                }
                .frame(height: 150)
            }

            Section {
                ForEach(settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        AppLabel(bundleID: id)
                        Spacer()
                        Button { settings.setExcluded(id, false) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Turn smoothing back on for this app")
                    }
                }
                Button("Add App…", action: addApps)
            } header: {
                Text("Off in these apps")
            } footer: {
                Text("Matched against the app under the pointer, since that's where the wheel scrolls.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
    }

    private func valueSlider(
        _ value: Binding<Double>, in range: ClosedRange<Double>, step: Double, label: (Double) -> String
    ) -> some View {
        HStack {
            Slider(value: value, in: range, step: step)
            Text(label(value.wrappedValue))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        .frame(width: 240)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { settings.setExcluded(id, true) }
        }
    }
}

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(url?.deletingPathExtension().lastPathComponent ?? bundleID)
        }
    }
}
