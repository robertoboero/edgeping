// Unit test of the pure logic of Placement.swift, without AppKit.
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

func expectSameNames(_ name: String, _ actual: [String], _ expected: [String]) {
  report(name, actual.sorted() == expected.sorted(), "expected \(expected.sorted()) got \(actual.sorted())")
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

let home = "/Users/test"

// MARK: project root and candidate names

func names(_ cwd: String) -> [String] { candidateNames(cwd: cwd, home: home) }

expectSameNames("worktree .worktrees/<slug> counts as its project", names("\(home)/project-a/.worktrees/x"), ["project-a"])
expectSameNames("worktree .worktrees/<slug> with a subfolder: slug and subfolder are never candidates", names("\(home)/project-a/.worktrees/x/src"), ["project-a"])
expectSameNames("worktree .claude/worktrees/<slug> of another project: the project is the candidate, never .claude", names("\(home)/project-a/.claude/worktrees/x"), ["project-a"])
expectSameNames("ancestor folders down to HOME (excluded) are candidates", names("\(home)/Dev/WebApps/project-a/.worktrees/x"), ["Dev", "WebApps", "project-a"])
expectSameNames("subfolder of a project: the names down to HOME (excluded)", names("\(home)/project-b/src/lib"), ["project-b", "src", "lib"])
expectSameNames("$HOME/.claude/worktrees/x: the root would be HOME, the worktree model does not apply, cwd stays as is", names("\(home)/.claude/worktrees/x"), [".claude", "worktrees", "x"])
expectSameNames("$HOME/.claude/.claude/worktrees/x: root is $HOME/.claude", names("\(home)/.claude/.claude/worktrees/x"), [".claude"])
expectSameNames("HOME root with .worktrees/x: the worktree model does not apply, cwd stays as is", names("\(home)/.worktrees/x"), [".worktrees", "x"])
expectSameNames(".worktrees without <slug>: the worktree model does not apply", names("\(home)/p/.worktrees"), ["p", ".worktrees"])
expectSameNames(".claude/worktrees without <slug>: the worktree model does not apply", names("\(home)/p/.claude/worktrees"), ["p", ".claude", "worktrees"])
expectSameNames("cwd outside HOME: the climb ends at the filesystem root, excluded", names("/tmp/no-window"), ["no-window", "tmp"])
expectSameNames("the worktree model outside HOME does not apply", names("/tmp/p/.worktrees/x"), ["tmp", "p", ".worktrees", "x"])
expectSameNames("cwd equal to HOME: no candidates", names(home), [])

// MARK: window name from the title

expectEqual("the name is the part after the last spaced em dash", windowName("Placement.swift — project-c"), "project-c")
expectEqual("several em dashes: the last one counts", windowName("a — b — project-a"), "project-a")
expectEqual("without an em dash: the whole title", windowName("project-b"), "project-b")
expectEqual("the short hyphen does not separate", windowName("a - b"), "a - b")
expectEqual("empty title: empty name", windowName(""), "")

// MARK: window choice

func win(_ id: Int, _ title: String) -> CodeWindow { CodeWindow(id: id, title: title, spaces: [id]) }

let a = win(1, "main.ts — project-a")
let b = win(2, "README.md — project-b")
let c = win(3, "settings.json — project-c")
let dev = win(4, "Dev")

do {
  let chosen = try chooseWindow([a, b, c], candidates: ["project-b"])
  expectEqual("a single matching window is chosen, with id and name", chosen, ChosenWindow(window: b, name: "project-b"))
} catch {
  report("a single matching window is chosen, with id and name", false, "error \(error)")
}
expectFailure("no window matches: window-not-found", .windowNotFound) {
  try chooseWindow([a, b], candidates: ["no-window", "tmp"])
}
expectFailure("no window open: window-not-found", .windowNotFound) {
  try chooseWindow([], candidates: ["project-b"])
}
expectFailure("no candidate: window-not-found", .windowNotFound) {
  try chooseWindow([a, b], candidates: [])
}
expectFailure("the name must match in full, not by prefix", .windowNotFound) {
  try chooseWindow([a], candidates: ["project"])
}
expectFailure("two windows with the same name: ambiguous-window", .ambiguousWindow) {
  try chooseWindow([a, win(9, "other.ts — project-a")], candidates: ["project-a"])
}
expectFailure("candidates of different levels pointing at different windows: ambiguous-window", .ambiguousWindow) {
  try chooseWindow([a, dev], candidates: ["Dev", "project-a"])
}
do {
  let chosen = try chooseWindow([a, b], candidates: ["Dev", "project-a"])
  expectEqual("two candidates, a single window: no ambiguity", chosen.window, a)
} catch {
  report("two candidates, a single window: no ambiguity", false, "error \(error)")
}
do {
  let chosen = try chooseWindow([win(5, "project-b")], candidates: ["project-b"])
  expectEqual("title without an em dash: the name is the whole title", chosen.name, "project-b")
} catch {
  report("title without an em dash: the name is the whole title", false, "error \(error)")
}
expectFailure("windows present but every title empty: empty-titles", .emptyTitles) {
  try chooseWindow([win(1, ""), win(2, "")], candidates: ["project-b"])
}
do {
  let chosen = try chooseWindow([win(1, ""), b], candidates: ["project-b"])
  expectEqual("a single empty title among others: not empty-titles", chosen.window, b)
} catch {
  report("a single empty title among others: not empty-titles", false, "error \(error)")
}

// MARK: presence

// Test order: desk, project-c, project-a, project-b.
let desk = 1, cSpace = 143, aSpace = 251, bSpace = 323
let order = [desk, cSpace, aSpace, bSpace]

func presence(current: Int, window: [Int], displays: Int = 1) throws -> Presence {
  try computePresence(Spaces(order: order, current: current, displayCount: displays), windowSpaces: window)
}

func expectPresence(_ name: String, current: Int, window: [Int], _ expected: Presence) {
  do {
    expectEqual(name, try presence(current: current, window: window), expected)
  } catch {
    report(name, false, "error \(error)")
  }
}

expectPresence("from project-a, alert from project-c: left side", current: aSpace, window: [cSpace], .side(.left))
expectPresence("from project-a, alert from project-b: right side", current: aSpace, window: [bSpace], .side(.right))
expectPresence("from project-b, alert from project-c (two spaces before): still left", current: bSpace, window: [cSpace], .side(.left))
expectPresence("at any distance to the right: from the desk, alert from project-b", current: desk, window: [bSpace], .side(.right))
expectPresence("at any distance to the left: from project-b, alert from the desk", current: bSpace, window: [desk], .side(.left))
expectPresence("on project-c: alert from project-a on the right", current: cSpace, window: [aSpace], .side(.right))
expectPresence("the window is in the current space, even when arriving there: hidden", current: aSpace, window: [aSpace], .hidden)
expectPresence("then on project-b it reappears on the left", current: bSpace, window: [aSpace], .side(.left))
expectPresence("one of the window spaces is the current one: hidden", current: cSpace, window: [aSpace, cSpace], .hidden)
expectFailure("more than one display: multiple-displays", .multipleDisplays) {
  try presence(current: aSpace, window: [cSpace], displays: 2)
}
expectFailure("more than one display wins even if the window is in the current space", .multipleDisplays) {
  try presence(current: aSpace, window: [aSpace], displays: 2)
}
expectFailure("window with no space at all: probe-failed", .probeFailed) {
  try presence(current: aSpace, window: [])
}
expectFailure("window space missing from the order: probe-failed", .probeFailed) {
  try presence(current: aSpace, window: [9999])
}

// MARK: colors, modes, codes

expectEqual("mode done is the argument \"done\"", Mode(rawValue: "done"), Mode.done)
expectEqual("mode question is the argument \"question\"", Mode(rawValue: "question"), Mode.question)
expectEqual("an unknown argument is not a mode", Mode(rawValue: "other"), nil)
expectEqual("the left side is called \"left\" (name of the slot files)", Side.left.rawValue, "left")
expectEqual("the right side is called \"right\" (name of the slot files)", Side.right.rawValue, "right")

let stableCodes: [(Outcome, String)] = [
  (.ok, "ok"), (.invalidArguments, "invalid-arguments"), (.probeFailed, "probe-failed"),
  (.emptyTitles, "empty-titles"), (.windowNotFound, "window-not-found"), (.ambiguousWindow, "ambiguous-window"),
  (.multipleDisplays, "multiple-displays"), (.currentSpace, "current-space"), (.slotsContended, "slots-contended"),
  (.slotsUnavailable, "slots-unavailable"), (.focusTaken, "focus-taken"),
  (.invalidInput, "invalid-input"), (.launchFailed, "launch-failed"),
  (.soundOK, "sound-ok"), (.soundFailed, "sound-failed"),
]
for (outcome, code) in stableCodes {
  expectEqual("the log code \"\(code)\" is stable", outcome.rawValue, code)
}

// MARK: contrast of the colors with black text

func linear(_ channel: UInt8) -> Double {
  let value = Double(channel) / 255
  return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
}

func luminance(_ color: RGBColor) -> Double {
  0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
}

func contrastWithBlack(_ color: RGBColor) -> Double {
  (luminance(color) + 0.05) / 0.05
}

let wcagThreshold = 4.5

expectEqual("the formula: black on white is 21:1", (contrastWithBlack(RGBColor(red: 255, green: 255, blue: 255)) * 100).rounded() / 100, 21.0)
report("default orange with black text above 4.5:1", contrastWithBlack(Settings().color(for: .done)) > wcagThreshold, "got \(contrastWithBlack(Settings().color(for: .done)))")
report("system blue with black text above 4.5:1", contrastWithBlack(Settings().color(for: .question)) > wcagThreshold, "got \(contrastWithBlack(Settings().color(for: .question)))")
report("default orange: declared ratio about 6.7:1", abs(contrastWithBlack(Settings().color(for: .done)) - 6.7) < 0.1, "got \(contrastWithBlack(Settings().color(for: .done)))")
report("system blue: declared ratio about 5.2:1", abs(contrastWithBlack(Settings().color(for: .question)) - 5.2) < 0.1, "got \(contrastWithBlack(Settings().color(for: .question)))")

// One test pins the required values by hand: a changed constant turns red.
expectEqual("done is #D97757", Settings().color(for: .done), RGBColor(red: 0xD9, green: 0x77, blue: 0x57))
expectEqual("question is #007AFF", Settings().color(for: .question), RGBColor(red: 0x00, green: 0x7A, blue: 0xFF))

// MARK: slot capacity

// Same values as the panel's private constants; the pinned case below fixes the requirement by hand.
let capacityLabel = 28.0
let capacityStep = 36.0
func capacity(_ height: Double) -> Int {
  slotCapacity(screenHeight: height, labelHeight: capacityLabel, slotStep: capacityStep)
}

expectEqual("capacity: a 900 pt screen holds 13 slots", slotCapacity(screenHeight: 900, labelHeight: 28, slotStep: 36), 13)

// The 13th slot appears once the 12th step below the centre still has the whole label on screen.
let thirteenthSlotHeight = capacityLabel + 2 * capacityStep * 12
expectEqual("capacity: just below the height of the 13th slot gives 12", capacity(thirteenthSlotHeight - 0.1), 12)
expectEqual("capacity: exactly the height of the 13th slot gives 13", capacity(thirteenthSlotHeight), 13)
expectEqual("capacity: just above the height of the 13th slot still gives 13", capacity(thirteenthSlotHeight + 0.1), 13)

// A screen as tall as the label holds the centre slot only; a shorter one holds none.
expectEqual("capacity: a screen just shorter than the label holds none", capacity(capacityLabel - 0.1), 0)
expectEqual("capacity: a screen exactly as tall as the label holds one", capacity(capacityLabel), 1)
expectEqual("capacity: a screen just taller than the label still holds one", capacity(capacityLabel + 0.1), 1)

expectEqual("capacity: a zero step holds none", slotCapacity(screenHeight: 900, labelHeight: capacityLabel, slotStep: 0), 0)
expectEqual("capacity: a negative step holds none", slotCapacity(screenHeight: 900, labelHeight: capacityLabel, slotStep: -36), 0)

print("PASSED: \(passed) FAILED: \(failed)")
exit(failed == 0 ? 0 : 1)
