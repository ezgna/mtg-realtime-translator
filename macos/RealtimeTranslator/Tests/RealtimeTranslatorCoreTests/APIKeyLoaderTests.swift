import XCTest
@testable import RealtimeTranslatorCore

final class APIKeyLoaderTests: XCTestCase {
    func testLoadsKeyFromExternalEnvFormat() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtg-realtime-translator-test-\(UUID().uuidString).env")
        try "OTHER=value\nOPENAI_API_KEY=\"sk-test\"\n".write(to: url, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let key = try APIKeyLoader(path: url.path).load()
        XCTAssertEqual(key, "sk-test")
    }

    func testMissingKeyThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtg-realtime-translator-test-\(UUID().uuidString).env")
        try "OTHER=value\n".write(to: url, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        XCTAssertThrowsError(try APIKeyLoader(path: url.path).load()) { error in
            XCTAssertEqual(error as? APIKeyError, .missingKey(url.path))
        }
    }
}
