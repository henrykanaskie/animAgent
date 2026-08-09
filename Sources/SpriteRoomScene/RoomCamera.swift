import Foundation

/// Population in, integer scale out. [I6]
///
/// Deliberately free of SpriteKit types so it unit-tests directly — nothing in
/// this file's signatures is anything but `Int` and `Double`. Fractional
/// scaling resamples pixel art into shimmer; there is no level between 2 and 1,
/// and `1x` is the floor because below it the art is being destroyed rather
/// than shrunk.
public struct RoomCamera: Sendable, Hashable {

    /// Descending. Sourced from `render.integer_scales` in the manifest so the
    /// ladder lives in one place.
    public let scales: [Int]

    /// Population at or below which a scale closer than the floor is preferred.
    ///
    /// **Empty by default: the room is drawn wide, at `1x`, whatever the
    /// population.** A scale absent from this table is never preferred on
    /// population grounds — which is why the table is read as an allow-list
    /// rather than "anything unlisted wins", the reading an earlier version
    /// used.
    public let comfortablePopulation: [Int: Int]

    public static let `default` = RoomCamera()

    /// `2x` up to three agents, `1x` from four.
    ///
    /// Three is not a taste. A `2x` frame is 360 px wide and holds **three seat
    /// columns**; seats fill outward from the centre, so the third agent is the
    /// last one whose column is inside that frame. Height stopped being the
    /// binding term at M6f, when the band went 300 → 170 against the 200 a `2x`
    /// view gives; width decides this now, and width says three.
    ///
    /// `3x` is absent because 170 does not fit its 133.
    ///
    /// **The cost, stated so nobody has to discover it:** the camera changes
    /// scale when the fourth agent arrives. That is a visible step, and it is
    /// the price of the ladder being integer [I6] — there is no level between 2
    /// and 1 to slide through. It is paid in exchange for the three features
    /// that are illegible at `1x` and readable at `2x`: costumes (0.00%
    /// silhouette difference, a hue channel), held objects (~90 px), and
    /// stations.
    public static let defaultComfortablePopulation = [2: 3]

    public init(
        scales: [Int] = [3, 2, 1],
        comfortablePopulation: [Int: Int]? = RoomCamera.defaultComfortablePopulation
    ) {
        let sorted = scales.filter { $0 >= 1 }.sorted(by: >)
        self.scales = sorted.isEmpty ? [1] : sorted
        // Was `[3: 2, 2: 5]` — 3x up to two characters, 2x up to five. The
        // maintainer looked at the shipped panel and said the room should be
        // bigger from the start, that it "doesn't need to be so zoomed in", and
        // that the zoomed-out view "looks fine with the size of the sprites".
        //
        // So population no longer pulls the camera in. The room is a *place*
        // first: you see the space and where people are in it, and the sprites
        // are legible at `1x` because that is the size they were drawn for.
        //
        // Note this reverses part of M5's composition fix, which made one agent
        // fill the panel at 3x. That fix was right about the bug it found — the
        // camera framed a nominal box that made 3x unreachable at any
        // population — and overshot on the remedy. The framing arithmetic it
        // corrected stays; only the preference changes.
        //
        // The ladder is untouched and still integer [I6]. Closer scales remain
        // on it and remain reachable through `largestFittingScale`; nothing
        // here forbids a future policy from using them again.
        //
        // **This comment used to carry a second reason, and it has expired.** It
        // said that nothing above `1x` fits the shipped panel at any population,
        // so the table could not have been otherwise. That was true at a 300 px
        // content band. It is not true now, and the honest version is narrower:
        //
        // The panel is 720×400, so `2x` frames 360×200 unscaled pixels and `3x`
        // frames 240×133. Against that, from the manifest and `RoomLayout`:
        //
        // - *Height.* The band is **170**: 51 px of badge slot above the feet and
        //   23 px of plate below them — the character's own art — over 64 px of
        //   seat rows and a 32 px walkway. It **fits `2x`**, with 30 px to spare,
        //   and does not fit `3x`. It was 300 until M6f, which spent two terms:
        //   96 px of delivery row, floor the report beat reserved so a reporter
        //   walking to its anchor crossed nobody, and 34 px of badge, which moved
        //   from above the head to beside it. 96 px is the room's own share now
        //   and it cannot go lower — a room needs its seats and one row of floor
        //   in front of them.
        // - *Width.* `RoomLayout.occupiedSpan` pads one seat to 160 px and the
        //   seat pitch is 96, so 360 px holds three seat columns (352) and not
        //   four (448). Seven agents span **736**.
        //
        // So **width is what holds the camera down now**, and it holds it only
        // above three agents. The width alone would look answerable by clustering
        // the seats — it is not, and `RoomLayout.isBackRow(seat:)` carries why a
        // narrower room cannot be built at all. It *is* partly answerable by
        // narrowing the pitch, which is the plate's number and not a composition
        // one; see `RoomLayout.minimumSeatSpacingTiles(plateWidth:plateHeight:
        // tile:)`. A 64 px pitch would fit four seat columns across a `2x` frame
        // rather than three. Seven is not among them at any plate width: seven
        // columns plus the padding need a pitch of 33 px, and a desk is 32.
        //
        // **The table therefore stays empty as a decision, not as a fact.** A
        // room of one to three agents *could* now be drawn at `2x`, and whether
        // it should is the maintainer's call — the cost is a camera that changes
        // scale as the fourth agent arrives, which is the lurch
        // `theRoomIsDrawnWideAtEveryPopulation` exists to prevent.
        // `theBandFitsACloserScaleAndWidthDecidesWhoGetsIt` pins the arithmetic
        // mechanically, in both directions, so neither the fact nor the decision
        // can drift without a test saying so.
        self.comfortablePopulation = comfortablePopulation ?? [:]
    }

    public init(manifest: Manifest) {
        self.init(scales: manifest.render.integerScales)
    }

    /// The floor. Never zero, never fractional.
    public var minimumScale: Int { scales.last ?? 1 }
    public var maximumScale: Int { scales.first ?? 1 }

    /// Scale for a population, ignoring the viewport.
    ///
    /// A scale is preferred only if `comfortablePopulation` names it *and* the
    /// population is within its ceiling. Anything else falls to the floor, so
    /// an empty table means the wide view always — which is the default.
    ///
    /// An empty or negative population is an empty room, which still has to
    /// draw at *some* scale; it gets the same wide view as a busy one, so the
    /// room does not lurch when the first character arrives.
    public func scale(forPopulation population: Int) -> Int {
        for scale in scales {
            guard let ceiling = comfortablePopulation[scale] else { continue }
            if population <= ceiling { return scale }
        }
        return minimumScale
    }

    /// Scale for a population that also has to fit the room inside a viewport.
    ///
    /// Takes the population's preferred scale and steps *down* the integer
    /// ladder until the content fits, stopping at the floor. It never steps up
    /// — a two-character room in a huge window stays at `3x` rather than
    /// inventing a `7x` that is not on the ladder.
    ///
    /// All dimensions are in the same unit (unscaled scene pixels for content,
    /// device-independent points or backing pixels for the viewport — the
    /// caller picks, consistently).
    public func scale(
        forPopulation population: Int,
        viewportWidth: Double,
        viewportHeight: Double,
        contentWidth: Double,
        contentHeight: Double
    ) -> Int {
        let preferred = scale(forPopulation: population)
        guard viewportWidth > 0, viewportHeight > 0,
              contentWidth > 0, contentHeight > 0 else { return preferred }
        for scale in scales where scale <= preferred {
            let fitsWidth = contentWidth * Double(scale) <= viewportWidth
            let fitsHeight = contentHeight * Double(scale) <= viewportHeight
            if fitsWidth && fitsHeight { return scale }
        }
        // Nothing fits, not even `1x`. The floor holds and the room is cropped;
        // shrinking further would destroy the art. [I6]
        return minimumScale
    }

    /// The largest scale on the ladder at which `content` fits `viewport`,
    /// ignoring population entirely. Same floor rule.
    public func largestFittingScale(
        viewportWidth: Double,
        viewportHeight: Double,
        contentWidth: Double,
        contentHeight: Double
    ) -> Int {
        guard viewportWidth > 0, viewportHeight > 0,
              contentWidth > 0, contentHeight > 0 else { return minimumScale }
        for scale in scales {
            if contentWidth * Double(scale) <= viewportWidth,
               contentHeight * Double(scale) <= viewportHeight {
                return scale
            }
        }
        return minimumScale
    }
}
