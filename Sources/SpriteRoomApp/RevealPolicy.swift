import Foundation

// Whether the panel should be down. Pointer position and time in, desired
// state out — no AppKit types anywhere in the signature, so the milestone's
// "diagonal paths do not cause oscillation" criterion is a unit test over
// synthesised paths rather than a claim about something someone watched.
//
// A bare `mouseEntered`/`mouseExited` pair fails that criterion twice over: a
// pointer skimming the notch on its way to the menu bar flashes the panel, and
// a pointer resting on the boundary chatters. Two independent mechanisms fix
// it, and both are needed:
//
//   * **Temporal hysteresis.** Entering must be *sustained* for `dwellToReveal`
//     before the panel comes down, and leaving must be sustained for
//     `graceToRetract` before it goes back up. A fast crossing never dwells.
//   * **Spatial hysteresis.** The rectangle you must stay inside to keep the
//     panel down is strictly larger than the one you must enter to bring it
//     down — and once the panel is down it grows again to include the panel
//     itself, because the pointer travelling into the room must not dismiss it.
//
// The result is a floor on how often the panel can change state: a retract can
// never be followed by a reveal sooner than `dwellToReveal`, and a reveal can
// never be followed by a retract sooner than `max(graceToRetract,
// minimumVisible)`. That floor is the anti-oscillation guarantee, and it is
// asserted directly over random walks in the tests.

/// What the panel is doing. `arming` and `retracting` are the waiting states —
/// the panel has not moved yet and may not.
public enum PanelPhase: Sendable, Hashable, CustomStringConvertible {
    /// Up. Pointer is elsewhere.
    case hidden
    /// Up, pointer is in the hot zone, waiting out the dwell.
    case arming
    /// Down.
    case revealed
    /// Down, pointer has left, waiting out the grace period.
    case retracting

    /// Whether the panel is on screen in this phase.
    public var isVisible: Bool {
        switch self {
        case .hidden, .arming: return false
        case .revealed, .retracting: return true
        }
    }

    public var description: String {
        switch self {
        case .hidden: return "hidden"
        case .arming: return "arming"
        case .revealed: return "revealed"
        case .retracting: return "retracting"
        }
    }
}

/// The one thing the policy ever asks for. `nil` from `update` means "no
/// change" — the overwhelmingly common answer.
public enum PanelTransition: Sendable, Hashable, CustomStringConvertible {
    case reveal
    case retract

    public var description: String {
        switch self {
        case .reveal: return "reveal"
        case .retract: return "retract"
        }
    }
}

public struct RevealPolicy: Sendable {

    /// Every number that decides how twitchy the panel is, in one place.
    public struct Tuning: Sendable, Hashable {
        /// How long the pointer must stay in the hot zone before the panel
        /// comes down. Long enough that a pointer travelling to a menu on the
        /// other side of the screen never triggers it; short enough that
        /// deliberately aiming at the notch feels immediate.
        public var dwellToReveal: TimeInterval
        /// How long the pointer must stay out of the keep-open zone before the
        /// panel goes up. Covers the overshoot at the end of a fast approach
        /// and the moment the pointer clips a corner.
        public var graceToRetract: TimeInterval
        /// Once down, the panel stays down at least this long regardless. Stops
        /// a reveal that was immediately regretted from reading as a flash.
        public var minimumVisible: TimeInterval
        /// Points added to every edge of the keep-open zone. This is the
        /// spatial half of the hysteresis: jitter smaller than this cannot move
        /// the panel at all, however slow it is.
        public var exitMargin: Double
        /// Samples further apart than this are treated as a gap in observation
        /// — a laptop lid, a stalled main thread — and reset the timers rather
        /// than instantly satisfying them.
        public var maximumSampleGap: TimeInterval

        public init(
            dwellToReveal: TimeInterval = 0.14,
            graceToRetract: TimeInterval = 0.45,
            minimumVisible: TimeInterval = 0.40,
            exitMargin: Double = 18,
            maximumSampleGap: TimeInterval = 1.0
        ) {
            self.dwellToReveal = max(0, dwellToReveal)
            self.graceToRetract = max(0, graceToRetract)
            self.minimumVisible = max(0, minimumVisible)
            self.exitMargin = max(0, exitMargin)
            self.maximumSampleGap = max(0.001, maximumSampleGap)
        }

        public static let `default` = Tuning()

        /// The guarantee the tests assert: no two state changes can ever be
        /// closer together than this.
        public var minimumIntervalBetweenTransitions: TimeInterval {
            min(dwellToReveal, max(graceToRetract, minimumVisible))
        }
    }

    /// The rectangle the pointer must enter.
    public let trigger: PanelRect
    /// Where the panel is when it is down. Part of the keep-open zone while it
    /// is down, and only then.
    public let revealedPanel: PanelRect
    public let tuning: Tuning

    public private(set) var phase: PanelPhase = .hidden

    /// When the current `arming` or `retracting` wait began.
    private var waitingSince: TimeInterval = 0
    /// When the panel last came down. Guards `minimumVisible`.
    private var revealedAt: TimeInterval = -.greatestFiniteMagnitude
    /// Timestamp of the previous sample, for gap detection.
    private var lastSampleAt: TimeInterval?

    public init(
        trigger: PanelRect,
        revealedPanel: PanelRect,
        tuning: Tuning = .default
    ) {
        self.trigger = trigger
        self.revealedPanel = revealedPanel
        self.tuning = tuning
    }

    public init(geometry: NotchGeometry, size: PanelSize, tuning: Tuning = .default) {
        self.init(
            trigger: geometry.region,
            revealedPanel: geometry.revealedPanelFrame(size: size),
            tuning: tuning)
    }

    /// The zone the pointer has to leave to start a retract. Strictly contains
    /// `trigger`, and while the panel is down it also contains the panel.
    public var keepOpen: PanelRect {
        let base = phase.isVisible ? trigger.union(revealedPanel) : trigger
        return base.inset(dx: -tuning.exitMargin, dy: -tuning.exitMargin)
    }

    /// Feed one pointer sample. `pointer` is `nil` when the pointer is not on
    /// any display we track — treat that exactly like being outside.
    ///
    /// `now` is a monotonic seconds value. Time going backwards is treated as a
    /// gap, not as a negative duration.
    public mutating func update(pointer: PanelPoint?, at now: TimeInterval) -> PanelTransition? {
        let gapped: Bool
        if let last = lastSampleAt {
            let delta = now - last
            gapped = delta < 0 || delta > tuning.maximumSampleGap
        } else {
            gapped = false
        }
        lastSampleAt = now

        // A gap means we do not know where the pointer has been. Restart any
        // wait in progress rather than letting the missing time count towards
        // it; a wait that "completed" while we were not looking is a guess.
        if gapped {
            switch phase {
            case .arming: waitingSince = now
            case .retracting: waitingSince = now
            case .hidden, .revealed: break
            }
        }

        let insideTrigger = pointer.map { trigger.contains($0) } ?? false
        let insideKeepOpen = pointer.map { keepOpen.contains($0) } ?? false

        switch phase {
        case .hidden:
            if insideTrigger {
                phase = .arming
                waitingSince = now
                // Zero dwell is a legal tuning; honour it on the same sample.
                return finishArmingIfDue(now: now)
            }
            return nil

        case .arming:
            // Leaving the *trigger* cancels arming outright — no grace on the
            // way up, because nothing has moved on screen yet and there is
            // nothing to flicker.
            guard insideTrigger else {
                phase = .hidden
                return nil
            }
            return finishArmingIfDue(now: now)

        case .revealed:
            guard !insideKeepOpen else { return nil }
            phase = .retracting
            waitingSince = now
            return finishRetractingIfDue(now: now)

        case .retracting:
            // Coming back inside cancels the retract silently. The panel never
            // moved, so there is nothing to undo — this is the case that makes
            // an overshoot free.
            if insideKeepOpen {
                phase = .revealed
                return nil
            }
            return finishRetractingIfDue(now: now)
        }
    }

    /// Force the panel down without a pointer. Used only by the verification
    /// harness, which drives cycles far faster than a hand could.
    public mutating func forceReveal(at now: TimeInterval) -> PanelTransition? {
        lastSampleAt = now
        guard !phase.isVisible else { phase = .revealed; return nil }
        phase = .revealed
        revealedAt = now
        return .reveal
    }

    /// Force the panel up. Ignores `minimumVisible`; the harness is not a hand.
    public mutating func forceRetract(at now: TimeInterval) -> PanelTransition? {
        lastSampleAt = now
        guard phase.isVisible else { phase = .hidden; return nil }
        phase = .hidden
        return .retract
    }

    private mutating func finishArmingIfDue(now: TimeInterval) -> PanelTransition? {
        guard now - waitingSince >= tuning.dwellToReveal else { return nil }
        phase = .revealed
        revealedAt = now
        return .reveal
    }

    private mutating func finishRetractingIfDue(now: TimeInterval) -> PanelTransition? {
        guard now - waitingSince >= tuning.graceToRetract else { return nil }
        guard now - revealedAt >= tuning.minimumVisible else { return nil }
        phase = .hidden
        return .retract
    }
}
