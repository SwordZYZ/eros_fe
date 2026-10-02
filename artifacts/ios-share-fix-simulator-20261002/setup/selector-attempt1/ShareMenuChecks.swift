import XCTest

final class ShareMenuChecks: XCTestCase {
    func testNativeShareCopy() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.fuhua.erosfe.step5a")
        app.activate()
        let copy = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Copy", "复制", "拷贝", "Copy Link", "复制链接"]
        )).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(copy.isHittable, app.debugDescription)
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "native-share-menu"
        menu.lifetime = .keepAlways
        add(menu)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "native-share-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
        print("SHARE_CLI menu_visible=true copy_hittable=true label=\(copy.label)")
        copy.tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: copy
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "after-copy"
        after.lifetime = .keepAlways
        add(after)
        print("SHARE_CLI copy_tapped=true menu_dismissed=true")
    }
}
