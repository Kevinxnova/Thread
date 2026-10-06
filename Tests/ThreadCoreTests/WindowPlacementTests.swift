import XCTest
@testable import ThreadCore
final class WindowPlacementTests: XCTestCase {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    func testRemovedDisplayReturnsWindowToVisibleScreen() {
        let result = WindowPlacement.clamp(CGRect(x: 2200, y: 500, width: 400, height: 340), screens: [main], fallback: main)
        XCTAssertTrue(main.contains(result)); XCTAssertEqual(result.minX, 1040)
    }
    func testNegativeCoordinateScreenIsPreserved() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let frame = CGRect(x: -1400, y: 100, width: 400, height: 340)
        XCTAssertEqual(WindowPlacement.clamp(frame, screens: [main, left], fallback: main), frame)
    }
    func testLargestOverlapChoosesIntendedMonitor() {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let result = WindowPlacement.clamp(CGRect(x: 1400, y: 100, width: 600, height: 340), screens: [main, right], fallback: main)
        XCTAssertEqual(result.minX, 1440)
    }
    func testOversizedWindowFitsSmallScreen() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(WindowPlacement.clamp(CGRect(x: -20, y: -10, width: 1200, height: 900), screens: [screen], fallback: screen), screen)
    }
    func testFrameMetadataSurvivesSaveCompleteAndRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkStore(root: root)
        let item = try store.create(goal: "保持位置", source: Source(appBundleID: "test", appName: "Test", title: ""))
        try store.update(item.id) { $0.noteFrame = "{{100, 200}, {390, 340}}"; $0.markerFrame = "{{400, 200}, {98, 32}}"; $0.markerOffset = "{12, -8}" }
        try store.saveNote(item.id, text: "记录", base: "")
        try store.complete(item.id); try store.restore(item.id)
        let decoded = try MarkdownCodec.decode(Data(contentsOf: store.noteURL(item.id)))
        XCTAssertEqual(decoded.noteFrame, "{{100, 200}, {390, 340}}")
        XCTAssertEqual(decoded.markerFrame, "{{400, 200}, {98, 32}}")
        XCTAssertEqual(decoded.markerOffset, "{12, -8}")
        XCTAssertEqual(decoded.note, "记录")
    }
}
