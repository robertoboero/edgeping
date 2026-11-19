import Foundation

enum Side: String {
  case left = "left"
  case right = "right"
}

enum Mode: String {
  case done = "done"
  case question = "question"
}

struct RGBColor: Equatable {
  let red: UInt8
  let green: UInt8
  let blue: UInt8
}

// Fixed values on purpose: no configuration.
func color(for mode: Mode) -> RGBColor {
  switch mode {
  case .done: return RGBColor(red: 0xD9, green: 0x77, blue: 0x57)
  case .question: return RGBColor(red: 0x00, green: 0x7A, blue: 0xFF)
  }
}

enum Presence: Equatable {
  case side(Side)
  case hidden
}

/// Stable log codes: changing a raw value breaks whoever reads outcomes.log.
enum Outcome: String {
  case ok
  case invalidArguments = "invalid-arguments"
  case probeFailed = "probe-failed"
  case emptyTitles = "empty-titles"
  case windowNotFound = "window-not-found"
  case ambiguousWindow = "ambiguous-window"
  case multipleDisplays = "multiple-displays"
  case currentSpace = "current-space"
  case slotsContended = "slots-contended"
  case slotsUnavailable = "slots-unavailable"
  case focusTaken = "focus-taken"
  case invalidInput = "invalid-input"
  case launchFailed = "launch-failed"
  case soundOK = "sound-ok"
  case soundFailed = "sound-failed"
  case optionInvalid = "option-invalid"
  case slotsFull = "slots-full"
  case windowGone = "window-gone"
}

struct Failure: Error, Equatable {
  let outcome: Outcome
}

struct Spaces: Equatable {
  let order: [Int]
  let current: Int
  let displayCount: Int
}

struct CodeWindow: Equatable {
  let id: Int
  let title: String
  let spaces: [Int]
}

struct Reading {
  let spaces: Spaces
  let windows: [CodeWindow]
}

struct Rereading {
  let spaces: Spaces
  let windowSpaces: [Int]
}

struct ChosenWindow: Equatable {
  let window: CodeWindow
  let name: String
}

struct Slot: Equatable {
  let presence: Presence
  let number: Int
}

enum Action: Equatable {
  case moveSlot(Presence)
  case show(Side)
  case hide
}

/// The macOS calls do not answer, or answer in an unexpected shape.
struct ProbeError: Error {}

enum SlotError: Error {
  case contended
  case unavailable
  /// The own slot file is missing or does not carry the own pid: the reservation is no longer certain.
  case uncertain
  /// No free number below the side's capacity; hidden slots never count.
  case full
}

protocol SpaceProbe {
  func read() throws -> Reading
  /// Spaces, and the spaces of the already recognised window, without matching by title again.
  func reread(window: Int) throws -> Rereading
}

protocol SlotLedger {
  /// Always drops the previous alert of the same window; reserves a slot only when the presence is a side.
  func takeSlot(name: String, presence: Presence, capacity: Int) throws -> Slot?
  /// Creates the new slot before removing the old one: if creation fails, the old one stays.
  func moveSlot(_ slot: Slot, to presence: Presence, name: String, capacity: Int) throws -> Slot
  func releaseSlot(_ slot: Slot)
}

/// Names to compare with titles: from the project root down to HOME (excluded), or down to "/" (excluded) outside HOME.
func candidateNames(cwd: String, home: String) -> [String] {
  let homeParts = segments(home)
  let root = projectRoot(segments(cwd), home: homeParts)
  let first = startsWith(root, prefix: homeParts) ? homeParts.count : 0
  return root[first...].map(String.init)
}

// A worktree counts as its project only when the root is strictly under HOME: never HOME itself.
private func projectRoot(_ parts: [Substring], home: [Substring]) -> [Substring] {
  for i in parts.indices {
    let opensWorktree = (parts[i] == ".worktrees" && i + 1 < parts.count)
      || (parts[i] == ".claude" && i + 2 < parts.count && parts[i + 1] == "worktrees")
    let root = Array(parts[..<i])
    if opensWorktree && root.count > home.count && startsWith(root, prefix: home) { return root }
  }
  return parts
}

private func segments(_ path: String) -> [Substring] {
  path.split(separator: "/")
}

private func startsWith(_ parts: [Substring], prefix: [Substring]) -> Bool {
  parts.count >= prefix.count && Array(parts.prefix(prefix.count)) == prefix
}

/// VS Code puts the opened folder after the last " — " of the title.
func windowName(_ title: String) -> String {
  guard let separator = title.range(of: " — ", options: .backwards) else { return title }
  return String(title[separator.upperBound...])
}

/// Accepts a single window: several matches are an ambiguity, never a choice by depth.
func chooseWindow(_ windows: [CodeWindow], candidates: [String]) throws -> ChosenWindow {
  if !windows.isEmpty && windows.allSatisfy({ $0.title.isEmpty }) {
    throw Failure(outcome: .emptyTitles)
  }
  let names = Set(candidates)
  let matches = windows.filter { names.contains(windowName($0.title)) }
  if matches.count > 1 { throw Failure(outcome: .ambiguousWindow) }
  guard let window = matches.first else { throw Failure(outcome: .windowNotFound) }
  return ChosenWindow(window: window, name: windowName(window.title))
}

func computePresence(_ spaces: Spaces, windowSpaces: [Int]) throws -> Presence {
  if spaces.displayCount > 1 { throw Failure(outcome: .multipleDisplays) }
  if windowSpaces.contains(spaces.current) { return .hidden }
  // A window with no space in the order is closed or unreadable: there is no real side to show.
  guard let current = spaces.order.firstIndex(of: spaces.current),
    let window = windowSpaces.compactMap({ spaces.order.firstIndex(of: $0) }).first
  else { throw Failure(outcome: .probeFailed) }
  return .side(window < current ? .left : .right)
}

/// Compares the desired presence with the owned slot and the visible panel, never with the last presence.
func reconcile(desired: Presence, slot: Presence, panel: Side?) -> [Action] {
  var actions: [Action] = []
  if slot != desired { actions.append(.moveSlot(desired)) }
  switch desired {
  case .side(let side) where panel != side: actions.append(.show(side))
  case .hidden where panel != nil: actions.append(.hide)
  default: break
  }
  return actions
}

let visitDwellSeconds: Double = 1.0
let windowCheckSeconds: Double = 5

/// Raw result of one window lookup, as the macOS adapter returns it.
struct WindowLookup {
  let listReadOK: Bool
  let listCount: Int
  /// nil when the window id is not among the VS Code windows.
  let windowSpaces: [Int]?
}

enum WindowRead: Equatable {
  case present([Int])
  case absent
  case unreadable
}

/// An empty or failed list, or a window with no space, is never a closure.
func classify(_ lookup: WindowLookup) -> WindowRead {
  guard lookup.listReadOK, lookup.listCount > 0 else { return .unreadable }
  guard let spaces = lookup.windowSpaces else { return .absent }
  return spaces.isEmpty ? .unreadable : .present(spaces)
}

/// Raw values are the `via=` field of the outcome log.
enum ReadSource: String {
  case poll
  case spaceChange = "space-change"
}

struct ClosureTracker {
  private(set) var consecutiveAbsent = 0
  /// Returns the source that completed two consecutive successful absences.
  mutating func record(_ read: WindowRead, from source: ReadSource) -> ReadSource? {
    guard read == .absent else {
      consecutiveAbsent = 0
      return nil
    }
    consecutiveAbsent += 1
    return consecutiveAbsent >= 2 ? source : nil
  }
}

struct VisitTracker {
  private(set) var arrivedAt: Double?
  mutating func arrived(at time: Double) { arrivedAt = time }
  mutating func left() { arrivedAt = nil }
  func isVisited(at time: Double) -> Bool {
    guard let start = arrivedAt else { return false }
    return time - start >= visitDwellSeconds
  }
}

/// Slots from the centre downwards whose label stays fully on screen.
func slotCapacity(screenHeight: Double, labelHeight: Double, slotStep: Double) -> Int {
  guard screenHeight >= labelHeight, slotStep > 0 else { return 0 }
  return Int(((screenHeight - labelHeight) / 2 / slotStep).rounded(.down)) + 1
}
