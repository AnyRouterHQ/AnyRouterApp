import XCTest

/// Settings › Local Models with a model the catalog dropped (Qwen3 0.6B) and an unfinished download on disk
/// (`-ARDemoOffCatalog YES`). The model must stay listed with its note and delete from Installed, or its files fill
/// the phone with no way out; Storage lists everything on disk and clears the unfinished download but not a running one.
@MainActor
final class ModelStorageTests: XCTestCase {
    private let droppedFolder = "gguf--unsloth--Qwen3-0.6B-GGUF--Qwen3-0.6B-Q4_K_M.gguf"

    private func openLocalModels() -> XCUIApplication {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoOffCatalog", "YES"])
        app.showSettingsPage("Local Models")
        return app
    }

    func testAModelTheCatalogDroppedIsListedAndDeletesFromInstalled() {
        let app = openLocalModels()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Qwen3-0.6B")).firstMatch
        app.scrollPage(under: app.navigationBars["Local Models"], until: row)
        XCTAssertTrue(row.isHittable, "the dropped model is listed under Installed")
        XCTAssertTrue(app.words(of: row).contains("No longer in the catalog"), "it says why it is not in the catalog")
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "swipe offers Delete")
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Delete Qwen3-0.6B")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete asks first")
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the model and its files are gone")
    }

    func testStorageListsEverythingOnDiskAndClearsWhatIsLeft() {
        let app = openLocalModels()
        let storage = app.element("local.storage")
        XCTAssertTrue(storage.waitForExistence(timeout: 5), "the storage row is on top")
        XCTAssertTrue(app.words(of: storage).contains("Models use"), "it says what models take")
        storage.tap()
        let bar = app.navigationBars["Storage"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "Storage opened")

        let dropped = app.element("storage.row.\(droppedFolder)")
        XCTAssertTrue(dropped.waitForExistence(timeout: 5), "the dropped model is on the list")
        XCTAssertTrue(app.words(of: dropped).contains("No longer in the catalog"))
        dropped.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "swipe offers Delete")
        delete.tap()
        XCTAssertTrue(dropped.waitForNonExistence(timeout: 5), "a swipe deletes it from disk")

        let unfinished = app.element("storage.row.demo-unfinished")
        XCTAssertTrue(unfinished.exists, "the download that stopped part way is listed")
        let clear = app.buttons["storage.deleteUnfinished"]
        app.scrollPage(under: bar, until: clear)
        XCTAssertTrue(clear.isEnabled, "there is something to clear")
        clear.tap()
        XCTAssertTrue(unfinished.waitForNonExistence(timeout: 5), "the unfinished download is cleared")
        XCTAssertFalse(clear.isEnabled, "nothing left to clear")
        XCTAssertTrue(app.element("storage.row.demo-downloading").exists, "a running download is kept")
    }
}
