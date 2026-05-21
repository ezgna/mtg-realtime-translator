import Foundation

public final class RealtimeClient {
    public var onEvent: ((RealtimeEvent) -> Void)?
    public var onDisconnect: ((Error?) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    deinit {
        disconnect()
    }

    public func connect(apiKey: String, language: String) async throws {
        var request = URLRequest(url: TranslatorConstants.websocketURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
        let sessionUpdate = try RealtimeProtocol.sessionUpdate(language: language)
        setupTask = Task { [weak self] in
            do {
                try await self?.sendText(sessionUpdate)
            } catch {
                self?.onDisconnect?(error)
            }
        }
    }

    public func updateLanguage(_ language: String) async throws {
        try await sendText(RealtimeProtocol.sessionUpdate(language: language))
    }

    public func sendAudio(_ pcm16: Data) async throws {
        try await sendText(RealtimeProtocol.appendAudio(pcm16))
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        setupTask?.cancel()
        setupTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func sendText(_ text: String) async throws {
        guard let task else {
            throw RealtimeClientError.notConnected
        }
        try await task.send(.string(text))
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let task else {
                return
            }
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    onEvent?(RealtimeProtocol.parseEvent(text))
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        onEvent?(RealtimeProtocol.parseEvent(text))
                    } else {
                        onEvent?(.ignored("binary_message"))
                    }
                @unknown default:
                    onEvent?(.ignored("unknown_message"))
                }
            } catch {
                if !Task.isCancelled {
                    onDisconnect?(error)
                }
                return
            }
        }
    }
}

public enum RealtimeClientError: LocalizedError {
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "Realtime WebSocket is not connected"
        }
    }
}
