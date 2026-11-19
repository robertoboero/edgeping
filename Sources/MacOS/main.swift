import AppKit

let t0 = DispatchTime.now()
let environment = ProcessInfo.processInfo.environment
let temporaryDirectory = URL(
  fileURLWithPath: environment["TMPDIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "/tmp")
let stateDirectory = temporaryDirectory.appendingPathComponent("edgeping").path
let subagentDirectory = stateDirectory + "/subagents"
let arguments = CommandLine.arguments
let home = environment["HOME"] ?? ""
let logDirectory = home + "/Library/Logs/edgeping"

// Three modes of the same binary; any other form is invalid-arguments.
if arguments.count == 2, let mode = Mode(rawValue: arguments[1]) {
  runHook(mode: mode)
} else if arguments.count == 4, arguments[1] == "sound", let mode = Mode(rawValue: arguments[2]),
  let event = EventID(text: arguments[3]) {
  runSound(mode: mode, event: event)
} else if arguments.count == 3 || arguments.count == 4, let mode = Mode(rawValue: arguments[1]) {
  runAlert(mode: mode, cwd: arguments[2], eventText: arguments.count == 4 ? arguments[3] : nil)
} else {
  OutcomeLog(directory: logDirectory, event: nil).write(.invalidArguments)
  exit(0)
}

/// Hook mode: decides, launches the sound and the alert detached, and exits without waiting for them.
func runHook(mode: Mode) -> Never {
  let event = EventID(startNanoseconds: t0.uptimeNanoseconds, pid: getpid())
  let log = OutcomeLog(directory: logDirectory, event: event)
  let input: HookInput
  do {
    input = try readHookInput()
  } catch {
    log.write(.invalidInput)
    exit(0)
  }
  let state = SubagentState(directory: subagentDirectory)
  let saved = input.runningSubagents == nil ? state.read(sessionID: input.sessionID) : nil
  let decision = decide(mode: mode, input: input, savedCount: saved)
  // The count is saved after the launches: a slow disk write must not delay the sound.
  let saveCount = { if let count = decision.countToSave { state.write(count, sessionID: input.sessionID) } }
  guard decision.plays else {
    saveCount()
    exit(0)
  }
  guard let executable = Bundle.main.executablePath else {
    log.write(.launchFailed, cwd: input.cwd)
    saveCount()
    exit(0)
  }
  let launcher = Launcher(executable: executable, environment: environment)
  // The sound starts first and alone: a failing alert neither stops nor delays it.
  launchChild(launcher, ["sound", mode.rawValue, event.text], log: log, cwd: input.cwd)
  if let cwd = decision.alertCwd {
    launchChild(launcher, [mode.rawValue, cwd, event.text], log: log, cwd: cwd)
  }
  saveCount()
  exit(0)
}

func launchChild(_ launcher: Launcher, _ childArguments: [String], log: OutcomeLog, cwd: String?) {
  do {
    try launcher.launch(childArguments)
  } catch {
    log.write(.launchFailed, cwd: cwd)
  }
}

/// Sound mode: lives until playback ends; `ms=` runs from the start of the hook mode to the return of play().
func runSound(mode: Mode, event: EventID) -> Never {
  let log = OutcomeLog(directory: logDirectory, event: event)
  do {
    // No NSApplication: it costs tens of ms before play() and NSSound does not need it.
    let player = try SoundPlayer(name: Settings().sound(for: mode), onFinish: { exit(0) })
    try player.play()
    log.write(.soundOK, fields: "ms=\(millisecondsSince(nanoseconds: event.startNanoseconds))")
    // The delegate and the timer live as long as the player: it must stay alive while the run loop runs.
    withExtendedLifetime(player) { RunLoop.main.run() }
  } catch {
    log.write(.soundFailed)
  }
  exit(0)
}

// A t0 later than now (a hand-written event) gives 0 instead of an arithmetic error.
func millisecondsSince(nanoseconds start: UInt64) -> Int {
  let now = DispatchTime.now().uptimeNanoseconds
  return Int((now - min(start, now)) / 1_000_000)
}

/// Alert mode: launched by the hook mode with the event, or by hand without it.
func runAlert(mode: Mode, cwd: String, eventText: String?) -> Never {
  let event = eventText.flatMap { EventID(text: $0) }
  let log = OutcomeLog(directory: logDirectory, event: event)
  guard cwd.hasPrefix("/"), home.hasPrefix("/"), eventText == nil || event != nil else {
    log.write(.invalidArguments, cwd: cwd)
    exit(0)
  }
  let alert = prepareAlert(mode: mode, cwd: cwd, home: home, directory: stateDirectory, log: log)
  NSApplication.shared.setActivationPolicy(.accessory)
  alert.showFirstTime(since: t0)
  NSWorkspace.shared.notificationCenter.addObserver(
    alert, selector: #selector(Alert.spaceDidChange(_:)),
    name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
  // The notification center does not retain the observer: the alert must stay alive until it expires.
  withExtendedLifetime(alert) { NSApplication.shared.run() }
  exit(0)
}

/// Recognises the window and takes the slot; every expected failure ends here with its log line.
func prepareAlert(mode: Mode, cwd: String, home: String, directory: String, log: OutcomeLog) -> Alert {
  do {
    let probe = try CGSProbe()
    let reading = try probe.read()
    let chosen = try chooseWindow(reading.windows, candidates: candidateNames(cwd: cwd, home: home))
    let presence = try computePresence(reading.spaces, windowSpaces: chosen.window.spaces)
    let slots = FileSlots(directory: directory, pid: getpid())
    guard let slot = try slots.takeSlot(name: chosen.name, presence: presence, capacity: Int.max) else {
      log.write(.currentSpace, name: chosen.name, cwd: cwd)
      exit(0)
    }
    return Alert(
      probe: probe, slots: slots, chosen: chosen, slot: slot, appearance: appearance(for: mode),
      log: log, cwd: cwd)
  } catch {
    log.write(outcome(of: error), cwd: cwd)
    exit(0)
  }
}

// Until the settings are read from the environment, the defaults give the values the strip always had.
func appearance(for mode: Mode) -> Appearance {
  let settings = Settings()
  let color = settings.color(for: mode)
  return Appearance(
    color: color, textIsBlack: labelTextIsBlack(on: color), showsLabel: settings.labelEnabled,
    lifetime: settings.lifetime)
}

// Expected failures have one branch each; only the default branch is a bug, logged as probe-failed.
func outcome(of error: Error) -> Outcome {
  switch error {
  case let failure as Failure: return failure.outcome
  case let slotError as SlotError:
    switch slotError {
    case .contended: return .slotsContended
    case .unavailable, .uncertain, .full: return .slotsUnavailable
    }
  case is ProbeError, is NoScreen: return .probeFailed
  default: return .probeFailed
  }
}

/// State of the alert in the process: desired presence and owned slot; the visible panel is known to `Panel`.
final class Alert: NSObject {
  private let probe: SpaceProbe
  private let slots: SlotLedger
  private let windowID: Int
  private let name: String
  private let appearance: Appearance
  private let log: OutcomeLog
  private let cwd: String
  private var slot: Slot
  // nil means "unknown": after a reread or move error, until a reread succeeds.
  private var desired: Presence?
  private var errorLogged = false
  private var focusLogged = false
  private lazy var panel = Panel(
    name: name, appearance: appearance,
    onSample: { [unowned self] active, elapsedMs in self.sample(active: active, elapsedMs: elapsedMs) },
    onExpiry: { [unowned self] in self.expire() })

  init(
    probe: SpaceProbe, slots: SlotLedger, chosen: ChosenWindow, slot: Slot, appearance: Appearance,
    log: OutcomeLog, cwd: String
  ) {
    self.probe = probe
    self.slots = slots
    self.windowID = chosen.window.id
    self.name = chosen.name
    self.appearance = appearance
    self.log = log
    self.cwd = cwd
    self.slot = slot
    self.desired = slot.presence
    super.init()
  }

  func showFirstTime(since t0: DispatchTime) {
    do {
      try reconcileNow()
    } catch {
      log.write(outcome(of: error), name: name, cwd: cwd)
      slots.releaseSlot(slot)
      exit(0)
    }
    log.write(.ok, name: name, cwd: cwd, fields: "ms=\(millisecondsSince(t0))")
  }

  @objc func spaceDidChange(_ notification: Notification) {
    do {
      let rereading = try probe.reread(window: windowID)
      desired = try computePresence(rereading.spaces, windowSpaces: rereading.windowSpaces)
      // The panel is recreated on the current space at every change, even when the side is unchanged.
      panel.hide()
      try reconcileNow()
    } catch SlotError.uncertain {
      panel.hide()
      exit(0)
    } catch {
      panel.hide()
      desired = nil
      guard !errorLogged else { return }
      errorLogged = true
      log.write(outcome(of: error), name: name, cwd: cwd)
    }
  }

  // The slot moves before showing: the panel is only created on an already owned slot.
  private func reconcileNow() throws {
    guard let wanted = desired else { return }
    for action in reconcile(desired: wanted, slot: slot.presence, panel: panel.visibleSide) {
      switch action {
      case .moveSlot(let target): slot = try slots.moveSlot(slot, to: target, name: name, capacity: Int.max)
      case .show(let side): try panel.show(side: side, slot: slot.number)
      case .hide: panel.hide()
      }
    }
  }

  private func sample(active: Bool, elapsedMs: Int) {
    guard active && !focusLogged else { return }
    focusLogged = true
    log.write(.focusTaken, name: name, cwd: cwd, fields: "elapsed_ms=\(elapsedMs)")
  }

  private func expire() {
    slots.releaseSlot(slot)
    exit(0)
  }
}
