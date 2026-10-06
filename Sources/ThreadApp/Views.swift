import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import ThreadCore


struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {}
    final class Handle: NSView {
        private var dragStart: NSPoint?
        private var frameStart: NSPoint?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            dragStart = window?.convertPoint(toScreen: event.locationInWindow); frameStart = window?.frame.origin
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let start = dragStart, let origin = frameStart else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(x: origin.x + point.x-start.x, y: origin.y + point.y-start.y))
        }
        override func mouseUp(with event: NSEvent) { dragStart = nil; frameStart = nil }
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

struct IconAction: View {
    var name: String; var label: String; var action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: name).font(.system(size: 19, weight: .regular)).frame(width: 42, height: 40).contentShape(Rectangle()) }.buttonStyle(.plain).help(label).accessibilityLabel(label) }
}
struct ToolbarView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 4) {
            IconAction(name: "tag", label: "添加标记") { model.coordinator.beginSelection() }
            Divider().frame(height: 24)
            IconAction(name: "list.bullet", label: "工作条项") { model.coordinator.toggleList() }
            Divider().frame(height: 24)
            IconAction(name: "tablecells", label: "完整总览") { model.coordinator.showOverview() }
        }.padding(.horizontal, 16).padding(.vertical, 8).background((reduceTransparency || CommandLine.arguments.contains("--test-accessibility")) ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial), in: Capsule()).overlay(Capsule().strokeBorder(.primary.opacity(0.07))).overlay(alignment: .bottom) { WindowDragHandle().frame(height: 8).padding(.horizontal, 18) }
    }
}
struct TaskRow: View {
    @ObservedObject var model: AppModel
    let item: WorkItem
    var ordering = true
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 3) {
            Button { if item.status == "completed" { model.restore(item.id) } else { model.complete(item.id) } } label: {
                Image(systemName: item.status == "completed" ? "checkmark.circle.fill" : "circle").font(.system(size: 18)).frame(width: 24, height: 26)
            }.buttonStyle(.plain).foregroundStyle(.secondary).help(item.status == "completed" ? "撤回完成" : "完成")
                .accessibilityLabel("\(item.status == "completed" ? "撤回完成" : "完成") \(item.id)")
            if ordering && item.status == "active" {
                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 24, height: 22).contentShape(Rectangle()).help("拖动排序").accessibilityLabel("拖动排序 \(item.id)").onDrag { NSItemProvider(object: item.id as NSString) }
            }
            }
            VStack(alignment: .leading, spacing: 5) {
                Button { if item.status == "active" { model.coordinator.activateTag(item.id, showNote: false) } else { model.focus(item) } } label: { Text(item.goal).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).help(item.goal)
                Button { model.focus(item) } label: { Text("\(item.source.appName) · \(item.id)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }.buttonStyle(.plain).help("回到来源")
                Button { model.coordinator.openNote(item.id) } label: { Text(item.note.isEmpty ? "记下下一步…" : item.note.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).accessibilityLabel("打开笔记 \(item.id)")
            }
            VStack(spacing: 6) {
                if item.status == "active" {
                    Button { model.togglePin(item.id) } label: { Image(systemName: item.pinRequested ? "pin.fill" : "pin.slash").frame(width: 24, height: 22) }.buttonStyle(.plain).help(model.pinStatus[item.id] ?? (item.pinRequested ? "点击标签继续" : "未置顶")).accessibilityLabel("\(item.pinRequested ? "取消置顶" : "置顶窗口") \(item.id)")
                }
                if item.status == "completed" { Button("撤回") { model.restore(item.id) }.font(.caption).buttonStyle(.borderless) }
                else { Button { model.toggleStar(item.id) } label: { Image(systemName: item.starred ? "star.fill" : "star").foregroundStyle(item.starred ? Color.orange : Color.secondary).frame(width: 24, height: 24) }.buttonStyle(.plain).accessibilityLabel("星标 \(item.id)") }
                Menu {
                    if item.status == "active" { Button(item.pinRequested ? "取消置顶" : "置顶窗口") { model.togglePin(item.id) } }
                    Button("编辑目标与关联") { model.coordinator.showDetail(item.id) }
                    if ordering { Button("上移") { model.perform { try model.store.nudge(item.id, delta: -1) } }; Button("下移") { model.perform { try model.store.nudge(item.id, delta: 1) } } }
                    Divider(); Button("删除…", role: .destructive) { model.delete(item.id) }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 20) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多操作 \(item.id)")
            }
        }.padding(.vertical, 12).foregroundStyle(item.status == "completed" ? .secondary : .primary)
    }
}
struct WorkListView: View {
    @ObservedObject var model: AppModel
    @State private var mode = 0
    @State private var query = ""
    @State private var starred = false
    @State private var showWarnings = false
    var ordering: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !starred }
    var filtered: [WorkItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.active.filter { (!starred || $0.starred) && (term.isEmpty || "\($0.id) \($0.goal) \($0.note) \($0.source.appName) \($0.source.title)".localizedCaseInsensitiveContains(term)) }
    }
    var groups: [String] { Array(Set(model.windows.map(\.bundleID))).sorted { a, b in (model.windows.first { $0.bundleID == a }?.appName ?? a) < (model.windows.first { $0.bundleID == b }?.appName ?? b) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("接着做").font(.title2.weight(.semibold)); Text("\(model.active.count)").font(.callout).foregroundStyle(.secondary); Spacer(); Button { model.coordinator.beginSelection() } label: { Image(systemName: "plus").frame(width: 26, height: 26) }.buttonStyle(.plain).help("添加标记").accessibilityLabel("添加标记") }
            Picker("视图", selection: $mode) { Text("已标记").tag(0); Text("全部打开").tag(1) }.labelsHidden().pickerStyle(.segmented).onChange(of: mode) { if $0 == 1 { model.scan() } }
            if !model.issues.isEmpty { ScrollView { Text(model.issues.joined(separator: "\n")).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 62) }
            if mode == 0 {
                HStack { TextField("搜索目标、来源、笔记", text: $query).textFieldStyle(.roundedBorder); Toggle(isOn: $starred) { Image(systemName: "star.fill") }.toggleStyle(.button).help("仅看星标").accessibilityLabel("仅看星标") }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if filtered.isEmpty { Text(model.active.isEmpty ? "添加一个标记，把下一步留在这里。" : "没有匹配的条项").font(.callout).foregroundStyle(.secondary).padding(.vertical, 35).frame(maxWidth: .infinity) }
                        ForEach(filtered) { item in
                            if ordering {
                                TaskRow(model: model, item: item).onDrag { NSItemProvider(object: item.id as NSString) }.onDrop(of: [.plainText], isTargeted: nil) { providers in
                                    guard let p = providers.first else { return false }
                                    _ = p.loadObject(ofClass: NSString.self) { object, _ in if let id = object as? String { DispatchQueue.main.async { model.perform { try model.store.move(id, before: item.id) } } } }; return true
                                }
                            } else { TaskRow(model: model, item: item, ordering: false) }
                            Divider()
                        }
                        if !model.recent.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                            Text("最近完成 · \(model.recent.count)").font(.caption).foregroundStyle(.secondary).padding(.top, 22).padding(.bottom, 4)
                            ForEach(model.recent) { TaskRow(model: model, item: $0, ordering: false); Divider() }
                            }.id("recent-completed-section")
                        }
                    }
                }
            } else {
                if !model.trusted { Button("允许辅助功能，读取完整窗口") { model.requestAccessibility() } }
                if !model.catalogWarnings.isEmpty { DisclosureGroup("\(model.catalogWarnings.count) 条窗口读取提示", isExpanded: $showWarnings) { Text(model.catalogWarnings.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary) } }
                ScrollView { LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.self) { bundleID in
                        let windows = model.windows.filter { $0.bundleID == bundleID }
                        HStack(spacing: 8) {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20) }
                            Text(windows.first?.appName ?? bundleID).font(.caption.weight(.semibold)); Spacer(); Text("\(windows.count)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 16).padding(.bottom, 6)
                        ForEach(windows) { window in
                            HStack {
                                Button { WindowCatalog.raise(window) } label: { VStack(alignment: .leading, spacing: 3) { Text(window.title.isEmpty ? "未命名窗口" : window.title).font(.callout).lineLimit(2); Text(window.minimized ? "已最小化" : "已打开").font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).help("回到窗口").accessibilityLabel("回到窗口 " + window.title)
                                Button { model.select(window) } label: { Image(systemName: "tag").frame(width: 28, height: 28) }.buttonStyle(.plain).help("添加目标").accessibilityLabel("添加目标 " + window.appName + " " + window.title)
                            }.padding(.vertical, 10)
                            Divider()
                        }
                    }
                    if model.windows.isEmpty { Text(model.scanning ? "正在读取窗口…" : "未找到可读取的窗口").foregroundStyle(.secondary).padding(.vertical, 30) }
                } }
                HStack { if model.scanning { ProgressView().controlSize(.small) }; Spacer(); Button("刷新窗口") { model.scan() }.buttonStyle(.borderless) }
            }
            Divider()
            HStack { Text("留住思路，随时继续。").font(.caption2).foregroundStyle(.secondary); Spacer(); Button("完整总览") { model.coordinator.showOverview() }.buttonStyle(.borderless) }
        }.padding(16).frame(minWidth: 360, minHeight: 460).background(Color(nsColor: .windowBackgroundColor))
    }
}
struct CreateView: View {
    @ObservedObject var model: AppModel
    var record: WindowRecord?
    var original: Source
    var warning: String?
    var done: () -> Void
    @State private var goal = ""
    @State private var rawURL = ""
    @State private var saving = false
    @FocusState private var goalFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("为这件事留个目标").font(.title2.bold())
            Text("\(original.appName) · \(original.title)").foregroundStyle(.secondary).lineLimit(2)
            TextField("下一步想做什么？", text: $goal).textFieldStyle(.roundedBorder).focused($goalFocused).onSubmit(create)
            if let warning { Text(warning).font(.caption).foregroundStyle(.orange).lineLimit(4) }
            TextField("网页地址（应用任务可留空）", text: $rawURL).textFieldStyle(.roundedBorder)
            Text("创建目标后显示来源、开启置顶镜像并打开笔记；可随时取消置顶，保留任务。").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("取消", action: done).keyboardShortcut(.cancelAction); Button(saving ? "正在保存…" : "创建标记", action: create).keyboardShortcut(.defaultAction).disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving) }
        }.padding(24).frame(width: 440).onAppear { rawURL = original.url ?? ""; goalFocused = true }
    }
    private func create() {
        guard !saving, !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saving = true; var source = original
        source.url = rawURL.isEmpty ? nil : rawURL; source.kind = rawURL.isEmpty ? "app" : "webpage"
        model.create(goal: goal, source: source, record: record) { success in saving = false; if success { done() } }
    }
}
struct DetailView: View {
    @ObservedObject var model: AppModel
    let id: String
    @State private var goal = ""
    @State private var url = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let item = model.store.item(id) {
                Text("条项 \(id)").font(.title2.bold())
                TextField("目标", text: $goal).textFieldStyle(.roundedBorder)
                HStack { Text(item.source.appName).foregroundStyle(.secondary); Spacer(); Button("重新关联到窗口…") { model.coordinator.beginSelection(relinkID: id) } }
                TextField("关联网页地址（留空按应用关联）", text: $url).textFieldStyle(.roundedBorder)
                Button("保存目标与关联") { model.perform { try model.store.update(id) { $0.goal = goal; $0.source.url = url.isEmpty ? nil : url; $0.source.kind = url.isEmpty ? "app" : "webpage" } } }
                Text(item.pinRequested ? (model.pinStatus[id] ?? "点击标签显示来源并恢复镜像置顶") : "未置顶 · 任务与笔记仍保留").font(.caption).foregroundStyle(.secondary)
                if item.status == "active" { Button(item.pinRequested ? "取消置顶" : "置顶窗口") { model.togglePin(id) } }
                HStack { Button("打开笔记") { model.coordinator.openNote(id) }; Button("回到来源") { model.focus(item) }; Button(item.starred ? "取消星标" : "星标") { model.toggleStar(id) } }
                HStack { Button("上移") { model.perform { try model.store.nudge(id, delta: -1) } }; Button("下移") { model.perform { try model.store.nudge(id, delta: 1) } }; Spacer(); if item.status == "active" { Button("完成") { model.complete(id) } } else { Button("撤回完成") { model.restore(id) } }; Button("删除…", role: .destructive) { model.delete(id) } }
            } else { Text("条项已删除") }
        }.padding(24).frame(width: 480).onAppear { if let item = model.store.item(id) { goal = item.goal; url = item.source.url ?? "" } }.onChange(of: model.store.item(id)?.source) { source in url = source?.url ?? "" }
    }
}
struct NativeTextEditor: NSViewRepresentable {
    @ObservedObject var session: NoteSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView(); let text = scroll.documentView as! NSTextView
        text.setAccessibilityLabel("笔记正文 " + session.id); text.isRichText = false; text.font = .systemFont(ofSize: 14); text.textContainerInset = NSSize(width: 18, height: 18); text.allowsUndo = true; text.isAutomaticQuoteSubstitutionEnabled = false; text.delegate = context.coordinator; text.string = session.text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let text = scroll.documentView as! NSTextView
        if text.string != session.text && !text.hasMarkedText() { let selection = text.selectedRange(); text.string = session.text; text.setSelectedRange(NSRange(location: min(selection.location, text.string.utf16.count), length: 0)) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        let session: NoteSession
        init(session: NoteSession) { self.session = session }
        func textDidChange(_ notification: Notification) { if let text = notification.object as? NSTextView, !text.hasMarkedText() { session.changed(text.string) } }
    }
}
struct NoteView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var session: NoteSession
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(model.store.item(session.id)?.goal ?? "笔记").font(.headline).lineLimit(2).overlay(WindowDragHandle()); Spacer(); Button { if session.flush(), let item = model.store.item(session.id) { model.focus(item) } } label: { Image(systemName: "arrow.up.forward.app") }.help("回到来源").accessibilityLabel("回到来源") }.padding(16)
            Divider(); NativeTextEditor(session: session); Divider()
            HStack { Text(session.status).font(.caption).foregroundStyle(session.status.hasPrefix("未保存") ? .orange : .secondary).lineLimit(3); Spacer(); Button("详情") { model.coordinator.showDetail(session.id) }; if model.store.item(session.id)?.status == "active" { Button("完成") { model.complete(session.id) } } else { Button("撤回") { model.restore(session.id) } } }.padding(12)
        }.frame(minWidth: 320, minHeight: 240)
    }
}
struct OverviewWeb: NSViewRepresentable {
    @ObservedObject var model: AppModel
    var revision: Int
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = context.coordinator; return web
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        let html: String
        do { html = Overview.html(markdown: try String(contentsOf: model.store.overviewURL, encoding: .utf8)).replacingOccurrences(of: "<a href='thread-[^']+'>", with: "<span>", options: .regularExpression).replacingOccurrences(of: "</a>", with: "</span>") }
        catch { html = "<p>无法读取总览：\(Overview.escape(error.localizedDescription))</p>" }
        if context.coordinator.last != html { context.coordinator.last = html; view.loadHTMLString(html, baseURL: nil) }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: AppModel; var last = ""
        init(model: AppModel) { self.model = model }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = action.request.url else { decisionHandler(.cancel); return }
            if u.scheme == "about" { decisionHandler(.allow); return }
            let id = String(u.absoluteString.dropFirst((u.scheme?.count ?? 0) + 1))
            if !model.store.overviewConflict, id.range(of: "^[0-9]{6,}$", options: .regularExpression) != nil, model.store.item(id) != nil {
                if u.scheme == "thread-note" { model.coordinator.openNote(id) }
                if u.scheme == "thread-detail" { model.coordinator.showDetail(id) }
                if u.scheme == "thread-source", let item = model.store.item(id) { model.focus(item) }
            }
            decisionHandler(.cancel)
        }
    }
}
