import Foundation

/// Answers whether a system sound exists; keeps Settings free of file-system access.
protocol SoundCatalog {
  func hasSound(named name: String) -> Bool
}

struct Settings: Equatable {
  var soundEnabled = true
  var stripEnabled = true
  var soundDone = "Glass"
  var soundQuestion = "Ping"
  var colorDone = RGBColor(red: 0xD9, green: 0x77, blue: 0x57)
  var colorQuestion = RGBColor(red: 0x00, green: 0x7A, blue: 0xFF)
  var durationSeconds: Double = 10
  var stayUntilVisited = false
  var labelEnabled = true

  static let optionPrefix = "CLAUDE_PLUGIN_OPTION_"
  static let durationRange: ClosedRange<Double> = 3...60

  func sound(for mode: Mode) -> String { mode == .done ? soundDone : soundQuestion }
  func color(for mode: Mode) -> RGBColor { mode == .done ? colorDone : colorQuestion }
  /// nil means the strip has no expiry.
  var lifetime: Double? { stayUntilVisited ? nil : durationSeconds }
}

struct ParsedSettings: Equatable {
  let settings: Settings
  /// Option keys (lowercase, as in the manifest) whose non-empty value was rejected.
  let invalid: [String]
}

func parseSettings(_ environment: [String: String], sounds: SoundCatalog) -> ParsedSettings {
  var settings = Settings()
  var invalid: [String] = []
  func raw(_ key: String) -> String? {
    let value = environment[Settings.optionPrefix + key.uppercased()]?.trimmingCharacters(in: .whitespaces)
    return value?.isEmpty == false ? value : nil
  }
  func apply<Value>(_ key: String, _ parse: (String) -> Value?, _ set: (Value) -> Void) {
    guard let text = raw(key) else { return }
    if let value = parse(text) { set(value) } else { invalid.append(key) }
  }
  apply("sound_enabled", parseSwitch) { settings.soundEnabled = $0 }
  apply("strip_enabled", parseSwitch) { settings.stripEnabled = $0 }
  apply("sound_done", { parseSound($0, sounds) }) { settings.soundDone = $0 }
  apply("sound_question", { parseSound($0, sounds) }) { settings.soundQuestion = $0 }
  apply("color_done", parseColor) { settings.colorDone = $0 }
  apply("color_question", parseColor) { settings.colorQuestion = $0 }
  apply("duration_seconds", parseDuration) { settings.durationSeconds = $0 }
  apply("stay_until_visited", parseSwitch) { settings.stayUntilVisited = $0 }
  apply("label_enabled", parseSwitch) { settings.labelEnabled = $0 }
  return ParsedSettings(settings: settings, invalid: invalid)
}

func parseSwitch(_ text: String) -> Bool? {
  switch text.lowercased() {
  case "true", "1": return true
  case "false", "0": return false
  default: return nil
  }
}

/// The name is validated before any path is built from it.
func parseSound(_ text: String, _ sounds: SoundCatalog) -> String? {
  let allowed = text.count <= 32 && text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
  return allowed && sounds.hasSound(named: text) ? text : nil
}

func parseColor(_ text: String) -> RGBColor? {
  let digits = text.dropFirst()
  guard text.count == 7, text.first == "#", digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
        let value = UInt32(digits, radix: 16) else { return nil }
  return RGBColor(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
}

func parseDuration(_ text: String) -> Double? {
  guard let value = Double(text), value.isFinite, Settings.durationRange.contains(value) else { return nil }
  return value
}

/// Black or white, whichever has the higher WCAG contrast ratio on the strip colour.
func labelTextIsBlack(on color: RGBColor) -> Bool {
  let luminance = relativeLuminance(color)
  return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
}

func relativeLuminance(_ color: RGBColor) -> Double {
  func channel(_ value: UInt8) -> Double {
    let c = Double(value) / 255
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
}
