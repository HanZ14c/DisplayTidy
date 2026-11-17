import AppKit
import ServiceManagement
import SwiftUI

func loginItemRequested(_ status: SMAppService.Status) -> Bool {
    status == .enabled || status == .requiresApproval
}

func menuIconVisible(onlyWithSecondScreen: Bool, screenCount: Int) -> Bool {
    !onlyWithSecondScreen || screenCount > 1
}

@MainActor
final class SettingsManager: ObservableObject {
    @Published var language = AppLanguage.current {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }
    @Published var menuOnlyWithSecondScreen = UserDefaults.standard.bool(forKey: "menuOnlyWithSecondScreen") {
        didSet { UserDefaults.standard.set(menuOnlyWithSecondScreen, forKey: "menuOnlyWithSecondScreen") }
    }
    @Published var hideNotch = UserDefaults.standard.bool(forKey: "hideNotch") {
        didSet { UserDefaults.standard.set(hideNotch, forKey: "hideNotch") }
    }
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var updating = false
    @Published private(set) var errorMessage: AppMessage?

    var launchAtLogin: Bool { loginItemRequested(loginStatus) }

    func refresh() { loginStatus = SMAppService.mainApp.status }

    func setLaunchAtLogin(_ enabled: Bool) async {
        guard !updating else { return }
        updating = true
        errorMessage = nil
        defer { refresh(); updating = false }
        refresh()
        guard enabled != launchAtLogin else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = AppMessage("Could not change launch at login: %@", AppMessage(error: error))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    let openLog: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("Language"))
                    Spacer()
                    Picker(L("Language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.name).tag(language)
                        }
                    }
                    .labelsHidden()
                }
                Divider()
                Toggle(isOn: $settings.menuOnlyWithSecondScreen) {
                    Text(L("Show menu icon only with multiple displays")).frame(maxWidth: .infinity, alignment: .leading)
                }
                    .toggleStyle(.switch)
                Text(L("Hide the icon when only one display is available. DisplayTidy keeps running. Open the app again to access the main window and settings."))
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(isOn: $settings.hideNotch) {
                    Text(L("Hide notch (experimental)")).frame(maxWidth: .infinity, alignment: .leading)
                }
                    .toggleStyle(.switch)
                Text(L("Adds a black menu bar background to the built-in display with a notch without changing your wallpaper. Results depend on the system menu bar background and text color; turn this off if it looks incorrect."))
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { value in Task { await settings.setLaunchAtLogin(value) } }
                )) {
                    Text(L("Launch at Login")).frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .disabled(settings.updating)
                Text(L("Start DisplayTidy in the menu bar when you log in to your Mac."))
                    .font(.caption).foregroundColor(.secondary)
                if settings.loginStatus == .requiresApproval {
                    Text(L("Approval required. Enable DisplayTidy in Login Items settings."))
                        .font(.caption).foregroundColor(.secondary)
                }
                if let error = settings.errorMessage {
                    Text(error.text()).font(.caption).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(L("Open Login Items Settings")) { SMAppService.openSystemSettingsLoginItems() }
                Divider()
                Button(L("View Log"), action: openLog)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(minWidth: 360, minHeight: 640)
        .navigationTitle(L("DisplayTidy Settings"))
        .onAppear { settings.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refresh()
        }
    }
}

struct LogView: View {
    @ObservedObject var manager: DisplayManager

    var body: some View {
        ScrollView {
            Text(manager.log.isEmpty ? L("No log entries yet") : manager.log)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }.frame(minWidth: 600, minHeight: 360)
    }
}

func runSettingsSelfChecks() throws {
    guard !loginItemRequested(.notRegistered), !loginItemRequested(.notFound),
          loginItemRequested(.enabled), loginItemRequested(.requiresApproval) else {
        throw PrototypeError("登录项状态映射检查失败。")
    }
    print("PASS: login-item states, including pending approval")
    for count in [0, 1, 2, 3] {
        guard menuIconVisible(onlyWithSecondScreen: false, screenCount: count),
              menuIconVisible(onlyWithSecondScreen: true, screenCount: count) == (count > 1) else {
            throw PrototypeError("菜单栏图标显示条件检查失败。")
        }
    }
    print("PASS: menu icon visibility with zero, one and multiple screens")
}
