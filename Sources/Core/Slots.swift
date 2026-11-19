import Foundation

/// Sole owner of the slot files and the lock: every operation is a section under `flock`.
final class FileSlots: SlotLedger {
  private static let maxWaitMs = 500
  private static let retryPauseUs: useconds_t = 10_000
  private static let hiddenPrefix = "hidden"
  private static let processName = "edgeping"
  private static let processNameBufferSize = 64

  private struct SlotEntry {
    let file: String
    let slot: Slot
    let pid: Int32?
    let name: String?
  }

  private let directory: String
  private let pid: Int32

  init(directory: String, pid: Int32) {
    self.directory = directory
    self.pid = pid
  }

  func takeSlot(name: String, presence: Presence, capacity: Int) throws -> Slot? {
    do {
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    } catch {
      throw SlotError.unavailable
    }
    return try withLock { () throws -> Slot? in
      var alive: [SlotEntry] = []
      for entry in try readEntries() {
        if let other = entry.pid, isLiveEdgeping(other) { alive.append(entry) } else { remove(entry.file) }
      }
      for entry in alive where entry.name == name {
        if let other = entry.pid, other != pid { kill(other, SIGTERM) }
        remove(entry.file)
      }
      guard case .side = presence else { return nil }
      let slot = Slot(
        presence: presence, number: try freeNumber(presence, capacity: capacity, among: alive.filter { $0.name != name }))
      guard create(slot, name: name) else { throw SlotError.unavailable }
      return slot
    }
  }

  func moveSlot(_ slot: Slot, to presence: Presence, name: String, capacity: Int) throws -> Slot {
    try withLock { () throws -> Slot in
      let old = fileName(slot)
      let entries = try readEntries()
      guard entries.contains(where: { $0.file == old && $0.pid == pid }) else { throw SlotError.uncertain }
      let new = Slot(presence: presence, number: try freeNumber(presence, capacity: capacity, among: entries))
      guard create(new, name: name) else { throw SlotError.unavailable }
      remove(old)
      return new
    }
  }

  func releaseSlot(_ slot: Slot) {
    let file = fileName(slot)
    // On expiry a single attempt is enough: a leftover file is removed by the next panel's cleanup.
    _ = try? withLock { () throws -> Void in
      if try readEntries().contains(where: { $0.file == file && $0.pid == pid }) { remove(file) }
    }
  }

  private func withLock<Value>(_ section: () throws -> Value) throws -> Value {
    let descriptor = open(path("lock"), O_RDWR | O_CREAT, 0o600)
    guard descriptor >= 0 else { throw SlotError.unavailable }
    // Closing the descriptor releases the flock, even if the section throws.
    defer { close(descriptor) }
    let deadline = DispatchTime.now() + .milliseconds(Self.maxWaitMs)
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      if DispatchTime.now() >= deadline { throw SlotError.contended }
      usleep(Self.retryPauseUs)
    }
    return try section()
  }

  private func readEntries() throws -> [SlotEntry] {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
      throw SlotError.unavailable
    }
    return files.compactMap { file in
      guard let slot = slotOfFile(file) else { return nil }
      // An unreadable file counts as a dead panel: the cleanup removes it.
      let content = (try? String(contentsOfFile: path(file), encoding: .utf8)) ?? ""
      let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
      return SlotEntry(
        file: file, slot: slot, pid: lines.first.flatMap { Int32($0) },
        name: lines.count > 1 ? String(lines[1]) : nil)
    }
  }

  private func slotOfFile(_ file: String) -> Slot? {
    let parts = file.split(separator: "-")
    guard parts.count == 2, let number = Int(parts[1]), number >= 0 else { return nil }
    if parts[0] == Self.hiddenPrefix { return Slot(presence: .hidden, number: number) }
    guard let side = Side(rawValue: String(parts[0])) else { return nil }
    return Slot(presence: .side(side), number: number)
  }

  private func fileName(_ slot: Slot) -> String {
    switch slot.presence {
    case .side(let side): return "\(side.rawValue)-\(slot.number)"
    case .hidden: return "\(Self.hiddenPrefix)-\(slot.number)"
    }
  }

  private func freeNumber(_ presence: Presence, capacity: Int, among entries: [SlotEntry]) throws -> Int {
    let number = firstFree(presence, among: entries)
    if case .side = presence, number >= capacity { throw SlotError.full }
    return number
  }

  private func firstFree(_ presence: Presence, among entries: [SlotEntry]) -> Int {
    let taken = Set(entries.filter { $0.slot.presence == presence }.map(\.slot.number))
    var number = 0
    while taken.contains(number) { number += 1 }
    return number
  }

  private func create(_ slot: Slot, name: String) -> Bool {
    FileManager.default.createFile(atPath: path(fileName(slot)), contents: Data("\(pid)\n\(name)\n".utf8))
  }

  // A pid reused by another process is no longer a panel: the signal must not reach it.
  private func isLiveEdgeping(_ other: Int32) -> Bool {
    var name = [CChar](repeating: 0, count: Self.processNameBufferSize)
    return proc_name(other, &name, UInt32(name.count)) > 0 && String(cString: name) == Self.processName
  }

  // A failed removal leaves a file that a later panel's cleanup removes once its process is dead.
  private func remove(_ file: String) {
    try? FileManager.default.removeItem(atPath: path(file))
  }

  private func path(_ file: String) -> String {
    directory + "/" + file
  }
}
