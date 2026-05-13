import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting
    @State private var selectedTab = 0
    @State private var showMindMap = false
    @State private var savedToNotes = false
    @State private var shareText: String?
    @Environment(\.dismiss) private var dismiss

    private var notes: MeetingNotes? { meeting.notes }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    Text("요약").tag(0)
                    Text("주제").tag(1)
                    Text("지시/제안").tag(2)
                    Text("마인드맵").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                TabView(selection: $selectedTab) {
                    SummaryTabView(meeting: meeting).tag(0)
                    TopicsTabView(topics: notes?.topicSummaries ?? []).tag(1)
                    DirectivesTabView(
                        directives: notes?.directives ?? [],
                        suggestions: notes?.suggestions ?? []
                    ).tag(2)
                    MindMapTabView(nodes: notes?.mindMapNodes ?? []).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(meeting.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                #if os(macOS)
                                if let n = meeting.notes {
                                    try? await AppleNotesService.save(meeting)
                                    savedToNotes = true
                                }
                                #endif
                            }
                        } label: {
                            Label("Apple 메모에 저장", systemImage: "note.text")
                        }

                        Button {
                            if let notes = meeting.notes {
                                shareText = AppleNotesService.formatNote(meeting: meeting, notes: notes)
                            }
                        } label: {
                            Label("텍스트 내보내기", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if savedToNotes {
                    VStack {
                        Spacer()
                        Label("Apple 메모에 저장됨", systemImage: "checkmark.circle.fill")
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 32)
                            .task {
                                try? await Task.sleep(for: .seconds(2))
                                savedToNotes = false
                            }
                    }
                }
            }
            #if os(iOS)
            .sheet(item: Binding(get: { shareText.map { ShareItem(text: $0) } },
                                 set: { _ in shareText = nil })) { item in
                ShareSheet(text: item.text)
            }
            #endif
        }
    }
}

// MARK: - Summary Tab

struct SummaryTabView: View {
    let meeting: Meeting
    private var notes: MeetingNotes? { meeting.notes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Meta
                metaCard

                // Overall summary
                if let summary = notes?.summary, !summary.isEmpty {
                    sectionCard(title: "전체 요약", icon: "doc.text") {
                        Text(summary)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Decisions
                let decisions = notes?.decisions ?? []
                if !decisions.isEmpty {
                    sectionCard(title: "결정 사항", icon: "checkmark.seal") {
                        ForEach(decisions, id: \.self) { d in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.callout)
                                    .padding(.top, 2)
                                Text(d).font(.callout)
                            }
                        }
                    }
                }

                // Categories & Tags
                if !meeting.categories.isEmpty {
                    sectionCard(title: "카테고리", icon: "tag") {
                        FlowLayout(spacing: 8) {
                            ForEach(meeting.categories, id: \.self) { c in
                                CategoryChip(label: c)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            let df = DateFormatter()
            let _ = { df.locale = Locale(identifier: "ko_KR"); df.dateStyle = .full; df.timeStyle = .short }()
            Label(df.string(from: meeting.date), systemImage: "calendar")
            Label(formatDuration(meeting.duration), systemImage: "clock")
            if let participants = notes?.participants, !participants.isEmpty {
                Label(participants.joined(separator: ", "), systemImage: "person.2")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return m > 0 ? "\(m)분 \(s)초" : "\(s)초"
    }
}

// MARK: - Topics Tab

struct TopicsTabView: View {
    let topics: [TopicSummary]
    @State private var expanded: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(topics) { topic in
                    TopicCard(topic: topic, isExpanded: expanded.contains(topic.id)) {
                        if expanded.contains(topic.id) {
                            expanded.remove(topic.id)
                        } else {
                            expanded.insert(topic.id)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct TopicCard: View {
    let topic: TopicSummary
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.title).font(.headline)
                        if !topic.category.isEmpty {
                            Text(topic.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text(topic.content)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    if !topic.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("핵심 포인트").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                            ForEach(topic.keyPoints, id: \.self) { kp in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundStyle(.accentColor)
                                    Text(kp).font(.callout)
                                }
                            }
                        }
                    }

                    if !topic.relatedTopics.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(topic.relatedTopics, id: \.self) { rt in
                                Text("# \(rt)")
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.accentColor)
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Directives Tab

struct DirectivesTabView: View {
    let directives: [Directive]
    let suggestions: [Suggestion]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !directives.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("지시 사항", systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(directives) { d in
                            DirectiveRow(directive: d)
                        }
                    }
                }

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("제안 사항", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(suggestions) { s in
                            SuggestionRow(suggestion: s)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

struct DirectiveRow: View {
    let directive: Directive

    var priorityColor: Color {
        switch directive.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(priorityColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(directive.content).font(.callout)
                HStack(spacing: 12) {
                    if !directive.assignee.isEmpty {
                        Label(directive.assignee, systemImage: "person")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !directive.deadline.isEmpty {
                        Label(directive.deadline, systemImage: "calendar.badge.clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text(directive.priority.displayName)
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(priorityColor.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(priorityColor)

                    Spacer()
                }
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct SuggestionRow: View {
    let suggestion: Suggestion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.yellow)
                .font(.title3)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.content).font(.callout)
                if !suggestion.proposedBy.isEmpty {
                    Text("제안: \(suggestion.proposedBy)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct MindMapTabView: View {
    let nodes: [MindMapNode]

    var body: some View {
        if nodes.isEmpty {
            ContentUnavailableView("마인드맵 없음", systemImage: "map", description: Text("회의록이 처리되면 마인드맵이 생성됩니다."))
        } else {
            MindMapView(rootNodes: nodes)
        }
    }
}

// MARK: - Helpers

struct CategoryChip: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(.accentColor)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, in: proposal.replacingUnspecifiedDimensions()).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, in: CGSize(width: bounds.width, height: .infinity))
        for (view, pos) in zip(subviews, result.positions) {
            view.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, in size: CGSize) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for view in subviews {
            let viewSize = view.sizeThatFits(.unspecified)
            if x + viewSize.width > size.width && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += viewSize.width + spacing
            rowHeight = max(rowHeight, viewSize.height)
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

#if os(iOS)
struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
