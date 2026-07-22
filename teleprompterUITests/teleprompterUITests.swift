//
//  teleprompterUITests.swift
//  teleprompterUITests
//
//  Created by Kevin Wang on 7/15/26.
//

import XCTest

final class TeleprompterUITests: XCTestCase {

  override func setUpWithError() throws {
    // Put setup code here. This method is called before the invocation of each test method in the class.

    // In UI tests it is usually best to stop immediately when a failure occurs.
    continueAfterFailure = false

    // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
  }

  override func tearDownWithError() throws {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
  }

  @MainActor
  func testCoreControlsAreAvailable() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()

    let playButton = app.buttons["teleprompter.playPause"]
    let settingsButton = app.buttons["teleprompter.settings"]
    let attachmentButton = app.buttons["teleprompter.attachment"]
    let closeButton = app.buttons["teleprompter.close"]
    XCTAssertTrue(playButton.waitForExistence(timeout: 3))
    XCTAssertTrue(settingsButton.exists)
    XCTAssertTrue(attachmentButton.exists)
    XCTAssertTrue(closeButton.exists)
    XCTAssertEqual(playButton.frame.midY, settingsButton.frame.midY, accuracy: 1)
    XCTAssertEqual(playButton.frame.midY, attachmentButton.frame.midY, accuracy: 1)
    XCTAssertEqual(playButton.frame.midY, closeButton.frame.midY, accuracy: 1)
    let reader = app.descendants(matching: .any)["teleprompter.reader"]
    XCTAssertTrue(reader.exists)
    XCTAssertLessThan(reader.frame.minY - playButton.frame.maxY, 24)

    let collapseButton = app.buttons["teleprompter.collapseNotch"]
    if collapseButton.exists {
      collapseButton.click()
      let expandButton = app.buttons["teleprompter.expandNotch"]
      XCTAssertTrue(expandButton.waitForExistence(timeout: 2))
      XCTAssertFalse(settingsButton.exists)
      XCTAssertFalse(attachmentButton.exists)
      XCTAssertFalse(closeButton.exists)
      expandButton.click()
      XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
    }

    app.buttons["teleprompter.settings"].click()
    let editor = app.textViews["teleprompter.scriptEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 2))
    XCTAssertTrue(app.sliders["teleprompter.speed"].exists)
    XCTAssertTrue(app.sliders["teleprompter.fontSize"].exists)
    XCTAssertTrue(app.sliders["teleprompter.islandOpacity"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any)["teleprompter.islandColor"].exists)

    editor.click()
    editor.typeKey("a", modifierFlags: .command)
    editor.typeText("hello world")
    XCTAssertEqual(editor.value as? String, "hello world")
  }

  @MainActor
  func testCompactSettingsAndAttachmentStressPath() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()

    let collapseButton = app.buttons["teleprompter.collapseNotch"]
    guard collapseButton.waitForExistence(timeout: 3) else { return }

    for _ in 0..<3 {
      collapseButton.click()
      XCTAssertTrue(app.buttons["teleprompter.expandNotch"].waitForExistence(timeout: 2))

      app.typeKey(",", modifierFlags: .command)
      XCTAssertTrue(app.textViews["teleprompter.scriptEditor"].waitForExistence(timeout: 2))
      app.buttons["Done"].click()
      XCTAssertTrue(collapseButton.waitForExistence(timeout: 2))
    }

    let attachmentButton = app.buttons["teleprompter.attachment"]
    attachmentButton.click()
    XCTAssertTrue(attachmentButton.waitForExistence(timeout: 2))
    attachmentButton.click()
    XCTAssertTrue(collapseButton.waitForExistence(timeout: 2))
  }

  @MainActor
  func testScriptCanBeEditedWithoutOpeningSettings() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()

    let editButton = app.buttons["teleprompter.editScript"]
    XCTAssertTrue(editButton.waitForExistence(timeout: 3))
    let markdownButton = app.buttons["teleprompter.markdownMode"]
    XCTAssertTrue(markdownButton.exists)
    markdownButton.click()
    editButton.click()

    let editor = app.textViews["teleprompter.directScriptEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 2))
    editor.click()
    editor.typeKey("a", modifierFlags: .command)
    editor.typeText("# A revised script\\n\\n**Formatted on return**")
    app.buttons["teleprompter.applyDirectScript"].click()

    XCTAssertTrue(editButton.waitForExistence(timeout: 2))
    XCTAssertEqual(
      app.descendants(matching: .any)["teleprompter.reader"].value as? String,
      "# A revised script\\n\\n**Formatted on return**")
  }

  @MainActor
  func testLaunchPerformance() throws {
    // This measures how long it takes to launch your application.
    measure(metrics: [XCTApplicationLaunchMetric()]) {
      let app = XCUIApplication()
      app.launchArguments = ["--ui-testing"]
      app.launch()
    }
  }
}
