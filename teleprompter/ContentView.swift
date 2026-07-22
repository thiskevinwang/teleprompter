//
//  ContentView.swift
//  teleprompter
//
//  Created by Kevin Wang on 7/15/26.
//

import AppKit
import SwiftUI
import Textual

struct ContentView: View {
  @Bindable var model: TeleprompterModel
  unowned let windowController: TeleprompterWindowController
  @State private var isHoveringCompactNotch = false

  var body: some View {
    ZStack(alignment: .top) {
      if model.isCompactAtNotch {
        Color.clear
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        expandedTeleprompter
          .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
      }

      if showsNotchControls {
        persistentNotchControls
      }
    }
    .background { shellBackground }
    .overlay { shellOutline }
    .mask { shellMask }
    .padding(model.isAttachedToNotch ? 0 : 6)
    .background(Color.clear)
    .preferredColorScheme(.dark)
    .animation(.snappy(duration: 0.38, extraBounce: 0.08), value: model.notchPresentation)
  }

  private var expandedTeleprompter: some View {
    VStack(spacing: 0) {
      if showsNotchControls {
        Color.clear
          .frame(height: topNotchControlHeight)
      } else {
        controlBar
          .padding(.horizontal, 14)
          .padding(.top, topChromePadding)
          .padding(.bottom, 10)
      }

      TeleprompterReader(model: model)
        .accessibilityIdentifier("teleprompter.reader")

      progressBar
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
    .frame(
      minWidth: TeleprompterNotchLayout.expandedMinimumSize.width,
      minHeight: TeleprompterNotchLayout.expandedMinimumSize.height
    )
  }

  private var persistentNotchControls: some View {
    notchControlStrip(isCompact: model.isCompactAtNotch)
      .frame(height: topNotchControlHeight)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .onTapGesture {
        if model.isCompactAtNotch {
          windowController.expandFromNotch(animated: true)
        }
      }
      .onHover { hovering in
        if model.isCompactAtNotch, hovering, !isHoveringCompactNotch {
          NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        isHoveringCompactNotch = hovering
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(
        model.isCompactAtNotch ? "Compact teleprompter" : "Teleprompter controls"
      )
      .accessibilityAction(.default) {
        if model.isCompactAtNotch {
          windowController.expandFromNotch(animated: true)
        }
      }
      .animation(nil, value: model.notchPresentation)
      .transaction { transaction in
        transaction.animation = nil
      }
  }

  private func notchControlStrip(isCompact: Bool) -> some View {
    GeometryReader { proxy in
      let coreWidth =
        model.screenNotchWidth + TeleprompterNotchLayout.compactWingWidth * 2
      let outerWidth = max(0, (proxy.size.width - coreWidth) / 2)

      HStack(spacing: 0) {
        ZStack(alignment: .trailing) {
          if !isCompact {
            playbackInfo
              .frame(maxWidth: 96, alignment: .trailing)
              .padding(.trailing, 8)
              .transition(.identity)
          }
        }
        .frame(width: outerWidth, height: proxy.size.height, alignment: .trailing)

        notchLeadingWing(isCompact: isCompact)
          .frame(width: TeleprompterNotchLayout.compactWingWidth)

        Color.clear
          .frame(width: model.screenNotchWidth)
          .accessibilityHidden(true)

        notchTrailingWing(isCompact: isCompact)
          .frame(width: TeleprompterNotchLayout.compactWingWidth)

        ZStack(alignment: .leading) {
          if !isCompact {
            expandedNotchActions
              .padding(.leading, 6)
              .transition(.identity)
          }
        }
        .frame(width: outerWidth, height: proxy.size.height, alignment: .leading)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }

  private func notchLeadingWing(isCompact: Bool) -> some View {
    HStack(spacing: 7) {
      Button {
        if isCompact {
          windowController.expandAndTogglePlayback()
        } else {
          model.togglePlayback()
        }
      } label: {
        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 10, weight: .bold))
          .frame(width: 27, height: 27)
          .foregroundStyle(model.isPlaying ? .black : .white)
          .background(
            model.isPlaying ? Color.orange : Color.white.opacity(0.12),
            in: Circle()
          )
      }
      .buttonStyle(.plain)
      .disabled(!model.hasScript || model.scrollLimit <= 0)
      .help(
        isCompact
          ? (model.isPlaying ? "Expand and pause" : "Expand and play")
          : (model.isPlaying ? "Pause" : "Play")
      )
      .accessibilityIdentifier(
        isCompact ? "teleprompter.compactPlayPause" : "teleprompter.playPause")

      if isCompact {
        Image(systemName: "text.line.first.and.arrowtriangle.forward")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 27, height: 27)
          .foregroundStyle(.white.opacity(isHoveringCompactNotch ? 0.8 : 0.48))
          .accessibilityHidden(true)
      } else {
        Button {
          model.restart()
        } label: {
          Image(systemName: "backward.end.fill")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 27, height: 27)
            .foregroundStyle(.white.opacity(0.86))
            .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Restart")
        .accessibilityIdentifier("teleprompter.restart")
      }
    }
    .padding(.leading, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private func notchTrailingWing(isCompact: Bool) -> some View {
    HStack(spacing: 7) {
      Text(model.progress, format: .percent.precision(.fractionLength(0)))
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(isHoveringCompactNotch ? 0.8 : 0.52))
        .monospacedDigit()
        .frame(width: 34, alignment: .trailing)

      Button {
        if isCompact {
          windowController.expandFromNotch(animated: true)
        } else {
          windowController.collapseIntoNotch(animated: true)
        }
      } label: {
        Image(systemName: isCompact ? "chevron.down" : "chevron.up")
          .font(.system(size: 10, weight: .bold))
          .frame(width: 27, height: 27)
          .foregroundStyle(.white.opacity(0.86))
          .background(.white.opacity(isHoveringCompactNotch ? 0.16 : 0.1), in: Circle())
      }
      .buttonStyle(.plain)
      .help(isCompact ? "Expand teleprompter" : "Collapse into notch")
      .accessibilityIdentifier(
        isCompact ? "teleprompter.expandNotch" : "teleprompter.collapseNotch")
    }
    .padding(.trailing, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  @ViewBuilder private var shellBackground: some View {
    if model.isAttachedToNotch {
      TeleprompterNotchShape(
        topShoulderRadius: model.isCompactAtNotch ? 7 : 10,
        bottomCornerRadius: model.isCompactAtNotch ? 16 : 24
      )
      .fill(shellGradient)
    } else {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(shellGradient)
    }
  }

  @ViewBuilder private var shellOutline: some View {
    if model.isAttachedToNotch {
      TeleprompterNotchShape(
        topShoulderRadius: model.isCompactAtNotch ? 7 : 10,
        bottomCornerRadius: model.isCompactAtNotch ? 16 : 24
      )
      .stroke(.white.opacity(isHoveringCompactNotch ? 0.16 : 0.1), lineWidth: 1)
      .mask {
        Rectangle().padding(.top, 1.5)
      }
    } else {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
    }
  }

  @ViewBuilder private var shellMask: some View {
    if model.isAttachedToNotch {
      TeleprompterNotchShape(
        topShoulderRadius: model.isCompactAtNotch ? 7 : 10,
        bottomCornerRadius: model.isCompactAtNotch ? 16 : 24
      )
    } else {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
    }
  }

  private var shellGradient: LinearGradient {
    let selectedColor =
      NSColor(model.islandBackgroundColor).usingColorSpace(.sRGB)
      ?? NSColor(red: 0.055, green: 0.06, blue: 0.075, alpha: 1)
    let bottomColor =
      selectedColor.blended(
        withFraction: model.isCompactAtNotch ? 0.12 : 0.35,
        of: .black
      ) ?? selectedColor
    let opacity = model.islandBackgroundOpacity

    return LinearGradient(
      colors: [
        Color(nsColor: selectedColor).opacity(opacity),
        Color(nsColor: bottomColor).opacity(opacity),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  private var topChromePadding: CGFloat {
    max(10, model.screenTopInset + 8)
  }

  private var topNotchControlHeight: CGFloat {
    max(42, model.screenTopInset + TeleprompterNotchLayout.compactExtraHeight)
  }

  private var showsNotchControls: Bool {
    model.isAttachedToNotch && model.supportsCompactNotch
  }

  private var controlBar: some View {
    HStack(spacing: 8) {
      Button {
        model.togglePlayback()
      } label: {
        Label(
          model.isPlaying ? "Pause" : "Play",
          systemImage: model.isPlaying ? "pause.fill" : "play.fill"
        )
        .labelStyle(.iconOnly)
      }
      .buttonStyle(PrompterControlButtonStyle(isActive: model.isPlaying))
      .disabled(!model.hasScript || model.scrollLimit <= 0)
      .help(model.isPlaying ? "Pause" : "Play")
      .accessibilityIdentifier("teleprompter.playPause")

      Button {
        model.restart()
      } label: {
        Label("Restart", systemImage: "backward.end.fill")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(PrompterControlButtonStyle())
      .help("Restart")
      .accessibilityIdentifier("teleprompter.restart")

      playbackInfo
        .padding(.leading, 3)

      Spacer(minLength: 8)

      WindowDragHandle {
        windowController.detachForDrag()
      }
      .frame(width: 54, height: 26)
      .help("Drag to detach and move")
      .accessibilityLabel("Move teleprompter")

      Spacer(minLength: 8)

      expandedNotchActions
    }
  }

  private var playbackInfo: some View {
    ViewThatFits(in: .horizontal) {
      Text(
        "\(model.playbackSpeed, format: .number.precision(.fractionLength(1)))×  ·  \(Int(model.fontSize)) pt"
      )
      Text("\(model.playbackSpeed, format: .number.precision(.fractionLength(1)))×")
    }
    .font(.system(size: 11, weight: .medium, design: .rounded))
    .foregroundStyle(.white.opacity(0.48))
    .monospacedDigit()
  }

  private var expandedNotchActions: some View {
    HStack(spacing: 6) {
      Button {
        windowController.toggleAttachment()
      } label: {
        Label(
          model.isAttachedToNotch ? "Detach from Notch" : "Attach to Notch",
          systemImage: model.isAttachedToNotch ? "pin.slash" : "pin.fill"
        )
        .labelStyle(.iconOnly)
      }
      .buttonStyle(PrompterControlButtonStyle(isActive: model.isAttachedToNotch))
      .help(model.isAttachedToNotch ? "Detach from notch" : "Attach to notch")
      .accessibilityIdentifier("teleprompter.attachment")

      Button {
        model.isSettingsPresented.toggle()
      } label: {
        Label("Playback Settings", systemImage: "slider.horizontal.3")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(PrompterControlButtonStyle(isActive: model.isSettingsPresented))
      .help("Playback settings")
      .accessibilityIdentifier("teleprompter.settings")
      .popover(isPresented: $model.isSettingsPresented, arrowEdge: .top) {
        SettingsPopover(model: model) {
          windowController.applyCaptureExclusion()
        }
      }

      Button {
        windowController.closeTeleprompter()
      } label: {
        Label("Close", systemImage: "xmark")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(PrompterControlButtonStyle())
      .help("Close teleprompter")
      .accessibilityIdentifier("teleprompter.close")
    }
  }

  private var progressBar: some View {
    HStack(spacing: 10) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.08))
          Capsule()
            .fill(Color(red: 0.93, green: 0.63, blue: 0.22))
            .frame(width: max(3, proxy.size.width * model.progress))
        }
      }
      .frame(height: 3)

      Text(model.progress, format: .percent.precision(.fractionLength(0)))
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.38))
        .monospacedDigit()
        .frame(width: 30, alignment: .trailing)
        .accessibilityIdentifier("teleprompter.progress")

      Image(systemName: "arrow.up.left.and.arrow.down.right")
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.22))
        .help("Resize from any window edge")
    }
  }
}

private struct TeleprompterReader: View {
  @Bindable var model: TeleprompterModel
  @State private var contentHeight: CGFloat = 0
  @State private var draft = ""
  @State private var isEditing = false
  @FocusState private var isEditorFocused: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.isPlaying)) { timeline in
      GeometryReader { viewport in
        ZStack(alignment: .topLeading) {
          if isEditing {
            scriptEditor
          } else {
            ZStack(alignment: .topLeading) {
              readerText(in: viewport.size)
                .offset(y: -model.scrollOffset)
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            .clipped()
            .mask {
              LinearGradient(
                stops: [
                  .init(color: .clear, location: 0),
                  .init(color: .black, location: 0.08),
                  .init(color: .black, location: 0.9),
                  .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
              )
            }

            readingGuide(in: viewport.size)
          }
        }
        .onPreferenceChange(PromptContentHeightKey.self) { newHeight in
          contentHeight = newHeight
          model.updateScrollLimit(model.hasScript ? max(0, newHeight - viewport.size.height) : 0)
        }
        .onChange(of: viewport.size) { _, newSize in
          model.updateScrollLimit(model.hasScript ? max(0, contentHeight - newSize.height) : 0)
        }
        .onChange(of: model.script) { _, _ in
          model.updateScrollLimit(
            model.hasScript ? max(0, contentHeight - viewport.size.height) : 0)
        }
      }
      .onChange(of: timeline.date) { _, _ in
        model.tick()
      }
    }
    .background(.black.opacity(0.16))
    .overlay {
      if !isEditing {
        PromptScrollCapture(lineScrollDistance: max(24, model.fontSize * 0.8)) { delta in
          model.scroll(by: delta)
        }
        .accessibilityHidden(true)
      }
    }
    .overlay(alignment: .topTrailing) {
      if !isEditing {
        HStack(spacing: 6) {
          Button {
            model.markdownMode.toggle()
          } label: {
            Label("Markdown mode", systemImage: "textformat")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(PrompterControlButtonStyle(isActive: model.markdownMode))
          .help(model.markdownMode ? "Disable Markdown viewer mode" : "Enable Markdown viewer mode")
          .accessibilityValue(model.markdownMode ? "On" : "Off")
          .accessibilityIdentifier("teleprompter.markdownMode")

          Button(action: beginEditing) {
            Label(model.markdownMode ? "Edit Markdown" : "Edit script", systemImage: "pencil")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(PrompterControlButtonStyle())
          .help(model.markdownMode ? "Edit Markdown source" : "Edit script directly")
          .accessibilityIdentifier("teleprompter.editScript")
        }
        .padding(12)
      }
    }
    .overlay(alignment: .top) {
      Rectangle()
        .fill(.white.opacity(0.05))
        .frame(height: 1)
    }
  }

  private var scriptEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(model.markdownMode ? "Editing Markdown" : "Editing script")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.62))
        if model.markdownMode {
          Text("Save to preview formatted text")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
        }
        Spacer()
        Button("Cancel", action: cancelEditing)
          .buttonStyle(.plain)
          .foregroundStyle(.white.opacity(0.68))
        Button("Done", action: applyEditing)
          .buttonStyle(.borderedProminent)
          .tint(.orange)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("teleprompter.applyDirectScript")
      }

      TextEditor(text: $draft)
        .font(editorFont)
        .lineSpacing(editorLineSpacing)
        .scrollContentBackground(.hidden)
        .focused($isEditorFocused)
        .padding(10)
        .background(
          .black.opacity(0.24),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(0.12))
        }
        .accessibilityLabel(model.markdownMode ? "Markdown source" : "Script content")
        .accessibilityIdentifier("teleprompter.directScriptEditor")
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onExitCommand(perform: cancelEditing)
  }

  private func readerText(in viewport: CGSize) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Color.clear.frame(height: max(30, viewport.height * 0.34))

      if model.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(
          model.markdownMode
            ? "Edit Markdown to add your script."
            : "Edit your script to get started."
        )
        .foregroundStyle(.white.opacity(0.35))
      } else {
        renderedScript
      }

      Color.clear.frame(height: max(50, viewport.height * 0.64))
    }
    .multilineTextAlignment(.leading)
    .frame(width: max(1, viewport.width - 64), alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 32)
    .background {
      GeometryReader { content in
        Color.clear.preference(key: PromptContentHeightKey.self, value: content.size.height)
      }
    }
    .accessibilityValue(model.script)
  }

  @ViewBuilder private var renderedScript: some View {
    if model.markdownMode {
      StructuredText(markdown: model.script)
        .font(.system(size: model.fontSize, weight: .regular, design: .default))
        .textual.structuredTextStyle(.gitHub)
    } else {
      Text(model.script)
        .font(.system(size: model.fontSize, weight: .semibold, design: .rounded))
        .lineSpacing(model.fontSize * 0.34)
        .foregroundStyle(.white.opacity(0.96))
    }
  }

  private var editorFont: Font {
    if model.markdownMode {
      return .system(size: max(14, model.fontSize * 0.55), weight: .medium, design: .monospaced)
    }
    return .system(size: model.fontSize, weight: .semibold, design: .rounded)
  }

  private var editorLineSpacing: CGFloat {
    model.markdownMode ? max(3, model.fontSize * 0.12) : model.fontSize * 0.34
  }

  private func beginEditing() {
    model.pause()
    draft = model.script
    isEditing = true
    isEditorFocused = true
  }

  private func cancelEditing() {
    isEditing = false
  }

  private func applyEditing() {
    model.replaceScript(with: draft)
    isEditing = false
  }

  private func readingGuide(in viewport: CGSize) -> some View {
    HStack(spacing: 8) {
      Circle().fill(Color.orange.opacity(0.7)).frame(width: 4, height: 4)
      Rectangle().fill(Color.orange.opacity(0.13)).frame(height: 1)
      Circle().fill(Color.orange.opacity(0.7)).frame(width: 4, height: 4)
    }
    .padding(.horizontal, 17)
    .offset(y: viewport.height * 0.34)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct PromptScrollCapture: NSViewRepresentable {
  let lineScrollDistance: Double
  let onScroll: (Double) -> Void

  func makeNSView(context: Context) -> ScrollCaptureView {
    let view = ScrollCaptureView()
    view.lineScrollDistance = lineScrollDistance
    view.onScroll = onScroll
    return view
  }

  func updateNSView(_ nsView: ScrollCaptureView, context: Context) {
    nsView.lineScrollDistance = lineScrollDistance
    nsView.onScroll = onScroll
  }

  final class ScrollCaptureView: NSView {
    var lineScrollDistance = 30.0
    var onScroll: ((Double) -> Void)?

    override func scrollWheel(with event: NSEvent) {
      let scale = event.hasPreciseScrollingDeltas ? 1 : lineScrollDistance
      let delta = -Double(event.scrollingDeltaY) * scale
      guard abs(delta) > 0.01 else {
        super.scrollWheel(with: event)
        return
      }
      onScroll?(delta)
    }
  }
}

private struct SettingsPopover: View {
  @Bindable var model: TeleprompterModel
  @Environment(\.dismiss) private var dismiss
  @State private var draft: String

  let captureSettingChanged: () -> Void

  init(model: TeleprompterModel, captureSettingChanged: @escaping () -> Void) {
    self.model = model
    self.captureSettingChanged = captureSettingChanged
    _draft = State(initialValue: model.script)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Playback Settings")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
          Text("Tune the look, pace, type, and script format.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Done") {
          applyScriptAndDismiss()
        }
        .keyboardShortcut(.defaultAction)
      }

      VStack(spacing: 13) {
        settingSlider(
          title: "Speed",
          value: $model.playbackSpeed,
          range: TeleprompterModel.playbackSpeedRange,
          displayValue: "\(model.playbackSpeed.formatted(.number.precision(.fractionLength(1))))×",
          accessibilityIdentifier: "teleprompter.speed"
        )

        settingSlider(
          title: "Font size",
          value: $model.fontSize,
          range: TeleprompterModel.fontSizeRange,
          displayValue: "\(Int(model.fontSize)) pt",
          accessibilityIdentifier: "teleprompter.fontSize"
        )

        Divider()

        HStack(spacing: 12) {
          Text("Island")
            .frame(width: 68, alignment: .leading)

          ColorPicker(
            "Island color",
            selection: $model.islandBackgroundColor,
            supportsOpacity: false
          )
          .labelsHidden()
          .accessibilityLabel("Island color")
          .accessibilityIdentifier("teleprompter.islandColor")

          Text("Opacity")
            .font(.caption)
            .foregroundStyle(.secondary)

          PrompterSlider(
            value: $model.islandBackgroundOpacity,
            range: TeleprompterModel.islandBackgroundOpacityRange,
            accessibilityLabel: "Island opacity",
            accessibilityValue: model.islandBackgroundOpacity.formatted(
              .percent.precision(.fractionLength(0))),
            accessibilityIdentifier: "teleprompter.islandOpacity"
          )

          Text(model.islandBackgroundOpacity, format: .percent.precision(.fractionLength(0)))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(width: 48, alignment: .trailing)
        }
      }
      .padding(14)
      .background(
        .primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      Toggle(isOn: $model.captureExclusionEnabled) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Hide from screen capture (legacy, best effort)")
          Text("Requests AppKit capture exclusion. Modern recording apps may ignore it.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(PrompterSwitchToggleStyle())
      .onChange(of: model.captureExclusionEnabled) { _, _ in
        captureSettingChanged()
      }
      .accessibilityIdentifier("teleprompter.captureExclusion")

      Divider()

      Toggle("Render Markdown as rich text", isOn: $model.markdownMode)
        .toggleStyle(PrompterSwitchToggleStyle())
        .accessibilityIdentifier("teleprompter.markdownMode")

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(model.markdownMode ? "Markdown" : "Script")
            .font(.headline)
          Spacer()
          Text("\(draft.count) characters")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }

        TextEditor(text: $draft)
          .font(.system(size: 14, design: model.markdownMode ? .monospaced : .rounded))
          .scrollContentBackground(.hidden)
          .padding(8)
          .background(
            .black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(.primary.opacity(0.1))
          }
          .accessibilityLabel(model.markdownMode ? "Markdown source" : "Script content")
          .accessibilityIdentifier("teleprompter.scriptEditor")
      }
      .frame(minHeight: 190)

      HStack {
        Button("Use Sample") {
          draft = TeleprompterModel.sampleScript
        }
        Spacer()
        Button("Apply Script") {
          applyScriptAndDismiss()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .accessibilityIdentifier("teleprompter.applyScript")
      }
    }
    .padding(20)
    .frame(width: 470, height: 540)
    .preferredColorScheme(.dark)
    .onAppear {
      captureSettingChanged()
    }
  }

  private func settingSlider(
    title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    displayValue: String,
    accessibilityIdentifier: String
  ) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .frame(width: 68, alignment: .leading)
      PrompterSlider(
        value: value,
        range: range,
        accessibilityLabel: title,
        accessibilityValue: displayValue,
        accessibilityIdentifier: accessibilityIdentifier
      )
      Text(displayValue)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(width: 48, alignment: .trailing)
    }
  }

  private func applyScriptAndDismiss() {
    model.replaceScript(with: draft)
    dismiss()
  }
}

private struct PrompterSlider: View {
  @Binding var value: Double

  let range: ClosedRange<Double>
  let accessibilityLabel: String
  let accessibilityValue: String
  let accessibilityIdentifier: String

  @State private var isHovering = false

  var body: some View {
    GeometryReader { proxy in
      let thumbDiameter = 16.0
      let thumbRadius = thumbDiameter / 2
      let usableWidth = max(1, proxy.size.width - thumbDiameter)
      let thumbCenter = thumbRadius + usableWidth * normalizedValue

      ZStack(alignment: .leading) {
        Capsule()
          .fill(.white.opacity(0.18))
          .frame(height: 5)

        Capsule()
          .fill(Color.accentColor)
          .frame(width: max(5, thumbCenter), height: 5)

        Circle()
          .fill(.white)
          .overlay {
            Circle().stroke(.black.opacity(0.24), lineWidth: 0.5)
          }
          .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
          .frame(width: thumbDiameter, height: thumbDiameter)
          .scaleEffect(isHovering ? 1.08 : 1)
          .offset(x: thumbCenter - thumbRadius)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { gesture in
            let progress = min(
              max((gesture.location.x - thumbRadius) / usableWidth, 0),
              1
            )
            value = range.lowerBound + progress * rangeLength
          }
      )
    }
    .frame(height: 22)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
    .focusable()
    .onMoveCommand { direction in
      switch direction {
      case .left, .down:
        adjust(by: -keyboardStep)
      case .right, .up:
        adjust(by: keyboardStep)
      default:
        break
      }
    }
    .accessibilityRepresentation {
      Slider(value: $value, in: range)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
  }

  private var rangeLength: Double {
    max(.ulpOfOne, range.upperBound - range.lowerBound)
  }

  private var normalizedValue: Double {
    min(max((value - range.lowerBound) / rangeLength, 0), 1)
  }

  private var keyboardStep: Double {
    rangeLength / 20
  }

  private func adjust(by delta: Double) {
    value = min(max(value + delta, range.lowerBound), range.upperBound)
  }
}

private struct PrompterSwitchToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      withAnimation(.snappy(duration: 0.18)) {
        configuration.isOn.toggle()
      }
    } label: {
      HStack(spacing: 12) {
        configuration.label
        Spacer(minLength: 12)

        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
          Capsule()
            .fill(configuration.isOn ? Color.accentColor : Color.white.opacity(0.18))
          Circle()
            .fill(.white)
            .overlay {
              Circle().stroke(.black.opacity(0.22), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.32), radius: 2, y: 1)
            .padding(3)
        }
        .frame(width: 44, height: 26)
        .overlay {
          Capsule().stroke(.white.opacity(configuration.isOn ? 0.08 : 0.12), lineWidth: 1)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct PrompterControlButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  var isActive = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .frame(width: 30, height: 28)
      .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.82))
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            isActive ? Color.orange : Color.white.opacity(configuration.isPressed ? 0.16 : 0.08))
      }
      .contentShape(Rectangle())
      .opacity(isEnabled ? 1 : 0.38)
  }
}

private struct PromptContentHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

private struct WindowDragHandle: NSViewRepresentable {
  let onDragStarted: () -> Void

  func makeNSView(context: Context) -> DragView {
    let view = DragView()
    view.onDragStarted = onDragStarted
    return view
  }

  func updateNSView(_ nsView: DragView, context: Context) {
    nsView.onDragStarted = onDragStarted
  }

  final class DragView: NSView {
    var onDragStarted: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
      onDragStarted?()
      window?.performDrag(with: event)
    }

    override func resetCursorRects() {
      addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDragged(with event: NSEvent) {
      NSCursor.closedHand.set()
    }

    override var acceptsFirstResponder: Bool { true }
  }
}

#Preview {
  ContentView(
    model: TeleprompterModel(defaults: UserDefaults(suiteName: "TeleprompterPreview")!),
    windowController: TeleprompterWindowController.preview
  )
  .frame(width: 720, height: 340)
}
