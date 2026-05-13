import SwiftUI

@main
struct MeetingRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                RecordingScreen()
            }
            .tabItem {
                Label("녹음", systemImage: "mic.circle.fill")
            }

            NavigationStack {
                HistoryScreen()
            }
            .tabItem {
                Label("회의록", systemImage: "doc.text.fill")
            }

            NavigationStack {
                SettingsScreen()
            }
            .tabItem {
                Label("설정", systemImage: "gear")
            }
        }
    }
}
