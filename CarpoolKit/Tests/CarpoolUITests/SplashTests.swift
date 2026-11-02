import SwiftUI
import Testing
@testable import CarpoolUI

@MainActor
@Suite("Splash-Ablauf")
struct SplashTimelineTests {
    private let timeline = SplashTimeline.full

    @Test("Start: mittlerer Schlüssel oben und unsichtbar, Titel verborgen")
    func start() {
        let pose = timeline.value(time: 0)
        #expect(pose.middleDrop < -300)
        #expect(pose.middleOpacity == 0)
        #expect(pose.titleOpacity == 0)
    }

    @Test("Nach der Landung hängt der Schlüssel am Haken, Titel noch verborgen")
    func landed() {
        let pose = timeline.value(time: SplashTimeline.landing)
        #expect(abs(pose.middleDrop) < 1)
        #expect(pose.titleOpacity == 0)
    }

    @Test("Pendeln stößt beide Nachbarn an")
    func nudgesNeighbours() {
        let samples = stride(from: 0, through: timeline.duration, by: 0.02).map { timeline.value(time: $0) }
        #expect(samples.map(\.middleAngle).max()! > 5)
        #expect(samples.map(\.leftAngle).max()! > 2)
        #expect(samples.map(\.rightAngle).min()! < -1.5)
    }

    @Test("Ende: Endstand, Ablauf unter 2 s")
    func end() {
        let pose = timeline.value(time: timeline.duration)
        #expect(abs(pose.middleAngle) < 0.5 && abs(pose.leftAngle) < 0.5 && abs(pose.rightAngle) < 0.5)
        #expect(pose.titleOpacity == 1 && abs(pose.titleOffset) < 0.5)
        #expect(timeline.duration < 2)
    }

    @Test("Bewegung reduzieren: nichts bewegt sich, nur der Titel blendet ein")
    func reduced() {
        let reduced = SplashTimeline.reduced
        #expect(reduced.value(time: 0).middleDrop == 0)
        #expect(reduced.value(time: reduced.duration) == .rest)
        #expect(reduced.duration < 0.3)
    }
}
