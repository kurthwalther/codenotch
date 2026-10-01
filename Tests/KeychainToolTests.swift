import XCTest
@testable import Codenotch

/// Claude Code's token is read through `/usr/bin/security`, which prints it
/// with a trailing newline — or as hex, if it judges the bytes unprintable.
final class KeychainToolTests: XCTestCase {
    func testTheTrailingNewlineIsDropped() {
        let printed = Data("{\"a\":1}\n".utf8)
        XCTAssertEqual(KeychainItem.decodeToolOutput(printed), Data("{\"a\":1}".utf8))
    }

    func testHexOutputIsDecoded() {
        let json = Data("{\"a\":1}".utf8)
        let hex = json.map { String(format: "%02x", $0) }.joined() + "\n"
        XCTAssertEqual(KeychainItem.decodeToolOutput(Data(hex.utf8)), json)
    }

    func testJSONIsNotMistakenForHex() {
        let printed = Data("{\"claudeAiOauth\":{}}".utf8)
        XCTAssertEqual(KeychainItem.decodeToolOutput(printed), printed)
    }

    /// "Not found" has to stay distinguishable from a failure: one means
    /// Claude Code has never signed in, the other falls back to the API read.
    func testAMissingItemIsReportedAsNotFound() {
        let read = KeychainItem.readViaSecurityTool(
            service: "codenotch-tests-no-such-item-\(UUID().uuidString)")
        XCTAssertEqual(read, .notFound)
    }
}
