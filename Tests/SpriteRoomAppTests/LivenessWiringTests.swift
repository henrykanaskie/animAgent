import Foundation
import SpriteKit
import Testing

@testable import SpriteRoomApp
@testable import SpriteRoomCore
@testable import SpriteRoomScene

/// The one wire between a proved fact and a drawn pixel.
///
/// `LivenessLampTests` covers what the lamp draws; `LivenessTests` covers what
/// makes it beat. This covers the join, and specifically the distinction that
/// keeps `--render` honest: **no lamp** means this run has nothing to answer
/// for, a **dark** lamp means we asked and nothing answered. [ADR-004 §6]
///
/// It asserts on node presence and phase only, never on pixels, so it needs the
/// manifest — which is committed — and not the art, which is not.
@MainActor
@Suite struct LivenessWiringTests {

    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func binding() throws -> SceneBinding {
        let manifest = try Manifest.load(root: Manifest.developmentRoot())
        return SceneBinding(
            manifest: manifest, themeID: nil, viewport: CGSize(width: 720, height: 400))
    }

    /// A replay, a render, a capture: no bound port, nothing receiving, and
    /// therefore nothing true to draw. [I1]
    @Test func aRunWithNoListenerDrawsNoLampAtAll() throws {
        let binding = try binding()
        binding.showLiveness(nil, at: Self.epoch)
        #expect(binding.lampPhase == nil)
        #expect(binding.scene.camera?.children.isEmpty == true)
    }

    @Test func aBoundListenerPutsALampOnTheFrame() throws {
        let binding = try binding()
        binding.showLiveness(
            Liveness(beats: 4, lastBeatAt: Self.epoch),
            at: Self.epoch.addingTimeInterval(0.4))
        #expect(binding.lampPhase == .lit)
        #expect(binding.scene.camera?.children.count == 1)
    }

    /// The case the whole feature exists for: the app is up, the room is empty,
    /// and the listener has stopped answering. The lamp is **drawn and dark**,
    /// which is a different picture from the one above and from the one with no
    /// lamp at all.
    @Test func aListenerThatStoppedAnsweringDrawsADarkLamp() throws {
        let binding = try binding()
        binding.showLiveness(
            Liveness(beats: 4, lastBeatAt: Self.epoch),
            at: Self.epoch.addingTimeInterval(0.4))
        #expect(binding.lampPhase == .lit)
        // Nothing arrives. Only the clock moves.
        binding.showLiveness(
            Liveness(beats: 4, lastBeatAt: Self.epoch),
            at: Self.epoch.addingTimeInterval(LivenessLamp.holdDuration + 0.1))
        #expect(binding.lampPhase == .dark)
        #expect(binding.scene.camera?.children.count == 1, "dark is drawn, not absent")
    }

    @Test func theLampIsBuiltOnceAndNotPerFrame() throws {
        let binding = try binding()
        for step in stride(from: 0.0, through: 3.0, by: 0.05) {
            binding.showLiveness(
                Liveness(beats: 1, lastBeatAt: Self.epoch),
                at: Self.epoch.addingTimeInterval(step))
        }
        #expect(binding.scene.camera?.children.count == 1)
    }

    /// Losing the source takes the lamp down rather than freezing it — a lamp
    /// left on screen with nothing behind it is the fiction this design is
    /// entirely about not shipping. [I4]
    @Test func losingTheSourceTakesTheLampDown() throws {
        let binding = try binding()
        binding.showLiveness(Liveness(beats: 1, lastBeatAt: Self.epoch), at: Self.epoch)
        #expect(binding.scene.camera?.children.count == 1)
        binding.showLiveness(nil, at: Self.epoch.addingTimeInterval(1))
        #expect(binding.lampPhase == nil)
        #expect(binding.scene.camera?.children.isEmpty == true)
    }
}
