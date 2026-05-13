import SwiftUI

// ─────────────────────────────────────────────
// MARK: - 회의록 목록 화면
// ─────────────────────────────────────────────

struct HistoryScreen: View {
    @ObservedObject private var db = LocalDB.shared
    @State private var query = ""
    @State private var selected: SavedMeeting?

    private var results: [SavedMeeting] {
        guard !query.isEmpty else { return db.meetings }
        let q = query.lowercased()
        return db.meetings.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "저장된 회의록이 없습니다" : "검색 결과 없음",
                    systemImage: "doc.text",
                    description: Text(query.isEmpty
                        ? "녹음 탭에서 회의를 시작하면 자동으로 저장됩니다."
                        : "'\(query)'에 대한 결과가 없습니다.")
                )
            } else {
                List {
                    ForEach(results) { m in
                        Button { selected = m } label: {
                            MeetingRow(meeting: m)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { db.delete(at: $0) }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("회의록 목록")
        .searchable(text: $query, prompt: "제목 또는 내용 검색")
        .sheet(item: $selected) { m in
            NoteDetailView(meeting: m)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - 목록 행
// ─────────────────────────────────────────────

struct MeetingRow: View {
    let meeting: SavedMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 12) {
                Label(meeting.date.formatted(.dateTime.month().day().hour().minute()),
                      systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
                Label(formatSec(meeting.seconds), systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // 미리보기: 첫 번째 내용 줄
            if let preview = meeting.body.components(separatedBy: "\n")
                .first(where: { !$0.hasPrefix("#") && !$0.isEmpty }) {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSec(_ s: Int) -> String {
        s >= 60 ? "\(s/60)분 \(s%60)초" : "\(s)초"
    }
}

// ─────────────────────────────────────────────
// MARK: - 회의록 상세 / 마크다운 뷰
// ─────────────────────────────────────────────

struct NoteDetailView: View {
    let meeting: SavedMeeting
    @State private var showShare = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MarkdownBody(text: meeting.body)
                    .padding()
            }
            .navigationTitle(meeting.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                ShareView(text: meeting.body, title: meeting.title)
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - 마크다운 렌더러 (간단 버전)
// ─────────────────────────────────────────────

struct MarkdownBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(for: line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(for line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(line.dropFirst(2))
                .font(.title2.bold())
                .padding(.top, 8)
        } else if line.hasPrefix("## ") {
            Text(line.dropFirst(3))
                .font(.title3.weight(.semibold))
                .padding(.top, 6)
        } else if line.hasPrefix("### ") {
            Text(line.dropFirst(4))
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } else if line.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundStyle(.accentColor)
                Text(line.dropFirst(2))
            }
            .font(.body)
        } else if line == "---" {
            Divider().padding(.vertical, 4)
        } else if line.isEmpty {
            Spacer().frame(height: 2)
        } else {
            // **굵게** 처리
            let parts = line.components(separatedBy: "**")
            if parts.count > 1 {
                parts.enumerated().reduce(Text("")) { acc, pair in
                    pair.offset % 2 == 0
                        ? acc + Text(pair.element)
                        : acc + Text(pair.element).bold()
                }
                .font(.body)
            } else {
                Text(line).font(.body)
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - 공유 시트
// ─────────────────────────────────────────────

struct ShareView: UIViewControllerRepresentable {
    let text: String
    let title: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.setValue(title, forKey: "subject")
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
