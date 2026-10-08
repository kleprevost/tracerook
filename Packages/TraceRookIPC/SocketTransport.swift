import Darwin
import Foundation

public enum SocketTransport {
    public static func descriptor() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.transport }
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { close(fd); throw IPCError.transport }
        var enabled: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else { close(fd); throw IPCError.transport }
        return fd
    }
    public static func address<T>(_ path: String, body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        let bytes = Array(path.utf8)
        guard !bytes.contains(0), bytes.count < 104 else { throw IPCError.unsafeEndpoint }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            target.initializeMemory(as: UInt8.self, repeating: 0); target.copyBytes(from: bytes)
        }
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
    private static func ready(_ fd: Int32, events: Int16, deadline: ContinuousClock.Instant) throws {
        while ContinuousClock().now < deadline {
            var item = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&item, 1, 100)
            if result < 0 && errno != EINTR { throw IPCError.transport }
            if item.revents & (Int16(POLLERR) | Int16(POLLNVAL)) != 0 { throw IPCError.transport }
            if item.revents & events != 0 { return }
            if item.revents & Int16(POLLHUP) != 0 { throw IPCError.transport }
        }
        throw IPCError.timeout
    }
    public static func read(_ fd: Int32, count: Int, deadline: ContinuousClock.Instant) throws -> Data {
        guard count > 0, count <= 1_048_576 else { throw IPCError.transport }
        var buffer = [UInt8](repeating: 0, count: count), offset = 0
        while offset < count {
            try ready(fd, events: Int16(POLLIN), deadline: deadline)
            let result = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress!.advanced(by: offset), count - offset, 0) }
            if result < 0 && [EINTR, EAGAIN].contains(errno) { continue }
            guard result > 0 else { throw IPCError.transport }; offset += result
        }
        return Data(buffer)
    }
    public static func readFrame(_ fd: Int32, maximum: Int, deadline: ContinuousClock.Instant) throws -> Data {
        let prefix = try read(fd, count: 4, deadline: deadline)
        let count = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, count <= maximum else { throw IPCError.transport }
        return prefix + (try read(fd, count: Int(count), deadline: deadline))
    }
    public static func write(_ fd: Int32, data: Data, deadline: ContinuousClock.Instant) throws {
        guard !data.isEmpty, data.count <= 1_048_580 else { throw IPCError.transport }
        var offset = 0
        while offset < data.count {
            try ready(fd, events: Int16(POLLOUT), deadline: deadline)
            let count = data.withUnsafeBytes { send(fd, $0.baseAddress!.advanced(by: offset), data.count - offset, 0) }
            if count < 0 && [EINTR, EAGAIN].contains(errno) { continue }
            guard count > 0 else { throw IPCError.transport }; offset += count
        }
    }
    public static func exchange(path: String, frame: Data, peer: PeerIdentity, deadline: ContinuousClock.Instant) throws -> Data {
        let fd = try descriptor(); defer { close(fd) }
        let result = try address(path) { connect(fd, $0, $1) }
        if result != 0 {
            guard errno == EINPROGRESS else { throw IPCError.transport }
            try ready(fd, events: Int16(POLLOUT), deadline: deadline)
            var error: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw IPCError.transport }
        }
        try peer.verifySocket(fd)
        try write(fd, data: frame, deadline: deadline)
        return try readFrame(fd, maximum: 16_384, deadline: deadline)
    }
}

public final class HookSocketServer: @unchecked Sendable {
    private let fd: Int32
    private let path: String
    private let source: DispatchSourceRead
    private let peer: PeerIdentity
    private let handler: @Sendable (Data) async throws -> Data
    private let lock = NSLock()
    private var active: Set<Int32> = []
    public init(path: String, peer: PeerIdentity, handler: @escaping @Sendable (Data) async throws -> Data) throws {
        self.path = path; self.peer = peer; self.handler = handler
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard existing.st_mode & S_IFMT == S_IFSOCK, existing.st_uid == geteuid() else { throw IPCError.unsafeEndpoint }
            // Caller holds the single-writer lock before removing a stale socket.
            guard unlink(path) == 0 else { throw IPCError.unsafeEndpoint }
        } else if errno != ENOENT { throw IPCError.unsafeEndpoint }
        let listenerFD = try SocketTransport.descriptor()
        fd = listenerFD
        do {
            guard try SocketTransport.address(path, body: { bind(listenerFD, $0, $1) }) == 0,
                  chmod(path, 0o600) == 0, listen(fd, 16) == 0 else { throw IPCError.transport }
        } catch { close(fd); unlink(path); throw error }
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in self?.acceptAvailable() }
        source.resume()
    }
    deinit { source.cancel(); close(fd); unlink(path) }
    private func acceptAvailable() {
        while true {
            let socket = accept(fd, nil, nil)
            if socket < 0 { return }
            let admitted = lock.withLock { if active.count >= 32 { return false }; active.insert(socket); return true }
            guard admitted else { close(socket); continue }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    guard fcntl(socket, F_SETFD, FD_CLOEXEC) == 0, fcntl(socket, F_SETFL, O_NONBLOCK) == 0 else { throw IPCError.transport }
                    var flag: Int32 = 1
                    guard setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &flag, socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw IPCError.transport }
                    try peer.verifySocket(socket)
                    let frame = try SocketTransport.readFrame(socket, maximum: 1_048_576, deadline: ContinuousClock().now.advanced(by: .seconds(3)))
                    let job = Task { try await handler(frame) }
                    let monitor = Task {
                        while !Task.isCancelled {
                            var status = pollfd(fd: socket, events: 0, revents: 0)
                            if poll(&status, 1, 0) > 0 && status.revents & (Int16(POLLHUP) | Int16(POLLERR)) != 0 { job.cancel(); return }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
                    Task {
                        defer { monitor.cancel(); finish(socket) }
                        guard let reply = try? await job.value else { return }
                        try? SocketTransport.write(socket, data: reply, deadline: ContinuousClock().now.advanced(by: .seconds(1)))
                    }
                } catch { finish(socket) }
            }
        }
    }
    private func finish(_ socket: Int32) { lock.withLock { _ = active.remove(socket); close(socket) } }
}
