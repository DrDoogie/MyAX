import SwiftUI
import UniformTypeIdentifiers

// MARK: - Weekly Summary View

struct WeeklySummaryView: View {
    @StateObject private var vm = WeeklySummaryViewModel()
    @State private var showFileList = false

    var body: some View {
        ZStack {
            Color.purple.opacity(0.05).ignoresSafeArea()

            VStack(spacing: 0) {
                switch vm.phase {
                case .idle:
                    idleView
                case .scanning:
                    processingView(label: "볼트 스캔 중...", icon: "magnifyingglass")
                case .summarizing(let n):
                    processingView(label: "\(n)개 노트 AI 요약 중...", icon: "brain")
                case .saving:
                    processingView(label: "볼트에 저장 중...", icon: "arrow.down.doc")
                case .ready, .speaking, .paused:
                    summaryView
                case .error(let msg):
                    errorView(message: msg)
                }
            }
        }
        .navigationTitle("주간 서머리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.isReady || vm.isVoiceActive {
                    Button { showFileList = true } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
        }
        .sheet(isPresented: $showFileList) {
            ScannedFilesSheet(files: vm.scannedFiles)
        }
    }

    // MARK: Idle

    private var idleView: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.purple.opacity(0.5))
                Text("이번 주 Obsidian 노트 요약")
                    .font(.title3.weight(.semibold))
                Text("iCloud 볼트에서 이번 주 마크다운을 가져와\nClaude로 요약하고 음성으로 브리핑합니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button(action: vm.generateSummary) {
                Label("서머리 생성", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: Processing

    private func processingView(label: String, icon: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().controlSize(.large).tint(.purple)
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Summary

    private var summaryView: some View {
        VStack(spacing: 0) {
            voiceControlBar
                .padding(.vertical, 10)
            Divider()
            ScrollView {
                MarkdownTextView(text: vm.summaryMarkdown)
                    .padding()
            }
        }
    }

    private var voiceControlBar: some View {
        HStack(spacing: 12) {
            // Play / Pause
            Button {
                if vm.isSpeaking { vm.pauseSpeaking() } else { vm.speak() }
            } label: {
                Image(systemName: vm.isSpeaking ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse, isActive: vm.isSpeaking)
            }

            // Stop
            if vm.isVoiceActive {
                Button(action: vm.stopSpeaking) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
            }

            // Status label
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.isSpeaking ? "음성 브리핑 중" : vm.isPaused ? "일시 정지" : "재생 준비")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(vm.isSpeaking ? .purple : .secondary)
                    .animation(.easeInOut, value: vm.isSpeaking)
                Text("한국어 음성 합성 (AVSpeechSynthesizer)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Regenerate
            Button(action: vm.generateSummary) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }

            // Share
            ShareLink(item: vm.summaryMarkdown) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: vm.generateSummary) {
                Label("다시 시도", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

// MARK: - Scanned Files Sheet

struct ScannedFilesSheet: View {
    let files: [ObsidianFile]
    @Environment(\.dismiss) private var dismiss

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            List(files) { file in
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name).font(.headline)
                    Text(Self.df.string(from: file.relevantDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("스캔된 파일 (\(files.count)개)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
