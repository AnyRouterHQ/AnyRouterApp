import SwiftUI
import UIKit

/// Rectangles, in window coordinates, where a tap must not end editing.
struct KeyboardZones: Equatable {
    private(set) var frames: [UUID: CGRect] = [:]

    mutating func set(_ frame: CGRect, for id: UUID) { frames[id] = frame }
    mutating func remove(_ id: UUID) { frames[id] = nil }
    func contains(_ point: CGPoint) -> Bool { frames.values.contains { $0.contains(point) } }
}

@MainActor
final class KeyboardZoneStore {
    static let shared = KeyboardZoneStore()
    private(set) var zones = KeyboardZones()
    func set(_ frame: CGRect, for id: UUID) { zones.set(frame, for: id) }
    func remove(_ id: UUID) { zones.remove(id) }
}

extension View {
    /// Taps inside this view do not dismiss the keyboard (the composer, for example).
    func keepsKeyboardOnTap() -> some View { modifier(KeepsKeyboardOnTap()) }
}

private struct KeepsKeyboardOnTap: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { KeyboardZoneStore.shared.set($0, for: id) }
            .onDisappear { KeyboardZoneStore.shared.remove(id) }
    }
}

/// App-wide "tap outside the text input hides the keyboard".
///
/// This is the documented UIKit exception (AGENTS.md): SwiftUI has no global tap-outside API. One
/// recognizer per window ends editing for any tap that is not on a text input or in a keep-keyboard
/// zone. It never cancels or delays the touch, so buttons and links still fire on the same tap.
/// Lives next to `WindowAppearance`, the other window-level hook.
@MainActor
enum KeyboardDismissal {
    private final class Recognizer: UITapGestureRecognizer {}

    private final class Handler: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return !MainActor.assumeIsolated { KeyboardZoneStore.shared.zones.contains(touch.location(in: nil)) }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    private static let handler = Handler()

    /// Installs the recognizer on every window that does not have it yet. Safe to call repeatedly.
    static func install() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where !(window.gestureRecognizers ?? []).contains(where: { $0 is Recognizer }) {
                let tap = Recognizer(target: window, action: #selector(UIView.endEditingFromTap))
                tap.cancelsTouchesInView = false
                tap.delaysTouchesEnded = false
                tap.delegate = handler
                window.addGestureRecognizer(tap)
            }
        }
    }

    /// Ends editing in the key window, for moments the app itself decides (the drawer opening).
    static func endEditing() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.endEditing(true) }
        }
    }
}

private extension UIView {
    @objc func endEditingFromTap() { endEditing(true) }
}
