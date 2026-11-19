// Behaviour test of CGSProbe: it must see a window whose owner is the VS Code process name.
// The test binary re-launches itself under the name `Code` and opens a real window.
import AppKit
import Foundation

let hostFlag = "--window-host"
let hostSeconds: TimeInterval = 6
let waitSeconds: TimeInterval = 5

if CommandLine.arguments.contains(hostFlag) {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled],
    backing: .buffered, defer: false)
  window.title = "test window"
  window.makeKeyAndOrderFront(nil)
  Timer.scheduledTimer(withTimeInterval: hostSeconds, repeats: false) { _ in exit(0) }
  app.run()
}

func windowCount(_ probe: CGSProbe) -> Int {
  (try? probe.read().windows.count) ?? -1
}

guard let probe = try? CGSProbe() else {
  print("FAIL probe creation")
  print("PASSED: 0 FAILED: 1")
  exit(1)
}

let before = windowCount(probe)

let directory = FileManager.default.temporaryDirectory
  .appendingPathComponent("probe-test-\(getpid())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let host = directory.appendingPathComponent("Code")
try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: host)

let process = Process()
process.executableURL = host
process.arguments = [hostFlag]
try process.run()

var seen = false
let deadline = Date().addingTimeInterval(waitSeconds)
while Date() < deadline && !seen {
  usleep(200_000)
  seen = windowCount(probe) > before
}
process.terminate()
process.waitUntilExit()
try? FileManager.default.removeItem(at: directory)

var passed = 0
var failed = 0
if before >= 0 && seen {
  passed += 1
  print("PASS finds the window of a process named Code")
} else {
  failed += 1
  print("FAIL finds the window of a process named Code (before=\(before))")
}
print("PASSED: \(passed) FAILED: \(failed)")
exit(failed == 0 ? 0 : 1)
