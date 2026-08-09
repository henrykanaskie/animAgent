import Foundation

/// **How a working character moves, keyed on the badge class.** [I2]
///
/// # Why motion, and why this is the last channel left
///
/// Three detail channels shipped before this one and all three were measured at
/// the only zoom that ships. `RoomCamera.comfortablePopulation` is empty by the
/// maintainer's decision, so `scale(forPopulation:)` returns `minimumScale` in
/// every configuration and the room renders at `1x`, always. At `1x`:
///
/// - **costumes** measure a 0.00% closest-pair silhouette difference — a value
///   and hue channel inside an unchanged outline [04-ART-DIRECTION, M6h];
/// - **held objects** are ~90 px of colour inside a 20x16 torso: "you can see
///   they are holding *something*", not *what* [04-ART-DIRECTION, M7b];
/// - **stations** desaturate to the same pale slab.
///
/// Motion is the one channel that does not depend on resolving detail. A cold
/// observer cannot read a 12x10 object in a character's hands, but they can see
/// one character moving differently from another.
///
/// # What the art can support — measured, not assumed
///
/// Re-derived from the six shipped premades rather than taken from a previous
/// agent's row map. Of Modern Interiors' **20 pose rows** (1792x1312 at a 32x64
/// canvas, rows 0...19; the trailing 32 px carry no ink), exactly **two are
/// seated** — rows 4 and 5 — and they are the only two whose every frame keeps
/// its feet off the canvas's floor row (`maxY` 61 against 63 for all eighteen
/// others). Row 5 is a cross-legged floor sit and no event means *sit on the
/// ground*, so the room draws row 4 and only row 4. [04-ART-DIRECTION, M6g]
///
/// **Row 4 has 3 frames per direction, and they hold two positions, not
/// three.** Over all six cast variants, block 0 (`right`):
///
/// | | frame 0 vs 1 | frame 0 vs 2 | bbox top |
/// |---|---:|---:|---|
/// | 06 | 16 px | 548 px | 20 → 20 → **18** |
/// | 07 | 20 px | 772 px | 16 → 16 → **14** |
/// | 09 | 32 px | 552 px | 16 → 16 → **14** |
/// | 10 | **0 px** | 532 px | 20 → 20 → **18** |
/// | 17 | 8 px | 616 px | 18 → 18 → **16** |
/// | 19 | 8 px | 728 px | 14 → 14 → **12** |
///
/// Frames 0 and 1 are the same pose — 0 to 32 px apart, an eye blink, and
/// literally identical on variant 10. Frame 2 lifts the whole upper body by
/// 2 px, which is 530-770 px of a ~950-1160 px body. So the entire seated motion
/// vocabulary this pack contains is **one two-position bob**: *settled* and
/// *raised*.
///
/// That is the finding, and it decides the design. There are not six seated
/// loops to hand out. There is one, and the only thing a tool class may choose
/// is **when it plays** — which of the two positions the body holds, and for how
/// long, on the manifest's own 8 fps grid.
///
/// **Nothing here invents a frame.** Every pixel drawn is a pixel the artist
/// drew for this pose. A phrase is a schedule over frames that already exist,
/// which is the same relationship `spawn` and `depart` have to `walk`.
///
/// # What a motion may assert [I1]
///
/// A phrase is keyed on the **badge class**, which is keyed on `tool_name`,
/// which is a real field of a real `PreToolUse`. So a phrase asserts exactly
/// what the badge above the same head asserts — *this agent's lowest-ordinal
/// open call is of this class* — and not one thing more. It is a second
/// encoding of one true fact, not a new claim.
///
/// Two consequences follow and both are rules:
///
/// - **`questionMark` gets no phrase**, and `phrase(for:)` returns `nil` for it,
///   which means the body plays the shipped loop exactly as authored. An
///   unmapped tool — `Monitor`, permanently, and anything that ships tomorrow —
///   moves the way a character has always moved. Guessing a motion for it would
///   be the `question_mark` glyph's own reasoning abandoned on a larger surface,
///   which is the argument `HeldObject.init(badge:)` already makes for the
///   hands. [I1]
/// - **The shapes are evocative and that is a bonus, not a claim.** `terminal`
///   buzzes and `magnifier` mostly sits still; if that reads as typing and
///   reading, good. The room is not asserting that anybody typed. It is
///   asserting the class, which the data gave us.
///
/// # The grid, and why six phrases rather than six inventions
///
/// A two-position bob has exactly two parameters — **period** and **duty**, the
/// fraction of the bar spent raised — so the six mapped classes are laid out on
/// a 3x2 grid of them rather than each being tasted separately. Every phrase
/// step is one frame of the manifest's `frame_rate` of 8, i.e. **125 ms**, and
/// no new rate is introduced anywhere.
///
/// | class | phrase | period | raised | reads as |
/// |---|---|---:|---:|---|
/// | `terminal` | `S R` | 250 ms | 50% | a continuous fast chatter |
/// | `document` | `S S S R` | 500 ms | 25% | quick taps with a pause between |
/// | `plug` | `S R R R` | 500 ms | 75% | held up, with a quick dip |
/// | `magnifier` | `S S S S S S R R` | 1000 ms | 25% | long still, one slow rise |
/// | `globe` | `S S S S R R R R` | 1000 ms | 50% | a slow even breathe |
/// | `checklist` | `S S R R R R R R` | 1000 ms | 75% | held up, one slow dip |
/// | `questionMark` | — | 375 ms | 33% | the shipped loop, untouched |
///
/// `magnifier` and `globe` are deliberately **inverses** of `checklist` and each
/// other in posture rather than merely in tempo: duty is the one parameter that
/// is legible from a character's *average* height as well as from its rhythm,
/// and average height survives a glance that a rhythm does not.
///
/// # What this does not do, stated before anyone hopes otherwise
///
/// **A motion is only as visible as the call is long, and I2 says so.** The body
/// is `working` exactly while the open-call set is non-empty, and there is no
/// closing beat for the body — `ADR-003` §2 makes the body idle for every frame
/// of the badge's beat and declares itself void if an implementation does
/// otherwise, and `CLAUDE.md`'s I2 clause says the badge slot may carry a fact
/// the body does not *provided the body is truthful for every frame*.
///
/// So this channel inherits the exposure problem `ADR-003` measured and cannot
/// inherit its fix. Over that document's 224 s capture, per class, total seconds
/// with a call open: `terminal` 102.75, `plug` 100.06, `globe` 13.19,
/// `document` 0.75, `magnifier` 0.11, `checklist` 0.07. A phrase needs a bar to
/// play — 250 ms to 1000 ms — so the last three classes' motion is not slow at
/// `1x`, it is **absent**: those calls do not last long enough for the body to
/// move at all. The honest claim for this layer is that it separates the classes
/// an agent *dwells* in, and that a `Read` is as invisible in motion as it was in
/// pixels.
public enum AmbientMotion {

    /// One of the two positions the seated art holds.
    ///
    /// Two, because the measurement above found two. `settled` is frame 0 and
    /// `raised` is the last frame; the blink between them is 0-32 px and is not
    /// a position, so nothing here schedules it — the shipped loop still plays
    /// it, because the shipped loop is the frame array in order and that is what
    /// `nil` below means.
    public enum Beat: Sendable, Hashable {
        /// Frame 0. Head and torso down.
        case settled
        /// The last frame. The whole upper body 2 px up.
        case raised

        /// Which frame of a `working` animation of `frameCount` frames this is.
        ///
        /// **Total for any count**, which is what keeps the extensibility
        /// property `03-EVENT-MODEL.md` protects for the pose table true here
        /// too: a manifest that ships a seated loop of a different length still
        /// plays every phrase, and no phrase can index out of it.
        public func frameIndex(inFrameCount frameCount: Int) -> Int {
            guard frameCount > 1 else { return 0 }
            switch self {
            case .settled: return 0
            case .raised: return frameCount - 1
            }
        }
    }

    /// The phrase a badge class plays while its character is `working`, or
    /// `nil` for **the shipped loop, unchanged**.
    ///
    /// `nil` is not a gap to fill later. It is the honest motion for a class we
    /// cannot name — see the type's note on `questionMark` — and it is also what
    /// every non-`working` state plays, because there is no claim to make about
    /// how a character walks.
    public static func phrase(for badge: ToolBadge?) -> [Beat]? {
        let s = Beat.settled
        let r = Beat.raised
        switch badge {
        // 250 ms, 50%. The fastest the 8 fps grid allows, and the only phrase
        // with no still section at all — which is what separates it from
        // `document`, whose active part is the same alternation.
        case .terminal: return [s, r]
        // 500 ms, 25%. A tap and a pause.
        case .document: return [s, s, s, r]
        // 500 ms, 75%. `document` inverted: held up, dipping.
        case .plug: return [s, r, r, r]
        // 1000 ms, 25%. Still for three quarters of a second, then one rise.
        case .magnifier: return [s, s, s, s, s, s, r, r]
        // 1000 ms, 50%. Half and half — the slow even breathe.
        case .globe: return [s, s, s, s, r, r, r, r]
        // 1000 ms, 75%. `magnifier` inverted.
        case .checklist: return [s, s, r, r, r, r, r, r]
        // The shipped loop. [I1]
        case .questionMark, nil: return nil
        }
    }

    /// The frame indices a character plays, given what its badge says and how
    /// many frames its current animation has.
    ///
    /// `nil` badge, `questionMark`, or any state other than `working` yields the
    /// identity sequence, which is byte-for-byte what this app drew before this
    /// file existed.
    public static func sequence(
        for badge: ToolBadge?, state: BodyState, frameCount: Int
    ) -> [Int] {
        let identity = Array(0..<max(frameCount, 1))
        guard state == .working, frameCount > 0,
              let phrase = phrase(for: badge) else { return identity }
        return phrase.map { $0.frameIndex(inFrameCount: frameCount) }
    }
}
