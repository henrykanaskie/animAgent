import Foundation
@testable import SpriteRoomApp

/// A pointer path, played into a `RevealPolicy` at a fixed sample rate.
///
/// Samples at 120 Hz by default — four times what the real controller uses —
/// so a path that survives this has seen more chances to chatter than it ever
/// will in the app.
struct Simulation {

    var policy: RevealPolicy
    private(set) var now: TimeInterval = 0
    /// Every state change, with the time it happened.
    private(set) var transitions: [(time: TimeInterval, transition: PanelTransition)] = []

    let rate: Double

    init(policy: RevealPolicy, rate: Double = 120) {
        self.policy = policy
        self.rate = rate
    }

    var step: TimeInterval { 1.0 / rate }
    var reveals: Int { transitions.filter { $0.transition == .reveal }.count }
    var retracts: Int { transitions.filter { $0.transition == .retract }.count }

    mutating func sample(_ pointer: PanelPoint?) {
        if let transition = policy.update(pointer: pointer, at: now) {
            transitions.append((now, transition))
        }
        now += step
    }

    /// Hold the pointer still.
    mutating func hold(_ pointer: PanelPoint?, for duration: TimeInterval) {
        var elapsed = 0.0
        while elapsed < duration {
            sample(pointer)
            elapsed += step
        }
    }

    /// Move the pointer in a straight line at constant speed.
    mutating func sweep(from start: PanelPoint, to end: PanelPoint, duration: TimeInterval) {
        let steps = max(1, Int(duration * rate))
        for index in 0...steps {
            let t = Double(index) / Double(steps)
            sample(
                PanelPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t))
        }
    }

    /// The shortest gap between any two state changes. `nil` when there are
    /// fewer than two.
    var closestTransitions: TimeInterval? {
        guard transitions.count >= 2 else { return nil }
        return zip(transitions.dropFirst(), transitions)
            .map { $0.time - $1.time }
            .min()
    }
}

enum PanelFixtures {

    /// The display this was developed on: 14-inch MacBook Pro, 1800×1169
    /// points, camera housing x ∈ [790, 1010], 39-point menu bar.
    static var notched: NotchGeometry {
        NotchGeometry(
            display: PanelRect(x: 0, y: 0, width: 1800, height: 1169),
            physicalNotch: PanelRect(x: 790, y: 1131, width: 220, height: 38),
            menuBarHeight: 39)
    }

    static var external: NotchGeometry {
        NotchGeometry(
            display: PanelRect(x: 0, y: 0, width: 2560, height: 1440),
            physicalNotch: nil,
            menuBarHeight: 24)
    }

    static func policy(
        _ geometry: NotchGeometry = PanelFixtures.notched,
        tuning: RevealPolicy.Tuning = .default
    ) -> RevealPolicy {
        RevealPolicy(geometry: geometry, size: .room, tuning: tuning)
    }

    /// Dead centre of the hot zone.
    static func inside(_ geometry: NotchGeometry = PanelFixtures.notched) -> PanelPoint {
        PanelPoint(x: geometry.region.midX, y: geometry.region.midY)
    }

    /// A long way from anything the panel cares about.
    static func away(_ geometry: NotchGeometry = PanelFixtures.notched) -> PanelPoint {
        PanelPoint(x: geometry.display.midX, y: geometry.display.minY + 40)
    }
}
