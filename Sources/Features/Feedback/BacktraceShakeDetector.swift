#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import Foundation

/// Detects shake gestures and screenshot events to trigger the feedback form.
final class BacktraceShakeDetector {

    private var trigger: BacktraceFeedbackTrigger = .none
    private var lastTriggerTime: Date = .distantPast
    private var debounceInterval: TimeInterval = 2.0
    private var onTrigger: (() -> Void)?
    private var screenshotObserver: NSObjectProtocol?

    func configure(trigger: BacktraceFeedbackTrigger,
                   debounceInterval: TimeInterval,
                   onTrigger: @escaping () -> Void) {
        self.trigger = trigger
        self.debounceInterval = debounceInterval
        self.onTrigger = onTrigger

        teardown()

        if trigger == .screenshot || trigger == .both {
            screenshotObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.userDidTakeScreenshotNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.handleTriggerEvent()
            }
        }

        if trigger == .shake || trigger == .both {
            BacktraceShakeWindow.shakeHandler = { [weak self] in
                self?.handleTriggerEvent()
            }
        }
    }

    func teardown() {
        if let observer = screenshotObserver {
            NotificationCenter.default.removeObserver(observer)
            screenshotObserver = nil
        }
        BacktraceShakeWindow.shakeHandler = nil
    }

    private func handleTriggerEvent() {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerTime) >= debounceInterval else { return }
        lastTriggerTime = now
        onTrigger?()
    }

    deinit {
        teardown()
    }
}

/// A UIWindow subclass that intercepts shake motions. Host apps can opt into this by
/// setting their window class, or the SDK can swizzle motionEnded.
final class BacktraceShakeWindow: UIWindow {

    static var shakeHandler: (() -> Void)?

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            BacktraceShakeWindow.shakeHandler?()
        }
    }
}
#endif
