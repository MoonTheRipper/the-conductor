import Foundation

final class DebugEventFeed: @unchecked Sendable {
    static let shared = DebugEventFeed()

    private let formatter: DateFormatter
    private let enabled: Bool
    private let lock = NSLock()

    private init() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        self.enabled = arguments.contains("--debug-feed") || environment["THE_CONDUCTOR_DEBUG_FEED"] == "1"
        self.formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
    }

    func log(_ category: String, _ message: String) {
        guard enabled else { return }

        lock.lock()
        defer { lock.unlock() }

        let line = "[\(formatter.string(from: Date()))] [\(category)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
