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

    // MARK: Why the allow-list is empty [see `RoomCamera.init`]

    /// **The empty table is not only a preference; on this panel it is the only
    /// answer that is true.**
    ///
    /// `theRoomIsDrawnWideAtEveryPopulation` records the *decision* to stop
    /// pulling the camera in. This records the *fact* that the decision has
    /// nothing to overrule: at 720×400 — `NotchGeometry.PanelSize.room`, the
    /// panel the app ships — no population fits a scale above the floor, so a
    /// table naming `2` would be ignored by `largestFittingScale` anyway and the
    /// room would go on drawing at `1x` with a comment claiming otherwise.
    ///
    /// It is written as a test because the arithmetic is spread over three
    /// files: the badge height and the head line come from the manifest, the
    /// plate from `SceneBitmaps`, the rows and the delivery reserve from
    /// `RoomLayout`. Any of them can move without anyone noticing this
    /// conclusion moved with it.
    ///
    /// **It is a tripwire, and failing is the useful direction.** A change that
    /// makes a closer scale reachable — a shorter badge, a shallower room, a
    /// panel with more height — fails here, and whoever made it is then holding
    /// the one place that decides whether the camera should use it.
    @Test func aCloserScaleDoesNotFitTheShippedPanel() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let camera = RoomCamera(manifest: manifest)
        // `NotchGeometry.PanelSize.room`, spelled out rather than imported:
        // `SpriteRoomScene` does not depend on `SpriteRoomApp` and must not.
        let panel = (width: 720.0, height: 400.0)

        // Exactly what `RoomScene.applyScale` feeds the camera.
        let headTop = manifest.characters.variants.values.map(\.headTopPx).min() ?? 0
        let badgeTop = Double(manifest.characters.canvas.height - headTop + 1)
            + Double(manifest.badges.canvas.height)
        let plateDrop = Double(SceneBitmaps.maximumNameplateHeight + 2)
        let band = layout.contentBand(
            badgeTopAboveFeet: badgeTop, plateDropBelowFeet: plateDrop)
        let contentHeight = band.top - band.bottom

        // Height settles it on its own, and does so at *every* population,
        // because the band is deliberately not a function of who is on screen.
        #expect(contentHeight > panel.height / 2, Comment(rawValue:
            "the content band is \(contentHeight) px and 2x has"
            + " \(panel.height / 2); if this now fits, revisit"
            + " RoomCamera.comfortablePopulation"))

        for population in 0...layout.seatCapacity {
            // Seat 0 is framed even when empty — `RoomScene.charactersBySeat`.
            let seats = Array(0...max(0, population - 1))
            let span = layout.occupiedSpan(seats: seats)
            let scale = camera.largestFittingScale(
                viewportWidth: panel.width, viewportHeight: panel.height,
                contentWidth: span.maxX - span.minX, contentHeight: contentHeight)
            #expect(scale == 1, "population \(population) fits at \(scale)x")
        }
    }

    /// **How much room a `2x` frame has across, in seats.** Three.
    ///
    /// The half of the refutation that looks answerable by rearranging the
    /// seats, pinned so the answer is a number rather than an impression. Four
    /// columns need 448 px of the 360 a `2x` frame has, and seven need 736.
    @Test func aCloserFrameWouldHoldThreeSeatColumnsAcross() {
        let layout = RoomLayout()
        func widthAtTwo(_ seats: Int) -> Double {
            let span = layout.occupiedSpan(seats: 0..<seats)
            return (span.maxX - span.minX) * 2
        }
        #expect(widthAtTwo(3) <= 720)
        #expect(widthAtTwo(4) > 720)
        #expect(widthAtTwo(layout.seatCapacity) > 720)
    }

    /// **And rearranging cannot answer even that half**, because a room narrower
    /// than one column per seat is a room with two seats in one column, and the
    /// only alternative — interleaving the two rows on a stagger — has no
    /// solution on this pitch. See `RoomLayout.isBackRow(seat:)`.
    ///
    /// A staggered row clears the columns on *both* sides of it only if the
    /// pitch is at least two plates wide. It is 96 against 71.
    @Test func noStaggerCanInterleaveTheTwoSeatRowsOnThisPitch() {
        let layout = RoomLayout()
        let pitch = layout.tile * layout.seatSpacingTiles
        let plate = SceneBitmaps.maximumNameplateWidth
        #expect(pitch < 2 * plate, "a \(pitch) px pitch would fit two \(plate) px plates")
        #expect((1..<pitch).allSatisfy { min($0, pitch - $0) < plate },
                "some offset clears a plate on both sides after all")
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
