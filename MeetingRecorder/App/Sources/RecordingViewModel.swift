import AVFoundation
import Speech
import Foundation
import SwiftUI
import AppKit

// ─────────────────────────────────────────────
// MARK: - Phase
// ─────────────────────────────────────────────

enum RecordingPhase: Equatable {
    case idle, recording, processing
}

// ─────────────────────────────────────────────
// MARK: - ViewModel
// ─────────────────────────────────────────────

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var phase: RecordingPhase = .idle
    @Published var audioLevel: Float = 0
    @Published var timerText = "00:00"
    @Published var processingStep = ""
    @Published var showError = false
    @Published var errorMessage: String?

    // Private state
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var elapsedSeconds = 0
    private var ticker: Timer?

    // ── Button tap ───────────────────────────────
    func toggleRecording() {
        switch phase {
        case .idle:       Task { await startRecording() }
        case .recording:  Task { await stopAndProcess() }
        case .processing: break
        }
    }

    // ── Start ────────────────────────────────────
    private func startRecording() async {
        // Permissions
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        guard micOK else { return fail("마이크 권한이 필요합니다. 시스템 환경설정 → 개인 정보 보호에서 허용하세요.") }

        let speechAuth = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechAuth else { return fail("음성 인식 권한이 필요합니다.") }

        // Setup recorder
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecorder/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("meeting_\(Date().ISO8601Format()).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            rec.record()
            recorder = rec
            recordingURL = url
        } catch {
            return fail("녹음 시작 실패: \(error.localizedDescription)")
        }

        phase = .recording
        elapsedSeconds = 0
        timerText = "00:00"

        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder else { return }
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)
                self.audioLevel = max(0, (power + 60) / 60)

                let secs = Int(rec.currentTime)
                if secs != self.elapsedSeconds {
                    self.elapsedSeconds = secs
                    self.timerText = String(format: "%02d:%02d", secs / 60, secs % 60)
                }
            }
        }
    }

    // ── Stop & Process ───────────────────────────
    private func stopAndProcess() async {
        ticker?.invalidate(); ticker = nil
        recorder?.stop()
        guard let url = recordingURL else { return }
        recorder = nil
        phase = .processing

        do {
            // 1. Transcribe (on-device preferred)
            processingStep = "음성 → 텍스트 변환 중..."
            let transcript = try await transcribe(url: url)

            // 2. Generate notes via Claude
            processingStep = "회의록 작성 중..."
            let notes = try await generateNotes(transcript: transcript, date: Date())

            // 3. Save to Apple Notes
            processingStep = "Apple 메모에 저장 중..."
            saveToNotes(title: notes.title, body: notes.body)

            // 4. Also save locally
            saveLocalMarkdown(filename: notes.title, body: notes.body)

            processingStep = "완료!"
            try? await Task.sleep(for: .milliseconds(800))
        } catch {
            fail(error.localizedDescription)
        }

        phase = .idle
        timerText = "00:00"
    }

    // ─────────────────────────────────────────────
    // MARK: - Transcription
    // ─────────────────────────────────────────────

    private func transcribe(url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")),
              recognizer.isAvailable else {
            throw AppError.transcriptionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true   // 기기 내에서만 처리
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    // On-device 모델 미설치시 네트워크 폴백
                    if (error as NSError).code == 203 {
                        Task { [weak self] in
                            do {
                                let text = try await self?.transcribeFallback(url: url) ?? ""
                                cont.resume(returning: text)
                            } catch { cont.resume(throwing: error) }
                        }
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let r = result, r.isFinal else { return }
                cont.resume(returning: r.bestTranscription.formattedString)
            }
        }
    }

    private func transcribeFallback(url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")) else {
            throw AppError.transcriptionUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = false
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error { cont.resume(throwing: error); return }
                guard let r = result, r.isFinal else { return }
                cont.resume(returning: r.bestTranscription.formattedString)
            }
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Claude API
    // ─────────────────────────────────────────────

    private struct NoteResult {
        let title: String
        let body: String
    }

    private func generateNotes(transcript: String, date: Date) async throws -> NoteResult {
        let apiKey = KeychainHelper.load(key: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else {
            // API 키 없으면 간단한 날짜+내용 형식으로 저장
            return fallbackNote(transcript: transcript, date: date)
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateStyle = .full; df.timeStyle = .short
        let dateStr = df.string(from: date)

        let prompt = """
        당신은 회의록 전문 작성가입니다. 아래 녹취록을 분석해 회의록을 작성하세요.

        날짜: \(dateStr)
        녹취록:
        \(transcript)

        다음 마크다운 형식으로 작성하세요:

        # [회의 제목 (내용 기반으로 자동 생성)]

        **날짜**: \(dateStr)

        ## 전체 요약
        (3-5문장 요약)

        ## 주제별 요약

        ### [주제1]
        - 핵심 내용
        - 핵심 포인트

        ### [주제2]
        ...

        ## 지시 사항
        - [높음/보통/낮음] 내용 (담당자 / 기한)

        ## 제안 사항
        - 제안 내용 (제안자)

        ## 결정 사항
        - 결정된 내용

        ---
        회의록은 한국어로 작성하고, 첫 줄 # 제목만 반환하는 것이 아니라 전체 마크다운을 반환하세요.
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
        let body = try JSONDecoder().decode(R.self, from: data).content.first?.text ?? ""
        let title = extractTitle(from: body, fallback: dateStr + " 회의")
        return NoteResult(title: title, body: body)
    }

    private func fallbackNote(transcript: String, date: Date) -> NoteResult {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateStyle = .full; df.timeStyle = .short
        let dateStr = df.string(from: date)
        let title = "\(dateStr) 회의"
        let body = """
        # \(title)

        **날짜**: \(dateStr)

        ## 녹취 내용

        \(transcript)

        ---
        ※ Anthropic API 키 미설정으로 AI 요약 없이 저장되었습니다.
        설정 방법: 터미널에서 아래 명령 실행
        `defaults write com.myax.MeetingRecorder apiKey "sk-ant-..."`
        """
        return NoteResult(title: title, body: body)
    }

    private func extractTitle(from markdown: String, fallback: String) -> String {
        let line = markdown.components(separatedBy: "\n").first { $0.hasPrefix("# ") }
        return line.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) } ?? fallback
    }

    // ─────────────────────────────────────────────
    // MARK: - Apple Notes (AppleScript)
    // ─────────────────────────────────────────────

    private func saveToNotes(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\"", with: "'")
        let safeBody = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
        tell application "Notes"
            if not (exists folder "회의록") then
                make new folder with properties {name:"회의록"}
            end if
            make new note at folder "회의록" with properties {name:"\(safeTitle)", body:"\(safeBody)"}
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    // ─────────────────────────────────────────────
    // MARK: - Local Markdown Backup
    // ─────────────────────────────────────────────

    private func saveLocalMarkdown(filename: String, body: String) {
        let safe = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecorder/Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(safe).md")
        try? body.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // ─────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────

    private func fail(_ message: String) {
        errorMessage = message
        showError = true
        phase = .idle
        timerText = "00:00"
    }
}

// ─────────────────────────────────────────────
// MARK: - Keychain
// ─────────────────────────────────────────────

enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// ─────────────────────────────────────────────
// MARK: - Errors
// ─────────────────────────────────────────────

enum AppError: LocalizedError {
    case transcriptionUnavailable
    case apiError(Int)

    var errorDescription: String? {
        switch self {
        case .transcriptionUnavailable:
            return "음성 인식을 사용할 수 없습니다. macOS 설정에서 한국어 음성 인식을 활성화하세요."
        case .apiError(let code):
            return "Claude API 오류 (HTTP \(code)). API 키를 확인하세요."
        }
    }
}
