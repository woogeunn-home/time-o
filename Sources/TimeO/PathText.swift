import AppKit
import QuartzCore
import SwiftUI

// MARK: - Controller

/// Full-screen overlay that carries the "Time's Up" capsule continuously around
/// the screen's outer edge until dismissed. The capsule is drawn as a band that
/// follows (bends along) the rounded-rectangle perimeter, with the text laid out
/// glyph-by-glyph on the path so it curves naturally around corners. Clicking
/// the capsule dismisses it.
final class TravelingTimeOutController {
    private var window: NSPanel?

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
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false

        let view = NSHostingView(rootView: TravelingTimeOutView(model: model))
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = view
        panel.orderFrontRegardless()
        window = panel
    }

    func stop() {
        window?.close()
        window = nil
    }
}

// MARK: - Travel driver

/// Advances a distance value at a steady speed, independent of view size. The
/// view mods it by the actual perimeter length.
private final class TravelModel: ObservableObject {
    @Published var distance: CGFloat = 0

    private let speed: CGFloat = 130   // points per second
    private var timer: Timer?
    private var last: CFTimeInterval = 0

    func start() {
        guard timer == nil else { return }
        last = CACurrentMediaTime()
        let tick = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            self.distance += self.speed * CGFloat(now - self.last)
            self.last = now
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Traveling, bending capsule

struct TravelingTimeOutView: View {
    @ObservedObject var model: TimerModel
    @StateObject private var travel = TravelModel()

    private let inset: CGFloat = 40
    private let cornerRadius: CGFloat = 80
    private let bandWidth: CGFloat = 60
    private let fontSize: CGFloat = 30
    private let message = "Time's Up"
    private let yellow = Color(red: 1.0, green: 0.82, blue: 0.0)
    private let ink = Color(white: 0.133)

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(
                x: inset, y: inset,
                width: geo.size.width - inset * 2,
                height: geo.size.height - inset * 2
            )
            let path = RoundedRectPath(rect: rect, radius: min(cornerRadius, min(rect.width, rect.height) / 2))
            let layout = contentLayout()
            let start = travel.distance.truncatingRemainder(dividingBy: path.total)

            ZStack {
                band(path: path, start: start, length: layout.total)
                    .fill(yellow)
                    .onTapGesture { model.stop() }

                glyph("", at: start + layout.xCenter, on: path, isSymbol: true)
                ForEach(layout.glyphs) { item in
                    glyph(String(item.character), at: start + item.center, on: path)
                }
            }
            .onAppear { travel.start() }
            .onDisappear { travel.stop() }
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
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(ink)
                    .fixedSize()
            }
        }
        .rotationEffect(.radians(Double(placement.1)))
        .position(placement.0)
        .allowsHitTesting(false)   // taps go to the band beneath
    }

    private func band(path: RoundedRectPath, start: CGFloat, length: CGFloat) -> Path {
        var p = Path()
        let steps = max(2, Int(length / 6))
        for i in 0...steps {
            let s = start + length * CGFloat(i) / CGFloat(steps)
            let point = path.locate(s).0
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p.strokedPath(StrokeStyle(lineWidth: bandWidth, lineCap: .round, lineJoin: .round))
    }

    // Arc-length offsets (from the band start) of the X marker and each glyph.
    private func contentLayout() -> ContentLayout {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let leadPad: CGFloat = 24
        let xSize: CGFloat = 30
        let gap: CGFloat = 12
        let trailPad: CGFloat = 28

        var cursor = leadPad
        let xCenter = cursor + xSize / 2
        cursor += xSize + gap

        var glyphs: [PlacedGlyph] = []
        for (index, character) in message.enumerated() {
            let advance = (String(character) as NSString).size(withAttributes: [.font: font]).width
            glyphs.append(PlacedGlyph(id: index, character: character, center: cursor + advance / 2))
            cursor += advance
        }
        cursor += trailPad
        return ContentLayout(xCenter: xCenter, glyphs: glyphs, total: cursor)
    }
}

private struct PlacedGlyph: Identifiable {
    let id: Int
    let character: Character
    let center: CGFloat
}

private struct ContentLayout {
    let xCenter: CGFloat
    let glyphs: [PlacedGlyph]
    let total: CGFloat
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
