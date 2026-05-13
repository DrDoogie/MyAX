import Foundation
import Security

// ─────────────────────────────────────────────
// MARK: - 회의록 모델
// ─────────────────────────────────────────────

struct SavedMeeting: Identifiable, Codable {
    let id: UUID
    let date: Date
    let title: String
    let body: String
    let seconds: Int
}

// ─────────────────────────────────────────────
// MARK: - 로컬 DB (JSON 파일)
// ─────────────────────────────────────────────

@MainActor
final class LocalDB: ObservableObject {
    static let shared = LocalDB()
    @Published private(set) var meetings: [SavedMeeting] = []

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecorder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("meetings.json")
    }()

    private init() { load() }

    func add(_ m: SavedMeeting) {
        meetings.insert(m, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        meetings.remove(atOffsets: offsets)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        meetings = (try? JSONDecoder().decode([SavedMeeting].self, from: data)) ?? []
    }

    private func persist() {
        try? JSONEncoder().encode(meetings).write(to: fileURL, options: .atomic)
    }
}

// ─────────────────────────────────────────────
// MARK: - Keychain
// ─────────────────────────────────────────────

enum KeychainStore {
    static func save(_ key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrAccount as String: key,
                                 kSecValueData as String: data]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrAccount as String: key,
                                 kSecReturnData as String: true,
                                 kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
