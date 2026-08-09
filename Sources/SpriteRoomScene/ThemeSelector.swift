import Foundation

/// Which room a project gets, and which station an agent sits at.
///
/// Pure arithmetic over strings. **No SpriteKit type appears in any signature
/// here**, for the same reason `RoomCamera` has none: these are the rules, and
/// rules that need a screen to exercise are rules nobody exercises.
/// [ADR-002 §8, items 1–4]
///
/// Everything below is *derived* in `docs/ADR-002-themed-rooms.md` §2b's sense:
/// a total function of a datum we already hold, whose output claims nothing the
/// datum does not establish. `theme(for:)` says "this is project X, and project
/// X is a different project from that one", which is exactly what a `cwd` is.
/// It does not say what the project is *about*, and nothing here may ever be
/// taught to. [§3b, §14 item 1]
public enum ThemeSelector {

    // MARK: The hash — §8 item 1

    /// FNV-1a, 64-bit, over raw bytes.
    ///
    /// **Not Swift's `Hasher`, and this is the whole reason this function
    /// exists.** `hashValue` is seeded per process, so the same `cwd` would draw
    /// a different room on every launch — the exact requirement themes exist to
    /// satisfy, violated in a way that reads as a rendering bug rather than as a
    /// hash bug. `ThemeSelectorTests.thePinnedVector…` pins the mapping so that
    /// a well-meaning refactor to `Hasher` turns a test red instead of quietly
    /// redecorating every user's rooms. [§3c, §11 item 7]
    ///
    /// The two constants are the published ones and are written as literals
    /// rather than derived, because they are the specification.
    public static func fnv1a64(_ bytes: some Sequence<UInt8>) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }

    /// The same hash over a string's UTF-8. Spelled once here so that no caller
    /// gets to choose an encoding.
    public static func fnv1a64(_ text: String) -> UInt64 { fnv1a64(text.utf8) }

    // MARK: Rendezvous — §8 item 2

    /// Separates the key from the candidate id inside the hashed string.
    ///
    /// `U+0001`, because it cannot occur in a path, an `agent_type` or a theme
    /// id, so `("ab", "c")` and `("a", "bc")` can never hash to the same bytes.
    public static let keySeparator = "\u{1}"

    /// Highest-random-weight selection: the id maximising
    /// `fnv1a64(key + separator + id)`.
    ///
    /// **Rendezvous rather than `hash(key) % count`, and the difference is the
    /// point.** Modulo renumbers everything the day a theme is added; rendezvous
    /// moves about one key in N. `ThemeSelectorTests.addingAThemeMoves…`
    /// measures that over a corpus rather than asserting it.
    ///
    /// Ties go to the lexicographically smaller id. That is not decoration: a
    /// 64-bit collision without it would make the room depend on the order the
    /// caller happened to build its array in. [§3c]
    ///
    /// `nil` for an empty pool — there is nothing to pick, and saying so is the
    /// caller's cue to fall to its own floor rather than receive a guess.
    public static func rendezvous(key: String, over ids: [String]) -> String? {
        var best: (id: String, score: UInt64)?
        for id in ids {
            let score = fnv1a64(key + keySeparator + id)
            guard let current = best else {
                best = (id, score)
                continue
            }
            if score > current.score || (score == current.score && id < current.id) {
                best = (id, score)
            }
        }
        return best?.id
    }

    // MARK: The theme — §8 item 3

    /// §3c, in the order §3c gives it:
    ///
    /// ```
    /// theme(cwd) =
    ///     stored[cwd]                      if stored[cwd] names a theme in the manifest
    ///     rendezvous(cwd, assignablePool)  otherwise
    ///     the manifest's default           if the pool is empty
    /// ```
    ///
    /// **Keyed on `cwd` exactly as received.** That is already the project
    /// bucket everywhere else in this app — a trailing slash or a symlink is
    /// already a different project — so the theme inherits that behaviour rather
    /// than inventing a normalisation of its own. [§3c]
    ///
    /// A stored entry naming a theme the manifest does not have falls through to
    /// the derived default *for this call only*. The caller does not delete the
    /// entry: the theme may come back. [§3d]
    ///
    /// **Returns `String?`, where §8 item 3 wrote `String`.** There is no theme
    /// id to name when the manifest declares no themes at all — a checkout with
    /// no art, and every user who has not run the import scripts — and the
    /// honest answer there is "none", not an invented sentinel. `nil` means
    /// *draw `manifest.room`*, which is the room this app has always drawn and
    /// which §14a establishes **is** the resolved default theme. The divergence
    /// is recorded in the implementation report; `SpriteRoomApp`'s already
    /// shipped `ThemeCatalog.themeID(for:stored:derive:)` returns `String?` for
    /// this same reason, so this is the signature the seam actually needed.
    public static func theme(
        for cwd: String, stored: [String: String], manifest: Manifest
    ) -> String? {
        if let chosen = stored[cwd], manifest.themes.contains(chosen) { return chosen }
        if let drawn = rendezvous(key: cwd, over: manifest.themes.assignableIDs) { return drawn }
        return manifest.themes.defaultID
    }

    // MARK: The station — §8 item 4

    /// The main thread's seat. Every theme is required to bind it. [§7]
    ///
    /// Distinguishing it is honest rather than decorative: `agent_id`'s absence
    /// *is* the main agent, which is the identity rule. [CLAUDE.md]
    public static let mainStationID = "main"

    /// A subagent whose type we were not told — the `question_mark` of
    /// furniture. A separate binding from `main`, because they say different
    /// things. [§4]
    public static let defaultStationID = "default"

    /// §4 as amended by §14c, total by construction:
    ///
    /// ```
    /// station(agent) =
    ///     "main"                                          if agent_id is absent
    ///     "default"                                       if agent_type is absent or ""
    ///     roles[agent_type]                               if the theme names that exact type
    ///     rendezvous(agent_type, theme.assignableStations) otherwise
    ///     "default"                                       if the pool is empty
    /// ```
    ///
    /// **The two tiers are the whole of I1 here, and they are the same two the
    /// wardrobe has** — see `costume(agentID:agentType:in:)`, whose doc argues
    /// it at length. A station says what kind of worker sits at it, and whether
    /// that is true depends entirely on how it was reached: through `roles` it
    /// is a translation of the exact `agent_type` a session produced, which is
    /// the licence the nameplate already runs on; through the hash it must claim
    /// nothing, so the hash's range is a pool whose members are neutral by
    /// contract.
    ///
    /// **Exact match, no folding**, for the same reason `cwd` is not normalised:
    /// `agent_type` is the user's own string and this app does not invent
    /// normalisations of those. A manifest that wants `Explore` and `explore` to
    /// agree lists both.
    ///
    /// **Empty and absent `agent_type` take the same branch**, and that is a
    /// measurement rather than defensiveness: M0c observed `agent_type` arriving
    /// as the empty string. [§2a, `docs/03-EVENT-MODEL.md`]
    ///
    /// Keyed on `agent_type`, never on `agent_id`. Four `general-purpose`
    /// subagents therefore get four identical desks, deliberately: "same desk
    /// means same kind of worker" is a rule a user learns in one glance, and
    /// keying on `agent_id` would spend the station's only meaning on variety.
    /// [§4]
    ///
    /// **The empty-pool case is not in §8 and is resolved here** — a theme that
    /// declares no assignable stations seats every typed subagent at `default`,
    /// because `default` is already this function's answer for "we have nothing
    /// that distinguishes this agent".
    public static func station(
        agentID: String?, agentType: String?, in theme: Manifest.Theme
    ) -> String {
        // Absence, not emptiness. `AgentID` in `SpriteRoomCore` is where the
        // main thread is decided; this mirrors it and does not second-guess it.
        guard agentID != nil else { return mainStationID }
        guard let agentType, !agentType.isEmpty else { return defaultStationID }
        if let named = theme.stationRoles[agentType] { return named }
        return rendezvous(key: agentType, over: theme.assignableStationIDs) ?? defaultStationID
    }

    // MARK: The costume

    /// What this agent is wearing, or `nil` for the clothes the cast came in.
    ///
    /// ```
    /// costume(agent) =
    ///     nil                            if agent_id is absent
    ///     nil                            if agent_type is absent or ""
    ///     roles[agent_type]              if the wardrobe translates that exact name
    ///     rendezvous(agent_type, pool)   otherwise
    ///     nil                            if the pool is empty
    /// ```
    ///
    /// **The two tiers are the whole of I1 here, and they are not the same
    /// rule.** A costume can say something — a lab coat says *this agent tests
    /// things* — and whether that is true depends entirely on how it was
    /// reached:
    ///
    /// - **Reached by `roles`, it is a translation.** The key is the exact
    ///   `agent_type` the user typed. If they called an agent `test-engineer`
    ///   and the manifest translates that name into a coat, the room is
    ///   repeating a name the user chose, which is the same licence the
    ///   nameplate already runs on. Nothing was inferred at any arrow.
    /// - **Reached by the hash, it must claim nothing.** An `agent_type` nobody
    ///   anticipated is arbitrary text and nothing in it licenses a costume that
    ///   asserts. So the hash draws only from `assignableIDs`, whose members are
    ///   neutral by contract, and "different clothes" then says exactly and only
    ///   *these are different agents* — which is exactly and only what we know.
    ///   It is `question_mark`'s answer worn instead of drawn.
    ///
    /// Keyed on `agent_type`, never on `agent_id`, for §4's reason: two
    /// `general-purpose` subagents are the same kind of worker and dressing them
    /// differently would spend the channel's meaning on variety. `nil` for the
    /// main thread is not a gap — absence of `agent_id` **is** the main agent,
    /// and it wears the cast's own clothes because there is no type to translate.
    ///
    /// **Exact match, no folding.** `agent_type` is the user's own string and
    /// this app does not invent normalisations of those — the same decision
    /// `theme(for:stored:manifest:)` makes about `cwd`. A wardrobe that wants
    /// `Explore` and `explore` to agree lists both.
    public static func costume(
        agentID: String?, agentType: String?, in costumes: Manifest.Costumes
    ) -> String? {
        guard agentID != nil else { return nil }
        guard let agentType, !agentType.isEmpty else { return nil }
        if let named = costumes.roles[agentType] { return named }
        return rendezvous(key: agentType, over: costumes.assignableIDs)
    }
}
