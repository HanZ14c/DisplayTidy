import SwiftUI

// Disambiguate the property wrapper from the newer SDK macro of the same name.
private typealias ViewState<Value> = SwiftUI.State<Value>

private let alignmentCanvasSize = CGSize(width: 244, height: 160)

func alignmentPreviewScale(main: Display, target: Display, showsActualPosition: Bool) -> Double {
    var halfWidth = Double(max(main.width, 1)) / 2 + Double(max(target.width, 1))
    var halfHeight = Double(max(main.height, 1)) / 2 + Double(max(target.height, 1))
    if showsActualPosition {
        let dx = Double(target.x) - Double(main.x) - Double(main.width) / 2
        let dy = Double(target.y) - Double(main.y) - Double(main.height) / 2
        halfWidth = max(halfWidth, abs(dx), abs(dx + Double(target.width)))
        halfHeight = max(halfHeight, abs(dy), abs(dy + Double(target.height)))
    }
    return min(alignmentCanvasSize.width * 0.4 / halfWidth,
               alignmentCanvasSize.height * 0.4 / halfHeight)
}

struct AlignmentControl: View {
    @ObservedObject var manager: DisplayManager
    var showsPositionMenu = false
    @GestureState private var isDragging = false
    @ViewState private var previewCenter: CGPoint? = nil
    @ViewState private var dragStart: CGPoint? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var main: Display? { manager.displays.first { $0.id == manager.reference } }
    private var target: Display? { manager.displays.first { $0.id == manager.target && $0.id != manager.reference } }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.06))
                if let main, let target {
                    screenPreview(main: main, target: target)
                } else {
                    Image(systemName: "display").font(.largeTitle).foregroundColor(.secondary)
                }
            }
            .frame(width: alignmentCanvasSize.width, height: alignmentCanvasSize.height)
            .coordinateSpace(name: "alignment")
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if !isDragging && (manager.hasPendingChange || manager.busy) {
                    Button {
                        Task {
                            do { try await manager.move(manager.target, relativeTo: manager.reference, direction: manager.selection.direction, alignment: manager.selection.alignment) }
                            catch { manager.report(error) }
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color.blue)
                            if manager.busy {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                            }
                        }.frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(L("应用排列"))
                    .accessibilityLabel(L("应用排列"))
                    .disabled(manager.busy)
                    .padding(8)
                }
            }
            if showsPositionMenu {
                Menu {
                    ForEach(AlignmentOption.all) { option in
                        Button(option.title) {
                            manager.selection = option
                        }
                    }
                } label: {
                    Text(manager.showingActualPosition ? L("当前位置") : manager.selection.title)
                        .font(.caption.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(manager.busy || target == nil)
            }
        }
        .onChange(of: manager.target) { _ in
            previewCenter = nil
            dragStart = nil
        }
        .onChange(of: manager.reference) { _ in
            previewCenter = nil
            dragStart = nil
        }
        .onChange(of: manager.displays) { _ in
            guard !isDragging else { return }
            previewCenter = nil
            dragStart = nil
        }
    }

    private func screenPreview(main: Display, target: Display) -> some View {
        let scale = alignmentPreviewScale(main: main, target: target, showsActualPosition: manager.showingActualPosition)
        let mainWidth = Double(main.width) * scale
        let mainHeight = Double(main.height) * scale
        let targetWidth = Double(target.width) * scale
        let targetHeight = Double(target.height) * scale
        let selected = manager.selection
        let proposed = manager.showingActualPosition ? target
            : ((try? alignedDisplay(target, relativeTo: main, direction: selected.direction, alignment: selected.alignment)) ?? target)
        let anchor = CGPoint(x: Double(main.x) + (Double(main.width) - Double(target.width)) / 2,
                             y: Double(main.y) + (Double(main.height) - Double(target.height)) / 2)
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                          tx: alignmentCanvasSize.width / 2 - anchor.x * scale,
                                          ty: alignmentCanvasSize.height / 2 - anchor.y * scale)
        func previewPoint(_ origin: CGPoint) -> CGPoint { origin.applying(transform) }
        func desktopPoint(_ point: CGPoint) -> CGPoint { point.applying(transform.inverted()) }
        let selectedCenter = previewPoint(CGPoint(x: Double(proposed.x), y: Double(proposed.y)))
        let center = previewCenter ?? selectedCenter
        let origin = desktopPoint(center)
        let hovered = try? nearestAlignment(target, relativeTo: main, x: origin.x, y: origin.y, preferred: selected)
        let placements = AlignmentOption.all.compactMap { option -> (AlignmentOption, CGPoint)? in
            guard let display = try? alignedDisplay(target, relativeTo: main, direction: option.direction, alignment: option.alignment) else { return nil }
            return (option, previewPoint(CGPoint(x: Double(display.x), y: Double(display.y))))
        }
        return ZStack {
            if isDragging {
                ForEach(placements.filter { $0.0 != hovered } + placements.filter { $0.0 == hovered }, id: \.0.id) { option, center in
                    let active = hovered == option
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.025))
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(active ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.22),
                                          style: StrokeStyle(lineWidth: active ? 1.5 : 1, dash: [3, 3])))
                        .frame(width: targetWidth, height: targetHeight)
                        .position(center)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            screen(width: mainWidth, height: mainHeight, highlighted: false)
                .position(x: alignmentCanvasSize.width / 2, y: alignmentCanvasSize.height / 2)
                .allowsHitTesting(false)
            screen(width: targetWidth, height: targetHeight, highlighted: !isDragging)
                .padding(6)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("alignment"))
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        if dragStart == nil { dragStart = previewCenter ?? selectedCenter }
                        let start = dragStart ?? selectedCenter
                        withAnimation(nil) {
                            previewCenter = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                        }
                    }
                    .onEnded { value in
                        let start = dragStart ?? selectedCenter
                        let released = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                        dragStart = nil
                        let origin = desktopPoint(released)
                        guard !manager.busy,
                              let option = try? nearestAlignment(target, relativeTo: main, x: origin.x, y: origin.y, preferred: selected),
                              let destination = placements.first(where: { $0.0 == option })?.1 else {
                            withAnimation(snapAnimation) { previewCenter = selectedCenter }
                            return
                        }
                        // Keep the release point independent of GestureState's automatic reset.
                        withAnimation(snapAnimation) {
                            manager.selection = option
                            previewCenter = destination
                        }
                    })
                .accessibilityLabel(L("移动屏幕排列"))
                .accessibilityValue(manager.showingActualPosition ? L("当前位置，未匹配固定对齐") : selected.title)
                .accessibilityHint(showsPositionMenu ? L("拖动选择位置，也可通过下方菜单选择对齐方式。") : L("拖动选择位置，使用应用排列按钮确认修改。"))
                .accessibilityAdjustableAction { adjustment in
                    guard !manager.busy, let index = AlignmentOption.all.firstIndex(of: selected) else { return }
                    let step = adjustment == .increment ? 1 : -1
                    let option = AlignmentOption.all[(index + step + AlignmentOption.all.count) % AlignmentOption.all.count]
                    manager.selection = option
                }
                .allowsHitTesting(!manager.busy)
                .position(center)
        }
        .onChange(of: selectedCenter) { newCenter in
            guard !isDragging, dragStart == nil else { return }
            withAnimation(snapAnimation) { previewCenter = newCenter }
        }
        .onChange(of: isDragging) { dragging in
            // A cancelled gesture goes back to the pending selection.
            if !dragging, dragStart != nil {
                dragStart = nil
                withAnimation(snapAnimation) { previewCenter = selectedCenter }
            }
        }
    }

    private var snapAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)
    }

    private func screen(width: Double, height: Double, highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(highlighted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(highlighted ? Color.accentColor : Color.secondary, lineWidth: 1))
            .frame(width: width, height: height)
    }
}

func runPreviewSelfChecks() throws {
    let main = Display(id: 1, uuid: "main", name: "", vendor: 0, model: 0, serial: 0,
                       main: true, mirrored: false, x: -2560, y: -1440, width: 2560, height: 1440)
    for (width, height) in [(1920, 1080), (1024, 1366), (7680, 2160), (600, 2400)] {
        var target = main
        target.id = 2; target.main = false
        target.width = Int32(width); target.height = Int32(height)
        for actual in [false, true] {
            target.x = actual ? 12000 : 0
            target.y = actual ? -8000 : 0
            let scale = alignmentPreviewScale(main: main, target: target, showsActualPosition: actual)
            let candidates = try AlignmentOption.all.map {
                try alignedDisplay(target, relativeTo: main, direction: $0.direction, alignment: $0.alignment)
            }
            let screens = [main] + candidates + (actual ? [target] : [])
            let center = CGPoint(x: Double(main.x) + Double(main.width) / 2,
                                 y: Double(main.y) + Double(main.height) / 2)
            let extentX = screens.map { max(abs(Double($0.x) - center.x), abs(Double($0.x) + Double($0.width) - center.x)) }.max()!
            let extentY = screens.map { max(abs(Double($0.y) - center.y), abs(Double($0.y) + Double($0.height) - center.y)) }.max()!
            let fill = max(extentX * 2 * scale / alignmentCanvasSize.width,
                           extentY * 2 * scale / alignmentCanvasSize.height)
            guard abs(fill - 0.8) < 0.000001 else { throw PrototypeError("拖拽预览未占满操作区的 80%。") }
        }
    }
    print("PASS: preview fills 80%, including all candidates, portrait, ultrawide and distant layouts")
}
