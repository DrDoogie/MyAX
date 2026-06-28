import Foundation
import AVFoundation

// MARK: - ViewModel

@MainActor
final class WeeklySummaryViewModel: NSObject, ObservableObject {

    // MARK: Phase

    enum Phase {
        case idle
        case scanning
        case summarizing(Int)
        case saving
        case ready
        case speaking
        case paused
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var summaryMarkdown = ""
    @Published var savedURL: URL?
    @Published var scannedFiles: [ObsidianFile] = []

    let vaultService = ObsidianVaultService()
    private let synthesizer = AVSpeechSynthesizer()

    private var apiKey: String { KeychainHelper.load(key: "anthropic_api_key") ?? "" }

    // Convenience phase checks used by the view
    var isReady:    Bool { if case .ready   = phase { return true }; return false }
    var isSpeaking: Bool { if case .speaking = phase { return true }; return false }
    var isPaused:   Bool { if case .paused  = phase { return true }; return false }
    var isVoiceActive: Bool { isSpeaking || isPaused }
    var errorMessage: String? { if case .error(let m) = phase { return m }; return nil }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Generate

    func generateSummary() {
        Task { await runGeneration() }
    }

    private func runGeneration() async {
        phase = .scanning

        do {
            let files = try vaultService.scanThisWeek()
            guard !files.isEmpty else {
                phase = .error(ObsidianError.noFilesFound.localizedDescription ?? "파일 없음")
                return
            }
            scannedFiles = files
            phase = .summarizing(files.count)

            let markdown = try await callClaude(files: files)
            phase = .saving

            summaryMarkdown = markdown
            savedURL = try vaultService.saveSummary(markdown: markdown)
            phase = .ready

        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Claude API

    private func callClaude(files: [ObsidianFile]) async throws -> String {
        guard !apiKey.isEmpty else { return buildFallbackSummary(files: files) }

        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy년 M월 d일"

        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let range = "\(df.string(from: weekStart)) ~ \(df.string(from: Date()))"

        // Limit to 20 files, 2 000 chars each to stay within context limits
        let filesBlock = files.prefix(20).enumerated().map { i, f in
            "### \(i + 1). \(f.name)  (\(df.string(from: f.relevantDate)))\n\n\(f.content.prefix(2000))"
        }.joined(separator: "\n\n---\n\n")

        let prompt = """
        당신은 옵시디언 노트 분석 전문가입니다.
        이번 주(\(range))에 작성/수정된 \(files.count)개의 노트를 분석하여 주간 서머리를 작성해주세요.

        ## 이번 주 노트

        \(filesBlock)

        ## 작성 형식 (마크다운, 한국어)

        # 주간 서머리 — \(range)

        ## 이번 주 한눈에 보기
        (전체 활동 3~5문장 요약)

        ## 주요 주제 & 인사이트
        ### [주제명]
        - 핵심 내용
        - 관련 노트: [[노트명]]

        ## 완료한 일
        - 항목

        ## 다음 주 액션 아이템
        - [ ] 할 일

        ## 회고
        (배운 점, 개선할 점)

        ---
        *자동 생성: \(df.string(from: Date()))*
        """

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppError.apiError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct R: Decodable {
            struct C: Decodable { let text: String }
            let content: [C]
        }
        return try JSONDecoder().decode(R.self, from: data).content.first?.text ?? ""
    }

    private func buildFallbackSummary(files: [ObsidianFile]) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy년 M월 d일"
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let range = "\(df.string(from: weekStart)) ~ \(df.string(from: Date()))"

        var md = "# 주간 서머리 — \(range)\n\n"
        md += "> API 키 미설정 — 목록만 표시됩니다. 설정에서 Anthropic API 키를 입력하면 AI 요약이 활성화됩니다.\n\n"
        md += "## 이번 주 노트 (\(files.count)개)\n\n"
        for f in files {
            md += "- [[\(f.name)]] — \(df.string(from: f.relevantDate))\n"
        }
        return md
    }

    // MARK: - Voice Briefing

    func speak() {
        guard isReady || isPaused else { return }

        if isPaused {
            synthesizer.continueSpeaking()
            phase = .speaking
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }

        let utterance = AVSpeechUtterance(string: plainText(from: summaryMarkdown))
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
        phase = .speaking
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
        phase = .paused
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        phase = .ready
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Strips markdown syntax so TTS reads naturally
    private func plainText(from markdown: String) -> String {
        markdown.components(separatedBy: "\n").compactMap { line -> String? in
            var s = line
            while s.hasPrefix("#") { s = String(s.dropFirst()) }
            s = s.replacingOccurrences(of: "- [ ] ", with: "할 일: ")
            s = s.replacingOccurrences(of: "- [x] ", with: "완료: ")
            s = s.replacingOccurrences(of: "- [X] ", with: "완료: ")
            if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
            s = s.replacingOccurrences(of: "**", with: "")
            s = s.replacingOccurrences(of: "*", with: "")
            // Unwrap [[wikilinks]]
            s = s.replacingOccurrences(of: "\\[\\[([^\\]]+)\\]\\]", with: "$1", options: .regularExpression)
            let t = s.trimmingCharacters(in: .whitespaces)
            if t == "---" || t.hasPrefix(">") || t.hasPrefix("*자동 생성") { return nil }
            return t.isEmpty ? nil : t
        }.joined(separator: ". ")
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension WeeklySummaryViewModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.phase = .ready
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.phase = .ready
        }
    }
}
