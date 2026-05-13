import SwiftUI

struct SettingsScreen: View {
    @State private var apiKey = KeychainStore.load("anthropic_api_key") ?? ""
    @State private var showKey = false
    @State private var saved = false

    var body: some View {
        Form {
            // ── API 키 ────────────────────────────────
            Section {
                HStack {
                    Group {
                        if showKey {
                            TextField("sk-ant-...", text: $apiKey)
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                        }
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    KeychainStore.save("anthropic_api_key", value: apiKey)
                    withAnimation { saved = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        await MainActor.run { saved = false }
                    }
                } label: {
                    HStack {
                        Text("저장").fontWeight(.semibold)
                        if saved {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

            } header: {
                Text("Anthropic API 키")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("api.anthropic.com 에서 발급받으세요.")
                    Text("API 키 없이도 녹음·저장은 가능하지만 AI 요약은 비활성화됩니다.")
                }
            }

            // ── 개인정보 안내 ─────────────────────────
            Section("개인정보 보호") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("녹음 파일").font(.body)
                        Text("이 기기에만 저장, 외부 전송 없음").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(.green)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("음성 인식").font(.body)
                        Text("가능한 경우 기기 내에서만 처리").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "iphone").foregroundStyle(.blue)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude AI 호출 시").font(.body)
                        Text("텍스트만 전송, 음성 파일은 전송되지 않음").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "network").foregroundStyle(.orange)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API 키").font(.body)
                        Text("iCloud 미동기화, Keychain에만 저장").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "key.fill").foregroundStyle(.purple)
                }
            }

            // ── 저장 경로 ─────────────────────────────
            Section("저장 위치") {
                Label("앱 내 회의록 탭", systemImage: "doc.text.below.ecg")
                Label("공유 버튼 → 메모 앱에 내보내기", systemImage: "square.and.arrow.up")
            }

            // ── 데이터 초기화 ─────────────────────────
            Section {
                Button(role: .destructive) {
                    LocalDB.shared.meetings.indices.forEach { _ in
                        LocalDB.shared.delete(at: IndexSet(integer: 0))
                    }
                } label: {
                    Label("모든 회의록 삭제", systemImage: "trash")
                }
            }
        }
        .navigationTitle("설정")
    }
}
