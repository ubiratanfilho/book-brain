import AppKit
import SwiftUI

@main
enum BookBrainApp {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let model = AppModel()
  private var window: NSWindow!
  private var statusItem: NSStatusItem!
  private var shortcut: GlobalHotKey?
  private var expandedSize = NSSize(width: 600, height: 830)

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 830),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    window.title = "Book Brain"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = NSColor(Palette.paper)
    window.minSize = NSSize(width: 300, height: 280)
    window.level = .floating
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.delegate = self
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(applicationActivated(_:)),
      name: NSWorkspace.didActivateApplicationNotification, object: nil)
    shortcut = GlobalHotKey { [weak self] in
      MainActor.assumeIsolated {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let kindle = frontmost?.bundleIdentifier == KindleSelection.bundleID ? frontmost : nil
        self?.captureAndShow(.shortcut(kindle: kindle))
      }
    }
    let root = ContentView(
      model: model, shortcutAvailable: shortcut?.register() == true,
      setFloating: { [weak self] floating in self?.window.level = floating ? .floating : .normal },
      setCompact: { [weak self] compact in self?.resizeWindow(compact: compact) })
    let content = NSHostingView(rootView: root)
    content.sizingOptions = []
    window.contentView = content
    window.setFrameAutosaveName("BookBrainWindow")
    if !window.setFrameUsingName("BookBrainWindow") { window.center() }
    if let screen = window.screen, window.frame.height > screen.visibleFrame.height {
      var frame = window.frame
      frame.size.height = min(830, screen.visibleFrame.height)
      window.setFrame(window.constrainFrameRect(frame, to: screen), display: false)
    }
    makeMenu()
    showWindow()
    Task { await model.connect() }
  }

  private func makeMenu() {
    let mainMenu = NSMenu()
    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu()
    applicationMenu.addItem(
      withTitle: "About Book Brain",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    applicationMenu.addItem(.separator())
    applicationMenu.addItem(
      withTitle: "Quit Book Brain", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)
    let editItem = NSMenuItem()
    editItem.title = "Edit"
    let editMenu = NSMenu(title: "Edit")
    for (title, action, key) in [
      ("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
      ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
      ("Select All", "selectAll:", "a"),
    ] {
      editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
    }
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)
    NSApp.mainMenu = mainMenu

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "book.closed", accessibilityDescription: "Book Brain")
    let menu = NSMenu()
    let open = menu.addItem(
      withTitle: "Open Book Brain", action: #selector(showWindow), keyEquivalent: "")
    open.target = self
    let paste = menu.addItem(
      withTitle: "Paste copied passage", action: #selector(pasteFromMenu), keyEquivalent: "")
    paste.target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem.menu = menu
  }

  @objc private func showWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    if let screen = readingScreen, !screen.visibleFrame.contains(window.frame) {
      fitWindow(size: window.frame.size, in: screen.visibleFrame)
    }
  }

  private func resizeWindow(compact: Bool) {
    guard let visible = (readingScreen ?? window.screen)?.visibleFrame else { return }
    if compact { expandedSize = window.frame.size }
    let requested = compact ? NSSize(width: 350, height: 390) : expandedSize
    fitWindow(size: requested, in: visible)
  }

  private func fitWindow(size requested: NSSize, in visible: NSRect) {
    let previous = window.frame
    let width = min(requested.width, visible.width)
    let height = min(requested.height, visible.height)
    let x = min(max(previous.maxX - width, visible.minX), visible.maxX - width)
    let y = min(max(previous.maxY - height, visible.minY), visible.maxY - height)
    window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
  }

  private func identifier(of screen: NSScreen) -> String? {
    guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber,
      let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
  }

  private var readingScreen: NSScreen? {
    guard let id = UserDefaults.standard.string(forKey: "ReadingDisplayUUID") else { return nil }
    return NSScreen.screens.first { identifier(of: $0) == id }
  }

  func windowDidMove(_ notification: Notification) {
    // AppKit can move a restored window during activation. Only a user's drag
    // changes the selected display; programmatic resizes preserve that choice.
    guard NSApp.currentEvent?.type == .leftMouseDragged, let screen = window.screen,
      let id = identifier(of: screen)
    else { return }
    UserDefaults.standard.set(id, forKey: "ReadingDisplayUUID")
  }

  @objc private func pasteFromMenu() {
    captureAndShow(.paste)
  }

  private func captureAndShow(_ source: PassageSource) {
    Task {
      guard !model.isImporting else { return }
      await model.pasteExcerpt(source)
      showWindow()
    }
  }

  @objc private func applicationActivated(_ notification: Notification) {
    let application =
      notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    if application?.bundleIdentifier == KindleSelection.bundleID { model.clipboard.beginReading() }
  }

  func applicationDidBecomeActive(_ notification: Notification) { model.refreshCopyAccess() }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showWindow()
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
  func windowWillClose(_ notification: Notification) { model.saveNow() }
}
