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

    /// Population at or below which each scale is preferred, longest first.
    /// One or two characters get the close view; a crowd gets the wide one.
    public let comfortablePopulation: [Int: Int]

    public static let `default` = RoomCamera()

    public init(scales: [Int] = [3, 2, 1]) {
        let sorted = scales.filter { $0 >= 1 }.sorted(by: >)
        self.scales = sorted.isEmpty ? [1] : sorted
        // 3x up to two characters, 2x up to five, 1x beyond. The thresholds are
        // a judgment call; the *integer-ness* is not.
        self.comfortablePopulation = [3: 2, 2: 5]
    }

    public init(manifest: Manifest) {
        self.init(scales: manifest.render.integerScales)
    }

    /// The floor. Never zero, never fractional.
    public var minimumScale: Int { scales.last ?? 1 }
    public var maximumScale: Int { scales.first ?? 1 }

    /// Scale for a population, ignoring the viewport.
    ///
    /// A negative or zero population is an empty room, which still has to draw
    /// at *some* scale; it gets the closest one.
    public func scale(forPopulation population: Int) -> Int {
        for scale in scales {
            guard let ceiling = comfortablePopulation[scale] else { return scale }
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
