import Foundation

/// Saves meeting notes to Apple Notes via AppleScript (macOS) or
/// EventKit Notes framework (iOS). Content stays on-device.
enum AppleNotesService {

    // MARK: - macOS (AppleScript)

    #if os(macOS)
    @discardableResult
    static func save(_ meeting: Meeting) async throws -> Bool {
        guard let notes = meeting.notes else { throw NotesError.noContent }
        let body = formatNote(meeting: meeting, notes: notes)
        let folderName = "회의록"
        let script = buildAppleScript(title: meeting.title, body: body, folder: folderName)
        return try await runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                script?.executeAndReturnError(&error)
                if let err = error {
                    continuation.resume(throwing: NotesError.appleScriptError(err.description))
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }

    private static func buildAppleScript(title: String, body: String, folder: String) -> String {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        return """
        tell application "Notes"
            activate
            if not (exists folder "\(folder)") then
                make new folder with properties {name:"\(folder)"}
            end if
            set targetFolder to folder "\(folder)"
            make new note at targetFolder with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
        end tell
        """
    }
    #endif

    // MARK: - iOS (Shortcuts URL Scheme fallback)

    #if os(iOS)
    static func save(_ meeting: Meeting) async throws {
        guard let notes = meeting.notes else { throw NotesError.noContent }
        let body = formatNote(meeting: meeting, notes: notes)
        // On iOS, open Notes app with pre-filled content via share sheet
        // This is handled in the UI layer via UIActivityViewController
        _ = body // content available for share sheet
    }
    #endif

    // MARK: - Note Formatter

    static func formatNote(meeting: Meeting, notes: MeetingNotes) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        var lines: [String] = []

        lines.append("# \(meeting.title)")
        lines.append("날짜: \(dateFormatter.string(from: meeting.date))")
        lines.append("소요시간: \(formatDuration(meeting.duration))")
        if !notes.participants.isEmpty {
            lines.append("참석자: \(notes.participants.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("---")
        lines.append("")

        // Summary
        lines.append("## 전체 요약")
        lines.append(notes.summary)
        lines.append("")

        // Topics
        if !notes.topicSummaries.isEmpty {
            lines.append("## 주제별 요약")
            for topic in notes.topicSummaries {
                lines.append("")
                lines.append("### \(topic.title)")
                if !topic.category.isEmpty {
                    lines.append("카테고리: \(topic.category)")
                }
                lines.append(topic.content)
                if !topic.keyPoints.isEmpty {
                    lines.append("")
                    lines.append("**핵심 포인트:**")
                    topic.keyPoints.forEach { lines.append("- \($0)") }
                }
            }
            lines.append("")
        }

        // Directives
        if !notes.directives.isEmpty {
            lines.append("---")
            lines.append("")
            lines.append("## 지시 사항")
            for d in notes.directives {
                var line = "- [\(d.priority.displayName)] \(d.content)"
                if !d.assignee.isEmpty { line += " (담당: \(d.assignee))" }
                if !d.deadline.isEmpty { line += " (기한: \(d.deadline))" }
                lines.append(line)
            }
            lines.append("")
        }

        // Suggestions
        if !notes.suggestions.isEmpty {
            lines.append("## 제안 사항")
            for s in notes.suggestions {
                var line = "- \(s.content)"
                if !s.proposedBy.isEmpty { line += " (제안: \(s.proposedBy))" }
                lines.append(line)
            }
            lines.append("")
        }

        // Decisions
        if !notes.decisions.isEmpty {
            lines.append("## 결정 사항")
            notes.decisions.forEach { lines.append("- \($0)") }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 { return "\(minutes)분 \(seconds)초" }
        return "\(seconds)초"
    }
}

enum NotesError: LocalizedError {
    case noContent
    case appleScriptError(String)

    var errorDescription: String? {
        switch self {
        case .noContent: return "저장할 회의록 내용이 없습니다."
        case .appleScriptError(let msg): return "Apple 메모 저장 실패: \(msg)"
        }
    }
}
