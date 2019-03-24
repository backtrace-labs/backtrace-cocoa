import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceFileManagerTests: QuickSpec {
    
    override func spec() {
        describe("File manager") {
            throwingContext("Exclude from context", closure: {
                it("non-existing file", closure: {
                    let nonExistingFile = URL(fileURLWithPath: "nonExisitingFile")
                    expect {
                        try BacktraceFileManager.excludeFromBackup(nonExistingFile)
                        }.to(throwError(FileError.fileNotExists))
                })
                
                it("http url", closure: {
                    guard let httpUrl = URL(string: "http://backtrace.io") else { fail(); return }
                    expect {
                        try BacktraceFileManager.excludeFromBackup(httpUrl)
                        }.to(throwError(FileError.unsupportedScheme))
                })
                it("existing file", closure: {
                    let bundle = Bundle(for: type(of: self))
                    guard let path = bundle.path(forResource: "test", ofType: "txt") else { fail(); return }
                    let url = URL(fileURLWithPath: path)
                    expect {
                        try BacktraceFileManager.excludeFromBackup(url)
                        }.toNot(throwError())
                })
            })
            
            throwingContext("Size of file", closure: {
                it("non-existing file", closure: {
                    let nonExistingFile = URL(fileURLWithPath: "nonExisitingFile")
                    expect {
                        try BacktraceFileManager.sizeOfFile(at: nonExistingFile)
                        }.to(throwError(FileError.fileNotExists))
                })
                
                it("http url", closure: {
                    guard let httpUrl = URL(string: "http://backtrace.io") else { fail(); return }
                    expect {
                        try BacktraceFileManager.sizeOfFile(at: httpUrl)
                        }.to(throwError(FileError.unsupportedScheme))
                })
                it("existing file", closure: {
                    let bundle = Bundle(for: type(of: self))
                    guard let path = bundle.path(forResource: "test", ofType: "txt") else { fail(); return }
                    let url = URL(fileURLWithPath: path)
                    expect {
                        try BacktraceFileManager.sizeOfFile(at: url)
                        }.toNot(throwError())
                })
            })
        }
    }
}
