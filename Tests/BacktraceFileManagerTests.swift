import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceFileManagerTests: QuickSpec {

    // swiftlint:disable function_body_length
    override func spec() {
        describe("File manager") {
            describe("Excluding from backup") {
                throwingContext("given non-existing") {
                    it("throws an error") {
                        let nonExistingFile = URL(fileURLWithPath: "nonExistingFile")
                        expect {
                            try BacktraceFileManager.excludeFromBackup(nonExistingFile)
                        }.to(throwError(FileError.fileNotExists))
                    }
                    throwingContext("given URL file") {
                        it("throws an error") {
                            guard let httpUrl = URL(string: "http://backtrace.io") else { fail(); return }
                            expect {
                                try BacktraceFileManager.excludeFromBackup(httpUrl)
                            }.to(throwError(FileError.unsupportedScheme))
                        }
                    }
                    throwingContext("given existing file") {
                        it("excludes file from backup") {
                            let bundle = Bundle(for: type(of: self))
                            var filePath: String?
#if SWIFT_PACKAGE
                            filePath = Bundle.module.path(forResource:"test", ofType:"txt")
#endif
                            if filePath == nil {
                                filePath = bundle.path(forResource: "test", ofType: "txt")
                            }
            
                            guard let path = filePath else { fail(); return }
                            let url = URL(fileURLWithPath: path)
                            expect {
                                try BacktraceFileManager.excludeFromBackup(url)
                            }.toNot(throwError())
                        }
                    }
                }
            }
            describe("Checking size of file") {
                throwingContext("given non-existing file") {
                    it("throws an error") {
                        let nonExistingFile = URL(fileURLWithPath: "nonExistingFile")
                        expect {
                            try BacktraceFileManager.sizeOfFile(at: nonExistingFile)
                        }.to(throwError(FileError.fileNotExists))
                    }
                }
                throwingContext("given URL file") {
                    it("throws an error") {
                        guard let httpUrl = URL(string: "http://backtrace.io") else { fail(); return }
                        expect {
                            try BacktraceFileManager.sizeOfFile(at: httpUrl)
                        }.to(throwError(FileError.unsupportedScheme))
                    }
                    throwingContext("given existing file") {
                        it("gets the size of a file") {
                            let bundle = Bundle(for: type(of: self))
                            var filePath: String?
#if SWIFT_PACKAGE
                            filePath = Bundle.module.path(forResource:"test", ofType:"txt")
#endif
                            if filePath == nil {
                                filePath = bundle.path(forResource: "test", ofType: "txt")
                            }
            
                            guard let path = filePath else { fail(); return }
                            let url = URL(fileURLWithPath: path)
                            expect {
                                try BacktraceFileManager.sizeOfFile(at: url)
                            }.toNot(throwError())
                        }
                    }
                }
            }
        }
    }
    // swiftlint:enable function_body_length
}
