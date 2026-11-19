import Foundation

/// The only event fields the program reads.
struct HookInput: Equatable {
  let sessionID: String?
  /// Non-shell subagents still running; nil when the event does not carry `background_tasks` as a list.
  let runningSubagents: Int?
  let cwd: String?
}

func readHookInput() throws -> HookInput {
  try parseHookInput(FileHandle.standardInput.readDataToEndOfFile())
}

/// The only point that sees the raw JSON: empty, non-JSON or non-object input is `invalid-input`.
func parseHookInput(_ data: Data) throws -> HookInput {
  guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
    throw Failure(outcome: .invalidInput)
  }
  let cwd = object["cwd"] as? String
  return HookInput(
    sessionID: object["session_id"] as? String,
    runningSubagents: (object["background_tasks"] as? [Any]).map(countRunningNonShell),
    cwd: cwd?.isEmpty == false ? cwd : nil)
}

// A missing `type` is not "shell", so the entry counts as non-shell.
private func countRunningNonShell(_ tasks: [Any]) -> Int {
  tasks.filter { task in
    guard let entry = task as? [String: Any] else { return false }
    return entry["status"] as? String == "running" && entry["type"] as? String != "shell"
  }.count
}
