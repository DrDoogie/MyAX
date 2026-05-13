import AVFoundation
import Speech
import Foundation
import SwiftUI

// ─────────────────────────────────────────────────────
// MARK: - Phase
// ─────────────────────────────────────────────────────

enum RecordingPhase: Equatable {
    case idle, recording, processing
}

// ─────────────────────────────────────────────────────
// MARK: - Storage
// ─────────────────────────────────────────────────────

final class LocalStorage: ObservableObject {
    static let shared = LocalStorage()
    @Published var meetings: [SavedMeeting] = []

    private let url: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecorder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("meetings.json")
    }()

    private init() { load() }

    func save(_ meeting: SavedMeeting) {
        meetings.insert(meeting, at: 0)
        try? JSONEncoder().encode(meetings).write(to: url, options: .atomic)
    }

    func delete(at offsets: IndexSet) {
        meetings.remove(atOffsets: offsets)
        try? JSONEncoder().encode(meetings).write(to: url, options: .atomic)
    }

    private func load() {
        meetings = (try? JSONDecoder().decode([SavedMeeting].self, from: Data(contentsOf: url))) ?? []
    }
}

struct SavedMeeting: Identifiable, Codable {
    let id: UUID
    let date: Date
    let title: String
    let markdownBody: String
    let durationSeconds: Int
}

// ─────────────────────────────────────────────────────
// MARK: - ViewModel
// ─────────────────────────────────────────────────────

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var phase: RecordingPhase = .idle
    @Published var audioLevel: Float = 0
    @Published var timerText = "00:00"
    @Published var processingStep = ""
    @Published var showError = false
    @Published var errorMessage: String?

    let storage = LocalStorage.shared

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var ticker: Timer?
    private var session = AVAudioSession.sharedInstance()

    // ── Toggle ────────────────────────────────────────
    func toggleRecording() {
        switch phase {
        case .idle:       Task { await startRecording() }
        case .recording:  Task { await stopAndProcess() }
        case .processing: break
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: - Start Recording
    // ─────────────────────────────────────────────────

    private func startRecording() async {
        // Microphone permission
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else {
            return fail("마이크 권한이 필요합니다.\n설정 → 개인 정보 보호 → 마이크에서 허용하세요.")
        }

        // Speech permission
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else {
            return fail("음성 인식 권한이 필요합니다.\n설정 → 개인 정보 보호 → 음성 인식에서 허용하세요.")
        }

        // Audio session
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return fail("오디오 세션 설정 실패: \(error.localizedDescription)")
        }

        // Recorder
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecorder/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("mtg_\(Date().ISO8601Format()).m4a")
        do {
            let rec = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            rec.isMeteringEnabled = true
            rec.record()
            recorder = rec
            recordingURL = url
        } catch {
            return fail("녹음 시작 실패: \(error.localizedDescription)")
        }

        phase = .recording
        timerText = "00:00"

        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder else { return }
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)
                self.audioLevel = max(0, (power + 60) / 60)
                let secs = Int(rec.currentTime)
                self.timerText = String(format: "%02d:%02d", secs / 60, secs % 60)
            }
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: - Stop & Process
    // ─────────────────────────────────────────────────

    private func stopAndProcess() async {
        ticker?.invalidate(); ticker = nil
        let duration = Int(recorder?.currentTime ?? 0)
        recorder?.stop()
        try? session.setActive(false)
        guard let url = recordingURL else { return }
        recorder = nil
        phase = .processing

        do {
            processingStep = "음성을 텍스트로 변환 중..."
            let transcript = try await transcribe(url: url)

            processingStep = "회의록 AI 작성 중..."
            let note = try await generateNote(transcript: transcript, date: Date())

            // Save locally
            let saved = SavedMeeting(
                id: UUID(),
                date: Date(),
                title: note.title,
                markdownBody: note.body,
                durationSeconds: duration
            )
            storage.save(saved)

            // Share sheet (iOS: no AppleScript — use UIActivityViewController)
            processingStep = "저장 완료!"
            try? await Task.sleep(for: .milliseconds(600))

            // Open share sheet on main thread
            await shareToNotes(text: note.body, title: note.title)
        } catch {
            fail(error.localizedDescription)
        }

        phase = .idle
        timerText = "00:00"
    }

    // ─────────────────────────────────────────────────
    // MARK: - Transcription
    // ─────────────────────────────────────────────────

    private func transcribe(url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")),
              recognizer.isAvailable else {
            throw AppError.transcriptionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    // On-device 모델 없으면 네트워크 폴백
                    if (error as NSError).code == 203 {
                        Task {
                            do {
                                let t = try await self.transcribeFallback(url: url)
                                cont.resume(returning: t)
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
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.requiresOnDeviceRecognition = false
        req.shouldReportPartialResults = false
        req.addsPunctuation = true
        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: req) { result, error in
                if let error { cont.resume(throwing: error); return }
                guard let r = result, r.isFinal else { return }
                cont.resume(returning: r.bestTranscription.formattedString)
            }
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: - Claude API
    // ─────────────────────────────────────────────────

    struct NoteResult { let title: String; let body: String }

    private func generateNote(transcript: String, date: Date) async throws -> NoteResult {
        let apiKey = KeychainHelper.load(key: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else { return fallbackNote(transcript, date) }

        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateStyle = .full; df.timeStyle = .short
        let dateStr = df.string(from: date)

        let prompt = """
        당신은 회의록 전문 작성가입니다. 아래 녹취록을 분석해 한국어 회의록을 작성하세요.

        날짜: \(dateStr)
        녹취록:
        \(transcript)

        다음 마크다운 형식으로 작성하세요:

        # [회의 제목]

        **날짜**: \(dateStr)

        ## 전체 요약
        (3-5문장)

        ## 주제별 요약

        ### [주제1]
        - 핵심 내용
        - 핵심 포인트

        ## 지시 사항
        - [높음/보통/낮음] 내용 (담당자 / 기한)

        ## 제안 사항
        - 제안 내용

        ## 결정 사항
        - 결정 내용

        마크다운 전체를 반환하세요.
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
        let title = body.components(separatedBy: "\n")
            .first { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            ?? "\(dateStr) 회의"
        return NoteResult(title: title, body: body)
    }

    private func fallbackNote(_ transcript: String, _ date: Date) -> NoteResult {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateStyle = .full; df.timeStyle = .short
        let dateStr = df.string(from: date)
        let title = "\(dateStr) 회의"
        let body = "# \(title)\n\n**날짜**: \(dateStr)\n\n## 녹취 내용\n\n\(transcript)\n\n---\n※ API 키 미설정으로 AI 요약 없이 저장되었습니다."
        return NoteResult(title: title, body: body)
    }

    // ─────────────────────────────────────────────────
    // MARK: - Share to Notes (iOS)
    // ─────────────────────────────────────────────────

    private func shareToNotes(text: String, title: String) async {
        // iOS에서는 UIActivityViewController를 통해 메모 앱으로 내보냄
        await MainActor.run {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else { return }

            let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            activityVC.setValue(title, forKey: "subject")
            rootVC.present(activityVC, animated: true)
        }
    }

    // ─────────────────────────────────────────────────
    private func fail(_ msg: String) {
        errorMessage = msg
        showError = true
        phase = .idle
        timerText = "00:00"
    }
}

// ─────────────────────────────────────────────────────
// MARK: - Keychain
// ─────────────────────────────────────────────────────

enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrAccount as String: key,
                                 kSecValueData as String: data]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrAccount as String: key,
                                 kSecReturnData as String: true,
                                 kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum AppError: LocalizedError {
    case transcriptionUnavailable
    case apiError(Int)
    var errorDescription: String? {
        switch self {
        case .transcriptionUnavailable: return "음성 인식을 사용할 수 없습니다. 설정에서 한국어 음성 인식을 활성화하세요."
        case .apiError(let c): return "Claude API 오류 (HTTP \(c)). 설정에서 API 키를 확인하세요."
        }
    }
}
