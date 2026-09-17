// VersionTests.swift — drift guard for the pinned engine release tag.
//
// The repo-root SELENIUM_CORE_VERSION file is the single source of truth for the
// libselenium_core release tag. Swift pins it as `let seleniumCoreVersion` in
// Package.swift because the manifest's linkerSettings must know the fetch-cache
// dir at manifest-evaluation time — but that `let` lives in MANIFEST scope and
// is NOT visible to this test target's code, and there is NO source-level
// (Sources/) version constant to compare against either. So this test cannot
// assert seleniumCoreVersion == file directly. Instead it asserts the source-of-truth
// file exists and holds the tag this package was written for ("v0.8.0"): if the
// engine is bumped, this test fails and is the reminder that Package.swift's
// `let seleniumCoreVersion` must be updated in LOCKSTEP (it can't be read from here
// because it is manifest-scope). Keep this expected value and Package.swift's
// seleniumCoreVersion identical.
import XCTest
import Foundation

final class VersionTests: XCTestCase {

    // The tag Package.swift's `let seleniumCoreVersion` is pinned to. Must be updated
    // together with that literal whenever the engine release is bumped.
    private static let expectedSeleniumCoreVersion = "v0.8.0"

    func testSeleniumCoreVersionPin() throws {
        // Reach the repo root from THIS file's location (CWD under `swift test`
        // is not reliable). File is at swift/Tests/SeleniumTests/VersionTests.swift,
        // so four parent hops land on the repo root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SeleniumTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // swift/
            .deletingLastPathComponent()   // repo root
        let versionFile = root.appendingPathComponent("SELENIUM_CORE_VERSION")

        let contents = try String(contentsOf: versionFile, encoding: .utf8)
        let want = contents.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(
            want, Self.expectedSeleniumCoreVersion,
            "SELENIUM_CORE_VERSION says \"\(want)\" but this test (and Package.swift's seleniumCoreVersion) expects \"\(Self.expectedSeleniumCoreVersion)\" — update Package.swift's seleniumCoreVersion in lockstep and this expected value"
        )
    }
}
