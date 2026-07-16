//
//  teleprompterApp.swift
//  teleprompter
//
//  Created by Kevin Wang on 7/15/26.
//

import AppKit
import SwiftUI

@main
struct TeleprompterApp: App {
  @NSApplicationDelegateAdaptor(TeleprompterAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("Show Teleprompter") {
          appDelegate.showTeleprompter()
        }
        .keyboardShortcut("0", modifiers: .command)
      }

      CommandGroup(replacing: .appSettings) {
        Button("Teleprompter Settings…") {
          appDelegate.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
      }

      CommandMenu("Playback") {
        Button(appDelegate.model.isPlaying ? "Pause" : "Play") {
          if appDelegate.model.isCompactAtNotch {
            appDelegate.windowController?.expandAndTogglePlayback()
          } else {
            appDelegate.model.togglePlayback()
          }
        }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(
          appDelegate.model.isSettingsPresented || !appDelegate.model.hasScript
            || appDelegate.model.scrollLimit <= 0)

        Button("Restart") {
          appDelegate.model.restart()
        }
        .keyboardShortcut("r", modifiers: .command)

        Divider()

        Button(
          appDelegate.model.isCompactAtNotch ? "Expand from Notch" : "Collapse into Notch"
        ) {
          appDelegate.windowController?.toggleNotchPresentation()
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(
          !appDelegate.model.isAttachedToNotch || !appDelegate.model.supportsCompactNotch)

        Button(appDelegate.model.isAttachedToNotch ? "Detach from Notch" : "Attach to Notch") {
          appDelegate.windowController?.toggleAttachment()
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])
      }
    }
  }
}

@MainActor
final class TeleprompterAppDelegate: NSObject, NSApplicationDelegate {
  let model: TeleprompterModel
  private let windowDefaults: UserDefaults
  private(set) var windowController: TeleprompterWindowController?

  override init() {
    let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    let defaults: UserDefaults
    if isUITesting {
      let suiteName = "TeleprompterUITests"
      defaults = UserDefaults(suiteName: suiteName)!
      defaults.removePersistentDomain(forName: suiteName)
    } else {
      defaults = .standard
    }

    let model = TeleprompterModel(defaults: defaults)
    if isUITesting {
      model.captureExclusionEnabled = false
    }
    self.model = model
    windowDefaults = defaults
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = TeleprompterWindowController(model: model, windowDefaults: windowDefaults)
    windowController = controller
    controller.showTeleprompter(activate: true)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showTeleprompter()
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func showTeleprompter() {
    windowController?.showTeleprompter(activate: true)
  }

  func showSettings() {
    windowController?.presentSettings()
  }
}
