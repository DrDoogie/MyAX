import SwiftUI

struct ContentView: View {
    @ObservedObject private var storage = StorageService.shared
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Record
            NavigationStack {
                RecordingView()
                    .navigationTitle("회의 녹음")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showSettings = true } label: {
                                Image(systemName: "gear")
                            }
                        }
                    }
            }
            .tabItem { Label("녹음", systemImage: "mic.circle.fill") }
            .tag(0)

            // Tab 2: Meeting List
            NavigationStack {
                MeetingListView(searchText: $searchText)
                    .searchable(text: $searchText, prompt: "회의록 검색")
                    .navigationTitle("회의록")
            }
            .tabItem { Label("회의록", systemImage: "doc.text.fill") }
            .tag(1)

            // Tab 3: Categories
            NavigationStack {
                CategoryListView()
                    .navigationTitle("카테고리")
            }
            .tabItem { Label("카테고리", systemImage: "folder.fill") }
            .tag(2)

            // Tab 4: Knowledge Graph
            GraphView()
                .tabItem { Label("그래프", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(3)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Meeting List

struct MeetingListView: View {
    @ObservedObject private var storage = StorageService.shared
    @Binding var searchText: String

    private var meetings: [Meeting] {
        searchText.isEmpty ? storage.meetings : storage.search(query: searchText)
    }

    var body: some View {
        Group {
            if meetings.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "회의록 없음" : "검색 결과 없음",
                    systemImage: "doc.text",
                    description: Text(searchText.isEmpty ? "녹음 탭에서 회의를 시작하세요." : "'\(searchText)'에 대한 결과가 없습니다.")
                )
            } else {
                List {
                    ForEach(meetings) { meeting in
                        NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                            MeetingRow(meeting: meeting)
                        }
                    }
                    .onDelete { offsets in
                        offsets.forEach { storage.delete(meetings[$0]) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}

struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meeting.title).font(.headline).lineLimit(1)
                Spacer()
                statusBadge
            }
            Text(meeting.date, style: .date)
                .font(.caption).foregroundStyle(.secondary)
            if let summary = meeting.notes?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !meeting.categories.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(meeting.categories.prefix(3), id: \.self) { c in
                        CategoryChip(label: c)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch meeting.status {
        case .recording:
            Label("녹음중", systemImage: "record.circle").foregroundStyle(.red).font(.caption)
        case .processing:
            Label("처리중", systemImage: "hourglass").foregroundStyle(.orange).font(.caption)
        case .completed:
            EmptyView()
        case .failed:
            Label("실패", systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption)
        }
    }
}

// MARK: - Category List

struct CategoryListView: View {
    @ObservedObject private var storage = StorageService.shared

    var body: some View {
        List {
            ForEach(storage.categories) { cat in
                NavigationLink(destination: CategoryDetailView(category: cat)) {
                    HStack(spacing: 12) {
                        Image(systemName: cat.icon)
                            .foregroundStyle(Color(hex: cat.color) ?? .accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(cat.name).font(.headline)
                            Text("\(cat.meetingIds.count)건").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct CategoryDetailView: View {
    let category: MeetingCategory
    @ObservedObject private var storage = StorageService.shared

    private var meetings: [Meeting] {
        storage.meetings(in: category.name)
    }

    var body: some View {
        List {
            ForEach(meetings) { meeting in
                NavigationLink(destination: MeetingDetailView(meeting: meeting)) {
                    MeetingRow(meeting: meeting)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.name)
        .overlay {
            if meetings.isEmpty {
                ContentUnavailableView("회의록 없음", systemImage: "doc.text")
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @State private var apiKey = KeychainHelper.load(key: "anthropic_api_key") ?? ""
    @State private var showKey = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $apiKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                        }
                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Anthropic API 키")
                } footer: {
                    Text("API 키는 기기 Keychain에 안전하게 저장됩니다. 외부로 전송되지 않습니다.")
                }

                Section("개인정보 보호") {
                    Label("모든 녹음은 기기에만 저장됩니다", systemImage: "lock.shield")
                    Label("음성 인식은 기기 내에서 처리됩니다", systemImage: "mic.badge.xmark")
                    Label("iCloud 동기화 비활성화됨", systemImage: "icloud.slash")
                }

                Section {
                    Button("저장") {
                        KeychainHelper.save(key: "anthropic_api_key", value: apiKey)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
