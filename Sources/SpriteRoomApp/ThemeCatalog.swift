import Foundation
import SpriteRoomScene

/// The themes the manifest declares, as `SpriteRoomApp` needs to see them.
///
/// This is `docs/ADR-002-themed-rooms.md` §7's contract narrowed to the two
/// things the menu bar has any business knowing: what may be listed, and what
/// the derived default may be drawn from. The bindings themselves — floors,
/// walls, stations, backdrops, poses — are the scene's, and nothing here has an
/// opinion about them.
///
/// It is **not** a theming engine. `CLAUDE.md`: "No speculative generality. No
/// plugin systems, no theming engine." There is no registry, no protocol and no
/// loader here; a theme is manifest data and this is a list of what the
/// manifest said.
///
/// **No theme name appears in this file, and none may.** [ADR-002 §8 item 5]
struct ThemeCatalog: Sendable, Equatable {

    struct Theme: Sendable, Equatable {
        /// The manifest key. This, never the title, is what is stored and
        /// compared — a title is prose and may be reworded.
        let id: String
        /// What the user reads in the menu.
        let title: String
        /// Whether the *derived default* may draw this theme. §3e.
        ///
        /// Every theme is choosable; only some are assignable. A user who picks
        /// a jail has said something about their project; a hash that picks one
        /// has said it for them.
        let isAssignable: Bool

        init(id: String, title: String, isAssignable: Bool) {
            self.id = id
            self.title = title
            self.isAssignable = isAssignable
        }
    }

    /// Ordered for display: by title, ties by id.
    ///
    /// Dictionary order is not stable and a menu whose items move between
    /// launches is a menu you cannot learn. Sorting on the title rather than
    /// the id is the one place this type prefers what the user reads to what
    /// the manifest says, and it is a menu, so that is the right way round.
    let themes: [Theme]

    /// `defaultThemeId` — the last line of §3c and the floor under every other
    /// answer. `nil` when the manifest declares no themes at all, which is not
    /// a corner: it is a checkout with no art, and it is every user who has not
    /// run the import scripts.
    let defaultThemeID: String?

    init(themes: [Theme], defaultThemeID: String?) {
        self.themes = themes.sorted { ($0.title, $0.id) < ($1.title, $1.id) }
        self.defaultThemeID = defaultThemeID
    }

    /// The room this app ships today: one room, no themes, nothing to pick.
    static let empty = ThemeCatalog(themes: [], defaultThemeID: nil)

    var isEmpty: Bool { themes.isEmpty }

    var ids: [String] { themes.map(\.id) }

    /// The pool the derived default draws from. §3e.
    var assignableIDs: [String] { themes.filter(\.isAssignable).map(\.id) }

    func contains(_ id: String) -> Bool { themes.contains { $0.id == id } }

    func title(for id: String) -> String? { themes.first { $0.id == id }?.title }

    /// §3c, in the order §3c gives:
    ///
    /// ```
    /// theme(cwd) =
    ///     stored[cwd]                      if stored[cwd] names a theme in the manifest
    ///     rendezvous(cwd, assignablePool)  otherwise
    ///     manifest.room.defaultThemeId     if the pool is empty
    /// ```
    ///
    /// **`derive` is a seam, not a parameter.** It is
    /// `ThemeSelector.rendezvous(key:over:)` — §8 item 2 — which lives in
    /// `SpriteRoomScene` because it needs `fnv1a64`, and that hash is pinned by
    /// a test vector there. Reimplementing it on this side of the module
    /// boundary would leave the pinned vector guarding half the mapping, which
    /// is the exact refactor risk §11 item 7 names. So it is handed in, and the
    /// two lines this function *can* answer without a hash — a stored choice
    /// that still exists, and the floor — are answered here.
    ///
    /// When `ThemeSelector.theme(for:stored:manifest:)` lands, this becomes a
    /// call to it and the three lines live in exactly one place.
    ///
    /// Returns `nil` only when the manifest declared nothing at all — there is
    /// then no theme id to name, and the room is the one it has always been.
    func themeID(
        for cwd: String,
        stored: [String: String],
        derive: (_ cwd: String, _ assignablePool: [String]) -> String?
    ) -> String? {
        // Keyed on `cwd` exactly as received. That is already the project
        // bucket everywhere else in this app, and the theme does not invent a
        // normalisation of its own. §3c.
        if let chosen = stored[cwd], contains(chosen) { return chosen }
        if let drawn = derive(cwd, assignableIDs) { return drawn }
        return defaultThemeID
    }
}

// MARK: - The manifest

extension ThemeCatalog {

    /// What `assets/manifest.json` declares under §7's theme contract.
    ///
    /// **This is the seam onto `SpriteRoomScene`, and it is currently open.**
    /// `Manifest` decodes `schema`, `render`, `credit`, `characters`, `badges`
    /// and `room`, and nothing else; it has no `themes` and no
    /// `defaultThemeId`. ADR-002 §8 items 3 and 5 put both on that type, in
    /// that module, and `Sources/SpriteRoomScene/` is another agent's scope.
    ///
    /// So this returns the empty catalog, and that is the correct answer rather
    /// than a placeholder: a manifest that declares no themes has none, the
    /// pool is empty, §3c falls to its last line, and the app draws the single
    /// room it has always drawn. It is also exactly what a user who has not run
    /// the import scripts sees, so the degraded path is not a path only tests
    /// take.
    ///
    /// Reading `assets/manifest.json` a second time from this module was the
    /// alternative and was refused: two decoders over one file drift, and the
    /// manifest reader belongs beside the scene that consumes the bindings.
    ///
    /// When `Manifest.themes` exists, this function is its adapter and nothing
    /// else in `SpriteRoomApp` changes.
    static func declared(in manifest: Manifest) -> ThemeCatalog {
        .empty
    }
}
