import Testing
import Foundation
@testable import Backtrace

@Suite(.serialized) struct BacktraceDatabaseTests {

    private let crashReporter = BacktraceCrashReporter()

    private func makeRepository() throws -> PersistentRepository<BacktraceReport> {
        return try PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())
    }

    @Test("Can clear database")
    func clearDatabase() throws {
        let repository = try makeRepository()
        try repository.clear()
    }

    @Test("Can save reports which matches to the latest saved one")
    func saveReportsMatchesLatest() throws {
        let repository = try makeRepository()
        let report = try crashReporter.generateLiveReport(attributes: [:])
        try repository.save(report)
        if let fetchedReport = try repository.getLatest().first {
            #expect(fetchedReport.reportData == report.reportData)
        }
    }

    @Test("Can add new report and remove it")
    func addAndRemoveReport() throws {
        let repository = try makeRepository()
        try repository.clear()
        let report = try crashReporter.generateLiveReport(attributes: [:])
        try repository.save(report)
        #expect(try repository.countResources() == 1)
        if let fetchedReport = try repository.getLatest().first {
            #expect(fetchedReport.reportData == report.reportData)
            try repository.delete(fetchedReport)
            #expect(try repository.countResources() == 0)
        } else {
            Issue.record("Expected to fetch a report but got none")
        }
    }

    @Test("Can add 100 new reports asynchronously")
    func add100ReportsAsync() throws {
        let repository = try makeRepository()
        try? repository.clear()
        for _ in 1...100 {
            let group = DispatchGroup()
            let report = try? crashReporter.generateLiveReport(attributes: [:])
            DispatchQueue.global().async(group: group) {
                try? repository.save(report!)
            }
            group.wait()
        }
        // Poll until the condition is met
        var count = try? repository.countResources()
        for _ in 0..<50 {
            if count == 100 { break }
            Thread.sleep(forTimeInterval: 0.1)
            count = try? repository.countResources()
        }
        #expect(count == 100)
    }

    @Test("Supports concurrent read/write operations")
    func concurrentReadWrite() throws {
        let repository = try makeRepository()
        try repository.clear()

        let writeGroup = DispatchGroup()
        let readGroup = DispatchGroup()

        // concurrent writes
        for _ in 1...5 {
            writeGroup.enter()
            DispatchQueue.global().async {
                defer { writeGroup.leave() }
                do {
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try repository.save(report)
                } catch {
                    Issue.record("Failed to save concurrently: \(error)")
                }
            }
        }

        // concurrent reads
        for _ in 1...5 {
            readGroup.enter()
            DispatchQueue.global().async {
                defer { readGroup.leave() }
                do {
                    _ = try repository.getLatest()
                } catch {
                    Issue.record("Failed to fetch concurrently: \(error)")
                }
            }
        }

        writeGroup.wait()
        readGroup.wait()
        #expect((try? repository.countResources()) == 5)
    }

    @Test("Custom maxRecordCount removes oldest records when max record count is exceeded")
    func customMaxRecordCount() throws {
        let settingsWithLimit = BacktraceDatabaseSettings()
        settingsWithLimit.maxRecordCount = 5
        let limitedRepository = try PersistentRepository<BacktraceReport>(settings: settingsWithLimit)
        try limitedRepository.clear()
        // Insert 6 reports
        let timeOrderedReports = try (1...6).map { _ -> BacktraceReport in
            let report = try crashReporter.generateLiveReport(attributes: [:])
            try limitedRepository.save(report)
            return report
        }
        // Should remove oldest if limit is 5
        let finalCount = try limitedRepository.countResources()
        #expect(finalCount == 5)

        // check if the first inserted record is deleted
        let firstInserted = timeOrderedReports.first!
        let allResources = try limitedRepository.getAll()
        let containsFirst = allResources.contains { $0.identifier == firstInserted.identifier }
        #expect(!containsFirst)
    }

    @Test("Increments retry count and removes resource when limit is exceeded")
    func incrementRetryCountRemovesOnExceed() throws {
        let repository = try makeRepository()
        try repository.clear()
        let report = try crashReporter.generateLiveReport(attributes: [:])
        try repository.save(report)
        // First increment
        try repository.incrementRetryCount(report, limit: 3)
        // Second increment
        try repository.incrementRetryCount(report, limit: 3)
        // getLatest should still return latest
        let secondCheck = try repository.getLatest().first
        #expect(secondCheck != nil)
        // Exceed the limit
        try repository.incrementRetryCount(report, limit: 2)
        // Now it should be removed
        #expect(try repository.countResources() == 0)
    }
}
