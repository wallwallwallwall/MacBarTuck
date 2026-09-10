import Foundation

@main
enum DiagnosticLogTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticLogTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory, maximumBytes: 512)
        for number in 0..<30 { log.record("refresh.test", ["transaction": number]) }
        log.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard files.count == 2 else { throw NSError(domain: "DiagnosticLog", code: 1) }
        for file in files {
            let data = try Data(contentsOf: file)
            guard data.count <= 512, !data.isEmpty else { throw NSError(domain: "DiagnosticLog", code: 2) }
            for line in data.split(separator: 0x0a) {
                let entry = try JSONSerialization.jsonObject(with: Data(line)) as! [String: Any]
                guard entry["event"] as? String == "refresh.test", entry["fields"] is [String: Int] else {
                    throw NSError(domain: "DiagnosticLog", code: 3)
                }
            }
        }
        let current = String(decoding: try Data(contentsOf: log.fileURL), as: UTF8.self)
        guard current.contains("\"transaction\":29") else { throw NSError(domain: "DiagnosticLog", code: 4) }
        print("DiagnosticLogTests: rotation, JSON records, bounds and latest event passed")
    }
}
