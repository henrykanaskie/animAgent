import Foundation

/// A rectangle of RGBA8 pixels, y-down. Pure data, so everything that draws
/// into one is testable without a graphics framework.
public struct Bitmap: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int, fill: RGBA = .clear) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
        if fill != .clear { self.fillAll(fill) }
    }

    public struct RGBA: Sendable, Hashable {
        public var r: UInt8, g: UInt8, b: UInt8, a: UInt8
        public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }
        public static let clear = RGBA(0, 0, 0, 0)
    }

    public mutating func fillAll(_ colour: RGBA) {
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = colour.r
            pixels[index + 1] = colour.g
            pixels[index + 2] = colour.b
            pixels[index + 3] = colour.a
        }
    }

    public mutating func set(_ x: Int, _ y: Int, _ colour: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let index = (y * width + x) * 4
        pixels[index] = colour.r
        pixels[index + 1] = colour.g
        pixels[index + 2] = colour.b
        pixels[index + 3] = colour.a
    }

    public func at(_ x: Int, _ y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        let index = (y * width + x) * 4
        return RGBA(pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])
    }

    public mutating func fill(x: Int, y: Int, w: Int, h: Int, _ colour: RGBA) {
        for row in y..<(y + h) {
            for column in x..<(x + w) { set(column, row, colour) }
        }
    }

    public mutating func stroke(x: Int, y: Int, w: Int, h: Int, _ colour: RGBA) {
        guard w > 0, h > 0 else { return }
        for column in x..<(x + w) {
            set(column, y, colour)
            set(column, y + h - 1, colour)
        }
        for row in y..<(y + h) {
            set(x, row, colour)
            set(x + w - 1, row, colour)
        }
    }

    /// Opaque pixel count. Used by the tests that check a nameplate actually
    /// has ink in it rather than trusting that it does.
    public var opaquePixelCount: Int {
        stride(from: 3, to: pixels.count, by: 4).reduce(0) { $0 + (pixels[$1] > 0 ? 1 : 0) }
    }
}

/// A 5×7 bitmap typeface, embedded as a constant.
///
/// **Why this exists.** No font ships with either LimeZu pack — M0 confirmed
/// there is no `.ttf` or `.otf` anywhere in the files, and the pack previews
/// use Arial Bold, which beside this art looks exactly as wrong as it sounds.
/// A system font rendered at 8pt antialiases, and antialiased text next to
/// nearest-neighbour pixel art is the single most obvious way to make a pixel
/// scene look broken.
///
/// So the nameplate is drawn from a glyph table instead. It is one constant
/// (`PixelFont.standard`) and one call site, so swapping it for a sourced pixel
/// typeface — or for a manifest-declared font, once the manifest carries one —
/// is a local change.
///
/// Since M0 established this art does **not** carry identity in silhouette
/// (the best six-way cast differs by 7.3% of outline and several premades are
/// silhouette-identical), the nameplate is a primary identity channel, not a
/// label. It is drawn with a plate behind it and an accent border so it reads
/// at `1x`. [04-ART-DIRECTION, criterion 5]
public struct PixelFont: Sendable {

    public let glyphWidth = 5
    public let glyphHeight = 7
    /// One pixel of air between glyphs.
    public let tracking = 1

    private let glyphs: [Swift.Character: [UInt8]]

    public static let standard = PixelFont()

    public init() {
        var table: [Swift.Character: [UInt8]] = [:]
        for (character, rows) in Self.source {
            table[character] = rows.map { row in
                var bits: UInt8 = 0
                for (index, pixel) in row.enumerated() where pixel != "." {
                    bits |= UInt8(1 << (4 - index))
                }
                return bits
            }
        }
        self.glyphs = table
    }

    /// Uppercases, and replaces anything with no glyph by a space rather than
    /// dropping it — a missing glyph must not silently shorten a name.
    public func normalise(_ text: String) -> String {
        String(text.uppercased().map { glyphs[$0] != nil ? $0 : Swift.Character(" ") })
    }

    public func width(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.count * (glyphWidth + tracking) - tracking
    }

    /// Truncates to `limit` glyphs with a trailing ellipsis. Names like
    /// `security-reviewer` are wider than the seat spacing; a truncated name
    /// still separates the cast, an overlapping one separates nothing.
    public func fit(_ text: String, limit: Int) -> String {
        let normalised = normalise(text)
        guard normalised.count > limit, limit > 1 else { return normalised }
        return String(normalised.prefix(limit - 1)) + "…"
    }

    /// Draws text into a bitmap at the given top-left origin.
    public func draw(
        _ text: String, into bitmap: inout Bitmap, x: Int, y: Int, colour: Bitmap.RGBA
    ) {
        var pen = x
        for character in normalise(text) {
            if let rows = glyphs[character] {
                for (row, bits) in rows.enumerated() {
                    for column in 0..<glyphWidth where bits & UInt8(1 << (4 - column)) != 0 {
                        bitmap.set(pen + column, y + row, colour)
                    }
                }
            }
            pen += glyphWidth + tracking
        }
    }

    /// Text on its own transparent bitmap.
    public func render(_ text: String, colour: Bitmap.RGBA) -> Bitmap {
        var bitmap = Bitmap(width: max(1, width(of: normalise(text))), height: glyphHeight)
        draw(text, into: &bitmap, x: 0, y: 0, colour: colour)
        return bitmap
    }

    // MARK: The table

    // 5 wide, 7 tall, `#` is ink. Authored as text so it can be read and
    // corrected by eye; packed to bits once at init.
    private static let source: [(Swift.Character, [String])] = [
        (" ", [".....", ".....", ".....", ".....", ".....", ".....", "....."]),
        ("A", [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"]),
        ("B", ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."]),
        ("C", [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."]),
        ("D", ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."]),
        ("E", ["#####", "#....", "#....", "####.", "#....", "#....", "#####"]),
        ("F", ["#####", "#....", "#....", "####.", "#....", "#....", "#...."]),
        ("G", [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."]),
        ("H", ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"]),
        ("I", ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"]),
        ("J", ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."]),
        ("K", ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"]),
        ("L", ["#....", "#....", "#....", "#....", "#....", "#....", "#####"]),
        ("M", ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"]),
        ("N", ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"]),
        ("O", [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."]),
        ("P", ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."]),
        ("Q", [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"]),
        ("R", ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"]),
        ("S", [".####", "#....", "#....", ".###.", "....#", "....#", "####."]),
        ("T", ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."]),
        ("U", ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."]),
        ("V", ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."]),
        ("W", ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"]),
        ("X", ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"]),
        ("Y", ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."]),
        ("Z", ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"]),
        ("0", [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."]),
        ("1", ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."]),
        ("2", [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"]),
        ("3", ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."]),
        ("4", ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."]),
        ("5", ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."]),
        ("6", ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."]),
        ("7", ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."]),
        ("8", [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."]),
        ("9", [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."]),
        ("-", [".....", ".....", ".....", "#####", ".....", ".....", "....."]),
        ("_", [".....", ".....", ".....", ".....", ".....", ".....", "#####"]),
        (".", [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."]),
        (":", [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."]),
        ("/", ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."]),
        ("+", [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."]),
        ("…", [".....", ".....", ".....", ".....", ".....", "#.#.#", "....."]),
        ("×", [".....", ".....", ".#.#.", "..#..", ".#.#.", ".....", "....."]),
    ]
}
