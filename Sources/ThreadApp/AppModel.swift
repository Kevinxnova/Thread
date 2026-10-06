import AppKit
import SwiftUI
import ThreadCore

final class AppModel: ObservableObject {
    let store: WorkStore
    @Published var items: [WorkItem] = []
    @Published var windows: [WindowRecord] = []
    @Published var issues: [String] = []
    @Published var catalogWarnings: [String] = []
    @Published var scanning = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var overviewRevision = 0
    @Published var pinStatus: [String: String] = [:]
    var coordinator: AppCoordinator!
    private let observation = WindowObservation()
    private var timer: Timer?
    private var timerTicks = 0
    private var scanCompletions: [() -> Void] = []
    private let systemQueue = DispatchQueue(label: "Thread.system-access", qos: .userInitiated)
    var active: [WorkItem] { store.active }
    var recent: [WorkItem] { store.recentCompleted }
    init(root: URL) throws { store = try WorkStore(root: root); sync() }
    func start() {
        observation.onChange = { [weak self] in self?.scan() }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let changed = self.store.reload()
            if changed { try? self.store.refreshOverview(); self.sync() }
            else { self.issues = self.store.issues }
            self.overviewRevision += 1
            self.trusted = AXIsProcessTrusted()
            self.timerTicks += 1
            if self.timerTicks % 3 == 0 && (!self.active.isEmpty || self.coordinator.listVisible) { self.scan() }
            self.coordinator.refreshMarkers()
        }
    }
    func sync() { items = store.items; issues = store.issues; overviewRevision += 1; coordinator?.refreshMarkers(); coordinator?.reconcileNotes(); coordinator?.reconcileMirrors() }
    @discardableResult func perform(_ work: () throws -> Void) -> Bool {
        do { try work(); sync(); return true } catch { sync(); coordinator.showError(error.localizedDescription); return false }
    }
    func toggleStar(_ id: String) { perform { try store.update(id) { $0.starred.toggle() } } }
    func complete(_ id: String) { guard coordinator.flushNote(id) else { return }; perform { try store.complete(id) } }
    func restore(_ id: String) {
        if perform({ try store.restore(id) }), store.item(id)?.pinRequested == true { coordinator.activateTag(id, showNote: false) }
    }
    func togglePin(_ id: String) {
        guard let item = store.item(id), item.status == "active" else { return }
        if item.pinRequested { perform { try store.update(id) { $0.pinRequested = false } } }
        else { coordinator.activateTag(id, showNote: false) }
    }
    func delete(_ id: String) {
        guard let item = store.item(id), coordinator.flushNote(id) else { return }
        let alert = NSAlert(); alert.messageText = "删除 \(id)？"; alert.informativeText = "\(item.goal)\n对应笔记将移到废纸篓，源应用和网页不会关闭。"; alert.alertStyle = .warning
        alert.addButton(withTitle: "取消"); let b = alert.addButton(withTitle: "删除"); b.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { perform { try store.delete(id) } }
    }
    func scan(completion: (() -> Void)? = nil) {
        if let completion { scanCompletions.append(completion) }; guard !scanning else { return }; scanning = true
        systemQueue.async { [weak self] in
            let result = WindowCatalog.scan()
            DispatchQueue.main.async {
                guard let self else { return }; self.windows = result.0; self.catalogWarnings = result.1; self.scanning = false
                self.observation.update(result.0)
                let status = Dictionary(uniqueKeysWithValues: self.items.map { item in
                    (item.id, item.source.kind == "webpage" ? "页面状态待定位" : (self.windows.contains { $0.bundleID == item.source.appBundleID } ? "应用已打开" : "未打开"))
                })
                try? self.store.refreshOverview(online: status); self.issues = self.store.issues; self.overviewRevision += 1
                self.coordinator?.refreshMarkers(); let pending = self.scanCompletions; self.scanCompletions.removeAll(); pending.forEach { $0() }
            }
        }
    }
    func select(_ record: WindowRecord) {
        if BrowserBridge.supported.contains(record.bundleID) {
            systemQueue.async { [weak self] in
                let source = Result { try BrowserBridge.source(for: record) }
                DispatchQueue.main.async { switch source {
                case .success(let s): self?.coordinator.showCreate(source: s, record: record)
                case .failure(let e): self?.coordinator.showCreate(source: record.source, record: record, warning: e.localizedDescription)
                } }
            }
        } else { coordinator.showCreate(source: record.source, record: record) }
    }
    func relink(_ id: String, to record: WindowRecord) {
        systemQueue.async { [weak self] in
            let result = Result { try BrowserBridge.source(for: record) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error): self.coordinator.showError(error.localizedDescription)
                case .success(let source):
                    if self.perform({ try self.store.update(id) { $0.source = source } }) {
                        self.coordinator.bindings[id] = record; self.coordinator.refreshMarkers(); if self.store.item(id)?.pinRequested == true { self.coordinator.activateTag(id, showNote: false) }
                    }
                }
            }
        }
    }
    func create(goal: String, source: Source, record: WindowRecord?, completion: @escaping (Bool) -> Void) {
        func finish() {
            var createdID: String?
            let success = perform {
                let item = try store.create(goal: goal, source: source); createdID = item.id
                if let record { coordinator.bindings[item.id] = record }
            }
            completion(success)
            if success, let id = createdID { DispatchQueue.main.async { self.coordinator.activateTag(id) } }
        }
        // Recheck automatically captured pages so navigation during target entry cannot silently change association.
        if source.kind == "webpage", let record, BrowserBridge.supported.contains(source.appBundleID) {
            systemQueue.async { [weak self] in
                let latest = try? BrowserBridge.source(for: record)
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let latest, latest.url != source.url {
                        let a = NSAlert(); a.messageText = "页面已变化"; a.informativeText = "仍将目标关联到刚才选择的页面：\n\(source.url ?? "")"; a.addButton(withTitle: "返回检查"); a.addButton(withTitle: "保留原页面创建")
                        if a.runModal() != .alertSecondButtonReturn { completion(false); return }
                    }
                    _ = self; finish()
                }
            }
        } else { finish() }
    }
    /// Resolve an exact source before opening a capture. Missing/ambiguous sources never pick an arbitrary window.
    func focus(_ item: WorkItem, attempt: Int = 0, completion: ((WindowRecord?) -> Void)? = nil) {
        if item.source.kind == "webpage", let raw = item.source.url, let url = URL(string: raw) {
            systemQueue.async { [weak self] in
                let result = Result { try BrowserBridge.tabs(for: item.source) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .failure(let error): self.coordinator.showError(error.localizedDescription); completion?(nil)
                    case .success(let tabs):
                        if tabs.isEmpty {
                            if attempt > 0 {
                                if attempt < 5 { DispatchQueue.main.asyncAfter(deadline: .now()+0.7) { self.focus(item, attempt: attempt+1, completion: completion) } }
                                else { self.coordinator.showError("页面已打开，但暂时无法可靠定位。请重新点击标签，或在详情中重新关联窗口。"); completion?(nil) }
                                return
                            }
                            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.source.appBundleID) else { self.coordinator.showError("找不到关联的浏览器。请重新关联，笔记仍然保留。"); completion?(nil); return }
                            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                                DispatchQueue.main.async {
                                    if let error { self.coordinator.showError(error.localizedDescription); completion?(nil) }
                                    else { self.focus(item, attempt: 1, completion: completion) }
                                }
                            }
                        } else if tabs.count == 1 { self.focusTab(tabs[0], item: item, completion: completion) }
                        else if let bound = self.coordinator.bindings[item.id],
                                let rect = bound.ax.flatMap({ WindowCatalog.frame($0) }) ?? bound.rect,
                                tabs.filter({ Self.near($0.rect, rect) }).count == 1,
                                let tab = tabs.first(where: { Self.near($0.rect, rect) }) {
                            self.focusTab(tab, item: item, completion: completion)
                        } else { self.coordinator.chooseTab(tabs, cancelled: { completion?(nil) }) { self.focusTab($0, item: item, completion: completion) } }
                    }
                }
            }
            return
        }
        scan { [weak self] in
            guard let self else { return }
            let candidates = self.windows.filter { $0.bundleID == item.source.appBundleID && $0.rect != nil }
            var identityRetries = 0
            func selected(_ record: WindowRecord) {
                // WindowServer can be sampled before AX exposes a newly launched window.
                // Rescan the same AX identity; never guess by title or bind another window.
                if record.number == nil && identityRetries < 5 {
                    identityRetries += 1
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
                        self.scan {
                            guard let fresh = self.windows.first(where: { $0.matches(record) }) else { completion?(nil); return }
                            selected(fresh)
                        }
                    }
                    return
                }
                self.coordinator.bindings[item.id] = record; WindowCatalog.raise(record)
                self.coordinator.refreshMarkers(); completion?(record)
            }
            if let binding = self.coordinator.bindings[item.id], let fresh = candidates.first(where: { $0.matches(binding) }) { selected(fresh) }
            else if candidates.count == 1 { selected(candidates[0]) }
            else if candidates.count > 1 { self.coordinator.chooseWindow(candidates, cancelled: { completion?(nil) }, selected: selected) }
            else if attempt == 0, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.source.appBundleID) {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    DispatchQueue.main.async {
                        if let error { self.coordinator.showError(error.localizedDescription); completion?(nil) }
                        else { self.focus(item, attempt: 1, completion: completion) }
                    }
                }
            } else if attempt > 0 && attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.7) { self.focus(item, attempt: attempt+1, completion: completion) }
            } else { self.coordinator.showError("没有可显示的关联窗口。请在应用中打开窗口后再次点击标签；任务和笔记仍然保留。"); completion?(nil) }
        }
    }
    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) < 3 && abs(a.minY-b.minY) < 3 && abs(a.width-b.width) < 3 && abs(a.height-b.height) < 3
    }
    private func focusTab(_ tab: BrowserBridge.Tab, item: WorkItem, completion: ((WindowRecord?) -> Void)?) {
        systemQueue.async { [weak self] in
            let result = Result { try BrowserBridge.focus(item.source, tab: tab) }
            DispatchQueue.main.async {
                guard let self else { return }
                if case .failure(let error) = result { self.coordinator.showError(error.localizedDescription); completion?(nil); return }
                self.scan {
                    let matches = self.windows.filter { $0.bundleID == item.source.appBundleID && $0.rect.map { Self.near($0, tab.rect) } == true }
                    guard matches.count == 1 else { self.coordinator.showError("页面已显示，但无法唯一识别其窗口。请重新关联后置顶。"); completion?(nil); return }
                    let record = matches[0]; self.coordinator.bindings[item.id] = record
                    WindowCatalog.raise(record); self.coordinator.refreshMarkers(); completion?(record)
                }
            }
        }
    }
    func requestAccessibility() { let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary; _ = AXIsProcessTrustedWithOptions(options) }
}

final class NoteSession: ObservableObject {
    let id: String
    let model: AppModel
    @Published var text: String
    @Published var status = "已保存"
    private var base: String
    private var pending: DispatchWorkItem?
    private var pendingFrame: String?
    init(item: WorkItem, model: AppModel) { id = item.id; self.model = model; text = item.note; base = item.note }
    func changed(_ value: String) {
        text = value; status = "未保存"; pending?.cancel()
        let task = DispatchWorkItem { [weak self] in _ = self?.flush() }; pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }
    func frameChanged(_ frame: NSRect) {
        pendingFrame = NSStringFromRect(frame); pending?.cancel()
        let task = DispatchWorkItem { [weak self] in _ = self?.flush() }; pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }
    @discardableResult func flush() -> Bool {
        pending?.cancel()
        do {
            if text != base { try model.store.saveNote(id, text: text, base: base); base = text }
            if let frame = pendingFrame {
                _ = model.store.reload()
                if model.store.item(id)?.noteFrame != frame { try model.store.update(id) { $0.noteFrame = frame } }
                pendingFrame = nil
            }
            status = "已保存"; model.sync(); return true
        }
        catch { status = "未保存：\(error.localizedDescription)"; return false }
    }
    func receiveExternal() { if let item = model.store.item(id), text == base, item.note != base { text = item.note; base = item.note; status = "已同步外部修改" } }
}
