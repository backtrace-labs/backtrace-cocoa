#if os(iOS)
import Foundation
import UIKit

/// Manages views that should be hidden (masked) in session screenshots.
///
/// Uses weak references so hidden views are automatically released when deallocated.
final class BacktraceSensitiveViewManager {

    private var sensitiveViews = NSHashTable<UIView>.weakObjects()
    private let lock = NSLock()

    /// Mark a view as sensitive. It will be masked in screenshots.
    func hide(_ view: UIView) {
        lock.lock()
        sensitiveViews.add(view)
        lock.unlock()
    }

    /// Remove a view from the sensitive list.
    func show(_ view: UIView) {
        lock.lock()
        sensitiveViews.remove(view)
        lock.unlock()
    }

    /// Add opaque overlay views on top of each sensitive view within the given window.
    /// Returns the overlays so they can be removed after capture.
    func addMaskOverlays(in window: UIWindow) -> [UIView] {
        lock.lock()
        let views = sensitiveViews.allObjects
        lock.unlock()

        var overlays: [UIView] = []
        for view in views {
            guard view.window == window else { continue }
            let frame = view.convert(view.bounds, to: window)
            let overlay = UIView(frame: frame)
            overlay.backgroundColor = .black
            overlay.tag = 999_999  // Marker tag for identification
            window.addSubview(overlay)
            overlays.append(overlay)
        }
        return overlays
    }

    /// Remove previously added mask overlays.
    func removeMaskOverlays(_ overlays: [UIView]) {
        for overlay in overlays {
            overlay.removeFromSuperview()
        }
    }
}
#endif
