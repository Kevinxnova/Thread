import AppKit
import ApplicationServices
import ThreadCore

struct WindowRecord: Identifiable {
    var id: String
    var pid: pid_t
    var bundleID: String
    var appName: String
    var title: String
    var rect: CGRect?
    var number: Int?
    var ax: AXUIElement?
    var minimized: Bool
    func matches(_ other: WindowRecord) -> Bool {
        guard pid == other.pid, bundleID == other.bundleID else { return false }
        if let a = ax, let b = other.ax { return CFEqual(a, b) }
        if let a = number, let b = other.number { return a == b }
        return ax == nil && other.ax == nil && rect == nil && other.rect == nil
    }
    var source: Source { Source(appBundleID: bundleID, appName: appName, title: title) }
}
final class WindowCatalog {
    private static let scanLock = NSLock()
    private static var previous: [WindowRecord] = []
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }; return result
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func scan() -> ([WindowRecord], [String]) {
        scanLock.lock(); defer { scanLock.unlock() }
        let cg = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var records: [WindowRecord] = []; var warnings: [String] = []
        let trusted = AXIsProcessTrusted()
        if !trusted { warnings.append("需要辅助功能权限以完整读取窗口；当前显示可获取的部分信息。") }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            guard let bid = app.bundleIdentifier else { continue }
            let owner = cg.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier) && ($0[kCGWindowLayer as String] as? Int) == 0 }
            var found: [WindowRecord] = []
            if trusted {
                let ax = AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(ax, 0.2)
                if let windows = value(ax, kAXWindowsAttribute) as? [AXUIElement] {
                    for window in windows {
                        let title = value(window, kAXTitleAttribute) as? String ?? "未命名窗口"
                        let rect = frame(window)
                        // App launch can briefly expose menu/helper surfaces before its document window.
                        guard let rect, rect.width >= 80, rect.height >= 60 else { continue }
                        let number = matchingNumber(rect: rect, title: title, rows: owner)
                        found.append(WindowRecord(id: "\(app.processIdentifier):\(number.map(String.init) ?? "ax-" + UUID().uuidString)", pid: app.processIdentifier, bundleID: bid, appName: app.localizedName ?? bid, title: title.isEmpty ? "未命名窗口" : title, rect: rect, number: number, ax: window, minimized: (value(window, kAXMinimizedAttribute) as? Bool) ?? false))
                    }
                } else { warnings.append("\(app.localizedName ?? bid)：暂时无法读取完整窗口。") }
            }
            if found.isEmpty {
                for (index, info) in owner.enumerated() {
                    let rect = (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
                    guard let rect, rect.width >= 80, rect.height >= 60 else { continue }
                    let number = info[kCGWindowNumber as String] as? Int
                    found.append(WindowRecord(id: "\(app.processIdentifier):\(number ?? index)", pid: app.processIdentifier, bundleID: bid, appName: app.localizedName ?? bid, title: info[kCGWindowName as String] as? String ?? "未命名窗口", rect: rect, number: number, ax: nil, minimized: false))
                }
            }
            if found.isEmpty { found.append(WindowRecord(id: "\(app.processIdentifier):app", pid: app.processIdentifier, bundleID: bid, appName: app.localizedName ?? bid, title: "无窗口应用", rect: nil, number: nil, ax: nil, minimized: false)) }
            records += found
        }
        // AX array order is not window identity. Preserve identity through move/minimize/reorder.
        for index in records.indices {
            if let old = previous.first(where: { $0.matches(records[index]) }) { records[index].id = old.id }
        }
        previous = records
        return (records.sorted { ($0.appName, $0.title, $0.id) < ($1.appName, $1.title, $1.id) }, warnings)
    }
    static func matchingNumber(rect: CGRect, title: String, rows: [[String: Any]]) -> Int? {
        let candidates = rows.filter { info in
            guard let raw = info[kCGWindowBounds as String] as? NSDictionary, let frame = CGRect(dictionaryRepresentation: raw) else { return false }
            return abs(frame.minX-rect.minX) < 2 && abs(frame.minY-rect.minY) < 2 && abs(frame.width-rect.width) < 2 && abs(frame.height-rect.height) < 2
        }
        if candidates.count == 1 { return candidates[0][kCGWindowNumber as String] as? Int }
        let named = candidates.filter { $0[kCGWindowName as String] as? String == title }
        return named.count == 1 ? named[0][kCGWindowNumber as String] as? Int : nil
    }
    static func raise(_ record: WindowRecord) {
        if let ax = record.ax { AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse); AXUIElementPerformAction(ax, kAXRaiseAction as CFString) }
        NSRunningApplication(processIdentifier: record.pid)?.unhide()
        NSRunningApplication(processIdentifier: record.pid)?.activate(options: [])
        if let ax = record.ax { AXUIElementPerformAction(ax, kAXRaiseAction as CFString); AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue) }
    }
    static func cocoaRect(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - rect.maxY, width: rect.width, height: rect.height) }
}
enum BrowserBridge {
    private static let scriptLock = NSLock()
    static let supported: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]
    static func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\"" }
    static func run(_ text: String) throws -> NSAppleEventDescriptor {
        scriptLock.lock(); defer { scriptLock.unlock() }
        guard let script = NSAppleScript(source: text) else { throw ThreadError.message("浏览器脚本无法创建。") }
        var error: NSDictionary?; let result = script.executeAndReturnError(&error)
        if let error { throw ThreadError.message("无法读取浏览器。请允许自动化权限，或手动填写 URL。\n\(error[NSAppleScript.errorMessage] ?? error)") }; return result
    }
    static func accessibilityURL(_ window: AXUIElement) -> String? {
        func url(_ element: AXUIElement, attribute: String) -> String? {
            guard let value = WindowCatalog.value(element, attribute) else { return nil }
            let raw: String?
            if let u = value as? URL { raw = u.absoluteString } else { raw = value as? String }
            guard let raw, let u = URL(string: raw), ["http", "https", "file"].contains(u.scheme ?? "") else { return nil }; return raw
        }
        if let raw = url(window, attribute: kAXDocumentAttribute) { return raw }
        var remaining = 300
        func visit(_ element: AXUIElement, depth: Int) -> String? {
            guard remaining > 0, depth < 9 else { return nil }; remaining -= 1
            if WindowCatalog.value(element, kAXRoleAttribute) as? String == "AXWebArea" { return url(element, attribute: "AXURL") }
            guard let children = WindowCatalog.value(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
            for child in children { if let result = visit(child, depth: depth+1) { return result } }
            return nil
        }
        return visit(window, depth: 0)
    }
    static func source(for record: WindowRecord) throws -> Source {
        guard supported.contains(record.bundleID) else { return record.source }
        if let ax = record.ax, let url = accessibilityURL(ax) { return Source(kind: "webpage", appBundleID: record.bundleID, appName: record.appName, title: record.title, url: url) }
        let tab = record.bundleID == "com.apple.Safari" ? "current tab" : "active tab"
        // Browser script IDs are not CGWindowIDs. Match the selected window by bounds, requiring a unique match.
        guard let bounds = record.rect else { throw ThreadError.message("无法可靠识别所选浏览器窗口，请手动填写当前页面 URL。") }
        let x = Int(bounds.minX), y = Int(bounds.minY), right = Int(bounds.maxX), bottom = Int(bounds.maxY)
        let result = try run("""
        with timeout of 3 seconds
        tell application id \(quoted(record.bundleID))
          set matches to {}
          repeat with candidate in windows
            set b to bounds of candidate
            if (item 1 of b >= \(x-3)) and (item 1 of b <= \(x+3)) and (item 2 of b >= \(y-3)) and (item 2 of b <= \(y+3)) and (item 3 of b >= \(right-3)) and (item 3 of b <= \(right+3)) and (item 4 of b >= \(bottom-3)) and (item 4 of b <= \(bottom+3)) then
              set end of matches to candidate
            end if
          end repeat
          if (count of matches) > 1 then
            set namedMatches to {}
            repeat with candidate in matches
              if name of candidate is \(quoted(record.title)) then set end of namedMatches to candidate
            end repeat
            set matches to namedMatches
          end if
          if (count of matches) is not 1 then error "Cannot uniquely match selected browser window"
          set w to item 1 of matches
          return {URL of \(tab) of w, \(record.bundleID == "com.apple.Safari" ? "name" : "title") of \(tab) of w}
        end tell
        end timeout
        """)
        guard let url = result.atIndex(1)?.stringValue, !url.isEmpty else { throw ThreadError.message("页面没有可保存的地址。请填写 URL 或按应用关联。") }
        guard let parsed = URL(string: url), ["http", "https", "file"].contains(parsed.scheme?.lowercased() ?? "") else {
            throw ThreadError.message("这是浏览器内部页面，暂不能按网页关联。可留空地址，按应用添加标记。")
        }
        return Source(kind: "webpage", appBundleID: record.bundleID, appName: record.appName, title: result.atIndex(2)?.stringValue ?? record.title, url: url)
    }
    struct Tab: Identifiable {
        let windowID: Int; let index: Int; let title: String; let rect: CGRect
        var id: String { "\(windowID):\(index)" }
        var label: String { "\(title) · 窗口 \(windowID) · 标签 \(index)" }
    }
    static func tabs(for source: Source) throws -> [Tab] {
        guard let url = source.url, supported.contains(source.appBundleID), !NSRunningApplication.runningApplications(withBundleIdentifier: source.appBundleID).isEmpty else { return [] }
        let name = source.appBundleID == "com.apple.Safari" ? "name" : "title"
        let result = try run("""
        with timeout of 3 seconds
        tell application id \(quoted(source.appBundleID))
          set matches to {}
          repeat with w in windows
            set n to 0
            repeat with t in tabs of w
              set n to n + 1
              if URL of t is \(quoted(url)) then set end of matches to {id of w, n, \(name) of t, bounds of w}
            end repeat
          end repeat
          return matches
        end tell
        end timeout
        """)
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { position in
            guard let entry = result.atIndex(position), let b = entry.atIndex(4), b.numberOfItems == 4 else { return nil }
            let x = Int(b.atIndex(1)!.int32Value), y = Int(b.atIndex(2)!.int32Value)
            return Tab(windowID: Int(entry.atIndex(1)!.int32Value), index: Int(entry.atIndex(2)!.int32Value), title: entry.atIndex(3)?.stringValue ?? source.title, rect: CGRect(x: x, y: y, width: Int(b.atIndex(3)!.int32Value)-x, height: Int(b.atIndex(4)!.int32Value)-y))
        }
    }
    static func focus(_ source: Source, tab: Tab) throws {
        guard let url = source.url else { throw ThreadError.message("关联页面没有地址。") }
        let action = source.appBundleID == "com.apple.Safari" ? "set current tab of w to t" : "set active tab index of w to \(tab.index)"
        let result = try run("""
        with timeout of 3 seconds
        tell application id \(quoted(source.appBundleID))
          set w to window id \(tab.windowID)
          set t to tab \(tab.index) of w
          if URL of t is not \(quoted(url)) then return false
          \(action)
          set index of w to 1
          activate
          return true
        end tell
        end timeout
        """)
        guard result.booleanValue else { throw ThreadError.message("标签页的位置或地址已变化，请再次点击回到来源。未打开重复页面。") }
    }
}
