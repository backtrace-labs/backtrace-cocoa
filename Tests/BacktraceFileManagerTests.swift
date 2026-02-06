import Testing
@testable import Backtrace
import Foundation

private class BundleToken {}

@Suite("File manager")
struct BacktraceFileManagerTests {

    // MARK: - Excluding from backup

    @Test("Excluding non-existing file from backup throws fileNotExists error")
    func excludeFromBackupNonExistingFileThrows() {
        let nonExistingFile = URL(fileURLWithPath: "nonExistingFile")
        #expect(throws: FileError.fileNotExists) {
            try BacktraceFileManager.excludeFromBackup(nonExistingFile)
        }
    }

    @Test("Excluding URL file from backup throws unsupportedScheme error")
    func excludeFromBackupUrlFileThrows() throws {
        guard let httpUrl = URL(string: "http://backtrace.io") else {
            Issue.record("Failed to create URL")
            return
        }
        #expect(throws: FileError.unsupportedScheme) {
            try BacktraceFileManager.excludeFromBackup(httpUrl)
        }
    }

    @Test("Excluding existing file from backup succeeds")
    func excludeFromBackupExistingFileSucceeds() throws {
#if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: "test", withExtension: "txt") else {
            Issue.record("Failed to find test resource")
            return
        }
#else
        let bundle = Bundle(for: BundleToken.self)
        guard let path = bundle.path(forResource: "test", ofType: "txt") else {
            Issue.record("Failed to find test resource")
            return
        }
        let url = URL(fileURLWithPath: path)
#endif
        #expect(throws: Never.self) {
            try BacktraceFileManager.excludeFromBackup(url)
        }
    }

    // MARK: - Checking size of file

    @Test("Size of non-existing file throws fileNotExists error")
    func sizeOfNonExistingFileThrows() {
        let nonExistingFile = URL(fileURLWithPath: "nonExistingFile")
        #expect(throws: FileError.fileNotExists) {
            try BacktraceFileManager.sizeOfFile(at: nonExistingFile)
        }
    }

    @Test("Size of URL file throws unsupportedScheme error")
    func sizeOfUrlFileThrows() throws {
        guard let httpUrl = URL(string: "http://backtrace.io") else {
            Issue.record("Failed to create URL")
            return
        }
        #expect(throws: FileError.unsupportedScheme) {
            try BacktraceFileManager.sizeOfFile(at: httpUrl)
        }
    }

    @Test("Size of existing file succeeds")
    func sizeOfExistingFileSucceeds() throws {
#if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: "test", withExtension: "txt") else {
            Issue.record("Failed to find test resource")
            return
        }
#else
        let bundle = Bundle(for: BundleToken.self)
        guard let path = bundle.path(forResource: "test", ofType: "txt") else {
            Issue.record("Failed to find test resource")
            return
        }
        let url = URL(fileURLWithPath: path)
#endif
        #expect(throws: Never.self) {
            try BacktraceFileManager.sizeOfFile(at: url)
        }
    }
}
