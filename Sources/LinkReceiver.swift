import AppKit
import Carbon

/// Receives hourdrop:// links. When any app (or Terminal's `open`) opens one, macOS sends it
/// to Hourdrop as an "open URL" Apple event; this passes each link to `onLink`.
/// Call `start()` before the app finishes launching, so a link that started Hourdrop isn't missed.
@MainActor
final class LinkReceiver: NSObject {
    static let shared = LinkReceiver()

    var onLink: (@MainActor (URL) -> Void)?

    func start() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(receive(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func receive(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        onLink?(url)
    }
}
