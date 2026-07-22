import AppKit
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class TeleprompterModel {
  static let playbackSpeedRange = 0.5...3.0
  static let fontSizeRange = 24.0...72.0
  static let islandBackgroundOpacityRange = 0.15...1.0
  static let basePointsPerSecond = 30.0
  static let defaultIslandBackgroundColor = Color(
    .sRGB,
    red: 0.055,
    green: 0.06,
    blue: 0.075
  )

  static let sampleScript = """
    Your words belong right here, close to the camera.

    Press play when you are ready. The script will move at a steady pace while you keep natural eye contact.

    Open playback settings to paste your own script, tune the speed, or make the type larger. Drag the center handle to detach this window from the notch, then resize it from any edge.

    When you want it back, use the pin button to return the teleprompter to the top center of your screen.
    """

  private enum DefaultsKey {
    static let script = "teleprompter.script"
    static let playbackSpeed = "teleprompter.playbackSpeed"
    static let fontSize = "teleprompter.fontSize"
    static let captureExclusion = "teleprompter.captureExclusion"
    static let islandBackgroundColor = "teleprompter.islandBackgroundColor"
    static let islandBackgroundOpacity = "teleprompter.islandBackgroundOpacity"
    static let markdownMode = "teleprompter.markdownMode"
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var lastTickUptime: TimeInterval?
  @ObservationIgnored private var pendingScrollProgress: Double?

  var script: String {
    didSet {
      defaults.set(script, forKey: DefaultsKey.script)
      guard script != oldValue else { return }
      stopAndReset()
    }
  }

  var playbackSpeed: Double {
    didSet {
      defaults.set(playbackSpeed, forKey: DefaultsKey.playbackSpeed)
    }
  }

  var fontSize: Double {
    didSet {
      defaults.set(fontSize, forKey: DefaultsKey.fontSize)
      guard fontSize != oldValue else { return }
      pendingScrollProgress = progress
      pause()
    }
  }

  var captureExclusionEnabled: Bool {
    didSet {
      defaults.set(captureExclusionEnabled, forKey: DefaultsKey.captureExclusion)
    }
  }

  var islandBackgroundColor: Color {
    didSet {
      Self.save(color: islandBackgroundColor, to: defaults)
    }
  }

  var islandBackgroundOpacity: Double {
    didSet {
      let clampedOpacity = min(
        max(islandBackgroundOpacity, Self.islandBackgroundOpacityRange.lowerBound),
        Self.islandBackgroundOpacityRange.upperBound
      )
      if islandBackgroundOpacity != clampedOpacity {
        islandBackgroundOpacity = clampedOpacity
      }
      defaults.set(clampedOpacity, forKey: DefaultsKey.islandBackgroundOpacity)
    }
  }

  var markdownMode: Bool {
    didSet {
      defaults.set(markdownMode, forKey: DefaultsKey.markdownMode)
      guard markdownMode != oldValue else { return }
      pendingScrollProgress = progress
      pause()
    }
  }

  var isPlaying = false
  var scrollOffset = 0.0
  var scrollLimit = 0.0
  var isAttachedToNotch = true
  var screenTopInset = 0.0
  var screenNotchWidth = 0.0
  var supportsCompactNotch = false
  var notchPresentation = NotchPresentation.expanded
  var isSettingsPresented = false

  var isCompactAtNotch: Bool {
    isAttachedToNotch && supportsCompactNotch && notchPresentation == .compact
  }

  var pointsPerSecond: Double {
    Self.basePointsPerSecond * playbackSpeed
  }

  var hasScript: Bool {
    !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var progress: Double {
    guard scrollLimit > 0 else { return 0 }
    return min(max(scrollOffset / scrollLimit, 0), 1)
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    script = defaults.string(forKey: DefaultsKey.script) ?? Self.sampleScript

    let savedSpeed = defaults.object(forKey: DefaultsKey.playbackSpeed) as? Double ?? 1.0
    playbackSpeed = min(
      max(savedSpeed, Self.playbackSpeedRange.lowerBound), Self.playbackSpeedRange.upperBound)

    let savedFontSize = defaults.object(forKey: DefaultsKey.fontSize) as? Double ?? 38.0
    fontSize = min(max(savedFontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)

    islandBackgroundColor =
      Self.restoredIslandBackgroundColor(from: defaults) ?? Self.defaultIslandBackgroundColor

    let savedBackgroundOpacity =
      defaults.object(forKey: DefaultsKey.islandBackgroundOpacity) as? Double ?? 1.0
    islandBackgroundOpacity = min(
      max(savedBackgroundOpacity, Self.islandBackgroundOpacityRange.lowerBound),
      Self.islandBackgroundOpacityRange.upperBound
    )

    markdownMode = defaults.bool(forKey: DefaultsKey.markdownMode)

    if defaults.object(forKey: DefaultsKey.captureExclusion) == nil {
      captureExclusionEnabled = true
    } else {
      captureExclusionEnabled = defaults.bool(forKey: DefaultsKey.captureExclusion)
    }
  }

  func togglePlayback(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    if isPlaying {
      pause()
    } else {
      play(now: now)
    }
  }

  func play(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    guard hasScript, scrollLimit > 0 else { return }
    if scrollOffset >= scrollLimit {
      scrollOffset = 0
    }
    lastTickUptime = now
    isPlaying = true
  }

  func pause() {
    isPlaying = false
    lastTickUptime = nil
  }

  func restart(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    pendingScrollProgress = nil
    scrollOffset = 0
    lastTickUptime = isPlaying ? now : nil
  }

  func scroll(by delta: Double) {
    guard delta.isFinite, abs(delta) > 0.01 else { return }
    if isPlaying {
      pause()
    }
    pendingScrollProgress = nil

    guard scrollLimit > 0 else { return }
    let nextOffset = min(max(scrollOffset + delta, 0), scrollLimit)
    if abs(scrollOffset - nextOffset) > 0.01 {
      scrollOffset = nextOffset
    }
  }

  func tick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    guard isPlaying, scrollLimit > 0 else { return }
    guard let previousTick = lastTickUptime else {
      lastTickUptime = now
      return
    }

    // Limit a single step so waking the Mac never jumps past several paragraphs.
    let elapsed = min(max(now - previousTick, 0), 0.25)
    lastTickUptime = now
    scrollOffset = min(scrollLimit, scrollOffset + elapsed * pointsPerSecond)

    if scrollOffset >= scrollLimit {
      pause()
    }
  }

  func updateScrollLimit(_ newLimit: Double) {
    let nextLimit = max(0, newLimit)
    let nextOffset: Double
    if let pendingScrollProgress {
      nextOffset = nextLimit * pendingScrollProgress
      self.pendingScrollProgress = nil
    } else {
      nextOffset = min(scrollOffset, nextLimit)
    }

    // Text measurement can report the same fractional size several times during a
    // window animation. Avoid publishing redundant observation changes back into layout.
    if abs(scrollLimit - nextLimit) > 0.01 {
      scrollLimit = nextLimit
    }
    if abs(scrollOffset - nextOffset) > 0.01 {
      scrollOffset = nextOffset
    }
    if nextLimit == 0, isPlaying {
      pause()
    }
  }

  func replaceScript(with newScript: String) {
    script = newScript
  }

  private func stopAndReset() {
    pendingScrollProgress = nil
    pause()
    scrollOffset = 0
  }

  private static func save(color: Color, to defaults: UserDefaults) {
    guard let color = NSColor(color).usingColorSpace(.sRGB) else { return }
    defaults.set(
      [
        Double(color.redComponent),
        Double(color.greenComponent),
        Double(color.blueComponent),
      ],
      forKey: DefaultsKey.islandBackgroundColor
    )
  }

  private static func restoredIslandBackgroundColor(from defaults: UserDefaults) -> Color? {
    guard let storedComponents = defaults.array(forKey: DefaultsKey.islandBackgroundColor) else {
      return nil
    }
    let components = storedComponents.compactMap { ($0 as? NSNumber)?.doubleValue }
    guard components.count == 3, components.allSatisfy(\.isFinite) else { return nil }

    return Color(
      .sRGB,
      red: min(max(components[0], 0), 1),
      green: min(max(components[1], 0), 1),
      blue: min(max(components[2], 0), 1)
    )
  }
}
