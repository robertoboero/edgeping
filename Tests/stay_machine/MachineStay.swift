import Foundation

// Component tests: StayMachine through the visit, error recovery, replacement and full-side paths.

func runMachineVisitTests() {
  test("a dwell shorter than the threshold is not a visit") {
    var machine = makeMachine()
    _ = machine.handle(notification(present(), current: onWindow, at: 10))
    let actions = machine.handle(dwellElapsed(present(), current: onWindow, at: 10 + visitDwellSeconds - 0.25))
    expectEqual(endings([actions]), [])
  }
  test("a dwell of the threshold on the window screen ends with a visit") {
    var machine = makeMachine()
    _ = machine.handle(notification(present(), current: onWindow, at: 10))
    let actions = machine.handle(dwellElapsed(present(), current: onWindow, at: 10 + visitDwellSeconds))
    expectEqual(actions, [.end(.visited)])
  }
  test("a dwell that elapses with the user elsewhere is not a visit") {
    var machine = makeMachine(initial: .side(.right))
    _ = machine.handle(notification(present(), current: onWindow, at: 10))
    let actions = machine.handle(dwellElapsed(present(), current: leftOfWindow, at: 12))
    expectEqual(endings([actions]), [])
  }
}

func runMachineRecoveryTests() {
  /// Shown strip, user arrives on the window screen, the dwell expires with a failed read.
  func machineAfterFailedDwell() -> (StayMachine, [[StayAction]]) {
    var machine = makeMachine(initial: .side(.right))
    let steps = feed(&machine, [
      notification(present(), current: onWindow, at: 10),
      dwellElapsed(.unreadable, current: nil, at: 11),
    ])
    return (machine, steps)
  }

  test("f: arrival hides the strip and starts the dwell") {
    var machine = makeMachine(initial: .side(.right))
    expectEqual(machine.handle(notification(present(), current: onWindow, at: 10)), [.hidePanel, .startDwell])
  }
  test("f: a failed read at dwell expiry is no visit and no closure, and is logged") {
    let (_, steps) = machineAfterFailedDwell()
    expectEqual(steps[1], [.logProbeFailedOnce])
  }
  test("f: after the failure a successful poll with the user on the window starts a new dwell") {
    var (machine, _) = machineAfterFailedDwell()
    expectEqual(machine.handle(tick(present(), current: onWindow, at: 15)), [.startDwell])
  }
  test("f: the chain ends with a visit, and the strip never comes back") {
    var (machine, steps) = machineAfterFailedDwell()
    steps += feed(&machine, [
      tick(present(), current: onWindow, at: 15),
      dwellElapsed(present(), current: onWindow, at: 15 + visitDwellSeconds),
    ])
    expectEqual(endings(steps), [.visited])
    expectEqual(steps.flatMap { $0 }.filter { if case .showPanel = $0 { return true } else { return false } }.count, 0, "show actions")
  }
  test("f variant: a successful poll that finds the user elsewhere brings the strip back on the right side") {
    var (machine, _) = machineAfterFailedDwell()
    let actions = machine.handle(tick(present(), current: leftOfWindow, at: 15))
    expectEqual(actions, [.hidePanel, .moveSlot(.side(.right))])
    expectEqual(machine.handle(.placement(succeeded: true, side: .right)), [.showPanel(.right)])
  }
  test("f variant: a failed poll with no decision pending changes nothing visible") {
    var machine = makeMachine(initial: .side(.right))
    let steps = feed(&machine, [
      notification(present(), current: leftOfWindow),
      .placement(succeeded: true, side: .right),
      tick(.unreadable, current: nil),
    ])
    let poll = steps[2]
    expect(!poll.contains(.hidePanel) && !poll.contains(.cancelDwell) && endings([poll]).isEmpty, "the poll touched the strip: \(poll)")
  }
  test("f variant: a failed poll resets the absence count, so the next absence is the first") {
    var machine = makeMachine()
    let steps = feed(&machine, [
      tick(.absent, current: onWindow),
      tick(.unreadable, current: nil),
      tick(.absent, current: onWindow),
    ])
    expectEqual(endings(steps), [])
  }
  test("f variant: a failed notification recovers on the next successful poll, without another notification") {
    var machine = makeMachine(initial: .side(.left))
    let steps = feed(&machine, [
      notification(.unreadable, current: nil),
      tick(present(), current: rightOfWindow, at: 5),
    ])
    expectEqual(steps[0], [.hidePanel, .logProbeFailedOnce], "the failed notification hides the strip")
    expectEqual(steps[1], [.hidePanel, .moveSlot(.side(.left))], "the poll places it")
  }
  test("f variant: without the poll, the next successful notification is the recovery") {
    var machine = makeMachine(initial: .side(.left), stayUntilVisited: false)
    _ = machine.handle(notification(.unreadable, current: nil))
    expectEqual(machine.handle(notification(present(), current: rightOfWindow)), [.hidePanel, .moveSlot(.side(.left))])
  }
}

func runMachineReplacementTests() {
  test("g: a lost slot hides the strip and ends as replaced") {
    var machine = makeMachine(initial: .side(.right))
    expectEqual(machine.handle(.slotLost), [.hidePanel, .end(.replaced)])
  }
  test("g: after being replaced the machine is silent") {
    var machine = makeMachine(initial: .side(.right))
    _ = machine.handle(.slotLost)
    expectEqual(feed(&machine, [notification(present(), current: leftOfWindow), tick(present(), current: onWindow)]), [[], []])
  }
  test("g: an alert launched while the user is on the window shows no strip") {
    var machine = makeMachine(initial: .hidden, stayUntilVisited: false)
    expectEqual(machine.handle(notification(present(), current: onWindow)), [])
  }
}

func runMachineFullSideTests() {
  /// The strip was on the left, the user swipes so that the window is now on the right, which is full.
  func machineWaiting() -> (StayMachine, [StayAction]) {
    var machine = makeMachine(initial: .side(.left))
    _ = machine.handle(notification(present(), current: leftOfWindow))
    let refused = machine.handle(.placement(succeeded: false, side: .right))
    return (machine, refused)
  }

  test("i: the move starts by hiding the old strip and asking for the new side") {
    var machine = makeMachine(initial: .side(.left))
    expectEqual(machine.handle(notification(present(), current: leftOfWindow)), [.hidePanel, .moveSlot(.side(.right))])
  }
  test("i: a refused move waits hidden and logs slots-full once") {
    let (_, refused) = machineWaiting()
    expectEqual(refused, [.moveSlotWaiting, .logSlotsFullOnMove])
  }
  test("i: a poll while the side is still full retries without showing or logging again") {
    var (machine, _) = machineWaiting()
    var steps = [machine.handle(tick(present(), current: leftOfWindow, at: 5))]
    steps.append(machine.handle(.placement(succeeded: false, side: .right)))
    expectEqual(steps[0], [.moveSlot(.side(.right))], "retry")
    expectEqual(steps[1], [], "second refusal")
  }
  test("i: a poll with the user on the window schedules no retry") {
    var (machine, _) = machineWaiting()
    expectEqual(machine.handle(tick(present(), current: onWindow, at: 5)), [])
  }
  test("i: when a slot frees up the poll places the strip on the right with a show") {
    var (machine, _) = machineWaiting()
    let retry = machine.handle(tick(present(), current: leftOfWindow, at: 5))
    expectEqual(retry, [.moveSlot(.side(.right))])
    expectEqual(machine.handle(.placement(succeeded: true, side: .right)), [.showPanel(.right)])
  }
  test("i: once shown, a poll no longer retries") {
    var (machine, _) = machineWaiting()
    _ = machine.handle(tick(present(), current: leftOfWindow, at: 5))
    _ = machine.handle(.placement(succeeded: true, side: .right))
    expectEqual(machine.handle(tick(present(), current: leftOfWindow, at: 10)), [])
  }
  test("i: a placement answer for a side that was not asked for is ignored") {
    var machine = makeMachine(initial: .side(.left))
    _ = machine.handle(notification(present(), current: leftOfWindow))
    expectEqual(machine.handle(.placement(succeeded: true, side: .left)), [])
  }
  test("i: the waiting entry ends with the machine when the window is gone") {
    var (machine, _) = machineWaiting()
    let steps = feed(&machine, [tick(.absent, current: leftOfWindow), tick(.absent, current: leftOfWindow)])
    expectEqual(endings(steps), [.gone(.poll)])
  }
}
