// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  파일 1: ContentView.swift
//  Swift Playgrounds에서 기본 ContentView.swift를
//  열고 안의 내용을 모두 지운 뒤 이 코드를 붙여넣으세요.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import SwiftUI
import AVFoundation
import Speech

// ─────────────────────────────────────────────
// 앱 탭 구조
// ─────────────────────────────────────────────

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { RecordingScreen() }
                .tabItem { Label("녹음", systemImage: "mic.circle.fill") }

            NavigationStack { HistoryScreen() }
                .tabItem { Label("회의록", systemImage: "doc.text.fill") }

            NavigationStack { SettingsScreen() }
                .tabItem { Label("설정", systemImage: "gear") }
        }
    }
}

// ─────────────────────────────────────────────
// 녹음 화면
// ─────────────────────────────────────────────

struct RecordingScreen: View {
    @StateObject private var vm = RecordingVM()

    var body: some View {
        ZStack {
            gradient.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: vm.phase)

            VStack(spacing: 0) {
                Spacer()

                // 상태 표시 영역
                Group {
                    switch vm.phase {
                    case .idle:
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 90))
                            .foregroundStyle(.white.opacity(0.25))

                    case .recording:
                        WaveformBars(level: vm.audioLevel)
                            .frame(height: 80)
                            .padding(.horizontal, 40)

                    case .processing:
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large).tint(.white)
                            Text(vm.step)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(height: 110)

                Spacer().frame(height: 28)

                // 타이머
                Text(vm.timer)
                    .font(.system(size: 76, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Spacer().frame(height: 46)

                // 메인 버튼
                Button(action: vm.toggle) {
                    ZStack {
                        if vm.phase == .recording {
                            Circle()
                                .stroke(.white.opacity(0.25), lineWidth: 3)
                                .frame(width: 148, height: 148)
                                .scaleEffect(1.18)
                                .animation(
                                    .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                    value: vm.phase
                                )
                        }
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 128, height: 128)
                            .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 2))

                        Image(systemName: vm.phase == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 54, weight: .medium))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.phase == .processing)

                Spacer().frame(height: 26)

                Text(vm.phase == .idle      ? "버튼을 눌러 녹음 시작"    :
                     vm.phase == .recording ? "다시 누르면 녹음 종료" : "")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .navigationTitle("회의 녹음")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("오류", isPresented: $vm.showErr, presenting: vm.errMsg) { _ in
            Button("확인", role: .cancel) {}
        } message: { m in Text(m) }
    }

    private var gradient: LinearGradient {
        switch vm.phase {
        case .idle:
            return LinearGradient(colors: [Color(hex:"#1a1a2e"), Color(hex:"#16213e")],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .recording:
            return LinearGradient(colors: [Color(hex:"#7f0000"), Color(hex:"#200122")],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .processing:
            return LinearGradient(colors: [Color(hex:"#0f3460"), Color(hex:"#16213e")],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// ─────────────────────────────────────────────
// 파형 막대
// ─────────────────────────────────────────────

struct WaveformBars: View {
    let level: Float
    @State private var bars: [CGFloat] = Array(repeating: 4, count: 34)

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(bars.indices, id: \.self) { i in
                    let dist = abs(Double(i) - Double(bars.count) / 2) / (Double(bars.count) / 2)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.4 + (1 - dist) * 0.6))
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
// 회의록 목록 화면
// ─────────────────────────────────────────────

struct HistoryScreen: View {
    @ObservedObject private var db = LocalDB.shared
    @State private var query = ""
    @State private var selected: SavedMeeting?

    private var list: [SavedMeeting] {
        guard !query.isEmpty else { return db.meetings }
        let q = query.lowercased()
        return db.meetings.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if list.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "저장된 회의록이 없습니다" : "검색 결과 없음",
                    systemImage: "doc.text",
                    description: Text(query.isEmpty
                        ? "녹음 탭에서 회의를 시작하면 자동 저장됩니다."
                        : "'\(query)'에 해당하는 결과가 없습니다.")
                )
            } else {
                List {
                    ForEach(list) { m in
                        Button { selected = m } label: { MeetingRow(m: m) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { db.delete(at: $0) }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("회의록 목록")
        .searchable(text: $query, prompt: "제목·내용 검색")
        .sheet(item: $selected) { NoteDetail(meeting: $0) }
    }
}

struct MeetingRow: View {
    let m: SavedMeeting
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(m.title).font(.headline).lineLimit(1)
            HStack(spacing: 10) {
                Label(m.date.formatted(.dateTime.month().day().hour().minute()),
                      systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                Label(m.seconds >= 60 ? "\(m.seconds/60)분 \(m.seconds%60)초" : "\(m.seconds)초",
                      systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
            if let preview = m.body.components(separatedBy: "\n")
                .first(where: { !$0.hasPrefix("#") && !$0.isEmpty }) {
                Text(preview).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NoteDetail: View {
    let meeting: SavedMeeting
    @State private var showShare = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MDText(text: meeting.body).padding()
            }
            .navigationTitle(meeting.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShare) { ShareSheet(text: meeting.body) }
        }
    }
}

// ─────────────────────────────────────────────
// 간단 마크다운 렌더러
// ─────────────────────────────────────────────

struct MDText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, ln in
                if      ln.hasPrefix("# ")   { Text(ln.dropFirst(2)).font(.title2.bold()).padding(.top,8) }
                else if ln.hasPrefix("## ")  { Text(ln.dropFirst(3)).font(.title3.weight(.semibold)).padding(.top,6) }
                else if ln.hasPrefix("### ") { Text(ln.dropFirst(4)).font(.headline).foregroundStyle(.secondary).padding(.top,4) }
                else if ln.hasPrefix("- ")   {
                    HStack(alignment:.top, spacing:8) {
                        Text("•").foregroundStyle(.accentColor)
                        Text(ln.dropFirst(2))
                    }.font(.body)
                }
                else if ln == "---" { Divider().padding(.vertical,4) }
                else if ln.isEmpty  { Spacer().frame(height:2) }
                else                { Text(ln).font(.body) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ─────────────────────────────────────────────
// 설정 화면
// ─────────────────────────────────────────────

struct SettingsScreen: View {
    @State private var key = KeychainStore.load("anthropic_api_key") ?? ""
    @State private var show = false
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if show { TextField("sk-ant-...", text: $key) }
                        else    { SecureField("sk-ant-...", text: $key) }
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    Button { show.toggle() } label: {
                        Image(systemName: show ? "eye.slash" : "eye").foregroundStyle(.secondary)
                    }
                }
                Button {
                    KeychainStore.save("anthropic_api_key", value: key)
                    withAnimation { saved = true }
                    Task { try? await Task.sleep(for: .seconds(2)); await MainActor.run { saved = false } }
                } label: {
                    HStack {
                        Text("저장").fontWeight(.semibold)
                        if saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
            } header: { Text("Anthropic API 키") }
              footer: { Text("api.anthropic.com에서 발급. 없으면 AI 요약 없이 원문만 저장됩니다.") }

            Section("개인정보 보호") {
                Label("녹음·회의록: 이 기기에만 저장됨", systemImage: "lock.fill")
                Label("음성 인식: 기기 내 처리 우선", systemImage: "iphone")
                Label("AI 호출 시 텍스트만 전송 (음성 파일 제외)", systemImage: "network")
            }
        }
        .navigationTitle("설정")
    }
}

// ─────────────────────────────────────────────
// 공유 시트 (iOS)
// ─────────────────────────────────────────────

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.permittedArrowDirections = []
            pop.sourceRect = CGRect(x: UIScreen.main.bounds.midX,
                                    y: UIScreen.main.bounds.midY, width: 0, height: 0)
        }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// ─────────────────────────────────────────────
// Color hex
// ─────────────────────────────────────────────

extension Color {
    init(hex: String) {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt64(h, radix: 16) ?? 0
        self.init(red: Double((v>>16)&0xFF)/255,
                  green: Double((v>>8)&0xFF)/255,
                  blue: Double(v&0xFF)/255)
    }
}
