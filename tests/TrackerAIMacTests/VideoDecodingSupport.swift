import AVFoundation
import XCTest

func skipIfVideoDecodingUnsupported(_ error: Error, file: StaticString = #filePath, line: UInt = #line) throws {
    let nsError = error as NSError
    if nsError.domain == AVFoundationErrorDomain, nsError.code == -11821 {
        throw XCTSkip("AVFoundation video decoding is unavailable in this test environment: \(nsError.localizedDescription)", file: file, line: line)
    }
}
