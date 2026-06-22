import AppKit
import QuartzCore
import SwiftUI

// MARK: - Controller

/// Full-screen overlay that anchors the first message block at the top-center of
/// the screen, then adds another phrase block every interval — cycling through a
/// set of phrases — until the trail wraps once around the screen edge.
final class TravelingTimeOutController {
    private var window: NSPanel?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalMoveMonitor: Any?
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

        startTime = CACurrentMediaTime()
        let view = NSHostingView(rootView: TravelingTimeOutView(
            model: model,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            startTime: startTime
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
            guard let self, self.isOverCapsule() else {
                return event
            }
            self.beginClose()
            return nil
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, self.isOverCapsule() else { return }
            DispatchQueue.main.async {
                self.beginClose()
            }
        }

        // Pause the flow while the cursor hovers a capsule; resume when it leaves.
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateHoverPause()
            return event
        }
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateHoverPause()
        }
    }

    /// Kick off the sequential close animation; the view tears the overlay down
    /// once every capsule has been retracted.
    private func beginClose() {
        guard let model = activeModel, !model.isClosing else { return }
        model.isClosing = true
    }

    private func stopClickMonitoring() {
        for monitor in [localClickMonitor, globalClickMonitor, localMoveMonitor, globalMoveMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        localClickMonitor = nil
        globalClickMonitor = nil
        localMoveMonitor = nil
        globalMoveMonitor = nil
    }

    /// Cursor position in the overlay's coordinate space, plus the layout area,
    /// or nil when the cursor is off the active screen.
    private func overlayPoint() -> (point: CGPoint, area: CGRect)? {
        guard let activeScreen else { return nil }
        let screenPoint = NSEvent.mouseLocation
        guard activeScreen.frame.contains(screenPoint) else { return nil }
        let point = CGPoint(
            x: screenPoint.x - activeScreen.frame.minX,
            y: activeScreen.frame.maxY - screenPoint.y
        )
        let area = TravelingTimeOutGeometry.layoutArea(
            screenFrame: activeScreen.frame,
            visibleFrame: activeScreen.visibleFrame
        )
        return (point, area)
    }

    private func currentFlowOffset(area: CGRect, now: CFTimeInterval) -> CGFloat {
        guard let model = activeModel else { return 0 }
        let capacity = TravelingTimeOutGeometry.capacity(in: area, timeString: TravelingTimeOutGeometry.currentTimeString())
        let revealDuration = TravelingTimeOutGeometry.revealDuration(capacity: capacity)
        let flowSeconds = model.flowSeconds(now: now, startTime: startTime, revealDuration: revealDuration)
        return TravelingTimeOutGeometry.flowOffset(flowSeconds: flowSeconds)
    }

    private func isOverCapsule() -> Bool {
        guard let (point, area) = overlayPoint() else { return false }
        let now = CACurrentMediaTime()
        let elapsed = now - startTime
        return TravelingTimeOutGeometry.contains(
            point,
            in: area,
            itemCount: TravelingTimeOutGeometry.itemCount(after: CGFloat(elapsed)),
            flowOffset: currentFlowOffset(area: area, now: now)
        )
    }

    private func updateHoverPause() {
        guard let model = activeModel else { return }
        let now = CACurrentMediaTime()
        if isOverCapsule() {
            if model.flowPauseStartedAt == nil { model.flowPauseStartedAt = now }
        } else if let started = model.flowPauseStartedAt {
            model.flowPausedTotal += now - started
            model.flowPauseStartedAt = nil
        }
    }
}

private enum TravelingTimeOutGeometry {
    static let inset: CGFloat = 34
    static let cornerRadius: CGFloat = 120
    static let bandWidth: CGFloat = 60
    static let fontSize: CGFloat = 30
    static let symbolSize: CGFloat = 32
    static let sidePadding: CGFloat = 28
    static let blockGap: CGFloat = 9
    static let ringSpacing: CGFloat = bandWidth + 16
    static let repeatInterval: TimeInterval = 0.5
    /// Arc-length the whole trail drifts clockwise per second.
    static let flowSpeed: CGFloat = 90

    /// Time the reveal takes to generate every capsule, after which flow begins.
    static func revealDuration(capacity: Int) -> TimeInterval {
        TimeInterval(max(0, capacity - 2)) * repeatInterval
    }

    /// Clockwise drift applied to every capsule, from the effective flowing time
    /// (reveal and hover-pauses already excluded).
    static func flowOffset(flowSeconds: TimeInterval) -> CGFloat {
        CGFloat(max(0, flowSeconds)) * flowSpeed
    }

    /// Number of capsules that fit in a single loop (independent of flow).
    static func capacity(in area: CGRect, timeString: String) -> Int {
        layout(count: Int.max, in: area, flowOffset: 0, timeString: timeString).count
    }

    /// The phrases that cycle through the trail, one per block.
    enum BlockContent {
        case text(String)
        case symbol(String)
        case currentTime
    }

    static let blocks: [BlockContent] = [
        .text("Cautions! Your focus session has fully ended now"),
        .symbol("globe.fill"),
        .text("Time's up — please wrap up whatever you're on"),
        .currentTime,
        .symbol("hand.raised.palm.facing"),
        .text("Hey, the clock ran out — go take a real break now"),
        .symbol("heart.badge.bolt"),
        .text("Stop right there, your scheduled time is officially over"),
        .symbol("eyes.inverse"),
        .symbol("trash"),
        .text("Seriously, step away from the screen and stretch a little"),
        .symbol("basketball"),
        .symbol("flag.pattern.checkered")
    ]

    static func content(at index: Int) -> BlockContent {
        blocks[index % blocks.count]
    }

    struct GlyphRel {
        let character: Character
        let isSymbol: Bool
        let symbolName: String?
        let center: CGFloat
    }

    static func itemCount(after elapsed: CGFloat) -> Int {
        2 + max(0, Int(floor(TimeInterval(max(0, elapsed)) / repeatInterval)))
    }

    static func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }

    static func layoutArea(screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - visibleFrame.maxY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }

    /// Concentric rounded-rect ring `index` (0 = outermost). Returns nil once the
    /// ring would collapse below the band width, so the spiral knows when to stop.
    static func ring(_ index: Int, in area: CGRect) -> RoundedRectPath? {
        let ringInset = inset + CGFloat(index) * ringSpacing
        let rect = CGRect(
            x: area.minX + ringInset,
            y: area.minY + ringInset,
            width: area.width - ringInset * 2,
            height: area.height - ringInset * 2
        )
        guard rect.width > bandWidth, rect.height > bandWidth else { return nil }
        // Shrink each ring's corner radius concentrically so inner corners nest
        // tightly inside the outer corner instead of bulging out.
        let nestedRadius = max(bandWidth / 2, cornerRadius - CGFloat(index) * ringSpacing)
        return RoundedRectPath(rect: rect, radius: min(nestedRadius, min(rect.width, rect.height) / 2))
    }

    /// All blocks start their trail from the top-center of the screen edge,
    /// regardless of the timer's overlay position.
    static func startDistance(on path: RoundedRectPath) -> CGFloat {
        path.lineH / 2
    }

    private static func measure(_ content: BlockContent, font: NSFont, timeString: String) -> (glyphs: [GlyphRel], width: CGFloat) {
        switch content {
        case .symbol(let name):
            return ([GlyphRel(character: " ", isSymbol: true, symbolName: name, center: symbolSize / 2)], symbolSize)
        case .text(let string):
            return measureText(string, font: font)
        case .currentTime:
            return measureText("It's already \(timeString) — step away for a moment", font: font)
        }
    }

    private static func measureText(_ string: String, font: NSFont) -> (glyphs: [GlyphRel], width: CGFloat) {
        var cursor: CGFloat = 0
        var glyphs: [GlyphRel] = []
        for character in string {
            let advance = (String(character) as NSString).size(withAttributes: [.font: font]).width
            glyphs.append(GlyphRel(character: character, isSymbol: false, symbolName: nil, center: cursor + advance / 2))
            cursor += advance
        }
        return (glyphs, cursor)
    }

    /// Lays out up to `count` separated capsule blocks. Block 0 is the close
    /// button (its own capsule); the rest cycle the phrases. Blocks fill clockwise
    /// from the top-center; when a loop completes, the trail steps to the next
    /// inner ring — starting directly below where the previous ring ran out of
    /// room so the seam bends downward — and stops after `maxLoops` loops.
    static let maxLoops = 1

    static func layout(count: Int, in area: CGRect, flowOffset: CGFloat = 0, timeString: String) -> [BlockLayout] {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        var ringIndex = 0
        guard var currentRing = ring(ringIndex, in: area) else { return [] }
        var base = startDistance(on: currentRing)
        var cursor = base
        var lastBlockEnd = base
        var layouts: [BlockLayout] = []
        var glyphID = 0

        for index in 0..<max(0, count) {
            // Block 0 is the standalone close button; the rest cycle the phrases.
            let blockContent: BlockContent = index == 0 ? .symbol("xmark.circle.fill") : content(at: index - 1)
            let measured = measure(blockContent, font: font, timeString: timeString)
            let blockLength = sidePadding * 2 + measured.width

            // After a full loop, step inward (up to maxLoops) or stop.
            if cursor + blockLength > base + currentRing.total {
                guard ringIndex + 1 < maxLoops, let next = ring(ringIndex + 1, in: area) else { break }
                let dropPoint = currentRing.locate(lastBlockEnd).0
                ringIndex += 1
                currentRing = next
                let seam = min(currentRing.lineH, max(0, dropPoint.x - (currentRing.rect.minX + currentRing.r)))
                base = seam
                cursor = seam
                lastBlockEnd = seam
                if cursor + blockLength > base + currentRing.total { break }
            }

            let contentStart = cursor + sidePadding + flowOffset
            let glyphs = measured.glyphs.map { glyph -> PlacedGlyph in
                defer { glyphID += 1 }
                let placement = currentRing.locate(contentStart + glyph.center)
                return PlacedGlyph(
                    id: glyphID,
                    character: glyph.character,
                    isSymbol: glyph.isSymbol,
                    symbolName: glyph.symbolName,
                    position: placement.0,
                    angle: placement.1
                )
            }

            layouts.append(BlockLayout(id: index, band: bandPath(on: currentRing, start: cursor + flowOffset, length: blockLength), glyphs: glyphs))
            lastBlockEnd = cursor + blockLength
            cursor = lastBlockEnd + blockGap
        }

        return layouts
    }

    /// Builds the filled capsule shape for one block along the given ring.
    static func bandPath(on ring: RoundedRectPath, start: CGFloat, length: CGFloat) -> Path {
        let capRadius = bandWidth / 2
        let s0 = start + capRadius
        let s1 = start + length - capRadius

        var p = Path()
        guard s1 > s0 else {
            let center = ring.locate(start + length / 2).0
            p.addEllipse(in: CGRect(x: center.x - capRadius, y: center.y - capRadius, width: bandWidth, height: bandWidth))
            return p
        }

        let steps = max(2, Int((s1 - s0) / 6))
        for index in 0...steps {
            let s = s0 + (s1 - s0) * CGFloat(index) / CGFloat(steps)
            let point = ring.locate(s).0
            if index == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p.strokedPath(StrokeStyle(lineWidth: bandWidth, lineCap: .round, lineJoin: .round))
    }

    static func contains(_ point: CGPoint, in area: CGRect, itemCount: Int, flowOffset: CGFloat) -> Bool {
        let layouts = layout(count: itemCount, in: area, flowOffset: flowOffset, timeString: currentTimeString())
        return layouts.contains { $0.band.contains(point) }
    }
}

// MARK: - Fill driver

private final class TimeOutFillModel: ObservableObject {
    // Start with the close button and the first phrase already showing.
    @Published var itemCount = 2
    /// Number of leading capsules already retracted during the close animation.
    @Published var closedCount = 0

    private var revealTimer: Timer?
    private var closeTimer: Timer?
    private var isClosing = false

    /// Fast retract interval, per capsule.
    private let closeInterval: TimeInterval = 0.05

    func start() {
        guard revealTimer == nil else { return }
        let tick = Timer(timeInterval: TravelingTimeOutGeometry.repeatInterval, repeats: true) { [weak self] _ in
            self?.itemCount += 1
        }
        RunLoop.main.add(tick, forMode: .common)
        revealTimer = tick
    }

    func stop() {
        revealTimer?.invalidate()
        revealTimer = nil
        closeTimer?.invalidate()
        closeTimer = nil
    }

    /// Retract capsules one at a time from the close button outward, then finish.
    func beginClose(total: Int, onComplete: @escaping () -> Void) {
        guard !isClosing else { return }
        isClosing = true
        revealTimer?.invalidate()
        revealTimer = nil

        guard total > 0 else {
            onComplete()
            return
        }

        let tick = Timer(timeInterval: closeInterval, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.closedCount += 1
            if self.closedCount >= total {
                timer.invalidate()
                onComplete()
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        closeTimer = tick
    }
}

// MARK: - Growing trail of separated phrase blocks

struct TravelingTimeOutView: View {
    @ObservedObject var model: TimerModel
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let startTime: CFTimeInterval
    @StateObject private var fill = TimeOutFillModel()

    private let yellow = Color(red: 1.0, green: 0.82, blue: 0.0)
    private let ink = Color(white: 0.133)

    var body: some View {
        let area = TravelingTimeOutGeometry.layoutArea(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        TimelineView(.animation) { _ in
            let timeString = TravelingTimeOutGeometry.currentTimeString()
            let now = CACurrentMediaTime()
            let capacity = TravelingTimeOutGeometry.capacity(in: area, timeString: timeString)
            let revealDuration = TravelingTimeOutGeometry.revealDuration(capacity: capacity)
            // Hold the trail still until every capsule has appeared; flow pauses
            // again whenever the cursor hovers a capsule.
            let flowSeconds = model.flowSeconds(now: now, startTime: startTime, revealDuration: revealDuration)
            let flow = TravelingTimeOutGeometry.flowOffset(flowSeconds: flowSeconds)
            let layouts = TravelingTimeOutGeometry.layout(
                count: fill.itemCount,
                in: area,
                flowOffset: flow,
                timeString: timeString
            )
            // Hide leading capsules already retracted by the close animation.
            let visible = layouts.filter { $0.id >= fill.closedCount }

            ZStack {
                ForEach(visible) { layout in
                    layout.band.fill(yellow)
                }
                ForEach(visible) { layout in
                    ForEach(layout.glyphs) { item in
                        glyph(item)
                    }
                }
            }
            .onAppear { fill.start() }
            .onDisappear { fill.stop() }
            .onChange(of: model.isClosing) { closing in
                guard closing else { return }
                let total = TravelingTimeOutGeometry.layout(
                    count: fill.itemCount,
                    in: area,
                    timeString: TravelingTimeOutGeometry.currentTimeString()
                ).count
                fill.beginClose(total: total) { model.stop() }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func glyph(_ item: PlacedGlyph) -> some View {
        Group {
            if item.isSymbol, let symbolName = item.symbolName {
                Image(systemName: symbolName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: TravelingTimeOutGeometry.symbolSize, height: TravelingTimeOutGeometry.symbolSize)
                    .foregroundColor(ink)
            } else {
                Text(String(item.character))
                    .font(.system(size: TravelingTimeOutGeometry.fontSize, weight: .semibold))
                    .foregroundColor(ink)
                    .fixedSize()
            }
        }
        .rotationEffect(.radians(Double(item.angle)))
        .position(item.position)
        .allowsHitTesting(false)
    }
}

private struct PlacedGlyph: Identifiable {
    let id: Int
    let character: Character
    let isSymbol: Bool
    let symbolName: String?
    let position: CGPoint
    let angle: CGFloat
}

private struct BlockLayout: Identifiable {
    let id: Int
    let band: Path
    let glyphs: [PlacedGlyph]
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
