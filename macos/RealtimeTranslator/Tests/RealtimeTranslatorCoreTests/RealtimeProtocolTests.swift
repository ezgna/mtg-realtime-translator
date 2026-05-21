import Foundation
import XCTest
@testable import RealtimeTranslatorCore

final class RealtimeProtocolTests: XCTestCase {
    func testAppendAudioMessageContainsBase64PCM() throws {
        let pcm = Data([0x01, 0x02, 0x03])
        let text = try RealtimeProtocol.appendAudio(pcm)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "session.input_audio_buffer.append")
        XCTAssertEqual(object["audio"] as? String, pcm.base64EncodedString())
    }

    func testParsesTranscriptDelta() {
        let event = RealtimeProtocol.parseEvent(#"{"type":"response.output_audio_transcript.delta","delta":"Hello"}"#)
        XCTAssertEqual(event, .transcriptDelta("Hello"))
    }

    func testParsesLegacyTranscriptDelta() {
        let event = RealtimeProtocol.parseEvent(#"{"type":"response.output_text.delta","delta":"Hello"}"#)
        XCTAssertEqual(event, .transcriptDelta("Hello"))
    }

    func testParsesAudioDelta() {
        let pcm = Data([0x01, 0x02, 0x03])
        let event = RealtimeProtocol.parseEvent(
            #"{"type":"response.audio.delta","delta":"\#(pcm.base64EncodedString())"}"#
        )
        XCTAssertEqual(event, .audioDelta(pcm))
    }
}
