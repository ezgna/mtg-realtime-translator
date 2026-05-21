import Foundation
import XCTest
@testable import RealtimeTranslatorCore

final class AudioFormatTests: XCTestCase {
    func testPCM16RoundTripKeepsSampleCount() {
        let samples: [Float] = [-1.0, -0.5, 0.0, 0.5, 1.0]
        let data = AudioFormat.pcm16Data(fromFloatSamples: samples)
        let decoded = AudioFormat.floatSamples(fromPCM16: data)

        XCTAssertEqual(decoded.count, samples.count)
        XCTAssertEqual(decoded[0], -1.0, accuracy: 0.001)
        XCTAssertEqual(decoded[1], -0.5, accuracy: 0.001)
        XCTAssertEqual(decoded[2], 0.0, accuracy: 0.001)
        XCTAssertEqual(decoded[3], 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded[4], 1.0, accuracy: 0.001)
    }

    func testPCM16DataUsesLittleEndianSampleBytes() {
        let data = AudioFormat.pcm16Data(fromFloatSamples: [1.0, 0.0])

        XCTAssertEqual(Array(data), [0xff, 0x7f, 0x00, 0x00])
    }
}
