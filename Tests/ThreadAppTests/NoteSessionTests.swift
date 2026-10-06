import XCTest
import AppKit
import ThreadCore
@testable import ThreadApp
final class NoteSessionTests: XCTestCase {
    func fixture() throws -> (AppModel, WorkItem, URL) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try AppModel(root: root)
        let item = try model.store.create(goal: "输入验证", source: Source(appBundleID: "test.app", appName: "Test", title: ""))
        return (model, item, root)
    }
    func testOverviewLayoutIsIsolatedByDataDirectory() throws {
        let (a, _, rootA) = try fixture(); let (b, _, rootB) = try fixture()
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        XCTAssertNotEqual(AppCoordinator(model: a).overviewFrameName, AppCoordinator(model: b).overviewFrameName)
        XCTAssertEqual(AppCoordinator(model: a).overviewFrameName, AppCoordinator(model: a).overviewFrameName)
    }
    func testMarkedTextIsNotSavedBeforeCompositionCommits() throws {
        let (model, item, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let session = NoteSession(item: item, model: model)
        let delegate = NativeTextEditor.Coordinator(session: session)
        let editor = NSTextView()
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        delegate.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertEqual(session.text, "")
        editor.unmarkText(); editor.string = "你好，留绪 🧵"
        delegate.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertTrue(session.flush())
        XCTAssertEqual(model.store.item(item.id)?.note, "你好，留绪 🧵")
    }
    func testNoteAndMovedFrameSaveTogether() throws {
        let (model, item, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let session = NoteSession(item: item, model: model)
        session.changed("下一步\n继续检查")
        session.frameChanged(NSRect(x: -300, y: 240, width: 420, height: 360))
        XCTAssertTrue(session.flush())
        let saved = try MarkdownCodec.decode(Data(contentsOf: model.store.noteURL(item.id)))
        XCTAssertEqual(saved.note, "下一步\n继续检查"); XCTAssertEqual(saved.noteFrame, "{{-300, 240}, {420, 360}}")
    }
    func testExternalEditPreventsSuccessfulFlushWithoutDiscardingDraft() throws {
        let (model, item, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let session = NoteSession(item: item, model: model)
        session.changed("我的草稿")
        var external = item; external.note = "外部新内容"
        try MarkdownCodec.encode(external).write(to: model.store.noteURL(item.id))
        XCTAssertFalse(session.flush()); XCTAssertEqual(session.text, "我的草稿")
        XCTAssertTrue(session.status.hasPrefix("未保存"))
        XCTAssertEqual(try MarkdownCodec.decode(Data(contentsOf: model.store.noteURL(item.id))).note, "外部新内容")
    }
}
