import AppKit
import Combine
import SwiftUI

@main
struct TimeOApp: App {
    @StateObject private var appState = TimeOAppState()
    @State private var selectedMinutes = 30

    var body: some Scene {
        MenuBarExtra("TimeO", systemImage: "hourglass") {
            TimerMenuBarWindow(
                model: appState.model,
                selectedMinutes: $selectedMinutes
            )
        }
        .menuBarExtraStyle(.window)
    }
}

enum OverlayAppearanceMode: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

enum TimerDisplayStyle: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case flapClock = "Flap Clock"

    var id: String { rawValue }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case topLeading = "Top Left"
    case topCenter = "Top Center"
    case topTrailing = "Top Right"
    case bottomLeading = "Bottom Left"
    case bottomCenter = "Bottom Center"
    case bottomTrailing = "Bottom Right"

    var id: String { rawValue }
}

final class TimerModel: ObservableObject {
    @Published var remainingSeconds: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var appearanceMode: OverlayAppearanceMode = .automatic
    @Published var displayStyle: TimerDisplayStyle = .normal
    @Published var overlayPosition: OverlayPosition = .topCenter
    @Published var isOverlayHovered = false

    private var endDate: Date?
    private var timer: Timer?

    var formattedRemaining: String {
        let hours = remainingSeconds / 3_600
        let minutes = (remainingSeconds % 3_600) / 60
        let seconds = remainingSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var remainingProgress: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, Double(remainingSeconds) / Double(totalSeconds)))
    }

    func start(minutes: Int) {
        let clampedMinutes = max(1, min(minutes, 24 * 60))
        totalSeconds = clampedMinutes * 60
        remainingSeconds = totalSeconds
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
        isPaused = false
        scheduleTimer()
    }

    func startPreview(seconds: Int) {
        totalSeconds = max(1, seconds)
        remainingSeconds = max(0, seconds)
        isRunning = true
        isPaused = false
        timer?.invalidate()
    }

    func pause() {
        guard isRunning, !isPaused else { return }

        tick()
        timer?.invalidate()
        timer = nil
        endDate = nil
        isPaused = true
    }

    func resume() {
        guard isRunning, isPaused, remainingSeconds > 0 else { return }

        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isPaused = false
        scheduleTimer()
    }

    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingSeconds = 0
        totalSeconds = 0
        isRunning = false
        isPaused = false
        isOverlayHovered = false
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        guard !isPaused else {
            return
        }

        guard let endDate else {
            stop()
            return
        }

        let nextRemainingSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if remainingSeconds != nextRemainingSeconds {
            remainingSeconds = nextRemainingSeconds
        }
        if remainingSeconds == 0 {
            stop()
        }
    }
}

final class TimeOAppState: ObservableObject {
    let model = TimerModel()

    private var overlayController: OverlayController?
    private var screenObserver: NSObjectProtocol?

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        overlayController = OverlayController(model: model)
        configurePreviewModeIfNeeded()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.overlayController?.rebuildWindows()
        }
    }

    private func configurePreviewModeIfNeeded() {
        let arguments = CommandLine.arguments
        guard arguments.contains("--preview") else { return }

        if arguments.contains("--light") {
            model.appearanceMode = .light
        } else {
            model.appearanceMode = .dark
        }
        model.startPreview(seconds: 23 * 60 + 42)
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }
}

struct TimerMenuBarWindow: View {
    @ObservedObject var model: TimerModel
    @Binding var selectedMinutes: Int

    private let presets = [
        ("30M", 30),
        ("1H", 60),
        ("1.5H", 90),
        ("2H", 120)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TimeO")
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit TimeO")
            }

            Stepper(value: $selectedMinutes, in: 1...1_440, step: 1) {
                HStack {
                    Text("Minutes")
                    Spacer()
                    TextField("Minutes", value: $selectedMinutes, format: .number)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 8) {
                ForEach(presets, id: \.1) { preset in
                    Button(preset.0) {
                        selectedMinutes = preset.1
                        model.start(minutes: preset.1)
                    }
                    .controlSize(.small)
                }
            }

            Picker("Appearance", selection: $model.appearanceMode) {
                ForEach(OverlayAppearanceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Style", selection: $model.displayStyle) {
                ForEach(TimerDisplayStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Picker("Position", selection: $model.overlayPosition) {
                ForEach(OverlayPosition.allCases) { position in
                    Text(position.rawValue).tag(position)
                }
            }

            HStack(spacing: 10) {
                Button {
                    if model.isRunning {
                        model.togglePause()
                    } else {
                        model.start(minutes: selectedMinutes)
                    }
                } label: {
                    Label(primaryActionTitle, systemImage: primaryActionIcon)
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)

                Button(role: .destructive) {
                    model.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.isRunning)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(width: 330)
    }

    private var statusText: String {
        if model.isPaused {
            return "Paused at \(model.formattedRemaining)"
        }
        if model.isRunning {
            return model.formattedRemaining
        }
        return "Set a timer overlay"
    }

    private var primaryActionTitle: String {
        if model.isPaused {
            return "Resume"
        }
        return model.isRunning ? "Pause" : "Start"
    }

    private var primaryActionIcon: String {
        if model.isPaused {
            return "play.fill"
        }
        return model.isRunning ? "pause.fill" : "play.fill"
    }
}

final class OverlayController {
    private let model: TimerModel
    private var windows: [OverlayWindow] = []
    private var cancellables: Set<AnyCancellable> = []
    private var hoverTimer: Timer?

    init(model: TimerModel) {
        self.model = model
        rebuildWindows()
        startHoverTracking()

        model.$overlayPosition
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateWindowPositions()
            }
            .store(in: &cancellables)

        model.$displayStyle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateWindowPositions()
            }
            .store(in: &cancellables)

    }

    func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen, model: model)
            window.orderFrontRegardless()
            return window
        }
    }

    private func updateWindowPositions(animated: Bool = false) {
        windows.forEach { $0.updateFrame(animated: animated) }
    }

    private func startHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateHoverState()
        }
        if let hoverTimer {
            RunLoop.main.add(hoverTimer, forMode: .common)
        }
    }

    private func updateHoverState() {
        guard model.isRunning else {
            if model.isOverlayHovered {
                model.isOverlayHovered = false
            }
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let isHovered = windows.contains { $0.containsHoverPoint(mouseLocation) }
        if model.isOverlayHovered != isHovered {
            model.isOverlayHovered = isHovered
        }
    }

}

final class OverlayWindow: NSPanel {
    private let overlayScreen: NSScreen
    private let model: TimerModel

    init(screen: NSScreen, model: TimerModel) {
        self.overlayScreen = screen
        self.model = model

        let frame = OverlayWindow.overlayFrame(
            for: screen,
            position: model.overlayPosition,
            displayStyle: model.displayStyle
        )
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: TimerOverlayView(model: model))
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateFrame(animated: Bool = false) {
        let frame = OverlayWindow.overlayFrame(
            for: overlayScreen,
            position: model.overlayPosition,
            displayStyle: model.displayStyle
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true, animate: false)
        }
    }

    func containsHoverPoint(_ point: NSPoint) -> Bool {
        OverlayWindow.overlayFrame(
            for: overlayScreen,
            position: model.overlayPosition,
            displayStyle: model.displayStyle
        )
        .contains(point)
    }

    private static func overlayFrame(
        for screen: NSScreen,
        position: OverlayPosition,
        displayStyle: TimerDisplayStyle
    ) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let targetWidth: CGFloat = displayStyle == .flapClock ? 300 : 240
        let targetHeight: CGFloat = displayStyle == .flapClock ? 84 : 76
        let width: CGFloat = min(targetWidth, visibleFrame.width - 48)
        let height: CGFloat = targetHeight
        let inset: CGFloat = 4

        let x: CGFloat
        switch position {
        case .topLeading, .bottomLeading:
            x = visibleFrame.minX + inset
        case .topCenter, .bottomCenter:
            x = visibleFrame.midX - width / 2
        case .topTrailing, .bottomTrailing:
            x = visibleFrame.maxX - width - inset
        }

        let y: CGFloat
        switch position {
        case .topLeading, .topCenter, .topTrailing:
            y = visibleFrame.maxY - height - inset
        case .bottomLeading, .bottomCenter, .bottomTrailing:
            y = visibleFrame.minY + inset
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

struct TimerOverlayView: View {
    @ObservedObject var model: TimerModel
    @State private var overlayOpacity: Double = 1

    var body: some View {
        ZStack {
            if model.isRunning {
                Group {
                    switch model.displayStyle {
                    case .normal:
                        NormalTimerText(
                            text: model.formattedRemaining,
                            progress: model.remainingProgress,
                            appearanceMode: model.appearanceMode,
                            isHovered: model.isOverlayHovered
                        )
                    case .flapClock:
                        FlipFlapTimerText(
                            text: model.formattedRemaining,
                            appearanceMode: model.appearanceMode,
                            isHovered: model.isOverlayHovered
                        )
                    }
                }
                .opacity(overlayOpacity)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.24), value: model.isRunning)
        .onChange(of: model.isOverlayHovered) { isHovered in
            updateHiddenOffset(isHovered: isHovered)
        }
        .onChange(of: model.overlayPosition) { _ in
            updateHiddenOffset(isHovered: model.isOverlayHovered, animated: false)
        }
        .onChange(of: model.displayStyle) { _ in
            updateHiddenOffset(isHovered: model.isOverlayHovered, animated: false)
        }
        .allowsHitTesting(model.isRunning)
    }

    private func updateHiddenOffset(isHovered: Bool, animated: Bool = true) {
        guard animated else {
            overlayOpacity = isHovered ? 0 : 1
            return
        }

        withAnimation(.easeOut(duration: isHovered ? 0.08 : 0.12)) {
            overlayOpacity = isHovered ? 0 : 1
        }
    }
}

struct FlipFlapTimerText: View {
    let text: String
    let appearanceMode: OverlayAppearanceMode
    let isHovered: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var resolvedIsDark: Bool {
        switch appearanceMode {
        case .dark:
            true
        case .light:
            false
        case .automatic:
            colorScheme == .dark
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                if character == ":" {
                    FlipFlapSeparator(isDark: resolvedIsDark)
                } else {
                    FlipFlapCharacterCell(
                        character: character,
                        isDark: resolvedIsDark
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            FlapClockBackground(isDark: resolvedIsDark)
        }
        .flipsForRightToLeftLayoutDirection(false)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct FlipFlapSeparator: View {
    let isDark: Bool

    var body: some View {
        Text(":")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isDark ? Color(red: 0.72, green: 0.73, blue: 0.76) : Color(red: 0.18, green: 0.18, blue: 0.2))
            .frame(width: 8, height: 44)
    }
}

struct FlipFlapCharacterCell: View {
    let character: Character
    let isDark: Bool

    @State private var displayedCharacter: Character
    @State private var incomingCharacter: Character
    @State private var outgoingCharacter: Character
    @State private var isAnimating = false
    @State private var isTopLeafVisible = false
    @State private var isBottomLeafVisible = false
    @State private var topRotation: Double = 0
    @State private var bottomRotation: Double = 90
    @State private var topShadow: Double = 0
    @State private var bottomShadow: Double = 1
    @State private var animationID = UUID()

    private let width: CGFloat = 28
    private let height: CGFloat = 44
    private let halfFlipDuration = 0.14

    init(character: Character, isDark: Bool) {
        self.character = character
        self.isDark = isDark
        _displayedCharacter = State(initialValue: character)
        _incomingCharacter = State(initialValue: character)
        _outgoingCharacter = State(initialValue: character)
    }

    var body: some View {
        ZStack {
            FlipFlapStaticTile(
                topCharacter: isAnimating ? incomingCharacter : displayedCharacter,
                bottomCharacter: displayedCharacter,
                isDark: isDark,
                width: width,
                height: height
            )

            if isTopLeafVisible {
                FlipFlapFoldShadowOverlay(
                    half: .bottom,
                    isDark: isDark,
                    width: width,
                    height: height,
                    intensity: topShadow,
                    direction: .show
                )
                .offset(y: height / 4)
                .zIndex(2)
            }

            if isBottomLeafVisible {
                FlipFlapFoldShadowOverlay(
                    half: .top,
                    isDark: isDark,
                    width: width,
                    height: height,
                    intensity: bottomShadow,
                    direction: .hide
                )
                .offset(y: -height / 4)
                .zIndex(2)
            }

            if isTopLeafVisible {
                FlipFlapHalfTile(
                    character: outgoingCharacter,
                    half: .top,
                    isDark: isDark,
                    width: width,
                    height: height,
                    reflection: 0.08,
                    shade: 0.06,
                    foldShadow: topShadow,
                    foldShadowDirection: .show
                )
                .rotation3DEffect(
                    .degrees(topRotation),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.34
                )
                .offset(y: -height / 4)
                .zIndex(3)
            }

            if isBottomLeafVisible {
                FlipFlapHalfTile(
                    character: incomingCharacter,
                    half: .bottom,
                    isDark: isDark,
                    width: width,
                    height: height,
                    reflection: 0.08,
                    shade: 0.12,
                    foldShadow: bottomShadow,
                    foldShadowDirection: .hide
                )
                .rotation3DEffect(
                    .degrees(bottomRotation),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .top,
                    perspective: 0.34
                )
                .offset(y: height / 4)
                .zIndex(3)
            }

            if isAnimating {
                Rectangle()
                    .fill(.black.opacity(isDark ? 0.58 : 0.22))
                    .frame(width: width - 3, height: 1)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.white.opacity(isDark ? 0.08 : 0.36))
                            .frame(height: 1)
                            .offset(y: 1)
                    }
                    .zIndex(4)
            }
        }
        .frame(width: width, height: height)
        .onChange(of: character) { newCharacter in
            animate(to: newCharacter)
        }
    }

    private func animate(to newCharacter: Character) {
        if isAnimating {
            incomingCharacter = newCharacter
            return
        }

        guard newCharacter != displayedCharacter else {
            return
        }

        let currentAnimationID = UUID()
        animationID = currentAnimationID
        outgoingCharacter = displayedCharacter
        incomingCharacter = newCharacter
        isAnimating = true
        isTopLeafVisible = true
        isBottomLeafVisible = false
        topRotation = 0
        bottomRotation = 90
        topShadow = 0
        bottomShadow = 1

        withAnimation(.timingCurve(0.42, 0.0, 1.0, 1.0, duration: halfFlipDuration)) {
            topRotation = -90
            topShadow = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + halfFlipDuration) {
            guard animationID == currentAnimationID else {
                return
            }
            isTopLeafVisible = false
            isBottomLeafVisible = true
            bottomRotation = 90
            bottomShadow = 1

            withAnimation(.timingCurve(0.0, 0.0, 0.18, 1.0, duration: halfFlipDuration)) {
                bottomRotation = 0
                bottomShadow = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (halfFlipDuration * 2)) {
            guard animationID == currentAnimationID else {
                return
            }
            displayedCharacter = newCharacter
            isAnimating = false
            isTopLeafVisible = false
            isBottomLeafVisible = false
            topRotation = 0
            bottomRotation = 90
            topShadow = 0
            bottomShadow = 1
        }
    }
}

enum FlipFlapHalf {
    case top
    case bottom
}

struct FlipFlapStaticTile: View {
    let topCharacter: Character
    let bottomCharacter: Character
    let isDark: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isDark ? Color(red: 0.055, green: 0.056, blue: 0.063) : Color(red: 0.84, green: 0.85, blue: 0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isDark ? 0.12 : 0.62),
                                    .black.opacity(isDark ? 0.42 : 0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }

            VStack(spacing: 0) {
                FlipFlapHalfTile(
                    character: topCharacter,
                    half: .top,
                    isDark: isDark,
                    width: width,
                    height: height,
                    reflection: 0.1,
                    shade: 0.06
                )
                FlipFlapHalfTile(
                    character: bottomCharacter,
                    half: .bottom,
                    isDark: isDark,
                    width: width,
                    height: height,
                    reflection: 0.06,
                    shade: 0.14
                )
            }

            Rectangle()
                .fill(.black.opacity(isDark ? 0.52 : 0.22))
                .frame(height: 1)

            Rectangle()
                .fill(.white.opacity(isDark ? 0.05 : 0.46))
                .frame(height: 1)
                .offset(y: 1)

            HStack {
                Circle()
                    .fill(.black.opacity(isDark ? 0.62 : 0.25))
                    .frame(width: 2, height: 2)
                Spacer()
                Circle()
                    .fill(.black.opacity(isDark ? 0.62 : 0.25))
                    .frame(width: 2, height: 2)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width, height: height)
    }
}

struct FlipFlapHalfTile: View {
    let character: Character
    let half: FlipFlapHalf
    let isDark: Bool
    let width: CGFloat
    let height: CGFloat
    let reflection: Double
    let shade: Double
    var foldShadow: Double = 0
    var foldShadowDirection: FlipFlapFoldShadowDirection = .none

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: baseColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    LinearGradient(
                        colors: [
                            .white.opacity(reflection),
                            .white.opacity(reflection * 0.2),
                            .clear,
                            .black.opacity(shade)
                        ],
                        startPoint: half == .top ? .top : .bottom,
                        endPoint: half == .top ? .bottom : .top
                    )
                }
                .overlay(alignment: half == .top ? .bottom : .top) {
                    Rectangle()
                        .fill(.black.opacity(isDark ? 0.34 : 0.14))
                        .frame(height: 1)
                }

            Text(String(character))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isDark ? Color(red: 0.8, green: 0.81, blue: 0.84) : Color(red: 0.12, green: 0.12, blue: 0.14))
                .frame(width: width, height: height)
                .offset(y: half == .top ? height / 4 : -height / 4)

            FlipFlapFoldShadowOverlay(
                half: half,
                isDark: isDark,
                width: width,
                height: height,
                intensity: foldShadow,
                direction: foldShadowDirection
            )
        }
        .frame(width: width, height: height / 2)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: half == .top ? 5 : 0,
                bottomLeadingRadius: half == .bottom ? 5 : 0,
                bottomTrailingRadius: half == .bottom ? 5 : 0,
                topTrailingRadius: half == .top ? 5 : 0,
                style: .continuous
            )
        )
        .clipped()
    }

    private var baseColors: [Color] {
        if isDark {
            return half == .top
                ? [
                    Color(red: 0.105, green: 0.107, blue: 0.118),
                    Color(red: 0.052, green: 0.053, blue: 0.06)
                ]
                : [
                    Color(red: 0.032, green: 0.033, blue: 0.039),
                    Color(red: 0.085, green: 0.087, blue: 0.098)
                ]
        }

        return half == .top
            ? [
                Color(red: 0.91, green: 0.92, blue: 0.95),
                Color(red: 0.72, green: 0.73, blue: 0.78)
            ]
            : [
                Color(red: 0.66, green: 0.67, blue: 0.72),
                Color(red: 0.86, green: 0.87, blue: 0.9)
            ]
    }

}

enum FlipFlapFoldShadowDirection {
    case none
    case show
    case hide
}

struct FlipFlapFoldShadowOverlay: View {
    let half: FlipFlapHalf
    let isDark: Bool
    let width: CGFloat
    let height: CGFloat
    let intensity: Double
    let direction: FlipFlapFoldShadowDirection

    var body: some View {
        LinearGradient(
            colors: shadowColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(direction == .none ? 0 : min(max(intensity, 0), 1))
        .frame(width: width, height: height / 2)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: half == .top ? 5 : 0,
                bottomLeadingRadius: half == .bottom ? 5 : 0,
                bottomTrailingRadius: half == .bottom ? 5 : 0,
                topTrailingRadius: half == .top ? 5 : 0,
                style: .continuous
            )
        )
        .allowsHitTesting(false)
    }

    private var shadowColors: [Color] {
        let strong = isDark ? 0.98 : 0.72
        let mid = isDark ? 0.56 : 0.36
        let weak = isDark ? 0.16 : 0.08

        switch direction {
        case .none:
            return [.clear, .clear]
        case .show:
            return [
                .black.opacity(weak),
                .black.opacity(mid),
                .black.opacity(strong)
            ]
        case .hide:
            return [
                .black.opacity(strong),
                .black.opacity(mid),
                .black.opacity(weak)
            ]
        }
    }
}

/// Shared rounded-rect HUD background used by both the Normal and Flap Clock styles.
struct FlapClockBackground: View {
    let isDark: Bool

    private let cornerRadius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .background {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [
                                    Color.black.opacity(0.00),
                                    Color.black.opacity(0.10)
                                ]
                                : [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.00)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.04),
                                .white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
    }
}

struct NormalTimerText: View {
    let text: String
    let progress: Double
    let appearanceMode: OverlayAppearanceMode
    let isHovered: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// #ddd
    private let textColor = Color(white: 0.867)

    private var resolvedIsDark: Bool {
        switch appearanceMode {
        case .dark:
            true
        case .light:
            false
        case .automatic:
            colorScheme == .dark
        }
    }

    var body: some View {
        TimerSurface(isHovered: isHovered) { _ in
            HStack(spacing: 10) {
                GlassProgressRing(
                    progress: progress,
                    size: 30,
                    color: textColor
                )

                Text(text)
                    .font(.system(size: 40, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(height: 48)
                    .offset(y: -1)
            }
            .padding(.leading, 14)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
        } background: { _ in
            FlapClockBackground(isDark: resolvedIsDark)
        }
        .flipsForRightToLeftLayoutDirection(false)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct GlassProgressRing: View {
    let progress: Double
    let size: CGFloat
    let color: Color

    private let lineWidth: CGFloat = 5

    private var clampedProgress: Double {
        max(0, min(1, progress))
    }

    private var progressColor: Color {
        color
    }

    private var trackColor: Color {
        color.opacity(0.4)
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    trackColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions[VerticalAlignment.center]
        }
        .animation(.easeOut(duration: 0.18), value: clampedProgress)
        .accessibilityHidden(true)
    }
}

struct TimerSurface<Content: View, Background: View>: View {
    let isHovered: Bool
    let content: (Bool) -> Content
    let background: (Bool) -> Background

    var body: some View {
        content(isHovered)
            .background {
                background(isHovered)
            }
            .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
