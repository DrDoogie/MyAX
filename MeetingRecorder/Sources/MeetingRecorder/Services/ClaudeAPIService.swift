import Foundation

/// Calls the Anthropic API locally. The API key is stored in the iOS Keychain,
/// never hardcoded. Transcript and notes never leave the device except for
/// this single structured API call.
final class ClaudeAPIService {
    private let model = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private var apiKey: String {
        KeychainHelper.load(key: "anthropic_api_key") ?? ""
    }

    func structureMeetingNotes(transcript: String, title: String) async throws -> MeetingNotes {
        let prompt = buildPrompt(transcript: transcript, title: title)
        let responseText = try await callClaude(prompt: prompt)
        return try parseResponse(responseText)
    }

    // MARK: - Prompt

    private func buildPrompt(transcript: String, title: String) -> String {
        """
        당신은 회의록 전문 작성 AI입니다. 아래 회의 녹취록을 분석하여 JSON 형식으로 구조화된 회의록을 작성하세요.

        회의 제목: \(title)

        회의 녹취록:
        \(transcript)

        다음 JSON 구조로 응답하세요. 반드시 유효한 JSON만 반환하고 다른 텍스트는 포함하지 마세요:

        {
          "summary": "전체 회의 요약 (3-5문장)",
          "participants": ["참여자1", "참여자2"],
          "topicSummaries": [
            {
              "title": "주제명",
              "content": "주제에 대한 상세 요약",
              "keyPoints": ["핵심 포인트1", "핵심 포인트2"],
              "relatedTopics": ["관련 주제명"],
              "category": "카테고리명"
            }
          ],
          "directives": [
            {
              "content": "지시 내용",
              "assignee": "담당자",
              "deadline": "기한",
              "priority": "high|medium|low"
            }
          ],
          "suggestions": [
            {
              "content": "제안 내용",
              "proposedBy": "제안자",
              "relatedTopic": "관련 주제"
            }
          ],
          "decisions": ["결정 사항1", "결정 사항2"],
          "mindMapNodes": [
            {
              "label": "회의 루트 노드",
              "nodeType": "root",
              "color": "#4A90D9",
              "detail": "",
              "children": [
                {
                  "label": "주제1",
                  "nodeType": "topic",
                  "color": "#5BA85A",
                  "detail": "주제 설명",
                  "children": [
                    {
                      "label": "세부사항",
                      "nodeType": "subtopic",
                      "color": "#E8A838",
                      "detail": "세부 내용",
                      "children": []
                    }
                  ]
                }
              ]
            }
          ],
          "categoryGraph": [
            {
              "source": "노드A",
              "target": "노드B",
              "relationship": "관계설명"
            }
          ]
        }

        지시사항:
        1. topicSummaries: 주제별 상세 요약. 각 주제마다 핵심 포인트를 명확히 추출
        2. directives: 지시, 명령, 할당된 업무만 포함 (제안과 구분)
        3. suggestions: 제안, 아이디어, 고려사항만 포함
        4. mindMapNodes: 계층적 마인드맵 구조. root → topic → subtopic → action/decision
        5. categoryGraph: 주제들 간의 연결 관계 (Obsidian 링크 구조)
        6. 모든 내용은 한국어로 작성
        """
    }

    // MARK: - API Call

    private func callClaude(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ClaudeError.apiError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    // MARK: - Parse

    private func parseResponse(_ text: String) throws -> MeetingNotes {
        // Extract JSON block if wrapped in markdown
        let jsonString: String
        if let start = text.range(of: "{"), let end = text.range(of: "}", options: .backwards) {
            jsonString = String(text[start.lowerBound...end.upperBound])
        } else {
            jsonString = text
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeError.parseError
        }

        let raw = try JSONDecoder().decode(RawMeetingNotesResponse.self, from: data)
        return raw.toMeetingNotes()
    }
}

// MARK: - Response Types

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable {
        let text: String
    }
}

private struct RawMeetingNotesResponse: Decodable {
    let summary: String
    let participants: [String]?
    let topicSummaries: [RawTopic]
    let directives: [RawDirective]
    let suggestions: [RawSuggestion]
    let decisions: [String]?
    let mindMapNodes: [RawMindMapNode]
    let categoryGraph: [RawGraphEdge]?

    struct RawTopic: Decodable {
        let title: String
        let content: String
        let keyPoints: [String]?
        let relatedTopics: [String]?
        let category: String?
    }

    struct RawDirective: Decodable {
        let content: String
        let assignee: String?
        let deadline: String?
        let priority: String?
    }

    struct RawSuggestion: Decodable {
        let content: String
        let proposedBy: String?
        let relatedTopic: String?
    }

    struct RawMindMapNode: Decodable {
        let label: String
        let nodeType: String?
        let color: String?
        let detail: String?
        let children: [RawMindMapNode]?
    }

    struct RawGraphEdge: Decodable {
        let source: String
        let target: String
        let relationship: String?
    }

    func toMeetingNotes() -> MeetingNotes {
        var notes = MeetingNotes()
        notes.summary = summary
        notes.participants = participants ?? []
        notes.decisions = decisions ?? []

        notes.topicSummaries = topicSummaries.map { raw in
            TopicSummary(
                title: raw.title,
                content: raw.content,
                keyPoints: raw.keyPoints ?? [],
                relatedTopics: raw.relatedTopics ?? [],
                category: raw.category ?? ""
            )
        }

        notes.directives = directives.map { raw in
            Directive(
                content: raw.content,
                assignee: raw.assignee ?? "",
                deadline: raw.deadline ?? "",
                priority: Priority(rawValue: raw.priority ?? "medium") ?? .medium
            )
        }

        notes.suggestions = suggestions.map { raw in
            Suggestion(
                content: raw.content,
                proposedBy: raw.proposedBy ?? "",
                relatedTopic: raw.relatedTopic ?? ""
            )
        }

        notes.mindMapNodes = mindMapNodes.map { convertNode($0) }

        notes.categoryGraph = (categoryGraph ?? []).map { raw in
            GraphEdge(source: raw.source, target: raw.target, relationship: raw.relationship ?? "")
        }

        return notes
    }

    private func convertNode(_ raw: RawMindMapNode) -> MindMapNode {
        MindMapNode(
            label: raw.label,
            detail: raw.detail ?? "",
            children: (raw.children ?? []).map { convertNode($0) },
            nodeType: MindMapNode.NodeType(rawValue: raw.nodeType ?? "topic") ?? .topic,
            color: raw.color ?? "#4A90D9"
        )
    }
}

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case apiError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API 키가 설정되지 않았습니다. 설정에서 Anthropic API 키를 입력해주세요."
        case .apiError(let code): return "API 오류: HTTP \(code)"
        case .parseError: return "응답 파싱에 실패했습니다."
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
