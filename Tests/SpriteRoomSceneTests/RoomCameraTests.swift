import Testing
@testable import SpriteRoomScene

/// [I6] — the camera snaps to integer scales. These are the criterion-4 tests:
/// population in, integer scale out, never a fraction.
struct RoomCameraTests {

    @Test func everyPopulationMapsToAnIntegerOnTheLadder() {
        let camera = RoomCamera.default
        for population in -5...200 {
            let scale = camera.scale(forPopulation: population)
            #expect(camera.scales.contains(scale), "population \(population) → \(scale)")
        }
    }

    @Test func theLadderIsExactlyThreeTwoOne() {
        #expect(RoomCamera.default.scales == [3, 2, 1])
    }

    /// **The room is drawn wide whatever the population.** This replaced
    /// `smallRoomsGetTheCloseView` and `mediumRoomsStepDownOnce`, which pinned
    /// 3x up to two characters and 2x up to five.
    ///
    /// The maintainer looked at the shipped panel and asked for the room to be
    /// bigger from the start — it "doesn't need to be so zoomed in", and the
    /// zoomed-out view "looks fine with the size of the sprites". Population
    /// pulling the camera in made a one-agent room a close-up of one desk
    /// instead of a view of a place.
    ///
    /// The ladder is untouched and still integer [I6]; only the preference
    /// changed. If a future policy wants a closer view again, this is the test
    /// that has to change with it, and it should say why the way this one does.
    @Test func theRoomIsDrawnWideAtEveryPopulation() {
        let camera = RoomCamera.default
        for population in [0, 1, 2, 3, 5, 6, 40] {
            #expect(camera.scale(forPopulation: population) == 1,
                    "population \(population) should get the wide view")
        }
    }

    /// The mechanism is still there, and still works — it is the *default*
    /// that changed, not the type. A camera told that 3x suits two characters
    /// still says so, which is what keeps this a policy change rather than a
    /// quiet deletion of the ladder's upper rungs.
    @Test func aCameraCanStillPreferACloserScaleIfItIsToldTo() {
        let camera = RoomCamera(comfortablePopulation: [3: 2, 2: 5])
        #expect(camera.scale(forPopulation: 2) == 3)
        #expect(camera.scale(forPopulation: 5) == 2)
        #expect(camera.scale(forPopulation: 6) == 1)
    }

    /// There is no level between 2 and 1, and 1 is the floor: below it the art
    /// is being destroyed rather than shrunk.
    @Test func oneIsTheFloorAndTheRoomNeverGoesBelowIt() {
        let camera = RoomCamera.default
        #expect(camera.scale(forPopulation: 6) == 1)
        #expect(camera.scale(forPopulation: 500) == 1)
        #expect(camera.minimumScale == 1)
    }

    @Test func scaleIsMonotonicInPopulation() {
        let camera = RoomCamera.default
        var previous = camera.scale(forPopulation: 0)
        for population in 1...100 {
            let scale = camera.scale(forPopulation: population)
            #expect(scale <= previous, "scale rose from \(previous) to \(scale) at \(population)")
            previous = scale
        }
    }

    @Test func anEmptyRoomStillHasAScale() {
        #expect(RoomCamera.default.scales.contains(RoomCamera.default.scale(forPopulation: 0)))
    }

    // MARK: Viewport fitting

    @Test func aTightViewportStepsDownTheLadderButNeverOffIt() {
        let camera = RoomCamera.default
        // Two characters want 3x; the viewport only has room for 1x.
        let scale = camera.scale(
            forPopulation: 2,
            viewportWidth: 300, viewportHeight: 200,
            contentWidth: 280, contentHeight: 190)
        #expect(scale == 1)
    }

    @Test func aHugeViewportNeverInventsAScaleAboveTheLadder() {
        let camera = RoomCamera.default
        let scale = camera.scale(
            forPopulation: 8,
            viewportWidth: 8000, viewportHeight: 8000,
            contentWidth: 200, contentHeight: 100)
        // Population says 1x. A big window does not promote it.
        #expect(scale == 1)
    }

    @Test func contentThatFitsNowhereStillClampsToTheFloor() {
        let camera = RoomCamera.default
        let scale = camera.scale(
            forPopulation: 1,
            viewportWidth: 100, viewportHeight: 100,
            contentWidth: 5000, contentHeight: 5000)
        #expect(scale == 1)
    }

    @Test func fittingIgnoresPopulationWhenAskedTo() {
        let camera = RoomCamera.default
        #expect(camera.largestFittingScale(
            viewportWidth: 960, viewportHeight: 540,
            contentWidth: 300, contentHeight: 180) == 3)
        #expect(camera.largestFittingScale(
            viewportWidth: 960, viewportHeight: 540,
            contentWidth: 400, contentHeight: 192) == 2)
    }

    @Test func everyFittedResultIsAlsoOnTheLadder() {
        let camera = RoomCamera.default
        for population in 0...20 {
            for width in stride(from: 120.0, through: 2400.0, by: 137.0) {
                let scale = camera.scale(
                    forPopulation: population,
                    viewportWidth: width, viewportHeight: width * 0.5625,
                    contentWidth: 448, contentHeight: 192)
                #expect(camera.scales.contains(scale))
            }
        }
    }

    /// A zero-sized viewport cannot be fitted against, so the population scale
    /// stands unmodified. Under the wide default that is the floor — the point
    /// is that the degenerate path defers to the policy rather than inventing
    /// a scale of its own, which is still what this proves.
    @Test func degenerateDimensionsFallBackToThePopulationScale() {
        #expect(RoomCamera.default.scale(
            forPopulation: 2,
            viewportWidth: 0, viewportHeight: 0,
            contentWidth: 0, contentHeight: 0) == 1)
        // Same call, on a camera that does prefer a closer scale: the fallback
        // follows the policy rather than the floor.
        #expect(RoomCamera(comfortablePopulation: [3: 2]).scale(
            forPopulation: 2,
            viewportWidth: 0, viewportHeight: 0,
            contentWidth: 0, contentHeight: 0) == 3)
    }

    /// The ladder comes from the manifest, so a manifest that changed it would
    /// change the camera without a code change — and the values it declares
    /// must still be integers.
    @Test func theLadderComesFromTheManifest() throws {
        let manifest = try SceneFixtures.manifest()
        let camera = RoomCamera(manifest: manifest)
        #expect(camera.scales == manifest.render.integerScales.sorted(by: >))
        #expect(camera.scales.allSatisfy { $0 >= 1 })
    }
}
