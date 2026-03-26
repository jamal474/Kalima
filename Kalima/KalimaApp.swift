import SwiftUI
import SwiftData

// To use this, replace the contents of the main App file generated in your new Xcode project with this code.
@main
struct kalimaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // This injects the SwiftData container and its persistent store into the environment.
        .modelContainer(for: Word.self)
    }
}
