import AppKit
import SwiftUI
import ThreadCore
import CryptoKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class NoteDelegate: NSObject, NSWindowDelegate {
    let session: NoteSession
    init(_ session: NoteSession) { self.session = session }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if session.flush() { return true }
        let alert = NSAlert(); alert.messageText = "笔记尚未保存"; alert.informativeText = session.status; alert.runModal(); return false
    }
    func windowDidMove(_ notification: Notification) { saveFrame(notification) }
    func windowDidResize(_ notification: Notification) { saveFrame(notification) }
    private func saveFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        session.frameChanged(window.frame)
    }
}
final class AppCoordinator: NSObject {
    let model: AppModel
    let preferences: UserDefaults
    let overviewFrameName: String
    var mirrorPrototype: MirrorController?
    var mirrorLinks = MirrorLinks()
    var pendingActivations: [String: UUID] = [:]
    var restoredMirrors = false
    var markersHidden = false
    var toolbar: NSPanel!
    var list: NSWindow?
    var overview: NSWindow?
    var createWindow: NSWindow?
    var details: [String: NSWindow] = [:]
    var notes: [String: (NSWindow, NoteSession, NoteDelegate)] = [:]
    var markers: [String: NSPanel] = [:]
    var bindings: [String: WindowRecord] = [:]
    var selectionPanels: [NSPanel] = []
    var statusItem: NSStatusItem?
    var outsideMonitor: Any?
    var localMonitor: Any?
    var listVisible: Bool { list?.isVisible == true }
    private var markedURL: [String: String] = [:]
    private var verifyingPages = false
    private var lastPageCheck = Date.distantPast
    private var updatingMarkers = false
    private var markerAnchors: [String: NSPoint] = [:]
    private var markerOffsets: [String: NSPoint] = [:]
    private var pendingMarkerFrames: [String: String] = [:]
    private var pendingMarkerOffsets: [String: String] = [:]
    private var markerSave: DispatchWorkItem?
    private var markerObservers: [String: NSObjectProtocol] = [:]
    init(model: AppModel) {
        self.model = model
        let hash = SHA256.hash(data: Data(model.store.root.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        overviewFrameName = "ThreadOverview04." + hash
        let normal = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Thread_kevin").standardizedFileURL
        if model.store.root.standardizedFileURL == normal { preferences = .standard }
        else {
            preferences = UserDefaults(suiteName: "com.kevin.thread.layout." + hash) ?? .standard
        }
        super.init()
    }
    func start() {
        buildMenu()
        let p = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 186, height: 58), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.hidesOnDeactivate = false; p.level = NSWindow.Level(rawValue: 20); p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true; p.isMovableByWindowBackground = true; p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: ToolbarView(model: model)); toolbar = p
        if let saved = preferences.string(forKey: "toolbar.frame") { p.setFrame(clamp(NSRectFromString(saved)), display: false) }
        else if let screen = NSScreen.main { p.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 230, y: screen.visibleFrame.maxY - 100)) }
        p.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(toolbarMoved), name: NSWindow.didMoveNotification, object: p)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.list?.orderOut(nil) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 { if !self.selectionPanels.isEmpty { self.endSelection(); return nil }; self.list?.orderOut(nil) }
            if event.type == .leftMouseDown, event.window !== self.list, event.window !== self.toolbar { self.list?.orderOut(nil) }
            return event
        }
        model.start()
        model.scan { [weak self] in self?.restoreAvailableMirrors() }
    }
    @objc private func toolbarMoved() { preferences.set(NSStringFromRect(toolbar.frame), forKey: "toolbar.frame") }
    @objc private func screensChanged() {
        let windows = [toolbar, list, overview, createWindow].compactMap { $0 } + Array(details.values) + notes.values.map { $0.0 }
        for window in windows { window.setFrame(clamp(window.frame), display: true) }
        endSelection(); refreshMarkers()
        Task { @MainActor in mirrorPrototype?.sessions.values.forEach { $0.clampToScreen() } }
    }
    func clamp(_ frame: NSRect) -> NSRect {
        WindowPlacement.clamp(frame, screens: NSScreen.screens.map(\.visibleFrame), fallback: NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
    }
    private func window<V: View>(title: String, size: NSSize, floating: Bool = false, view: V) -> NSWindow {
        let w: NSWindow = floating ? FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false) : NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title; w.contentMinSize = size; w.isMovable = true; w.isMovableByWindowBackground = true; w.isReleasedWhenClosed = false; w.contentView = NSHostingView(rootView: view)
        if floating { w.level = NSWindow.Level(rawValue: 21); w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; (w as? NSPanel)?.hidesOnDeactivate = false }
        w.center(); return w
    }
    func showError(_ text: String) { let a = NSAlert(); a.messageText = "操作未完成"; a.informativeText = text; a.alertStyle = .warning; NSApp.activate(ignoringOtherApps: true); a.runModal() }
    @objc func showMirrorPrototype() { showList() }
    @objc func hideToolbar() { toolbar.orderOut(nil) }
    @objc func toggleMarkers() { markersHidden.toggle(); refreshMarkers() }
    @objc func showToolbar() { toolbar.setFrame(clamp(toolbar.frame), display: true); toolbar.orderFrontRegardless() }
    @objc func showList() { if !listVisible { toggleList() } }
    func toggleList() {
        if listVisible { list?.orderOut(nil); return }
        let w = window(title: "留绪 · 工作条项", size: NSSize(width: 392, height: 660), floating: true, view: WorkListView(model: model))
        list = w; w.contentMinSize = NSSize(width: 360, height: 460); w.setFrameOrigin(NSPoint(x: toolbar.frame.maxX - w.frame.width, y: toolbar.frame.minY - w.frame.height - 12)); w.setFrame(clamp(w.frame), display: false); w.makeKeyAndOrderFront(nil)
    }
    @objc func showOverview() {
        if overview == nil { overview = window(title: "留绪 · 完整总览", size: NSSize(width: 1120, height: 720), view: OverviewView(model: model)); overview?.contentMinSize = NSSize(width: 760, height: 480); overview?.setFrameAutosaveName(overviewFrameName); if let w = overview { w.setFrame(clamp(w.frame), display: false) } }
        overview?.level = NSWindow.Level(rawValue: 21); overview?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showCreate(source: Source, record: WindowRecord?, warning: String? = nil) {
        let w = window(title: "添加标记", size: NSSize(width: 488, height: 330), floating: true, view: CreateView(model: model, record: record, original: source, warning: warning) { [weak self] in self?.createWindow?.close(); self?.createWindow = nil })
        createWindow = w; w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func openNote(_ id: String) {
        guard let item = model.store.item(id) else { return }
        if let (w, session, _) = notes[id] { session.receiveExternal(); w.makeKeyAndOrderFront(nil); return }
        let session = NoteSession(item: item, model: model)
        let w = window(title: "\(id) · 留绪", size: NSSize(width: 390, height: 340), floating: true, view: NoteView(model: model, session: session))
        w.contentMinSize = NSSize(width: 320, height: 240)
        let delegate = NoteDelegate(session)
        if let saved = item.noteFrame ?? legacyFrame("note." + id) { w.setFrame(clamp(NSRectFromString(saved)), display: false) }
        w.delegate = delegate
        notes[id] = (w, session, delegate); w.makeKeyAndOrderFront(nil)
    }
    func flushNote(_ id: String) -> Bool {
        if let (_, session, _) = notes[id], !session.flush() { showError(session.status); return false }; return true
    }
    func flushAll() -> Bool {
        for id in notes.keys { if !flushNote(id) { return false } }
        return flushMarkerFrames()
    }
    func reconcileNotes() {
        for (id, (w, session, _)) in notes {
            if model.store.item(id) == nil { w.orderOut(nil); notes.removeValue(forKey: id) }
            else { session.receiveExternal(); if model.store.item(id)?.status == "completed" { w.orderOut(nil) } }
        }
    }
    func showDetail(_ id: String) {
        let w = window(title: "条项详情", size: NSSize(width: 528, height: 340), view: DetailView(model: model, id: id)); details[id] = w; w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func chooseTab(_ tabs: [BrowserBridge.Tab], cancelled: @escaping () -> Void = {}, selected: @escaping (BrowserBridge.Tab) -> Void) {
        let alert = NSAlert(); alert.messageText = "这个页面已在多个标签中打开"; alert.informativeText = "选择要继续的标签，不会新增页面。"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 390, height: 28)); popup.addItems(withTitles: tabs.map(\.label)); alert.accessoryView = popup
        alert.addButton(withTitle: "前往"); alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { selected(tabs[popup.indexOfSelectedItem]) } else { cancelled() }
    }
    func chooseWindow(_ records: [WindowRecord], cancelled: @escaping () -> Void = {}, selected: @escaping (WindowRecord) -> Void) {
        let a = NSAlert(); a.messageText = "选择要继续的窗口"; let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28)); popup.addItems(withTitles: records.map { $0.title }); a.accessoryView = popup; a.addButton(withTitle: "前往"); a.addButton(withTitle: "取消")
        if a.runModal() == .alertFirstButtonReturn { selected(records[popup.indexOfSelectedItem]) } else { cancelled() }
    }
    private func legacyFrame(_ key: String) -> String? {
        guard model.store.root.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Thread_kevin").standardizedFileURL else { return nil }
        return UserDefaults.standard.string(forKey: key)
    }
    private func flushMarkerFrames() -> Bool {
        markerSave?.cancel()
        do {
            _ = model.store.reload()
            for (id, frame) in pendingMarkerFrames {
                if model.store.item(id) != nil { try model.store.update(id) { $0.markerFrame = frame; if let offset = pendingMarkerOffsets[id] { $0.markerOffset = offset } } }
                pendingMarkerOffsets.removeValue(forKey: id)
                pendingMarkerFrames.removeValue(forKey: id)
            }
            return true
        } catch { showError(error.localizedDescription); return false }
    }
    func refreshMarkers() {
        updatingMarkers = true; defer { updatingMarkers = false }
        let ids = Set(model.active.map(\.id))
        for (id, p) in markers where !ids.contains(id) { p.orderOut(nil); markers.removeValue(forKey: id); bindings.removeValue(forKey: id); if let observer = markerObservers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) } }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var slots: [String: Int] = [:]
        for (index, item) in model.active.enumerated() {
            let panel: NSPanel
            if let old = markers[item.id] { panel = old }
            else {
                panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 98, height: 32), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = NSWindow.Level(rawValue: 20); panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isMovableByWindowBackground = true; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.isReleasedWhenClosed = false
                panel.contentView = NSHostingView(rootView: MarkerView(model: model, id: item.id)); markers[item.id] = panel
                if let saved = item.markerOffset { markerOffsets[item.id] = NSPointFromString(saved) }
                markerObservers[item.id] = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self, weak panel] _ in
                    guard let self, let panel, !self.updatingMarkers else { return }
                    if let anchor = self.markerAnchors[item.id] { self.markerOffsets[item.id] = NSPoint(x: panel.frame.minX-anchor.x, y: panel.frame.minY-anchor.y) }
                    if let offset = self.markerOffsets[item.id] { self.pendingMarkerOffsets[item.id] = NSStringFromPoint(offset) }
                    self.pendingMarkerFrames[item.id] = NSStringFromRect(panel.frame)
                    self.markerSave?.cancel()
                    let task = DispatchWorkItem { [weak self] in _ = self?.flushMarkerFrames() }; self.markerSave = task
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.5, execute: task)
                }
                if let screen = NSScreen.main { let row = index % max(1, Int((screen.visibleFrame.height - 150) / 40)); let col = index / max(1, Int((screen.visibleFrame.height - 150) / 40)); panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 112 - CGFloat(col)*106, y: screen.visibleFrame.maxY - 170 - CGFloat(row)*40)) }
            }
            let sameApp = model.windows.filter { $0.bundleID == item.source.appBundleID && $0.rect != nil }
            if let old = bindings[item.id] { bindings[item.id] = sameApp.first { $0.matches(old) } }
            if bindings[item.id] == nil && sameApp.count == 1 { bindings[item.id] = sameApp.first }
            if let bound = bindings[item.id], bound.pid == frontPID, !bound.minimized, let rect = bound.rect,
               item.source.kind == "app" || markedURL[bound.id] == item.source.url {
                let slot = slots[bound.id, default: 0]; slots[bound.id] = slot + 1
                let r = WindowCatalog.cocoaRect(rect); let f = NSRect(x: r.maxX - 108, y: r.maxY - 72 - CGFloat(slot)*36, width: 98, height: 32)
                markerAnchors[item.id] = f.origin
                let offset = markerOffsets[item.id] ?? .zero
                panel.setFrame(clamp(f.offsetBy(dx: offset.x, dy: offset.y)), display: true)
            } else {
                markerAnchors.removeValue(forKey: item.id)
                if let saved = pendingMarkerFrames[item.id] ?? item.markerFrame ?? legacyFrame("marker." + item.id) { panel.setFrame(clamp(NSRectFromString(saved)), display: true) }
                else if let screen = NSScreen.main {
                    let capacity = max(1, Int((screen.visibleFrame.height - 150) / 40)); let row = index % capacity; let col = index / capacity
                    panel.setFrame(clamp(NSRect(x: screen.visibleFrame.maxX - 112 - CGFloat(col)*106, y: screen.visibleFrame.maxY - 170 - CGFloat(row)*40, width: 98, height: 32)), display: true)
                }
            }
            if markersHidden { panel.orderOut(nil) } else if !panel.isVisible { panel.orderFrontRegardless() }
        }
        verifyPagesIfNeeded()
    }
    private func verifyPagesIfNeeded() {
        guard !verifyingPages, Date().timeIntervalSince(lastPageCheck) > 5 else { return }
        let pageBindings = model.active.filter { $0.source.kind == "webpage" }.compactMap { bindings[$0.id] }
        guard !pageBindings.isEmpty else { return }; verifyingPages = true; lastPageCheck = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var values: [String: String] = [:]
            for window in pageBindings { if let source = try? BrowserBridge.source(for: window), let url = source.url { values[window.id] = url } }
            DispatchQueue.main.async { self?.markedURL = values; self?.verifyingPages = false }
        }
    }
    func beginSelection(relinkID: String? = nil) {
        list?.orderOut(nil)
        model.scan { [weak self] in
            guard let self else { return }; self.endSelection()
            let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? Int }
            let records = self.model.windows.filter { !$0.minimized && $0.rect != nil && $0.number.map { order.contains($0) } == true }.sorted { (order.firstIndex(of: $0.number ?? -1) ?? Int.max) < (order.firstIndex(of: $1.number ?? -1) ?? Int.max) }
            for screen in NSScreen.screens {
                let panel = FloatingPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.level = .popUpMenu; panel.isOpaque = false; panel.backgroundColor = .clear; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
                let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size)); view.screenFrame = screen.frame; view.records = records
                view.selected = { [weak self] record in self?.endSelection(); if let record { if let relinkID { self?.model.relink(relinkID, to: record) } else { self?.model.select(record) } } }
                panel.contentView = view; self.selectionPanels.append(panel); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    func endSelection() { selectionPanels.forEach { $0.orderOut(nil) }; selectionPanels.removeAll() }
    @objc private func dataFolder() { NSWorkspace.shared.open(model.store.root) }
    @objc private func permissions() { model.requestAccessibility() }
    @objc private func quit() { NSApp.terminate(nil) }
    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); statusItem?.button?.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "留绪")
        let menu = NSMenu()
        for (title, action) in [("留绪 · Thread 0.8", #selector(showToolbar)), ("显示悬浮条", #selector(showToolbar)), ("隐藏悬浮条", #selector(hideToolbar)), ("显示/隐藏标签", #selector(toggleMarkers)), ("工作条项", #selector(showList)), ("完整总览", #selector(showOverview)), ("置顶与工作条项", #selector(showMirrorPrototype)), ("打开数据文件夹", #selector(dataFolder)), ("辅助功能权限", #selector(permissions)), ("退出留绪", #selector(quit))] { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        statusItem?.menu = menu
        let main = NSMenu(); let appItem = NSMenuItem(); main.addItem(appItem); let appMenu = NSMenu(); appItem.submenu = appMenu; let quitItem = NSMenuItem(title: "退出留绪", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self; appMenu.addItem(quitItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); main.addItem(editItem); let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (title, action, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key)) }
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: ""); main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口"); windowItem.submenu = windowMenu
        for (title, action, key) in [("显示悬浮条", #selector(showToolbar), "0"), ("隐藏悬浮条", #selector(hideToolbar), ""), ("显示/隐藏标签", #selector(toggleMarkers), ""), ("工作条项", #selector(showList), "1"), ("完整总览", #selector(showOverview), "2"), ("置顶与工作条项", #selector(showMirrorPrototype), "3")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; windowMenu.addItem(item)
        }
        windowMenu.addItem(.separator()); windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        NSApp.mainMenu = main
    }
}
struct MarkerView: View {
    @ObservedObject var model: AppModel; let id: String
    var body: some View { Button { model.coordinator.activateTag(id) } label: { HStack(spacing: 5) { Image(systemName: model.store.item(id)?.pinRequested == true ? "pin.fill" : "tag"); Text(id).font(.system(size: 11, weight: .medium, design: .monospaced)) }.frame(width: 94, height: 30).background(.regularMaterial, in: Capsule()) }.buttonStyle(.plain).help((model.store.item(id)?.goal ?? "笔记") + " · 点击显示来源、置顶并打开笔记").accessibilityLabel("继续条项 \(id)").overlay(alignment: .trailing) { WindowDragHandle().frame(width: 12, height: 30).help("拖动标记") } }
}
final class SelectionTarget: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}
final class SelectionView: NSView {
    var screenFrame = NSRect.zero
    private var targets: [SelectionTarget] = []
    var records: [WindowRecord] = [] {
        didSet {
            targets = records.filter { $0.rect.map { WindowCatalog.cocoaRect($0).intersects(screenFrame) } == true }.map { record in
                let target = SelectionTarget(); target.setAccessibilityRole(.button); target.setAccessibilityEnabled(true)
                target.setAccessibilityLabel("选择窗口 " + record.appName + " " + record.title)
                target.setAccessibilityFrame(WindowCatalog.cocoaRect(record.rect!)); target.setAccessibilityParent(self)
                target.press = { [weak self] in self?.selected?(record) }; return target
            }
        }
    }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { targets }
    var selected: ((WindowRecord?) -> Void)?
    var current: WindowRecord?
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() { super.updateTrackingAreas(); for area in trackingAreas { removeTrackingArea(area) }; addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)) }
    override func mouseMoved(with event: NSEvent) { let point = NSEvent.mouseLocation; current = records.first { if let r = $0.rect { return WindowCatalog.cocoaRect(r).contains(point) }; return false }; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { mouseMoved(with: event); selected?(current) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { selected?(nil); return }
        if event.keyCode == 36, let current { selected?(current); return }
        if [48, 123, 124, 125, 126].contains(event.keyCode), !records.isEmpty {
            let backwards = [123, 126].contains(event.keyCode) || event.modifierFlags.contains(.shift)
            let index = current.flatMap { value in records.firstIndex { $0.id == value.id } }
            let next = index.map { ($0 + (backwards ? -1 : 1) + records.count) % records.count } ?? 0
            current = records[next]; needsDisplay = true
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill(); bounds.fill()
        if let r = current?.rect { var rect = WindowCatalog.cocoaRect(r); rect.origin.x -= screenFrame.minX; rect.origin.y -= screenFrame.minY; NSColor.controlAccentColor.setStroke(); let path = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10); path.lineWidth = 4; path.stroke() }
        let text = (current.map { "\($0.appName) · \(String($0.title.prefix(36))) · 回车确认 / Esc 取消" } ?? "点击窗口 · Tab 切换 · 回车确认 · Esc 取消") as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs); let rect = NSRect(x: (bounds.width-size.width)/2-20, y: bounds.height-120, width: size.width+40, height: 52)
        NSColor.black.withAlphaComponent(0.75).setFill(); NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill(); text.draw(at: NSPoint(x: rect.minX+20, y: rect.minY+15), withAttributes: attrs)
    }
}
