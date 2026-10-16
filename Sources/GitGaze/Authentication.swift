import Foundation

/// Reads the CLI's active github.com session into memory. Never signs out, saves, or revokes credentials.
enum Credentials {
    static var cliPath: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func cliToken() async -> String? {
        await Task.detached {
            guard let path = cliPath else { return nil }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                return token.isEmpty ? nil : token
            } catch { return nil }
        }.value
    }
}

enum LoginError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}
