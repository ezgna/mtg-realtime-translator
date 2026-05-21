import Foundation
import XCTest
@testable import RealtimeTranslatorCore

final class SpeechGateTests: XCTestCase {
    func testPreRollFlushesOnSpeechStart() {
        let gate = SpeechGate(preRollLimit: 2, tailChunkCount: 1, frameByteCount: 2)

        _ = gate.process(frame: Data([1, 1]), event: nil)
        _ = gate.process(frame: Data([2, 2]), event: nil)
        _ = gate.process(frame: Data([3, 3]), event: nil)
        let output = gate.process(frame: Data([4, 4]), event: .speechStart)

        XCTAssertEqual(output, [Data([2, 2]), Data([3, 3]), Data([4, 4])])
    }

    func testSilenceTailAfterSpeechEnd() {
        let gate = SpeechGate(preRollLimit: 1, tailChunkCount: 2, frameByteCount: 2)

        _ = gate.process(frame: Data([1, 1]), event: .speechStart)
        let firstTail = gate.process(frame: Data([2, 2]), event: .speechEnd)
        let secondTail = gate.process(frame: Data([3, 3]), event: nil)
        let afterTail = gate.process(frame: Data([4, 4]), event: nil)

        XCTAssertEqual(firstTail, [Data([0, 0])])
        XCTAssertEqual(secondTail, [Data([0, 0])])
        XCTAssertEqual(afterTail, [])
    }
}
