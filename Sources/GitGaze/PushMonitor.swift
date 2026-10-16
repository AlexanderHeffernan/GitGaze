import Foundation
import Darwin
import GitGazeCore

/// Git writes datagrams to a user-private socket. No hooks, repository access or raw trace logs.
@MainActor
final class PushMonitor {
    private var source: DispatchSourceRead?
    private var lock: Int32 = -1
    var onPush: (() -> Void)?
    // Stable path: existing opt-in Trace2 configurations must survive app renames.
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("GitBar", isDirectory: true)
    }
    static var socketPath: String { directory.appendingPathComponent("push.sock").path }
    static var target: String { "af_unix:dgram:" + socketPath }

    func start() throws {
        guard source == nil else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.directory.path)
        lock = open(Self.directory.appendingPathComponent("listener.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if lock >= 0 { close(lock); lock = -1 }
            throw LoginError.message("Another GitGaze push listener is already running.")
        }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { stop(); throw LoginError.message("Couldn't create the Git push listener.") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(Self.socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd); stop(); throw LoginError.message("The home directory path is too long for a Git event socket.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in path.withUnsafeBytes { buffer.copyBytes(from: $0) } }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        unlink(Self.socketPath)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { close(fd); stop(); throw LoginError.message("Couldn't bind the Git event socket.") }
        chmod(Self.socketPath, 0o600)
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let reader = PushEventReader(fd: fd) { [weak self] in self?.onPush?() }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "app.gitbar.push-events", qos: .utility))
        source.setEventHandler { @Sendable in reader.read() }
        source.setCancelHandler { @Sendable in close(fd) }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        if lock >= 0 {
            unlink(Self.socketPath)
            flock(lock, LOCK_UN)
            close(lock)
            lock = -1
        }
    }

    /// Changes only our exact config value; an existing tracing setup is never overwritten.
    func configure(_ enabled: Bool) throws {
        let existing = try config(["--get-all", "trace2.eventTarget"], allowMissing: true)
            .split(separator: "\n").map(String.init)
        if enabled {
            guard existing.isEmpty || existing == [Self.target] else {
                throw LoginError.message("Git already has a Trace2 event target. GitGaze left it unchanged.")
            }
            try start()
            do {
                if existing.isEmpty { _ = try config(["--add", "trace2.eventTarget", Self.target]) }
            } catch { stop(); throw error }
        } else {
            if existing.contains(Self.target) {
                _ = try config(["--fixed-value", "--unset-all", "trace2.eventTarget", Self.target])
            }
            stop()
        }
    }

    private func config(_ arguments: [String], allowMissing: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["config", "--global"] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || (allowMissing && process.terminationStatus == 1) else {
            throw LoginError.message("Couldn't update Git's user configuration. Check ~/.gitconfig permissions.")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// All mutable parser state is confined to the serial read queue. Only confirmed hints reach the UI.
private final class PushEventReader: @unchecked Sendable {
    let fd: Int32
    let onPush: @MainActor @Sendable () -> Void
    private var events = PushEvents()
    init(fd: Int32, onPush: @escaping @MainActor @Sendable () -> Void) { self.fd = fd; self.onPush = onPush }
    func read() {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        for _ in 0..<512 {
            let length = recv(fd, &buffer, buffer.count, 0)
            guard length > 0 else { return }
            if events.receive(Data(buffer.prefix(length))) { Task { @MainActor in onPush() } }
        }
    }
}
