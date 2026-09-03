import UIKit

/// Haptic vocabulary for the catch sequence.
///
/// Generators are kept alive and pre-prepared: creating one on demand adds
/// perceptible lag, which defeats the point of a haptic meant to land exactly
/// on an animation beat.
@MainActor
enum Haptics {
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() {
        impactLight.prepare()
        impactHeavy.prepare()
        impactRigid.prepare()
        notify.prepare()
    }

    /// Chrome opening / closing.
    static func hinge() { impactRigid.impactOccurred(intensity: 0.7) }

    /// One beat of the catch shake.
    static func shake() { impactHeavy.impactOccurred(intensity: 0.85) }

    /// A creature entered the reticle.
    static func detect() { impactLight.impactOccurred(intensity: 0.5) }

    static func caught() { notify.notificationOccurred(.success) }
    static func failed() { notify.notificationOccurred(.error) }
    static func tick() { impactLight.impactOccurred(intensity: 0.35) }
}
