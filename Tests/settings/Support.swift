import Foundation

/// A sound catalog that knows exactly the names it is given, so no test touches the file system.
struct FakeSounds: SoundCatalog {
  let names: Set<String>
  func hasSound(named name: String) -> Bool { names.contains(name) }
}

/// Accepts every name: a rejection can then only come from the name validation itself.
struct AnySound: SoundCatalog {
  func hasSound(named name: String) -> Bool { true }
}

let knownSounds = FakeSounds(names: ["Glass", "Ping", "Basso", "Hero"])

func environment(_ options: [String: String]) -> [String: String] {
  Dictionary(uniqueKeysWithValues: options.map { (Settings.optionPrefix + $0.key.uppercased(), $0.value) })
}

func parse(_ options: [String: String], sounds: SoundCatalog = knownSounds) -> ParsedSettings {
  parseSettings(environment(options), sounds: sounds)
}

/// WCAG contrast ratio written out here so the test does not reuse the code it checks.
func wcagLuminance(_ color: RGBColor) -> Double {
  func channel(_ value: UInt8) -> Double {
    let c = Double(value) / 255
    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
}

func contrastRatio(_ a: Double, _ b: Double) -> Double {
  (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

/// Contrast of the text colour the code picks (black or white) on the strip colour.
func chosenContrast(on color: RGBColor) -> Double {
  contrastRatio(wcagLuminance(color), labelTextIsBlack(on: color) ? 0 : 1)
}
