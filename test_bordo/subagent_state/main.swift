// Integration check of SubagentState on the real file system.
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

// Each case gets its own temporary root, never the real state folder; the state lives in `root/subagents`.
func withSandbox(_ body: (_ root: String, _ state: SubagentState) -> Void) {
  let root = NSTemporaryDirectory() + "test_subagent_state-\(UUID().uuidString)"
  try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(atPath: root) }
  body(root, SubagentState(directory: root + "/subagents"))
}

func names(_ path: String) -> [String] {
  ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
}

func plant(_ root: String, _ file: String, _ content: String) {
  let dir = root + "/subagents"
  try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  try? content.write(toFile: dir + "/" + file, atomically: false, encoding: .utf8)
}

withSandbox { _, state in
  state.write(2, sessionID: "s1")
  expectEqual("the written count reads back unchanged", state.read(sessionID: "s1"), 2)
}

withSandbox { _, state in
  state.write(0, sessionID: "s1")
  expectEqual("zero reads back as zero, not as absent", state.read(sessionID: "s1"), 0)
}

withSandbox { _, state in
  state.write(1, sessionID: "s1")
  state.write(3, sessionID: "s1")
  expectEqual("a second write replaces the first", state.read(sessionID: "s1"), 3)
}

withSandbox { _, state in
  state.write(1, sessionID: "a")
  state.write(2, sessionID: "b")
  expectEqual("sessions have separate counts", [state.read(sessionID: "a"), state.read(sessionID: "b")], [1, 2])
}

withSandbox { _, state in
  expectEqual("file absent and folder absent: absent", state.read(sessionID: "s1"), nil)
}

withSandbox { root, state in
  plant(root, "other", "1\n")
  expectEqual("file absent with folder present: absent", state.read(sessionID: "s1"), nil)
}

for (label, content) in [("text", "abc\n"), ("with minus sign", "-1\n"), ("with plus sign", "+1\n"),
                         ("digits and text", "1a\n"), ("two numbers", "1 2\n"), ("decimal", "1.5\n")] {
  withSandbox { root, state in
    plant(root, "s1", content)
    expectEqual("content \(label): absent", state.read(sessionID: "s1"), nil)
  }
}

for id in ["", ".", ".."] {
  withSandbox { root, state in
    state.write(1, sessionID: id)
    expectEqual("session_id \"\(id)\": no file and no folder created", names(root), [])
  }
}

withSandbox { root, state in
  state.write(1, sessionID: nil)
  expectEqual("session_id absent: no file", names(root), [])
}

withSandbox { root, state in
  plant(root, "s1", "1\n")
  expectEqual("a read with session_id \"..\" does not leave the folder", state.read(sessionID: ".."), nil)
}

withSandbox { root, state in
  state.write(1, sessionID: "../x")
  expectEqual("../x: outside the state folder nothing is created", names(root), ["subagents"])
  expectEqual("../x: inside the folder one file is created", names(root + "/subagents").count, 1)
}

withSandbox { _, state in
  state.write(4, sessionID: "../x")
  expectEqual("../x: the count reads back with the same session_id", state.read(sessionID: "../x"), 4)
}

withSandbox { root, _ in
  // A regular file where the folder should be: creation cannot succeed.
  let blocked = root + "/subagents"
  try? "not a folder".write(toFile: blocked, atomically: false, encoding: .utf8)
  SubagentState(directory: blocked).write(1, sessionID: "s1")
  let content = try? String(contentsOfFile: blocked, encoding: .utf8)
  expectEqual("folder not creatable: the write gives no error and leaves what is there untouched", content, "not a folder")
  expectEqual("folder not creatable: the read gives absent", SubagentState(directory: blocked).read(sessionID: "s1"), nil)
}

print("PASSED: \(passed) FAILED: \(failed)")
exit(failed == 0 ? 0 : 1)
