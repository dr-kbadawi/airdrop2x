import Foundation

public enum Log {
    public static var verbose = false
    /// When set, every line is appended here as well as written to stdout.
    public static var filePath: String? {
        didSet { fileHandle = nil }
    }
    private static var fileHandle: FileHandle?
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static func debug(_ message: @autoclosure () -> String) { if verbose { write("DEBUG", message()) } }
    public static func info(_ message: String)  { write("INFO ", message) }
    public static func warn(_ message: String)  { write("WARN ", message) }
    public static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        lock.lock(); defer { lock.unlock() }
        let data = line.data(using: .utf8)!
        FileHandle.standardOutput.write(data)
        if let path = filePath {
            if fileHandle == nil {
                if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
                fileHandle = FileHandle(forWritingAtPath: path)
                fileHandle?.seekToEndOfFile()
            }
            fileHandle?.write(data)
        }
    }
}

public func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024, unit < units.count - 1 { value /= 1024; unit += 1 }
    return unit == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[unit])
}

public func errnoString(_ code: Int32 = errno) -> String {
    String(cString: strerror(code))
}
