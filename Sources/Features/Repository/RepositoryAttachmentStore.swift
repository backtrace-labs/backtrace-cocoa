import Foundation

enum RepositoryAttachmentStoreError: Error {
    case unsafePath(URL)
    case incompleteAttachmentStaging
}

/// Owns immutable attachment copies referenced by retry database rows.
///
/// Each write is built under `.staging` and then moved into a new immutable generation.
/// Core Data is updated only after that move succeeds, so an interrupted write is either still staging or unreferenced.
/// Both cases are safe to reconcile on the next startup.
final class RepositoryAttachmentStore {
    struct StoredAttachments {
        let paths: [String]
        let generationUrl: URL?
        let isComplete: Bool
    }

    let rootUrl: URL
    let stagingRootUrl: URL
    private let fileManager: FileManager

    init(databaseUrl: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootUrl = databaseUrl.deletingLastPathComponent()
            .appendingPathComponent("BacktraceAttachments", isDirectory: true)
            .standardizedFileURL
        self.stagingRootUrl = rootUrl.appendingPathComponent(".staging", isDirectory: true)

        try rejectSymbolicLink(rootUrl)
        try createDirectoryIfNeeded(rootUrl)
        try rejectSymbolicLink(rootUrl)
        try rejectSymbolicLink(stagingRootUrl)
        try createDirectoryIfNeeded(stagingRootUrl)
        try rejectSymbolicLink(stagingRootUrl)
        try? BacktraceFileManager.excludeFromBackup(rootUrl)
    }

    func store(_ attachmentPaths: [String], reportIdentifier: UUID) throws -> StoredAttachments {
        var uniquePaths = [String]()
        var seenPaths = Set<String>()
        for path in attachmentPaths where seenPaths.insert(path).inserted {
            uniquePaths.append(path)
        }

        guard !uniquePaths.isEmpty else {
            return StoredAttachments(paths: [], generationUrl: nil, isComplete: true)
        }

        let transactionUrl = stagingRootUrl
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try createDirectoryIfNeeded(transactionUrl)
        try requireContained(transactionUrl)

        var storedPaths = [String]()
        var copiedFileCount = 0

        do {
            for (index, path) in uniquePaths.enumerated() {
                let sourceUrl = URL(fileURLWithPath: path).standardizedFileURL
                if contains(sourceUrl) {
                    guard fileManager.fileExists(atPath: sourceUrl.path) else {
                        BacktraceLogger.warning("Skipping missing repository attachment: \(sourceUrl.path)")
                        continue
                    }
                    storedPaths.append(sourceUrl.resolvingSymlinksInPath().standardizedFileURL.path)
                    continue
                }

                guard fileManager.fileExists(atPath: sourceUrl.path) else {
                    BacktraceLogger.warning("Skipping missing attachment during persistence: \(sourceUrl.path)")
                    continue
                }

                let resolvedSourceUrl = sourceUrl.resolvingSymlinksInPath()
                let resourceValues = try resolvedSourceUrl.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true else {
                    BacktraceLogger.warning("Skipping non-file attachment during persistence: \(sourceUrl.path)")
                    continue
                }

                let fileName = "\(index)-\(resolvedSourceUrl.lastPathComponent)"
                let destinationUrl = transactionUrl.appendingPathComponent(fileName, isDirectory: false)
                try fileManager.copyItem(at: resolvedSourceUrl, to: destinationUrl)
                storedPaths.append(destinationUrl.path)
                copiedFileCount += 1
            }

            guard copiedFileCount > 0 else {
                try? fileManager.removeItem(at: transactionUrl)
                return StoredAttachments(paths: storedPaths,
                                         generationUrl: nil,
                                         isComplete: storedPaths.count == uniquePaths.count)
            }

            let reportDirectoryUrl = rootUrl
                .appendingPathComponent(reportIdentifier.uuidString, isDirectory: true)
            try rejectSymbolicLink(reportDirectoryUrl)
            try createDirectoryIfNeeded(reportDirectoryUrl)
            try rejectSymbolicLink(reportDirectoryUrl)
            try requireContained(reportDirectoryUrl)
            let generationUrl = reportDirectoryUrl
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try requireContained(generationUrl)
            try fileManager.moveItem(at: transactionUrl, to: generationUrl)

            let finalizedPaths = storedPaths.map { path -> String in
                let url = URL(fileURLWithPath: path).standardizedFileURL
                guard transactionUrl.path == url.deletingLastPathComponent().path else { return path }
                return generationUrl.appendingPathComponent(url.lastPathComponent).path
            }
            return StoredAttachments(paths: finalizedPaths,
                                     generationUrl: generationUrl,
                                     isComplete: finalizedPaths.count == uniquePaths.count)
        } catch {
            try? fileManager.removeItem(at: transactionUrl)
            throw error
        }
    }

    func rollback(_ storedAttachments: StoredAttachments) {
        guard let generationUrl = storedAttachments.generationUrl,
              contains(generationUrl) else { return }
        try? fileManager.removeItem(at: generationUrl)
        removeDirectoryIfEmpty(generationUrl.deletingLastPathComponent())
    }

    func removeAttachments(for reportIdentifier: UUID) throws {
        let reportDirectoryUrl = rootUrl
            .appendingPathComponent(reportIdentifier.uuidString, isDirectory: true)
            .standardizedFileURL
        guard contains(reportDirectoryUrl) else {
            throw RepositoryAttachmentStoreError.unsafePath(reportDirectoryUrl)
        }
        guard fileManager.fileExists(atPath: reportDirectoryUrl.path) else { return }
        try fileManager.removeItem(at: reportDirectoryUrl)
    }

    func reconcile(referencedAttachmentPaths: [String]) throws {
        try rejectSymbolicLink(rootUrl)
        try createDirectoryIfNeeded(rootUrl)

        if fileManager.fileExists(atPath: stagingRootUrl.path) {
            try rejectSymbolicLink(stagingRootUrl)
            try requireContained(stagingRootUrl)
            try fileManager.removeItem(at: stagingRootUrl)
        }
        try createDirectoryIfNeeded(stagingRootUrl)
        try rejectSymbolicLink(stagingRootUrl)
        try requireContained(stagingRootUrl)

        let referencedUrls = referencedAttachmentPaths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter(contains)

        let reportDirectories = try fileManager.contentsOfDirectory(at: rootUrl,
                                                                     includingPropertiesForKeys: [.isDirectoryKey,
                                                                                                  .isSymbolicLinkKey],
                                                                     options: [.skipsHiddenFiles])
        for reportDirectoryUrl in reportDirectories where reportDirectoryUrl.lastPathComponent != ".staging" {
            let values = try reportDirectoryUrl.resourceValues(forKeys: [.isDirectoryKey,
                                                                          .isSymbolicLinkKey])
            guard containsLexically(reportDirectoryUrl) else {
                throw RepositoryAttachmentStoreError.unsafePath(reportDirectoryUrl)
            }
            guard values.isSymbolicLink != true,
                  contains(reportDirectoryUrl),
                  values.isDirectory == true else {
                try fileManager.removeItem(at: reportDirectoryUrl)
                continue
            }

            let generations = try fileManager.contentsOfDirectory(at: reportDirectoryUrl,
                                                                   includingPropertiesForKeys: [.isDirectoryKey,
                                                                                                .isSymbolicLinkKey],
                                                                   options: [.skipsHiddenFiles])
            for generationUrl in generations {
                let values = try generationUrl.resourceValues(forKeys: [.isDirectoryKey,
                                                                         .isSymbolicLinkKey])
                guard containsLexically(generationUrl) else {
                    throw RepositoryAttachmentStoreError.unsafePath(generationUrl)
                }
                guard values.isSymbolicLink != true,
                      values.isDirectory == true,
                      contains(generationUrl) else {
                    try fileManager.removeItem(at: generationUrl)
                    continue
                }
                let resolvedGenerationUrl = generationUrl.resolvingSymlinksInPath().standardizedFileURL
                let generationPath = resolvedGenerationUrl.path + "/"
                let isReferenced = referencedUrls.contains {
                    let resolvedUrl = $0.resolvingSymlinksInPath().standardizedFileURL
                    return resolvedUrl.path == resolvedGenerationUrl.path || resolvedUrl.path.hasPrefix(generationPath)
                }
                if !isReferenced {
                    try fileManager.removeItem(at: generationUrl)
                }
            }
            removeDirectoryIfEmpty(reportDirectoryUrl)
        }
    }

    func contains(_ url: URL) -> Bool {
        let rootPath = rootUrl.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func containsLexically(_ url: URL) -> Bool {
        let rootPath = rootUrl.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func requireContained(_ url: URL) throws {
        guard containsLexically(url), contains(url) else {
            throw RepositoryAttachmentStoreError.unsafePath(url)
        }
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw RepositoryAttachmentStoreError.unsafePath(url)
        }
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.createDirectory(at: url,
                                        withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.none])
    }

    private func removeDirectoryIfEmpty(_ url: URL) {
        guard contains(url),
              let contents = try? fileManager.contentsOfDirectory(atPath: url.path),
              contents.isEmpty else { return }
        try? fileManager.removeItem(at: url)
    }
}
