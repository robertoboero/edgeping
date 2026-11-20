// Contract of reading the options (Settings.swift) and of the label text colour choice.
import Foundation

var passed = 0
var failed = 0

func report(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
  if ok { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name) \(detail())") }
}

func expectEqual<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
  report(name, actual == expected, "expected \(expected) got \(actual)")
}

let defaults = Settings()

// One neighbour per option that differs from every default, so an invalid option cannot leak into it.
let neighbours: [String: String] = [
  "sound_enabled": "false", "strip_enabled": "false", "sound_done": "Hero", "sound_question": "Basso",
  "color_done": "#112233", "color_question": "#445566", "duration_seconds": "42",
  "stay_until_visited": "true", "label_enabled": "false",
]
let keys = neighbours.keys.sorted()

/// What the neighbour values must produce, written out by hand and not obtained from parse.
let allApplied = Settings(
  soundEnabled: false, stripEnabled: false, soundDone: "Hero", soundQuestion: "Basso",
  colorDone: RGBColor(red: 0x11, green: 0x22, blue: 0x33), colorQuestion: RGBColor(red: 0x44, green: 0x55, blue: 0x66),
  durationSeconds: 42, stayUntilVisited: true, labelEnabled: false)

/// `base` with the field of `key` taken from `source`.
func setting(_ key: String, from source: Settings, into base: Settings) -> Settings {
  var result = base
  switch key {
  case "sound_enabled": result.soundEnabled = source.soundEnabled
  case "strip_enabled": result.stripEnabled = source.stripEnabled
  case "sound_done": result.soundDone = source.soundDone
  case "sound_question": result.soundQuestion = source.soundQuestion
  case "color_done": result.colorDone = source.colorDone
  case "color_question": result.colorQuestion = source.colorQuestion
  case "duration_seconds": result.durationSeconds = source.durationSeconds
  case "stay_until_visited": result.stayUntilVisited = source.stayUntilVisited
  case "label_enabled": result.labelEnabled = source.labelEnabled
  default: fatalError("unknown key \(key)")
  }
  return result
}

/// Every option applied except `key`, which keeps its default.
func neighboursApplied(except key: String) -> Settings { setting(key, from: defaults, into: allApplied) }

/// Only `key` applied; every other option at its default.
func onlyApplied(_ key: String) -> Settings { setting(key, from: allApplied, into: defaults) }

// Rows of the options table: a value that is not valid for the key.
let invalidValue: [String: String] = [
  "sound_enabled": "yes", "strip_enabled": "on", "sound_done": "Missing", "sound_question": "Missing",
  "color_done": "#abc", "color_question": "abcdef", "duration_seconds": "2.9",
  "stay_until_visited": "maybe", "label_enabled": "2",
]

for key in keys {
  let others = neighbours.filter { $0.key != key }
  let expectedOthers = neighboursApplied(except: key)

  let absent = parse(others)
  expectEqual("\(key): absent keeps the default and is not reported", absent.invalid, [])
  expectEqual("\(key): absent leaves the other options applied", absent.settings, expectedOthers)

  let empty = parse(others.merging([key: ""]) { $1 })
  expectEqual("\(key): empty keeps the default and is not reported", empty.invalid, [])
  expectEqual("\(key): empty leaves the other options applied", empty.settings, expectedOthers)

  let blank = parse(others.merging([key: "  "]) { $1 })
  expectEqual("\(key): blanks only count as empty", blank.invalid, [])

  let bad = parse(others.merging([key: invalidValue[key]!]) { $1 })
  expectEqual("\(key): invalid is reported once, by key only", bad.invalid, [key])
  expectEqual("\(key): invalid keeps the default and the other options applied", bad.settings, expectedOthers)

  let good = parse([key: neighbours[key]!])
  expectEqual("\(key): valid is not reported", good.invalid, [])
  expectEqual("\(key): valid is applied and nothing else changes", good.settings, onlyApplied(key))
}

expectEqual("every valid option together is applied and none is reported", parse(neighbours), ParsedSettings(settings: allApplied, invalid: []))

expectEqual("no options gives the defaults", parse([:]).settings, defaults)
expectEqual("an unknown key with the prefix is ignored", parseSettings([Settings.optionPrefix + "NO_SUCH": "x"], sounds: knownSounds),
            ParsedSettings(settings: defaults, invalid: []))
expectEqual("a key without the prefix is ignored", parseSettings(["SOUND_ENABLED": "false"], sounds: knownSounds),
            ParsedSettings(settings: defaults, invalid: []))
expectEqual("several invalid options are all reported", Set(parse(["sound_enabled": "x", "color_done": "x"]).invalid), Set(["sound_enabled", "color_done"]))

// Switches.
for (text, value) in [("true", true), ("false", false), ("1", true), ("0", false), ("TRUE", true), ("False", false), (" false ", false)] {
  expectEqual("switch '\(text)'", parse(["sound_enabled": text]).settings.soundEnabled, value)
}
expectEqual("an off-by-default switch accepts true", parse(["stay_until_visited": "true"]).settings.stayUntilVisited, true)
expectEqual("an invalid on-by-default switch stays on", parse(["label_enabled": "nope"]).settings.labelEnabled, true)
expectEqual("an invalid off-by-default switch stays off", parse(["stay_until_visited": "nope"]).settings.stayUntilVisited, false)

// Duration: below, equal, above, each bound, read from the code; then the requirement written by hand.
let low = Settings.durationRange.lowerBound
let high = Settings.durationRange.upperBound
for (text, valid) in [("\(low - 0.1)", false), ("\(low)", true), ("\(low + 0.1)", true),
                      ("\(high - 0.1)", true), ("\(high)", true), ("\(high + 0.1)", false)] {
  let parsed = parse(["duration_seconds": text])
  expectEqual("duration \(text) is \(valid ? "valid" : "invalid")", parsed.invalid, valid ? [] : ["duration_seconds"])
  expectEqual("duration \(text) result", parsed.settings.durationSeconds, valid ? Double(text)! : defaults.durationSeconds)
}
for (text, valid) in [("3", true), ("60", true), ("2.9", false), ("60.1", false), ("2", false), ("61", false)] {
  expectEqual("requirement: duration \(text)", parse(["duration_seconds": text]).invalid.isEmpty, valid)
}
for text in ["abc", "nan", "inf", "-inf", "1e999", "-5", "0", "1e-3"] {
  expectEqual("duration '\(text)' is invalid", parse(["duration_seconds": text]).invalid, ["duration_seconds"])
}
expectEqual("an invalid duration is reported with the stay switch on",
            parse(["duration_seconds": "2.9", "stay_until_visited": "true"]).invalid, ["duration_seconds"])
expectEqual("an invalid duration is not clamped", parse(["duration_seconds": "61"]).settings.durationSeconds, defaults.durationSeconds)
expectEqual("lifetime is the duration by default", parse(["duration_seconds": "20"]).settings.lifetime, 20)
expectEqual("lifetime is nil with the stay switch on", parse(["stay_until_visited": "true", "duration_seconds": "20"]).settings.lifetime, nil)

// Colours.
expectEqual("#abcdef is valid", parse(["color_done": "#abcdef"]).settings.colorDone, RGBColor(red: 0xAB, green: 0xCD, blue: 0xEF))
expectEqual("hex digits are case-insensitive", parse(["color_done": "#ABCDEF"]).settings.colorDone, RGBColor(red: 0xAB, green: 0xCD, blue: 0xEF))
expectEqual("the question colour is read from its own key", parse(["color_question": "#010203"]).settings.colorQuestion, RGBColor(red: 1, green: 2, blue: 3))
for text in ["#abc", "abcdef", "#12345G", "+12345", "#abcdeff", "#abcde", "#+12345", "#-12345", "# 12345", "#\u{FF21}\u{FF22}\u{FF23}\u{FF24}\u{FF25}\u{FF26}"] {
  let parsed = parse(["color_done": text])
  expectEqual("colour '\(text)' is invalid", parsed.invalid, ["color_done"])
  expectEqual("colour '\(text)' keeps the default", parsed.settings.colorDone, defaults.colorDone)
}

// Sound names: the validation must reject before the catalog is asked, so the catalog accepts everything here.
let thirtyTwo = String(repeating: "a", count: 32)
let thirtyThree = String(repeating: "a", count: 33)
for text in ["../../x", "Glass.aiff", "Gl ass", "Glass\nPing", "Glass\n", thirtyThree, "Gl\u{E4}ss", "Glass/x", "..", "a-b"] {
  let parsed = parse(["sound_done": text], sounds: AnySound())
  expectEqual("sound name '\(text.debugDescription)' is invalid", parsed.invalid, ["sound_done"])
  expectEqual("sound name '\(text.debugDescription)' keeps the default", parsed.settings.soundDone, defaults.soundDone)
}
expectEqual("a 32-character name is valid", parse(["sound_done": thirtyTwo], sounds: AnySound()).settings.soundDone, thirtyTwo)
expectEqual("a name with digits is valid", parse(["sound_done": "Tink2"], sounds: AnySound()).invalid, [])
expectEqual("a known name is applied", parse(["sound_done": "Hero"]).settings.soundDone, "Hero")
expectEqual("the question sound is read from its own key", parse(["sound_question": "Basso"]).settings.soundQuestion, "Basso")
expectEqual("a well-formed name the catalog lacks is invalid", parse(["sound_done": "Missing"]).invalid, ["sound_done"])
expectEqual("the catalog decides: a name valid in one catalog is invalid in another",
            parse(["sound_done": "Hero"], sounds: FakeSounds(names: ["Glass"])).invalid, ["sound_done"])

// Mode accessors.
let both = parse(neighbours).settings
expectEqual("done uses the done sound", both.sound(for: .done), "Hero")
expectEqual("question uses the question sound", both.sound(for: .question), "Basso")
expectEqual("done uses the done colour", both.color(for: .done), RGBColor(red: 0x11, green: 0x22, blue: 0x33))
expectEqual("question uses the question colour", both.color(for: .question), RGBColor(red: 0x44, green: 0x55, blue: 0x66))

// RNF-05: label contrast over a grid of colours that includes the greys.
let levels: [UInt8] = [0, 32, 64, 96, 128, 160, 192, 224, 255]
var grid: [RGBColor] = []
for r in levels { for g in levels { for b in levels { grid.append(RGBColor(red: r, green: g, blue: b)) } } }
for v in 0...255 { grid.append(RGBColor(red: UInt8(v), green: UInt8(v), blue: UInt8(v))) }
let ratios = grid.map { chosenContrast(on: $0) }
let minimum = ratios.min()!
print("RNF-05 colours: \(grid.count), minimum contrast: \(String(format: "%.4f", minimum)) (theoretical 4.58)")
report("grid has at least 512 colours", grid.count >= 512)
report("every chosen contrast is at least 4.5", ratios.allSatisfy { $0 >= 4.5 }, "minimum \(minimum)")
report("the minimum is not below the theoretical 4.58", minimum >= 4.58 - 0.01, "minimum \(minimum)")
report("the greys are in the grid", grid.contains(RGBColor(red: 119, green: 119, blue: 119)))
expectEqual("yellow takes black text", labelTextIsBlack(on: RGBColor(red: 255, green: 255, blue: 0)), true)
expectEqual("dark blue takes white text", labelTextIsBlack(on: RGBColor(red: 0x10, green: 0x20, blue: 0x40)), false)
expectEqual("the default done colour takes black text", labelTextIsBlack(on: defaults.colorDone), true)
expectEqual("the default question colour takes black text", labelTextIsBlack(on: defaults.colorQuestion), true)
report("default done contrast is about 6.7", abs(chosenContrast(on: defaults.colorDone) - 6.7) < 0.1, "\(chosenContrast(on: defaults.colorDone))")
report("default question contrast is about 5.2", abs(chosenContrast(on: defaults.colorQuestion) - 5.2) < 0.1, "\(chosenContrast(on: defaults.colorQuestion))")

print("PASSED: \(passed) FAILED: \(failed)")
exit(failed == 0 ? 0 : 1)
