import SwiftUI
import AVFoundation
import Speech
import AppKit

// ─────────────────────────────────────────────
// MARK: - App Entry
// ─────────────────────────────────────────────

@main
struct MeetingRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            RecordingWindowView()
                .frame(width: 340, height: 420)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
