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

    public init(scales: [Int] = [3, 2, 1], comfortablePopulation: [Int: Int]? = nil) {
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
        // **It stays empty for a second reason, and this one is arithmetic
        // rather than taste: on the panel this app ships, nothing above `1x`
        // fits, at any population and under any arrangement of the seats.** The
        // panel is 720×400, so `2x` frames 360×200 unscaled pixels and `3x`
        // frames 240×133. Against that, from the manifest and `RoomLayout`:
        //
        // - *Height.* One seated character reserves **85 px** of badge above its
        //   own feet and **23 px** of nameplate below them — 108 of the 200,
        //   before a single tile of floor. The two seat rows are 64 px apart, the
        //   walkway is 32 px in front of them, and the report choreography
        //   reserves one delivery row per ring below *that*, 96 px. The content
        //   band is 108 + 64 + 32 + 96 = **300**. Deleting every delivery row
        //   outright still leaves 204, and folding the seats deeper makes it
        //   worse, not better, because depth is the axis a cluster spends.
        // - *Width.* `RoomLayout.occupiedSpan` pads one seat to 160 px and the
        //   seat pitch is 96, so 360 px holds three seat columns (352) and not
        //   four (448). Seven agents span **736**.
        //
        // The width alone would look answerable by clustering the seats — it is
        // not, and `RoomLayout.isBackRow(seat:)` carries why a narrower room
        // cannot be built at all — but even a free answer to the width would
        // leave the height, and the height is mostly art this file does not
        // control. The largest room that fits a `2x` frame is three seats on one
        // row, which is not this product.
        //
        // `aCloserScaleDoesNotFitTheShippedPanel` pins all of it mechanically,
        // so a future change that *does* make a closer scale reachable fails a
        // test and is told to come back here, rather than silently doing nothing
        // because this table is empty.
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
