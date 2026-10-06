import XCTest
import AppKit
@testable import ThreadApp
final class WindowIdentityTests: XCTestCase {
    func record(pid: pid_t = 1, number: Int? = nil, ax: AXUIElement? = nil) -> WindowRecord {
        WindowRecord(id: UUID().uuidString, pid: pid, bundleID: "test.app", appName: "Test", title: "same", rect: CGRect(x: 0, y: 0, width: 300, height: 200), number: number, ax: ax, minimized: false)
    }
    func testAXIdentitySurvivesChangingCGAvailability() {
        let ax = AXUIElementCreateApplication(1)
        XCTAssertTrue(record(number: 42, ax: ax).matches(record(ax: AXUIElementCreateApplication(1))))
    }
    func testDifferentAXObjectsNeverMatchReusedCGNumber() {
        XCTAssertFalse(record(number: 42, ax: AXUIElementCreateApplication(1)).matches(record(number: 42, ax: AXUIElementCreateApplication(2))))
    }
    func testEqualTitlesAndGeometryDoNotIdentifyAWindow() {
        XCTAssertFalse(record(number: 42).matches(record(number: 43)))
        XCTAssertFalse(record().matches(record()))
    }
    func testSameNumberInDifferentProcessesDoesNotMatch() {
        XCTAssertFalse(record(pid: 1, number: 42).matches(record(pid: 2, number: 42)))
    }
    func testAppKitFrameConversionAcrossDisplayOrigins() {
        let input = CGRect(x: -800, y: -120, width: 500, height: 300)
        let result = WindowCatalog.cocoaRect(input)
        XCTAssertEqual(result.minX, -800)
        XCTAssertEqual(result.maxY, (NSScreen.screens.first?.frame.maxY ?? 0)+120)
    }
    func testOverlappingWindowTitlesDisambiguateButDuplicateTitlesDoNot() {
        let rect = CGRect(x: 50, y: 100, width: 600, height: 400)
        func row(_ id: Int, _ title: String) -> [String: Any] {
            [kCGWindowNumber as String: id, kCGWindowName as String: title, kCGWindowBounds as String: rect.dictionaryRepresentation]
        }
        XCTAssertEqual(WindowCatalog.matchingNumber(rect: rect, title: "Document", rows: [row(1,"Document"), row(2,"Helper")]), 1)
        XCTAssertNil(WindowCatalog.matchingNumber(rect: rect, title: "Document", rows: [row(1,"Document"), row(2,"Document")]))
        XCTAssertNil(WindowCatalog.matchingNumber(rect: rect.offsetBy(dx: 100, dy: 0), title: "Document", rows: [row(1,"Document")]))
    }
}
