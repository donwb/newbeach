//
//  BeachRampTVUITests.swift
//  BeachRampTVUITests
//
//  Created by Don Browning on 3/11/26.
//

import XCTest

/// Remote-navigation tests for the video-first board's focus graph. There
/// is no mode toggle: the resting screen is header (outlook button) over the
/// picture over the cam strip over the ledger. Focus rows: cam strip →
/// ramps header → ramp rows; the outlook button sits above the strip; the
/// right box has no focusables in v1, so Left/Right stays box-local for
/// free. Select on a ramp row opens Ramp detail; the outlook button opens
/// Beach outlook; Back closes a surface and restores focus.
final class BeachRampTVUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Initial focus lands on the cam strip once the roster loads.
        XCTAssertTrue(
            focusedElement(withPrefix: "camStrip.").waitForExistence(timeout: 20),
            "initial focus should land on the cam strip"
        )
    }

    private var focusedButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    private func focusedElement(withPrefix prefix: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "hasFocus == true AND identifier BEGINSWITH %@", prefix)
        ).firstMatch
    }

    private var focusedID: String { focusedButton.identifier }

    @MainActor
    func testLeftRightSwitchesCam() throws {
        let before = focusedID
        remote.press(.right)
        // Focus moved to a different cam; the strip switch is focus-driven.
        XCTAssertTrue(focusedID.hasPrefix("camStrip."), "focus stays on the strip (got \(focusedID))")
        XCTAssertNotEqual(focusedID, before, "Right should move to the next cam")

        // The newly focused cam becomes the watched one.
        let watched = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND value == %@", focusedID, "watching")
        ).firstMatch
        XCTAssertTrue(watched.waitForExistence(timeout: 3),
                      "the focused cam should become the watched cam")
    }

    @MainActor
    func testDownWalksIntoTheLedger() throws {
        remote.press(.down)
        XCTAssertTrue(
            focusedID == "rampsHeader" || focusedID.hasPrefix("rampRow."),
            "Down from the strip should land in the ramps box (got \(focusedID))"
        )
    }

    @MainActor
    func testCityCycleOnRampsHeader() throws {
        focusRampsHeader()
        let before = app.buttons["rampsHeader"].value as? String
        remote.press(.right)
        // City cycling is instant and local; the header keeps focus.
        XCTAssertEqual(focusedID, "rampsHeader", "focus stays on the header")
        let after = app.buttons["rampsHeader"].value as? String
        XCTAssertNotEqual(before, after, "Right on the header should cycle the city")
    }

    @MainActor
    func testRampRowStaysBoxLocalOnRight() throws {
        focusFirstRampRow()
        let before = focusedID
        remote.press(.right)
        XCTAssertEqual(focusedID, before, "Right on a ramp row is inert — box-local rule")
    }

    @MainActor
    func testSelectRampRowOpensDetailAndBackRestores() throws {
        focusFirstRampRow()
        let row = focusedID
        remote.press(.select)
        XCTAssertTrue(surface("surface.rampDetail").waitForExistence(timeout: 5),
                      "Select on a ramp row should open Ramp detail")

        remote.press(.menu)
        XCTAssertTrue(waitForDisappearance(of: surface("surface.rampDetail"), timeout: 5),
                      "Back should close the surface")
        // Focus returns to the row that opened it, one runloop later.
        let restored = app.buttons.matching(
            NSPredicate(format: "hasFocus == true AND identifier == %@", row)
        ).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 3),
                      "focus should return to the ramp row that opened the surface")
    }

    @MainActor
    func testOutlookButtonOpensSurface() throws {
        remote.press(.up)
        XCTAssertEqual(focusedID, "outlookButton",
                       "Up from the cam strip should reach the outlook button")
        remote.press(.select)
        XCTAssertTrue(surface("surface.outlook").waitForExistence(timeout: 5),
                      "Select should open the Beach outlook surface")

        remote.press(.menu)
        XCTAssertTrue(waitForDisappearance(of: surface("surface.outlook"), timeout: 5),
                      "Back should close the surface")
        let restored = app.buttons.matching(
            NSPredicate(format: "hasFocus == true AND identifier == %@", "outlookButton")
        ).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 3),
                      "focus should return to the outlook button")
    }

    // MARK: - Helpers

    /// A pull surface by identifier, whatever element type SwiftUI exposes
    /// the container as.
    private func surface(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func focusRampsHeader() {
        remote.press(.down)
        for _ in 0..<3 where focusedID != "rampsHeader" {
            remote.press(.up)
        }
        XCTAssertEqual(focusedID, "rampsHeader",
                       "should be able to reach the ramps header (got \(focusedID))")
    }

    private func focusFirstRampRow() {
        focusRampsHeader()
        remote.press(.down)
        XCTAssertTrue(focusedID.hasPrefix("rampRow."),
                      "Down from the header should land on a ramp row (got \(focusedID))")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
