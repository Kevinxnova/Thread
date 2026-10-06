import XCTest
@testable import ThreadCore

final class MirrorGeometryTests: XCTestCase {
    func testLetterboxMappingAndOutsideRejection() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let source = CGRect(x: -1440, y: 100, width: 1000, height: 500)
        let size = CGSize(width: 2000, height: 1000)
        XCTAssertEqual(MirrorGeometry.sourcePoint(CGPoint(x: 200, y: 200), image: size, in: bounds, source: source), CGPoint(x: -940, y: 350))
        XCTAssertNil(MirrorGeometry.sourcePoint(CGPoint(x: 100, y: 50), image: size, in: bounds, source: source))
        XCTAssertEqual(MirrorGeometry.sourcePoint(CGPoint(x: 0, y: 100), image: size, in: bounds, source: source), source.origin)
    }
    func testMovedResizedSourceAndInvalidFrames() {
        let size = CGSize(width: 800, height: 600), bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(MirrorGeometry.sourcePoint(CGPoint(x: 100, y: 75), image: size, in: bounds, source: CGRect(x: 500, y: -800, width: 1200, height: 900)), CGPoint(x: 800, y: -575))
        XCTAssertNil(MirrorGeometry.fittedRect(image: .zero, in: bounds))
        XCTAssertNil(MirrorGeometry.fittedRect(image: CGSize(width: CGFloat.infinity, height: 1), in: bounds))
    }
    func testNewestPriorityDoesNotChangeOnRepeatAndReopenMovesToTop() {
        var order = MirrorOrder()
        order.add(1); order.add(2); order.add(3); order.add(1)
        XCTAssertEqual(order.ids, [1,2,3])
        order.remove(1); order.add(1)
        XCTAssertEqual(order.ids, [2,3,1]); XCTAssertEqual(order.rank(1), 2)
        order.remove(3); XCTAssertEqual(order.rank(1), 1)
        XCTAssertNil(order.rank(3))
    }
}
