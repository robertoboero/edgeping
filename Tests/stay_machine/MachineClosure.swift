import Foundation

// Component tests: StayMachine with ClosureTracker and VisitTracker inside it, events in an order chosen by the test.

private let closed = [StayAction.hidePanel, .end(.gone(.spaceChange))]

func runMachineClosureTests() {
  test("d2: two absences, both from notifications, close via space-change") {
    var machine = makeMachine()
    let steps = feed(&machine, [
      notification(present(), current: leftOfWindow),
      notification(.absent, current: leftOfWindow),
      notification(.absent, current: leftOfWindow),
    ])
    expectEqual(endings(Array(steps.dropLast())), [], "ended too early")
    expectEqual(steps.last, closed)
  }
  test("d2: an absence from the poll then one from a notification closes via space-change") {
    var machine = makeMachine()
    let steps = feed(&machine, [
      tick(.absent, current: onWindow),
      notification(.absent, current: onWindow),
    ])
    expectEqual(endings(steps), [.gone(.spaceChange)])
  }
  test("d2: an absence from a notification then one from the poll closes via poll") {
    var machine = makeMachine()
    let steps = feed(&machine, [
      notification(present(), current: onWindow),
      notification(.absent, current: onWindow),
      tick(.absent, current: onWindow),
    ])
    expectEqual(endings(steps), [.gone(.poll)])
  }
  test("d2: absent, present, absent is no closure") {
    var machine = makeMachine()
    let steps = feed(&machine, [
      tick(.absent, current: onWindow),
      tick(present(), current: onWindow),
      tick(.absent, current: onWindow),
    ])
    expectEqual(endings(steps), [])
  }
  test("d2: a closed machine ignores every later event") {
    var machine = makeMachine()
    _ = feed(&machine, [tick(.absent, current: onWindow), tick(.absent, current: onWindow)])
    expectEqual(feed(&machine, [notification(present(), current: leftOfWindow), tick(present(), current: onWindow)]), [[], []])
  }
  test("e: an unreadable read between two absences prevents the closure") {
    var machine = makeMachine()
    let steps = feed(&machine, [
      tick(.absent, current: onWindow),
      tick(.unreadable, current: onWindow),
      tick(.absent, current: onWindow),
    ])
    expectEqual(endings(steps), [])
  }
  test("e: a single absence is not a closure") {
    var machine = makeMachine()
    expectEqual(endings(feed(&machine, [tick(.absent, current: onWindow)])), [])
  }
  test("e: a single absence on a notification keeps the last known reading and hides nothing") {
    var machine = makeMachine(initial: .hidden)
    let steps = feed(&machine, [
      notification(present(), current: onWindow),
      notification(.absent, current: onWindow),
    ])
    expectEqual(steps[1], [.cancelDwell, .startDwell], "the absence reasons on the last successful read")
  }
  test("e: a probe-failed row is logged once per process however many reads fail") {
    var machine = makeMachine(initial: .side(.left))
    let steps = feed(&machine, [
      notification(.unreadable, current: nil),
      dwellElapsed(.unreadable, current: nil, at: 1),
      notification(.unreadable, current: nil),
      tick(.unreadable, current: nil),
    ])
    expectEqual(count(.logProbeFailedOnce, in: steps), 1)
  }
  test("e: a failed read followed by an empty-list read is still not a closure") {
    var machine = makeMachine()
    let reads = [
      classify(WindowLookup(listReadOK: false, listCount: 0, windowSpaces: nil)),
      classify(WindowLookup(listReadOK: true, listCount: 0, windowSpaces: nil)),
      classify(WindowLookup(listReadOK: true, listCount: 4, windowSpaces: [])),
    ]
    let steps = feed(&machine, reads.map { tick($0, current: onWindow) })
    expectEqual(endings(steps), [])
  }
}
