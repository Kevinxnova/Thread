import AppKit
import SwiftUI
import ScreenCaptureKit
import CoreMedia
import CoreImage
import ApplicationServices
import ThreadCore
import Darwin

/// Captures are shared by task owners; the coordinator owns task lifecycle and persistence.
@MainActor final class MirrorController: NSObject, ObservableObject {
    @Published var windows: [SCWindow] = []
    @Published var status = "选择一个窗口，创建实时镜像。键盘输入请回到原窗口。"
    @Published var pinned: Set<UInt32> = []
    @Published var loading = false
    var picker: NSWindow?
    var sessions: [UInt32: MirrorSession] = [:]
    var order = MirrorOrder()
    var onUserUnpin: ((UInt32) -> Void)?
    var onStatus: ((UInt32, String) -> Void)?
    func present(_ record: WindowRecord) async throws -> UInt32 {
        guard let number = record.number, number > 0 else { throw ThreadError.message("无法可靠识别这个窗口。请重新选择窗口；任务和笔记已经保留。") }
        let id = UInt32(number)
        if let existing = sessions[id], existing.pid != record.pid || !existing.isAlive { unpin(id) }
        if sessions[id] == nil {
            guard sessions.count < 6 else { throw ThreadError.message("最多同时置顶 6 个窗口。请先取消一个窗口的置顶；任务和笔记仍会保留。") }
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let source = content.windows.first(where: { $0.windowID == id && $0.owningApplication?.processID == record.pid }) else { throw ThreadError.message("这个窗口当前无法捕获，请显示原窗口后重试。") }
            pin(source)
        }
        promote(id)
        return id
    }
    func promote(_ id: UInt32) {
        guard sessions[id] != nil else { return }
        order.promote(id); updateLevels(); sessions[id]?.show()
        log("promote source=\(id) order=\(order.ids)")
    }
    func requestUnpin(_ id: UInt32) {
        if let onUserUnpin { onUserUnpin(id) } else { unpin(id) }
    }
    var logURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["THREAD_MIRROR_LOG"] else { return nil }
        return URL(fileURLWithPath: path)
    }
    func log(_ value: String) {
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(value)\n"
        print(text, terminator: "")
        guard let url = logURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: url) { defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(text.utf8)) }
    }
    @objc func show() {
        if CommandLine.arguments.contains("--mirror-prototype"), NSApp.mainMenu == nil {
            let menu = NSMenu(), appItem = NSMenuItem(), windowItem = NSMenuItem()
            menu.addItem(appItem); menu.addItem(windowItem)
            let appMenu = NSMenu(), windowMenu = NSMenu(title: "窗口")
            appItem.submenu = appMenu; windowItem.submenu = windowMenu
            appMenu.addItem(withTitle: "退出留绪", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            let select = NSMenuItem(title: "选择镜像窗口", action: #selector(show), keyEquivalent: "0"); select.target = self; windowMenu.addItem(select)
            NSApp.mainMenu = menu
        }
        if picker == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 610), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
            w.title = "留绪 · 镜像置顶实验"; w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 480, height: 400)
            w.contentView = NSHostingView(rootView: MirrorPicker(lab: self)); w.center(); picker = w
        }
        picker?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        Task { await refresh() }
    }
    func refresh() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            windows = content.windows.filter { w in
                w.owningApplication?.processID != getpid() && w.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.activationPolicy } == .regular && w.windowLayer == 0 && w.frame.width > 80 && w.frame.height > 60
            }.sorted { ($0.owningApplication?.applicationName ?? "", $0.title ?? "", $0.windowID) < ($1.owningApplication?.applicationName ?? "", $1.title ?? "", $1.windowID) }
            status = "选择窗口创建实时镜像 · 已开启 \(sessions.count)/6 · 点击和滚动为实验功能"
            log("catalog count=\(windows.count) screen=\(CGPreflightScreenCaptureAccess()) accessibility=\(AXIsProcessTrusted())")
        } catch { status = "无法读取画面：请在系统设置中允许 Thread 录制屏幕，然后重新打开应用。\n\(error.localizedDescription)"; log("catalog error=\(error.localizedDescription)") }
    }
    func pin(_ source: SCWindow) {
        guard sessions[source.windowID] == nil else { return }
        guard sessions.count < 6 else { status = "最多同时显示 6 个镜像，请先关闭一个。"; return }
        guard let pid = source.owningApplication?.processID else { return }
        let session = MirrorSession(source: source, pid: pid, lab: self)
        sessions[source.windowID] = session; pinned.insert(source.windowID); order.add(source.windowID)
        updateLevels(); session.show(); status = "已开启 \(sessions.count)/6 · 点击和滚动为实验功能"
        log("pin source=\(source.windowID) pid=\(pid) mirror=\(session.panel.windowNumber)")
        Task { await session.start() }
    }
    func unpin(_ id: UInt32) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        pinned.remove(id); order.remove(id); session.stop(); session.panel.orderOut(nil)
        updateLevels(); status = "已开启 \(sessions.count)/6 · 点击和滚动为实验功能"; log("unpin source=\(id) remaining=\(sessions.count)")
    }
    func updateLevels() {
        for id in order.ids {
            if let rank = order.rank(id), let session = sessions[id] {
                session.panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + rank)
            }
        }
    }
    func stopAll() { for id in Array(sessions.keys) { unpin(id) } }
}

private struct MirrorPicker: View {
    @ObservedObject var lab: MirrorController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "rectangle.on.rectangle").font(.title).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("留住眼前的内容").font(.title2.bold())
                    Text("实时镜像 · 新开启的浮窗优先显示").foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") { Task { await lab.refresh() } }.disabled(lab.loading)
            }
            Text(lab.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(lab.windows, id: \.windowID) { window in
                HStack(spacing: 12) {
                    if let app = window.owningApplication, let icon = NSRunningApplication(processIdentifier: app.processID)?.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(window.title?.isEmpty == false ? window.title! : "未命名窗口").lineLimit(1)
                        Text(window.owningApplication?.applicationName ?? "应用").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if lab.pinned.contains(window.windowID) {
                        Button("取消置顶") { lab.requestUnpin(window.windowID) }
                    } else { Button("镜像置顶") { lab.pin(window) } }
                }.padding(.vertical, 5)
            }.listStyle(.inset)
            HStack {
                Text("录屏权限用于实时画面；辅助功能权限用于实验点击与滚动。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("关闭全部") { lab.stopAll() }.disabled(lab.pinned.isEmpty)
            }
        }.padding(20)
    }
}

private final class MirrorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Bound pending frames to one, so a busy main thread never accumulates video buffers.
private final class MirrorFrameSink: NSObject, SCStreamOutput, SCStreamDelegate {
    let context = CIContext(options: [.cacheIntermediates: false])
    let lock = NSLock()
    var scheduled = false
    var latest: CGImage?
    var frames = 0
    var onFrame: ((CGImage, Int) -> Void)?
    var onError: ((Error) -> Void)?
    func stream(_ stream: SCStream, didStopWithError error: Error) { DispatchQueue.main.async { [weak self] in self?.onError?(error) } }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = context.createCGImage(image, from: image.extent) else { return }
        lock.lock(); frames += 1; latest = cg
        if scheduled { lock.unlock(); return }; scheduled = true; lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let next = self.latest, count = self.frames; self.latest = nil; self.scheduled = false; self.lock.unlock()
            if let next { self.onFrame?(next, count) }
        }
    }
}

@MainActor final class MirrorSession: NSObject, NSWindowDelegate {
    let source: SCWindow
    let pid: pid_t
    weak var lab: MirrorController?
    fileprivate let panel: MirrorPanel
    private let canvas = MirrorCanvas()
    private let caption = NSTextField(labelWithString: "正在连接实时画面…")
    private let pauseButton = NSButton(title: "暂停", target: nil, action: nil)
    private let sink = MirrorFrameSink()
    private var stream: SCStream?
    private var timer: Timer?
    private var closed = false
    private var paused = false
    private var transitioning = false
    private var frameTime: TimeInterval = 0
    private var received = 0
    private var startedAt = Date()
    private var inputFailure = false
    private var lastBounds: CGRect?
    private var sourceBundle: String?
    private var sourceApplication: NSRunningApplication?
    private var failureMessage: String?
    private var expectedImageSize: CGSize?
    private var geometryValid = true
    private var generation = 0
    private var alive = true
    var isAlive: Bool { !closed && alive && failureMessage == nil }
    private var taskID: String?
    private var pageRecord: WindowRecord?
    private var expectedURL: String?
    private var pageAllowed = true
    private var pageChecking = false
    private var pageGeneration = 0
    private var pageMessage: String?
    private var noteAction: (() -> Void)?
    private var returnAction: (() -> Void)?
    private let noteButton = NSButton(title: "笔记", target: nil, action: nil)
    func configureTask(_ item: WorkItem, count: Int, record: WindowRecord?, note: @escaping () -> Void, back: @escaping () -> Void) {
        let url = item.source.kind == "webpage" ? item.source.url : nil
        if taskID != item.id || expectedURL != url {
            pageGeneration += 1; expectedURL = url; pageAllowed = url == nil
            pageMessage = url == nil ? nil : "正在核对关联页面…"
            if url != nil { canvas.image = nil }
        }
        taskID = item.id; pageRecord = record; noteAction = note; returnAction = back
        noteButton.isHidden = false
        panel.title = "\(item.id) · \(item.goal)" + (count > 1 ? " · 共享 \(count) 项" : "")
        Task { _ = await validatePage() }
    }
    private func validatePage() async -> Bool {
        guard let expectedURL else { pageAllowed = true; pageMessage = nil; return true }
        guard var record = pageRecord, !pageChecking else { return false }
        record.rect = currentBounds() ?? record.rect
        pageChecking = true; defer { pageChecking = false }
        let generation = pageGeneration
        let actual: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: (try? BrowserBridge.source(for: record))?.url)
            }
        }
        guard !closed, generation == pageGeneration else { return false }
        let wasAllowed = pageAllowed
        pageAllowed = actual == expectedURL
        if wasAllowed != pageAllowed {
            lab?.log("page-guard source=\(source.windowID) allowed=\(pageAllowed)")
            lab?.onStatus?(source.windowID, pageAllowed ? "镜像已置顶" : "页面已切换 · 点击标签返回关联页面")
        }
        pageMessage = pageAllowed ? nil : "页面已切换或无法核对 · 点击标签返回关联页面"
        if !pageAllowed { canvas.image = nil }
        if !wasAllowed, pageAllowed, !paused, !transitioning, let stream {
            transitioning = true
            do { try await stream.stopCapture(); if !closed { try await stream.startCapture() } }
            catch { fail("页面画面恢复失败，请取消置顶后重试") }
            transitioning = false
        }
        updateCaption()
        return pageAllowed
    }
    @objc private func openTaskNote() { noteAction?() }
    func clampToScreen() {
        panel.setFrame(WindowPlacement.clamp(panel.frame, screens: NSScreen.screens.map(\.visibleFrame), fallback: NSScreen.main?.visibleFrame ?? panel.frame), display: true)
    }
    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void
    private let setWindowLocation: SetWindowLocation? = {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation") else { return nil }
        return unsafeBitCast(pointer, to: SetWindowLocation.self)
    }()

    init(source: SCWindow, pid: pid_t, lab: MirrorController) {
        self.source = source; self.pid = pid; self.lab = lab
        sourceApplication = NSRunningApplication(processIdentifier: pid)
        sourceBundle = sourceApplication?.bundleIdentifier
        let width = min(600, max(440, source.frame.width * 0.55))
        let height = min(540, max(240, width * source.frame.height / source.frame.width))
        panel = MirrorPanel(contentRect: NSRect(x: 160, y: 160, width: width, height: height + 66), styleMask: [.titled,.closable,.resizable,.nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "镜像 · \(source.owningApplication?.applicationName ?? "应用") — \(source.title ?? "窗口")"
        panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.minSize = NSSize(width: 440, height: 260); panel.delegate = self
        panel.setFrameOrigin(NSPoint(x: 140 + CGFloat(lab.sessions.count)*44, y: 170 + CGFloat(lab.sessions.count)*36))
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let controls = NSStackView(); controls.orientation = .horizontal; controls.spacing = 10
        let back = NSButton(title: "回到原窗口", target: self, action: #selector(backToSource))
        back.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil); back.imagePosition = .imageLeading
        pauseButton.target = self; pauseButton.action = #selector(togglePause)
        let close = NSButton(title: "取消置顶", target: self, action: #selector(closeMirror))
        noteButton.target = self; noteButton.action = #selector(openTaskNote); noteButton.isHidden = true
        [back,noteButton,pauseButton,close].forEach { controls.addArrangedSubview($0) }
        caption.font = .systemFont(ofSize: 11); caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        [controls,caption,canvas].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 8), controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            caption.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 6), caption.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), caption.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            canvas.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 8), canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor), canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        panel.contentView = root
        canvas.setAccessibilityLabel("实时镜像画面，支持实验点击和滚动，输入文字请回到原窗口")
        canvas.onClick = { [weak self] p in Task { @MainActor in guard let self, await self.validatePage() else { return }; self.click(p) } }
        canvas.onScroll = { [weak self] p, dx, dy in Task { @MainActor in guard let self, await self.validatePage() else { return }; self.scroll(p, dx: dx, dy: dy) } }
        sink.onFrame = { [weak self] image, count in
            guard let self, !self.closed, !self.paused, self.pageAllowed else { return }
            if let expected = self.expectedImageSize,
               image.width == Int(expected.width), image.height == Int(expected.height) { self.geometryValid = true }
            self.canvas.image = image; self.received = count; self.frameTime = Date.timeIntervalSinceReferenceDate
            if count == 1 { self.lab?.log("first-frame source=\(source.windowID) pixels=\(image.width)x\(image.height)") }
            self.updateCaption()
        }
        sink.onError = { [weak self] error in self?.fail("画面已停止：\(error.localizedDescription)") }
    }
    func show() { clampToScreen(); panel.orderFrontRegardless() }
    func start() async {
        guard !closed else { return }
        transitioning = true; defer { transitioning = false }
        let config = SCStreamConfiguration()
        configure(config, bounds: source.frame)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: source), configuration: config, delegate: sink)
        self.stream = stream; lastBounds = source.frame
        do {
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.kevin.thread.mirror.\(source.windowID)", qos: .userInitiated))
            try await stream.startCapture()
            if closed { try? await stream.stopCapture(); return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in Task { @MainActor in await self?.checkSource() } }
            lab?.log("capture-start source=\(source.windowID)")
        } catch { fail("无法开始镜像：\(error.localizedDescription)") }
    }
    private func configure(_ config: SCStreamConfiguration, bounds: CGRect) {
        let scale = min(2, 1600 / max(bounds.width, bounds.height))
        config.width = max(2, Int(bounds.width * scale)); config.height = max(2, Int(bounds.height * scale))
        expectedImageSize = CGSize(width: config.width, height: config.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30); config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA; config.showsCursor = false; config.capturesAudio = false
        if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = true }
    }
    private func currentBounds() -> CGRect? {
        guard let running = sourceApplication, !running.isTerminated, running.bundleIdentifier == sourceBundle,
              let rows = CGWindowListCopyWindowInfo([.optionIncludingWindow], source.windowID) as? [[String:Any]],
              let row = rows.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == source.windowID && ($0[kCGWindowOwnerPID as String] as? Int32) == pid }),
              let dictionary = row[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary)
    }
    private func checkSource() async {
        guard !closed, alive else { return }
        guard let bounds = currentBounds() else { alive = false; fail("来源暂不可用 · 点击标签重新显示"); return }
        if let old = lastBounds, old.size != bounds.size, !transitioning, !paused {
            geometryValid = false; generation += 1; let token = generation
            let config = SCStreamConfiguration(); configure(config, bounds: bounds)
            lastBounds = bounds
            do { try await stream?.updateConfiguration(config); if token != generation { return } }
            catch { fail("窗口尺寸更新失败，请重新开启镜像") }
        }
        _ = await validatePage()
        updateCaption()
    }
    private func updateCaption() {
        defer { canvas.placeholder = caption.stringValue }
        guard alive, !closed else { return }
        if let failureMessage { caption.stringValue = failureMessage; return }
        if let pageMessage { caption.stringValue = pageMessage }
        else if paused { caption.stringValue = "已暂停 · 点击与滚动已关闭" }
        else if inputFailure { caption.stringValue = "交互可能改变焦点 · 请使用“回到原窗口”" }
        else if frameTime == 0 { caption.stringValue = "等待首帧 · 未收到画面时不会转发操作" }
        else { caption.stringValue = "实时镜像 · 点击/滚动为实验功能 · 输入请回到原窗口" }
    }
    private func fail(_ message: String) {
        failureMessage = message; caption.stringValue = message; geometryValid = false; inputFailure = true; canvas.image = nil; canvas.placeholder = message
        lab?.onStatus?(source.windowID, message)
        lab?.log("capture-error source=\(source.windowID) message=\(message)")
    }
    func stop() {
        closed = true; generation += 1; timer?.invalidate(); timer = nil
        canvas.onClick = nil; canvas.onScroll = nil; sink.onFrame = nil; sink.onError = nil
        let elapsed = Date().timeIntervalSince(startedAt)
        lab?.log("capture-stop source=\(source.windowID) frames=\(received) duration=\(String(format: "%.2f", elapsed))")
        if let stream { Task { try? await stream.stopCapture() } }; self.stream = nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { lab?.requestUnpin(source.windowID); return false }
    @objc private func closeMirror() { lab?.requestUnpin(source.windowID) }
    @objc private func togglePause() {
        guard !transitioning, !closed, alive, let stream else { return }
        transitioning = true; pauseButton.isEnabled = false
        Task {
            defer { transitioning = false; pauseButton.isEnabled = true }
            do {
                if paused { try await stream.startCapture(); paused = false; pauseButton.title = "暂停" }
                else { paused = true; try await stream.stopCapture(); pauseButton.title = "继续" }
                if closed { try? await stream.stopCapture(); return }
                updateCaption(); lab?.log("pause source=\(source.windowID) value=\(paused)")
            } catch { fail("暂停/继续失败，请重新开启镜像") }
        }
    }
    @objc private func backToSource() {
        if let returnAction { returnAction(); return }
        guard currentBounds() != nil else { fail("原窗口已关闭"); return }
        let record = WindowCatalog.scan().0.first { $0.pid == pid && $0.number == Int(source.windowID) }
        if let record { WindowCatalog.raise(record) }
        else { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
        lab?.log("return-to-source source=\(source.windowID)")
    }
    private func inputPoint(_ local: CGPoint) -> CGPoint? {
        guard !closed, !paused, !transitioning, !inputFailure, geometryValid, pageAllowed, frameTime > 0,
              failureMessage == nil, AXIsProcessTrusted(), let bounds = currentBounds(), bounds.size == lastBounds?.size,
              let image = canvas.image else { return nil }
        return MirrorGeometry.sourcePoint(local, image: CGSize(width: image.width, height: image.height), in: canvas.bounds, source: bounds)
    }
    private func checkFocus(_ before: pid_t?, kind: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.closed else { return }
            let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let preserved = before == after
            self.lab?.log("input source=\(self.source.windowID) kind=\(kind) focusBefore=\(before ?? -1) focusAfter=\(after ?? -1) preserved=\(preserved)")
            if !preserved { self.inputFailure = true; self.updateCaption() }
        }
    }
    private func target(_ event: CGEvent, at point: CGPoint) {
        event.location = point
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        // CGEvent scroll construction has no window parameter; 51 is the WindowServer window identity field.
        if let windowField = CGEventField(rawValue: 51) { event.setIntegerValueField(windowField, value: Int64(source.windowID)) }
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(source.windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(source.windowID))
        guard let bounds = currentBounds(), let setWindowLocation else {
            caption.stringValue = "系统不支持实验坐标转发，请回到原窗口"; return
        }
        setWindowLocation(event, CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
        event.postToPid(pid)
    }
    private func click(_ local: CGPoint) {
        guard let point = inputPoint(local) else { if !AXIsProcessTrusted() { caption.stringValue = "需要辅助功能权限才能操作 · 可先回到原窗口" }; return }
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Prefer the target's semantic button/link action; it avoids pixel-event focus side effects.
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &hit) == .success, let hit {
            let role = WindowCatalog.value(hit, kAXRoleAttribute) as? String
            let hitWindow = WindowCatalog.value(hit, kAXWindowAttribute)
            let hitBounds: CGRect? = hitWindow.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? WindowCatalog.frame($0 as! AXUIElement) : nil }
            if let bounds = currentBounds(), let hitBounds,
               abs(hitBounds.minX - bounds.minX) < 1, abs(hitBounds.minY - bounds.minY) < 1,
               abs(hitBounds.width - bounds.width) < 1, abs(hitBounds.height - bounds.height) < 1,
               [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, "AXLink"].contains(role ?? ""),
               AXUIElementPerformAction(hit, kAXPressAction as CFString) == .success {
                checkFocus(before, kind: "AXPress"); return
            }
        }
        guard let bounds = currentBounds() else { return }
        let local = NSPoint(x: point.x - bounds.minX, y: bounds.height - (point.y - bounds.minY))
        func mouse(_ type: NSEvent.EventType) -> CGEvent? {
            NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: Int(source.windowID), context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)?.cgEvent
        }
        guard let down = mouse(.leftMouseDown), let up = mouse(.leftMouseUp) else { return }
        target(down, at: point); target(up, at: point); checkFocus(before, kind: "click")
    }
    private func scroll(_ local: CGPoint, dx: CGFloat, dy: CGFloat) {
        guard let point = inputPoint(local) else { return }
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let x = Int32(max(-1000, min(1000, dx.rounded()))), y = Int32(max(-1000, min(1000, dy.rounded())))
        guard x != 0 || y != 0, let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .privateState), units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0) else { return }
        target(event, at: point); checkFocus(before, kind: "scroll")
    }
}

private final class MirrorCanvas: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var image: CGImage? { didSet { needsDisplay = true } }
    var placeholder = "正在连接实时画面…" { didSet { needsDisplay = true } }
    var onClick: ((CGPoint)->Void)?
    var onScroll: ((CGPoint,CGFloat,CGFloat)->Void)?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        guard image != nil else {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let text = placeholder as NSString
            text.draw(in: NSRect(x: 24, y: max(24, bounds.midY-30), width: max(0, bounds.width-48), height: 70),
                      withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
            return
        }
        guard let image, let rect = MirrorGeometry.fittedRect(image: CGSize(width:image.width,height:image.height), in: bounds) else { return }
        NSImage(cgImage: image, size: NSSize(width: image.width,height: image.height)).draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func mouseDown(with event: NSEvent) { onClick?(convert(event.locationInWindow, from: nil)) }
    override func scrollWheel(with event: NSEvent) { onScroll?(convert(event.locationInWindow, from: nil), event.scrollingDeltaX, event.scrollingDeltaY) }
}
