import AppKit
import Foundation
import SpriteKit

/// Drives the panel: samples the pointer, asks `RevealPolicy` what should
/// happen, and slides the window.
///
/// **The pointer is sampled, not received.** `NSEvent.mouseLocation` is read on
/// a timer instead of installing a global event monitor or a tracking area.
/// Three reasons, in order of importance:
///
///   1. A tracking area only fires for a window that is under the pointer, and
///      the panel is above the screen when hidden — there is nothing to track.
///   2. A global event monitor for mouse movement is an input tap; sampling a
///      coordinate is not, and needs no permission from the user.
///   3. Sampling gives the hysteresis a regular clock. `mouseExited` fires once
///      and never again; a grace period needs something to tick.
///
/// Thirty hertz is the sample rate. The dwell is 140 ms — four samples — so the
/// rate is not what decides anything; the policy is.
@MainActor
final class NotchPanelController {

    let panel: NotchPanel
    /// The room's view, kept only so the render loop can be stopped while the
    /// panel is away. See `setRendering(_:)`.
    private weak var roomView: SKView?
    private let size: PanelSize
    private let tuning: RevealPolicy.Tuning
    private var policy: RevealPolicy
    private(set) var geometry: NotchGeometry
    private var timer: Timer?

    /// Judgment call: down is slightly slower than up. A reveal you asked for
    /// reads better with a beat of travel; a retract you have already walked
    /// away from should just be gone.
    static let revealDuration: TimeInterval = 0.22
    static let retractDuration: TimeInterval = 0.16
    static let sampleInterval: TimeInterval = 1.0 / 30.0

    /// Called after every state change, for the verification harness and for
    /// `SPRITEROOM_DEBUG`. Never used to drive anything.
    var onTransition: ((PanelTransition, PanelPhase) -> Void)?

    private(set) var revealCount = 0
    private(set) var retractCount = 0

    var phase: PanelPhase { policy.phase }
    var isRevealed: Bool { policy.phase.isVisible }

    init(
        contentView: NSView,
        size: PanelSize = .room,
        tuning: RevealPolicy.Tuning = .default,
        screen: NSScreen? = nil
    ) {
        self.size = size
        self.tuning = tuning
        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        let geometry = screen.map { NotchGeometry.forScreen($0) }
            ?? NotchGeometry(
                display: PanelRect(x: 0, y: 0, width: 1440, height: 900),
                physicalNotch: nil,
                menuBarHeight: 24)
        self.geometry = geometry
        self.policy = RevealPolicy(geometry: geometry, size: size, tuning: tuning)

        let container = PanelContainerView(frame: geometry.hiddenPanelFrame(size: size).cgRect)
        panel = NotchPanel(contentRect: container.frame)
        panel.contentView = container
        contentView.frame = container.bounds
        contentView.autoresizingMask = [.width, .height]
        container.addSubview(contentView)
        panel.setFrame(geometry.hiddenPanelFrame(size: size).cgRect, display: false)
        roomView = contentView as? SKView
        // The panel starts retracted, so the room starts paused. Without this the
        // first stretch of every run renders into nothing.
        setRendering(false)
    }

    /// Starts and stops the room's render loop with the panel.
    ///
    /// **The claim this replaces was wrong, and the terminal said so.** `slide`
    /// used to assert that "a hidden panel costs nothing — an off-screen
    /// `SKView` stops rendering, an ordered-out one is not in the window list at
    /// all". Ordering a window out does remove it from the window list; it does
    /// not stop the view's display link. What it actually produces, once per
    /// frame for as long as the panel is away — which is nearly all the time —
    /// is:
    ///
    /// > `SKView: no drawables available for rendering. Skipping this frame.`
    ///
    /// A maintainer running `--live` reported it filling their terminal. It is a
    /// log line rather than an error, but the work behind it is real: the room
    /// was drawing every frame of every retracted minute for nobody.
    ///
    /// **Pausing is safe here specifically because ingest does not run on this
    /// clock.** Deltas reach the scene from `LiveDriver` through
    /// `SceneBinding.apply`, which is driven by the listener; `isPaused` stops
    /// rendering and `SKAction` time and touches neither the director nor the
    /// scene graph. A retracted room therefore keeps *arriving* at the right
    /// state and simply stops drawing it, which is why the panel is correct on
    /// the frame it reappears rather than catching up visibly.
    private func setRendering(_ isOn: Bool) {
        roomView?.isPaused = !isOn
    }

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        // `.common` so the panel keeps working while a menu is tracking or a
        // window is being dragged — both put the run loop in a modal mode.
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Take the panel off the screen **now** — no animation, no timer — and
    /// leave the policy agreeing that it is away.
    ///
    /// This is the teardown call, and it is the one thing that must happen
    /// before the process goes away. Ordering out is what removes the surface
    /// from the window server; a process that exits while this panel is ordered
    /// in can leave the surface drawn with nothing behind it, and **that ghost
    /// cannot be dismissed by hand**: `ignoresMouseEvents = true` means clicks
    /// go through it, the level is above the menu bar so nothing can be brought
    /// in front of it, and `canJoinAllSpaces` means it follows you to every
    /// desktop. Clearing it takes a space switch or Mission Control, and
    /// killing the process does not help — the process is already gone. So the
    /// exit paths call this, and so does `applicationWillTerminate`.
    ///
    /// `stop()` first, so a sample cannot re-reveal the panel between the
    /// order-out and the exit. Not an animation, because the caller is about to
    /// stop existing and an animation needs frames it will not get.
    func hide(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        stop()
        _ = policy.forceRetract(at: now)
        panel.setFrame(geometry.hiddenPanelFrame(size: size).cgRect, display: false)
        panel.orderOut(nil)
        setRendering(false)
    }

    // MARK: Sampling

    /// One pointer sample. Split out from the timer so the verification harness
    /// can drive it at whatever rate it likes.
    func tick(at now: TimeInterval) {
        let pointer = PanelPoint(NSEvent.mouseLocation)
        // Re-read the display only while the panel is away. Re-anchoring a
        // panel that is on screen — because the pointer crossed onto a second
        // display — would make it jump, and the pointer is on its way out
        // anyway.
        if !policy.phase.isVisible {
            adoptScreenIfChanged(for: pointer)
        }
        apply(policy.update(pointer: pointer, at: now))
    }

    /// Force the panel down. Harness only — there is no user-facing path to
    /// this, because there is no user-facing control anywhere. [I8]
    func forceReveal(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        apply(policy.forceReveal(at: now))
    }

    /// Force the panel up. Harness only.
    func forceRetract(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        apply(policy.forceRetract(at: now))
    }

    private func apply(_ transition: PanelTransition?) {
        guard let transition else { return }
        switch transition {
        case .reveal:
            revealCount += 1
            slide(to: geometry.revealedPanelFrame(size: size), duration: Self.revealDuration)
        case .retract:
            retractCount += 1
            slide(to: geometry.hiddenPanelFrame(size: size), duration: Self.retractDuration)
        }
        onTransition?(transition, policy.phase)
    }

    private func adoptScreenIfChanged(for pointer: PanelPoint) {
        guard let screen = NotchGeometry.activeScreen(pointer: pointer) else { return }
        let fresh = NotchGeometry.forScreen(screen)
        guard fresh != geometry else { return }
        geometry = fresh
        policy = RevealPolicy(geometry: fresh, size: size, tuning: tuning)
        panel.setFrame(fresh.hiddenPanelFrame(size: size).cgRect, display: false)
    }

    // MARK: Moving the window

    /// Slides the window between the two frames.
    ///
    /// `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the first
    /// shows a window without activating the app, the second is the exact call
    /// that would break I8. The panel is ordered in *before* the animation so
    /// the frames it travels through are real, and ordered out *after* a
    /// retract so a hidden panel is not in the window list at all.
    ///
    /// **Rendering is resumed before the reveal and stopped after the retract**,
    /// in that order for the same reason the ordering is: the slide has to be
    /// drawn, so the room must be live for the whole of it and may only stop
    /// once the panel is actually gone. `setRendering(_:)` has the account of
    /// why an ordered-out panel does not stop drawing by itself.
    private func slide(to target: PanelRect, duration: TimeInterval) {
        let revealing = policy.phase.isVisible
        if revealing, !panel.isVisible {
            panel.orderFrontRegardless()
        }
        if revealing { setRendering(true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(target.cgRect, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.policy.phase.isVisible {
                    self.panel.orderOut(nil)
                    self.setRendering(false)
                }
            }
        }
    }
}

/// The panel's content: a clipped, rounded-bottom box the room sits inside.
///
/// The top corners are square and the bottom ones are round, which is what
/// makes it read as something hanging out of the notch rather than a window
/// that happens to be near the top of the screen.
private final class PanelContainerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Read-only surface. Nothing here is a responder. [I8]
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
