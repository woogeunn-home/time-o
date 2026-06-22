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
                selectedMinutes: $selectedMinutes,
                onTogglePathDemo: { appState.toggleTimesUp() }
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

enum OverlayPosition: String, CaseIterable, Identifiable {
    case topLeading = "Top Left"
    case topCenter = "Top Center"
    case topTrailing = "Top Right"
    case bottomLeading = "Bottom Left"
    case bottomCenter = "Bottom Center"
    case bottomTrailing = "Bottom Right"

    static let allCases: [OverlayPosition] = [
        .topCenter,
        .topTrailing,
        .bottomCenter,
        .bottomTrailing
    ]

    var id: String { rawValue }
}

final class TimerModel: ObservableObject {
    @Published var remainingSeconds: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var appearanceMode: OverlayAppearanceMode = .automatic
    @Published var overlayPosition: OverlayPosition = .topCenter
    @Published var isOverlayHovered = false
    @Published var isFinished = false

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
        isFinished = false
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
        isFinished = false
    }

    /// Timer reached zero: keep the overlay on screen showing "Time Out!" until
    /// the user dismisses it, instead of clearing it like `stop()`.
    private func finish() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingSeconds = 0
        isRunning = false
        isPaused = false
        isOverlayHovered = false
        isFinished = true
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
            finish()
        }
    }
}

final class TimeOAppState: ObservableObject {
    let model = TimerModel()

    private var overlayController: OverlayController?
    private var screenObserver: NSObjectProtocol?

    /// Debug: flip the "Time's Up" state on/off without waiting for a timer.
    func toggleTimesUp() {
        model.isFinished.toggle()
    }

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
    var onTogglePathDemo: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var isCustomMinutesPresented = false
    @State private var customMinutesText = ""
    @FocusState private var isCustomMinutesFocused: Bool

    private let contentWidth: CGFloat = 320
    private let contentHeight: CGFloat = 258
    private let contentPadding: CGFloat = 12
    private let settingControlWidth: CGFloat = 190

    private let presets = [
        ("30m", 30),
        ("60m", 60),
        ("90m", 90),
        ("120m", 120)
    ]

    var body: some View {
        timerContent
        .padding(contentPadding)
        .frame(
            width: contentWidth + contentPadding * 2,
            height: contentHeight + contentPadding * 2,
            alignment: .top
        )
    }

    @ViewBuilder
    private var timerContent: some View {
        VStack(spacing: 10) {
            header

            if model.isRunning {
                runningControls
            } else {
                presetControls
            }

            Divider()

            settingRow(title: "Mood") {
                Picker("Mood", selection: $model.appearanceMode) {
                    ForEach(OverlayAppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
            }

            settingRow(title: "Position") {
                Picker("Position", selection: $model.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.rawValue).tag(position)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.regular)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("TimeO")
                .font(.headline)

            Spacer()

            iconButton(systemName: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var presetControls: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(presets[(row * 2)..<(row * 2 + 2)], id: \.1) { preset in
                        menuButton(maxWidth: .infinity) {
                            Text(preset.0)
                        } action: {
                            startTimer(minutes: preset.1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if isCustomMinutesPresented {
                TextField("", text: $customMinutesText)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .focused($isCustomMinutesFocused)
                    .onSubmit(startCustomMinutes)
                    .onChange(of: customMinutesText) { value in
                        customMinutesText = value.filter(\.isNumber)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            isCustomMinutesFocused = true
                        }
                    }
            } else {
                menuButton(maxWidth: .infinity) {
                    Image(systemName: "plus")
                } action: {
                    customMinutesText = ""
                    isCustomMinutesPresented = true
                }
            }
        }
        .frame(width: contentWidth)
    }

    private var runningControls: some View {
        HStack(spacing: 8) {
            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            menuButton(maxWidth: .infinity) {
                Image(systemName: "stop.fill")
            } action: {
                model.stop()
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: contentWidth)
    }

    private func settingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .frame(width: 86, alignment: .leading)

            Spacer(minLength: 16)

            content()
                .frame(width: settingControlWidth, alignment: .trailing)
        }
        .frame(width: contentWidth)
    }

    private func menuButton<Content: View>(
        maxWidth: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: maxWidth)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.borderless)
    }

    private func startCustomMinutes() {
        guard let minutes = Int(customMinutesText), minutes > 0 else {
            return
        }
        let clampedMinutes = min(minutes, 1_440)
        isCustomMinutesPresented = false
        startTimer(minutes: clampedMinutes)
    }

    private func startTimer(minutes: Int) {
        selectedMinutes = minutes
        model.start(minutes: minutes)
        dismiss()
    }
}

final class OverlayController {
    private let model: TimerModel
    private var windows: [OverlayWindow] = []
    private var cancellables: Set<AnyCancellable> = []
    private var hoverTimer: Timer?
    private let traveling = TravelingTimeOutController()

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

        model.$remainingSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateWindowPositions()
            }
            .store(in: &cancellables)

        // On finish, carry the "Time's Up" capsule around the screen edge.
        model.$isFinished
            .receive(on: RunLoop.main)
            .sink { [weak self] finished in
                guard let self else { return }
                if finished, let screen = NSScreen.main ?? NSScreen.screens.first {
                    self.traveling.play(on: screen, model: self.model)
                } else if !finished {
                    self.traveling.stop()
                }
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
            text: model.formattedRemaining
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
            text: model.formattedRemaining
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
            text: model.formattedRemaining
        )
        .contains(point)
    }

    private static func overlayFrame(
        for screen: NSScreen,
        position: OverlayPosition,
        text: String
    ) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let isCornerPosition: Bool
        switch position {
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            isCornerPosition = true
        case .topCenter, .bottomCenter:
            isCornerPosition = false
        }

        let targetWidth: CGFloat = isCornerPosition ? 220 : centerOverlayWidth(for: text)
        let targetHeight: CGFloat = isCornerPosition ? 220 : 76
        let width: CGFloat = min(targetWidth, visibleFrame.width - 48)
        let height: CGFloat = min(targetHeight, visibleFrame.height - 48)
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

    private static func centerOverlayWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 40, weight: .semibold)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return max(240, textWidth + 48)
    }
}

struct TimerOverlayView: View {
    @ObservedObject var model: TimerModel
    @State private var overlayOpacity: Double = 1

    var body: some View {
        ZStack {
            if model.isRunning {
                NormalTimerText(
                    text: model.formattedRemaining,
                    appearanceMode: model.appearanceMode,
                    overlayPosition: model.overlayPosition,
                    isHovered: model.isOverlayHovered
                )
                .opacity(overlayOpacity)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
        .animation(.easeOut(duration: 0.24), value: model.isRunning)
        .onChange(of: model.isOverlayHovered) { isHovered in
            updateHiddenOffset(isHovered: isHovered)
        }
        .onChange(of: model.overlayPosition) { _ in
            updateHiddenOffset(isHovered: model.isOverlayHovered, animated: false)
        }
        .allowsHitTesting(model.isRunning)
    }

    /// Hug the overlay content to the active corner so the gap to the touching
    /// screen edges matches the window inset on every side.
    private var contentAlignment: Alignment {
        switch model.overlayPosition {
        case .topLeading: return .topLeading
        case .topCenter: return .top
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
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
            FlapClockBackground(
                isDark: resolvedIsDark,
                shape: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .flipsForRightToLeftLayoutDirection(false)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct FlipFlapSeparator: View {
    let isDark: Bool

    var body: some View {
        Text(":")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isDark ? Color(red: 0.72, green: 0.73, blue: 0.76) : Color(red: 0.18, green: 0.18, blue: 0.2))
            .frame(width: 10, height: 52)
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

    private let width: CGFloat = 33
    private let height: CGFloat = 52
    private let halfFlipDuration = 0.14

    /// The shadow the moving leaf casts onto the static half it covers. Kept
    /// gentle in light mode so the still-readable old digit doesn't appear to
    /// abruptly change color.
    private var castShadowScale: Double {
        isDark ? 1.0 : 0.4
    }

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
                    intensity: topShadow * castShadowScale,
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
                    intensity: bottomShadow * castShadowScale,
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
                .font(.system(size: 35, weight: .semibold, design: .rounded))
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
        let strong = isDark ? 0.98 : 0.26
        let mid = isDark ? 0.56 : 0.12
        let weak = isDark ? 0.16 : 0.03

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

/// Shared HUD background used by both the Normal and Flap Clock styles.
/// The clip/stroke shape is supplied by the caller (capsule for Normal,
/// rounded rectangle for Flap Clock).
struct FlapClockBackground<ContainerShape: InsettableShape>: View {
    let isDark: Bool
    let shape: ContainerShape

    var body: some View {
        shape
            .fill(.clear)
            .background {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [
                                    Color.black.opacity(0.20),
                                    Color.black.opacity(0.26)
                                ]
                                : [
                                    Color.white.opacity(0.46),
                                    Color.white.opacity(0.40)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                shape
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
    let appearanceMode: OverlayAppearanceMode
    let overlayPosition: OverlayPosition
    let isHovered: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// #ddd in dark, #222 in light.
    private var textColor: Color {
        resolvedIsDark ? Color(white: 0.867) : Color(white: 0.133)
    }

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
            Group {
                if isCornerPosition {
                    cornerBody
                } else {
                    centerBody
                }
            }
        } background: { _ in
            Group {
                if isCornerPosition {
                    TimerCornerBackground(
                        isDark: resolvedIsDark,
                        position: overlayPosition,
                        contentLength: cornerSegmentLength
                    )
                } else {
                    FlapClockBackground(isDark: resolvedIsDark, shape: Capsule(style: .continuous))
                }
            }
        }
        .frame(width: isCornerPosition ? 220 : nil, height: isCornerPosition ? 220 : 68)
        .flipsForRightToLeftLayoutDirection(false)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var isCornerPosition: Bool {
        switch overlayPosition {
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            true
        case .topCenter, .bottomCenter:
            false
        }
    }

    private var centerBody: some View {
        timerText
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(minWidth: 168)
    }

    private var cornerBody: some View {
        GeometryReader { geometry in
            let path = TimerCornerPath(position: overlayPosition, rect: CGRect(origin: .zero, size: geometry.size))
            let layout = cornerGlyphLayout()
            let start = path.cornerDistance - layout.total / 2

            ZStack {
                ForEach(layout.glyphs) { item in
                    let placement = path.locate(start + item.center)
                    Text(String(item.character))
                        .font(.system(size: 40, weight: .semibold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(textColor)
                        .fixedSize()
                        .rotationEffect(.radians(Double(readableCornerAngle(placement.angle))))
                        .position(placement.point)
                }
            }
        }
    }

    private func readableCornerAngle(_ angle: CGFloat) -> CGFloat {
        overlayPosition == .topLeading ? angle + .pi : angle
    }

    private var cornerSegmentLength: CGFloat {
        max(72, cornerGlyphLayout().total - 16)
    }

    private var timerText: some View {
        Text(text)
            .font(.system(size: 40, weight: .semibold, design: .default))
            .monospacedDigit()
            .foregroundStyle(textColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .frame(height: 48)
            .offset(y: -1)
    }

    private func cornerGlyphLayout() -> CornerTimerGlyphLayout {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 40, weight: .semibold)
        var cursor: CGFloat = 0
        let glyphs = text.enumerated().map { index, character in
            let advance = (String(character) as NSString).size(withAttributes: [.font: font]).width
            defer { cursor += advance }
            return CornerTimerGlyph(id: index, character: character, center: cursor + advance / 2)
        }
        return CornerTimerGlyphLayout(glyphs: glyphs, total: cursor)
    }
}

private struct CornerTimerGlyph: Identifiable {
    let id: Int
    let character: Character
    let center: CGFloat
}

private struct CornerTimerGlyphLayout {
    let glyphs: [CornerTimerGlyph]
    let total: CGFloat
}

struct TimerCornerBackground: View {
    let isDark: Bool
    let position: OverlayPosition
    let contentLength: CGFloat

    private var shape: TimerCornerShape {
        TimerCornerShape(position: position, contentLength: contentLength)
    }

    var body: some View {
        shape
            .fill(.clear)
            .background {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [
                                    Color.black.opacity(0.20),
                                    Color.black.opacity(0.26)
                                ]
                                : [
                                    Color.white.opacity(0.46),
                                    Color.white.opacity(0.40)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                shape
                    .stroke(
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

struct TimerCornerShape: Shape {
    let position: OverlayPosition
    let contentLength: CGFloat

    func path(in rect: CGRect) -> Path {
        TimerCornerPath(position: position, rect: rect)
            .segmentPath(length: contentLength)
            .strokedPath(
                StrokeStyle(
                    lineWidth: TimerCornerPath.lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
    }
}

private struct TimerCornerPath {
    static let lineWidth: CGFloat = 60

    let position: OverlayPosition
    let rect: CGRect

    private var inset: CGFloat { Self.lineWidth / 2 }
    private var bendRadius: CGFloat { 80 }
    private var minX: CGFloat { rect.minX + inset }
    private var maxX: CGFloat { rect.maxX - inset }
    private var minY: CGFloat { rect.minY + inset }
    private var maxY: CGFloat { rect.maxY - inset }
    private var lineA: CGFloat { max(0, maxX - minX - bendRadius) }
    private var lineB: CGFloat { max(0, maxY - minY - bendRadius) }
    private var arcLength: CGFloat { bendRadius * .pi / 2 }
    private var total: CGFloat { max(1, lineA + arcLength + lineB) }
    var cornerDistance: CGFloat { lineA + arcLength / 2 }

    func segmentPath(length: CGFloat) -> Path {
        let start = max(0, cornerDistance - length / 2)
        let end = min(total, cornerDistance + length / 2)
        let segmentLength = max(0, end - start)
        let steps = max(2, Int(segmentLength / 5))

        var path = Path()
        for index in 0...steps {
            let distance = start + segmentLength * CGFloat(index) / CGFloat(steps)
            let point = locate(distance).point
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    func path() -> Path {
        var path = Path()
        switch position {
        case .topTrailing:
            path.move(to: CGPoint(x: minX, y: minY))
            path.addLine(to: CGPoint(x: maxX - bendRadius, y: minY))
            path.addArc(center: CGPoint(x: maxX - bendRadius, y: minY + bendRadius), radius: bendRadius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: maxX, y: maxY))
        case .topLeading:
            path.move(to: CGPoint(x: maxX, y: minY))
            path.addLine(to: CGPoint(x: minX + bendRadius, y: minY))
            path.addArc(center: CGPoint(x: minX + bendRadius, y: minY + bendRadius), radius: bendRadius, startAngle: .degrees(-90), endAngle: .degrees(-180), clockwise: true)
            path.addLine(to: CGPoint(x: minX, y: maxY))
        case .bottomTrailing:
            path.move(to: CGPoint(x: minX, y: maxY))
            path.addLine(to: CGPoint(x: maxX - bendRadius, y: maxY))
            path.addArc(center: CGPoint(x: maxX - bendRadius, y: maxY - bendRadius), radius: bendRadius, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
            path.addLine(to: CGPoint(x: maxX, y: minY))
        case .bottomLeading:
            path.move(to: CGPoint(x: maxX, y: maxY))
            path.addLine(to: CGPoint(x: minX + bendRadius, y: maxY))
            path.addArc(center: CGPoint(x: minX + bendRadius, y: maxY - bendRadius), radius: bendRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: minX, y: minY))
        case .topCenter, .bottomCenter:
            path.move(to: CGPoint(x: minX, y: rect.midY))
            path.addLine(to: CGPoint(x: maxX, y: rect.midY))
        }
        return path
    }

    func locate(_ rawDistance: CGFloat) -> (point: CGPoint, angle: CGFloat) {
        let distance = min(max(0, rawDistance), total)

        if distance <= lineA {
            return locateOnFirstLine(distance)
        }
        if distance <= lineA + arcLength {
            return locateOnArc(distance - lineA)
        }
        return locateOnSecondLine(distance - lineA - arcLength)
    }

    private func locateOnFirstLine(_ distance: CGFloat) -> (point: CGPoint, angle: CGFloat) {
        switch position {
        case .topTrailing:
            return (CGPoint(x: minX + distance, y: minY), 0)
        case .topLeading:
            return (CGPoint(x: maxX - distance, y: minY), .pi)
        case .bottomTrailing:
            return (CGPoint(x: minX + distance, y: maxY), 0)
        case .bottomLeading:
            return (CGPoint(x: maxX - distance, y: maxY), .pi)
        case .topCenter, .bottomCenter:
            return (CGPoint(x: minX + distance, y: rect.midY), 0)
        }
    }

    private func locateOnArc(_ distance: CGFloat) -> (point: CGPoint, angle: CGFloat) {
        let progress = distance / bendRadius
        switch position {
        case .topTrailing:
            let angle = -.pi / 2 + progress
            return arcPlacement(center: CGPoint(x: maxX - bendRadius, y: minY + bendRadius), angle: angle, tangent: angle + .pi / 2)
        case .topLeading:
            let angle = -.pi / 2 - progress
            return arcPlacement(center: CGPoint(x: minX + bendRadius, y: minY + bendRadius), angle: angle, tangent: angle - .pi / 2)
        case .bottomTrailing:
            let angle = .pi / 2 - progress
            return arcPlacement(center: CGPoint(x: maxX - bendRadius, y: maxY - bendRadius), angle: angle, tangent: angle - .pi / 2)
        case .bottomLeading:
            let angle = .pi / 2 + progress
            return arcPlacement(center: CGPoint(x: minX + bendRadius, y: maxY - bendRadius), angle: angle, tangent: angle + .pi / 2)
        case .topCenter, .bottomCenter:
            return locateOnFirstLine(distance)
        }
    }

    private func locateOnSecondLine(_ distance: CGFloat) -> (point: CGPoint, angle: CGFloat) {
        switch position {
        case .topTrailing:
            return (CGPoint(x: maxX, y: minY + bendRadius + distance), .pi / 2)
        case .topLeading:
            return (CGPoint(x: minX, y: minY + bendRadius + distance), -.pi / 2)
        case .bottomTrailing:
            return (CGPoint(x: maxX, y: maxY - bendRadius - distance), -.pi / 2)
        case .bottomLeading:
            return (CGPoint(x: minX, y: maxY - bendRadius - distance), .pi / 2)
        case .topCenter, .bottomCenter:
            return locateOnFirstLine(distance)
        }
    }

    private func arcPlacement(center: CGPoint, angle: CGFloat, tangent: CGFloat) -> (point: CGPoint, angle: CGFloat) {
        (
            CGPoint(
                x: center.x + bendRadius * cos(angle),
                y: center.y + bendRadius * sin(angle)
            ),
            tangent
        )
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
