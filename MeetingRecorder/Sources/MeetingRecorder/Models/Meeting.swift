import Foundation

// MARK: - Core Models

struct Meeting: Identifiable, Codable {
    let id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var audioFileURL: URL?
    var transcript: String
    var notes: MeetingNotes?
    var categories: [String]
    var tags: [String]
    var status: MeetingStatus

    init(id: UUID = UUID(), title: String = "", date: Date = Date()) {
        self.id = id
        self.title = title
        self.date = date
        self.duration = 0
        self.audioFileURL = nil
        self.transcript = ""
        self.notes = nil
        self.categories = []
        self.tags = []
        self.status = .recording
    }
}

enum MeetingStatus: String, Codable, CaseIterable {
    case recording = "recording"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

// MARK: - Structured Meeting Notes

struct MeetingNotes: Codable {
    var summary: String
    var topicSummaries: [TopicSummary]
    var directives: [Directive]
    var suggestions: [Suggestion]
    var decisions: [String]
    var participants: [String]
    var mindMapNodes: [MindMapNode]
    var categoryGraph: [GraphEdge]

    init() {
        summary = ""
        topicSummaries = []
        directives = []
        suggestions = []
        decisions = []
        participants = []
        mindMapNodes = []
        categoryGraph = []
    }
}

struct TopicSummary: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var keyPoints: [String]
    var relatedTopics: [String]
    var category: String

    init(id: UUID = UUID(), title: String, content: String, keyPoints: [String] = [], relatedTopics: [String] = [], category: String = "") {
        self.id = id
        self.title = title
        self.content = content
        self.keyPoints = keyPoints
        self.relatedTopics = relatedTopics
        self.category = category
    }
}

struct Directive: Identifiable, Codable {
    let id: UUID
    var content: String
    var assignee: String
    var deadline: String
    var priority: Priority
    var status: ActionStatus

    init(id: UUID = UUID(), content: String, assignee: String = "", deadline: String = "", priority: Priority = .medium) {
        self.id = id
        self.content = content
        self.assignee = assignee
        self.deadline = deadline
        self.priority = priority
        self.status = .pending
    }
}

struct Suggestion: Identifiable, Codable {
    let id: UUID
    var content: String
    var proposedBy: String
    var relatedTopic: String

    init(id: UUID = UUID(), content: String, proposedBy: String = "", relatedTopic: String = "") {
        self.id = id
        self.content = content
        self.proposedBy = proposedBy
        self.relatedTopic = relatedTopic
    }
}

enum Priority: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var displayName: String {
        switch self {
        case .high: return "높음"
        case .medium: return "보통"
        case .low: return "낮음"
        }
    }
}

enum ActionStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case inProgress = "inProgress"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .pending: return "대기"
        case .inProgress: return "진행중"
        case .completed: return "완료"
        }
    }
}

// MARK: - Mind Map

struct MindMapNode: Identifiable, Codable {
    let id: UUID
    var label: String
    var detail: String
    var children: [MindMapNode]
    var nodeType: NodeType
    var color: String

    init(id: UUID = UUID(), label: String, detail: String = "", children: [MindMapNode] = [], nodeType: NodeType = .topic, color: String = "#4A90D9") {
        self.id = id
        self.label = label
        self.detail = detail
        self.children = children
        self.nodeType = nodeType
        self.color = color
    }

    enum NodeType: String, Codable {
        case root
        case topic
        case subtopic
        case action
        case decision
    }
}

struct GraphEdge: Identifiable, Codable {
    let id: UUID
    var source: String
    var target: String
    var relationship: String

    init(id: UUID = UUID(), source: String, target: String, relationship: String = "") {
        self.id = id
        self.source = source
        self.target = target
        self.relationship = relationship
    }
}

// MARK: - Category

struct MeetingCategory: Identifiable, Codable {
    let id: UUID
    var name: String
    var icon: String
    var color: String
    var meetingIds: [UUID]
    var subcategories: [String]

    init(id: UUID = UUID(), name: String, icon: String = "folder", color: String = "#4A90D9") {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.meetingIds = []
        self.subcategories = []
    }
}
