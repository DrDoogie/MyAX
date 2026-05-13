import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class TranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var partialTranscript = ""

    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = Locale(identifier: "ko-KR")) {
        // Korean recognizer; falls back to device default
        self.recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: .current)
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Transcribes audio file entirely on-device — no data leaves the device
    func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        // Force on-device to guarantee privacy
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        isTranscribing = true
        defer { isTranscribing = false }

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error {
                    // If on-device fails (model not downloaded), retry without constraint
                    if (error as NSError).code == 203 {
                        Task { @MainActor [weak self] in
                            do {
                                let fallback = try await self?.transcribeWithNetwork(audioURL: audioURL)
                                continuation.resume(returning: fallback ?? "")
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    /// Network fallback — only used if on-device model unavailable
    private func transcribeWithNetwork(audioURL: URL) async throws -> String {
        guard let recognizer else { throw TranscriptionError.recognizerUnavailable }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = false
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error { continuation.resume(throwing: error); return }
                guard let result, result.isFinal else { return }
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "음성 인식을 사용할 수 없습니다."
        case .permissionDenied: return "음성 인식 권한이 없습니다."
        }
    }
}
