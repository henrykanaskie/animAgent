import Foundation

/// **How a dormant character recedes.** [ADR-006 §12]
///
/// One tint, one factor, and no animation of any kind: a character that goes
/// dormant steps from its lit colours to its dimmed ones on the frame the delta
/// arrives, and steps back on the frame it wakes. `Character.refreshDim` is the
/// only caller.
///
/// # Why an instant step and never a fade
///
/// A crossfade is motion, and I2 licenses motion on a character **if and only
/// if** it holds at least one open tool call. A dormant agent holds none —
/// `SubagentStop` abandons every one of them in the same batch that sets
/// dormancy — so a fade would be the one thing this room may not draw: a
/// character animating with no call open. Two still states, and the transition
/// between them takes exactly the frame the fact changed on. This is ADR-005's
/// posture argument on a second channel: *a still frame is not activity.*
///
/// # Tint, not alpha, and the measurement is why
///
/// The plan offered both. Alpha is not available here, and the arithmetic is
/// short enough to show.
///
/// I7's third check is `theme mean value − the character's darkest pixel ≥
/// 0.40`. The shipped numbers, from `scripts/lint-palette.py`: the cast's
/// darkest pixel is **0.314** and the lowest theme mean is `mission_control`'s
/// **0.738**, so the binding character clears the floor at **0.424** — 0.024 of
/// headroom, the tightest number in the whole palette argument.
///
/// **Reducing alpha over a pale room raises that darkest pixel and eats the
/// headroom immediately**, which is the opposite of the intuition that a
/// see-through character recedes safely. Compositing value `v` at alpha `α`
/// over a background of value `b` gives `vα + b(1−α)`:
///
/// | background | contrast at alpha `α` | α needed for 0.40 |
/// |---|---|---:|
/// | the theme's own mean, 0.738 | `0.424 α` | **0.943** |
/// | that theme's darkest ink, 0.604 | `0.134 + 0.29 α` | **0.917** |
///
/// So the entire alpha range I7 permits is roughly `[0.92, 1.0]`: an 8%
/// reduction at best, which is not a signal — it is a rounding error with a
/// mechanism attached. **Alpha is measured out, not judged out.**
///
/// A tint toward a colour **at or below** the cast's own darkest value has the
/// opposite sign: every character pixel moves toward that value, so the darkest
/// pixel cannot rise and the contrast cannot fall. The dim recedes by giving up
/// **saturation and internal value structure** — the two channels I7 hands the
/// cast — rather than by giving up presence, which is the honest thing for a
/// character that is still in the room.
///
/// # The numbers this ships with
///
/// Measured over every opaque pixel of all 94 frames × 6 variants in
/// `assets/processed/characters/32x32/`, and re-measured by
/// `CharacterDimTests` rather than trusted from this comment:
///
/// | | lit | dimmed | floor |
/// |---|---:|---:|---:|
/// | cast peak saturation | 1.000 (var 09) | **0.520** | — |
/// | cast darkest value | 0.314 | **0.304** | — |
/// | contrast vs `mission_control`'s 0.738 mean | 0.424 | **0.434** | 0.40 |
/// | cast mean value | 0.533 | **0.369** | — |
///
/// The contrast **improves**, from 0.424 to 0.434, so the dim moves away from
/// I7's floor rather than toward it and the tightest number in the palette
/// argument is not made tighter by this feature.
public enum CharacterDim {

    /// **The colour a dormant character is tinted toward** — `(58, 58, 80)`.
    ///
    /// Not a new ink: it is `HeldObjectArt.outline`, already authored, already
    /// ratified, and already drawn *on* a character. Its own doc comment records
    /// why it is allowed to be as dark as it is — "`HeldObjectArt` is allowed
    /// `(58, 58, 80)` precisely because it is drawn on a character and is
    /// measured against the cast's floor instead" (`DeskWorkArt`, "What is not
    /// available") — and its value is **0.314**, which is the cast's darkest
    /// pixel to three decimal places.
    ///
    /// **That equality is the whole safety argument and it is why this colour
    /// rather than a taste.** Blending is a per-channel lerp, so no channel of
    /// any result can exceed the larger of the two inputs' channels; with a tint
    /// whose value equals the cast floor, no dimmed pixel can be brighter than
    /// the cast's darkest lit pixel *is*. The I7 contrast check therefore cannot
    /// be weakened by this feature at **any** factor between 0 and 1, which is a
    /// stronger statement than "the shipped factor is safe" and is the one
    /// `theDimCannotWeakenI7sContrastFloorAtAnyFactor` asserts.
    public static let tint = Bitmap.RGBA(58, 58, 80)

    /// **How far toward `tint` a dormant character is taken** — `0.65`.
    ///
    /// Derived from the two saturation thresholds `scripts/lint-palette.py`
    /// already enforces, rather than chosen by eye:
    ///
    /// - `CHAR_MIN_SAT = 0.55` — every *lit* character must carry a colour above
    ///   it. It is the line that says "this is a working member of the cast".
    /// - `ROOM_MAX_SAT = 0.25` — nothing in the room may reach it. It is the
    ///   line that says "this is scenery".
    ///
    /// > **A dormant character sits in the gap between them: it no longer
    /// > carries the saturation I7 reserves for the cast, and it has not become
    /// > scenery either.**
    ///
    /// That is a two-sided criterion with a measured answer. Cast-wide peak
    /// saturation against the factor, over the shipped art:
    ///
    /// | factor | 0.55 | 0.60 | **0.65** | 0.70 | 1.00 |
    /// |---|---:|---:|---:|---:|---:|
    /// | peak saturation | 0.642 | 0.585 | **0.520** | 0.447 | 0.275 |
    ///
    /// The threshold is first crossed at 0.63; **0.65 is the smallest twentieth
    /// that clears it**, which is the quantisation this repository already uses
    /// when a measurement lands between round numbers (`SceneDirector
    /// .deskObjectDwell` took the largest whole second under a measured 4.226 s
    /// for the same reason). The lower bound needs no factor at all: the tint's
    /// own saturation is 0.275, so no blend of any strength can fall under the
    /// room's 0.25 ceiling. **A dimmed character can never be mistaken for
    /// furniture, at any factor, by construction.**
    ///
    /// Both bounds are asserted by `CharacterDimTests
    /// .theDimmedCastSitsBetweenTheTwoSaturationThresholds`, which measures the
    /// real PNGs and fails if this constant moves past either.
    public static let factor: Double = 0.65

    /// One pixel, dimmed. The blend `SKSpriteNode.colorBlendFactor` performs — a
    /// per-channel linear interpolation toward `color`, with alpha untouched —
    /// written out here so the measurement can be made without a renderer and
    /// the silhouette's invariance is visible rather than assumed.
    ///
    /// **Alpha is carried through unchanged**, which is the silhouette staying
    /// exactly where it was: the dim is a colour change and never an outline
    /// change, so nothing about M0's silhouette findings, the badge slot's
    /// clearances or the seated head's occlusion arithmetic moves with it.
    public static func dimmed(_ colour: Bitmap.RGBA, factor: Double = CharacterDim.factor)
    -> Bitmap.RGBA {
        func blend(_ from: UInt8, _ to: UInt8) -> UInt8 {
            let value = Double(from) * (1 - factor) + Double(to) * factor
            return UInt8(max(0, min(255, value.rounded())))
        }
        return Bitmap.RGBA(
            blend(colour.r, tint.r), blend(colour.g, tint.g), blend(colour.b, tint.b), colour.a)
    }
}
