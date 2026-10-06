import AppKit
import ThreadCore
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    var mirrorPrototype: MirrorController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--mirror-prototype") {
            let prototype = MirrorController(); mirrorPrototype = prototype; prototype.show(); return
        }
        if CommandLine.arguments.contains("--test-dark-appearance") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--test-high-contrast") { NSApp.appearance = NSAppearance(named: .accessibilityHighContrastDarkAqua) }
        let rootPath = ProcessInfo.processInfo.environment["THREAD_DATA_DIR"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Thread_kevin").path
        do {
            let model = try AppModel(root: URL(fileURLWithPath: rootPath, isDirectory: true)); self.model = model; model.coordinator = AppCoordinator(model: model); model.coordinator.start()
            if CommandLine.arguments.contains("--overview") { model.coordinator.showOverview() }
            if CommandLine.arguments.contains("--list") { model.coordinator.showList() }
        } catch { let alert = NSAlert(); alert.messageText = "留绪无法打开数据目录"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.coordinator.flushAll() == false { return .terminateCancel }
        mirrorPrototype?.stopAll(); model?.coordinator.mirrorPrototype?.stopAll()
        return .terminateNow
    }
}
if CommandLine.arguments.contains("--diagnostics") {
    let result = WindowCatalog.scan()
    print("Thread 0.8 diagnostics")
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Screen capture granted: \(CGPreflightScreenCaptureAccess())")
    print("Accessibility trusted: \(AXIsProcessTrusted())")
    print("Enumerated entries: \(result.0.count)")
    print("AX-backed windows: \(result.0.filter { $0.ax != nil }.count)")
    print("Partial enumeration warnings: \(result.1.count)")
    if CommandLine.arguments.contains("--browser-diagnostics") {
        for window in result.0 where BrowserBridge.supported.contains(window.bundleID) {
            let started = Date()
            do { let source = try BrowserBridge.source(for: window); print("Browser \(window.bundleID): URL recognized=\(source.url != nil), elapsed=\(Date().timeIntervalSince(started))") }
            catch { print("Browser \(window.bundleID): failed: \(error.localizedDescription)") }
        }
    }
    print("Third-party persistent pin: unavailable (not substituted with AXRaise)")
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
