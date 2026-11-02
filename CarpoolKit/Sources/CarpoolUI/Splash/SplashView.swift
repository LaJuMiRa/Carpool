import SwiftUI

/// Stand des Splashs zu einem Zeitpunkt. Winkel in Grad, positiv = im Uhrzeigersinn um den Haken.
public struct SplashPose: Equatable, Sendable {
    public var middleDrop: CGFloat
    public var middleOpacity: Double
    public var middleAngle: Double
    public var leftAngle: Double
    public var rightAngle: Double
    public var titleOpacity: Double
    public var titleOffset: CGFloat

    /// Endstand: alle Schlüssel hängen, Titel steht.
    public static let rest = SplashPose(middleDrop: 0, middleOpacity: 1, middleAngle: 0, leftAngle: 0,
                                        rightAngle: 0, titleOpacity: 1, titleOffset: 0)
}

/// Ablauf F01: Brett und äußere Schlüssel stehen; der mittlere Schlüssel fliegt von oben auf den
/// freien Haken, pendelt gedämpft aus (bounce 0.3) und stößt die Nachbarn kurz an; danach steigt
/// „Carpool" 8 pt auf (250 ms).
@MainActor
public enum SplashTimeline {
    /// Ab hier hängt der Schlüssel (Haptik).
    public nonisolated static let landing: TimeInterval = 0.5
    /// Nach dem Titel kurz stehen lassen, dann ausblenden.
    public nonisolated static let hold: TimeInterval = 0.45

    private static let start = SplashPose(middleDrop: -360, middleOpacity: 0, middleAngle: 0, leftAngle: 0,
                                          rightAngle: 0, titleOpacity: 0, titleOffset: 8)
    private static let swing = Spring(duration: 0.24, bounce: 0)
    private static let settle = Spring(duration: 0.3, bounce: 0.3)

    public static let full = KeyframeTimeline(initialValue: start) {
        KeyframeTrack(\.middleDrop) {
            LinearKeyframe(-360, duration: 0.05)
            SpringKeyframe(0, duration: landing - 0.05, spring: Spring(duration: 0.3, bounce: 0))
        }
        KeyframeTrack(\.middleOpacity) {
            LinearKeyframe(1, duration: 0.12)
        }
        KeyframeTrack(\.middleAngle) {
            LinearKeyframe(0, duration: landing)
            SpringKeyframe(10, duration: 0.16, spring: swing)
            SpringKeyframe(-7, duration: 0.24, spring: swing)
            SpringKeyframe(4, duration: 0.22, spring: swing)
            SpringKeyframe(-2, duration: 0.2, spring: swing)
            SpringKeyframe(0, duration: 0.3, spring: settle)
        }
        // Erster Ausschlag nach links (Uhrzeigersinn) stößt den linken Schlüssel an, der zweite den rechten.
        KeyframeTrack(\.leftAngle) {
            LinearKeyframe(0, duration: landing + 0.1)
            SpringKeyframe(4, duration: 0.12, spring: swing)
            SpringKeyframe(0, duration: 0.5, spring: settle)
        }
        KeyframeTrack(\.rightAngle) {
            LinearKeyframe(0, duration: landing + 0.32)
            SpringKeyframe(-3, duration: 0.12, spring: swing)
            SpringKeyframe(0, duration: 0.5, spring: settle)
        }
        KeyframeTrack(\.titleOpacity) {
            LinearKeyframe(0, duration: 1.35)
            CubicKeyframe(1, duration: 0.25)
        }
        KeyframeTrack(\.titleOffset) {
            LinearKeyframe(8, duration: 1.35)
            SpringKeyframe(0, duration: 0.35, spring: Spring(duration: 0.2, bounce: 0))
        }
    }

    /// „Bewegung reduzieren": alles steht, nur der Titel blendet kurz ein.
    public static let reduced = KeyframeTimeline(initialValue: SplashPose.rest) {
        KeyframeTrack(\.titleOpacity) {
            LinearKeyframe(0, duration: 0.01)
            LinearKeyframe(1, duration: 0.15)
        }
    }
}

/// Splash (F01). Läuft einmal durch und meldet sich dann mit `onFinish`; Tippen überspringt.
public struct SplashView: View {
    private let hold: TimeInterval
    private let onFinish: () -> Void
    @State private var startDate: Date?
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// - Parameter hold: wie lange der Endstand stehen bleibt, bevor `onFinish` kommt.
    public init(hold: TimeInterval = SplashTimeline.hold, onFinish: @escaping () -> Void) {
        self.hold = hold
        self.onFinish = onFinish
    }

    private var timeline: KeyframeTimeline<SplashPose> {
        reduceMotion || voiceOver ? SplashTimeline.reduced : SplashTimeline.full
    }

    public var body: some View {
        TimelineView(.animation(paused: startDate == nil)) { context in
            let elapsed = startDate.map { context.date.timeIntervalSince($0) } ?? 0
            SplashContent(pose: timeline.value(time: min(elapsed, timeline.duration)))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carpool")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tippen überspringt")
        .accessibilityIdentifier("splash")
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
        .task { await run() }
    }

    private func run() async {
        startDate = .now
        let showsKey = timeline.duration > SplashTimeline.landing
        if showsKey {
            try? await Task.sleep(for: .seconds(SplashTimeline.landing))
            landed = true
        }
        let rest = timeline.duration + hold - (showsKey ? SplashTimeline.landing : 0)
        try? await Task.sleep(for: .seconds(rest))
        if !Task.isCancelled { onFinish() }
    }
}

/// Unbewegte Darstellung eines Standes (für Vorschau und Tests).
public struct SplashContent: View {
    private let pose: SplashPose

    public init(pose: SplashPose = .rest) {
        self.pose = pose
    }

    public var body: some View {
        VStack(spacing: 72) {
            KeyBoardScene(pose: pose)
            Text("Carpool")
                .font(.system(size: 44, weight: .bold))
                .kerning(-1)
                .foregroundStyle(Color.ink)
                .opacity(pose.titleOpacity)
                .offset(y: pose.titleOffset)
        }
        .offset(y: -24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }
}

#Preview("Splash") {
    SplashView {}
}

#Preview("Endstand") {
    SplashContent()
}
