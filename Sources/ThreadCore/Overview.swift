import Foundation
public enum Overview {
    public static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func cell(_ value: String) -> String { escape(value).replacingOccurrences(of: "|", with: "&#124;").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "[", with: "&#91;").replacingOccurrences(of: "]", with: "&#93;") }
    public static func markdown(active: [WorkItem], completed: [WorkItem], online: [String: String] = [:]) -> String {
        var out = "# 留绪 · Thread\n\n留住思路，随时继续。\n\n> 此文件由 Thread 自动维护。请在应用或编号笔记中修改目标与笔记。来源状态是最近一次检查的快照。\n"
        for (title, rows) in [("进行中", active), ("已完成", completed)] {
            out += "\n## \(title)\n\n| 编号 | 目标 | 当前打开网页/应用 | 笔记 |\n| --- | --- | --- | --- |\n"
            for item in rows {
                var source = cell(item.source.appName + " · " + item.source.title)
                if let raw = item.source.url {
                    let url = raw.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "|", with: "%7C")
                    source = "[" + source + "](" + url + ")"
                }
                let status = cell(online[item.id] ?? "状态待检查")
                out += "| \(item.id) | \(item.starred ? "★ " : "")\(cell(item.goal)) | \(source)（\(status)） | [打开笔记](笔记/\(item.id).md) |\n"
            }
        }
        return out
    }
    public static func html(markdown: String) -> String {
        var body = ""; var inTable = false; var completed = false
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("| ---") { continue }
            if line.hasPrefix("|") && line.hasSuffix("|") {
                if !inTable { body += "<table class='\(completed ? "completed" : "")'>"; inTable = true }
                let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { String($0).trimmingCharacters(in: .whitespaces) }
                body += "<tr>" + cells.enumerated().map { index, cell in
                    var display = cell
                    if index == 2, cell.hasPrefix("["), let labelEnd = cell.range(of: "]("), let urlEnd = cell.range(of: ")", options: .backwards) {
                        display = String(cell[cell.index(after: cell.startIndex)..<labelEnd.lowerBound]) + String(cell[urlEnd.upperBound...])
                    }
                    var text = escape(display)
                    // Decode only the entities produced by our Markdown writer. Never accept raw HTML.
                    for (encoded, entity) in [("&amp;#124;", "&#124;"), ("&amp;#91;", "&#91;"), ("&amp;#93;", "&#93;"), ("&amp;lt;", "&lt;"), ("&amp;gt;", "&gt;"), ("&amp;quot;", "&quot;"), ("&amp;amp;", "&amp;")] { text = text.replacingOccurrences(of: encoded, with: entity) }
                    if index == 3, let range = cell.range(of: #"^\[打开笔记\]\(笔记/([0-9]{6,})\.md\)$"#, options: .regularExpression) {
                        let part = String(cell[range]); let id = part.components(separatedBy: "/").last!.replacingOccurrences(of: ".md)", with: "")
                        text = "<a href='thread-note:\(id)'>打开笔记</a>"
                    }
                    if index == 0, cell.range(of: "^[0-9]{6,}$", options: .regularExpression) != nil { text = "<a href='thread-detail:\(cell)'>\(cell)</a>" }
                    if index == 2, let id = cells.first, id.range(of: "^[0-9]{6,}$", options: .regularExpression) != nil { text = "<a href='thread-source:\(id)'>\(text)</a>" }
                    return "<td>\(text)</td>"
                }.joined() + "</tr>"
            } else {
                if inTable { body += "</table>"; inTable = false }
                if line.hasPrefix("## ") { completed = line.contains("已完成"); body += "<h2>\(escape(String(line.dropFirst(3))))</h2>" }
                else if line.hasPrefix("# ") { body += "<h1>\(escape(String(line.dropFirst(2))))</h1>" }
                else if !line.isEmpty { body += "<p>\(escape(line.hasPrefix("> ") ? String(line.dropFirst(2)) : line))</p>" }
            }
        }
        if inTable { body += "</table>" }
        return """
        <!doctype html><html lang="zh"><head><meta charset="utf-8"><meta name="color-scheme" content="light dark"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><style>
        :root{color-scheme:light dark}body{font:14px -apple-system,BlinkMacSystemFont,sans-serif;margin:32px;color:CanvasText;background:Canvas}h1{font-size:26px;letter-spacing:-.6px}h2{font-size:17px;margin-top:32px}p{color:#686870;line-height:1.6}table{width:100%;border-collapse:collapse;table-layout:fixed}td{padding:14px 12px;border-bottom:1px solid color-mix(in srgb,CanvasText 12%,transparent);vertical-align:top;overflow-wrap:anywhere}tr:first-child{font-weight:600;background:color-mix(in srgb,CanvasText 5%,transparent)}td:first-child{width:70px}td:last-child{width:80px}.completed{color:#686870}a{color:LinkText;text-decoration:none}a:hover{text-decoration:underline}
        @media(prefers-color-scheme:dark){p,.completed{color:#aaaab3}}
        </style></head><body>\(body)</body></html>
        """
    }
}
