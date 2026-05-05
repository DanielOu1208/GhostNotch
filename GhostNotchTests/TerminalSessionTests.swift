import XCTest

@MainActor
final class TerminalSessionTests: XCTestCase {
    func testSessionRunsCommandAndCapturesOutput() async throws {
        let state = TerminalSessionState(outputLimit: 16 * 1024)
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            state: state
        )

        try session.start(cols: 80, rows: 24)
        defer {
            session.stop()
        }

        let marker = "GHOSTNOTCH_TEST_\(UUID().uuidString)"
        try session.write("printf '\\n\(marker)\\n'\n")

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if state.outputText.contains(marker) {
                XCTAssertTrue(session.isRunning)
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Terminal session did not capture command output. Output was: \(state.outputText)")
    }

    func testStoppingSessionMarksItStopped() throws {
        let state = TerminalSessionState(outputLimit: 16 * 1024)
        let session = TerminalSession(
            shellResolver: ShellResolver(environment: ["SHELL": "/bin/sh"]),
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            state: state
        )

        try session.start(cols: 80, rows: 24)
        XCTAssertTrue(session.isRunning)
        XCTAssertTrue(state.isRunning)

        session.stop()

        XCTAssertFalse(session.isRunning)
        XCTAssertFalse(state.isRunning)
    }

    func testTerminalInputMappingUsesPTYControlBytes() {
        XCTAssertEqual(TerminalInputMapping.data(forKeyCode: 36, characters: "\r"), Data([0x0D]))
        XCTAssertEqual(TerminalInputMapping.data(forKeyCode: 76, characters: "\r"), Data([0x0D]))
        XCTAssertEqual(TerminalInputMapping.data(forKeyCode: 48, characters: "\t"), Data([0x09]))
        XCTAssertEqual(TerminalInputMapping.data(forKeyCode: 51, characters: "\u{7F}"), Data([0x7F]))
        XCTAssertEqual(TerminalInputMapping.data(forKeyCode: 117, characters: "\u{7F}"), Data([0x7F]))
    }

    func testTerminalInputMappingPreservesTextAndNormalizesNewlines() {
        XCTAssertEqual(TerminalInputMapping.data(forInsertedText: "pwd"), Data("pwd".utf8))
        XCTAssertEqual(TerminalInputMapping.data(forInsertedText: "echo hi\n"), Data("echo hi\r".utf8))
        XCTAssertEqual(TerminalInputMapping.data(forKeyCode: 0, characters: "a"), Data("a".utf8))
        XCTAssertNil(TerminalInputMapping.data(forInsertedText: ""))
        XCTAssertNil(TerminalInputMapping.data(forKeyCode: 0, characters: nil))
    }

    func testTerminalPasteMappingSanitizesUnsafeEscapesWithoutBracketedWrappers() {
        XCTAssertEqual(TerminalInputMapping.data(forPastedText: "echo hi\u{1B}\n"), Data("echo hi \r".utf8))
        XCTAssertNil(TerminalInputMapping.data(forPastedText: ""))
    }
}
