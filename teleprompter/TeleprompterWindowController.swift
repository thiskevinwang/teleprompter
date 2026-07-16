import AppKit
import SwiftUI

struct NotchScreenGeometry: Equatable {
  let frame: CGRect
  let visibleFrame: CGRect
  let safeAreaTop: CGFloat
  let auxiliaryTopLeftArea: CGRect?
  let auxiliaryTopRightArea: CGRect?

  init(screen: NSScreen) {
    frame = screen.frame
    visibleFrame = screen.visibleFrame
    safeAreaTop = screen.safeAreaInsets.top
    auxiliaryTopLeftArea = screen.auxiliaryTopLeftArea
    auxiliaryTopRightArea = screen.auxiliaryTopRightArea
  }

  init(
    frame: CGRect,
    visibleFrame: CGRect,
    safeAreaTop: CGFloat,
    auxiliaryTopLeftArea: CGRect? = nil,
    auxiliaryTopRightArea: CGRect? = nil
  ) {
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.safeAreaTop = safeAreaTop
    self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
    self.auxiliaryTopRightArea = auxiliaryTopRightArea
  }

  var hasNotch: Bool {
    guard let left = auxiliaryTopLeftArea,
      let right = auxiliaryTopRightArea,
      !left.isEmpty,
      !right.isEmpty
    else {
      return safeAreaTop > 0
    }
    return left.maxX < right.minX
  }

  var topContentInset: CGFloat {
    hasNotch ? max(safeAreaTop, frame.maxY - visibleFrame.maxY) : 0
  }

  var notchWidth: CGFloat {
    guard hasNotch else { return 0 }
    if let left = auxiliaryTopLeftArea,
      let right = auxiliaryTopRightArea,
      !left.isEmpty,
      !right.isEmpty,
      left.maxX < right.minX
    {
      return right.minX - left.maxX
    }
    return min(220, visibleFrame.width / 5)
  }

  var compactNotchSize: CGSize {
    TeleprompterNotchLayout.compactSize(
      notchWidth: notchWidth,
      notchHeight: topContentInset
    )
  }

  var attachedTopY: CGFloat {
    hasNotch ? frame.maxY : visibleFrame.maxY
  }

  func attachedFrame(for requestedSize: CGSize) -> CGRect {
    let width = min(max(requestedSize.width, 1), visibleFrame.width)
    let availableHeight = max(1, attachedTopY - visibleFrame.minY)
    let height = min(max(requestedSize.height, 1), availableHeight)

    let centerX: CGFloat
    if let left = auxiliaryTopLeftArea,
      let right = auxiliaryTopRightArea,
      !left.isEmpty,
      !right.isEmpty,
      left.maxX < right.minX
    {
      centerX = (left.maxX + right.minX) / 2
    } else {
      centerX = frame.midX
    }

    let minimumX = visibleFrame.minX
    let maximumX = visibleFrame.maxX - width
    let x = min(max(centerX - width / 2, minimumX), maximumX)
    return CGRect(x: x, y: attachedTopY - height, width: width, height: height)
  }

  func compactNotchFrame() -> CGRect {
    attachedFrame(for: compactNotchSize)
  }

  func detachedFrame(for proposedFrame: CGRect) -> CGRect {
    let width = min(max(proposedFrame.width, 1), visibleFrame.width)
    let height = min(max(proposedFrame.height, 1), visibleFrame.height)
    let maximumX = visibleFrame.maxX - width
    let maximumY = visibleFrame.maxY - height
    let x = min(max(proposedFrame.minX, visibleFrame.minX), maximumX)
    let y = min(max(proposedFrame.minY, visibleFrame.minY), maximumY)
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

final class TeleprompterPanel: NSPanel {
  var allowsTopScreenArea = false

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    guard allowsTopScreenArea, let screen else {
      return super.constrainFrameRect(frameRect, to: screen)
    }

    let geometry = NotchScreenGeometry(screen: screen)
    let width = min(max(frameRect.width, 1), geometry.visibleFrame.width)
    let availableHeight = max(1, geometry.attachedTopY - geometry.visibleFrame.minY)
    let height = min(max(frameRect.height, 1), availableHeight)
    let maximumX = geometry.visibleFrame.maxX - width
    let maximumY = geometry.attachedTopY - height
    let x = min(max(frameRect.minX, geometry.visibleFrame.minX), maximumX)
    let y = min(max(frameRect.minY, geometry.visibleFrame.minY), maximumY)
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

/// Keeps SwiftUI's content measurements from becoming window-sizing constraints.
/// The panel owns its frame; the hosting view only autoresizes inside that frame.
final class TeleprompterHostingContainer<Content: View>: NSView {
  let hostingView: NSHostingView<Content>

  init(rootView: Content, frame: CGRect) {
    hostingView = NSHostingView(rootView: rootView)
    super.init(frame: frame)

    autoresizingMask = [.width, .height]
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@MainActor
final class TeleprompterWindowController: NSWindowController, NSWindowDelegate {
  static let preview: TeleprompterWindowController = {
    let defaults = UserDefaults(suiteName: "TeleprompterPreviewWindow")!
    defaults.removePersistentDomain(forName: "TeleprompterPreviewWindow")
    return TeleprompterWindowController(
      model: TeleprompterModel(defaults: defaults),
      windowDefaults: defaults,
      shouldObserveScreens: false
    )
  }()

  private enum DefaultsKey {
    static let windowWidth = "teleprompter.windowWidth"
    static let windowHeight = "teleprompter.windowHeight"
    static let attached = "teleprompter.windowAttached"
    static let detachedFrame = "teleprompter.detachedFrame"
  }

  let model: TeleprompterModel

  private let windowDefaults: UserDefaults
  private var screenParametersObserver: NSObjectProtocol?
  private var preferredAttachedScreen: NSScreen?
  private var expandedSize: CGSize
  private var isDraggingWindow = false
  private var dragCompletionTask: Task<Void, Never>?
  private var settingsPresentationTask: Task<Void, Never>?

  init(
    model: TeleprompterModel,
    windowDefaults: UserDefaults = .standard,
    shouldObserveScreens: Bool = true
  ) {
    self.model = model
    self.windowDefaults = windowDefaults

    let initialSize = Self.restoredSize(from: windowDefaults)
    expandedSize = initialSize
    let panel = TeleprompterPanel(
      contentRect: CGRect(origin: .zero, size: initialSize),
      styleMask: [.borderless, .resizable, .closable],
      backing: .buffered,
      defer: false
    )

    super.init(window: panel)

    panel.title = "Teleprompter"
    panel.delegate = self
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovableByWindowBackground = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.minSize = TeleprompterNotchLayout.expandedMinimumSize
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .canJoinAllApplications,
      .fullScreenAuxiliary,
      .ignoresCycle,
    ]
    let hostingContainer = TeleprompterHostingContainer(
      rootView: ContentView(model: model, windowController: self),
      frame: panel.contentView?.bounds ?? CGRect(origin: .zero, size: initialSize)
    )
    panel.contentView = hostingContainer
    panel.setFrame(CGRect(origin: panel.frame.origin, size: initialSize), display: false)

    applyCaptureExclusion()
    restorePlacement()

    if shouldObserveScreens {
      screenParametersObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.screenParametersChanged()
        }
      }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    dragCompletionTask?.cancel()
    settingsPresentationTask?.cancel()
    if let screenParametersObserver {
      NotificationCenter.default.removeObserver(screenParametersObserver)
    }
  }

  func showTeleprompter(activate: Bool) {
    guard let panel = window else { return }
    if model.isAttachedToNotch {
      attachToNotch(animated: false)
    } else {
      clampDetachedWindow(animated: false)
    }
    if activate {
      NSApp.activate()
      panel.makeKeyAndOrderFront(nil)
    } else {
      panel.orderFrontRegardless()
    }
    // Ordering a borderless panel can make AppKit constrain it below the menu bar once.
    // Reapply the public notch geometry after the panel is visible so its top edge stays flush.
    if model.isAttachedToNotch {
      attachToNotch(animated: false)
    }
  }

  func toggleAttachment() {
    cancelDragMonitoring()
    if model.isAttachedToNotch {
      detachFromNotch()
    } else {
      attachToNotch(animated: true)
    }
  }

  func toggleNotchPresentation() {
    if model.isCompactAtNotch {
      expandFromNotch(animated: true)
    } else {
      collapseIntoNotch(animated: true)
    }
  }

  func presentSettings() {
    settingsPresentationTask?.cancel()
    showTeleprompter(activate: true)

    // A popover cannot safely attach while its toolbar anchor is being inserted and
    // the parent panel is animating from compact to expanded geometry.
    expandFromNotch(animated: false)
    settingsPresentationTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard !Task.isCancelled, let self, self.window?.isVisible == true else { return }
      self.model.isSettingsPresented = true
      self.applyCaptureExclusion()
      self.settingsPresentationTask = nil
    }
  }

  func collapseIntoNotch(animated: Bool) {
    guard model.isAttachedToNotch,
      let panel = window as? TeleprompterPanel,
      let screen = targetScreen(for: panel)
    else { return }

    let geometry = NotchScreenGeometry(screen: screen)
    guard geometry.hasNotch else { return }

    if panel.frame.width >= TeleprompterNotchLayout.expandedMinimumSize.width,
      panel.frame.height >= TeleprompterNotchLayout.expandedMinimumSize.height
    {
      expandedSize = panel.frame.size
    }
    settingsPresentationTask?.cancel()
    settingsPresentationTask = nil
    model.pause()
    model.isSettingsPresented = false
    configurePanel(panel, for: .compact, geometry: geometry)
    withAnimation(.snappy(duration: 0.38, extraBounce: 0.08)) {
      model.notchPresentation = .compact
    }
    setPanelFrame(panel, to: geometry.compactNotchFrame(), animated: animated)
  }

  func expandFromNotch(animated: Bool) {
    guard model.isAttachedToNotch,
      let panel = window as? TeleprompterPanel,
      let screen = targetScreen(for: panel)
    else { return }

    let geometry = NotchScreenGeometry(screen: screen)
    configurePanel(panel, for: .expanded, geometry: geometry)
    withAnimation(.snappy(duration: 0.38, extraBounce: 0.08)) {
      model.notchPresentation = .expanded
    }
    setPanelFrame(
      panel,
      to: expandedAttachedFrame(in: geometry),
      animated: animated
    )
  }

  func expandAndTogglePlayback() {
    expandFromNotch(animated: true)
    model.togglePlayback()
  }

  func detachForDrag() {
    guard let panel = window as? TeleprompterPanel else { return }
    ensureExpanded(panel, animated: false)
    panel.level = .floating
    panel.isMovable = true
    isDraggingWindow = true
    model.isAttachedToNotch = false
    // Keep the safe inset and top-area allowance until the drag finishes so the grip never jumps.
    panel.allowsTopScreenArea = true
    windowDefaults.set(false, forKey: DefaultsKey.attached)
    scheduleDragCompletionCheck()
  }

  func finishDragging() {
    guard isDraggingWindow else { return }
    isDraggingWindow = false
    dragCompletionTask?.cancel()
    dragCompletionTask = nil

    guard !model.isAttachedToNotch,
      let panel = window as? TeleprompterPanel,
      let screen = bestAvailableScreen(for: panel.frame)
    else { return }

    let target = NotchScreenGeometry(screen: screen).attachedFrame(for: panel.frame.size)
    let topDistance = abs(panel.frame.maxY - target.maxY)
    let horizontalDistance = abs(panel.frame.midX - target.midX)
    if topDistance <= 40, horizontalDistance <= 56 {
      attachToNotch(on: screen, animated: true)
      return
    }

    panel.allowsTopScreenArea = false
    clampDetachedWindow(to: screen, animated: false)
    model.screenTopInset = 0
    model.screenNotchWidth = 0
    model.supportsCompactNotch = false
  }

  func attachToNotch(animated: Bool) {
    guard let panel = window, let screen = targetScreen(for: panel) else { return }
    attachToNotch(on: screen, animated: animated)
  }

  func closeTeleprompter() {
    cancelDragMonitoring()
    settingsPresentationTask?.cancel()
    settingsPresentationTask = nil
    model.pause()
    model.isSettingsPresented = false
    if !model.isAttachedToNotch {
      saveDetachedFrame()
    }
    window?.orderOut(nil)
  }

  func applyCaptureExclusion() {
    let sharingType: NSWindow.SharingType = model.captureExclusionEnabled ? .none : .readOnly
    window?.sharingType = sharingType
    guard model.isSettingsPresented else { return }

    applyCaptureExclusionToPresentedWindows(sharingType)
    Task { @MainActor [weak self] in
      await Task.yield()
      self?.applyCaptureExclusionToPresentedWindows(sharingType)
    }
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let panel = window else { return }
    guard !model.isCompactAtNotch else { return }
    expandedSize = panel.frame.size
    if model.isAttachedToNotch {
      attachToNotch(animated: false)
    } else {
      clampDetachedWindow(animated: false)
    }
    expandedSize = panel.frame.size
    Self.save(size: expandedSize, to: windowDefaults)
  }

  func windowDidChangeScreen(_ notification: Notification) {
    if model.isAttachedToNotch {
      attachToNotch(animated: false)
    }
  }

  func windowDidMove(_ notification: Notification) {
    if isDraggingWindow {
      scheduleDragCompletionCheck()
    } else if !model.isAttachedToNotch {
      saveDetachedFrame()
    }
  }

  func windowWillClose(_ notification: Notification) {
    cancelDragMonitoring()
    settingsPresentationTask?.cancel()
    settingsPresentationTask = nil
    model.pause()
    model.isSettingsPresented = false
    if !model.isAttachedToNotch {
      saveDetachedFrame()
    }
  }

  private func restorePlacement() {
    let shouldAttach: Bool
    if windowDefaults.object(forKey: DefaultsKey.attached) == nil {
      shouldAttach = true
    } else {
      shouldAttach = windowDefaults.bool(forKey: DefaultsKey.attached)
    }

    if shouldAttach {
      attachToNotch(animated: false)
      return
    }

    model.isAttachedToNotch = false
    model.screenTopInset = 0
    model.screenNotchWidth = 0
    model.supportsCompactNotch = false
    model.notchPresentation = .expanded
    if let panel = window as? TeleprompterPanel {
      panel.allowsTopScreenArea = false
      configurePanel(panel, for: .expanded, geometry: nil)
    }
    if let restoredFrame = Self.restoredDetachedFrame(from: windowDefaults) {
      expandedSize = restoredFrame.size
      window?.setFrame(restoredFrame, display: false)
    }
    clampDetachedWindow(animated: false)
  }

  private func attachToNotch(on screen: NSScreen, animated: Bool) {
    guard let panel = window as? TeleprompterPanel else { return }
    if !model.isAttachedToNotch,
      panel.frame.width >= TeleprompterNotchLayout.expandedMinimumSize.width,
      panel.frame.height >= TeleprompterNotchLayout.expandedMinimumSize.height
    {
      expandedSize = panel.frame.size
    }
    preferredAttachedScreen = screen
    let geometry = NotchScreenGeometry(screen: screen)
    if !geometry.hasNotch {
      model.notchPresentation = .expanded
    }
    panel.allowsTopScreenArea = true
    panel.level = geometry.hasNotch ? .statusBar : .floating
    panel.isMovable = false
    model.isAttachedToNotch = true
    model.screenTopInset = geometry.topContentInset
    model.screenNotchWidth = geometry.notchWidth
    model.supportsCompactNotch = geometry.hasNotch
    windowDefaults.set(true, forKey: DefaultsKey.attached)
    applyAttachedPresentation(on: geometry, to: panel, animated: animated)
  }

  private func detachFromNotch() {
    guard let panel = window as? TeleprompterPanel else { return }
    ensureExpanded(panel, animated: false)
    let screen = bestAvailableScreen(for: panel.frame)
    panel.allowsTopScreenArea = false
    panel.level = .floating
    panel.isMovable = true
    // Move below the menu bar before removing the safe inset so controls are never obscured.
    clampDetachedWindow(to: screen, animated: false)
    model.isAttachedToNotch = false
    model.screenTopInset = 0
    model.screenNotchWidth = 0
    model.supportsCompactNotch = false
    model.notchPresentation = .expanded
    windowDefaults.set(false, forKey: DefaultsKey.attached)
    saveDetachedFrame()
  }

  private func clampDetachedWindow(to preferredScreen: NSScreen? = nil, animated: Bool) {
    guard let panel = window as? TeleprompterPanel else { return }
    configurePanel(panel, for: .expanded, geometry: nil)
    panel.level = .floating
    panel.isMovable = true
    let availablePreferredScreen = preferredScreen.flatMap { candidate in
      NSScreen.screens.contains(candidate) ? candidate : nil
    }
    guard let screen = availablePreferredScreen ?? bestAvailableScreen(for: panel.frame) else {
      return
    }

    panel.allowsTopScreenArea = false
    let frame = NotchScreenGeometry(screen: screen).detachedFrame(for: panel.frame)
    panel.setFrame(frame, display: true, animate: animated)
    saveDetachedFrame()
  }

  private func screenParametersChanged() {
    if model.isAttachedToNotch {
      attachToNotch(animated: false)
    } else {
      clampDetachedWindow(animated: false)
    }
  }

  private func applyAttachedPresentation(
    on geometry: NotchScreenGeometry,
    to panel: TeleprompterPanel,
    animated: Bool
  ) {
    let presentation: NotchPresentation =
      geometry.hasNotch ? model.notchPresentation : .expanded
    configurePanel(panel, for: presentation, geometry: geometry)

    let frame =
      presentation == .compact
      ? geometry.compactNotchFrame()
      : expandedAttachedFrame(in: geometry)
    setPanelFrame(panel, to: frame, animated: animated)
  }

  private func configurePanel(
    _ panel: TeleprompterPanel,
    for presentation: NotchPresentation,
    geometry: NotchScreenGeometry?
  ) {
    switch presentation {
    case .compact:
      let compactSize = geometry?.compactNotchSize ?? CGSize(width: 320, height: 42)
      panel.minSize = compactSize
      panel.styleMask.remove(.resizable)
    case .expanded:
      panel.styleMask.insert(.resizable)
      panel.minSize =
        if let geometry, geometry.hasNotch {
          TeleprompterNotchLayout.attachedExpandedMinimumSize(
            notchWidth: geometry.notchWidth
          )
        } else {
          TeleprompterNotchLayout.expandedMinimumSize
        }
    }
  }

  private func ensureExpanded(_ panel: TeleprompterPanel, animated: Bool) {
    guard model.isCompactAtNotch,
      let screen = targetScreen(for: panel)
    else {
      configurePanel(panel, for: .expanded, geometry: nil)
      return
    }

    let geometry = NotchScreenGeometry(screen: screen)
    configurePanel(panel, for: .expanded, geometry: geometry)
    withAnimation(.snappy(duration: 0.38, extraBounce: 0.08)) {
      model.notchPresentation = .expanded
    }
    setPanelFrame(
      panel,
      to: expandedAttachedFrame(in: geometry),
      animated: animated
    )
  }

  private func setPanelFrame(_ panel: NSWindow, to frame: CGRect, animated: Bool) {
    guard panel.frame != frame else { return }
    panel.setFrame(frame, display: true, animate: animated)
  }

  private func expandedAttachedFrame(in geometry: NotchScreenGeometry) -> CGRect {
    let minimumSize = TeleprompterNotchLayout.attachedExpandedMinimumSize(
      notchWidth: geometry.notchWidth
    )
    return geometry.attachedFrame(
      for: CGSize(
        width: max(expandedSize.width, minimumSize.width),
        height: max(expandedSize.height, minimumSize.height)
      )
    )
  }

  private func targetScreen(for panel: NSWindow) -> NSScreen? {
    if let screen = panel.screen, panel.isVisible {
      return screen
    }
    if let preferredAttachedScreen, NSScreen.screens.contains(preferredAttachedScreen) {
      return preferredAttachedScreen
    }
    return NSScreen.screens.first(where: { NotchScreenGeometry(screen: $0).hasNotch })
      ?? NSScreen.main
      ?? NSScreen.screens.first
  }

  private func bestAvailableScreen(for windowFrame: CGRect) -> NSScreen? {
    let rankedScreens = NSScreen.screens.map { screen in
      let intersection = screen.visibleFrame.intersection(windowFrame)
      let area = intersection.isNull ? 0 : intersection.width * intersection.height
      return (screen: screen, area: area)
    }
    if let best = rankedScreens.max(by: { $0.area < $1.area }), best.area > 0 {
      return best.screen
    }
    return NSScreen.main ?? NSScreen.screens.first
  }

  private func applyCaptureExclusionToPresentedWindows(_ sharingType: NSWindow.SharingType) {
    for applicationWindow in NSApp.windows where !(applicationWindow is TeleprompterPanel) {
      applicationWindow.sharingType = sharingType
    }
  }

  private func scheduleDragCompletionCheck() {
    dragCompletionTask?.cancel()
    dragCompletionTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 80_000_000)
      guard !Task.isCancelled, let self, self.isDraggingWindow else { return }

      if NSEvent.pressedMouseButtons & 1 == 0 {
        self.finishDragging()
      } else {
        self.scheduleDragCompletionCheck()
      }
    }
  }

  private func cancelDragMonitoring() {
    isDraggingWindow = false
    dragCompletionTask?.cancel()
    dragCompletionTask = nil
  }

  private func saveDetachedFrame() {
    guard let panel = window, !model.isAttachedToNotch else { return }
    windowDefaults.set(NSStringFromRect(panel.frame), forKey: DefaultsKey.detachedFrame)
  }

  private static func restoredSize(from defaults: UserDefaults) -> CGSize {
    let width = defaults.double(forKey: DefaultsKey.windowWidth)
    let height = defaults.double(forKey: DefaultsKey.windowHeight)
    guard width >= 460, height >= 220 else {
      return CGSize(width: 720, height: 340)
    }
    return CGSize(width: width, height: height)
  }

  private static func save(size: CGSize, to defaults: UserDefaults) {
    defaults.set(size.width, forKey: DefaultsKey.windowWidth)
    defaults.set(size.height, forKey: DefaultsKey.windowHeight)
  }

  private static func restoredDetachedFrame(from defaults: UserDefaults) -> CGRect? {
    guard let value = defaults.string(forKey: DefaultsKey.detachedFrame) else { return nil }
    let frame = NSRectFromString(value)
    guard frame.width > 0, frame.height > 0 else { return nil }
    return frame
  }
}
