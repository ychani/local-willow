import AppKit
import SwiftUI

/// State shared with the floating pill overlay.
final class OverlayModel: ObservableObject {
    enum Phase { case recording, processing }
    @Published var phase: Phase = .recording
    @Published var level: Float = 0
    /// Ring buffer of recent levels drawn as waveform bars.
    @Published var bars: [Float] = Array(repeating: 0.05, count: 24)

    func push(level: Float) {
        self.level = level
        bars.removeFirst()
        bars.append(max(0.05, level))
    }
}

struct PillView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            if model.phase == .recording {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 13, weight: .semibold))
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(Array(model.bars.enumerated()), id: \.offset) { _, v in
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 2.5, height: CGFloat(4 + v * 22))
                    }
                }
                .animation(.linear(duration: 0.05), value: model.bars)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
                Text("Transcribing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(
            Capsule().fill(Color.black.opacity(0.82))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        )
        .padding(20)
    }
}

/// Borderless, click-through, always-on-top pill centered near the bottom of the screen —
/// the visual anchor while dictating, like Willow's.
final class OverlayPanel {
    private var panel: NSPanel?
    let model = OverlayModel()

    func show(phase: OverlayModel.Phase) {
        model.phase = phase
        if panel == nil { build() }
        position()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        model.bars = Array(repeating: 0.05, count: 24)
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: PillView(model: model))
        host.frame = p.contentRect(forFrameRect: p.frame)
        p.contentView = host
        panel = p
    }

    private func position() {
        guard let p = panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = p.contentView?.fittingSize ?? NSSize(width: 320, height: 80)
        p.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + 60,
                          width: size.width, height: size.height), display: true)
    }
}
