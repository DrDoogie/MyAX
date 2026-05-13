import SwiftUI

@main
struct MeetingRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 700)
        #endif
    }
}
