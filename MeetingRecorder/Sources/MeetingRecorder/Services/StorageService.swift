import Foundation
import Combine

/// All data is stored locally on-device in Application Support.
/// Nothing is synced to iCloud or any external service.
@MainActor
final class StorageService: ObservableObject {
    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var categories: [MeetingCategory] = []

    private let meetingsURL: URL
    private let categoriesURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static let shared = StorageService()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("MeetingRecorder", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        meetingsURL = base.appendingPathComponent("meetings.json")
        categoriesURL = base.appendingPathComponent("categories.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    // MARK: - Load / Save

    private func load() {
        meetings = (try? decoder.decode([Meeting].self, from: Data(contentsOf: meetingsURL))) ?? []
        categories = (try? decoder.decode([MeetingCategory].self, from: Data(contentsOf: categoriesURL))) ?? defaultCategories()
    }

    private func saveMeetings() {
        try? encoder.encode(meetings).write(to: meetingsURL, options: .atomic)
    }

    private func saveCategories() {
        try? encoder.encode(categories).write(to: categoriesURL, options: .atomic)
    }

    // MARK: - Meeting CRUD

    func save(_ meeting: Meeting) {
        if let idx = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[idx] = meeting
        } else {
            meetings.insert(meeting, at: 0)
        }
        saveMeetings()
        updateCategoryMembership(for: meeting)
    }

    func delete(_ meeting: Meeting) {
        meetings.removeAll { $0.id == meeting.id }
        // Remove audio file
        if let url = meeting.audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        saveMeetings()
    }

    func meeting(by id: UUID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    // MARK: - Search

    func search(query: String) -> [Meeting] {
        guard !query.isEmpty else { return meetings }
        let q = query.lowercased()
        return meetings.filter { meeting in
            meeting.title.lowercased().contains(q)
            || meeting.transcript.lowercased().contains(q)
            || (meeting.notes?.summary.lowercased().contains(q) ?? false)
            || meeting.tags.contains { $0.lowercased().contains(q) }
            || meeting.categories.contains { $0.lowercased().contains(q) }
            || (meeting.notes?.topicSummaries.contains { $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q) } ?? false)
        }
    }

    func meetings(in categoryName: String) -> [Meeting] {
        meetings.filter { $0.categories.contains(categoryName) }
    }

    func meetings(withTag tag: String) -> [Meeting] {
        meetings.filter { $0.tags.contains(tag) }
    }

    // MARK: - Category Management

    func addCategory(_ category: MeetingCategory) {
        guard !categories.contains(where: { $0.name == category.name }) else { return }
        categories.append(category)
        saveCategories()
    }

    func deleteCategory(id: UUID) {
        categories.removeAll { $0.id == id }
        saveCategories()
    }

    private func updateCategoryMembership(for meeting: Meeting) {
        for categoryName in meeting.categories {
            if let idx = categories.firstIndex(where: { $0.name == categoryName }) {
                if !categories[idx].meetingIds.contains(meeting.id) {
                    categories[idx].meetingIds.append(meeting.id)
                }
            } else {
                var newCat = MeetingCategory(name: categoryName)
                newCat.meetingIds = [meeting.id]
                categories.append(newCat)
            }
        }
        saveCategories()
    }

    // MARK: - Graph Data

    /// Returns all unique topic nodes and their connections across all meetings
    func buildGlobalGraph() -> (nodes: [String], edges: [GraphEdge]) {
        var nodeSet = Set<String>()
        var edges: [GraphEdge] = []

        for meeting in meetings {
            guard let notes = meeting.notes else { continue }
            for topic in notes.topicSummaries {
                nodeSet.insert(topic.title)
                for related in topic.relatedTopics {
                    nodeSet.insert(related)
                    edges.append(GraphEdge(source: topic.title, target: related, relationship: "관련"))
                }
            }
            edges.append(contentsOf: notes.categoryGraph)
        }

        return (Array(nodeSet), edges)
    }

    // MARK: - Defaults

    private func defaultCategories() -> [MeetingCategory] {
        [
            MeetingCategory(name: "전략", icon: "chart.bar", color: "#4A90D9"),
            MeetingCategory(name: "운영", icon: "gear", color: "#5BA85A"),
            MeetingCategory(name: "인사", icon: "person.2", color: "#E8A838"),
            MeetingCategory(name: "기술", icon: "cpu", color: "#9B59B6"),
            MeetingCategory(name: "마케팅", icon: "megaphone", color: "#E74C3C"),
        ]
    }
}
