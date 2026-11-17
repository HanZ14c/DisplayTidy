import AppKit
import ColorSync
import CoreGraphics

func screenAtPointer(_ point: CGPoint, screens: [(id: UInt32, frame: CGRect)]) -> UInt32? {
    screens.first(where: { $0.frame.contains(point) })?.id
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published var displays: [Display] = []
    @Published var log = ""
    @Published var busy = false
    @Published var reference: UInt32 = 0 {
        didSet {
            guard reference != oldValue else { return }
            if !displays.contains(where: { $0.id == target && $0.id != reference }) { target = defaultTarget }
            syncCurrentAlignment()
        }
    }
    @Published var target: UInt32 = 0 { didSet { if target != oldValue { syncCurrentAlignment() } } }
    @Published var selection = AlignmentOption(direction: .below, alignment: .center) { didSet { showingActualPosition = false } }
    @Published var showingActualPosition = false
    @Published var status: AppMessage = "选择参考屏幕、移动屏幕和对齐方式，然后应用。"
    @Published var errorMessage: AppMessage?
    @Published var saved: Arrangement?
    let arrangementURL: URL
    var storageError: AppMessage?

    private var defaultTarget: UInt32 {
        displays.filter { $0.id != reference }.map(\.id).min() ?? 0
    }

    var hasPendingChange: Bool {
        guard !showingActualPosition,
              let main = displays.first(where: { $0.id == reference }),
              let target = displays.first(where: { $0.id == self.target && $0.id != reference }),
              let changed = try? selection.changesPosition(of: target, relativeTo: main) else { return false }
        return changed
    }

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        arrangementURL = root.appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.DisplayTidy").appendingPathComponent("arrangement.json")
        if FileManager.default.fileExists(atPath: arrangementURL.path) {
            do {
                let value = try JSONDecoder().decode(Arrangement.self, from: Data(contentsOf: arrangementURL))
                saved = value; selection = AlignmentOption(direction: value.direction, alignment: value.alignment)
                status = "已载入上次的排列；点击应用才会移动屏幕。"
            } catch {
                storageError = AppMessage("排列文件无法读取，原文件已保留：%@", AppMessage(error: error))
                status = storageError!
                errorMessage = storageError
            }
        }
    }

    func report(_ error: Error) {
        status = AppMessage("应用失败：%@", AppMessage(error: error))
        errorMessage = status
        note(status.text())
    }

    func note(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)"
        log += line + "\n"
        print(line)
    }

    func check(_ error: CGError, _ operation: String) throws {
        guard error == .success else { throw PrototypeError("\(operation): CGError \(error.rawValue) (\(error))") }
    }

    func read() throws -> [Display] {
        var count: UInt32 = 0
        try check(CGGetActiveDisplayList(0, nil, &count), "CGGetActiveDisplayList/count")
        guard count > 0 else { throw PrototypeError("没有活动显示器。") }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        try check(CGGetActiveDisplayList(count, &ids, &count), "CGGetActiveDisplayList/list")
        let names = Dictionary(NSScreen.screens.compactMap { screen -> (UInt32, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        }, uniquingKeysWith: { first, _ in first })
        return try ids.prefix(Int(count)).map { id in
            let bounds = CGDisplayBounds(id)
            let values = [bounds.minX, bounds.minY, bounds.width, bounds.height]
            guard values.allSatisfy({ $0.isFinite && $0 >= CGFloat(Int32.min) && $0 <= CGFloat(Int32.max) && $0.rounded() == $0 }) else {
                throw PrototypeError("屏幕 %@ 的 bounds 无效或不是整数。", AppMessage(verbatim: String(id)))
            }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            return Display(id: id, uuid: uuid, name: names[id] ?? "Display \(id)", vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id), main: CGDisplayIsMain(id) != 0, mirrored: CGDisplayIsInMirrorSet(id) != 0, x: Int32(bounds.minX), y: Int32(bounds.minY), width: Int32(bounds.width), height: Int32(bounds.height))
        }
    }

    func refresh() {
        guard !busy else { return }
        errorMessage = storageError
        do {
            displays = try read()
            reconcileSelections()
            for d in displays {
                note("ID=\(d.id) \(d.name) main=\(d.main) bounds=(\(d.x),\(d.y),\(d.width),\(d.height)) UUID=\(d.uuid ?? "missing")")
            }
        } catch { status = AppMessage("读取失败：%@", AppMessage(error: error)); errorMessage = status; note(status.text()) }
    }

    func reconcileSelections() {
        let previousTarget = target
        if !displays.contains(where: { $0.id == reference }) {
            reference = saved.flatMap { saved in displays.first(where: { $0.uuid == saved.referenceUUID }) }?.id
                ?? displays.first(where: \.main)?.id ?? 0
        }
        if !displays.contains(where: { $0.id == previousTarget && $0.id != reference }) {
            target = saved.flatMap { saved in
                displays.first(where: { $0.id != reference && $0.uuid == saved.targetUUID })
            }?.id ?? defaultTarget
        }
        syncCurrentAlignment()
    }

    func selectReferenceAtPointer() {
        let screens = NSScreen.screens.compactMap { screen -> (id: UInt32, frame: CGRect)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.frame)
        }
        selectReferenceForOpening(screenAtPointer(NSEvent.mouseLocation, screens: screens))
    }

    func selectReferenceForOpening(_ screenID: UInt32?) {
        guard !busy else { return }
        if let screenID, displays.contains(where: { $0.id == screenID }) {
            reference = screenID
        } else {
            reconcileSelections()
        }
        target = defaultTarget
        syncCurrentAlignment()
    }

    func syncCurrentAlignment() {
        errorMessage = storageError
        guard let main = displays.first(where: { $0.id == reference }),
              let target = displays.first(where: { $0.id == self.target && $0.id != reference }) else {
            showingActualPosition = false
            status = storageError ?? "请选择不同的参考屏幕和移动屏幕。"
            return
        }
        do {
            if let option = try matchingAlignment(target, relativeTo: main,
                    preferred: selection) {
                selection = option
                status = storageError ?? AppMessage("当前排列：%@ · %@", AppMessage(option.direction.localizationKey), AppMessage(option.alignment.localizationKey(for: option.direction)))
            } else {
                showingActualPosition = true
                status = storageError ?? (target.mirrored || main.mirrored
                    ? "当前为镜像模式，不能独立排列。"
                    : "当前为自定义位置；拖动选择对齐后再应用。")
                if target.mirrored || main.mirrored { errorMessage = status }
            }
        } catch { showingActualPosition = true; status = AppMessage("对齐检查失败：%@", AppMessage(error: error)); errorMessage = status }
    }

    func move(_ id: UInt32, relativeTo referenceID: UInt32? = nil, direction: DisplayDirection = .below, alignment: EdgeAlignment = .center) async throws {
        guard !busy else { throw PrototypeError("正在应用，请稍候。") }
        busy = true; defer { busy = false }
        if let storageError { throw PrototypeError(message: storageError) }
        errorMessage = nil
        let current = try read()
        let referenceID = referenceID ?? current.first(where: \.main)?.id
        guard let main = current.first(where: { $0.id == referenceID }), let mainUUID = main.uuid,
              let target = current.first(where: { $0.id == id && $0.id != referenceID }), let targetUUID = target.uuid else {
            throw PrototypeError("请选择不同的活动参考屏和移动屏，两者必须有可识别的 UUID。")
        }
        let relation = Arrangement(targetUUID: targetUUID, referenceUUID: mainUUID, direction: direction, alignment: alignment)
        let desired = try relation.layout(for: current)
        status = AppMessage("正在应用%@ · %@…", AppMessage(direction.localizationKey), AppMessage(alignment.localizationKey(for: direction)))
        try await submit(desired, expected: current)
        try FileManager.default.createDirectory(at: arrangementURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try encoder.encode(relation).write(to: arrangementURL, options: .atomic) }
        catch { throw PrototypeError("屏幕已对齐，但未能保存排列：%@", AppMessage(error: error)) }
        saved = relation
        selection = AlignmentOption(direction: direction, alignment: alignment)
        status = AppMessage("已应用并记住：%@ → %@ %@ · %@", AppMessage(verbatim: target.name), AppMessage(verbatim: main.name), AppMessage(direction.localizationKey), AppMessage(alignment.localizationKey(for: direction)))
        note(status.text())
    }

    func submit(_ desired: [Display], expected: [Display]) async throws {
        try validate(desired)
        guard try read() == expected else { throw PrototypeError("提交前屏幕状态改变，请刷新后重试。") }
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config), "CGBeginDisplayConfiguration")
        var completed = false
        defer {
            if !completed {
                let error = CGCancelDisplayConfiguration(config)
                note(AppMessage("取消事务：CGError %@", AppMessage(verbatim: String(error.rawValue))).text())
            }
        }
        for d in desired {
            note(AppMessage("请求 ID=%@ origin=(%@,%@)", AppMessage(verbatim: String(d.id)), AppMessage(verbatim: String(d.x)), AppMessage(verbatim: String(d.y))).text())
            try check(CGConfigureDisplayOrigin(config, d.id, d.x, d.y), "CGConfigureDisplayOrigin/\(d.id)")
        }
        let result = CGCompleteDisplayConfiguration(config, .forSession)
        completed = true // Complete consumes the transaction, including on failure.
        note("CGCompleteDisplayConfiguration: CGError \(result.rawValue)")
        // Re-read even when Complete reports an error.
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 200_000_000)
            displays = try read()
            if result == .success && displays.sorted(by: { $0.id < $1.id }) == desired.sorted(by: { $0.id < $1.id }) {
                note(L("重新读取确认：实际布局与请求一致。"))
                return
            }
        }
        refresh()
        try check(result, "CGCompleteDisplayConfiguration")
        throw PrototypeError("系统实际布局与请求不一致或屏幕状态改变；请刷新屏幕并重新应用。")
    }
}

@MainActor
func runScreenSelectionSelfChecks() throws {
    let system = Display(id: 1, uuid: "system", name: "MacBook", vendor: 0, model: 0, serial: 0,
                         main: true, mirrored: false, x: 0, y: 0, width: 100, height: 100)
    var external = system
    external.id = 2; external.uuid = "external"; external.main = false; external.x = 100
    var ipad = external
    ipad.id = 3; ipad.uuid = "ipad"; ipad.y = 100
    let manager = DisplayManager()
    manager.saved = nil; manager.storageError = nil
    manager.displays = [system, external, ipad]
    manager.reconcileSelections()
    guard manager.reference == system.id, manager.target == external.id else { throw PrototypeError("默认参考屏或 ID 最小移动屏选择错误。") }
    manager.target = ipad.id
    manager.reference = external.id
    guard manager.target == ipad.id, !manager.hasPendingChange,
          manager.selection.direction == .below else { throw PrototypeError("切换参考屏未同步当前对齐。") }
    manager.target = system.id
    manager.reconcileSelections()
    guard manager.target == system.id, !manager.showingActualPosition,
          manager.selection.direction == .left else { throw PrototypeError("系统主屏作为移动目标被清除或未同步。") }
    manager.selection = AlignmentOption(direction: .above, alignment: .center)
    guard manager.hasPendingChange else { throw PrototypeError("系统主屏的待应用修改未识别。") }
    manager.target = ipad.id
    manager.selection = AlignmentOption(direction: .right, alignment: .center)
    guard manager.hasPendingChange else { throw PrototypeError("非系统主屏的参考位置未识别待应用修改。") }
    manager.reference = ipad.id
    guard manager.target == system.id, !manager.hasPendingChange else { throw PrototypeError("参考与移动屏重合后未选择最小可用 ID。") }
    manager.saved = Arrangement(targetUUID: "ipad", referenceUUID: "external", alignment: .center)
    manager.reference = external.id
    manager.target = ipad.id
    external.id = 22; ipad.id = 33
    manager.displays = [ipad, system, external]
    manager.reconcileSelections()
    guard manager.reference == external.id, manager.target == ipad.id else {
        throw PrototypeError("重连后未按 UUID 恢复参考屏和移动屏。")
    }
    manager.saved = Arrangement(targetUUID: "system", referenceUUID: "external", alignment: .center)
    manager.target = 0
    manager.reconcileSelections()
    guard manager.target == system.id else { throw PrototypeError("系统主屏作为移动目标的保存关系未恢复。") }
    manager.saved = Arrangement(targetUUID: "ipad", referenceUUID: "external", alignment: .center)
    manager.target = ipad.id
    manager.displays = [system, ipad]
    manager.reconcileSelections()
    guard manager.reference == system.id, manager.target == ipad.id else {
        throw PrototypeError("参考屏断开后未回到系统主屏。")
    }
    manager.displays = [system, external]
    manager.reconcileSelections()
    guard manager.target == external.id else { throw PrototypeError("移动屏断开后未选择剩余可用屏幕。") }
    manager.displays = [system]
    manager.reconcileSelections()
    guard manager.target == 0 else { throw PrototypeError("移动屏断开后仍保留失效选择。") }
    let screenFrames: [(id: UInt32, frame: CGRect)] = [
        (system.id, CGRect(x: 0, y: 0, width: 100, height: 100)),
        (external.id, CGRect(x: 100, y: -50, width: 200, height: 150)),
        (ipad.id, CGRect(x: -120, y: 100, width: 120, height: 80))
    ]
    for (point, expected) in [(CGPoint(x: 50, y: 50), system.id),
                              (CGPoint(x: 150, y: -25), external.id),
                              (CGPoint(x: -60, y: 140), ipad.id),
                              (CGPoint(x: 100, y: 0), external.id)] {
        guard screenAtPointer(point, screens: screenFrames) == expected else {
            throw PrototypeError("Pointer display detection failed for negative coordinates or shared edges.")
        }
    }
    guard screenAtPointer(CGPoint(x: 400, y: 400), screens: screenFrames) == nil else {
        throw PrototypeError("A pointer outside all displays matched a display.")
    }
    manager.saved = nil
    manager.displays = [ipad, external, system]
    manager.target = ipad.id
    manager.selectReferenceForOpening(external.id)
    guard manager.reference == external.id, manager.target == system.id else {
        throw PrototypeError("Opening did not select the pointer reference and lowest target ID.")
    }
    manager.target = ipad.id
    manager.reference = system.id
    manager.reconcileSelections()
    guard manager.reference == system.id, manager.target == ipad.id else { throw PrototypeError("Refresh overrode the manual reference or target.") }
    manager.selectReferenceForOpening(ipad.id)
    guard manager.reference == ipad.id, manager.target == system.id else {
        throw PrototypeError("Reopening did not update the reference or exclude the same target.")
    }
    manager.selectReferenceForOpening(999)
    guard manager.reference == ipad.id else { throw PrototypeError("An unavailable pointer display replaced the reference.") }
    manager.busy = true
    manager.selectReferenceForOpening(system.id)
    guard manager.reference == ipad.id else { throw PrototypeError("Opening changed the reference during submission.") }
    print("PASS: automatic target uses lowest non-reference ID, preserves manual choice on refresh and handles a single screen")
    print("PASS: reference selection, current alignment, pending changes, same-screen exclusion and UUID reconnect")
    print("PASS: pointer reference on opening, manual override, reopening, negative screen frames and busy protection")
}
