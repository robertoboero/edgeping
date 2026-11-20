// Unit test of parseHookInput, decide and EventID (HookInput.swift, Hook.swift), without AppKit.
import Foundation

var passed = 0
var failed = 0

func report(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
  if ok {
    passed += 1
    print("PASS \(name)")
  } else {
    failed += 1
    print("FAIL \(name) \(detail())")
  }
}

func expectEqual<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
  report(name, actual == expected, "expected \(expected) got \(actual)")
}

/// The expected failure is a `Failure` with the given code; any other outcome is red.
func expectFailure<T>(_ name: String, _ outcome: Outcome, _ body: () throws -> T) {
  do {
    let value = try body()
    report(name, false, "expected \(outcome.rawValue), no error (got \(value))")
  } catch let failure as Failure {
    report(name, failure.outcome == outcome, "expected \(outcome.rawValue) got \(failure.outcome.rawValue)")
  } catch {
    report(name, false, "expected \(outcome.rawValue), unexpected error \(error)")
  }
}

// MARK: parseHookInput

func parse(_ text: String) throws -> HookInput { try parseHookInput(Data(text.utf8)) }

/// Only one field matters: the others stay absent, so each test states one rule.
func subagents(_ tasks: String) -> Int? {
  (try? parse("{\"background_tasks\": \(tasks)}"))?.runningSubagents
}

expectFailure("empty input: invalid-input", .invalidInput) { try parseHookInput(Data()) }
expectFailure("non-JSON text: invalid-input", .invalidInput) { try parse("not json") }
expectFailure("empty array: invalid-input", .invalidInput) { try parse("[]") }
expectFailure("JSON string: invalid-input", .invalidInput) { try parse("\"x\"") }
expectFailure("JSON number: invalid-input", .invalidInput) { try parse("3") }
expectFailure("JSON null: invalid-input", .invalidInput) { try parse("null") }

expectEqual("empty object is valid with every field absent", try? parse("{}"),
  HookInput(sessionID: nil, runningSubagents: nil, cwd: nil))
expectEqual("session_id and cwd, when present, are read", try? parse("{\"session_id\":\"s1\",\"cwd\":\"/tmp\"}"),
  HookInput(sessionID: "s1", runningSubagents: nil, cwd: "/tmp"))
expectEqual("empty cwd counts as absent", (try? parse("{\"cwd\":\"\"}"))?.cwd, nil)

expectEqual("background_tasks absent: count absent", (try? parse("{}"))?.runningSubagents, nil)
expectEqual("background_tasks object, not a list: count absent", subagents("{}"), nil)
expectEqual("background_tasks string, not a list: count absent", subagents("\"x\""), nil)
expectEqual("background_tasks null: count absent", subagents("null"), nil)
expectEqual("background_tasks empty list: count 0", subagents("[]"), 0)
expectEqual("running of type agent counts", subagents("[{\"status\":\"running\",\"type\":\"agent\"}]"), 1)
expectEqual("running of type shell does not count", subagents("[{\"status\":\"running\",\"type\":\"shell\"}]"), 0)
expectEqual("running without type counts", subagents("[{\"status\":\"running\"}]"), 1)
expectEqual("any other status does not count", subagents("[{\"status\":\"completed\",\"type\":\"agent\"}]"), 0)
expectEqual("missing status does not count", subagents("[{\"type\":\"agent\"}]"), 0)
expectEqual("entry that is not an object does not count", subagents("[\"running\", 3]"), 0)
expectEqual("the count sums only the entries that count",
  subagents("[{\"status\":\"running\"},{\"status\":\"running\",\"type\":\"agent\"},{\"status\":\"running\",\"type\":\"shell\"}]"), 2)

// MARK: decide

func input(_ running: Int?, cwd: String? = "/tmp/p") -> HookInput {
  HookInput(sessionID: nil, runningSubagents: running, cwd: cwd)
}

expectEqual("a running non-shell subagent: no sound and no alert",
  decide(mode: .done, input: input(1), savedCount: nil), Decision(plays: false, alertCwd: nil, countToSave: 1))
expectEqual("only shells running (count 0): plays",
  decide(mode: .done, input: input(0), savedCount: nil).plays, true)
expectEqual("count absent: the saved one applies, running, does not play",
  decide(mode: .done, input: input(nil), savedCount: 2).plays, false)
expectEqual("count absent: the saved 0 applies, plays",
  decide(mode: .done, input: input(nil), savedCount: 0).plays, true)
expectEqual("count and saved both absent: plays",
  decide(mode: .done, input: input(nil), savedCount: nil).plays, true)
expectEqual("the event count wins over the saved one",
  decide(mode: .done, input: input(0), savedCount: 3).plays, true)
expectEqual("alertCwd is set when it plays and cwd exists",
  decide(mode: .done, input: input(0), savedCount: nil).alertCwd, "/tmp/p")
expectEqual("alertCwd is nil when it plays but cwd is missing",
  decide(mode: .done, input: input(0, cwd: nil), savedCount: nil).alertCwd, nil)
expectEqual("alertCwd is nil when it does not play, even with cwd",
  decide(mode: .done, input: input(1), savedCount: nil).alertCwd, nil)
expectEqual("countToSave for done with count 0",
  decide(mode: .done, input: input(0), savedCount: nil).countToSave, 0)
expectEqual("countToSave for done with count above 0",
  decide(mode: .done, input: input(4), savedCount: nil).countToSave, 4)
expectEqual("countToSave is nil for done without a count",
  decide(mode: .done, input: input(nil), savedCount: 2).countToSave, nil)
expectEqual("countToSave is nil for question even with a count",
  decide(mode: .question, input: input(2), savedCount: nil).countToSave, nil)
expectEqual("question without subagents plays with an alert",
  decide(mode: .question, input: input(0), savedCount: nil), Decision(plays: true, alertCwd: "/tmp/p", countToSave: nil))

// MARK: EventID

let sample = EventID(startNanoseconds: 123_456_789_012, pid: 4242)
expectEqual("text round-trips", EventID(text: sample.text), sample)
expectEqual("text has the form <t0>-<pid>", sample.text, "123456789012-4242")
expectEqual("round trip at the minimum values", EventID(text: EventID(startNanoseconds: 0, pid: 1).text),
  EventID(startNanoseconds: 0, pid: 1))
expectEqual("round trip at the maximum values",
  EventID(text: EventID(startNanoseconds: UInt64.max, pid: Int32.max).text),
  EventID(startNanoseconds: UInt64.max, pid: Int32.max))
for rejected in ["abc", "1-", "-1", "1-2-3", "1-0", "+1-2", " 1-2"] {
  expectEqual("EventID rejects \"\(rejected)\"", EventID(text: rejected), nil)
}

print("PASSED: \(passed) FAILED: \(failed)")
exit(failed == 0 ? 0 : 1)
