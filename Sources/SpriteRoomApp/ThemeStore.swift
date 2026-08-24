import Foundation

/// `~/Library/Application Support/SpriteRoom/themes.json`: the per-project
/// room theme, and **the first thing this app has ever persisted**.
///
/// `docs/ADR-002-themed-rooms.md` §3d specifies this file completely, and it
/// specifies it as an architectural change rather than a detail, because
/// `docs/02-ARCHITECTURE.md` had to be corrected once already for describing a
/// configuration file that did not exist. This is the deliberate addition that
/// paragraph asks for.
///
/// Two things it is not. It is **not a general preferences store**: schema 1
/// holds themes and nothing else, and the next preference is a new ADR, not a
/// new key (§9). And it is **not a file a user is expected to hand-edit**.
///
/// **Never on a hook path.** The read happens once, at launch. The write
/// happens when a human picks something off a menu. Nothing downstream of
/// ingest touches this type, because nothing downstream of ingest may touch a
/// disk. [I5]
///
/// `@MainActor` for the same reason `ProjectSelector` is: both ends of this
/// object's life are main-actor work (constructed on the launch path, written
/// from a menu action), so it needs no lock and no `@unchecked Sendable`.
@MainActor
final class ThemeStore {

    /// What happened when we read the file. Kept because "the user's choices
    /// silently went away" and "the user had no choices" are different events
    /// and only one of them is worth anything in a log.
    enum Load: Equatable {
        /// No file. The first-run case, and not a failure.
        case fresh
        case loaded(count: Int)
        /// Unusable, set aside at `themes.json.bad`, and started again.
        case discarded(String)
    }

    /// Bumped only by an ADR. §9: "A second preference in `themes.json`.
    /// Schema 1 holds themes."
    static let schema = 1

    let url: URL

    /// `cwd` → theme id, exactly as §3d's format says: the keys are the `cwd`
    /// strings the events carried, with no normalisation of our own.
    private(set) var stored: [String: String] = [:]

    private(set) var load: Load = .fresh

    /// "Write failures are counted, not surfaced." (§3d). A read-only home
    /// directory means the picker works for this launch and forgets on the
    /// next. That is a degradation the user can live with; a modal dialog about
    /// a desk skin is not.
    private(set) var writeFailures = 0

    /// Reads the file. **Once, and it cannot throw.**
    ///
    /// Every one of §3d's failure modes (missing, unreadable, not JSON, wrong
    /// `schema`, `themes` not an object) means the same thing: no stored
    /// choices. The app launches and every project takes its derived theme. A
    /// theme preference is not something to fail a launch over, and an
    /// initialiser that could throw is an initialiser someone eventually calls
    /// with `try!`.
    init(url: URL) {
        self.url = url

        guard let data = try? Data(contentsOf: url) else {
            // Missing, or a directory, or unreadable. Indistinguishable from
            // here and identical in consequence.
            load = .fresh
            return
        }
        guard let entries = Self.decode(data) else {
            load = .discarded(Self.setAside(url))
            return
        }
        stored = entries
        load = .loaded(count: entries.count)
    }

    convenience init() {
        self.init(url: Self.defaultURL())
    }

    subscript(cwd: String) -> String? { stored[cwd] }

    /// Whether this project has a pick of its own, as opposed to the room §3c
    /// derives for it from `cwd`.
    ///
    /// The menu needs this and `themeID` cannot answer it: §3c is one function
    /// and a stored choice and a derived one come back indistinguishable, which
    /// is right for *what the room is* and useless for *whether there is
    /// anything to undo*.
    func hasChoice(for cwd: String) -> Bool { stored[cwd] != nil }

    /// The user picked a theme for this project. One of the two things that
    /// write this file.
    ///
    /// In memory first, then to disk: a write that cannot happen must not cost
    /// the user the pick they just made for the session they are in.
    ///
    /// **No eviction** (§3d). Entries are a few dozen bytes and a project you
    /// have not opened in a year is exactly the one whose choice you would be
    /// annoyed to lose. An entry naming a theme the manifest no longer has is
    /// left alone too: the theme may come back.
    func choose(_ themeID: String, for cwd: String) {
        stored[cwd] = themeID
        persist()
    }

    /// The user asked for the derived room back. The other thing that writes
    /// this file, and the inverse of `choose`.
    ///
    /// **This is not eviction.** §3d's "no eviction" is about what *this app*
    /// may drop on its own: nothing here ages an entry out, garbage-collects
    /// one, or drops the choice of a project you have not opened in a year. A
    /// person taking their own pin out is the opposite: a preference that can
    /// be set and not un-set is a trap, and the way out of a bad pick would
    /// otherwise be hand-editing a file §3d says is not for hand-editing.
    ///
    /// Removing the key rather than storing a sentinel keeps §3c's first line
    /// exactly as written, "`stored[cwd]` if it names a theme in the manifest",
    /// and keeps the file's shape to the one schema 1 declares.
    ///
    /// A project with no entry is already the common case, so this writes
    /// nothing when there is nothing to remove: no file is created by asking a
    /// question whose answer is already "the derived one".
    func clearChoice(for cwd: String) {
        guard stored.removeValue(forKey: cwd) != nil else { return }
        persist()
    }

    // MARK: - Reading

    /// `{"schema": 1, "themes": {"<cwd>": "<themeId>"}}`, or `nil` for anything
    /// that is not exactly that.
    ///
    /// Every rejection is silent and total. Salvaging half a file we cannot
    /// read is how a preference store starts guessing.
    private static func decode(_ data: Data) -> [String: String]? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schema"] as? Int == schema,
              let themes = object["themes"] as? [String: Any]
        else { return nil }

        var entries: [String: String] = [:]
        for (cwd, value) in themes {
            guard let id = value as? String else { return nil }
            entries[cwd] = id
        }
        return entries
    }

    /// "A file that fails to parse is renamed once to `themes.json.bad` and a
    /// fresh one is started, so a corrupt file cannot wedge the picker forever
    /// and the user's bytes are still on disk if they want them." (§3d).
    ///
    /// Applied to every unusable shape, not only to malformed JSON: a file with
    /// the wrong `schema` would wedge the picker just as thoroughly, and the
    /// sentence's stated purpose is about wedging. Nothing is deleted either
    /// way: the bytes move, they do not go.
    ///
    /// "Once" is the count per launch. A second bad file overwrites the first
    /// rather than accumulating `.bad.bad`, since we read at launch and only
    /// ever write good files afterwards.
    private static func setAside(_ url: URL) -> String {
        let bad = url.appendingPathExtension("bad")
        // Moved rather than copied, so the next launch is a clean `.fresh`
        // rather than another `.discarded` over the same bytes.
        try? FileManager.default.removeItem(at: bad)
        guard (try? FileManager.default.moveItem(at: url, to: bad)) != nil else {
            // A read-only parent directory. Nothing to be done, and nothing
            // that needs doing: the caller still launches with no stored
            // choices, and the user's bytes are still where they were.
            return url.path
        }
        return bad.path
    }

    // MARK: - Writing

    /// Atomic, in the shape §3d spells out: a sibling temp file and a `rename`
    /// over the target, so a crash mid-write cannot leave a truncated file.
    ///
    /// `Data.write(options: .atomic)` is that mechanism: Foundation writes a
    /// temp file in the *same directory* and renames it into place, which is
    /// why the temp has to be a sibling: `rename(2)` is only atomic within a
    /// filesystem. It is spelled out here because "atomic" is the property and
    /// the option name is the implementation, and the two are easy to conflate
    /// on the day someone swaps this for a stream.
    private func persist() {
        do {
            let object: [String: Any] = ["schema": Self.schema, "themes": stored]
            var data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            data.append(0x0A)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            writeFailures += 1
        }
    }

    // MARK: - Location

    /// Beside `settings-backup.json`, in the directory this app already owns.
    /// §3d: "no new location is introduced".
    ///
    /// That directory holds the copy of the user's `~/.claude/settings.json`
    /// taken at hook install, which is what `--remove-hooks` restores from byte
    /// for byte. Nothing here goes near it.
    static func defaultURL() -> URL {
        HookInstaller.supportDirectory().appending(path: "themes.json")
    }
}
