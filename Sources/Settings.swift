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
            errorMessage = AppMessage("无法修改开机自启：%@", AppMessage(error: error))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    let openLog: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker(L("语言"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.name).tag(language)
                    }
                }
                Divider()
                Toggle(L("仅连接扩展屏时显示菜单栏图标"), isOn: $settings.menuOnlyWithSecondScreen)
                    .toggleStyle(.switch)
                Text(L("没有可用扩展屏时隐藏图标，应用继续运行。重新打开 DisplayTidy 可进入主界面和设置。"))
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(L("隐藏刘海（实验性）"), isOn: $settings.hideNotch)
                    .toggleStyle(.switch)
                Text(L("为带刘海的内建屏幕添加黑色菜单栏背景，不修改壁纸。效果取决于系统菜单栏背景及文字颜色；若显示异常，请关闭。"))
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(L("开机自启"), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { value in Task { await settings.setLaunchAtLogin(value) } }
                ))
                .toggleStyle(.switch)
                .disabled(settings.updating)
                Text(L("登录 Mac 后自动启动，在菜单栏运行。"))
                    .font(.caption).foregroundColor(.secondary)
                if settings.loginStatus == .requiresApproval {
                    Text(L("等待系统允许，请在登录项设置中启用 DisplayTidy。"))
                        .font(.caption).foregroundColor(.secondary)
                }
                if let error = settings.errorMessage {
                    Text(error.text()).font(.caption).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(L("打开系统登录项设置")) { SMAppService.openSystemSettingsLoginItems() }
                Divider()
                Button(L("查看日志"), action: openLog)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(minWidth: 360, minHeight: 260)
        .navigationTitle(L("DisplayTidy 设置"))
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
            Text(manager.log.isEmpty ? L("暂无日志") : manager.log)
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
