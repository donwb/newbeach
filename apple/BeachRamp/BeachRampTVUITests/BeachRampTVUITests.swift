//
//  BeachRampTVUITests.swift
//  BeachRampTVUITests
//
//  Created by Don Browning on 3/11/26.
//

import XCTest

/// Remote-navigation tests for the v3 board's focus graph: row order is
/// cam caption strip → ramp heading (city selector, Recent changes) →
/// weekend day panels, the video never takes focus, and closing an overlay
/// returns focus to the control that opened it.
final class BeachRampTVUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.buttons["Recent changes"].waitForExistence(timeout: 15),
            "board should load with the ramp heading"
        )
    }

    /// The single currently focused button.
    private var focusedButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Walk focus to the top of the board — the cam caption strip, which
    /// sits inside the top 405pt cam band.
    private func focusCamStrip() {
        for _ in 0..<4 { remote.press(.up) }
        XCTAssertLessThan(focusedButton.frame.minY, app.frame.height * 0.45,
                          "top of the focus order should be the cam caption strip (focused: \(focusedButton.label))")
    }

    @MainActor
    func testVerticalOrderCamStripToHeadingToDayPanels() throws {
        focusCamStrip()

        remote.press(.down)
        let headingY = focusedButton.frame.minY
        XCTAssertGreaterThan(headingY, app.frame.height * 0.3,
                             "down from the cam strip should leave the band (focused: \(focusedButton.label))")
        XCTAssertLessThan(headingY, app.frame.height * 0.6,
                          "down from the cam strip should land on the ramp heading, not the day panels (focused: \(focusedButton.label))")

        remote.press(.down)
        XCTAssertGreaterThan(focusedButton.frame.minY, app.frame.height * 0.6,
                             "down from the heading should land on the day panels (focused: \(focusedButton.label))")

        remote.press(.up)
        let backY = focusedButton.frame.minY
        XCTAssertGreaterThan(backY, app.frame.height * 0.3,
                             "up from the day panels should return to the heading, not the cam band")
        XCTAssertLessThan(backY, app.frame.height * 0.6,
                          "up from the day panels should return to the heading (focused: \(focusedButton.label))")
    }

    @MainActor
    func testRecentChangesReachableAndOpens() throws {
        focusCamStrip()
        remote.press(.down)

        // Walk right along the heading; the last stop is Recent changes.
        let recentChanges = app.buttons["Recent changes"]
        for _ in 0..<4 where !recentChanges.hasFocus {
            remote.press(.right)
        }
        XCTAssertTrue(recentChanges.hasFocus, "Recent changes should be reachable from the heading")

        remote.press(.select)
        XCTAssertTrue(
            app.staticTexts["Recent changes"].waitForExistence(timeout: 5),
            "selecting the button should open the activity overlay"
        )

        remote.press(.menu)
        let refocus = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"), object: recentChanges)
        XCTAssertEqual(XCTWaiter.wait(for: [refocus], timeout: 5), .completed,
                       "closing the overlay should return focus to the Recent changes button")
    }

    @MainActor
    func testMenuOpensRecentChangesFromBoard() throws {
        remote.press(.menu)
        XCTAssertTrue(
            app.staticTexts["Recent changes"].waitForExistence(timeout: 5),
            "Menu on the board should open the Recent changes overlay"
        )
        remote.press(.menu)
    }

    @MainActor
    func testForecastOverlayReturnsFocusToDayPanel() throws {
        focusCamStrip()
        remote.press(.down)
        remote.press(.down)

        // The day panels exist only when the weekend outlook is being
        // served — skip rather than fail when the feature is off.
        guard focusedButton.frame.minY > app.frame.height * 0.6 else {
            throw XCTSkip("no weekend day panels on the board (weekend outlook off)")
        }

        let openingLabel = focusedButton.label
        remote.press(.select)
        XCTAssertTrue(
            app.staticTexts["Press Menu to close"].waitForExistence(timeout: 5),
            "selecting a day panel should open the beach forecast overlay"
        )

        remote.press(.menu)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { [weak self] _, _ in
                self?.focusedButton.label == openingLabel
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                       "closing the forecast should return focus to the panel that opened it")
    }
}
