import Foundation

enum ProbeLog {
    private static let queue = DispatchQueue(label: "com.hnl1.cursorquota.probe")
    private static let path = "/tmp/cursor-quota-keychain.log"

    static func write(_ message: String, stack: Bool = false) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let main = Thread.isMainThread
        let symbols = stack ? Thread.callStackSymbols : []
        queue.sync {
            let stamp = ISO8601DateFormatter().string(from: Date())
            var text = "\(stamp) pid=\(pid) main=\(main) \(message)\n"
            if !symbols.isEmpty {
                text += symbols.joined(separator: "\n") + "\n"
            }
            text += "\n"
            if let data = text.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: path),
                    let handle = FileHandle(forWritingAtPath: path)
                {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    FileManager.default.createFile(atPath: path, contents: data)
                }
            }
        }
    }
}
