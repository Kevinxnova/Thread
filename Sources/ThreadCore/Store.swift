import Foundation
import Darwin

public final class WorkStore {
    public let root: URL
    public private(set) var items: [WorkItem] = []
    public private(set) var issues: [String] = []
    public private(set) var overviewConflict = false
    private var snapshots: [String: Data] = [:]
    private var missing = Set<String>()
    private var overviewSnapshot: Data?
    private var lockFD: Int32 = -1
    private var highWater: Int = 0
    private let fm = FileManager.default
    public var notesURL: URL { root.appendingPathComponent("笔记", isDirectory: true) }
    public var overviewURL: URL { root.appendingPathComponent("总览.md") }
    private var state: URL { root.appendingPathComponent(".thread", isDirectory: true) }
    private var journal: URL { state.appendingPathComponent("transaction.json") }
    public var active: [WorkItem] { items.filter { $0.status == "active" }.sorted { $0.activeOrder == $1.activeOrder ? $0.id < $1.id : $0.activeOrder < $1.activeOrder } }
    public var completed: [WorkItem] { items.filter { $0.status == "completed" }.sorted { $0.completedOrder == $1.completedOrder ? $0.id > $1.id : $0.completedOrder < $1.completedOrder } }
    public var recentCompleted: [WorkItem] { Array(items.filter { $0.status == "completed" }.sorted { $0.completedAt == $1.completedAt ? $0.id > $1.id : ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.prefix(3)) }
    public func item(_ id: String) -> WorkItem? { items.first { $0.id == id } }
    public func noteURL(_ id: String) -> URL { notesURL.appendingPathComponent(id + ".md") }
    public init(root: URL) throws {
        self.root = root
        let hadState = fm.fileExists(atPath: state.path)
        try fm.createDirectory(at: notesURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: state, withIntermediateDirectories: true)
        lockFD = Darwin.open(state.appendingPathComponent("writer.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { if lockFD >= 0 { close(lockFD); lockFD = -1 }; throw ThreadError.message("这个数据目录已被另一个 Thread 实例使用。") }
        do {
            let counter = state.appendingPathComponent("store.json")
            let notesExist = !(try fm.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }).isEmpty
            if fm.fileExists(atPath: counter.path) { highWater = try JSONDecoder().decode(Int.self, from: Data(contentsOf: counter)) }
            else if hadState || notesExist { throw ThreadError.message("编号记录缺失。请恢复 .thread/store.json 后再打开，避免复用历史编号。") }
            try recover()
            _ = reload()
            highWater = max(highWater, items.compactMap { Int($0.id) }.max() ?? 0)
            try atomic(try JSONEncoder().encode(highWater), to: counter)
            if fm.fileExists(atPath: overviewURL.path) {
                let disk = try Data(contentsOf: overviewURL)
                if (try? Data(contentsOf: state.appendingPathComponent("overview-baseline.md"))) != disk { overviewConflict = true; issues.append("总览存在外部修改，已暂停自动覆盖。") }
                overviewSnapshot = disk
            }
            try refreshOverview()
        } catch { close(lockFD); lockFD = -1; throw error }
    }
    deinit { if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) } }
    private struct Transaction: Codable { var before: [String: Data?]; var after: [String: Data] }
    private func recover() throws {
        guard fm.fileExists(atPath: journal.path) else { return }
        let tx = try JSONDecoder().decode(Transaction.self, from: Data(contentsOf: journal))
        for (id, after) in tx.after {
            guard id.range(of: "^[0-9]{6,}$", options: .regularExpression) != nil else { throw ThreadError.message("事务编号无效。") }
            let disk = try? Data(contentsOf: noteURL(id))
            let before = tx.before[id] ?? nil
            guard disk == before || disk == after else { throw ThreadError.message("未完成事务与外部修改冲突；已保留事务和原文。") }
        }
        for (id, data) in tx.after { try atomic(data, to: noteURL(id)) }
        try fm.removeItem(at: journal)
    }
    public func reload() -> Bool {
        let old = items
        var parsed: [WorkItem] = []; var errors: [String] = []; var seen = Set<String>()
        do {
            for file in try fm.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) where file.pathExtension == "md" {
                let id = file.deletingPathExtension().lastPathComponent
                do {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ThreadError.message("不读取符号链接笔记。") }
                    let data = try Data(contentsOf: file); let item = try MarkdownCodec.decode(data)
                    guard item.id == id, !seen.contains(id) else { throw ThreadError.message("文件名与编号不一致或编号重复。") }
                    seen.insert(id); parsed.append(item); snapshots[id] = data; missing.remove(id)
                } catch { errors.append("\(file.lastPathComponent)：\(error.localizedDescription)"); if let previous = item(id) { parsed.append(previous); missing.insert(id); seen.insert(id) } }
            }
            for previous in old where !seen.contains(previous.id) { parsed.append(previous); missing.insert(previous.id); errors.append("\(previous.id)：文件缺失，记录保留但不可覆盖。") }
            items = parsed
        } catch { errors.append(error.localizedDescription) }
        issues = errors + (overviewConflict ? ["总览存在外部修改，自动汇总已暂停。"] : [])
        return old != items
    }
    private func atomic(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: tmp) }
        try data.write(to: tmp, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: tmp); try handle.synchronize(); try handle.close()
        guard Darwin.rename(tmp.path, url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    private func commit(_ changed: [WorkItem]) throws {
        if fm.fileExists(atPath: journal.path) { try recover(); _ = reload(); throw ThreadError.message("已恢复上次中断的保存，请检查最新内容后重试本次操作。") }
        var before: [String: Data?] = [:]; var after: [String: Data] = [:]
        for var item in changed {
            guard !missing.contains(item.id) else { throw ThreadError.message("笔记文件缺失或损坏，请先修复原文件。") }
            let disk = try? Data(contentsOf: noteURL(item.id))
            guard disk == snapshots[item.id] else { throw ThreadError.message("文件已被外部修改，请刷新后重试；未覆盖外部内容。") }
            item.updatedAt = Date(); before[item.id] = .some(disk)
            let encoded = try MarkdownCodec.encode(item, preserving: disk)
            _ = try MarkdownCodec.decode(encoded)
            after[item.id] = encoded
        }
        try atomic(try JSONEncoder().encode(Transaction(before: before, after: after)), to: journal)
        try recover()
        for (id, data) in after { snapshots[id] = data; let item = try MarkdownCodec.decode(data); items.removeAll { $0.id == id }; items.append(item) }
        do { try refreshOverview() } catch { issues.append("笔记已保存，总览待同步：\(error.localizedDescription)") }
    }
    @discardableResult public func create(goal: String, source: Source) throws -> WorkItem {
        let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { throw ThreadError.message("请填写目标。") }
        guard !source.appBundleID.isEmpty else { throw ThreadError.message("请先选择关联应用。") }
        if source.kind == "webpage" { guard let raw = source.url, let u = URL(string: raw), ["https", "http", "file"].contains(u.scheme ?? "") else { throw ThreadError.message("请输入完整网页地址。") } }
        highWater += 1
        try atomic(try JSONEncoder().encode(highWater), to: state.appendingPathComponent("store.json"))
        let id = String(format: "%06d", highWater)
        guard !fm.fileExists(atPath: noteURL(id).path) else { throw ThreadError.message("编号冲突，创建已停止。") }
        let item = WorkItem(id: id, goal: goal, source: source, order: (active.first?.activeOrder ?? 0) - 1000)
        try commit([item]); return self.item(id)!
    }
    public func update(_ id: String, change: (inout WorkItem) -> Void) throws {
        guard var item = item(id) else { throw ThreadError.message("条项不存在。") }
        change(&item)
        item.goal = item.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.goal.isEmpty else { throw ThreadError.message("目标不能为空。") }
        try commit([item])
    }
    public func saveNote(_ id: String, text: String, base: String) throws {
        guard let current = item(id) else { throw ThreadError.message("条项已不存在。") }
        let diskData = try Data(contentsOf: noteURL(id)); let disk = try MarkdownCodec.decode(diskData)
        if disk.note != base && disk.note != text { try saveConflict(id, text: text); throw ThreadError.message("笔记同时在外部修改。你的草稿已保存在 .thread/conflicts，请合并后继续。") }
        if disk != current { _ = reload() }
        try update(id) { $0.note = text }
    }
    public func saveConflict(_ id: String, text: String) throws {
        let folder = state.appendingPathComponent("conflicts"); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent("\(id)-\(UUID().uuidString).md"), options: .atomic)
    }
    public func complete(_ id: String) throws { try update(id) { $0.status = "completed"; $0.completedAt = Date(); $0.completedOrder = (completed.first?.completedOrder ?? 0) - 1000 } }
    public func restore(_ id: String) throws { try update(id) { $0.status = "active"; $0.completedAt = nil } }
    public func move(_ id: String, before target: String) throws {
        guard let selected = item(id), let other = item(target), selected.status == other.status, id != target else { return }
        var rows = selected.status == "active" ? active : completed
        rows.removeAll { $0.id == id }
        guard let index = rows.firstIndex(where: { $0.id == target }) else { return }
        rows.insert(selected, at: index)
        for i in rows.indices { if selected.status == "active" { rows[i].activeOrder = Double(i) * 1000 } else { rows[i].completedOrder = Double(i) * 1000 } }
        try commit(rows)
    }
    public func nudge(_ id: String, delta: Int) throws {
        guard let item = item(id) else { return }; let rows = item.status == "active" ? active : completed
        guard let i = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(i + delta) else { return }
        if delta < 0 { try move(id, before: rows[i + delta].id) } else { try move(rows[i + delta].id, before: id) }
    }
    public func delete(_ id: String, trash: ((URL) throws -> Void)? = nil) throws {
        guard item(id) != nil else { return }
        if fm.fileExists(atPath: journal.path) { try recover(); _ = reload(); throw ThreadError.message("已恢复上次保存，请刷新后再删除。") }
        guard !missing.contains(id), (try? Data(contentsOf: noteURL(id))) == snapshots[id] else { throw ThreadError.message("原文件已变化，请刷新后再删除。") }
        if let trash { try trash(noteURL(id)) } else { try fm.trashItem(at: noteURL(id), resultingItemURL: nil) }
        items.removeAll { $0.id == id }; snapshots.removeValue(forKey: id); missing.remove(id)
        do { try refreshOverview() } catch { issues.append("删除已完成，总览待同步：\(error.localizedDescription)") }
    }
    public func refreshOverview(force: Bool = false, online: [String: String] = [:]) throws {
        let existing = try? Data(contentsOf: overviewURL)
        if !force && (overviewConflict || (overviewSnapshot != nil && existing != overviewSnapshot)) { overviewConflict = true; return }
        if force, let existing {
            let dir = state.appendingPathComponent("conflicts"); try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try existing.write(to: dir.appendingPathComponent("总览-\(UUID().uuidString).md"))
        }
        let text = Overview.markdown(active: active, completed: completed, online: online)
        let data = Data(text.utf8)
        if data != existing { try atomic(data, to: overviewURL) }
        try atomic(data, to: state.appendingPathComponent("overview-baseline.md"))
        overviewSnapshot = data; overviewConflict = false
    }
}
