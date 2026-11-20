import Foundation

/// Support for the Slots.swift integration suite: sandbox, fake processes, assertions.
struct TestFailure: Error {
  let message: String
  let file: String
  let line: UInt
}

func expect(_ condition: @autoclosure () -> Bool, _ what: String, file: String = #fileID, line: UInt = #line) throws {
  if !condition() { throw TestFailure(message: what, file: file, line: line) }
}

func expectEqual<Value: Equatable>(_ actual: Value, _ expected: Value, _ what: String, file: String = #fileID, line: UInt = #line) throws {
  if actual != expected {
    throw TestFailure(message: "\(what): expected \(expected), got \(actual)", file: file, line: line)
  }
}

/// The error of a call that must throw a `SlotError`: any other error passes through.
func slotError(_ body: () throws -> Void, file: String = #fileID, line: UInt = #line) throws -> SlotError {
  do {
    try body()
  } catch let error as SlotError {
    return error
  }
  throw TestFailure(message: "expected a SlotError, none thrown", file: file, line: line)
}

/// The slot of a take that must succeed: a `nil` is a failed case, not a runner crash.
func takenSlot(_ ledger: FileSlots, name: String, presence: Presence, file: String = #fileID, line: UInt = #line) throws -> Slot {
  guard let slot = try ledger.takeSlot(name: name, presence: presence, capacity: Int.max) else {
    throw TestFailure(message: "taking a slot for \(name) should have given a slot, got nil", file: file, line: line)
  }
  return slot
}

/// A temporary folder per case, with the child processes the case started.
final class Sandbox {
  let root: String
  let dir: String
  private var children: [Process] = []

  init() throws {
    root = NSTemporaryDirectory() + "test-edgeping-slots-" + UUID().uuidString
    dir = root + "/edgeping"
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
  }

  func ledger(pid: Int32 = getpid()) -> FileSlots {
    FileSlots(directory: dir, pid: pid)
  }

  /// Names of the slot files present, sorted; the lock and the log are not slots.
  func files() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: dir)
      .filter { $0 != "lock" && $0 != "outcomes.log" }
      .sorted()
  }

  func content(_ file: String) throws -> String {
    try String(contentsOfFile: dir + "/" + file, encoding: .utf8)
  }

  func mode(_ path: String) throws -> Int {
    Int(truncating: try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as! NSNumber) & 0o777
  }

  func writeFile(_ file: String, _ text: String) throws {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try text.write(toFile: dir + "/" + file, atomically: false, encoding: .utf8)
  }

  func setWritable(_ writable: Bool) throws {
    try FileManager.default.setAttributes([.posixPermissions: writable ? 0o700 : 0o500], ofItemAtPath: dir)
  }

  /// A live process posing as another window's panel: the binary name is the real one.
  func spawnAlive() throws -> Process {
    // The binary lives in its own folder: `dir` already uses the name edgeping.
    try FileManager.default.createDirectory(atPath: root + "/bin", withIntermediateDirectories: true)
    let copy = root + "/bin/edgeping"
    if !FileManager.default.fileExists(atPath: copy) {
      try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: copy)
      // macOS kills a copy of a system binary that keeps its original signature.
      let signer = Process()
      signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
      signer.arguments = ["--force", "-s", "-", copy]
      signer.standardError = FileHandle.nullDevice
      try signer.run()
      signer.waitUntilExit()
      if signer.terminationStatus != 0 { throw TestFailure(message: "codesign of the edgeping copy failed", file: #fileID, line: #line) }
    }
    return try spawn(copy)
  }

  /// A live process that is not a panel: its pid can only have been reused.
  func spawnForeign() throws -> Process {
    try spawn("/bin/sleep")
  }

  private func spawn(_ executable: String) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["60"]
    try process.run()
    children.append(process)
    return process
  }

  /// The pid of a process that has already terminated and been reaped.
  func deadPid() throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()
    return process.processIdentifier
  }

  /// Another process holds `flock` on the lock: macOS has no such command, so python3 calls flock(2).
  func holdLock(seconds: Int) throws {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let script = "import fcntl, sys, time\nf = open(sys.argv[1], 'a')\nfcntl.flock(f, fcntl.LOCK_EX)\n"
      + "print('ready', flush=True)\ntime.sleep(float(sys.argv[2]))"
    let holder = Process()
    holder.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    holder.arguments = ["-I", "-c", script, dir + "/lock", String(seconds)]
    let pipe = Pipe()
    holder.standardOutput = pipe
    try holder.run()
    children.append(holder)
    let line = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)
    if line != "ready\n" { throw TestFailure(message: "the process holding the lock did not start", file: #fileID, line: #line) }
  }

  /// Waits for an observable condition, never a fixed time.
  func waitUntil(timeoutSeconds: Double = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while !condition() {
      if Date() >= deadline { return false }
      usleep(10_000)
    }
    return true
  }

  func killChildren() {
    for child in children where child.isRunning { child.terminate() }
    for child in children { child.waitUntilExit() }
  }

  func cleanUp() {
    try? setWritable(true)
    killChildren()
    try? FileManager.default.removeItem(atPath: root)
  }
}

struct TestCase {
  let name: String
  let body: (Sandbox) throws -> Void
}

func run(_ cases: [TestCase]) -> Int32 {
  var passed = 0
  var failed = 0
  for testCase in cases {
    let sandbox: Sandbox
    do { sandbox = try Sandbox() } catch {
      print("FAILED  \(testCase.name): temporary folder not created (\(error))")
      failed += 1
      continue
    }
    do {
      try testCase.body(sandbox)
      print("ok      \(testCase.name)")
      passed += 1
    } catch let failure as TestFailure {
      print("FAILED  \(testCase.name): \(failure.message) (\(failure.file) line \(failure.line))")
      failed += 1
    } catch {
      print("FAILED  \(testCase.name): unexpected error \(error)")
      failed += 1
    }
    sandbox.cleanUp()
  }
  print("PASSED: \(passed) FAILED: \(failed)")
  return failed == 0 ? 0 : 1
}
