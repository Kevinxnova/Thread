import Foundation

/// Read-only presentation of the file on disk. Never regenerates or repairs user data.
public struct OverviewDocument {
    public enum Filter: String, CaseIterable { case all = "全部记录", active = "进行中", starred = "星标", completed = "已完成" }
    public struct Row: Identifiable, Equatable {
        public let id: String
        public let goal: String
        public let source: String
        public let sourceURL: String?
        public let completed: Bool
        public let starred: Bool
    }
    public let rows: [Row]
    public init(markdown: String) throws {
        var parsed: [Row] = [], ids = Set<String>(), sections = Set<String>()
        var status: Bool?, header = false, separator = false
        let heading = "| 编号 | 目标 | 当前打开网页/应用 | 笔记 |"
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line == "## 进行中" || line == "## 已完成" {
                if status != nil && (!header || !separator) { throw Self.unsupported }
                guard sections.insert(line).inserted else { throw Self.unsupported }
                status = line == "## 已完成"; header = false; separator = false; continue
            }
            if status == nil {
                guard line == "# 留绪 · Thread" || line == "留住思路，随时继续。" || line == "> 此文件由 Thread 自动维护。请在应用或编号笔记中修改目标与笔记。来源状态是最近一次检查的快照。" else { throw Self.unsupported }
                continue
            }
            if !header { guard line == heading else { throw Self.unsupported }; header = true; continue }
            if !separator { guard line == "| --- | --- | --- | --- |" else { throw Self.unsupported }; separator = true; continue }
            guard line.hasPrefix("|"), line.hasSuffix("|") else { throw Self.unsupported }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { String($0).trimmingCharacters(in: .whitespaces) }
            guard cells.count == 4, cells[0].range(of: "^[0-9]{6,}$", options: .regularExpression) != nil, ids.insert(cells[0]).inserted,
                  cells[3] == "[打开笔记](笔记/\(cells[0]).md)" else { throw Self.unsupported }
            let starred = cells[1].hasPrefix("★ ")
            let goal = Self.decode(starred ? String(cells[1].dropFirst(2)) : cells[1])
            guard !goal.isEmpty else { throw Self.unsupported }
            var source = cells[2]
            var sourceURL: String?
            if source.hasPrefix("["), let end = source.range(of: "]("), let close = source.range(of: ")", options: .backwards), end.upperBound <= close.lowerBound {
                sourceURL = String(source[end.upperBound..<close.lowerBound])
                source = String(source[source.index(after: source.startIndex)..<end.lowerBound]) + String(source[close.upperBound...])
            }
            parsed.append(Row(id: cells[0], goal: goal, source: Self.decode(source), sourceURL: sourceURL, completed: status == true, starred: starred))
        }
        guard sections.count == 2, header, separator else { throw Self.unsupported }
        rows = parsed
    }
    private static var unsupported: ThreadError { .message("此文件含有自定义或无法识别的内容，已切换为文档阅读，原文保留。") }
    private static func decode(_ value: String) -> String {
        // Decode a single layer only; an escaped literal entity must remain literal.
        var result = value
        for (from, to) in [("&#124;", "|"), ("&#91;", "["), ("&#93;", "]"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&amp;", "&")] { result = result.replacingOccurrences(of: from, with: to) }
        return result
    }
    public func filtered(_ filter: Filter, query: String, notes: [String: String] = [:]) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            let includes = filter == .all || (filter == .active && !row.completed) || (filter == .completed && row.completed) || (filter == .starred && row.starred)
            return includes && (query.isEmpty || "\(row.id) \(row.goal) \(row.source) \(notes[row.id] ?? "")".localizedCaseInsensitiveContains(query))
        }
    }
    public static func readNote(id: String, root: URL) throws -> WorkItem {
        guard id.range(of: "^[0-9]{6,}$", options: .regularExpression) != nil else { throw unsupported }
        let directory = root.appendingPathComponent("笔记", isDirectory: true)
        let file = directory.appendingPathComponent(id + ".md")
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              directory.resolvingSymlinksInPath().standardizedFileURL == root.resolvingSymlinksInPath().appendingPathComponent("笔记", isDirectory: true).standardizedFileURL else { throw ThreadError.message("笔记链接不在编号笔记目录内。") }
        let item = try MarkdownCodec.decode(Data(contentsOf: file))
        guard item.id == id else { throw ThreadError.message("笔记文件名与编号不一致。") }
        return item
    }
}
