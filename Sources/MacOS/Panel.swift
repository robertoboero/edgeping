import AppKit
import QuartzCore

struct NoScreen: Error {}
/// The label view has no layer: an AppKit invariant was violated, and main.swift logs it as a bug.
struct NoLayer: Error {}

// Values confirmed by eye on screen; do not change them without a new visual check.
private let stripWidth: CGFloat = 16
private let labelGap: CGFloat = 4
private let labelHeight: CGFloat = 28
private let slotStep: CGFloat = 36
private let maxTextWidth: CGFloat = 220
private let fontSize: CGFloat = 13
private let labelPadding: CGFloat = 12
private let labelCornerRadius: CGFloat = 14
private let coreWidth: CGFloat = 1.5
private let coreTint: CGFloat = 0.35
// Offset from the edge in points and opacity of the base colour; the core fades from the edge to the first stop.
private let glowStops: [(offset: CGFloat, alpha: CGFloat)] = [
  (coreWidth, 0.90), (3, 0.59), (4.8, 0.37), (7.2, 0.19), (10.4, 0.08), (13.6, 0.03), (16, 0),
]
private let haloWidth: CGFloat = 36
private let haloStops: [(offset: CGFloat, alpha: CGFloat)] = [
  (0, 0.14), (9, 0.118), (18, 0.07), (27, 0.022), (36, 0),
]
private let endTaper: CGFloat = 0.18
// Fade at each end: fractions of endTaper and mask opacity.
private let taperSteps: [(fraction: CGFloat, alpha: CGFloat)] = [
  (0, 0), (0.25, 0.16), (0.5, 0.5), (0.75, 0.84), (1, 1),
]
private let labelGlowRadius: CGFloat = 8
private let labelGlowAlpha: Float = 0.40
private let labelBleed: CGFloat = 10
private let labelSlideDistance: CGFloat = 10
// Collapsed scale: the light's horizontal scale at the start of the entrance and at the end of the exit; the mask's vertical scale.
private let collapsedScale = 0.35
private let enterSeconds: TimeInterval = 0.70
private let exitSeconds: TimeInterval = 0.60
private let breathMinOpacity: Float = 0.74
private let breathHalfPeriodSeconds: TimeInterval = 1.6
private let breathStartDelaySeconds: TimeInterval = enterSeconds
private let reducedFadeSeconds: TimeInterval = 0.25
private let sampleIntervalSeconds: TimeInterval = 0.25

/// How one alert looks and how long it lives; Settings values are mapped to it in one place.
struct Appearance {
  let color: RGBColor
  let textIsBlack: Bool
  let showsLabel: Bool
  /// nil: no exit animation and no expiry.
  let lifetime: TimeInterval?
}

func millisecondsSince(_ start: DispatchTime) -> Int {
  Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
}

private enum Part {
  case light, mask, label
}

/// The animated layers of the visible panel; the exit finds them here.
private struct Layers {
  let light: CALayer
  let mask: CALayer
  let breath: CALayer
  let label: CALayer
  let side: Side
  let reduceMotion: Bool

  func layer(_ part: Part) -> CALayer {
    switch part {
    case .light: return light
    case .mask: return mask
    case .label: return label
    }
  }
}

/// One row of the entrance and exit motion tables; a nil `from` starts from the model value.
private struct Motion {
  let part: Part
  let keyPath: String
  let from: Double?
  let to: Double
  let delay: TimeInterval
  let duration: TimeInterval
  let curve: CAMediaTimingFunction
}

private func curve(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> CAMediaTimingFunction {
  CAMediaTimingFunction(controlPoints: a, b, c, d)
}

// The label slides towards the edge: left towards smaller x, right towards larger x.
private func slide(_ side: Side) -> Double {
  side == .left ? -Double(labelSlideDistance) : Double(labelSlideDistance)
}

private func entranceMotions(_ layers: Layers) -> [Motion] {
  if layers.reduceMotion {
    let fade = CAMediaTimingFunction(name: .easeOut)
    return [
      Motion(part: .light, keyPath: "opacity", from: 0, to: 1, delay: 0, duration: reducedFadeSeconds, curve: fade),
      Motion(part: .label, keyPath: "opacity", from: 0, to: 1, delay: 0, duration: reducedFadeSeconds, curve: fade),
    ]
  }
  let fade = curve(0, 0, 0.2, 1)
  let spring = curve(0.16, 1, 0.3, 1)
  return [
    Motion(part: .light, keyPath: "opacity", from: 0, to: 1, delay: 0, duration: 0.25, curve: fade),
    Motion(
      part: .light, keyPath: "transform.scale.x", from: collapsedScale, to: 1, delay: 0, duration: 0.55,
      curve: spring),
    Motion(
      part: .mask, keyPath: "transform.scale.y", from: collapsedScale, to: 1, delay: 0, duration: 0.70,
      curve: spring),
    Motion(part: .label, keyPath: "opacity", from: 0, to: 1, delay: 0.12, duration: 0.30, curve: fade),
    Motion(
      part: .label, keyPath: "transform.translation.x", from: slide(layers.side), to: 0, delay: 0.12,
      duration: 0.40, curve: spring),
  ]
}

private func exitMotions(_ layers: Layers) -> [Motion] {
  if layers.reduceMotion {
    let fade = CAMediaTimingFunction(name: .easeInEaseOut)
    return [
      Motion(part: .light, keyPath: "opacity", from: nil, to: 0, delay: 0, duration: exitSeconds, curve: fade),
      Motion(part: .label, keyPath: "opacity", from: nil, to: 0, delay: 0, duration: exitSeconds, curve: fade),
    ]
  }
  let away = curve(0.4, 0, 1, 1)
  return [
    Motion(part: .label, keyPath: "opacity", from: nil, to: 0, delay: 0, duration: 0.35, curve: away),
    Motion(
      part: .label, keyPath: "transform.translation.x", from: nil, to: slide(layers.side), delay: 0,
      duration: 0.35, curve: away),
    Motion(part: .light, keyPath: "opacity", from: nil, to: 0, delay: 0.10, duration: 0.50, curve: away),
    Motion(
      part: .light, keyPath: "transform.scale.x", from: nil, to: collapsedScale, delay: 0.10, duration: 0.50,
      curve: away),
  ]
}

private func animation(_ motion: Motion, on layer: CALayer, scale: Double, entering: Bool) -> CABasicAnimation {
  let animation = CABasicAnimation(keyPath: motion.keyPath)
  if let from = motion.from {
    animation.fromValue = from
  } else {
    animation.fromValue = layer.value(forKeyPath: motion.keyPath)
  }
  animation.toValue = motion.to
  animation.beginTime = CACurrentMediaTime() + motion.delay * scale
  animation.duration = motion.duration * scale
  animation.timingFunction = motion.curve
  // Entrance: the model already holds the final value. Exit: holds the last value until the layer is removed.
  animation.fillMode = entering ? .backwards : .forwards
  animation.isRemovedOnCompletion = entering
  return animation
}

/// Draws the alert on the screen edge without activating the app; it lives `lifetime` from the first show, even when hidden.
final class Panel: NSObject {
  private let name: String
  private let color: NSColor
  private let textIsBlack: Bool
  private let showsLabel: Bool
  private let lifetime: TimeInterval?
  private let onSample: (_ active: Bool, _ elapsedMs: Int) -> Void
  private let onExpiry: () -> Void
  private var window: NSPanel?
  private var layers: Layers?
  private var firstShown: DispatchTime?
  private var exitStarted = false
  private(set) var visibleSide: Side?

  init(
    name: String, appearance: Appearance,
    onSample: @escaping (_ active: Bool, _ elapsedMs: Int) -> Void,
    onExpiry: @escaping () -> Void
  ) {
    self.name = name
    let rgb = appearance.color
    self.color = NSColor(
      srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
      blue: CGFloat(rgb.blue) / 255, alpha: 1)
    self.textIsBlack = appearance.textIsBlack
    self.showsLabel = appearance.showsLabel
    self.lifetime = appearance.lifetime
    self.onSample = onSample
    self.onExpiry = onExpiry
    super.init()
  }

  /// Slots from the centre downwards whose label fits the main screen.
  func sideCapacity() throws -> Int {
    guard let screen = NSScreen.screens.first?.frame else { throw NoScreen() }
    return slotCapacity(
      screenHeight: Double(screen.height), labelHeight: Double(labelHeight), slotStep: Double(slotStep))
  }

  // This setup was verified not to take focus; retest any change on screen.
  func show(side: Side, slot: Int) throws {
    guard let screen = NSScreen.screens.first?.frame else { throw NoScreen() }
    hide()
    let label = showsLabel ? makeLabel() : nil
    // Without a label the animation tables still need a layer to act on; it is never attached.
    guard let labelLayer = label == nil ? CALayer() : label?.layer else { throw NoLayer() }
    let width = stripWidth + labelBleed + (label.map { labelGap + $0.frame.width } ?? 0)
    let panel = NSPanel(
      contentRect: NSRect(
        x: side == .left ? screen.minX : screen.maxX - width, y: screen.minY,
        width: width, height: screen.height),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .screenSaver
    panel.collectionBehavior = [.fullScreenAuxiliary]
    panel.ignoresMouseEvents = true
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: screen.height))
    content.wantsLayer = true
    guard let root = content.layer else { throw NoLayer() }
    // Layers and animations are created in the same transaction, before orderFrontRegardless.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let built = makeLayers(
      side: side, width: width, height: screen.height, label: labelLayer,
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    root.addSublayer(built.light)
    if let label {
      label.setFrameOrigin(NSPoint(
        x: side == .left ? stripWidth + labelGap : labelBleed,
        y: (screen.height - labelHeight) / 2 - CGFloat(slot) * slotStep))
      content.addSubview(label)
    }
    panel.contentView = content
    if exitStarted, let remaining = remainingSeconds() {
      startExit(built, scale: remaining / exitSeconds)
    } else { enter(built) }
    CATransaction.commit()
    panel.orderFrontRegardless()
    window = panel
    layers = built
    visibleSide = side
    if firstShown == nil { startLifetime() }
  }

  func hide() {
    window?.orderOut(nil)
    window = nil
    layers = nil
    visibleSide = nil
  }

  private func startLifetime() {
    firstShown = DispatchTime.now()
    Timer.scheduledTimer(
      timeInterval: sampleIntervalSeconds, target: self, selector: #selector(sample),
      userInfo: nil, repeats: true)
    guard let lifetime else { return }
    Timer.scheduledTimer(
      timeInterval: lifetime - exitSeconds, target: self, selector: #selector(beginExit),
      userInfo: nil, repeats: false)
    Timer.scheduledTimer(
      timeInterval: lifetime, target: self, selector: #selector(expire),
      userInfo: nil, repeats: false)
  }

  @objc private func sample() {
    guard let start = firstShown else { return }
    onSample(NSRunningApplication.current.isActive, millisecondsSince(start))
  }

  // From here on, each new panel starts already in the exit, with times scaled to the time left.
  @objc private func beginExit() {
    exitStarted = true
    if let layers { startExit(layers, scale: 1) }
  }

  @objc private func expire() {
    onExpiry()
  }

  private func remainingSeconds() -> TimeInterval? {
    guard let lifetime else { return nil }
    guard let start = firstShown else { return lifetime }
    return max(0, lifetime - Double(millisecondsSince(start)) / 1000)
  }

  private func enter(_ layers: Layers) {
    for motion in entranceMotions(layers) {
      let layer = layers.layer(motion.part)
      layer.add(animation(motion, on: layer, scale: 1, entering: true), forKey: motion.keyPath)
    }
    guard !layers.reduceMotion else { return }
    let breath = CABasicAnimation(keyPath: "opacity")
    breath.fromValue = 1
    breath.toValue = breathMinOpacity
    breath.beginTime = CACurrentMediaTime() + breathStartDelaySeconds
    breath.duration = breathHalfPeriodSeconds
    breath.autoreverses = true
    breath.repeatCount = .infinity
    breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    breath.fillMode = .backwards
    layers.breath.add(breath, forKey: "breath")
  }

  // Required order: copy the shown values into the model without implicit animations, remove entrance and breath animations, then add the exit.
  private func startExit(_ layers: Layers, scale: Double) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let animated = [layers.light, layers.mask, layers.breath, layers.label]
    let shown = animated.map { $0.presentation() }
    // A layer never shown has no presentation values: its model already holds the final value.
    for (layer, value) in zip(animated, shown) {
      guard let value else { continue }
      layer.opacity = value.opacity
      layer.transform = value.transform
    }
    animated.forEach { $0.removeAllAnimations() }
    for motion in exitMotions(layers) {
      let layer = layers.layer(motion.part)
      layer.add(animation(motion, on: layer, scale: scale, entering: false), forKey: motion.keyPath)
    }
    CATransaction.commit()
  }

  private func makeLayers(
    side: Side, width: CGFloat, height: CGFloat, label: CALayer, reduceMotion: Bool
  ) -> Layers {
    let left = side == .left
    let bounds = CGRect(x: 0, y: 0, width: haloWidth, height: height)
    let light = CALayer()
    light.bounds = bounds
    light.anchorPoint = CGPoint(x: left ? 0 : 1, y: 0.5)
    light.position = CGPoint(x: left ? 0 : width, y: height / 2)
    let breath = CALayer()
    breath.frame = bounds
    let halo = gradient(haloStops, span: haloWidth, side: side, core: nil)
    halo.frame = bounds
    let glow = gradient(
      glowStops, span: stripWidth, side: side,
      core: color.blended(withFraction: coreTint, of: .white) ?? color)
    glow.frame = CGRect(x: left ? 0 : haloWidth - stripWidth, y: 0, width: stripWidth, height: height)
    let mask = CAGradientLayer()
    mask.frame = bounds
    let edges = taperSteps.map { ($0.fraction * endTaper, $0.alpha) }
    let points = edges + edges.reversed().map { (1 - $0.0, $0.1) }
    mask.colors = points.map { NSColor(white: 0, alpha: $0.1).cgColor }
    mask.locations = points.map { NSNumber(value: Double($0.0)) }
    mask.startPoint = CGPoint(x: 0.5, y: 0)
    mask.endPoint = CGPoint(x: 0.5, y: 1)
    light.mask = mask
    breath.addSublayer(halo)
    breath.addSublayer(glow)
    light.addSublayer(breath)
    return Layers(
      light: light, mask: mask, breath: breath, label: label, side: side, reduceMotion: reduceMotion)
  }

  // The first stop always sits against the edge; the gradient mirrors on the right side.
  private func gradient(
    _ stops: [(offset: CGFloat, alpha: CGFloat)], span: CGFloat, side: Side, core: NSColor?
  ) -> CAGradientLayer {
    let layer = CAGradientLayer()
    let edge = core.map { [($0, CGFloat(0))] } ?? []
    let points = edge + stops.map { (color.withAlphaComponent($0.alpha), $0.offset) }
    layer.colors = points.map { $0.0.cgColor }
    layer.locations = points.map { NSNumber(value: Double($0.1 / span)) }
    layer.startPoint = CGPoint(x: side == .left ? 0 : 1, y: 0.5)
    layer.endPoint = CGPoint(x: side == .left ? 1 : 0, y: 0.5)
    return layer
  }

  private func makeLabel() -> NSView {
    let text = NSTextField(labelWithString: name)
    text.font = .systemFont(ofSize: fontSize, weight: .semibold)
    text.textColor = textIsBlack ? .black : .white
    text.lineBreakMode = .byTruncatingTail
    text.maximumNumberOfLines = 1
    text.sizeToFit()
    let textWidth = min(text.frame.width, maxTextWidth)
    text.frame = NSRect(
      x: labelPadding, y: (labelHeight - text.frame.height) / 2,
      width: textWidth, height: text.frame.height)
    let background = NSView(frame: NSRect(
      x: 0, y: 0, width: textWidth + 2 * labelPadding, height: labelHeight))
    background.wantsLayer = true
    if let layer = background.layer {
      layer.backgroundColor = color.cgColor
      layer.cornerRadius = labelCornerRadius
      layer.masksToBounds = false
      layer.shadowColor = color.cgColor
      layer.shadowOpacity = labelGlowAlpha
      layer.shadowRadius = labelGlowRadius
      layer.shadowOffset = .zero
      layer.shadowPath = CGPath(
        roundedRect: background.bounds, cornerWidth: labelCornerRadius,
        cornerHeight: labelCornerRadius, transform: nil)
    }
    background.addSubview(text)
    return background
  }
}
