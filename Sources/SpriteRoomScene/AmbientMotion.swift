import Foundation

/// **How a working character moves, keyed on the badge class.** [I2]
///
/// # Why motion, and why this is the last channel left
///
/// Three detail channels shipped before this one and all three were measured at
/// `1x`, which was the only zoom that shipped when they were written.
///
/// **That is no longer true and the correction matters.** `44e82f0` set
/// `RoomCamera.defaultComfortablePopulation` to `[2: 3]`, so a room of one to
/// three agents now renders at `2x` and only a fourth agent drops it to `1x`.
/// This comment previously read "the room renders at `1x`, always" and a design
/// agent reasoning from it concluded that a beat which reads only at `2x` is
/// worth *nothing* rather than *nothing above three agents*, which is a
/// different and much weaker claim.
///
/// The ranking below survives the correction, because `1x` is still where the
/// room lands whenever it is busy, and busy is when a person most needs to read
/// it. At `1x`:
///
/// - **costumes** measure a 0.00% closest-pair silhouette difference: a value
///   and hue channel inside an unchanged outline [04-ART-DIRECTION, M6h];
/// - **held objects** are ~90 px of colour inside a 20x16 torso: "you can see
///   they are holding *something*", not *what* [04-ART-DIRECTION, M7b];
/// - **stations** desaturate to the same pale slab.
///
/// Motion is the one channel that does not depend on resolving detail. A cold
/// observer cannot read a 12x10 object in a character's hands, but they can see
/// one character moving differently from another.
///
/// # What the art can support: measured, not assumed
///
/// Re-derived from the six shipped premades rather than taken from a previous
/// agent's row map. Of Modern Interiors' **20 pose rows** (1792x1312 at a 32x64
/// canvas, rows 0...19; the trailing 32 px carry no ink), exactly **two are
/// seated**, rows 4 and 5, and they are the only two whose every frame keeps
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
/// Frames 0 and 1 are the same pose: 0 to 32 px apart, an eye blink, and
/// literally identical on variant 10. Frame 2 lifts the whole upper body by
/// 2 px, which is 530-770 px of a ~950-1160 px body. So the entire seated motion
/// vocabulary this pack contains is **one two-position bob**: *settled* and
/// *raised*.
///
/// That is the finding, and it decides the design. There are not six seated
/// loops to hand out. There is one, and the only thing a tool class may choose
/// is **when it plays**: which of the two positions the body holds, and for how
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
/// what the badge above the same head asserts: *this agent's lowest-ordinal
/// open call is of this class*, and not one thing more. It is a second
/// encoding of one true fact, not a new claim.
///
/// Two consequences follow and both are rules:
///
/// - **`questionMark` gets no phrase**, and `phrase(for:)` returns `nil` for it,
///   which means the body plays the shipped loop exactly as authored. An
///   unmapped tool (`Monitor`, permanently, and anything that ships tomorrow)
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
/// A two-position bob has exactly two parameters: **period** and **duty**, the
/// fraction of the bar spent raised, so the six mapped classes are laid out on
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
/// | `questionMark` | - | 375 ms | 33% | the shipped loop, untouched |
///
/// `magnifier` and `globe` are deliberately **inverses** of `checklist` and each
/// other in posture rather than merely in tempo: duty is the one parameter that
/// is legible from a character's *average* height as well as from its rhythm,
/// and average height survives a glance that a rhythm does not.
///
/// # What this does not do, stated before anyone hopes otherwise
///
/// **A motion is only as visible as the call is long, and I2 says so.** The body
/// **moves** exactly while the open-call set is non-empty and no permission gate
/// is open on it [ADR-005 §7], and there is no closing beat for the body: `ADR-003` §2 requires that the body assert no
/// ongoing work for any frame of the badge's beat and declares itself void if an
/// implementation does otherwise, and `CLAUDE.md`'s I2 clause says the badge
/// slot may carry a fact the body does not *provided the body is truthful for
/// every frame*. ADR-005 moved the posture off the open-call set and left this
/// sentence exactly where it was: during a beat the character is seated and
/// **still**, which asserts less than the standing frame it used to draw, not
/// more.
///
/// So this channel inherits the exposure problem `ADR-003` measured and cannot
/// inherit its fix. Over that document's 224 s capture, per class, total seconds
/// with a call open: `terminal` 102.75, `plug` 100.06, `globe` 13.19,
/// `document` 0.75, `magnifier` 0.11, `checklist` 0.07. A phrase needs a bar to
/// play (250 ms to 1000 ms), so the last three classes' motion is not slow at
/// `1x`, it is **absent**: those calls do not last long enough for the body to
/// move at all. The honest claim for this layer is that it separates the classes
/// an agent *dwells* in, and that a `Read` is as invisible in motion as it was in
/// pixels.
public enum AmbientMotion {

    /// One of the two positions the seated art holds.
    ///
    /// Two, because the measurement above found two. `settled` is frame 0 and
    /// `raised` is the last frame; the blink between them is 0-32 px and is not
    /// a position, so nothing here schedules it: the shipped loop still plays
    /// it, because the shipped loop is the frame array in order and that is what
    /// `nil` below means.
    public enum Beat: Sendable, Hashable {
        /// Frame 0. Head and torso down.
        case settled
        /// The frame that holds the whole upper body 2 px up.
        case raised

        /// Which frame of the animation this is, given how many frames it has
        /// and which of them the manifest **measured** as the raised one.
        ///
        /// **`raisedFrame` is a measurement and it used to be a guess.** This
        /// returned `frameCount − 1` for `raised`, which is right for the
        /// three-frame `sit` row `(rest, rest, up)` and wrong for every other
        /// row in the pack: the six-frame `idle` row bobs on frames **2 and 3**
        /// and comes back to rest on 4 and 5, so the last frame is *settled* and
        /// a phrase built on it alternates between two identical pictures. A
        /// character with a call open would then hold still, which inverts the
        /// one signal this whole file exists to carry. That stopped being
        /// hypothetical the day a seat could face the camera, because a turned
        /// seat draws the idle row. `Manifest.StateAnimation.raisedFrame` is
        /// measured off the frames by `scripts/build-manifest.py`.
        ///
        /// **Total for any count and for any manifest**, which is what keeps the
        /// extensibility property `03-EVENT-MODEL.md` protects for the pose table
        /// true here too: an out-of-range or absent measurement falls back to the
        /// old rule, so a manifest that predates it draws exactly what it drew
        /// before, and no phrase can index out of any animation.
        public func frameIndex(inFrameCount frameCount: Int, raisedFrame: Int? = nil) -> Int {
            guard frameCount > 1 else { return 0 }
            switch self {
            case .settled: return 0
            case .raised:
                guard let raisedFrame, raisedFrame > 0, raisedFrame < frameCount else {
                    return frameCount - 1
                }
                return raisedFrame
            }
        }
    }

    /// The phrase a badge class plays while its character is `working`, or
    /// `nil` for **the shipped loop, unchanged**.
    ///
    /// `nil` is not a gap to fill later. It is the honest motion for a class we
    /// cannot name (see the type's note on `questionMark`) and it is also what
    /// every non-`working` state plays, because there is no claim to make about
    /// how a character walks.
    public static func phrase(for badge: ToolBadge?) -> [Beat]? {
        let s = Beat.settled
        let r = Beat.raised
        switch badge {
        // 250 ms, 50%. The fastest the 8 fps grid allows, and the only phrase
        // with no still section at all, which is what separates it from
        // `document`, whose active part is the same alternation.
        case .terminal: return [s, r]
        // 500 ms, 25%. A tap and a pause.
        case .document: return [s, s, s, r]
        // 500 ms, 75%. `document` inverted: held up, dipping.
        case .plug: return [s, r, r, r]
        // 1000 ms, 25%. Still for three quarters of a second, then one rise.
        case .magnifier: return [s, s, s, s, s, s, r, r]
        // 1000 ms, 50%. Half and half: the slow even breathe.
        case .globe: return [s, s, s, s, r, r, r, r]
        // 1000 ms, 75%. `magnifier` inverted.
        case .checklist: return [s, s, r, r, r, r, r, r]
        // The shipped loop. [I1]
        case .questionMark, nil: return nil
        }
    }

    /// **A character with no open call holds one frame.** [I1]
    ///
    /// The shipped `idle` loop is 6 frames at 8 fps. It was playing at full
    /// amplitude under every character that had nothing to show, and that is not
    /// a cosmetic complaint: it inverted the one distinction this room exists to
    /// make. Measured over 8 consecutive 125 ms frames of the real capture
    /// (`scratchpad/observe/baseline/capture.jsonl` at t=110, a 32x52 body box,
    /// total absolute RGB delta):
    ///
    /// | character | state | delta |
    /// |---|---|---:|
    /// | A69 | `terminal` open | 577,962 |
    /// | **MAIN** | **idle, zero open calls** | **196,404** |
    /// | 430 | `plug` open | 181,080 |
    /// | 8AB | dormant | 123,480 |
    ///
    /// The idle body out-moved a working one. Motion is the channel that
    /// survives `1x`, and `1x` is where the room lands from four agents up,
    /// which is exactly when a person needs to read it, and it was carrying no
    /// busy/idle signal at all.
    ///
    /// This sentence used to justify itself with "`comfortablePopulation` is
    /// empty, so nothing else does". That stopped being true at `44e82f0`, which
    /// turned `2x` on for up to three agents; see the correction at the head of
    /// this file. The conclusion stands on the narrower ground above.
    ///
    /// **The art cannot fix this from the other end.** The type note above
    /// re-derives it: the seated pack row holds *two* positions, 2 px of
    /// upper-body lift, and there is no third. A working loop cannot be given
    /// more amplitude than it has. The only lever is the idle loop, and the only
    /// honest thing to do with it is take it away: I1 says that where the data
    /// does not say something happened, the room shows nothing, and the hook
    /// stream says **nothing at all** about an agent between its calls: 84% of
    /// its life, by ADR-003 §0's measurement. A breathing loop over that silence
    /// was the room's one piece of invented activity, small enough that nobody
    /// called it fiction and loud enough to drown the real signal beside it.
    ///
    /// So `idle` is one frame, held. Nothing else changes: `walk`, `spawn`,
    /// `depart` and `deliver` play exactly as authored, because each of those is
    /// a real event being told. After this, **movement in a seat means an open
    /// call**, and that is a claim the room can back.
    ///
    /// What it costs, stated rather than discovered later: a room where nobody
    /// is working is a room where nothing moves. That is the truth about such a
    /// room, but it is also indistinguishable at a glance from a room that has
    /// stopped updating, and this file cannot close that gap: see
    /// `notes.md` for the one channel that could.
    public static let idleSequence = [0]

    /// **A seated character with no open call holds one frame too.** [ADR-005 §3]
    ///
    /// This is the sentence above, applied on the day the seated pose stopped
    /// meaning *executing* and started meaning *at its workstation, in a turn*.
    /// The rule I2 defends did not move an inch: a character animates **if and
    /// only if** it holds an open tool call. What moved is which still frame the
    /// dead air is drawn with (a standing one before, a seated one now) and
    /// the amplitude of that dead air is 0 px/s either way, so
    /// `04-ART-DIRECTION.md`'s motion budget is untouched by ADR-005 and this is
    /// where that is true rather than merely claimed.
    ///
    /// It is frame 0 of the *seated* animation, which is `Beat.settled`: the
    /// position every phrase already begins and ends on. So a call opening finds
    /// the body exactly where its phrase starts, and a call closing leaves it
    /// exactly where the phrase left it: the motion stops, and nothing jumps.
    public static let seatedStillSequence = [Beat.settled.frameIndex(inFrameCount: 2)]

    /// **A character stopped at a permission gate holds one frame too.**
    /// [ADR-005 §7]
    ///
    /// This is the third and last thing that stops the body, and it is the only
    /// one of the three that removes motion the room was previously drawing.
    ///
    /// **The defect it fixes was the room asserting the opposite of the truth.**
    /// A `Bash` parked at a dialog is still an *open call*, so until now it kept
    /// playing `terminal`: `S R`, a 250 ms period, the busiest schedule in the
    /// table above. Measured on `fixtures/concurrent-permission-gates.jsonl` at
    /// t=20 s, with two subagents blocked on a human since t=6.45 and t=7.92:
    /// **3 760 px changing every 125 ms** on each of them. The stuck agents were
    /// the two busiest-looking characters in the room, in the one channel this
    /// file's own note measures as the only one that survives `1x`.
    ///
    /// The badge layer never had this bug: `BadgeSelection.isAttention` refuses
    /// to draw `terminal` over a gated `Bash` because "a call parked at a
    /// permission gate is not running", which is ADR-003 §1's sentence. This is
    /// that sentence applied to the body.
    ///
    /// **It needs no carve-out from I2 and no new art.** It removes motion, and
    /// nothing needs a licence to move less; it returns the same one-element
    /// shape `idleSequence` and `seatedStillSequence` already are, so it draws
    /// zero new pixels and adds no manifest key.
    ///
    /// **It does not depend on the attention bubble and must not be made to.**
    /// The `Notification` that raises the bubble arrives 6.0 s *after* the
    /// `PermissionRequest` that arms the gate (four measured occurrences), so
    /// for those six seconds the stillness is the only signal there is. The two
    /// compose rather than duplicate: the bubble says *the room needs you*, the
    /// stillness says *and this one is getting nothing done meanwhile*.
    public static let gatedStillSequence = seatedStillSequence

    /// The frame indices a character plays, given what its badge says, whether
    /// it holds any open call, whether it is stopped at a permission gate, and
    /// how many frames its current animation has.
    ///
    /// - `idle`: standing, which under ADR-005 means *no turn in progress*,
    ///   is `idleSequence`, one held frame.
    /// - `working` with an **empty** open-call set is `seatedStillSequence`, one
    ///   held frame. Seated and still: in a turn, between calls, thinking.
    /// - `working` **at a permission gate** is `gatedStillSequence`, one held
    ///   frame, whatever the badge class says and however many calls are open.
    ///   Seated and still: blocked on a human, getting nothing done.
    /// - `working` with an open call and no gate is the badge class's phrase, or
    ///   the identity sequence for `questionMark` and for `nil`: the shipped
    ///   loop, byte for byte what this app drew before this file existed.
    /// - every other state is the identity sequence. `walk`, `spawn`, `depart`
    ///   and `deliver` each *are* a real event being told, so they play as
    ///   authored whatever the open-call set or the gate says. A character
    ///   cannot be walking and blocked at the same instant in the live stream,
    ///   and if it were, the walk is the event being told and the gate is a
    ///   state: the told event wins, exactly as it does over the open-call set.
    ///
    /// - Parameter openCalls: how many tool calls this character is holding.
    ///   **The fact, not a state name**: this is the one input that decides
    ///   whether the body moves, and it is passed in rather than inferred from
    ///   `state`, because since ADR-005 the state name no longer carries it.
    /// - Parameter isGated: whether this character has an open permission-gate
    ///   mark: `WorldDelta.gateChanged`. Defaulted to `false` so that every
    ///   caller who has nothing to say about a gate says nothing, which is the
    ///   ungated case and is what this function always assumed.
    /// - Parameter raisedFrame: which frame of this animation the manifest
    ///   measured as the raised one. Defaulted to `nil`: the old
    ///   count-derived rule, so that a caller with no measurement in hand asks
    ///   for exactly the behaviour that shipped before it existed.
    public static func sequence(
        for badge: ToolBadge?, state: BodyState, openCalls: Int, isGated: Bool = false,
        frameCount: Int, raisedFrame: Int? = nil
    ) -> [Int] {
        guard frameCount > 0 else { return [0] }
        if state == .idle { return idleSequence }
        let identity = Array(0..<frameCount)
        guard state == .working else { return identity }
        guard openCalls > 0 else { return seatedStillSequence }
        // Third, and after the open-call test rather than before it only because
        // the two agree: a gated agent with an empty set is still and a gated
        // agent holding five calls is still, and the empty case has the older
        // reason. [ADR-005 §7]
        guard !isGated else { return gatedStillSequence }
        guard let phrase = phrase(for: badge) else { return identity }
        return phrase.map {
            $0.frameIndex(inFrameCount: frameCount, raisedFrame: raisedFrame)
        }
    }
}
