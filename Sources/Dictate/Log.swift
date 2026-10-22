import Foundation

private let formatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    return f
}()

/// Writes to stderr, which the LaunchAgent sends to ~/Library/Logs/Dictate.log.
/// Never log transcript text.
func log(_ message: String) {
    FileHandle.standardError.write(Data("[\(formatter.string(from: Date()))] \(message)\n".utf8))
}
