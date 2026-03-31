#if os(iOS)
import Foundation
import UIKit

/// Detects device shake gestures and triggers a callback.
///
/// Uses method swizzling on `UIWindow.motionEnded(_:with:)` to intercept shake events.
/// Can be disabled via `BacktraceSessionSettings.shakeToReport = false`.
final class BacktraceShakeDetector {

    private var onShake: (() -> Void)?
    private var isEnabled = false
    static var sharedDetector: BacktraceShakeDetector?

    /// Enable shake detection with the given callback.
    func enable(onShake: @escaping () -> Void) {
        self.onShake = onShake
        guard !isEnabled else { return }
        isEnabled = true
        BacktraceShakeDetector.sharedDetector = self
        swizzleMotionEnded()
    }

    /// Disable shake detection and remove the swizzle.
    func disable() {
        isEnabled = false
        BacktraceShakeDetector.sharedDetector = nil
        onShake = nil
    }

    /// Called by the swizzled method when a shake is detected.
    func handleShake() {
        guard isEnabled else { return }

        // Present confirmation alert
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                  let window = scene.windows.first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else { return }

            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }

            let alert = UIAlertController(
                title: "Report a Bug",
                message: "Would you like to report a bug?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Report", style: .default) { _ in
                self.onShake?()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            presenter.present(alert, animated: true)
        }
    }

    // MARK: - Swizzling

    private static var hasSwizzled = false

    private func swizzleMotionEnded() {
        guard !BacktraceShakeDetector.hasSwizzled else { return }
        BacktraceShakeDetector.hasSwizzled = true

        let originalSelector = #selector(UIWindow.motionEnded(_:with:))
        let swizzledSelector = #selector(UIWindow.backtrace_motionEnded(_:with:))

        guard let originalMethod = class_getInstanceMethod(UIWindow.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// MARK: - UIWindow Extension for Swizzling

extension UIWindow {

    @objc func backtrace_motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        // Call original implementation (swizzled, so this calls the original)
        backtrace_motionEnded(motion, with: event)

        if motion == .motionShake {
            BacktraceShakeDetector.sharedDetector?.handleShake()
        }
    }
}
#endif
