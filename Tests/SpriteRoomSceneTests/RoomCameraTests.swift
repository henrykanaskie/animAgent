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
    ///
    /// **A future policy did want one, and this is that change.** The wide-at-
    /// every-population rule held for as long as it was forced: the content
    /// band was 300 px against the 200 a `2x` view of this panel gives, so no
    /// closer scale fitted and the preference was not really a preference. M6f
    /// spent 96 px of delivery rows and 34 px of badge slot to bring the band
    /// to 170, and the question became live again. It is **192** now — one of
    /// those three delivery rows was bought back, so that a reporter arrives
    /// beside the agent it is reporting to — and 192 still fits 200.
    ///
    /// The maintainer's original complaint survives intact where it applies: a
    /// **one-agent** room is still not a close-up of one desk, because `2x` at
    /// population 1 frames 360×200 of room, not a seat. What changed is that
    /// three agents now get a view in which their costumes, stations and held
    /// objects are legible — none of which is true at `1x`.
    @Test func theRoomIsDrawnCloseUntilTheFourthAgentArrives() {
        let camera = RoomCamera.default
        for population in [0, 1, 2, 3] {
            #expect(camera.scale(forPopulation: population) == 2,
                    "population \(population) should get the close view")
        }
        for population in [4, 5, 6, 7, 40] {
            #expect(camera.scale(forPopulation: population) == 1,
                    "population \(population) is too wide for 2x and should get the wide view")
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
    /// stands unmodified. The point is that the degenerate path defers to the
    /// policy rather than inventing a scale of its own — which is now a
    /// stronger claim than it was, because the policy no longer returns the
    /// floor for a small room, so "defers to the policy" and "returns 1" have
    /// stopped being the same sentence.
    @Test func degenerateDimensionsFallBackToThePopulationScale() {
        #expect(RoomCamera.default.scale(
            forPopulation: 2,
            viewportWidth: 0, viewportHeight: 0,
            contentWidth: 0, contentHeight: 0) == 2)
        // Same call, on a camera that does prefer a closer scale: the fallback
        // follows the policy rather than the floor.
        #expect(RoomCamera(comfortablePopulation: [3: 2]).scale(
            forPopulation: 2,
            viewportWidth: 0, viewportHeight: 0,
            contentWidth: 0, contentHeight: 0) == 3)
    }

    // MARK: What actually fits the shipped panel [see `RoomCamera.init`]

    /// **The band fits `2x` now, and width is what decides who gets it.**
    ///
    /// This test was `aCloserScaleDoesNotFitTheShippedPanel`, and it was written
    /// to fail. It has: the two changes it was watching for both landed, and the
    /// useful direction was the direction it fell in.
    ///
    /// | | px |
    /// |---|---:|
    /// | badge slot above the feet | 85 → **51** — the slot moved beside the head |
    /// | nameplate below the feet | 23 → 31 → **13** — a task row on, then three rows down to one |
    /// | the two seat rows | **64** |
    /// | the walkway | **32** |
    /// | the delivery row | 96 → 0 → **32** — three per ring, then none, now one shared |
    /// | **content band** | 300 → 170 → 178 → 160 → **192** |
    ///
    /// A `2x` view of a 720×400 panel frames 200 px of height. 192 is inside it,
    /// with 8 px to spare, and `3x` is still out of reach at 133. So height still
    /// does not settle the question at every population — **width does**, and it
    /// says three. `aCloserFrameWouldHoldThreeSeatColumnsAcross` is the binding
    /// constraint rather than a footnote, and the boundary is asserted here as a
    /// scale per population rather than as one answer for all of them.
    ///
    /// **The 8 px is the whole margin and it is deliberately not spent.** The
    /// last row bought — one shared delivery row, which is what puts a reporter
    /// beside the agent it reports to [`RoomLayout.deliveryPosition(anchorSeat:
    /// reporterSeat:)`] — took 32 of the 40 px `2caa864` freed. There is no room
    /// for a second one, and a room that wanted one would be choosing to give
    /// `2x` up rather than trimming something.
    ///
    /// **It is still a tripwire and it still fails in both directions.** A
    /// taller badge, a deeper room or a wider plate pushes a population back down
    /// to `1x`; a narrower plate pulls another one up. Either way whoever made
    /// the change is holding the one place that decides whether the camera should
    /// use it — and `comfortablePopulation` is still empty, so nothing here
    /// changes what the app draws until someone decides that separately.
    @Test func theBandFitsACloserScaleAndWidthDecidesWhoGetsIt() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let camera = RoomCamera(manifest: manifest)
        // `NotchGeometry.PanelSize.room`, spelled out rather than imported:
        // `SpriteRoomScene` does not depend on `SpriteRoomApp` and must not.
        let panel = (width: 720.0, height: 400.0)

        // Exactly what `RoomScene.applyScale` feeds the camera.
        let headTop = manifest.characters.variants.values.map(\.headTopPx).min() ?? 0
        let badgeTop = Character.badgeSlotTopAboveFeet(
            canvasHeight: manifest.characters.canvas.height, headTopPx: headTop)
        let plateDrop = Double(SceneBitmaps.maximumNameplateHeight + 2)
        let band = layout.contentBand(
            badgeTopAboveFeet: badgeTop, plateDropBelowFeet: plateDrop)
        let contentHeight = band.top - band.bottom

        // **The decomposition, so a failure says which term moved.** The room's
        // own share is the two seat rows, the walkway and the delivery row;
        // everything else is the character's own art, out of the layout's hands.
        let roomsShare = layout.topSeatRowY - (layout.standingRows.min() ?? 0)
        #expect(contentHeight == roomsShare + badgeTop + plateDrop)
        #expect(roomsShare == 128, Comment(rawValue:
            "the room's own share of the band is \(roomsShare) px; it was 192 with"
            + " a delivery row per ring and 96 with none, and 128 is two seat rows,"
            + " a walkway to arrive on and one delivery row to walk along"))

        // **Height: 2x fits, 3x does not.**
        #expect(contentHeight <= panel.height / 2, Comment(rawValue:
            "the content band is \(contentHeight) px and 2x has \(panel.height / 2)."
            + " It stopped fitting: the terms are \(roomsShare) px of room,"
            + " \(badgeTop) px of badge slot and \(plateDrop) px of plate"))
        #expect(contentHeight > panel.height / 3, Comment(rawValue:
            "3x now fits too, at \(contentHeight) px against \(panel.height / 3)"))

        // **Width: three seat columns, and the boundary is where it says.**
        let across = Self.populationsThatFitAcrossAtTwo(layout)
        #expect(across == 3, "a 2x frame holds \(across) seat columns, not three")
        for population in 0...layout.seatCapacity {
            // Seat 0 is framed even when empty — `RoomScene.charactersBySeat`.
            let seats = Array(0...max(0, population - 1))
            let span = layout.occupiedSpan(seats: seats)
            let scale = camera.largestFittingScale(
                viewportWidth: panel.width, viewportHeight: panel.height,
                contentWidth: span.maxX - span.minX, contentHeight: contentHeight)
            #expect(scale == (population <= across ? 2 : 1),
                    "population \(population) fits at \(scale)x")
        }

        // **And the shipped policy agrees with that arithmetic**, which is the
        // assertion that keeps the table honest. `comfortablePopulation` is a
        // typed constant; `across` is derived from the seat pitch and the panel
        // width. Pinning them to each other means a change to either — a wider
        // plate, a different pitch, a resized panel — makes the policy fail
        // rather than quietly promise a scale that no longer fits.
        #expect(camera.comfortablePopulation == [2: across], Comment(rawValue:
            "the camera prefers 2x up to \(camera.comfortablePopulation[2] ?? 0) agents,"
            + " but only \(across) fit across a 2x frame at this pitch"))
        for population in 0...layout.seatCapacity {
            #expect(camera.scale(forPopulation: population) == (population <= across ? 2 : 1))
        }
    }

    /// How many characters a `2x` frame can hold **across**, at the shipped
    /// pitch. Used only to make the message above say something useful.
    static func populationsThatFitAcrossAtTwo(_ layout: RoomLayout) -> Int {
        var fits = 0
        for population in 1...layout.seatCapacity {
            let span = layout.occupiedSpan(seats: 0..<population)
            if (span.maxX - span.minX) * 2 <= 720 { fits = population }
        }
        return fits
    }

    /// **How much room a `2x` frame has across, in seats.** Three.
    ///
    /// The half of the refutation that looks answerable by rearranging the
    /// seats, pinned so the answer is a number rather than an impression. Four
    /// columns need 448 px of the 360 a `2x` frame has, and seven need 736.
    ///
    /// **It was a footnote and it is now the whole answer.** Height used to hold
    /// every population to `1x` at 300 px of band; the band is 192 and this is
    /// what is left. It is also the one term a narrower plate can move: a 64 px
    /// pitch would make it four rather than three
    /// [`RoomLayout.minimumSeatSpacingTiles(plateWidth:plateHeight:tile:)`].
    /// Seven is not reachable at any plate width — seven columns plus
    /// `occupiedSpan`'s padding need a pitch of 33 px, and a desk is 32.
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
    /// solution at any pitch this room can have. See `RoomLayout.isBackRow(seat:)`.
    ///
    /// A staggered row clears the columns on *both* sides of it only if the pitch
    /// is at least two plates wide. It is 96 against 71 today, and the reason
    /// that is not a coincidence of two constants is
    /// `RoomLayout.minimumSeatSpacingTiles(plateWidth:plateHeight:tile:)`: the
    /// pitch is **one** plate plus a margin, rounded up to a tile. So the second
    /// case below is the one that matters — the refutation is re-derived at every
    /// plate width the font could produce, rather than at the one it produces
    /// now, and it holds at all of them.
    @Test func noStaggerCanInterleaveTheTwoSeatRowsAtAnyPlateWidth() {
        let layout = RoomLayout()
        let pitch = layout.tile * layout.seatSpacingTiles
        let plate = SceneBitmaps.maximumNameplateWidth
        #expect(pitch < 2 * plate, "a \(pitch) px pitch would fit two \(plate) px plates")
        #expect((1..<pitch).allSatisfy { min($0, pitch - $0) < plate },
                "some offset clears a plate on both sides after all")

        // Every plate width a plate could plausibly be, against the pitch that
        // width would buy. `pitch < 2 × plate` is what has no solution, and one
        // tile of rounding-up is never a second plate.
        //
        // **33 px, not 0, and the boundary is real rather than a convenience.**
        // Below it the pitch stops being the plate's and becomes the *desk's* —
        // `minimumSeatSpacingTiles` floors at two tiles because a seat is a
        // character and its desk whatever the plate does — and a 64 px pitch is
        // two plates wide once a plate is 32. A stagger would then be
        // arithmetically available, and it would buy nothing: an interleave at
        // offset `s` is just a room whose columns are `min(s, pitch − s)` apart,
        // which is narrower than the narrowest spacing this formula allows. The
        // room would be built by narrowing the pitch, not by staggering it.
        //
        // **49 px, not 44, and the gap is what the one-row plate opened.** The
        // margin this formula borrows from the row axis is `tile − plateHeight`,
        // so a *shorter* plate asks for a wider gap: at 21 px of plate it was
        // 11 px and at 11 px it is 21. That moves the width at which the pitch
        // rounds up to three tiles from 54 down to 44, and between 44 and 48 the
        // 96 px pitch it rounds up to is two plates wide. Nothing in the room is
        // in that band — the plate is 63 px and buys 96, which is not two plates
        // — but the claim is no longer universal and is not stated as if it
        // were. Whoever narrows the plate into 44…48 px is choosing a room where
        // a stagger is arithmetically available; `RoomLayout.isBackRow`'s
        // refutation would then have to be re-derived rather than inherited.
        let openBand = (33...120).filter { width in
            let tiles = RoomLayout.minimumSeatSpacingTiles(
                plateWidth: width, plateHeight: SceneBitmaps.maximumNameplateHeight,
                tile: layout.tile)
            return tiles * layout.tile >= 2 * width
        }
        #expect(openBand == Array(44...48), Comment(rawValue:
            "the widths at which a stagger opens up moved: \(openBand)"))
        #expect(!openBand.contains(plate), Comment(rawValue:
            "the shipped \(plate) px plate buys a pitch two plates wide — a"
            + " stagger would open up, and RoomLayout.isBackRow's refutation"
            + " would stop holding"))
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
