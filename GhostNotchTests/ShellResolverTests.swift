import XCTest

final class ShellResolverTests: XCTestCase {
    func testUsesExecutableShellFromEnvironment() {
        let resolver = ShellResolver(environment: ["SHELL": "/bin/sh"])

        XCTAssertEqual(resolver.resolve(), "/bin/sh")
    }

    func testFallsBackWhenShellIsMissing() {
        let resolver = ShellResolver(environment: [:])

        XCTAssertEqual(resolver.resolve(), ShellResolver.defaultFallbackShell)
    }

    func testFallsBackWhenShellIsEmpty() {
        let resolver = ShellResolver(environment: ["SHELL": "  "])

        XCTAssertEqual(resolver.resolve(), ShellResolver.defaultFallbackShell)
    }

    func testFallsBackWhenShellIsNotExecutable() {
        let resolver = ShellResolver(environment: ["SHELL": "/not/a/real/shell"])

        XCTAssertEqual(resolver.resolve(), ShellResolver.defaultFallbackShell)
    }
}
