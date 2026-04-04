import Foundation
import XCTest

final class MigrationBacklog22Tests: XCTestCase {
    func testNativeReleaseValidatorPassesForRepositoryConfiguration() throws {
        let result = try runScript(arguments: [
            "scripts/validate_native_macos_release.sh",
            "--project-root", repositoryRoot().path,
            "--source-only",
        ])

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
        XCTAssertTrue(result.combinedOutput.contains("Source release configuration looks valid."), result.combinedOutput)
    }

    func testNativeBuildScriptSupportsSourceOnlyValidationMode() throws {
        let result = try runScript(arguments: [
            "scripts/build_native_macos_app.sh",
            "--source-only-validation",
            "--skip-tests",
        ])

        XCTAssertEqual(result.exitCode, 0, result.combinedOutput)
        XCTAssertTrue(result.combinedOutput.contains("Source-only validation complete."), result.combinedOutput)
    }

    private func runScript(arguments: [String]) throws -> ScriptResult {
        let process = Process()
        process.currentDirectoryURL = repositoryRoot()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let combinedOutput = String(decoding: outputData + errorData, as: UTF8.self)
        return ScriptResult(exitCode: process.terminationStatus, combinedOutput: combinedOutput)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ScriptResult {
    let exitCode: Int32
    let combinedOutput: String
}
