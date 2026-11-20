import Foundation

// Best-effort log: if a line cannot be written, the alert carries on anyway.
struct OutcomeLog {
  private static let maxBytes: off_t = 64 * 1024
  let directory: String
  /// Ties together the lines of the processes of the same event; nil for an alert launched by hand.
  let event: EventID?

  func write(_ outcome: Outcome, name: String? = nil, cwd: String? = nil, fields: String? = nil) {
    try? FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let path = directory + "/outcomes.log"
    var info = stat()
    if stat(path, &info) == 0 && info.st_size > Self.maxBytes { truncate(path, 0) }
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    var line = formatter.string(from: Date()) + " outcome=" + outcome.rawValue
    if let event { line += " event=" + event.text }
    if let name { line += " name=" + name }
    if let cwd { line += " cwd=" + cwd }
    if let fields { line += " " + fields }
    let bytes = Array((line + "\n").utf8)
    let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    guard descriptor >= 0 else { return }
    _ = bytes.withUnsafeBufferPointer { Darwin.write(descriptor, $0.baseAddress, $0.count) }
    close(descriptor)
  }
}
