import SwiftUI
import AVFoundation

@MainActor
final class MeetingViewModel: ObservableObject {
    @Published var currentMeeting: Meeting?
    @Published var isProcessing = false
    @Published var processingStep = ""
    @Published var errorMessage: String?
    @Published var showError = false

    let recorder = AudioRecordingService()
    let transcriber = TranscriptionService()
    let claude = ClaudeAPIService()
    let storage = StorageService.shared

    func startMeeting(title: String) async {
        let permitted = await recorder.requestPermission()
        let speechPermitted = await transcriber.requestPermission()
        guard permitted, speechPermitted else {
            errorMessage = "마이크 및 음성 인식 권한이 필요합니다."
            showError = true
            return
        }

        var meeting = Meeting(title: title.isEmpty ? autoTitle() : title)
        do {
            let url = try recorder.startRecording()
            meeting.audioFileURL = url
            meeting.status = .recording
            currentMeeting = meeting
            storage.save(meeting)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func stopMeeting() async {
        guard var meeting = currentMeeting else { return }
        guard let result = recorder.stopRecording() else { return }
        meeting.duration = result.duration
        meeting.status = .processing
        currentMeeting = meeting
        storage.save(meeting)

        isProcessing = true
        do {
            processingStep = "음성을 텍스트로 변환 중..."
            meeting.transcript = try await transcriber.transcribe(audioURL: result.url)

            processingStep = "회의록 작성 중..."
            meeting.notes = try await claude.structureMeetingNotes(
                transcript: meeting.transcript,
                title: meeting.title
            )

            // Auto-categorize from topics
            meeting.categories = Array(Set(meeting.notes?.topicSummaries.compactMap {
                $0.category.isEmpty ? nil : $0.category
            } ?? []))

            meeting.status = .completed
            currentMeeting = meeting
            storage.save(meeting)

            // Save to Apple Notes
            processingStep = "Apple 메모에 저장 중..."
            #if os(macOS)
            try? await AppleNotesService.save(meeting)
            #endif
        } catch {
            meeting.status = .failed
            storage.save(meeting)
            errorMessage = error.localizedDescription
            showError = true
        }
        isProcessing = false
        processingStep = ""
    }

    private func autoTitle() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 회의"
        return f.string(from: Date())
    }
}

// MARK: - Recording View

struct RecordingView: View {
    @StateObject private var vm = MeetingViewModel()
    @State private var meetingTitle = ""
    @State private var showTitleInput = false
    @State private var pendingStart = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Status text
                statusLabel

                // Waveform / idle indicator
                if vm.recorder.isRecording {
                    WaveformView(level: vm.recorder.audioLevel)
                        .frame(height: 60)
                        .padding(.horizontal, 40)
                }

                // Timer
                if vm.recorder.isRecording {
                    Text(formatDuration(vm.recorder.recordingDuration))
                        .font(.system(.title2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Record Button
                recordButton

                if vm.isProcessing {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(vm.processingStep)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .alert("오류", isPresented: $vm.showError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $showTitleInput) {
            TitleInputSheet(title: $meetingTitle) {
                showTitleInput = false
                Task { await vm.startMeeting(title: meetingTitle) }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if vm.isProcessing {
            Label("처리 중...", systemImage: "waveform.and.sparkles")
                .font(.headline)
                .foregroundStyle(.orange)
        } else if vm.recorder.isRecording {
            Label("녹음 중", systemImage: "record.circle.fill")
                .font(.headline)
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
        } else {
            Text("회의 녹음을 시작하려면\n버튼을 누르세요")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var recordButton: some View {
        Button {
            if vm.recorder.isRecording {
                Task { await vm.stopMeeting() }
            } else {
                showTitleInput = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(vm.recorder.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 88, height: 88)
                    .shadow(radius: vm.recorder.isRecording ? 12 : 6)

                Image(systemName: vm.recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
        }
        .disabled(vm.isProcessing)
        .scaleEffect(vm.recorder.isRecording ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                   value: vm.recorder.isRecording)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let level: Float
    @State private var bars: [CGFloat] = Array(repeating: 0.1, count: 30)

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: max(2, (geo.size.width - CGFloat(bars.count) * 3) / CGFloat(bars.count)),
                               height: bars[i] * geo.size.height)
                }
            }
        }
        .onChange(of: level) { _, newLevel in
            withAnimation(.easeOut(duration: 0.1)) {
                bars.removeFirst()
                bars.append(CGFloat(newLevel) * 0.9 + CGFloat.random(in: 0...0.1))
            }
        }
    }
}

// MARK: - Title Input Sheet

struct TitleInputSheet: View {
    @Binding var title: String
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("예: 주간 팀 미팅", text: $title)
                        .font(.body)
                } header: {
                    Text("회의 제목 (선택사항)")
                } footer: {
                    Text("비워두면 날짜로 자동 생성됩니다.")
                }
            }
            .navigationTitle("새 회의")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onConfirm() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("녹음 시작") { onConfirm() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}
