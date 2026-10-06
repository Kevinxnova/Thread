import XCTest
@testable import ThreadCore

final class MirrorLinksTests: XCTestCase {
    func item(_ id: String, url: String? = nil) -> WorkItem {
        WorkItem(id: id, goal: "下一步", source: Source(kind: url == nil ? "app" : "webpage", appBundleID: "test", appName: "Test", title: "Window", url: url), order: 0)
    }
    func testCompletingOneOwnerRetainsCaptureUntilLastOwnerFinishes() {
        var links = MirrorLinks(); var a = item("000001"); var b = item("000002")
        links.attach(a, to: 10); links.attach(b, to: 10)
        a.status = "completed"
        XCTAssertTrue(links.reconcile([a,b]).isEmpty)
        XCTAssertEqual(links.owners(10), [b.id])
        b.status = "completed"
        XCTAssertEqual(links.reconcile([a,b]), [10]); XCTAssertTrue(links.windows.isEmpty)
    }
    func testCancelDoesNotAffectOtherTaskAndRebindingReleasesOldWindow() {
        var links = MirrorLinks(); var a = item("000001"); let b = item("000002")
        links.attach(a, to: 10); links.attach(b, to: 10)
        a.pinRequested = false
        XCTAssertTrue(links.reconcile([a,b]).isEmpty)
        XCTAssertEqual(links.attach(b, to: 20), 10)
        XCTAssertEqual(links.windows, [b.id:20])
        XCTAssertEqual(links.reconcile([]), [20])
    }
    func testPageEditInvalidatesBindingAndLatestTaskSelectsSharedPage() {
        var links = MirrorLinks(); var a = item("000001", url: "https://example.com/a"); let b = item("000002", url: "https://example.com/b")
        links.attach(a, to: 10); links.attach(b, to: 10)
        XCTAssertEqual(links.selected[10], b.id)
        links.attach(a, to: 10); XCTAssertEqual(links.selected[10], a.id)
        a.source.url = "https://example.com/c"
        XCTAssertTrue(links.reconcile([a,b]).isEmpty)
        XCTAssertEqual(links.selected[10], b.id)
        XCTAssertEqual(links.owners(10), [b.id])
    }
    func testPromotingExistingMirrorKeepsUniqueOrder() {
        var order = MirrorOrder(); order.add(10); order.add(20); order.promote(10)
        XCTAssertEqual(order.ids,[20,10]); order.promote(10); XCTAssertEqual(order.ids,[20,10])
    }
}
