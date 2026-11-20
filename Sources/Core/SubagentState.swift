import Foundation

/// Subagent count left by the last `done` event of each session, one decimal number per file.
struct SubagentState {
  let directory: String

  /// nil when the session gives no safe file name, the file is missing, or it holds anything but digits.
  func read(sessionID: String?) -> Int? {
    guard let path = path(sessionID), let content = try? String(contentsOfFile: path, encoding: .utf8)
    else { return nil }
    let digits = content.trimmingCharacters(in: .newlines)
    return isDecimalDigits(digits) ? Int(digits) : nil
  }

  // Best-effort: an unwritten count reads as unknown at the next event.
  func write(_ count: Int, sessionID: String?) {
    guard let path = path(sessionID) else { return }
    try? FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    _ = FileManager.default.createFile(
      atPath: path, contents: Data("\(count)\n".utf8), attributes: [.posixPermissions: 0o600])
  }

  // The session_id ends up in a file name: only safe characters, never "." or "..".
  private func path(_ sessionID: String?) -> String? {
    let safe = String((sessionID ?? "").unicodeScalars.filter(isSafeInFileName))
    guard !safe.isEmpty, safe != ".", safe != ".." else { return nil }
    return directory + "/" + safe
  }
}

private func isSafeInFileName(_ scalar: Unicode.Scalar) -> Bool {
  ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    || scalar == "." || scalar == "_" || scalar == "-"
}
