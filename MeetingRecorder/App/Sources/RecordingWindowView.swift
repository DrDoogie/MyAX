import SwiftUI

struct RecordingWindowView: View {
    @StateObject private var vm = RecordingViewModel()

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // ── 상태 아이콘 ──
                stateIcon
                    .frame(height: 60)

                // ── 타이머 ──
                Text(vm.timerText)
                    .font(.system(size: 44, weight: .thin, design: .monospaced))
                    .foregroundStyle(vm.phase == .idle ? .secondary : .primary)
                    .contentTransition(.numericText())

                // ── 메인 버튼 ──
                Button(action: vm.toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(buttonColor)
                            .frame(width: 100, height: 100)
                            .shadow(color: buttonColor.opacity(0.4), radius: 16, y: 6)

                        Image(systemName: buttonIcon)
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.phase == .processing)
                .scaleEffect(vm.phase == .recording ? 1.06 : 1.0)
                .animation(
                    vm.phase == .recording
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 0.2),
                    value: vm.phase
                )

                // ── 상태 텍스트 ──
                statusText
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 40)
            }
            .padding(32)
        }
        .alert("오류", isPresented: $vm.showError, presenting: vm.errorMessage) { _ in
            Button("확인", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // ─────────────────────────────────────
    private var buttonColor: Color {
        switch vm.phase {
        case .idle:       return .accentColor
        case .recording:  return .red
        case .processing: return .orange
        }
    }

    private var buttonIcon: String {
        switch vm.phase {
        case .idle:       return "mic.fill"
        case .recording:  return "stop.fill"
        case .processing: return "ellipsis"
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch vm.phase {
        case .idle:
            Image(systemName: "waveform.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
        case .recording:
            WaveformBars(level: vm.audioLevel)
        case .processing:
            VStack(spacing: 6) {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch vm.phase {
        case .idle:
            Text("버튼을 눌러 회의 녹음을 시작하세요")
        case .recording:
            Text("녹음 중 — 다시 누르면 종료됩니다")
                .foregroundStyle(.red)
        case .processing:
            Text(vm.processingStep)
        }
    }
}

// ── 파형 막대 ──────────────────────────────────
struct WaveformBars: View {
    let level: Float
    @State private var heights: [CGFloat] = Array(repeating: 4, count: 24)

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 5, height: heights[i])
            }
        }
        .onChange(of: level) { _, v in
            withAnimation(.easeOut(duration: 0.08)) {
                heights.removeFirst()
                heights.append(max(4, CGFloat(v) * 50 + CGFloat.random(in: 0...8)))
            }
        }
    }
}

// ── macOS 배경 블러 ────────────────────────────
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
