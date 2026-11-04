import SwiftUI
import GoodScrollCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let statusProvider: () -> String
    let onRestartTap: () -> Void

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var trusted = Permissions.isTrusted
    @State private var status = ""

    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Enable GoodScroll", isOn: $settings.enabled)
            }

            Section("Mouse") {
                Toggle("Discrete scrolling", isOn: $settings.discrete)
                Stepper(value: $settings.linesPerNotch, in: ScrollConfig.lineRange) {
                    HStack {
                        Text("Lines per notch")
                        Spacer()
                        Text("\(settings.linesPerNotch)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .disabled(!settings.discrete)
                Toggle("Discrete horizontal scrolling", isOn: $settings.applyHorizontal)
                    .disabled(!settings.discrete)
                Picker("Direction", selection: $settings.mouseDirection) {
                    ForEach(ScrollDirection.allCases, id: \.self) { Text(directionLabel($0)).tag($0) }
                }
                Picker("Smooth scroll while holding", selection: $settings.bypassModifier) {
                    ForEach(BypassModifier.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(!settings.discrete)
                Text(settings.discrete
                     ? "Each wheel click scrolls exactly this many lines, with no acceleration."
                     : "Discrete scrolling is off: the mouse keeps macOS acceleration; only the direction setting applies.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!settings.enabled)

            Section("Trackpad & Magic Mouse") {
                Picker("Direction", selection: $settings.trackpadDirection) {
                    ForEach(ScrollDirection.allCases, id: \.self) { Text(directionLabel($0)).tag($0) }
                }
                Text("Speed, acceleration and momentum are never changed, only direction. Tip: Natural here and Traditional for the mouse gives each device its own feel, whatever the system checkbox says.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!settings.enabled)

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do { try LoginItem.set(newValue); loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = LoginItem.isEnabled }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                if LoginItem.needsApproval {
                    Text("Approve GoodScroll in System Settings → General → Login Items.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    Text("Open GoodScroll again from Finder or Spotlight to get back to this window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Status") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Device Control & Data Access granted" : "Needs Device Control & Data Access")
                    Spacer()
                    if !trusted { Button("Open Settings…") { Permissions.openAccessibilitySettings() } }
                }
                HStack {
                    Text(status).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Event Tap", action: onRestartTap).disabled(!trusted)
                }
            }

            HStack {
                Button("Reset to Defaults") { settings.resetToDefaults() }
                Spacer()
                Link("Source on GitHub", destination: AppDelegate.repoURL)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private func directionLabel(_ d: ScrollDirection) -> String {
        d == .followSystem ? "Follow System (\(settings.systemNatural ? "Natural" : "Traditional"))" : d.label
    }

    private func refresh() {
        settings.refreshSystemNatural()
        trusted = Permissions.isTrusted
        status = statusProvider()
        launchAtLogin = LoginItem.isEnabled
    }
}
