import AppKit
import Foundation

/// Inserts text at the cursor of the frontmost app: pasteboard + synthetic ⌘V,
/// then restores the previous pasteboard contents.
enum Paster {
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Synthetic keystrokes are silently dropped without Accessibility. In that
        // case leave the text in the clipboard so the user can ⌘V manually.
        guard AXIsProcessTrusted() else {
            Log.write("paste: Accessibility NOT trusted — left text in clipboard, no ⌘V sent")
            Notify.post("Accessibility permission missing — text copied to clipboard, paste with ⌘V")
            return
        }

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        Log.write("paste: sent ⌘V (\(text.count) chars)")

        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pb.clearContents()
                pb.setString(previous, forType: .string)
            }
        }
    }
}
