import AppKit
import Combine

func notchBackgroundFrame(screen: NSRect, topInset: CGFloat, builtIn: Bool) -> NSRect? {
    guard builtIn, topInset > 0, topInset < screen.height, screen.width > 0 else { return nil }
    return NSRect(x: screen.minX, y: screen.maxY - topInset, width: screen.width, height: topInset)
}

private final class NotchWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchBackground {
    private var windows: [NSWindow] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var enabled = false

    init(settings: SettingsManager) {
        settings.$hideNotch.removeDuplicates().sink { [weak self] enabled in
            self?.enabled = enabled
            self?.refresh()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        ).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
    }

    private func refresh() {
        windows.forEach { $0.close() }
        windows.removeAll()
        guard enabled else { return }
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let frame = notchBackgroundFrame(screen: screen.frame, topInset: screen.safeAreaInsets.top,
                                                   builtIn: CGDisplayIsBuiltin(number.uint32Value) != 0) else { continue }
            let window = NotchWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            // shortcut: system menu backgrounds can cover this layer; revisit after testing supported macOS versions.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isExcludedFromWindowsMenu = true
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }
}

func runNotchSelfChecks() throws {
    for origin in [NSPoint.zero, NSPoint(x: -1512, y: 300), NSPoint(x: 800, y: -1400)] {
        let screen = NSRect(origin: origin, size: NSSize(width: 1512, height: 982))
        let expected = NSRect(x: origin.x, y: origin.y + 950, width: 1512, height: 32)
        guard notchBackgroundFrame(screen: screen, topInset: 32, builtIn: true) == expected,
              notchBackgroundFrame(screen: screen, topInset: 0, builtIn: true) == nil,
              notchBackgroundFrame(screen: screen, topInset: 32, builtIn: false) == nil,
              notchBackgroundFrame(screen: screen, topInset: 982, builtIn: true) == nil else {
            throw PrototypeError("Notch background geometry check failed.")
        }
    }
    print("PASS: notch strip geometry, offset screens, external and notch-free exclusions")
}
