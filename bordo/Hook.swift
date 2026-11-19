import Foundation

/// Event identifier `<t0>-<pid>` of the hook mode. The only place that writes and reads it.
struct EventID: Equatable {
  /// Start of the hook mode on the system monotonic clock, the same for every process.
  let startNanoseconds: UInt64
  let pid: Int32

  init(startNanoseconds: UInt64, pid: Int32) {
    self.startNanoseconds = startNanoseconds
    self.pid = pid
  }

  /// nil for any other shape: a caller receiving it as an argument treats it as `invalid-arguments`.
  init?(text: String) {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, parts.allSatisfy(isDecimalDigits),
      let start = UInt64(parts[0]), let pid = Int32(parts[1]), pid > 0
    else { return nil }
    self.init(startNanoseconds: start, pid: pid)
  }

  var text: String { "\(startNanoseconds)-\(pid)" }
}

func isDecimalDigits<Text: StringProtocol>(_ text: Text) -> Bool {
  !text.isEmpty && text.allSatisfy { $0 >= "0" && $0 <= "9" }
}

/// What the hook mode does for an event.
struct Decision: Equatable {
  let plays: Bool
  /// `cwd` to pass to the alert mode; nil: no alert is started.
  let alertCwd: String?
  /// Only for `done` with `background_tasks` present: the count to leave to the session.
  let countToSave: Int?
}

/// The event count wins, then the saved one, then 0; it plays only at 0.
func decide(mode: Mode, input: HookInput, savedCount: Int?) -> Decision {
  let plays = (input.runningSubagents ?? savedCount ?? 0) == 0
  return Decision(
    plays: plays, alertCwd: plays ? input.cwd : nil,
    countToSave: mode == .done ? input.runningSubagents : nil)
}
