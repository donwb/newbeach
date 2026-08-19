//
//  BeachRampTVUITests.swift
//  BeachRampTVUITests
//
//  Created by Don Browning on 3/11/26.
//

import XCTest

/// Remote-navigation tests for the board's focus graph: row order is
/// city chip → stat tiles → coastline rail, the video never takes focus,
/// "Recent changes" is reachable at the rail's right edge, and closing a
/// detail overlay returns focus to the tile that opened it.
final class BeachRampTVUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    /// Stat-tile kicker labels; a focused button whose label starts with one
    /// of these is a stat tile. ("New Smyrna Beach" is ambiguous — it names
    /// both the city chip and a camera pin — so tests locate elements by
    /// focus + geometry instead of by label lookup.)
    private let statPrefixes = ["Outlook", "Weather"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.buttons["Recent changes"].waitForExistence(timeout: 15),
            "board should load with the coastline rail"
        )
    }

    /// The single currently focused button.
    private var focusedButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Walk focus up to the top of the board — the city chip.
    private func focusCityChip() {
        for _ in 0..<3 { remote.press(.up) }
        XCTAssertEqual(focusedButton.label, "New Smyrna Beach",
                       "top of the focus order should be the city chip")
        XCTAssertLessThan(focusedButton.frame.minY, app.frame.height * 0.2,
                          "the focused chip should be the one in the top bar")
    }

    private func assertFocusOnStatTile(_ message: String) {
        let label = focusedButton.label
        XCTAssertTrue(statPrefixes.contains { label.hasPrefix($0) },
                      "\(message) (focused: \(label))")
    }

    @MainActor
    func testVerticalOrderCityChipToStatsToRail() throws {
        focusCityChip()

        remote.press(.down)
        assertFocusOnStatTile("down from the city chip should land on the stat tiles")

        remote.press(.down)
        XCTAssertGreaterThan(focusedButton.frame.minY, app.frame.height * 0.7,
                             "down from the stats should land in the coastline rail, not the video (focused: \(focusedButton.label))")

        remote.press(.up)
        assertFocusOnStatTile("up from the rail should return to the stat tiles")

        remote.press(.up)
        XCTAssertEqual(focusedButton.label, "New Smyrna Beach",
                       "up from the stats should return to the city chip")
    }

    @MainActor
    func testRecentChangesReachableAndOpens() throws {
        focusCityChip()
        remote.press(.down)
        remote.press(.down)

        // Walk right along the rail; the last stop is Recent changes.
        let recentChanges = app.buttons["Recent changes"]
        for _ in 0..<8 where !recentChanges.hasFocus {
            remote.press(.right)
        }
        XCTAssertTrue(recentChanges.hasFocus, "Recent changes should be reachable from the rail")

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
    func testDetailOverlayReturnsFocusToOpeningTile() throws {
        focusCityChip()
        remote.press(.down)
        assertFocusOnStatTile("down from the city chip should land on the stat tiles")
        remote.press(.right)
        assertFocusOnStatTile("right should stay within the stat tiles")

        // Whichever tile has focus: open its overlay, close it, and expect
        // focus back on the same tile.
        let openingLabel = focusedButton.label
        remote.press(.select)
        sleep(1)
        remote.press(.menu)

        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { [weak self] _, _ in
                self?.focusedButton.label == openingLabel
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                       "closing the overlay should return focus to the tile that opened it")
    }
}
