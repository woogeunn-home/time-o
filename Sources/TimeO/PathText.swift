import AppKit
import QuartzCore
import SwiftUI

// MARK: - Controller

/// Full-screen overlay that anchors the first message block at the top-center of
/// the screen, then adds another phrase block every interval — cycling through a
/// set of phrases — until the trail wraps once around the screen edge.
final class TravelingTimeOutController {
    private var window: NSPanel?
    private var closeButtonWindow: NSPanel?
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
        createCloseButtonTrackingWindow(on: screen, model: model)
        startClickMonitoring()
    }

    func stop() {
        stopClickMonitoring()
        closeButtonWindow?.close()
        closeButtonWindow = nil
        window?.close()
        window = nil
        activeModel = nil
        activeScreen = nil
    }

    private func startClickMonitoring() {
        stopClickMonitoring()

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, self.isOverCloseButton() else {
                return event
            }
            self.beginClose()
            return nil
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, self.isOverCloseButton() else { return }
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
        activeModel?.isCompletionCapsuleHovered = false
    }

    private func createCloseButtonTrackingWindow(on screen: NSScreen, model: TimerModel) {
        let area = TravelingTimeOutGeometry.layoutArea(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        let buttonFrame = TravelingTimeOutGeometry.closeButtonFrame(
            in: area,
            timerText: model.formattedRemaining
        )
        let screenFrame = NSRect(
            x: screen.frame.minX + buttonFrame.minX,
            y: screen.frame.maxY - buttonFrame.maxY,
            width: buttonFrame.width,
            height: buttonFrame.height
        )
        let panel = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(Int(NSWindow.Level.screenSaver.rawValue) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        let trackingView = CloseButtonTrackingView(frame: NSRect(origin: .zero, size: screenFrame.size)) { [weak self] in
            self?.beginClose()
        }
        trackingView.autoresizingMask = [.width, .height]
        panel.contentView = trackingView
        panel.orderFrontRegardless()
        closeButtonWindow = panel
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
        let capacity = TravelingTimeOutGeometry.capacity(
            in: area,
            position: .topCenter,
            timerText: model.formattedRemaining,
            timeString: TravelingTimeOutGeometry.currentTimeString()
        )
        let revealDuration = TravelingTimeOutGeometry.revealDuration(capacity: capacity)
        let flowSeconds = model.flowSeconds(now: now, startTime: startTime, revealDuration: revealDuration)
        return TravelingTimeOutGeometry.flowOffset(flowSeconds: flowSeconds)
    }

    private func isOverCloseButton() -> Bool {
        guard let (point, area) = overlayPoint() else { return false }
        return TravelingTimeOutGeometry.closeButtonFrame(
            in: area,
            timerText: activeModel?.formattedRemaining ?? "00:00"
        ).contains(point)
    }

    private func isOverInteractiveArea() -> Bool {
        guard let (point, area) = overlayPoint() else { return false }
        if TravelingTimeOutGeometry.closeButtonFrame(
            in: area,
            timerText: activeModel?.formattedRemaining ?? "00:00"
        ).contains(point) {
            return true
        }
        if let model = activeModel,
           !model.isTimesUpFlowing,
           let activeScreen,
           OverlayWindow.overlayFrame(
               for: activeScreen,
               position: .topCenter,
               text: model.formattedRemaining,
               isPaused: model.isPaused
           ).contains(NSEvent.mouseLocation) {
            return true
        }
        let now = CACurrentMediaTime()
        let elapsed = now - startTime
        return TravelingTimeOutGeometry.contains(
            point,
            in: area,
            itemCount: TravelingTimeOutGeometry.itemCount(after: CGFloat(elapsed)),
            flowOffset: currentFlowOffset(area: area, now: now),
            position: .topCenter,
            includesTimer: activeModel?.isTimesUpFlowing ?? false,
            timerText: activeModel?.formattedRemaining ?? "00:00"
        )
    }

    private func updateHoverPause() {
        guard let model = activeModel else { return }
        let now = CACurrentMediaTime()
        let isHovered = isOverInteractiveArea()
        if model.isCompletionCapsuleHovered != isHovered {
            model.isCompletionCapsuleHovered = isHovered
        }
        if isHovered {
            if model.flowPauseStartedAt == nil { model.flowPauseStartedAt = now }
        } else if let started = model.flowPauseStartedAt {
            model.flowPausedTotal += now - started
            model.flowPauseStartedAt = nil
        }
    }
}

private final class CloseButtonTrackingView: NSView {
    private let onClick: () -> Void
    private var trackingArea: NSTrackingArea?

    init(frame frameRect: NSRect, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}

private enum TravelingTimeOutGeometry {
    static let inset: CGFloat = 32
    static let cornerRadius: CGFloat = 120
    static let bandWidth: CGFloat = 56
    static let fontSize: CGFloat = 30
    static let symbolSize: CGFloat = 32
    static let sidePadding: CGFloat = 24
    static let blockGap: CGFloat = 9
    static let closeButtonGap: CGFloat = 10
    static let closeButtonSize: CGFloat = 56
    static let ringSpacing: CGFloat = bandWidth + 16
    static let repeatInterval: TimeInterval = 0.5
    /// Arc-length the whole trail drifts clockwise per second.
    static let flowSpeed: CGFloat = 90
    static func timerCapsuleLength(for timerText: String) -> CGFloat {
        OverlayWindow.centerOverlayWidth(for: timerText)
    }

    /// Time the reveal takes to generate every capsule, after which flow begins.
    static func revealDuration(capacity: Int) -> TimeInterval {
        TimeInterval(max(0, capacity - 1)) * repeatInterval
    }

    /// Clockwise drift applied to every capsule, from the effective flowing time
    /// (reveal and hover-pauses already excluded).
    static func flowOffset(flowSeconds: TimeInterval) -> CGFloat {
        CGFloat(max(0, flowSeconds)) * flowSpeed
    }

    /// Number of capsules that fit in a single loop (independent of flow).
    static func capacity(
        in area: CGRect,
        position: OverlayPosition,
        timerText: String,
        timeString: String
    ) -> Int {
        layout(
            count: Int.max,
            in: area,
            flowOffset: 0,
            position: position,
            timerText: timerText,
            timeString: timeString
        ).count
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
        .text("Take a breath"),
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

    static func isSymbol(_ content: BlockContent) -> Bool {
        if case .symbol = content {
            return true
        }
        return false
    }

    struct GlyphRel {
        let character: Character
        let isSymbol: Bool
        let symbolName: String?
        let usesMonospacedDigit: Bool
        let center: CGFloat
    }

    static func itemCount(after elapsed: CGFloat) -> Int {
        1 + max(0, Int(floor(TimeInterval(max(0, elapsed)) / repeatInterval)))
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

    static func closeButtonFrame(in area: CGRect, timerText: String) -> CGRect {
        let timerWidth = timerCapsuleLength(for: timerText)
        let timerHeight = bandWidth
        let timerX = area.midX - timerWidth / 2
        let timerY = area.minY + 4
        return CGRect(
            x: timerX + timerWidth / 2 - closeButtonSize / 2,
            y: timerY + timerHeight + closeButtonGap,
            width: closeButtonSize,
            height: closeButtonSize
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

    /// Start immediately after the overtime timer capsule, following the
    /// rounded screen path clockwise from the selected timer position.
    static func timerCenterDistance(on path: RoundedRectPath, position: OverlayPosition) -> CGFloat {
        let center: CGFloat
        switch position {
        case .topLeading:
            center = 0
        case .topCenter:
            center = path.lineH / 2
        case .topTrailing:
            center = path.lineH
        case .middleTrailing:
            center = path.lineH + path.arc + path.lineV / 2
        case .bottomTrailing:
            center = path.lineH + path.arc + path.lineV + path.arc
        case .bottomCenter:
            center = path.lineH + path.arc + path.lineV + path.arc + path.lineH / 2
        case .bottomLeading:
            center = path.lineH * 2 + path.arc * 2 + path.lineV
        case .middleLeading:
            center = path.lineH * 2 + path.arc * 3 + path.lineV * 1.5
        }

        return center
    }

    private static func measure(_ content: BlockContent, font: NSFont, timeString: String) -> (glyphs: [GlyphRel], width: CGFloat) {
        switch content {
        case .symbol(let name):
            return ([
                GlyphRel(
                    character: " ",
                    isSymbol: true,
                    symbolName: name,
                    usesMonospacedDigit: false,
                    center: symbolSize / 2
                )
            ], symbolSize)
        case .text(let string):
            return measureText(string, font: font)
        case .currentTime:
            return measureText("It's already \(timeString) — step away for a moment", font: font)
        }
    }

    private static func blockLength(
        for content: BlockContent,
        measuredWidth: CGFloat,
        isTimerBlock: Bool,
        timerCapsuleLength: CGFloat
    ) -> CGFloat {
        if isTimerBlock {
            return timerCapsuleLength
        }

        return isSymbol(content)
            ? bandWidth
            : sidePadding * 2 + measuredWidth
    }

    private static func wouldLeaveOnlyTrailingSymbols(
        startingAt trailIndex: Int,
        cursor: CGFloat,
        trailEnd: CGFloat,
        font: NSFont,
        timeString: String
    ) -> Bool {
        var lookaheadCursor = cursor
        var lookaheadIndex = trailIndex

        while isSymbol(content(at: lookaheadIndex)) {
            if lookaheadCursor + bandWidth > trailEnd {
                return true
            }
            lookaheadCursor += bandWidth + blockGap
            lookaheadIndex += 1
        }

        let nextContent = content(at: lookaheadIndex)
        let nextMeasured = measure(nextContent, font: font, timeString: timeString)
        let nextLength = blockLength(
            for: nextContent,
            measuredWidth: nextMeasured.width,
            isTimerBlock: false,
            timerCapsuleLength: 0
        )
        return lookaheadCursor + nextLength > trailEnd
    }

    private static func measureText(
        _ string: String,
        font: NSFont,
        usesMonospacedDigit: Bool = false
    ) -> (glyphs: [GlyphRel], width: CGFloat) {
        var cursor: CGFloat = 0
        var glyphs: [GlyphRel] = []
        for character in string {
            let advance = (String(character) as NSString).size(withAttributes: [.font: font]).width
            glyphs.append(
                GlyphRel(
                    character: character,
                    isSymbol: false,
                    symbolName: nil,
                    usesMonospacedDigit: usesMonospacedDigit,
                    center: cursor + advance / 2
                )
            )
            cursor += advance
        }
        return (glyphs, cursor)
    }

    /// Lays out up to `count` separated phrase blocks. While flowing, the timer
    /// capsule becomes the first block in the same rounded-rect path. Blocks fill
    /// clockwise from the top-center; when a loop completes, the trail steps to
    /// the next inner ring and stops after `maxLoops` loops.
    static let maxLoops = 1

    static func layout(
        count: Int,
        in area: CGRect,
        flowOffset: CGFloat = 0,
        position: OverlayPosition,
        includesTimer: Bool = false,
        timerText: String,
        timeString: String
    ) -> [BlockLayout] {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let timerCapsuleLength = timerCapsuleLength(for: timerText)
        var ringIndex = 0
        guard var currentRing = ring(ringIndex, in: area) else { return [] }
        let timerCenter = timerCenterDistance(on: currentRing, position: position)
        var base = includesTimer
            ? timerCenter - timerCapsuleLength / 2
            : timerCenter + timerCapsuleLength / 2 + blockGap
        var trailEnd = base + currentRing.total - blockGap
        var cursor = base
        var lastBlockEnd = base
        var layouts: [BlockLayout] = []
        var blockStarts: [CGFloat] = []
        var glyphID = 0
        var reachedEndOfTrail = false

        let layoutCount = max(0, count) + (includesTimer ? 1 : 0)
        for index in 0..<layoutCount {
            let isTimerBlock = includesTimer && index == 0
            let trailIndex = includesTimer ? index - 1 : index
            let blockContent: BlockContent = isTimerBlock
                ? .text(timerText)
                : content(at: trailIndex)
            let measured = isTimerBlock
                ? measureText(
                    timerText,
                    font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                    usesMonospacedDigit: true
                )
                : measure(blockContent, font: font, timeString: timeString)
            let isSymbolBlock: Bool
            if case .symbol = blockContent {
                isSymbolBlock = true
            } else {
                isSymbolBlock = false
            }
            let blockLength = blockLength(
                for: blockContent,
                measuredWidth: measured.width,
                isTimerBlock: isTimerBlock,
                timerCapsuleLength: timerCapsuleLength
            )

            // After a full loop, step inward (up to maxLoops) or stop.
            if cursor + blockLength > trailEnd {
                guard ringIndex + 1 < maxLoops, let next = ring(ringIndex + 1, in: area) else {
                    reachedEndOfTrail = true
                    break
                }
                let dropPoint = currentRing.locate(lastBlockEnd).0
                ringIndex += 1
                currentRing = next
                let seam = min(currentRing.lineH, max(0, dropPoint.x - (currentRing.rect.minX + currentRing.r)))
                base = seam
                trailEnd = base + currentRing.total
                cursor = seam
                lastBlockEnd = seam
                if cursor + blockLength > trailEnd {
                    reachedEndOfTrail = true
                    break
                }
            }

            if !isTimerBlock,
               isSymbolBlock,
               ringIndex + 1 >= maxLoops,
               wouldLeaveOnlyTrailingSymbols(
                   startingAt: trailIndex,
                   cursor: cursor,
                   trailEnd: trailEnd,
                   font: font,
                   timeString: timeString
               ) {
                reachedEndOfTrail = true
                break
            }

            blockStarts.append(cursor)
            let contentInset = (isTimerBlock || isSymbolBlock)
                ? (blockLength - measured.width) / 2
                : sidePadding
            let contentStart = cursor + contentInset + flowOffset
            let glyphs = measured.glyphs.map { glyph -> PlacedGlyph in
                defer { glyphID += 1 }
                let placement = currentRing.locate(contentStart + glyph.center)
                return PlacedGlyph(
                    id: glyphID,
                    character: glyph.character,
                    isSymbol: glyph.isSymbol,
                    symbolName: glyph.symbolName,
                    usesMonospacedDigit: glyph.usesMonospacedDigit,
                    position: placement.0,
                    angle: placement.1
                )
            }

            layouts.append(BlockLayout(id: index, band: bandPath(on: currentRing, start: cursor + flowOffset, length: blockLength), glyphs: glyphs))
            lastBlockEnd = cursor + blockLength
            cursor = lastBlockEnd + blockGap
        }

        // When the final requested block is also the last one that can fit,
        // close the loop immediately instead of waiting for one more reveal tick.
        if !reachedEndOfTrail, layouts.count == layoutCount {
            let nextTrailIndex = count
            let nextContent = content(at: nextTrailIndex)
            if isSymbol(nextContent) {
                reachedEndOfTrail = ringIndex + 1 >= maxLoops
                    && wouldLeaveOnlyTrailingSymbols(
                        startingAt: nextTrailIndex,
                        cursor: cursor,
                        trailEnd: trailEnd,
                        font: font,
                        timeString: timeString
                    )
            } else {
                let nextMeasurement = measure(nextContent, font: font, timeString: timeString)
                let nextLength = blockLength(
                    for: nextContent,
                    measuredWidth: nextMeasurement.width,
                    isTimerBlock: false,
                    timerCapsuleLength: timerCapsuleLength
                )
                reachedEndOfTrail = cursor + nextLength > trailEnd
                    && ringIndex + 1 >= maxLoops
            }
        }

        // Stretch the last capsule to the first capsule's edge so the completed
        // trail keeps the standard gap without swapping its generated content.
        // Never use an icon capsule as the trail's final filler. Remove trailing
        // icons and let the preceding text capsule absorb the remaining width.
        while reachedEndOfTrail,
              layouts.count > 1,
              layouts.last?.glyphs.contains(where: \.isSymbol) == true {
            layouts.removeLast()
            blockStarts.removeLast()
        }

        if reachedEndOfTrail,
           let lastBlockStart = blockStarts.last,
           let last = layouts.last {
            let finalLength = trailEnd - lastBlockStart
            layouts[layouts.count - 1] = BlockLayout(
                id: last.id,
                band: bandPath(
                    on: currentRing,
                    start: lastBlockStart + flowOffset,
                    length: finalLength
                ),
                glyphs: last.glyphs
            )
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

    static func contains(
        _ point: CGPoint,
        in area: CGRect,
        itemCount: Int,
        flowOffset: CGFloat,
        position: OverlayPosition,
        includesTimer: Bool,
        timerText: String
    ) -> Bool {
        let layouts = layout(
            count: itemCount,
            in: area,
            flowOffset: flowOffset,
            position: position,
            includesTimer: includesTimer,
            timerText: timerText,
            timeString: currentTimeString()
        )
        return layouts.contains { $0.band.contains(point) }
    }
}

// MARK: - Fill driver

private final class TimeOutFillModel: ObservableObject {
    // The overtime timer capsule remains visible; reveal the close button beside it first.
    @Published var itemCount = 1
    /// Number of trailing capsules already retracted during the close animation.
    @Published var closedCount = 0

    private var revealTimer: Timer?
    private var closeTimer: Timer?
    private var isClosing = false

    /// Fast retract interval, per capsule.
    private let closeInterval: TimeInterval = 0.025

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

    /// Retract capsules in reverse creation order, leaving the close button last.
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

    private let ink = Color(white: 0.133)

    var body: some View {
        let area = TravelingTimeOutGeometry.layoutArea(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        TimelineView(.animation) { _ in
            let timeString = TravelingTimeOutGeometry.currentTimeString()
            let now = CACurrentMediaTime()
            let capacity = TravelingTimeOutGeometry.capacity(
                in: area,
                position: .topCenter,
                timerText: model.formattedRemaining,
                timeString: timeString
            )
            let revealDuration = TravelingTimeOutGeometry.revealDuration(capacity: capacity)
            let flowSeconds = model.flowSeconds(
                now: now,
                startTime: startTime,
                revealDuration: revealDuration
            )
            let isFlowing = flowSeconds > 0
            let flow = TravelingTimeOutGeometry.flowOffset(flowSeconds: flowSeconds)
            let layouts = TravelingTimeOutGeometry.layout(
                count: fill.itemCount,
                in: area,
                flowOffset: flow,
                position: .topCenter,
                includesTimer: isFlowing,
                timerText: model.formattedRemaining,
                timeString: timeString
            )
            // Remove the most recently generated capsules first.
            let visible = Array(layouts.dropLast(min(fill.closedCount, layouts.count)))

            ZStack {
                ForEach(visible) { layout in
                    layout.band.fill(WarningCapsuleStyle.completionFill)
                        .opacity(capsuleOpacity(for: layout))
                }
                ForEach(visible) { layout in
                    ForEach(layout.glyphs) { item in
                        glyph(item)
                    }
                    .opacity(capsuleOpacity(for: layout))
                }
                closeButton(
                    frame: TravelingTimeOutGeometry.closeButtonFrame(
                        in: area,
                        timerText: model.formattedRemaining
                    )
                )
            }
            .animation(.easeOut(duration: 0.12), value: model.isCompletionCapsuleHovered)
            .onAppear { fill.start() }
            .onDisappear { fill.stop() }
            .onChange(of: isFlowing) { flowing in
                model.isTimesUpFlowing = flowing
            }
            .onChange(of: model.isClosing) { closing in
                guard closing else { return }
                let total = TravelingTimeOutGeometry.layout(
                    count: fill.itemCount,
                    in: area,
                    position: .topCenter,
                    includesTimer: model.isTimesUpFlowing,
                    timerText: model.formattedRemaining,
                    timeString: TravelingTimeOutGeometry.currentTimeString()
                ).count
                fill.beginClose(total: total) { model.stop() }
            }
        }
        .ignoresSafeArea()
    }

    private func capsuleOpacity(for layout: BlockLayout) -> Double {
        model.isCompletionCapsuleHovered ? 0.5 : 1
    }

    private func closeButton(frame: CGRect) -> some View {
        ZStack {
            Circle()
                .fill(WarningCapsuleStyle.completionFill)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.03), lineWidth: 1)
                }

            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ink)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .opacity(model.isCompletionCapsuleHovered ? 1 : 0.92)
        .allowsHitTesting(false)
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
                if item.usesMonospacedDigit {
                    Text(String(item.character))
                        .font(.system(size: TravelingTimeOutGeometry.fontSize, weight: .semibold, design: .default))
                        .monospacedDigit()
                        .foregroundColor(ink)
                        .fixedSize()
                } else {
                    Text(String(item.character))
                        .font(.system(size: TravelingTimeOutGeometry.fontSize, weight: .semibold, design: .default))
                        .foregroundColor(ink)
                        .fixedSize()
                }
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
    let usesMonospacedDigit: Bool
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
