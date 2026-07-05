import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI

/// Live permission status for the onboarding tab.
final class PermissionsModel: ObservableObject {
    @Published var mic = false
    @Published var accessibility = false

    func refresh() {
        mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = AXIsProcessTrusted()
    }

    func requestMic() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.refresh() }
            }
        default:
            // Already denied — the system won't re-prompt; send them to the pane.
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    static func relaunchApp() {
        let path = Bundle.main.bundlePath
        Log.write("relaunch requested")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", path]
        // Delay so the new instance starts after this one exits (single-instance apps).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            try? p.run()
            NSApp.terminate(nil)
        }
    }
}

struct SettingsView: View {
    @StateObject private var perms = PermissionsModel()
    @StateObject private var history = HistoryStore.shared

    @State private var hotkey = Config.shared.hotkey
    @State private var language = Config.shared.language
    @State private var removeFillers = Config.shared.removeFillers
    @State private var sounds = Config.shared.sounds
    @State private var aiMode = Config.shared.aiMode
    @State private var ollamaModel = Config.shared.ollamaModel
    @State private var modelPath = Config.shared.modelPath
    @State private var vocabulary = Config.shared.vocabularyRaw
    @State private var replacements = Config.shared.replacementsRaw
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var onEngineSettingsChanged: (() -> Void)?

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            permissionsTab.tabItem { Label("Permissions", systemImage: "lock.shield") }
            dictionaryTab.tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            historyTab.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 520, height: 420)
        .onAppear { perms.refresh() }
        .onReceive(timer) { _ in perms.refresh() }
    }

    private var generalTab: some View {
        Form {
            Picker("Hold to dictate:", selection: $hotkey) {
                ForEach(Hotkey.allCases) { hk in Text(hk.label).tag(hk) }
            }
            .onChange(of: hotkey) { Config.shared.hotkey = hotkey }

            TextField("Language (ISO code):", text: $language)
                .onChange(of: language) { Config.shared.language = language }

            Toggle("Remove filler words (um, uh…)", isOn: $removeFillers)
                .onChange(of: removeFillers) { Config.shared.removeFillers = removeFillers }

            Toggle("Sound feedback", isOn: $sounds)
                .onChange(of: sounds) { Config.shared.sounds = sounds }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    do {
                        if launchAtLogin { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }

            Divider()

            Toggle("AI mode — rewrite with local LLM (Ollama)", isOn: $aiMode)
                .onChange(of: aiMode) { Config.shared.aiMode = aiMode }
            TextField("Ollama model:", text: $ollamaModel)
                .disabled(!aiMode)
                .onChange(of: ollamaModel) { Config.shared.ollamaModel = ollamaModel }

            Divider()

            TextField("Whisper model path:", text: $modelPath)
                .font(.system(size: 11))
                .onChange(of: modelPath) { Config.shared.modelPath = modelPath }
            HStack {
                Spacer()
                Button("Apply engine settings") { onEngineSettingsChanged?() }
                    .help("Restarts the local transcription engine")
            }
        }
        .padding(20)
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LocalWillow needs two permissions. Everything stays on this Mac.")
                .font(.callout)

            permissionRow(
                granted: perms.mic, title: "Microphone",
                detail: "To hear your dictation.",
                action: { perms.requestMic() })

            permissionRow(
                granted: perms.accessibility, title: "Accessibility",
                detail: "To detect the hold-to-dictate key and insert text at your cursor.",
                action: {
                    perms.requestAccessibility()
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                })

            if perms.mic && perms.accessibility {
                Label("All set — hold \(Config.shared.hotkey.label) in any app to dictate.",
                      systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .padding(.top, 4)
            } else {
                Text("The app picks up new grants automatically within a couple of seconds — no relaunch needed. Troubleshooting: if a grant doesn't register, remove LocalWillow from the list in System Settings (−), re-add it, then use Relaunch below.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Relaunch LocalWillow") { PermissionsModel.relaunchApp() }
            }
            Spacer()
        }
        .padding(20)
    }

    private func permissionRow(granted: Bool, title: String, detail: String,
                               action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if !granted { Button("Grant…", action: action) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private var dictionaryTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vocabulary — one term per line. Biases transcription toward your names and jargon.")
                .font(.caption)
            TextEditor(text: $vocabulary)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 110)
                .onChange(of: vocabulary) { Config.shared.vocabularyRaw = vocabulary }

            Text("Corrections — one per line, format:  heard text -> replacement")
                .font(.caption)
            TextEditor(text: $replacements)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 110)
                .onChange(of: replacements) { Config.shared.replacementsRaw = replacements }

            HStack {
                Spacer()
                Button("Apply engine settings") { onEngineSettingsChanged?() }
            }
        }
        .padding(20)
    }

    private var historyTab: some View {
        VStack(alignment: .leading) {
            if history.items.isEmpty {
                Spacer()
                Text("No dictations yet.").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(history.items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text).font(.system(size: 12)).lineLimit(3)
                        Text(item.date, style: .time)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.text, forType: .string)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Clear History") { history.clear() }
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
    }
}
