import XCTest

/// Captures every main screen from demo data (launch argument `-ARDemoData YES`), light and dark.
/// PNGs are attached to the result bundle and, when SCREENSHOT_DIR is set (via TEST_RUNNER_SCREENSHOT_DIR),
/// written to that folder as `<appearance>-<screen>.png`.
@MainActor
final class ScreenshotTests: XCTestCase {
    private enum Appearance: String, CaseIterable { case light, dark }

    private func forEachAppearance(extra: [String] = [], _ body: (XCUIApplication, Appearance) -> Void) {
        for appearance in Appearance.allCases {
            let app = XCUIApplication()
            app.launchArguments = ["-ARDemoData", "YES", "-ARAppearance", appearance.rawValue] + extra
            app.launch()
            body(app, appearance)
            app.terminate()
        }
    }

    /// `landscape`: `pngRepresentation` stays in the device's portrait frame (content turned). `image` carries the
    /// orientation, but `pngData()` drops it (run 46027222840 saved the iPad landscape capture turned), so the image is
    /// drawn once to bake the orientation into the pixels.
    private func capture(_ name: String, _ appearance: Appearance, landscape: Bool = false) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let png = landscape ? Self.upright(screenshot.image) : screenshot.pngRepresentation
        let attachment = XCTAttachment(uniformTypeIdentifier: "public.png", name: "\(appearance.rawValue)-\(name)", payload: png)
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(appearance.rawValue)-\(name).png")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        } catch {
            XCTFail("Could not write \(url.lastPathComponent): \(error)")
        }
    }

    private static func upright(_ image: UIImage) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in image.draw(at: .zero) }
    }

    /// Menus and sheets animate in; their rows exist before they are drawn, so a capture waits until a row takes taps.
    private func waitUntilHittable(_ element: XCUIElement) {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed, "\(element) never became tappable")
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// iPhone: the sidebar is a drawer behind the menu button. iPad: a column, open in landscape only.
    private func showSidebar(_ app: XCUIApplication) {
        app.revealSidebar(whenVisible: app.buttons["Settings"].firstMatch)
        logFrames(app)
    }

    /// With the drawer closed: is its gear still in the XCUITest tree, and where? (opacity 0 hides it on screen only)
    private func logClosedDrawer(_ app: XCUIApplication) {
        let gear = app.buttons["sidebar.settings"]
        let text = "closed drawer: gear " + (gear.exists ? "IN the tree at " + NSCoder.string(for: gear.frame) : "not in the tree")
            + ", main.container " + (app.descendants(matching: .any)["main.container"].exists ? NSCoder.string(for: app.descendants(matching: .any)["main.container"].frame) : "missing")
        let attachment = XCTAttachment(string: text)
        attachment.name = "closed-drawer"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("frames.txt")
        let entry = "[closed drawer]\n\(text)\n\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }

    /// Frames of the gear, the chat panel, its + button and the scrim with the sidebar open, written to frames.txt.
    private func logFrames(_ app: XCUIApplication) {
        func frame(_ element: XCUIElement) -> String {
            element.exists ? NSCoder.string(for: element.frame) + (element.isHittable ? " hittable" : " not-hittable") : "missing"
        }
        let text = [
            "window=" + NSCoder.string(for: app.windows.firstMatch.frame),
            "gear=" + frame(app.buttons["Settings"].firstMatch),
            "compose=" + frame(app.buttons["sidebar.compose"]),
            "scrim=" + frame(app.buttons["Close sidebar"]),
            "chatPlus=" + frame(app.buttons["Add"]),
            "chat=" + frame(app.descendants(matching: .any)["chat.detail"]),
        ].joined(separator: "\n")
        // With the drawer open the gear must be hittable; when it is not, keep the element tree to see what sits on top.
        if app.buttons["Settings"].firstMatch.exists, !app.buttons["Settings"].firstMatch.isHittable {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tree-\(name)"
            tree.lifetime = .keepAlways
            add(tree)
            if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
                try? app.debugDescription.write(to: URL(fileURLWithPath: dir).appendingPathComponent("drawer-tree.txt"), atomically: true, encoding: .utf8)
            }
        }
        let attachment = XCTAttachment(string: text)
        attachment.name = "frames-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let short = name.split(separator: " ").last.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "]")) } ?? "test"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("drawer-open-\(short).png"))
        let url = URL(fileURLWithPath: dir).appendingPathComponent("frames.txt")
        let entry = "[\(name)]\n\(text)\n\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }

    private func open(_ app: XCUIApplication, footer title: String) {
        showSidebar(app)
        tapRow(button(app, containing: title))
    }

    /// Taps a drawer row through the accessibility tree. The rows must be hittable there: the chat's accessibility
    /// container is hidden while the drawer is open, so Switch Control and VoiceOver reach them too.
    private func tapRow(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "row \(element)")
        XCTAssertTrue(element.isHittable, "drawer row is reachable through the accessibility tree: \(element)")
        element.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while (!element.exists || !element.isHittable) && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    func testOnboarding() {
        forEachAppearance(extra: ["-ARDemoOnboarding", "YES"]) { app, appearance in
            XCTAssertTrue(app.staticTexts["Welcome to AnyRouter"].waitForExistence(timeout: 15))
            capture("onboarding", appearance)
        }
    }

    /// What a finger does: a tap at the gear's centre with the drawer open, independent of XCUITest's hittability.
    /// If Settings opens, the drawer works and a "not hittable" report is an accessibility-tree problem.
    func testDrawerGearOpensSettingsByCoordinate() {
        forEachAppearance { app, appearance in
            showSidebar(app)
            let gear = app.buttons["Settings"].firstMatch
            XCTAssertTrue(gear.exists, "gear is in the tree")
            XCTAssertTrue(gear.isHittable, "gear is hittable with the drawer open")
            gear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "a tap at the gear's centre opens Settings")
            capture("drawer-gear-coordinate-tap", appearance)
        }
    }

    /// The drawer with no pinned chat: the Pinned section goes away and Recents follows Apps.
    func testSidebarWithoutPins() {
        forEachAppearance(extra: ["-ARDemoLongThread", "8", "-ARDemoNoPins", "YES"]) { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20))
            showSidebar(app)
            XCTAssertFalse(app.staticTexts["Pinned"].exists, "no Pinned section without pinned chats")
            capture("sidebar-no-pins", appearance)
        }
    }

    /// The rename alert opened from the chat's "..." menu, then the sidebar. Demo chats keep the titles they were made with;
    /// a generated title needs a model, which the simulator run does not have.
    func testRenameChatAlertAndSidebar() {
        forEachAppearance(extra: ["-ARDemoLongThread", "8"]) { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20))
            app.buttons["chat.more"].tap()
            XCTAssertTrue(app.buttons["chat.rename"].waitForExistence(timeout: 5))
            app.buttons["chat.rename"].tap()
            XCTAssertTrue(app.alerts["Rename chat"].waitForExistence(timeout: 5))
            capture("rename-alert", appearance)
            app.alerts["Rename chat"].buttons["Cancel"].tap()
            showSidebar(app)
            capture("sidebar-titles", appearance)
        }
    }

    func testEmptyChat() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["home.greeting"].waitForExistence(timeout: 15))
            logClosedDrawer(app)
            // Nothing is copied in a demo run, so the cards are the general starters; the demo model takes tools.
            XCTAssertTrue(app.descendants(matching: .any)["composer.suggestion.preset.what-time"].waitForExistence(timeout: 5),
                          "an empty clipboard offers starters that work right away")
            capture("empty-chat", appearance)
        }
    }

    /// The row above the composer when text was copied (the "Copied text" chip, then cards that act on the copy), and after
    /// the chip is tapped (text presets for what was pasted). `-ARDemoClipboard` makes the app offer the row; the runner puts the
    /// text on the system pasteboard. Reading it in code may ask "Allow Paste" once.
    func testComposerSuggestions() {
        let sample = "Hi team, can you send me the revised budget by Friday? I need to review it before the meeting, thanks."
        UIPasteboard.general.string = sample
        forEachAppearance(extra: ["-ARDemoClipboard", "YES"]) { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["home.greeting"].waitForExistence(timeout: 15))
            let paste = app.descendants(matching: .any)["composer.suggestion.clipboard"]
            XCTAssertTrue(paste.waitForExistence(timeout: 10), "the copy's chip leads the row")
            XCTAssertTrue(app.descendants(matching: .any)["composer.suggestion.preset.explain-text"].exists,
                          "copied text turns the cards into actions on it")
            let hide = app.descendants(matching: .any)["composer.suggestion.hide"]
            XCTAssertTrue(hide.isHittable, "Hide is in view at the end of the row")
            XCTAssertGreaterThanOrEqual(hide.frame.width, 44, "Hide is at least 44 pt wide")
            XCTAssertGreaterThanOrEqual(hide.frame.height, 44, "Hide is at least 44 pt tall")
            capture("composer-clipboard", appearance)
            paste.tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            XCTAssertTrue(app.descendants(matching: .any)["composer.suggestions"].waitForExistence(timeout: 5))
            sleep(1)
            XCTAssertFalse(paste.exists, "the copy's chip is gone after a paste")
            capture("composer-after-paste", appearance)
        }
    }

    /// The voice button on a phone with no speech model downloaded: the Voice Mode cover naming the model with its real size,
    /// then the picker for another model open.
    func testVoiceModeGate() throws {
        var offered = true
        forEachAppearance { app, appearance in
            let voice = app.buttons["Voice input"]
            XCTAssertTrue(voice.waitForExistence(timeout: 15))
            voice.tap()
            guard app.descendants(matching: .any)["voice-gate.title"].waitForExistence(timeout: 5) else {
                offered = false
                return
            }
            capture("voice-mode-gate", appearance)
            XCTAssertTrue(app.descendants(matching: .any)["voice-gate.model"].exists, "the gate names the model")
            let choose = app.buttons["voice-gate.choose"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5), "a phone that fits more than one speech model can pick another")
            choose.tap()
            let recommended = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Recommended")).firstMatch
            XCTAssertTrue(recommended.waitForExistence(timeout: 5), "the picker marks this device's model")
            capture("voice-mode-gate-picker", appearance)
        }
        if !offered { throw XCTSkip("No speech model fits this simulator, so the voice button dictates at once") }
    }

    /// The More menu on the empty chat: the phone use cases under "On this device", then the presets.
    func testComposerMoreMenu() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["home.greeting"].waitForExistence(timeout: 15))
            let more = app.descendants(matching: .any)["composer.suggestion.more"]
            XCTAssertTrue(more.waitForExistence(timeout: 10), "the More menu ends the row")
            // More stays in view beside the scrolling cards, so Edit Presets… needs no scroll, and it is a full hit area.
            XCTAssertTrue(more.isHittable, "More is reachable without scrolling the cards")
            XCTAssertGreaterThanOrEqual(more.frame.width, 44, "More is at least 44 pt wide")
            XCTAssertGreaterThanOrEqual(more.frame.height, 44, "More is at least 44 pt tall")
            more.tap()
            XCTAssertTrue(app.descendants(matching: .any)["composer.suggestion.edit"].waitForExistence(timeout: 5), "Edit Presets is in the menu")
            capture("composer-more-menu", appearance)
        }
    }

    /// The + menu from the top (Camera first), its Tools submenu with this chat's switch, and the "On this device" switches.
    func testPlusMenu() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["home.greeting"].waitForExistence(timeout: 15))
            app.buttons["Add"].tap()
            XCTAssertTrue(app.buttons["composer.add-camera"].waitForExistence(timeout: 5))
            capture("plus-menu", appearance)
            let tools = app.descendants(matching: .any)["composer.tools"]
            guard tools.exists else { return XCTFail("the demo model takes tools, so Tools is in the menu") }
            tools.tap()
            XCTAssertTrue(app.descendants(matching: .any)["composer.tools-toggle"].waitForExistence(timeout: 5))
            waitUntilHittable(app.descendants(matching: .any)["composer.tool-group.device"])
            capture("plus-menu-tools", appearance)
            let device = app.descendants(matching: .any)["composer.tool-group.device"]
            XCTAssertTrue(device.waitForExistence(timeout: 5))
            device.tap()
            XCTAssertTrue(app.descendants(matching: .any)["composer.tool-source.device"].waitForExistence(timeout: 5))
            waitUntilHittable(app.descendants(matching: .any)["composer.tool-source.device"])
            capture("plus-menu-tools-device", appearance)
        }
    }

    /// The @ list: every plugin with its icon and On or Off, then presets and files.
    func testMentionPanel() {
        forEachAppearance { app, appearance in
            let input = app.descendants(matching: .any)["composer.input"]
            XCTAssertTrue(input.waitForExistence(timeout: 15))
            input.tap()
            input.typeText("@")
            XCTAssertTrue(app.descendants(matching: .any)["mention.panel"].waitForExistence(timeout: 5), "the @ list opens")
            // Audit #3: the field and its button once sat half under the keyboard with the list open.
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists {
                XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 1, "the field stays above the keyboard")
                XCTAssertLessThanOrEqual(app.buttons["composer.action"].frame.maxY, keyboard.frame.minY + 1)
            }
            capture("composer-mention-panel", appearance)
        }
    }

    func testThreadMenu() {
        forEachAppearance { app, appearance in
            let row = app.staticTexts["Dinner with chickpeas"]
            app.revealSidebar(whenVisible: row)
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.press(forDuration: 1.2)
            let archive = app.buttons["thread.menu.archive"]
            XCTAssertTrue(archive.waitForExistence(timeout: 5))
            waitUntilHittable(archive)
            capture("thread-menu", appearance)
        }
    }

    func testThreadList() {
        forEachAppearance { app, appearance in
            showSidebar(app)
            XCTAssertTrue(app.staticTexts["Explain Swift actors"].waitForExistence(timeout: 5))
            capture("thread-list", appearance)
        }
    }

    /// iPad only: the split view in landscape, sidebar open next to the chat.
    func testPadSplitLandscape() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        XCUIDevice.shared.orientation = .landscapeLeft
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            sleep(1)
            capture("pad-split-landscape", appearance, landscape: true)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testChatWithMarkdown() {
        forEachAppearance { app, appearance in
            showSidebar(app)
            tapRow(app.staticTexts["Explain Swift actors"])
            XCTAssertTrue(app.replyText("Key points:").waitForExistence(timeout: 10))
            capture("chat-markdown", appearance)
        }
    }

    /// One reply with its parts: the reasoning row, the tool line, the answer, a photo and a file card, and the footer.
    /// The photo opens full screen and a double tap zooms it; the reasoning row opens to its text.
    func testReplyParts() {
        forEachAppearance(extra: ["-ARDemoParts", "YES"]) { app, appearance in
            showSidebar(app)
            tapRow(app.staticTexts["Reply parts"])
            let reasoning = app.buttons["reasoning.row"].firstMatch
            XCTAssertTrue(reasoning.waitForExistence(timeout: 10), "the reasoning row is there")
            XCTAssertTrue(reasoning.label.contains("Thought for 12s"), "it says how long the model thought: \(reasoning.label)")
            let photo = app.buttons["attachment.diagram.jpg"].firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 10), "the photo sits under the answer")
            XCTAssertTrue(app.buttons["attachment.Actors.pdf"].firstMatch.exists, "and so does the file card")
            capture("reply-parts", appearance)

            // The photo tile can sit under the composer when the thread opens; scroll it up so the tap lands on it.
            var lifts = 0
            while !photo.isHittable && lifts < 6 { app.swipeUp(); lifts += 1 }
            photo.tap()
            let viewer = app.descendants(matching: .any)["image-viewer.image"]
            XCTAssertTrue(viewer.waitForExistence(timeout: 10), "a tap on the photo opens the viewer")
            capture("image-viewer", appearance)
            viewer.doubleTap()
            sleep(1)
            capture("image-viewer-zoomed", appearance)
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(reasoning.waitForExistence(timeout: 10), "the viewer closes back to the chat")

            // The lift above can push the reasoning row off the top; bring it back before the tap.
            var drops = 0
            while !reasoning.isHittable && drops < 6 { app.swipeDown(); drops += 1 }
            reasoning.tap()
            XCTAssertTrue(app.descendants(matching: .any)["reasoning.text"].firstMatch.waitForExistence(timeout: 5))
            capture("reply-parts-reasoning-open", appearance)

            let subagent = app.buttons["subagent.card"].firstMatch
            XCTAssertTrue(subagent.waitForExistence(timeout: 5), "the subagent is one collapsed line")
            XCTAssertTrue(subagent.label.contains("Subagent · Research · 4 steps"), "its heading: \(subagent.label)")
            subagent.tap()
            capture("reply-parts-subagent-open", appearance)

            // The folded part of the chat is above: the divider, then the summary it stands for.
            let divider = app.buttons["compaction.divider"].firstMatch
            var tries = 0
            while !(divider.exists && divider.isHittable) && tries < 6 {
                app.swipeDown()
                tries += 1
            }
            XCTAssertTrue(divider.exists, "the divider between the folded messages and the rest")
            divider.tap()
            XCTAssertTrue(app.descendants(matching: .any)["compaction.summary"].firstMatch.waitForExistence(timeout: 5))
            capture("reply-parts-compaction", appearance)
        }
    }

    /// A markdown reply that cites pages: the footer row with its favicon chain and "5 sources", then the list behind it.
    func testReplyWithSources() {
        forEachAppearance(extra: ["-ARDemoSources", "YES"]) { app, appearance in
            showSidebar(app)
            tapRow(app.staticTexts["Swift actors with sources"])
            XCTAssertTrue(app.replyText("Key points:").waitForExistence(timeout: 10))
            let sources = app.buttons["reply.sources"].firstMatch
            XCTAssertTrue(sources.waitForExistence(timeout: 5))
            XCTAssertEqual(sources.label, "5 sources", "six results, one of them the same page twice")
            XCTAssertFalse(app.buttons["reply.share"].exists, "share moved into the reply's long-press menu")
            capture("reply-sources", appearance)
            sources.tap()
            XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 5))
            let first = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "docs.example.com")).firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 5), "the list names each page and its host")
            capture("sources-sheet", appearance)
        }
    }

    /// Settings, Responses: the text size slider, the font picker and the live preview; then the same
    /// markdown reply at the largest step in the serif font.
    func testReplyTextSettings() {
        forEachAppearance { app, appearance in
            open(app, footer: "Settings")
            let row = button(app, containing: "Responses")
            scrollTo(row, in: app)
            row.tap()
            let slider = app.sliders["settings-reply-text-size"]
            XCTAssertTrue(slider.waitForExistence(timeout: 10))
            scrollTo(slider, in: app)
            // A form sheet on iPad is short: the preview is a lazy row below the slider, so scroll until it is built.
            let preview = app.descendants(matching: .any)["preview.reply-text"]
            var swipes = 0
            while !preview.exists && swipes < 4 { app.swipeUp(); swipes += 1 }
            XCTAssertTrue(preview.exists, "the preview sits under the font picker")
            capture("reply-text-settings", appearance)
        }
        forEachAppearance(extra: ["-ARReplyTextStep", "3", "-ARReplyFont", "serif"]) { app, appearance in
            showSidebar(app)
            tapRow(app.staticTexts["Explain Swift actors"])
            XCTAssertTrue(app.replyText("Key points:").waitForExistence(timeout: 10))
            capture("chat-markdown-large-serif", appearance)
        }
    }

    func testResponseDetailsAndSwitchNote() {
        forEachAppearance { app, appearance in
            showSidebar(app)
            tapRow(app.staticTexts["Switch models in a chat"])
            XCTAssertTrue(app.staticTexts["switch-note"].waitForExistence(timeout: 10), "the switch note sits between the replies")
            // A free cloud reply, a paid one and a local one, each with its own footer line.
            let paid = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "$0.0004")).firstMatch
            XCTAssertTrue(paid.waitForExistence(timeout: 5), "the paid reply shows its price")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Gemma 4 E2B")).firstMatch.exists, "the local reply has a line")
            let free = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Nemotron 3.5")).firstMatch
            XCTAssertTrue(free.exists, "the free reply has a line too")
            XCTAssertFalse(free.label.contains("$"), "a free reply shows no price")
            capture("response-footer", appearance)
            paid.tap()
            XCTAssertTrue(app.buttons["reply.details.copy-all"].waitForExistence(timeout: 5), "the details sheet opens")
            capture("response-details", appearance)
            // Request ID is the last section of a lazy list in a half-height sheet: it is built once scrolled to.
            let list = app.descendants(matching: .any)["reply.details"]
            let requestID = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "req_demo02", "req_demo02")).firstMatch
            var swipes = 0
            while !requestID.exists && swipes < 4 { list.swipeUp(); swipes += 1 }
            XCTAssertTrue(requestID.exists, "the details end with the request ID")
        }
    }

    func testModelPickerFilters() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            app.buttons["Model"].tap()
            let tabs = app.segmentedControls.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 5))
            tabs.buttons["AnyRouter"].tap()
            XCTAssertTrue(app.buttons["model-filter"].waitForExistence(timeout: 5))
            app.buttons["model-filter"].tap()
            XCTAssertTrue(app.switches["filter-free-only"].waitForExistence(timeout: 5))
            capture("model-filters", appearance)
            // A tap at the switch row's center lands on the label; tap the switch itself.
            app.switches["filter-free-only"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            app.buttons["Done"].tap()
            capture("model-picker-free", appearance)
        }
    }

    /// A reply that failed: the sentence, Retry, then the raw text behind Details.
    func testFailedReply() {
        forEachAppearance(extra: ["-ARDemoFail", "rateLimited"]) { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["home.greeting"].waitForExistence(timeout: 15))
            let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
            field.tap()
            field.typeText("Plan a weekend in Porto")
            app.buttons["Send"].tap()
            let failure = app.buttons["reply-failure"]
            XCTAssertTrue(failure.waitForExistence(timeout: 10))
            app.swipeDown()
            capture("failed-reply", appearance)
            failure.tap()
            XCTAssertTrue(app.descendants(matching: .any)["reply-failure.detail"].waitForExistence(timeout: 5))
            capture("failed-reply-details", appearance)
        }
    }

    /// A reply streams and two messages wait above the composer.
    func testQueuedMessages() {
        forEachAppearance(extra: ["-ARDemoStream", "1000@20"]) { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["home.greeting"].waitForExistence(timeout: 15))
            let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
            field.tap()
            field.typeText("Plan a weekend in Porto")
            app.buttons["composer.action"].tap()
            XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
            for text in ["Add a day trip to Douro", "Keep it under 300 euros"] {
                field.tap()
                field.typeText(text)
                app.buttons["composer.action"].tap()
            }
            XCTAssertTrue(app.descendants(matching: .any)["chat.queue.row"].waitForExistence(timeout: 5))
            capture("queued-messages", appearance)
        }
    }

    func testComposerWithText() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["home.greeting"].waitForExistence(timeout: 15))
            let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
            field.tap()
            field.typeText("Write a haiku about routers")
            capture("composer-text", appearance)
        }
    }

    /// The picker at its medium height, both tabs: the last Local row must not sit under anything (operator's device).
    func testModelPickerMedium() {
        forEachAppearance(extra: ["-ARDemoPickerMedium", "YES"]) { app, appearance in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            app.buttons["Model"].tap()
            let tabs = app.segmentedControls.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 5))
            let local = tabs.buttons["Local"]
            for _ in 0..<3 where !local.isSelected {
                local.tap()
                sleep(1)
            }
            XCTAssertTrue(app.buttons["model-row.apple/foundation"].waitForExistence(timeout: 5))
            capture("model-picker-local-medium", appearance)
            tabs.buttons["AnyRouter"].tap()
            sleep(1)
            capture("model-picker-medium", appearance)
        }
    }

    func testModelPicker() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            app.buttons["Model"].tap()
            let tabs = app.segmentedControls.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 5))
            // The sheet opens on the tab of the current model (AnyRouter in demo data), so switch before the capture.
            // Both tabs' rows can sit in the tree, so wait for the segment itself to be selected, not for a row.
            let local = tabs.buttons["Local"]
            for _ in 0..<3 where !local.isSelected {
                local.tap()
                sleep(1)
            }
            XCTAssertTrue(local.isSelected, "the Local segment is selected before the capture")
            XCTAssertTrue(app.buttons["model-row.apple/foundation"].waitForExistence(timeout: 5))
            capture("model-picker-local", appearance)
            tabs.buttons["AnyRouter"].tap()
            XCTAssertTrue(app.buttons["model-row.anyrouter/anthropic/claude-sonnet-4-6"].waitForExistence(timeout: 5))
            capture("model-picker", appearance)
        }
    }

    func testHub() {
        forEachAppearance { app, appearance in
            // The sidebar has no hub entry any more: Settings > Models > Local Models.
            open(app, footer: "Settings")
            let manage = button(app, containing: "Local Models")
            scrollTo(manage, in: app)
            manage.tap()
            XCTAssertTrue(app.navigationBars["Local Models"].waitForExistence(timeout: 10))
            capture("hub", appearance)
        }
    }

    /// Browse all models scrolled to the experimental Inkling 2 Mini row (its symbol tile, size and fit line).
    func testHubInkling() {
        forEachAppearance { app, appearance in
            open(app, footer: "Settings")
            let manage = button(app, containing: "Local Models")
            scrollTo(manage, in: app)
            manage.tap()
            XCTAssertTrue(app.navigationBars["Local Models"].waitForExistence(timeout: 10))
            let browse = app.buttons["local.browse"]
            scrollTo(browse, in: app)
            browse.tap()
            let inkling = button(app, containing: "Inkling 2 Mini")
            scrollTo(inkling, in: app)
            capture("hub-inkling", appearance)
        }
    }

    private func openApps(_ app: XCUIApplication) {
        showSidebar(app)
        tapRow(app.buttons["sidebar-apps"])
        XCTAssertTrue(app.navigationBars["Apps"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["apps-tile-scam-check"].waitForExistence(timeout: 5))
    }

    /// The model row's logo once filled the whole Decisions sheet: a picker dropped the logo's frame (ab9181a).
    private func assertNoGiantImages(_ app: XCUIApplication, _ screen: String, maxHeight: CGFloat = 60) {
        for image in app.images.allElementsBoundByIndex where image.exists {
            XCTAssertLessThan(image.frame.height, maxHeight,
                              "an image in \(screen) is \(image.frame.height) pt tall: id '\(image.identifier)', label '\(image.label)', frame \(image.frame)")
        }
    }

    func testDecisions() {
        forEachAppearance { app, appearance in
            openApps(app)
            assertNoGiantImages(app, "Apps")
            capture("apps", appearance)
        }
    }

    /// A text app: a sample, Run, the answer as one sentence and its bars.
    func testDecisionTextApp() {
        forEachAppearance { app, appearance in
            openApps(app)
            app.buttons["apps-tile-email-triage"].tap()
            let sample = app.buttons["decisions-sample-Needs a reply"]
            XCTAssertTrue(sample.waitForExistence(timeout: 10))
            sample.tap()
            app.buttons["decisions-run"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["decisions-result-line"].waitForExistence(timeout: 10))
            assertNoGiantImages(app, "a decision app")
            app.swipeUp()
            capture("decision-text-result", appearance)
        }
    }

    /// A photo app: the demo receipt (the Simulator has no camera), Run, the answer.
    func testDecisionPhotoApp() {
        forEachAppearance(extra: ["-ARDemoDecisionPhoto", "YES"]) { app, appearance in
            openApps(app)
            app.buttons["apps-tile-receipt-sort"].tap()
            XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: 15), "the demo photo is in the row")
            capture("decision-photo-ready", appearance)
            app.buttons["decisions-run"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["decisions-result-line"].waitForExistence(timeout: 10))
            // The 88 pt photo tile fills its square, so XCUITest reports the photo's unclipped height (117 pt for the
            // 3:4 demo receipt). A giant image is the height of the sheet.
            assertNoGiantImages(app, "a decision app", maxHeight: 200)
            app.swipeUp()
            capture("decision-photo-result", appearance)
        }
    }

    /// Traffic sign: photo first, the demo stop sign (the Simulator has no camera), Run, the answer.
    func testDecisionTrafficSign() {
        forEachAppearance(extra: ["-ARDemoDecisionPhoto", "YES"]) { app, appearance in
            openApps(app)
            app.buttons["apps-tile-traffic-sign"].tap()
            XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: 15), "the demo sign is in the row")
            capture("decision-sign-ready", appearance)
            app.buttons["decisions-run"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["decisions-result-line"].waitForExistence(timeout: 10))
            assertNoGiantImages(app, "a decision app", maxHeight: 200)
            app.swipeUp()
            capture("decision-sign-result", appearance)
        }
    }

    /// The custom decision, empty and then filled by a sample.
    func testDecisionCustom() {
        forEachAppearance { app, appearance in
            openApps(app)
            app.buttons["apps-tile-custom"].tap()
            XCTAssertTrue(app.navigationBars["Custom decision"].waitForExistence(timeout: 10))
            capture("decision-custom-empty", appearance)
            let sample = app.buttons["decisions-sample-Email"]
            XCTAssertTrue(sample.waitForExistence(timeout: 5))
            sample.tap()
            capture("decision-custom-filled", appearance)
        }
    }

    /// Extract from the + menu: empty, with a document, with fields, and with one field's source marked.
    private func extractShot(_ stage: String?, _ name: String, tapsField: String? = nil) {
        forEachAppearance(extra: stage.map { ["-ARDemoExtract", $0] } ?? []) { app, appearance in
            XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 15))
            app.buttons["Add"].tap()
            XCTAssertTrue(app.buttons["composer.extract"].waitForExistence(timeout: 5))
            app.buttons["composer.extract"].tap()
            XCTAssertTrue(app.navigationBars["Extract"].waitForExistence(timeout: 10))
            if stage == "fields" || stage == "selected" {
                XCTAssertTrue(app.buttons["extract-field-Total"].waitForExistence(timeout: 5))
            }
            if let tapsField { app.buttons["extract-field-\(tapsField)"].tap() }
            capture(name, appearance)
        }
    }

    func testExtractEmpty() { extractShot(nil, "extract-empty") }
    func testExtractWithADocument() { extractShot("document", "extract-document") }
    func testExtractWithFields() { extractShot("fields", "extract-fields") }
    func testExtractWithOneFieldHighlighted() { extractShot("selected", "extract-highlighted") }

    func testAttachmentChip() {
        forEachAppearance(extra: ["-ARDemoAttachFile", "YES"]) { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["attachment-chip.notes.txt"].waitForExistence(timeout: 20))
            capture("attachment-chip", appearance)
        }
    }

    func testSettings() {
        forEachAppearance { app, appearance in
            open(app, footer: "Settings")
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
            capture("settings", appearance)
        }
    }

    /// The pages that moved off the root list: Chat Behavior, Shortcuts & Controls and About.
    func testSettingsPages() {
        forEachAppearance { app, appearance in
            open(app, footer: "Settings")
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
            for (row, shot) in [("Chat Behavior", "settings-chat-behavior"), ("Shortcuts & Controls", "settings-shortcuts"), ("About", "settings-about")] {
                let element = button(app, containing: row)
                scrollTo(element, in: app)
                element.tap()
                XCTAssertTrue(app.navigationBars[row].waitForExistence(timeout: 5), "\(row) page")
                capture(shot, appearance)
                app.buttons["BackButton"].tap()
                XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            }
        }
    }

    /// Settings > Memory with a few items, in the order the page groups them.
    func testSettingsMemory() {
        forEachAppearance(extra: ["-ARDemoMemories", "YES"]) { app, appearance in
            open(app, footer: "Settings")
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
            let element = button(app, containing: "Memory")
            scrollTo(element, in: app)
            element.tap()
            XCTAssertTrue(app.navigationBars["Memory"].waitForExistence(timeout: 5))
            capture("settings-memory", appearance)
            app.swipeUp()
            capture("settings-memory-more", appearance)
        }
    }

    func testSettingsAccountSignedOut() {
        forEachAppearance(extra: ["-ARDemoSignedOut", "YES"]) { app, appearance in
            open(app, footer: "Settings")
            XCTAssertTrue(app.buttons["Sign in with AnyRouter"].waitForExistence(timeout: 10))
            capture("settings-account", appearance)
        }
    }

    func testLicenses() {
        forEachAppearance { app, appearance in
            open(app, footer: "Settings")
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
            let about = button(app, containing: "About")
            scrollTo(about, in: app)
            about.tap()
            let licenses = app.buttons["Licenses"]
            XCTAssertTrue(licenses.waitForExistence(timeout: 5))
            licenses.tap()
            XCTAssertTrue(app.staticTexts["Licenses"].waitForExistence(timeout: 5))
            capture("licenses", appearance)
        }
    }
}
