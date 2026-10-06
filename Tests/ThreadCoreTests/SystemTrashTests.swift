import XCTest
@testable import ThreadCore
final class SystemTrashTests: XCTestCase {
    func testRealTrashOnDisposableGeneratedNote() throws {
        guard ProcessInfo.processInfo.environment["THREAD_TEST_REAL_TRASH"] == "1" else { throw XCTSkip("Run with THREAD_TEST_REAL_TRASH=1 for real system Trash integration") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("thread-trash-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkStore(root: root)
        let item = try store.create(goal: "Thread 自动生成的废纸篓验收条目", source: Source(appBundleID: "test.app", appName: "Test", title: ""))
        try store.saveNote(item.id, text: "仅用于 Thread 验证的可丢弃测试内容。", base: "")
        try store.delete(item.id)
        XCTAssertNil(store.item(item.id)); XCTAssertFalse(FileManager.default.fileExists(atPath: store.noteURL(item.id).path))
        let next = try store.create(goal: "编号不回收", source: item.source)
        XCTAssertNotEqual(next.id, item.id)
    }
}
