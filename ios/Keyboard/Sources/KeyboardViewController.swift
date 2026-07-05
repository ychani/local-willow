import SwiftUI
import UIKit

/// Custom keyboard: shows recent LocalWillow dictations (via the App Group)
/// and inserts one into the current text field with a tap. Keyboards can't
/// use the microphone on iOS, so the mic button jumps to the main app.
final class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(rootView: KeyboardView(
            insert: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            deleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            nextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            openApp: { [weak self] in
                self?.openMainApp()
            }
        ))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: 240),
        ])
        host.didMove(toParent: self)
    }

    /// Extensions can't call UIApplication.open directly; walk the responder
    /// chain to reach the host app's opener.
    private func openMainApp() {
        guard let url = URL(string: "localwillow://dictate") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }
}

struct KeyboardView: View {
    let insert: (String) -> Void
    let deleteBackward: () -> Void
    let nextKeyboard: () -> Void
    let openApp: () -> Void

    @State private var items: [HistoryItem] = []

    var body: some View {
        VStack(spacing: 8) {
            if items.isEmpty {
                Text("Dictate in LocalWillow — results appear here")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            Button { insert(item.text) } label: {
                                Text(item.text)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(white: 0.16)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Button(action: nextKeyboard) {
                    Image(systemName: "globe").frame(width: 44, height: 36)
                }
                Button(action: openApp) {
                    Label("Dictate", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.2)))
                }
                .buttonStyle(.plain)
                Button(action: deleteBackward) {
                    Image(systemName: "delete.left").frame(width: 44, height: 36)
                }
            }
            .padding(.bottom, 4)
        }
        .padding(10)
        .background(Color(white: 0.07))
        .colorScheme(.dark)
        .onAppear { reload() }
    }

    private func reload() {
        guard let defaults = UserDefaults(suiteName: HistoryStore.suite) else { return }
        items = HistoryStore.load(from: defaults)
    }
}
