import AppKit
import SwiftUI
import Combine

@main
struct DayproofMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = DayproofModel(config: DesktopConfig())
    var mainWindow: NSWindow!
    var floatWindow: NSPanel!
    var petWindow: NSPanel!
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    private var observer: AnyCancellable?
    private var trayMenu: NSMenu!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !model.backend.config.smoke,
           NSRunningApplication.runningApplications(withBundleIdentifier: "app.dayproof.desktop").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSRunningApplication.runningApplications(withBundleIdentifier: "app.dayproof.desktop").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?.activate(options: [.activateAllWindows])
            NSApp.terminate(nil); return
        }
        makeMenu()
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 730), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        mainWindow.title = "Dayproof · 每一天，都算数"
        mainWindow.isReleasedWhenClosed = false
        mainWindow.delegate = self
        mainWindow.contentView = NSHostingView(rootView: PlannerView(model: model))
        mainWindow.center()
        mainWindow.setFrameAutosaveName("DayproofMain")
        floatWindow = panel(view: FloatingPlan(model: model), size: NSSize(width: 346, height: 420))
        floatWindow.level = model.floatPinned ? .floating : .normal
        petWindow = panel(view: PetWindowView(model: model), size: NSSize(width: 230, height: 218))
        petWindow.level = .floating
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        floatWindow.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 366, y: screen.maxY - 24))
        petWindow.setFrameOrigin(NSPoint(x: screen.maxX - 260, y: screen.minY + 35))
        if !model.backend.config.smoke {
            restorePosition(floatWindow, key: "floatingPosition")
            restorePosition(petWindow, key: "petPosition")
        }
        model.onShowMain = { [weak self] in self?.showMain() }
        model.onShowFloat = { [weak self] in self?.floatWindow.orderFrontRegardless() }
        model.onHideFloat = { [weak self] in self?.floatWindow.orderOut(nil) }
        model.onPinChange = { [weak self] pinned in self?.floatWindow.level = pinned ? .floating : .normal }
        model.onPetVisibility = { [weak self] visible in if visible { self?.petWindow.orderFrontRegardless() } else { self?.petWindow.orderOut(nil) } }
        model.onChange = { [weak self] in self?.updateStatus() }
        observer = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeFloat() }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Dayproof")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: FloatingPlan(model: model).preferredColorScheme(.light))
        trayMenu = NSMenu()
        addItem(trayMenu, "打开完整计划", #selector(showMain))
        addItem(trayMenu, "显示悬浮计划", #selector(showFloat))
        addItem(trayMenu, "显示 / 隐藏小伙伴", #selector(togglePet))
        trayMenu.addItem(.separator())
        addItem(trayMenu, "退出 Dayproof", #selector(quit), key: "q")
        showMain(); floatWindow.orderFrontRegardless()
        if model.petVisible { petWindow.orderFrontRegardless() }
        updateStatus()
        Task {
            await model.launch()
            resizeFloat()
            if model.backend.config.smoke { await runSmoke() }
        }
    }
    private func panel<V: View>(view: V, size: NSSize) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = NSHostingView(rootView: view.preferredColorScheme(.light))
        p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true
        p.isMovableByWindowBackground = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false; p.isFloatingPanel = true
        return p
    }
    func resizeFloat() {
        guard let floatWindow, let view = floatWindow.contentView else { return }
        let top = floatWindow.frame.maxY
        let height: CGFloat = model.collapsed ? 94 : (model.todayTasks.isEmpty ? 360 : min(540, 246 + CGFloat(min(model.todayTasks.count, 6)) * 61))
        view.setFrameSize(NSSize(width: 346, height: height))
        floatWindow.setFrame(NSRect(x: floatWindow.frame.minX, y: top - height, width: 346, height: height), display: true)
    }
    func restorePosition(_ window: NSWindow, key: String) {
        guard let value = UserDefaults.standard.string(forKey: key) else { return }
        let point = NSPointFromString(value)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(point) }) else { return }
        let f = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: min(max(f.minX, point.x), f.maxX - window.frame.width), y: min(max(f.minY, point.y), f.maxY - window.frame.height)))
    }
    func updateStatus() {
        statusItem?.button?.title = " \(model.todayDone)/\(model.todayTasks.count)"
        statusItem?.button?.toolTip = model.nextTask.map { "下一项：\($0.title)" } ?? "Dayproof · 按自己的节奏"
    }
    @objc func statusClick() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = trayMenu; button.performClick(nil); statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    @objc func showMain() { popover.performClose(nil); mainWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showFloat() { floatWindow.orderFrontRegardless() }
    @objc func togglePet() { model.petVisible.toggle() }
    @objc func newTask() { model.newTask() }
    @objc func quit() { NSApp.terminate(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if !model.backend.config.smoke, floatWindow != nil {
            UserDefaults.standard.set(NSStringFromPoint(floatWindow.frame.origin), forKey: "floatingPosition")
            UserDefaults.standard.set(NSStringFromPoint(petWindow.frame.origin), forKey: "petPosition")
        }
        model.stop()
    }
    func makeMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let menu = NSMenu(); appItem.submenu = menu
        addItem(menu, "关于 Dayproof", #selector(about))
        menu.addItem(.separator()); addItem(menu, "打开计划", #selector(showMain), key: "1")
        addItem(menu, "新建任务", #selector(newTask), key: "n")
        addItem(menu, "悬浮计划", #selector(showFloat), key: "2")
        menu.addItem(.separator()); addItem(menu, "关闭窗口", #selector(closeMain), key: "w")
        addItem(menu, "退出 Dayproof", #selector(quit), key: "q")
        let editItem = NSMenuItem(); editItem.title = "编辑"; main.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (name, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
    }
    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    @objc func closeMain() { NSApp.keyWindow?.performClose(nil) }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(nil) }
}
