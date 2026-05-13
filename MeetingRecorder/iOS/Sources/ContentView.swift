import SwiftUI

struct ContentView: View {
    @StateObject private var vm = RecordingViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // 배경 그라데이션
                LinearGradient(
                    colors: vm.phase == .recording
                        ? [Color.red.opacity(0.08), Color(.systemBackground)]
                        : [Color.accentColor.opacity(0.06), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: vm.phase)

                VStack(spacing: 0) {
                    Spacer()

                    // ── 상태 영역 ──────────────────────────────
                    stateArea
                        .frame(height: 120)

                    Spacer().frame(height: 32)

                    // ── 타이머 ─────────────────────────────────
                    Text(vm.timerText)
                        .font(.system(size: 72, weight: .ultraLight, design: .monospaced))
                        .contentTransition(.numericText())
                        .foregroundStyle(vm.phase == .idle ? .tertiary : .primary)

                    Spacer().frame(height: 48)

                    // ── 메인 버튼 ──────────────────────────────
                    RecordButton(phase: vm.phase, action: vm.toggleRecording)

                    Spacer().frame(height: 28)

                    // ── 상태 텍스트 ────────────────────────────
                    statusLabel
                        .frame(height: 48)

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("회의록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: HistoryView(storage: vm.storage)) {
                        Image(systemName: "doc.text.below.ecg")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .alert("오류", isPresented: $vm.showError, presenting: vm.errorMessage) { _ in
            Button("확인", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // ── 상태 영역 ──────────────────────────────────
    @ViewBuilder
    private var stateArea: some View {
        switch vm.phase {
        case .idle:
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.quaternary)
                Text("버튼을 눌러 회의를 시작하세요")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .recording:
            WaveformView(level: vm.audioLevel)
                .frame(maxWidth: .infinity)
        case .processing:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.accentColor)
                Text(vm.processingStep)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch vm.phase {
        case .idle:
            Text("녹음 후 자동으로 회의록이 작성됩니다")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        case .recording:
            Label("녹음 중 — 다시 누르면 종료", systemImage: "record.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
        case .processing:
            EmptyView()
        }
    }
}

// ─────────────────────────────────────────────────────
// MARK: - Record Button
// ─────────────────────────────────────────────────────

struct RecordButton: View {
    let phase: RecordingPhase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // 외곽 링 (recording 시)
                if phase == .recording {
                    Circle()
                        .stroke(Color.red.opacity(0.25), lineWidth: 4)
                        .frame(width: 136, height: 136)
                        .scaleEffect(1.15)
                        .opacity(0.7)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: phase
                        )
                }

                Circle()
                    .fill(buttonColor)
                    .frame(width: 120, height: 120)
                    .shadow(color: buttonColor.opacity(0.35), radius: 20, y: 8)

                Image(systemName: buttonIcon)
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .disabled(phase == .processing)
    }

    private var buttonColor: Color {
        switch phase {
        case .idle:       return .accentColor
        case .recording:  return .red
        case .processing: return .orange
        }
    }

    private var buttonIcon: String {
        switch phase {
        case .idle:       return "mic.fill"
        case .recording:  return "stop.fill"
        case .processing: return "ellipsis"
        }
    }
}

// ─────────────────────────────────────────────────────
// MARK: - Waveform
// ─────────────────────────────────────────────────────

struct WaveformView: View {
    let level: Float
    @State private var heights: [CGFloat] = Array(repeating: 4, count: 40)

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(heights.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(index: i))
                        .frame(
                            width: max(2, (geo.size.width - CGFloat(heights.count * 2)) / CGFloat(heights.count)),
                            height: max(4, heights[i])
                        )
                }
            }
        }
        .onChange(of: level) { _, v in
            withAnimation(.easeOut(duration: 0.07)) {
                heights.removeFirst()
                let h = max(4, CGFloat(v) * 80 + CGFloat.random(in: 0...10))
                heights.append(h)
            }
        }
    }

    private func barColor(index: Int) -> Color {
        let mid = heights.count / 2
        let dist = abs(index - mid)
        let ratio = 1.0 - Double(dist) / Double(mid)
        return Color.red.opacity(0.5 + ratio * 0.5)
    }
}
