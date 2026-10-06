import XCTest
@testable import ThreadCore

final class StoreTests: XCTestCase {
    var root: URL!
    var store: WorkStore!
    let source = Source(appBundleID: "com.apple.TextEdit", appName: "文本编辑", title: "测试文稿")
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("ThreadTests-" + UUID().uuidString); store = try WorkStore(root: root) }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at: root) }
    @discardableResult func create(_ goal: String = "测试目标") throws -> WorkItem { try store.create(goal: goal, source: source) }
    func testCreateHasNumberedMarkdownAndOverview() throws { let i = try create(); XCTAssertEqual(i.id,"000001"); XCTAssertTrue(FileManager.default.fileExists(atPath: store.noteURL(i.id).path)); XCTAssertTrue(try String(contentsOf: store.overviewURL).contains("[打开笔记](笔记/000001.md)")) }
    func testEmptyGoalDoesNotCreate() throws { XCTAssertThrowsError(try create(" \n ")); XCTAssertEqual(store.items.count,0); XCTAssertEqual(try create().id,"000001") }
    func testSameSourceIndependentNotes() throws { let a = try create("一"); let b = try create("二"); try store.saveNote(a.id,text:"甲",base:""); try store.saveNote(b.id,text:"乙",base:""); XCTAssertEqual(store.item(a.id)?.note,"甲"); XCTAssertEqual(store.item(b.id)?.note,"乙") }
    func testUnicodeAndMarkdownRoundTrip() throws { let i = try create(); let text = "中文输入 🧵\n# 标题\n| 数据 |\n---\n<script>bad()</script>\n"; try store.saveNote(i.id,text:text,base:""); XCTAssertEqual(try MarkdownCodec.decode(Data(contentsOf: store.noteURL(i.id))).note,text) }
    func testCompletionAndRestoreKeepIdentityNoteAndStar() throws { let i = try create(); try store.update(i.id) { $0.starred = true; $0.note = "继续这里" }; try store.complete(i.id); XCTAssertEqual(store.active.count,0); XCTAssertNotNil(store.item(i.id)?.completedAt); try store.restore(i.id); XCTAssertEqual(store.active.first?.id,i.id); XCTAssertEqual(store.active.first?.note,"继续这里"); XCTAssertTrue(store.active.first!.starred); XCTAssertNil(store.active.first!.completedAt) }
    func testOnlyRecentThreeButHistoryRetained() throws { var ids:[String]=[]; for n in 0..<4 { let i=try create("\(n)"); try store.complete(i.id); ids.append(i.id) }; XCTAssertEqual(store.completed.count,4); XCTAssertEqual(store.recentCompleted.count,3); XCTAssertEqual(store.recentCompleted.first?.id,ids.last); try store.restore(ids.last!); XCTAssertEqual(store.recentCompleted.count,3); XCTAssertTrue(store.recentCompleted.contains{$0.id == ids[0]}) }
    func testReorderingAndStarIndependent() throws { let a=try create("一"), b=try create("二"), c=try create("三"); try store.move(a.id,before:c.id); let order=store.active.map(\.id); XCTAssertEqual(order,[a.id,c.id,b.id]); try store.update(b.id){$0.starred=true}; XCTAssertEqual(store.active.map(\.id),order) }
    func testNudgeDown() throws { let a=try create(), b=try create(); try store.nudge(b.id,delta:1); XCTAssertEqual(store.active.map(\.id),[a.id,b.id]) }
    func testRestartRetainsData() throws { let a=try create(); try store.update(a.id){$0.note="保留";$0.starred=true}; try store.complete(a.id); store=nil; store=try WorkStore(root:root); XCTAssertEqual(store.completed.first?.note,"保留"); XCTAssertTrue(store.completed.first!.starred) }
    func testDeleteDoesNotReuseID() throws { let a=try create(); try store.delete(a.id){ try FileManager.default.removeItem(at:$0) }; XCTAssertTrue(store.items.isEmpty); XCTAssertEqual(try create().id,"000002") }
    func testDeleteFailureKeepsRecord() throws { let a=try create(); XCTAssertThrowsError(try store.delete(a.id){_ in throw ThreadError.message("模拟失败")}); XCTAssertNotNil(store.item(a.id)); XCTAssertTrue(FileManager.default.fileExists(atPath:store.noteURL(a.id).path)) }
    func testExternalNoteEditReloads() throws { var a=try create(); a.note="外部修改"; try MarkdownCodec.encode(a).write(to:store.noteURL(a.id)); XCTAssertTrue(store.reload()); XCTAssertEqual(store.item(a.id)?.note,"外部修改") }
    func testConcurrentNoteConflictKeepsBoth() throws { var a=try create(); a.note="外部"; try MarkdownCodec.encode(a).write(to:store.noteURL(a.id)); XCTAssertThrowsError(try store.saveNote(a.id,text:"内部",base:"")); XCTAssertEqual(try MarkdownCodec.decode(Data(contentsOf:store.noteURL(a.id))).note,"外部"); let conflicts=root.appendingPathComponent(".thread/conflicts"); let files=try FileManager.default.contentsOfDirectory(at:conflicts,includingPropertiesForKeys:nil); XCTAssertTrue(try files.contains{try String(contentsOf:$0)=="内部"}) }
    func testExternalMetadataChangeDoesNotLoseNote() throws { var a=try create(); a.starred=true; try MarkdownCodec.encode(a).write(to:store.noteURL(a.id)); try store.saveNote(a.id,text:"内部",base:""); XCTAssertTrue(store.item(a.id)!.starred); XCTAssertEqual(store.item(a.id)?.note,"内部") }
    func testMissingFileNeverOverwritten() throws { let a=try create(); try FileManager.default.removeItem(at:store.noteURL(a.id)); _=store.reload(); XCTAssertNotNil(store.item(a.id)); XCTAssertThrowsError(try store.update(a.id){$0.goal="修改"}); XCTAssertFalse(FileManager.default.fileExists(atPath:store.noteURL(a.id).path)) }
    func testInvalidFilePreserved() throws { let a=try create(); let bad=Data("---\n[]\n---\n正文".utf8); try bad.write(to:store.noteURL(a.id)); XCTAssertThrowsError(try MarkdownCodec.decode(bad)); _=store.reload(); XCTAssertEqual(try Data(contentsOf:store.noteURL(a.id)),bad); XCTAssertFalse(store.issues.isEmpty) }
    func testOverviewExternalEditPausesAndBackup() throws { _=try create(); let custom="# 我的修改"; try custom.write(to:store.overviewURL,atomically:true,encoding:.utf8); try store.refreshOverview(); XCTAssertTrue(store.overviewConflict); XCTAssertEqual(try String(contentsOf:store.overviewURL),custom); try store.refreshOverview(force:true); XCTAssertFalse(store.overviewConflict); let files=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent(".thread/conflicts"),includingPropertiesForKeys:nil); XCTAssertTrue(try files.contains{try String(contentsOf:$0)==custom}) }
    func testOverviewExternalEditSurvivesRestart() throws { _=try create(); try "# 外部".write(to:store.overviewURL,atomically:true,encoding:.utf8); store=nil; store=try WorkStore(root:root); XCTAssertTrue(store.overviewConflict); XCTAssertEqual(try String(contentsOf:store.overviewURL),"# 外部") }
    func testSecondWriterRejected() throws { XCTAssertThrowsError(try WorkStore(root:root)) }
    func testLostCounterBlocksReuse() throws { _=try create(); store=nil; try FileManager.default.removeItem(at:root.appendingPathComponent(".thread/store.json")); XCTAssertThrowsError(try WorkStore(root:root)) }
    func testMetadataIdentityMismatchIsFlagged() throws { var a=try create(); a.id="123456"; try MarkdownCodec.encode(a).write(to:store.noteURL("000001")); _=store.reload(); XCTAssertFalse(store.issues.isEmpty) }
    func testUnsafeWebURLRejected() throws { let s=Source(kind:"webpage",appBundleID:"com.apple.Safari",appName:"Safari",title:"Bad",url:"javascript:alert(1)"); XCTAssertThrowsError(try store.create(goal:"目标",source:s)) }
    func testURLQueryAndFragmentPreserved() throws { let url="https://example.com/p?a=1&b=2#part"; let a=try store.create(goal:"测试",source:Source(kind:"webpage",appBundleID:"com.apple.Safari",appName:"Safari",title:"Page",url:url)); XCTAssertEqual(try MarkdownCodec.decode(Data(contentsOf:store.noteURL(a.id))).source.url,url) }
    func testHTMLCannotExecuteMarkupOrExternalLinks() throws { let text="# <script>alert(1)</script>\n| 000001 | <img src=x onerror=alert(1)> | a | [打开笔记](../../secret.md) |"; let html=Overview.html(markdown:text); XCTAssertFalse(html.contains("<script>")); XCTAssertFalse(html.contains("<img")); XCTAssertFalse(html.contains("href='../../")); XCTAssertTrue(html.contains("&lt;script&gt;")) }
    func testMarkdownFourColumnsWithPipes() throws { _=try create("甲|乙\n下一步"); let text=try String(contentsOf:store.overviewURL); let rows=text.components(separatedBy:.newlines).filter{$0.hasPrefix("| 000")}; XCTAssertEqual(rows.first?.filter{$0=="|"}.count,5); XCTAssertTrue(text.contains("&#124;")); XCTAssertTrue(text.contains("| 编号 | 目标 | 当前打开网页/应用 | 笔记 |")) }
    func testUnknownMetadataPreserved() throws { let a=try create(); var text=try String(contentsOf:store.noteURL(a.id)); text=text.replacingOccurrences(of:"\"goal\"",with:"\"customField\": 42,\n  \"goal\""); try text.write(to:store.noteURL(a.id),atomically:true,encoding:.utf8); _=store.reload(); try store.update(a.id){$0.starred=true}; XCTAssertTrue(try String(contentsOf:store.noteURL(a.id)).contains("\"customField\" : 42")) }
    func testInvalidUpdateDoesNotCorrupt() throws { let a=try create(); XCTAssertThrowsError(try store.update(a.id){$0.source.kind="webpage";$0.source.url="javascript:x"}); XCTAssertEqual(try MarkdownCodec.decode(Data(contentsOf:store.noteURL(a.id))).source.kind,"app") }
    func testRecoverInterruptedTransaction() throws {
        var a=try create(); let original=try Data(contentsOf:store.noteURL(a.id)); a.note="事务恢复后正文"; let updated=try MarkdownCodec.encode(a)
        let tx:[String:Any]=["before":[a.id:original.base64EncodedString()],"after":[a.id:updated.base64EncodedString()]]
        try JSONSerialization.data(withJSONObject:tx).write(to:root.appendingPathComponent(".thread/transaction.json"))
        store=nil; store=try WorkStore(root:root); XCTAssertEqual(store.item(a.id)?.note,"事务恢复后正文"); XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent(".thread/transaction.json").path))
    }
    func testInterruptedTransactionDoesNotOverwriteExternalEdit() throws {
        var a=try create(); let original=try Data(contentsOf:store.noteURL(a.id)); a.note="事务"; let updated=try MarkdownCodec.encode(a)
        let tx:[String:Any]=["before":[a.id:original.base64EncodedString()],"after":[a.id:updated.base64EncodedString()]]
        try JSONSerialization.data(withJSONObject:tx).write(to:root.appendingPathComponent(".thread/transaction.json"))
        a.note="外部不同内容"; let external=try MarkdownCodec.encode(a); try external.write(to:store.noteURL(a.id)); store=nil
        XCTAssertThrowsError(try WorkStore(root:root)); XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("笔记/000001.md")),external)
    }
    func testThousandRecordsReloadAndRender() throws {
        store=nil
        for n in 1...1000 { let i=WorkItem(id:String(format:"%06d",n),goal:"任务 \(n)",source:source,order:Double(n)); try MarkdownCodec.encode(i).write(to:root.appendingPathComponent("笔记/\(i.id).md")) }
        try Data("1000".utf8).write(to:root.appendingPathComponent(".thread/store.json"))
        let start=Date(); store=try WorkStore(root:root)
        let html=Overview.html(markdown:try String(contentsOf:store.overviewURL)); XCTAssertEqual(store.active.count,1000); XCTAssertTrue(html.contains("thread-note:001000")); XCTAssertLessThan(Date().timeIntervalSince(start),5)
        print("PERFORMANCE: 1000 records reload+render \(Date().timeIntervalSince(start)) seconds")
    }
    func testExistingUnmanagedOverviewIsNotOverwritten() throws {
        store=nil; try FileManager.default.removeItem(at:root.appendingPathComponent(".thread/overview-baseline.md")); try "我的原总览".write(to:root.appendingPathComponent("总览.md"),atomically:true,encoding:.utf8)
        store=try WorkStore(root:root); XCTAssertTrue(store.overviewConflict); XCTAssertEqual(try String(contentsOf:store.overviewURL),"我的原总览")
    }

    func testLostCounterAfterAllTasksDeletedStillBlocksReuse() throws {
        let a=try create(); try store.delete(a.id){try FileManager.default.removeItem(at:$0)}; store=nil
        try FileManager.default.removeItem(at:root.appendingPathComponent(".thread/store.json")); XCTAssertThrowsError(try WorkStore(root:root))
    }
    func testPendingTransactionCannotBeOverwrittenByNextEdit() throws {
        var a=try create(); let original=try Data(contentsOf:store.noteURL(a.id)); a.note="恢复事务"; let updated=try MarkdownCodec.encode(a)
        let tx:[String:Any]=["before":[a.id:original.base64EncodedString()],"after":[a.id:updated.base64EncodedString()]]
        try JSONSerialization.data(withJSONObject:tx).write(to:root.appendingPathComponent(".thread/transaction.json"))
        XCTAssertThrowsError(try store.update(a.id){$0.goal="另一项修改"}); XCTAssertEqual(store.item(a.id)?.note,"恢复事务"); XCTAssertEqual(store.item(a.id)?.goal,"测试目标")
    }

}
