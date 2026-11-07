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
    window.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.94, alpha: 1)
    window.minSize = NSSize(width: 480, height: 650)
    window.level = .floating
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.delegate = self
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(applicationActivated(_:)),
      name: NSWorkspace.didActivateApplicationNotification, object: nil)
    shortcut = GlobalHotKey { [weak self] in
      MainActor.assumeIsolated { self?.pasteFromMenu() }
    }
    let root = ContentView(model: model, shortcutAvailable: shortcut?.register() == true) {
      [weak self] floating in
      self?.window.level = floating ? .floating : .normal
    }
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
      withTitle: "Sobre o Book Brain",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    applicationMenu.addItem(.separator())
    applicationMenu.addItem(
      withTitle: "Sair do Book Brain", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)
    let editItem = NSMenuItem()
    editItem.title = "Editar"
    let editMenu = NSMenu(title: "Editar")
    for (title, action, key) in [
      ("Desfazer", "undo:", "z"), ("Recortar", "cut:", "x"),
      ("Copiar", "copy:", "c"), ("Colar", "paste:", "v"),
      ("Selecionar tudo", "selectAll:", "a"),
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
      withTitle: "Abrir Book Brain", action: #selector(showWindow), keyEquivalent: "")
    open.target = self
    let paste = menu.addItem(
      withTitle: "Colar trecho copiado  ⌘⇧B", action: #selector(pasteFromMenu), keyEquivalent: "")
    paste.target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem.menu = menu
  }

  @objc private func showWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  @objc private func pasteFromMenu() {
    Task {
      guard !model.isImporting else { return }
      await model.pasteExcerpt()
      showWindow()
    }
  }

  @objc private func applicationActivated(_ notification: Notification) {
    let application =
      notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    if application?.bundleIdentifier == "com.amazon.Lassen" { model.clipboard.beginReading() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showWindow()
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
  func windowWillClose(_ notification: Notification) { model.saveNow() }
}
