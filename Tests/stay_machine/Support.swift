import Foundation

var passed = 0
var failed = 0
private var currentFailures: [String] = []

/// Runs one case; any failed expectation inside it makes the case red.
func test(_ name: String, _ body: () -> Void) {
  currentFailures = []
  body()
  if currentFailures.isEmpty {
    passed += 1
    print("PASS \(name)")
  } else {
    failed += 1
    print("FAIL \(name) \(currentFailures.joined(separator: "; "))")
  }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String = "value") {
  if actual != expected { currentFailures.append("\(what): expected \(expected) got \(actual)") }
}

func expect(_ condition: Bool, _ what: String) {
  if !condition { currentFailures.append(what) }
}

/// The window lives on space 2 of the order [1, 2, 3]: current 2 is on it, 1 is left of it, 3 is right of it.
let order = [1, 2, 3]
let windowSpace = 2
let onWindow = 2
let leftOfWindow = 1
let rightOfWindow = 3

func present(_ spaces: [Int] = [windowSpace]) -> WindowRead { .present(spaces) }

func notification(_ read: WindowRead, current: Int?, at: Double = 0) -> StayEvent {
  .notification(read: read, current: current, order: order, at: at)
}

func dwellElapsed(_ read: WindowRead, current: Int?, at: Double) -> StayEvent {
  .dwellElapsed(read: read, current: current, order: order, at: at)
}

func tick(_ read: WindowRead, current: Int?, at: Double = 0) -> StayEvent {
  .tick(read: read, current: current, order: order, at: at)
}

func makeMachine(initial: Presence = .hidden, stayUntilVisited: Bool = true) -> StayMachine {
  StayMachine(initial: initial, stayUntilVisited: stayUntilVisited)
}

/// Feeds the events in order and returns the actions of each one.
func feed(_ machine: inout StayMachine, _ events: [StayEvent]) -> [[StayAction]] {
  events.map { machine.handle($0) }
}

func endings(_ actions: [[StayAction]]) -> [StayEnd] {
  actions.flatMap { $0 }.compactMap { action in
    if case .end(let end) = action { return end }
    return nil
  }
}

func count(_ action: StayAction, in actions: [[StayAction]]) -> Int {
  actions.flatMap { $0 }.filter { $0 == action }.count
}
