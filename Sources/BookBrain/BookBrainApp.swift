import AppKit
import SwiftUI

@main
struct BookBrainApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    Settings { EmptyView() }
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
    let root = ContentView(model: model) { [weak self] floating in
      self?.window.level = floating ? .floating : .normal
    }
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
    window.contentView = NSHostingView(rootView: root)
    window.setFrameAutosaveName("BookBrainWindow")
    if !window.setFrameUsingName("BookBrainWindow") { window.center() }
    makeMenu()
    shortcut = GlobalHotKey { [weak self] in
      MainActor.assumeIsolated {
        self?.showWindow()
        self?.model.pasteExcerpt()
      }
    }
    if shortcut?.register() != true {
      model.notice =
        "⌘⇧B está em uso por outro app. Use Colar trecho na janela ou na barra de menus."
    }
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
    showWindow()
    model.pasteExcerpt()
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
