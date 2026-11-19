import Foundation

// Integration suite of FileSlots (bordo/Slots.swift) on the real file system and real processes.

let right = Presence.side(.right)
let left = Presence.side(.left)

/// A live panel of another window, created through the public API with the fake process's pid.
@discardableResult
func plant(_ box: Sandbox, name: String, presence: Presence) throws -> Process {
  let process = try box.spawnAlive()
  let ledger = box.ledger(pid: process.processIdentifier)
  switch presence {
  case .side:
    _ = try ledger.takeSlot(name: name, presence: presence)
  case .hidden:
    let slot = try takenSlot(ledger, name: name, presence: left)
    _ = try ledger.moveSlot(slot, to: .hidden, name: name)
  }
  return process
}

func isStopped(_ box: Sandbox, _ process: Process) -> Bool {
  box.waitUntil { !process.isRunning }
}

func predecessorCase(_ label: String, _ presence: Presence, _ planted: String) -> TestCase {
  TestCase(name: "the predecessor of the same window \(label) is stopped and its file replaced") { box in
    let predecessor = try plant(box, name: "A", presence: presence)
    try expectEqual(try box.files(), [planted], "files before")

    let slot = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(slot, Slot(presence: right, number: 0), "slot of the new panel")
    try expectEqual(try box.files(), ["right-0"], "files after")
    try expectEqual(try box.content("right-0"), "\(getpid())\nA\n", "content: pid and name on two lines")
    try expect(isStopped(box, predecessor), "the predecessor should have received SIGTERM")
  }
}

func hiddenEntryCase(_ label: String, _ presence: Presence) -> TestCase {
  TestCase(name: "with a hidden presence the predecessor \(label) is removed and no file is created") { box in
    let predecessor = try plant(box, name: "A", presence: presence)

    let slot = try box.ledger().takeSlot(name: "A", presence: .hidden)

    try expect(slot == nil, "no slot for a hidden presence")
    try expectEqual(try box.files(), [], "no files")
    try expect(isStopped(box, predecessor), "the predecessor should have received SIGTERM")
  }
}

let cases: [TestCase] = [
  predecessorCase("on the left side", left, "left-0"),
  predecessorCase("on the right side", right, "right-0"),
  predecessorCase("hidden", .hidden, "hidden-0"),
  hiddenEntryCase("on the left side", left),
  hiddenEntryCase("on the right side", right),
  hiddenEntryCase("hidden", .hidden),

  TestCase(name: "replacing the predecessor leaves the other windows alone") { box in
    let other = try plant(box, name: "B", presence: left)
    try plant(box, name: "A", presence: right)

    _ = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(try box.files(), ["left-0", "right-0"], "files")
    try expect(other.isRunning, "another window's panel must not be stopped")
  },

  TestCase(name: "with a hidden presence no file is created and other windows' panels stay") { box in
    try plant(box, name: "B", presence: right)

    let slot = try box.ledger().takeSlot(name: "A", presence: .hidden)

    try expect(slot == nil, "no slot")
    try expectEqual(try box.files(), ["right-0"], "only B's file")
  },

  TestCase(name: "two windows on the same side take slots 0 and 1") { box in
    try plant(box, name: "B", presence: right)

    let slot = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(slot, Slot(presence: right, number: 1), "slot")
    try expectEqual(try box.files(), ["right-0", "right-1"], "files")
  },

  TestCase(name: "the first free slot fills the gap left by a panel") { box in
    try plant(box, name: "B", presence: right)
    let middle = try box.spawnAlive()
    let slotC = try takenSlot(box.ledger(pid: middle.processIdentifier), name: "C", presence: right)
    try plant(box, name: "D", presence: right)
    box.ledger(pid: middle.processIdentifier).releaseSlot(slotC)
    try expectEqual(try box.files(), ["right-0", "right-2"], "files with the gap")

    let slot = try box.ledger().takeSlot(name: "E", presence: right)

    try expectEqual(slot, Slot(presence: right, number: 1), "slot")
  },

  TestCase(name: "the first free slot is searched on the requested side only") { box in
    try plant(box, name: "B", presence: left)

    let slot = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(slot, Slot(presence: right, number: 0), "slot")
  },

  TestCase(name: "when a panel releases its slot the others do not close up") { box in
    let first = try box.spawnAlive()
    let slotB = try takenSlot(box.ledger(pid: first.processIdentifier), name: "B", presence: right)
    try plant(box, name: "C", presence: right)
    try plant(box, name: "D", presence: right)
    let before = try (box.content("right-1"), box.content("right-2"))

    box.ledger(pid: first.processIdentifier).releaseSlot(slotB)

    try expectEqual(try box.files(), ["right-1", "right-2"], "the numbers stay")
    try expectEqual(try box.content("right-1"), before.0, "content of right-1")
    try expectEqual(try box.content("right-2"), before.1, "content of right-2")
  },

  TestCase(name: "moving a panel leaves the others on the same side in place") { box in
    let mover = try box.spawnAlive()
    let slotB = try takenSlot(box.ledger(pid: mover.processIdentifier), name: "B", presence: right)
    try plant(box, name: "C", presence: right)

    let moved = try box.ledger(pid: mover.processIdentifier).moveSlot(slotB, to: left, name: "B")

    try expectEqual(moved, Slot(presence: left, number: 0), "new slot")
    try expectEqual(try box.files(), ["left-0", "right-1"], "C stays in slot 1")
  },

  TestCase(name: "a move takes the first free slot of the new side and removes the old file") { box in
    try plant(box, name: "B", presence: left)
    let slotA = try takenSlot(box.ledger(), name: "A", presence: right)

    let moved = try box.ledger().moveSlot(slotA, to: left, name: "A")

    try expectEqual(moved, Slot(presence: left, number: 1), "new slot")
    try expectEqual(try box.files(), ["left-0", "left-1"], "files")
    try expectEqual(try box.content("left-1"), "\(getpid())\nA\n", "content of the new file")
  },

  TestCase(name: "a move to hidden keeps a hidden file with the window name") { box in
    let slotA = try takenSlot(box.ledger(), name: "A", presence: right)

    let moved = try box.ledger().moveSlot(slotA, to: .hidden, name: "A")

    try expectEqual(moved, Slot(presence: .hidden, number: 0), "new slot")
    try expectEqual(try box.files(), ["hidden-0"], "files")
    try expectEqual(try box.content("hidden-0"), "\(getpid())\nA\n", "content")
  },

  TestCase(name: "a move with its own file gone gives uncertain and creates nothing") { box in
    let slotA = try takenSlot(box.ledger(), name: "A", presence: right)
    try FileManager.default.removeItem(atPath: box.dir + "/right-0")

    let error = try slotError { _ = try box.ledger().moveSlot(slotA, to: left, name: "A") }

    try expectEqual(error, .uncertain, "error")
    try expectEqual(try box.files(), [], "no new file")
  },

  TestCase(name: "a move with another pid's file gives uncertain and leaves that file") { box in
    try box.writeFile("right-0", "\(getppid())\nA\n")

    let error = try slotError {
      _ = try box.ledger().moveSlot(Slot(presence: right, number: 0), to: left, name: "A")
    }

    try expectEqual(error, .uncertain, "error")
    try expectEqual(try box.files(), ["right-0"], "the other's file stays, no new file")
  },

  TestCase(name: "creating the new file fails: the old file stays intact and the error is unavailable") { box in
    let slotA = try takenSlot(box.ledger(), name: "A", presence: right)
    let before = try box.content("right-0")
    try box.setWritable(false)

    let error = try slotError { _ = try box.ledger().moveSlot(slotA, to: .hidden, name: "A") }

    try expectEqual(error, .unavailable, "error")
    try expectEqual(try box.files(), ["right-0"], "only the old file, no hidden-*")
    try expectEqual(try box.content("right-0"), before, "content of the old file")
  },

  TestCase(name: "after a failed creation and the permission restored the move succeeds with a single file") { box in
    let slotA = try takenSlot(box.ledger(), name: "A", presence: right)
    try box.setWritable(false)
    _ = try slotError { _ = try box.ledger().moveSlot(slotA, to: .hidden, name: "A") }
    try box.setWritable(true)

    let moved = try box.ledger().moveSlot(slotA, to: left, name: "A")

    try expectEqual(moved, Slot(presence: left, number: 0), "new slot")
    try expectEqual(try box.files(), ["left-0"], "a single file")
  },

  TestCase(name: "releasing removes the file of its own pid") { box in
    let slotA = try takenSlot(box.ledger(), name: "A", presence: right)

    box.ledger().releaseSlot(slotA)

    try expectEqual(try box.files(), [], "files")
  },

  TestCase(name: "releasing leaves the file that carries another pid") { box in
    let other = try plant(box, name: "A", presence: right)

    box.ledger().releaseSlot(Slot(presence: right, number: 0))

    try expectEqual(try box.files(), ["right-0"], "files")
    try expectEqual(try box.content("right-0"), "\(other.processIdentifier)\nA\n", "content")
  },

  TestCase(name: "cleanup removes the file of a dead pid and its slot becomes free again") { box in
    try box.writeFile("right-0", "\(try box.deadPid())\nB\n")

    let slot = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(slot, Slot(presence: right, number: 0), "slot")
    try expectEqual(try box.content("right-0"), "\(getpid())\nA\n", "the file is the new one")
  },

  TestCase(name: "cleanup leaves the file of another window's live edgeping") { box in
    try plant(box, name: "B", presence: right)

    let slot = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(slot, Slot(presence: right, number: 1), "slot")
    try expectEqual(try box.files(), ["right-0", "right-1"], "files")
  },

  TestCase(name: "cleanup removes the file of a live pid that is not edgeping and does not stop it") { box in
    let foreign = try box.spawnForeign()
    try box.writeFile("right-0", "\(foreign.processIdentifier)\nB\n")

    let slot = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(slot, Slot(presence: right, number: 0), "slot")
    try expectEqual(try box.content("right-0"), "\(getpid())\nA\n", "the file is the new one")
    try expect(foreign.isRunning, "a foreign process must not be stopped")
  },

  TestCase(name: "a predecessor with a foreign process pid gets no SIGTERM and the slot is taken") { box in
    let foreign = try box.spawnForeign()
    try box.writeFile("right-0", "\(foreign.processIdentifier)\nalpha\n")

    let slot = try box.ledger().takeSlot(name: "alpha", presence: .side(.right))

    try expectEqual(slot, Slot(presence: right, number: 0), "slot")
    try expectEqual(try box.files(), ["right-0"], "files")
    try expectEqual(try box.content("right-0"), "\(getpid())\nalpha\n", "content")
    try expect(foreign.isRunning, "a foreign process must not be stopped")
  },

  TestCase(name: "slot cleanup leaves the outcomes.log log alone") { box in
    try box.writeFile("outcomes.log", "line\n")

    _ = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(try box.content("outcomes.log"), "line\n", "log")
  },

  TestCase(name: "a missing state folder is created") { box in
    let slot = try box.ledger().takeSlot(name: "A", presence: left)

    try expectEqual(slot, Slot(presence: left, number: 0), "slot")
  },

  TestCase(name: "a state folder that cannot be created gives unavailable") { box in
    try FileManager.default.createDirectory(atPath: box.root, withIntermediateDirectories: true)
    try "not a folder".write(toFile: box.dir, atomically: false, encoding: .utf8)

    let error = try slotError { _ = try box.ledger().takeSlot(name: "A", presence: right) }

    try expectEqual(error, .unavailable, "error")
  },

  TestCase(name: "an existing but non-writable folder gives unavailable and leaves the files unchanged") { box in
    try plant(box, name: "B", presence: left)
    try box.setWritable(false)

    let error = try slotError { _ = try box.ledger().takeSlot(name: "A", presence: right) }

    try expectEqual(error, .unavailable, "error")
    try expectEqual(try box.files(), ["left-0"], "files")
  },

  TestCase(name: "with the lock held by another process taking a slot gives contended after the maximum wait") { box in
    try box.holdLock(seconds: 5)
    let start = Date()

    let error = try slotError { _ = try box.ledger().takeSlot(name: "A", presence: right) }

    let elapsed = Date().timeIntervalSince(start)
    try expectEqual(error, .contended, "error")
    try expect(elapsed >= 0.45, "wait too short: \(elapsed) s")
    try expect(elapsed < 3, "wait too long: \(elapsed) s")
    try expectEqual(try box.files(), [], "no slot created")
  },

  TestCase(name: "with the lock contended the previous panel of the same window is not stopped") { box in
    let predecessor = try plant(box, name: "A", presence: right)
    try box.holdLock(seconds: 5)

    let error = try slotError { _ = try box.ledger().takeSlot(name: "A", presence: .hidden) }

    try expectEqual(error, .contended, "error")
    try expectEqual(try box.files(), ["right-0"], "the predecessor's file stays")
    try expect(predecessor.isRunning, "the predecessor must not be stopped")
  },

  TestCase(name: "with the lock contended a move gives contended and the old file stays") { box in
    let slotA = try takenSlot(box.ledger(), name: "A", presence: right)
    try box.holdLock(seconds: 5)

    let error = try slotError { _ = try box.ledger().moveSlot(slotA, to: left, name: "A") }

    try expectEqual(error, .contended, "error")
    try expectEqual(try box.files(), ["right-0"], "files")
  },

  TestCase(name: "with the lock contended releasing leaves the file") { box in
    let slotA = try takenSlot(box.ledger(), name: "A", presence: right)
    try box.holdLock(seconds: 5)

    box.ledger().releaseSlot(slotA)

    try expectEqual(try box.files(), ["right-0"], "the next panel's cleanup will remove the file")
  },

  TestCase(name: "when the other process dies the lock can be obtained again") { box in
    try box.holdLock(seconds: 5)
    let error = try slotError { _ = try box.ledger().takeSlot(name: "A", presence: right) }
    try expectEqual(error, .contended, "error during the contention")
    box.killChildren()

    let slot = try box.ledger().takeSlot(name: "A", presence: right)

    try expectEqual(slot, Slot(presence: right, number: 0), "slot")
  },
]

exit(run(cases))
