import Foundation
import OSLog

final class DiagnosticLog: @unchecked Sendable {
    // Keep the legacy directory so upgrades retain diagnostic history.
    static let shared = DiagnosticLog(directory: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/BarTuck", isDirectory: true))
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("diagnostic.jsonl") }
    private let queue = DispatchQueue(label: "com.bartuck.diagnostics")
    private let maximumBytes: Int
    private let logger = Logger(subsystem: "com.bartuck.app", category: "diagnostics")

    init(directory: URL, maximumBytes: Int = 1_048_576) {
        self.directory = directory
        self.maximumBytes = maximumBytes
    }

    // Call sites use fixed event names and numeric diagnostics only. No
    // window titles, application names, images or user content are recorded.
    func record(_ event: String, _ fields: [String: Int] = [:]) {
        let entry: [String: Any] = ["time": Date().ISO8601Format(), "event": String(event.prefix(100)),
                                    "pid": Int(getpid()), "fields": fields]
        guard var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              data.count < maximumBytes else { return }
        data.append(0x0a)
        let line = data
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
                if size + line.count > maximumBytes {
                    let previous = directory.appendingPathComponent("diagnostic.previous.jsonl")
                    if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                    try FileManager.default.moveItem(at: fileURL, to: previous)
                }
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    FileManager.default.createFile(atPath: fileURL.path, contents: nil,
                                                  attributes: [.posixPermissions: 0o600])
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                logger.error("Diagnostic log write failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func flush() { queue.sync {} }
}
