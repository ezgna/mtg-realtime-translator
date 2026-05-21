import Foundation

public enum RealtimeProtocol {
    public static func sessionUpdate(language: String) throws -> String {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "audio": [
                    "input": [
                        "noise_reduction": [
                            "type": "near_field",
                        ],
                    ],
                    "output": [
                        "language": language,
                    ],
                ],
            ],
        ]
        return try encode(payload)
    }

    public static func appendAudio(_ pcm16: Data) throws -> String {
        let payload: [String: Any] = [
            "type": "session.input_audio_buffer.append",
            "audio": pcm16.base64EncodedString(),
        ]
        return try encode(payload)
    }

    public static func parseEvent(_ text: String) -> RealtimeEvent {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .ignored("invalid_json")
        }

        let type = object["type"] as? String ?? ""
        switch type {
        case "session.created":
            return .sessionCreated

        case "session.updated":
            let session = object["session"] as? [String: Any]
            let audio = session?["audio"] as? [String: Any]
            let output = audio?["output"] as? [String: Any]
            return .sessionUpdated(language: output?["language"] as? String)

        case "response.audio.delta", "response.output_audio.delta", "session.output_audio.delta":
            let base64 = (object["delta"] as? String) ?? (object["audio"] as? String) ?? ""
            guard let data = Data(base64Encoded: base64) else {
                return .ignored("invalid_audio_delta")
            }
            return .audioDelta(data)

        case "response.audio_transcript.delta",
             "response.output_audio_transcript.delta",
             "response.output_text.delta",
             "response.text.delta",
             "session.output_transcript.delta",
             "session.output_text.delta":
            return .transcriptDelta(object["delta"] as? String ?? "")

        case "response.audio_transcript.done",
             "response.output_audio_transcript.done",
             "response.output_text.done",
             "response.text.done",
             "session.output_transcript.done",
             "session.output_text.done":
            return .transcriptDone

        case "response.done":
            let response = object["response"] as? [String: Any]
            return .responseDone(status: response?["status"] as? String ?? "completed")

        case "error":
            let error = object["error"] as? [String: Any]
            return .error(error?["message"] as? String ?? "\(object)")

        default:
            return .ignored(type)
        }
    }

    private static func encode(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeProtocolError.encodingFailed
        }
        return text
    }
}

public enum RealtimeEvent: Equatable {
    case sessionCreated
    case sessionUpdated(language: String?)
    case audioDelta(Data)
    case transcriptDelta(String)
    case transcriptDone
    case responseDone(status: String)
    case error(String)
    case ignored(String)
}

public enum RealtimeProtocolError: Error {
    case encodingFailed
}
