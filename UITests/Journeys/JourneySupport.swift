import XCTest
import UIKit

/// Base class for user journeys. Each journey runs in passes (light, dark, large text), launches the app on
/// demo data, and records a screenshot and an accessibility audit at every step.
/// Evidence goes to the result bundle and, when SCREENSHOT_DIR is set (TEST_RUNNER_SCREENSHOT_DIR), to
/// `$SCREENSHOT_DIR/<journey>/<pass>-<NN>-<step>.png` plus `results.tsv` and `audit.tsv` rows.
@MainActor
class JourneyCase: XCTestCase {
    enum Pass: String, CaseIterable {
        case light, dark
        case largeText = "large-text"

        var launchArguments: [String] {
            switch self {
            case .light: ["-ARAppearance", "light"]
            case .dark: ["-ARAppearance", "dark"]
            case .largeText: ["-ARAppearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
            }
        }
    }

    private var stepNumber = 0
    private var currentPass = Pass.light
    var journey: String { String(describing: type(of: self)).replacingOccurrences(of: "Journey", with: "").lowercased() }

    // MARK: Passes and launch

    func runPasses(_ passes: [Pass] = Pass.allCases, _ body: (XCUIApplication, Pass) -> Void) {
        continueAfterFailure = false
        for pass in passes {
            currentPass = pass
            stepNumber = 0
            let app = launch(pass.launchArguments)
            body(app, pass)
            app.terminate()
        }
    }

    @discardableResult
    func launch(_ extra: [String] = [], keepSettings: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"] + (keepSettings ? ["-ARDemoKeepSettings", "YES"] : []) + extra
        app.launch()
        return app
    }

    // MARK: Evidence

    private var evidenceDir: URL? {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: dir).appendingPathComponent(journey)
    }

    private func append(_ line: String, to file: String) {
        guard let dir = evidenceDir?.deletingLastPathComponent() else { return }
        let url = dir.appendingPathComponent(file)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    /// Screenshot of the current state. Name the step after what just happened or what is now visible.
    func step(_ name: String) {
        sleep(1)
        stepNumber += 1
        let label = String(format: "%@-%02d-%@", currentPass.rawValue, stepNumber, name)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(journey)-\(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = evidenceDir else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(label).png"))
            append("\(journey)\t\(currentPass.rawValue)\t\(stepNumber)\t\(name)\t\(journey)/\(label).png", to: "results.tsv")
        } catch {
            XCTFail("Could not write \(label).png: \(error)")
        }
    }

    /// Runs the system accessibility audit on the current screen. Issues are recorded as evidence, not failures.
    func audit(_ app: XCUIApplication, _ name: String) {
        // Let drawers, sheets and tab switches finish animating first; a mid-animation audit reports false clipping.
        sleep(1)
        var issues: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element?.label ?? ""
                issues.append("\(issue.compactDescription) [\(element)]")
                return true
            }
        } catch {
            issues.append("audit error: \(error)")
        }
        let text = issues.isEmpty ? "no issues" : issues.joined(separator: "\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = "audit-\(journey)-\(currentPass.rawValue)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        // audited.tsv has one row per audit call and audit.tsv one per finding, both with the number of the step
        // the audit ran after, so scripts/ux-score.py can tell a clean audit from no audit.
        append("\(journey)\t\(currentPass.rawValue)\t\(name)\t\(stepNumber)", to: "audited.tsv")
        for issue in issues {
            append("\(journey)\t\(currentPass.rawValue)\t\(name)\t\(issue.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " "))\t\(stepNumber)", to: "audit.tsv")
        }
    }

    // MARK: Driving helpers

    func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func waitHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: element)
        return XCTWaiter().wait(for: [done], timeout: timeout) == .completed
    }

    /// True once the element is gone or off screen.
    func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: element)
        return XCTWaiter().wait(for: [done], timeout: timeout) == .completed
    }

    /// On screen by frame. `isHittable` is not usable here: a closed drawer's views sit off screen in the tree and
    /// Xcode reports "Activation point invalid" for them, and glass bars can make an open one report not hittable.
    func isOnScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        let window = app.windows.firstMatch.frame
        return !frame.isEmpty && frame.midX > window.minX && frame.midX < window.maxX
            && frame.midY > window.minY && frame.midY < window.maxY
    }

    func waitOnScreen(_ app: XCUIApplication, _ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if isOnScreen(app, element) { return true }
            usleep(200_000)
        }
        return isOnScreen(app, element)
    }

    /// Whether the thread list can be used. iPhone: the drawer sits under the chat and its views stay in the tree
    /// while it is closed, so the only reliable sign is the "Close sidebar" scrim that exists while it is open.
    /// iPad: the column's compose button is on screen.
    func sidebarIsOpen(_ app: XCUIApplication) -> Bool {
        if app.buttons["Close sidebar"].exists { return true }
        if app.buttons["Menu"].exists { return false }
        let compose = app.buttons["sidebar.compose"]
        return compose.exists && isOnScreen(app, compose)
    }

    func openSidebar(_ app: XCUIApplication) {
        if sidebarIsOpen(app) { return }
        if app.buttons["Menu"].waitForExistence(timeout: 10) {
            app.buttons["Menu"].tap()
        } else {
            button(app, containing: "Sidebar").tap()
        }
        let end = Date().addingTimeInterval(5)
        while Date() < end, !sidebarIsOpen(app) { usleep(200_000) }
        if !sidebarIsOpen(app) {
            logSidebarFrames(app, "did-not-open")
            fail(app, "sidebar-did-not-open", "sidebar did not open")
        }
        // The drawer springs in; a tap while it moves lands on the old position.
        sleep(1)
        logSidebarFrames(app, "drawer-open")
    }

    /// Frames of the gear, the chat panel, its + button and the scrim with the drawer open, to tell a real overlap
    /// from a test mistake: what covers what is visible in the numbers. Written to frames.tsv and attached.
    func logSidebarFrames(_ app: XCUIApplication, _ context: String) {
        func frame(_ element: XCUIElement) -> String {
            element.exists ? NSCoder.string(for: element.frame) + (element.isHittable ? " hittable" : " not-hittable") : "missing"
        }
        let parts = [
            "window=" + NSCoder.string(for: app.windows.firstMatch.frame),
            "gear=" + frame(app.buttons["Settings"].firstMatch),
            "compose=" + frame(app.buttons["sidebar.compose"]),
            "search=" + frame(app.buttons["sidebar.search"]),
            "scrim=" + frame(app.buttons["Close sidebar"]),
            "chatPlus=" + frame(app.buttons["Add"]),
            "menu=" + frame(app.buttons["Menu"]),
            "chat=" + frame(app.descendants(matching: .any)["chat.detail"]),
        ]
        let line = "\(journey)\t\(currentPass.rawValue)\t\(context)\t" + parts.joined(separator: "\t")
        append(line, to: "frames.tsv")
        let attachment = XCTAttachment(string: parts.joined(separator: "\n"))
        attachment.name = "frames-\(journey)-\(currentPass.rawValue)-\(context)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A button that is on screen. Closed-drawer buttons stay in the tree, so plain label lookups can pick them.
    func visibleButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.first(where: { $0.identifier != "sidebar.compose" && isOnScreen(app, $0) }) ?? app.buttons[label].firstMatch
    }

    func openSettings(_ app: XCUIApplication) {
        openSidebar(app)
        for attempt in 1...2 {
            app.buttons["Settings"].firstMatch.tap()
            if app.navigationBars["Settings"].waitForExistence(timeout: 5) || app.staticTexts["Settings"].exists { return }
            if attempt == 1 { step("settings-first-tap-no-sheet"); openSidebar(app) }
        }
        fail(app, "settings-did-not-open", "Settings did not open after two taps")
    }

    /// Records the screen and the element tree as evidence, then fails the test.
    func fail(_ app: XCUIApplication, _ name: String, _ message: String) {
        step(name)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "tree-\(journey)-\(name)"
        tree.lifetime = .keepAlways
        add(tree)
        if let dir = evidenceDir {
            try? app.debugDescription.write(to: dir.appendingPathComponent("\(name).tree.txt"), atomically: true, encoding: .utf8)
        }
        XCTFail(message)
    }

    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) is not reachable")
    }

    /// The home greeting ("What can I help with?"). It is a button now: tapping it swaps the subtitle for a tip.
    func greeting(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["home.greeting"]
    }

    func composer(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["composer.input"]
    }

    /// Mean brightness of the screen, 0 (black) to 1 (white). Tells a dark theme from a light one.
    func brightness() -> Double {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += (0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1]) + 0.114 * Double(pixels[index + 2])) / 255
        }
        return total / Double(side * side)
    }

    var keyboardIsUp: Bool { XCUIApplication().keyboards.count > 0 }
}
