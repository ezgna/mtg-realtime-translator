import Foundation

public struct APIKeyLoader {
    public static let defaultPath = "~/.keys/openai/mtg-realtime-translator/.env"

    private let path: String
    private let fileManager: FileManager

    public init(path: String = APIKeyLoader.defaultPath, fileManager: FileManager = .default) {
        self.path = path
        self.fileManager = fileManager
    }

    public func load() throws -> String {
        let resolvedPath = (path as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: resolvedPath) else {
            throw APIKeyError.fileNotFound(resolvedPath)
        }

        let text = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }
            guard let equalIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<equalIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "OPENAI_API_KEY" else {
                continue
            }
            let rawValue = line[line.index(after: equalIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else {
                throw APIKeyError.emptyValue(resolvedPath)
            }
            return value
        }

        throw APIKeyError.missingKey(resolvedPath)
    }
}

public enum APIKeyError: LocalizedError, Equatable {
    case fileNotFound(String)
    case missingKey(String)
    case emptyValue(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            "OpenAI API key file not found: \(path)"
        case .missingKey(let path):
            "OPENAI_API_KEY was not found in \(path)"
        case .emptyValue(let path):
            "OPENAI_API_KEY is empty in \(path)"
        }
    }
}
