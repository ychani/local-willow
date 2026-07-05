import AppKit
import Foundation

/// Global hold-to-talk hotkey via a listen-only CGEventTap.
/// Needs only Accessibility (no Input Monitoring). If the tap can't be created
/// yet, `start()` returns false and can be retried once trust is granted.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Esc pressed while holding the hotkey — abort the dictation.
    var onCancel: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = false
    /// A tap created before Accessibility was granted exists but never receives
    /// keyboard events — it must be recreated after the grant.
    private(set) var trustedAtCreation = false

    var isActive: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    @discardableResult
    func start() -> Bool {
        if isActive { return true }
        stop()
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: refcon
        ) else {
            Log.write("hotkey: event tap creation failed (Accessibility not granted yet)")
            return false
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        trustedAtCreation = AXIsProcessTrusted()
        Log.write("hotkey: event tap active (trusted=\(trustedAtCreation))")
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        held = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        // macOS disables taps that stall (e.g. during heavy load) — re-arm.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if keyCode == 53, type == .keyDown, held {  // Esc cancels an active take
            held = false
            Log.write("hotkey: cancelled with Esc")
            onCancel?()
            return
        }

        let hk = Config.shared.hotkey
        guard keyCode == hk.keyCode else { return }
        switch type {
        case .flagsChanged where hk.isModifier:
            let flag: CGEventFlags = {
                switch hk {
                case .rightOption: return .maskAlternate
                case .rightCommand: return .maskCommand
                case .rightControl: return .maskControl
                case .f13: return []
                }
            }()
            transition(down: event.flags.contains(flag))
        case .keyDown where !hk.isModifier:
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                transition(down: true)
            }
        case .keyUp where !hk.isModifier:
            transition(down: false)
        default:
            break
        }
    }

    private func transition(down: Bool) {
        if down && !held {
            held = true
            Log.write("hotkey: pressed")
            onPress?()
        } else if !down && held {
            held = false
            Log.write("hotkey: released")
            onRelease?()
        }
    }
}

private func hotkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                               event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            .handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
