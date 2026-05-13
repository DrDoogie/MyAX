// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  파일 2: Logic.swift  (새 파일로 추가)
//  왼쪽 파일 목록 아래 + 버튼 → New Swift File
//  이름: Logic  → 이 내용 전체 붙여넣기
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import AVFoundation
import Speech
import Foundation
import Security
import SwiftUI

// ─────────────────────────────────────────────
// 상태
// ─────────────────────────────────────────────

enum RecordPhase: Equatable { case idle, recording, processing }

// ─────────────────────────────────────────────
// 녹음 + AI 처리 ViewModel
// ─────────────────────────────────────────────

@MainActor
final class RecordingVM: ObservableObject {
    @Published var phase: RecordPhase = .idle
    @Published var audioLevel: Float  = 0
    @Published var timer  = "00:00"
    @Published var step   = ""
    @Published var showErr = false
    @Published var errMsg: String?

    private var recorder:  AVAudioRecorder?
    private var recordURL: URL?
    private var ticker:    Timer?
    private let session = AVAudioSession.sharedInstance()

    func toggle() {
        switch phase {
        case .idle:       Task { await startRecording() }
        case .recording:  Task { await stopAndProcess() }
        case .processing: break
        }
    }

    // ── 녹음 시작 ─────────────────────────────

    private func startRecording() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            return fail("마이크 권한이 필요합니다.\n설정 앱 → 개인 정보 보호 → 마이크에서 허용해 주세요.")
        }
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool,Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else {
            return fail("음성 인식 권한이 필요합니다.\n설정 앱 → 개인 정보 보호 → 음성 인식에서 허용해 주세요.")
        }

        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch { return fail("오디오 오류: \(error.localizedDescription)") }

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MRec/Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("rec_\(Date().ISO8601Format()).m4a")
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
        timer = "00:00"
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = self.recorder else { return }
                rec.updateMeters()
                self.audioLevel = max(0, (rec.averagePower(forChannel: 0) + 60) / 60)
                let s = Int(rec.currentTime)
                self.timer = String(format: "%02d:%02d", s / 60, s % 60)
            }
        }
    }

    // ── 녹음 중지 & 처리 ──────────────────────

    private func stopAndProcess() async {
        ticker?.invalidate(); ticker = nil
        let dur = Int(recorder?.currentTime ?? 0)
        recorder?.stop()
        try? session.setActive(false)
        guard let url = recordURL else { return }
        recorder = nil
        phase = .processing

        do {
            step = "🎙️ 음성을 텍스트로 변환 중..."
            let transcript = try await transcribe(url: url)

            step = "✍️ AI가 회의록을 작성 중..."
            let note = try await generateNote(transcript: transcript)

            let saved = SavedMeeting(id: UUID(), date: Date(),
                                     title: note.title, body: note.body, seconds: dur)
            LocalDB.shared.add(saved)

            step = "✅ 완료!"
            try? await Task.sleep(for: .milliseconds(600))
            await shareSheet(text: note.body, title: note.title)

        } catch { fail(error.localizedDescription) }

        phase = .idle
        timer = "00:00"
    }

    // ── 음성 인식 (기기 내 우선) ───────────────

    private func transcribe(url: URL) async throws -> String {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")),
              rec.isAvailable else { throw MRError.noRecognizer }

        return try await withCheckedThrowingContinuation { cont in
            let req = SFSpeechURLRecognitionRequest(url: url)
            req.requiresOnDeviceRecognition = true   // 기기 내 처리 (보안)
            req.shouldReportPartialResults = false
            req.addsPunctuation = true

            rec.recognitionTask(with: req) { result, error in
                if let error {
                    // 온디바이스 모델 없으면 네트워크 사용
                    if (error as NSError).code == 203 {
                        let req2 = SFSpeechURLRecognitionRequest(url: url)
                        req2.requiresOnDeviceRecognition = false
                        req2.shouldReportPartialResults = false
                        req2.addsPunctuation = true
                        rec.recognitionTask(with: req2) { r2, e2 in
                            if let e2 { cont.resume(throwing: e2); return }
                            guard let r2, r2.isFinal else { return }
                            cont.resume(returning: r2.bestTranscription.formattedString)
                        }
                    } else { cont.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal else { return }
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    // ── Claude AI 회의록 작성 ─────────────────

    private struct NoteResult { let title: String; let body: String }

    private func generateNote(transcript: String) async throws -> NoteResult {
        let apiKey = KeychainStore.load("anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else { return plainNote(transcript) }

        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateStyle = .full; df.timeStyle = .short
        let dateStr = df.string(from: Date())

        let prompt = """
        당신은 한국어 회의록 전문 작성가입니다.

        날짜: \(dateStr)
        녹취록:
        \(transcript)

        아래 형식의 마크다운으로만 응답하세요:

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
        - 제안 내용

        ## 결정 사항
        - 결정 내용
        """

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,      forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw MRError.api((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct R: Decodable {
            struct C: Decodable { let text: String }
            let content: [C]
        }
        let body = try JSONDecoder().decode(R.self, from: data).content.first?.text ?? ""
        let title = body.components(separatedBy: "\n")
            .first { $0.hasPrefix("# ") }
            .map   { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            ?? "\(dateStr) 회의"
        return NoteResult(title: title, body: body)
    }

    private func plainNote(_ t: String) -> NoteResult {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR"); df.dateStyle = .full; df.timeStyle = .short
        let ds = df.string(from: Date())
        let title = "\(ds) 회의"
        return NoteResult(title: title,
            body: "# \(title)\n\n**날짜**: \(ds)\n\n## 녹취 내용\n\n\(t)\n\n---\n※ API 키 미설정으로 원문만 저장되었습니다.\n설정 탭에서 API 키를 입력하면 AI 요약이 활성화됩니다.")
    }

    // ── 공유 시트 ─────────────────────────────

    private func shareSheet(text: String, title: String) async {
        await MainActor.run {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            vc.setValue(title, forKey: "subject")
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
        errMsg = msg; showErr = true; phase = .idle; timer = "00:00"
    }
}

// ─────────────────────────────────────────────
// 로컬 저장 (JSON)
// ─────────────────────────────────────────────

struct SavedMeeting: Identifiable, Codable {
    let id: UUID
    let date: Date
    let title: String
    let body: String
    let seconds: Int
}

@MainActor
final class LocalDB: ObservableObject {
    static let shared = LocalDB()
    @Published private(set) var meetings: [SavedMeeting] = []

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MRec", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("meetings.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL) {
            meetings = (try? JSONDecoder().decode([SavedMeeting].self, from: data)) ?? []
        }
    }

    func add(_ m: SavedMeeting) {
        meetings.insert(m, at: 0)
        try? JSONEncoder().encode(meetings).write(to: fileURL, options: .atomic)
    }

    func delete(at offsets: IndexSet) {
        meetings.remove(atOffsets: offsets)
        try? JSONEncoder().encode(meetings).write(to: fileURL, options: .atomic)
    }
}

// ─────────────────────────────────────────────
// Keychain
// ─────────────────────────────────────────────

enum KeychainStore {
    static func save(_ key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key, kSecValueData as String: data]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load(_ key: String) -> String? {
        let q: [String:Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess,
              let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

// ─────────────────────────────────────────────
// 오류
// ─────────────────────────────────────────────

enum MRError: LocalizedError {
    case noRecognizer
    case api(Int)
    var errorDescription: String? {
        switch self {
        case .noRecognizer: return "음성 인식을 사용할 수 없습니다.\n설정 → 일반 → 언어 및 지역에서 한국어가 추가되어 있는지 확인하세요."
        case .api(let c):   return "AI 오류 (HTTP \(c)).\n설정 탭에서 API 키를 확인하세요."
        }
    }
}
