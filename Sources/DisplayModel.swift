import Foundation

struct Display: Codable, Equatable, Identifiable {
    var id: UInt32
    var uuid: String?
    var name: String
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    var main: Bool
    var mirrored: Bool
    var x: Int32
    var y: Int32
    var width: Int32
    var height: Int32
}

struct DisplayReport: Codable {
    var schemaVersion = 1
    var capturedAt = Date()
    var displays: [Display]
}

struct PrototypeError: LocalizedError {
    let message: AppMessage
    init(_ key: String, _ arguments: AppMessage...) { message = AppMessage(key, arguments: arguments) }
    init(message: AppMessage) { self.message = message }
    var errorDescription: String? { message.text() }
}

enum DisplayDirection: String, Codable, CaseIterable {
    case above, below, left, right
    var horizontal: Bool { self == .left || self == .right }
    var title: String { L(localizationKey) }
    var localizationKey: String {
        switch self {
        case .above: return "Above"
        case .below: return "Below"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

enum EdgeAlignment: String, Codable, CaseIterable {
    case start, center, end
    func title(for direction: DisplayDirection) -> String {
        L(localizationKey(for: direction))
    }
    func localizationKey(for direction: DisplayDirection) -> String {
        switch self {
        case .start: return direction.horizontal ? "Align Top" : "Align Left"
        case .center: return "Center"
        case .end: return direction.horizontal ? "Align Bottom" : "Align Right"
        }
    }
}

struct AlignmentOption: Equatable, Identifiable {
    let direction: DisplayDirection
    let alignment: EdgeAlignment
    var id: String { "\(direction.rawValue)-\(alignment.rawValue)" }
    var title: String { "\(direction.title) · \(alignment.title(for: direction))" }
    static let all = DisplayDirection.allCases.flatMap { direction in
        EdgeAlignment.allCases.map { AlignmentOption(direction: direction, alignment: $0) }
    }

    func changesPosition(of target: Display, relativeTo reference: Display) throws -> Bool {
        let desired = try alignedDisplay(target, relativeTo: reference, direction: direction, alignment: alignment)
        return desired.x != target.x || desired.y != target.y
    }
}

func nearestAlignment(_ target: Display, relativeTo reference: Display, x: Double, y: Double, preferred: AlignmentOption? = nil) throws -> AlignmentOption {
    guard x.isFinite, y.isFinite else { throw PrototypeError("Invalid drag position.") }
    var nearest = AlignmentOption.all[0]
    var distance = Double.infinity
    for option in AlignmentOption.all {
        let position = try alignedDisplay(target, relativeTo: reference, direction: option.direction, alignment: option.alignment)
        let candidateDistance = hypot(Double(position.x) - x, Double(position.y) - y)
        let preservesAlignment = option.alignment == preferred?.alignment && nearest.alignment != preferred?.alignment
        if candidateDistance < distance || (candidateDistance == distance && preservesAlignment) {
            nearest = option; distance = candidateDistance
        }
    }
    return nearest
}

func matchingAlignment(_ target: Display, relativeTo reference: Display, preferred: AlignmentOption? = nil) throws -> AlignmentOption? {
    guard !target.mirrored, !reference.mirrored else { return nil }
    let nearest = try nearestAlignment(target, relativeTo: reference, x: Double(target.x), y: Double(target.y), preferred: preferred)
    let expected = try alignedDisplay(target, relativeTo: reference, direction: nearest.direction, alignment: nearest.alignment)
    return expected.x == target.x && expected.y == target.y ? nearest : nil
}

struct Arrangement: Codable, Equatable {
    let schemaVersion = 2
    var targetUUID: String
    var referenceUUID: String
    var direction: DisplayDirection = .below
    var alignment: EdgeAlignment

    func layout(for current: [Display]) throws -> [Display] {
        guard targetUUID != referenceUUID,
              current.filter({ $0.uuid == targetUUID }).count == 1,
              current.filter({ $0.uuid == referenceUUID }).count == 1,
              let reference = current.first(where: { $0.uuid == referenceUUID }),
              let target = current.first(where: { $0.uuid == targetUUID }) else {
            throw PrototypeError("The reference or target display is disconnected or ambiguous. Select the displays again and apply.")
        }
        var result = current
        result[result.firstIndex(where: { $0.id == target.id })!] = try alignedDisplay(target, relativeTo: reference, direction: direction, alignment: alignment)
        guard let primary = result.first(where: \.main) else { throw PrototypeError("No primary display was found.") }
        // Quartz keeps the primary at (0, 0); rebasing preserves every pairwise offset.
        result = try result.map { display in
            guard let x = Int32(exactly: Int64(display.x) - Int64(primary.x)),
                  let y = Int32(exactly: Int64(display.y) - Int64(primary.y)) else {
                throw PrototypeError("Rebased display coordinates exceed the Int32 range.")
            }
            var shifted = display
            shifted.x = x; shifted.y = y
            return shifted
        }
        try validate(result)
        return result
    }
}

extension Arrangement {
    enum CodingKeys: String, CodingKey {
        case schemaVersion, targetUUID, referenceUUID, direction, alignment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 || version == 2 else { throw PrototypeError("Unsupported layout version.") }
        targetUUID = try values.decode(String.self, forKey: .targetUUID)
        referenceUUID = try values.decode(String.self, forKey: .referenceUUID)
        if version == 1 {
            direction = .below
            switch try values.decode(String.self, forKey: .alignment) {
            case "left": alignment = .start
            case "center": alignment = .center
            case "right": alignment = .end
            default: throw PrototypeError("The legacy layout has an invalid alignment.")
            }
        } else {
            direction = try values.decode(DisplayDirection.self, forKey: .direction)
            alignment = try values.decode(EdgeAlignment.self, forKey: .alignment)
        }
    }
}

func alignedDisplay(_ target: Display, relativeTo reference: Display, direction: DisplayDirection = .below, alignment: EdgeAlignment = .center) throws -> Display {
    var result = target
    let difference = direction.horizontal
        ? Double(reference.height) - Double(target.height)
        : Double(reference.width) - Double(target.width)
    let offset: Double
    switch alignment {
    case .start: offset = 0
    case .center: offset = (difference / 2).rounded(.toNearestOrAwayFromZero)
    case .end: offset = difference
    }
    let x: Double, y: Double
    switch direction {
    case .above:
        x = Double(reference.x) + offset; y = Double(reference.y) - Double(target.height)
    case .below:
        x = Double(reference.x) + offset; y = Double(reference.y) + Double(reference.height)
    case .left:
        x = Double(reference.x) - Double(target.width); y = Double(reference.y) + offset
    case .right:
        x = Double(reference.x) + Double(reference.width); y = Double(reference.y) + offset
    }
    guard let originX = Int32(exactly: x.rounded(.toNearestOrAwayFromZero)),
          let originY = Int32(exactly: y.rounded(.toNearestOrAwayFromZero)) else {
        throw PrototypeError("Calculated coordinates exceed the Int32 range.")
    }
    result.x = originX; result.y = originY
    return result
}

func validate(_ displays: [Display]) throws {
    guard !displays.isEmpty, Set(displays.map(\.id)).count == displays.count,
          displays.allSatisfy({ $0.width > 0 && $0.height > 0 }) else {
        throw PrototypeError("The display list is empty, IDs are duplicated, or sizes are invalid.")
    }
    guard !displays.contains(where: \.mirrored) else { throw PrototypeError("Mirrored displays cannot be arranged independently.") }
    let mains = displays.filter(\.main)
    guard mains.count == 1, mains[0].x == 0, mains[0].y == 0 else {
        throw PrototypeError("There must be exactly one primary display at (0, 0).")
    }
    var edges = Array(repeating: [Int](), count: displays.count)
    for i in displays.indices {
        for j in displays.indices where j > i {
            let a = displays[i], b = displays[j]
            let horizontal = min(Int64(a.x) + Int64(a.width), Int64(b.x) + Int64(b.width)) - max(Int64(a.x), Int64(b.x))
            let vertical = min(Int64(a.y) + Int64(a.height), Int64(b.y) + Int64(b.height)) - max(Int64(a.y), Int64(b.y))
            if horizontal > 0 && vertical > 0 { throw PrototypeError("Displays %@ and %@ overlap.", AppMessage(verbatim: String(a.id)), AppMessage(verbatim: String(b.id))) }
            if (horizontal == 0 && vertical >= 1) || (vertical == 0 && horizontal >= 1) {
                edges[i].append(j); edges[j].append(i)
            }
        }
    }
    var visited: Set<Int> = [0], pending = [0]
    while let i = pending.popLast() {
        for j in edges[i] where visited.insert(j).inserted { pending.append(j) }
    }
    guard visited.count == displays.count else { throw PrototypeError("The layout is disconnected. Displays must share an edge of at least one desktop coordinate unit; corner contact is not sufficient.") }
}

func runSelfChecks() throws {
    let a = Display(id: 1, uuid: "A", name: "A", vendor: 0, model: 0, serial: 0, main: true, mirrored: false, x: 0, y: 0, width: 101, height: 101)
    var b = a; b.id = 2; b.uuid = "B"; b.main = false; b.width = 80; b.height = 50
    let aligned = try alignedDisplay(b, relativeTo: a)
    guard aligned.x == 11, aligned.y == 101 else { throw PrototypeError("居中取整检查失败。") }
    try validate([a, aligned])
    let left = try alignedDisplay(b, relativeTo: a, alignment: .start)
    guard left.x == 0, left.y == 101 else { throw PrototypeError("下侧左对齐检查失败。") }
    try validate([a, left])
    var wider = b; wider.width = 104
    let negativeCenter = try alignedDisplay(wider, relativeTo: a)
    guard negativeCenter.x == -2, negativeCenter.y == 101 else { throw PrototypeError("负半整数居中检查失败。") }
    try validate([a, negativeCenter])
    b.x = -80; b.y = -10
    try validate([a, b])
    func rejects(_ operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw PrototypeError("预期拒绝的输入被接受。")
    }
    var invalid = b; invalid.x = 100; invalid.y = 0
    try rejects { try validate([a, invalid]) }
    invalid.x = 101; invalid.y = 101
    try rejects { try validate([a, invalid]) }
    invalid.x = 200; invalid.y = 0
    try rejects { try validate([a, invalid]) }
    invalid = b; invalid.mirrored = true
    try rejects { try validate([a, invalid]) }
    let relation = Arrangement(targetUUID: "B", referenceUUID: "A", alignment: .end)
    var resized = b; resized.id = 9; resized.width = 120; resized.height = 75
    let matched = try relation.layout(for: [a, resized])
    guard matched[1].id == 9, matched[1].x == -19, matched[1].y == 101 else { throw PrototypeError("尺寸变化后的关系计算失败。") }
    try rejects { _ = try relation.layout(for: [a]) }
    var duplicate = resized; duplicate.id = 10
    try rejects { _ = try relation.layout(for: [a, resized, duplicate]) }
    var changedMain = a; changedMain.main = false
    try rejects { _ = try relation.layout(for: [changedMain, resized]) }
    let data = try JSONEncoder().encode(relation)
    guard try JSONDecoder().decode(Arrangement.self, from: data) == relation else { throw PrototypeError("排列保存检查失败。") }
    try rejects { _ = try JSONDecoder().decode(Arrangement.self, from: Data("broken".utf8)) }
    for alignment in EdgeAlignment.allCases {
        let actual = try Arrangement(targetUUID: "B", referenceUUID: "A", alignment: alignment).layout(for: [a, resized])[1]
        let expectedX: Int32 = alignment == .start ? 0 : (alignment == .center ? -10 : -19)
        guard actual.x == expectedX, actual.y == 101 else { throw PrototypeError("重新计算对齐失败。") }
    }
    let expected: [DisplayDirection: [(Int32, Int32)]] = [
        .above: [(0, -50), (11, -50), (21, -50)],
        .below: [(0, 101), (11, 101), (21, 101)],
        .left: [(-80, 0), (-80, 26), (-80, 51)],
        .right: [(101, 0), (101, 26), (101, 51)]
    ]
    for direction in DisplayDirection.allCases {
        for (index, alignment) in EdgeAlignment.allCases.enumerated() {
            let actual = try alignedDisplay(b, relativeTo: a, direction: direction, alignment: alignment)
            let point = expected[direction]![index]
            guard actual.x == point.0, actual.y == point.1 else { throw PrototypeError("12 种对齐计算失败。") }
            try validate([a, actual])
            let snapped = try nearestAlignment(b, relativeTo: a, x: Double(actual.x) + 1, y: Double(actual.y) - 1)
            guard snapped == AlignmentOption(direction: direction, alignment: alignment) else {
                throw PrototypeError("拖动吸附检查失败。")
            }
            guard try matchingAlignment(actual, relativeTo: a) == AlignmentOption(direction: direction, alignment: alignment) else {
                throw PrototypeError("当前对齐识别失败。")
            }
            let option = AlignmentOption(direction: direction, alignment: alignment)
            guard try !option.changesPosition(of: actual, relativeTo: a) else {
                throw PrototypeError("未修改布局错误地显示待应用。")
            }
            var offset = actual; offset.x += 1
            guard try option.changesPosition(of: offset, relativeTo: a) else {
                throw PrototypeError("新位置未识别为待应用。")
            }
        }
    }
    var custom = b; custom.x = 101; custom.y = 10
    guard try matchingAlignment(custom, relativeTo: a) == nil else { throw PrototypeError("自定义偏移被误判为固定对齐。") }
    var mirrored = custom; mirrored.mirrored = true
    guard try matchingAlignment(mirrored, relativeTo: a) == nil else { throw PrototypeError("镜像布局被误判为固定对齐。") }
    try rejects { _ = try nearestAlignment(b, relativeTo: a, x: .infinity, y: 0) }
    var sameSize = b; sameSize.width = a.width; sameSize.height = a.height
    let preferred = AlignmentOption(direction: .below, alignment: .center)
    let tied = try nearestAlignment(sameSize, relativeTo: a, x: -101, y: 0, preferred: preferred)
    guard tied == AlignmentOption(direction: .left, alignment: .center) else {
        throw PrototypeError("同尺寸候选重合时未保留对齐方式。")
    }
    let identicalAligned = try alignedDisplay(sameSize, relativeTo: a, direction: .left, alignment: .center)
    guard try matchingAlignment(identicalAligned, relativeTo: a, preferred: preferred) == tied else {
        throw PrototypeError("同尺寸屏幕的当前对齐识别未保留居中关系。")
    }
    guard try !AlignmentOption(direction: .left, alignment: .end).changesPosition(of: identicalAligned, relativeTo: a) else {
        throw PrototypeError("同尺寸的等价位置错误地显示待应用。")
    }
    var taller = b; taller.height = 104
    let negativeY = try alignedDisplay(taller, relativeTo: a, direction: .left)
    guard negativeY.y == -2 else { throw PrototypeError("负半整数纵向居中检查失败。") }
    var shifted = a; shifted.x = -300; shifted.y = -200
    let shiftedTarget = try alignedDisplay(b, relativeTo: shifted, direction: .above, alignment: .end)
    guard shiftedTarget.x == -279, shiftedTarget.y == -250 else { throw PrototypeError("负参考坐标检查失败。") }
    let legacy = Data(#"{"schemaVersion":1,"targetUUID":"B","referenceUUID":"A","alignment":"left"}"#.utf8)
    let migrated = try JSONDecoder().decode(Arrangement.self, from: legacy)
    guard migrated.schemaVersion == 2, migrated.direction == .below, migrated.alignment == .start else {
        throw PrototypeError("旧排列兼容检查失败。")
    }
    try rejects { _ = try JSONDecoder().decode(Arrangement.self, from: Data(#"{"schemaVersion":3}"#.utf8)) }
    let mainAsTarget = Arrangement(targetUUID: "A", referenceUUID: "A", alignment: .center)
    try rejects { _ = try mainAsTarget.layout(for: [a, b]) }
    var third = a; third.id = 3; third.uuid = "C"; third.main = false; third.x = 101
    let externalReference = Arrangement(targetUUID: "B", referenceUUID: "C", direction: .below, alignment: .center)
    let threeScreenLayout = try externalReference.layout(for: [a, third, b])
    guard threeScreenLayout[0] == a, threeScreenLayout[1] == third,
          threeScreenLayout[2].x == 112, threeScreenLayout[2].y == 101,
          try matchingAlignment(threeScreenLayout[2], relativeTo: third) == AlignmentOption(direction: .below, alignment: .center) else {
        throw PrototypeError("三屏参考屏对齐改变了无关屏幕或位置错误。")
    }
    let restoredReference = try JSONDecoder().decode(Arrangement.self, from: JSONEncoder().encode(externalReference))
    guard restoredReference == externalReference else { throw PrototypeError("非系统主屏参考关系保存失败。") }
    var reconnectedReference = third; reconnectedReference.id = 30
    let reconnectedLayout = try restoredReference.layout(for: [resized, a, reconnectedReference])
    guard reconnectedLayout[0].id == resized.id, reconnectedLayout[0].y == 101,
          reconnectedLayout[1] == a, reconnectedLayout[2] == reconnectedReference else {
        throw PrototypeError("三屏重连后的参考关系匹配失败。")
    }
    try rejects { _ = try externalReference.layout(for: [a, b]) }
    for (target, reference) in [(a, aligned), (aligned, a)] {
        for option in AlignmentOption.all {
            let relation = Arrangement(targetUUID: target.uuid!, referenceUUID: reference.uuid!,
                                       direction: option.direction, alignment: option.alignment)
            let layout = try relation.layout(for: [a, aligned])
            let moved = layout.first { $0.id == target.id }!
            let anchor = layout.first { $0.id == reference.id }!
            let expected = try alignedDisplay(moved, relativeTo: anchor, direction: option.direction, alignment: option.alignment)
            guard moved == expected, layout.first(where: \.main)?.id == a.id,
                  layout.first(where: \.main)?.x == 0, layout.first(where: \.main)?.y == 0 else {
                throw PrototypeError("任意屏幕作为移动目标的对齐或主屏基准错误。")
            }
            guard try relation.layout(for: layout) == layout else { throw PrototypeError("主屏对齐后的重复应用不是幂等操作。") }
        }
    }
    var neighbor = b; neighbor.x = 202; neighbor.y = 0
    let movingPrimary = Arrangement(targetUUID: "A", referenceUUID: "C", direction: .below, alignment: .center)
    let rebased = try movingPrimary.layout(for: [a, third, neighbor])
    guard rebased[0].main, rebased[0].x == 0, rebased[0].y == 0,
          rebased[1].x == 0, rebased[1].y == -101,
          rebased[2].x - rebased[1].x == neighbor.x - third.x,
          rebased[2].y - rebased[1].y == neighbor.y - third.y else {
        throw PrototypeError("三屏主屏移动改变了其他屏幕间的相对位置。")
    }
    let restoredPrimary = try JSONDecoder().decode(Arrangement.self, from: JSONEncoder().encode(movingPrimary))
    guard try restoredPrimary.layout(for: [a, third, neighbor]) == rebased else {
        throw PrototypeError("主屏作为移动目标的保存关系未恢复。")
    }
    try rejects { _ = try Arrangement(targetUUID: "A", referenceUUID: "C", direction: .right, alignment: .start).layout(for: [a, third, neighbor]) }
    var distant = third; distant.x = Int32.max - 101
    var farLeft = neighbor; farLeft.x = Int32.min
    try rejects { _ = try movingPrimary.layout(for: [a, distant, farLeft]) }
    try rejects { _ = try Arrangement(targetUUID: "C", referenceUUID: "C", alignment: .center).layout(for: [a, third, b]) }
    let collidingReference = Arrangement(targetUUID: "B", referenceUUID: "C", direction: .left, alignment: .start)
    try rejects { _ = try collidingReference.layout(for: [a, third, b]) }
    let colliding = Arrangement(targetUUID: "B", referenceUUID: "A", direction: .right, alignment: .start)
    try rejects { _ = try colliding.layout(for: [a, b, third]) }
    print("PASS: 12 alignments, current-layout matching, pending changes and drag snapping, legacy migration, rounding, negative coordinates, overlap, connectivity, mirror rejection, UUID reconnect, changed dimensions, missing/ambiguous identities, changed main and arrangement JSON")
    print("PASS: three-screen alignment against a non-primary reference, unchanged other screens and saved reference UUID")
    print("PASS: primary as target in all 12 alignments, rebasing, unchanged non-target offsets, idempotency and overflow rejection")
}
