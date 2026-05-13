import AVFoundation
import Speech
import SwiftUI

// ─────────────────────────────────────────────
// MARK: - 상태
// ─────────────────────────────────────────────

enum RecordPhase: Equatable { case idle, recording, processing }

// ─────────────────────────────────────────────
// MARK: - ViewModel
// ─────────────────────────────────────────────

@MainActor
final class RecordingVM: ObservableObject {
    @Published var phase: RecordPhase = .idle
    @Published var audioLevel: Float = 0
    @Published var timerText = "00:00"
    @Published var processingStep = ""
    @Published var showError = false
    @Published var errorMsg: String?

    private var recorder: AVAudioRecorder?
    private var recordURL: URL?
    private var ticker: Timer?
    private let session = AVAudioSession.sharedInstance()

    // ── 버튼 탭 ──────────────────────────────
    func toggle() {
        switch phase {
        case .idle:      Task { await start() }
        case .recording: Task { await stop() }
        case .processing: break
        }
    }

    // ─────────────────────────────────────────
    // MARK: - 녹음 시작
    // ─────────────────────────────────────────

    private func start() async {
        // 마이크 권한
        guard await AVAudioApplication.requestRecordPermission() else {
            return fail("마이크 권한이 필요합니다.\n설정 앱 → 개인 정보 보호 → 마이크 → 회의록 앱 허용")
        }
        // 음성 인식 권한
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard ok else {
            return fail("음성 인식 권한이 필요합니다.\n설정 앱 → 개인 정보 보호 → 음성 인식 → 회의록 앱 허용")
        }

        // 오디오 세션
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch { return fail("오디오 세션 오류: \(error.localizedDescription)") }

        // 저장 경로
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
            recordURL = url
        } catch { return fail("녹음 시작 실패: \(error.localizedDescription)") }

        phase = .recording
        timerText = "00:00"

        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder else { return }
                rec.updateMeters()
                self.audioLevel = max(0, (rec.averagePower(forChannel: 0) + 60) / 60)
                let s = Int(rec.currentTime)
                self.timerText = String(format: "%02d:%02d", s / 60, s % 60)
            }
        }
    }

    // ─────────────────────────────────────────
    // MARK: - 녹음 중지 & 처리
    // ─────────────────────────────────────────

    private func stop() async {
        ticker?.invalidate(); ticker = nil
        let duration = Int(recorder?.currentTime ?? 0)
        recorder?.stop()
        try? session.setActive(false)
        guard let url = recordURL else { return }
        recorder = nil
        phase = .processing

        do {
            // 1. 음성 → 텍스트
            processingStep = "🎙️ 음성을 텍스트로 변환 중..."
            let transcript = try await transcribe(url: url)

            // 2. Claude AI 회의록 작성
            processingStep = "✍️ AI가 회의록을 작성 중..."
            let note = try await generateNote(transcript: transcript, date: Date())

            // 3. 로컬 저장
            let saved = SavedMeeting(
                id: UUID(), date: Date(),
                title: note.title, body: note.body,
                seconds: duration
            )
            LocalDB.shared.add(saved)

            processingStep = "✅ 완료!"
            try? await Task.sleep(for: .milliseconds(700))

            // 4. 공유 시트 (메모 앱으로 내보내기)
            await share(text: note.body, title: note.title)

        } catch {
            fail(error.localizedDescription)
        }

        phase = .idle
        timerText = "00:00"
    }

    // ─────────────────────────────────────────
    // MARK: - 음성 인식
    // ─────────────────────────────────────────

    private func transcribe(url: URL) async throws -> String {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")),
              rec.isAvailable else { throw AppErr.noRecognizer }

        let req = SFSpeechURLRecognitionRequest(url: url)
        req.requiresOnDeviceRecognition = true   // 기기 내 처리 (개인정보 보호)
        req.shouldReportPartialResults = false
        req.addsPunctuation = true

        return try await withCheckedThrowingContinuation { cont in
            rec.recognitionTask(with: req) { result, error in
                if let error {
                    // 온디바이스 모델 없으면 네트워크 사용
                    if (error as NSError).code == 203 {
                        Task { [rec] in
                            let req2 = SFSpeechURLRecognitionRequest(url: url)
                            req2.requiresOnDeviceRecognition = false
                            req2.shouldReportPartialResults = false
                            req2.addsPunctuation = true
                            rec.recognitionTask(with: req2) { r2, e2 in
                                if let e2 { cont.resume(throwing: e2); return }
                                guard let r2, r2.isFinal else { return }
                                cont.resume(returning: r2.bestTranscription.formattedString)
                            }
                        }
                    } else { cont.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal else { return }
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    // ─────────────────────────────────────────
    // MARK: - Claude API 회의록 작성
    // ─────────────────────────────────────────

    struct NoteResult { let title: String; let body: String }

    private func generateNote(transcript: String, date: Date) async throws -> NoteResult {
        let key = KeychainStore.load("anthropic_api_key") ?? ""

        // API 키 없으면 원본 텍스트만 저장
        guard !key.isEmpty else { return plain(transcript, date) }

        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateStyle = .full; df.timeStyle = .short
        let dateStr = df.string(from: date)

        let prompt = """
        당신은 회의록 전문 작성가입니다. 한국어로 구조화된 회의록을 작성하세요.

        날짜: \(dateStr)
        녹취록:
        \(transcript)

        아래 마크다운 형식으로만 응답하세요:

        # [회의 제목]

        **날짜**: \(dateStr)

        ## 전체 요약
        (3~5문장 핵심 요약)

        ## 주제별 요약

        ### [주제명]
        - 내용
        - 핵심 포인트

        ## 지시 사항
        - [높음/보통/낮음] 내용 (담당자 / 기한)

        ## 제안 사항
        - 제안 내용 (제안자)

        ## 결정 사항
        - 결정된 내용
        """

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppErr.api((resp as? HTTPURLResponse)?.statusCode ?? -1)
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

    private func plain(_ t: String, _ d: Date) -> NoteResult {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateStyle = .full; df.timeStyle = .short
        let ds = df.string(from: d)
        let title = "\(ds) 회의"
        return NoteResult(title: title, body: "# \(title)\n\n**날짜**: \(ds)\n\n## 녹취 내용\n\n\(t)\n\n---\n※ API 키가 없어 원문만 저장되었습니다. 설정 탭에서 API 키를 입력하세요.")
    }

    // ─────────────────────────────────────────
    // MARK: - 공유 시트
    // ─────────────────────────────────────────

    private func share(text: String, title: String) async {
        await MainActor.run {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            vc.setValue(title, forKey: "subject")
            // iPad: popover 위치 설정
            if let pop = vc.popoverPresentationController {
                pop.sourceView = root.view
                pop.sourceRect = CGRect(x: root.view.bounds.midX,
                                        y: root.view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
            root.present(vc, animated: true)
        }
    }

    private func fail(_ msg: String) {
        errorMsg = msg; showError = true
        phase = .idle; timerText = "00:00"
    }
}

// ─────────────────────────────────────────────
// MARK: - Errors
// ─────────────────────────────────────────────

enum AppErr: LocalizedError {
    case noRecognizer
    case api(Int)
    var errorDescription: String? {
        switch self {
        case .noRecognizer: return "음성 인식을 사용할 수 없습니다. 설정 → 일반 → 언어 및 지역에서 한국어를 확인하세요."
        case .api(let c):   return "AI 서비스 오류 (HTTP \(c)). 설정 탭에서 API 키를 확인하세요."
        }
    }
}
