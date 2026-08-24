import Foundation
import Testing

@testable import SpriteRoomApp
@testable import SpriteRoomScene

/// `ThemeCatalog.declared(in:)` is the adapter between the manifest and the
/// menu bar, and for a while it was a stub returning `.empty`.
///
/// **That stub was invisible to the whole suite.** Every other theme-menu test
/// builds its catalog by hand (correctly, because they are testing the menu,
/// not the manifest), and `.empty` is *also* the legitimate answer for a
/// checkout with no art. So the one thing nothing checked was whether the
/// adapter reads the manifest at all, and the symptom of the regression is a
/// `Room ▸` submenu that is silently empty in the shipped app while every test
/// stays green.
///
/// It is the same shape as the two stubs it sat beside: `RoomHost.derive`
/// returning `nil`, `SceneBinding` not forwarding a theme. Each was a declared
/// seam with its reasoning attached, left open because the other half did not
/// exist yet, and nothing closed the loop when it did. This is the loop.
@Suite struct ThemeCatalogAdapterTests {

    static let manifest: Manifest? = try? Manifest.load(root: Manifest.developmentRoot())

    /// The shipped manifest declares themes, and the adapter surfaces them.
    ///
    /// Asserts against the manifest rather than a literal list, so adding a
    /// theme does not break this and *removing every* theme does.
    @Test func theCatalogSurfacesEveryThemeTheManifestDeclares() throws {
        let manifest = try #require(Self.manifest, "the tracked manifest did not load")
        #expect(!manifest.themes.isEmpty, "the manifest itself declares no themes")

        let catalog = ThemeCatalog.declared(in: manifest)

        #expect(catalog.themes.count == manifest.themes.orderedIDs.count)
        #expect(Set(catalog.themes.map(\.id)) == Set(manifest.themes.orderedIDs))
        #expect(catalog.defaultThemeID == manifest.themes.defaultID)
    }

    /// Every field the menu draws comes from the manifest, not from a default.
    ///
    /// A catalog that returned the right *ids* with blank titles would list six
    /// unreadable rows, so the title is checked too, and `isAssignable` is what
    /// keeps the derived default from picking a room that reads as a claim about
    /// the work [ADR-002 §3e], which is worth more than a menu label.
    @Test func everyThemeCarriesItsTitleAndAssignability() throws {
        let manifest = try #require(Self.manifest)
        let catalog = ThemeCatalog.declared(in: manifest)

        for theme in catalog.themes {
            let declared = try #require(manifest.themes.theme(theme.id))
            #expect(theme.title == declared.title)
            #expect(!theme.title.isEmpty, "\(theme.id) would draw a blank menu row")
            #expect(theme.isAssignable == declared.isAssignable)
        }
    }

    /// `.empty` stays the honest answer for a manifest with no themes (that is
    /// a checkout that predates them, not a defect), so the adapter must not
    /// invent one. Proving both directions is what stops "fix the stub" from
    /// becoming "hard-code six".
    ///
    /// The themeless manifest is the tracked one with its `themes` key removed
    /// and decoded for real, rather than a value built by hand: `Manifest` has
    /// no public initialiser and is only ever produced by the decoder, so a
    /// hand-built one would be testing a shape the app can never receive.
    @Test func aManifestWithNoThemesStillYieldsAnEmptyCatalog() throws {
        let root = Manifest.developmentRoot()
        let source = try Data(contentsOf: root.appending(path: "assets/manifest.json"))
        var object = try #require(
            try JSONSerialization.jsonObject(with: source) as? [String: Any])
        #expect(object["themes"] != nil, "the manifest no longer has a themes key to strip")
        object.removeValue(forKey: "themes")

        let stripped = URL.temporaryDirectory
            .appending(path: "spriteroom-themeless-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: stripped)
        defer { try? FileManager.default.removeItem(at: stripped) }

        let manifest = try Manifest.load(contentsOf: stripped, root: root)
        #expect(manifest.themes.isEmpty)

        let catalog = ThemeCatalog.declared(in: manifest)
        #expect(catalog.themes.isEmpty)
        #expect(catalog.defaultThemeID == nil)
    }
}
