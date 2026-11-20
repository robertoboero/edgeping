import Foundation

// Unit tests of classify, VisitTracker and ClosureTracker.

func runClassifyTests() {
  test("classify: a failed list read is unreadable") {
    expectEqual(classify(WindowLookup(listReadOK: false, listCount: 5, windowSpaces: [2])), .unreadable)
  }
  test("classify: an empty list is unreadable, never a closure") {
    expectEqual(classify(WindowLookup(listReadOK: true, listCount: 0, windowSpaces: nil)), .unreadable)
  }
  test("classify: a window with no spaces is unreadable") {
    expectEqual(classify(WindowLookup(listReadOK: true, listCount: 3, windowSpaces: [])), .unreadable)
  }
  test("classify: a window missing from a non-empty list is absent") {
    expectEqual(classify(WindowLookup(listReadOK: true, listCount: 3, windowSpaces: nil)), .absent)
  }
  test("classify: a window with spaces is present with those spaces") {
    expectEqual(classify(WindowLookup(listReadOK: true, listCount: 3, windowSpaces: [4, 7])), .present([4, 7]))
  }
}

func runStayReadTests() {
  let found = WindowLookup(listReadOK: true, listCount: 3, windowSpaces: [4])
  let absent = WindowLookup(listReadOK: true, listCount: 3, windowSpaces: nil)
  let failed = WindowLookup(listReadOK: false, listCount: 0, windowSpaces: nil)
  let twoDisplays = Spaces(order: [1, 2], current: 1, displayCount: 2)
  let oneDisplay = Spaces(order: [1, 2], current: 1, displayCount: 1)
  test("stayRead: with more than one display every window is unreadable") {
    for lookup in [found, absent, failed] {
      expectEqual(stayRead(spaces: twoDisplays, lookup: lookup), .unreadable)
    }
  }
  test("stayRead: with one display the read is classify's") {
    for lookup in [found, absent, failed] {
      expectEqual(stayRead(spaces: oneDisplay, lookup: lookup), classify(lookup))
    }
  }
  test("stayRead: spaces that could not be read fall back to classify") {
    expectEqual(stayRead(spaces: nil, lookup: found), classify(found))
  }
}

func runVisitTrackerTests() {
  let arrival = 100.0
  test("visit threshold: just below the dwell is not a visit") {
    var tracker = VisitTracker()
    tracker.arrived(at: arrival)
    expect(!tracker.isVisited(at: arrival + visitDwellSeconds - 0.25), "visited below the threshold")
  }
  test("visit threshold: exactly the dwell is a visit") {
    var tracker = VisitTracker()
    tracker.arrived(at: arrival)
    expect(tracker.isVisited(at: arrival + visitDwellSeconds), "not visited at the threshold")
  }
  test("visit threshold: just above the dwell is a visit") {
    var tracker = VisitTracker()
    tracker.arrived(at: arrival)
    expect(tracker.isVisited(at: arrival + visitDwellSeconds + 0.25), "not visited above the threshold")
  }
  // The requirement fixes the value by hand: a wrong constant turns this red.
  test("visit dwell is 1.0 seconds") {
    expectEqual(visitDwellSeconds, 1.0)
  }
  test("a visitor who never arrived has not visited") {
    expect(!VisitTracker().isVisited(at: 1000), "visited without arriving")
  }
  test("leaving cancels the dwell however long ago the arrival was") {
    var tracker = VisitTracker()
    tracker.arrived(at: arrival)
    tracker.left()
    expect(!tracker.isVisited(at: arrival + 10 * visitDwellSeconds), "visited after leaving")
  }
}

func runClosureTrackerTests() {
  test("closure: absent, present, absent is not a closure") {
    var tracker = ClosureTracker()
    expectEqual(tracker.record(.absent, from: .poll), nil, "first absent")
    expectEqual(tracker.record(.present([2]), from: .poll), nil, "present")
    expectEqual(tracker.record(.absent, from: .poll), nil, "second absent")
  }
  test("closure: an unreadable read between two absences resets the count") {
    var tracker = ClosureTracker()
    _ = tracker.record(.absent, from: .poll)
    expectEqual(tracker.record(.unreadable, from: .poll), nil, "unreadable")
    expectEqual(tracker.record(.absent, from: .poll), nil, "absent after unreadable")
  }
  test("closure: one absence alone is not a closure") {
    var tracker = ClosureTracker()
    expectEqual(tracker.record(.absent, from: .spaceChange), nil)
  }
  test("closure: two consecutive absences report the source of the second") {
    var tracker = ClosureTracker()
    _ = tracker.record(.absent, from: .poll)
    expectEqual(tracker.record(.absent, from: .spaceChange), .spaceChange)
  }
  test("closure: the source is the completing read, not the first one") {
    var tracker = ClosureTracker()
    _ = tracker.record(.absent, from: .spaceChange)
    expectEqual(tracker.record(.absent, from: .poll), .poll)
  }
}
