import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceFileManagerTests: QuickSpec {
    
    override func spec() {
        describe("File manager") {
            throwingContext("excluding from backup") {
                it("non-existing file") {
                    let nonExistingFile = URL(fileURLWithPath: "nonExistingFile")
                    expect {
                        try BacktraceFileManager.excludeFromBackup(nonExistingFile)
                        }.to(throwError(FileError.fileNotExists))
                }
                
                it("http url") {
                    guard let httpUrl = URL(string: "http://backtrace.io") else { fail(); return }
                    expect {
                        try BacktraceFileManager.excludeFromBackup(httpUrl)
                        }.to(throwError(FileError.unsupportedScheme))
                }
                it("existing file") {
                    let bundle = Bundle(for: type(of: self))
                    guard let path = bundle.path(forResource: "test", ofType: "txt") else { fail(); return }
                    let url = URL(fileURLWithPath: path)
                    expect {
                        try BacktraceFileManager.excludeFromBackup(url)
                        }.toNot(throwError())
                }
            }
            
            throwingContext("Size of file") {
                it("non-existing file") {
                    let nonExistingFile = URL(fileURLWithPath: "nonExistingFile")
                    expect {
                        try BacktraceFileManager.sizeOfFile(at: nonExistingFile)
                        }.to(throwError(FileError.fileNotExists))
                }
                
                it("http url") {
                    guard let httpUrl = URL(string: "http://backtrace.io") else { fail(); return }
                    expect {
                        try BacktraceFileManager.sizeOfFile(at: httpUrl)
                        }.to(throwError(FileError.unsupportedScheme))
                }
                it("existing file") {
                    let bundle = Bundle(for: type(of: self))
                    guard let path = bundle.path(forResource: "test", ofType: "txt") else { fail(); return }
                    let url = URL(fileURLWithPath: path)
                    expect {
                        try BacktraceFileManager.sizeOfFile(at: url)
                        }.toNot(throwError())
                }
            }
        }
    }
}
