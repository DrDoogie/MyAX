import Foundation
import UniformTypeIdentifiers

// MARK: - Model

struct ObsidianFile: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let content: String
    let createdAt: Date
    let modifiedAt: Date

    var relevantDate: Date { max(createdAt, modifiedAt) }
}

// MARK: - Errors

enum ObsidianError: LocalizedError {
    case vaultNotFound
    case noFilesFound

    var errorDescription: String? {
        switch self {
        case .vaultNotFound:
            return "Obsidian 볼트를 찾을 수 없습니다.\n설정에서 볼트 폴더를 선택해주세요."
        case .noFilesFound:
            return "이번 주에 생성/수정된 마크다운 파일이 없습니다."
        }
    }
}

// MARK: - Service

final class ObsidianVaultService {
    private enum Keys {
        static let bookmark = "obsidian_vault_bookmark"
        static let path     = "obsidian_vault_path"
        static let subpath  = "obsidian_vault_subpath"
    }

    var subpath: String {
        get { UserDefaults.standard.string(forKey: Keys.subpath) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.subpath) }
    }

    var displayPath: String {
        UserDefaults.standard.string(forKey: Keys.path) ?? ""
    }

    // MARK: Vault URL

    func resolvedVaultURL() -> URL? {
        // 1. Security-scoped bookmark saved from file importer
        if let data = UserDefaults.standard.data(forKey: Keys.bookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                return appendSubpath(to: url)
            }
        }

        // 2. iCloud Obsidian container (requires entitlement in production)
        if let container = FileManager.default
            .url(forUbiquityContainerIdentifier: "iCloud~md~obsidian") {
            return appendSubpath(to: container.appendingPathComponent("Documents"))
        }

        return nil
    }

    private func appendSubpath(to base: URL) -> URL {
        let sub = subpath.trimmingCharacters(in: .whitespacesAndNewlines)
        return sub.isEmpty ? base : base.appendingPathComponent(sub)
    }

    // MARK: Save Bookmark (called after file importer picks a folder)

    func saveVaultFolder(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        if let bookmark = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: Keys.bookmark)
        }
        UserDefaults.standard.set(url.path, forKey: Keys.path)
    }

    // MARK: Scan This Week

    func scanThisWeek() throws -> [ObsidianFile] {
        guard let vault = resolvedVaultURL() else { throw ObsidianError.vaultNotFound }

        let weekStart = Calendar.current
            .dateInterval(of: .weekOfYear, for: Date())?.start
            ?? Date().addingTimeInterval(-7 * 86400)

        _ = vault.startAccessingSecurityScopedResource()
        defer { vault.stopAccessingSecurityScopedResource() }

        return try enumerate(directory: vault, since: weekStart)
    }

    private func enumerate(directory: URL, since date: Date) throws -> [ObsidianFile] {
        let fm = FileManager.default
        try? fm.startDownloadingUbiquitousItem(at: directory)

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [ObsidianFile] = []

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }

            let rv = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let created  = rv?.creationDate ?? .distantPast
            let modified = rv?.contentModificationDate ?? .distantPast
            guard max(created, modified) >= date else { continue }

            try? fm.startDownloadingUbiquitousItem(at: url)
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

            results.append(ObsidianFile(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
                content: content,
                createdAt: created,
                modifiedAt: modified
            ))
        }

        return results.sorted { $0.relevantDate > $1.relevantDate }
    }

    // MARK: Save Summary

    func saveSummary(markdown: String) throws -> URL {
        guard let vault = resolvedVaultURL() else { throw ObsidianError.vaultNotFound }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-'W'ww"
        let filename = "Weekly-Summary-\(fmt.string(from: Date())).md"

        _ = vault.startAccessingSecurityScopedResource()
        defer { vault.stopAccessingSecurityScopedResource() }

        let dest = vault.appendingPathComponent(filename)
        try markdown.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }
}
