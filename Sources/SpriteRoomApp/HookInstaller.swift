import Foundation

/// Writes and removes SpriteRoom's hook block in `~/.claude/settings.json`.
///
/// **User scope, and only user scope.** Hooks registered once and routed by
/// `cwd` is the whole design; a project-level registration would have to be
/// repeated per project and would leak into repositories that are not ours to
/// write to. `docs/02-ARCHITECTURE.md`.
///
/// Three properties this type exists to guarantee, because the file it edits is
/// the user's live configuration and a bad write breaks every Claude Code
/// session on the machine at once:
///
/// 1. **Additive.** Every other top-level key, and every hook entry that is not
///    ours, survives with its value unchanged.
/// 2. **Reversible.** `remove` takes the file back to what it was. When the
///    file has not been edited by anyone else in the meantime, it is restored
///    **byte for byte** from the copy taken at install time, key order and
///    whitespace included, because re-serialising JSON does not preserve
///    either and "I only changed what I said I would" should be checkable with
///    `diff`.
/// 3. **Recognisable.** Our entries are identified by shape, not by position,
///    so a hand-edited file is still cleaned up correctly.
///
/// Nothing here reads or writes a project-level settings file. Nothing here
/// asks for consent either; that is the caller's job, and it is a separate
/// job on purpose.
struct HookInstaller: Sendable {

    /// The events `docs/03-EVENT-MODEL.md` says we consume, and no others.
    ///
    /// 2.1.224 emits at least sixteen more. An unregistered event costs the
    /// user nothing and costs us nothing (the listener decodes anything that
    /// does arrive to `.unhandled` rather than throwing), so registering only
    /// what we act on is the smaller tax on every tool call.
    static let events = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "SubagentStart",
        "SubagentStop",
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "PostToolBatch",
        "Stop",
        "Notification",
        // ADR-001 (d). Consumed as the *marker* that an agent has a call at a
        // permission gate, never as a close, and never joined to a
        // `tool_use_id`, which it does not carry. Without this line the model
        // consumes an event that never arrives, and a denied call goes back to
        // sitting open for 900 s.
        //
        // Registered with `matcher: "*"`, which is the shape it was captured
        // firing under at M0c, not a guess. A wrong matcher here is a hook
        // that silently never fires and looks like a working install.
        "PermissionRequest",
    ]

    /// `PostToolBatch` was captured working *without* a matcher, and it is the
    /// only close path a permission-denied call has. It is the last entry to
    /// get clever with, so it keeps the shape it was observed under.
    static let eventsWithoutMatcher: Set<String> = ["PostToolBatch", "UserPromptSubmit"]

    /// Seconds the user's session will wait on us before giving up.
    ///
    /// A floor under our own failure: if SpriteRoom is not running, or wedges,
    /// this is the *most* any one event can cost. There is no `async` field on
    /// the HTTP hook schema, so the session blocks. Keep it low. [I5]
    static let timeout = 2

    let settingsURL: URL
    let backupURL: URL
    let port: UInt16

    // MARK: - Reading

    enum State: Equatable {
        /// No hook block of ours, at any port.
        case absent
        /// Ours, pointing at this port.
        case installed(port: UInt16)
        /// Ours, but pointing somewhere else: a stale install from a run on a
        /// different port.
        case installedAtOtherPort(ports: [UInt16])
    }

    func state() throws -> State {
        let object = try read()
        var ports: Set<UInt16> = []
        var found = false
        for entry in ourEntries(in: object) {
            found = true
            if let port = Self.port(ofHookURL: entry) { ports.insert(port) }
        }
        guard found else { return .absent }
        if ports == [port] { return .installed(port: port) }
        return .installedAtOtherPort(ports: ports.sorted())
    }

    // MARK: - Writing

    /// Adds our entry to each consumed event, removing any earlier entry of
    /// ours first so a re-install on a new port does not accumulate.
    ///
    /// Returns the events actually written.
    @discardableResult
    func install() throws -> [String] {
        // A machine that has never had a settings file is the first-run case,
        // not a failure. An empty backup then means "there was nothing here",
        // which is the truth to restore to.
        let original = (try? Data(contentsOf: settingsURL)) ?? Data()
        guard var object = try Self.parse(original) else {
            throw InstallError.notAnObject(settingsURL)
        }

        try writeBackup(original)

        var hooks = (object["hooks"] as? [String: Any]) ?? [:]
        for event in Self.events {
            var registrations = (hooks[event] as? [[String: Any]]) ?? []
            registrations.removeAll { isOurs($0) }
            registrations.append(registration(for: event))
            hooks[event] = registrations
        }
        object["hooks"] = hooks

        try write(object)
        return Self.events
    }

    /// Takes every entry of ours back out.
    ///
    /// Restores the exact original bytes when the rest of the file is
    /// untouched since install; otherwise re-serialises what is left, keeping
    /// anyone else's edits.
    @discardableResult
    func remove() throws -> Bool {
        guard let current = try? Data(contentsOf: settingsURL),
              var object = try Self.parse(current)
        else { return false }

        var removed = false
        var hooks = (object["hooks"] as? [String: Any]) ?? [:]
        for (event, value) in hooks {
            guard var registrations = value as? [[String: Any]] else { continue }
            let before = registrations.count
            registrations.removeAll { isOurs($0) }
            guard registrations.count != before else { continue }
            removed = true
            // An event whose only registration was ours goes away entirely
            // rather than being left as an empty array we invented.
            if registrations.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = registrations
            }
        }
        if hooks.isEmpty {
            object.removeValue(forKey: "hooks")
        } else {
            object["hooks"] = hooks
        }
        guard removed else { return false }

        // The byte-exact path. Only taken when what is left agrees, key for
        // key, with the file we found at install time, so restoring the
        // original bytes cannot silently discard someone else's edit.
        if let backup = try? Data(contentsOf: backupURL),
           let backupObject = try? Self.parse(backup),
           Self.equal(object, backupObject) {
            if backup.isEmpty {
                // There was no settings file before us. Leaving an empty one
                // behind is not "as we found it".
                try? FileManager.default.removeItem(at: settingsURL)
            } else {
                try backup.write(to: settingsURL, options: .atomic)
            }
            return true
        }

        try write(object)
        return true
    }

    // MARK: - The block itself

    var url: String { "http://127.0.0.1:\(port)/hook" }

    func registration(for event: String) -> [String: Any] {
        var entry: [String: Any] = [
            "hooks": [["type": "http", "url": url, "timeout": Self.timeout]]
        ]
        if !Self.eventsWithoutMatcher.contains(event) {
            entry["matcher"] = "*"
        }
        return entry
    }

    /// Ours by *shape*: a native HTTP hook posting to `/hook` on loopback.
    ///
    /// Matching on shape rather than on remembering where we put it is what
    /// makes removal work on a file someone has since hand-edited. The pattern
    /// is narrow enough that nothing else plausibly matches, and everything it
    /// could match is on this machine's loopback anyway.
    func isOurs(_ registration: [String: Any]) -> Bool {
        Self.port(ofHookURL: registration) != nil
    }

    static func port(ofHookURL registration: [String: Any]) -> UInt16? {
        guard let hooks = registration["hooks"] as? [[String: Any]] else { return nil }
        for hook in hooks {
            guard hook["type"] as? String == "http",
                  let url = hook["url"] as? String,
                  let components = URLComponents(string: url),
                  components.host == "127.0.0.1",
                  components.path == "/hook",
                  let port = components.port,
                  let narrowed = UInt16(exactly: port)
            else { continue }
            return narrowed
        }
        return nil
    }

    private func ourEntries(in object: [String: Any]) -> [[String: Any]] {
        guard let hooks = object["hooks"] as? [String: Any] else { return [] }
        return hooks.values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { $0 }
            .filter(isOurs)
    }

    // MARK: - File handling

    enum InstallError: Error, CustomStringConvertible {
        case notAnObject(URL)

        var description: String {
            switch self {
            case .notAnObject(let url):
                return "\(url.path) is not a JSON object; refusing to touch it"
            }
        }
    }

    /// An absent settings file is an empty object, not an error; a machine
    /// that has never had one is the first-run case.
    private func read() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        return try Self.parse(data) ?? [:]
    }

    private static func parse(_ data: Data) throws -> [String: Any]? {
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any]
    }

    /// Deterministic output: sorted keys, two-space pretty printing, and no
    /// escaped slashes so the URLs stay readable. Key *order* is therefore
    /// normalised, which is exactly why `remove` restores the original bytes
    /// rather than re-serialising when it can.
    private func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }

    private func writeBackup(_ original: Data) throws {
        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: backupURL, options: .atomic)
    }

    /// Deep equality over the subset of JSON that can appear in a settings
    /// file. `NSDictionary` compares recursively and by value, which is
    /// precisely what is wanted and is why the objects are not decoded into
    /// Swift types first.
    static func equal(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }
}

// MARK: - First run

/// What the user said when asked whether to register the hooks.
///
/// Split out from the asking so the *decision* is testable without an AppKit
/// modal: the branch that writes to the user's configuration is the part that
/// has to be right, and it should not need a screen to prove.
enum HookConsent: String, Sendable {
    case install
    case decline
}

extension HookInstaller {

    enum FirstRunOutcome: Equatable {
        /// Already registered, at our port. Nothing to ask.
        case alreadyInstalled
        /// Registered, but pointing elsewhere. Re-registering is a fix, not a
        /// first run, but it is still a write, so it still asks.
        case reinstalled(from: [UInt16])
        case installed
        case declined
        case failed(String)
    }

    /// The first-run flow, with the asking supplied by the caller.
    ///
    /// `ask` is `nil` when nobody can be asked (a non-interactive harness),
    /// in which case nothing is written. Silence is not consent.
    func firstRun(ask: () -> HookConsent?) -> FirstRunOutcome {
        let current: State
        do {
            current = try state()
        } catch {
            return .failed("\(error)")
        }
        if case .installed = current { return .alreadyInstalled }

        guard ask() == .install else { return .declined }
        do {
            try install()
        } catch {
            return .failed("\(error)")
        }
        if case .installedAtOtherPort(let ports) = current { return .reinstalled(from: ports) }
        return .installed
    }
}

// MARK: - Quitting

/// What the user said when asked whether to take the hooks back out on the way
/// out of the app.
///
/// Split from the asking for the same reason `HookConsent` is: the branch that
/// writes to the user's configuration has to be right, and it should not need a
/// screen to prove.
enum HookQuit: String, Sendable {
    case remove
    case keep
}

extension HookInstaller {

    enum QuitOutcome: Equatable {
        /// Nothing of ours is in the file. There is nothing to ask about.
        case notInstalled
        /// Asked, and the answer was to leave them, or nobody could be asked.
        /// Either way **nothing was written.**
        case kept
        case removed
        case failed(String)
    }

    /// The quit flow: our hooks are about to start pointing at a process that
    /// no longer exists, so offer to take them out.
    ///
    /// **Why this exists.** The hooks are registered at *user* scope, which is
    /// the whole design: one registration, routed by `cwd`. The cost of that
    /// design is that they fire for every Claude Code session on the machine,
    /// in every project, including while SpriteRoom is not listening. Claude
    /// Code has no `async` field on the HTTP hook schema and no "ignore
    /// failures" flag, so a POST to a dead port surfaces as `ECONNREFUSED` in
    /// the user's session on **every tool call**. A status viewer that degrades
    /// the thing it is watching has inverted its own purpose; I5 says the app
    /// must never surface an error into the user's session, and this is the
    /// same sentence one process boundary further out.
    ///
    /// **Why it asks rather than just doing it.** `~/.claude/settings.json` is
    /// the user's file. The install path asks; removal without asking would be
    /// the app editing that file behind the user's back, which is a worse
    /// failure than the error it prevents, and it would silently undo a
    /// deliberate choice for the user who quits and relaunches all day. The
    /// symmetry is the point.
    ///
    /// `ask` returning `nil` means nobody could be asked (a harness, a
    /// non-interactive run), and the answer to "may I write to your settings"
    /// with nobody present is no.
    ///
    /// Any state that is not `.absent` is offered: entries pointing at some
    /// other port are still ours, and still cost the user a failed POST per
    /// tool call.
    func atQuit(ask: () -> HookQuit?) -> QuitOutcome {
        let current: State
        do {
            current = try state()
        } catch {
            return .failed("\(error)")
        }
        if case .absent = current { return .notInstalled }

        guard ask() == .remove else { return .kept }
        do {
            return try remove() ? .removed : .kept
        } catch {
            return .failed("\(error)")
        }
    }
}

// MARK: - Locations

extension HookInstaller {
    /// `~/.claude/settings.json`, unless a caller points somewhere else.
    ///
    /// Overridable so the install logic can be exercised against a copy: this
    /// is the one file in the system whose real version cannot be treated as a
    /// test fixture.
    static func defaultSettingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude")
            .appending(path: "settings.json")
    }

    /// `~/Library/Application Support/SpriteRoom/`, where
    /// `docs/02-ARCHITECTURE.md` puts our own configuration.
    static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support")
        return base.appending(path: "SpriteRoom")
    }

    /// The real settings file's backup lives with our own configuration; any
    /// other file's backup lives beside it.
    ///
    /// Derived from the settings path rather than fixed, so exercising the
    /// installer against a copy (which is the only safe way to test it)
    /// cannot overwrite the backup that `--remove-hooks` would restore the
    /// user's real file from.
    static func defaultBackupURL(for settings: URL) -> URL {
        if settings.standardizedFileURL == defaultSettingsURL().standardizedFileURL {
            return supportDirectory().appending(path: "settings-backup.json")
        }
        return settings.deletingLastPathComponent()
            .appending(path: settings.lastPathComponent + ".spriteroom-backup")
    }

    init(settingsURL: URL? = nil, backupURL: URL? = nil, port: UInt16) {
        let settings = settingsURL ?? Self.defaultSettingsURL()
        self.settingsURL = settings
        self.backupURL = backupURL ?? Self.defaultBackupURL(for: settings)
        self.port = port
    }
}
