import SwiftUI

// ─────────────────────────────────────────────────────
// MARK: - History (저장된 회의록 목록)
// ─────────────────────────────────────────────────────

struct HistoryView: View {
    @ObservedObject var storage: LocalStorage
    @State private var searchText = ""

    private var meetings: [SavedMeeting] {
        guard !searchText.isEmpty else { return storage.meetings }
        let q = searchText.lowercased()
        return storage.meetings.filter {
            $0.title.lowercased().contains(q) || $0.markdownBody.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if meetings.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "저장된 회의록 없음" : "검색 결과 없음",
                    systemImage: "doc.text",
                    description: Text(searchText.isEmpty
                        ? "녹음 후 회의록이 자동으로 저장됩니다."
                        : "'\(searchText)'에 맞는 결과가 없습니다.")
                )
            } else {
                List {
                    ForEach(meetings) { meeting in
                        NavigationLink(destination: MeetingNoteView(meeting: meeting)) {
                            MeetingRow(meeting: meeting)
                        }
                    }
                    .onDelete { offsets in
                        storage.delete(at: offsets)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("회의록 목록")
        .searchable(text: $searchText, prompt: "제목 또는 내용 검색")
    }
}

struct MeetingRow: View {
    let meeting: SavedMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 12) {
                Label(meeting.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(formatDuration(meeting.durationSeconds), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Preview first meaningful line
            let preview = meeting.markdownBody
                .components(separatedBy: "\n")
                .first { !$0.hasPrefix("#") && !$0.isEmpty }
            if let preview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ s: Int) -> String {
        s >= 60 ? "\(s/60)분 \(s%60)초" : "\(s)초"
    }
}

// ─────────────────────────────────────────────────────
// MARK: - Note Detail View
// ─────────────────────────────────────────────────────

struct MeetingNoteView: View {
    let meeting: SavedMeeting
    @State private var showShare = false

    var body: some View {
        ScrollView {
            MarkdownTextView(text: meeting.markdownBody)
                .padding()
        }
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(text: meeting.markdownBody, title: meeting.title)
        }
    }
}

// ─────────────────────────────────────────────────────
// MARK: - Simple Markdown Renderer
// ─────────────────────────────────────────────────────

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(line.dropFirst(2))
                .font(.title2.weight(.bold))
                .padding(.top, 8)
        } else if line.hasPrefix("## ") {
            Text(line.dropFirst(3))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.top, 6)
        } else if line.hasPrefix("### ") {
            Text(line.dropFirst(4))
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } else if line.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(.accentColor)
                    .font(.body)
                Text(line.dropFirst(2))
                    .font(.body)
            }
        } else if line.hasPrefix("**") && line.hasSuffix("**") {
            Text(line.replacingOccurrences(of: "**", with: ""))
                .font(.body.weight(.semibold))
        } else if line == "---" {
            Divider().padding(.vertical, 4)
        } else if line.isEmpty {
            Spacer().frame(height: 4)
        } else {
            Text(try! AttributedString(markdown: line))
                .font(.body)
        }
    }
}

// ─────────────────────────────────────────────────────
// MARK: - Share Sheet
// ─────────────────────────────────────────────────────

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    let title: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.setValue(title, forKey: "subject")
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// ─────────────────────────────────────────────────────
// MARK: - Settings View
// ─────────────────────────────────────────────────────

struct SettingsView: View {
    @State private var apiKey = KeychainHelper.load(key: "anthropic_api_key") ?? ""
    @State private var showKey = false
    @State private var saved = false

    // Obsidian
    private let vaultService = ObsidianVaultService()
    @State private var showVaultPicker = false
    @State private var vaultSubpath = ""
    @State private var vaultConnected = false

    var body: some View {
        Form {
            // ── API Key ───────────────────────────────────
            Section {
                HStack {
                    if showKey {
                        TextField("sk-ant-...", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
                    } else {
                        SecureField("sk-ant-...", text: $apiKey)
                            .textInputAutocapitalization(.never)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    KeychainHelper.save(key: "anthropic_api_key", value: apiKey)
                    withAnimation { saved = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        saved = false
                    }
                } label: {
                    HStack {
                        Text("저장")
                        if saved {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text("Anthropic API 키")
            } footer: {
                Text("api.anthropic.com에서 발급. Keychain에 안전하게 저장됩니다.")
            }

            // ── Obsidian Vault ────────────────────────────
            Section {
                if vaultConnected {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("볼트 연결됨").font(.body)
                            if !vaultService.displayPath.isEmpty {
                                Text(vaultService.displayPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                } else {
                    Label("볼트 미연결", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }

                Button {
                    showVaultPicker = true
                } label: {
                    Label("볼트 폴더 선택", systemImage: "folder.badge.plus")
                }

                HStack {
                    Text("하위 경로")
                    Spacer()
                    TextField("예: MyVault", text: $vaultSubpath)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: vaultSubpath) { _, v in vaultService.subpath = v }
                }
            } header: {
                Text("Obsidian 볼트 (주간 서머리)")
            } footer: {
                Text("iCloud Drive → Obsidian 앱 폴더를 선택하세요. 필요시 그 안의 특정 볼트 폴더 이름을 하위 경로에 입력합니다.")
            }

            // ── Privacy ───────────────────────────────────
            Section("개인정보 보호") {
                Label("녹음 파일: 기기에만 저장", systemImage: "lock.fill")
                Label("음성 인식: 기기 내 처리 우선", systemImage: "iphone")
                Label("회의록: iCloud 동기화 없음", systemImage: "icloud.slash")
                Label("API 호출: 텍스트만 전송 (음성 파일 제외)", systemImage: "network")
            }

            Section("저장 위치") {
                Label("앱 내 회의록 탭에서 조회", systemImage: "doc.text.below.ecg")
                Label("공유 버튼으로 메모 앱에 저장", systemImage: "square.and.arrow.up")
            }
        }
        .navigationTitle("설정")
        .onAppear {
            vaultSubpath = vaultService.subpath
            vaultConnected = (vaultService.resolvedVaultURL() != nil)
        }
        .fileImporter(
            isPresented: $showVaultPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vaultService.saveVaultFolder(url)
                vaultConnected = (vaultService.resolvedVaultURL() != nil)
            }
        }
    }
}
