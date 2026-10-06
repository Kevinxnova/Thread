import Foundation

/// Several tasks can share a capture. Only the last owner releases its window.
public struct MirrorLinks {
    public private(set) var windows: [String: UInt32] = [:]
    public private(set) var sources: [String: Source] = [:]
    public private(set) var selected: [UInt32: String] = [:]
    public init() {}
    public func owners(_ window: UInt32) -> [String] { windows.keys.filter { windows[$0] == window }.sorted() }
    @discardableResult public mutating func attach(_ item: WorkItem, to window: UInt32) -> UInt32? {
        let released = detach(item.id)
        windows[item.id] = window; sources[item.id] = item.source; selected[window] = item.id
        return released == window ? nil : released
    }
    @discardableResult public mutating func detach(_ id: String) -> UInt32? {
        guard let window = windows.removeValue(forKey: id) else { return nil }
        sources.removeValue(forKey: id)
        let remaining = owners(window)
        if remaining.isEmpty { selected.removeValue(forKey: window); return window }
        if selected[window] == id { selected[window] = remaining.first }
        return nil
    }
    public mutating func reconcile(_ items: [WorkItem]) -> Set<UInt32> {
        let valid = Dictionary(uniqueKeysWithValues: items.filter { $0.status == "active" && $0.pinRequested }.map { ($0.id, $0.source) })
        var released = Set<UInt32>()
        for id in Array(windows.keys) where valid[id] != sources[id] {
            if let window = detach(id) { released.insert(window) }
        }
        return released
    }
}
