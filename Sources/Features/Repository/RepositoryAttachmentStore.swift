import Foundation

enum RepositoryAttachmentStoreError: Error {
    case unsafePath(URL)
    case cleanupDeferred
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
    private let copyItem: (URL, URL) throws -> Void
    private let regularFileResourceValues: (URL) throws -> URLResourceValues

    init(databaseUrl: URL,
         fileManager: FileManager = .default,
         copyItem: ((URL, URL) throws -> Void)? = nil,
         regularFileResourceValues: ((URL) throws -> URLResourceValues)? = nil) throws {
        self.fileManager = fileManager
        self.copyItem = copyItem ?? { sourceUrl, destinationUrl in
            try fileManager.copyItem(at: sourceUrl, to: destinationUrl)
        }
        self.regularFileResourceValues = regularFileResourceValues ?? { sourceUrl in
            try sourceUrl.resourceValues(forKeys: [.isRegularFileKey])
        }
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

    func store(_ attachmentPaths: [String],
               reportIdentifier: UUID,
               skipsUnreadableSources: Bool = false) throws -> StoredAttachments {
        let uniquePaths = unique(attachmentPaths)

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
                guard let staged = try stage(path,
                                             index: index,
                                             transactionUrl: transactionUrl,
                                             skipsUnreadableSources: skipsUnreadableSources) else { continue }
                storedPaths.append(staged.path)
                copiedFileCount += staged.wasCopied ? 1 : 0
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

    // Reconciliation deliberately walks and validates both repository hierarchy levels in one pass so unsafe paths are never handed to a helper without the surrounding containment state.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func reconcile(referencedAttachmentPaths: [String]) throws {
        var cleanupWasDeferred = false
        try rejectSymbolicLink(rootUrl)
        try createDirectoryIfNeeded(rootUrl)

        if fileManager.fileExists(atPath: stagingRootUrl.path) {
            try rejectSymbolicLink(stagingRootUrl)
            try requireContained(stagingRootUrl)
            do {
                try fileManager.removeItem(at: stagingRootUrl)
            } catch {
                BacktraceLogger.warning("Deferred cleanup of stale attachment staging data.")
                throw RepositoryAttachmentStoreError.cleanupDeferred
            }
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
                do {
                    try fileManager.removeItem(at: reportDirectoryUrl)
                } catch {
                    BacktraceLogger.warning("Deferred cleanup of an unsafe attachment repository entry.")
                    cleanupWasDeferred = true
                }
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
                    do {
                        try fileManager.removeItem(at: generationUrl)
                    } catch {
                        BacktraceLogger.warning("Deferred cleanup of an unsafe attachment generation.")
                        cleanupWasDeferred = true
                    }
                    continue
                }
                let resolvedGenerationUrl = generationUrl.resolvingSymlinksInPath().standardizedFileURL
                let generationPath = resolvedGenerationUrl.path + "/"
                let isReferenced = referencedUrls.contains {
                    let resolvedUrl = $0.resolvingSymlinksInPath().standardizedFileURL
                    return resolvedUrl.path == resolvedGenerationUrl.path || resolvedUrl.path.hasPrefix(generationPath)
                }
                if !isReferenced {
                    do {
                        try fileManager.removeItem(at: generationUrl)
                    } catch {
                        BacktraceLogger.warning("Deferred cleanup of an orphan attachment generation.")
                        cleanupWasDeferred = true
                    }
                }
            }
            removeDirectoryIfEmpty(reportDirectoryUrl)
        }
        if cleanupWasDeferred {
            throw RepositoryAttachmentStoreError.cleanupDeferred
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

    private func unique(_ paths: [String]) -> [String] {
        var seenPaths = Set<String>()
        return paths.filter { seenPaths.insert($0).inserted }
    }

    private func stage(_ path: String,
                       index: Int,
                       transactionUrl: URL,
                       skipsUnreadableSources: Bool) throws -> (path: String, wasCopied: Bool)? {
        let sourceUrl = URL(fileURLWithPath: path).standardizedFileURL
        if contains(sourceUrl) {
            return repositoryOwnedAttachment(sourceUrl)
        }

        guard fileManager.fileExists(atPath: sourceUrl.path) else {
            BacktraceLogger.warning("Skipping a missing attachment during persistence.")
            return nil
        }

        let resolvedSourceUrl = sourceUrl.resolvingSymlinksInPath()
        guard try validateSource(resolvedSourceUrl,
                                 skipsUnreadableSources: skipsUnreadableSources) else { return nil }
        return try copySource(resolvedSourceUrl,
                              index: index,
                              transactionUrl: transactionUrl,
                              skipsUnreadableSources: skipsUnreadableSources)
    }

    private func repositoryOwnedAttachment(_ sourceUrl: URL) -> (path: String, wasCopied: Bool)? {
        guard fileManager.fileExists(atPath: sourceUrl.path) else {
            BacktraceLogger.warning("Skipping a missing repository-owned attachment.")
            return nil
        }
        return (sourceUrl.resolvingSymlinksInPath().standardizedFileURL.path, false)
    }

    private func validateSource(_ sourceUrl: URL,
                                skipsUnreadableSources: Bool) throws -> Bool {
        if skipsUnreadableSources && !fileManager.isReadableFile(atPath: sourceUrl.path) {
            BacktraceLogger.warning("Skipping an unreadable attachment during pending-crash persistence.")
            return false
        }
        let resourceValues: URLResourceValues
        do {
            resourceValues = try regularFileResourceValues(sourceUrl)
        } catch {
            guard skipsUnreadableSources else { throw error }
            BacktraceLogger.warning(
                "Skipping a pending-crash attachment that became unavailable during validation.")
            return false
        }
        guard resourceValues.isRegularFile == true else {
            BacktraceLogger.warning("Skipping a non-file attachment during persistence.")
            return false
        }
        return true
    }

    private func copySource(_ sourceUrl: URL,
                            index: Int,
                            transactionUrl: URL,
                            skipsUnreadableSources: Bool) throws -> (path: String, wasCopied: Bool)? {
        let fileName = "\(index)-\(sourceUrl.lastPathComponent)"
        let destinationUrl = transactionUrl.appendingPathComponent(fileName, isDirectory: false)
        do {
            try copyItem(sourceUrl, destinationUrl)
        } catch {
            // Pending attachments are optional. A source can disappear or become unreadable after preflight but before FileManager opens it.
            // Destination failures remain fatal.
            guard skipsUnreadableSources, !isReadableRegularFile(sourceUrl) else {
                throw error
            }
            try? fileManager.removeItem(at: destinationUrl)
            BacktraceLogger.warning(
                "Skipping a pending-crash attachment that became unavailable during persistence.")
            return nil
        }
        return (destinationUrl.path, true)
    }

    private func isReadableRegularFile(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              fileManager.isReadableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
            return false
        }
        return values.isRegularFile == true
    }

    private func removeDirectoryIfEmpty(_ url: URL) {
        guard contains(url),
              let contents = try? fileManager.contentsOfDirectory(atPath: url.path),
              contents.isEmpty else { return }
        try? fileManager.removeItem(at: url)
    }
}
