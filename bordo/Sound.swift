import AppKit

struct SoundFailed: Error {}

private let volume: Float = 0.6
// Cap against a delegate callback that never comes: the sound process must not linger.
private let maxSoundSeconds: TimeInterval = 5

/// Glass when the turn is done, Ping for a question; `onFinish` fires at the end of the sound or after `maxSoundSeconds`.
final class SoundPlayer: NSObject, NSSoundDelegate {
  private let sound: NSSound
  private let onFinish: () -> Void

  init(mode: Mode, onFinish: @escaping () -> Void) throws {
    let name = mode == .done ? "Glass" : "Ping"
    guard let sound = NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)
    else { throw SoundFailed() }
    self.sound = sound
    self.onFinish = onFinish
    super.init()
  }

  /// The return of `play()` is the last step: it is the instant that `ms=` measures.
  func play() throws {
    sound.volume = volume
    sound.delegate = self
    Timer.scheduledTimer(
      timeInterval: maxSoundSeconds, target: self, selector: #selector(timeOut),
      userInfo: nil, repeats: false)
    guard sound.play() else { throw SoundFailed() }
  }

  func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
    onFinish()
  }

  @objc private func timeOut() {
    onFinish()
  }
}
