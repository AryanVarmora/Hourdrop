import Carbon.HIToolbox

/// The keyboard shortcut ⌃⌥W (Control-Option-W). It works from any app
/// and needs no special permission.
@MainActor
final class HotKey {
    static let shared = HotKey()
    static let label = "⌃⌥W"

    /// What to do when you press it.
    var onPress: (() -> Void)?
    /// False if another app already uses ⌃⌥W.
    private(set) var isRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        guard hotKeyRef == nil else { return }
        if handlerRef == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                        eventKind: UInt32(kEventHotKeyPressed))
            // Carbon calls this on the main thread when the shortcut is pressed.
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { HotKey.shared.onPress?() }
                return noErr
            }, 1, &pressed, nil, &handlerRef)
        }
        let id = EventHotKeyID(signature: OSType(0x5349_5050), id: 1)   // "SIPP"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(controlKey | optionKey),
                                         id, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
        if !isRegistered { hotKeyRef = nil }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        isRegistered = false
    }

    /// Turn the shortcut on or off to match Settings.
    func applyPrefs() {
        if Prefs.shortcutQuarters.value > 0 { register() } else { unregister() }
    }
}
