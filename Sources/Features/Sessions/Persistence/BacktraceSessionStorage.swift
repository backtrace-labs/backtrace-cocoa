import Foundation

/// File-based offline storage for pending session uploads.
///
/// Stores failed uploads as individual files in the Caches directory.
/// A retry timer periodically attempts to re-send pending items.
final class BacktraceSessionStorage {

    enum PendingType: String, CaseIterable {
        case events
        case screenshots
        case logs
        case feedback
    }

    private let storageDir: URL
    private let maxSizeBytes: Int
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "io.backtrace.sessions.storage", qos: .background)

    init(maxSizeMB: Int) {
        self.maxSizeBytes = maxSizeMB * 1024 * 1024
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.storageDir = caches.appendingPathComponent("io.backtrace.sessions/pending", isDirectory: true)
        createDirectoryStructure()
    }

    // MARK: - Save

    /// Save pending data to disk for later retry.
    func save(type: PendingType, data: Data) throws {
        let dir = storageDir.appendingPathComponent(type.rawValue, isDirectory: true)
        let ext: String
        switch type {
        case .events, .logs: ext = "json.gz"
        case .screenshots: ext = "jpg"
        case .feedback: ext = "multipart"
        }
        let file = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")

        try queue.sync {
            try data.write(to: file, options: .atomic)
            pruneIfNeeded()
        }
    }

    // MARK: - Load Pending

    /// Load all pending items of a given type, sorted oldest first.
    func loadPending(type: PendingType) -> [(url: URL, data: Data)] {
        let dir = storageDir.appendingPathComponent(type.rawValue, isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let sorted = files.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return dateA < dateB
        }

        return sorted.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (url: url, data: data)
        }
    }

    // MARK: - Remove

    /// Remove a pending item after successful upload.
    func remove(at url: URL) {
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Prune

    /// Remove oldest files until total size is under the limit.
    func pruneIfNeeded() {
        var allFiles: [(url: URL, date: Date, size: Int)] = []

        for type in PendingType.allCases {
            let dir = storageDir.appendingPathComponent(type.rawValue, isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]) else { continue }
                let date = values.creationDate ?? .distantPast
                let size = values.fileSize ?? 0
                allFiles.append((url: file, date: date, size: size))
            }
        }

        // Sort oldest first
        allFiles.sort { $0.date < $1.date }

        var totalSize = allFiles.reduce(0) { $0 + $1.size }

        // Remove files older than 7 days
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for file in allFiles where file.date < cutoff {
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }

        // Remove oldest files until under size limit
        var index = 0
        while totalSize > maxSizeBytes && index < allFiles.count {
            let file = allFiles[index]
            if fileManager.fileExists(atPath: file.url.path) {
                try? fileManager.removeItem(at: file.url)
                totalSize -= file.size
            }
            index += 1
        }
    }

    // MARK: - Private

    private func createDirectoryStructure() {
        for type in PendingType.allCases {
            let dir = storageDir.appendingPathComponent(type.rawValue, isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
