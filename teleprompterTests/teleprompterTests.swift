import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import teleprompter

@MainActor
struct TeleprompterTests {
  @Test func playbackUsesElapsedTimeAndSelectedSpeed() {
    let model = makeModel()
    model.playbackSpeed = 2
    model.updateScrollLimit(500)

    model.play(now: 10)
    model.tick(now: 11)

    // A single update is capped to avoid a large jump after sleep or a stalled run loop.
    #expect(model.scrollOffset == 15)
    #expect(model.isPlaying)

    model.tick(now: 11.1)
    #expect(abs(model.scrollOffset - 21) < 0.001)
  }

  @Test func playbackClampsAtEndAndStops() {
    let model = makeModel()
    model.updateScrollLimit(10)
    model.play(now: 20)

    model.tick(now: 20.25)
    model.tick(now: 20.5)

    #expect(model.scrollOffset == 10)
    #expect(!model.isPlaying)
    #expect(model.progress == 1)
  }

  @Test func changingScriptStopsAndRewinds() {
    let model = makeModel()
    model.updateScrollLimit(200)
    model.play(now: 30)
    model.tick(now: 30.2)

    model.replaceScript(with: "A new script")

    #expect(!model.isPlaying)
    #expect(model.scrollOffset == 0)
    #expect(model.script == "A new script")
  }

  @Test func pauseAndResumeExcludePausedTime() {
    let model = makeModel()
    model.updateScrollLimit(500)
    model.play(now: 10)
    model.tick(now: 10.1)
    let pausedOffset = model.scrollOffset

    model.pause()
    model.play(now: 100)
    model.tick(now: 100.1)

    #expect(abs(model.scrollOffset - (pausedOffset + 3)) < 0.001)
  }

  @Test func restartWhilePlayingKeepsPlaybackActive() {
    let model = makeModel()
    model.updateScrollLimit(500)
    model.play(now: 10)
    model.tick(now: 10.1)

    model.restart(now: 20)
    #expect(model.scrollOffset == 0)
    #expect(model.isPlaying)

    model.tick(now: 20.1)
    #expect(abs(model.scrollOffset - 3) < 0.001)
  }

  @Test func manualScrollClampsAndPausesPlayback() {
    let model = makeModel()
    model.updateScrollLimit(100)

    model.scroll(by: 35)
    #expect(model.scrollOffset == 35)

    model.play(now: 10)
    model.scroll(by: 500)
    #expect(!model.isPlaying)
    #expect(model.scrollOffset == 100)

    model.scroll(by: -500)
    #expect(model.scrollOffset == 0)
  }

  @Test func islandAppearancePersists() throws {
    let defaults = makeDefaults()
    let model = TeleprompterModel(defaults: defaults)
    model.updateScrollLimit(100)
    model.play(now: 10)
    model.islandBackgroundColor = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6)
    model.islandBackgroundOpacity = 0.45

    #expect(model.isPlaying)

    let restoredModel = TeleprompterModel(defaults: defaults)
    let restoredColor = try #require(
      NSColor(restoredModel.islandBackgroundColor).usingColorSpace(.sRGB))

    #expect(abs(restoredColor.redComponent - 0.2) < 0.01)
    #expect(abs(restoredColor.greenComponent - 0.4) < 0.01)
    #expect(abs(restoredColor.blueComponent - 0.6) < 0.01)
    #expect(restoredModel.islandBackgroundOpacity == 0.45)
  }

  @Test func fontChangePreservesNormalizedPositionAndPauses() {
    let model = makeModel()
    model.updateScrollLimit(100)
    model.scrollOffset = 50
    model.play(now: 10)

    model.fontSize = 48
    model.updateScrollLimit(200)

    #expect(!model.isPlaying)
    #expect(model.scrollOffset == 100)
  }

  @Test func emptyScriptCannotPlay() {
    let model = makeModel()
    model.replaceScript(with: "  \n  ")
    model.updateScrollLimit(100)

    model.play(now: 10)

    #expect(!model.isPlaying)
    #expect(model.scrollOffset == 0)
  }

  @Test func notchedScreenCentersOnCameraHousingAndUsesScreenTop() {
    let geometry = NotchScreenGeometry(
      frame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
      visibleFrame: CGRect(x: -1512, y: 0, width: 1512, height: 944),
      safeAreaTop: 38,
      auxiliaryTopLeftArea: CGRect(x: -1512, y: 944, width: 650, height: 38),
      auxiliaryTopRightArea: CGRect(x: -650, y: 944, width: 650, height: 38)
    )

    let frame = geometry.attachedFrame(for: CGSize(width: 720, height: 340))
    let compactFrame = geometry.compactNotchFrame()

    #expect(geometry.hasNotch)
    #expect(geometry.notchWidth == 212)
    #expect(frame.midX == -756)
    #expect(frame.maxY == 982)
    #expect(frame.minY == 642)
    #expect(geometry.topContentInset == 38)
    #expect(compactFrame.midX == -756)
    #expect(compactFrame.maxY == 982)
    #expect(compactFrame.width == 396)
    #expect(compactFrame.height == 48)
  }

  @Test func ordinaryScreenAnchorsBelowMenuBar() {
    let geometry = NotchScreenGeometry(
      frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
      visibleFrame: CGRect(x: 0, y: 40, width: 1920, height: 1015),
      safeAreaTop: 0
    )

    let frame = geometry.attachedFrame(for: CGSize(width: 700, height: 300))

    #expect(!geometry.hasNotch)
    #expect(frame.midX == 960)
    #expect(frame.maxY == 1055)
    #expect(geometry.topContentInset == 0)
  }

  @Test func attachedExpandedMinimumLeavesRoomOutsideTheNotchControls() {
    let minimumSize = TeleprompterNotchLayout.attachedExpandedMinimumSize(notchWidth: 212)

    #expect(minimumSize.width == 652)
    #expect(minimumSize.height == TeleprompterNotchLayout.expandedMinimumSize.height)
  }

  @Test func panelIsResizableDetachableAndCaptureProtectedByDefault() throws {
    let defaults = makeDefaults()
    let model = TeleprompterModel(defaults: defaults)
    let controller = TeleprompterWindowController(
      model: model,
      windowDefaults: defaults,
      shouldObserveScreens: false
    )
    let panel = try #require(controller.window as? TeleprompterPanel)

    #expect(panel.styleMask.contains(.resizable))
    #expect(panel.minSize.width >= 460)
    #expect(panel.minSize.height >= 220)
    #expect(panel.sharingType == .none)
    #expect(model.isAttachedToNotch)
    #expect(model.notchPresentation == .expanded)
    #expect(panel.level == (model.supportsCompactNotch ? .statusBar : .floating))
    #expect(!panel.isMovable)
    if model.supportsCompactNotch {
      #expect(
        panel.minSize
          == TeleprompterNotchLayout.attachedExpandedMinimumSize(
            notchWidth: model.screenNotchWidth
          )
      )
      #expect(panel.frame.width >= panel.minSize.width)
    }

    let expandedFrame = panel.frame
    if model.supportsCompactNotch {
      model.updateScrollLimit(100)
      model.play(now: 10)
      controller.collapseIntoNotch(animated: false)

      #expect(model.isCompactAtNotch)
      #expect(!model.isPlaying)
      #expect(!panel.styleMask.contains(.resizable))
      #expect(panel.frame.width < expandedFrame.width)
      #expect(panel.sharingType == .none)

      controller.expandFromNotch(animated: false)

      #expect(model.notchPresentation == .expanded)
      #expect(panel.styleMask.contains(.resizable))
      #expect(panel.frame.size == expandedFrame.size)
      #expect(panel.sharingType == .none)
    }

    let visibleDefaults = makeDefaults()
    let visibleModel = TeleprompterModel(defaults: visibleDefaults)
    visibleModel.captureExclusionEnabled = false
    let visibleController = TeleprompterWindowController(
      model: visibleModel,
      windowDefaults: visibleDefaults,
      shouldObserveScreens: false
    )
    let visiblePanel = try #require(visibleController.window as? TeleprompterPanel)
    #expect(visiblePanel.sharingType == .readOnly)

    controller.toggleAttachment()
    #expect(!model.isAttachedToNotch)
    #expect(model.notchPresentation == .expanded)
    #expect(panel.styleMask.contains(.resizable))
    #expect(panel.level == .floating)
    #expect(panel.isMovable)
    #expect(panel.minSize == TeleprompterNotchLayout.expandedMinimumSize)

    model.updateScrollLimit(100)
    model.play(now: 10)
    controller.closeTeleprompter()
    #expect(!model.isPlaying)
  }

  @Test func swiftUIContentCannotDrivePanelSizing() throws {
    let defaults = makeDefaults()
    let controller = TeleprompterWindowController(
      model: TeleprompterModel(defaults: defaults),
      windowDefaults: defaults,
      shouldObserveScreens: false
    )
    let panel = try #require(controller.window as? TeleprompterPanel)
    let container = try #require(
      panel.contentView as? TeleprompterHostingContainer<ContentView>)

    #expect(panel.contentViewController == nil)
    #expect(container.hostingView.sizingOptions == [])
    #expect(container.hostingView.safeAreaRegions == [])
    #expect(container.hostingView.autoresizingMask.contains(.width))
    #expect(container.hostingView.autoresizingMask.contains(.height))
  }

  @Test func visiblePanelSurvivesClickThroughTransitions() async throws {
    let defaults = makeDefaults()
    let model = TeleprompterModel(defaults: defaults)
    let controller = TeleprompterWindowController(
      model: model,
      windowDefaults: defaults,
      shouldObserveScreens: false
    )
    let panel = try #require(controller.window as? TeleprompterPanel)

    controller.showTeleprompter(activate: false)
    defer { controller.closeTeleprompter() }
    try await settleWindowLayout()

    if model.supportsCompactNotch {
      for _ in 0..<3 {
        controller.collapseIntoNotch(animated: true)
        try await settleWindowLayout()
        #expect(model.isCompactAtNotch)

        controller.presentSettings()
        try await settleWindowLayout()
        #expect(model.notchPresentation == .expanded)
        #expect(model.isSettingsPresented)

        model.isSettingsPresented = false
        try await settleWindowLayout()
      }
    }

    controller.toggleAttachment()
    try await settleWindowLayout()
    #expect(!model.isAttachedToNotch)
    #expect(panel.styleMask.contains(.resizable))

    controller.toggleAttachment()
    try await settleWindowLayout()
    #expect(model.isAttachedToNotch)
  }

  private func makeModel() -> TeleprompterModel {
    TeleprompterModel(defaults: makeDefaults())
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "TeleprompterTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func settleWindowLayout() async throws {
    try await Task.sleep(for: .milliseconds(450))
  }
}
