import Foundation
import CoreAudio
import CoreGraphics

/// Is now a bad moment for a reminder? Checks whether the screen is locked,
/// whether you've stepped away from the Mac, and whether any app is using a microphone
/// (a call or meeting). Only reads status; nothing is recorded.
enum Presence {
    /// No keyboard or mouse use for this long counts as away.
    static let awayAfter: TimeInterval = 5 * 60

    /// Why now is a bad time for a reminder, or nil if it's fine.
    static func busyReason() -> String? {
        if screenIsLocked { return "screen locked" }
        if idleSeconds >= awayAfter { return "away from the Mac" }
        if microphoneInUse { return "on a call" }
        return nil
    }

    /// Seconds since you last used the keyboard, mouse or trackpad.
    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// True while any app is recording from any microphone (Zoom, Meet, FaceTime...).
    /// Asks per app, so music playing through AirPods doesn't count as a call.
    static var microphoneInUse: Bool {
        guard #available(macOS 14.2, *) else { return false }
        return audioProcesses().contains { isRunningInput($0) }
    }

    @available(macOS 14.2, *)
    private static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    @available(macOS 14.2, *)
    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}
