import SwiftUI
import AVFoundation
import Speech

// ─────────────────────────────────────────────
// MARK: - 녹음 화면
// ─────────────────────────────────────────────

struct RecordingScreen: View {
    @StateObject private var vm = RecordingVM()

    var body: some View {
        ZStack {
            // 배경 그라데이션
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: vm.phase)

            VStack(spacing: 0) {
                Spacer()

                // ── 파형 / 아이콘 ─────────────────
                Group {
                    switch vm.phase {
                    case .idle:
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.3))

                    case .recording:
                        WaveformBars(level: vm.audioLevel)
                            .frame(height: 80)
                            .padding(.horizontal, 40)

                    case .processing:
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                            Text(vm.processingStep)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(height: 120)

                Spacer().frame(height: 32)

                // ── 타이머 ────────────────────────
                Text(vm.timerText)
                    .font(.system(size: 80, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .shadow(radius: 4)

                Spacer().frame(height: 50)

                // ── 버튼 ──────────────────────────
                Button(action: vm.toggle) {
                    ZStack {
                        // 외곽 펄스 링 (녹음 중)
                        if vm.phase == .recording {
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 3)
                                .frame(width: 150, height: 150)
                                .scaleEffect(1.2)
                                .animation(
                                    .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                    value: vm.phase
                                )
                        }

                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 130, height: 130)
                            .overlay(
                                Circle().stroke(.white.opacity(0.5), lineWidth: 2)
                            )

                        Image(systemName: buttonIcon)
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.phase == .processing)

                Spacer().frame(height: 30)

                // ── 안내 텍스트 ───────────────────
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .navigationTitle("회의 녹음")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("오류", isPresented: $vm.showError, presenting: vm.errorMsg) { _ in
            Button("확인", role: .cancel) {}
        } message: { msg in Text(msg) }
    }

    private var backgroundColors: [Color] {
        switch vm.phase {
        case .idle:       return [Color(hex: "#1a1a2e"), Color(hex: "#16213e")]
        case .recording:  return [Color(hex: "#7f0000"), Color(hex: "#200122")]
        case .processing: return [Color(hex: "#0f3460"), Color(hex: "#16213e")]
        }
    }

    private var buttonIcon: String {
        switch vm.phase {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .processing: return "hourglass"
        }
    }

    private var statusText: String {
        switch vm.phase {
        case .idle: return "버튼을 눌러 회의 녹음을 시작하세요"
        case .recording: return "녹음 중 — 다시 누르면 종료됩니다"
        case .processing: return ""
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - 파형 애니메이션
// ─────────────────────────────────────────────

struct WaveformBars: View {
    let level: Float
    @State private var bars: [CGFloat] = Array(repeating: 4, count: 36)

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(bars.indices, id: \.self) { i in
                    let ratio = 1.0 - abs(Double(i) - Double(bars.count)/2) / (Double(bars.count)/2)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.4 + ratio * 0.6))
                        .frame(
                            width: max(2, (geo.size.width - CGFloat(bars.count) * 2) / CGFloat(bars.count)),
                            height: bars[i]
                        )
                }
            }
        }
        .onChange(of: level) { _, v in
            withAnimation(.easeOut(duration: 0.07)) {
                bars.removeFirst()
                bars.append(max(4, CGFloat(v) * 70 + CGFloat.random(in: 0...10)))
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Color hex helper
// ─────────────────────────────────────────────

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        let val = UInt64(h, radix: 16) ?? 0
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
