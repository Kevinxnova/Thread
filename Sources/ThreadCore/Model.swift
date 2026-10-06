import Foundation

public struct Source: Codable, Equatable {
    public var kind: String
    public var appBundleID: String
    public var appName: String
    public var title: String
    public var url: String?
    public init(kind: String = "app", appBundleID: String, appName: String, title: String, url: String? = nil) {
        self.kind = kind; self.appBundleID = appBundleID; self.appName = appName; self.title = title; self.url = url
    }
}
public struct WorkItem: Codable, Equatable, Identifiable {
    public var schemaVersion = 1
    public var id: String
    public var goal: String
    public var status = "active"
    public var starred = false
    public var activeOrder: Double
    public var completedOrder: Double = 0
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var source: Source
    public var pinRequested = true
    public var noteFrame: String?
    public var markerFrame: String?
    public var markerOffset: String?
    public var note = ""
    public init(id: String, goal: String, source: Source, order: Double, now: Date = Date()) {
        self.id = id; self.goal = goal; self.source = source; self.activeOrder = order; self.createdAt = now; self.updatedAt = now
    }
}
public enum ThreadError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
public enum MarkdownCodec {
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e }
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    public static func encode(_ item: WorkItem, preserving original: Data? = nil) throws -> Data {
        var meta = item; meta.note = ""
        let encoded = try encoder().encode(meta)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        if let original, let old = try? parts(original), let extras = try? JSONSerialization.jsonObject(with: old.0) as? [String: Any] {
            for (key, value) in extras where object[key] == nil && !["completedAt", "noteFrame", "markerFrame", "markerOffset"].contains(key) { object[key] = value }
        }
        object.removeValue(forKey: "note")
        let body = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return Data(("---\n" + String(decoding: body, as: UTF8.self) + "\n---\n" + item.note).utf8)
    }
    static func parts(_ data: Data) throws -> (Data, String) {
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) else { throw ThreadError.message("笔记格式损坏：缺少元数据边界，原文已保留。") }
        return (Data(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound].utf8), String(text[end.upperBound...]))
    }
    public static func decode(_ data: Data) throws -> WorkItem {
        let (meta, body) = try parts(data)
        guard var object = try JSONSerialization.jsonObject(with: meta) as? [String: Any] else { throw ThreadError.message("元数据必须是 JSON 对象，原文已保留。") }
        object["note"] = body
        let item = try decoder().decode(WorkItem.self, from: JSONSerialization.data(withJSONObject: object))
        guard item.schemaVersion == 1, !item.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.id.range(of: "^[0-9]{6,}$", options: .regularExpression) != nil, ["active", "completed"].contains(item.status), item.activeOrder.isFinite, item.completedOrder.isFinite, ["app", "webpage"].contains(item.source.kind), !item.source.appBundleID.isEmpty else { throw ThreadError.message("无效的笔记元数据，原文件已保留。") }
        if item.status == "completed" && item.completedAt == nil { throw ThreadError.message("已完成条目缺少完成时间。") }
        if item.source.kind == "webpage" { guard let raw = item.source.url, let u = URL(string: raw), ["http", "https", "file"].contains(u.scheme?.lowercased() ?? "") else { throw ThreadError.message("网页条目缺少有效 URL。") } }
        return item
    }
}
