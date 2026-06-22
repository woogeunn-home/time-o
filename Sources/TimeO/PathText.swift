import AppKit
import QuartzCore
import SwiftUI

// MARK: - Controller

/// Full-screen overlay that keeps the first "Time's Up" capsule anchored at the
/// chosen timer position, then adds another label to the right every second
/// until the text trail wraps around the screen.
final class TravelingTimeOutController {
    private var window: NSPanel?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var startTime: CFTimeInterval = 0
    private weak var activeModel: TimerModel?
    private var activeScreen: NSScreen?

    func play(on screen: NSScreen, model: TimerModel) {
        guard window == nil else { return }

        let frame = screen.frame
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let view = NSHostingView(rootView: TravelingTimeOutView(
            model: model,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        ))
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = view
        panel.orderFrontRegardless()
        window = panel
        activeModel = model
        activeScreen = screen
        startTime = CACurrentMediaTime()
        startClickMonitoring()
    }

    func stop() {
        stopClickMonitoring()
        window?.close()
        window = nil
        activeModel = nil
        activeScreen = nil
    }

    private func startClickMonitoring() {
        stopClickMonitoring()

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, self.shouldDismiss() else {
                return event
            }
            self.activeModel?.stop()
            return nil
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, self.shouldDismiss() else { return }
            DispatchQueue.main.async {
                self.activeModel?.stop()
            }
        }
    }

    private func stopClickMonitoring() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func shouldDismiss() -> Bool {
        guard let activeScreen else { return false }

        let screenPoint = NSEvent.mouseLocation
        guard activeScreen.frame.contains(screenPoint) else { return false }

        let point = CGPoint(
            x: screenPoint.x - activeScreen.frame.minX,
            y: activeScreen.frame.maxY - screenPoint.y
        )
        let elapsed = CGFloat(CACurrentMediaTime() - startTime)
        return TravelingTimeOutGeometry.contains(
            point,
            in: TravelingTimeOutGeometry.layoutArea(
                screenFrame: activeScreen.frame,
                visibleFrame: activeScreen.visibleFrame
            ),
            position: activeModel?.overlayPosition ?? .topCenter,
            itemCount: TravelingTimeOutGeometry.itemCount(after: elapsed)
        )
    }
}

private enum TravelingTimeOutGeometry {
    static let inset: CGFloat = 34
    static let cornerRadius: CGFloat = 80
    static let bandWidth: CGFloat = 60
    static let fontSize: CGFloat = 30
    static let message = "Time's Up"
    static let repeatInterval: TimeInterval = 0.2

    static func itemCount(after elapsed: CGFloat) -> Int {
        max(1, Int(floor(TimeInterval(elapsed) / repeatInterval)) + 1)
    }

    static func contains(_ point: CGPoint, in area: CGRect, position: OverlayPosition, itemCount: Int) -> Bool {
        let path = perimeterPath(in: area)
        let start = startDistance(for: position, on: path)
        let length = filledLength(for: itemCount, on: path)
        let steps = max(2, Int(length / 6))
        let hitRadius = bandWidth / 2

        for index in 0...steps {
            let s = start + length * CGFloat(index) / CGFloat(steps)
            let pathPoint = path.locate(s).0
            if hypot(pathPoint.x - point.x, pathPoint.y - point.y) <= hitRadius {
                return true
            }
        }
        return false
    }

    static func layoutArea(screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - visibleFrame.maxY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    static func perimeterPath(in area: CGRect) -> RoundedRectPath {
        let rect = CGRect(
            x: area.minX + inset,
            y: area.minY + inset,
            width: area.width - inset * 2,
            height: area.height - inset * 2
        )
        return RoundedRectPath(rect: rect, radius: min(cornerRadius, min(rect.width, rect.height) / 2))
    }

    static func startDistance(for position: OverlayPosition, on path: RoundedRectPath) -> CGFloat {
        let bottomLineStart = path.lineH + path.arc + path.lineV + path.arc

        switch position {
        case .topLeading:
            return 0
        case .topCenter:
            return path.lineH / 2
        case .topTrailing:
            return path.lineH
        case .middleTrailing:
            return path.lineH + path.arc + path.lineV / 2
        case .bottomTrailing:
            return bottomLineStart
        case .bottomCenter:
            return bottomLineStart + path.lineH / 2
        case .bottomLeading:
            return bottomLineStart + path.lineH
        case .middleLeading:
            return bottomLineStart + path.lineH + path.arc + path.lineV / 2
        }
    }

    static func filledLength(for itemCount: Int, on path: RoundedRectPath) -> CGFloat {
        let layout = contentLayout()
        let cappedItemCount = min(itemCount, maxItemCount(on: path, layout: layout))
        let textTrailLength = layout.firstTotal + CGFloat(max(0, cappedItemCount - 1)) * layout.repeatedTotal
        let length = textTrailLength + layout.terminalEndExtension
        return length
    }

    static func maxItemCount(on path: RoundedRectPath, layout: ContentLayout = contentLayout()) -> Int {
        let remaining = path.total - layout.firstTotal - layout.terminalEndExtension
        guard remaining > 0 else { return 1 }
        return max(1, Int(floor(remaining / layout.repeatedTotal)) + 1)
    }

    static func contentLayout() -> ContentLayout {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let firstLeadPad: CGFloat = -18
        let xSize: CGFloat = 30
        let iconTextGap: CGFloat = 4
        let wordGap = (" " as NSString).size(withAttributes: [.font: font]).width
        let firstTrailPad: CGFloat = 0
        let repeatedLeadPad: CGFloat = wordGap
        let repeatedTrailPad: CGFloat = 0
        let terminalTextToRoundGap: CGFloat = 16

        var firstCursor = firstLeadPad
        let xCenter = firstCursor + xSize / 2
        firstCursor += xSize + iconTextGap
        let firstGlyphs = messageGlyphs(startingAt: firstCursor, font: font)
        firstCursor = (firstGlyphs.last?.trailingEdge ?? firstCursor) + firstTrailPad

        var repeatedCursor = repeatedLeadPad
        let repeatedGlyphs = messageGlyphs(startingAt: repeatedCursor, font: font)
        repeatedCursor = (repeatedGlyphs.last?.trailingEdge ?? repeatedCursor) + repeatedTrailPad

        return ContentLayout(
            xCenter: xCenter,
            firstGlyphs: firstGlyphs,
            repeatedGlyphs: repeatedGlyphs,
            firstTotal: firstCursor,
            repeatedTotal: repeatedCursor,
            terminalEndExtension: terminalTextToRoundGap
        )
    }

    private static func messageGlyphs(startingAt start: CGFloat, font: NSFont) -> [PlacedGlyph] {
        var cursor = start
        return message.enumerated().map { index, character in
            let advance = (String(character) as NSString).size(withAttributes: [.font: font]).width
            defer { cursor += advance }
            return PlacedGlyph(
                id: index,
                character: character,
                center: cursor + advance / 2,
                trailingEdge: cursor + advance
            )
        }
    }
}

// MARK: - Fill driver

private final class TimeOutFillModel: ObservableObject {
    @Published var itemCount = 1

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let tick = Timer(timeInterval: TravelingTimeOutGeometry.repeatInterval, repeats: true) { [weak self] _ in
            self?.itemCount += 1
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Growing, bending capsule trail

struct TravelingTimeOutView: View {
    @ObservedObject var model: TimerModel
    let screenFrame: CGRect
    let visibleFrame: CGRect
    @StateObject private var fill = TimeOutFillModel()

    private let yellow = Color(red: 1.0, green: 0.82, blue: 0.0)
    private let ink = Color(white: 0.133)

    var body: some View {
        GeometryReader { geo in
            let area = TravelingTimeOutGeometry.layoutArea(
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            )
            let path = TravelingTimeOutGeometry.perimeterPath(in: area)
            let layout = TravelingTimeOutGeometry.contentLayout()
            let start = TravelingTimeOutGeometry.startDistance(for: model.overlayPosition, on: path)
            let maxItemCount = TravelingTimeOutGeometry.maxItemCount(on: path, layout: layout)
            let visibleItemCount = min(fill.itemCount, maxItemCount)
            let filledLength = TravelingTimeOutGeometry.filledLength(for: visibleItemCount, on: path)

            ZStack {
                band(path: path, start: start, length: filledLength)
                    .fill(yellow)
                startCap(path: path, start: start)
                    .fill(yellow)
                endCap(path: path, start: start, visualLength: filledLength)
                    .fill(yellow)

                glyph("", at: start + layout.xCenter, on: path, isSymbol: true)
                ForEach(layout.firstGlyphs) { item in
                    glyph(item, at: start + item.center, on: path)
                }
                ForEach(1..<visibleItemCount, id: \.self) { index in
                    ForEach(layout.repeatedGlyphs) { item in
                        glyph(
                            item,
                            at: start + layout.firstTotal + CGFloat(index - 1) * layout.repeatedTotal + item.center,
                            on: path
                        )
                    }
                }
            }
            .onAppear { fill.start() }
            .onDisappear { fill.stop() }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func glyph(_ text: String, at s: CGFloat, on path: RoundedRectPath, isSymbol: Bool = false) -> some View {
        let placement = path.locate(s)
        Group {
            if isSymbol {
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundColor(ink)
            } else {
                Text(text)
                    .font(.system(size: TravelingTimeOutGeometry.fontSize, weight: .semibold))
                    .foregroundColor(ink)
                    .fixedSize()
            }
        }
        .rotationEffect(.radians(Double(readableAngle(placement.1))))
        .position(placement.0)
        .allowsHitTesting(false)   // taps go to the band beneath
    }

    @ViewBuilder
    private func glyph(_ item: PlacedGlyph, at s: CGFloat, on path: RoundedRectPath) -> some View {
        let placement = path.locate(s)
        Text(String(item.character))
            .font(.system(size: TravelingTimeOutGeometry.fontSize, weight: .semibold))
            .foregroundColor(ink)
            .fixedSize()
            .rotationEffect(.radians(Double(readableAngle(placement.1))))
            .position(placement.0)
            .allowsHitTesting(false)
    }

    private func readableAngle(_ angle: CGFloat) -> CGFloat {
        var normalized = atan2(sin(angle), cos(angle))
        if normalized > .pi / 2 {
            normalized -= .pi
        } else if normalized < -.pi / 2 {
            normalized += .pi
        }
        return normalized
    }

    private func band(path: RoundedRectPath, start: CGFloat, length: CGFloat) -> Path {
        var p = Path()
        let drawnLength = max(0, length - TravelingTimeOutGeometry.bandWidth / 2)
        let steps = max(2, Int(drawnLength / 6))
        for i in 0...steps {
            let s = start + drawnLength * CGFloat(i) / CGFloat(steps)
            let point = path.locate(s).0
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p.strokedPath(StrokeStyle(lineWidth: TravelingTimeOutGeometry.bandWidth, lineCap: .butt, lineJoin: .round))
    }

    private func startCap(path: RoundedRectPath, start: CGFloat) -> Path {
        let point = path.locate(start).0
        return Path(ellipseIn: CGRect(
            x: point.x - TravelingTimeOutGeometry.bandWidth / 2,
            y: point.y - TravelingTimeOutGeometry.bandWidth / 2,
            width: TravelingTimeOutGeometry.bandWidth,
            height: TravelingTimeOutGeometry.bandWidth
        ))
    }

    private func endCap(path: RoundedRectPath, start: CGFloat, visualLength: CGFloat) -> Path {
        let capRadius = TravelingTimeOutGeometry.bandWidth / 2
        let point = path.locate(start + max(0, visualLength - capRadius)).0
        return Path(ellipseIn: CGRect(
            x: point.x - capRadius,
            y: point.y - capRadius,
            width: TravelingTimeOutGeometry.bandWidth,
            height: TravelingTimeOutGeometry.bandWidth
        ))
    }
}

private struct PlacedGlyph: Identifiable {
    let id: Int
    let character: Character
    let center: CGFloat
    let trailingEdge: CGFloat
}

private struct ContentLayout {
    let xCenter: CGFloat
    let firstGlyphs: [PlacedGlyph]
    let repeatedGlyphs: [PlacedGlyph]
    let firstTotal: CGFloat
    let repeatedTotal: CGFloat
    let terminalEndExtension: CGFloat
}

/// Arc-length parameterization of a rounded rectangle, walked clockwise starting
/// just after the top-left corner. Returns position and the tangent angle.
private struct RoundedRectPath {
    let rect: CGRect
    let r: CGFloat
    let lineH: CGFloat
    let lineV: CGFloat
    let arc: CGFloat
    let total: CGFloat

    init(rect: CGRect, radius: CGFloat) {
        self.rect = rect
        self.r = radius
        lineH = max(0, rect.width - radius * 2)
        lineV = max(0, rect.height - radius * 2)
        arc = .pi / 2 * radius
        total = lineH * 2 + lineV * 2 + arc * 4
    }

    func locate(_ rawS: CGFloat) -> (CGPoint, CGFloat) {
        var s = rawS.truncatingRemainder(dividingBy: total)
        if s < 0 { s += total }

        if s < lineH {
            return (CGPoint(x: rect.minX + r + s, y: rect.minY), 0)
        }
        s -= lineH
        if s < arc {
            return arcPoint(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), startAngle: -.pi / 2, travel: s)
        }
        s -= arc
        if s < lineV {
            return (CGPoint(x: rect.maxX, y: rect.minY + r + s), .pi / 2)
        }
        s -= lineV
        if s < arc {
            return arcPoint(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), startAngle: 0, travel: s)
        }
        s -= arc
        if s < lineH {
            return (CGPoint(x: rect.maxX - r - s, y: rect.maxY), .pi)
        }
        s -= lineH
        if s < arc {
            return arcPoint(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), startAngle: .pi / 2, travel: s)
        }
        s -= arc
        if s < lineV {
            return (CGPoint(x: rect.minX, y: rect.maxY - r - s), .pi * 1.5)
        }
        s -= lineV
        return arcPoint(center: CGPoint(x: rect.minX + r, y: rect.minY + r), startAngle: .pi, travel: s)
    }

    private func arcPoint(center: CGPoint, startAngle: CGFloat, travel: CGFloat) -> (CGPoint, CGFloat) {
        let a = startAngle + travel / r
        let point = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
        let angle = atan2(cos(a), -sin(a))
        return (point, angle)
    }
}
