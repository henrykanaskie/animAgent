import Foundation
import Testing
@testable import SpriteRoomApp

/// Exit criteria 1 and 4, as unit tests.
///
/// "Diagonal pointer paths across the notch region do not cause reveal/retract
/// oscillation" is a claim about a *sequence of pointer positions*, so it is
/// tested by synthesising sequences of pointer positions. Nothing here opens a
/// window, and nothing here needs anyone to watch a screen.
struct RevealPolicyTests {

    // MARK: Criterion 1 — reveal on entry, retract on exit

    @Test func pointingAtTheNotchRevealsThePanel() {
        var run = Simulation(policy: PanelFixtures.policy())
        run.hold(PanelFixtures.away(), for: 0.5)
        #expect(run.reveals == 0)
        run.hold(PanelFixtures.inside(), for: 0.5)
        #expect(run.reveals == 1)
        #expect(run.policy.phase == .revealed)
    }

    @Test func leavingRetractsThePanel() {
        var run = Simulation(policy: PanelFixtures.policy())
        run.hold(PanelFixtures.inside(), for: 0.6)
        run.hold(PanelFixtures.away(), for: 1.2)
        #expect(run.reveals == 1)
        #expect(run.retracts == 1)
        #expect(run.policy.phase == .hidden)
    }

    @Test func aPointerThatIsNowhereCountsAsOutside() {
        // Pointer on a display we do not track, or off every display.
        var run = Simulation(policy: PanelFixtures.policy())
        run.hold(PanelFixtures.inside(), for: 0.6)
        run.hold(nil, for: 1.2)
        #expect(run.retracts == 1)
    }

    // MARK: The dwell — temporal hysteresis on the way in

    @Test func aBrushPastTheNotchNeverRevealsAnything() {
        let tuning = RevealPolicy.Tuning.default
        var run = Simulation(policy: PanelFixtures.policy(tuning: tuning))
        run.hold(PanelFixtures.away(), for: 0.3)
        run.hold(PanelFixtures.inside(), for: tuning.dwellToReveal * 0.7)
        run.hold(PanelFixtures.away(), for: 1.0)
        #expect(run.transitions.isEmpty)
    }

    @Test func leavingDuringTheDwellCancelsItCompletely() {
        let tuning = RevealPolicy.Tuning.default
        var run = Simulation(policy: PanelFixtures.policy(tuning: tuning))
        // Two half-dwells with a gap: they must not add up to one dwell.
        for _ in 0..<6 {
            run.hold(PanelFixtures.inside(), for: tuning.dwellToReveal * 0.5)
            run.hold(PanelFixtures.away(), for: 0.05)
        }
        #expect(run.reveals == 0)
    }

    // MARK: The grace period — temporal hysteresis on the way out

    @Test func anOvershootShorterThanTheGraceCostsNothing() {
        let tuning = RevealPolicy.Tuning.default
        var run = Simulation(policy: PanelFixtures.policy(tuning: tuning))
        run.hold(PanelFixtures.inside(), for: 0.8)
        #expect(run.reveals == 1)
        run.hold(PanelFixtures.away(), for: tuning.graceToRetract * 0.6)
        run.hold(PanelFixtures.inside(), for: 0.3)
        #expect(run.retracts == 0)
        #expect(run.policy.phase == .revealed)
    }

    @Test func thePanelStaysDownForItsMinimumEvenIfTheGraceHasElapsed() {
        let tuning = RevealPolicy.Tuning(
            dwellToReveal: 0.05, graceToRetract: 0.05, minimumVisible: 0.6)
        var run = Simulation(policy: PanelFixtures.policy(tuning: tuning))
        run.hold(PanelFixtures.inside(), for: 0.06)
        let revealedAt = run.transitions.first?.time
        run.hold(PanelFixtures.away(), for: 1.0)
        let retractedAt = run.transitions.last?.time
        #expect(run.reveals == 1 && run.retracts == 1)
        #expect((retractedAt ?? 0) - (revealedAt ?? 0) >= 0.6)
    }

    // MARK: Spatial hysteresis — the keep-open zone

    @Test func theKeepOpenZoneStrictlyContainsTheTriggerZone() {
        var policy = PanelFixtures.policy()
        for _ in 0..<40 { _ = policy.update(pointer: PanelFixtures.inside(), at: 1) }
        let keep = policy.keepOpen
        let trigger = policy.trigger
        #expect(keep.minX < trigger.minX)
        #expect(keep.maxX > trigger.maxX)
        #expect(keep.minY < trigger.minY)
    }

    @Test func theRevealedPanelIsPartOfWhatKeepsItOpen() {
        let geometry = PanelFixtures.notched
        var run = Simulation(policy: PanelFixtures.policy(geometry))
        run.hold(PanelFixtures.inside(), for: 0.6)
        // Deep inside the room, hundreds of points below the notch. Moving the
        // pointer into what you are looking at must not dismiss it.
        let inTheRoom = PanelPoint(
            x: geometry.revealedPanelFrame(size: .room).midX,
            y: geometry.revealedPanelFrame(size: .room).minY + 20)
        run.hold(inTheRoom, for: 3.0)
        #expect(run.retracts == 0)
        #expect(run.policy.phase == .revealed)
    }

    @Test func jitterSmallerThanTheExitMarginCannotMoveThePanel() {
        let tuning = RevealPolicy.Tuning.default
        let geometry = PanelFixtures.notched
        var run = Simulation(policy: PanelFixtures.policy(geometry, tuning: tuning))
        run.hold(PanelFixtures.inside(geometry), for: 0.6)
        #expect(run.reveals == 1)
        // A hand resting on the left edge of the hot zone, trembling either
        // side of it for four seconds.
        let edge = geometry.region.minX
        let amplitude = tuning.exitMargin - 4
        var t = 0.0
        while t < 4.0 {
            let offset = sin(t * 22) * amplitude
            run.sample(PanelPoint(x: edge + offset, y: geometry.region.midY))
            t += run.step
        }
        #expect(run.retracts == 0)
    }

    // MARK: Criterion 4 — diagonals do not oscillate

    /// A straight line crosses a rectangle at most once, so a diagonal can
    /// legitimately produce at most one reveal and one retract. Anything more
    /// is the oscillation the criterion forbids.
    @Test(arguments: [0.08, 0.15, 0.3, 0.6, 1.0, 1.8, 3.0, 5.0])
    func straightDiagonalsProduceAtMostOneRevealAndOneRetract(duration: Double) {
        let geometry = PanelFixtures.notched
        let region = geometry.region
        for slope in [-1.0, -0.4, 0.4, 1.0] {
            var run = Simulation(policy: PanelFixtures.policy(geometry))
            let start = PanelPoint(x: region.midX - 700, y: region.midY - 700 * slope)
            let end = PanelPoint(x: region.midX + 700, y: region.midY + 700 * slope)
            run.hold(PanelFixtures.away(geometry), for: 0.3)
            run.sweep(from: start, to: end, duration: duration)
            run.hold(PanelFixtures.away(geometry), for: 2.0)

            #expect(run.reveals <= 1, "slope \(slope), \(duration)s: \(run.reveals) reveals")
            #expect(run.retracts <= 1, "slope \(slope), \(duration)s: \(run.retracts) retracts")
            // Whatever happened, the panel is away at the end.
            #expect(run.policy.phase == .hidden)
        }
    }

    @Test func aFastDiagonalDoesNotFlashThePanelAtAll() {
        let geometry = PanelFixtures.notched
        let region = geometry.region
        var run = Simulation(policy: PanelFixtures.policy(geometry))
        run.hold(PanelFixtures.away(geometry), for: 0.3)
        // 1400 points of travel in 120 ms — a flick towards a menu on the far
        // side of the screen. The pointer is over the hot zone for ~20 ms.
        run.sweep(
            from: PanelPoint(x: region.midX - 700, y: region.midY - 200),
            to: PanelPoint(x: region.midX + 700, y: region.midY + 200),
            duration: 0.12)
        run.hold(PanelFixtures.away(geometry), for: 1.5)
        #expect(run.transitions.isEmpty)
    }

    /// The anti-oscillation guarantee, stated directly: **no two state changes
    /// can ever be closer together than the tuning allows**, whatever the
    /// pointer does. A deterministic pseudo-random walk stands in for a hand.
    @Test func noPathCanMakeThePanelChangeStateFasterThanTheTuningAllows() {
        let tuning = RevealPolicy.Tuning.default
        let geometry = PanelFixtures.notched
        let floor = tuning.minimumIntervalBetweenTransitions

        for seed in UInt64(1)...30 {
            var random = SplitMix64(seed: seed)
            var run = Simulation(policy: PanelFixtures.policy(geometry, tuning: tuning))
            // Start near the hot zone so the walk spends real time on the
            // boundary rather than wandering the desktop.
            var point = PanelFixtures.inside(geometry)
            for _ in 0..<3600 {  // 30 seconds at 120 Hz
                point.x += (random.unit() - 0.5) * 90
                point.y += (random.unit() - 0.5) * 90
                point.x = min(max(point.x, geometry.region.minX - 400), geometry.region.maxX + 400)
                point.y = min(max(point.y, geometry.display.maxY - 700), geometry.display.maxY - 1)
                run.sample(point)
            }
            if let closest = run.closestTransitions {
                #expect(
                    closest >= floor - 1e-9,
                    "seed \(seed): two transitions \(closest)s apart, floor is \(floor)s")
            }
        }
    }

    @Test func revealsAndRetractsAlwaysAlternate() {
        var random = SplitMix64(seed: 99)
        let geometry = PanelFixtures.notched
        var run = Simulation(policy: PanelFixtures.policy(geometry))
        var point = PanelFixtures.inside(geometry)
        for _ in 0..<6000 {
            point.x += (random.unit() - 0.5) * 120
            point.y += (random.unit() - 0.5) * 120
            point.x = min(max(point.x, geometry.display.minX), geometry.display.maxX - 1)
            point.y = min(max(point.y, geometry.display.minY), geometry.display.maxY - 1)
            run.sample(point)
        }
        var expected = PanelTransition.reveal
        for entry in run.transitions {
            #expect(entry.transition == expected)
            expected = expected == .reveal ? .retract : .reveal
        }
    }

    // MARK: Gaps in observation

    @Test func aGapInSamplingRestartsAWaitRatherThanSatisfyingIt() {
        var policy = PanelFixtures.policy()
        // Enter, then vanish for a minute — a closed lid, a stalled main
        // thread. The dwell must not be considered served by the missing time.
        #expect(policy.update(pointer: PanelFixtures.inside(), at: 0) == nil)
        #expect(policy.update(pointer: PanelFixtures.inside(), at: 60) == nil)
        #expect(policy.phase == .arming)
        #expect(policy.update(pointer: PanelFixtures.inside(), at: 60.2) == .reveal)
    }

    @Test func timeGoingBackwardsIsTreatedAsAGapNotANegativeDuration() {
        var policy = PanelFixtures.policy()
        _ = policy.update(pointer: PanelFixtures.inside(), at: 100)
        _ = policy.update(pointer: PanelFixtures.inside(), at: 5)
        #expect(policy.phase == .arming)
        #expect(policy.update(pointer: PanelFixtures.inside(), at: 5.05) == nil)
        #expect(policy.update(pointer: PanelFixtures.inside(), at: 5.2) == .reveal)
    }

    // MARK: An external display behaves the same way

    @Test func theSyntheticRegionRevealsAndRetractsLikeARealNotch() {
        let geometry = PanelFixtures.external
        var run = Simulation(policy: PanelFixtures.policy(geometry))
        run.hold(PanelFixtures.away(geometry), for: 0.4)
        run.hold(PanelFixtures.inside(geometry), for: 0.6)
        run.hold(PanelFixtures.away(geometry), for: 1.2)
        #expect(run.reveals == 1)
        #expect(run.retracts == 1)
    }

    // MARK: The harness door

    @Test func forcedCyclesReportOneTransitionEach() {
        var policy = PanelFixtures.policy()
        #expect(policy.forceReveal(at: 0) == .reveal)
        #expect(policy.forceReveal(at: 0.01) == nil)
        #expect(policy.forceRetract(at: 0.02) == .retract)
        #expect(policy.forceRetract(at: 0.03) == nil)
    }
}

/// Deterministic, dependency-free, and identical on every machine — a seeded
/// walk that fails on one Mac and passes on another would be worthless.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
