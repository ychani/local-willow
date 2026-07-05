import SwiftUI

struct DictationView: View {
    @StateObject private var engine = SpeechEngine()
    @StateObject private var history = HistoryStore()
    @AppStorage("locale") private var localeID = "en-US"
    @State private var authorized = false
    @State private var justCopied = false

    private let locales = [("en-US", "English"), ("ko-KR", "한국어")]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Language", selection: $localeID) {
                    ForEach(locales, id: \.0) { id, name in Text(name).tag(id) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                transcriptCard

                if let error = engine.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()
                historyList
                talkButton
                    .padding(.bottom, 24)
            }
            .navigationTitle("LocalWillow")
            .background(Color.black.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            authorized = await SpeechEngine.requestPermissions()
        }
    }

    private var transcriptCard: some View {
        ScrollView {
            Text(engine.partial.isEmpty
                 ? (engine.isRecording ? "Listening…" : "Hold the button and speak")
                 : engine.partial)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(engine.partial.isEmpty ? .secondary : .primary)
                .padding()
        }
        .frame(maxHeight: 180)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.10)))
        .padding(.horizontal)
    }

    private var historyList: some View {
        List {
            ForEach(history.items) { item in
                Button {
                    UIPasteboard.general.string = item.text
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text).lineLimit(2).font(.subheadline)
                        Text(item.date, style: .time)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: 220)
        .overlay {
            if history.items.isEmpty {
                Text("Dictations appear here and in the keyboard")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var talkButton: some View {
        ZStack {
            Circle()
                .fill(engine.isRecording ? Color.red : Color(white: 0.15))
                .frame(width: 96, height: 96)
                .scaleEffect(engine.isRecording ? 1.0 + CGFloat(engine.level) * 0.25 : 1.0)
                .animation(.easeOut(duration: 0.1), value: engine.level)
            if justCopied {
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                WaveformMark(animating: engine.isRecording)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard authorized, !engine.isRecording else { return }
                    engine.start(localeID: localeID)
                }
                .onEnded { _ in
                    guard engine.isRecording else { return }
                    Task {
                        let raw = await engine.stop()
                        let text = TextCleaner.clean(raw)
                        guard !text.isEmpty else { return }
                        history.add(text)
                        UIPasteboard.general.string = text
                        withAnimation { justCopied = true }
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        withAnimation { justCopied = false }
                    }
                }
        )
        .accessibilityLabel("Hold to dictate")
    }
}

/// Small five-bar waveform mark matching the product icon.
struct WaveformMark: View {
    var animating: Bool
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 5, height: barHeight(i))
            }
        }
        .animation(animating ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true) : .default,
                   value: phase)
        .onAppear { phase = true }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let base: [CGFloat] = [14, 24, 36, 24, 14]
        return animating && phase ? base[i] * 1.4 : base[i]
    }
}
