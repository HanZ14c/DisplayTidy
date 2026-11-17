import AppKit
import Combine
import SwiftUI

struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct MenuBarTopAnchor: NSViewRepresentable {
    let onOpen: () -> Void
    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onOpen = onOpen
        return view
    }
    func updateNSView(_ nsView: AnchorView, context: Context) { nsView.onOpen = onOpen }

    final class AnchorView: NSView {
        private var activation: AnyCancellable?
        private var visibility: AnyCancellable?
        var onOpen: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            activation = nil
            visibility = nil
            guard let window else { return }
            visibility = window.publisher(for: \.isVisible, options: [.initial, .new])
                .removeDuplicates()
                .filter { $0 }
                .sink { [weak self] _ in
                    DispatchQueue.main.async { [weak self] in
                        guard self?.window?.isVisible == true else { return }
                        self?.onOpen?()
                    }
                }
            activation = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window)
                .sink { [weak self] _ in self?.scheduleAlignment() }
            scheduleAlignment()
        }

        private func scheduleAlignment() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, let screen = window.screen else { return }
                window.setFrameOrigin(CGPoint(x: window.frame.minX,
                                              y: screen.visibleFrame.maxY - window.frame.height))
            }
        }
    }
}

struct MainView: View {
    @ObservedObject var manager: DisplayManager
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("DisplayTidy").font(.title).bold()
                Spacer()
                Button(L("Refresh Displays")) { manager.refresh() }.buttonStyle(.bordered).disabled(manager.busy)
                Button(L("Settings"), action: openSettings).buttonStyle(.bordered)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker(L("Reference"), selection: $manager.reference) {
                                ForEach(manager.displays) { d in
                                    Text("\(d.name) · \(d.width) × \(d.height)").tag(d.id)
                                }
                            }
                            Picker(L("Move"), selection: $manager.target) {
                                ForEach(manager.displays.filter { $0.id != manager.reference }.sorted { $0.id < $1.id }) { d in
                                    Text("\(d.name) · \(d.width) × \(d.height)").tag(d.id)
                                }
                            }
                            Divider()
                            AlignmentControl(manager: manager, showsPositionMenu: true).frame(maxWidth: .infinity)
                        }.padding(10)
                    }.disabled(manager.busy)
                    Text(manager.status.text()).font(.callout).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                Button(L("Quit DisplayTidy")) { NSApp.terminate(nil) }
                    .buttonStyle(.bordered).disabled(manager.busy)
            }
        }.padding(20).frame(minWidth: 600, minHeight: 560)

    }
}

struct QuickPanel: View {
    @ObservedObject var manager: DisplayManager
    let openMainWindow: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DisplayTidy").font(.headline)
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .help(L("Settings")).accessibilityLabel(L("Settings"))
                Button { manager.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }.help(L("Refresh Displays")).accessibilityLabel(L("Refresh Displays"))
                    .disabled(manager.busy)
            }
            Picker(L("Reference"), selection: $manager.reference) {
                ForEach(manager.displays) { display in
                    Text(display.name).tag(display.id)
                }
            }.disabled(manager.busy)
            Picker(L("Move"), selection: $manager.target) {
                ForEach(manager.displays.filter { $0.id != manager.reference }.sorted { $0.id < $1.id }) { display in
                    Text(display.name).tag(display.id)
                }
            }.disabled(manager.busy)
            AlignmentControl(manager: manager)
            if let error = manager.errorMessage {
                Text(error.text()).font(.caption).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button(L("Open Main Window"), action: openMainWindow)
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }.disabled(manager.busy)
            }
        }.padding(12).frame(width: 268)
            .background(MenuBarTopAnchor(onOpen: { manager.selectReferenceAtPointer() }))
    }
}

@MainActor
final class AppWindows: NSObject, ObservableObject, NSWindowDelegate {
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var logWindow: NSWindow?
    let settings = SettingsManager()
    private var languageChanges: AnyCancellable?

    override init() {
        super.init()
        languageChanges = settings.$language.sink { [weak self] language in
            self?.settingsWindow?.title = L("DisplayTidy Settings", language: language)
            self?.logWindow?.title = L("DisplayTidy Log", language: language)
        }
    }

    func openMain(manager: DisplayManager) {
        manager.selectReferenceAtPointer()
        NSApp.keyWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.regular)
        if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }
        show(&mainWindow, title: "DisplayTidy", size: NSSize(width: 680, height: 700),
             content: MainView(manager: manager, openSettings: { self.openSettings(manager: manager) }))
        mainWindow?.delegate = self
        mainWindow?.contentMinSize = NSSize(width: 600, height: 560)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func openSettings(manager: DisplayManager) {
        // Only dismiss the menu panel; keep the main window visible.
        if NSApp.keyWindow?.title.isEmpty == true { NSApp.keyWindow?.orderOut(nil) }
        settings.refresh()
        show(&settingsWindow, title: "DisplayTidy Settings", size: NSSize(width: 420, height: 380),
             content: SettingsView(settings: settings, openLog: { self.openLog(manager: manager) }))
        settingsWindow?.contentMinSize = NSSize(width: 360, height: 260)
    }

    func openLog(manager: DisplayManager) {
        show(&logWindow, title: "DisplayTidy Log", size: NSSize(width: 760, height: 480), content: LogView(manager: manager))
        logWindow?.contentMinSize = NSSize(width: 600, height: 360)
    }

    private func show<Content: View>(_ window: inout NSWindow?, title: String, size: NSSize, content: Content) {
        if window == nil {
            let created = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                   backing: .buffered, defer: false)
            created.title = L(title)
            created.isReleasedWhenClosed = false
            created.titlebarAppearsTransparent = true
            created.isOpaque = false
            created.backgroundColor = .clear
            // Extend only the material; keep controls inside the title bar's safe area.
            created.contentView = NSHostingView(rootView: LocalizedRoot(settings: settings, content: content)
                .background(WindowBackground().ignoresSafeArea()))
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ScreenAvailability: ObservableObject {
    @Published private(set) var count: Int
    private var changes: AnyCancellable?

    init(notifications: NotificationCenter = .default,
         readCount: @escaping @MainActor () -> Int = { NSScreen.screens.count }) {
        count = readCount()
        changes = Publishers.Merge3(
            notifications.publisher(for: NSApplication.didChangeScreenParametersNotification),
            notifications.publisher(for: NSApplication.didFinishLaunchingNotification),
            notifications.publisher(for: NSApplication.didBecomeActiveNotification)
        )
        .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in self?.count = readCount() }
    }
}

@MainActor
final class MenuBarApplication: NSObject, NSApplicationDelegate {
    let manager = DisplayManager()
    let windows = AppWindows()
    private var notchBackground: NotchBackground?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notchBackground = NotchBackground(settings: windows.settings)
        manager.refresh()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        manager.refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.openMain(manager: manager)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct DisplayTidyApplication: App {
    @NSApplicationDelegateAdaptor(MenuBarApplication.self) private var application
    @StateObject private var screens = ScreenAvailability()
    @AppStorage("menuOnlyWithSecondScreen") private var onlyWithSecondScreen = false

    var body: some Scene {
        MenuBarExtra("DisplayTidy", systemImage: "display.2", isInserted: Binding(
            get: { menuIconVisible(onlyWithSecondScreen: onlyWithSecondScreen, screenCount: screens.count) },
            set: { _ in }
        )) {
            LocalizedRoot(settings: application.windows.settings, content: QuickPanel(manager: application.manager,
                       openMainWindow: { application.windows.openMain(manager: application.manager) },
                       openSettings: { application.windows.openSettings(manager: application.manager) }))
        }
        .menuBarExtraStyle(.window)
        // Keep a standard settings scene when the menu bar item is hidden.
        Settings {
            LocalizedRoot(settings: application.windows.settings, content: SettingsView(settings: application.windows.settings,
                         openLog: { application.windows.openLog(manager: application.manager) }))
        }
    }
}

@main
struct Entry {
    @MainActor static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty { DisplayTidyApplication.main(); return }
        do {
            switch args {
            case ["--self-test"]: try runSelfChecks(); try runSettingsSelfChecks(); try runNotchSelfChecks(); try runPreviewSelfChecks(); try runScreenSelectionSelfChecks(); try runLocalizationSelfChecks(); try await runMenuVisibilitySelfChecks()
            case ["--list"]:
                let manager = DisplayManager()
                let displays = try manager.read()
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(DisplayReport(displays: displays)), as: UTF8.self))
            default:
                guard args.count == 2, ["--move-below-center", "--move-below-left", "--move-below-right"].contains(args[0]), let id = UInt32(args[1]) else {
                    throw PrototypeError("Usage: --list | --self-test | --move-below-center DISPLAY_ID | --move-below-left DISPLAY_ID | --move-below-right DISPLAY_ID; run without arguments to start the menu bar app.")
                }
                try await DisplayManager().move(id, alignment: args[0] == "--move-below-left" ? .start : (args[0] == "--move-below-right" ? .end : .center))
            }
        } catch {
            print("ERROR: \(error.localizedDescription)")
            exit(1)
        }
    }

}
