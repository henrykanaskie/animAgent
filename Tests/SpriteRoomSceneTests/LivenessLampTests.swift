import Foundation
import SpriteKit
import Testing

@testable import SpriteRoomCore
@testable import SpriteRoomScene

/// The pilot lamp: what it draws, when it stops drawing it, and what it costs.
///
/// **No art gate.** The lamp draws its own bitmaps, so unlike every other test
/// that touches the scene this one runs identically on a fresh clone — which is
/// what a test of "is this app alive" ought to do.
@MainActor
@Suite struct LivenessLampTests {

    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: The phase table

    @Test func aLivenessThatHasNeverBeatenIsDark() {
        #expect(LivenessLamp.phase(lastBeatAt: nil, now: Self.epoch) == .dark)
    }

    @Test func aBeatWinksAndThenSettlesToLit() {
        func phase(_ elapsed: TimeInterval) -> LivenessLamp.Phase {
            LivenessLamp.phase(
                lastBeatAt: Self.epoch, now: Self.epoch.addingTimeInterval(elapsed))
        }
        #expect(phase(0) == .wink)
        #expect(phase(LivenessLamp.winkDuration - 0.001) == .wink)
        #expect(phase(LivenessLamp.winkDuration) == .lit)
        #expect(phase(0.5) == .lit)
        // One dropped beat is tolerated: the hold is two heartbeat intervals.
        #expect(phase(ListenerHeartbeat.interval + 0.1) == .lit)
        #expect(phase(LivenessLamp.holdDuration) == .lit)
        #expect(phase(LivenessLamp.holdDuration + 0.001) == .dark)
        #expect(phase(60) == .dark)
    }

    /// The one thing this indicator may never do: keep saying *alive* because
    /// time passed. Time only ever moves it **towards** dark.
    @Test func timeAloneCanOnlyEverDarkenIt() {
        let liveness = Liveness(beats: 12, lastBeatAt: Self.epoch)
        var previous = LivenessLamp.phase(lastBeatAt: liveness.lastBeatAt, now: Self.epoch)
        var sawDark = false
        for step in stride(from: 0.0, through: 10.0, by: 0.01) {
            let phase = LivenessLamp.phase(
                lastBeatAt: liveness.lastBeatAt,
                now: Self.epoch.addingTimeInterval(step))
            if phase == .dark { sawDark = true }
            #expect(!(sawDark && phase != .dark), "a dark lamp re-lit itself on the clock alone")
            previous = phase
        }
        #expect(previous == .dark)
        #expect(sawDark)
    }

    @Test func aBeatStampedInTheFutureStillCounts() {
        // A clock that moved is not a listener that failed, and the round trip
        // genuinely completed. [I1]
        #expect(LivenessLamp.phase(
            lastBeatAt: Self.epoch.addingTimeInterval(30), now: Self.epoch) == .lit)
    }

    // MARK: The pictures

    @Test func thePhasesDifferByExtentAndNothingElse() {
        let pictures = LivenessLamp.Phase.allCases.map {
            ($0, SceneBitmaps.pilotLamp(core: $0.core))
        }
        for (phase, bitmap) in pictures {
            #expect(bitmap.width == SceneBitmaps.pilotLampSize)
            #expect(bitmap.height == SceneBitmaps.pilotLampSize)
            var colours = Set<Bitmap.RGBA>()
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width { colours.insert(bitmap.at(x, y)) }
            }
            // Two values in the room's existing lettering palette, never a
            // third and never a hue of its own. [I7]
            #expect(colours.isSubset(of: [SceneBitmaps.nameplatePlate, SceneBitmaps.nameplateInk]),
                    "\(phase) drew a colour the room does not already use")
        }

        func ink(_ phase: LivenessLamp.Phase) -> Int {
            let bitmap = SceneBitmaps.pilotLamp(core: phase.core)
            var count = 0
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.at(x, y) == SceneBitmaps.nameplateInk {
                    count += 1
                }
            }
            return count
        }
        #expect(ink(.lit) == 25)
        #expect(ink(.wink) == 9)
        #expect(ink(.dark) == 0)
    }

    /// **The rule the three pictures exist to make total**: any ink at all
    /// means the listener answered recently. There is no phase in which a live
    /// app draws an empty lamp, so a glance can never read the pulse as a
    /// failure.
    @Test func onlyADeadListenerDrawsALampWithNoInkInIt() {
        for phase in LivenessLamp.Phase.allCases {
            #expect((phase.core > 0) == (phase != .dark))
        }
    }

    // MARK: The motion budget

    /// 32 px/s, placed, for the whole room, at any population.
    ///
    /// Measured off the pictures rather than restated, so a change to either
    /// one moves this number and this test is where it is noticed. The ceiling
    /// it is compared against is *not* `04-ART-DIRECTION.md`'s 1461 px/s prop
    /// budget — that number rests on "an idling character is the quietest thing
    /// the cast can be", and an idling character now moves 0, so the
    /// justification is void and the document says so. The comparison that
    /// governs here is against a **working** character, because the only thing
    /// this lamp must never do is mask the busy/idle distinction.
    @Test func theLampCostsThirtyTwoChangedPixelsPerSecond() {
        func changed(_ a: LivenessLamp.Phase, _ b: LivenessLamp.Phase) -> Int {
            let first = SceneBitmaps.pilotLamp(core: a.core)
            let second = SceneBitmaps.pilotLamp(core: b.core)
            var count = 0
            for y in 0..<first.height {
                for x in 0..<first.width where first.at(x, y) != second.at(x, y) { count += 1 }
            }
            return count
        }
        let perTransition = changed(.lit, .wink)
        #expect(perTransition == 16)
        // Two transitions per beat: lit → wink at the beat, wink → lit 125 ms
        // later. Nothing else in the cycle changes a pixel.
        let perSecond = Double(perTransition * 2) / ListenerHeartbeat.interval
        #expect(perSecond == 32)

        // The quietest thing a *working* character does, from `AmbientMotion`:
        // `magnifier`'s 1000 ms bar is two position changes a second over a
        // 2 px lift of the upper body, on the order of 1300 px/s. A hundredth
        // of that is the bar this has to clear, and it clears it by 40×.
        #expect(perSecond < 1300 / 40)
    }

    /// It says nothing about any agent, and that is what keeps it from becoming
    /// a second activity channel competing with the cast. [I2]
    @Test func theLampIsTheSameWhateverTheRoomIsDoing() {
        // The phase is a function of exactly two things and neither of them is
        // the room. If this signature ever grows a third argument, that is the
        // moment to argue about it again.
        let busy = LivenessLamp.phase(lastBeatAt: Self.epoch, now: Self.epoch.addingTimeInterval(0.5))
        let empty = LivenessLamp.phase(lastBeatAt: Self.epoch, now: Self.epoch.addingTimeInterval(0.5))
        #expect(busy == empty)
    }

    // MARK: The node

    /// A bare `SKScene` with a camera — enough to place a lamp, and no art.
    private func scene(width: Double = 720, height: Double = 400) -> SKScene {
        let scene = SKScene(size: CGSize(width: width, height: height))
        let camera = SKCameraNode()
        scene.addChild(camera)
        scene.camera = camera
        return scene
    }

    @Test func theLampHangsOffTheCameraAndAboveEverything() throws {
        let scene = scene()
        let lamp = try #require(LivenessLamp(scene: scene))
        let node = try #require(scene.camera?.children.first as? SKSpriteNode)
        #expect(node.zPosition > Character.Layer.nameplate)
        #expect(node.zPosition == LivenessLamp.depth)
        #expect(node.size == CGSize(width: 9, height: 9))
        // Bottom-left of the frame, in the camera's own coordinates.
        #expect(node.position == CGPoint(x: -720 / 2 + 4, y: -400 / 2 + 4))
        #expect(lamp.phase == .dark, "nothing has been proved yet")
    }

    @Test func theNodeFollowsThePhase() throws {
        let scene = scene()
        let lamp = try #require(LivenessLamp(scene: scene))
        let node = try #require(scene.camera?.children.first as? SKSpriteNode)

        lamp.update(Liveness(beats: 1, lastBeatAt: Self.epoch), at: Self.epoch)
        #expect(lamp.phase == .wink)
        let winking = node.texture

        lamp.update(
            Liveness(beats: 1, lastBeatAt: Self.epoch),
            at: Self.epoch.addingTimeInterval(0.3))
        #expect(lamp.phase == .lit)
        #expect(node.texture !== winking)

        lamp.update(
            Liveness(beats: 1, lastBeatAt: Self.epoch),
            at: Self.epoch.addingTimeInterval(30))
        #expect(lamp.phase == .dark)
    }

    /// The frame moves — the camera rescales with population — and the lamp
    /// stays in its corner.
    @Test func theLampStaysInTheCornerWhenTheFrameResizes() throws {
        let scene = scene()
        let lamp = try #require(LivenessLamp(scene: scene))
        let node = try #require(scene.camera?.children.first as? SKSpriteNode)
        scene.size = CGSize(width: 360, height: 200)
        lamp.update(Liveness(), at: Self.epoch)
        #expect(node.position == CGPoint(x: -360 / 2 + 4, y: -200 / 2 + 4))
    }

    @Test func removingTheLampTakesItOffScreen() throws {
        let scene = scene()
        let lamp = try #require(LivenessLamp(scene: scene))
        #expect(scene.camera?.children.count == 1)
        lamp.remove()
        #expect(scene.camera?.children.isEmpty == true)
    }
}
