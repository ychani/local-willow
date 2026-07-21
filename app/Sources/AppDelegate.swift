import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let engine = WhisperEngine()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let overlay = OverlayPanel()
    private var settingsWindow: NSWindow?
    private var busy = false
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.write("launch: mic=\(micStatus == .authorized ? "granted" : "NOT granted (\(micStatus.rawValue))") "
            + "accessibility=\(AXIsProcessTrusted() ? "trusted" : "NOT trusted")")

        // Dark UI throughout, independent of the system theme.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        buildMainMenu()
        setupStatusItem()
        engine.start()

        recorder.onLevel = { [weak self] level in
            self?.overlay.model.push(level: level)
        }
        hotkey.onPress = { [weak self] in self?.handleHotkeyPress() }
        hotkey.onRelease = { [weak self] in self?.handleHotkeyRelease() }
        hotkey.onCancel = { [weak self] in self?.cancelDictation() }
        hotkey.isTakeActive = { [weak self] in self?.recorder.isRecording ?? false }
        hotkey.start()

        watchPermissions()

        // First-run onboarding if anything is missing.
        if micStatus != .authorized || !AXIsProcessTrusted() {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    /// Re-arms the hotkey tap the moment Accessibility is granted — no relaunch needed.
    private func watchPermissions() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Re-arm when the tap is missing OR was created before trust was granted
            // (such a tap exists but never receives keyboard events).
            if AXIsProcessTrusted() && !(self.hotkey.isActive && self.hotkey.trustedAtCreation) {
                Log.write("permissions: Accessibility granted — (re)arming hotkey tap")
                self.hotkey.stop()
                if self.hotkey.start() {
                    Notify.post("Ready — \(Config.shared.actionHint.lowercased()) to dictate")
                }
            }
        }
        // TCC broadcasts accessibility changes; poke the check immediately when it fires.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.permissionTimer?.fire()
            }
        }
    }

    // MARK: - Dictation flow

    /// Hotkey pressed. Push-to-talk starts a take; toggle mode starts if idle,
    /// otherwise finishes the running take.
    private func handleHotkeyPress() {
        if Config.shared.toggleDictation, recorder.isRecording {
            endDictation()
        } else {
            beginDictation()
        }
    }

    /// Hotkey released. Ends the take only in push-to-talk mode; toggle mode
    /// keeps recording until the next press.
    private func handleHotkeyRelease() {
        guard !Config.shared.toggleDictation else { return }
        endDictation()
    }

    private func beginDictation() {
        guard !busy, !recorder.isRecording else { return }
        // Trigger the system mic prompt on first use rather than failing silently.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        }
        do {
            try recorder.start()
            setIcon(state: .recording)
            overlay.show(phase: .recording)
            playSound("Pop")
        } catch {
            Log.write("record: start failed — \(error.localizedDescription)")
            notify("Couldn't start recording: \(error.localizedDescription)")
        }
    }

    private func cancelDictation() {
        guard recorder.isRecording else { return }
        if let wav = recorder.stop() {
            try? FileManager.default.removeItem(at: wav)
        }
        overlay.hide()
        setIcon(state: .idle)
        playSound("Bottle")
    }

    private func endDictation() {
        guard recorder.isRecording else { return }
        guard let wav = recorder.stop() else {
            Log.write("record: too short or empty, ignored")
            overlay.hide()
            setIcon(state: .idle)
            return
        }
        Log.write("record: captured \(String(format: "%.1f", recordedSeconds(of: wav)))s")
        busy = true
        setIcon(state: .processing)
        overlay.show(phase: .processing)

        Task { @MainActor in
            defer {
                self.busy = false
                self.overlay.hide()
                self.setIcon(state: .idle)
            }
            do {
                let t0 = Date()
                let raw = try await engine.transcribe(wav: wav)
                Log.write("transcribe: \(Int(Date().timeIntervalSince(t0) * 1000))ms, \(raw.count) chars")
                var text = TextCleaner.clean(raw)
                if Config.shared.aiMode, !text.isEmpty {
                    text = await TextCleaner.aiRewrite(text)
                }
                guard !text.isEmpty else {
                    Log.write("transcribe: empty result (silence?)")
                    return
                }
                Paster.paste(text)
                HistoryStore.shared.add(text)
                playSound("Purr")
            } catch {
                Log.write("transcribe: FAILED — \(error.localizedDescription)")
                self.notify("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Menu bar

    private enum IconState { case idle, recording, processing }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon(state: .idle)
        statusItem.menu = buildStatusMenu()
    }

    private func setIcon(state: IconState) {
        guard let button = statusItem?.button else { return }
        // Custom waveform mark matching the app icon (template → adapts to menu bar theme).
        let heights: [CGFloat] = {
            switch state {
            case .idle: return [0.30, 0.55, 0.85, 0.55, 0.30]
            case .recording: return [0.45, 0.75, 1.0, 0.75, 0.45]
            case .processing: return [0.22, 0.38, 0.55, 0.38, 0.22]
            }
        }()
        button.image = Self.waveformIcon(heights: heights)
        switch state {
        case .idle: button.contentTintColor = nil
        case .recording: button.contentTintColor = .systemRed
        case .processing: button.contentTintColor = .secondaryLabelColor
        }
    }

    private static func waveformIcon(heights: [CGFloat]) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let barWidth: CGFloat = 2.4
        let gap: CGFloat = 1.4
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            var x = rect.midX - total / 2
            for h in heights {
                let barHeight = max(barWidth, rect.height * h)
                let bar = NSRect(x: x, y: rect.midY - barHeight / 2,
                                 width: barWidth, height: barHeight)
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2,
                             yRadius: barWidth / 2).fill()
                x += barWidth + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
        historyItem.submenu = NSMenu()
        menu.addItem(historyItem)

        let ai = NSMenuItem(title: "AI Mode (Ollama rewrite)",
                            action: #selector(toggleAI), keyEquivalent: "")
        ai.target = self
        menu.addItem(ai)

        let transcribeFile = NSMenuItem(title: "Transcribe Audio File…",
                                        action: #selector(transcribeAudioFileAction), keyEquivalent: "")
        transcribeFile.target = self
        menu.addItem(transcribeFile)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LocalWillow",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// Minimal main menu so standard shortcuts (⌘C/⌘V/⌘A in Settings fields, ⌘W, ⌘Q) work.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit LocalWillow",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    @objc private func toggleAI() {
        Config.shared.aiMode.toggle()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    // MARK: - Transcribe an existing audio file

    @objc private func transcribeAudioFileAction() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an audio file to transcribe"
        panel.prompt = "Transcribe"
        var types = AudioConverter.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        types.append(.audio)  // catch-all for any other audio the system recognizes
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transcribeFile(url)
    }

    /// Converts the picked file to whisper's WAV, transcribes it, writes a sibling
    /// .txt next to the source, and copies the transcript to the clipboard.
    private func transcribeFile(_ source: URL) {
        guard !busy, !recorder.isRecording else {
            notify("Busy — finish the current dictation first.")
            return
        }
        busy = true
        setIcon(state: .processing)
        Notify.post("Transcribing \(source.lastPathComponent)…")

        Task { @MainActor in
            defer {
                self.busy = false
                self.setIcon(state: .idle)
            }
            do {
                let wav = try AudioConverter.toWhisperWAV(source)
                let t0 = Date()
                // Files can be long; give the server a generous ceiling. transcribe()
                // deletes the temp wav — the user's original is never touched.
                let raw = try await engine.transcribe(wav: wav, timeout: 3600)
                Log.write("file-transcribe: \(source.lastPathComponent) "
                    + "\(Int(Date().timeIntervalSince(t0) * 1000))ms, \(raw.count) chars")
                let text = TextCleaner.clean(raw)
                guard !text.isEmpty else {
                    notify("No speech found in \(source.lastPathComponent).")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                if let dest = try? writeTranscript(text, for: source) {
                    notify("Saved \(dest.lastPathComponent) · copied to clipboard")
                } else {
                    notify("Transcribed \(source.lastPathComponent) · copied to clipboard "
                        + "(couldn't write a file next to it)")
                }
            } catch {
                Log.write("file-transcribe: FAILED — \(error.localizedDescription)")
                self.notify("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    /// Writes the transcript beside the source as "<name>.txt", never overwriting
    /// an existing file (falls back to "<name> (2).txt", etc.).
    private func writeTranscript(_ text: String, for source: URL) throws -> URL {
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        var dest = dir.appendingPathComponent(base + ".txt")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) (\(n)).txt")
            n += 1
        }
        try text.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openSettings() {
        if settingsWindow == nil {
            var view = SettingsView()
            view.onEngineSettingsChanged = { [weak self] in self?.engine.restart() }
            let w = NSWindow(contentRect: .zero,
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "LocalWillow Settings"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        // Become a regular app while a window is visible so ⌘-Tab can reach it.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Helpers

    private func recordedSeconds(of wav: URL) -> Double {
        let attrs = try? FileManager.default.attributesOfItem(atPath: wav.path)
        let bytes = (attrs?[.size] as? Int) ?? 0
        return Double(max(0, bytes - 44)) / 32000.0  // 16 kHz mono int16
    }

    private func playSound(_ name: String) {
        guard Config.shared.sounds else { return }
        NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)?.play()
    }

    private func notify(_ message: String) {
        Notify.post(message)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        // Back to menu-bar-only once the settings window is gone, and apply any
        // engine-relevant setting changes (language, model, vocabulary).
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            self.engine.restart()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let status = menu.items.first {
            if !AXIsProcessTrusted() {
                status.title = "⚠️ Grant Accessibility in Settings…"
            } else if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                status.title = "⚠️ Grant Microphone in Settings…"
            } else if !engine.isRunning {
                status.title = "⚠️ Engine stopped — \(engine.lastError ?? "check Settings")"
            } else {
                status.title = "\(Config.shared.actionHint) to dictate · Esc cancels"
            }
        }
        for item in menu.items {
            if item.title.hasPrefix("AI Mode") {
                item.state = Config.shared.aiMode ? .on : .off
            }
            if item.title == "Recent Dictations", let sub = item.submenu {
                sub.removeAllItems()
                let items = HistoryStore.shared.items
                if items.isEmpty {
                    let empty = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    sub.addItem(empty)
                } else {
                    for h in items.prefix(10) {
                        let title = h.text.count > 60 ? String(h.text.prefix(57)) + "…" : h.text
                        let mi = NSMenuItem(title: title, action: #selector(copyHistoryItem(_:)),
                                            keyEquivalent: "")
                        mi.target = self
                        mi.representedObject = h.text
                        mi.toolTip = "Click to copy"
                        sub.addItem(mi)
                    }
                }
            }
        }
    }
}
