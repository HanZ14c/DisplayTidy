import AppKit

@MainActor
func runMenuVisibilitySelfChecks() async throws {
    let notifications = NotificationCenter()
    @MainActor final class Count { var value = 3 }
    let activeCount = Count()
    let screens = ScreenAvailability(notifications: notifications, readCount: { activeCount.value })
    guard screens.count == 3 else { throw PrototypeError("Initial display count was not loaded.") }

    for count in [1, 2, 1, 3, 1] {
        activeCount.value = count
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        guard screens.count == count,
              menuIconVisible(onlyWithSecondScreen: true, screenCount: screens.count) == (count > 1),
              menuIconVisible(onlyWithSecondScreen: false, screenCount: screens.count) else {
            throw PrototypeError("Display notifications did not update menu visibility.")
        }
    }
    for count in [0, 2, 1] {
        activeCount.value = count
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    try await Task.sleep(nanoseconds: 250_000_000)
    guard screens.count == 1 else { throw PrototypeError("Transient display events replaced the final count.") }
    activeCount.value = 2
    notifications.post(name: NSApplication.didFinishLaunchingNotification, object: nil)
    try await Task.sleep(nanoseconds: 250_000_000)
    guard screens.count == 2 else { throw PrototypeError("Startup display count was not refreshed.") }
    activeCount.value = 1
    notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    try await Task.sleep(nanoseconds: 250_000_000)
    guard screens.count == 1 else { throw PrototypeError("Activation display count was not refreshed.") }
    print("PASS: menu visibility follows 3→1→2→1 screens, final reconfiguration state, startup and activation")
}
