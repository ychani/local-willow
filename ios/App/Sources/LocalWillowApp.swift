import SwiftUI

@main
struct LocalWillowApp: App {
    var body: some Scene {
        WindowGroup {
            DictationView()
                .preferredColorScheme(.dark)
        }
    }
}
