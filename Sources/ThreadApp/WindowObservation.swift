import AppKit
import ApplicationServices

/// Event-driven marker updates; the catalog timer remains a fallback for apps with incomplete AX events.
final class WindowObservation {
    private struct Entry { let observer: AXObserver; let windows: [AXUIElement] }
    private var entries: [pid_t: Entry] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    var onChange: (() -> Void)?
    init() {
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.changed() })
        }
    }
    func changed() {
        pending?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.onChange?() }; pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }
    func update(_ records: [WindowRecord]) {
        let groups = Dictionary(grouping: records.filter { $0.ax != nil }, by: \.pid)
        for pid in Array(entries.keys) where groups[pid] == nil { remove(pid) }
        for (pid, group) in groups {
            let windows = group.compactMap(\.ax)
            if let old = entries[pid], old.windows.count == windows.count,
               windows.allSatisfy({ new in old.windows.contains { CFEqual(new, $0) } }) { continue }
            remove(pid)
            var observer: AXObserver?
            guard AXObserverCreate(pid, { _, _, _, context in
                guard let context else { return }
                let owner = Unmanaged<WindowObservation>.fromOpaque(context).takeUnretainedValue()
                owner.changed()
            }, &observer) == .success, let observer else { continue }
            let context = Unmanaged.passUnretained(self).toOpaque()
            let app = AXUIElementCreateApplication(pid)
            for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] { AXObserverAddNotification(observer, app, notification as CFString, context) }
            for window in windows {
                for notification in [kAXMovedNotification, kAXResizedNotification, kAXTitleChangedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification] { AXObserverAddNotification(observer, window, notification as CFString, context) }
            }
            entries[pid] = Entry(observer: observer, windows: windows)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
    private func remove(_ pid: pid_t) {
        if let old = entries.removeValue(forKey: pid) { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old.observer), .commonModes) }
    }
    deinit {
        pending?.cancel()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        for entry in entries.values { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(entry.observer), .commonModes) }
    }
}
