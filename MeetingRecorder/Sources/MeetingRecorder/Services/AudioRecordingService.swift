import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioRecordingService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private(set) var currentRecordingURL: URL?

    // All recordings stored locally only — never uploaded
    private let recordingsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MeetingRecorder/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func requestPermission() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #elseif os(macOS)
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }

    func startRecording() throws -> URL {
        let filename = "meeting_\(ISO8601DateFormatter().string(from: Date())).m4a"
        let url = recordingsDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()

        currentRecordingURL = url
        isRecording = true
        startTime = Date()
        startTimer()
        return url
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let recorder = audioRecorder, let url = currentRecordingURL else { return nil }
        recorder.stop()
        let duration = recorder.currentTime
        stopTimer()
        isRecording = false
        return (url, duration)
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            self.recordingDuration = recorder.currentTime
            recorder.updateMeters()
            // Normalize power level to 0-1 range
            let power = recorder.averagePower(forChannel: 0)
            self.audioLevel = max(0, (power + 60) / 60)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        recordingDuration = 0
        audioLevel = 0
    }
}

extension AudioRecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                self.isRecording = false
                self.stopTimer()
            }
        }
    }
}
