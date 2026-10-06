import AppKit
import ThreadCore

extension AppCoordinator {
    /// A tag always resumes its exact source; the note remains available if capture is unavailable.
    func activateTag(_ id: String, showNote: Bool = true) {
        guard let item = model.store.item(id), item.status == "active" else { return }
        guard model.perform({ if !item.pinRequested { try model.store.update(id) { $0.pinRequested = true } } }) else { return }
        let token = UUID(); pendingActivations[id] = token
        model.pinStatus[id] = "正在显示来源…"
        model.focus(item) { [weak self] record in
            guard let self, self.pendingActivations[id] == token,
                  let current = self.model.store.item(id), current.status == "active",
                  current.pinRequested, current.source == item.source else { return }
            if showNote { self.openNote(id) }
            guard let record else { self.model.pinStatus[id] = "来源待定位 · 点击标签重试"; return }
            Task { @MainActor in await self.attachMirror(current, record: record, token: token) }
        }
    }

    @MainActor private func controller() -> MirrorController {
        if let mirrorPrototype { return mirrorPrototype }
        let controller = MirrorController()
        controller.onUserUnpin = { [weak self] window in
            guard let self else { return }
            let ids = self.mirrorLinks.owners(window)
            _ = self.model.perform {
                for id in ids { try self.model.store.update(id) { $0.pinRequested = false } }
            }
        }
        controller.onStatus = { [weak self] window, text in
            guard let self else { return }
            for id in self.mirrorLinks.owners(window) { self.model.pinStatus[id] = text }
        }
        mirrorPrototype = controller
        return controller
    }

    @MainActor private func attachMirror(_ item: WorkItem, record: WindowRecord, token: UUID) async {
        let controller = controller()
        do {
            let window = try await controller.present(record)
            guard pendingActivations[item.id] == token, let fresh = model.store.item(item.id),
                  fresh.status == "active", fresh.pinRequested, fresh.source == item.source else {
                if mirrorLinks.owners(window).isEmpty { controller.unpin(window) }
                return
            }
            if let released = mirrorLinks.attach(fresh, to: window) { controller.unpin(released) }
            model.pinStatus[item.id] = "镜像已置顶"
            updateMirrorTasks()
            // Keep the tag and writing surface accessible above captures.
            if let note = notes[item.id]?.0, note.isVisible { note.orderFrontRegardless() }
            controller.log("task-attach id=\(item.id) source=\(window) owners=\(mirrorLinks.owners(window))")
        } catch {
            model.pinStatus[item.id] = "未能置顶 · 点击标签重试"
            showError("任务与笔记已保留。镜像未能开启：\n\(error.localizedDescription)")
        }
    }

    func reconcileMirrors() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let previousIDs = Set(self.mirrorLinks.windows.keys)
            let released = self.mirrorLinks.reconcile(self.model.items)
            for id in previousIDs.subtracting(self.mirrorLinks.windows.keys) {
                if let item = self.model.store.item(id), item.status == "active", item.pinRequested {
                    self.model.pinStatus[id] = "关联已更新 · 点击标签继续"
                } else { self.model.pinStatus.removeValue(forKey: id) }
            }
            for window in released { self.mirrorPrototype?.unpin(window) }
            for id in Array(self.pendingActivations.keys) {
                guard let item = self.model.store.item(id), item.status == "active", item.pinRequested else {
                    self.pendingActivations.removeValue(forKey: id)
                    self.model.pinStatus.removeValue(forKey: id)
                    continue
                }
            }
            self.updateMirrorTasks()
        }
    }

    @MainActor private func updateMirrorTasks() {
        for (window, id) in mirrorLinks.selected {
            guard let item = model.store.item(id), let session = mirrorPrototype?.sessions[window] else { continue }
            session.configureTask(item, count: mirrorLinks.owners(window).count, record: bindings[id],
                                  note: { [weak self] in self?.openNote(id) },
                                  back: { [weak self] in guard let self, let fresh = self.model.store.item(id) else { return }; self.model.focus(fresh) })
        }
    }

    /// Startup preserves tasks and labels without launching apps or stealing focus.
    func restoreAvailableMirrors() {
        guard !restoredMirrors else { return }; restoredMirrors = true
        for item in model.active where item.pinRequested {
            let records = model.windows.filter { $0.bundleID == item.source.appBundleID && $0.rect != nil && !$0.minimized }
            guard records.count == 1, let record = records.first else { model.pinStatus[item.id] = "点击标签继续"; continue }
            bindings[item.id] = record
            // Web pages are located explicitly by a tag click, never guessed from a browser window.
            guard item.source.kind == "app" else { model.pinStatus[item.id] = "点击标签返回页面"; continue }
            let token = UUID(); pendingActivations[item.id] = token
            Task { @MainActor in await attachMirror(item, record: record, token: token) }
        }
    }
}
