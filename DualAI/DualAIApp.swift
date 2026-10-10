import SwiftUI

@main
struct DualAIApp: App {
    var body: some Scene {
        WindowGroup {
            WebContainer()
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}
