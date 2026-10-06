import XCTest
@testable import ThreadCore

final class OverviewDocumentTests: XCTestCase {
    func item(_ id: Int) -> WorkItem { WorkItem(id: String(format: "%06d", id), goal: "整理结论 \(id)", source: Source(appBundleID: "test.app", appName: "应用", title: "同一个窗口"), order: Double(id)) }
    func testAllFourColumnsRoundTripEscapedContent() throws {
        var a = item(1); a.goal = "中文 | [目标] <示例> & &#124;"; a.starred = true
        a.source = Source(kind: "webpage", appBundleID: "test.browser", appName: "浏览器", title: "页面 [标题] | &", url: "https://example.com/a(b)?c=d")
        let doc = try OverviewDocument(markdown: Overview.markdown(active: [a], completed: []))
        XCTAssertEqual(doc.rows[0].goal, a.goal); XCTAssertTrue(doc.rows[0].starred)
        XCTAssertEqual(doc.rows[0].source, "浏览器 · 页面 [标题] | &（状态待检查）")
    }
    func testEmptyAndThousandRowsKeepOrderAndHistory() throws {
        XCTAssertTrue(try OverviewDocument(markdown: Overview.markdown(active: [], completed: [])).rows.isEmpty)
        let items = (1...1000).map(item)
        let doc = try OverviewDocument(markdown: Overview.markdown(active: Array(items.prefix(700)), completed: Array(items.suffix(300))))
        XCTAssertEqual(doc.rows.count, 1000); XCTAssertEqual(doc.rows.map(\.id), items.map(\.id))
        XCTAssertEqual(doc.filtered(.active, query: "").count, 700); XCTAssertEqual(doc.filtered(.completed, query: "").count, 300)
    }
    func testSearchIncludesNoteAndSourceWithoutMutatingDocument() throws {
        var a = item(1); a.starred = true
        let doc = try OverviewDocument(markdown: Overview.markdown(active: [a, item(2)], completed: [item(3)]))
        XCTAssertEqual(doc.filtered(.starred, query: "").map(\.id), [a.id])
        XCTAssertEqual(doc.filtered(.all, query: "  NEEDLE  ", notes: [a.id: "needle 笔记"]).map(\.id), [a.id])
        XCTAssertEqual(doc.filtered(.completed, query: "应用").count, 1)
        XCTAssertEqual(doc.rows.count, 3)
    }
    func testExternalGoalIsShownInsteadOfReconstructed() throws {
        let text = Overview.markdown(active: [item(1)], completed: []).replacingOccurrences(of: "整理结论 1", with: "文件里的新目标")
        XCTAssertEqual(try OverviewDocument(markdown: text).rows.first?.goal, "文件里的新目标")
    }
    func testUnknownAndMalformedContentRequiresWholeDocumentFallback() throws {
        let base = Overview.markdown(active: [item(1)], completed: [])
        for changed in [base + "\n额外段落不能丢失", base.replacingOccurrences(of: "| 编号 |", with: "| ID |"), base.replacingOccurrences(of: "| 000001 |", with: "| 000001 | 额外列 |"), base.replacingOccurrences(of: "## 已完成", with: "## 其他"), Overview.markdown(active: [item(1), item(1)], completed: [])] {
            XCTAssertThrowsError(try OverviewDocument(markdown: changed))
        }
    }
    func testUnsafeOrMismatchedNoteLinksNeverBecomeRows() throws {
        let base = Overview.markdown(active: [item(1)], completed: [])
        for link in ["../secret.md", "笔记/000002.md", "/tmp/000001.md", "https://example.com/000001.md", "笔记/%30%30%30%30%30%31.md"] {
            XCTAssertThrowsError(try OverviewDocument(markdown: base.replacingOccurrences(of: "笔记/000001.md", with: link)))
        }
    }
    func testReadingAndFilteringDoNotWriteAndReadCurrentNote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkStore(root: root)
        let a = try store.create(goal: "目标", source: item(1).source)
        var external = a; external.note = "磁盘笔记新内容"
        try MarkdownCodec.encode(external).write(to: store.noteURL(a.id))
        let before = try Data(contentsOf: store.overviewURL)
        let noteBefore = try Data(contentsOf: store.noteURL(a.id))
        let doc = try OverviewDocument(markdown: String(decoding: before, as: UTF8.self))
        for filter in OverviewDocument.Filter.allCases { _ = doc.filtered(filter, query: "目标") }
        XCTAssertEqual(try OverviewDocument.readNote(id: a.id, root: root).note, external.note)
        XCTAssertEqual(try Data(contentsOf: store.overviewURL), before)
        XCTAssertEqual(try Data(contentsOf: store.noteURL(a.id)), noteBefore)
    }
    func testBrokenMissingSymlinkAndIdentityMismatchNotesAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("笔记"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("笔记/000001.md")
        XCTAssertThrowsError(try OverviewDocument.readNote(id: "000001", root: root))
        try Data("broken".utf8).write(to: file)
        XCTAssertThrowsError(try OverviewDocument.readNote(id: "000001", root: root))
        try MarkdownCodec.encode(item(2)).write(to: file)
        XCTAssertThrowsError(try OverviewDocument.readNote(id: "000001", root: root))
        try FileManager.default.removeItem(at: file)
        let other = root.appendingPathComponent("other.md"); try MarkdownCodec.encode(item(1)).write(to: other)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: other)
        XCTAssertThrowsError(try OverviewDocument.readNote(id: "000001", root: root))
        XCTAssertThrowsError(try OverviewDocument.readNote(id: "../other", root: root))
    }
}
