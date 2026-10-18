import AppKit
import SwiftUI

final class HubAppDelegate: NSObject, NSApplicationDelegate {
  let store = HubStore()
  var statusItem: NSStatusItem!
  var popover: NSPopover!
  var window: NSWindow?
  var timer: Timer?
  private var overlayRequested = false
  private var pendingSpaceRestore: DispatchWorkItem?
  private var localMouseMonitor: Any?
  private var globalMouseMonitor: Any?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "circle.hexagongrid", accessibilityDescription: "PiHub")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(toggle)
    statusItem.button?.toolTip = "PiHub · Centre de contrôle IA"
    popover = NSPopover()
    popover.behavior = .applicationDefined
    popover.contentSize = NSSize(width: 420, height: 620)
    popover.contentViewController = NSHostingController(rootView: compactContent())
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(activeSpaceDidChange(_:)),
      name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
      [weak self] event in
      guard let self, self.popover.isShown,
        event.window !== self.popover.contentViewController?.view.window,
        event.window !== self.statusItem.button?.window
      else { return event }
      self.closeOverlay()
      return event
    }
    // A local event monitor cannot see clicks delivered to another app. Use a
    // global monitor for that case instead of closing on app deactivation:
    // accessory apps can resign active shortly after presenting a popover,
    // even though the user did not click away.
    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
      [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.overlayRequested else { return }
        self.closeOverlay()
      }
    }
    store.statusChanged = { [weak self] count in
      self?.statusItem.button?.image = NSImage(
        systemSymbolName: count > 0 ? "circle.hexagongrid.fill" : "circle.hexagongrid",
        accessibilityDescription: "PiHub")
      self?.statusItem.button?.toolTip = "PiHub · \(count) moteur(s) prêt(s)"
    }
    store.inspectRequested = { [weak self] in self?.showWindow() }
    timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
      self?.store.refresh()
    }
    store.refresh()
    if let page = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--page=") }) {
      store.page = String(page.dropFirst(7))
    }
    if ProcessInfo.processInfo.arguments.contains("--window") { showWindow() }
    if let capture = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--capture=") })
    {
      showWindow()
      if ProcessInfo.processInfo.arguments.contains("--compact") {
        window?.minSize = NSSize(width: 420, height: 450)
        window?.contentViewController = NSHostingController(rootView: compactContent())
        window?.setContentSize(NSSize(width: 420, height: 620))
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        guard let view = self?.window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        if let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
          view.cacheDisplay(in: view.bounds, to: image)
          if let data = image.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: String(capture.dropFirst(10))))
          }
        }
        NSApp.terminate(nil)
      }
    }
  }
  func content() -> HubRootView {
    HubRootView(
      store: store,
      detach: { [weak self] in
        self?.window?.orderOut(nil)
        self?.toggle()
      }, pinChanged: { [weak self] pinned in self?.window?.level = pinned ? .floating : .normal })
  }
  func compactContent() -> HubCompactView {
    HubCompactView(
      store: store,
      expand: { [weak self] in self?.showWindow() },
      editInstance: { [weak self] item in self?.showInstanceEditor(item) },
      importFolder: { [weak self] kind in self?.showFolderImporter(kind) },
      openInWindow: { [weak self] action in self?.showInWindow(action) })
  }
  @objc func activeSpaceDidChange(_ notification: Notification) {
    pendingSpaceRestore?.cancel()
    let restore = DispatchWorkItem { [weak self] in
      guard let self, self.overlayRequested, !self.popover.isShown else { return }
      // NSPopover needs to finish its dismissal animation before it can be
      // shown again reliably. Reactivate PiHub so the restored overlay still
      // accepts keyboard and pointer input in the destination Space.
      self.presentOverlay(activate: true)
    }
    pendingSpaceRestore = restore
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: restore)
  }
  private func closeOverlay() {
    overlayRequested = false
    if popover.isShown { popover.performClose(nil) }
  }
  private func presentOverlay(activate: Bool = true) {
    guard let button = statusItem.button else { return }
    let available = button.window?.screen?.visibleFrame.size ?? NSSize(width: 1200, height: 850)
    popover.contentSize = NSSize(
      width: min(420, available.width - 30), height: min(620, available.height - 45))
    popover.behavior = .applicationDefined
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary,
    ]
    overlayRequested = true
    if activate { NSApp.activate(ignoringOtherApps: true) }
    store.refresh()
  }
  @objc func toggle() {
    if popover.isShown {
      closeOverlay()
      return
    }
    presentOverlay()
  }
  func showWindow() {
    closeOverlay()
    if window == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1060, height: 790),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = "PiHub · Local AI Workspace"
      window.minSize = NSSize(width: 870, height: 600)
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(rootView: content())
      window.center()
      self.window = window
    }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  private func showInstanceEditor(_ item: HubInstance) {
    showWindow()
    DispatchQueue.main.async { [weak self] in self?.store.inspectID = item.id }
  }
  private func showFolderImporter(_ kind: String) {
    showWindow()
    DispatchQueue.main.async { [weak self] in self?.store.requestedImportKind = kind }
  }
  private func showInWindow(_ action: HubWindowAction) {
    showWindow()
    DispatchQueue.main.async { [weak self] in self?.store.windowAction = action }
  }
}

@main struct PiHubApplication {
  static func main() {
    let app = NSApplication.shared
    let delegate = HubAppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}
